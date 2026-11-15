local _, ns = ...
local L = ns.L

-- Our own copy of Forever's talent panel (design document 2): TalentFrameBaseMixin (Blizzard_SharedTalentUI) with
-- the class panel's behaviour copied from Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua and its
-- Camelot overrides. Nothing here touches Blizzard's own window.
--
-- It shows one of two things:
--  * "player": your own talents, for either spec group, through your real config. Your active spec is editable and
--    saved with Apply (5.5); the other spec group and a read-only view are locked.
--  * "template": a template, through the view config (-3), with each node's state patched from the template
--    (Templates.PatchNodeInfo). Clicks change the template, never your talents (5.6). Someone else's talents (5.14)
--    are shown the same way, read-only.

local VIEW_CONFIG_ID = ns.VIEW_CONFIG_ID
local NODE_PURCHASE_IN_PROGRESS_FX_1 = 166
local NODE_PURCHASE_COMPLETE_FX_1 = 150
local PURCHASE_FX_DELAY = 1.2
-- Talent buttons sit at ButtonsParent's level plus up to about 500 (GetFrameLevelForButton); the choice flyout is at 2000.
local RESET_BUTTON_LEVEL = 900

-- Events only the class panel needs, while shown (Blizzard_ClassTalentsFrame.lua ClassTalentsFrameEvents).
local SHOWN_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
local SHOWN_UNIT_EVENTS = { "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED" }

-- Node events that only matter for a real config. On a template we refresh ourselves.
local NODE_EVENTS = {
	TRAIT_NODE_CHANGED = true,
	TRAIT_NODE_CHANGED_PARTIAL = true,
	TRAIT_NODE_ENTRY_UPDATED = true,
	TRAIT_SUB_TREE_CHANGED = true,
	TRAIT_TREE_CURRENCY_INFO_UPDATED = true,
}

-- The game's class IDs, fixed (the keys of Blizzard's ClassVisuals, Camelot Blizzard_ClassTalentUtil.lua). Not read
-- with GetClassInfo(1 .. GetNumClasses()): on Forever that stopped short of the druid's 11 (15 Nov), so the druid got
-- no class visuals and the default pan offset, 60 px off Blizzard's, and its talents sat left of their headers.
local CLASS_IDS = {
	WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

-- The window -------------------------------------------------------------------------------------------------------

TooManyTalentsWindowMixin = {}
local Window = TooManyTalentsWindowMixin

-- Puts the window back where it was last placed (dragged or centred), by its top left corner, if it ever was. Called
-- by every layout, after the window's final size is set (UI/Layout.lua): an anchor set on load didn't survive until the
-- first layout in game (15 Nov, the window came back at its default place after every reload).
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

function Window:OnShow()
	PlaySound(SOUNDKIT.UI_CLASS_TALENT_OPEN_WINDOW)
end

function Window:OnHide()
	PlaySound(SOUNDKIT.UI_CLASS_TALENT_CLOSE_WINDOW)
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

-- Shift-right-click anywhere on the window that isn't a control centres it on the screen at its current size (user's
-- request, design document 5.11). The talent area's own frames take the mouse, so they pass it on (Frame:OnLoad).
function Window:OnMouseUp(button)
	if button ~= "RightButton" or not IsShiftKeyDown() then return end
	local screenWidth, screenHeight = UIParent:GetSize()
	PlaceWindow(self, Round((screenWidth - self:GetWidth()) / 2), Round((screenHeight + self:GetHeight()) / 2))
end

-- The talent panel ------------------------------------------------------------------------------------------------

TooManyTalentsFrameMixin = CreateFromMixins(TalentFrameBaseMixin, ClassTalentSearchMixin)
local Frame = TooManyTalentsFrameMixin

function Frame:OnLoad()
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

	self:RegisterEvent("PLAYER_TALENT_UPDATE")
	self:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
	-- Reached only if nothing above errored: ns.CanOpen (Core.lua) checks it before Blizzard's window is touched.
	self.tmtLoaded = true
end

function Frame:OnShow()
	-- The window always opens on your own talents (5.5).
	self:ShowPlayerTalents()

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
	self.NameBox:ClearFocus()
	ns.Options.Hide()
	ns.Menus.Refresh()
end

