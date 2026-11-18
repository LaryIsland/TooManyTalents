local _, ns = ...

-- The shape of each class's talent tree, read once and kept for the session: which of the three trees each talent
-- is in, its tier (points needed earlier in that tree), its prerequisites and its position. Templates are checked
-- and applied against it, and the window lays talents out with it.
--
-- Every class, the player's included, is read from an empty view config: on the player's own config a tier
-- condition reports only the points still missing, not the full requirement.

local Tree = {}
ns.Tree = Tree

local EDGE_REQUIRED = Enum.TraitEdgeType.RequiredForAvailability
local EDGE_SUFFICIENT = Enum.TraitEdgeType.SufficientForAvailability

-- Talents are 600 units apart. A node further than this from every other on either axis is misplaced in the game's
-- data (Hunter's Improved Serpent Sting) and is left out, as Talented does (Talented/forever.lua:78-92).
local OUTLIER_DISTANCE = 1500
-- The level of the first talent point, used only if the game doesn't say how many points the level cap gives.
local FIRST_TALENT_LEVEL = 10

local models = {}

local function IsOutlier(node, nodes)
	local nearX, nearY
	for _, other in ipairs(nodes) do
		if other ~= node then
			local dx = math.abs(other.posX - node.posX)
			local dy = math.abs(other.posY - node.posY)
			nearX = nearX and math.min(nearX, dx) or dx
			nearY = nearY and math.min(nearY, dy) or dy
		end
	end
	return (nearX or 0) > OUTLIER_DISTANCE or (nearY or 0) > OUTLIER_DISTANCE
end

-- {currencyID = points} for the "spend N points" conditions in the list.
local function AddSpendConditions(configID, conditionIDs, result, gates)
	for _, condID in ipairs(conditionIDs or {}) do
		local cond = C_Traits.GetConditionInfo(configID, condID)
		local amount = cond and cond.spentAmountRequired or 0
		if amount > 0 and cond.traitCurrencyID then
			result[cond.traitCurrencyID] = math.max(result[cond.traitCurrencyID] or 0, amount)
			gates[condID] = { currencyID = cond.traitCurrencyID, required = amount }
		end
	end
	return result
end

-- What the view config (-3) holds as far as we know: "empty:<class>" after InitializeView, a template's
-- table after Templates.LoadIntoView, nil when unknown. The game's talent links load into it too (Blizzard's
-- ClassTalentImportExport.lua ViewLoadout), so Core.lua's post-hooks on the two C_ClassTalents calls clear it when
-- anything but us calls them (`loadingView` marks our own calls), and the window loads what it shows again before
-- reading the view config (Frame:EnsureView).
Tree.viewHolds = nil
Tree.loadingView = false

function Tree.OnViewLoadedElsewhere()
	if not Tree.loadingView then Tree.viewHolds = nil end
end

-- Loads an empty view of the class's tree into the view config. Returns the tree ID, or nil if the game refused.
function Tree.InitializeView(class)
	local specID = ns.SpecForClass(class)
	Tree.viewHolds = nil
	if not specID then return end
	Tree.loadingView = true
	local ok = pcall(C_ClassTalents.InitializeViewLoadout, specID, ns.MaxLevel())
	Tree.loadingView = false
	if not ok then return end
	Tree.viewHolds = "empty:" .. class
	return C_ClassTalents.GetTraitTreeForSpec(specID), specID
end

