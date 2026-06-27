-- HDG.TooltipRecipes
-- ============================================================================
-- Central registry for every tooltip in HDG. Spec authors reference recipes
-- by name; the layout validator enforces that every widget either declares
-- `tooltip = { recipe = "Name" }` or explicit `tooltip = false`.
--
-- Architecture: docs/HDGR_TOOLTIP_PORT.md (Lattice consumption pattern).
-- Validated production exemplar: VamoosesDyeStudio/Core/VDS_TooltipRecipes.lua.
--
-- Recipe value shapes accepted by HDG.TooltipEngine:
--   table    -- passed directly as the TE def
--   function -- called per hover (function(self) -> def | nil)
--
-- HDG's TooltipEngine does NOT auto-wrap bare strings (VDS does); use the
-- table form { title = "..." } for the simple case. If string-shorthand is
-- desired later, add the wrap in TooltipEngine:Attach OR Components.lua.
--
-- TE def fields (from Core/HDGR_TooltipEngine.lua):
--   title, body, anchor, textFn, itemID, hyperlink, extraLines
--
-- Adding a recipe:
--   1. Add the entry below (alphabetical within its section)
--   2. Reference it via { recipe = "YourRecipeName" } in LayoutConfig spec
--   3. The Layout:Validate boot check catches name typos
--
-- TODO sections are placeholders; replace stubs as each call site migrates to recipe form.

HDG = HDG or {}

-- ============================================================================
-- Interaction hints registry
-- ============================================================================
-- Centralised so every hint reads identically and L10n swapping happens in one place.

HDG.TooltipHints = {
    -- Click hints (single button)
    click_expand_collapse  = "locale:HINT_CLICK_EXPAND_COLLAPSE",
    click_navigate         = "locale:HINT_CLICK_NAVIGATE",
    click_scan             = "locale:HINT_CLICK_SCAN",
    click_confirm_craft    = "locale:HINT_CLICK_CONFIRM_CRAFT",
    click_copy_url         = "locale:HINT_CLICK_COPY_URL",
    click_cycle_sort       = "locale:HINT_CLICK_CYCLE_SORT",
    click_ah_search        = "locale:HINT_CLICK_AH_SEARCH",
    click_open_profession  = "locale:HINT_CLICK_OPEN_PROFESSION",
    click_inspect          = "locale:HINT_CLICK_INSPECT",
    left_apply             = "locale:HINT_LEFT_APPLY",

    -- Shift+click
    shift_shopping     = "locale:HINT_SHIFT_SHOPPING",
    shift_waypoint     = "locale:HINT_SHIFT_WAYPOINT",
    shift_auctionator  = "locale:HINT_SHIFT_AUCTIONATOR",
    shift_remove_one   = "locale:HINT_SHIFT_REMOVE_ONE",
    shift_remove_all   = "locale:HINT_SHIFT_REMOVE_ALL",

    -- Ctrl+click
    ctrl_queue = "locale:HINT_CTRL_QUEUE",

    -- Right-click
    right_remove       = "locale:HINT_RIGHT_REMOVE",
    right_auctionator  = "locale:HINT_RIGHT_AUCTIONATOR",
}

-- ============================================================================
-- Recipes
-- ============================================================================

HDG.TooltipRecipes = HDG.TooltipRecipes or {}

local R = HDG.TooltipRecipes
local H = HDG.TooltipHints

-- ===== Window chrome ========================================================

R.Close = {
    title  = "locale:TIP_CLOSE",
    anchor = "ANCHOR_BOTTOM",
}

-- Compartment / minimap buttons -- click hints inline (button-specific, not reusable).
R.AddonCompartment = {
    title      = "locale:TIP_ADDON_TITLE",
    body       = "locale:TIP_ADDON_BODY",
    anchor     = "ANCHOR_RIGHT",
    extraLines = {
        { text = "locale:TIP_COMPARTMENT_CLICK", r = 0.7, g = 0.7, b = 0.7 },
    },
}

R.MinimapButton = {
    title      = "locale:TIP_ADDON_TITLE",
    anchor     = "ANCHOR_LEFT",   -- LibDBIcon-managed; engine override may apply
    extraLines = {
        { text = "locale:TIP_MINIMAP_LEFT_CLICK",   r = 0.7, g = 0.7, b = 0.7 },
        { text = "locale:TIP_MINIMAP_RIGHT_CLICK",  r = 0.7, g = 0.7, b = 0.7 },
        { text = "locale:TIP_MINIMAP_DRAG",         r = 0.7, g = 0.7, b = 0.7 },
    },
}

-- ===== Outreach (about pane) ================================================

R.Discord = {
    title  = "locale:TIP_DISCORD_TITLE",
    body   = "locale:TIP_DISCORD_BODY",
    anchor = "ANCHOR_RIGHT",
}

R.Coffee = {
    title  = "locale:TIP_COFFEE_TITLE",
    body   = "locale:TIP_COFFEE_BODY",
    anchor = "ANCHOR_RIGHT",
}

