local _, ns = ...

-- A template set as the target for your talents, shown on your own talents as the rank the
-- target wants, at the top of each talent that differs from it: light blue where you still need points, red where
-- you have points (or a choice) the target doesn't. Nothing on talents that already match. Talented's idea
-- (Talented/view.lua:235-253), without its grey "done" badges.
--
-- Stored on the template itself, keyed by character and spec group, so renaming or deleting the template can't leave
-- a target pointing at nothing: templates[class][name].targets = { ["<GUID>/<spec group>"] = true }.

local Target = {}
ns.Target = Target

local MEDIA = "Interface\\AddOns\\TooManyTalents\\Media\\"

local function Key(specGroup)
	local guid = UnitGUID("player")
	return guid and (guid .. "/" .. specGroup)
end

local function ClassTemplates()
	return ns.saved.templates[ns.PLAYER_CLASS] or {}
end

-- The target for a spec group (the active one if nil), or nil.
function Target.Get(specGroup)
	local key = Key(specGroup or ns.ActiveSpecGroup())
	if not key then return nil end
	for _, template in pairs(ClassTemplates()) do
		if template.targets and template.targets[key] then
			return template
		end
	end
end

function Target.IsTarget(template)
	return template.class == ns.PLAYER_CLASS and Target.Get() == template
end

-- Makes the template the target for a spec group (the active one if nil), or with template nil clears it.
function Target.Set(template, specGroup)
	local key = Key(specGroup or ns.ActiveSpecGroup())
	if not key then return end
	for _, other in pairs(ClassTemplates()) do
		if other.targets then
			other.targets[key] = nil
			if not next(other.targets) then other.targets = nil end
		end
	end
	if template then
		template.targets = template.targets or {}
		template.targets[key] = true
	end
	if ns.frame then ns.TalentedStyle.MarkDirty(ns.frame) end
end

-- Badges ------------------------------------------------------------------------------------------------------------

-- Not a child of the talent button: with Old icons on, the button is drawn at alpha 0.
local function CreateBadge(parent)
	local badge = CreateFrame("Frame", nil, parent)
	badge:EnableMouse(false)
	badge.border = badge:CreateTexture(nil, "ARTWORK")
	badge.border:SetTexture(MEDIA .. "border")
	badge.border:SetSize(32, 32)
	badge.text = badge:CreateFontString(nil, "OVERLAY")
	return badge
end

function Target.HideBadge(button)
	if button.tmtTarget then button.tmtTarget:Hide() end
end

-- Blizzard's look: the rank's own font, mirrored at the top of the talent. Talented's (Old points): its rank badge in
-- the top right corner of the icon (Talented/ui/buttons.lua:27-35, 85-92).
local function ShowBadge(frame, button, rank, color)
	local badge = button.tmtTarget
	if not badge then
		badge = CreateBadge(frame.ButtonsParent)
		button.tmtTarget = badge
	end
	-- In the style of the rank it mirrors, and placed as that rank is, so neither moves when Old icons is toggled:
	-- Talented's badge (Old points) at the top right of the square icon's box centred on the talent, as the points badge
	-- sits at its bottom right; otherwise Blizzard's number mirrored from the bottom of Blizzard's button.
	badge:ClearAllPoints()
	if ns.settings.oldPoints then
		local size = ns.TalentedStyle.ICON_SIZE
		badge:SetSize(size, size)
		badge:SetPoint("CENTER", button)
	else
		badge:SetAllPoints(button)
	end
	badge:SetFrameLevel(button:GetFrameLevel() + 2)
	badge.border:ClearAllPoints()
	badge.text:ClearAllPoints()
	if ns.settings.oldPoints then
		badge.border:SetPoint("CENTER", badge, "TOPRIGHT")
		badge.border:Show()
		badge.text:SetFontObject("GameFontNormalSmall")
		badge.text:SetPoint("CENTER", badge.border)
	else
		badge.border:Hide()
		badge.text:SetFontObject("SystemFont16_Shadow_ThickOutline")
		badge.text:SetPoint("TOP", badge, "TOP", 11, -4)
	end
	badge.text:SetText(rank)
	badge.text:SetTextColor(color:GetRGB())
	badge:Show()
end

-- What the target wants on a node and how that compares with what you have: the badge's rank and colour, or nil.
function Target.Compare(template, nodeID, nodeInfo)
	local wanted = template.ranks[nodeID] or 0
	local have = nodeInfo.ranksPurchased or 0
	if ns.Templates.HasMoreThan(template, nodeID, nodeInfo) then
		return wanted, RED_FONT_COLOR
	elseif have < wanted then
		return wanted, LIGHTBLUE_FONT_COLOR
	end
end

-- Runs with the arrows, at most once per frame (TalentedStyle.Refresh).
function Target.Refresh(frame)
	local template = frame.mode == "player" and Target.Get(frame.specGroup)
	local invisible = TalentButtonUtil.BaseVisualState.Invisible
	for button in frame:EnumerateAllTalentButtons() do
		local nodeID, nodeInfo = button:GetNodeID(), button:GetNodeInfo()
		local rank, color
		if template and nodeID and nodeInfo and button:IsShown() and button:GetVisualState() ~= invisible then
			rank, color = Target.Compare(template, nodeID, nodeInfo)
		end
		if rank then
			ShowBadge(frame, button, rank, color)
		else
			Target.HideBadge(button)
		end
	end
end
