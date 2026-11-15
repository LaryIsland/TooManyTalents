local addonName, ns = ...

-- Names of things in the addon players see or click are marked {like this} in Locales, and shown in a colour of
-- their own: Blizzard's for links and terms in its own text. Done once every locale file has loaded.
ns.NAME_COLOR = "ff71d5ff"
for key, text in pairs(ns.L) do
	if type(text) == "string" and text:find("{", 1, true) then
		rawset(ns.L, key, (text:gsub("{(.-)}", "|c" .. ns.NAME_COLOR .. "%1|r")))
	end
end

-- Config -3: the sandbox the game uses to show talent links. Templates are shown in it (design document 4).
ns.VIEW_CONFIG_ID = Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID

-- One spec per class (Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentUtil.lua).
ns.SPEC_BY_CLASS = {
	MAGE = 1482,
	DRUID = 1484,
	HUNTER = 1485,
	PALADIN = 1486,
	PRIEST = 1487,
	ROGUE = 1488,
	SHAMAN = 1489,
	WARLOCK = 1490,
	WARRIOR = 1491,
}

ns.PLAYER_CLASS = select(2, UnitClass("player"))

function ns.MaxLevel()
	return GetMaxLevelForPlayerExpansion()
end

function ns.SpecForClass(class)
	if class == ns.PLAYER_CLASS then
		local specID = PlayerUtil.GetCurrentSpecID()
		if specID then return specID end
	end
	return ns.SPEC_BY_CLASS[class]
end

-- Your active spec group (1 without dual spec).
function ns.ActiveSpecGroup()
	return C_SpecializationInfo.GetActiveSpecGroup() or 1
end

function ns.ClassName(class)
	return LOCALIZED_CLASS_NAMES_MALE[class] or class
end

function ns.ClassColoredName(class)
	local color = C_ClassColor.GetClassColor(class)
	local name = ns.ClassName(class)
	return color and color:WrapTextInColorCode(name) or name
end

-- The player's class first, then the rest by name.
function ns.ClassesInMenuOrder()
	local others = {}
	for class in pairs(ns.SPEC_BY_CLASS) do
		if class ~= ns.PLAYER_CLASS then
			others[#others + 1] = class
		end
	end
	table.sort(others, function(a, b) return ns.ClassName(a) < ns.ClassName(b) end)
	if ns.SPEC_BY_CLASS[ns.PLAYER_CLASS] then
		table.insert(others, 1, ns.PLAYER_CLASS)
	end
	return others
end

-- Chat output has no addon prefix, so it's easy to skim.
function ns.Print(text, ...)
	if select("#", ...) > 0 then
		text = text:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage(text)
end

-- Events ------------------------------------------------------------------------------------------------------------

local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, handler in ipairs(handlers[event]) do
		handler(...)
	end
end)

function ns.On(event, handler)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], handler)
end

-- Saved data --------------------------------------------------------------------------------------------------------

-- The options, kept in AceDB profiles (UI/Options.lua). All off, so the window looks like Blizzard's unless chosen
-- (design document 5.10).
local DEFAULTS = {
	oldIcons = false,
	oldPoints = false,
	oldArrows = false,
	hideBottomBar = false,
	hideSearch = false,
	pointsInTabRow = false,
}

-- Templates, the window's position and the two layout sliders are account-wide (design document 4 and 6).
-- templates[class][name] = { class, name, ranks = { [nodeID] = rank }, choices = { [nodeID] = entryID }, targets }
-- treeGap and talentSpacing are percentages of Blizzard's spacing, 100 being Blizzard's own.
ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	local db = LibStub("AceDB-3.0"):New("TooManyTalentsDB", {
		profile = DEFAULTS,
		global = { templates = {}, window = {}, treeGap = 100, talentSpacing = 100 },
	}, true)
	ns.saved = db.global
	ns.settings = db.profile
	for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
		db.RegisterCallback(ns, event, function()
			ns.settings = db.profile
			if ns.frame then ns.frame:ApplySettings() end
		end)
	end
end)

-- Opening -----------------------------------------------------------------------------------------------------------

