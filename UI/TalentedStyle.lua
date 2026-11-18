local _, ns = ...

-- The Talented look, three options, all off by default:
--  * icons: square action-button style, green when a point can go in, yellow when maxed, grey and desaturated when
--    not available (and darkened as Blizzard's are, most on rows not reached yet), with Blizzard's rank number
--    (Talented/ui/buttons.lua, view.lua:180-250).
--  * points: the rank in Talented's badge at the bottom right, on our icons or Blizzard's, in place of Blizzard's
--    number.
--  * arrows: straight branches that turn at right angles, with Talented's arrowheads (Talented/ui/lines.lua).
-- Blizzard's buttons stay where they are, invisible (alpha 0), so clicks and tooltips are still theirs; the icons are
-- drawn over them. Blizzard's arrows are hidden the same way. The textures in Media/ are Blizzard's Classic talent
-- art, as Talented ships them.

local TalentedStyle = {}
ns.TalentedStyle = TalentedStyle

local MEDIA = "Interface\\AddOns\\TooManyTalents\\Media\\"
local ICON_SIZE = 37
-- The target badges (UI/Target.lua) sit on the same box.
TalentedStyle.ICON_SIZE = ICON_SIZE
local LINE_WIDTH = 32
local VisualState = TalentButtonUtil.BaseVisualState

-- Pieces of branches-normal and arrows-normal (Talented/ui/lines.lua:5-17).
local BRANCH_VERTICAL = { 0.12890625, 0.25390625, 0, 0.96875 }
local BRANCH_HORIZONTAL = { 0.2578125, 0.3828125, 0, 1 }
local BRANCH_TOP_RIGHT = { 0.515625, 0.640625, 0, 1 }
local BRANCH_TOP_LEFT = { 0.640625, 0.515625, 0, 1 }
local ARROW_DOWN = { 0, 0.5, 0, 1 }
-- The right half of arrows-normal points right; flipped, left (Talented's "left"/"right" name the side of the target
-- the arrowhead sits on, not where it points: lines.lua:73-81).
local ARROW_RIGHT = { 0.5, 1, 0, 1 }
local ARROW_LEFT = { 1, 0.5, 0, 1 }

local GREY = CreateColor(0.65, 0.65, 0.65)
-- Blizzard's darkening of unavailable talents, reproduced layer for layer so the icon's colour is Blizzard's own
-- (TalentButtonArtMixin:ApplyVisualState and the square art set):
--  * every unavailable talent: the icon desaturated, then a black overlay, 0.7 on rows whose tier isn't reached yet
--    (gated) and 0.25 on talents locked by a prerequisite or disabled;
--  * gated only: Blizzard's border is then talents-node-square-locked, whose middle isn't empty but a lightly textured
--    warm dark grey (about 52/46/42) at half opacity, drawn over the icon. That's what lifts the shadows. We draw
--    the same art's middle (FILL_INSET: its 4-unit frame of 40 cut off) over ours.
--  * borders: Blizzard's locked frame is 0.64 as bright as its grey one (mean luminance 41.2 against 64.3), so on gated
--    talents both our borders (the state-coloured slot and the button frame) are multiplied by 0.64. Locked and
--    disabled use Blizzard's plain grey border, so ours stay as they are.
local DIM = {
	[VisualState.Gated] = { alpha = 0.7, border = 0.64, fill = true },
	[VisualState.Locked] = { alpha = 0.25, border = 1 },
	[VisualState.Disabled] = { alpha = 0.25, border = 1 },
}
local LOCKED_ART = "talents-node-square-locked"
local FILL_INSET = 4 / 40
-- The arrows' colours follow Blizzard's thin ones (TalentEdgeArrowMixin:UpdateState): gold when the edge is active,
-- dark grey when the talent it points to is gated, light grey otherwise, red when a refund would break it. The greys
-- and red are Blizzard's (talents-arrow-line-gray 81, -locked 48, -red 166/19/19) relative to its gold (166), applied
-- to our gold's strength, as Talented's line art is white.
local ARROW_GREY = CreateColor(0.49, 0.49, 0.49)
local ARROW_LOCKED = CreateColor(0.29, 0.29, 0.29)
local ARROW_RED = CreateColor(1, 0.11, 0.11)

local function ArrowColor(edge, startButton, endButton)
	local startState, endState = startButton:GetVisualState(), endButton:GetVisualState()
	local refundInvalid = startState == VisualState.RefundInvalid
		or (endState == VisualState.RefundInvalid and startState == VisualState.Maxed)
	local info = edge.GetEdgeInfo and edge:GetEdgeInfo()
	if refundInvalid then
		return ARROW_RED
	elseif endState == VisualState.Gated then
		return ARROW_LOCKED
	elseif info and info.isActive then
		return NORMAL_FONT_COLOR
	end
	return ARROW_GREY
end

local function IconsOn() return ns.settings.oldIcons end
local function PointsOn() return ns.settings.oldPoints end

-- Where Blizzard draws the four black copies under its rank number (TalentButtonArtTemplate SpendTextShadow1-4).
local SPEND_SHADOW_OFFSETS = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }
local function ArrowsOn() return ns.settings.oldArrows end

