-- HDG.HousingCatalogObserver
-- ============================================================================
-- Sole owner of C_HousingCatalog (Iron Invariant §9). One searcher, one owner
-- (see feedback_lua_empty_string_truthy.md for the prior split-owner lesson).
-- All housing catalog work flows through this module:
--   * Cold-sweep (ReconcileFull / _OnSearcherResults atomic-rebuild) + single
--     searcher with full Blizzard config (BasicDecor + all tags/indoor/outdoor)
--   * Incremental updates (ReconcileEntry) on HOUSING_STORAGE_ENTRY_UPDATED
--   * Sync per-item lookup (Resolve(itemID)) for modelPreview + allItems fallback
-- ADR-012: hot UI actions never invalidate the catalog cache.
-- Stability: searcher callbacks can fire with partial data; 500ms settle timer coalesces.

HDG = HDG or {}
HDG.HousingCatalogObserver = HDG.HousingCatalogObserver or {}

local R = HDG.HousingCatalogObserver

-- Reverse indexes (atomic-swapped at the end of each sweep; persist between
-- sweeps because the table references survive on R).
R.byItemID       = R.byItemID       or {}
R.byDecorID      = R.byDecorID      or {}  -- [decorID] = row (built alongside byItemID)
R.byVendor       = R.byVendor       or {}
R.allVendorNames = R.allVendorNames or {}
R.tagIDToGroup   = R.tagIDToGroup   or {}

-- ===== Reconciler ============================================================
-- Two entry points:
--   ReconcileFull       -- cold sweep, atomic-rebuilds all indexes
--   ReconcileEntry(id)  -- targeted update from HOUSING_STORAGE_ENTRY_UPDATED
-- Both mutate state via reducer dispatches (per ADR-012).

function R:GetClientVer()
    local v = _G.GetBuildInfo and _G.GetBuildInfo()
    return tostring(v or "unknown")
end

function R:_CancelSettleTimer()
    if self._settleTimer then
        if self._settleTimer.Cancel then self._settleTimer:Cancel() end  -- exception(boundary): C_Timer.After returns a handle; Cancel is the cancel API but handle shape varies
        self._settleTimer = nil
    end
end

-- Category / subcategory display-name cache (ADR-003: API calls at resolver seam).
-- Stamped onto each row at sweep time. Nil catID = sparse row (only legit nil input).
local _categoryNameCache    = {}
local _subcategoryNameCache = {}
local function resolveCategoryName(catID)
    if not catID then return nil end
    local cached = _categoryNameCache[catID]
    if cached then return cached end
    local info = _G.C_HousingCatalog.GetCatalogCategoryInfo(catID)
    local name = info.name
    if name then _categoryNameCache[catID] = name end
    return name
end
local function resolveSubcategoryName(subID)
    if not subID then return nil end
    local cached = _subcategoryNameCache[subID]
    if cached then return cached end
    local info = _G.C_HousingCatalog.GetCatalogSubcategoryInfo(subID)
    local name = info.name
    if name then _subcategoryNameCache[subID] = name end
    return name
end

-- ============================================================================
-- Catalog searcher: ONE persistent R._searcher (Blizzard HousingCatalogFrameMixin shape).
-- Created + callback-set once; reused for every RunSearch.
-- Guard: namespace + searcher object guarded (CreateCatalogSearcher can fail);
-- all searcher methods called strictly (vanished method = loud fail, never silent skip).
--
-- exception(boundary): GetAllFilterTagGroups() reads 0 then N a moment later (tag metadata streams in at open).
-- We re-apply config on each kick while not "ready" so tag groups land when they exist;
-- storage/catalog events drive re-kicks. Once "ready" just RunSearch.
-- ============================================================================

-- ALL-category focus. nil also means "all categories" to the searcher (Blizzard convention).
-- exception(boundary): Blizzard global table.
local function _allCategoryID()
    local C = _G.Constants and _G.Constants.HousingCatalogConsts
    return C and C.HOUSING_CATALOG_ALL_CATEGORY_ID
end

-- _EnsureSearcher: single persistent searcher, created + held on R._searcher so GC
-- can't reclaim it before the async callback fires. boundary: C_HousingCatalog absent.
function R:_EnsureSearcher()
    if self._searcher then return self._searcher end
    if not (_G.C_HousingCatalog and _G.C_HousingCatalog.CreateCatalogSearcher) then
        return nil
    end
    local s = _G.C_HousingCatalog.CreateCatalogSearcher()
    if not s then return nil end
    self._searcher = s
    -- Set once; fires on the initial RunSearch AND every later re-RunSearch.
    s:SetResultsUpdatedCallback(function() R:_OnSearcherResults(s) end)
    return s
end

-- _ConfigureSearcher: Blizzard's exact config (OneTimeInit + ResetFiltersToDefault + ALL-focus).
function R:_ConfigureSearcher(s)
    s:SetAutoUpdateOnParamChanges(false)
    s:SetStoredOnly(false)
    s:SetBaseVariantOnly(true)
    s:SetEditorModeContext(_G.Enum.HouseEditorMode.BasicDecor)
    s:SetCustomizableOnly(false)
    s:SetAllowedIndoors(true)
    s:SetAllowedOutdoors(true)
    s:SetCollected(true)
    s:SetUncollected(true)
    s:SetFirstAcquisitionBonusOnly(false)
    s:SetFilteredCategoryID(_allCategoryID())
    s:SetFilteredSubcategoryID(nil)
    for _, group in ipairs(_G.C_HousingCatalog.GetAllFilterTagGroups() or {}) do
        s:SetAllInFilterTagGroup(group.groupID, true)
    end
    s:SetAutoUpdateOnParamChanges(true)
end

-- ReconcileFull: kick the search. Re-applies config while not "ready" (tag groups
-- may still be streaming in); RunSearch. Results land async in _OnSearcherResults;
-- 0.5s settle timer coalesces bursts. Storage/catalog events re-kick until loaded.
function R:ReconcileFull()
    local s = self:_EnsureSearcher()
    if not s then
        HDG.Log:Warn("catalog_error", "ReconcileFull aborted: C_HousingCatalog unavailable")
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.CATALOG_LOAD_FAILED, payload = { reason = "no_api" } })
        return
    end
    if HDG.Store:GetState().session.catalog.status ~= "ready" then
        self:_ConfigureSearcher(s)
    end
    HDG.Log:Info("catalog_swept", "Starting full catalog sweep...")
    -- Perf RTT: stamp when we fire the external catalog search. The gap to the
    -- first _OnSearcherResults callback is the EXTERNAL round-trip (Blizzard
    -- building/returning the catalog) -- not our CPU. Recorded as an "rtt" mark.
    if HDG.Perf and HDG.Perf.Enabled and HDG.Perf:Enabled() then  -- exception(false-positive): HDG.Perf is TOC-guaranteed at runtime; headless test mock omits it
        self._perfSearchFiredAt = _G.debugprofilestop and _G.debugprofilestop() or nil
    end
    s:RunSearch()
end

-- ===== Per-sweep index builders ==============================================
-- `acc` = per-sweep accumulator: { byItemID, byDecorID, byVendor, allVendorNames,
-- vendorNamesSeen, owned }. Atomic-assigned onto R at commit; subscribers never
-- see partial state.