-- The window is built the first time it's opened, not in the loading screen. An error in its OnLoad goes to the error
-- handler rather than out of CreateFrame, so a build counts only if both OnLoads ran to their end (they set
-- tmtLoaded). If it fails out of combat, it isn't tried again this session: Blizzard's window is used, and chat says
-- so once. A failure in combat is retried (see Build).
local buildFailed

local function Build()
	if ns.frame then return true end
	if buildFailed then return false end
	local inCombat = InCombatLockdown()
	local ok, window = pcall(CreateFrame, "Frame", "TooManyTalentsFrame", UIParent, "TooManyTalentsWindowTemplate")
	local talents = ok and window and window.TalentsFrame
	if type(talents) == "table" and window.tmtLoaded and talents.tmtLoaded then
		ns.frame = talents
		tinsert(UISpecialFrames, "TooManyTalentsFrame")
		return true
	end
	if ok and window then window:Hide() end
	-- In combat the cause may be combat itself (something protected), so it isn't held against the window: it's tried
	-- again the next time it's needed. Out of combat the failure is the window's own and would repeat every time.
	if inCombat then return false end
	buildFailed = true
	ns.Print(ns.L.WINDOW_FAILED)
	return false
end

-- Our window, or nil if it can't be built.
function ns.GetFrame()
	Build()
	return ns.frame
end

-- Whether our window can open on a class's talents (yours if nil): built, and the class's tree readable. Asked before
-- Blizzard's window is touched (design document 5.11), so when ours can't open Blizzard's simply opens or stays, and
-- nothing is hidden for a window that then doesn't come.
function ns.CanOpen(class)
	if not Build() then return false end
	local ok, model = pcall(ns.Tree.Get, class or ns.PLAYER_CLASS)
	return ok and model ~= nil
end

function ns.Toggle()
	local frame = ns.GetFrame()
	if not frame then return end
	local window = frame:GetParent()
	window:SetShown(not window:IsShown())
end

-- The talent key and micro button open our window in place of Blizzard's (design document 5.11). Both call
-- TogglePlayerSpellsFrame; this runs after Blizzard's own toggle, so Blizzard's code stays untainted. In combat
-- Blizzard's window is left alone, as hiding a UI panel then isn't safe. Opening someone else's talents is too.
local function AfterBlizzardToggle(suggestedTab, inspectUnit)
	if inspectUnit or suggestedTab ~= PlayerSpellsUtil.FrameTabs.ClassTalents or InCombatLockdown() then return end
	if not ns.CanOpen() then return end
	local blizzard = PlayerSpellsFrame
	local blizzardShown = blizzard and blizzard:IsShown() and blizzard:IsFrameTabActive(suggestedTab)
	if blizzardShown then
		HideUIPanel(blizzard)
		ns.Toggle()
	elseif not (blizzard and blizzard:IsShown()) then
		-- Blizzard refused to open (below the talent level), or it was open and this toggle closed it while ours
		-- was showing. Either way, toggle ours.
		ns.Toggle()
	end
end

-- Someone else's talents (design document 5.14): a snapshot of the inspected player's build, shaped like a template
-- but never saved, with `inspected` set so the window shows it read-only. Nil if it can't be read.
local INSPECT_CONFIG_ID = Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID

function ns.ReadInspected(unit)
	if not C_Traits.HasValidInspectData() then return end
	local _, class = UnitClass(unit)
	local name = GetUnitName(unit, true)
	if not canaccessvalue(class) or not canaccessvalue(name) then return end
	if not class or not ns.SPEC_BY_CLASS[class] or not name or name == "" then return end
	local model = ns.Tree.Get(class)
	if not model then return end
	local ranks, choices = ns.Templates.ReadConfig(model, INSPECT_CONFIG_ID)
	-- Their own unspent points, as Blizzard's inspect view shows them, not the level cap's (0.7.1).
	local currencies = C_Traits.GetTreeCurrencyInfo(INSPECT_CONFIG_ID, model.treeID, false)
	local unspent = currencies and currencies[1] and currencies[1].quantity
	return { class = class, name = name, ranks = ranks, choices = choices, unspent = unspent, inspected = true }