local function Build(class)
	local treeID, specID = Tree.InitializeView(class)
	if not treeID then return end
	local configID = ns.VIEW_CONFIG_ID

	local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
	if not groups or #groups == 0 then return end
	table.sort(groups, function(a, b) return a.orderIndex < b.orderIndex end)

	local model = { class = class, specID = specID, treeID = treeID, trees = {}, nodes = {}, gates = {} }
	local treeByGroup, groupIDs = {}, {}
	for index, group in ipairs(groups) do
		treeByGroup[group.groupID] = index
		groupIDs[index] = group.groupID
		model.trees[index] = { groupID = group.groupID, name = group.displayName, icon = group.icon, nodes = {} }
	end
	for _, groupInfo in ipairs(C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}) do
		local index = treeByGroup[groupInfo.traitNodeGroupID]
		local currency = groupInfo.currencyInfos and groupInfo.currencyInfos[1]
		if index and currency then
			model.trees[index].currencyID = currency.traitCurrencyID
		end
	end

	-- The nodes that belong to one of the three trees.
	-- inGame: every node in the game's tree, shown or not (a template's ranks are only dropped for nodes not in it).
	local found = {}
	model.inGame = {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		model.inGame[nodeID] = true
		local info = C_Traits.GetNodeInfo(configID, nodeID)
		if info and info.ID ~= 0 and info.isVisible ~= false and (info.maxRanks or 0) > 0 and info.entryIDs and info.entryIDs[1] then
			local tree
			for _, groupID in ipairs(info.groupIDs or {}) do
				tree = tree or treeByGroup[groupID]
			end
			if tree then
				found[#found + 1] = info
				info.tree = tree
			end
		end
	end
	if #found == 0 then return end

	-- The game only reports a tree's currency once points are spent in it, so when it's missing use the currency most
	-- of that tree's tier conditions refer to (Talented/forever.lua:226-245).
	local votes = {}
	for _, info in ipairs(found) do
		info.spend = AddSpendConditions(configID, info.conditionIDs, {}, model.gates)
		for _, entryID in ipairs(info.entryIDs) do
			local entry = C_Traits.GetEntryInfo(configID, entryID)
			AddSpendConditions(configID, entry and entry.conditionIDs, info.spend, model.gates)
		end
		votes[info.tree] = votes[info.tree] or {}
		for currencyID in pairs(info.spend) do
			votes[info.tree][currencyID] = (votes[info.tree][currencyID] or 0) + 1
		end
	end
	local currencyToTree = {}
	for index, tree in ipairs(model.trees) do
		if not tree.currencyID then
			local best
			for currencyID, count in pairs(votes[index] or {}) do
				if not best or count > votes[index][best] then best = currencyID end
			end
			tree.currencyID = best
		end
		if tree.currencyID then currencyToTree[tree.currencyID] = index end
	end
	for _, gate in pairs(model.gates) do
		gate.tree = currencyToTree[gate.currencyID]
	end

	-- The tree's own gates (the markers at a tier's first talent) are conditions too.
	local treeInfo = C_Traits.GetTreeInfo(configID, treeID)
	for _, gateInfo in ipairs(treeInfo and treeInfo.gates or {}) do
		local cond = C_Traits.GetConditionInfo(configID, gateInfo.conditionID)
		if cond and cond.traitCurrencyID and (cond.spentAmountRequired or 0) > 0 then
			model.gates[gateInfo.conditionID] = {
				currencyID = cond.traitCurrencyID, required = cond.spentAmountRequired, tree = currencyToTree[cond.traitCurrencyID],
			}
		end
	end

	model.skipped = {}
	for _, info in ipairs(found) do
		if IsOutlier(info, found) then
			model.skipped[info.ID] = true
		else
			local node = {
				id = info.ID,
				tree = info.tree,
				maxRanks = info.maxRanks,
				type = info.type,
				entryIDs = info.entryIDs,
				tier = info.spend[model.trees[info.tree].currencyID or false] or 0,
				posX = info.posX,
				posY = info.posY,
				required = {},
				sufficient = {},
				edges = info.visibleEdges or {},
			}
			model.nodes[node.id] = node
			table.insert(model.trees[info.tree].nodes, node.id)
		end
	end

	-- Edges live on the source node. Only the availability edges are prerequisites.
	for sourceID, source in pairs(model.nodes) do
		for _, edge in ipairs(source.edges) do
			local target = model.nodes[edge.targetNode]
			if target then
				if edge.type == EDGE_REQUIRED then
					table.insert(target.required, sourceID)
				elseif edge.type == EDGE_SUFFICIENT then
					table.insert(target.sufficient, sourceID)
				end
			end
		end
	end

	-- Purchase order: tier, then top to bottom, left to right.
	model.order = {}
	for nodeID in pairs(model.nodes) do
		model.order[#model.order + 1] = nodeID
	end
	table.sort(model.order, function(a, b)
		local na, nb = model.nodes[a], model.nodes[b]
		if na.tier ~= nb.tier then return na.tier < nb.tier end
		if na.posY ~= nb.posY then return na.posY < nb.posY end
		if na.posX ~= nb.posX then return na.posX < nb.posX end
		return a < b
	end)

	-- Each tree's extent, for the layout sliders.
	for _, tree in ipairs(model.trees) do
		for _, nodeID in ipairs(tree.nodes) do
			local node = model.nodes[nodeID]
			tree.left = math.min(tree.left or node.posX, node.posX)
			tree.right = math.max(tree.right or node.posX, node.posX)
			tree.top = math.min(tree.top or node.posY, node.posY)
			tree.bottom = math.max(tree.bottom or node.posY, node.posY)
		end
		model.top = math.min(model.top or tree.top or math.huge, tree.top or math.huge)
		model.bottom = math.max(model.bottom or tree.bottom or -math.huge, tree.bottom or -math.huge)
	end
	-- Every tree is as wide as the class's widest: a tree with an empty last column keeps it, as in Blizzard's window
	-- (the warlock's Destruction has talents in only three of its four columns), rather than the gap slider taking it.
	local widest = 0
	for _, tree in ipairs(model.trees) do
		if tree.left then widest = math.max(widest, tree.right - tree.left) end
	end
	for _, tree in ipairs(model.trees) do
		if tree.left then tree.right = tree.left + widest end
	end

	-- Points available at the level cap: what the empty view has to spend.
	local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
	local currency = currencies and currencies[1]
	model.cap = currency and (currency.quantity + (currency.spent or 0)) or 0
	-- If it reports none: a point a level from the first talent level (10 on Forever) to the cap.
	if model.cap <= 0 then
		model.cap = ns.MaxLevel() - FIRST_TALENT_LEVEL + 1
	end
	return model
end

-- A class whose tree couldn't be read is left a moment before it's read again, rather than rebuilt (and the
-- view config reset) on every call while the game hasn't got it.
local RETRY_SECONDS = 2
local failedAt = {}

-- The class's model, or nil if the game hasn't got its tree yet (try again later).
function Tree.Get(class)
	local model = models[class]
	if model == nil then
		local failed = failedAt[class]
		if failed and GetTime() - failed < RETRY_SECONDS then return nil end
		model = Build(class)
		models[class] = model
		failedAt[class] = not model and GetTime() or nil
	end
	return model
end