function Frame:OnEvent(event, ...)
	if self.mode == "template" and NODE_EVENTS[event] then return end

	if event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
		self:SetCommitSpinnerShown(false)
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
	end

	TalentFrameBaseMixin.OnEvent(self, event, ...)

	-- A failed commit leaves the config as it was: show it again (Blizzard's ResetToLastConfigID).
	if event == "CONFIG_COMMIT_FAILED" and self:IsShown() and self.mode == "player" then
		self:ShowPlayerTalents(self.specGroup)
	end
end

-- TalentFrameBaseMixin's, without its EventRegistry triggers: those run Blizzard's listeners, and from here they
-- would run tainted.
function Frame:OnUpdate()
	self:SetScript("OnUpdate", nil)

	if self:IsTreeDirty() then
		self:LoadTalentTree()
	else
		local buttonsToUpdate = {}
		for button in self:EnumerateAllTalentButtons() do
			if self.dirtyNodeIDSet[button:GetNodeID()] then
				buttonsToUpdate[button] = button.UpdateNodeInfo
			elseif self.dirtyEntryIDSet[button:GetEntryID()] then
				buttonsToUpdate[button] = button.UpdateEntryInfo
			elseif self.definitionInfoCache[button:GetDefinitionID()] then
				buttonsToUpdate[button] = button.UpdateEntryContentInfo
			end
		end
		for condID in pairs(self.dirtyCondIDSet) do
			self.condInfoCache[condID] = nil
		end
		for subTreeID in pairs(self.dirtySubTreeIDSet) do
			self.subTreeInfoCache[subTreeID] = nil
		end
		for definitionID in pairs(self.dirtyDefinitionIDSet) do
			self.definitionInfoCache[definitionID] = nil
		end
		for entryID in pairs(self.dirtyEntryIDSet) do
			self.entryInfoCache[entryID] = nil
		end
		for nodeID in pairs(self.dirtyNodeIDSet) do
			self.nodeInfoCache[nodeID] = nil
		end
		self.dirtySubTreeIDSet = {}
		self.dirtyCondIDSet = {}
		self.dirtyDefinitionIDSet = {}
		self.dirtyEntryIDSet = {}
		self.dirtyNodeIDSet = {}

		if self.treeInfoDirty then
			self.treeInfoDirty = false
			self:UpdateTreeInfo()
		end
		for button, update in pairs(buttonsToUpdate) do
			update(button)
		end
		for button, isDirty in pairs(self.buttonsWithDirtyEdges) do
			if isDirty then
				self:UpdateEdgesForButton(button)
			end
		end
	end

	self:UpdateFullSearchResults()
	self:UpdateConfigButtonsState()
	ns.TalentedStyle.Refresh(self)
end

-- TalentFrameBaseMixin's, without the EventRegistry trigger (see OnUpdate).
function Frame:LoadTalentTreeInternal()
	self:ReleaseAllTalentButtons()
	self:ClearInfoCaches()
	self:SetZoomLevel(1)
	self:SetPanOffset(0, 0)
	for _, nodeID in ipairs(self:GetTreeNodes()) do
		self:InstantiateTalentButton(nodeID)
	end
	self:RefreshGates()
	self:MarkTreeClean()
	self:UpdateConfigButtonsState()
	self:ApplyLayout()
end

-- What's shown ------------------------------------------------------------------------------------------------------

function Frame:GetShownClass()
	return self.template and self.template.class or ns.PLAYER_CLASS
end

-- Whether your active spec group is on show (editable, unless read-only).
function Frame:IsActiveTabSelected()
	return self.mode == "player" and self.specGroup == ns.ActiveSpecGroup()
end

-- Your own talents for a spec group (the active one if nil).
function Frame:ShowPlayerTalents(specGroup)
	local activeGroup = ns.ActiveSpecGroup()
	specGroup = specGroup or activeGroup
	self.mode = "player"
	self.template = nil
	self.specGroup = specGroup
	self.model = ns.Tree.Get(ns.PLAYER_CLASS)
	self.viewOnly = false
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
end

function Frame:ShowTemplate(template)
	local model = ns.Tree.Get(template.class)
	if not model then
		ns.Print(L.NO_TREE_DATA, ns.ClassName(template.class))
		return
	end
	self.NameBox:ClearFocus()
	self.mode = "template"
	self.template = template
	self.model = model
	-- Talents no longer in the game (after a patch) are dropped, giving their points back, and it says so (design
	-- document 4).
	local orphans = ns.Templates.RemoveOrphans(model, template)
	if orphans > 0 then
		ns.Print(L.ORPHANS_FOUND, template.name, orphans)
	end
	ns.Templates.LoadIntoView(model, template)
	self.TabSystem:SetTabVisuallySelected(nil)
	self:UpdateClassVisuals()
	self:SetDisabledOverlayShown(false)
	self:SetConfigID(VIEW_CONFIG_ID, true)
	self:RefreshChrome()
end

-- Called after a template's ranks change: reload the view config and redraw every button in place, so the tooltip
-- under the mouse stays up while clicking.
function Frame:RefreshTemplate()
	if self.mode ~= "template" then return end
	ns.Templates.LoadIntoView(self.model, self.template)
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
	ns.Menus.Refresh()
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

-- Your active spec is edited as in Blizzard's panel and saved with Apply (5.5). A spec that isn't active, or a
-- read-only view, is locked as in Blizzard's panel, and so is your active spec whenever the game won't let talents
-- change (in combat, among others: C_ClassTalents.CanEditTalents, as Blizzard's ClassTalentsFrame:IsLocked, its reason
-- shown in the talents' tooltips; refreshed on PLAYER_REGEN_*). Someone else's build (5.14) is locked too, keeping its
-- learned talents' colours and showing the rest as locked, as Blizzard's inspect view does. Templates stay editable in
-- combat: they're the addon's own data.
function Frame:IsLocked()
	if self.mode == "template" then return self:IsShowingInspected() end
	if self.viewOnly or not self:IsActiveTabSelected() then return true end
	local canEdit, errorMessage = C_ClassTalents.CanEditTalents()
	return not canEdit, errorMessage
end

-- Someone else's talents (5.14): shown like a template, read-only, never saved.
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

function Frame:GetAndCacheNodeInfo(nodeID)
	local info = TalentFrameBaseMixin.GetAndCacheNodeInfo(self, nodeID)
	if info and self.mode == "template" and not info.tmtPatched then
		ns.Templates.PatchNodeInfo(self.model, self.template, info)
		info.tmtPatched = true
	end
	return info
end

function Frame:GetAndCacheCondInfo(condID, ...)
	local info = TalentFrameBaseMixin.GetAndCacheCondInfo(self, condID, ...)
	if info and self.mode == "template" and not info.tmtPatched then
		ns.Templates.PatchCondInfo(self.model, self.template, condID, info)
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
		-- Someone else's build shows their own unspent points (5.14); a template, what the level cap leaves.
		local inspectedUnspent = self:IsShowingInspected() and self.template.unspent
		self.templatePointsLeft = inspectedUnspent or (self.model.cap - spent)
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

function Frame:RefreshCurrencyDisplay()
	local amount
	if self.mode == "template" then
		amount = self.templatePointsLeft or 0
	else
		local currency = self.treeCurrencyInfo and self.treeCurrencyInfo[1]
		amount = currency and currency.quantity or 0
	end
	self.ClassCurrencyDisplay:SetAmount(amount)
end

-- Blizzard's headers are pooled and rebuilt on every change (Camelot ClassTalentsFrame.lua:94-121); ours too, placed
-- by the layout. The reset buttons are our own frames, re-anchored after each rebuild (design document 5.7).
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
			reset:SetFrameLevel(self.ButtonsParent:GetFrameLevel() + RESET_BUTTON_LEVEL)
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

-- Gates ------------------------------------------------------------------------------------------------------------

function Frame:RefreshGates()
	self.traitCurrencyIDToGate = {}
	TalentFrameBaseMixin.RefreshGates(self)
end

function Frame:ShouldDisplayGate(firstButton, condInfo)
	return TalentFrameBaseMixin.ShouldDisplayGate(self, firstButton, condInfo)
		and (not condInfo.traitCurrencyID or not self.traitCurrencyIDToGate[condInfo.traitCurrencyID])
end

function Frame:OnGateDisplayed(gate, _, condInfo)
	if condInfo.traitCurrencyID then
		self.traitCurrencyIDToGate[condInfo.traitCurrencyID] = gate
	end
end

function Frame:AnchorGate(gate, button)
	gate:SetPoint("RIGHT", button, "LEFT")
end

-- Layering: lower rows draw over higher ones so shadows line up (Blizzard_ClassTalentsFrame.lua:730-749).
function Frame:GetFrameLevelForButton(nodeInfo)
	return 500 - Round(((nodeInfo.posY - 1500) / 600) * 10)
end

-- Applying your own changes (the Apply button) ----------------------------------------------------------------------

function Frame:HasValidConfig()
	return self:GetConfigID() ~= nil and self:GetTalentTreeID() ~= nil
end

function Frame:HasAnyConfigChanges()
	if self.mode ~= "player" or self.viewOnly or self:IsCommitInProgress() or not self:HasValidConfig() then return false end
	return C_Traits.ConfigHasStagedChanges(self:GetConfigID())
end

function Frame:HasAnyRefundInvalidNodes()
	for button in self:EnumerateAllTalentButtons() do
		if button:IsRefundInvalid() then return true end
	end
	return false
end

function Frame:CanChangeTalents()
	if self:HasAnyRefundInvalidNodes() then
		return false, false, TALENT_FRAME_REFUND_INVALID_ERROR
	end
	if self:IsCommitInProgress() then
		return false, false
	end
	return C_ClassTalents.CanChangeTalents()
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

function Frame:CommitConfigInternal()
	return C_ClassTalents.CommitConfig(nil)
end

function Frame:RollbackConfig(...)
	TalentFrameBaseMixin.RollbackConfig(self, ...)
	self:UpdateTreeCurrencyInfo()
	self:UpdateConfigButtonsState()
end

function Frame:GetConfigCommitErrorString()
	return TALENT_FRAME_CONFIG_OPERATION_TOO_FAST
end

-- Apply and Undo, on your own talents: in the bottom bar, or in the tree area's bottom-left corner without it (Layout).
-- Blizzard's green glow is its shared GlowEmitterFactory, so ours keeps to the button's own yellow glow.
function Frame:UpdateConfigButtonsState()
	local shown = self.mode == "player" and not self.viewOnly
	local pending, canApply, applyError = self:GetConfigApplicationState()
	self.ApplyButton:SetShown(shown)
	self.ApplyButton:SetEnabled(canApply)
	self.ApplyButton:SetDisabledTooltip(applyError)
	self.ApplyButton.YellowGlow:SetShown(pending)
	self.UndoButton:SetShown(shown and pending)
end

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
	ns.Menus.Refresh()
end

function Frame:OnApplyFinished()
	if self:IsShown() then
		self:RefreshChrome()
	end
end

-- Commit visuals (Blizzard_ClassTalentsFrame.lua:940-1114, without hero talents) -----------------------------------

function Frame:SetCommitStarted(configID, reason, skipAnimation)
	if configID then
		local purchases, _, swaps = C_Traits.GetStagedChanges(self:GetConfigID())
		local gained = purchases or {}
		if swaps then tAppendAll(gained, swaps) end
		self.stagedPurchaseNodes = #gained > 0 and gained or nil
	end
	TalentFrameBaseMixin.SetCommitStarted(self, configID, reason, skipAnimation)
	local ongoing = configID and reason ~= TalentFrameBaseMixin.CommitUpdateReasons.InstantCommit
	if not ongoing and not self.commitCompleteVisualsActive then
		self.stagedPurchaseNodes = nil
	end
	self:UpdateConfigButtonsState()
end

function Frame:SetCommitVisualsActive(active, reason, skipSpinnerDelay)
	TalentFrameBaseMixin.SetCommitVisualsActive(self, active, reason, skipSpinnerDelay)
	if (active and not self:IsVisible()) or self.commitVisualsActive == active then return end
	if not active and reason == TalentFrameBaseMixin.VisualsUpdateReasons.FrameHidden then return end
	if active then
		self:PlayPurchaseEffectOnNodes(self.stagedPurchaseNodes, "PlayPurchaseInProgressEffect", { NODE_PURCHASE_IN_PROGRESS_FX_1 })
	else
		self.FxModelScene:ClearEffects()
		self:StopPurchaseEffectOnNodes(self.stagedPurchaseNodes, "StopPurchaseInProgressEffect")
	end
	self.commitVisualsActive = active and self.stagedPurchaseNodes ~= nil
end

function Frame:SetCommitCompleteVisualsActive(active)
	TalentFrameBaseMixin.SetCommitCompleteVisualsActive(self, active)
	if (active and not self:IsVisible()) or self.commitCompleteVisualsActive == active then return end
	self.commitCompleteVisualsActive = active
	for _, animGroup in ipairs(self.commitFlashAnims) do
		if animGroup:IsPlaying() ~= active then
			if active then animGroup:Restart() else animGroup:Stop() end
		end
	end
	if active then
		if self.stagedPurchaseNodes and not self.stagedPurchaseTimer then
			self.stagedPurchaseTimer = C_Timer.NewTimer(PURCHASE_FX_DELAY, function()
				self.stagedPurchaseTimer = nil
				self.commitCompleteVisualsActive = false
				if not self.stagedPurchaseNodes then return end
				self:PlayPurchaseEffectOnNodes(self.stagedPurchaseNodes, "PlayPurchaseCompleteEffect", { NODE_PURCHASE_COMPLETE_FX_1 })
				PlaySound(SOUNDKIT.UI_CLASS_TALENT_APPLY_COMPLETE)
				self.stagedPurchaseNodes = nil
			end)
		elseif not self.stagedPurchaseNodes then
			self.commitCompleteVisualsActive = false
		end
	else
		if self.stagedPurchaseTimer then
			self.stagedPurchaseTimer:Cancel()
			self.stagedPurchaseTimer = nil
		end
		self.FxModelScene:ClearEffects()
		self:StopPurchaseEffectOnNodes(self.stagedPurchaseNodes, "StopPurchaseCompleteEffect")
	end
end

function Frame:PlayPurchaseEffectOnNodes(nodes, method, fxIDs)
	if not nodes then return end
	local handled = {}
	for _, nodeID in ipairs(nodes) do
		if not handled[nodeID] then
			handled[nodeID] = true
			local button = self:GetTalentButtonByNodeID(nodeID)
			if button and button[method] then
				button[method](button, self.FxModelScene, fxIDs)
			end
		end
	end
end

function Frame:StopPurchaseEffectOnNodes(nodes, method)
	if nodes then
		for _, nodeID in ipairs(nodes) do
			local button = self:GetTalentButtonByNodeID(nodeID)
			if button and button[method] then button[method](button) end
		end
	else
		for button in self:EnumerateAllTalentButtons() do
			if button[method] then button[method](button) end
		end
	end
end

-- Spec switching (Camelot ClassTalentActiveSpecMixin calls these). No cast bar overlay: see the XML.
function Frame:SetSpecSwitchCastBarActive(active)
	self:SetCommitSpinnerShown(active)
end

-- What the button templates ask of the panel -------------------------------------------------------------------------

-- A template's talents aren't learned, so no "not on your action bars" hints for them.
function Frame:HasAnyPendingChanges()
	return self.mode == "template"
end

function Frame:IsHighlightedStarterBuildEntry()
	return false
end

function Frame:IsHeroSpecActive()
	return false
end

function Frame:IsPreviewingSubTree()
	return false
end

function Frame:GetClassID()
	return CLASS_IDS[self:GetShownClass()]
end

function Frame:GetDefinitionInfoForEntry(entryID)
	local definitionID = self:GetAndCacheEntryInfo(entryID).definitionID
	return definitionID and self:GetAndCacheDefinitionInfo(definitionID) or nil
end

function Frame:GetSubTreeInfoForEntry(entryID)
	local subTreeID = self:GetAndCacheEntryInfo(entryID).subTreeID
	return subTreeID and self:GetAndCacheSubTreeInfo(subTreeID) or nil
end

-- Search options (Camelot ClassTalentsFrame.lua:266-327).
function Frame:InitializeSearchOptionsDropdown()
	self.hidePassivesFromSearch = false
	self.showRanksInSearch = false
	self.SearchOptionsDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:CreateCheckbox(CLASS_TALENT_SEARCH_OPTION_HIDE_PASSIVES,
			function() return self.hidePassivesFromSearch end,
			function() self.hidePassivesFromSearch = not self.hidePassivesFromSearch end)
		rootDescription:CreateCheckbox(CLASS_TALENT_SEARCH_OPTION_SHOW_RANKS,
			function() return self.showRanksInSearch end,
			function() self.showRanksInSearch = not self.showRanksInSearch end)
	end)
end

function Frame:TransformPreviewResults(previewResults)
	if not self.hidePassivesFromSearch and not self.showRanksInSearch then
		return previewResults
	end
	local filtered = {}
	for _, resultInfo in ipairs(previewResults) do
		local definitionInfo = self:GetDefinitionInfoForEntry(resultInfo.resultID)
		local spellID = definitionInfo and definitionInfo.spellID
		if not (self.hidePassivesFromSearch and spellID and C_Spell.IsSpellPassive(spellID)) then
			if self.showRanksInSearch and resultInfo.nodeID then
				local nodeInfo = self:GetAndCacheNodeInfo(resultInfo.nodeID)
				if nodeInfo then
					resultInfo = CopyTable(resultInfo)
					resultInfo.searchName = resultInfo.name
					resultInfo.name = resultInfo.name .. " (" .. nodeInfo.ranksPurchased .. "/" .. nodeInfo.maxRanks .. ")"
				end
			end
			table.insert(filtered, resultInfo)
		end
	end
	return filtered
end

function Frame:OnPreviewSearchResultClicked(resultInfo)
	if resultInfo and resultInfo.searchName then
		resultInfo = CopyTable(resultInfo)
		resultInfo.name = resultInfo.searchName
	end
	ClassTalentSearchMixin.OnPreviewSearchResultClicked(self, resultInfo)
end

-- Options changed: redo the layout and the Talented style.
function Frame:ApplySettings()
	self:UpdateConfigButtonsState()
	ns.TalentedStyle.Apply(self)
	self:ApplyLayout()
end
