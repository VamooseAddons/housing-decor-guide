-- HDG.Selectors -- HouseTab dashboard
-- ============================================================================
-- ~25 HouseTab dashboard widget selectors. HouseAggregator builds a snapshot
-- on every relevant dispatch (debounced 100ms); selectors derive per-widget
-- shapes from that snapshot + account-side layout overrides.
--
-- Snapshot-derived selectors read snapshotTick (atomic rebuild; one tick
-- invalidates every consumer). Layout-override selectors use narrow path reads.

HDG = HDG or {}
HDG.Selectors = HDG.Selectors or {}
local Selectors = HDG.Selectors

-- ============================================================================
-- Bare-path selectors (chrome state)
-- ============================================================================

Selectors:Register("house.snapshot", {
    reads = {"session.house.snapshot", "session.house.snapshotTick"},
    fn    = function(state) return state.session.house.snapshot end,
})

Selectors:Register("house.snapshotTick", {
    reads = {"session.house.snapshotTick"},
    fn    = function(state) return state.session.house.snapshotTick end,
})

Selectors:Register("houseTab.pickerOpen", {
    reads = {"session.ui.houseTab.pickerOpen"},
    fn    = function(state) return state.session.ui.houseTab.pickerOpen end,
})

-- Dynamic columns: dashboard always 840px; picker column (320) appears when open.
-- Column removed (not hidden) on close so chrome/status colSpan cells shrink.
-- Column-collapse-via-visible doesn't work because they mark col 2 live via colSpan.
Selectors:Register("house.viewColumns", {
    reads = {"session.ui.houseTab.pickerOpen"},
    fn = function(state)
        if state.session.ui.houseTab.pickerOpen then
            return { 840, 320 }
        end
        return { 840 }
    end,
})

Selectors:Register("houseTab.designMode", {
    reads = {"session.ui.houseTab.designMode"},
    fn    = function(state) return state.session.ui.houseTab.designMode end,
})

-- Header button labels (bind to button widgets via `binding = "..."`).
Selectors:Register("house.pickerButtonLabel", {
    reads = {"session.ui.houseTab.pickerOpen"},
    fn = function(state)
        return state.session.ui.houseTab.pickerOpen and "Close Picker" or "Customise"
    end,
})
Selectors:Register("house.designButtonLabel", {
    reads = {"session.ui.houseTab.designMode"},
    fn = function(state)
        return state.session.ui.houseTab.designMode and "Exit Design" or "Design Mode"
    end,
})

-- ============================================================================
-- Title tier: { current, prev, next, withinTierProgress (0..1) }.
-- Aggregator resolves the tier triple; selector adds within-tier progress for the status bar.
-- ============================================================================

Selectors:Register("house.titleTier", {
    reads = {"session.house.snapshotTick"},
    calls = {"house.snapshot"},
    fn = function(state, ctx)
        local snap = Selectors:Call("house.snapshot", state, ctx)
        local tier = snap.titleTier
        if not tier then
            return { current = nil, prev = nil, next = nil, withinTierProgress = 0 }
        end
        local owned = snap.collectedAll or 0  -- exception(boundary): snapshot {} until first aggregator build
        local prevThreshold = (tier.prev and tier.prev.threshold) or 0
        local nextThreshold = tier.next and tier.next.threshold
        local progress = 1   -- 100% if no next tier (capped at top)
        if nextThreshold and nextThreshold > prevThreshold then
            local raw = (owned - prevThreshold) / (nextThreshold - prevThreshold)
            if raw < 0 then progress = 0
            elseif raw > 1 then progress = 1
            else progress = raw end
        end
        return {
            current            = tier.current,
            prev               = tier.prev,
            next               = tier.next,
            withinTierProgress = progress,
        }
    end,
})

-- ============================================================================
-- Per-widget data envelopes. house.widgetRows stamps these into cell.data
-- so row factories read from ed without a Store dive (skill section 6).
-- ============================================================================

