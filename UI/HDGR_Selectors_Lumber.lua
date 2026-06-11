-- HDG.Selectors -- Lumber Tracker family
--
-- Pure selectors over the lumber state slots.
-- lumberID -> icon is resolved by ItemNameResolver at the row-factory boundary
-- (C_Item.GetItemIconByID is a Blizzard call; pure selectors don't call it).

HDG = HDG or {}
HDG.Selectors = HDG.Selectors or {}
local Selectors = HDG.Selectors

-- ===== Atomic config reads ===================================================

Selectors:Register("lumber.windowVisible", {
    reads = { "account.lumber.config.windowVisible" },
    fn = function(state, _ctx)
        return state.account.lumber.config.windowVisible == true
    end,
})

Selectors:Register("lumber.windowPosition", {
    reads = { "account.lumber.config.position" },
    fn = function(state, _ctx)
        return state.account.lumber.config.position
    end,
})

Selectors:Register("lumber.radarCollapsed", {
    reads = { "account.lumber.config.radarCollapsed" },
    fn = function(state, _ctx)
        return state.account.lumber.config.radarCollapsed == true
    end,
})

Selectors:Register("lumber.radarScale", {
    reads = { "account.lumber.config.radarScale" },
    fn = function(state, _ctx)
        return state.account.lumber.config.radarScale
    end,
})

Selectors:Register("lumber.activeFarmingID", {
    reads = { "session.lumber.activeFarmingID" },
    fn = function(state, _ctx)
        return state.session.lumber.activeFarmingID
    end,
})

-- ===== Queue-derived lumber need =============================================
-- Total lumber needed by queued crafts. Dense map (LUMBER_DATA pre-seeded to 0)
-- so consumers strict-read without `or 0`. Reads staticData.tick so a
-- cold-cache recipe DB landing after first paint triggers re-bind.
Selectors:Register("lumber.queueNeed", {
    reads = { "account.craft.queue", "session.resolvers.staticData.tick" },
    fn = function(state, _ctx)
        -- Dense map: every LUMBER_DATA id pre-seeded to 0 so consumers
        -- strict-read (no `or 0` fallback at the call site). Lumber types
        -- not referenced by any queued recipe stay at 0.
        local out = {}
        for _, l in ipairs(HDG.Constants.LUMBER_DATA) do
            out[l.id] = 0
        end
        local q  = state.account.craft.queue
        for _, row in ipairs(q) do
            HDG.StaticData.Recipes:VisitReagents(HDG.StaticData.Recipes:Get(row.recipeID), function(slot)
                -- ~= nil discriminates lumber slots (dense pre-seed)
                if slot.itemID and slot.qty and out[slot.itemID] ~= nil then
                    out[slot.itemID] = out[slot.itemID] + slot.qty * (row.remaining or 1)  -- exception(boundary): queue row from SVars may lack remaining
                end
            end)
        end
        return out
    end,
})

-- ===== Counter rows ==========================================================
-- One row per LUMBER_DATA entry. Held via BagObserver:GetTotal (boundary).
-- Rate: linear extrapolation from (currentHeld - startCount) / sessionDuration.
-- RATE_MIN_DURATION/RATE_MIN_SAMPLES gate: prevents "+3600/hr" on the very first harvest.
local RATE_MIN_DURATION = 15
local RATE_MIN_SAMPLES  = 2

local function _computeRate(sessionTotal, duration)
    if duration < RATE_MIN_DURATION then return 0 end
    if sessionTotal < RATE_MIN_SAMPLES then return 0 end
    return (sessionTotal / duration) * 3600
end

Selectors:Register("lumber.counterRows", {
    -- session.itemNames.names: boundary signal from ItemNameResolver.
    -- ITEM_INFO_RESOLVED bumps it so cold-cache rows re-bind with the real icon.
    reads = { "session.resolvers.bag.tick",
              "session.itemNames.names",
              "session.lumber.activeFarmingID",
              "account.collection.ownedDecorIDs",      -- denominator drops as decor is collected
              "session.resolvers.catalog.tick" },     -- recipe->decorID map warms async
    calls = { "lumber.activeFarmingID", "lumber.queueNeed", "warehouse.lumberRequired" },
    fn = function(state, ctx)
        local Bag       = HDG.BagObserver
        local Resolver  = HDG.ItemNameResolver
        local LUMBER    = HDG.Constants.LUMBER_DATA
        local activeID  = Selectors:Call("lumber.activeFarmingID", state, ctx)
        local queueNeed = Selectors:Call("lumber.queueNeed", state, ctx)
        -- Same algorithm as the Warehouse Need column: lumber for UNCOLLECTED
        -- decor only (owner call 2026-06-11) -- one shared selector, no drift.
        local decorNeed = Selectors:Call("warehouse.lumberRequired", state, ctx)

        local out = {}
        for i, row in ipairs(LUMBER) do
            local held = Bag and Bag:GetTotal(row.id) or 0
            -- Icon stamped into envelope (not resolved at paint) so the async
            -- ResolveIcon -> ITEM_INFO_RESOLVED -> tick bump cycle re-runs selector.
            local icon = (Resolver and Resolver:ResolveIcon(row.id)) or HDG.Constants.PLACEHOLDER_ICON
            local isActive    = (row.id == activeID)
            local shortName   = row.shortName or row.name
            -- Active-row: leading asterisk so the player can see which lumber is accumulating.
            local displayName = isActive and ("* " .. shortName) or shortName
            out[#out + 1] = {
                lumberID     = row.id,
                name         = row.name,
                shortName    = shortName,
                displayName  = displayName,
                expansion    = row.expansion,
                icon         = icon,
                held         = held,
                queueNeed    = queueNeed[row.id],       -- dense map pre-seeded 0 for all LUMBER_DATA ids
                decorNeed    = decorNeed[row.id] or 0,  -- exception(boundary): sparse map (uncollected-decor need)
                isActive     = isActive,
                order        = i,
            }
        end
        return out
    end,
})

-- ===== Blips for radar =======================================================
-- Returns all blips with ageSec computed at selector time.
-- Zone/age filtering is deferred to the radar paint (live C_Map.GetBestMapForUnit).
-- Filtering here caused empty radar on ZoneObserver cold-start/debounce/sub-zone race.
-- Sorted by ageSec ascending so newest blips render on top.
Selectors:Register("lumber.blipsForRadar", {
    reads = { "session.lumber.blips",
              "session.lumber.tick" },
    fn = function(state, _ctx)
        local blips = state.session.lumber.blips
        local now   = _G.GetTime and _G.GetTime() or 0  -- exception(boundary): GetTime nil in headless

        local out = {}
        for _, b in ipairs(blips) do
            out[#out + 1] = {
                x        = b.x,
                y        = b.y,
                mapID    = b.mapID,
                ageSec   = now - b.ts,
                lumberID = b.lumberID,
            }
        end
        -- Newest first (lower ageSec = rendered on top)
        table.sort(out, function(a, b) return a.ageSec < b.ageSec end)
        return out
    end,
})

-- ===== Session stats + view-spec helpers =====================================
-- sessionStats: aggregate stats for the active farming session (nil when inactive).
-- View-spec helpers live here (not in LayoutConfig) because selectors must register
-- before LayoutConfig file load time (TOC order: Selectors_Lumber before LayoutConfig_Lumber).

-- dynamicRows: 5-row layout (header / radar / tracking / counter / action).
-- Radar collapses on user toggle; tracking hides when no active session.
Selectors:Register("lumber.dynamicRows", {
    reads = { "account.lumber.config.radarCollapsed",
              "account.lumber.config.listCollapsed",
              "session.lumber.activeFarmingID" },
    fn = function(state, _ctx)
        local farming   = state.session.lumber.activeFarmingID ~= nil
        local radarH    = state.account.lumber.config.radarCollapsed and 0 or 210
        local trackingH = farming and 38 or 0
        -- Minimize: listCollapsed drops counter + action bar to 0 (works with or without a session).
        local minimized = state.account.lumber.config.listCollapsed == true
        local counterH  = minimized and 0 or 280
        local actionH   = minimized and 0 or 24
        return { 28, radarH, trackingH, counterH, actionH }
    end,
})

-- radarShouldRender: bool gate for the panel.visible binding.
Selectors:Register("lumber.radarShouldRender", {
    reads = { "account.lumber.config.radarCollapsed" },
    fn = function(state, _ctx)
        return not (state.account.lumber.config.radarCollapsed == true)
    end,
})

-- trackingShouldRender: gates tracking-panel labels so they leave layout
-- when no session is active. Without this, fixed-height labels over-spec a 0px section.
Selectors:Register("lumber.trackingShouldRender", {
    reads = { "session.lumber.activeFarmingID" },
    fn = function(state, _ctx)
        return state.session.lumber.activeFarmingID ~= nil
    end,
})

-- rowsShown: `active` state for the session-only toggle (counter list visible/collapsed).
Selectors:Register("lumber.rowsShown", {
    reads = { "account.lumber.config.listCollapsed" },
    fn = function(state, _ctx)
        return not (state.account.lumber.config.listCollapsed == true)
    end,
})

-- ===== Tracking panel ======================================================
-- 2-line strip: lumber + zone on line 1, duration + rate + total on line 2.
-- Two selectors (not one struct) so each label binding is one-to-one with a widget.
local function _formatDuration(seconds)
    local mins = math.floor(seconds / 60)
    if mins < 60 then return string.format("%dm", mins) end
    local h = math.floor(mins / 60)
    return string.format("%dh %dm", h, mins - h * 60)
end

Selectors:Register("lumber.trackingPanelLine1", {
    reads = { "session.zone.currentZoneName" },
    calls = { "lumber.sessionStats" },
    fn = function(state, ctx)
        local stats = Selectors:Call("lumber.sessionStats", state, ctx)
        if not stats then return "" end
        local zone = state.session.zone.currentZoneName
        if zone == "" then
            return stats.lumberName
        end
        -- ASCII separator only (no unicode in Lua source)
        return string.format("%s  -  %s", stats.lumberName, zone)
    end,
})

Selectors:Register("lumber.trackingPanelLine2", {
    reads = {},     -- composed via sessionStats; reads-closure handled by calls
    calls = { "lumber.sessionStats" },
    fn = function(state, ctx)
        local stats = Selectors:Call("lumber.sessionStats", state, ctx)
        if not stats then return "" end
        local dur = _formatDuration(stats.duration)
        local rate = stats.perHour > 0
            and string.format("+%d/hr", math.floor(stats.perHour + 0.5))
            or "+-/hr"        -- cold-start: not enough samples yet
        return string.format("%s  -  %s  -  +%d this session",
            dur, rate, stats.totalGathered)
    end,
})

-- (lumber.sessionLabel removed: duplicated the tracking panel; dropped with the action-bar label.)
Selectors:Register("lumber.sessionStats", {
    memoized = true,
    reads = { "session.lumber.activeFarmingID",
              "session.resolvers.bag.tick",
              "session.lumber.tick",       -- 1s live ticker drives duration/rate refresh between bag-deltas
              "session.identity.charKey",
              "account.lumber.sessions" },
    calls = { "lumber.activeFarmingID" },
    fn = function(state, ctx)
        local activeID = Selectors:Call("lumber.activeFarmingID", state, ctx)
        if not activeID then return nil end

        local charKey = state.session.identity.charKey
        local charSessions = state.account.lumber.sessions[charKey] or {}
        local session = charSessions[activeID]
        if not session then return nil end

        local Bag     = HDG.BagObserver
        -- Bag-only to match the bag-only startCount (LUMBER_SESSION_START records the
        -- pre-harvest BAG count). GetTotal here counted bank+warband stock as
        -- "gathered this session" -- e.g. harvest 1 with 67 in the bank showed +68.
        -- Mirrors LumberObserver:FinalizeSession's bag-only delta.
        local held    = Bag and Bag:GetBagCount(activeID) or 0
        local now     = _G.GetTime and _G.GetTime() or 0  -- exception(boundary): GetTime nil in headless
        local duration = math.max(1, now - session.startedAt)
        local totalGathered = held - session.startCount
        if totalGathered < 0 then totalGathered = 0 end

        -- Display name from LUMBER_DATA (static constant; no Blizzard call needed).
        local lumberName
        for _, row in ipairs(HDG.Constants.LUMBER_DATA) do
            if row.id == activeID then lumberName = row.shortName or row.name; break end
        end

        return {
            lumberID      = activeID,
            lumberName    = lumberName,
            startedAt     = session.startedAt,
            duration      = duration,
            totalGathered = totalGathered,
            perHour       = _computeRate(totalGathered, duration),
        }
    end,
})