-- Index a (name, zone) vendor into acc.byVendor + dedup into allVendorNames.
-- Composite (name, zone) key: ~9 vendor names on 12.0.5 are shared across zones;
-- keying by name alone collapses distinct vendors into one bucket.
local function _indexVendor(acc, name, zone, faction, standing, itemID)
    local vkey = name .. "::" .. (zone or "")
    local ven = acc.byVendor[vkey]
    if not ven then
        local Aug = HDG.StaticData.VendorAugment   -- exception(boundary): absent in headless until StaticData loads
        ven = {
            name = name, items = {}, zone = zone,
            faction = faction or "", standing = standing or "",
            -- Resolved npcID so consumers can look a vendor up by ID (event cards,
            -- waypoints) without name reconciliation. Same resolution _bakeVendors uses.
            npcID = Aug and Aug:ResolveName(name, zone),
            _seenItems = {},
        }
        acc.byVendor[vkey] = ven
        if not acc.vendorNamesSeen[name] then
            acc.vendorNamesSeen[name] = true
            acc.allVendorNames[#acc.allVendorNames + 1] = name
        end
    end
    if not ven._seenItems[itemID] then
        ven._seenItems[itemID] = true
        table.insert(ven.items, itemID)
    end
end

-- Feed a row's vendor sources into _indexVendor. row.vendors is the complete list:
-- _bakeVendors folds CatalogOverride type=5 vendors (hidden/placeholder sellers like
-- Chel the Chip) into it, so no separate row.sources pass is needed here.
local function _indexVendorsFromRow(acc, row)
    if row.vendors then
        for _, v in ipairs(row.vendors) do
            if v.name and v.name ~= "" then
                _indexVendor(acc, v.name, v.zone, v.faction, v.standing, row.itemID)
            end
        end
    end
end

-- Process one searcher entry: build the row, stamp the indexes, feed vendors.
-- Skips non-qualifying entries (non-zero subtype = variant placeholders; no
-- itemID = catalog inconsistency).
local function _processEntry(acc, entry)
    local rid = entry.recordID
    if not rid then return end
    local info = _G.C_HousingCatalog.GetCatalogEntryInfo(entry)
    if not info then return end
    local subtype = (type(entry) == "table" and entry.subtypeIdentifier) or 0
    if subtype ~= 0 or not info.itemID then return end
    -- info.recordID isn't always populated by the entry-info API; the entry
    -- itself carries it via the searcher result.
    info.recordID = info.recordID or rid
    local row = R:BuildRow(info)
    acc.byItemID[row.itemID] = row
    acc.byDecorID[rid]       = row
    if row.isOwned then acc.owned[rid] = true end
    _indexVendorsFromRow(acc, row)
end

function R:_OnSearcherResults(searcher)
    -- Driven by the persistent searcher's results-updated callback (and the
    -- storage-event re-kicks). Reads GetCatalogSearchResults() -- the FILTERED
    -- set; our ALL-category + all-tags config makes that the full catalog
    -- (mirrors Blizzard's HousingCatalogFrameMixin:UpdateCatalogData read).
    if not (searcher and searcher.GetCatalogSearchResults) then return end
    -- Perf RTT: first callback after RunSearch -> external catalog round-trip.
    -- One-shot (clear the stamp) so multi-fire searcher bursts don't re-mark.
    if self._perfSearchFiredAt and HDG.Perf then
        local rtt = (_G.debugprofilestop and _G.debugprofilestop() or 0) - self._perfSearchFiredAt
        self._perfSearchFiredAt = nil
        HDG.Perf:Mark("catalog searcher RTT (external -- Blizzard built the catalog)", rtt, "rtt")
    end
    local items = searcher:GetCatalogSearchResults()
    if not items then
        -- nil result set: nothing to commit yet. Stay "loading"; the next
        -- storage/catalog event re-kicks (re-applying config) until entries land.
        HDG.Log:Warn("catalog_error", "GetCatalogSearchResults returned nil; sweep not committed (will retry on next storage event)")
        return
    end

    R:_BuildTagIDIndex()  -- must precede the sweep so _bakeTags sees Expansion/Size tags

    -- Build into per-sweep acc; _CommitSweep atomic-assigns in the settle callback.
    local acc = {
        byItemID = {}, byDecorID = {}, byVendor = {},
        allVendorNames = {}, vendorNamesSeen = {}, owned = {},
    }
    -- Perf: catalog-load cost (outside dispatch path; flush probe never sees it). boundary: Perf optional.
    local _perf  = HDG.Perf
    local _timed = _perf and _perf:Enabled()
    local _t0    = _timed and _G.debugprofilestop() or nil
    for _, entry in ipairs(items) do
        _processEntry(acc, entry)
    end
    if _timed then
        _perf:RecordOp("catalog.indexSweep (" .. #items .. " entries)",
                       _G.debugprofilestop() - _t0)
    end
    table.sort(acc.allVendorNames)

    local result = {
        byItemID       = acc.byItemID,
        byDecorID      = acc.byDecorID,
        byVendor       = acc.byVendor,
        allVendorNames = acc.allVendorNames,
        owned          = acc.owned,
        sweptAt        = _G.GetTime and _G.GetTime() or 0,  -- exception(boundary): GetTime/time absent in headless harness
        clientVer      = self:GetClientVer(),
    }

    -- Settle 0.5s: coalesces searcher multi-fire bursts (boundary: loading screens / login cascade).
    self:_CancelSettleTimer()
    self._settleTimer = C_Timer.NewTimer(0.5, function()
        self._settleTimer = nil
        R:_CommitSweep(result)
    end)
end

-- _CommitSweep: atomic index swap + dispatch catalog-ready notifications.
function R:_CommitSweep(result)
    local itemCount = 0
    for _ in pairs(result.byDecorID) do itemCount = itemCount + 1 end
    if itemCount == 0 then
        -- 0 entries = catalog not loaded yet (tag groups still streaming). Don't
        -- commit; storage/catalog events re-kick with the config once entries arrive.
        HDG.Log:Warn("catalog_error",
            "catalog search returned 0 entries; not loaded yet -- awaiting storage-event re-kick")
        return
    end

    -- ATOMIC ASSIGN: consumers see either old or new, never mid-build.
    R.byItemID       = result.byItemID
    R.byDecorID      = result.byDecorID
    R.byVendor       = result.byVendor
    R.allVendorNames = result.allVendorNames
    R._catalogSchemaVersion = HDG.Constants.CATALOG_SCHEMA_VERSION

    local vendorCount = 0
    for _ in pairs(result.byVendor) do vendorCount = vendorCount + 1 end
    local generation = (HDG.Store:GetState().session.catalog.sweepGeneration or 0) + 1

    -- COLLECTION_BULK_LOAD = canonical "catalog refreshed" action. Reducer reads
    -- payload.owned to update state.account.collection.ownedDecorIDs (persisted).
    HDG.Store:Dispatch({
        type = HDG.Constants.ACTIONS.COLLECTION_BULK_LOAD,
        payload = {
            owned                = result.owned,
            swept_at             = result.sweptAt,
            clientVer            = result.clientVer,
            catalogSchemaVersion = HDG.Constants.CATALOG_SCHEMA_VERSION,
        },
    })
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.DECOR_CATALOG_READY })
    HDG.Store:Dispatch({
        type = HDG.Constants.ACTIONS.CATALOG_LOAD_COMPLETED,
        payload = {
            loadedAt    = _G.GetTime and _G.GetTime() or 0,
            itemCount   = itemCount,
            vendorCount = vendorCount,
            generation  = generation,
        },
    })

    -- Rebuild category nav: the MAIN_WINDOW_OPENING build runs before the sweep
    -- completes; this ensures subcategory info (e.g. Furnishings) is populated.
    R:QueueCategoryTreeRebuild()

    HDG.Log:Success("catalog_refreshed",
        string.format("Catalog ready -- %d items, %d vendors indexed", itemCount, vendorCount))
end

