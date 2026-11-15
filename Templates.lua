local _, ns = ...
local L = ns.L

-- Templates: named builds for one class, stored as { [nodeID] = rank } (design document 4). Ranks for talents no
-- longer in the game are dropped when the template is opened, giving those points back.

local Templates = {}
ns.Templates = Templates

local function ClassTable(class)
	local templates = ns.saved.templates
	templates[class] = templates[class] or {}
	return templates[class]
end

-- Names, sorted.
function Templates.List(class)
	local names = {}
	for name in pairs(ClassTable(class)) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b) return strcmputf8i(a, b) < 0 end)
	return names
end

function Templates.Get(class, name)
	return ClassTable(class)[name]
end

-- base, or base followed by the first free number.
-- The name box takes 30 letters (UI/Frame.xml), so names are kept to that wherever they're made: a longer one would be
-- cut by the box and renamed to the cut version on leaving it.
local NAME_LETTERS = 30

-- text cut to at most `letters` characters (UTF-8: a character is one lead byte and its continuation bytes).
local function CutLetters(text, letters)
	local count = 0
	for start in text:gmatch("()[%z\1-\127\192-\255][\128-\191]*") do
		count = count + 1
		if count > letters then return text:sub(1, start - 1) end
	end
	return text
end

-- A template name as it's stored: colour, link and texture codes taken out (a link keeps its text, any other "|" goes),
-- trimmed, and cut to the name box's length. Imported names come from anyone.
function Templates.CleanName(name)
	name = (name or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
		:gsub("|[TA].-|[ta]", ""):gsub("|", "")
	return strtrim(CutLetters(strtrim(name), NAME_LETTERS))
end

-- base, cleaned, or with the first free number (" 2", " 3"...), cut so the number still fits.
function Templates.UniqueName(class, base)
	local templates = ClassTable(class)
	base = Templates.CleanName(base)
	if not templates[base] then return base end
	local n = 2
	local function Numbered()
		local suffix = " " .. n
		return strtrim(CutLetters(base, NAME_LETTERS - #suffix)) .. suffix
	end
	while templates[Numbered()] do
		n = n + 1
	end
	return Numbered()
end

function Templates.Create(class, name, ranks, choices)
	name = Templates.UniqueName(class, name)
	local template = { class = class, name = name, ranks = ranks or {}, choices = choices or {} }
	ClassTable(class)[name] = template
	return template
end

function Templates.Duplicate(template, name)
	return Templates.Create(template.class, name, CopyTable(template.ranks), CopyTable(template.choices))
end

-- Returns false (and says why) if the name is taken. An empty name leaves it unchanged.
function Templates.Rename(template, name)
	name = Templates.CleanName(name)
	if name == "" or name == template.name then return true end
	local templates = ClassTable(template.class)
	if templates[name] then
		UIErrorsFrame:AddExternalErrorMessage(L.NAME_TAKEN:format(name))
		return false
	end
	templates[template.name] = nil
	template.name = name
	templates[name] = template
	return true
end

function Templates.Delete(template)
	ClassTable(template.class)[template.name] = nil
end

-- The player's own ranks on a config, as a new template's tables.
function Templates.ReadConfig(model, configID)
	local ranks, choices = {}, {}
	for nodeID, node in pairs(model.nodes) do
		local info = C_Traits.GetNodeInfo(configID, nodeID)
		local rank = info and info.ranksPurchased or 0
		if rank > 0 then
			ranks[nodeID] = math.min(rank, node.maxRanks)
			if node.type == Enum.TraitNodeType.Selection and info.activeEntry then
				choices[nodeID] = info.activeEntry.entryID
			end
		end
	end
	return ranks, choices
end

-- Points --------------------------------------------------------------------------------------------------------------

-- Whether you have something on a node the template doesn't: more ranks than it, or another option of a choice
-- talent. Applying can't take it away (5.8), and the target marks it red (5.12).
function Templates.HasMoreThan(template, nodeID, info)
	local have = info and info.ranksPurchased or 0
	local choice = template.choices[nodeID]
	return have > (template.ranks[nodeID] or 0)
		or (choice ~= nil and have > 0 and info.activeEntry ~= nil and info.activeEntry.entryID ~= choice)
end

-- Total points, and points per tree. Talents no longer in the game aren't counted: they're in no tree.
function Templates.Points(model, ranks)
	local total, perTree = 0, {}
	for index in ipairs(model.trees) do
		perTree[index] = 0
	end
	for nodeID, rank in pairs(ranks) do
		local node = model.nodes[nodeID]
		if node then
			total = total + rank
			perTree[node.tree] = perTree[node.tree] + rank
		end
	end
	return total, perTree
end

-- Ranks for talents no longer in the game's tree are dropped (design document 4). Talents still in the game that the
-- window leaves out (the misplaced-node rule, or filtered when the model was read) keep theirs: they're not counted
-- or applied, but they're not lost either. Returns how many talents with points were dropped.
local function Gone(model, nodeID)
	return not model.nodes[nodeID] and not model.inGame[nodeID]
end

function Templates.RemoveOrphans(model, template)
	local count = 0
	for nodeID, rank in pairs(template.ranks) do
		if Gone(model, nodeID) then
			if rank > 0 then count = count + 1 end
			template.ranks[nodeID] = nil
		end
	end
	for nodeID in pairs(template.choices) do
		if Gone(model, nodeID) and not template.ranks[nodeID] then template.choices[nodeID] = nil end
	end
	return count
end

-- The rules ---------------------------------------------------------------------------------------------------------

-- Points in the node's tree spent in lower tiers. A talent needs its tier's worth there: counting only lower tiers
-- (not the whole tree) is what guarantees a template can be learned in tier order (Talented/editmode.lua:72-100).
local function PointsBelowTier(model, ranks, node)
	local total = 0
	for _, nodeID in ipairs(model.trees[node.tree].nodes) do
		local other = model.nodes[nodeID]
		if other.tier < node.tier then
			total = total + (ranks[nodeID] or 0)
		end
	end
	return total
end

local function IsFull(model, ranks, nodeID)
	local node = model.nodes[nodeID]
	return node and (ranks[nodeID] or 0) >= node.maxRanks
end

-- Every required prerequisite fully ranked, and at least one of the sufficient ones if there are any.
local function MeetsPrerequisites(model, ranks, node)
	for _, sourceID in ipairs(node.required) do
		if not IsFull(model, ranks, sourceID) then return false end
	end
	if #node.sufficient > 0 then
		for _, sourceID in ipairs(node.sufficient) do
			if IsFull(model, ranks, sourceID) then return true end
		end
		return false
	end
	return true
end

local function MeetsTier(model, ranks, node)
	return node.tier <= 0 or PointsBelowTier(model, ranks, node) >= node.tier
end

-- Whether every ranked talent in the template still has its tier and prerequisites.
function Templates.IsValid(model, ranks)
	for nodeID, rank in pairs(ranks) do
		local node = model.nodes[nodeID]
		if node and rank > 0 and not (MeetsTier(model, ranks, node) and MeetsPrerequisites(model, ranks, node)) then
			return false
		end
	end
	return true
end

function Templates.CanAddRank(model, template, nodeID)
	local node = model.nodes[nodeID]
	local ranks = template.ranks
	if not node or (ranks[nodeID] or 0) >= node.maxRanks then return false end
	if Templates.Points(model, ranks) >= model.cap then return false end
	return MeetsTier(model, ranks, node) and MeetsPrerequisites(model, ranks, node)
end

-- A rank can come off if every talent still ranked afterwards keeps its tier and prerequisites.
function Templates.CanRemoveRank(model, template, nodeID)
	local rank = template.ranks[nodeID] or 0
	if rank <= 0 or not model.nodes[nodeID] then return false end
	local ranks = template.ranks
	ranks[nodeID] = rank - 1
	local valid = Templates.IsValid(model, ranks)
	ranks[nodeID] = rank
	return valid
end

function Templates.AddRank(model, template, nodeID)
	if not Templates.CanAddRank(model, template, nodeID) then return false end
	local node = model.nodes[nodeID]
	template.ranks[nodeID] = (template.ranks[nodeID] or 0) + 1
	if node.type == Enum.TraitNodeType.Selection and not template.choices[nodeID] then
		template.choices[nodeID] = node.entryIDs[1]
	end
	return true
end

function Templates.RemoveRank(model, template, nodeID)
	if not Templates.CanRemoveRank(model, template, nodeID) then return false end
	local rank = template.ranks[nodeID] - 1
	template.ranks[nodeID] = rank > 0 and rank or nil
	if rank <= 0 then
		template.choices[nodeID] = nil
	end
	return true
end

-- A choice node: picking an option takes the node's ranks with it, nil clears it.
function Templates.SetChoice(model, template, nodeID, entryID)
	local node = model.nodes[nodeID]
	if not node then return false end
	if not entryID then
		if not template.ranks[nodeID] then return true end
		local saved = template.ranks[nodeID]
		template.ranks[nodeID] = nil
		if not Templates.IsValid(model, template.ranks) then
			template.ranks[nodeID] = saved
			return false
		end
		template.choices[nodeID] = nil
		return true
	end
	if not template.ranks[nodeID] then
		if not Templates.CanAddRank(model, template, nodeID) then return false end
		template.ranks[nodeID] = node.maxRanks
		if Templates.Points(model, template.ranks) > model.cap then
			template.ranks[nodeID] = nil
			return false
		end
	end
	template.choices[nodeID] = entryID
	return true
end

-- Clears every rank in one of the three trees (the per-tree reset button, design document 5.7). Nothing outside the
-- tree depends on it.
function Templates.ResetTree(model, template, treeIndex)
	for _, nodeID in ipairs(model.trees[treeIndex].nodes) do
		template.ranks[nodeID] = nil
		template.choices[nodeID] = nil
	end
end

-- Showing a template ----------------------------------------------------------------------------------------------

-- The template as the view config's entries.
local function Entries(model, template)
	local entries = {}
	for _, nodeID in ipairs(model.order) do
		local rank = template.ranks[nodeID]
		if rank and rank > 0 then
			local node = model.nodes[nodeID]
			entries[#entries + 1] = {
				nodeID = nodeID,
				ranksPurchased = rank,
				ranksGranted = 0,
				selectionEntryID = template.choices[nodeID] or node.entryIDs[1],
			}
		end
	end
	return entries
end

-- Loads the template into the view config. The window patches each node's state from the template too
-- (Templates.PatchNodeInfo), so what's drawn follows these rules even if the game's view config doesn't.
function Templates.LoadIntoView(model, template)
	if not ns.Tree.InitializeView(model.class) then return false end
	return pcall(C_ClassTalents.ViewLoadout, Entries(model, template))
end

-- Rewrites a node's info from the view config to match the template: ranks, what can be bought or refunded,
-- whether its tier and prerequisites are met, and which arrows out of it are lit.
function Templates.PatchNodeInfo(model, template, info)
	local node = model.nodes[info.ID]
	if not node then return end
	local ranks = template.ranks
	local rank = ranks[info.ID] or 0
	info.ranksPurchased = rank
	info.currentRank = rank
	info.activeRank = rank
	info.ranksIncreased = 0
	info.isDisplayError = false
	info.isCascadeRepurchasable = false
	-- The game suggests putting newly learned spells on the action bars; a template's aren't learned.
	info.entryIDsWithCommittedRanks = {}
	local entryID = template.choices[info.ID] or (info.activeEntry and info.activeEntry.entryID) or node.entryIDs[1]
	if node.type == Enum.TraitNodeType.Selection and rank <= 0 then
		info.activeEntry = nil
	else
		info.activeEntry = { entryID = entryID, rank = rank }
	end
	info.isAvailable = MeetsTier(model, ranks, node)
	info.meetsEdgeRequirements = MeetsPrerequisites(model, ranks, node)
	info.canPurchaseRank = Templates.CanAddRank(model, template, info.ID)
	info.canRefundRank = Templates.CanRemoveRank(model, template, info.ID)
	local full = rank >= node.maxRanks
	for _, edge in ipairs(info.visibleEdges or {}) do
		edge.isActive = full
	end
end

-- Rewrites a tier condition (gate) from the view config to match the template.
function Templates.PatchCondInfo(model, template, condID, info)
	local gate = model.gates[condID]
	if not gate or not gate.tree then return end
	local _, perTree = Templates.Points(model, template.ranks)
	local missing = math.max(0, gate.required - (perTree[gate.tree] or 0))
	info.isMet = missing == 0
	info.spentAmountRequired = missing
end
