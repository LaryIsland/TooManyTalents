local _, ns = ...

-- Copies of Blizzard's talent panel code that our window needs: kept apart from our own logic in
-- UI/Frame.lua so that after a game patch each block can be compared with its source. All from the Forever UI source,
-- 1.60.1 build 70938 (branch forever of Gethe/wow-ui-source): Blizzard_SharedTalentUI/Blizzard_SharedTalentFrame.lua
-- (the base frame, "Shared") and Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua (the class panel,
-- "Class"; Camelot/ClassTalents/ for Forever's overrides). Each block says what it leaves out or changes; anything
-- that depends on our modes (template, inspected, view only) stays in UI/Frame.lua.

local Frame = TooManyTalentsFrameMixin

-- The update loop ------------------------------------------------------------------------------------------------

local function CheckSetSafe(set, id)
	return id and set[id] or false
end

-- Shared:202-278, without its EventRegistry trigger: that runs Blizzard's listeners, and from here they would run
-- tainted. Then our own redraws (search results, Apply and Undo, the Old icons and arrows).
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
			elseif self.definitionInfoCache[button:GetDefinitionID()]
					or CheckSetSafe(self.dirtySubTreeIDSet, button:GetEntrySubTreeID())
					or CheckSetSafe(self.dirtySubTreeIDSet, button:GetNodeSubTreeID()) then
				buttonsToUpdate[button] = button.UpdateEntryContentInfo
			end
		end
		local displaysToUpdate = {}
		for display in self.talentDisplayFramePool:EnumerateActive() do
			if self.dirtyEntryIDSet[display:GetEntryID()] then
				displaysToUpdate[display] = display.FullUpdate
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
		for display, update in pairs(displaysToUpdate) do
			update(display)
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

-- Shared:1472-1489, without the EventRegistry trigger (see OnUpdate), then our buttons' state and layout.
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

-- Gates and layering (Class:696-761) ------------------------------------------------------------------------------

-- One gate per tree currency: only the first tier condition of each tree draws its marker.
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

-- Lower rows draw over higher ones so shadows line up (Class:1-4, 730-749, without hero talents' sub-trees).
local FRAME_LEVEL_PER_ROW, TOTAL_FRAME_LEVEL_SPREAD, BASE_Y_OFFSET, BASE_ROW_HEIGHT = 10, 500, 1500, 600

function Frame:GetFrameLevelForButton(nodeInfo)
	return TOTAL_FRAME_LEVEL_SPREAD - Round(((nodeInfo.posY - BASE_Y_OFFSET) / BASE_ROW_HEIGHT) * FRAME_LEVEL_PER_ROW)
end

-- Applying (Class:1159-1186, 1252-1255, 1370-1389) ------------------------------------------------------------------

function Frame:HasValidConfig()
	return self:GetConfigID() ~= nil and self:GetTalentTreeID() ~= nil
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

-- Without loadouts (hidden on Forever): always the active config.
function Frame:CommitConfigInternal()
	return C_ClassTalents.CommitConfig(nil)
end

function Frame:GetConfigCommitErrorString()
	return TALENT_FRAME_CONFIG_OPERATION_TOO_FAST
end

-- Commit visuals (Class:1-8, 940-1114, without hero talents) -------------------------------------------------------

local NODE_PURCHASE_IN_PROGRESS_FX_1 = 166
local NODE_PURCHASE_COMPLETE_FX_1 = 150
local PURCHASE_FX_DELAY = 1.2

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

-- What the talent buttons ask of the panel (Class:1469-1500, 1636-1643) ----------------------------------------------

-- No starter builds or hero talents on Forever.
function Frame:IsHighlightedStarterBuildEntry()
	return false
end

function Frame:IsHeroSpecActive()
	return false
end

function Frame:IsPreviewingSubTree()
	return false
end

function Frame:GetDefinitionInfoForEntry(entryID)
	local definitionID = self:GetAndCacheEntryInfo(entryID).definitionID
	return definitionID and self:GetAndCacheDefinitionInfo(definitionID) or nil
end

function Frame:GetSubTreeInfoForEntry(entryID)
	local subTreeID = self:GetAndCacheEntryInfo(entryID).subTreeID
	return subTreeID and self:GetAndCacheSubTreeInfo(subTreeID) or nil
end

-- Search options (Forever's own: Camelot ClassTalentsFrame.lua:254-316, without the menu tag) -----------------------

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

-- Applies the search options to the results before they're shown: passives left out, or ranks after the names.
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

-- With ranks shown, the name searched for is the spell's own, without them.
function Frame:OnPreviewSearchResultClicked(resultInfo)
	if resultInfo and resultInfo.searchName then
		resultInfo = CopyTable(resultInfo)
		resultInfo.name = resultInfo.searchName
	end
	ClassTalentSearchMixin.OnPreviewSearchResultClicked(self, resultInfo)
end
