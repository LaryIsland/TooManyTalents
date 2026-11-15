local _, ns = ...
local L = ns.L

-- Sharing templates as text (design document 5.13): Actions > Export gives a line to copy, Actions > Import takes one.
-- The line is a version prefix, then base64 of the raw-deflated payload, one field per line:
--   class, name, ranks ("nodeID:rank,..."), choices ("nodeID:entryID,...")
-- Plain text rather than the client's CBOR serialiser, which isn't confirmed in game; deflate and base64 are.

local Share = {}
ns.Share = Share

local PREFIX = "!TMT1!"
local DEFLATE = Enum.CompressionMethod.Deflate

local function Pairs(map)
	local ids = {}
	for id in pairs(map) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local parts = {}
	for i, id in ipairs(ids) do
		parts[i] = id .. ":" .. map[id]
	end
	return table.concat(parts, ",")
end

-- nil if any entry isn't two whole numbers.
local function ReadPairs(text)
	local map = {}
	if text == "" then return map end
	for entry in (text .. ","):gmatch("([^,]*),") do
		local id, value = entry:match("^(%d+):(%d+)$")
		if not id then return nil end
		map[tonumber(id)] = tonumber(value)
	end
	return map
end

function Share.Export(template)
	local payload = table.concat({
		template.class,
		(template.name:gsub("[\r\n]", " ")),
		Pairs(template.ranks),
		Pairs(template.choices),
	}, "\n")
	return PREFIX .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(payload, DEFLATE))
end

-- Reads a pasted line. Returns class, name, ranks, choices, or nil and why not.
function Share.Decode(text)
	text = (text or ""):gsub("%s", "")
	if text:sub(1, #PREFIX) ~= PREFIX then return nil, L.IMPORT_INVALID end
	local ok, compressed = pcall(C_EncodingUtil.DecodeBase64, text:sub(#PREFIX + 1))
	if not ok or not compressed then return nil, L.IMPORT_INVALID end
	local payload
	ok, payload = pcall(C_EncodingUtil.DecompressString, compressed, DEFLATE)
	if not ok or type(payload) ~= "string" then return nil, L.IMPORT_INVALID end

	local class, name, rankText, choiceText = payload:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
	name = name and ns.Templates.CleanName(name)
	if not class or not ns.SPEC_BY_CLASS[class] or name == "" then return nil, L.IMPORT_INVALID end
	local ranks, choices = ReadPairs(rankText), ReadPairs(choiceText)
	if not ranks or not choices then return nil, L.IMPORT_INVALID end
	return class, name, ranks, choices
end

-- Whether the ranks fit the class's tree as it is now: every rank within its talent's maximum, choices among the
-- talent's options, no more points than the level cap gives, tiers and prerequisites met. Talents no longer in the
-- game are let through: opening the template drops them and says so (design document 4).
local function Fits(model, ranks, choices)
	for nodeID, rank in pairs(ranks) do
		local node = model.nodes[nodeID]
		if node and (rank < 1 or rank > node.maxRanks) then return false end
	end
	for nodeID, entryID in pairs(choices) do
		local node = model.nodes[nodeID]
		if node then
			local known = false
			for _, id in ipairs(node.entryIDs) do
				if id == entryID then known = true end
			end
			if not known then return false end
		end
	end
	return ns.Templates.Points(model, ranks) <= model.cap and ns.Templates.IsValid(model, ranks)
end

-- Makes a new template from a pasted line, under its own name (numbered if taken). Returns it, or nil and why not.
function Share.Import(text)
	local class, name, ranks, choices = Share.Decode(text)
	if not class then return nil, name end
	local model = ns.Tree.Get(class)
	if not model then return nil, L.NO_TREE_DATA:format(ns.ClassName(class)) end
	if not Fits(model, ranks, choices) then return nil, L.IMPORT_DOESNT_FIT:format(name, ns.ClassName(class)) end
	-- A choice talent with ranks but no option given gets its first, as the window shows it and Apply would learn it.
	for nodeID in pairs(ranks) do
		local node = model.nodes[nodeID]
		if node and node.type == Enum.TraitNodeType.Selection and not choices[nodeID] then
			choices[nodeID] = node.entryIDs[1]
		end
	end
	return ns.Templates.Create(class, name, ranks, choices)
end
