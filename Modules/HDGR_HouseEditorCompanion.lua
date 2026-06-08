-- HDG.HouseEditorCompanion
-- ============================================================================
-- Launcher button + decor PLACEMENT for the in-editor companion window.
-- The companion WINDOW itself is a declarative HDG.Window satellite
-- (LC.windows.companion). This module owns only the imperative pieces:
--   * launcher button (toggles companion.windowShown)
--   * companionGridCell cardGrid cell kind (decor placement click)
--   * recent-session history tracking (StartPlacingNewDecor hook)
--   * injection lifecycle (create launcher + EnsureCreated on editor-open)
-- Sidebar rows + toolbar wiring live in UI/HDGR_Controller_Companion.lua.
--
-- TAINT-SAFE INJECTION (see reference_storagepanel_taint.md):
--   The launcher + the satellite frame parent to HouseEditorFrame for the
--   visibility cascade only. We do NOT participate in StoragePanel's TabSystem
--   -- no AddNamedTab, no SetTabCallback, no hooksecurefunc on protected panels.
--   HookScript on HouseEditorFrame:OnShow is safe (additive, not replacement).
--   12.0.5 productInfo-nil race is avoided by zero contact with the storage panel.
--
-- LIFECYCLE:
--   ADDON_LOADED (filter Blizzard_HouseEditor) -> InjectShell()
--   HOUSE_EDITOR_MODE_CHANGED -> InjectShell() fallback if not yet injected.
--   OnEnable: if Blizzard_HouseEditor already loaded, InjectShell.
--   InjectShell -> create launcher + install placement hook + HookScript OnShow
--     + HDG.Window:EnsureCreated("companion") (lazy satellite, now that its
--     parent HouseEditorFrame exists). The reconciler owns visibility/position.
--   Parent cascade -> closing HouseEditor hides the launcher + the satellite.

HDG = HDG or {}
HDG.HouseEditorCompanion = HDG.HouseEditorCompanion or {}
local H = HDG.HouseEditorCompanion

H._injected = false
H._launcher = nil
H._isInside = false   -- HousingObserver:IsInsideHouse() captured on editor open; fixed for the edit session

local CreateLauncher

-- ============================================================================
-- Grid-cell click -> place decor in the house editor.
-- ============================================================================
-- Module-scope handler (no per-cell closure allocation): reads the placement
-- payload stamped onto the cell in initFunc, validates ownership + indoor/
-- outdoor rules, then fires the housing-editor placement API. Dyed-variant
-- cells carry the variant entryID, so this places the dyed copy directly.

-- Place decor mirroring Blizzard's HousingCatalogDecorEntryMixin:TypeSpecificOnInteract.
-- 1. If not in BasicDecor mode: activate it + defer one frame (mode switch needs to settle).
-- 2. In BasicDecor: set commitNewDecorOnMouseUp=FALSE so the click attaches to cursor
--    rather than immediately committing (without this, selecting also commits -- "places immediately").
-- Editor-mode access routes through HousingObserver (owner of C_HouseEditor);
-- C_HousingBasicMode is OWNED here.
local function _placeDecor(entryID)
    local BasicDecor = _G.Enum.HouseEditorMode.BasicDecor
    if not HDG.HousingObserver:IsHouseEditorModeActive(BasicDecor) then
        HDG.HousingObserver:ActivateHouseEditorMode(BasicDecor)
        _G.RunNextFrame(function() _G.C_HousingBasicMode.StartPlacingNewDecor(entryID) end)
        return
    end
    local modeFrame = _G.HouseEditorFrame:GetActiveModeFrame()
    if modeFrame then modeFrame.commitNewDecorOnMouseUp = false end  -- click, not drag
    _G.C_HousingBasicMode.StartPlacingNewDecor(entryID)
end

local function _companionCellClick(self)
    local entryID = self._placeEntryID
    if not entryID then return end          -- non-placeable cell (catalog miss)
    local name = self._placeName or "this decor"
    -- Inside/outside (via HousingObserver, owner of C_Housing) decides whether
    -- indoor-only / outdoor-only decor can be placed from where the player stands.
    local inside = HDG.HousingObserver:IsInsideHouse()
    if inside and not self._placeAllowIndoors then
        HDG.Log:Notify("warn", '"' .. name .. '" is outdoor only.'); return
    elseif not inside and not self._placeAllowOutdoors then
        HDG.Log:Notify("warn", '"' .. name .. '" is indoor only.'); return
    end
    if (self._placeQty or 0) < 1 then
        HDG.Log:Notify("warn", 'No "' .. name .. '" available to place.'); return
    end
    _placeDecor(entryID)
