local _, ns = ...

-- What our window relies on in Blizzard's talent UI code, checked when the window is built, so a game patch
-- that renames or removes any of it is caught at once instead of breaking something quietly (an override of ours that
-- Blizzard no longer calls, a field that's now nil). If anything is missing the window isn't used: Blizzard's own
-- opens instead, as for any failed build (Core.lua Build), and chat names what's missing.
--
-- Written against 1.60.1 build 70938 (Blizzard_SharedTalentUI, Blizzard_PlayerSpells and Forever's Camelot overrides).

local Contract = {}
ns.Contract = Contract

Contract.LIST = {
	-- Methods Blizzard's code calls on our panel, which we override (UI/Frame.lua, UI/BlizzardCopy.lua, UI/Layout.lua):
	-- each must still be a method of the Blizzard mixin it overrides, or ours would no longer be called.
	overrides = {
		TalentFrameBaseMixin = {
			"AddCostToTooltip", "AnchorGate", "AttemptConfigOperation", "CanAfford", "ClearInfoCaches",
			"CommitConfigInternal", "GetAndCacheCondInfo", "GetAndCacheEntryInfo", "GetAndCacheNodeInfo",
			"GetConfigCommitErrorString", "GetFrameLevelForButton", "GetTraitTreeName", "IsLocked",
			"LoadTalentTreeInternal", "OnEvent", "OnGateDisplayed", "OnHide", "OnLoad", "OnShow", "OnTraitConfigUpdated",
			"OnUpdate", "PurchaseRank", "RefreshGates", "RefundAllRanks", "RefundRank", "RollbackConfig",
			"SetCommitCompleteVisualsActive", "SetCommitStarted", "SetCommitVisualsActive", "SetConfigID", "SetSelection",
			"ShouldDisplayGate", "ShouldInstantiateNode", "UpdateTalentButtonPosition", "UpdateTreeCurrencyInfo",
		},
		-- The class panel's, called on the panel by the talent buttons and the commit controls.
		ClassTalentsFrameMixin = {
			"GetClassID", "GetConfigApplicationState", "HasAnyConfigChanges", "HasAnyPendingChanges", "HasValidConfig",
			"IsHeroSpecActive", "IsHighlightedStarterBuildEntry", "IsPreviewingSubTree", "UpdateConfigButtonsState",
		},
		ClassTalentSearchMixin = { "OnPreviewSearchResultClicked", "TransformPreviewResults" },
	},
	-- Blizzard's methods we call on our panel (from the mixins and templates it's built from).
	methods = {
		"AcquireEdge", "AddNamedTab", "CommitConfig", "EnumerateAllTalentButtons", "GetAndCacheDefinitionInfo",
		"GetAndCacheSubTreeInfo", "GetButtonSize", "GetConfigID", "GetPanOffset", "GetTalentButtonByNodeID",
		"GetTalentTreeID", "GetTreeNodes", "InitializeSearch", "InstantiateTalentButton", "IsCommitInProgress",
		"IsTreeDirty", "LoadTalentTree", "MarkTreeClean", "RefreshConditionsCache", "RegisterCallback",
		"ReleaseAllTalentButtons", "SetBasePanOffset", "SetCommitSpinnerShown", "SetDisabledOverlayShown", "SetPanOffset",
		"SetTabSystem", "SetTalentTreeID", "SetZoomLevel", "UpdateAllButtons", "UpdateAllGatePositions",
		"UpdateAllTalentButtonPositions", "UpdateEdgesForButton", "UpdateFullSearchResults", "UpdatePadding",
		"UpdateTreeInfo",
	},
	-- Blizzard's fields we read on our panel: set up by TalentFrameBaseMixin.OnLoad and the templates.
	fields = {
		"basePanOffsetX", "basePanOffsetY", "bottomPadding", "buttonsWithDirtyEdges", "condInfoCache",
		"definitionInfoCache", "dirtyCondIDSet", "dirtyDefinitionIDSet", "dirtyEntryIDSet", "dirtyNodeIDSet",
		"dirtySubTreeIDSet", "edgePool", "entryInfoCache", "nodeInfoCache", "subTreeInfoCache", "talentDisplayFramePool",
	},
	-- What we use of the children that Blizzard's templates make (paths from the panel).
	children = {
		"ButtonsParent", "DisabledOverlay", "BackgroundFlash", "ClassCurrencyDisplay.SetAmount",
		"ClassCurrencyDisplay.UnspentLabel", "ClassCurrencyDisplay.Border",
		"ClassCurrencyDisplay.CurrentAmountContainer.CurrencyAmount", "ActiveSpec.SetGlow", "ActiveSpec.Refresh",
		"TabSystem.tabs", "TabSystem.GetTabButton", "TabSystem.MarkDirty", "TabSystem.Layout",
		"TabSystem.SetTabVisuallySelected", "ApplyButton.SetOnClickHandler", "ApplyButton.SetDisabledTooltip",
		"ApplyButton.YellowGlow", "UndoButton.SetOnClickHandler", "SearchPreviewContainer",
	},
	-- What we use of a tab (the spec tab) and a tree header (made from Blizzard's template for the check).
	tab = { "UpdateTabText", "UpdateTabWidth", "SetIsActive", "Text" },
	header = { "Setup", "Name" },
	-- Methods of the talent buttons and lines between them we call or hook (UI/BlizzardCopy.lua, UI/TalentedStyle.lua,
	-- UI/Target.lua): each must be in at least one of Blizzard's button (or edge) mixins, wherever it moves among them.
	buttonMixins = { "TalentDisplayMixin", "TalentButtonBaseMixin", "TalentButtonSpendMixin", "TalentButtonSelectMixin",
		"ClassTalentButtonBaseMixin", "ClassTalentButtonSpendMixin", "ClassTalentButtonSelectMixin" },
	buttonMethods = {
		"GetDefinitionID", "GetEntryID", "GetEntrySubTreeID", "GetNodeID", "GetNodeInfo", "GetNodeSubTreeID",
		"GetVisualState", "IsRefundInvalid", "SetVisualState", "UpdateEntryContentInfo", "UpdateEntryInfo",
		"UpdateIconTexture", "UpdateNodeInfo", "UpdateSpendText",
	},
	edgeMixins = { "TalentEdgeBaseMixin", "TalentEdgeArrowMixin", "TalentEdgeStraightMixin", "ClassTalentEdgeArrowMixin" },
	edgeMethods = { "GetEdgeInfo", "GetEndButton", "GetStartButton", "MarkPositionDirty", "UpdatePosition" },
	-- Blizzard's tables and functions we use directly.
	globals = {
		"TalentFrameBaseMixin.CommitUpdateReasons.CommitStarted", "TalentFrameBaseMixin.CommitUpdateReasons.CommitSucceeded",
		"TalentFrameBaseMixin.CommitUpdateReasons.InstantCommit",
		"TalentFrameBaseMixin.VisualsUpdateReasons.CommitStoppedComplete",
		"TalentFrameBaseMixin.VisualsUpdateReasons.FrameHidden", "TalentFrameBaseMixin.Event.TalentButtonAcquired",
		"TalentButtonUtil.ApplyPosition", "TalentButtonUtil.BaseVisualState",
		"TalentButtonUtil.TranslateNodePositionsToAnchorPositions", "ClassTalentUtil.GetVisualsForClassID",
		"ClassTalentUtil.GetVisualsForSpecID", "ClassTalentUtil.ShouldRefundClearEdges", "TabSystemOwnerMixin.OnLoad",
		"TabSystemOwnerMixin.SetTab", "Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID",
		"Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID",
	},
}

local function Get(root, path)
	local value = root
	for key in path:gmatch("[^.]+") do
		if type(value) ~= "table" then return nil end
		value = value[key]
	end
	return value
end

local function InAny(mixinNames, method)
	for _, mixinName in ipairs(mixinNames) do
		local mixin = _G[mixinName]
		if type(mixin) == "table" and type(mixin[method]) == "function" then return true end
	end
	return false
end

-- What's missing of the parts that don't need our panel: Blizzard's mixins and tables. Checked before the panel uses
-- any of them. Returns a list of names, or nil.
function Contract.CheckBlizzard()
	local list, missing = Contract.LIST, {}
	for mixinName, methods in pairs(list.overrides) do
		local mixin = _G[mixinName]
		for _, method in ipairs(methods) do
			if type(mixin) ~= "table" or type(mixin[method]) ~= "function" then
				missing[#missing + 1] = mixinName .. "." .. method
			end
		end
	end
	for _, method in ipairs(list.buttonMethods) do
		if not InAny(list.buttonMixins, method) then missing[#missing + 1] = "talent button " .. method end
	end
	for _, method in ipairs(list.edgeMethods) do
		if not InAny(list.edgeMixins, method) then missing[#missing + 1] = "talent edge " .. method end
	end
	for _, path in ipairs(list.globals) do
		if Get(_G, path) == nil then missing[#missing + 1] = path end
	end
	table.sort(missing)
	return #missing > 0 and missing or nil
end

-- What's missing on our built panel (after Blizzard's OnLoad and our tabs). Returns a list of names, or nil.
function Contract.CheckPanel(panel)
	local list, missing = Contract.LIST, {}
	for _, method in ipairs(list.methods) do
		if type(panel[method]) ~= "function" then missing[#missing + 1] = method end
	end
	for _, field in ipairs(list.fields) do
		if panel[field] == nil then missing[#missing + 1] = field end
	end
	for _, path in ipairs(list.children) do
		if Get(panel, path) == nil then missing[#missing + 1] = path end
	end
	local tab = panel.TabSystem and panel.TabSystem.GetTabButton and panel.TabSystem:GetTabButton(panel.specTabID)
	for _, key in ipairs(list.tab) do
		if not tab or tab[key] == nil then missing[#missing + 1] = "tab " .. key end
	end
	local header = panel.treeHeaderPool and panel.treeHeaderPool:Acquire()
	for _, key in ipairs(list.header) do
		if not header or header[key] == nil then missing[#missing + 1] = "tree header " .. key end
	end
	if header then panel.treeHeaderPool:Release(header) end
	table.sort(missing)
	return #missing > 0 and missing or nil
end
