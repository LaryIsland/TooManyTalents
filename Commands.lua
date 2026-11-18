local _, ns = ...
local L = ns.L

-- /tmt toggles the window; /tmt options opens it with its options beside it.
SLASH_TOOMANYTALENTS1 = "/tmt"
SLASH_TOOMANYTALENTS2 = "/toomanytalents"
SlashCmdList.TOOMANYTALENTS = function(input)
	local command = strtrim(input or ""):lower()
	if command == "" then
		ns.Toggle()
	elseif command == "options" then
		local frame = ns.GetFrame()
		if not frame then return end
		frame:GetParent():Show()
		ns.Options.Show(frame)
	else
		ns.Print(L.USAGE)
	end
end
