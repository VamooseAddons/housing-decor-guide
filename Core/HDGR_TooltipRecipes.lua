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

-- Shopping list Buy All button.
R.BuyAll = {
    title  = "locale:SHOP_BUY_ALL",
    body   = "locale:SHOP_BUY_ALL_HINT",
    anchor = "ANCHOR_RIGHT",
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

-- Essence of Lumber chrome badge: state-aware. Owned -> account-wide total plus
-- a per-character breakdown (class-coloured, bank-stranded count called out,
-- alts flagged as last-login). None -> an educational blurb so the greyed glyph
-- is self-explaining. Computed at hover from the chrome.essenceBadge selector.
R.EssenceBadge = function()
    local sel = HDG.Selectors:Call("chrome.essenceBadge", HDG.Store:GetState(), {})
    local dim = HDG.Theme:ColorCode("text.dim")
    if not sel.owned then
        return { title = "Essence of Lumber", anchor = "ANCHOR_LEFT", extraLines = {
            { text = "None across your characters." },
            { text = dim .. "From the weekly neighborhood quest, or ~1% while harvesting lumber.|r" },
        } }
    end
    local extraLines = { { text = ("%d total across your characters"):format(sel.total) } }
    for _, e in ipairs(sel.perChar) do
        local hex  = HDG.Constants.CLASS_COLORS[e.classFile] or "ffffffff"  -- exception(nullable): classFile absent on a legacy record
        local name = "|c" .. hex .. e.name .. "|r"
        if e.bank > 0     then name = name .. dim .. ("  (%d in bank)|r"):format(e.bank) end
        if not e.isCurrent then name = name .. dim .. "  - last login|r" end
        extraLines[#extraLines + 1] = { text = name, right = tostring(e.count) }
    end
    return { title = "Essence of Lumber", anchor = "ANCHOR_LEFT", extraLines = extraLines }
end
R.LumberAutoShow       = { title = "locale:TIP_LUMBER_AUTO_SHOW_TITLE",      body = "locale:TIP_LUMBER_AUTO_SHOW_BODY" }
R.LumberGoal           = { title = "locale:TIP_LUMBER_GOAL_TITLE",           body = "locale:TIP_LUMBER_GOAL_BODY" }
R.BlueprintMeterRoom     = { title = "locale:TIP_BP_METER_ROOM",     anchor = "ANCHOR_TOP" }
R.BlueprintMeterInterior = { title = "locale:TIP_BP_METER_INTERIOR", anchor = "ANCHOR_TOP" }
R.BlueprintMeterExterior = { title = "locale:TIP_BP_METER_EXTERIOR", anchor = "ANCHOR_TOP" }
R.VendorJump           = { title = "locale:TIP_VENDOR_JUMP_TITLE",           body = "locale:TIP_VENDOR_JUMP_BODY",    anchor = "ANCHOR_RIGHT" }
R.ZoneMapOpen          = { title = "locale:TIP_ZONE_MAP_TITLE",              body = "locale:TIP_ZONE_MAP_BODY" }

-- Layouts tab actions (effect-focused -- what each does, not just the label).
R.LayoutLoad      = { title = "locale:TIP_LAYOUT_LOAD_TITLE",      body = "locale:TIP_LAYOUT_LOAD_BODY",      anchor = "ANCHOR_TOP" }
R.LayoutShare     = { title = "locale:TIP_LAYOUT_SHARE_TITLE",     body = "locale:TIP_LAYOUT_SHARE_BODY",     anchor = "ANCHOR_TOP" }
R.LayoutImport    = { title = "locale:TIP_LAYOUT_IMPORT_TITLE",    body = "locale:TIP_LAYOUT_IMPORT_BODY",    anchor = "ANCHOR_BOTTOM" }
R.LayoutDuplicate = { title = "locale:TIP_LAYOUT_DUPLICATE_TITLE", body = "locale:TIP_LAYOUT_DUPLICATE_BODY", anchor = "ANCHOR_TOP" }

-- Blueprints tab (12.1) -- effect-focused.
R.BlueprintInspect     = { title = "locale:TIP_BP_INSPECT_TITLE",     body = "locale:TIP_BP_INSPECT_BODY",     anchor = "ANCHOR_TOP" }
R.BlueprintTargetHouse = { title = "locale:TIP_BP_TARGET_TITLE",      body = "locale:TIP_BP_TARGET_BODY",      anchor = "ANCHOR_BOTTOM" }
R.BlueprintCopyCode    = { title = "locale:TIP_BP_COPY_TITLE",        body = "locale:TIP_BP_COPY_BODY",        anchor = "ANCHOR_TOP" }
R.BlueprintRename      = { title = "locale:TIP_BP_RENAME_TITLE",      body = "locale:TIP_BP_RENAME_BODY",      anchor = "ANCHOR_TOP" }
R.BlueprintMissingOnly = { title = "locale:TIP_BP_MISSING_TITLE",     body = "locale:TIP_BP_MISSING_BODY",     anchor = "ANCHOR_TOP" }
R.BlueprintRoute       = { title = "locale:TIP_BP_ROUTE_TITLE",       body = "locale:TIP_BP_ROUTE_BODY",       anchor = "ANCHOR_TOP" }
R.BlueprintImportSet   = { title = "locale:TIP_BP_SET_TITLE",         body = "locale:TIP_BP_SET_BODY",         anchor = "ANCHOR_TOP" }
R.BlueprintArchitect   = { title = "locale:TIP_BP_ARCHITECT_TITLE",   body = "locale:TIP_BP_ARCHITECT_BODY",   anchor = "ANCHOR_TOP" }
R.BlueprintSave        = { title = "locale:TIP_BP_SAVE_TITLE",        body = "locale:TIP_BP_SAVE_BODY",        anchor = "ANCHOR_TOP" }
R.BlueprintLink        = { title = "locale:TIP_BP_LINK_TITLE",        body = "locale:TIP_BP_LINK_BODY",        anchor = "ANCHOR_TOP" }
R.BlueprintImportHouse = { title = "locale:TIP_BP_IMPORT_HOUSE_TITLE", body = "locale:TIP_BP_IMPORT_HOUSE_BODY", anchor = "ANCHOR_TOP" }

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

R.RedeemableTag       = { title = "locale:TIP_REDEEMABLE_TAG_TITLE",         body = "locale:TIP_REDEEMABLE_TAG_BODY",         anchor = "ANCHOR_BOTTOM" }

-- ===== House-editor companion: mode tabs ===================================
R.CompanionStyles      = { title = "locale:TIP_COMPANION_STYLES_TITLE",      body = "locale:TIP_COMPANION_STYLES_BODY",      anchor = "ANCHOR_BOTTOM" }
R.CompanionRooms       = { title = "locale:TIP_COMPANION_ROOMS_TITLE",       body = "locale:TIP_COMPANION_ROOMS_BODY",       anchor = "ANCHOR_BOTTOM" }
R.CompanionSnapshots   = { title = "locale:TIP_COMPANION_SNAPSHOTS_TITLE",   body = "locale:TIP_COMPANION_SNAPSHOTS_BODY",   anchor = "ANCHOR_BOTTOM" }
R.CompanionThemes      = { title = "locale:TIP_COMPANION_THEMES_TITLE",      body = "locale:TIP_COMPANION_THEMES_BODY",      anchor = "ANCHOR_BOTTOM" }
R.CompanionCollections = { title = "locale:TIP_COMPANION_COLLECTIONS_TITLE", body = "locale:TIP_COMPANION_COLLECTIONS_BODY", anchor = "ANCHOR_BOTTOM" }
R.CompanionRecent      = { title = "locale:TIP_COMPANION_RECENT_TITLE",      body = "locale:TIP_COMPANION_RECENT_BODY",      anchor = "ANCHOR_BOTTOM" }




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

-- [icon] quality-colored name for a custom (non-item) tooltip title. Quality
-- color + icon come from C_Item; both are nil for an uncached item. Shared by
-- the Decor and Recipe row recipes (identical construction).
local function _buildIconQualityTitle(itemID, name)
    name = name or HDG.ItemNameResolver:ResolveName(itemID)
    local CI = _G.C_Item
    local q  = CI and CI.GetItemQualityByID and CI.GetItemQualityByID(itemID)  -- exception(boundary): nil for uncached
    if q then
        local _, _, _, hex = CI.GetItemQualityColor(q)
        if hex then name = "|c" .. hex .. name .. "|r" end
    end
    local icon = CI and CI.GetItemIconByID and CI.GetItemIconByID(itemID)  -- exception(boundary): nil for uncached
    return icon and (("|T%d:16:16|t "):format(icon) .. name) or name
end

-- Ownership breakdown ("Owned: N (Placed: P, Storage: S[, Redeemable: R])" /
-- "Not collected"), matching the Housing Companion editor tooltip. Counts are
-- aggregate across dye variants (the 12.0.5 catalog API doesn't split them).
local function _appendDecorOwnership(extras, row)
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
end

-- Source line(s). Decor is often sold by MORE than one vendor -- list every
-- vendor the way the House Editor / native-catalog tooltip does (ReganB
-- 2026-07-05: browser tooltip showed 1 of the Nightborne Lantern's 2 vendors).
-- Non-vendor sources keep a single line.
local function _appendDecorSource(extras, row)
    local kind = row.sourceType and HDG.Constants.SOURCE_KIND_BY_DONOR[row.sourceType]
    if not (kind and kind.label) then return end
    if kind.key == "VENDOR" and row.vendors and #row.vendors > 0 then
        for _, v in ipairs(row.vendors) do
            local line = kind.label .. ": " .. v.name
            if v.zone and v.zone ~= "" then line = line .. " (" .. v.zone .. ")" end
            extras[#extras + 1] = { text = line, r = 0.6, g = 0.78, b = 0.95 }
        end
    else
        local line = kind.label
        if row.sourceName and row.sourceName ~= "" then
            line = line .. ": " .. row.sourceName
            if row.sourceDetail and row.sourceDetail ~= "" then
                line = line .. " (" .. row.sourceDetail .. ")"
            end
        end
        extras[#extras + 1] = { text = line, r = 0.6, g = 0.78, b = 0.95 }
    end
end

-- Expansion line (skips "" / "?" placeholders).
local function _appendDecorExpansion(extras, row)
    if row.expansion and row.expansion ~= "" and row.expansion ~= "?" then
        extras[#extras + 1] = { text = "Expansion: " .. row.expansion, r = 0.6, g = 0.6, b = 0.6 }
    end
end

function R.DecorRow(self)
    if not self._itemID then return nil end
    local extras = {}

    -- Ownership, source, and expansion -- all read live from the catalog row at
    -- hover (fresher than a filter-time stamp).
    local row = HDG.HousingCatalogObserver:GetRow(self._itemID)
    if row then
        _appendDecorOwnership(extras, row)
        _appendDecorSource(extras, row)
        _appendDecorExpansion(extras, row)
    end

    HDG.TooltipEngine.AppendClickHints(extras, DECOR_ROW_HINTS)
    return {
        title      = _buildIconQualityTitle(self._itemID, self._name),
        anchor     = "ANCHOR_RIGHT",
        extraLines = extras,
    }
end


-- Decor collection status of the item this recipe produces. Same green/amber as
-- the decor row tooltip; catalog miss (non-decor recipe / uncached) skips the line.
local function _appendRecipeDecorStatus(extras, itemID)
    local crow = HDG.HousingCatalogObserver:GetRow(itemID)
    if not crow then return end
    if crow.isOwned then
        extras[#extras + 1] = { text = "Decor: Collected",     r = 0.4,  g = 0.9,  b = 0.4  }
    else
        extras[#extras + 1] = { text = "Decor: Not collected", r = 0.85, g = 0.72, b = 0.35 }
    end
end

-- Recipe knowledge status. For alt-known recipes, NAME the alt: Mogul resolves
-- the char from per-char knownRecipes (keyed by spellID, NOT the recipe key).
-- Falls back to the generic line if no scanner data has landed for the alt.
local function _appendRecipeKnowledge(extras, itemID)
    local known = HDG.Store:GetState().account.recipes[itemID]
    if known and known.selfKnown then
        extras[#extras + 1] = { text = "Recipe: Known", r = 0.45, g = 0.82, b = 0.45 }
    elseif known and known.altKnown then
        local knowers = known.spellID and HDG.Mogul:AltsKnowingSpellID(known.spellID)
        local who     = knowers and #knowers > 0 and table.concat(knowers, ", ")
        extras[#extras + 1] = {
            text = who and ("Recipe: Known by " .. who) or "Recipe: Known by an alt",
            r = 0.85, g = 0.72, b = 0.35,
        }
    else
        extras[#extras + 1] = { text = "Recipe: Not learned", r = 0.78, g = 0.45, b = 0.45 }
    end
end

-- Queue multiplier note + seller stock context (Deadi, Discord 2026-06-13):
-- own-listings count from the AH-open ownedAuctions snapshot + bag count.
local function _appendRecipeStockContext(extras, itemID, counts, mult)
    if mult > 1 then
        extras[#extras + 1] = { text = ("Queued: %dx -- materials below are for all %d"):format(mult, mult), r = 0.6, g = 0.78, b = 0.95 }
    end
    local mine = HDG.Store:GetState().account.prices.ownedAuctions[itemID]  -- top-level only: hover-time read
    if mine then
        extras[#extras + 1] = { text = ("Yours on AH: x%d"):format(mine.qty), r = 0.45, g = 0.82, b = 0.45 }
    end
    extras[#extras + 1] = {
        text = ("In bags: %d"):format(counts[itemID] or 0),  -- exception(nullable): sparse bag map; miss = 0
        r = 0.75, g = 0.75, b = 0.75,
    }
end

-- Materials (have / need x qty), colored by sufficiency. VisitReagents yields
-- the immediate reagents; bag counts come from the BagObserver fetch. Locale-
-- correct reagent name (resolver first); baked slot.name is the fallback.
local function _buildRecipeRowMaterials(extras, recipe, counts, mult)
    local mats = {}
    HDG.StaticData.Recipes:VisitReagents(recipe, function(slot)
        if slot.itemID and slot.qty then
            local rn, resolved = HDG.ItemNameResolver:ResolveName(slot.itemID)
            mats[#mats + 1] = {
                name = (resolved and rn) or slot.name or ("item " .. tostring(slot.itemID)),
                have = counts[slot.itemID] or 0,
                need = slot.qty * mult,
            }
        end
    end)
    if #mats == 0 then return end
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

-- R4: Recipe row -- Recipes tab, Mogul, Queue.
-- stamp: row._itemID, _recipeID, optional _qtyMult (queue rows), _clickHints (goblin)
-- Materials computed at hover time from StaticData.Professions + BagObserver.
function R.RecipeRow(self)
    if not self._itemID then return nil end
    local extras = {}
    local counts = HDG.BagObserver:GetCounts() or {}
    local mult   = self._qtyMult or 1  -- queue rows stamp count; other rows leave nil (= 1)

    _appendRecipeDecorStatus(extras, self._itemID)
    _appendRecipeKnowledge(extras, self._itemID)
    _appendRecipeStockContext(extras, self._itemID, counts, mult)
    local recipe = self._recipeID and HDG.StaticData.Recipes:Get(self._recipeID)
    if recipe then _buildRecipeRowMaterials(extras, recipe, counts, mult) end

    -- Goblin scanner rows stamp _clickHints; recipe-list / queue rows leave it nil (no hints).
    HDG.TooltipEngine.AppendClickHints(extras, self._clickHints)
    return {
        title      = _buildIconQualityTitle(self._itemID, self._name),
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
