local _, ns = ...

-- Where everything in the window goes: the two spacing sliders, and the bottom bar, search
-- box and tab row options. With the defaults it's Blizzard's layout exactly.
--
-- Talent positions are in the game's units: tenths of a pixel, talents 600 apart.

local Frame = TooManyTalentsFrameMixin

-- Blizzard's sizes for the window, the talent panel and its background (Camelot Blizzard_PlayerSpellsFrame.xml and
-- Blizzard_ClassTalentsFrame.xml), as UI/Frame.xml sets them: read from the frames when the panel loads, before any
-- layout changes them (Frame:ReadBlizzardSizes), so they're only written down in the XML.
local WINDOW_WIDTH, WINDOW_HEIGHT, FRAME_WIDTH, FRAME_HEIGHT, BACKGROUND_HEIGHT

function Frame:ReadBlizzardSizes()
	WINDOW_WIDTH, WINDOW_HEIGHT = self:GetParent():GetSize()
	FRAME_WIDTH, FRAME_HEIGHT = self:GetSize()
	BACKGROUND_HEIGHT = self.Background:GetHeight()
end

local TOP_STRIP = 70
-- The inner border (Talents-inner-frame-c60) reaches this far past the class art on the sides and at top and bottom;
-- the top ornaments hang this far below its top edge (Frame.xml, from Blizzard's anchors).
local BORDER_X, BORDER_Y, ORNAMENT_Y = 2, 4, -4
-- The top ornaments are cut this far in from the border's ends when the window is narrower.
local ORNAMENT_INSET = 8
-- Blizzard's places: the unspent points box from the border's top right, and the spec control (Active / Activate)
-- below the border's top.
local POINTS_X, POINTS_TOP, SPEC_Y = -20, -6, -20
-- The tabs' bottom edge from the border's top, the search box's, and the search options arrow beside it.
local TABS_Y, SEARCH_Y, ARROW_GAP, ARROW_Y = -4, 4, 3, -2
-- Apply from the background's bottom with the bottom bar, and from the art's bottom in the corner without it.
local APPLY_BAR_Y, APPLY_CORNER_Y = 8, 12
-- Without the bottom bar the art reaches the frame's bottom, so its border meets the window's.
local BOTTOM_STRIP, BOTTOM_STRIP_REMOVED = 36, 0
local BOTTOM_PADDING_REMOVED = 4
-- Without the bottom bar, this much of the empty art under the trees' last row goes too (it's about 45 below it).
local BOTTOM_TRIM = 28
local TREE_HEADER_OFFSET_X, TREE_HEADER_SPACING_X = 140, 400
local HEADER_DIVIDER_SPACE = 45
local DIVIDER_OFFSET_X, DIVIDER_OFFSET_Y = 95, -60
local TAB_WIDTH_MIN, TAB_WIDTH_MAX = 150, 200
-- When the trees are narrower than the tab row: tabs only as wide as their text (Blizzard's own minimum, the tab's
-- sides plus 20), the search box down to this, and room kept for a template's name box.
local TAB_WIDTH_TIGHT, SEARCH_WIDTH_MIN, NAME_BOX_MIN, NAME_BOX_MAX = 0, 100, 80, 200
-- Between the tab row's groups (tabs, name box or spec control, search box), and from the search options arrow to
-- the edge when the points aren't in the row.
local ROW_GAP, SEARCH_RIGHT = 24, 4
-- The tree headers: centred 100 px below the border's top, 48 px tall, so their top is 76 px down.
local HEADER_Y, HEADER_TOP = -100, 76
-- With the unspent points row removed, the headers stay at least this far below the border's top.
local HEADER_CLEARANCE = 6
-- The points at the tab row's right end: in from the border's right edge, and the space after the search options arrow.
local POINTS_RIGHT, POINTS_GAP = 16, 8
-- Where Blizzard's "Unspent Talents" text ends, into the box's art (x = 60), and in the tab row its space from the box.
local LABEL_OVERLAP, LABEL_SPACING = 60, 6
-- The box in Talents-Square-Box-c60 (125 wide): its right 53 (its left edge, 72 in); the rest is a fade for the text.
local POINTS_BOX_WIDTH = 53
-- The strip the tabs sit in, between the title bar (it covers the background's top 18) and the border (66 below the
-- background's top).
local TAB_STRIP_SHOWN = 48
-- The points' middle in the tab row, above the border's top: the box's bottom edge on the border's line. The box's
-- visible height (Talents-Square-Box-c60's frame, 36.5 of its 45); the strip is trimmed
-- to it, so its edges touch the title bar and the border alike.
local POINTS_Y, POINTS_BOX_HEIGHT = 13, 36
-- At the smallest space between trees, one empty column is left between them.
local MIN_TREE_GAP = 1200
local APPLY_WIDTH, APPLY_TEXT_PADDING = 164, 40
-- In the corner (no bottom bar): in from the art's right edge, and how many points the sliders take off together
-- before it reads just "Apply".
-- 13 in from the right as it's 12 up from the bottom, which looks even.
local APPLY_CORNER_X, APPLY_SHORT_AT = 13, 80
-- Between Apply and Undo: Blizzard's in the bottom bar, 5 closer in the corner.
local UNDO_GAP, UNDO_GAP_CORNER = 14, 9
local function AtlasSize(atlas)
	local info = C_Texture.GetAtlasInfo(atlas)
	return info and info.width or 0, info and info.height or 0
end

-- A space shrunk by the gap slider: down to its minimum at 0%, never grown.
local function Shrink(space, minimum, keep)
	minimum = math.min(space, minimum)
	return minimum + (space - minimum) * keep
end

-- Each tree's new left edge, and how much narrower and shorter the trees end up (in pixels). The gap slider shrinks
-- the gaps between trees (to one empty column) and the margins between the outer trees and the window's edges (to half
-- that, so an edge looks like half a gap). panX is the panel's pan offset: a talent at posX sits posX / 10 - panX
-- pixels from the panel's left edge.
local function Compute(model, gapPercent, spacingPercent, panX)
	local scale = spacingPercent / 100
	local keep = gapPercent / 100
	local layout = { scale = scale, trees = {}, shrinkX = 0, shrinkY = 0, dividerShift = {} }
	if not model or not model.top then return layout end

	local leftEdge, rightEdge = panX * 10, (FRAME_WIDTH + panX) * 10
	local first, previous, previousRight
	for index, tree in ipairs(model.trees) do
		if tree.left then
			local newLeft
			if not previous then
				first = tree
				newLeft = leftEdge + Shrink(tree.left - leftEdge, MIN_TREE_GAP * scale / 2, keep)
			else
				newLeft = previousRight + Shrink(tree.left - previous.right, MIN_TREE_GAP * scale, keep)
				-- The divider stays in the middle of the gap.
				local oldMiddle = (previous.right + tree.left) / 2
				local newMiddle = (previousRight + newLeft) / 2
				layout.dividerShift[#layout.dividerShift + 1] = (newMiddle - oldMiddle) / 10
			end
			layout.trees[index] = { left = tree.left, newLeft = newLeft, shift = (newLeft - tree.left) / 10 }
			previous = tree
			previousRight = newLeft + (tree.right - tree.left) * scale
		end
	end
	if first then
		local newRightEdge = previousRight + Shrink(rightEdge - previous.right, MIN_TREE_GAP * scale / 2, keep)
		layout.shrinkX = (rightEdge - newRightEdge) / 10
	end
	layout.top = model.top
	layout.shrinkY = (model.bottom - model.top) * (1 - scale) / 10
	return layout
end

-- Not called by the addon itself; kept for testing the sliders' maths.
ns.LayoutCompute = Compute

-- The same layout with every tree (and the dividers between them) moved right by extra pixels, and the window that
-- much wider on each side.
local function CentreTrees(layout, extra)
	for _, tree in pairs(layout.trees) do
		tree.newLeft = tree.newLeft + extra * 10
		tree.shift = tree.shift + extra
	end
	for index, shift in ipairs(layout.dividerShift) do
		layout.dividerShift[index] = shift + extra
	end
	layout.shrinkX = layout.shrinkX - 2 * extra
	return layout
end

-- A node's position after the sliders: scaled about its tree's left edge and the top row, then the tree moved.
function Frame:GetLayoutPosition(nodeInfo)
	local layout = self.layout
	local node = layout and self.model and self.model.nodes[nodeInfo.ID]
	local tree = node and layout.trees[node.tree]
	if not tree then
		return nodeInfo.posX, nodeInfo.posY
	end
	local x = tree.newLeft + (nodeInfo.posX - tree.left) * layout.scale
	local y = layout.top + (nodeInfo.posY - layout.top) * layout.scale
	return x, y
end

function Frame:UpdateTalentButtonPosition(button)
	local nodeInfo = button:GetNodeInfo()
	if button:GetParent() ~= self.ButtonsParent then
		button:SetParent(self.ButtonsParent)
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", self.ButtonsParent, "TOPLEFT")
	local x, y = self:GetLayoutPosition(nodeInfo)
	TalentButtonUtil.ApplyPosition(button, self, x, y)
end

function Frame:GetHeaderX(index)
	local tree = self.layout and self.layout.trees[index]
	return TREE_HEADER_OFFSET_X + (index - 1) * TREE_HEADER_SPACING_X + (tree and tree.shift or 0)
end

-- The line under a tree's header (355 wide; Blizzard's are 400 apart, so 45 apart at the ends) narrows as the gap
-- slider brings the trees closer, keeping that space, so neighbouring lines don't run into each other and the outer
-- ones stay inside the window.
function Frame:LayoutHeaderDivider(index, header)
	local divider = header.Divider
	if not divider then return end
	local width = AtlasSize("Talents-small-divider-c60")
	local x = self:GetHeaderX(index)
	for _, other in ipairs({ index - 1, index + 1 }) do
		if self.model and self.model.trees[other] then
			width = math.min(width, math.abs(self:GetHeaderX(other) - x) - HEADER_DIVIDER_SPACE)
		end
	end
	divider:SetWidth(width)
end

-- Shows the atlas by its file and coordinates, cropped to width x height (as fractions) from the middle or one side
-- horizontally and from the top. Always by file, cropped or not: after SetAtlas a crop lands on the wrong part, and
-- SetAtlas draws the top dividers wrong.
local function SetCroppedAtlas(texture, atlas, widthFraction, heightFraction, align)
	local info = C_Texture.GetAtlasInfo(atlas)
	if not info then return end
	local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local width = (right - left) * math.min(widthFraction, 1)
	if align == "LEFT" then
		right = left + width
	elseif align == "RIGHT" then
		left = right - width
	else
		left = left + ((right - left) - width) / 2
		right = left + width
	end
	bottom = top + (bottom - top) * math.min(heightFraction, 1)
	texture:SetTexture(info.file)
	texture:SetTexCoord(left, right, top, bottom)
end

-- The class art in one piece per tree, cut where Blizzard's dividers between trees are. Each piece moves with its tree
-- and loses what the gap slider takes out of the gaps beside it, so a tree keeps the art that was behind it. Cropped
-- from the bottom when the talent spacing slider makes the area shorter, and from the top by the removed points row
-- (so the art behind the trees moves up with them); never squashed. dividerX: Blizzard's divider centres, from the
-- border's left edge (the art starts BORDER_X in).
function Frame:LayoutClassArt(layout, frameWidth, dividerX, rowRemoved, bottomTrim)
	local pieces = self.tmtArtPieces
	if not pieces then
		pieces = {}
		for index = 1, 3 do
			pieces[index] = self:CreateTexture(nil, "BACKGROUND", nil, 1)
		end
		self.tmtArtPieces = pieces
		-- Still the anchor for the border, masks and animations; the pieces draw the art.
		self.ClassBackground:SetAlpha(0)
	end
	local info = self.specBackgroundAtlas and C_Texture.GetAtlasInfo(self.specBackgroundAtlas)
	if not info then
		for _, piece in ipairs(pieces) do piece:Hide() end
		return
	end

	-- Blizzard fills the area with the whole art (Forever's are 2046 x 1177, so it's squashed a little into 1212 x 595);
	-- the game looks like that, so it stays.
	local fullHeight = BACKGROUND_HEIGHT - TOP_STRIP - BOTTOM_STRIP
	local fromTop = rowRemoved / fullHeight
	local heightFraction = math.min(1, (fullHeight - layout.shrinkY - rowRemoved - (bottomTrim or 0)) / fullHeight)
	local left, right = info.leftTexCoord, info.rightTexCoord
	local artHeight = info.bottomTexCoord - info.topTexCoord
	local top = info.topTexCoord + artHeight * fromTop
	local bottom = top + artHeight * heightFraction
	local edges = { 0, dividerX[1] - BORDER_X + (layout.dividerShift[1] or 0), dividerX[2] - BORDER_X + (layout.dividerShift[2] or 0),
		frameWidth }
	local trimmed = heightFraction < 1 or frameWidth ~= FRAME_WIDTH
	for index, piece in ipairs(pieces) do
		local tree = layout.trees[index]
		local shift = tree and tree.shift or 0
		if shift ~= 0 then trimmed = true end
		local newLeft, newRight = edges[index], edges[index + 1]
		-- The part of Blizzard's art that was behind this stretch, kept within the art.
		local sourceLeft, sourceRight = newLeft - shift, newRight - shift
		if sourceLeft < 0 then
			sourceLeft, sourceRight = 0, sourceRight - sourceLeft
		end
		if sourceRight > FRAME_WIDTH then
			sourceLeft, sourceRight = math.max(0, sourceLeft - (sourceRight - FRAME_WIDTH)), FRAME_WIDTH
		end
		piece:SetTexture(info.file)
		piece:SetTexCoord(left + (right - left) * sourceLeft / FRAME_WIDTH, left + (right - left) * sourceRight / FRAME_WIDTH,
			top, bottom)
		piece:ClearAllPoints()
		piece:SetPoint("TOPLEFT", self.ClassBackground, "TOPLEFT", newLeft, 0)
		piece:SetPoint("BOTTOMRIGHT", self.ClassBackground, "BOTTOMLEFT", newRight, 0)
		piece:Show()
	end
	-- Blizzard's slow glow animations are single copies of the whole art; they'd no longer line up with the pieces.
	for _, overlay in ipairs({ self.OverlayBackgroundRight, self.OverlayBackgroundMid }) do
		overlay:SetShown(not trimmed)
		if not trimmed then overlay:SetAtlas(self.specBackgroundAtlas) end
	end
end

-- The frame's background (the strip behind the tabs, and the bottom bar) at its own scale, whatever the window's size:
-- the top piece shows the art from its top down, the bottom piece its bottom bar, and what's cut is the middle (the
-- class art covers it). A narrower window cuts it at the right. Squashing it to fit would move the tab strip's dark edge
-- up into a black line under the tabs. Background itself stays as the anchor for the rest. topTrim: rows taken
-- off the tab strip (the art starts that far down, so the strip's edge stays on the border).
function Frame:LayoutBackground(frameWidth, height, topTrim)
	local info = C_Texture.GetAtlasInfo("Talents-Background-c60")
	if not info then return end
	local pieces = self.tmtBackgroundPieces
	if not pieces then
		pieces = { self:CreateTexture(nil, "BACKGROUND", nil, 0), self:CreateTexture(nil, "BACKGROUND", nil, 0) }
		self.tmtBackgroundPieces = pieces
		self.Background:SetAlpha(0)
	end
	local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	right = left + (right - left) * math.min(1, frameWidth / FRAME_WIDTH)
	local perUnit = (bottom - top) / BACKGROUND_HEIGHT
	local bar = math.min(BOTTOM_STRIP, height)
	local upper, lower = pieces[1], pieces[2]
	upper:SetTexture(info.file)
	local from = top + perUnit * (topTrim or 0)
	upper:SetTexCoord(left, right, from, from + perUnit * (height - bar))
	upper:ClearAllPoints()
	upper:SetPoint("TOPLEFT", self.Background, "TOPLEFT")
	upper:SetPoint("BOTTOMRIGHT", self.Background, "BOTTOMRIGHT", 0, bar)
	lower:SetTexture(info.file)
	lower:SetTexCoord(left, right, bottom - perUnit * bar, bottom)
	lower:ClearAllPoints()
	lower:SetPoint("TOPLEFT", self.Background, "BOTTOMLEFT", 0, bar)
	lower:SetPoint("BOTTOMRIGHT", self.Background, "BOTTOMRIGHT")
end

local function SetTabWidths(tabSystem, minWidth, maxWidth)
	if tabSystem.minTabWidth == minWidth then return end
	tabSystem.minTabWidth, tabSystem.maxTabWidth = minWidth, maxWidth
	for _, tab in ipairs(tabSystem.tabs) do
		-- UpdateTabWidth measures the text's set width, which its last run set to the old tab width, so without this
		-- a tab can never get narrower.
		tab.Text:SetWidth(0)
		tab:UpdateTabWidth()
	end
	tabSystem:MarkDirty()
	tabSystem:Layout()
end

function Frame:ApplyLayout()
	local settings = ns.settings
	local layout = Compute(self.model, ns.saved.treeGap, ns.saved.talentSpacing, (self:GetPanOffset()))
	self.layout = layout
	local pointsInTabRow = settings.pointsInTabRow
	local barRemoved = settings.hideBottomBar
	local searchHidden = settings.hideSearch
	local border = self.BackgroundBorder
	local leftWidth, leftHeight = AtlasSize("Talents-divider-left-c60")
	local rightWidth = AtlasSize("Talents-divider-right-c60")

	-- The unspent points row (the strip above the tree headers: the top ornament, a glow over a line) goes with the
	-- option, ornament and all (its line only divided the row off), and everything under it moves up by its height.
	local rowRemoved = pointsInTabRow and Clamp(HEADER_TOP - HEADER_CLEARANCE, 0, leftHeight) or 0
	self.rowRemoved = rowRemoved

	-- The tab row: tabs on the left; the unspent points at the right end with the option; the search box before them.
	local tabSystem = self.TabSystem
	tabSystem:ClearAllPoints()
	tabSystem:SetPoint("BOTTOMLEFT", border, "TOPLEFT", TOP_STRIP, TABS_Y)
	-- With the points in the tab row they sit POINTS_Y above the border (the box's bottom edge on the border's line),
	-- and the strip loses its top until the box's top edge touches the title bar: it shows TAB_STRIP_SHOWN, the box is
	-- POINTS_BOX_HEIGHT tall, so it loses the difference (never so much that the tabs reach the title bar).
	local tabsTop = TABS_Y + tabSystem:GetHeight()
	local topTrim = pointsInTabRow and Clamp(TAB_STRIP_SHOWN - POINTS_BOX_HEIGHT, 0, TAB_STRIP_SHOWN - tabsTop) or 0

	local points = self.ClassCurrencyDisplay
	points:ClearAllPoints()
	if pointsInTabRow then
		points:SetPoint("RIGHT", border, "TOPRIGHT", -POINTS_RIGHT, POINTS_Y)
	else
		points:SetPoint("TOPRIGHT", border, "TOPRIGHT", POINTS_X, POINTS_TOP)
	end
	-- What's visible of the points in the tab row: the box (the art's right POINTS_BOX_WIDTH), and the "Unspent
	-- Talents" text LABEL_SPACING left of it while it's shown.
	local label = points.UnspentLabel
	local function PointsExtent(withLabel)
		return POINTS_BOX_WIDTH + (withLabel and (LABEL_SPACING + label:GetUnboundedStringWidth()) or 0)
	end

	local search, dropdown = self.SearchBox, self.SearchOptionsDropdown
	search:SetShown(not searchHidden)
	dropdown:SetShown(not searchHidden)
	if searchHidden then
		search:ClearFocus()
		self.SearchPreviewContainer:Hide()
	end

	-- The spec control (Active / Activate) moves up into the tab row with the option, where a template's name box goes.
	local spec = self.ActiveSpec
	spec:ClearAllPoints()
	if pointsInTabRow then
		spec:SetPoint("LEFT", tabSystem, "RIGHT", ROW_GAP, 0)
	else
		spec:SetPoint("TOP", border, "TOP", 0, SPEC_Y)
	end

	-- The talents decide the window's width; the tab row gives way. The row, left to right: the tabs (from TOP_STRIP);
	-- ROW_GAP and the middle (a template's name box, or the spec control with the option); ROW_GAP and the search box
	-- with its options arrow; the points (POINTS_GAP after the arrow, or ROW_GAP without the search box) and
	-- POINTS_RIGHT to the edge. Only what's shown takes room. When the trees want less room than the row, the
	-- "Unspent Talents" text goes first, then the name box narrows (to NAME_BOX_MIN), then the search box (to
	-- SEARCH_WIDTH_MIN), then the tabs (to their text). The window is only wider than the trees want if the row still
	-- doesn't fit; the trees are then centred in it.
	local treesWidth = FRAME_WIDTH - layout.shrinkX
	local nameShown = self.NameBox:IsShown()
	local specWidth = (pointsInTabRow and spec:IsShown()) and spec:GetWidth() or 0
	local middleMin = math.max(nameShown and NAME_BOX_MIN or 0, specWidth)
	self.tmtSearchWidth = self.tmtSearchWidth or search:GetWidth()
	local arrow = ARROW_GAP + dropdown:GetWidth()
	local tabMin, middle, searchBox = TAB_WIDTH_MIN, math.max(nameShown and NAME_BOX_MAX or 0, specWidth), self.tmtSearchWidth
	local withLabel = pointsInTabRow
	local function RowWidth()
		SetTabWidths(tabSystem, tabMin, TAB_WIDTH_MAX)
		local width = TOP_STRIP + tabSystem:GetWidth()
		if middle > 0 then width = width + ROW_GAP + middle end
		if not searchHidden then width = width + ROW_GAP + searchBox + arrow end
		if pointsInTabRow then
			return width + (searchHidden and ROW_GAP or POINTS_GAP) + PointsExtent(withLabel) + POINTS_RIGHT
		end
		return width + (searchHidden and ROW_GAP or SEARCH_RIGHT)
	end
	if RowWidth() > treesWidth and withLabel then
		withLabel = false
	end
	if RowWidth() > treesWidth and middle > middleMin then
		middle = math.max(middleMin, middle - (RowWidth() - treesWidth))
	end
	if RowWidth() > treesWidth and not searchHidden then
		searchBox = math.max(SEARCH_WIDTH_MIN, searchBox - (RowWidth() - treesWidth))
	end
	if RowWidth() > treesWidth then
		-- The tabs narrow only as far as needed (a tab is never narrower than its text): the widest minimum that fits.
		local low, high = TAB_WIDTH_TIGHT, TAB_WIDTH_MIN
		while high - low > 1 do
			tabMin = math.floor((low + high) / 2)
			if RowWidth() <= treesWidth then low = tabMin else high = tabMin end
		end
		tabMin = low
	end
	local rowWidth = RowWidth()

	-- The text sits LABEL_SPACING left of the box in the tab row (Blizzard's anchor elsewhere). Without it, the box
	-- loses the fade its art has on the left for the text.
	label:SetShown(not pointsInTabRow or withLabel)
	label:ClearAllPoints()
	if pointsInTabRow then
		label:SetPoint("RIGHT", points.Border, "RIGHT", -(POINTS_BOX_WIDTH + LABEL_SPACING), 0)
	else
		label:SetPoint("RIGHT", points.Border, "LEFT", LABEL_OVERLAP, 0)
	end
	local boxWidth = AtlasSize("Talents-Square-Box-c60")
	local shownWidth = (pointsInTabRow and not withLabel) and POINTS_BOX_WIDTH or boxWidth
	SetCroppedAtlas(points.Border, "Talents-Square-Box-c60", shownWidth / boxWidth, 1, "RIGHT")
	points.Border:SetWidth(shownWidth)

	if not searchHidden then search:SetWidth(searchBox) end
	local rightOfArrow = pointsInTabRow and (POINTS_RIGHT + PointsExtent(withLabel) + POINTS_GAP) or SEARCH_RIGHT
	search:ClearAllPoints()
	dropdown:ClearAllPoints()
	search:SetPoint("BOTTOMRIGHT", border, "TOPRIGHT", -(rightOfArrow + arrow), SEARCH_Y)
	dropdown:SetPoint("LEFT", search, "RIGHT", ARROW_GAP, ARROW_Y)
	self.NameBox:SetWidth(Clamp(middle, NAME_BOX_MIN, NAME_BOX_MAX))
	local frameWidth = math.max(treesWidth, rowWidth)
	if frameWidth > treesWidth then
		layout = CentreTrees(layout, (frameWidth - treesWidth) / 2)
		self.layout = layout
	end
	local shrinkX = FRAME_WIDTH - frameWidth

	local bottomStrip = barRemoved and BOTTOM_STRIP_REMOVED or BOTTOM_STRIP
	local bottomTrim = barRemoved and BOTTOM_TRIM or 0
	local shrinkY = layout.shrinkY + rowRemoved + (BOTTOM_STRIP - bottomStrip) + bottomTrim + topTrim

	-- The window's top left stays where it is and only its size changes. Never placed: its current top left, whatever
	-- it's anchored by, becomes the anchor. Placed (dragged or centred): it goes back to the saved place once the size
	-- is set, every time, rather than trusting the anchor to have survived since load (UI/Frame.lua).
	local window = self:GetParent()
	local point, _, relativePoint = window:GetPoint(1)
	if not ns.saved.window.point and not (point == "TOPLEFT" and relativePoint == "BOTTOMLEFT") then
		local left, top = window:GetLeft(), window:GetTop()
		if left and top then
			window:ClearAllPoints()
			window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
	end
	window:SetSize(WINDOW_WIDTH - shrinkX, WINDOW_HEIGHT - shrinkY)
	ns.RestoreWindowPosition(window)
	self:SetSize(frameWidth, FRAME_HEIGHT - shrinkY)
	self.Background:SetHeight(BACKGROUND_HEIGHT - shrinkY)
	self:LayoutBackground(frameWidth, BACKGROUND_HEIGHT - shrinkY, topTrim)
	self.ClassBackground:ClearAllPoints()
	self.ClassBackground:SetPoint("TOPLEFT", self.Background, "TOPLEFT", 0, -(TOP_STRIP - topTrim))
	self.ClassBackground:SetPoint("BOTTOMRIGHT", self.Background, "BOTTOMRIGHT", 0, bottomStrip)

	-- Talents move up into the removed row; the bottom bar's padding goes with it.
	-- The talents are placed from the frame's top, which the tab strip's trim doesn't move, while the art and headers
	-- move up with the border: they move up by the trim too (they sat that much lower, towards the bottom edge).
	self:SetBasePanOffset(self.basePanOffsetX, self:GetBaseOffsetYForClass() + rowRemoved + topTrim)
	self.bottomPadding = barRemoved and BOTTOM_PADDING_REMOVED or self.initialBottomPadding
	self:UpdatePadding()

	-- The ornaments along the top keep their size, cropped at the outer ends if the window is narrower.
	local borderWidth = frameWidth + 2 * BORDER_X
	local center = (FRAME_WIDTH + 2 * BORDER_X) / 2
	local dividerX = { center - leftWidth / 2 + DIVIDER_OFFSET_X, center + rightWidth / 2 - DIVIDER_OFFSET_X }

	self:LayoutClassArt(layout, frameWidth, dividerX, rowRemoved, bottomTrim)
	-- Always by the file and its coordinates, at full size too: through SetAtlas they draw as a dark block with no bar.
	local half = borderWidth / 2 - ORNAMENT_INSET
	for _, d in ipairs({ { self.DividerHorizontalLeft, "Talents-divider-left-c60", leftWidth, "RIGHT" },
		{ self.DividerHorizontalRight, "Talents-divider-right-c60", rightWidth, "LEFT" } }) do
		local texture, atlas, width, align = d[1], d[2], d[3], d[4]
		texture:SetShown(not pointsInTabRow)
		SetCroppedAtlas(texture, atlas, math.min(1, half / width), 1, align)
		texture:SetSize(math.min(width, half), leftHeight)
	end

	-- The dividers between trees, where Blizzard's anchors put them, moved with the gap they're in.
	-- They keep their size, cut at the bottom where the art ends when the window is shorter (uncut, they reach past
	-- the window's bottom at the smallest talent spacing).
	local dividerY = ORNAMENT_Y - leftHeight / 2 + DIVIDER_OFFSET_Y + rowRemoved
	local verticalWidth, verticalHeight = AtlasSize("Talents-divider-vertical-c60")
	local artHeight = BACKGROUND_HEIGHT - shrinkY - (TOP_STRIP - topTrim) - bottomStrip
	local room = artHeight + BORDER_Y + dividerY -- from the divider's top to the art's bottom
	local height = Clamp(room, 1, verticalHeight)
	for index, divider in ipairs({ self.DividerVerticalLeft, self.DividerVerticalRight }) do
		divider:ClearAllPoints()
		divider:SetPoint("TOP", border, "TOPLEFT", dividerX[index] + (layout.dividerShift[index] or 0), dividerY)
		SetCroppedAtlas(divider, "Talents-divider-vertical-c60", 1, height / verticalHeight)
		divider:SetSize(verticalWidth, height)
	end

	-- The name box sits in the tab row between the tabs and the search box (and the points, with the option).
	local nameBox = self.NameBox
	nameBox:ClearAllPoints()
	nameBox:SetPoint("LEFT", tabSystem, "RIGHT", ROW_GAP, 0)

	-- Apply (with Undo to its right) where Blizzard has it, or in the tree area's bottom-right corner without the bar
	-- (more room around the last row there than on the left), as narrow as its text allows, with Undo to its left so
	-- Apply doesn't move when Undo appears. Above the talent buttons, which would take its clicks where they overlap.
	-- In the corner its text is the game's "Apply Changes", or just "Apply" once the sliders squeeze the corner enough.
	-- Either slider alone barely does; the two together do. So the points both take off Blizzard's spacing count as
	-- (X + Y) / max(X, Y) * (X + Y): one slider alone counts as itself, two equal ones as four times one of them. Y
	-- (talent spacing) counts double, so both run 0 to 80 points (spacing only goes down to 60%). "Apply" from
	-- APPLY_SHORT_AT.
	local apply, undo = self.ApplyButton, self.UndoButton
	apply:ClearAllPoints()
	undo:ClearAllPoints()
	apply:SetText(TALENT_FRAME_APPLY_BUTTON_TEXT)
	if barRemoved then
		apply:SetPoint("BOTTOMRIGHT", self.ClassBackground, "BOTTOMRIGHT", -APPLY_CORNER_X, APPLY_CORNER_Y)
		undo:SetPoint("RIGHT", apply, "LEFT", -UNDO_GAP_CORNER, 0)
		local x, y = 100 - ns.saved.treeGap, 2 * (100 - ns.saved.talentSpacing)
		local most = math.max(x, y)
		if most > 0 and (x + y) / most * (x + y) >= APPLY_SHORT_AT then
			apply:SetText(APPLY)
		end
		apply:SetWidth(apply:GetFontString():GetUnboundedStringWidth() + APPLY_TEXT_PADDING)
	else
		apply:SetPoint("BOTTOM", self.Background, "BOTTOM", 0, APPLY_BAR_Y)
		undo:SetPoint("LEFT", apply, "RIGHT", UNDO_GAP, 0)
		apply:SetWidth(APPLY_WIDTH)
	end
	local buttonLevel = self.ButtonsParent:GetFrameLevel() + ns.ABOVE_TALENTS_LEVEL
	apply:SetFrameLevel(buttonLevel)
	undo:SetFrameLevel(buttonLevel)

	self:UpdateAllTalentButtonPositions()
	self:UpdateAllGatePositions()
	for edge in self.edgePool:EnumerateActive() do
		edge:MarkPositionDirty()
		edge:UpdatePosition()
	end
	for index, header in ipairs(self.treeHeaders) do
		header:ClearAllPoints()
		header:SetPoint("CENTER", border, "TOPLEFT", self:GetHeaderX(index), self:GetHeaderY())
		self:LayoutHeaderDivider(index, header)
	end
	ns.TalentedStyle.MarkDirty(self)
end

-- The tree headers' height (centre, from the border's top): Blizzard's, raised by the removed points row.
function Frame:GetHeaderY()
	return HEADER_Y + (self.rowRemoved or 0)
end

-- The class's own offset (UpdateClassVisuals), before the tab row option moves it.
function Frame:GetBaseOffsetYForClass()
	local classVisuals = ClassTalentUtil.GetVisualsForClassID(self:GetClassID())
	local offsets = classVisuals and classVisuals.panOffset
	return self.initialBasePanOffsetY - (offsets and offsets.y or 0)
end
