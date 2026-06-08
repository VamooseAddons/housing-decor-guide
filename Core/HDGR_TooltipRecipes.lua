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
    click_expand_collapse  = "Click to expand or collapse",
    click_navigate         = "Click to set a waypoint",
    click_scan             = "Click to refresh",
    click_confirm_craft    = "Click to confirm craft",
    click_copy_url         = "Click to copy URL",
    click_cycle_sort       = "Click to cycle sort order",
    click_ah_search        = "Click to search the auction house",
    click_open_profession  = "Click to open profession window",
    click_inspect          = "Click to inspect",
    left_apply             = "Left-click to apply",

    -- Shift+click
    shift_shopping     = "Shift-click to add to shopping list",
    shift_waypoint     = "Shift-click to set waypoint",
    shift_auctionator  = "Shift-click to send to Auctionator",
    shift_remove_one   = "Shift-click to remove one",
    shift_remove_all   = "Shift-click to remove all",

    -- Ctrl+click
    ctrl_queue = "Ctrl-click to queue",

    -- Right-click
    right_remove       = "Right-click to remove",
    right_auctionator  = "Right-click to send to Auctionator",
}

-- ============================================================================
-- Recipes
-- ============================================================================

HDG.TooltipRecipes = HDG.TooltipRecipes or {}

local R = HDG.TooltipRecipes
local H = HDG.TooltipHints

-- ===== Window chrome ========================================================

R.Close = {
    title  = "Close",
    anchor = "ANCHOR_BOTTOM",
}

-- Compartment / minimap buttons -- click hints inline (button-specific, not reusable).
R.AddonCompartment = {
    title      = "|cFFfcd34dHousing Decor Guide|r",
    body       = "Track and craft housing decor items",
    anchor     = "ANCHOR_RIGHT",
    extraLines = {
        { text = "Click: Toggle addon window", r = 0.7, g = 0.7, b = 0.7 },
    },
}

R.MinimapButton = {
    title      = "|cFFfcd34dHousing Decor Guide|r",
    anchor     = "ANCHOR_LEFT",   -- LibDBIcon-managed; engine override may apply
    extraLines = {
        { text = "Left-click: Toggle window",      r = 0.7, g = 0.7, b = 0.7 },
        { text = "Right-click: Open settings",     r = 0.7, g = 0.7, b = 0.7 },
        { text = "Drag: Reposition icon",          r = 0.7, g = 0.7, b = 0.7 },
    },
}

-- ===== Outreach (about pane) ================================================

R.Discord = {
    title  = "Discord",
    body   = "Join the Vamoose Discord community",
    anchor = "ANCHOR_RIGHT",
}

R.Coffee = {
    title  = "Buy me a coffee",
    body   = "Support the addon",
    anchor = "ANCHOR_RIGHT",
}

-- ===== Config sidebar checkboxes ============================================
R.ConfigDebugToggle    = { title = "Debug mode",  body = "Print debug breadcrumbs to chat" }
R.ConfigMinimapToggle  = { title = "Minimap icon", body = "Show / hide the minimap button" }
R.OpenDebugLog         = { title = "Open Debug Log", body = "Open the HDG log window (buffered debug trace; requires Debug Mode on to populate)" }
R.WowheadLink          = { title = "Wowhead", body = "Open this item's Wowhead page in your browser" }
R.ProjectsAddCrate     = { title = "Add Crate", body = "A crate holds one room's worth of decor. Adds it to the selected room." }
R.ProjectsDetachCrate  = { title = "Detach Crate", body = "Unlinks this crate from the room and moves it to the orphan bay (Projects -> Orphaned crates), where you can reattach it to another room. Nothing is deleted." }
R.ProjectsCaptureAll   = { title = "Capture all floors", body = "Captures every room on each floor of your house. NOTE: the game doesn't tell addons how your rooms connect, so HDG can't auto-arrange them -- after capturing, drag the rooms into their real layout yourself (rooms join where their doors touch)." }
R.LumberAutoShow       = { title = "Auto-show on harvest", body = "Pop the lumber tracker automatically when you harvest lumber. Turn off to keep it out of the way -- the Warehouse tab always has the numbers." }

