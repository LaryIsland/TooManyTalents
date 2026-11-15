local _, ns = ...

-- A small two-level menu of our own, for the Templates tab (design document 5.3). Blizzard's menu system opens a
-- submenu only once the mouse has rested on its entry for a third of a second (Blizzard_Menu/Menu.lua,
-- RestartMouseEventTimer, in secure code addons can't change); here the class submenus open the moment they're
-- hovered. Drawn with the same art as Forever's menus (Blizzard_Menu/Mainline/MenuTemplates.lua MenuStyle1Mixin,
-- Mainline/MenuVariants.lua CreateRadio, MenuVariants.lua dividers, arrows and highlights).
--
-- Entries: { text = , onClick = function, radio = true, checked = bool } | { text = , submenu = function -> entries }
-- | { divider = true }.

local Flyout = {}
ns.Flyout = Flyout

local ROW_HEIGHT, DIVIDER_HEIGHT = 20, 13
local INSET_LEFT, INSET_TOP, INSET_RIGHT, INSET_BOTTOM = 8, 8, 8, 15
local EXTRA_WIDTH = 20  -- Blizzard's child extent padding
local ARROW_WIDTH = 16
-- The first level opens a little up and left of the cursor, so the cursor lands on its first row.
local CURSOR_OFFSET_X, CURSOR_OFFSET_Y = -12, 8

local levels = {}
local owner, closedByOwner

local function SetKeyboard(menu, enabled)
	-- Keyboard propagation can't be changed in combat; the menu then closes with the window instead of on Escape.
	if InCombatLockdown() then return end
	menu:EnableKeyboard(enabled)
	if enabled then menu:SetPropagateKeyboardInput(true) end
end

local function CloseLevel(index)
	for level = #levels, index, -1 do
		local menu = levels[level]
		if menu:IsShown() then
			if menu.parentRow then
				menu.parentRow.highlight:Hide()
				menu.parentRow = nil
			end
			SetKeyboard(menu, false)
			menu:Hide()
		end
	end
end

function Flyout.Close()
	if levels[1] and levels[1]:IsShown() then
		CloseLevel(1)
	end
	owner = nil
end

function Flyout.IsOpen()
	return levels[1] ~= nil and levels[1]:IsShown()
end

local OpenLevel

local function RowEnter(row)
	row.highlight:Show()
	local menu = row:GetParent()
	local deeper = levels[menu.level + 1]
	local open = deeper and deeper:IsShown() and deeper.parentRow == row
	if deeper and deeper:IsShown() and not open then
		CloseLevel(menu.level + 1)
	end
	if row.entry.submenu and not open then
		OpenLevel(menu.level + 1, row.entry.submenu(), row)
	end
end

-- A row whose submenu is open stays highlighted.
local function RowLeave(row)
	local deeper = levels[row:GetParent().level + 1]
	if not (deeper and deeper:IsShown() and deeper.parentRow == row) then
		row.highlight:Hide()
	end
end

local function RowClick(row)
	local entry = row.entry
	if entry.submenu then return end
	Flyout.Close()
	if entry.onClick then entry.onClick() end
end

local function CreateRow(menu)
	local row = CreateFrame("Button", nil, menu)
	row:SetHeight(ROW_HEIGHT)
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.highlight:SetBlendMode("ADD")
	row.highlight:Hide()
	row.radio = row:CreateTexture(nil, "ARTWORK")
	row.radio:SetAtlas("common-dropdown-tickradial", TextureKitConstants.UseAtlasSize)
	row.radio:SetPoint("LEFT", -3, 0)
	row.tick = row:CreateTexture(nil, "OVERLAY")
	row.tick:SetAtlas("common-dropdown-icon-radialtick-yellow", TextureKitConstants.UseAtlasSize)
	row.tick:SetPoint("TOPLEFT", row.radio, "TOPLEFT")
	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.text:SetHeight(ROW_HEIGHT)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.arrow = row:CreateTexture(nil, "ARTWORK")
	row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	row.arrow:SetSize(ARROW_WIDTH, ARROW_WIDTH)
	row.arrow:SetPoint("RIGHT")
	row.divider = row:CreateTexture(nil, "ARTWORK")
	row.divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
	row.divider:SetHeight(DIVIDER_HEIGHT)
	row.divider:SetPoint("LEFT")
	row.divider:SetPoint("RIGHT")
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	row:SetScript("OnClick", RowClick)
	return row
