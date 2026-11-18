local _, ns = ...
local L = ns.L

-- Our own copy of Forever's talent panel: TalentFrameBaseMixin (Blizzard_SharedTalentUI) with
-- the class panel's behaviour from Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua and its Camelot
-- overrides. This file is our own logic; the parts copied from Blizzard's code are in UI/BlizzardCopy.lua, each with
-- its source, and the layout in UI/Layout.lua. Nothing here touches Blizzard's own window.
--
-- It shows one of two things:
--  * "player": your own talents, for either spec group, through your real config. Your active spec is editable and
--    saved with Apply; the other spec group and a read-only view are locked.
--  * "template": a template, through the view config (-3), with each node's state patched from the template
--    (Templates.PatchNodeInfo). Clicks change the template, never your talents. Someone else's talents
--    are shown the same way, read-only.

local VIEW_CONFIG_ID = ns.VIEW_CONFIG_ID
-- Above the talent buttons, for our controls over the tree area (the per-tree reset buttons, Apply and Undo in the
-- corner), which the buttons would otherwise take clicks from: they sit at ButtonsParent's level plus up to about 500
-- (GetFrameLevelForButton). Below the choice flyout (2000).
ns.ABOVE_TALENTS_LEVEL = 900

-- Events only the class panel needs, while shown (Blizzard_ClassTalentsFrame.lua ClassTalentsFrameEvents).
local SHOWN_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
-- The two failures are for a spec switch that doesn't finish (Frame:SetSpecSwitchCastBarActive).
local SHOWN_UNIT_EVENTS = { "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

-- How long a view config that won't load is left before it's tried again (Frame:EnsureView).
local VIEW_RETRY_SECONDS = 2

-- Node events that only matter for a real config. On a template we refresh ourselves.
local NODE_EVENTS = {
	TRAIT_NODE_CHANGED = true,
	TRAIT_NODE_CHANGED_PARTIAL = true,
	TRAIT_NODE_ENTRY_UPDATED = true,
	TRAIT_SUB_TREE_CHANGED = true,
	TRAIT_TREE_CURRENCY_INFO_UPDATED = true,
}

-- The game's class IDs, fixed (the keys of Blizzard's ClassVisuals, Camelot Blizzard_ClassTalentUtil.lua). Not read
-- with GetClassInfo(1 .. GetNumClasses()): on Forever that stops short of the druid's 11, which would leave the druid
-- without class visuals and its talents left of their headers.
local CLASS_IDS = {
	WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

-- The window -------------------------------------------------------------------------------------------------------

TooManyTalentsWindowMixin = {}
local Window = TooManyTalentsWindowMixin

-- Puts the window back where it was last placed (dragged or centred), by its top left corner, if it ever was. Called
-- by every layout, after the window's final size is set (UI/Layout.lua): an anchor set on load doesn't survive until the
-- first layout.
function ns.RestoreWindowPosition(window)
	local saved = ns.saved.window
	-- Mid-drag the mouse has it; it's saved when dropped.
	if not saved.point or window.tmtMoving then return end
	window:ClearAllPoints()
	window:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
end

function Window:OnLoad()
	self:RegisterForDrag("LeftButton")
	self:SetTitle(TALENTS)
	self.tmtLoaded = true
end

-- The open and close sounds, Blizzard's window's own (Core.lua ns.WindowSound, which keeps them in step with Blizzard's
-- window when the hooks open ours in its place).
function Window:OnShow()
	ns.WindowSound(true)
	-- When it opened, for Frame:NoteView (no switch sound on opening). Not when it's shown again in the same moment
	-- Blizzard's window closed it (ns.quietOpen): to the player it stayed open.
	if not ns.quietOpen then self.tmtOpenedAt = GetTime() end
	ns.UpdateMicroButton()
end

function Window:OnHide()
	ns.WindowSound(false)
	ns.UpdateMicroButton()
end

function Window:OnDragStart()
	self.tmtMoving = true
	self:StartMoving()
end

-- Saved by the top left corner, so the window keeps its place when the layout options change its size.
local function PlaceWindow(window, left, top)
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	local saved = ns.saved.window
	saved.point, saved.relativePoint, saved.x, saved.y = "TOPLEFT", "BOTTOMLEFT", left, top
end

function Window:OnDragStop()
	self:StopMovingOrSizing()
	self.tmtMoving = nil
	PlaceWindow(self, self:GetLeft(), self:GetTop())
end

-- Shift-right-click anywhere on the window that isn't a control centres it on the screen at its current size. The
-- talent area's own frames take the mouse, so they pass it on (Frame:OnLoad).
function Window:OnMouseUp(button)
	if button ~= "RightButton" or not IsShiftKeyDown() then return end
	local screenWidth, screenHeight = UIParent:GetSize()
	PlaceWindow(self, Round((screenWidth - self:GetWidth()) / 2), Round((screenHeight + self:GetHeight()) / 2))
end

-- The talent panel ------------------------------------------------------------------------------------------------

TooManyTalentsFrameMixin = CreateFromMixins(TalentFrameBaseMixin, ClassTalentSearchMixin)
local Frame = TooManyTalentsFrameMixin

function Frame:OnLoad()
	-- First, while the window, panel and background still have Frame.xml's sizes (UI/Layout.lua).
	self:ReadBlizzardSizes()
	-- Blizzard's code that the panel relies on, before any of it is used (UI/Contract.lua): if a game update
	-- changed it, the window isn't built (tmtLoaded stays unset) and Blizzard's opens instead.
	ns.contractMissing = ns.Contract.CheckBlizzard()
	if ns.contractMissing then return end
	self.initialBasePanOffsetX = self.basePanOffsetX
	self.initialBasePanOffsetY = self.basePanOffsetY
	self.initialBottomPadding = self.bottomPadding
	TalentFrameBaseMixin.OnLoad(self)

	-- One tab for your talents, named for the spec group it shows (Primary or Secondary, as in Blizzard's panel); each
	-- click switches to the other group. Actions and Templates open menus.
	TabSystemOwnerMixin.OnLoad(self)
	self:SetTabSystem(self.TabSystem)
	self.specTabID = self:AddNamedTab(DUAL_SPEC_PRIMARY)
	self.actionsTabID = self:AddNamedTab(L.TAB_ACTIONS)
	self.templatesTabID = self:AddNamedTab(L.TAB_TEMPLATES)
	-- The tab system's sound (TabSystemTemplate's tabSelectSound) is played by NoteView on every switch of what's shown,
	-- the spec tab's included, so the tab system itself doesn't play it too.
	self.switchSound = self.TabSystem.tabSelectSound or SOUNDKIT.IG_CHARACTER_INFO_TAB
	self.TabSystem.tabSelectSound = nil

	self.treeHeaderPool = CreateFramePool("FRAME", self, "ClassTalentTreeHeaderTemplate")
	self.treeHeaders = {}
	self.resetButtonPool = CreateFramePool("BUTTON", self, "TooManyTalentsTreeResetButtonTemplate")

	self.ApplyButton:SetOnClickHandler(GenerateClosure(self.ApplyConfig, self))
	self.UndoButton:SetOnClickHandler(GenerateClosure(self.RollbackConfig, self))

	local nameBox = self.NameBox
	nameBox.Instructions:SetText(L.NAME_BOX_HINT)
	nameBox.tmtTextColor = { nameBox:GetTextColor() }
	nameBox:SetScript("OnTextChanged", function(box)
		box.Instructions:SetShown(box:GetText() == "")
	end)
	nameBox:SetScript("OnEnterPressed", EditBox_ClearFocus)
	nameBox:SetScript("OnEscapePressed", function(box)
		box.cancelled = true
		box:ClearFocus()
	end)
	nameBox:SetScript("OnEditFocusLost", function(box)
		EditBox_ClearHighlight(box)
		local template = self.template
		if template and not box.cancelled then
			ns.Templates.Rename(template, box:GetText())
		end
		box.cancelled = nil
		box:SetText(template and template.name or "")
	end)

	self.DisabledOverlay:ClearAllPoints()
	self.DisabledOverlay:SetPoint("TOPLEFT", self.ClassBackground, "TOPLEFT")
	self.DisabledOverlay:SetPoint("BOTTOMRIGHT", self.ClassBackground, "BOTTOMRIGHT")

	-- The tree area (panning) and the greyed overlay over an inactive spec cover most of the window and take the
	-- mouse: Shift-right-click on them centres the window as it does on the window itself.
	local window = self:GetParent()
	for _, area in ipairs({ self.ButtonsParent, self.DisabledOverlay }) do
		area:HookScript("OnMouseUp", function(_, button) Window.OnMouseUp(window, button) end)
	end

	self:InitializeSearch()
	self:InitializeSearchOptionsDropdown()
	ns.TalentedStyle.Init(self)

	-- And what the built panel has from Blizzard's mixins and templates (fields, children, a tab and a tree header).
	ns.contractMissing = ns.Contract.CheckPanel(self)
	if ns.contractMissing then return end

	self:RegisterEvent("PLAYER_TALENT_UPDATE")
	self:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
	-- Reached only if nothing above errored: ns.CanOpen (Core.lua) checks it before Blizzard's window is touched.
	self.tmtLoaded = true
end

function Frame:OnShow()
	-- The window opens where you last had it this session.
	self:ShowLastScreen()

	TalentFrameBaseMixin.OnShow(self)
	FrameUtil.RegisterFrameForEvents(self, SHOWN_EVENTS)
	FrameUtil.RegisterFrameForUnitEvents(self, SHOWN_UNIT_EVENTS, "player")
	self:SetBackgroundAnimationsPlaying(true)
	self:UpdateConfigButtonsState()
end

function Frame:OnHide()
	TalentFrameBaseMixin.OnHide(self)
	FrameUtil.UnregisterFrameForEvents(self, SHOWN_EVENTS)
	FrameUtil.UnregisterFrameForEvents(self, SHOWN_UNIT_EVENTS)
	self:SetBackgroundAnimationsPlaying(false)
	self:SetDisabledOverlayShown(false)
	-- As Camelot's ClassTalentsFrame:OnHide (HideSpecChangeElements); a switch still going is caught on the next open
	-- by ACTIVE_COMBAT_CONFIG_CHANGED.
	self:SetSpecSwitchCastBarActive(false)
	self.NameBox:ClearFocus()
	ns.Options.Hide()
	ns.Flyout.Close()
end

function Frame:OnEvent(event, ...)
	if self.mode == "template" and NODE_EVENTS[event] then return end

	if event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
		self:SetSpecSwitchCastBarActive(false)
		if self:IsShown() and self.mode == "player" then
			self:ShowPlayerTalents(self.specGroup)
		end
		self:UpdateTabs()
	elseif event == "PLAYER_TALENT_UPDATE" then
		self:UpdateTabs()
		if self:IsShown() then self:RefreshChrome() end
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" or event == "UNIT_AURA" then
		self:UpdateConfigButtonsState()
		self:UpdateAllButtons()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = select(3, ...)
		if spellID == Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID then
			self:SetCommitVisualsActive(false, TalentFrameBaseMixin.VisualsUpdateReasons.CommitStoppedComplete)
			self:SetCommitCompleteVisualsActive(true)
		end
	elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED") and self.tmtSpecSwitching then
		-- A spec switch that didn't finish (moving, interrupted): the spinner and grey overlay go, back to the spec
		-- group as it was (Blizzard's spec tab does the same on these events, Mainline
		-- Blizzard_ClassSpecializationsFrame.lua:185). Only once nothing is being cast, so a failed press of another
		-- spell while the switch is cast doesn't end it.
		if not UnitCastingInfo("player") then
			self:SetSpecSwitchCastBarActive(false)
			if self.mode == "player" then
				self:ShowPlayerTalents(self.specGroup)
			end
		end
	end

	TalentFrameBaseMixin.OnEvent(self, event, ...)

	-- A failed commit leaves the config as it was: show it again (Blizzard's ResetToLastConfigID).
	if event == "CONFIG_COMMIT_FAILED" and self:IsShown() and self.mode == "player" then
		self:ShowPlayerTalents(self.specGroup)
	end
end

-- What's shown ------------------------------------------------------------------------------------------------------

function Frame:GetShownClass()
	return self.template and self.template.class or ns.PLAYER_CLASS
end

-- Whether your active spec group is on show (editable, unless read-only).
function Frame:IsActiveTabSelected()
	return self.mode == "player" and self.specGroup == ns.ActiveSpecGroup()
end

-- The last screen shown this session, to open on next time: your talents (`specGroup` set only for the spec
-- group that wasn't active, so your active spec stays the one shown after a spec change) or a template. Someone
-- else's build isn't kept: closing on it opens on whatever came before it. Only in memory, so the first open of a
-- session (or after a reload) is always your own talents.
local lastScreen

function Frame:ShowLastScreen()
	local template = lastScreen and lastScreen.template
	if template then
		-- Still saved under its name (renames keep the same table), and its class's tree readable. Checked here, not
		-- left to ShowTemplate, so a tree that can't be read falls back to your talents without its chat line.
		local ok, model = pcall(ns.Tree.Get, template.class)
		if ns.Templates.Get(template.class, template.name) == template and ok and model and self:ShowTemplate(template) then
			return
		end
	end
	local specGroup = lastScreen and lastScreen.specGroup
	if specGroup and specGroup > GetNumSpecGroups() then specGroup = nil end
	self:ShowPlayerTalents(specGroup)
end

-- The spec tab's sound whenever what's shown changes while the window is already open:
-- between your talents (either spec group), templates, someone else's build and a talent link. Not when the window
-- opens (Window:OnShow notes when; showing its last screen or the build it opened for is part of opening), and not
-- when the same thing is shown again (a refresh). Nor while it's shown again in the moment Blizzard's window closed it
-- (ns.quietOpen, Inspect Talents or a link with ours open): its last screen comes back first, then the build, and only
-- the build is a switch (one sound, not two). `key` is the template, or "player<spec group>".
function Frame:NoteView(key)
	local window = self:GetParent()
	if self.viewKey ~= nil and key ~= self.viewKey and window:IsShown() and window.tmtOpenedAt ~= GetTime()
		and not ns.quietOpen then
		PlaySound(self.switchSound)
	end
	self.viewKey = key
end

-- Your own talents for a spec group (the active one if nil).
function Frame:ShowPlayerTalents(specGroup)
	local activeGroup = ns.ActiveSpecGroup()
	specGroup = specGroup or activeGroup
	lastScreen = { specGroup = specGroup ~= activeGroup and specGroup or nil }
	self.mode = "player"
	self.template = nil
	self.specGroup = specGroup
	self.model = ns.Tree.Get(ns.PLAYER_CLASS)
	self.viewOnly = false
	self.viewRetryAt = nil
	TabSystemOwnerMixin.SetTab(self, self.specTabID)

	local configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(specGroup)
	if specGroup == activeGroup then
		configID = C_ClassTalents.GetActiveConfigID() or configID
		if not configID and ns.Tree.InitializeView(ns.PLAYER_CLASS) then
			-- Below the talent level there may be no config yet: show the empty tree, read-only.
			configID = VIEW_CONFIG_ID
			self.viewOnly = true
		end
	end

	self:UpdateClassVisuals()
	if configID then
		self:SetDisabledOverlayShown(false)
		self.ActiveSpec:SetGlow(false)
		self:SetConfigID(configID, true)
	else
		-- The second spec isn't unlocked: Blizzard's panel greys the tree and highlights Activate.
		self:SetDisabledOverlayShown(true)
		self.ActiveSpec:SetGlow(true)
	end
	self:RefreshChrome()
	self:NoteView("player" .. specGroup)
end

-- Returns whether it's shown. It isn't if its class's tree can't be read or the game won't load it into the view
-- config: it says so, and the window stays on what it showed (your own talents, if it showed nothing yet).
function Frame:ShowTemplate(template)
	local model = ns.Tree.Get(template.class)
	-- Talents no longer in the game (after a patch) are dropped, giving their points back, and it says so.
	local orphans = model and ns.Templates.RemoveOrphans(model, template) or 0
	if orphans > 0 then
		ns.Print(L.ORPHANS_FOUND, template.name, orphans)
	end
	if not model or not ns.Templates.LoadIntoView(model, template) then
		ns.Print(L.NO_TREE_DATA, ns.ClassName(template.class))
		if not self.mode then
			self:ShowPlayerTalents()
		end
		return false
	end
	self.NameBox:ClearFocus()
	if not template.inspected then lastScreen = { template = template } end
	self.mode = "template"
	self.template = template
	self.model = model
	self.viewRetryAt = nil
	self.TabSystem:SetTabVisuallySelected(nil)
	self:UpdateClassVisuals()
	self:SetDisabledOverlayShown(false)
	self:SetConfigID(VIEW_CONFIG_ID, true)
	self:RefreshChrome()
	self:NoteView(template)
	return true
end

-- Called after a template's ranks change: reload the view config and redraw every button in place, so the tooltip
-- under the mouse stays up while clicking. If the game won't load it now, back to your own talents.
function Frame:RefreshTemplate()
	if self.mode ~= "template" then return end
	if not ns.Templates.LoadIntoView(self.model, self.template) then
		ns.Print(L.NO_TREE_DATA, ns.ClassName(self.template.class))
		self:ShowPlayerTalents()
		return
	end
	self:ClearInfoCaches()
	for button in self:EnumerateAllTalentButtons() do
		button:UpdateNodeInfo()
	end
	self:UpdateTreeCurrencyInfo()
	self:RefreshGates()
end

function Frame:SetConfigID(configID, forceUpdate)
	if not forceUpdate and configID == self:GetConfigID() then return end
	local configInfo = configID and C_Traits.GetConfigInfo(configID)
	if not configInfo and configID == VIEW_CONFIG_ID and self.model then
		configInfo = { ID = configID, treeIDs = { self.model.treeID } }
	end
	if not configInfo then return end
	self.configurationInfo = configInfo
	self:SetTalentTreeID(configInfo.treeIDs[1], true)
end

-- Blizzard_ClassTalentsFrame.lua UpdateClassVisuals and UpdateSpecBackground, for the class shown.
function Frame:UpdateClassVisuals()
	local class = self:GetShownClass()
	local classVisuals = ClassTalentUtil.GetVisualsForClassID(CLASS_IDS[class])
	if classVisuals and classVisuals.activationFX and C_Texture.GetAtlasInfo(classVisuals.activationFX) then
		for _, texture in ipairs(self.classActivationTextures) do
			texture:SetAtlas(classVisuals.activationFX, TextureKitConstants.UseAtlasSize)
		end
	end
	local offsets = classVisuals and classVisuals.panOffset
	self:SetBasePanOffset(self.initialBasePanOffsetX - (offsets and offsets.x or 0), self:GetBaseOffsetYForClass())

	local specVisuals = ClassTalentUtil.GetVisualsForSpecID(ns.SpecForClass(class))
	self.specBackgroundAtlas = specVisuals and specVisuals.background and C_Texture.GetAtlasInfo(specVisuals.background) and specVisuals.background
	if self.specBackgroundAtlas then
		self.BackgroundFlash:SetAtlas(self.specBackgroundAtlas, specVisuals.useAtlasSize)
	end
	self:GetParent():SetPortraitToClassIcon(class)
end

function Frame:SetBackgroundAnimationsPlaying(playing)
	for _, animGroup in ipairs(self.backgroundAnims) do
		animGroup:SetPlaying(playing)
	end
end

-- Everything around the tree that depends on what's shown.
function Frame:RefreshChrome()
	local isTemplate = self.mode == "template"
	local nameBox = self.NameBox
	nameBox:SetShown(isTemplate)
	if isTemplate and not nameBox:HasFocus() then
		nameBox:SetText(self.template.name)
		nameBox:SetCursorPosition(0)
	end
	-- Someone else's build: their name, class-coloured, and not editable (it's not a template of yours).
	local inspected = self:IsShowingInspected()
	nameBox:SetEnabled(not inspected)
	local classColor = inspected and C_ClassColor.GetClassColor(self.template.class)
	if classColor then
		nameBox:SetTextColor(classColor:GetRGB())
	else
		nameBox:SetTextColor(unpack(nameBox.tmtTextColor))
	end
	self.ActiveSpec:SetShown(not isTemplate and GetNumSpecGroups() > 1)
	self.ActiveSpec:Refresh()
	self:UpdateTabs()
	self:UpdateConfigButtonsState()
	self:RefreshTreeHeaders()
	self:ApplyLayout()
	ns.Flyout.Close()
end

-- The spec tab names the group on show (on a template, your active one, which it goes back to), with Blizzard's
-- "active" mark when that's your active group.
function Frame:UpdateTabs()
	local tab = self.TabSystem:GetTabButton(self.specTabID)
	local group = self.mode == "player" and self.specGroup or ns.ActiveSpecGroup()
	local text = group == 2 and DUAL_SPEC_SECONDARY or DUAL_SPEC_PRIMARY
	if tab.tabText ~= text then
		tab.tabText = text
		tab:UpdateTabText()
		tab:UpdateTabWidth()
		self.TabSystem:MarkDirty()
	end
	tab:SetIsActive(group == ns.ActiveSpecGroup())
end

-- Tabs: the spec tab switches to the other spec group (with dual spec), or from a template back to your talents;
-- Actions and Templates open their menus and are never selected.
function Frame:SetTab(tabID)
	if tabID == self.actionsTabID or tabID == self.templatesTabID then
		ns.Menus.Open(self, tabID == self.templatesTabID and "templates" or "actions", self.TabSystem:GetTabButton(tabID))
		return true
	end
	self.NameBox:ClearFocus()
	if self.mode ~= "player" then
		self:ShowPlayerTalents()
	elseif GetNumSpecGroups() > 1 then
		self:ShowPlayerTalents(self.specGroup == 2 and 1 or 2)
	end
end

-- Editing ---------------------------------------------------------------------------------------------------------

-- Your active spec is edited as in Blizzard's panel and saved with Apply. A spec that isn't active, or a
-- read-only view, is locked as in Blizzard's panel, and so is your active spec whenever the game won't let talents
-- change (in combat, among others: C_ClassTalents.CanEditTalents, as Blizzard's ClassTalentsFrame:IsLocked, its reason
-- shown in the talents' tooltips; refreshed on PLAYER_REGEN_*). Someone else's build is locked too, keeping its
-- learned talents' colours and showing the rest as locked, as Blizzard's inspect view does. Templates stay editable in
-- combat: they're the addon's own data.
function Frame:IsLocked()
	if self.mode == "template" then return self:IsShowingInspected() end
	if self.viewOnly or not self:IsActiveTabSelected() then return true end
	local canEdit, errorMessage = C_ClassTalents.CanEditTalents()
	return not canEdit, errorMessage
end

-- Someone else's talents: shown like a template, read-only, never saved.
function Frame:IsShowingInspected()
	return self.mode == "template" and self.template.inspected == true
end

function Frame:PurchaseRank(nodeID)
	if self.mode ~= "template" then
		return TalentFrameBaseMixin.PurchaseRank(self, nodeID)
	end
	if self:IsShowingInspected() then return end
	if ns.Templates.AddRank(self.model, self.template, nodeID) then
		self:RefreshTemplate()
	end
end

function Frame:RefundRank(nodeID)
	if self.mode ~= "template" then
		return self:AttemptConfigOperation(C_Traits.RefundRank, nodeID, ClassTalentUtil.ShouldRefundClearEdges())
	end
	if self:IsShowingInspected() then return end
	if ns.Templates.RemoveRank(self.model, self.template, nodeID) then
		self:RefreshTemplate()
	end
end

function Frame:RefundAllRanks(nodeID)
	if self.mode ~= "template" then
		return TalentFrameBaseMixin.RefundAllRanks(self, nodeID)
	end
end

function Frame:SetSelection(nodeID, entryID)
	if self.mode ~= "template" then
		return self:AttemptConfigOperation(C_Traits.SetSelection, nodeID, entryID, ClassTalentUtil.ShouldRefundClearEdges())
	end
	if self:IsShowingInspected() then return end
	if ns.Templates.SetChoice(self.model, self.template, nodeID, entryID) then
		self:RefreshTemplate()
	end
end

function Frame:ResetTemplateTree(treeIndex)
	if self.mode ~= "template" or self:IsShowingInspected() then return end
	ns.Templates.ResetTree(self.model, self.template, treeIndex)
	PlaySound(SOUNDKIT.UI_CLASS_TALENT_NODE_REFUND)
	self:RefreshTemplate()
end

function Frame:AttemptConfigOperation(...)
	local result = TalentFrameBaseMixin.AttemptConfigOperation(self, ...)
	self:UpdateConfigButtonsState()
	return result
end

-- On a template, a point can be spent while the template is under the level cap's total.
function Frame:CanAfford(costs)
	if self.mode == "template" then
		return (self.templatePointsLeft or 0) > 0
	end
	return TalentFrameBaseMixin.CanAfford(self, costs)
end

function Frame:AddCostToTooltip(tooltip, costs)
	if self.mode ~= "template" then
		TalentFrameBaseMixin.AddCostToTooltip(self, tooltip, costs)
	end
end

-- The view config (-3) is shared with the game's talent links: opening one loads its build there, over what
-- we loaded. What's cached was read from ours and stays right; before anything else is read from it, what's shown is
-- loaded again if the view config no longer holds it (Tree.viewHolds). A load the game refuses isn't tried again for a
-- moment, so a redraw doesn't try once per talent.
function Frame:EnsureView()
	local wanted = (self.mode == "template" and self.template) or (self.viewOnly and "empty:" .. ns.PLAYER_CLASS) or nil
	if not wanted or ns.Tree.viewHolds == wanted then return end
	if self.viewRetryAt and GetTime() < self.viewRetryAt then return end
	local loaded
	if wanted == self.template then
		loaded = ns.Templates.LoadIntoView(self.model, self.template)
	else
		loaded = ns.Tree.InitializeView(ns.PLAYER_CLASS) ~= nil
	end
	self.viewRetryAt = not loaded and GetTime() + VIEW_RETRY_SECONDS or nil
end

function Frame:GetAndCacheEntryInfo(entryID)
	if not self.entryInfoCache[entryID] then self:EnsureView() end
	return TalentFrameBaseMixin.GetAndCacheEntryInfo(self, entryID)
end

-- The shown template's points added up once for a whole redraw (Templates.Tally), instead of once per talent
-- and rule. Every change to its ranks redraws through ClearInfoCaches (RefreshTemplate), which drops it.
function Frame:GetTally()
	local ranks = self.template.ranks
	if not self.tally or self.tally.ranks ~= ranks then
		self.tally = ns.Templates.Tally(self.model, ranks)
	end
	return self.tally
end

function Frame:ClearInfoCaches()
	self.tally = nil
	TalentFrameBaseMixin.ClearInfoCaches(self)
end

function Frame:GetAndCacheNodeInfo(nodeID)
	if not self.nodeInfoCache[nodeID] then self:EnsureView() end
	local info = TalentFrameBaseMixin.GetAndCacheNodeInfo(self, nodeID)
	if info and self.mode == "template" and not info.tmtPatched then
		ns.Templates.PatchNodeInfo(self.model, self.template, info, self:GetTally())
		info.tmtPatched = true
	end
	return info
end

function Frame:GetAndCacheCondInfo(condID, ...)
	if not self.condInfoCache[condID] then self:EnsureView() end
	local info = TalentFrameBaseMixin.GetAndCacheCondInfo(self, condID, ...)
	if info and self.mode == "template" and not info.tmtPatched then
		ns.Templates.PatchCondInfo(self.model, self.template, condID, info, self:GetTally())
		info.tmtPatched = true
	end
	return info
end

function Frame:ShouldInstantiateNode(nodeID, nodeInfo)
	if nodeInfo.type == Enum.TraitNodeType.SubTreeSelection then return false end
	return not (self.model and self.model.skipped[nodeID])
end

-- Currency and tree headers ----------------------------------------------------------------------------------------

function Frame:UpdateTreeCurrencyInfo(skipButtonUpdates)
	if self.mode == "template" then
		local spent, perTree = ns.Templates.Points(self.model, self.template.ranks)
		-- Someone else's build shows their own unspent points; a template, what the level cap leaves.
		local inspectedUnspent = self:IsShowingInspected() and self.template.unspent
		self.templatePointsLeft = inspectedUnspent or (self.model.cap - spent)
		self.templateSpent = spent
		self.templateSpentPerTree = perTree
		self.treeCurrencyInfo = {}
		self.treeCurrencyInfoMap = {}
		if not skipButtonUpdates then
			self:UpdateAllButtons()
		end
	else
		TalentFrameBaseMixin.UpdateTreeCurrencyInfo(self, skipButtonUpdates)
	end
	self:RefreshCurrencyDisplay()
	self:RefreshTreeHeaders()
	if not skipButtonUpdates then
		self:RefreshConditionsCache()
	end
end

-- With "Level required on templates", a template (not someone else's build) shows the level its points need
-- instead of the points left: a point a level from the first talent level, the levels before it read from the level
-- cap and the points it gives (the model's cap). An empty template needs no level: a grey 0, jumping to the first
-- talent level with its first point. In the game's green for that number (ClassTalentCurrencyDisplayMixin:SetAmount);
-- grey at the level cap too, as Blizzard's 0 points left is (the template has spent every point).
function Frame:IsShowingTemplateLevel()
	return self.mode == "template" and ns.settings.templateLevel and not self:IsShowingInspected()
end

function Frame:RefreshCurrencyDisplay()
	local display = self.ClassCurrencyDisplay
	local showLevel = self:IsShowingTemplateLevel()
	local labelText = showLevel and L.LEVEL_REQUIRED_LABEL or UNSPENT_POINTS
	if display.UnspentLabel:GetText() ~= labelText then
		display.UnspentLabel:SetText(labelText)
	end
	if showLevel then
		local spent = self.templateSpent or 0
		local level = spent > 0 and (ns.MaxLevel() - self.model.cap + spent) or 0
		display:SetAmount(level)
		local color = (spent == 0 or level >= ns.MaxLevel()) and GRAY_FONT_COLOR or GREEN_FONT_COLOR
		display.CurrentAmountContainer.CurrencyAmount:SetTextColor(color:GetRGBA())
		return
	end
	local amount
	if self.mode == "template" then
		amount = self.templatePointsLeft or 0
	else
		local currency = self.treeCurrencyInfo and self.treeCurrencyInfo[1]
		amount = currency and currency.quantity or 0
	end
	display:SetAmount(amount)
end

-- Blizzard's headers are pooled and rebuilt on every change (Camelot ClassTalentsFrame.lua:94-121); ours too, placed
-- by the layout. The reset buttons are our own frames, re-anchored after each rebuild.
function Frame:RefreshTreeHeaders()
	self.treeHeaderPool:ReleaseAll()
	self.resetButtonPool:ReleaseAll()
	wipe(self.treeHeaders)
	local model = self.model
	if not model then return end

	local spentByTree = {}
	if self.mode == "template" then
		spentByTree = self.templateSpentPerTree or select(2, ns.Templates.Points(model, self.template.ranks))
	elseif self:GetConfigID() then
		local groupIDs = {}
		for index, tree in ipairs(model.trees) do
			groupIDs[index] = tree.groupID
		end
		for _, groupInfo in ipairs(C_Traits.GetGroupCurrencyInfo(self:GetConfigID(), groupIDs) or {}) do
			local currency = groupInfo.currencyInfos and groupInfo.currencyInfos[1]
			for index, tree in ipairs(model.trees) do
				if tree.groupID == groupInfo.traitNodeGroupID then
					spentByTree[index] = currency and currency.spent or 0
				end
			end
		end
	end

	for index, tree in ipairs(model.trees) do
		local spent = spentByTree[index] or 0
		local header = self.treeHeaderPool:Acquire()
		header:Setup({ displayName = tree.name, icon = tree.icon, groupID = tree.groupID }, { currencyInfos = { { spent = spent } } })
		header:SetPoint("CENTER", self.BackgroundBorder, "TOPLEFT", self:GetHeaderX(index), self:GetHeaderY())
		self:LayoutHeaderDivider(index, header)
		header:Show()
		self.treeHeaders[index] = header

		if self.mode == "template" and not self:IsShowingInspected() and spent > 0 then
			local reset = self.resetButtonPool:Acquire()
			reset.talentFrame = self
			reset.treeIndex = index
			reset.treeName = tree.name
			reset:SetPoint("LEFT", header.Name, "RIGHT", 6, 0)
			-- Above the talent buttons (ButtonsParent + about 500), which otherwise take its clicks where a top-row
			-- talent reaches up beside the tree's name.
			reset:SetFrameLevel(self.ButtonsParent:GetFrameLevel() + ns.ABOVE_TALENTS_LEVEL)
			reset:Show()
		end
	end
end

-- Blizzard's red reset art, toned down to sit with the bronze headers rather than draw the eye.
local RESET_DESATURATION = 0.65
local RESET_BRIGHTNESS = 0.85

function TooManyTalentsTreeResetButton_OnLoad(button)
	for _, texture in ipairs({ button:GetNormalTexture(), button:GetHighlightTexture() }) do
		texture:SetDesaturation(RESET_DESATURATION)
		texture:SetVertexColor(RESET_BRIGHTNESS, RESET_BRIGHTNESS, RESET_BRIGHTNESS)
	end
end

function TooManyTalentsTreeResetButton_OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, L.RESET_TREE:format(button.treeName))
	GameTooltip:Show()
end

function TooManyTalentsTreeResetButton_OnClick(button)
	GameTooltip_Hide()
	button.talentFrame:ResetTemplateTree(button.treeIndex)
end

function Frame:GetTraitTreeName(_, groupIDs)
	if self.model and groupIDs then
		for _, tree in ipairs(self.model.trees) do
			for _, groupID in ipairs(groupIDs) do
				if tree.groupID == groupID then return tree.name end
			end
		end
	end
	return ""
end

-- Applying your own changes (the Apply button) ----------------------------------------------------------------------

function Frame:HasAnyConfigChanges()
	if self.mode ~= "player" or self.viewOnly or self:IsCommitInProgress() or not self:HasValidConfig() then return false end
	return C_Traits.ConfigHasStagedChanges(self:GetConfigID())
end

-- Whether there are changes, whether they can be applied, and why not.
function Frame:GetConfigApplicationState()
	local changes = self:HasAnyConfigChanges()
	if not changes then return false, false end
	local canChange, canAdd, changeError = self:CanChangeTalents()
	return true, canChange or canAdd, not canChange and changeError or nil
end

function Frame:ApplyConfig()
	if self:HasAnyConfigChanges() then
		self:CommitConfig()
	end
end

function Frame:RollbackConfig(...)
	TalentFrameBaseMixin.RollbackConfig(self, ...)
	self:UpdateTreeCurrencyInfo()
	self:UpdateConfigButtonsState()
end

-- Apply and Undo, on your own talents: in the bottom bar, or in the tree area's bottom-right corner without it (Layout).
-- Blizzard's green glow is its shared GlowEmitterFactory, so ours keeps to the button's own yellow glow.
function Frame:UpdateConfigButtonsState()
	local shown = self.mode == "player" and not self.viewOnly
	local pending, canApply, applyError = self:GetConfigApplicationState()
	self.ApplyButton:SetShown(shown)
	self.ApplyButton:SetEnabled(canApply)
	self.ApplyButton:SetDisabledTooltip(applyError)
	self.ApplyButton.YellowGlow:SetShown(pending)
	self.UndoButton:SetShown(shown and pending)

	-- Blizzard's UpdatePendingChangeState: the talents' "not on your action bars" state is worked out again when
	-- changes start or stop being staged (HasAnyPendingChanges).
	local wasPending = self.tmtPending
	self.tmtPending = pending == true
	if self.tmtPending ~= (wasPending == true) then
		for button in self:EnumerateAllTalentButtons() do
			if button.UpdateActionBarStatus then button:UpdateActionBarStatus() end
		end
	end
end

-- As Blizzard's class panel (Blizzard_ClassTalentsFrame.lua:388-425, which overrides the base mixin's): every update
-- to the shown config reloads it and ends a commit, not only while one is in progress.
function Frame:OnTraitConfigUpdated(configID)
	if self.mode ~= "player" or configID ~= self:GetConfigID() then return end
	self:SetConfigID(configID, true)
	self:SetCommitStarted(nil, TalentFrameBaseMixin.CommitUpdateReasons.CommitSucceeded)
	self:UpdateTreeCurrencyInfo(true)
end

-- Applying a template while showing your own talents plays the same commit visuals as Apply.
function Frame:OnApplyStarted()
	if self:IsShown() and self.mode == "player" and self:GetConfigID() == C_ClassTalents.GetActiveConfigID() then
		self:SetCommitStarted(self:GetConfigID(), TalentFrameBaseMixin.CommitUpdateReasons.CommitStarted)
	end
	ns.Flyout.Close()
end

function Frame:OnApplyFinished()
	if self:IsShown() then
		self:RefreshChrome()
	end
end

-- Spec switching (Camelot ClassTalentActiveSpecMixin calls these). No cast bar overlay: see the XML. Ended by
-- ACTIVE_COMBAT_CONFIG_CHANGED, a failed or interrupted cast (OnEvent), or closing the window.
function Frame:SetSpecSwitchCastBarActive(active)
	self.tmtSpecSwitching = active or nil
	self:SetCommitSpinnerShown(active)
end

-- What the button templates ask of the panel -------------------------------------------------------------------------

-- Whether to leave out the talents' "not on your action bars" hints: on a template, whose talents aren't learned, and
-- on your own while changes are staged (not learned yet), as Blizzard's panel means to. Forever's own panel passes an
-- undefined variable there (Blizzard_ClassTalentsFrame.lua:1342, build 70938), so its hints stay on while staging.
function Frame:HasAnyPendingChanges()
	return self.mode == "template" or self.tmtPending == true
end

function Frame:GetClassID()
	return CLASS_IDS[self:GetShownClass()]
end

function Frame:ApplySettings()
	self:UpdateConfigButtonsState()
	-- Before the layout, which measures the label beside the number.
	self:RefreshCurrencyDisplay()
	ns.TalentedStyle.Apply(self)
	self:ApplyLayout()
end
