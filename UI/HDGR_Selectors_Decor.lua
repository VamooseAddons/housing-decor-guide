-- HDG.Selectors -- Decor tab
-- ============================================================================
-- decor.* selectors: catalog, filter chain, selection, variants, aggregates.
-- Helpers stay file-local.

HDG = HDG or {}
local Selectors = HDG.Selectors

-- ============================================================================
-- Decor browser selectors
-- ============================================================================
-- decor.allItems -> unfiltered sorted list from HousingCatalogObserver
-- decor.filterQuery -> current search query
-- decor.items -> post-filter list (scrollbox binds here)
-- decor.headerLabel -> "OWNED/TOTAL (PCT%)" + optional "* N shown" tail
--
-- iconTexture is the catalog's rendered preview icon (NOT GetItemIconByID).
Selectors:Register("decor.allItems", {
    reads    = {"account.collection.ownedDecorIDs", "session.catalog.sweepGeneration"},
    memoized = true,
    fn = function(state, ctx)
        if not HDG.HousingCatalogObserver:IsReady() then return {} end
        local items = {}
        HDG.HousingCatalogObserver:IterateRows(function(itemID, row)
            local iconTex, iconAtl = HDG.Format.CoerceIconPair(
                row.iconTexture, row.iconAtlas)
            items[#items + 1] = {
                itemID                = itemID,
                decorID               = row.decorID,
                name                  = row.name,
                -- exp uses baked row.expansion; "?" sentinel preserved for label selectors.
                exp                   = row.expansion or "?",
                canCustomize          = row.canCustomize,
                -- Baked per-owned-dyed-variant list; decor.items expands into variant rows.
                dyedVariants          = row.dyedVariants,
                isOwned               = row.isOwned,
                numStored             = row.quantity,
                numPlaced             = row.numPlaced,
                placementCost         = row.placementCost,
                isAllowedIndoors      = row.isAllowedIndoors,
                isAllowedOutdoors     = row.isAllowedOutdoors,
                iconTexture           = iconTex,
                iconAtlas             = iconAtl,
                firstAcquisitionBonus = row.firstAcquisitionBonus,
            }
        end)
        table.sort(items, function(a, b)
            if a.name == b.name then return (a.itemID or 0) < (b.itemID or 0) end
            return (a.name or "") < (b.name or "")
        end)
        return items
    end,
})

-- O(1) lookup index over decor.allItems. Memoized; invalidates with decor.allItems.
Selectors:Register("decor.allItemsByID", {
    memoized = true,
    calls    = {"decor.allItems"},
    fn = function(state, ctx)
        local list = Selectors:Call("decor.allItems", state, ctx)
        local out = {}
        for _, row in ipairs(list) do
            if row.itemID then out[row.itemID] = row end
        end
        return out
    end,
})

-- Current search query from session state. Defaults to "" (callers need no nil-guard).
Selectors:Register("decor.filterQuery", {
    reads = {"session.ui.decor.searchQuery"},
    fn = function(state, ctx)
        local decor = state.session.ui.decor
        return decor.searchQuery or ""
    end,
})

-- (decor.activeProfessions retired -- profession filtering lives in the tag-row
--  system under topFilter='crafted'; state slot + chips had no consumers.)

-- Shown items: allItems through every active filter (AND-composed).
-- Filter axes: search query, top-filter bucket, active tag, onlyUncollected, onlyStored.
-- Data-state gates (catalog Section B):
--   hasItems: catalog ready AND filtered list non-empty -> show list.
--   isBlank:  catalog ready AND filtered list empty     -> "no results".
Selectors:Register("decor.hasItems", {
    calls = { "catalog.isReady", "decor.items" },
    fn = function(state, ctx)
        if not Selectors:Call("catalog.isReady", state, ctx) then return false end
        return #Selectors:Call("decor.items", state, ctx) > 0
    end,
})
Selectors:Register("decor.isBlank", {
    calls = { "catalog.isReady", "decor.items" },
    fn = function(state, ctx)
        if not Selectors:Call("catalog.isReady", state, ctx) then return false end
        return #Selectors:Call("decor.items", state, ctx) == 0
    end,
})

-- ===== decor.items row helpers ==============================================
-- Per-item work split into three pure helpers; `f` bundles resolved predicates
-- + filter scalars so each helper takes one context arg.

-- Filter gate. f.* predicates are closure-returning selectors (always functions).
local function _decorRowPasses(item, f)
    local id = item.itemID
    if f.needle and not item.name:lower():find(f.needle, 1, true) then return false end
    if not f.matchTag(id) then return false end
    if f.onlyUncollected and f.isCollected(id) then return false end
    if f.onlyStored and not f.isStored(id) then return false end
    return true
end

-- Shallow-copy the shared (memoized) row before stamping to avoid mutating the cache.
local function _stampDecorRow(item, f)
    local id = item.itemID
    local stamped = {}
    for k, v in pairs(item) do stamped[k] = v end
    stamped.isFavorite       = f.isFavorite(id)
    stamped.craftableState   = f.craftableState(id)
    stamped.isCollected      = f.isCollected(id)
    stamped.inStoredMode     = f.onlyStored == true
    stamped.destroyableCount = f.destroyableCount(id)
    return stamped
end