end

local function CreateLevel(index)
	local menu = CreateFrame("Frame", "TooManyTalentsFlyout" .. index, UIParent)
	menu.level = index
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetToplevel(true)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	local background = menu:CreateTexture(nil, "BACKGROUND", nil, -1)
	background:SetAtlas("common-dropdown-bg")
	background:SetPoint("TOPLEFT", -10, 3)
	background:SetPoint("BOTTOMRIGHT", 10, -3)
	background:SetAlpha(0.925)
	menu:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
			Flyout.Close()
		end
	end)
	menu.rows = {}
	levels[index] = menu
	return menu
end

-- Lays out the entries and sizes the menu to fit the widest.
local function Fill(menu, entries)
	local width, y = 0, INSET_TOP
	for index, entry in ipairs(entries) do
		local row = menu.rows[index] or CreateRow(menu)
		menu.rows[index] = row
		row.entry = entry
		row.highlight:Hide()
		local divider = entry.divider
		row:SetHeight(divider and DIVIDER_HEIGHT or ROW_HEIGHT)
		row:EnableMouse(not divider)
		row.divider:SetShown(divider)
		row.radio:SetShown(entry.radio == true)
		row.tick:SetShown(entry.radio == true and entry.checked == true)
		row.arrow:SetShown(entry.submenu ~= nil)
		row.text:SetShown(not divider)
		row.text:ClearAllPoints()
		local rowWidth = 0
		if not divider then
			row.text:SetText(entry.text)
			if entry.radio then
				row.text:SetPoint("LEFT", row.radio, "RIGHT", 1, 0)
				rowWidth = row.radio:GetWidth() - 3 + 1
			else
				row.text:SetPoint("LEFT")
			end
			rowWidth = rowWidth + row.text:GetUnboundedStringWidth() + (entry.submenu and ARROW_WIDTH or 0)
		end
		width = math.max(width, rowWidth)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", INSET_LEFT, -y)
		row:SetPoint("RIGHT", -INSET_RIGHT, 0)
		row:Show()
		y = y + row:GetHeight()
	end
	for index = #entries + 1, #menu.rows do
		menu.rows[index]:Hide()
	end
	menu:SetSize(INSET_LEFT + width + EXTRA_WIDTH + INSET_RIGHT, y + INSET_BOTTOM)
end

-- Level 1 just up and left of the cursor; deeper levels against their row, as Blizzard's submenus are
-- (Blizzard_Menu/Menu.lua GenerateSubmenuInternal: TOPLEFT on the row's TOPRIGHT, so the backgrounds meet), on
-- whichever side fits, lined up so their first row is level with it.
function OpenLevel(index, entries, parentRow)
	local menu = levels[index] or CreateLevel(index)
	CloseLevel(index)
	Fill(menu, entries)
	menu:ClearAllPoints()
	if parentRow then
		menu.parentRow = parentRow
		parentRow.highlight:Show()
		local right = parentRow:GetRight() + menu:GetWidth()
		if right <= UIParent:GetRight() then
			menu:SetPoint("TOPLEFT", parentRow, "TOPRIGHT", 0, INSET_TOP)
		else
			menu:SetPoint("TOPRIGHT", parentRow, "TOPLEFT", 0, INSET_TOP)
		end
		menu:SetFrameLevel(levels[index - 1]:GetFrameLevel() + 20)
	else
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + CURSOR_OFFSET_X, y / scale + CURSOR_OFFSET_Y)
	end
	menu:Show()
	SetKeyboard(menu, true)
end

-- Opens the menu for a button (a tab). Clicking that button again while it's open closes it, as Blizzard's do.
function Flyout.Open(ownerButton, entries)
	if closedByOwner == ownerButton then
		closedByOwner = nil
		return
	end
	Flyout.Close()
	owner = ownerButton
	OpenLevel(1, entries)
end

-- A click anywhere outside the menu closes it.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
watcher:SetScript("OnEvent", function()
	closedByOwner = nil
	if not Flyout.IsOpen() then return end
	for _, menu in ipairs(levels) do
		if menu:IsShown() and menu:IsMouseOver() then return end
	end
	if owner and owner:IsMouseOver() then closedByOwner = owner end
	Flyout.Close()
end)