-- decoratorProfile: title tier + house identity + within-tier progress.
-- Active house: match ownedHouses by neighborhoodGUID against activeNeighborhoodGUID.
-- Falls back to first owned house pre-NEIGHBORHOOD_INITIATIVE_UPDATED.
Selectors:Register("house.decoratorProfileData", {
    reads = {
        "session.house.snapshotTick",
        "session.house.ownedHouses",
        "session.house.activeNeighborhoodGUID",
        "session.daily.bestowed",
    },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        local snap = Selectors:Call("house.snapshot", state, ctx)
        local owned = state.session.house.ownedHouses
        local activeGUID = state.session.house.activeNeighborhoodGUID
        local bestowed = state.session.daily.bestowed

        local activeHouse
        if activeGUID then
            for _, h in pairs(owned) do
                if h.neighborhoodGUID == activeGUID then
                    activeHouse = h
                    break
                end
            end
        end
        if not activeHouse then
            for _, h in pairs(owned) do
                activeHouse = h
                break
            end
        end

        return {
            title        = snap.title,
            titleTier    = snap.titleTier,
            -- exception(boundary): snapshot {} until first aggregator build (deferred to window-open
            -- to dodge the cold-client housing-C CTD); strict-read numbers default here.
            collectedAll = snap.collectedAll or 0,  -- exception(boundary): house snapshot {} until aggregator build
            totalAll     = snap.totalAll or 0,  -- exception(boundary): house snapshot {} until aggregator build
            houseName       = activeHouse and activeHouse.name,
            houseFaction    = activeHouse and activeHouse.faction,
            houseLevel      = activeHouse and activeHouse.level,
            houseFavor      = activeHouse and activeHouse.favor,
            houseMaxLevel   = activeHouse and activeHouse.maxLevel,
            houseThresholds = activeHouse and activeHouse.thresholds,
            bestowedName    = bestowed and bestowed.name,
            bestowedQuote   = bestowed and bestowed.quote,
            trophies          = snap.trophies or {},
            trophiesCollected = snap.trophiesCollected or 0,  -- exception(boundary): house snapshot {} until aggregator build
            trophiesTotal     = snap.trophiesTotal or 0,  -- exception(boundary): house snapshot {} until aggregator build
        }
    end,
})

-- sourceDonut: bySource sorted by collected DESC.
Selectors:Register("house.sourceDonutData", {
    reads = { "session.house.snapshotTick", "session.catalog.sweepGeneration" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        local snap = Selectors:Call("house.snapshot", state, ctx)
        local list = {}
        for srcType, b in pairs(snap.bySource or {}) do
            list[#list + 1] = {
                sourceType = srcType,
                total      = b.total,
                collected  = b.collected,
                pct        = b.pct,
            }
        end
        table.sort(list, function(a, b) return a.collected > b.collected end)
        return {
            buckets      = list,
            -- exception(boundary): snapshot {} until first aggregator build; default to 0
            -- so strict-reads (compare/divide) render 0% instead of erroring.
            collectedAll = snap.collectedAll or 0,  -- exception(boundary): house snapshot {} until aggregator build
            totalAll     = snap.totalAll or 0,  -- exception(boundary): house snapshot {} until aggregator build
        }
    end,
})

-- expansionDonut: byExp in EXPANSION_DATA canonical order (newest first).
Selectors:Register("house.expansionDonutData", {
    reads = { "session.house.snapshotTick", "session.catalog.sweepGeneration" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        local snap = Selectors:Call("house.snapshot", state, ctx)
        local byExp = snap.byExp or {}
        local list = {}
        local seen = {}
        local ED = HDG.Constants.EXPANSION_DATA
        -- Walk newest-first.
        for i = #ED, 1, -1 do
            local exp = ED[i]
            local b = byExp[exp.display] or byExp[exp.api]
            if b then
                list[#list + 1] = {
                    expansion = exp.display,
                    short     = exp.short,
                    total     = b.total,
                    collected = b.collected,
                    pct       = b.pct,
                }
                seen[exp.display] = true
                seen[exp.api]     = true
            end
        end
        -- Tail: any expansion key in byExp not in EXPANSION_DATA.
        for expKey, b in pairs(byExp) do
            if not seen[expKey] then
                list[#list + 1] = {
                    expansion = expKey, short = expKey,
                    total = b.total, collected = b.collected, pct = b.pct,
                }
            end
        end
        return {
            buckets      = list,
            collectedAll = snap.collectedAll,
        }
    end,
})

-- styleAffinity: top-5 style tags. Pass-through from snapshot.
Selectors:Register("house.styleAffinityData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { tags = Selectors:Call("house.snapshot", state, ctx).topStyles or {} }
    end,
})

-- closeCards: top-3 closest-to-complete subcategories.
Selectors:Register("house.closeCardsData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { rows = Selectors:Call("house.snapshot", state, ctx).closestToComplete or {} }
    end,
})

-- hotPicks: top-5 uncollected by firstAcquisitionBonus.
Selectors:Register("house.hotPicksData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { items = Selectors:Call("house.snapshot", state, ctx).hotPicks or {} }
    end,
})