-- ReconcileEntry(entryID): targeted update from HOUSING_STORAGE_ENTRY_UPDATED.
function R:ReconcileEntry(entryID)
    if not (entryID and _G.C_HousingCatalog
            and _G.C_HousingCatalog.GetCatalogEntryInfo) then return end
    local info = _G.C_HousingCatalog.GetCatalogEntryInfo(entryID)
    if type(info) ~= "table" then
        HDG.Log:Warn("catalog_error",
            "GetCatalogEntryInfo returned non-table for entryID: " .. tostring(entryID))
        return
    end
    local decorID = type(info.entryID) == "table" and info.entryID.recordID or nil
    if not decorID then return end

    local A        = HDG.Constants.ACTIONS
    local row      = R.byDecorID[decorID]
    local wasOwned = row and row.isOwned or false
    local total    = (info.quantity or 0) + (info.remainingRedeemable or 0) + (info.numPlaced or 0)  -- exception(boundary): Blizzard struct field sparse
    local isOwned  = total > 0

    -- New row path: build + ROW_ADDED immediately (don't defer to next full sweep).
    if not row then
        -- info.recordID isn't always populated by GetCatalogEntryInfo; stamp it from decorID.
        info.recordID = info.recordID or decorID
        local newRow = R:BuildRow(info)
        HDG.Store:Dispatch({
            type = A.COLLECTION_CATALOG_ROW_ADDED,
            payload = { decorID = decorID, entry = newRow },
        })
        -- Update local ref so COUNTS_UPDATED sees the new row (wasOwned stays false).
        row = newRow
    end

    if isOwned and not wasOwned then
        HDG.Store:Dispatch({ type = A.COLLECTION_ITEM_LEARNED, payload = { decorID = decorID } })
        -- Record a "learned" craft-history entry for the Your Data tab.
        HDG.Store:Dispatch({
            type    = A.CRAFT_HISTORY_PUSH,
            payload = {
                eventType = "learned",
                itemID    = row.itemID,
                qty       = 1,
                completed = true,
                timestamp = (_G.time and _G.time()) or 0,
            },
        })
    elseif not isOwned and wasOwned then
        HDG.Store:Dispatch({ type = A.COLLECTION_ITEM_REMOVED, payload = { decorID = decorID } })
    end

    -- Patch the mutable count fields + bump sweepGeneration -- on ownership
    -- TRANSITIONS too, not just the counts-only case (this was an `elseif` that
    -- skipped learn/remove -- the screen-update regression).
    --
    -- CRITICAL ORDERING: PatchCounts the row SYNCHRONOUSLY here, THEN dispatch the
    -- re-render signal. The dispatch's own Subscribe handler ALSO calls PatchCounts,
    -- but it races the BindingEngine's Apply subscriber on the SAME dispatch -- if
    -- Apply wins, catalog selectors (decor.items "only uncollected" filter, detail
    -- status) re-run against the STALE row and the just-learned item stays
    -- "uncollected" for that frame (the tooltip reads the row live at hover, AFTER
    -- the patch lands -- which is why it showed owned while the list didn't). Mutate
    -- before signalling -> the row is fresh no matter which subscriber fires first.
    -- COUNTS_UPDATED still bumps session.catalog.sweepGeneration, the path every
    -- catalog-derived selector reads (LEARNED/REMOVED only touch ownedDecorIDs,
    -- which those selectors do NOT read). `row` is always set (built above).
    local counts = {
        quantity                 = info.quantity                 or 0,  -- exception(boundary): Blizzard struct field sparse
        numPlaced                = info.numPlaced                or 0,  -- exception(boundary): Blizzard struct field sparse
        remainingRedeemable      = info.remainingRedeemable      or 0,  -- exception(boundary): Blizzard struct field sparse
        destroyableInstanceCount = info.destroyableInstanceCount or 0,  -- exception(boundary): Blizzard struct field sparse
        firstAcquisitionBonus    = info.firstAcquisitionBonus
                                     or row.firstAcquisitionBonus or 0,  -- exception(boundary): Blizzard struct field sparse
    }
    R:PatchCounts(decorID, counts)
    HDG.Store:Dispatch({
        type    = A.COLLECTION_CATALOG_ROW_COUNTS_UPDATED,
        payload = { decorID = decorID, counts = counts },
    })
end

-- ===== Row builder ===========================================================
-- _BuildTagIDIndex: tagID -> groupName map from GetAllFilterTagGroups. Runs once (idempotent).
function R:_BuildTagIDIndex()
    if next(R.tagIDToGroup) then return end  -- idempotency guard (not a defensive nil-check)
    if not (_G.C_HousingCatalog and _G.C_HousingCatalog.GetAllFilterTagGroups) then return end  -- exception(boundary): C_HousingCatalog nil before catalog load
    local groups = _G.C_HousingCatalog.GetAllFilterTagGroups()  -- exception(boundary): C_HousingCatalog nil before catalog load
    if not groups then return end  -- exception(boundary): API may return nil before housing DB loads
    for _, g in ipairs(groups) do
        for _, tag in pairs(g.tags or {}) do
            if tag.tagID and g.groupName then
                R.tagIDToGroup[tag.tagID] = g.groupName
            end
        end
    end
end

-- BuildRow: transforms one catalog info table into the enriched row shape.
-- NOT pure: makes boundary calls (dye variants, category names, VendorAugment).
-- Snapshots live state at sweep time; stale until next sweep/reload.
-- Internal callers must never pass nil (strict read -- will throw on nil info).
function R:BuildRow(info)
    local row = {
        -- identity
        itemID    = info.itemID,
        decorID   = info.recordID,
        entryID   = info.entryID,
        entryType = info.entryType,

        -- catalog scalars
        name              = info.name,
        iconTexture       = info.iconTexture,
        iconAtlas         = info.iconAtlas,
        quality           = info.quality,
        size              = info.size,
        placementCost     = info.placementCost,
        -- Catalog struct may omit the allow-flags; default missing -> allowed
        -- (HDG-verified semantics). Normalized to a strict boolean here so every
        -- consumer (placement label, companion placement) reads it direct.
        isAllowedIndoors  = info.isAllowedIndoors  ~= false,  -- exception(boundary): catalog API field nil-able
        isAllowedOutdoors = info.isAllowedOutdoors ~= false,  -- exception(boundary): catalog API field nil-able
        canCustomize      = info.canCustomize,
        isPrefab          = info.isPrefab,
        isUniqueTrophy    = info.isUniqueTrophy,
        asset             = info.asset,
        uiModelSceneID    = info.uiModelSceneID,

        -- categorization
        -- categoryName / subcategoryName resolved at BuildRow time for direct render.
        categoryIDs     = info.categoryIDs,
        subcategoryIDs  = info.subcategoryIDs,
        categoryID      = info.categoryIDs    and info.categoryIDs[1],  -- exception(boundary): Blizzard struct optional array field
        subcategoryID   = info.subcategoryIDs and info.subcategoryIDs[1],  -- exception(boundary): Blizzard struct optional array field
        categoryName    = resolveCategoryName(info.categoryIDs    and info.categoryIDs[1]),
        subcategoryName = resolveSubcategoryName(info.subcategoryIDs and info.subcategoryIDs[1]),
        dataTagsByID    = info.dataTagsByID,
        dyeSlots        = info.dyeSlots,

        -- Ownership counters. Three real fields: quantity / numPlaced / remainingRedeemable.
        -- NOTE: info.numStored / totalNumStored / totalNumPlaced are documented but
        -- NEVER exposed at runtime -- reading them gives nil (verified 12.0.5+).
        quantity                 = info.quantity                 or 0,  -- exception(boundary): Blizzard struct field sparse
        numPlaced                = info.numPlaced                or 0,  -- exception(boundary): Blizzard struct field sparse
        remainingRedeemable      = info.remainingRedeemable      or 0,  -- exception(boundary): Blizzard struct field sparse
        destroyableInstanceCount = info.destroyableInstanceCount or 0,  -- exception(boundary): Blizzard struct field sparse
        firstAcquisitionBonus    = info.firstAcquisitionBonus    or 0,  -- exception(boundary): Blizzard struct field sparse

        -- customization metadata
        showQuantity   = info.showQuantity,
        customizations = info.customizations,
        dyeIDs         = info.dyeIDs,
    }
    -- isOwned: includes remainingRedeemable (unclaimed tokens count as owned).
    row.isOwned = (row.quantity + row.remainingRedeemable + row.numPlaced) > 0

    -- Dye variants for customizable items. API takes {recordID, entryType} table arg
    -- (not positional -- exception(boundary): positional args silently errored under old pcall).
    if row.canCustomize and _G.C_HousingCatalog
       and _G.C_HousingCatalog.GetAllVariantInfosForEntry then
        local entryType = (type(info.entryID) == "table"
                           and info.entryID.entryType) or 1
        local variants = _G.C_HousingCatalog.GetAllVariantInfosForEntry({
            recordID  = info.recordID,
            entryType = entryType,
        })
        if type(variants) == "table" then
            row.variants = variants
        end
    end

    -- Parse sourceText into structured vendor/quest/achievement/category/
    -- factionGate fields. Sets row.vendors[], row.quest, row.achievement,
    -- row.category, row.factionGate. Pure; mutates row in place.
    R:_ParseSourceText(info.sourceText or "", row)

    -- Apply CatalogOverrides. Sparse: most items have no entry, :Get returns nil.
    -- Transparent to selectors: they see corrected rows directly without knowing
    -- overrides were applied.
    local overrides = HDG.StaticData.CatalogOverrides:Get(row.itemID)
    if overrides then
        for k, v in pairs(overrides) do row[k] = v end
    end

    -- Bake derived/display fields onto the row so every consumer sees the
    -- same canonical shape. Each helper is small + focused + idempotent.
    -- Order matters: bakes that depend on others (gateLine reads gates,
    -- costLine reads costEntries) come after the producers.
    R:_bakeItemAugmentBackfill(row)  -- row.achievement / row.achievementID from aug.sources type=1
    R:_bakeTags(row)         -- row.expansion, row.sizeLabel, row.tags(+Label), row.dataTags
    R:_bakeCategory(row)     -- row.categoryLabel
    R:_bakePlacement(row)    -- row.placementLabel (budget icon prefixed)
    R:_bakeVendors(row)      -- per-vendor enrichment + row.vendorLines[]
    R:_bakeCost(row)         -- row.costEntries (unified) + row.costLine
    R:_bakeRecipe(row)       -- row.recipe + row.recipeLabel (MUST precede _bakeSourceTypes,
                             -- which reads row.recipe to assign sourceType=6 / CRAFTED)
    R:_bakeSourceTypes(row)  -- row.sourceType / sourceName / altSourceType / altSourceName
    R:_bakeBonusXp(row)      -- row.bonusXpLabel (first-acquisition reward chip)
    R:_bakeVariantDyes(row)  -- row.dyedVariants[] (per-owned-variant dye derivation)
    -- Single canonical source/gate bake. Produces row.sourceTags[] in
    -- SOURCE_KIND_PRIORITY order; entries carry text + extras (factionPrefix,
    -- achievementID, ...) for kinds that have them, nothing for chip-only
    -- kinds (DROP, VENDOR, etc.). row.gateLine + row.primarySourceCode are
    -- thin derivations of sourceTags[1] kept for backward-compat consumers.
    R:_bakeSourceTags(row)

    return row
end

-- ===== BuildRow bake helpers =================================================
-- Pure; mutate row in place. Run AFTER override merge so override-corrected fields are bake inputs.

-- _bakeItemAugmentBackfill: fill row.achievement + row.achievementID from ItemAugment
-- type=1 sources. Runs before _bakeSourceTypes so downstream sees consistent ach data.
-- The catalog "Achievement:" line gives a name but NEVER an achievementID; ItemAugment
-- is the sole achievementID source -- without it the [ACH] hyperlink has no ID.
function R:_bakeItemAugmentBackfill(row)
    local aug = HDG.StaticData.ItemAugment
                and HDG.StaticData.ItemAugment:Get(row.itemID)
    if not (aug and aug.sources) then return end
    for _, s in ipairs(aug.sources) do
        if s.type == 1 and s.name and s.name ~= "" then
            -- Name: catalog parse wins for display; only fill when absent.
            if not (row.achievement and row.achievement ~= "") then
                row.achievement = s.name
            end
            -- ID: ItemAugment is the sole source; always backfill.
            row.achievementID = row.achievementID or s.achievementID
        elseif (s.type == 2 or s.type == 3) and s.questID then
            -- Quest/WQ ID(s). ItemAugment is the sole source (catalog gives name, never ID).
            -- Single number or {ids} variant set (A/H); runtime ORs IsQuestFlaggedCompleted.
            row.questID = row.questID or s.questID
        end
    end
end

-- _bakeTags: classify dataTagsByID into expansion / size / styles-or-factions / other.
--   row.expansion / expansionLabel, sizeLabel, tags / tagsLabel (Styles+Factions),
--   dataTags / dataTagsLabel (full set). Expansion colors are Palette (scheme-invariant).
-- _classifyTag: inner helper extracted from the loop to keep _bakeTags flat.
local function _classifyTag(row, tagID, displayName, descriptive, styleFaction, getCategory)
    local group = R.tagIDToGroup[tagID]   -- tagIDToGroup is init'd to {} at load (line ~47), never nil
    if group == "Expansion" then row.expansion = displayName; return end
    if group == "Size"      then row.sizeLabel = displayName; return end
    descriptive[#descriptive + 1] = displayName
    if getCategory then
        local cat = getCategory(tagID)
        if cat == "Styles" or cat == "Factions" then
            styleFaction[#styleFaction + 1] = displayName
        end
    end
end

function R:_bakeTags(row)
    local descriptive, styleFaction = {}, {}
    local getCategory = HDG.TagData and HDG.TagData.GetCategory  -- exception(false-positive): HDG.TagData is TOC-guaranteed at runtime; headless test mock omits it
    if row.dataTagsByID then
        for tagID, displayName in pairs(row.dataTagsByID) do
            _classifyTag(row, tagID, displayName, descriptive, styleFaction, getCategory)
        end
        table.sort(descriptive)
        table.sort(styleFaction)
    end
    row.dataTags      = descriptive
    row.dataTagsLabel = table.concat(descriptive, ", ")
    row.tags          = styleFaction
    row.tagsLabel     = table.concat(styleFaction, ", ")
    -- Palette-colored expansion label (scheme-invariant; safe to bake).
    if row.expansion and row.expansion ~= "" then
        local hex = HDG.Expansion.GetColorHex(row.expansion)
        row.expansionLabel = hex and (hex .. row.expansion .. "|r") or row.expansion
    end
end

-- _bakeCategory: "Accents > Ornamental" breadcrumb.
function R:_bakeCategory(row)
    if row.categoryName and row.subcategoryName then
        row.categoryLabel = row.categoryName .. " > " .. row.subcategoryName
    elseif row.categoryName then
        row.categoryLabel = row.categoryName
    else
        row.categoryLabel = ""
    end
end

-- Icon escapes baked into row labels so detail panels never write |A:...|a.
-- Standardized at 14:14 across all decor labels for consistent visual weight.
local BUDGET_ICON = "|A:house-decor-budget-icon:14:14|a"
local XP_ICON     = "|A:housing-dashboard-icon-xp:14:14|a"

-- _bakePlacement: "<budget-icon> Indoor + Outdoor (3)" / "<budget-icon> Indoor only" / etc.
function R:_bakePlacement(row)
    local where
    if row.isAllowedIndoors and row.isAllowedOutdoors then
        where = "Indoor + Outdoor"
    elseif row.isAllowedIndoors then
        where = "Indoor only"
    elseif row.isAllowedOutdoors then
        where = "Outdoor only"
    else
        where = ""
    end
    if where == "" then row.placementLabel = ""; return end
    if (row.placementCost or 0) > 0 then  -- exception(boundary): catalog struct field sparse
        row.placementLabel = BUDGET_ICON .. " " .. where .. " (" .. row.placementCost .. ")"
    else
        row.placementLabel = BUDGET_ICON .. " " .. where
    end
end

-- _bakeVendors: enrich each vendor with VendorAugment fields (npcID, mapID, x, y,
-- canWaypoint) + bake vendorLines[] for direct row-factory use.
-- _resolveVendorNpc: extracted from loop to keep _bakeVendors flat.
local function _resolveVendorNpc(v, Aug)
    local npcID = Aug and Aug:ResolveName(v.name, v.zone)
    v.npcID       = npcID
    v.canWaypoint = npcID ~= nil
    if not npcID then return end
    local meta = Aug:Get(npcID)
    if not meta then return end
    v.mapID   = meta.mapID
    v.x       = meta.x
    v.y       = meta.y
    v.faction = v.faction ~= "" and v.faction or (meta.faction or "N")
    -- VendorAugment is authoritative for vendor location: overwrite the (often
    -- wrong) catalog zone. Vendors not in VendorAugment fall through the early
    -- returns above and keep their catalog zone. This makes the zone filter,
    -- the byVendor index, and the per-item vendor display agree on one zone.
    v.zone    = meta.zone or v.zone
end

function R:_bakeVendors(row)
    -- Fold CatalogOverride vendors (row.sources type=5) into row.vendors so the whole
    -- pipeline -- the zone/faction filters, the per-item vendor display, AND the byVendor
    -- index -- sees ONE complete vendor list (catalog + override-supplied vendors). The
    -- resolve loop below then stamps their npcID/zone from VendorAugment like any vendor.
    if row.sources then
        for _, s in ipairs(row.sources) do
            if s.type == 5 and s.name and s.name ~= "" then
                row.vendors = row.vendors or {}
                row.vendors[#row.vendors + 1] = { name = s.name, zone = s.detail or "", faction = "", standing = "" }
            end
        end
    end
    if not row.vendors then row.vendors, row.vendorLines = {}, {}; return end
    local Aug = HDG.StaticData.VendorAugment
    local lines = {}
    for _, v in ipairs(row.vendors) do
        _resolveVendorNpc(v, Aug)
        -- Baked line: "Name - Zone - 44.2, 62.7"
        local parts = { v.name }
        if v.zone and v.zone ~= "" then parts[#parts+1] = v.zone end
        if v.x and v.y and v.x > 0 and v.y > 0 then
            parts[#parts+1] = string.format("%.1f, %.1f", v.x, v.y)
        end
        lines[#lines+1] = table.concat(parts, " - ")
    end
    row.vendorLines = lines
end

-- _bakeVariantDyes: per-owned-dyed-variant display data baked once at sweep time.
-- Emits row.dyedVariants[]: { variantIdentifier, numStored, dyeColorsByChannel (sparse
-- 0/1/2), dyeColorIDs (flat), label, entryID }. entryID is what
-- C_HousingBasicMode.StartPlacingNewDecor takes to place the dyed copy.
function R:_bakeVariantDyes(row)
    if not row.variants then return end
    local dyed = {}
    for _, v in ipairs(row.variants) do
        if v.numStored > 0 then
            local byChannel, names = {}, {}
            for _, slot in ipairs(v.dyeSlots) do
                if slot.dyeColorID then
                    byChannel[slot.channel] = slot.dyeColorID
                    local dci = R:GetDyeColorInfo(slot.dyeColorID)
                    if dci and dci.name then names[#names + 1] = dci.name end
                end
            end
            if next(byChannel) then
                local flat = {}
                for ch = 0, 2 do
                    if byChannel[ch] then flat[#flat + 1] = byChannel[ch] end
                end
                dyed[#dyed + 1] = {
                    variantIdentifier  = v.entryVariantID.variantIdentifier,
                    numStored          = v.numStored,
                    dyeColorsByChannel = byChannel,
                    dyeColorIDs        = flat,
                    label              = #names > 0 and table.concat(names, ", ") or "Dyed",
                    entryID            = v.entryVariantID,
                }
            end
        end
    end
    row.dyedVariants = dyed
end

-- _bakeCost: unify vendor cost + override source cost into {currencyID, amount} entries
-- + bake costLine. row.costEntries for structured access; row.costLine for direct render.

-- gold(copper) + currency list -> normalized {currencyID, amount} entries.
local function _entriesFromCostSpec(cost, GOLD)
    local entries = {}
    if cost.gold and cost.gold > 0 then
        entries[#entries + 1] = { currencyID = GOLD, amount = math.floor(cost.gold / 10000) }
    end
    if cost.currencies then
        for _, c in ipairs(cost.currencies) do
            entries[#entries + 1] = { currencyID = c.id, amount = c.amount }
        end
    end
    return entries
end

-- Catalog cost: currency hyperlinks from the Cost: line, or gold fallback.
local function _costFromVendor(vendor, GOLD)
    if not vendor then return nil end
    if vendor.costEntries and #vendor.costEntries > 0 then
        local entries = {}
        for _, e in ipairs(vendor.costEntries) do
            entries[#entries + 1] = { currencyID = e.currencyID, amount = e.amount, icon = e.icon }
        end
        return entries
    end
    if vendor.cost and vendor.cost:match("^[%d,]+$") then
        local n = tonumber((vendor.cost:gsub(",", "")))
        if n and n > 0 then return { { currencyID = GOLD, amount = n } } end
    end
    return nil
end

-- Override fallback (only when catalog has no cost). First source with a .cost wins.
local function _costFromOverrideSources(sources, GOLD)
    if not sources then return nil end
    for _, s in ipairs(sources) do
        if s.cost then return _entriesFromCostSpec(s.cost, GOLD) end
    end
    return nil
end

local function _formatCostLine(entries)
    if not (entries and #entries > 0) then return "" end
    local parts = {}
    for _, e in ipairs(entries) do
        local s = HDG.Format.FormatCurrency(e.amount, e.currencyID, e.icon)
        if s ~= "" then parts[#parts + 1] = s end
    end
    return table.concat(parts, "  +  ")
end

-- Order-independent key for a cost-entry set (dedup distinct payment options).
local function _costKey(entries)
    local parts = {}
    for _, e in ipairs(entries) do
        parts[#parts + 1] = tostring(e.currencyID) .. ":" .. tostring(e.amount)
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

-- Distinct cost variants across all vendor blocks (e.g. 30 coupons OR 500g = two options).
local function _costVariants(row, GOLD)
    local lines, seen = {}, {}
    for _, vendor in ipairs(row.vendors or {}) do
        local entries = _costFromVendor(vendor, GOLD)
        if entries and #entries > 0 then
            local key = _costKey(entries)
            if not seen[key] then
                seen[key] = true
                lines[#lines + 1] = _formatCostLine(entries)
            end
        end
    end
    return lines
end

function R:_bakeCost(row)
    local GOLD   = HDG.Constants.CURRENCY_GOLD
    local vendor = row.vendors and row.vendors[1]
    local entries = _costFromVendor(vendor, GOLD)
                 or _costFromOverrideSources(row.sources, GOLD)
    row.costEntries = entries or {}
    row.costLine    = _formatCostLine(entries)
    -- Per-option lines (>=1 when any cost). Multi-option drives vendor list to show item once per option.
    local variants = _costVariants(row, GOLD)
    if #variants == 0 and row.costLine ~= "" then variants = { row.costLine } end
    row.costVariants = variants
end

-- Map ItemAugment minRep to display string. Convention: 4=Neutral…8=Exalted, 9+=Renown.
local function _repStandingFromMinRep(minRep)
    if not minRep or minRep <= 0 then return nil end
    if minRep == 4 then return "Neutral"     end
    if minRep == 5 then return "Friendly"    end
    if minRep == 6 then return "Honored"     end
    if minRep == 7 then return "Revered"     end
    if minRep == 8 then return "Exalted"     end
    if minRep >= 9 then return "Renown " .. tostring(minRep - 8) end
    return nil
end

-- Reverse map: standing string -> numeric code. Used when only catalog factionGate.standing
-- is available (no aug.minRep). Built lazily; FACTION_STANDING_LABEL globals are ready by load.
local _STANDING_TO_CODE = nil
local function _standingStringToCode(s)
    if not s or s == "" then return 0 end
    if not _STANDING_TO_CODE then
        _STANDING_TO_CODE = {}
        for i = 1, 8 do
            local lbl = _G["FACTION_STANDING_LABEL" .. i]
            if lbl then _STANDING_TO_CODE[lbl] = i end
        end
        for n = 1, 40 do _STANDING_TO_CODE["Renown " .. n] = 8 + n end
    end
    return _STANDING_TO_CODE[s] or 0
end

-- Rep progress lives in HDG.RepObserver:GetProgress (dynamic state; stale if baked at sweep).

-- factionName -> factionID lookup via the static HDG.Constants.REP_FACTIONS
-- table. Catalog factionGate carries only the localized faction name; this
-- maps it to a factionID the C_Reputation APIs can act on. The constants
-- table was built from a Rep Scan (Alliance + Horde merged) + wago.tools
-- Faction.db2 fill-in. Pure table lookup -- no rep-pane walk, no UI taint.
local function _factionIDByName(name)
    if not name or name == "" then return nil end
    local M = HDG.Constants.REP_FACTION_BY_NAME
    return M[name] or M[string.lower(name)]
end


-- Player-faction crest atlases. Prepended to REP gates whose rep-faction is
-- Alliance- or Horde-only (per HDG.Constants.REP_FACTIONS[factionID].faction)
-- so an Alliance char looking at Honorbound decor sees the Horde crest as a
-- visual "you can't earn this rep" cue. Neutral rep-factions get no prefix.
local _FACTION_ATLAS_ALLIANCE = "|A:communities-create-button-wow-alliance:14:14|a"
local _FACTION_ATLAS_HORDE    = "|A:communities-create-button-wow-horde:14:14|a"
local function _factionPrefixFor(factionID)
    if not factionID then return nil end
    local e = HDG.Constants.REP_FACTIONS[factionID]
    if not e then return nil end
    if e.faction == "A" then return _FACTION_ATLAS_ALLIANCE end
    if e.faction == "H" then return _FACTION_ATLAS_HORDE    end
    return nil
end

-- _composeRepProgressSuffix lives in HDG.Format (live progress via detail-panel selector + RepObserver).

-- _bakeSourceTypes: detail-panel "Source: X" label. Priority: Quest > Ach > Vendor > Crafted.
-- Distinct from _bakeSourceTags (binding-strength priority for House donut buckets).
function R:_bakeSourceTypes(row)
    local firstVendor = row.vendors and row.vendors[1]
    if row.quest then
        row.sourceType, row.sourceName = 2, row.quest
    elseif row.achievement then
        row.sourceType, row.sourceName = 1, row.achievement
    elseif firstVendor then
        -- Vendor: surface the first vendor's name (Hesta Forlath) and zone
        -- (Silvermoon City) in the label. Detail-panel renders as
        --   [VEND] Hesta Forlath (Silvermoon City)
        row.sourceType, row.sourceName = 5, firstVendor.name or ""
        row.sourceDetail              = firstVendor.zone or ""
    elseif row.recipe then
        row.sourceType, row.sourceName = 6, row.recipe.expansion or ""
    else
        row.sourceType, row.sourceName = 0, ""
    end
end

-- _bakeSourceTags: canonical source/gate bake. Produces:
--   row.sourceTags[] -- SOURCE_KIND_PRIORITY-ordered list of { kind, text?, ... }
--   row.gateLine     -- compact one-liner from sourceTags[1] (for row factories)
--   row.primarySourceCode -- donor code of sourceTags[1].kind (HDG-compat)
-- DROP fallback when no other signal exists (chip rendering always has something).
-- Aug code 11 (PROFESSION) and 3 (WorldQuest->QUEST) handled as edge cases.
-- _repTagEntry: extracts REP entry; static gate only (live progress via RepObserver).
local function _repTagEntry(row, aug)
    local fg = row.factionGate
    if fg and fg.factionName and fg.factionName ~= "" then
        local standing  = fg.standing or ""
        local factionID = (aug and aug.factionID) or _factionIDByName(fg.factionName)
        return {
            text          = (standing ~= "") and (standing .. " with " .. fg.factionName) or fg.factionName,
            factionName   = fg.factionName,
            standing      = standing,
            factionID     = factionID,
            requiredCode  = _standingStringToCode(standing),
            factionPrefix = _factionPrefixFor(factionID),
        }
    end
    if aug and aug.factionName and aug.factionName ~= "" then
        local standing = _repStandingFromMinRep(aug.minRep) or ""
        return {
            text          = (standing ~= "") and (standing .. " with " .. aug.factionName) or aug.factionName,
            factionName   = aug.factionName,
            standing      = standing,
            factionID     = aug.factionID,
            minRep        = aug.minRep,
            requiredCode  = aug.minRep,   -- ItemAugment minRep IS the standing code
            factionPrefix = _factionPrefixFor(aug.factionID),
        }
    end
    if aug and aug.factionID then return {} end   -- chip-only REP
    return nil
end

function R:_bakeSourceTags(row)
    local aug = HDG.StaticData.ItemAugment and HDG.StaticData.ItemAugment:Get(row.itemID)
    local byKind = {}     -- {[kind] = entry} -- dedupes per-kind contributions
    local order  = {}     -- insertion order; re-sorted by priority at end

    local function emit(kind, entry)
        if not kind or byKind[kind] then return end
        entry.kind = kind
        byKind[kind] = entry
        order[#order+1] = kind
    end

    local repEntry = _repTagEntry(row, aug)
    if repEntry then emit("REP", repEntry) end

    -- Catalog-derived gates (text-carrying).
    if row.quest and row.quest ~= "" then
        emit("QUEST", { text = row.quest })
    end
    if row.achievement and row.achievement ~= "" then
        emit("ACH", { text = row.achievement, achievementID = row.achievementID })
    end
    if row.recipe and row.recipe.expansion and row.recipe.expansion ~= "" then
        emit("CRAFT", {
            text       = row.recipe.expansion,
            profession = row.recipe.profession,
        })
    elseif row.recipe then
        -- Recipe present but no expansion string -- chip-only CRAFT.
        emit("CRAFT", {})
    end

    -- Non-gating signals: chip-only or "Source (Zone)" when descriptor text exists.
    -- Drop/Treasure/Event come from _ParseSourceText (stamps row.drop/treasure/event).
    local function _composeSourceText(rec)
        if not rec then return nil end
        if rec.zone and rec.zone ~= "" then
            return rec.source .. " (" .. rec.zone .. ")"
        end
        return rec.source
    end

    if row.vendors and #row.vendors > 0 then emit("VENDOR", {}) end
    if row.drop      then emit("DROP",     { text = _composeSourceText(row.drop)     }) end
    if row.treasure  then emit("TREASURE", { text = _composeSourceText(row.treasure) }) end
    if row.event     then emit("EVENT",    { text = _composeSourceText(row.event)    }) end
    if row.shop      then emit("SHOP",     {}) end   -- catalog bare "Shop"/"In-Game Shop" line

    -- type->kind mapper: type 3 (WQ) -> QUEST; type 11 (PROFESSION) dropped; else donor index.
    local function fromSourceType(code)
        if code == 3  then return "QUEST" end
        if code == 11 then return nil end
        local kind = HDG.Constants.SOURCE_KIND_BY_DONOR[code]
        return kind and kind.key
    end

    -- ItemAugment signals: catalog-undetectable kinds (SHOP/PROMO/TREASURE/DROP/etc).
    -- VENDOR is chip-only. emit() dedupes per kind (catalog signal wins).
    if aug and aug.sources then
        for _, s in ipairs(aug.sources) do
            local k = s.type and fromSourceType(s.type)
            if k == "VENDOR" then
                emit(k, {})
            elseif k then
                local txt = (s.name and s.name ~= "")
                    and _composeSourceText({ source = s.name, zone = s.detail }) or nil
                emit(k, { text = txt })
            end
        end
    end

    -- CatalogOverrides sources (row.sources): real vendor/source for placeholder
    -- catalog entries (Chel the Chip, Disguised Decor Duel Vendor etc -> else [DROP]).
    -- VENDOR chip-only; other kinds carry the override's name+zone text.
    if row.sources then
        for _, s in ipairs(row.sources) do
            local k = s.type and fromSourceType(s.type)
            if k == "VENDOR" then
                emit(k, {})
            elseif k then
                local txt = s.name and _composeSourceText({ source = s.name, zone = s.detail }) or nil
                emit(k, { text = txt })
            end
        end
    end

    -- DROP fallback: items with no other source signal default to a chip-
    -- only DROP entry (no text -- nothing specific to say beyond "drops").
    if #order == 0 then emit("DROP", {}) end

    -- Sort by SOURCE_KIND_PRIORITY; head entry is highest-priority kind (gateLine + primarySourceCode).
    local tags = {}
    for _, key in ipairs(HDG.Constants.SOURCE_KIND_PRIORITY) do
        if byKind[key] then tags[#tags+1] = byKind[key] end
    end
    row.sourceTags = tags

    -- Derived single-value fields for back-compat.
    local head = tags[1]
    if head and head.text then
        -- Compact "[CHIP]  text" with optional faction crest prefix.
        local prefix = head.factionPrefix and (head.factionPrefix .. " ") or ""
        row.gateLine = prefix .. HDG.Format.SourceChip(head.kind) .. "  " .. head.text
    else
        row.gateLine = nil
    end
    row.primarySourceCode = (head and HDG.Constants.SOURCE_KIND_BY_KEY[head.kind].donorCode) or 0
end

-- _bakeBonusXp: first-acquisition XP chip. Baked when bonus > 0; render gated by isOwned at consumer.
function R:_bakeBonusXp(row)
    local fab = row.firstAcquisitionBonus or 0  -- exception(boundary): catalog struct field sparse
    if fab > 0 then
        row.bonusXpLabel = XP_ICON .. " +" .. fab .. " XP"
    end
end

-- _bakeRecipe: cross-join with StaticData.Recipes. row.recipe nil when not crafted;
-- row.recipeLabel = "Profession - Requires Rep" for the detail panel.
function R:_bakeRecipe(row)
    local Recipes = HDG.StaticData.Recipes
    if not Recipes then row.recipe, row.recipeLabel = nil, nil; return end
    local rec = Recipes:Get(row.itemID)
    if not rec then row.recipe, row.recipeLabel = nil, nil; return end
    row.recipe = rec
    local parts = {}
    if rec.profession   and rec.profession   ~= "" then parts[#parts+1] = rec.profession end
    if rec.requiresRep  and rec.requiresRep  ~= "" then parts[#parts+1] = rec.requiresRep end
    row.recipeLabel = table.concat(parts, " - ")
end

-- _ParseSourceText: extract Vendor:/Zone:/Faction:/Cost:/Quest:/Achievement:/Category:
-- lines. Multi-vendor items repeat the Vendor/Zone/Faction/Cost block.
-- row.factionGate = first Faction: line; selectors fall back to ItemAugment if absent.
--
-- _extractCostEntries: parse {currencyID, amount, icon} from the RAW Cost: line.
-- MUST be raw (not SHL-stripped) -- SHL nukes |Hcurrency:<id>|h wrappers.
-- The catalog-embedded icon is always correct; avoids a stale hand-curated table
-- and won't drop currencies outside it (boundary: any currency in Cost: IS a decor cost).
local function _extractCostEntries(raw)
    local iconByID = {}
    for cid, icon in raw:gmatch("|Hcurrency:(%d+)|h|T([^:|]+)") do
        iconByID[tonumber(cid)] = icon
    end
    local entries = {}
    for amt, cid in raw:gmatch("([%d,]+)%s*|Hcurrency:(%d+)|h") do
        local n  = tonumber((amt:gsub(",", "")))
        local id = tonumber(cid)
        if n and id then
            entries[#entries + 1] = { currencyID = id, amount = n, icon = iconByID[id] }
        end
    end
    return entries
end

function R:_ParseSourceText(sourceText, row)
    -- Always stamp row.vendors = {} so downstream ipairs(row.vendors) is safe.
    -- exception(boundary): quest-only items have empty sourceText -> row.vendors was nil, exploding consumers.
    if sourceText == "" then row.vendors = {}; return end
    -- Per-line walk: SHL gives display line for prefix matching; raw line kept for cost-entry
    -- extraction (SHL nukes |Hcurrency:<id>|h even with maintainTextures=true).
    local rawText = sourceText:gsub("|n", "\n")
    local SHL = _G.C_StringUtil.StripHyperlinks
    local SOURCE_TOKENS = HDG.Constants.CATALOG_SOURCE_TOKENS

    local vendors = {}
    local current = nil
    -- Tracks the active Drop:/Treasure:/Event: record so the following Zone: line can fill .zone.
    local pendingZoneTarget = nil
    for raw in rawText:gmatch("[^\n]+") do
        local line = SHL(raw, false, false, false, false, false)
        line = line:match("^%s*(.-)%s*$") or line  -- trim
        local vName    = line:match("^Vendors?:%s*(.+)")  -- matches Vendor: AND Vendors:
        local zone     = line:match("^Zone:%s*(.+)")
        local fac      = line:match("^Faction:%s*(.+)")
        local renown   = line:match("^Renown:%s*(.+)")
        local cost     = line:match("^Cost:%s*(.+)")
        local quest    = line:match("^Quest:%s*(.+)")
        local ach      = line:match("^Achievement:%s*(.+)")
        local cat      = line:match("^Category:%s*(.+)")
        local drop     = line:match("^Drop:%s*(.+)")
        local treasure = line:match("^Treasure:%s*(.+)")
        local event    = line:match("^Event:%s*(.+)")
        -- Bare-line source (no colon): Shop / In-Game Shop. Other bare lines
        -- (e.g. a stray "Profession") are not in the table -> nil -> ignored.
        local bareKind = SOURCE_TOKENS[line]
        if vName then
            if current then table.insert(vendors, current) end
            current = { name = vName, zone = "", cost = "", faction = "", standing = "" }
            pendingZoneTarget = nil
        elseif drop then
            -- "Drop: <Source>" optional "Zone:" follows via pendingZoneTarget.
            row.drop = { source = drop }
            pendingZoneTarget = row.drop
        elseif treasure then
            row.treasure = { source = treasure }
            pendingZoneTarget = row.treasure
        elseif event then
            row.event = { source = event }
            pendingZoneTarget = row.event
        elseif bareKind == "SHOP" then
            -- Bare "Shop"/"In-Game Shop" line. NOTE: Profession: lines deliberately
            -- not handled here (CRAFT comes from recipe DB; catalog 'prof' false-positives).
            row.shop = true
            pendingZoneTarget = nil
        elseif zone and current then
            current.zone = zone
        elseif zone and pendingZoneTarget then
            pendingZoneTarget.zone = zone
            pendingZoneTarget = nil
        elseif fac and current then
            local fName, standing = fac:match("(.-)%s*-%s*(.+)")
            current.faction  = fName or fac
            current.standing = standing or ""
            -- row.factionGate: first Faction: wins. Selectors fall back to ItemAugment when absent.
            row.factionGate = row.factionGate or {
                factionName = current.faction,
                standing    = current.standing,
            }
        elseif renown then
            -- "Renown: N" -- standing for the preceding Faction: gate (catalog splits name + level).
            if current then current.standing = renown end
            if row.factionGate and (row.factionGate.standing or "") == "" then
                row.factionGate.standing = renown
            end
            pendingZoneTarget = nil
        elseif cost and current then
            current.cost = cost
            -- Parse currencies from raw line (SHL strips |Hcurrency: wrappers).
            local entries = _extractCostEntries(raw)
            if next(entries) then current.costEntries = entries end
        elseif quest then
            row.quest = quest
        elseif ach then
            row.achievement = ach
        elseif cat then
            row.category = cat
        elseif current and raw:match("|Hcurrency:") then
            -- Bare cost line (no "Cost:" prefix): achievement-vendor catalog format
            -- (e.g. "800|Hcurrency:3392|h"). Same handling as the Cost: branch.
            current.cost = line
            local entries = _extractCostEntries(raw)
            if next(entries) then current.costEntries = entries end
        end
    end
    if current then table.insert(vendors, current) end
    row.vendors = vendors
end

-- ===== Public API ============================================================
-- Methods gate on IsReady(). nil/empty while loading is a CONTRACT (ADR-008/022).

function R:IsReady()
    local s = HDG.Store:GetState().session.catalog
    return s and s.status == "ready"
end

-- C_DyeColor accessor (sole owner; all reads funnel through here). nil on unknown/invalid id.
function R:GetDyeColorInfo(dyeColorID)
    if not dyeColorID then return nil end
    return _G.C_DyeColor.GetDyeColorInfo(dyeColorID)   -- exception(boundary): nil on unknown/invalid id
end

function R:GetRow(itemID)
    if not R:IsReady() then return nil end
    return R.byItemID[itemID]
end

-- GetVariantDyes: 0/1/2-channel dye map for a dyed variant; nil for base or non-dyed.
-- Drives model preview SetGradientMaskWithDyes from the baked row.dyedVariants.
function R:GetVariantDyes(itemID, variantKey)
    local row = R.byItemID[itemID]
    if not (row and row.dyedVariants) then return nil end
    local vid = tostring(variantKey):match(":(.+)$")
    if not vid or vid == "base" then return nil end
    vid = tonumber(vid)
    for _, dv in ipairs(row.dyedVariants) do
        if dv.variantIdentifier == vid then return dv.dyeColorsByChannel end
    end
    return nil
end

-- IsOwned: canonical ownership predicate. Three real fields: quantity + remainingRedeemable
-- + numPlaced (per Blizzard_HousingTemplates/HousingCatalogEntry.lua:437-438).
-- DEAD fields (boundary: always nil at runtime): numStored, totalNumStored, totalNumPlaced.
-- Accepts a row table, itemID, or decorID. Returns false for unknown inputs.
function R:IsOwned(rowOrID)
    local row
    if type(rowOrID) == "table" then
        row = rowOrID
    elseif type(rowOrID) == "number" then
        row = R.byItemID[rowOrID] or R.byDecorID[rowOrID]
    end
    if not row then return false end
    return ((row.quantity or 0)  -- exception(boundary): catalog struct field sparse
         + (row.remainingRedeemable or 0)  -- exception(boundary): catalog struct field sparse
         + (row.numPlaced or 0)) > 0  -- exception(boundary): catalog struct field sparse
end

-- decorID -> itemID via byDecorID (used by ShoppingCodec + StyleEngine).
function R:GetItemIDByDecorID(decorID)
    if not decorID then return nil end
    local row = R.byDecorID[decorID]
    return row and row.itemID
end

-- itemID -> decorID (rows carry decorID).
function R:GetDecorIDByItemID(itemID)
    if not itemID then return nil end
    local row = R.byItemID[itemID]
    return row and row.decorID
end

-- Full decorID -> itemID map (StyleSerializer batch-convert).
function R:GetItemIDByDecorIDMap()
    return R.byDecorID  -- [decorID] = row; callers need .itemID field
end

-- Full itemID -> decorID map (StyleSerializer export, useDecorID=true). Built on demand.
function R:GetDecorIDByItemIDMap()
    local out = {}
    for itemID, row in pairs(R.byItemID) do
        if row.decorID then out[itemID] = row.decorID end
    end
    return out
end

function R:GetIcon(itemID)
    local row = R:GetRow(itemID)
    return row and row.iconTexture
end

function R:GetExpansionForItem(itemID)
    local row = R:GetRow(itemID)
    if not (row and row.dataTagsByID) then return nil end
    for tagID, displayName in pairs(row.dataTagsByID) do
        if R.tagIDToGroup[tagID] == "Expansion" then
            return displayName
        end
    end
    return nil
end

function R:GetVendorsForItem(itemID)
    local row = R:GetRow(itemID)
    return row and row.vendors
end

function R:GetFactionGateForItem(itemID)
    local row = R:GetRow(itemID)
    return row and row.factionGate
end

function R:GetCategoryForItem(itemID)
    local row = R:GetRow(itemID)
    return row and row.category
end

function R:GetBindTypeForItem(itemID)
    local row = R:GetRow(itemID)
    if not row then return nil end
    return (row.category == "Professions") and "BoE" or "BoP"
end

function R:GetItemsByVendor(vendorName, vendorZone)
    if not R:IsReady() then return nil end
        -- byVendor keyed by (name, zone); ~9 display names are shared across zones.
    return R.byVendor[(vendorName or "") .. "::" .. (vendorZone or "")]
end

function R:GetAllVendorNames()
    if not R:IsReady() then return {} end
    return R.allVendorNames
end

function R:IterateRows(fn)
    if not R:IsReady() then return end
    for itemID, row in pairs(R.byItemID) do fn(itemID, row) end
end

function R:GetItemCount()
    if not R:IsReady() then return 0 end
    local n = 0
    for _ in pairs(R.byItemID) do n = n + 1 end
    return n
end

-- ===== Synchronous per-item resolver =========================================
-- Resolve() wraps C_HousingCatalog.GetCatalogEntryInfoByRecordID.
-- Failures are silent here; the widget treats nil as "Preview unavailable".
local DECOR_CATALOG_ID = 1   -- Blizzard's housing catalog is catalog 1

function R:Resolve(itemID)
    if type(itemID) ~= "number" then return nil end

    -- Primary: byItemID; falls back to Recipes for recipe-only paths and cold catalog.
    local decorID
    local nameFallback
    local catalogRow = R.byItemID[itemID]
    if catalogRow then
        decorID      = catalogRow.decorID
        nameFallback = catalogRow.name
    else
        local db = HDG.StaticData.Recipes:GetAll()
        local entry = db and db[itemID]
        decorID      = entry and entry.decorID
        nameFallback = entry and entry.name
    end
    if not decorID then return nil end

    local cat = _G.C_HousingCatalog
    if not (cat and cat.GetCatalogEntryInfoByRecordID) then return nil end
    -- exception(boundary): 12.0.5 dropped the 3rd arg (tryGetOwnedInfo); 3-arg throws "bad argument #2".
    local info = cat.GetCatalogEntryInfoByRecordID(DECOR_CATALOG_ID, decorID)
    if type(info) ~= "table" then return nil end

    return {
        asset           = info.asset,
        uiModelSceneID  = info.uiModelSceneID,
        iconTexture     = info.iconTexture,
        iconAtlas       = info.iconAtlas,
        name            = info.name or nameFallback,
    }
end

-- ===== Load-on-demand lifecycle =============================================
-- Sweep fires when a catalog-consuming view first activates (CATALOG_CONSUMING_TAB_VIEWS).

-- RequestLoad: idempotent cold-start trigger (only when status == "idle").
function R:RequestLoad()
    local s = HDG.Store:GetState().session.catalog
    if s.status ~= "idle" then return end
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.CATALOG_LOAD_REQUESTED })
    R:_RunSweep()
end

function R:Refresh()    R:_RunSweep() end
function R:_RunSweep()  R:ReconcileFull() end

-- ===== Room catalog =========================================================
-- Second persistent searcher in Layout mode (C_HousingCatalog owned here; one namespace per module).
-- Same lifecycle as the decor searcher; cheap (~20 entries) so no settle timer.
function R:_EnsureRoomSearcher()
    if self._roomSearcher then return self._roomSearcher end
    if not (_G.C_HousingCatalog and _G.C_HousingCatalog.CreateCatalogSearcher) then return nil end
    local s = _G.C_HousingCatalog.CreateCatalogSearcher()
    if not s then return nil end
    self._roomSearcher = s
    s:SetResultsUpdatedCallback(function() R:_OnRoomResults(s) end)
    return s
end

-- Room searcher config: decor config with editorModeContext=Layout + storedOnly=false.
function R:_ConfigureRoomSearcher(s)
    s:SetAutoUpdateOnParamChanges(false)
    s:SetStoredOnly(false)
    s:SetBaseVariantOnly(true)
    s:SetEditorModeContext(_G.Enum.HouseEditorMode.Layout)   -- ROOMS, not decor
    s:SetCustomizableOnly(false)
    s:SetAllowedIndoors(true)
    s:SetAllowedOutdoors(true)
    s:SetCollected(true)
    s:SetUncollected(true)
    s:SetFirstAcquisitionBonusOnly(false)
    s:SetFilteredCategoryID(_allCategoryID())
    s:SetFilteredSubcategoryID(nil)
    for _, group in ipairs(_G.C_HousingCatalog.GetAllFilterTagGroups() or {}) do
        s:SetAllInFilterTagGroup(group.groupID, true)
    end
    s:SetAutoUpdateOnParamChanges(true)
end

-- ReconcileRooms: (re)configure the room searcher + RunSearch.
function R:ReconcileRooms()
    local s = self:_EnsureRoomSearcher()
    if not s then return end   -- exception(boundary): C_HousingCatalog unavailable (decor path logs it)
    self:_ConfigureRoomSearcher(s)
    s:RunSearch()
end

-- _OnRoomResults: snapshot Layout-mode results. Stock = totalNumStored+totalNumPlaced>0;
-- geometry via ShapeAtlas.ShapeForRecordID. byShapeID = palette/stock lookup; entries = full list.
function R:_OnRoomResults(searcher)
    if not (searcher and searcher.GetCatalogSearchResults) then return end
    local items = searcher:GetCatalogSearchResults()
    if not items or #items == 0 then return end   -- exception(boundary): catalog priming / searcher race -> next event re-kicks
    local HC    = _G.C_HousingCatalog
    local Shape = HDG.Projects.ShapeAtlas
    local byShapeID, entries = {}, {}
    for _, ev in ipairs(items) do
        local info = HC.GetCatalogEntryInfo(ev)
        if info then   -- exception(boundary): nil for an uncached entry; it returns on a later sweep
            local stored  = info.totalNumStored or 0   -- exception(boundary): external struct field
            local placed  = info.totalNumPlaced or 0  -- exception(boundary): Blizzard struct field sparse
            local shapeID = Shape.ShapeForRecordID(ev.recordID)
            local entry = {
                recordID          = ev.recordID,
                variantIdentifier = ev.variantIdentifier,
                shapeID           = shapeID,
                name              = info.name,
                iconAtlas         = info.iconAtlas,
                iconTexture       = info.iconTexture,
                placementCost     = info.placementCost,
                numStored         = stored,
                numPlaced         = placed,
                quantity          = info.quantity,
                owned             = (stored + placed) > 0,
                isAllowedIndoors  = info.isAllowedIndoors,
                isAllowedOutdoors = info.isAllowedOutdoors,
                isPrefab          = info.isPrefab,
                quality           = info.quality,
            }
            entries[#entries + 1] = entry
            if shapeID then byShapeID[shapeID] = entry end
        end
    end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.PROJECTS_ROOM_CATALOG_UPDATED,
        payload = { byShapeID = byShapeID, entries = entries },
    })
end

-- ===== Category nav tree ====================================================
-- Snapshot of session.house.categoryTree for the Curator + Projects decor picker.
-- Atlas state suffix stripped once here; selectors append at render (Inv 1).

-- Strip atlas state suffix (e.g. "_active"). "_active-parent" tried first (longest-first to avoid half-strip).
local _CAT_ATLAS_MODIFIERS = { "_active%-parent", "_inactive", "_pressed", "_active" }
local function _stripCategoryAtlas(icon)
    if not icon or icon == "" then return nil end   -- exception(boundary): icon is a nilable API field
    for _, mod in ipairs(_CAT_ATLAS_MODIFIERS) do
        local base = icon:gsub(mod, "")
        if base ~= icon then return base end
    end
    return icon
end

-- Full category tree walk + dispatch. rootIDs unfiltered; selectors apply storedOnly via anyStoredEntries.
function R:_RebuildCategoryTree()
    local HC = _G.C_HousingCatalog
    if not (HC and HC.SearchCatalogCategories) then return end   -- exception(boundary): API namespace not present yet
    -- BasicDecor mode: decor categories only; editorModeContext excludes Room.
    local catIDs = HC.SearchCatalogCategories({
        withStoredEntriesOnly   = false,
        includeFeaturedCategory = true,
        editorModeContext       = _G.Enum.HouseEditorMode.BasicDecor,
    })
    if not catIDs or #catIDs == 0 then return end   -- exception(boundary): catalog priming -> next event re-kicks
    local byID, subcatByID, rootIDs = {}, {}, {}
    for _, catID in ipairs(catIDs) do
        local info = HC.GetCatalogCategoryInfo(catID)
        if info then   -- exception(boundary): nil for an uncached category
            local subIDs = info.subcategoryIDs or {}   -- exception(boundary): external struct field
            byID[catID] = {
                id               = catID,
                name             = info.name,                -- nilable per API
                iconBase         = _stripCategoryAtlas(info.icon),
                orderIndex       = info.orderIndex or 0,     -- exception(boundary): external struct field
                subcategoryIDs   = subIDs,
                anyStoredEntries = info.anyStoredEntries,
            }
            rootIDs[#rootIDs + 1] = catID
            for _, subID in ipairs(subIDs) do
                if not subcatByID[subID] then
                    local sub = HC.GetCatalogSubcategoryInfo(subID)
                    if sub then   -- exception(boundary): nil for an uncached subcategory
                        subcatByID[subID] = {
                            id               = subID,
                            name             = sub.name,
                            iconBase         = _stripCategoryAtlas(sub.icon),
                            orderIndex       = sub.orderIndex or 0,  -- exception(boundary): Blizzard struct field sparse
                            parentCategoryID = sub.parentCategoryID,
                            anyStoredEntries = sub.anyStoredEntries,
                        }
                    end
                end
            end
        end
    end
    table.sort(rootIDs, function(a, b) return byID[a].orderIndex < byID[b].orderIndex end)
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.CATALOG_CATEGORY_TREE_UPDATED,
        payload = { byID = byID, subcatByID = subcatByID, rootIDs = rootIDs },
    })
end

function R:_CancelCategoryTreeTimer()
    if self._categoryTreeTimer then
        if self._categoryTreeTimer.Cancel then self._categoryTreeTimer:Cancel() end   -- exception(boundary): C_Timer API
        self._categoryTreeTimer = nil
    end
end

-- Coalesce HOUSING_CATALOG_(SUB)CATEGORY_UPDATED bursts. Own timer (no cross-trigger with decor settle).
function R:QueueCategoryTreeRebuild()
    self:_CancelCategoryTreeTimer()
    self._categoryTreeTimer = C_Timer.NewTimer(0.4, function()
        self._categoryTreeTimer = nil
        R:_RebuildCategoryTree()
    end)
end

-- _OnViewChange: routes to RequestLoad (cold) or Refresh (deferred) based on catalog state.
function R:_OnViewChange(view)
    if not HDG.Constants.CATALOG_CONSUMING_TAB_VIEWS[view] then return end
    local s = HDG.Store:GetState().session.catalog
    if s.status == "idle" then
        R:RequestLoad()
    elseif s.refreshPending then
        R:Refresh()
    end
end

-- ===== In-memory row mutations ===============================================
-- Observer owns byDecorID/byItemID. Called from onEnable subscriber on per-entry
-- events (ROW_ADDED / ROW_REMOVED / COUNTS_UPDATED) between full sweeps.

function R:UpsertRow(decorID, entry)
    if not (decorID and entry) then return end
    local row = entry
    R.byDecorID[decorID] = row
    if row.itemID then R.byItemID[row.itemID] = row end
end

function R:RemoveRow(decorID)
    if not decorID then return end
    local row = R.byDecorID[decorID]
    if row and row.itemID then R.byItemID[row.itemID] = nil end
    R.byDecorID[decorID] = nil
end

function R:PatchCounts(decorID, counts)
    if not (decorID and counts) then return end
    local row = R.byDecorID[decorID]
    if not row then return end
    row.quantity                 = counts.quantity                 or 0  -- exception(boundary): Blizzard struct field sparse
    row.numPlaced                = counts.numPlaced                or 0  -- exception(boundary): Blizzard struct field sparse
    row.remainingRedeemable      = counts.remainingRedeemable      or 0  -- exception(boundary): Blizzard struct field sparse
    row.destroyableInstanceCount = counts.destroyableInstanceCount or 0  -- exception(boundary): Blizzard struct field sparse
    row.firstAcquisitionBonus    = counts.firstAcquisitionBonus    or 0  -- exception(boundary): Blizzard struct field sparse
    row.isOwned = R:IsOwned(row)
end

function R:ClearStore()
    R.byDecorID = {}
    R.byItemID  = {}
    R.byVendor  = {}
    R.allVendorNames = {}
    R._catalogSchemaVersion = 0
end

-- ===== Module registration ====================================================
-- BlizzardEvents resolves handlers via mod[handler]; functions live on the module
-- def table and delegate to singleton R.

HDG.Modules:Declare({
    name = "HousingCatalogObserver",
    ownsBlizzardNamespaces = { "C_HousingCatalog", "C_DyeColor" },
    -- Store is a top-level engine, not a module. No dependencies.
    dependencies = {},
    logTags = {
        catalog_swept     = { user = false, level = "debug"   },
        catalog_refreshed = { user = true,  level = "success", duration = 5    },
        catalog_error     = { user = true,  level = "error",   duration = nil  },
        catalog_validated = { user = false, level = "debug"   },
    },
    blizzardEvents = {
        -- Queuing model: events dispatch CATALOG_REFRESH_QUEUED regardless of window state.
        -- Actual sweep deferred to next catalog-tab activation (UI_SET_PERSISTENT subscriber).
        HOUSING_STORAGE_UPDATED              = { handler = "OnHousingStorageUpdated", debounce = 0.5 },
        HOUSING_STORAGE_ENTRY_UPDATED        = { handler = "OnHousingStorageEntryUpdated" },
        HOUSING_CATALOG_CATEGORY_UPDATED     = { handler = "OnHousingCatalogChange" },
        HOUSING_CATALOG_SUBCATEGORY_UPDATED  = { handler = "OnHousingCatalogChange" },
        -- (HOUSING_DECOR_PLACE_SUCCESS/REMOVED/etc. are NOT here: redundant with
        -- the storage signals + their decorGUID is nil -- they can't drive a
        -- targeted update. In-editor place/remove is captured granularly via the
        -- per-entry HOUSING_STORAGE_ENTRY_UPDATED below, exactly as Blizzard's own
        -- HouseEditorStorageFrame does. The earlier full-sweep-per-event approach
        -- stormed the catalog index sweep -- see the perf profile.)
    },
    -- Handlers are pure dispatch sites; sweep deferred to UI_SET_PERSISTENT subscriber.
    OnHousingStorageUpdated = function(self)
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.CATALOG_REFRESH_QUEUED })
    end,
    OnHousingStorageEntryUpdated = function(self, entryID)
        -- Per-entry reconcile: targeted path (Blizzard's HouseEditorStorageFrame pattern).
        -- Only path that emits COLLECTION_ITEM_LEARNED + CRAFT_HISTORY_PUSH for newly-owned decor.
        -- exception(boundary): entry data is already fresh in Blizzard's cache when this event fires.
        if entryID then
            R:ReconcileEntry(entryID)
            return
        end
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.CATALOG_REFRESH_QUEUED })
    end,
    OnHousingCatalogChange = function(self)
        -- Rare hotfix events. Same queuing semantics.
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.CATALOG_REFRESH_QUEUED })
    end,
    onEnable = function(self)
        local A = HDG.Constants.ACTIONS
        -- UI_SET_PERSISTENT: load-on-demand trigger (filter on account.ui.view writes).
        -- Also handles row mutations (ROW_ADDED/REMOVED/COUNTS_UPDATED) and COLLECTION_RESET
        -- so byDecorID/byItemID stay consistent (observer = sole writer; reducer = no-op).
        self._storeToken = HDG.Store:Subscribe(function(actionType, invalidation, action)
            if actionType == A.UI_SET_PERSISTENT then
                -- Only proceed when account.ui.view was the written key.
                if type(invalidation) == "table" and invalidation[1] ~= "account.ui.view" then return end
                local view = HDG.Store:GetState().account.ui.view
                if view then R:_OnViewChange(view) end
            elseif actionType == A.MAIN_WINDOW_OPENING then
                -- Load unconditionally on first open (most views derive from the catalog).
                -- RequestLoad is idempotent; re-opens are no-ops.
                R:RequestLoad()
                R:ReconcileRooms()          -- live room catalog (cheap; Layout-mode searcher)
                R:QueueCategoryTreeRebuild()   -- Blizzard category/subcategory nav snapshot
            elseif actionType == A.MAIN_WINDOW_TOGGLE then
                -- Resume/pause searcher auto-update with window show/hide (Blizzard symmetry).
                if R._searcher then
                    R._searcher:SetAutoUpdateOnParamChanges(
                        HDG.Store:GetState().account.ui.mainWindowShown == true)
                end
            elseif actionType == A.CATALOG_REFRESH_QUEUED then
                -- Drain immediately when window is shown so open views reflect just-collected items.
                -- Still LOADING: re-kick ReconcileFull (tag groups may now be present).
                -- Editor-only (window closed): skip full sweep; HOUSING_STORAGE_ENTRY_UPDATED
                -- captures in-editor changes via ReconcileEntry (targeted; avoids 1673-entry storm).
                if HDG.Store:GetState().account.ui.mainWindowShown then
                    if HDG.Store:GetState().session.catalog.status == "loading" then
                        R:ReconcileFull()
                    else
                        R:_OnViewChange(HDG.Store:GetState().account.ui.view)
                    end
                    R:ReconcileRooms()         -- storage change -> refresh room stock too
                    R:QueueCategoryTreeRebuild()   -- category ownership (anyStoredEntries) may have changed
                end
            elseif actionType == A.COLLECTION_CATALOG_ROW_ADDED then
                if action and action.payload then
                    R:UpsertRow(action.payload.decorID, action.payload.entry)
                end
            elseif actionType == A.COLLECTION_CATALOG_ROW_REMOVED then
                if action and action.payload then
                    R:RemoveRow(action.payload.decorID)
                end
            elseif actionType == A.COLLECTION_CATALOG_ROW_COUNTS_UPDATED then
                if action and action.payload then
                    R:PatchCounts(action.payload.decorID, action.payload.counts)
                end
            elseif actionType == A.COLLECTION_RESET then
                R:ClearStore()
            -- COLLECTION_BULK_LOAD: handled reducer-side only (writes ownedDecorIDs).
            end
        end)
    end,
    onShutdown = function(self)
        R:_CancelSettleTimer()
        R:_CancelCategoryTreeTimer()
        if self._storeToken then
            HDG.Store:Unsubscribe(self._storeToken)
            self._storeToken = nil
        end
    end,
})
