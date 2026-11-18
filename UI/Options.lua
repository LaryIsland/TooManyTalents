local _, ns = ...
local L = ns.L

-- The options, in a small panel beside the talent window, opened from the Actions menu or
-- /tmt options. Changes show at once.

local Options = {}
ns.Options = Options

local PAD = 20
local CLOSE_ROOM = 32 -- either side of the title: the close button and a gap
local TITLE_BAR = 21 -- the frame's title bar, which the title sits in
local SLIDER_WIDTH = 150
local ROW = 30
-- The main window's metal frame without its portrait, over the bronze background of the character panels.
local BORDER_LAYOUT = "ButtonFrameTemplateNoPortrait"
local BACKGROUND = "heavybronze-frame-background"

local panel

local function Changed()
	if ns.frame then ns.frame:ApplySettings() end
end

-- No tooltips: clicking an option shows what it does.
local function Checkbox(parent, key, title)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetSize(26, 26)
	box.Text:SetFontObject("GameFontHighlight")
	box.Text:SetText(title)
	box:SetScript("OnShow", function(self) self:SetChecked(ns.settings[key]) end)
	box:SetScript("OnClick", function(self)
		ns.settings[key] = self:GetChecked()
		Changed()
	end)
	return box
end

-- A label with a slider under it, its value drawn to its right. Percentages of Blizzard's spacing.
local function Slider(parent, key, title, minValue)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetText(title)
	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(SLIDER_WIDTH, 20)
	slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	slider:Init(ns.saved[key], minValue, 100, (100 - minValue) / 5,
		{ [MinimalSliderWithSteppersMixin.Label.Right] = function(value) return FormatPercentage(value / 100, true) end })
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = Round(value)
		if ns.saved[key] ~= value then
			ns.saved[key] = value
			Changed()
		end
	end, label)
	slider:HookScript("OnShow", function(self) self:SetValue(ns.saved[key]) end)
	return label, slider
end

local function Create()
	panel = CreateFrame("Frame", "TooManyTalentsOptions", UIParent)
	panel:SetToplevel(true)
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	table.insert(UISpecialFrames, "TooManyTalentsOptions")

	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas(BACKGROUND)
	background:SetPoint("TOPLEFT", 6, -TITLE_BAR)
	background:SetPoint("BOTTOMRIGHT", -2, 2)
	local border = CreateFrame("Frame", nil, panel, "NineSlicePanelTemplate")
	border:SetAllPoints()
	border:SetFrameLevel(panel:GetFrameLevel())
	NineSliceUtil.ApplyLayoutByName(border, BORDER_LAYOUT)
	CreateFrame("Button", nil, panel, "UIPanelCloseButtonDefaultAnchors")

	-- The title in a frame of its own above the border, whose title bar art would cover it otherwise.
	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetFrameLevel(border:GetFrameLevel() + 10)
	titleBar:SetPoint("TOPLEFT", 24, -1)
	titleBar:SetPoint("TOPRIGHT", -24, -1)
	titleBar:SetHeight(TITLE_BAR - 1)
	local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -5)
	title:SetText(L.OPTIONS_TITLE)

	-- As wide as what's in it: the widest of the title (with room for the close button each
	-- side), each slider with its value and each check box with its text, plus the padding.
	local widest = title:GetUnboundedStringWidth() + 2 * CLOSE_ROOM
	local sliders = {}
	local y = -TITLE_BAR - 14
	for _, slider in ipairs({
		{ "treeGap", L.OPT_TREE_GAP, 0 },
		{ "talentSpacing", L.OPT_TALENT_SPACING, 60 },
	}) do
		local label, control = Slider(panel, slider[1], slider[2], slider[3])
		label:SetPoint("TOPLEFT", PAD, y)
		widest = math.max(widest, label:GetUnboundedStringWidth())
		sliders[#sliders + 1] = control
		y = y - 50
	end
	y = y - 4
	for _, option in ipairs({
		{ "oldIcons", L.OPT_OLD_ICONS },
		{ "oldPoints", L.OPT_OLD_POINTS },
		{ "oldArrows", L.OPT_OLD_ARROWS },
		{ "hideBottomBar", L.OPT_HIDE_BOTTOM_BAR },
		{ "hideSearch", L.OPT_HIDE_SEARCH },
		{ "pointsInTabRow", L.OPT_POINTS_IN_TAB_ROW },
		{ "templateLevel", L.OPT_TEMPLATE_LEVEL },
	}) do
		local box = Checkbox(panel, option[1], option[2])
		box:SetPoint("TOPLEFT", PAD - 4, y)
		-- The text starts at the box's right edge (UICheckButtonTemplate); the box is set 4 left of the padding.
		widest = math.max(widest, box:GetWidth() - 4 + box.Text:GetUnboundedStringWidth())
		y = y - ROW
	end
	panel:SetHeight(-y + 12)
	panel.tmtSliders = sliders
	panel.tmtWidest = widest
	panel:SetWidth(PAD + widest + PAD)
end

-- A slider's value is drawn to its right (MinimalSliderWithSteppersTemplate), so the panel is widened to it once the
-- panel has a place and the slider a value: from the panel's left edge to the value's right edge, plus the padding.
local function FitWidth()
	local left = panel:GetLeft()
	if not left then return end
	local right = 0
	for _, slider in ipairs(panel.tmtSliders) do
		local text = slider.RightText
		if text and text:IsShown() and text:GetRight() then
			right = math.max(right, text:GetRight() - left)
		end
	end
	panel:SetWidth(math.max(PAD + panel.tmtWidest + PAD, right + PAD))
end

-- Left of the talent window, always: the sliders resize the window, which keeps its top left corner, so a panel on
-- its left never moves under the mouse mid-drag. Kept on screen (over the window's edge) when there's no room.
local function Place(frame)
	panel:ClearAllPoints()
	panel:SetPoint("TOPRIGHT", frame:GetParent(), "TOPLEFT", -4, 0)
end

function Options.Show(frame)
	if not panel then Create() end
	Place(frame)
	panel:Show()
	FitWidth()
end

function Options.Toggle(frame)
	if panel and panel:IsShown() then
		panel:Hide()
	else
		Options.Show(frame)
	end
end

function Options.Hide()
	if panel then panel:Hide() end
end
