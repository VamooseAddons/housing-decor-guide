-- HDG.LumberObserver
-- ============================================================================
-- Sole boundary for lumber-related Blizzard API impurity. Watches bag
-- mutations, detects per-lumber-type gain deltas, captures the player's
-- current map coords at the harvest moment, and dispatches LUMBER_HARVESTED.
--
-- Four responsibilities:
--   1. Bag-delta detection (per lumber ID)
--      Cache the last-known total per lumber ID; on every BAG_UPDATE,
--      diff against the live BAG count via BagObserver:GetBagCount. Positive
--      delta -> harvest event(s); negative delta -> consumed (no event,
--      just refresh the cache). SUPPRESSED while a transfer UI (mail /
--      bank / merchant / trade) is open -- lumber gained that way is not a
--      harvest. See the source gate in Scan + the _suspended flag.
--   2. Session bookkeeping (auto-start)
--      First harvest in N_IDLE_SECONDS dispatches LUMBER_SESSION_START so
--      the per-char session record is created with the bag total at
--      session start. Subsequent harvests just dispatch HARVESTED; the
--      reducer updates the active session's lastHarvestAt.
--   3. Blip GC ticker (self-terminating)
--      Armed by a harvest that appends a blip; dispatches LUMBER_BLIP_GC
--      every GC_INTERVAL so the reducer drops blips older than
--      BLIP_TTL_SECONDS (1 hr). Cancels itself once the last blip ages out
--      -- an idle radar produces no dispatch and no C_Timer churn.
--   4. Live heartbeat ticker (self-terminating)
--      Armed on SESSION_START; bumps session.lumber.tick every 1s so the
--      counter panel's duration + rate texts update between harvests.
--      Cancels itself the tick after activeFarmingID clears.
--
-- ownsBlizzardNamespaces = { "C_Map.GetPlayerMapPosition" } -- sub-API claim;
-- ZoneObserver owns GetBestMapForUnit (zone probe). C_Map calls are safe in open-world.

HDG = HDG or {}
HDG.LumberObserver = HDG.LumberObserver or {}
local L = HDG.LumberObserver

-- ===== Tunables ==============================================================
local IDLE_SECONDS    = 15 * 60   -- 15 min idle = new session next harvest
-- BLIP_TTL_SECONDS = 1 hr (matches HDG DECAY.OLD). Distinct from RESPAWN_SECONDS (color cycle);
-- conflating the two dropped blips before their color cycle completed.
local BLIP_TTL_SECONDS = 60 * 60
local GC_INTERVAL      = 60

L.IDLE_SECONDS    = IDLE_SECONDS
L.RESPAWN_SECONDS = BLIP_TTL_SECONDS  -- kept under the old name for back-compat with reducer + tests; semantics widened
L.GC_INTERVAL     = GC_INTERVAL

-- Per-lumber-id last-known bag total. First sweep is conservative (unknown->known = no harvest).
L._lastTotals    = L._lastTotals    or {}
L._initialized   = L._initialized   or false
L._lumberIDSet   = L._lumberIDSet   or nil  -- built lazily from Constants.LUMBER_DATA
L._gcTicker      = L._gcTicker      or nil   -- C_Timer handle; nil when no blips to sweep (self-terminating)
L._liveTicker    = L._liveTicker    or nil   -- C_Timer handle; nil when no active farming session
L._suspended     = L._suspended     or false -- true while a transfer UI (mail/bank/merchant/trade) is open

-- Build + cache the lumber-ID set (avoids iterating LUMBER_DATA every BAG_UPDATE).
local function _ensureLumberIDSet()
    if L._lumberIDSet then return L._lumberIDSet end
    local set = {}
    for _, row in ipairs(HDG.Constants.LUMBER_DATA) do
        set[row.id] = true
    end
    L._lumberIDSet = set
    return set
end