end

-- ============================================================================
-- "Can't place here" border (HDG parity). The player's inside/outside location
-- is FIXED for an edit session (you can't walk in/out mid-edit), so it's
-- captured once in H._isInside on editor open -- no live re-check needed. A cell
-- whose decor can't be placed from where the player stands (indoor-only item
-- while outside, or outdoor-only while inside) gets a warning border. 4 lazy
-- edges tinted via SetColorTexture (block chars don't render -- see
-- reference_wow_color_swatches).
local PLACE_BORDER = { 0.95, 0.5, 0.12, 0.9 }   -- warning orange
local function _ensurePlaceBorder(cell)
    if cell._placeBorder then return cell._placeBorder end
    local e = {}
    for i = 1, 4 do
        e[i] = cell:CreateTexture(nil, "OVERLAY")
        e[i]:SetColorTexture(PLACE_BORDER[1], PLACE_BORDER[2], PLACE_BORDER[3], PLACE_BORDER[4])
    end
    e[1]:SetPoint("TOPLEFT");     e[1]:SetPoint("TOPRIGHT");     e[1]:SetHeight(2)  -- top
    e[2]:SetPoint("BOTTOMLEFT");  e[2]:SetPoint("BOTTOMRIGHT");  e[2]:SetHeight(2)  -- bottom
    e[3]:SetPoint("TOPLEFT");     e[3]:SetPoint("BOTTOMLEFT");   e[3]:SetWidth(2)   -- left
    e[4]:SetPoint("TOPRIGHT");    e[4]:SetPoint("BOTTOMRIGHT");  e[4]:SetWidth(2)   -- right
    cell._placeBorder = e
    return e
end
local function _paintPlaceBorder(cell, blocked)
    if not blocked then
        if cell._placeBorder then for _, t in ipairs(cell._placeBorder) do t:Hide() end end
        return
    end
    for _, t in ipairs(_ensurePlaceBorder(cell)) do t:Show() end
end

-- Recent-activity +/- corner overlays (HDG parity): communities-chat-icon-plus
-- (blue, placed this session) over communities-chat-icon-minus (red, removed),
-- top-right, stacked when both apply. Exact counts live in the tooltip. Driven
-- by ed.placedCount / ed.removedCount (only the recent strip + recent mode set them).
local function _ensureRecentBadges(cell)
    if cell._recentPlus then return end
    cell._recentPlus = cell:CreateTexture(nil, "OVERLAY", nil, 3)
    cell._recentPlus:SetSize(13, 13)
    cell._recentPlus:SetPoint("TOPRIGHT", -1, -1)
    cell._recentPlus:SetAtlas("communities-chat-icon-plus")
    cell._recentMinus = cell:CreateTexture(nil, "OVERLAY", nil, 3)
    cell._recentMinus:SetSize(13, 13)
    cell._recentMinus:SetAtlas("communities-chat-icon-minus")
    -- Count numbers (recent-MODE grid only), left of each +/- icon, accent-colored.
    cell._recentPlusFs = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    cell._recentMinusFs = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