-- Icons ------------------------------------------------------------------------------------------------------------

local function CreateIcon(button, parent)
	local icon = CreateFrame("Frame", nil, parent)
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("CENTER", button)
	icon:EnableMouse(false)

	icon.slot = icon:CreateTexture(nil, "BACKGROUND")
	icon.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot-White")
	icon.slot:SetSize(64, 64)
	icon.slot:SetPoint("CENTER", 0, -1)

	icon.texture = icon:CreateTexture(nil, "BORDER")
	icon.texture:SetAllPoints()

	icon.dim = icon:CreateTexture(nil, "BORDER", nil, 1)
	icon.dim:SetAllPoints()
	icon.dim:SetColorTexture(0, 0, 0)
	icon.dim:Hide()

	-- The middle of Blizzard's locked border, cropped from the atlas by whole-file coordinates (SetAtlas then
	-- SetTexCoord crops the wrong part).
	icon.fill = icon:CreateTexture(nil, "BORDER", nil, 2)
	icon.fill:SetAllPoints()
	icon.fill:Hide()
	local info = C_Texture.GetAtlasInfo(LOCKED_ART)
	if info then
		local width, height = info.rightTexCoord - info.leftTexCoord, info.bottomTexCoord - info.topTexCoord
		icon.fill:SetTexture(info.file)
		icon.fill:SetTexCoord(info.leftTexCoord + width * FILL_INSET, info.rightTexCoord - width * FILL_INSET,
			info.topTexCoord + height * FILL_INSET, info.bottomTexCoord - height * FILL_INSET)
		icon.hasFill = true
	end

	icon.normal = icon:CreateTexture(nil, "ARTWORK")
	icon.normal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	icon.normal:SetSize(64, 64)
	icon.normal:SetPoint("CENTER", 0, -1)

	icon.highlight = icon:CreateTexture(nil, "HIGHLIGHT")
	icon.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	icon.highlight:SetBlendMode("ADD")
	icon.highlight:SetSize(36, 36)
	icon.highlight:SetPoint("CENTER")
	icon.highlight:Hide()

	-- Blizzard's rank number, for Old icons without Old points: Blizzard's own is on its button, drawn at alpha 0, so
	-- this copies its text, colour, font and place, with the four black shadows Blizzard draws under it
	-- (TalentButtonArtTemplate: SpendText on OVERLAY 2, SpendTextShadow1-4 on ARTWORK 1).
	icon.spend = icon:CreateFontString(nil, "OVERLAY", "SystemFont16_Shadow_ThickOutline")
	icon.spend:SetDrawLayer("OVERLAY", 2)
	icon.spendShadows = {}
	for index, offset in ipairs(SPEND_SHADOW_OFFSETS) do
		local shadow = icon:CreateFontString(nil, "ARTWORK", "SystemFont16_Shadow_ThickOutline")
		shadow:SetDrawLayer("ARTWORK", 1)
		shadow:SetTextColor(0, 0, 0)
		shadow:SetPoint("CENTER", icon.spend, "CENTER", offset[1], offset[2])
		icon.spendShadows[index] = shadow
	end
	icon.spend:Hide()
	return icon
end