-- ===== Player coords boundary ================================================
-- Returns (x, y, mapID) or nil (mid-loading-screen, sub-map without world origin, etc).
-- nil -> skip the blip portion of the dispatch (returning (0,0,0) would collapse
-- worldCache keys + produce bogus out-of-range blips, as hit with the earlier port).
local function _getPlayerCoords()
    if not (_G.C_Map and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetPlayerMapPosition) then
        return nil  -- exception(boundary): C_Map API missing -- shouldn't happen on retail
    end
    local mapID = _G.C_Map.GetBestMapForUnit("player")
    if not mapID or mapID == 0 then return nil end  -- exception(boundary): mid-load-screen
    local pos = _G.C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end                  -- exception(boundary): sub-map without world origin
    local x, y = pos.x, pos.y
    if not x or not y then return nil end           -- exception(boundary): sparse pos struct
    return x, y, mapID
end
L._GetPlayerCoords = _getPlayerCoords  -- exported for tests

-- ===== Harvest detection =====================================================
-- Diff current bag total against last-known. First scan is warm-up (records totals, no HARVESTED).
local function _now()
    return _G.GetTime and _G.GetTime() or 0  -- exception(boundary): GetTime/time absent in headless harness
end

function L:Scan()
    local Bag = HDG.BagObserver
    if not Bag then return end
    -- Source gate: lumber gained via mail/bank/merchant/trade is NOT a harvest.
    -- Baseline re-snapped on transfer-UI close; post-close scan sees no phantom delta.
    if self._suspended then return end
    local lumberSet = _ensureLumberIDSet()
    local firstPass = not self._initialized
    self._initialized = true

    for lumberID, _ in pairs(lumberSet) do
        local cur  = Bag:GetBagCount(lumberID)  -- bags ONLY: bank/warband swings are not harvests
        local prev = self._lastTotals[lumberID] or cur  -- first observation = no delta
        self._lastTotals[lumberID] = cur
        if not firstPass and cur > prev then
            self:_HandleHarvest(lumberID, cur - prev, cur)
        end
    end
    -- Satellite-window live totals (Discord report 2026-06-11): BagObserver's
    -- own BAG_UPDATE scan is gated requiresMainWindow -- right for the
    -- warehouse, wrong for the lumber tracker farming with the main window
    -- CLOSED. The tracker rows read Bag:GetTotal + session.resolvers.bag.tick, so the
    -- counts froze until End Session / opening the warehouse. Kick the
    -- owner's scan whenever the tracker is on screen (we already own this
    -- debounced BAG_UPDATE for harvest deltas).
    if HDG.Store:GetState().account.lumber.config.windowVisible == true then
        Bag:Scan()
    end
end

-- Snap baseline without firing harvests. Called on transfer-UI close so
-- lumber gained while suspended doesn't register as a harvest.
function L:_RefreshBaseline()
    local Bag = HDG.BagObserver
    if not Bag then return end
    for lumberID in pairs(_ensureLumberIDSet()) do
        self._lastTotals[lumberID] = Bag:GetBagCount(lumberID)
    end
    self._initialized = true  -- we now hold a known-good baseline
end

