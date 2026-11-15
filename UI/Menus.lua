local _, ns = ...
local L = ns.L

-- The Actions and Templates tabs open these menus rather than switching page (design document 5.3).

local Menus = {}
ns.Menus = Menus

local openMenu

-- New templates and copies are made straight away under a default name (numbered if taken) and opened with the name
-- box empty and in focus for typing a name (its hint shows while empty). Left empty, the default name stays. Only if
-- the class's tree can be shown: otherwise nothing is made, and no name box (perhaps another template's) is touched.
local function OpenToName(frame, class, make)
	if not ns.Tree.Get(class) then
		ns.Print(L.NO_TREE_DATA, ns.ClassName(class))
		return
	end
	frame:ShowTemplate(make())
	local nameBox = frame.NameBox
	nameBox:SetText("")
	nameBox:SetFocus()
end

local function NewTemplate(frame, class)
	OpenToName(frame, class, function() return ns.Templates.Create(class, L.DEFAULT_NEW_NAME) end)
end

local function CopyCurrent(frame)
	local model = frame.model
	local configID = frame:GetConfigID()
	if not model or not configID then return end
	local ranks, choices = ns.Templates.ReadConfig(model, configID)
	OpenToName(frame, ns.PLAYER_CLASS, function()
		return ns.Templates.Create(ns.PLAYER_CLASS, L.DEFAULT_CURRENT_NAME, ranks, choices)
	end)
end

local function CopyInspected(frame, inspected)
	frame:ShowTemplate(ns.Templates.Create(inspected.class, inspected.name, CopyTable(inspected.ranks),
		CopyTable(inspected.choices)))
end

local function Duplicate(frame, template)
	OpenToName(frame, template.class, function()
		return ns.Templates.Duplicate(template, L.DEFAULT_COPY_NAME:format(template.name))
	end)
end

local function Delete(frame, template)
	StaticPopup_ShowCustomGenericConfirmation({
		text = L.DELETE_CONFIRM,
		text_arg1 = template.name,
		acceptText = DELETE,
		cancelText = CANCEL,
		callback = function()
			ns.Templates.Delete(template)
			if frame.template == template then
				frame:ShowPlayerTalents()
			end
		end,
	})
end

-- Import and Export (5.13), in Blizzard's own popup. The popup's edit box keeps the last dialog's letter limit unless
-- given one, so both set 0 (no limit): a template's line is longer than any name.
local SHARE_BOX_WIDTH = 350

-- The line is selected for Ctrl+C, and typing over it puts it back.
StaticPopupDialogs["TOOMANYTALENTS_EXPORT"] = {
	text = L.EXPORT_TEXT,
	button1 = CLOSE,
	hasEditBox = 1,
	maxLetters = 0,
	editBoxWidth = SHARE_BOX_WIDTH,
	OnShow = function(dialog, data)
		local editBox = dialog:GetEditBox()
		editBox:SetText(data.text)
		editBox:HighlightText()
	end,
	EditBoxOnTextChanged = function(editBox, data)
		if editBox:GetText() ~= data.text then
			editBox:SetText(data.text)
			editBox:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(editBox) editBox:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
}

-- On a bad line the popup stays up with the reason, so the paste can be fixed.
local function ImportPasted(dialog, data)
	local template, reason = ns.Share.Import(dialog:GetEditBox():GetText())
	if not template then
		UIErrorsFrame:AddExternalErrorMessage(reason)
		return true
	end
	data.frame:ShowTemplate(template)
end

StaticPopupDialogs["TOOMANYTALENTS_IMPORT"] = {
	text = L.IMPORT_TEXT,
	button1 = L.MENU_IMPORT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 0,
	editBoxWidth = SHARE_BOX_WIDTH,
	OnShow = function(dialog)
		dialog:GetEditBox():SetText("")
		dialog:GetButton1():Disable()
	end,
	OnAccept = ImportPasted,
	EditBoxOnEnterPressed = function(editBox, data)
		local dialog = editBox:GetParent()
		if dialog:GetButton1():IsEnabled() and not ImportPasted(dialog, data) then
			dialog:Hide()
		end
	end,
	EditBoxOnTextChanged = StaticPopup_StandardNonEmptyTextHandler,
	EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
}

local function Export(template)
	StaticPopup_Show("TOOMANYTALENTS_EXPORT", template.name, nil, { text = ns.Share.Export(template) })
end