-- Talented's rank badge in the bottom right corner (Old points), over our icon or Blizzard's button.
local function CreatePoints(parent)
	local points = CreateFrame("Frame", nil, parent)
	points:EnableMouse(false)
	points.border = points:CreateTexture(nil, "OVERLAY")
	points.border:SetTexture(MEDIA .. "border")
	points.border:SetSize(32, 32)
	points.border:SetPoint("CENTER", points, "BOTTOMRIGHT")
	points.rank = points:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	points.rank:SetPoint("CENTER", points.border)
	return points
end

-- Talented's colours for a talent you can put points in: yellow when maxed, green otherwise. Nil when unavailable.
local function AvailableColor(state)
	if state == VisualState.Maxed then
		return NORMAL_FONT_COLOR
	elseif state == VisualState.Selectable or state == VisualState.Normal then
		return GREEN_FONT_COLOR
	end
end

local function SetSpendCopy(icon, button)
	local source = button.SpendText
	local text = source and source:GetText()
	local shown = not PointsOn() and text ~= nil and text ~= ""
	icon.spend:SetShown(shown)
	for _, shadow in ipairs(icon.spendShadows) do
		shadow:SetShown(shown)
	end
	if not shown then return end
	local font = source:GetFontObject()
	icon.spend:SetFontObject(font)
	icon.spend:ClearAllPoints()
	icon.spend:SetPoint(source:GetPoint(1))
	icon.spend:SetText(text)
	icon.spend:SetTextColor(source:GetTextColor())
	for _, shadow in ipairs(icon.spendShadows) do
		shadow:SetFontObject(font)
		shadow:SetText(text)
	end
end

local function UpdateIcon(button)
	local icon = button.tmtIcon
	if not icon then return end
	local state = button:GetVisualState()
	if not IconsOn() or not button:IsShown() or state == VisualState.Invisible then
		icon:Hide()
		-- Old icons turned off: Blizzard's button shows again (it's drawn at alpha 0 under ours).
		if not IconsOn() and state ~= VisualState.Invisible then
			button:SetAlpha(1)
		end
		return
	end
	button:SetAlpha(0)
	icon:SetFrameLevel(button:GetFrameLevel() + 1)
	icon:Show()
	icon.texture:SetTexture(button.Icon and button.Icon:GetTexture() or 134400)
	SetSpendCopy(icon, button)

	local color = AvailableColor(state)
	if color then
		icon.texture:SetDesaturated(false)
		icon.slot:SetVertexColor(color:GetRGB())
	else
		-- The slot's grey is set below, darkened with the border.
		icon.texture:SetDesaturated(true)
	end
	local dim = DIM[state]
	icon.dim:SetShown(dim ~= nil)
	if dim then icon.dim:SetAlpha(dim.alpha) end
	icon.fill:SetShown(dim ~= nil and dim.fill == true and icon.hasFill == true)
	local border = dim and dim.border or 1
	icon.normal:SetVertexColor(border, border, border)
	if not color then
		local r, g, b = GREY:GetRGB()
		icon.slot:SetVertexColor(r * border, g * border, b * border)
	end
end

-- Blizzard's own rank number (and its shadows) is hidden while Old points are on, on our own button instances.
local function SetBlizzardSpendShown(button, shown)
	local alpha = shown and 1 or 0
	if button.SpendText then button.SpendText:SetAlpha(alpha) end
	for _, shadow in ipairs(button.spendTextShadows or {}) do
		shadow:SetAlpha(alpha)
	end
end