end

-- Inspect Talents (right-click a player, Interact) waits for the inspect data, then opens Blizzard's window on that
-- player's talents through PlayerSpellsUtil.OpenToClassTalentsTab(unit). This runs after it: the build is read while
-- the inspect data is still there, then ours opens in place of Blizzard's. Out of combat only, as for the talent key;
-- in combat, or if the build can't be read, Blizzard's window stays.
local function AfterBlizzardInspect(inspectUnit)
	if not inspectUnit or InCombatLockdown() then return end
	local inspected = ns.ReadInspected(inspectUnit)
	if not inspected or not ns.CanOpen(inspected.class) then return end
	local blizzard = PlayerSpellsFrame
	if blizzard and blizzard:IsShown() then
		HideUIPanel(blizzard)
	end
	local frame = ns.GetFrame()
	-- Shown first: opening the window shows your own talents (5.5), so the inspected build goes in after.
	frame:GetParent():Show()
	frame:ShowTemplate(inspected)
end

ns.On("PLAYER_LOGIN", function()
	if PlayerSpellsUtil and PlayerSpellsUtil.TogglePlayerSpellsFrame then
		hooksecurefunc(PlayerSpellsUtil, "TogglePlayerSpellsFrame", AfterBlizzardToggle)
	end
	if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
		hooksecurefunc(PlayerSpellsUtil, "OpenToClassTalentsTab", AfterBlizzardInspect)
	end
end)

-- The talent key itself: bound (an override binding, as addons' own keys are) to a button that toggles our window, so
-- Blizzard's window never opens and closes behind it. In game, closing our window through the hook above failed
-- (8 Nov) without a cause found. The binding stays through combat (0.7.4): a binding may click an addon's own button
-- then, and our window is shown with Show, not Blizzard's panel system, so the key opens ours in combat too, with your
-- talents locked as in Blizzard's panel (Frame:IsLocked). Bindings can't change in combat, so a rebinding made then is
-- picked up when it ends.
local keyButton = CreateFrame("Button", "TooManyTalentsKeyButton", UIParent)
keyButton:Hide()
-- Ours, or Blizzard's when ours can't open (TMT-D1), opened from our code, which only happens in that failure. Not in
-- combat: opening Blizzard's panel from addon code then isn't safe, so the game's "not in combat" message instead.
local function KeyToggle()
	local window = ns.frame and ns.frame:GetParent()
	if (window and window:IsShown()) or ns.CanOpen() then
		ns.Toggle()
	elseif InCombatLockdown() then
		UIErrorsFrame:AddExternalErrorMessage(ERR_NOT_IN_COMBAT)
	elseif PlayerSpellsUtil and PlayerSpellsUtil.TogglePlayerSpellsFrame then
		PlayerSpellsUtil.TogglePlayerSpellsFrame(PlayerSpellsUtil.FrameTabs.ClassTalents)
	end
end

-- Acts on the key going down; on the key coming up only if no "down" click arrived for it.
keyButton:RegisterForClicks("AnyDown", "AnyUp")
keyButton:SetScript("OnClick", function(self, _, down)
	if down then
		self.pressed = true
		KeyToggle()
	elseif self.pressed then
		self.pressed = nil
	else
		KeyToggle()
	end
end)

local keyOwner = CreateFrame("Frame")
local armedKeys

local function ArmTalentKey()
	if InCombatLockdown() then return end
	local keys = table.concat({ GetBindingKey("TOGGLETALENTS") }, " ")
	-- Our own override fires UPDATE_BINDINGS too: only re-arm when the player's keys changed.
	if keys == armedKeys then return end
	armedKeys = keys
	ClearOverrideBindings(keyOwner)
	for key in keys:gmatch("%S+") do
		SetOverrideBindingClick(keyOwner, false, key, keyButton:GetName())
	end
end

ns.On("PLAYER_LOGIN", ArmTalentKey)
ns.On("UPDATE_BINDINGS", ArmTalentKey)
ns.On("PLAYER_REGEN_ENABLED", ArmTalentKey)