-- Single harvest event: maybe auto-start a session, dispatch HARVESTED.
function L:_HandleHarvest(lumberID, qty, currentTotal)
    local state   = HDG.Store:GetState()
    local lumber  = state.session.lumber
    local active  = lumber.activeFarmingID
    local now     = _now()
    local x, y, mapID = _getPlayerCoords()

    -- Session-start: no active session, different lumber type, or idle > IDLE_SECONDS.
    local needSessionStart = false
    if active ~= lumberID then
        needSessionStart = true
    else
        local charKey = state.session.identity.charKey
        local session = state.account.lumber.sessions[charKey]
                        and state.account.lumber.sessions[charKey][lumberID]
        if not session then
            needSessionStart = true
        elseif session.lastHarvestAt and (now - session.lastHarvestAt) > IDLE_SECONDS then
            needSessionStart = true
        end
    end

    if needSessionStart then
        -- Finalize prior session so it logs to farming history before being superseded.
        if active then
            L:FinalizeSession()
        end
        HDG.Store:Dispatch({
            type = HDG.Constants.ACTIONS.LUMBER_SESSION_START,
            payload = {
                lumberID   = lumberID,
                timestamp  = now,
                startCount = currentTotal - qty,  -- bag total BEFORE this harvest
            },
        })
        -- Auto-show the lumber window on session start (unless user has
        -- opted out via autoShowOnHarvest = false).
        if state.account.lumber.config.autoShowOnHarvest then
            HDG.Store:Dispatch({
                type = HDG.Constants.ACTIONS.LUMBER_WINDOW_TOGGLE,
                payload = { visible = true },
            })
        end
    end

    HDG.Store:Dispatch({
        type = HDG.Constants.ACTIONS.LUMBER_HARVESTED,
        payload = {
            lumberID = lumberID, qty = qty,
            x = x, y = y, mapID = mapID,
            timestamp = now,
        },
    })

    -- Arm heartbeat AFTER HARVESTED dispatch (keeps action order SESSION_START -> WINDOW_TOGGLE -> HARVESTED).
    if needSessionStart then
        self:_StartLiveTicker()
    end

    -- Ensure GC sweep running when a blip was appended (self-terminates on last blip).
    if x and y and mapID then
        self:_StartGCTicker()
    end
end

-- ===== Periodic GC ticker (self-terminating) =================================
-- Drops expired blips. Armed only when a harvest appends a blip; cancels when
-- blip list is empty (no idle dispatch, no C_Timer churn). Re-armed by next harvest.
function L:_StartGCTicker()
    if self._gcTicker then return end  -- already running
    if not (_G.C_Timer and _G.C_Timer.NewTicker) then return end
    self._gcTicker = _G.C_Timer.NewTicker(GC_INTERVAL, function()
        if #HDG.Store:GetState().session.lumber.blips == 0 then
            self._gcTicker:Cancel()
            self._gcTicker = nil
            return  -- nothing left to sweep; re-armed by the next harvest
        end
        HDG.Store:Dispatch({
            type = HDG.Constants.ACTIONS.LUMBER_BLIP_GC,
            payload = { now = _now() },
        })
    end)
end

-- ===== Live heartbeat ticker (self-terminating) ==============================
-- 1s tick to update duration + rate between harvests. Armed on SESSION_START;
-- cancels when activeFarmingID clears. No idle churn (same shape as GC ticker).
function L:_StartLiveTicker()
    if self._liveTicker then return end  -- already running
    if not (_G.C_Timer and _G.C_Timer.NewTicker) then return end
    self._liveTicker = _G.C_Timer.NewTicker(1.0, function()
        local state = HDG.Store:GetState()
        local activeID = state.session.lumber.activeFarmingID
        if not activeID then
            self._liveTicker:Cancel()
            self._liveTicker = nil
            return  -- session ended; re-armed by the next SESSION_START
        end
        -- Idle auto-finalize: walk-away session logged + ended before next SESSION_START supersedes.
        local charKey      = state.session.identity.charKey
        local charSessions = state.account.lumber.sessions[charKey]
        local session      = charSessions and charSessions[activeID]
        local last         = session and session.lastHarvestAt
        if last and (_now() - last) > IDLE_SECONDS then
            L:FinalizeSession()
            return
        end
        HDG.Store:Dispatch({
            type = HDG.Constants.ACTIONS.LUMBER_TICK,
        })
    end)
end