-- ===== Config sidebar checkboxes ============================================
R.ConfigDebugToggle    = { title = "locale:TIP_CONFIG_DEBUG_TITLE",    body = "locale:TIP_CONFIG_DEBUG_BODY" }
R.ConfigMinimapToggle  = { title = "locale:TIP_CONFIG_MINIMAP_TITLE",  body = "locale:TIP_CONFIG_MINIMAP_BODY" }
R.OpenDebugLog         = { title = "locale:TIP_OPEN_DEBUG_LOG_TITLE",  body = "locale:TIP_OPEN_DEBUG_LOG_BODY" }
R.WowheadLink          = { title = "locale:TIP_WOWHEAD_TITLE",         body = "locale:TIP_WOWHEAD_BODY" }
R.ProjectsNewRoom      = { title = "locale:TIP_PROJECTS_NEW_ROOM_TITLE",     body = "locale:TIP_PROJECTS_NEW_ROOM_BODY" }
R.ProjectsOpenArchitect = { title = "locale:TIP_PROJECTS_OPEN_ARCHITECT_TITLE", body = "locale:TIP_PROJECTS_OPEN_ARCHITECT_BODY" }
R.ProjectsLandingEquip = { title = "locale:TIP_PROJECTS_LANDING_EQUIP_TITLE", body = "locale:TIP_PROJECTS_LANDING_EQUIP_BODY" }
R.ProjectsUnassign     = { title = "locale:TIP_PROJECTS_UNASSIGN_TITLE",     body = "locale:TIP_PROJECTS_UNASSIGN_BODY" }
R.ProjectsHelp         = { title = "locale:TIP_PROJECTS_HELP_TITLE",         body = "locale:TIP_PROJECTS_HELP_BODY" }
R.ProjectsAutoAssign   = { title = "locale:TIP_PROJECTS_AUTO_ASSIGN_TITLE",   body = "locale:TIP_PROJECTS_AUTO_ASSIGN_BODY" }
R.ProjectsForkDesign   = { title = "locale:TIP_PROJECTS_FORK_TITLE",          body = "locale:TIP_PROJECTS_FORK_BODY" }
R.ProjectsQueueCraft   = { title = "locale:TIP_PROJECTS_QUEUE_CRAFT_TITLE",   body = "locale:TIP_PROJECTS_QUEUE_CRAFT_BODY" }
R.ProjectsAddShopping  = { title = "locale:TIP_PROJECTS_ADD_SHOPPING_TITLE",  body = "locale:TIP_PROJECTS_ADD_SHOPPING_BODY" }
R.ProjectsNewSet       = { title = "locale:TIP_PROJECTS_NEW_SET_TITLE",      body = "locale:TIP_PROJECTS_NEW_SET_BODY" }
R.ProjectsRoomMore     = { title = "locale:TIP_PROJECTS_ROOM_MORE_TITLE",    body = "locale:TIP_PROJECTS_ROOM_MORE_BODY" }
R.ProjectsSetMore      = { title = "locale:TIP_PROJECTS_SET_MORE_TITLE",     body = "locale:TIP_PROJECTS_SET_MORE_BODY" }
R.ProjectsNewRoomHere  = { title = "locale:TIP_PROJECTS_NEW_ROOM_HERE_TITLE",  body = "locale:TIP_PROJECTS_NEW_ROOM_HERE_BODY" }
R.ProjectsPickerSource = { title = "locale:TIP_PROJECTS_PICKER_SOURCE_TITLE", body = "locale:TIP_PROJECTS_PICKER_SOURCE_BODY" }
R.ProjectsSaveAsSet    = { title = "locale:TIP_PROJECTS_SAVE_AS_SET_TITLE",  body = "locale:TIP_PROJECTS_SAVE_AS_SET_BODY" }
R.ProjectsEquipSet     = { title = "locale:TIP_PROJECTS_EQUIP_SET_TITLE",    body = "locale:TIP_PROJECTS_EQUIP_SET_BODY" }
R.ProjectsImportSet    = { title = "locale:TIP_PROJECTS_IMPORT_SET_TITLE",   body = "locale:TIP_PROJECTS_IMPORT_SET_BODY" }
R.ProjectsDetachCrate  = { title = "locale:TIP_PROJECTS_DETACH_CRATE_TITLE", body = "locale:TIP_PROJECTS_DETACH_CRATE_BODY" }
R.ProjectsCaptureAll   = { title = "locale:TIP_PROJECTS_CAPTURE_ALL_TITLE",  body = "locale:TIP_PROJECTS_CAPTURE_ALL_BODY" }
R.LumberToggle         = { title = "locale:TIP_LUMBER_TOGGLE_TITLE",         body = "locale:TIP_LUMBER_TOGGLE_BODY" }
R.ShoppingToggle       = { title = "locale:TIP_SHOPPING_TOGGLE_TITLE",       body = "locale:TIP_SHOPPING_TOGGLE_BODY" }
R.LumberAutoShow       = { title = "locale:TIP_LUMBER_AUTO_SHOW_TITLE",      body = "locale:TIP_LUMBER_AUTO_SHOW_BODY" }
R.LumberGoal           = { title = "locale:TIP_LUMBER_GOAL_TITLE",           body = "locale:TIP_LUMBER_GOAL_BODY" }
R.ZoneMapOpen          = { title = "locale:TIP_ZONE_MAP_TITLE",              body = "locale:TIP_ZONE_MAP_BODY" }

