local _, ns = ...
local L = ns.L

-- Applying a template to the player's talents (design document 5.8). Only ever adds: buys ranks on the active config
-- in tier order, repeating passes until nothing more can be bought, then commits. If anything can't be bought it rolls
-- back, so nothing changes (Talented/forever.lua:546-617, 676-730).

local Apply = {}
ns.Apply = Apply

-- Blizzard's own backup timer is 6 s (Camelot ClassTalentsFrame.xml); this one only catches a commit that never ends.
local COMMIT_TIMEOUT = 30

local committing, commitTimer

function Apply.IsBusy()
	return committing ~= nil
end

local function Unspent(configID, treeID)
	local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, true)
	local currency = currencies and currencies[1]
	return currency and currency.quantity or 0
end

-- Whether the template can be applied now. Returns the plan, or nil and why not and whether that's a real problem
-- (shown in red) rather than just "not now".
function Apply.Check(model, template)
	if template.class ~= ns.PLAYER_CLASS then return nil end
	if committing then return nil, L.APPLY_BUSY end
	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID then return nil, L.APPLY_CANT_CHANGE end

	-- Before comparing ranks: staged points count as yours, and would read as the template removing them.
	if C_Traits.ConfigHasStagedChanges(configID) then return nil, L.APPLY_UNSAVED end

	local wanted, order, count, fewer = {}, {}, 0, 0
	for _, nodeID in ipairs(model.order) do
		local info = C_Traits.GetNodeInfo(configID, nodeID)
		local current = info and info.ranksPurchased or 0
		local target = template.ranks[nodeID] or 0
		if ns.Templates.HasMoreThan(template, nodeID, info) then
			fewer = fewer + 1
		elseif target > current then
			wanted[nodeID] = target - current
			order[#order + 1] = nodeID
			count = count + target - current
		end
	end
	if fewer > 0 then return nil, L.APPLY_WOULD_REMOVE:format(fewer), true end
	if count == 0 then return nil, L.APPLY_NOTHING end

	local canChange, canAdd, changeError = C_ClassTalents.CanChangeTalents()
	if not (canChange or canAdd) then
		return nil, changeError and changeError ~= "" and changeError or L.APPLY_CANT_CHANGE
	end
	local unspent = Unspent(configID, model.treeID)
	if count > unspent then return nil, L.APPLY_NEEDS_POINTS:format(count, unspent) end

	return { configID = configID, wanted = wanted, order = order, count = count, template = template }
end

local function Finish(message)
	if commitTimer then
		commitTimer:Cancel()
		commitTimer = nil
	end
	committing = nil
	if message then ns.Print(message) end
	if ns.frame then ns.frame:OnApplyFinished() end
end

-- Buys one rank (or the choice) at a time, in passes, so prerequisites and tiers are met in order.
local function Run(plan)
	local configID = plan.configID
	local remaining = plan.count
	local choices = plan.template.choices
	-- Passes over the plan (one rank per talent each) until everything is bought. A pass that spends nothing ends it (a
	-- refused rank, or a choice the game accepted without its rank showing), so there are never more passes than points.
	for _ = 1, plan.count + 1 do
		local before = remaining
		for _, nodeID in ipairs(plan.order) do
			if plan.wanted[nodeID] > 0 then
				local info = C_Traits.GetNodeInfo(configID, nodeID)
				if info and info.type == Enum.TraitNodeType.Selection and (info.ranksPurchased or 0) == 0 then
					local choice = choices[nodeID] or (info.entryIDs and info.entryIDs[1])
					if choice and C_Traits.SetSelection(configID, nodeID, choice) then
						local now = C_Traits.GetNodeInfo(configID, nodeID)
						local gained = now and now.ranksPurchased or 0
						remaining = remaining - gained
						plan.wanted[nodeID] = plan.wanted[nodeID] - gained
					end
				elseif C_Traits.PurchaseRank(configID, nodeID) then
					plan.wanted[nodeID] = plan.wanted[nodeID] - 1
					remaining = remaining - 1
				end
			end
		end
		if remaining <= 0 or remaining >= before then break end
	end

	if remaining > 0 then
		C_Traits.RollbackConfig(configID)
		ns.Print(L.APPLY_FAILED_STAGE, remaining)
		return
	end

	committing = configID
	if ns.frame then ns.frame:OnApplyStarted() end
	if not C_ClassTalents.CommitConfig(nil) then
		C_Traits.RollbackConfig(configID)
		Finish(L.APPLY_REJECTED)
		return
	end
	commitTimer = C_Timer.NewTimer(COMMIT_TIMEOUT, function()
		commitTimer = nil
		Finish(L.APPLY_SLOW)
	end)
end

-- Checks again, then asks before learning anything.
function Apply.Start(model, template)
	local plan, reason = Apply.Check(model, template)
	if not plan then
		if reason then UIErrorsFrame:AddExternalErrorMessage(reason) end
		return
	end
	StaticPopup_ShowCustomGenericConfirmation({
		text = L.APPLY_CONFIRM,
		text_arg1 = plan.count,
		text_arg2 = template.name,
		acceptText = YES,
		cancelText = NO,
		callback = function()
			-- Things may have changed while the question was up.
			local fresh = Apply.Check(model, template)
			if fresh then Run(fresh) end
		end,
	})
end

ns.On("TRAIT_CONFIG_UPDATED", function(configID)
	if committing and configID == committing and not C_Traits.ConfigHasStagedChanges(configID) then
		Finish()
	end
end)

ns.On("CONFIG_COMMIT_FAILED", function(configID)
	if committing and configID == committing then
		if C_Traits.ConfigHasStagedChanges(configID) then
			C_Traits.RollbackConfig(configID)
		end
		Finish(L.APPLY_INTERRUPTED)
	end
end)
