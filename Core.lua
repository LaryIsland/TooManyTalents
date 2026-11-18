local addonName, ns = ...

-- Names of things in the addon players see or click are marked {like this} in Locales, and shown in a colour of
-- their own: Blizzard's for links and terms in its own text. Done once every locale file has loaded.
ns.NAME_COLOR = "ff71d5ff"
for key, text in pairs(ns.L) do
	if type(text) == "string" and text:find("{", 1, true) then
		rawset(ns.L, key, (text:gsub("{(.-)}", "|c" .. ns.NAME_COLOR .. "%1|r")))
	end
end

-- Config -3: the sandbox the game uses to show talent links. Templates are shown in it.
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

-- The options, kept in AceDB profiles (UI/Options.lua). All off, so the window looks like Blizzard's unless chosen.
local DEFAULTS = {
	oldIcons = false,
	oldPoints = false,
	oldArrows = false,
	hideBottomBar = false,
	hideSearch = false,
	pointsInTabRow = false,
	templateLevel = false,
}

-- Templates, the window's position and the two layout sliders are account-wide.
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
		window:HookScript("OnHide", ns.OnWindowHidden)
		return true
	end
	if ok and window then window:Hide() end
	-- In combat the cause may be combat itself (something protected), so it isn't held against the window: it's tried
	-- again the next time it's needed. Out of combat the failure is the window's own and would repeat every time.
	if inCombat then return false end
	buildFailed = true
	ns.Print(ns.L.WINDOW_FAILED)
	-- A game update that changed what the window is built on (UI/Contract.lua): say what, for a bug report.
	if ns.contractMissing then
		ns.Print(ns.L.WINDOW_FAILED_MISSING, table.concat(ns.contractMissing, ", "))
	end
	return false
end

-- Our window, or nil if it can't be built.
function ns.GetFrame()
	Build()
	return ns.frame
end

-- Whether our window can open on a class's talents (yours if nil): built, and the class's tree readable. Asked before
-- Blizzard's window is touched, so when ours can't open Blizzard's simply opens or stays, and
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

-- When our window last closed. On Forever, Blizzard's talent window is a "center" UI panel
-- (Camelot Blizzard_PlayerSpellsFrame.lua AreaAttributeForTab), and showing one closes every UISpecialFrames window,
-- ours included (UIParentPanelManager.lua: CloseWindows, CloseSpecialWindows), before the hooks below run. GetTime()
-- is the same all through one frame, so a window closed at this GetTime() was closed by the same click.
local windowHiddenAt

function ns.OnWindowHidden()
	windowHiddenAt = GetTime()
end

-- The window's own sounds, as Blizzard's window plays them (UI/Frame.lua OnShow/OnHide). Quiet while ns.quietOpen is
-- set; the close sound's handle is kept so ShowAfterBlizzard can stop it.
local closeSoundHandle

function ns.WindowSound(shown)
	if shown then
		if not ns.quietOpen then PlaySound(SOUNDKIT.UI_CLASS_TALENT_OPEN_WINDOW) end
	else
		local _, handle = PlaySound(SOUNDKIT.UI_CLASS_TALENT_CLOSE_WINDOW)
		closeSoundHandle = handle
	end
end

-- When Blizzard's talent window last opened (a post-hook on its OnShow, set at login).
local blizzardShownAt

-- After one of the hooks below has hidden Blizzard's window again: its sounds (its OnShow and OnHide play them
-- unconditionally) are the last ones started, so they're stopped. That's its close sound, and its open sound only if it
-- opened in this same moment: it didn't if it was already open (on the spellbook, say), as ShowUIPanel then returns
-- early. Sound handles are consecutive numbers, and a sound stopped in the frame it started is never heard (both
-- confirmed in game); the current handle comes from a sound played and stopped at once.
local function StopBlizzardSounds()
	local count = blizzardShownAt == GetTime() and 2 or 1
	local _, handle = PlaySound(SOUNDKIT.UI_CLASS_TALENT_OPEN_WINDOW)
	if type(handle) ~= "number" then return end
	StopSound(handle)
	for previous = handle - count, handle - 1 do
		if C_Sound.IsPlaying(previous) then StopSound(previous) end
	end