-- velocity: structured data only; renderer assembles the display label (selectors return data).
Selectors:Register("house.velocityData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        local v = Selectors:Call("house.snapshot", state, ctx).velocity
        if not v then
            return { hasActivity = false }
        end
        return {
            hasActivity     = true,
            perWeek         = v.perWeek,
            perDay          = v.perDay,
            daysToNextTier  = v.daysToNextTier,
            nextTierName    = v.nextTierName,
        }
    end,
})

-- capacity: structured data only. Tier "healthy"/"warn"/"full" -> StatusBar Skinner variant.
Selectors:Register("house.capacityData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        local c = Selectors:Call("house.snapshot", state, ctx).capacity
        if not c then
            return { available = false, owned = 0, max = 0, pct = 0, tier = "healthy" }
        end
        return {
            available = true,
            owned     = c.owned,
            max       = c.max,
            exempt    = c.exempt,
            pct       = c.pct,
            tier      = c.tier,
        }
    end,
})

-- featured: 4 owned items (week-rotated).
Selectors:Register("house.featuredData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { items = Selectors:Call("house.snapshot", state, ctx).featured or {} }
    end,
})

-- favorites: top 5 favorited items (mix of collected + uncollected).
Selectors:Register("house.favoritesData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { items = Selectors:Call("house.snapshot", state, ctx).favorites or {} }
    end,
})

-- themedSets: top 4 themed-set buckets (closest to complete first).
Selectors:Register("house.themedSetsData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { sets = Selectors:Call("house.snapshot", state, ctx).themedSets or {} }
    end,
})

-- topVendors: top 3 vendors by uncollected item count.
Selectors:Register("house.topVendorsData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { rows = Selectors:Call("house.snapshot", state, ctx).topVendors or {} }
    end,
})

-- recentActivity: last 5 learned-decor entries from craft history.
-- Renderer joins itemID -> name+icon via catalog at paint time.
Selectors:Register("house.recentActivityData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { entries = Selectors:Call("house.snapshot", state, ctx).recentActivity or {} }
    end,
})

-- lumberWallet: per-expansion lumber counts (current char bag, v1).
Selectors:Register("house.lumberWalletData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { types = Selectors:Call("house.snapshot", state, ctx).walletLumber or {} }
    end,
})

-- decorCurrency: housing-relevant currencies (count + need).
Selectors:Register("house.decorCurrencyData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { currencies = Selectors:Call("house.snapshot", state, ctx).walletHousing or {} }
    end,
})

-- Initiative event cards: thin pass-throughs over snapshot fields.
Selectors:Register("house.ritualSitesData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return Selectors:Call("house.snapshot", state, ctx).ritualSites
               or { items = {}, collected = 0, total = 0, pct = 0 }
    end,
})

Selectors:Register("house.abyssAnglersData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return Selectors:Call("house.snapshot", state, ctx).abyssAnglers
               or { items = {}, collected = 0, total = 0, pct = 0 }
    end,
})

Selectors:Register("house.decorDuelsData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return Selectors:Call("house.snapshot", state, ctx).decorDuels
               or { items = {}, collected = 0, total = 0, pct = 0 }
    end,
})

-- nextRewards: returns nil if no owned house yet (renderer shows
-- "Loading..."). Otherwise carries { level, maxLevel, targetLevel,
-- atMax, rewards } -- rewards nil while async fetch is in flight.
Selectors:Register("house.nextRewardsData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return Selectors:Call("house.snapshot", state, ctx).nextRewards
    end,
})

-- craftableNow: { canCraftNow, almostCraftable }. Headline numbers for
-- the "how many decor recipes can I craft right now" widget.
Selectors:Register("house.craftableNowData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return Selectors:Call("house.snapshot", state, ctx).craftableNow
               or { canCraftNow = 0, almostCraftable = 0 }
    end,
})

-- records: lifetime stats (totals, age, bestDay, streak).
Selectors:Register("house.recordsData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return Selectors:Call("house.snapshot", state, ctx).records or {}
    end,
})

-- goblinTopLumber: top-5 craftable decor by gold-per-lumber.
Selectors:Register("house.goblinTopLumberData", {
    reads = { "session.house.snapshotTick" },
    calls = { "house.snapshot" },
    fn = function(state, ctx)
        return { items = Selectors:Call("house.snapshot", state, ctx).goblinTopLumber or {} }
    end,
})