-- Append base row then one row per owned dyed variant. Under "Dyed" tag the
-- undyed base is suppressed. variantKey (itemID:variant) is pool + selection
-- identity. Each variant carries its own dv.numStored (not the aggregate base count).
local function _emitDecorRows(out, stamped, activeTag)
    local id = stamped.itemID
    local dyedVariants = stamped.dyedVariants
    local hasDyed = dyedVariants and #dyedVariants > 0
    if not (activeTag == "Dyed" and hasDyed) then
        stamped.variantKey = tostring(id) .. ":base"
        out[#out + 1] = stamped
    end
    if not hasDyed then return end
    for _, dv in ipairs(dyedVariants) do
        local vrow = {}
        for k, v in pairs(stamped) do vrow[k] = v end
        vrow.isVariantRow       = true
        vrow.variantIdentifier  = dv.variantIdentifier
        vrow.variantKey         = tostring(id) .. ":" .. tostring(dv.variantIdentifier)
        vrow.dyeColorIDs        = dv.dyeColorIDs
        vrow.dyeColorsByChannel = dv.dyeColorsByChannel
        vrow.numStored          = dv.numStored
        vrow.destroyableCount   = dv.numStored
        out[#out + 1] = vrow
    end
end

Selectors:Register("decor.items", {
    -- Memoized: decor.headerLabel calls into us for "shown N", which would
    -- double-walk ~2000 items per dispatch without caching.
    memoized = true,
    calls = {
        "decor.allItems",
        "decor.filterQuery",
        "decor.onlyUncollected",
        "decor.onlyStored",
        "decor.matchesTag",
        "decor.isCollected",
        "decor.isStored",
        "decor.activeTag",
        "decor.destroyableCount",
        -- isFavorite + craftableState called directly in fn -> declared here per
        -- accurate-calls invariant. Their paths also reach via matchesTag, but
        -- direct calls must still be declared.
        "decor.isFavorite",
        "decor.craftableState",
        -- decor.selectedItemID retired: selection highlight owned by
        -- SelectionBehaviorMixin; clicks no longer invalidate the items list.
    },
    fn = function(state, ctx)
        local all = Selectors:Call("decor.allItems",   state, ctx)
        local q   = Selectors:Call("decor.filterQuery", state, ctx)
        -- Resolve all per-item predicates once (not per row) and bundle into `f`.
        local f = {
            onlyUncollected  = Selectors:Call("decor.onlyUncollected",  state, ctx),
            onlyStored       = Selectors:Call("decor.onlyStored",       state, ctx),
            matchTag         = Selectors:Call("decor.matchesTag",       state, ctx),
            isCollected      = Selectors:Call("decor.isCollected",      state, ctx),
            isStored         = Selectors:Call("decor.isStored",         state, ctx),
            activeTag        = Selectors:Call("decor.activeTag",        state, ctx),
            isFavorite       = Selectors:Call("decor.isFavorite",       state, ctx),
            craftableState   = Selectors:Call("decor.craftableState",   state, ctx),
            destroyableCount = Selectors:Call("decor.destroyableCount", state, ctx),
            needle           = q ~= "" and q:lower() or nil,
        }

        local out = {}
        for _, item in ipairs(all) do
            if _decorRowPasses(item, f) then
                _emitDecorRows(out, _stampDecorRow(item, f), f.activeTag)
            end
        end

        -- Stored mode: most-cluttering first (destroyable count desc, name asc).
        if f.onlyStored then
            table.sort(out, function(a, b)
                local da, db = a.destroyableCount or 0, b.destroyableCount or 0  -- exception(boundary): sparse struct field
                if da ~= db then return da > db end
                return (a.name or "") < (b.name or "")
            end)
        end
        return out
    end,
})

-- Decor selection. Detail pane + model preview bind through this chain.
Selectors:Register("decor.selectedItemID", {
    memoized = true,
    reads = {"session.ui.decor.selectedItemID", "session.staticData.tick"},
    fn = function(state, ctx)
        local d = state.session.ui.decor
        return d.selectedItemID or nil
    end,
})
-- Which variant row is selected ("itemID:variantIdentifier" or "itemID:base").
-- Drives list highlight + dyed model preview.
Selectors:Register("decor.selectedVariantKey", {
    memoized = true,
    reads = {"session.ui.decor.selectedVariantKey"},
    fn = function(state, ctx)
        return state.session.ui.decor.selectedVariantKey or nil
    end,
})

-- Observer is primary. Returns nil while catalog loads (layout shows loading panel).
Selectors:Register("decor.selectedItem", {
    memoized = true,
    calls = {"decor.selectedItemID"},
    reads = {"session.catalog.sweepGeneration"},
    fn = function(state, ctx)
        local id = Selectors:Call("decor.selectedItemID", state, ctx)
        if not id then return nil end
        local row = HDG.HousingCatalogObserver:GetRow(id)
        if not row then return nil end  -- catalog cold or item not in catalog
        -- Vendor-first priority for sourceType: the detail panel surfaces vendor
        -- name/zone via sourceName/sourceDetail (distinct from _bakeSourceTypes'
        -- quest-first priority). Per-surface composition at the selector level.
        local firstVendor = row.vendors and row.vendors[1]
        local sourceType =
              (firstVendor and 5)                                 -- VENDOR (highest priority for this surface)
           or (row.achievement and 1)                             -- ACHIEVEMENT
           or (row.quest and 2)                                   -- QUEST
           or (row.recipe and 6)                                  -- CRAFTED (recipe DB canonical)
           or 0                                                   -- truly unknown
        return {
            itemID        = id,
            decorID       = row.decorID,
            name          = row.name or "Unknown",
            profession    = (row.recipe and row.recipe.profession) or "?",
            expansion     = row.expansion or "?",
            sourceType    = sourceType,
            sourceName    = (firstVendor and firstVendor.name) or "",
            sourceDetail  = (firstVendor and firstVendor.zone) or "",
            sourceTags    = row.sourceTags,   -- full baked tag list for the detail chip strip
            canCustomize  = row.canCustomize or false,
            isOwned       = row.isOwned or false,
            numStored     = row.quantity or 0,  -- exception(boundary): catalog struct field sparse
            categoryName             = row.categoryName,
            subcategoryName          = row.subcategoryName,
            isUniqueTrophy           = row.isUniqueTrophy or false,
            isAllowedIndoors         = row.isAllowedIndoors,
            isAllowedOutdoors        = row.isAllowedOutdoors,
            placementCost            = row.placementCost or 0,  -- exception(boundary): catalog struct field sparse
            numPlaced                = row.numPlaced or 0,  -- exception(boundary): catalog struct field sparse
            destroyableInstanceCount = row.destroyableInstanceCount or 0,  -- exception(boundary): catalog struct field sparse
            firstAcquisitionBonus    = row.firstAcquisitionBonus or 0,  -- exception(boundary): catalog struct field sparse
            dataTagsByID             = row.dataTagsByID,
            variants                 = row.variants,
            entryID                  = row.entryID,
        }
    end,
})

-- True when decor.selectedItem resolves to a non-nil record (e.g. Cart+ button gate).
Selectors:Register("decor.hasSelectedItem", {
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        return Selectors:Call("decor.selectedItem", state, ctx) ~= nil
    end,
})

Selectors:Register("decor.selectedItem.name", {
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        return v and v.name or "Click an item"
    end,
})
-- Profession line. Empty string for non-crafted items so the widget collapses.
-- Prefers sourceName (expansion-prefixed, e.g. "Draenor Engineering (80)") over
-- raw recipe profession when present.
Selectors:Register("decor.selectedItem.profession", {
    -- account.config.scheme: this selector bakes Theme color codes into
    -- the returned string, so it must re-run when the scheme switches.
    reads = {"account.config.scheme"},
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        if not v then return "" end
        if v.sourceType ~= 6 then return "" end           -- 6 = CRAFTED
        local profName = (v.sourceName ~= "" and v.sourceName ~= "Crafted") and v.sourceName
                         or (v.profession ~= "?" and v.profession)
        if not profName then return "" end
        local accent = HDG.Theme:ColorCode("semantic.accent")
        local known  = HDG.Theme:GetTextStateColorToken("known_self")
        return string.format("%sProfession:|r %s%s|r", accent, known, profName)
    end,
})
Selectors:Register("decor.selectedItem.expansion", {
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        if not v or not v.expansion or v.expansion == "?" then return "" end
        return "Expansion: " .. v.expansion
    end,
})
Selectors:Register("decor.selectedItem.itemID", {
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        return v and ("itemID: " .. tostring(v.itemID)) or ""
    end,
})

-- Source label: chip-style [VEND] / [QST] / [PROF] + name + "(detail)".
-- Consistent with sourceLine rendering across every detail-panel source surface.
Selectors:Register("decor.selectedItem.sourceLabel", {
    reads = {"account.config.scheme"},
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        if not v then return "" end
        -- All source chips from baked sourceTags (same as GateChips in row factories).
        -- Falls back to primary-donor chip for items with no baked tags.
        local chip = HDG.DecorFormat:GateChips(v)
        if chip == "" then
            local kind = HDG.Constants.SOURCE_KIND_BY_DONOR[v.sourceType]
            chip = (kind and HDG.Format.SourceChip(kind.key)) or ""
        end
        local pieces = (chip ~= "") and { chip } or {}
        if v.sourceName and v.sourceName ~= "" then
            pieces[#pieces + 1] = v.sourceName
        end
        if v.sourceDetail and v.sourceDetail ~= "" and v.sourceDetail ~= v.sourceName then
            pieces[#pieces + 1] = "(" .. v.sourceDetail .. ")"
        end
        -- chip alone is fine when no name/detail
        return table.concat(pieces, "  ")
    end,
})

-- Combined Collected / placement status line.
-- Collection segment: DecorFormat:Collection (ownership + stored + placed).
-- Placement segment: row.placementLabel (baked at BuildRow). +XP chip when applicable.
Selectors:Register("decor.selectedItem.statusLabel", {
    reads = {"account.config.scheme", "session.catalog.sweepGeneration"},
    calls = {"decor.selectedItemID"},
    fn = function(state, ctx)
        local id = Selectors:Call("decor.selectedItemID", state, ctx)
        if not id then return "" end
        local row = HDG.HousingCatalogObserver:GetRow(id)
        if not row then return "" end
        local F      = HDG.DecorFormat
        local dimCC  = HDG.Theme:ColorCode("text.dim")
        local successCC = HDG.Theme:ColorCode("semantic.success")
        local textCC = HDG.Theme:ColorCode("text.primary")

        local statusSegment = F:Collection(row)
        -- Append +XP chip for not-yet-collected items with a first-acquisition bonus.
        if (not row.isOwned) and row.bonusXpLabel then
            statusSegment = statusSegment .. "  " .. dimCC .. "(|r" ..
                successCC .. row.bonusXpLabel .. "|r" .. dimCC .. ")|r"
        end

        -- Placement segment (baked label includes the budget icon).
        local placementSegment = ""
        if row.placementLabel ~= "" then
            placementSegment = "   " .. textCC .. row.placementLabel .. "|r"
        end

        return statusSegment .. placementSegment
    end,
})

-- Category breadcrumb + size tag + optional trophy marker.
-- Reads row.categoryLabel + row.sizeLabel (baked at BuildRow).
Selectors:Register("decor.selectedItem.categoryLabel", {
    reads = {"account.config.scheme", "session.catalog.sweepGeneration"},
    calls = {"decor.selectedItemID"},
    fn = function(state, ctx)
        local id = Selectors:Call("decor.selectedItemID", state, ctx)
        if not id then return "" end
        local row = HDG.HousingCatalogObserver:GetRow(id)
        if not row or not row.categoryLabel or row.categoryLabel == "" then return "" end
        local accentCC  = HDG.Theme:ColorCode("semantic.accent")
        local textCC    = HDG.Theme:ColorCode("text.primary")
        local dimCC     = HDG.Theme:ColorCode("text.dim")
        local warningCC = HDG.Theme:ColorCode("semantic.warning")

        local line = accentCC .. row.categoryLabel .. "|r"
        if row.sizeLabel and row.sizeLabel ~= "" then
            line = line .. dimCC .. "  -  |r" .. textCC .. row.sizeLabel .. "|r"
        end
        if row.isUniqueTrophy then
            line = line .. "  " .. warningCC .. "Trophy|r"
        end
        return line
    end,
})

-- Tags line (Styles + Factions, baked as row.tagsLabel at BuildRow).
Selectors:Register("decor.selectedItem.tagsLabel", {
    reads = {"account.config.scheme", "session.catalog.sweepGeneration"},
    calls = {"decor.selectedItemID"},
    fn = function(state, ctx)
        local id = Selectors:Call("decor.selectedItemID", state, ctx)
        if not id then return "" end
        local row = HDG.HousingCatalogObserver:GetRow(id)
        if not row or not row.tagsLabel or row.tagsLabel == "" then return "" end
        local accentCC = HDG.Theme:ColorCode("semantic.accent")
        local knownCC  = HDG.Theme:GetTextStateColorToken("known_self")
        return accentCC .. "Tags:|r " .. knownCC .. row.tagsLabel .. "|r"
    end,
})

-- Expansion label: baked at BuildRow as row.expansionLabel (Palette is scheme-invariant).
Selectors:Register("decor.selectedItem.headerExpansion", {
    reads = {"session.catalog.sweepGeneration"},
    calls = {"decor.selectedItemID"},
    fn = function(state, ctx)
        local id = Selectors:Call("decor.selectedItemID", state, ctx)
        if not id then return "" end
        local row = HDG.HousingCatalogObserver:GetRow(id)
        return (row and row.expansionLabel) or ""
    end,
})

-- Destroyable flag for the destroy-button widget (visibility / enabled).
-- True when the catalog row reports at least one destroyable instance.
Selectors:Register("decor.selectedItem.destroyable", {
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        return v and (v.destroyableInstanceCount or 0) > 0 or false
    end,
})

-- Destroy button: only show when Stored filter is active AND a destroyable item
-- is selected. Destructive action gated behind the intentional Stored toggle.
Selectors:Register("decor.showDestroyButton", {
    calls = {"decor.onlyStored", "decor.selectedItem.destroyable"},
    fn = function(state, ctx)
        local onlyStored  = Selectors:Call("decor.onlyStored", state, ctx)
        local destroyable = Selectors:Call("decor.selectedItem.destroyable", state, ctx)
        return onlyStored == true and destroyable == true
    end,
})

-- Visibility predicates: collapse profession + tags widgets when their selector returns "".
Selectors:Register("decor.selectedItem.isCrafted", {
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        return v and v.sourceType == 6 or false   -- 6 = CRAFTED
    end,
})
Selectors:Register("decor.selectedItem.hasTags", {
    calls = {"decor.selectedItem"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        if not v or not v.dataTagsByID then return false end
        for tagID in pairs(v.dataTagsByID) do
            local cat = HDG.TagData.GetCategory(tagID)
            if cat == "Styles" or cat == "Factions" then return true end
        end
        return false
    end,
})

-- (Dye-variant swatch selectors removed with the in-card variant strip:
-- decor.selectedItem.variants / selectedVariantIdentifier / variantSlot.* /
-- hasVariants. The owned-dyed-variant ROWS + dye-dots still use row.dyedVariants
-- via decor.items + decor.isDyed -- that system is untouched.)

-- Category line: row.categoryName + row.subcategoryName, pre-resolved at sweep. per ADR-003.
Selectors:Register("decor.selectedItem.category", {
    calls = {"decor.selectedItem"},
    reads = {"session.catalog.sweepGeneration"},
    fn = function(state, ctx)
        local v = Selectors:Call("decor.selectedItem", state, ctx)
        if not (v and v.decorID) then return "" end
        local row = HDG.HousingCatalogObserver.byDecorID[v.decorID]
        if not row then return "" end
        local cat = row.categoryName
        local sub = row.subcategoryName
        if cat and sub then return cat .. "  >  " .. sub end
        return cat or sub or ""
    end,
})

-- User-note text for the note editbox. Empty string when no note set.
Selectors:Register("decor.selectedItem.note", {
    calls = {"decor.selectedItemID"},
    reads = {"account.userNotes"},
    fn = function(state, ctx)
        local id = Selectors:Call("decor.selectedItemID", state, ctx)
        if not id then return "" end
        local notes = state.account.userNotes
        local n = notes[id]
        return (n and n.text) or ""
    end,
})

-- (decor.previewInfo removed: model preview dispatcher resolves selectedItemID
--  -> previewInfo at the UI seam where the Blizzard catalog API call belongs.)

-- (decor.countLabel retired: no widget bound after decorPanel.count -> decor.headerLabel.)

-- Rich header: "1557/1958 (79%)" + "  *  M shown" when any filter is active.
Selectors:Register("decor.headerDenominator", {
    memoized = true,
    calls = {"decor.allItems"},
    fn = function(state, ctx)
        local all = Selectors:Call("decor.allItems", state, ctx)
        return #all
    end,
})

Selectors:Register("decor.headerLabel", {
    calls = {"decor.headerDenominator", "decor.ownedCount", "decor.filterActive",
             "decor.items", "decor.isCollected", "decor.activeTag"},
    fn = function(state, ctx)
        local denom = Selectors:Call("decor.headerDenominator", state, ctx)
        if denom == 0 then return "" end
        -- No filter: whole-collection ratio (e.g. "1605/1673 (95%)").
        if not Selectors:Call("decor.filterActive", state, ctx) then
            local owned = Selectors:Call("decor.ownedCount", state, ctx)
            return string.format("%d/%d (%d%%)", owned, denom, math.floor(owned / denom * 100))
        end
        -- Filtered: collected / shown WITHIN the current filter, + the filter name
        -- (e.g. "204/309 (66%)  Quest"). Counts rows so it matches the "shown" total.
        local items  = Selectors:Call("decor.items", state, ctx)
        local isColl = Selectors:Call("decor.isCollected", state, ctx)
        local shown, collected = #items, 0
        for _, row in ipairs(items) do
            if isColl(row.itemID) then collected = collected + 1 end
        end
        local pct = shown > 0 and math.floor(collected / shown * 100) or 0
        local out = string.format("%d/%d (%d%%)", collected, shown, pct)
        local tag = Selectors:Call("decor.activeTag", state, ctx)
        if tag then
            -- Source-kind tags are stored as SOURCE_KINDS.key (e.g. "QUEST"); show the
            -- friendly label. Other tags (Favorites/sizes/styles) are already friendly.
            local kind = HDG.Constants.SOURCE_KIND_BY_KEY[tag]
            out = out .. "  " .. ((kind and kind.label) or tag)
        end
        return out
    end,
})

-- ============================================================================
-- Per-item flag selectors + aggregates
-- ============================================================================
-- Each returns a curried (itemID) -> bool. Closure holds the data lookup;
-- O(1) per item. Hot filter toggles NEVER invalidate these (per ADR-012).

-- isCollected: via Observer:IsOwned (same predicate as BuildRow/PatchCounts/HouseAggregator).
-- Re-fires on sweepGeneration bump (covers full sweep AND incremental PatchCounts).
Selectors:Register("decor.isCollected", {
    memoized = true,
    reads = {"session.catalog.sweepGeneration"},
    fn = function(state, ctx)
        return function(itemID)
            return HDG.HousingCatalogObserver:IsOwned(itemID)
        end
    end,
})

-- isStored: destroyableInstanceCount > 0 (stored AND destroyable; unique trophies excluded).
Selectors:Register("decor.isStored", {
    reads = {"session.catalog.sweepGeneration"},
    fn = function(state, ctx)
        local byItemID = HDG.HousingCatalogObserver.byItemID
        return function(itemID)
            local row = byItemID[itemID]
            return (row and (row.destroyableInstanceCount or 0) > 0) or false  -- exception(boundary): catalog struct field sparse
        end
    end,
})

-- destroyableCount: destroyable copies in storage. Used for row stamping + sort order.
Selectors:Register("decor.destroyableCount", {
    reads = {"session.catalog.sweepGeneration"},
    fn = function(state, ctx)
        local byItemID = HDG.HousingCatalogObserver.byItemID
        return function(itemID)
            local row = byItemID[itemID]
            return (row and row.destroyableInstanceCount) or 0
        end
    end,
})

-- isFavorite: account.favorites membership.
Selectors:Register("decor.isFavorite", {
    reads = {"account.favorites"},
    fn = function(state, ctx)
        local favs = state.account.favorites
        return function(itemID) return favs[itemID] == true end
    end,
})

-- craftableState: 4-state recipe knowledge enum (HDG.Constants.RECIPE_STATE).
-- known_alt requires account.recipes[itemID].altKnown (populated by alt scanner).
Selectors:Register("decor.craftableState", {
    reads = {"account.recipes"},
    fn = function(state, ctx)
        local recipes = state.account.recipes
        local S = HDG.Constants.RECIPE_STATE
        return function(itemID)
            local r = recipes[itemID]
            if not r then return S.NotARecipe end
            if r.selfKnown then return S.KnownByCharacter end
            if r.altKnown  then return S.KnownByAlt       end
            return S.UnknownOnAccount
        end
    end,
})

-- ===== Filter state surface ===================================================
-- Used by chip `active` bindings and by decor.items as composed filter inputs.

Selectors:Register("decor.topFilter", {
    reads = {"session.ui.decor.filters.topFilter"},
    fn = function(state, ctx)
        local d = state.session.ui.decor
        return (d.filters and d.filters.topFilter) or "all"
    end,
})

-- Per-top-filter boolean selectors for chip `active` bindings. HDG.Constants.TOP_FILTERS is SSoT.
for _, entry in ipairs(HDG.Constants.TOP_FILTERS or {}) do
    local captured = entry.value
    Selectors:Register("decor.topFilter.active_" .. captured, {
        calls = {"decor.topFilter"},
        fn = function(state, ctx)
            return Selectors:Call("decor.topFilter", state, ctx) == captured
        end,
    })
end

-- ===== Tags-row dynamic slot selectors =======================================
-- 20 pre-allocated slots per top filter (TAG_SLOT_COUNT = 20). Each slot:
--   decor.tagSlot.text_N    -- tag label or "" when slot empty
--   decor.tagSlot.active_N  -- true when this slot's tag is active
--   decor.tagSlot.visible_N -- true when slot has content
HDG.Constants.TAG_SLOT_COUNT = 20
for slot = 1, HDG.Constants.TAG_SLOT_COUNT do
    local n = slot
    Selectors:Register("decor.tagSlot.text_" .. n, {
        calls = {"decor.tagsForFilter", "decor.topFilter"},
        fn = function(state, ctx)
            local tags = Selectors:Call("decor.tagsForFilter", state, ctx)
            local raw  = tags[n]
            if not raw then return "" end
            -- Source kinds arrive as SOURCE_KINDS.key (all caps); show the friendly
            -- label for DISPLAY only. activeTag + matchesTag still use the raw key.
            if Selectors:Call("decor.topFilter", state, ctx) == "sources" then
                local kind = HDG.Constants.SOURCE_KIND_BY_KEY[raw]
                return (kind and kind.label) or raw
            end
            return raw
        end,
    })
    Selectors:Register("decor.tagSlot.active_" .. n, {
        calls = {"decor.tagsForFilter", "decor.activeTag"},
        fn = function(state, ctx)
            local tags = Selectors:Call("decor.tagsForFilter", state, ctx)
            local mine = tags[n]
            local active = Selectors:Call("decor.activeTag", state, ctx)
            return mine ~= nil and active == mine
        end,
    })
    Selectors:Register("decor.tagSlot.visible_" .. n, {
        calls = {"decor.tagsForFilter"},
        fn = function(state, ctx)
            local tags = Selectors:Call("decor.tagsForFilter", state, ctx)
            return tags[n] ~= nil and true or false
        end,
    })
end

-- "Tags:" label visibility. Explicit boolean (callers expect false/true, not false/nil).
Selectors:Register("decor.hasTagsRow", {
    calls = {"decor.tagsForFilter"},
    fn = function(state, ctx)
        local tags = Selectors:Call("decor.tagsForFilter", state, ctx)
        return tags[1] ~= nil and true or false
    end,
})

Selectors:Register("decor.activeTag", {
    reads = {"session.ui.decor.filters.activeTag"},
    fn = function(state, ctx)
        local d = state.session.ui.decor
        return d.filters and d.filters.activeTag or nil
    end,
})

Selectors:Register("decor.onlyUncollected", {
    reads = {"session.ui.decor.filters.onlyUncollected"},
    fn = function(state, ctx)
        local d = state.session.ui.decor
        return (d.filters and d.filters.onlyUncollected) == true
    end,
})

Selectors:Register("decor.onlyStored", {
    reads = {"session.ui.decor.filters.onlyStored"},
    fn = function(state, ctx)
        local d = state.session.ui.decor
        return (d.filters and d.filters.onlyStored) == true
    end,
})

-- (decor.onlyDyed / decor.onlyDyeable retired: Dyed/Dyeable moved to sub-tags
--  under topFilter='all'; matchesTag reads isDyed/isDyeable directly.)

-- Curried per-item flag for dyed-or-dyeable filtering. Reads catalog row
-- data populated by ReconcileFull.
Selectors:Register("decor.isDyeable", {
    reads = {"session.catalog.sweepGeneration"},
    fn = function(state, ctx)
        local byItemID = HDG.HousingCatalogObserver.byItemID
        return function(itemID)
            local row = byItemID[itemID]
            return row and row.canCustomize == true or false
        end
    end,
})
Selectors:Register("decor.isDyed", {
    reads = {"session.catalog.sweepGeneration"},
    fn = function(state, ctx)
        local byItemID = HDG.HousingCatalogObserver.byItemID
        return function(itemID)
            local row = byItemID[itemID]
            -- row.dyedVariants is baked by the observer (_bakeVariantDyes) =
            -- owned variants (numStored>0) with an applied dye. Single source of
            -- truth, shared with the decor.items per-variant expansion.
            return (row and row.dyedVariants and #row.dyedVariants > 0) or false
        end
    end,
})

-- Any filter active? Drives the 'Clear filters' affordance.
-- decor.activeProfessions (retired) not checked here: legacy state with no UI effect.
Selectors:Register("decor.filterActive", {
    calls = {
        "decor.topFilter",
        "decor.activeTag",
        "decor.onlyUncollected",
        "decor.onlyStored",
        "decor.filterQuery",
    },
    fn = function(state, ctx)
        if Selectors:Call("decor.topFilter",       state, ctx) ~= "all"   then return true end
        if Selectors:Call("decor.activeTag",       state, ctx) ~= nil     then return true end
        if Selectors:Call("decor.onlyUncollected", state, ctx) == true    then return true end
        if Selectors:Call("decor.onlyStored",      state, ctx) == true    then return true end
        if (Selectors:Call("decor.filterQuery", state, ctx)) ~= "" then return true end
        return false
    end,
})

-- ===== Tags row content + bucket/tag matching =================================
-- decor.tagsForFilter -> ordered chip list for the current topFilter.
-- decor.matchesTag -> curried predicate composed into decor.items.
Selectors:Register("decor.tagsForFilter", {
    reads    = {"session.catalog.sweepGeneration"},
    calls    = {"decor.topFilter"},
    memoized = true,
    fn = function(state, ctx)
        local top = Selectors:Call("decor.topFilter", state, ctx)
        -- Curated set under 'all'. Dyed/Dyeable moved from Row 3 toggles to
        -- sub-tags (toggle row was crowded; composability with profession sub-tags
        -- under 'crafted' is a niche case and was dropped).
        -- "All Decor" dropped: redundant; top='all' with no activeTag = everything.
        -- per ADR-018: DECOR_FILTER_RESET on the 'All' chip is the canonical reset.
        -- Uncollected stays a Row 3 toggle so it composes with Crafted prof sub-tags.
        if top == "all" then
            -- Structural/status sub-tags. Rep/Quest/Ach dropped: they duplicated
            -- the Sources top-filter. "Placed" = decor currently placed in a house.
            return { "Favorites", "Crafted", "House XP", "Dyed", "Dyeable", "Placed", "Redeemable" }
        end
        if top == "crafted" then
            local profs = HDG.Constants.DECOR_PROFESSIONS or {}
            local out = {}
            for i, p in ipairs(profs) do out[i] = p end
            return out
        end
        -- 'sources': derive distinct kind keys from catalog sourceTags.
        if top == "sources" then
            local byDecorID = HDG.HousingCatalogObserver.byDecorID
            local seen = {}
            for _, row in pairs(byDecorID) do
                local st = row.sourceTags
                if type(st) == "table" then
                    for _, entry in ipairs(st) do
                        if entry.kind then seen[entry.kind] = true end
                    end
                end
            end
            local out = {}
            for kind in pairs(seen) do out[#out + 1] = kind end
            table.sort(out)
            return out
        end
        -- sizes/factions/styles/expansions/other: derive labels from live catalog tagIDs.
        local bucket = ({
            sizes      = "Sizes",
            factions   = "Factions",
            styles     = "Styles",
            expansions = "Expansions",
            other      = "Other",
        })[top]
        if not bucket then return {} end
        local TagData = HDG.TagData
        local byDecorID = HDG.HousingCatalogObserver.byDecorID
        local seen = {}
        for _, row in pairs(byDecorID) do
            local ids = row.dataTagsByID
            if type(ids) == "table" then
                for tagID in pairs(ids) do
                    if TagData.GetCategory(tagID) == bucket then
                        local label = TagData.GetShortLabel(tagID)  -- shortens expansions; identity for others
                        if label then seen[label] = true end
                    end
                end
            end
        end
        local out = {}
        for label in pairs(seen) do out[#out + 1] = label end
        if top == "expansions" then
            -- Canonical release order (EXPANSION_DATA via Expansion.GetIndex), not
            -- alphabetical. Short labels (TBC/WotLK/...) resolve through the alias map.
            table.sort(out, function(a, b)
                local ia = HDG.Expansion.GetIndex(a) or math.huge
                local ib = HDG.Expansion.GetIndex(b) or math.huge
                if ia ~= ib then return ia < ib end
                return a < b
            end)
        else
            table.sort(out)
        end
        return out
    end,
})

-- Pass-through placeholder for future bucket-level filters. No reads/calls
-- since the function is constant. Re-add to decor.items.calls if a bucket needs it.
Selectors:Register("decor.matchesTopFilter", {
    fn = function(state, ctx)
        return function() return true end
    end,
})

-- Curried (itemID) -> bool for "matches the active tag at the current top filter".
-- nil or "All Decor" activeTag matches everything.
Selectors:Register("decor.matchesTag", {
    reads = {"account.recipes", "account.favorites", "session.catalog.sweepGeneration"},
    calls = {"decor.topFilter", "decor.activeTag",
             "decor.isFavorite", "decor.isCollected",
             "decor.isDyed", "decor.isDyeable"},
    fn = function(state, ctx)
        local top = Selectors:Call("decor.topFilter", state, ctx)
        local tag = Selectors:Call("decor.activeTag",  state, ctx)
        -- Crafted is source-restricting: even with no profession sub-tag it must narrow
        -- to crafted decor (handled below), so it skips this pass-all early-out.
        if (tag == nil or tag == "All Decor") and top ~= "crafted" then
            return function() return true end
        end

        -- ===== Sub-tags under 'all' =====
        if top == "all" then
            if tag == "Favorites" then
                local isFav = Selectors:Call("decor.isFavorite", state, ctx)
                return function(itemID) return isFav and isFav(itemID) or false end
            end
            if tag == "Crafted" then
                local recipes = state.account.recipes
                return function(itemID) return recipes[itemID] ~= nil end
            end
            if tag == "House XP" then
                -- Items eligible for first-acquisition House XP AND not yet owned.
                local byItemID = HDG.HousingCatalogObserver.byItemID
                local isColl   = Selectors:Call("decor.isCollected", state, ctx)
                return function(itemID)
                    if isColl and isColl(itemID) then return false end
                    local row = byItemID[itemID]
                    return row and (row.firstAcquisitionBonus or 0) > 0 or false  -- exception(boundary): catalog struct field sparse
                end
            end
            if tag == "Dyed" then
                local isDyed = Selectors:Call("decor.isDyed", state, ctx)
                return function(itemID) return isDyed and isDyed(itemID) or false end
            end
            if tag == "Dyeable" then
                local isDyeable = Selectors:Call("decor.isDyeable", state, ctx)
                return function(itemID) return isDyeable and isDyeable(itemID) or false end
            end
            if tag == "Placed" then
                -- Decor currently placed in a house (catalog live numPlaced > 0).
                local byItemID = HDG.HousingCatalogObserver.byItemID
                return function(itemID)
                    local row = byItemID[itemID]
                    return row and (row.numPlaced or 0) > 0 or false  -- exception(boundary): catalog struct field sparse
                end
            end
            if tag == "Redeemable" then
                -- A redeemable token is outstanding AND no copy has been claimed yet
                -- (nothing in storage, nothing placed) -- i.e. still waiting to redeem.
                local byItemID = HDG.HousingCatalogObserver.byItemID
                return function(itemID)
                    local row = byItemID[itemID]
                    if not row then return false end  -- exception(boundary): catalog struct field sparse
                    return (row.remainingRedeemable or 0) > 0
                       and (row.quantity or 0)  == 0
                       and (row.numPlaced or 0) == 0
                end
            end
            -- Unknown sub-tag under 'all' -> no matches.
            return function() return false end
        end

        -- ===== Crafted: items whose canonical source IS the recipe (sourceType==6) =====
        -- row.sourceType is baked by _bakeSourceTypes (priority Quest>Ach>Vendor>Crafted),
        -- so 6 = recipe-backed with no higher source -- the row's craft star. Matches the
        -- curated recipe DB, NOT the player's known recipes. No profession sub-tag selected
        -- -> all crafted; else narrow to that recipe's profession.
        if top == "crafted" then
            local byItemID = HDG.HousingCatalogObserver.byItemID
            if tag == nil or tag == "All Decor" then
                return function(itemID)
                    local row = byItemID[itemID]
                    return row ~= nil and row.sourceType == 6
                end
            end
            return function(itemID)
                local row = byItemID[itemID]
                return row ~= nil and row.sourceType == 6
                   and row.recipe and row.recipe.profession == tag
            end
        end

        -- ===== Source-kind chips under 'sources' =====
        if top == "sources" then
            local byItemID = HDG.HousingCatalogObserver.byItemID
            return function(itemID)
                local row = byItemID[itemID]
                if not (row and row.sourceTags) then return false end
                for _, entry in ipairs(row.sourceTags) do
                    if entry.kind == tag then return true end
                end
                return false
            end
        end

        -- ===== Tag-bucket categories =====
        local bucket = ({
            sizes      = "Sizes",
            factions   = "Factions",
            styles     = "Styles",
            expansions = "Expansions",
            other      = "Other",
        })[top]
        if not bucket then return function() return true end end
        local byItemID = HDG.HousingCatalogObserver.byItemID
        local TagData = HDG.TagData
        -- Compare via GetShortLabel: activeTag uses the short display form,
        -- so long-form comparison would miss shortened expansion tags.
        return function(itemID)
            local row = byItemID[itemID]
            if not (row and row.dataTagsByID) then return false end
            for tagID in pairs(row.dataTagsByID) do
                if TagData.GetCategory(tagID) == bucket
                   and TagData.GetShortLabel(tagID) == tag then
                    return true
                end
            end
            return false
        end
    end,
})

-- ===== Aggregates ===========================================================
-- "Owned: N/T" sidebar counter. Memoized; re-runs only on catalog-side mutation.
Selectors:Register("decor.ownedCount", {
    reads    = {"account.collection.ownedDecorIDs"},
    memoized = true,
    fn = function(state, ctx)
        local col   = state.account.collection
        local owned = col.ownedDecorIDs
        local n = 0
        for _ in pairs(owned) do n = n + 1 end
        return n
    end,
})

-- "N stored" sidebar counter. Memoized; re-runs only on catalog sweep.
Selectors:Register("decor.storedCount", {
    reads    = {"session.catalog.sweepGeneration"},
    memoized = true,
    fn = function(state, ctx)
        if not HDG.HousingCatalogObserver:IsReady() then return 0 end
        local n = 0
        for _, row in pairs(HDG.HousingCatalogObserver.byDecorID) do
            if (row.quantity or 0) > 0 then n = n + 1 end  -- exception(boundary): catalog struct field sparse
        end
        return n
    end,
})

-- Composite sidebar label: "Owned: 4547/7500   3895 stored". Stored half hidden when 0.
Selectors:Register("decor.ownedSidebarLabel", {
    calls = {"decor.ownedCount", "decor.storedCount", "decor.allItems"},
    fn = function(state, ctx)
        local owned  = Selectors:Call("decor.ownedCount",  state, ctx)
        local stored = Selectors:Call("decor.storedCount", state, ctx)
        local total  = #(Selectors:Call("decor.allItems",   state, ctx))
        if total == 0 then return "" end
        local out = string.format("Owned: %d/%d", owned, total)
        if stored > 0 then out = out .. string.format("   %d stored", stored) end
        return out
    end,
})