end

-- Shows ours after a hook below has hidden Blizzard's window again (Blizzard's sounds stopped): with its own open
-- sound, or with none if Blizzard's opening had just closed it (Inspect Talents or a link with ours open: to the
-- player it never closed, so its close sound is stopped too).
local function ShowAfterBlizzard(window)
	StopBlizzardSounds()
	if windowHiddenAt == GetTime() then
		if closeSoundHandle and C_Sound.IsPlaying(closeSoundHandle) then StopSound(closeSoundHandle) end
		ns.quietOpen = true
		window:Show()
		ns.quietOpen = nil
	else
		window:Show()
	end
end

-- Anything that opens Blizzard's talents through TogglePlayerSpellsFrame (other addons, macros) opens ours in place of
-- Blizzard's; the talent key and micro button go straight to ours (below). This runs after
-- Blizzard's own toggle, so Blizzard's code stays untainted. In combat Blizzard's window is left alone, as hiding a UI
-- panel then isn't safe. Opening someone else's talents is too.
local function AfterBlizzardToggle(suggestedTab, inspectUnit)
	if inspectUnit or suggestedTab ~= PlayerSpellsUtil.FrameTabs.ClassTalents or InCombatLockdown() then return end
	if not ns.CanOpen() then return end
	local blizzard = PlayerSpellsFrame
	local blizzardShown = blizzard and blizzard:IsShown() and blizzard:IsFrameTabActive(suggestedTab)
	if blizzardShown then
		HideUIPanel(blizzard)
		-- Blizzard's opening just closed ours if it was open (above): then the call was to close it, so it stays
		-- closed, with its own close sound. Toggling here would reopen it.
		if windowHiddenAt == GetTime() then
			StopBlizzardSounds()
		else
			ShowAfterBlizzard(ns.GetFrame():GetParent())
		end
	elseif not (blizzard and blizzard:IsShown()) then
		-- Blizzard refused to open (below the talent level), or it was open and this toggle closed it while ours
		-- was showing. Either way, toggle ours.
		ns.Toggle()
	end
end

-- Someone else's talents: a snapshot of the inspected player's build, shaped like a template
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
	-- Their own unspent points, as Blizzard's inspect view shows them, not the level cap's.
	local currencies = C_Traits.GetTreeCurrencyInfo(INSPECT_CONFIG_ID, model.treeID, false)
	local unspent = currencies and currencies[1] and currencies[1].quantity
	return { class = class, name = name, ranks = ranks, choices = choices, unspent = unspent, inspected = true }
end

-- A talent link's build: the link's options are "specID:level:string", the string in Blizzard's loadout format,
-- read with Blizzard's own reader (Blizzard_ClassTalentImportExport.lua ReadLoadoutHeader, ReadLoadoutContent: a few
-- bits per node, in C_Traits.GetTreeNodes order). Shaped like Inspect's snapshot, with the points the link's level
-- would leave unspent. Nil if it can't be read (another serialisation version, a spec we don't know, a bad string).
local CLASS_BY_SPEC = {}
for class, specID in pairs(ns.SPEC_BY_CLASS) do CLASS_BY_SPEC[specID] = class end