-- multiHouse: owned houses from HousingObserver state (not snapshot), so it stays
-- live under HOUSE_LIST_UPDATED / HOUSE_LEVEL_UPDATED.
Selectors:Register("house.multiHouseData", {
    reads = { "session.house.ownedHouses" },
    fn = function(state)
        local list = {}
        for guid, h in pairs(state.session.house.ownedHouses) do
            list[#list + 1] = {
                houseGUID = guid,
                name      = h.name,
                faction   = h.faction,
                level     = h.level,
                favor     = h.favor,
                maxLevel  = h.maxLevel,
            }
        end
        -- Alliance first (stable enough for now).
        table.sort(list, function(a, b)
            local aA = (a.faction == "Alliance") and 0 or 1
            local bA = (b.faction == "Alliance") and 0 or 1
            return aA < bA
        end)
        return { houses = list }
    end,
})

-- ============================================================================
-- WIDTH_UNITS: layout sizing token -> packer units (3 per row).
-- Unknown values default to 3 (full); the enum is closed.
-- ============================================================================

local WIDTH_UNITS = {
    third     = 1,
    twoThirds = 2,
    full      = 3,
}

-- ============================================================================
-- _resolveWidgets: canonical effective widget records (sorted by order).
-- Shared by widgetRows (enabled only) and pickerRows (all).
-- ============================================================================

local function _resolveWidgets(state)
    local defaults  = HDG.StaticData.WidgetDefaults:GetAll()
    local enabledOvr = state.account.ui.houseTab.enabled
    local orderOvr   = state.account.ui.houseTab.order
    local widthOvr   = state.account.ui.houseTab.width
    local layoutOvr  = state.account.ui.houseTab.layoutOverrides

    local out = {}
    for _, def in ipairs(defaults) do
        -- enabled override: `true` = user flipped from default (2nd toggle clears to nil).
        local defaultEnabled = def.enabled == true
        local override       = enabledOvr[def.id]
        local effectiveEnabled
        if override == true then
            effectiveEnabled = not defaultEnabled
        else
            effectiveEnabled = defaultEnabled
        end

        local heightOvr = layoutOvr[def.id] and layoutOvr[def.id].height
        out[#out + 1] = {
            id      = def.id,
            title   = def.title,
            order   = orderOvr[def.id] or def.order,
            width   = widthOvr[def.id] or def.width,
            height  = heightOvr or def.defaultHeight,
            enabled = effectiveEnabled,
        }
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

-- ============================================================================
-- house.widgetRows: bin-packed dashboard rows (greedy left-to-right, <= 3 units).
-- Cells carry per-widget data envelopes stamped from per-widget selectors.
-- ============================================================================

-- Dashboard blank state: no widget emitted any card (fresh install, nothing
-- captured yet). Mirrors decor.isBlank -- gate on the rendered row list itself
-- so the message is correct whatever the upstream cause.
Selectors:Register("house.isBlank", {
    calls = { "house.widgetRows" },
    fn = function(state, ctx)
        return #Selectors:Call("house.widgetRows", state, ctx) == 0
    end,
})