end
-- showCount: recent-MODE grid shows the placed/removed COUNT number (accent); the
-- per-action STRIP passes false -> direction icon only (each card is one action).
local function _paintRecentBadges(cell, placed, removed, showCount)
    placed, removed = placed or 0, removed or 0
    if placed <= 0 and removed <= 0 then
        if cell._recentPlus then
            cell._recentPlus:Hide();   cell._recentMinus:Hide()
            cell._recentPlusFs:Hide(); cell._recentMinusFs:Hide()
        end
        return
    end
    _ensureRecentBadges(cell)
    cell._recentPlus:SetShown(placed > 0)
    if removed > 0 then
        cell._recentMinus:ClearAllPoints()
        cell._recentMinus:SetPoint("TOPRIGHT", -1, placed > 0 and -15 or -1)  -- stack below + when both
        cell._recentMinus:Show()
    else
        cell._recentMinus:Hide()
    end
    if showCount then
        -- Count colored via the TextStatus role (= semantic.accent) through
        -- Theme:Register, so it repaints on scheme switch -- NOT an inline SetTextColor
        -- (which bakes a color the row rails can't track = the row-paint smell).
        cell._recentPlusFs:SetShown(placed > 0)
        if placed > 0 then
            cell._recentPlusFs:SetText(placed)
            HDG.Theme:Register(cell._recentPlusFs, "TextStatus")
            cell._recentPlusFs:ClearAllPoints()
            cell._recentPlusFs:SetPoint("RIGHT", cell._recentPlus, "LEFT", -1, 0)
        end
        cell._recentMinusFs:SetShown(removed > 0)
        if removed > 0 then
            cell._recentMinusFs:SetText(removed)
            HDG.Theme:Register(cell._recentMinusFs, "TextStatus")
            cell._recentMinusFs:ClearAllPoints()
            cell._recentMinusFs:SetPoint("RIGHT", cell._recentMinus, "LEFT", -1, 0)
        end
    else
        cell._recentPlusFs:Hide(); cell._recentMinusFs:Hide()
    end
end

-- ============================================================================
-- Tooltip def for companion grid cells. Function form: reads live cell fields
-- at hover time so it always reflects the current paint pass.
-- ============================================================================

local function _companionCellTooltipDef(self)
    if not self._placeName then return nil end
    local lines = {}
    if (self._recentPlaced or 0) > 0 then
        lines[#lines + 1] = { text = "Placed " .. self._recentPlaced .. " this session", r = 0.55, g = 0.78, b = 0.55 }
    end
    if (self._recentRemoved or 0) > 0 then
        lines[#lines + 1] = { text = "Removed " .. self._recentRemoved .. " this session", r = 0.85, g = 0.55, b = 0.45 }
    end
    if self._placeEntryID then
        local storage = self._placeQty or 0
        local placedN = self._placeNumPlaced
        if placedN ~= nil then
            lines[#lines + 1] = { text = ("Owned: %d (Placed: %d, Storage: %d)"):format(storage + placedN, placedN, storage), r = 0, g = 1, b = 0 }
        elseif storage > 0 then
            lines[#lines + 1] = { text = "In storage: " .. storage, r = 0.4, g = 0.9, b = 0.4 }
        else
            lines[#lines + 1] = { text = "None available to place", r = 0.85, g = 0.45, b = 0.45 }
        end
        if self._placeWhere then
            lines[#lines + 1] = { text = self._placeWhere, r = 0.78, g = 0.78, b = 0.6 }
        end
        if (self._placeCost or 0) > 0 then
            lines[#lines + 1] = { text = "Placement cost: " .. self._placeCost, r = 0.78, g = 0.78, b = 0.6 }
        end
        lines[#lines + 1] = { text = "Click to place", r = 0.5, g = 0.5, b = 0.5 }
    end
    return { title = self._placeName, extraLines = lines }
end

-- ============================================================================
-- CardGrid cell kind: companion grid items. Used by BOTH the main grid and
-- the recent strip (different cellSize cfg, same renderer).
-- ============================================================================

HDG.CardGrid:RegisterCellKind("companionGridCell", {
    template = "Button",
    initFunc = function(cell, ed, cfg)
        HDG.CardGrid:EnsureDefaultAnatomy(cell, cfg)
        cell:Show()
        HDG.CardGrid:PaintIcon(cell, ed.iconTexture, ed.iconAtlas)
        -- No collected check/X badge -- this is a PLACEMENT grid; the owned-to-
        -- place count badge below carries ownership (matches HDG's cell).
        cell.label:Hide()

        -- Cost badge (bottom-left): gated by ed.showCost, stamped per-cell from
        -- session.ui.companion.showCost. Pure function of ed; COMPANION_TOGGLE_COST re-pushes.
        if not cell._costFs then
            cell._costFs = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            cell._costFs:SetPoint("BOTTOMLEFT", 3, 3)
        end
        local cost = ed.placementCost
        if ed.showCost and cost and cost > 0 then
            cell._costFs:SetText(_G.CreateAtlasMarkup("house-decor-budget-icon", 11, 11) .. cost)
            cell._costFs:Show()
        else
            cell._costFs:Hide()
        end

        -- Owned-to-place count badge; gray the icon when 0 copies free.
        -- per-action STRIP hides it (each card is one action, not a count).
        local qty = ed.ownedQty or 0
        if ed.isActionStrip then
            HDG.CardGrid:PaintBadge(cell, nil)
        else
            HDG.CardGrid:PaintBadge(cell, qty > 0 and tostring(qty) or nil)
            if ed.entryID and qty < 1 then
                cell.icon:SetDesaturated(true)
                cell.icon:SetAlpha(0.45)
            end
        end

        -- Stamp the placement payload the click handler + tooltip read.
        cell._placeEntryID      = ed.entryID
        cell._placeName         = ed.name
        cell._placeQty          = qty
        cell._placeAllowIndoors = ed.allowIndoors
        cell._placeAllowOutdoors = ed.allowOutdoors
        cell._placeWhere = (ed.allowIndoors and not ed.allowOutdoors and "Indoor only")
            or (ed.allowOutdoors and not ed.allowIndoors and "Outdoor only") or nil
        cell._placeCost = ed.placementCost
        cell._placeNumPlaced = ed.numPlaced   -- "Placed:" tooltip line (nil for dyed variants -> storage-only)
        -- Recent-mode session activity (nil in other modes).
        cell._recentPlaced  = ed.placedCount
        cell._recentRemoved = ed.removedCount

        -- Recent-activity +/- corner overlays (placed/removed this session). Recent-MODE
        -- grid shows the count number (accent); the per-action strip = direction only.
        _paintRecentBadges(cell, ed.placedCount, ed.removedCount, not ed.isActionStrip)

        -- Orange border when this owned decor can't be placed from where the
        -- player stands (indoor-only while outside, or vice versa). Only
        -- placeable cells (entryID present) qualify; the recent strip's
        -- non-placeable cells carry no entryID so they never border.
        _paintPlaceBorder(cell, ed.entryID ~= nil
            and ((H._isInside and not ed.allowIndoors)
              or (not H._isInside and not ed.allowOutdoors)))

        cell:RegisterForClicks("LeftButtonUp")
        cell:SetScript("OnClick", _companionCellClick)
        -- Show the tooltip from WITHIN OnEnter (re-wired every init), NOT via
        -- TooltipEngine:Attach. This cell re-SetScripts OnEnter each init (hover bg),
        -- which clobbers Attach's once-installed HookScript on pooled re-acquire ->
        -- the tooltip vanishes after the first paint. (Same fix as stylesCuratorTile.)
        cell:SetScript("OnEnter", function(self_)
            self_.hoverBg:Show()
            HDG.TooltipEngine:Show(self_, _companionCellTooltipDef)
        end)
        cell:SetScript("OnLeave", function(self_)
            self_.hoverBg:Hide()
            HDG.TooltipEngine:Hide()
        end)
    end,
    resetFunc = function(_pool, cell)
        cell:SetScript("OnClick", nil)
        cell:SetScript("OnEnter", nil)
        cell:SetScript("OnLeave", nil)
        cell.hoverBg:Hide()
        if cell.badge then cell.badge:Hide() end
        if cell._costFs then cell._costFs:Hide() end
        _paintPlaceBorder(cell, false)
        _paintRecentBadges(cell, 0, 0)
        if cell.icon then cell.icon:SetDesaturated(false); cell.icon:SetAlpha(1) end
        cell._placeEntryID = nil
        cell._placeName = nil
        cell._placeQty = nil
        cell._placeNumPlaced = nil
        cell._placeAllowIndoors = nil
        cell._placeAllowOutdoors = nil
        cell._placeWhere = nil
        cell._placeCost = nil
        cell._recentPlaced = nil
        cell._recentRemoved = nil
    end,
})

-- ============================================================================
-- Recent Activity: edit-session history tracking.
-- ============================================================================
-- Sessions keyed by stable faction house id (not process-scoped houseGUID).
-- Placements captured by hooking StartPlacingNewDecor; removals reducer-side off STYLES_PLACED_DECOR_REMOVED.

local function _currentHouseKey()
    -- Single source of house identity (HousingObserver owns C_Housing); plot-keyed.
    return HDG.HousingObserver:CurrentHouseID()
end

local function _startRecentSession()
    local key = _currentHouseKey()
    if key then
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.RECENT_SESSION_START,
            payload = { houseKey = key },
        })
    end
end

-- Hook StartPlacingNewDecor once. StartPlacing is INTENT (not a placement yet);
-- only stash the pending itemID here. HousingObserver:OnDecorPlaceSuccess records
-- RECENT_DECOR_PLACED on the actual commit, so a cancelled pick records nothing.
-- entryID is the HousingCatalogEntryID table (.recordID = decorID); resolve to itemID.
local function _installPlacementHook()
    if H._placeHookInstalled then return end
    local function stashPending(entryID)
        local decorID = type(entryID) == "table" and entryID.recordID or nil
        local itemID  = decorID and HDG.HousingCatalogObserver:GetItemIDByDecorID(decorID)
        if itemID then HDG.HousingObserver:SetPendingPlacement(itemID) end
    end
    if _G.C_HousingBasicMode and _G.C_HousingBasicMode.StartPlacingNewDecor then
        hooksecurefunc(_G.C_HousingBasicMode, "StartPlacingNewDecor", stashPending)  -- exception(boundary): housing C_API nil off-house-context
        H._placeHookInstalled = true
    end
    if _G.C_HousingExpertMode and _G.C_HousingExpertMode.StartPlacingNewDecor then
        hooksecurefunc(_G.C_HousingExpertMode, "StartPlacingNewDecor", stashPending)  -- exception(boundary): housing C_API nil off-house-context
    end
end

-- Editor became visible. Trigger the load-on-demand catalog sweep (the main window
-- does this on tab-activate; editor-only open never would -> "?" placeholder icons).
-- Sweep is async + idempotent; completion bumps sweepGeneration -> companion re-resolves.
local function _onEditorShown()
    -- Capture inside/outside ONCE per editor open (fixed for the edit session) so
    -- grid cells can border decor that can't be placed from here. Via HousingObserver
    -- (owner of C_Housing).
    H._isInside = HDG.HousingObserver:IsInsideHouse()
    HDG.HousingCatalogObserver:RequestLoad()
    _startRecentSession()   -- new edit session per editor open
    H._launcher:Show()
    -- Idempotent: builds the satellite the first time the editor opens (its
    -- parent HouseEditorFrame now exists); HDG.Window's reconciler -- already
    -- subscribed at OnEnable -- drives visibility/position/content from there.
    HDG.Window:EnsureCreated("companion")
end

local function InjectShell()
    if H._injected then return end
    if not _G.HouseEditorFrame then return end
    H._injected = true

    H._launcher = CreateLauncher()
    _installPlacementHook()

    _G.HouseEditorFrame:HookScript("OnShow", _onEditorShown)

    if _G.HouseEditorFrame:IsShown() then
        _onEditorShown()
    end
end

-- ============================================================================
-- Launcher button.
-- ============================================================================

function CreateLauncher()
    local btn = CreateFrame("Button", "HDGR_HouseEditorLauncher", _G.HouseEditorFrame)
    btn:SetSize(40, 40)
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnDragStart", btn.StartMoving)
    -- Persist the launcher position (UIParent-TOPLEFT, top-down y) so a dragged
    -- icon stays put across editor re-opens + /reload. Mirrors the companion
    -- window's COMPANION_SET_POSITION convention.
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top, screenH = self:GetLeft(), self:GetTop(), _G.UIParent:GetHeight()
        if left and top and screenH then
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.COMPANION_SET_LAUNCHER_POSITION,
                payload = { x = left, y = top - screenH },
            })
        end
    end)
    btn:Hide()

    -- Restore saved position (UIParent-anchored: fixed screen spot regardless of HouseEditorFrame parent).
    local pos = HDG.Store:GetState().account.ui.companion.launcher
    if type(pos.x) == "number" and type(pos.y) == "number" then
        btn:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", pos.x, pos.y)
    else
        btn:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 0, -30)
    end

    -- The HDG icon (same texture the minimap button uses). Hover brightens it
    -- (additive). Framed with a gold border + an expandable arrow (below).
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface/AddOns/HousingDecorGuide/textures/HousingDecorIcon")
    icon:SetAllPoints()

    btn:SetHighlightTexture("Interface/AddOns/HousingDecorGuide/textures/HousingDecorIcon")
    local hl = btn:GetHighlightTexture()
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.25)

    -- Gold frame around the icon (4 thin edges; SetColorTexture per
    -- reference_wow_color_swatches -- block/border chars don't render). OVERLAY so
    -- it sits above the icon's perimeter.
    local BORDER = { 0.85, 0.68, 0.32, 1 }
    local edges = {}
    for i = 1, 4 do
        edges[i] = btn:CreateTexture(nil, "OVERLAY")
        edges[i]:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    end
    edges[1]:SetPoint("TOPLEFT");    edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(2)  -- top
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(2)  -- bottom
    edges[3]:SetPoint("TOPLEFT");    edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(2)   -- left
    edges[4]:SetPoint("TOPRIGHT");   edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(2)   -- right

    -- Expandable affordance: Blizzard's arrow, just right of the icon. Points RIGHT
    -- when the window is CLOSED (expand), flips to LEFT when OPEN (collapse). It lives
    -- outside the 40x40 icon, so extend the hit rect right to keep it clickable.
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas("plunderstorm-pickup-arrow")
    arrow:SetSize(14, 20)
    arrow:SetPoint("LEFT", btn, "RIGHT", 2, 0)
    btn:SetHitRectInsets(0, -18, 0, 0)
    -- Capture the 8-value texcoord quad to mirror-flip the arrow without GetAtlasInfo field names.
    local ulx, uly, llx, lly, urx, ury, lrx, lry = arrow:GetTexCoord()
    local arrowOpen
    local function updateArrow()
        local open = HDG.Store:GetState().session.ui.companion.windowShown and true or false
        if open == arrowOpen then return end   -- only on actual open/close transitions
        arrowOpen = open
        if not ulx then return end             -- exception(boundary): atlas unresolved -> keep SetAtlas default
        if open then   -- mirror horizontally: swap the left column (UL,LL) with the right (UR,LR)
            arrow:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly)
        else
            arrow:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
        end
    end
    updateArrow()
    HDG.Store:Subscribe(updateArrow)

    HDG.TooltipEngine:Attach(btn, {
        title      = "Housing Decor Guide",
        extraLines = {
            { text = "Click to open the Housing Decor Guide chest to place decor.", wrap = true },
            { text = "Drag to move.", r = 0.7, g = 0.7, b = 0.7, wrap = true },
        },
    })

    btn:SetScript("OnClick", function()
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.COMPANION_TOGGLE,
            payload = {},
        })
    end)
    return btn
end

-- ============================================================================
-- Module declare.
-- ============================================================================

local function _OnAddonLoaded(self, addonName)
    if addonName ~= "Blizzard_HouseEditor" then return end
    _G.RunNextFrame(InjectShell)  -- defer: some subframes complete on the next tick
end

local function _OnHouseEditorModeChanged(self)
    if H._injected then return end
    if not _G.HouseEditorFrame then return end
    _G.RunNextFrame(InjectShell)  -- defer: OnShow handlers settle on the next tick
end

HDG.Modules:Declare({
    name = "HouseEditorCompanion",
    dependencies = { "HousingObserver" },   -- consumes HO editor-mode / inside accessors
    -- Owns the placement-mode namespaces: it HOOKS StartPlacingNewDecor on both
    -- (the recent-activity observe rail) AND issues the placement command. C_HouseEditor
    -- + C_Housing are NOT owned here -- they belong to HousingObserver; the companion
    -- consumes them through HO accessors (invariant 9).
    ownsBlizzardNamespaces = { "C_HousingBasicMode", "C_HousingExpertMode" },
    blizzardEvents = {
        ADDON_LOADED              = { handler = "OnAddonLoaded" },
        HOUSE_EDITOR_MODE_CHANGED = { handler = "OnHouseEditorModeChanged" },
    },
    OnAddonLoaded              = _OnAddonLoaded,
    OnHouseEditorModeChanged   = _OnHouseEditorModeChanged,
    -- onEnable: safety net for /reload-with-editor-already-loaded (no defer needed post-PLAYER_LOGIN).
    onEnable = function(self)
        if _G.C_AddOns.IsAddOnLoaded("Blizzard_HouseEditor") then
            InjectShell()
        end
    end,
})