-- Talented's badge, only on talents you can put points in (as in Talented), at the square icon's corner whether Old
-- icons is on or not.
local function UpdatePoints(button)
	local points = button.tmtPoints
	if not points then return end
	SetBlizzardSpendShown(button, not PointsOn())
	local state = button:GetVisualState()
	local color = AvailableColor(state)
	if not PointsOn() or not button:IsShown() or state == VisualState.Invisible or not color then
		points:Hide()
		return
	end
	local nodeInfo = button:GetNodeInfo()
	-- The square icon's box, centred on the button as the icon is, so the badge doesn't move when Old icons is toggled
	-- (Blizzard's button is bigger than the icon).
	points:ClearAllPoints()
	points:SetSize(ICON_SIZE, ICON_SIZE)
	points:SetPoint("CENTER", button)
	points:SetFrameLevel(button:GetFrameLevel() + 2)
	points.rank:SetText(nodeInfo and nodeInfo.currentRank or 0)
	points.rank:SetTextColor(color:GetRGB())
	points:Show()
end

local function UpdateButton(button)
	UpdateIcon(button)
	UpdatePoints(button)
end

-- Every button is hooked once, whatever the options: a change to its state or rank redraws the arrows and target
-- badges (next frame), and its icon if it has one. The hooks are on our own button instances, never on Blizzard's
-- mixins.
local function HookButton(frame, button)
	if button.tmtHooked then return end
	button.tmtHooked = true
	local function Changed()
		UpdateButton(button)
		TalentedStyle.MarkDirty(frame)
	end
	hooksecurefunc(button, "SetVisualState", Changed)
	hooksecurefunc(button, "UpdateSpendText", Changed)
	hooksecurefunc(button, "UpdateIconTexture", UpdateIcon)
	button:HookScript("OnShow", UpdateButton)
	button:HookScript("OnHide", function()
		if button.tmtIcon then button.tmtIcon:Hide() end
		if button.tmtPoints then button.tmtPoints:Hide() end
		ns.Target.HideBadge(button)
	end)
	button:HookScript("OnEnter", function() if IconsOn() and button.tmtIcon then button.tmtIcon.highlight:Show() end end)
	button:HookScript("OnLeave", function() if button.tmtIcon then button.tmtIcon.highlight:Hide() end end)
end

-- The icon and the badge are made the first time the button is shown with their option on, and kept (hidden) after.
local function StyleButton(frame, button)
	HookButton(frame, button)
	if IconsOn() and not button.tmtIcon then
		button.tmtIcon = CreateIcon(button, frame.ButtonsParent)
	end
	if PointsOn() and not button.tmtPoints then
		button.tmtPoints = CreatePoints(frame.ButtonsParent)
	end
	UpdateButton(button)
end

local function NeedsStyle(button)
	return IconsOn() or PointsOn() or button.tmtIcon or button.tmtPoints
end

-- Arrows -----------------------------------------------------------------------------------------------------------

-- The arrow pieces, reused between redraws: per texture file, a list and how many are in use.
local function AcquireTexture(frame, file, layer)
	local pool = frame.tmtArrowPools[file]
	pool.used = pool.used + 1
	local texture = pool[pool.used]
	if not texture then
		texture = frame.tmtArrowHolder:CreateTexture(nil, layer)
		texture:SetTexture(file)
		pool[pool.used] = texture
	end
	texture:SetDrawLayer(layer)
	texture:Show()
	return texture
end

local function ReleaseTextures(frame)
	for _, pool in pairs(frame.tmtArrowPools) do
		for index = 1, pool.used do
			pool[index]:Hide()
		end
		pool.used = 0
	end
end

local function Place(texture, coords, x, y, width, height, color)
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", texture:GetParent(), "TOPLEFT", x, y)
	texture:SetSize(width, height)
	texture:SetVertexColor(color:GetRGB())
end

-- A button's centre in ButtonsParent's coordinates, from the layout (positions are set before they're drawn).
local function Center(frame, button)
	local x, y = frame:GetLayoutPosition(button:GetNodeInfo())
	local panX, panY = frame:GetPanOffset()
	return TalentButtonUtil.TranslateNodePositionsToAnchorPositions(x, y, panX, panY)
end

-- Straight down, straight across, or across from the start's row then down to the end (Talented/ui/lines.lua).
local function DrawEdge(frame, startButton, endButton, color)
	local sx, sy = Center(frame, startButton)
	local ex, ey = Center(frame, endButton)
	local half = frame:GetButtonSize() / 2
	local branch, arrow = MEDIA .. "branches-normal", MEDIA .. "arrows-normal"

	if math.abs(sx - ex) < 4 then
		local top, bottom = sy - half, ey + half
		if top - bottom > 0 then
			Place(AcquireTexture(frame, branch, "BORDER"), BRANCH_VERTICAL, sx, (top + bottom) / 2, LINE_WIDTH, top - bottom, color)
		end
		Place(AcquireTexture(frame, arrow, "OVERLAY"), ARROW_DOWN, ex, ey + half + 2, LINE_WIDTH, LINE_WIDTH, color)
	elseif math.abs(sy - ey) < 4 then
		local direction = ex > sx and 1 or -1
		local from, to = sx + direction * half, ex - direction * half
		if math.abs(to - from) > 0 then
			Place(AcquireTexture(frame, branch, "BORDER"), BRANCH_HORIZONTAL, (from + to) / 2, sy, math.abs(to - from), LINE_WIDTH, color)
		end
		Place(AcquireTexture(frame, arrow, "OVERLAY"), direction > 0 and ARROW_RIGHT or ARROW_LEFT, ex - direction * (half + 2), ey, LINE_WIDTH, LINE_WIDTH, color)
	else
		local direction = ex > sx and 1 or -1
		local from, to = sx + direction * half, ex - direction * LINE_WIDTH / 2
		if math.abs(to - from) > 0 then
			Place(AcquireTexture(frame, branch, "BORDER"), BRANCH_HORIZONTAL, (from + to) / 2, sy, math.abs(to - from), LINE_WIDTH, color)
		end
		Place(AcquireTexture(frame, branch, "BORDER"), direction > 0 and BRANCH_TOP_LEFT or BRANCH_TOP_RIGHT, ex, sy, LINE_WIDTH, LINE_WIDTH, color)
		local top, bottom = sy - LINE_WIDTH / 2, ey + half
		if top - bottom > 0 then
			Place(AcquireTexture(frame, branch, "BORDER"), BRANCH_VERTICAL, ex, (top + bottom) / 2, LINE_WIDTH, top - bottom, color)
		end
		Place(AcquireTexture(frame, arrow, "OVERLAY"), ARROW_DOWN, ex, ey + half + 2, LINE_WIDTH, LINE_WIDTH, color)
	end
end

local function DrawArrows(frame)
	ReleaseTextures(frame)
	local holder = frame.tmtArrowHolder
	holder:SetShown(ArrowsOn())
	if not ArrowsOn() then return end
	-- Under the buttons and their icons.
	holder:SetFrameLevel(frame.ButtonsParent:GetFrameLevel() + 1)
	for edge in frame.edgePool:EnumerateActive() do
		local startButton, endButton = edge:GetStartButton(), edge:GetEndButton()
		if startButton and endButton and startButton:GetNodeInfo() and endButton:GetNodeInfo() then
			DrawEdge(frame, startButton, endButton, ArrowColor(edge, startButton, endButton))
		end
	end
end

local function SetEdgeAlpha(edge)
	edge:SetAlpha(ArrowsOn() and 0 or 1)
end

-- Hooks into the panel ---------------------------------------------------------------------------------------------

function TalentedStyle.Init(frame)
	local holder = CreateFrame("Frame", nil, frame.ButtonsParent)
	holder:SetAllPoints()
	frame.tmtArrowHolder = holder
	frame.tmtArrowPools = {
		[MEDIA .. "branches-normal"] = { used = 0 },
		[MEDIA .. "arrows-normal"] = { used = 0 },
	}

	frame:RegisterCallback(TalentFrameBaseMixin.Event.TalentButtonAcquired, function(_, button)
		if NeedsStyle(button) then
			StyleButton(frame, button)
		else
			HookButton(frame, button)
		end
	end, frame)
	hooksecurefunc(frame, "AcquireEdge", function(_, _, _, _)
		TalentedStyle.MarkDirty(frame)
	end)
	hooksecurefunc(frame, "UpdateAllButtons", function() TalentedStyle.MarkDirty(frame) end)
end

-- Redrawn at most once per frame.
function TalentedStyle.MarkDirty(frame)
	if frame.tmtStyleDirty then return end
	frame.tmtStyleDirty = true
	RunNextFrame(function()
		frame.tmtStyleDirty = false
		TalentedStyle.Refresh(frame)
	end)
end

function TalentedStyle.Refresh(frame)
	if not frame:IsVisible() then return end
	for edge in frame.edgePool:EnumerateActive() do
		SetEdgeAlpha(edge)
	end
	DrawArrows(frame)
	ns.Target.Refresh(frame)
end

-- An option changed: style every button, or put Blizzard's look back.
function TalentedStyle.Apply(frame)
	-- Each piece hides itself (and gives Blizzard's back) when its option is off.
	for button in frame:EnumerateAllTalentButtons() do
		if NeedsStyle(button) then
			StyleButton(frame, button)
		end
	end
	TalentedStyle.Refresh(frame)
end