function ns.ReadLink(linkOptions)
	local reader, export = ClassTalentImportExportMixin, ExportUtil
	if not (reader and reader.ReadLoadoutHeader and reader.ReadLoadoutContent and export and export.MakeImportDataStream) then
		return
	end
	local level, importText = (linkOptions or ""):match("^[^:]*:([^:]*):([^:]*)$")
	level = tonumber(level)
	if not level or not importText or importText == "" then return end
	local ok, stream = pcall(export.MakeImportDataStream, importText)
	if not ok or not stream then return end
	local valid, version, specID
	ok, valid, version, specID = pcall(reader.ReadLoadoutHeader, reader, stream)
	if not ok or not valid or version ~= C_Traits.GetLoadoutSerializationVersion() then return end
	local class = CLASS_BY_SPEC[specID]
	local model = class and ns.Tree.Get(class)
	if not model then return end
	local content
	ok, content = pcall(reader.ReadLoadoutContent, reader, stream, model.treeID)
	if not ok or type(content) ~= "table" then return end
	local nodeIDs = C_Traits.GetTreeNodes(model.treeID) or {}
	local ranks, choices, spent = {}, {}, 0
	for index, result in ipairs(content) do
		local nodeID = nodeIDs[index]
		local node = nodeID and model.nodes[nodeID]
		-- Granted talents come free; only bought ranks are part of a build.
		if node and result.isNodeSelected and not result.isNodeGranted then
			local rank = result.isPartiallyRanked and math.min(result.partialRanksPurchased or 0, node.maxRanks) or node.maxRanks
			if rank > 0 then
				ranks[nodeID] = rank
				spent = spent + rank
				if result.isChoiceNode then choices[nodeID] = node.entryIDs[result.choiceNodeSelection] end
			end
		end
	end
	-- The points at the link's level: one a level from the first talent level to the cap.
	local atLevel = math.max(0, model.cap - (ns.MaxLevel() - math.min(level, ns.MaxLevel())))
	return {
		class = class, name = ns.L.LINKED_BUILD_NAME:format(ns.ClassName(class)), ranks = ranks, choices = choices,
		unspent = math.max(0, atLevel - spent), inspected = true,
	}
end

