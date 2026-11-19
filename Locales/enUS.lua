local _, ns = ...

-- Every line of text players see, in one place for reviewing and translating. Code uses the names on the left
-- (L.TAB_TEMPLATES); a name with no text here shows as itself, with an error, so a typo is easy to spot.
--
-- This is British English. It's registered as enUS because the game has no English locale but enUS (British
-- clients report enUS too) and AceLocale treats enGB as enUS. A translation goes in a file of its own, loaded after
-- this one in the TOC, that starts:
--   local L = LibStub("AceLocale-3.0"):NewLocale("TooManyTalents", "deDE")
--   if not L then return end
-- and sets the lines it translates; anything it leaves out stays in English.
--
-- Placeholders: %s is text (a name, another line), %d a whole number. Keep them, in the same order.
-- |4singular:plural; picks the word by the number before it.
--
-- Names of things in the addon players see or click (tabs, buttons, options, commands) go in braces, {like this}:
-- they're shown in a colour of their own.

local L = LibStub("AceLocale-3.0"):NewLocale("TooManyTalents", "enUS", true)

-- The window --------------------------------------------------------------------------------------------------------

-- The two tabs after the spec tab. Each opens a menu.
L["TAB_ACTIONS"] = "Actions"
L["TAB_TEMPLATES"] = "Templates"
-- The button beside each tree's name on a template, and its tooltip.
L["RESET_TREE"] = "Remove all points from %s"

-- The Templates menu ------------------------------------------------------------------------------------------------

L["MENU_NEW_TEMPLATE"] = "New template"

-- The Actions menu --------------------------------------------------------------------------------------------------

L["MENU_APPLY"] = "Apply"
L["MENU_COPY_CURRENT"] = "Copy to new template"
L["MENU_DUPLICATE"] = "Duplicate"
L["MENU_DELETE"] = "Delete"
-- On a template of your class: show it on your own talents as the build you're working towards.
L["MENU_SET_TARGET"] = "Set as target"
L["MENU_CLEAR_TARGET"] = "Clear target"
-- On your own talents, with a target set. %s is the target template's name.
L["MENU_CLEAR_TARGET_NAMED"] = "Clear target (%s)"
L["MENU_IMPORT"] = "Import"
L["MENU_EXPORT"] = "Export"
L["MENU_OPTIONS"] = "Options"

-- Why Apply is greyed out on a template, in its tooltip.
L["APPLY_NEEDS_POINTS"] = "Needs %d talent |4point:points;, you have %d."
L["APPLY_WOULD_REMOVE"] = "Has fewer points than you in %d |4talent:talents;. Applying can't remove talents."
L["APPLY_UNSAVED"] = "Apply or undo your unsaved talent changes first."
L["APPLY_NOTHING"] = "You already have every talent in this template."
L["APPLY_CANT_CHANGE"] = "You can't change talents right now."
L["APPLY_BUSY"] = "Learning talents..."

-- Applying a template.
L["APPLY_CONFIRM"] = "Learn %d talent |4point:points; from \"%s\"?"
L["APPLY_FAILED_STAGE"] = "Couldn't learn %d of the talent |4point:points; (points, requirements or tiers). Nothing was changed."
L["APPLY_REJECTED"] = "The talent change was refused. Nothing was changed."
L["APPLY_INTERRUPTED"] = "Learning talents failed or was interrupted. Nothing was changed."
L["APPLY_SLOW"] = "Learning talents is taking longer than expected. Check your talents."

-- Naming, copying and deleting templates.
L["DEFAULT_NEW_NAME"] = "New template"
L["DEFAULT_COPY_NAME"] = "%s (copy)"
L["DEFAULT_CURRENT_NAME"] = "My talents"
L["LINKED_BUILD_NAME"] = "%s talents"
L["LINK_FAILED"] = "That talent link can't be shown."
L["DELETE_CONFIRM"] = "Delete the template \"%s\"?"
L["NAME_TAKEN"] = "There's already a template called \"%s\"."
L["NAME_BOX_HINT"] = "Template name"

-- Sharing templates (Actions > Import and Export). %s in EXPORT_TEXT is the template's name; in IMPORT_DOESNT_FIT the
-- template's name, then the class.
L["EXPORT_TEXT"] = "Press Ctrl+C to copy \"%s\"."
L["IMPORT_TEXT"] = "Paste a template:"
L["IMPORT_INVALID"] = "That isn't a talent template."
L["IMPORT_DOESNT_FIT"] = "\"%s\" doesn't fit the %s talent tree as it is now."

-- A template saved before the game changed its talent tree, when it's opened: those talents are removed.
L["ORPHANS_FOUND"] = "\"%s\" had %d |4talent:talents; no longer in the game. They've been removed and the points given back."
-- Opening a template of a class whose talent tree hasn't loaded yet. %s is the class.
L["NO_TREE_DATA"] = "The talent tree for %s isn't available yet. Try again in a moment."

-- Options -----------------------------------------------------------------------------------------------------------

L["OPTIONS_TITLE"] = "Options"
L["OPT_TREE_GAP"] = "Space between trees"
L["OPT_TALENT_SPACING"] = "Space between talents"
L["OPT_OLD_ICONS"] = "Old icons"
L["OPT_OLD_POINTS"] = "Old points"
L["OPT_OLD_ARROWS"] = "Old arrows"
L["OPT_HIDE_BOTTOM_BAR"] = "Remove the bottom bar"
L["OPT_HIDE_SEARCH"] = "Remove the search box"
L["OPT_POINTS_IN_TAB_ROW"] = "Unspent points in the tab row"
L["OPT_TEMPLATE_LEVEL"] = "Level required on templates"

-- With that option, the label beside the number on a template, in place of the game's "Unspent Talents".
L["LEVEL_REQUIRED_LABEL"] = "Level Required"

-- If the talent window fails to build (an error in it), once per session: the key opens the Blizzard's window instead.
L["WINDOW_FAILED"] = "TooManyTalents couldn't open its talent window, so Blizzard's is used until you reload."
-- Straight after it, when the cause is a game update changing the game's talent window code ours is built on. %s: the
-- names of what's missing, for a bug report.
L["WINDOW_FAILED_MISSING"] = "A game update changed the talent window it's built on. Missing: %s"

-- Slash command -----------------------------------------------------------------------------------------------------

L["USAGE"] = "{/tmt} opens the talent window, {/tmt options} for options."

ns.L = LibStub("AceLocale-3.0"):GetLocale("TooManyTalents")