Selectors:Register("house.widgetRows", {
    reads = {
        "account.ui.houseTab.enabled",
        "account.ui.houseTab.order",
        "account.ui.houseTab.width",
        "account.ui.houseTab.layoutOverrides",
        -- snapshotTick + ownedHouses are read transitively via
        -- house.decoratorProfileData; declared here so BindingEngine
        -- knows widgetRows invalidates on those paths too. As more
        -- per-widget selectors plug in, their roots land in this list.
        "session.house.snapshotTick",
        "session.house.ownedHouses",
        -- sweepGeneration: donut selectors re-derive buckets from catalog
        -- observer on each sweep; widgetRows must invalidate transitively.
        "session.catalog.sweepGeneration",
    },
    calls = {
        "house.snapshot",   -- readiness gate (see fn): no cards until the snapshot is built
        "house.decoratorProfileData",
        "house.sourceDonutData",
        "house.expansionDonutData",
        "house.styleAffinityData",
        "house.closeCardsData",
        "house.hotPicksData",
        "house.velocityData",
        "house.capacityData",
        "house.featuredData",
        "house.multiHouseData",
        "house.favoritesData",
        "house.themedSetsData",
        "house.topVendorsData",
        "house.recentActivityData",
        "house.lumberWalletData",
        "house.decorCurrencyData",
        "house.ritualSitesData",
        "house.abyssAnglersData",
        "house.decorDuelsData",
        "house.nextRewardsData",
        "house.craftableNowData",
        "house.goblinTopLumberData",
        "house.recordsData",
    },
    fn = function(state, ctx)
        -- Readiness gate: snapshot {} until first build (deferred to window-open
        -- to dodge the cold-client housing-C CTD). Card renderers strict-read snapshot
        -- fields and erupt on nil; emit zero cards until snapshot exists. widgetRows
        -- reads snapshotTick so it re-runs on HOUSE_SNAPSHOT_UPDATED.
        if next(Selectors:Call("house.snapshot", state, ctx)) == nil then
            return {}
        end

        local widgets = _resolveWidgets(state)

        -- Per-widget data envelopes stamped into cell.data (skill section 6).
        local data = {
            decoratorProfile = Selectors:Call("house.decoratorProfileData", state, ctx),
            sourceDonut      = Selectors:Call("house.sourceDonutData",      state, ctx),
            expansionDonut   = Selectors:Call("house.expansionDonutData",   state, ctx),
            styleAffinity    = Selectors:Call("house.styleAffinityData",    state, ctx),
            closeCards       = Selectors:Call("house.closeCardsData",       state, ctx),
            hotPicks         = Selectors:Call("house.hotPicksData",         state, ctx),
            velocity         = Selectors:Call("house.velocityData",         state, ctx),
            capacity         = Selectors:Call("house.capacityData",         state, ctx),
            featured         = Selectors:Call("house.featuredData",         state, ctx),
            multiHouse       = Selectors:Call("house.multiHouseData",       state, ctx),
            favorites        = Selectors:Call("house.favoritesData",        state, ctx),
            themedSets       = Selectors:Call("house.themedSetsData",       state, ctx),
            topVendors       = Selectors:Call("house.topVendorsData",       state, ctx),
            recentActivity   = Selectors:Call("house.recentActivityData",   state, ctx),
            lumberWallet     = Selectors:Call("house.lumberWalletData",     state, ctx),
            decorCurrency    = Selectors:Call("house.decorCurrencyData",    state, ctx),
            ritualSites      = Selectors:Call("house.ritualSitesData",      state, ctx),
            abyssAnglers     = Selectors:Call("house.abyssAnglersData",     state, ctx),
            decorDuels       = Selectors:Call("house.decorDuelsData",       state, ctx),
            nextRewards      = Selectors:Call("house.nextRewardsData",      state, ctx),
            craftableNow     = Selectors:Call("house.craftableNowData",     state, ctx),
            goblinTopLumber  = Selectors:Call("house.goblinTopLumberData",  state, ctx),
            records          = Selectors:Call("house.recordsData",          state, ctx),
        }

        -- Greedy bin-pack into rows of <= 3 units.
        local rows = {}
        local curr = { cells = {}, units = 0, height = 0 }
        local function flush()
            if #curr.cells > 0 then
                rows[#rows + 1] = curr
                curr = { cells = {}, units = 0, height = 0 }
            end
        end
        for _, w in ipairs(widgets) do
            if w.enabled then
                local units = WIDTH_UNITS[w.width] or 3  -- exception(boundary): unknown width defaults to 3
                if curr.units + units > 3 then flush() end
                curr.cells[#curr.cells + 1] = {
                    id     = w.id,
                    title  = w.title,
                    width  = w.width,
                    units  = units,
                    height = w.height,
                    data   = data[w.id],
                }
                curr.units  = curr.units + units
                if w.height > curr.height then curr.height = w.height end
                if curr.units == 3 then flush() end
            end
        end
        flush()

        -- Per-row id for the row factory's key() contract.
        for i, r in ipairs(rows) do
            local parts = {}
            for _, c in ipairs(r.cells) do parts[#parts + 1] = c.id end
            r.id = "row:" .. table.concat(parts, "+")
            r.index = i
        end
        return rows
    end,
})

-- ============================================================================
-- house.pickerRows: every widget (enabled OR disabled) sorted by order.
-- Includes prev/next widget IDs for the picker's up/down arrows.
-- ============================================================================

Selectors:Register("house.pickerRows", {
    reads = {
        "account.ui.houseTab.enabled",
        "account.ui.houseTab.order",
        "account.ui.houseTab.width",
        "account.ui.houseTab.layoutOverrides",
    },
    fn = function(state)
        local widgets = _resolveWidgets(state)
        local out = {}
        for i, w in ipairs(widgets) do
            local prev = widgets[i - 1]
            local next_ = widgets[i + 1]
            out[#out + 1] = {
                id        = w.id,
                title     = w.title,
                width     = w.width,
                enabled   = w.enabled,
                order     = w.order,
                prevID    = prev and prev.id    or nil,
                prevOrder = prev and prev.order or nil,
                nextID    = next_ and next_.id    or nil,
                nextOrder = next_ and next_.order or nil,
            }
        end
        return out
    end,
})