-- Layouts tab actions (effect-focused -- what each does, not just the label).
R.LayoutLoad      = { title = "locale:TIP_LAYOUT_LOAD_TITLE",      body = "locale:TIP_LAYOUT_LOAD_BODY",      anchor = "ANCHOR_TOP" }
R.LayoutShare     = { title = "locale:TIP_LAYOUT_SHARE_TITLE",     body = "locale:TIP_LAYOUT_SHARE_BODY",     anchor = "ANCHOR_TOP" }
R.LayoutImport    = { title = "locale:TIP_LAYOUT_IMPORT_TITLE",    body = "locale:TIP_LAYOUT_IMPORT_BODY",    anchor = "ANCHOR_BOTTOM" }
R.LayoutDuplicate = { title = "locale:TIP_LAYOUT_DUPLICATE_TITLE", body = "locale:TIP_LAYOUT_DUPLICATE_BODY", anchor = "ANCHOR_TOP" }

-- ===== Mogul / Goblin TSM columns ==========================================
-- Registered unconditionally so Layout:Validate passes regardless of TSM load state.
R.GoblinTsmServer  = { title = "locale:TIP_GOBLIN_TSM_SERVER_TITLE",   body = "locale:TIP_GOBLIN_TSM_SERVER_BODY" }
R.GoblinTsmMarket  = { title = "locale:TIP_GOBLIN_TSM_MARKET_TITLE",   body = "locale:TIP_GOBLIN_TSM_MARKET_BODY" }
R.GoblinTsmRegion  = { title = "locale:TIP_GOBLIN_TSM_REGION_TITLE",   body = "locale:TIP_GOBLIN_TSM_REGION_BODY" }
R.GoblinSaleRate   = { title = "locale:TIP_GOBLIN_SALE_RATE_TITLE",    body = "locale:TIP_GOBLIN_SALE_RATE_BODY" }
R.GoblinSoldPerDay = { title = "locale:TIP_GOBLIN_SOLD_PER_DAY_TITLE", body = "locale:TIP_GOBLIN_SOLD_PER_DAY_BODY" }
R.GoblinAhQty      = { title = "locale:TIP_GOBLIN_AH_QTY_TITLE",       body = "locale:TIP_GOBLIN_AH_QTY_BODY" }