-- Inspect Talents and talent links open Blizzard's window on someone else's build; these run after it and open ours on
-- that build in its place. If the build can't be read, Blizzard's window stays. In combat, a Blizzard
-- window that did open stays (hiding a UI panel then isn't safe). If Blizzard's was refused (its ShowUIPanel needs
-- secure code in combat), ours opens on the build instead: ours isn't a UI panel, so Show works then, as for the
-- talent key.
local function OpenBuildInOurs(read, ...)
	local blizzard = PlayerSpellsFrame
	local blizzardShown = blizzard and blizzard:IsShown()
	if blizzardShown and InCombatLockdown() then return end
	local build = read(...)
	if not build or not ns.CanOpen(build.class) then return end
	local window = ns.GetFrame():GetParent()
	if blizzardShown then
		HideUIPanel(blizzard)
		ShowAfterBlizzard(window)
	else
		window:Show()
	end
	-- Shown first: opening the window shows the last screen, so the build goes in after.
	ns.GetFrame():ShowTemplate(build)
end

-- Inspect Talents (right-click a player, Interact) waits for the inspect data, then calls
-- PlayerSpellsUtil.OpenToClassTalentsTab(unit); the build is read while the inspect data is still there.
local function AfterBlizzardInspect(inspectUnit)
	if inspectUnit then OpenBuildInOurs(ns.ReadInspected, inspectUnit) end
end

-- A talent link clicked in chat calls PlayerSpellsUtil.InspectLoadout(linkOptions) (ItemRefHandlers.lua). Blizzard
-- allows one handler per link type, so this is a post-hook too.
local function AfterBlizzardLink(linkOptions)
	OpenBuildInOurs(ns.ReadLink, linkOptions)
end

ns.On("PLAYER_LOGIN", function()
	if PlayerSpellsUtil and PlayerSpellsUtil.TogglePlayerSpellsFrame then
		hooksecurefunc(PlayerSpellsUtil, "TogglePlayerSpellsFrame", AfterBlizzardToggle)
	end
	if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
		hooksecurefunc(PlayerSpellsUtil, "OpenToClassTalentsTab", AfterBlizzardInspect)
	end
	if PlayerSpellsUtil and PlayerSpellsUtil.InspectLoadout then
		hooksecurefunc(PlayerSpellsUtil, "InspectLoadout", AfterBlizzardLink)
	end
	if PlayerSpellsFrame then
		PlayerSpellsFrame:HookScript("OnShow", function() blizzardShownAt = GetTime() end)
	end
	-- The view config is shared with the game's talent links (Tree.viewHolds): note when it's loaded by
	-- anything but us. Post-hooks on the game's API, so its callers run as before.
	hooksecurefunc(C_ClassTalents, "InitializeViewLoadout", ns.Tree.OnViewLoadedElsewhere)
	hooksecurefunc(C_ClassTalents, "ViewLoadout", ns.Tree.OnViewLoadedElsewhere)
end)

-- The talent key itself: bound (an override binding, as addons' own keys are) to a button that toggles our window, so
-- Blizzard's window never opens and closes behind it (closing ours through the hook above doesn't work: Blizzard's
-- opening closes ours first). The binding stays through combat: a binding may click an addon's own button then, and
-- our window is shown with Show, not Blizzard's panel system, so the key opens ours in combat too, with your talents
-- locked as in Blizzard's panel (Frame:IsLocked). Bindings can't change in combat, so a rebinding made then is picked
-- up when it ends.
local keyButton = CreateFrame("Button", "TooManyTalentsKeyButton", UIParent)
keyButton:Hide()
-- Ours, or Blizzard's when ours can't open, opened from our code, which only happens in that failure. Not in
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

-- The talents micro button does what the talent key does, so Blizzard's window doesn't open and close first (playing
-- its open and close sounds on top of ours), as it would through the toggle hook above. Its click script is replaced;
-- its tooltip, highlight and alerts stay Blizzard's. That taints only this button's clicks, so Blizzard's toggle is
-- never called from here in combat: as with the key, ours opens then, or the game's "not in combat" message if ours
-- can't. Blizzard's click script (QuickKeybindButtonTemplate's, with PlayerSpellsMicroButtonMixin:OnClick appended,
-- MainMenuBarMicroButtons.xml) still runs in quick keybind mode (out of combat only), where it binds the clicked mouse
-- button and toggles nothing.
local microButton

local function TakeOverMicroButton()
	microButton = TalentMicroButton
	if not microButton then return end
	local blizzardClick = microButton:GetScript("OnClick")
	microButton:SetScript("OnClick", function(self, mouseButton, down)
		if KeybindFrames_InQuickKeybindMode and KeybindFrames_InQuickKeybindMode() then
			if blizzardClick then blizzardClick(self, mouseButton, down) end
			return
		end
		KeyToggle()
		ns.UpdateMicroButton()
	end)
	hooksecurefunc(microButton, "UpdateMicroButton", ns.UpdateMicroButton)
end

-- The micro button looks pressed while our window is open, as it does for Blizzard's
-- (PlayerSpellsMicroButtonMixin:UpdateMicroButton). Blizzard's update only knows its own window, and pressing the
-- button leaves it pressed (its OnMouseDown calls SetPushed, which only Blizzard's window opening or closing put right,
-- and that window doesn't open here), so this runs after Blizzard's update, after a click, and when our window shows or
-- hides (UI/Frame.lua). Left alone while it's disabled (below the talent level), as Blizzard's update disables it.
function ns.UpdateMicroButton()
	if not microButton or not microButton:IsEnabled() then return end
	local window = ns.frame and ns.frame:GetParent()
	if window and window:IsShown() then
		microButton:SetPushed()
	else
		microButton:SetNormal()
	end
end

ns.On("PLAYER_LOGIN", ArmTalentKey)
ns.On("PLAYER_LOGIN", TakeOverMicroButton)
ns.On("UPDATE_BINDINGS", ArmTalentKey)
ns.On("PLAYER_REGEN_ENABLED", ArmTalentKey)