local function Import(frame)
	StaticPopup_Show("TOOMANYTALENTS_IMPORT", nil, nil, { frame = frame })
end

-- Templates: a submenu per class, the player's first, each listing that class's templates (5.3). In our own flyout
-- (UI/Flyout.lua), so a class's submenu opens as soon as it's hovered.
local function TemplateEntries(frame)
	local entries = {}
	for _, class in ipairs(ns.ClassesInMenuOrder()) do
		entries[#entries + 1] = { text = ns.ClassColoredName(class), submenu = function()
			local list = {}
			for _, name in ipairs(ns.Templates.List(class)) do
				list[#list + 1] = {
					text = name,
					radio = true,
					checked = frame.template ~= nil and not frame.template.inspected and frame.template.class == class
						and frame.template.name == name,
					onClick = function()
						local template = ns.Templates.Get(class, name)
						if template then frame:ShowTemplate(template) end
					end,
				}
			end
			if #list > 0 then
				list[#list + 1] = { divider = true }
			end
			list[#list + 1] = { text = L.MENU_NEW_TEMPLATE, onClick = function() NewTemplate(frame, class) end }
			return list
		end }
	end
	return entries
end

-- A greyed entry's tooltip says why: red only for a real problem, a calm colour otherwise.
local function SetReasonTooltip(element, reason, isProblem)
	element:SetTooltip(function(tooltip)
		if isProblem then
			GameTooltip_AddErrorLine(tooltip, reason)
		else
			GameTooltip_AddColoredLine(tooltip, reason, LIGHTBLUE_FONT_COLOR)
		end
	end)
end

-- Actions: what can be done with whatever is open (5.3).
local function ActionsMenu(frame, root)
	local template = frame.template
	if template and template.inspected then
		-- Someone else's build (5.14): copied into a template of your own, named after them (numbered if taken).
		root:CreateButton(L.MENU_COPY_CURRENT, function() CopyInspected(frame, template) end)
	elseif template then
		if template.class == ns.PLAYER_CLASS then
			local plan, reason, isProblem = ns.Apply.Check(frame.model, template)
			local apply = root:CreateButton(L.MENU_APPLY, function() ns.Apply.Start(frame.model, template) end)
			apply:SetEnabled(plan ~= nil)
			if not plan and reason then
				SetReasonTooltip(apply, reason, isProblem)
			end
			-- The target for your active spec's talents (5.12).
			if ns.Target.IsTarget(template) then
				root:CreateButton(L.MENU_CLEAR_TARGET, function() ns.Target.Set(nil) end)
			else
				-- Then straight to your talents, where the target shows.
				root:CreateButton(L.MENU_SET_TARGET, function()
					ns.Target.Set(template)
					frame:ShowPlayerTalents()
				end)
			end
		end
		root:CreateButton(L.MENU_DUPLICATE, function() Duplicate(frame, template) end)
		root:CreateButton(L.MENU_DELETE, function() Delete(frame, template) end)
		-- No "Back to my talents": the spec tab does that (0.6.2, user's request).
	else
		if not frame.viewOnly and frame:GetConfigID() then
			root:CreateButton(L.MENU_COPY_CURRENT, function() CopyCurrent(frame) end)
		end
		local target = ns.Target.Get(frame.specGroup)
		if target then
			root:CreateButton(L.MENU_CLEAR_TARGET_NAMED:format(target.name), function() ns.Target.Set(nil, frame.specGroup) end)
		end
	end
	-- Sharing, between its own dividers (5.13): Export only with a template open.
	root:CreateDivider()
	root:CreateButton(L.MENU_IMPORT, function() Import(frame) end)
	if template then
		root:CreateButton(L.MENU_EXPORT, function() Export(template) end)
	end
	root:CreateDivider()
	root:CreateButton(L.MENU_OPTIONS, function() ns.Options.Toggle(frame) end)
end

function Menus.Open(frame, which, owner)
	if which == "templates" then
		Menus.Refresh()
		ns.Flyout.Open(owner, TemplateEntries(frame))
		return
	end
	ns.Flyout.Close()
	openMenu = MenuUtil.CreateContextMenu(owner, function(_, root)
		ActionsMenu(frame, root)
	end)
end

-- Closes an open menu after what it was about changes (a template opened, talents learned), so it's never stale.
function Menus.Refresh()
	if openMenu and openMenu:IsShown() then
		openMenu:Close()
	end
	openMenu = nil
	ns.Flyout.Close()
end