-- Layouts tab actions (effect-focused -- what each does, not just the label).
R.LayoutLoad      = { title = "Load in Architect", body = "Open this layout in the Architect to view or edit it. Editing a what-if never changes your real house or the Live snapshot.", anchor = "ANCHOR_TOP" }
R.LayoutShare     = { title = "Share code", body = "Copy a shareable code of this layout's room plan (geometry only -- no decor). A friend pastes it into Import to recreate it in their own house.", anchor = "ANCHOR_TOP" }
R.LayoutImport    = { title = "Import layout", body = "Paste a shared layout code to add it as a new what-if. With more than one house, you pick which house it lands under.", anchor = "ANCHOR_BOTTOM" }
R.LayoutDuplicate = { title = "Duplicate", body = "Copy this layout into a new what-if you can redesign freely, leaving the original untouched.", anchor = "ANCHOR_TOP" }

-- ===== Mogul / Goblin TSM columns ==========================================
-- Registered unconditionally so Layout:Validate passes regardless of TSM load state.
R.GoblinTsmServer = { title = "Server", body = "Maps to TSM DBMinBuyout: the lowest current auction-house buyout on your realm." }
R.GoblinTsmMarket = { title = "Market", body = "Maps to TSM DBMarket: TSM's calculated market value for this item." }
R.GoblinTsmRegion = { title = "Region", body = "Maps to TSM DBRegionSaleAvg: the average sale price across your whole region." }
R.GoblinSaleRate  = { title = "Rate",   body = "Maps to TSM DBRegionSaleRate: how often this item sells region-wide (sold/day vs posted/day). Needs the TSM Desktop App." }
R.GoblinSoldPerDay = { title = "/Day",  body = "Maps to TSM DBRegionSoldPerDay: estimated units sold per day across your region. Needs the TSM Desktop App." }
R.GoblinAhQty     = { title = "#AH",    body = "Units currently listed on your realm's auction house. Populated by 'Refresh from AH'; shows '-' until you scan." }