-- ===== Styles ===============================================================
-- Save Snapshot explains its disabled state; severity chips define the
-- HDG-specific band vocabulary (UX review 2026-06-10 #4 + #5).
R.StylesSnapshot = { title = "locale:TIP_STY_SNAPSHOT_TITLE", body = "locale:TIP_STY_SNAPSHOT_BODY", anchor = "ANCHOR_BOTTOMRIGHT" }
R.StylesSeverity_all       = { title = "locale:TIP_STY_SEV_ALL_TITLE",       body = "locale:TIP_STY_SEV_ALL_BODY",       anchor = "ANCHOR_BOTTOMRIGHT" }
R.StylesSeverity_signature = { title = "locale:TIP_STY_SEV_SIGNATURE_TITLE", body = "locale:TIP_STY_SEV_SIGNATURE_BODY", anchor = "ANCHOR_BOTTOMRIGHT" }
R.StylesSeverity_accent    = { title = "locale:TIP_STY_SEV_ACCENT_TITLE",    body = "locale:TIP_STY_SEV_ACCENT_BODY",    anchor = "ANCHOR_BOTTOMRIGHT" }
R.StylesSeverity_versatile = { title = "locale:TIP_STY_SEV_VERSATILE_TITLE", body = "locale:TIP_STY_SEV_VERSATILE_BODY", anchor = "ANCHOR_BOTTOMRIGHT" }
R.StylesSeverity_clashing  = { title = "locale:TIP_STY_SEV_CLASHING_TITLE",  body = "locale:TIP_STY_SEV_CLASHING_BODY",  anchor = "ANCHOR_BOTTOMRIGHT" }

-- ===== Acquisition filter strip (UX tooltip audit 2026-06-10) ==============
-- Preset chips are HDG vocabulary (source-axis filters); one recipe per chip,
-- names match the LayoutConfig loop key "AcqPreset_" .. p.value.
R.AcqPreset_achievement = { title = "locale:TIP_ACQ_PRESET_ACH_TITLE",  body = "locale:TIP_ACQ_PRESET_ACH_BODY",  anchor = "ANCHOR_BOTTOM" }
R.AcqPreset_reputation  = { title = "locale:TIP_ACQ_PRESET_REP_TITLE",  body = "locale:TIP_ACQ_PRESET_REP_BODY",  anchor = "ANCHOR_BOTTOM" }
R.AcqPreset_endeavor    = { title = "locale:TIP_ACQ_PRESET_END_TITLE",  body = "locale:TIP_ACQ_PRESET_END_BODY",  anchor = "ANCHOR_BOTTOM" }
R.AcqPreset_quest       = { title = "locale:TIP_ACQ_PRESET_QST_TITLE",  body = "locale:TIP_ACQ_PRESET_QST_BODY",  anchor = "ANCHOR_BOTTOM" }
R.AcqPreset_recipes     = { title = "locale:TIP_ACQ_PRESET_REC_TITLE",  body = "locale:TIP_ACQ_PRESET_REC_BODY",  anchor = "ANCHOR_BOTTOM" }
R.AcqMissingToggle      = { title = "locale:TIP_ACQ_MISSING_TITLE",     body = "locale:TIP_ACQ_MISSING_BODY",     anchor = "ANCHOR_BOTTOM" }

-- ===== Decor browser controls ===============================================
R.DecorWishlist     = { title = "locale:TIP_DECOR_WISHLIST_TITLE",      body = "locale:TIP_DECOR_WISHLIST_BODY",      anchor = "ANCHOR_TOP" }
R.DecorDestroy      = { title = "locale:TIP_DECOR_DESTROY_TITLE",       body = "locale:TIP_DECOR_DESTROY_BODY",       anchor = "ANCHOR_TOP" }
R.DecorStoredFilter = { title = "locale:TIP_DECOR_STORED_FILTER_TITLE", body = "locale:TIP_DECOR_STORED_FILTER_BODY", anchor = "ANCHOR_BOTTOM" }

-- ===== Goblin price-source + actions ========================================
R.GoblinSrcAuto   = { title = "locale:TIP_GOBLIN_SRC_AUTO_TITLE",   body = "locale:TIP_GOBLIN_SRC_AUTO_BODY",   anchor = "ANCHOR_BOTTOMRIGHT" }
R.GoblinSrcDirect = { title = "locale:TIP_GOBLIN_SRC_DIRECT_TITLE", body = "locale:TIP_GOBLIN_SRC_DIRECT_BODY", anchor = "ANCHOR_BOTTOMRIGHT" }
R.GoblinTsmPct    = { title = "locale:TIP_GOBLIN_TSM_PCT_TITLE",    body = "locale:TIP_GOBLIN_TSM_PCT_BODY",    anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulQueueAll   = { title = "locale:TIP_MOGUL_QUEUE_ALL_TITLE",   body = "locale:TIP_MOGUL_QUEUE_ALL_BODY",   anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulSendToAH   = { title = "locale:TIP_MOGUL_SEND_AH_TITLE",     body = "locale:TIP_MOGUL_SEND_AH_BODY",     anchor = "ANCHOR_BOTTOMRIGHT" }

-- ===== Recipes materials controls ===========================================
R.RecipesGroupingToggle = { title = "locale:TIP_REC_GROUPING_TITLE", body = "locale:TIP_REC_GROUPING_BODY", anchor = "ANCHOR_BOTTOMRIGHT" }
R.RecipesDepth          = { title = "locale:TIP_REC_DEPTH_TITLE",    body = "locale:TIP_REC_DEPTH_BODY",    anchor = "ANCHOR_BOTTOMRIGHT" }
R.RecipesAddAllToAH     = { title = "locale:TIP_REC_ADD_ALL_TITLE",  body = "locale:TIP_REC_ADD_ALL_BODY",  anchor = "ANCHOR_BOTTOMRIGHT" }

-- ===== Config: collection cache reset (NOT WarnResetConfig -- that copy is
-- about display options; this button forces a rescan, not a wipe) ============
R.ConfigCollectionReset = { title = "locale:TIP_CONFIG_COLL_RESET_TITLE", body = "locale:TIP_CONFIG_COLL_RESET_BODY", anchor = "ANCHOR_BOTTOM" }

-- ===== Styles curator controls ==============================================
R.CuratorMove = { title = "locale:TIP_CUR_MOVE_TITLE", body = "locale:TIP_CUR_MOVE_BODY", anchor = "ANCHOR_BOTTOM" }
R.CuratorUndo = { title = "locale:TIP_CUR_UNDO_TITLE", body = "locale:TIP_CUR_UNDO_BODY", anchor = "ANCHOR_BOTTOM" }

-- ===== Mogul optimizer controls ============================================
-- Effect guidance (what the toggle does FOR you), not the mechanics. Kept short.
R.MogulModeProfit     = { title = "locale:TIP_MOGUL_MODE_PROFIT_TITLE",      body = "locale:TIP_MOGUL_MODE_PROFIT_BODY",      anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulModeCollection = { title = "locale:TIP_MOGUL_MODE_COLLECTION_TITLE", body = "locale:TIP_MOGUL_MODE_COLLECTION_BODY", anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulViewChar       = { title = "locale:TIP_MOGUL_VIEW_CHAR_TITLE",       body = "locale:TIP_MOGUL_VIEW_CHAR_BODY",       anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulViewAccount    = { title = "locale:TIP_MOGUL_VIEW_ACCOUNT_TITLE",    body = "locale:TIP_MOGUL_VIEW_ACCOUNT_BODY",    anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulOptOwned       = { title = "locale:TIP_MOGUL_OPT_OWNED_TITLE",       body = "locale:TIP_MOGUL_OPT_OWNED_BODY",       anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulOptBuy         = { title = "locale:TIP_MOGUL_OPT_BUY_TITLE",         body = "locale:TIP_MOGUL_OPT_BUY_BODY",         anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulFrugal         = { title = "locale:TIP_MOGUL_FRUGAL_TITLE",          body = "locale:TIP_MOGUL_FRUGAL_BODY",          anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulSupplyImpact   = { title = "locale:TIP_MOGUL_SUPPLY_IMPACT_TITLE",   body = "locale:TIP_MOGUL_SUPPLY_IMPACT_BODY",   anchor = "ANCHOR_BOTTOMRIGHT" }

-- ===== Recipe list filters =================================================
R.RecipeFilterUnknown = { title = "locale:TIP_RECIPE_FILTER_UNKNOWN_TITLE", body = "locale:TIP_RECIPE_FILTER_UNKNOWN_BODY", anchor = "ANCHOR_BOTTOM" }
R.RedeemableTag       = { title = "locale:TIP_REDEEMABLE_TAG_TITLE",         body = "locale:TIP_REDEEMABLE_TAG_BODY",         anchor = "ANCHOR_BOTTOM" }

-- ===== House-editor companion: mode tabs ===================================
R.CompanionStyles      = { title = "locale:TIP_COMPANION_STYLES_TITLE",      body = "locale:TIP_COMPANION_STYLES_BODY",      anchor = "ANCHOR_BOTTOM" }
R.CompanionRooms       = { title = "locale:TIP_COMPANION_ROOMS_TITLE",       body = "locale:TIP_COMPANION_ROOMS_BODY",       anchor = "ANCHOR_BOTTOM" }
R.CompanionSnapshots   = { title = "locale:TIP_COMPANION_SNAPSHOTS_TITLE",   body = "locale:TIP_COMPANION_SNAPSHOTS_BODY",   anchor = "ANCHOR_BOTTOM" }
R.CompanionThemes      = { title = "locale:TIP_COMPANION_THEMES_TITLE",      body = "locale:TIP_COMPANION_THEMES_BODY",      anchor = "ANCHOR_BOTTOM" }
R.CompanionCollections = { title = "locale:TIP_COMPANION_COLLECTIONS_TITLE", body = "locale:TIP_COMPANION_COLLECTIONS_BODY", anchor = "ANCHOR_BOTTOM" }
R.CompanionRecent      = { title = "locale:TIP_COMPANION_RECENT_TITLE",      body = "locale:TIP_COMPANION_RECENT_BODY",      anchor = "ANCHOR_BOTTOM" }

-- ===== Section headers / instructional ======================================
R.QueueHeader = {
    title  = "locale:TIP_QUEUE_HEADER_TITLE",
    body   = "locale:TIP_QUEUE_HEADER_BODY",
    anchor = "ANCHOR_BOTTOM",
}

R.MaterialsHeader = {
    title  = "locale:TIP_MATERIALS_HEADER_TITLE",
    body   = "locale:TIP_MATERIALS_HEADER_BODY",
    anchor = "ANCHOR_BOTTOM",
}

-- ===== Warning button recipes ===============================================
R.WarnResetConfig = {
    title  = "locale:TIP_WARN_RESET_CONFIG_TITLE",
    body   = "locale:TIP_WARN_RESET_CONFIG_BODY",
    anchor = "ANCHOR_BOTTOM",
}

R.WarnHardReset = {
    title  = "locale:TIP_WARN_HARD_RESET_TITLE",
    body   = "locale:TIP_WARN_HARD_RESET_BODY",
    anchor = "ANCHOR_BOTTOM",
}

R.WarnClearPins = {
    title  = "locale:TIP_WARN_CLEAR_PINS_TITLE",
    body   = "locale:TIP_WARN_CLEAR_PINS_BODY",
    anchor = "ANCHOR_BOTTOM",
}

-- ============================================================================
-- Composed recipe SCAFFOLDS (function-form, read per-row state stamps)
-- ============================================================================
-- Each recipe gates on expected stamp fields and returns nil if not stamped (pooled-row safety).
-- TODOs are placeholders; replace as each tab is migrated.

-- R1: Item row -- item-icon buttons, trophies, favorites, crate cells, picker cells.
-- stamp: row._itemID; optional row._hintKeys = {"shift_shopping", ...}
function R.ItemRow(self)
    if not self._itemID then return nil end
    local extras = {}
    if self._hintKeys then
        for _, key in ipairs(self._hintKeys) do
            local hint = H[key]
            if hint then
                extras[#extras + 1] = { text = hint, r = 0.5, g = 0.5, b = 0.5 }
            end
        end
    end
    return {
        itemID     = self._itemID,
        anchor     = "ANCHOR_RIGHT",
        extraLines = extras,
    }
end

-- R2: Decor row -- decor picker, house editor grid.
-- Custom (non-item) tooltip; source + expansion read live at hover from HousingCatalogObserver.
-- stamp: row._itemID, _name, _collected, _storedCount
-- Mouse-action hints shown on every decor row tooltip (same wording as the
-- decor header clickHints; resolved live so a locale switch repaints them).
local DECOR_ROW_HINTS = {
    leftText  = "locale:DECOR_HINT_LEFT",
    rightText = "locale:DECOR_HINT_RIGHT",
    shiftText = "locale:DECOR_HINT_SHIFT",
}

function R.DecorRow(self)
    if not self._itemID then return nil end
    local extras = {}

    -- Ownership breakdown (matches the Housing Companion editor tooltip
    -- "Owned: N (Placed: P, Storage: S)"), source, and expansion -- all read live
    -- from the catalog row at hover (fresher than a filter-time stamp). Counts are
    -- aggregate across dye variants (the 12.0.5 catalog API doesn't split them).
    local row = HDG.HousingCatalogObserver:GetRow(self._itemID)
    if row then
        local storage = row.quantity or 0  -- exception(boundary): catalog struct field sparse
        local placed  = row.numPlaced or 0  -- exception(boundary): catalog struct field sparse
        local redeem  = row.remainingRedeemable or 0  -- exception(boundary): catalog struct field sparse
        local owned   = storage + placed + redeem
        if owned > 0 then
            local parts = { ("Placed: %d"):format(placed), ("Storage: %d"):format(storage) }
            if redeem > 0 then parts[#parts + 1] = ("Redeemable: %d"):format(redeem) end
            extras[#extras + 1] = { text = ("Owned: %d (%s)"):format(owned, table.concat(parts, ", ")), r = 0.4, g = 0.9, b = 0.4 }
        else
            extras[#extras + 1] = { text = "Not collected", r = 0.85, g = 0.72, b = 0.35 }
        end
        local kind = row.sourceType and HDG.Constants.SOURCE_KIND_BY_DONOR[row.sourceType]
        if kind and kind.label then
            local line = kind.label
            if row.sourceName and row.sourceName ~= "" then
                line = line .. ": " .. row.sourceName
                if row.sourceDetail and row.sourceDetail ~= "" then
                    line = line .. " (" .. row.sourceDetail .. ")"
                end
            end
            extras[#extras + 1] = { text = line, r = 0.6, g = 0.78, b = 0.95 }
        end
        if row.expansion and row.expansion ~= "" and row.expansion ~= "?" then
            extras[#extras + 1] = { text = "Expansion: " .. row.expansion, r = 0.6, g = 0.6, b = 0.6 }
        end
    end

    -- Title: [icon] quality-colored name (custom, non-item tooltip -- no spam).
    local name = self._name or HDG.ItemNameResolver:ResolveName(self._itemID)
    local CI = _G.C_Item
    local q  = CI and CI.GetItemQualityByID and CI.GetItemQualityByID(self._itemID)  -- exception(boundary): nil uncached
    if q then
        local _, _, _, hex = CI.GetItemQualityColor(q)
        if hex then name = "|c" .. hex .. name .. "|r" end
    end
    local icon  = CI and CI.GetItemIconByID and CI.GetItemIconByID(self._itemID)  -- exception(boundary): nil uncached
    local title = icon and (("|T%d:16:16|t "):format(icon) .. name) or name

    HDG.TooltipEngine.AppendClickHints(extras, DECOR_ROW_HINTS)
    return {
        title      = title,
        anchor     = "ANCHOR_RIGHT",
        extraLines = extras,
    }
end

-- R3: Vendor item row -- VendorShoppingList, ZoneMode, AcqRows.
-- stamp: row._itemID; prefer pre-projected row._priceLines to avoid mid-paint vendor lookups.
function R.VendorItemRow(self)
    if not self._itemID then return nil end
    local extras = {}
    extras[#extras + 1] = { text = "TODO: price + currency lines", r = 0.5, g = 0.5, b = 0.5 }
    extras[#extras + 1] = { text = H.shift_shopping,                r = 0.5, g = 0.5, b = 0.5 }
    extras[#extras + 1] = { text = H.shift_waypoint,                r = 0.5, g = 0.5, b = 0.5 }
    return {
        itemID     = self._itemID,
        anchor     = "ANCHOR_RIGHT",
        extraLines = extras,
    }
end

-- R4: Recipe row -- Recipes tab, Mogul, Queue.
-- stamp: row._itemID, _recipeID, optional _qtyMult (queue rows)
-- Materials computed at hover time from StaticData.Professions + BagObserver.
function R.RecipeRow(self)
    if not self._itemID then return nil end
    local extras = {}

    -- Decor collection status (the item this recipe produces). Same green/amber as
    -- the decor row tooltip; catalog miss (non-decor recipe / uncached) skips the line.
    local crow = HDG.HousingCatalogObserver:GetRow(self._itemID)
    if crow then
        if crow.isOwned then
            extras[#extras + 1] = { text = "Decor: Collected",     r = 0.4,  g = 0.9,  b = 0.4  }
        else
            extras[#extras + 1] = { text = "Decor: Not collected", r = 0.85, g = 0.72, b = 0.35 }
        end
    end

    -- Recipe knowledge status. For alt-known recipes, NAME the alt: Mogul resolves
    -- the char from per-char knownRecipes (recipeID == spellID). Char name is the
    -- part of the "Name-Realm" key before the "-" (same as the Mogul plan rows).
    -- Falls back to the generic line if no scanner data has landed for the alt.
    local known = HDG.Store:GetState().account.recipes[self._itemID]
    if known and known.selfKnown then
        extras[#extras + 1] = { text = "Recipe: Known", r = 0.45, g = 0.82, b = 0.45 }
    elseif known and known.altKnown then
        -- Use the entry's spellID (NOT _recipeID): per-char knownRecipes + the
        -- scanner's altKnown bridge are keyed by spellID, and _recipeID is the
        -- ProfessionsDB recipe key (works for materials, but != the craft spell).
        local knowers = known.spellID and HDG.Mogul:AltsKnowingSpellID(known.spellID)
        local who     = knowers and #knowers > 0 and table.concat(knowers, ", ")
        extras[#extras + 1] = {
            text = who and ("Recipe: Known by " .. who) or "Recipe: Known by an alt",
            r = 0.85, g = 0.72, b = 0.35,
        }
    else
        extras[#extras + 1] = { text = "Recipe: Not learned", r = 0.78, g = 0.45, b = 0.45 }
    end

    -- Queue multiplier: queue rows stamp _qtyMult = queued count; recipe-list /
    -- goblin / mogul rows leave it nil (= 1). The materials below scale by it.
    local mult = self._qtyMult or 1
    if mult > 1 then
        extras[#extras + 1] = { text = ("Queued: %dx -- materials below are for all %d"):format(mult, mult), r = 0.6, g = 0.78, b = 0.95 }
    end

    -- Seller stock context (Deadi, Discord 2026-06-13): own-listings count from
    -- the AH-open ownedAuctions snapshot + the crafted item's bag count.
    -- Snapshot refreshes on AH open; the Goblin view surfaces freshness.
    local counts = HDG.BagObserver:GetCounts() or {}
    local mine = HDG.Store:GetState().account.prices.ownedAuctions[self._itemID]  -- top-level only: hover-time read
    if mine then
        extras[#extras + 1] = {
            text = ("Yours on AH: x%d"):format(mine.qty),
            r = 0.45, g = 0.82, b = 0.45,
        }
    end
    extras[#extras + 1] = {
        text = ("In bags: %d"):format(counts[self._itemID] or 0),  -- exception(nullable): sparse bag map; miss = 0
        r = 0.75, g = 0.75, b = 0.75,
    }

    -- Materials (have / need x qty), colored by sufficiency. VisitReagents
    -- yields the immediate reagents; bag counts come from the BagObserver
    -- fetch above.
    local recipe = self._recipeID and HDG.StaticData.Recipes:Get(self._recipeID)
    if recipe then
        local mats = {}
        HDG.StaticData.Recipes:VisitReagents(recipe, function(slot)
            if slot.itemID and slot.qty then
                -- Locale-correct reagent name (resolver first); baked slot.name is the fallback.
                -- Render-time resolve: a cold miss shows the placeholder, the next hover shows localized.
                local rn, resolved = HDG.ItemNameResolver:ResolveName(slot.itemID)
                mats[#mats + 1] = {
                    name = (resolved and rn) or slot.name or ("item " .. tostring(slot.itemID)),
                    have = counts[slot.itemID] or 0,
                    need = slot.qty * mult,
                }
            end
        end)
        if #mats > 0 then
            extras[#extras + 1] = { text = "Materials:", r = 0.75, g = 0.75, b = 0.75 }
            for i = 1, math.min(#mats, 8) do
                local m  = mats[i]
                local ok = m.have >= m.need
                extras[#extras + 1] = {
                    text = ("  %s  %d/%d"):format(m.name, m.have, m.need),
                    r = ok and 0.45 or 0.85, g = ok and 0.82 or 0.45, b = 0.45,
                }
            end
            if #mats > 8 then
                extras[#extras + 1] = { text = ("  +%d more"):format(#mats - 8), r = 0.6, g = 0.6, b = 0.6 }
            end
        end
    end

    -- Custom (non-item) tooltip: avoids third-party addon pile-on. Icon + quality-colored name.
    local name = self._name or HDG.ItemNameResolver:ResolveName(self._itemID)
    local CI = _G.C_Item
    local q  = CI and CI.GetItemQualityByID and CI.GetItemQualityByID(self._itemID)  -- exception(boundary): nil for uncached
    if q then
        local _, _, _, hex = CI.GetItemQualityColor(q)
        if hex then name = "|c" .. hex .. name .. "|r" end
    end
    -- Item icon to the LEFT of the name (texture escape accepts the fileID directly).
    local icon  = CI and CI.GetItemIconByID and CI.GetItemIconByID(self._itemID)  -- exception(boundary): nil for uncached
    local title = icon and (("|T%d:16:16|t "):format(icon) .. name) or name

    -- Goblin scanner rows stamp _clickHints; recipe-list / queue rows leave it nil (no hints).
    HDG.TooltipEngine.AppendClickHints(extras, self._clickHints)
    return {
        title      = title,
        anchor     = "ANCHOR_RIGHT",
        extraLines = extras,
    }
end

-- R5: Vendor location -- VSL vendor row, ZoneMode vendor row.
-- stamp: row._vendorName, optional row._coords = { x, y, mapID, zone }
function R.VendorLocation(self)
    if not self._vendorName then return nil end
    local extras = {}
    if self._coords then
        local zone = self._coords.zone or "Unknown zone"
        extras[#extras + 1] = {
            text = string.format("%s  (%.1f, %.1f)", zone, self._coords.x or 0, self._coords.y or 0),
            r = 0.7, g = 0.7, b = 0.7,
        }
    end
    extras[#extras + 1] = { text = H.shift_waypoint, r = 0.5, g = 0.5, b = 0.5 }
    return {
        title      = self._vendorName,
        anchor     = "ANCHOR_RIGHT",
        extraLines = extras,
    }
end

-- R6: Toggle -- pin, sort, mode, eye, view toggles.
-- Recipe-as-function reads state at hover time (not creation time, which goes stale).
-- stamp: row._stateLabel
function R.Toggle(self)
    if not self._stateLabel then return nil end
    return {
        title      = self._stateLabel,
        anchor     = "ANCHOR_RIGHT",
        extraLines = {
            { text = H.click_cycle_sort, r = 0.5, g = 0.5, b = 0.5 },
        },
    }
end

-- R7: Progress header -- sidebar headers, profession buttons.
-- stamp: row._headerName, optional _known, _total, _descLine
function R.ProgressHeader(self)
    if not self._headerName then return nil end
    local extras = {}
    if self._known and self._total then
        local pct = (self._total > 0) and math.floor(100 * self._known / self._total) or 0
        extras[#extras + 1] = {
            text = string.format("%d / %d (%d%%)", self._known, self._total, pct),
            r = 0.7, g = 0.7, b = 0.7,
        }
    end
    if self._descLine then
        extras[#extras + 1] = { text = self._descLine, r = 0.7, g = 0.7, b = 0.7 }
    end
    return {
        title      = self._headerName,
        anchor     = "ANCHOR_BOTTOM",
        extraLines = extras,
    }
end

-- R8: Profession status -- alts skill button, sidebar prof button.
-- stamp: row._profName, optional _stateLabel, _known, _total
-- TODO: wire alts knowers selector
function R.ProfessionStatus(self)
    if not self._profName then return nil end
    local extras = {}
    if self._stateLabel then
        extras[#extras + 1] = { text = self._stateLabel, r = 0.7, g = 0.7, b = 0.7 }
    end
    if self._known and self._total then
        extras[#extras + 1] = {
            text = string.format("%d / %d recipes known", self._known, self._total),
            r = 0.7, g = 0.7, b = 0.7,
        }
    end
    extras[#extras + 1] = { text = "TODO: knowers (Known by alt: N)", r = 0.5, g = 0.5, b = 0.5 }
    return {
        title      = self._profName,
        anchor     = "ANCHOR_RIGHT",
        extraLines = extras,
    }
end

-- R9: Material stock -- warehouse + recipes materials rows. Per-stash breakdown of
-- what you're holding (bags / bank / warband). Title-only (NO itemID/SetItemByID) so
-- other addons' item-data processors (TSM, Auctionator, ...) don't bleed in.
-- stamp: row._tipName, _tipBag, _tipBank, _tipWarband, _tipNeed
local STOCK_TIP_ATLAS = { bag = "ParagonReputation_Bag", bank = "Banker", warband = "warbands-icon" }
local function _stockStashLine(lines, key, label, count)
    if count > 0 then
        lines[#lines + 1] = {
            text  = "|A:" .. STOCK_TIP_ATLAS[key] .. ":14:14|a " .. label,
            right = tostring(count),
            r = 0.75, g = 0.75, b = 0.75,   -- inline: GameTooltip is outside the theme registry
        }
    end
end
function R.MaterialStock(self)
    local name = self._tipName
    if not name then return nil end
    local total = self._tipBag + self._tipBank + self._tipWarband
    local lines = { { text = "Your stock", right = total > 0 and tostring(total) or nil,
                      r = 1, g = 0.82, b = 0 } }   -- gold header + summed total
    _stockStashLine(lines, "bag",     "Bags",    self._tipBag)
    _stockStashLine(lines, "bank",    "Bank",    self._tipBank)
    _stockStashLine(lines, "warband", "Warband", self._tipWarband)
    if #lines == 1 then   -- header only -> nothing on hand anywhere
        lines[#lines + 1] = { text = "None on hand", r = 0.6, g = 0.6, b = 0.6 }
    end
    if self._tipNeed > 0 then
        lines[#lines + 1] = { text = "Needed by queue", right = tostring(self._tipNeed),
                              r = 0.75, g = 0.75, b = 0.75, rr = 0.95, rg = 0.55, rb = 0.45 }
    end
    return { title = name, extraLines = lines }
end

-- ============================================================================
-- Dynamic toggle recipes (function form -- read live state at hover)
-- ============================================================================

-- Zone "Show Collected" toggle. Reads state at hover time so text stays current.
function R.ZoneShowCollected()
    local showing = HDG.Store:GetState().session.ui.zoneScanner.showCollected
    return {
        title  = showing and "Showing collected decor" or "Hiding collected decor",
        body   = showing and "Click to hide decor you've already collected."
                          or  "Click to also show decor you've already collected.",
        anchor = "ANCHOR_RIGHT",
    }
end