-- ===== Session finalization ===================================================
-- FinalizeSession: LUMBER_SESSION_END + LUMBER_HISTORY_PUSH atomic pair.
-- Called by "End Session" button and idle-auto-finalize. No-op if no active session.
function L:FinalizeSession()
    local state    = HDG.Store:GetState()
    local activeID = state.session.lumber.activeFarmingID
    if not activeID then return end  -- exception(boundary): no active session

    local now          = _G.GetTime and _G.GetTime() or 0  -- exception(boundary): GetTime/time absent in headless harness
    local charKey      = state.session.identity.charKey
    local charSessions = state.account.lumber.sessions[charKey]
    local session      = charSessions and charSessions[activeID]
    local startedAt    = session and session.startedAt  or 0
    local startCount   = session and session.startCount or 0

    -- History needs wall-clock (date() expects Unix epoch); session uses GetTime (client uptime).
    -- Derive: end-wall = time(); start-wall = end - elapsed. Duration preserved.
    local wallNow       = (_G.time and _G.time()) or 0  -- exception(boundary): GetTime/time absent in headless harness
    local startedAtWall = wallNow - math.max(0, now - startedAt)

    -- sessionTotal = current bag count minus startCount. Bag-only to match the
    -- bag-only startCount (harvest detection); bank/warband stock is excluded.
    local Bag   = HDG.BagObserver
    local cur   = Bag and Bag:GetBagCount(activeID) or 0
    local total = math.max(0, cur - startCount)

    -- Zone is best-effort; nil on loading screens.
    local zone = _G.GetRealZoneText and _G.GetRealZoneText() or nil  -- exception(boundary): GetRealZoneText nil between zones

    -- Identity from session (already resolved by SessionIdentity).
    local charName = state.session.identity.name
    local realm    = state.session.identity.realm

    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.LUMBER_SESSION_END,
        payload = { timestamp = now },
    })
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.LUMBER_HISTORY_PUSH,
        payload = {
            lumberID     = activeID,
            charKey      = charKey,
            startedAt    = startedAtWall,
            finalizedAt  = wallNow,
            sessionTotal = total,
            zone         = zone,
            character    = charName,
            realm        = realm,
        },
    })
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name = "LumberObserver",
    dependencies = { "BagObserver" },  -- we delegate item-count lookups
    ownsBlizzardNamespaces = { "C_Map.GetPlayerMapPosition" },
    blizzardEvents = {
        -- BAG_UPDATE debounced: 5-slot stack split fires 5 events; collapse to one scan.
        BAG_UPDATE = { handler = "OnBagUpdate", debounce = 0.2 },
        -- Source gate: transfer UIs open = bag gains are transfers, not harvests.
        MAIL_SHOW        = { handler = "OnTransferUIOpen"  },
        MERCHANT_SHOW    = { handler = "OnTransferUIOpen"  },
        TRADE_SHOW       = { handler = "OnTransferUIOpen"  },
        BANKFRAME_OPENED = { handler = "OnTransferUIOpen"  },
        MAIL_CLOSED      = { handler = "OnTransferUIClose" },
        MERCHANT_CLOSED  = { handler = "OnTransferUIClose" },
        TRADE_CLOSED     = { handler = "OnTransferUIClose" },
        BANKFRAME_CLOSED = { handler = "OnTransferUIClose" },
        -- Warband/portable banker fires PLAYER_INTERACTION_MANAGER events, not BANKFRAME_*.
        PLAYER_INTERACTION_MANAGER_FRAME_SHOW = { handler = "OnInteractionOpen"  },
        PLAYER_INTERACTION_MANAGER_FRAME_HIDE = { handler = "OnInteractionClose" },
    },
    OnBagUpdate = function()
        L:Scan()  -- the GC + live tickers self-arm from the harvest path now
    end,
    OnTransferUIOpen  = function() L._suspended = true end,
    OnTransferUIClose = function()
        L._suspended = false
        L:_RefreshBaseline()  -- items gained while suspended become the baseline
    end,
    OnInteractionOpen = function(_, interactionType)
        local PI = _G.Enum.PlayerInteractionType
        if interactionType == PI.Banker or interactionType == PI.AccountBanker then
            L._suspended = true
        end
    end,
    OnInteractionClose = function(_, interactionType)
        local PI = _G.Enum.PlayerInteractionType
        if interactionType == PI.Banker or interactionType == PI.AccountBanker then
            L._suspended = false
            L:_RefreshBaseline()
        end
    end,
})