-- ===== Mogul optimizer controls ============================================
-- Effect guidance (what the toggle does FOR you), not the mechanics. Kept short.
R.MogulModeProfit     = { title = "Profit",                  body = "Ranks crafts by the gold you'll make.",                                           anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulModeCollection = { title = "Collection",              body = "Ranks by decor you don't own yet -- completion over gold.",                         anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulViewChar       = { title = "This character",          body = "Plans from this character's known recipes and bags.",                              anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulViewAccount    = { title = "Account-wide",            body = "Pools recipes and materials across all your characters.",                          anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulOptOwned       = { title = "Use owned materials",     body = "Only plans crafts your current materials cover -- no shopping.",                    anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulOptBuy         = { title = "Buy materials from the AH", body = "Includes buying missing reagents; their AH cost is subtracted from the profit.",  anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulFrugal         = { title = "Frugal",                  body = "Favors lumber-light crafts so your wood stretches across more pieces.",             anchor = "ANCHOR_BOTTOMRIGHT" }
R.MogulSupplyImpact   = { title = "Supply impact",           body = "Accounts for prices dropping as you flood the market. Smooth% decays the price per copy sold; Cap limits how many you plan.", anchor = "ANCHOR_BOTTOMRIGHT" }

-- ===== Recipe list filters =================================================
R.RecipeFilterUnknown = { title = "Unknown", body = "Recipes no character on your account has learned.", anchor = "ANCHOR_BOTTOM" }
R.RedeemableTag       = { title = "Redeemable", body = "You own these -- they were auto-awarded to you (e.g. an achievement or quest reward); you've just never placed one. Place it once to claim a permanent copy. Until then it sits in your catalog as an unredeemed instance.", anchor = "ANCHOR_BOTTOM" }

-- ===== House-editor companion: mode tabs ===================================
R.CompanionStyles      = { title = "Your Styles",  body = "Place decor from the style sets you've saved.",                              anchor = "ANCHOR_BOTTOM" }
R.CompanionShopping    = { title = "Shopping",     body = "Place straight from your shopping lists.",                                   anchor = "ANCHOR_BOTTOM" }
R.CompanionSnapshots   = { title = "Snapshots",    body = "Re-place a saved layout to rebuild a room.",                                 anchor = "ANCHOR_BOTTOM" }
R.CompanionThemes      = { title = "Themes",       body = "Furnish a space from a ready-made room concept.",                            anchor = "ANCHOR_BOTTOM" }
R.CompanionCollections = { title = "Collections",  body = "Browse decor by category -- Recently Learned, Dyeable, and by placement cost.", anchor = "ANCHOR_BOTTOM" }
R.CompanionRecent      = { title = "Recent",       body = "Decor you've placed or removed this editing session.",                       anchor = "ANCHOR_BOTTOM" }

-- ===== Section headers / instructional ======================================
R.QueueHeader = {
    title  = "Queue",
    body   = "TODO: lift workflow description from HDG queue header tooltip.",
    anchor = "ANCHOR_BOTTOM",
}

R.MaterialsHeader = {
    title  = "Materials",
    body   = "TODO: lift workflow description from HDG materials panel header tooltip.",
    anchor = "ANCHOR_BOTTOM",
}

-- ===== Warning button recipes ===============================================
R.WarnResetConfig = {
    title  = "|cffff6060Reset all settings|r",
    body   = "This resets HDG's display options. Your tracked data is preserved.",
    anchor = "ANCHOR_BOTTOM",
}

R.WarnHardReset = {
    title  = "|cffff6060Hard reset all data|r",
    body   = "Wipes ALL HDG data: SavedVariables, queue, alts. Requires /reload.",
    anchor = "ANCHOR_BOTTOM",
}

R.WarnClearPins = {
    title  = "|cffff6060Clear all map pins|r",
    body   = "Removes every HDG pin from the world map. Pinned again on next refresh.",
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

    -- Knowledge status. For alt-known recipes, NAME the alt: Mogul resolves the
    -- char from per-char knownRecipes (recipeID == spellID). Char name is the
    -- part of the "Name-Realm" key before the "-" (same as the Mogul plan rows).
    -- Falls back to the generic line if no scanner data has landed for the alt.
    local known = HDG.Store:GetState().account.recipes[self._itemID]
    if known and known.selfKnown then
        extras[#extras + 1] = { text = "Learned",        r = 0.45, g = 0.82, b = 0.45 }
    elseif known and known.altKnown then
        -- Use the entry's spellID (NOT _recipeID): per-char knownRecipes + the
        -- scanner's altKnown bridge are keyed by spellID, and _recipeID is the
        -- ProfessionsDB recipe key (works for materials, but != the craft spell).
        local knowers = known.spellID and HDG.Mogul:AltsKnowingSpellID(known.spellID)
        local who     = knowers and #knowers > 0 and table.concat(knowers, ", ")
        extras[#extras + 1] = {
            text = who and ("Known by " .. who) or "Known by an alt",
            r = 0.85, g = 0.72, b = 0.35,
        }
    else
        extras[#extras + 1] = { text = "Not learned yet", r = 0.78, g = 0.45, b = 0.45 }
    end

    -- Queue multiplier: queue rows stamp _qtyMult = queued count; recipe-list /
    -- goblin / mogul rows leave it nil (= 1). The materials below scale by it.
    local mult = self._qtyMult or 1
    if mult > 1 then
        extras[#extras + 1] = { text = ("Queued: %dx -- materials below are for all %d"):format(mult, mult), r = 0.6, g = 0.78, b = 0.95 }
    end

    -- Materials (have / need x qty), colored by sufficiency. VisitBasicSlots
    -- yields the immediate reagents; bag counts come from the BagObserver.
    local db     = HDG.StaticData.Professions:GetAll()
    local recipe = self._recipeID and db and db[self._recipeID]
    if recipe then
        local counts, mats = HDG.BagObserver:GetCounts() or {}, {}
        HDG.StaticData.Professions:VisitBasicSlots(recipe, function(slot)
            if slot.itemID and slot.qty then
                mats[#mats + 1] = {
                    name = slot.name or HDG.ItemNameResolver:ResolveName(slot.itemID),
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
