-- HDG.HousingObserver
-- ============================================================================
-- The single boundary that owns all `C_Housing` + `C_NeighborhoodInitiative`
-- async-event impurity. Subscribes to housing-domain Blizzard events,
-- captures the event payloads, and dispatches Store actions. Selectors
-- never call these APIs directly -- they read from the state slots this
-- module writes into.
--
-- Domains owned (per ADR-022, observer consolidated by Blizzard API
-- namespace, not by event family):
--
--   1. Placed decor (account.styles.placedDecor):
--        HOUSE_EDITOR_MODE_CHANGED       -> clear on entry
--        HOUSING_DECOR_CUSTOMIZATION_CHANGED  -> per-decor observe (queued + batched)
--        HOUSING_DECOR_REMOVED           -> remove
--        PLAYER_ENTERING_WORLD           -> clear when leaving a house context
--
--   2. House meta (session.house.ownedHouses, keyed by houseGUID):
--        PLAYER_HOUSE_LIST_UPDATED       -> dispatch HOUSE_LIST_UPDATED
--        HOUSE_LEVEL_FAVOR_UPDATED       -> dispatch HOUSE_LEVEL_UPDATED
--
-- Initial fetch (kicks the async chain) happens at onEnable.
-- C_Housing.GetPlayerOwnedHouses is async (fires PLAYER_HOUSE_LIST_UPDATED),
-- spammy (3-5 fires on login -- 0.3s debounce on the handler).
-- C_Housing.GetCurrentHouseLevelFavor is async per house (fires
-- HOUSE_LEVEL_FAVOR_UPDATED) and the event fires for ALL houses, not just
-- the requested one -- payload includes houseGUID so the reducer can
-- target the right entry.
--
-- Taint-safe placed-decor enumeration: C_HousingDecor.GetAllPlacedDecor TAINTS
-- unconditionally even via C_Timer.After(0); event-driven OBSERVE is the only safe path.
-- See Reference/HOUSING_API.md.

HDG = HDG or {}
HDG.HousingObserver = HDG.HousingObserver or {}
local HO = HDG.HousingObserver

-- Log tag for C_Housing / C_NeighborhoodInitiative boundary failures.
-- Surfaces SECRET-value returns + invalid-GUID throws + cold-cache nil.
HDG.Log:RegisterTags({ housing_api = { user = false, level = "warn" } })

-- =============================================================================
-- Placed-decor channel.
-- =============================================================================

local function _resolveItemID(decorID)
    -- Map decorID -> itemID via catalog observer. Catalog may not be ready on
    -- first edit-mode entry; dispatch carries decorID as fallback.
    local row = HDG.HousingCatalogObserver.byDecorID[decorID]
    return row and row.itemID
end

-- Pending batch queue. Drained on the next frame by a single dispatch.
local _queue = {}
local _flushScheduled = false

local function _flushQueue()
    _flushScheduled = false
    local entries = _queue
    _queue = {}
    local n = #entries
    if n == 0 then return end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.STYLES_PLACED_DECOR_OBSERVED_BATCH,
        payload = { entries = entries },
    })
end

function HO:Observe(decorGUID)
    if type(decorGUID) ~= "string" then return end
    -- decorID from GUID "Housing-1-<plotID>-<decorID>-<hash>".
    -- exception(boundary): GetDecorInstanceInfoForGUID returns nil for freshly-enumerated GUIDs during
    -- the editor-entry burst; parse the GUID directly instead. Instance-info = optional name enrichment.
    local info = (C_HousingDecor and C_HousingDecor.GetDecorInstanceInfoForGUID
                  and C_HousingDecor.GetDecorInstanceInfoForGUID(decorGUID)) or nil  -- exception(boundary): nil during editor-entry burst
    local decorID = tonumber(decorGUID:match("^Housing%-1%-%d+%-(%d+)%-")) or (info and info.decorID)
    if not decorID then return end
    local name = (info and info.name)
              or (C_HousingDecor and C_HousingDecor.GetDecorName and C_HousingDecor.GetDecorName(decorID))  -- exception(boundary): housing C_API nil off-house-context
    _queue[#_queue + 1] = {
        decorGUID = decorGUID,
        decorID   = decorID,
        itemID    = _resolveItemID(decorID),
        name      = name,
    }
    if not _flushScheduled then
        _flushScheduled = true
        C_Timer.After(0, _flushQueue)
    end
end

function HO:RemovePlaced(decorGUID)
    if type(decorGUID) ~= "string" then return end
    -- Parse decorID from GUID so pre-existing decor (never in placedDecor) is attributed.
    -- Reducer prefers live placedDecor entry's itemID + falls back to this.
    local decorID = tonumber(decorGUID:match("^Housing%-1%-%d+%-(%d+)%-"))
    local itemID  = decorID and _resolveItemID(decorID)
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.STYLES_PLACED_DECOR_REMOVED,
        payload = { decorGUID = decorGUID, itemID = itemID },
    })
end

-- Stash the pending itemID here; OnDecorPlaceSuccess commits on actual world-click.
-- A cancelled pick (ESC, no PLACE_SUCCESS) records nothing.
function HO:SetPendingPlacement(itemID)
    HO._pendingPlaceItemID = itemID
end

function HO:ClearPlaced()
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.STYLES_PLACED_DECOR_CLEAR })
end

-- =============================================================================
-- House meta channel.
-- =============================================================================

-- Faction derivation: HouseInfo struct lacks faction; derived from
-- C_Housing.DoesFactionMatchNeighborhood + the player's own faction.
local function _deriveFaction(neighborhoodGUID)
    if not (C_Housing and C_Housing.DoesFactionMatchNeighborhood and neighborhoodGUID) then
        return nil
    end
    local ok, matches = pcall(C_Housing.DoesFactionMatchNeighborhood, neighborhoodGUID)
    if not ok then HDG.Log:Warn("housing_api", "DoesFactionMatchNeighborhood(" .. tostring(neighborhoodGUID) .. ") failed: " .. tostring(matches)) end
    if not ok then return nil end
    local pFaction = UnitFactionGroup and UnitFactionGroup("player")
    if pFaction == "Alliance" then return matches and "Alliance" or "Horde"
    elseif pFaction == "Horde"  then return matches and "Horde"    or "Alliance" end
    return nil
end

-- Stable order-independent digest for deduping PLAYER_HOUSE_LIST_UPDATED re-fires.
-- Control-byte separators (US/RS, ASCII 31/30) don't occur in GUIDs/names.
local function _houseListSignature(houseInfoList)
    local parts = {}
    for _, h in ipairs(houseInfoList) do
        parts[#parts + 1] = table.concat({
            tostring(h.houseGUID), tostring(h.neighborhoodGUID),
            tostring(h.neighborhoodName), tostring(h.houseName),
            tostring(h.plotID),
        }, "\31")
    end
    table.sort(parts)
    return table.concat(parts, "\30")
end

-- Gate for the REWARD fetch only (GetHouseLevelRewardsForLevel). That call fires
-- RECEIVED_HOUSE_LEVEL_REWARDS, which Blizzard's housing dashboard rebuilds its reward track
-- on every time -- blanking the level nodes to "0" with no repaint. HDG's reward data only
-- feeds the House + Projects/Architect tabs, so we only request it while one of those is the
-- active view AND the window is shown. (Favor/level fetching stays ungated -- it drives the
-- ring and is harmless to the dashboard.) account.ui.view persists across closes, hence the
-- mainWindowShown half. Mirrors the CATALOG_CONSUMING_TAB_VIEWS gate.
local function _houseLevelViewActive()
    local ui = HDG.Store:GetState().account.ui
    return ui.mainWindowShown == true and HDG.Constants.HOUSE_LEVEL_VIEWS[ui.view] == true
end

-- PLAYER_HOUSE_LIST_UPDATED: { houseGUID, neighborhoodGUID, neighborhoodName,
-- houseName, plotID, ... }. Faction derived here; reducer preserves level/favor on re-fire.
function HO:OnHouseList(houseInfoList)
    if type(houseInfoList) ~= "table" then return end
    -- Dedup: PLAYER_HOUSE_LIST_UPDATED re-fires 3-5 times on login with identical data.
    local sig = _houseListSignature(houseInfoList)
    if sig == HO._lastHouseListSig then return end
    HO._lastHouseListSig = sig

    local enriched = {}
    for i, h in ipairs(houseInfoList) do
        enriched[i] = {
            houseGUID        = h.houseGUID,
            neighborhoodGUID = h.neighborhoodGUID,
            neighborhoodName = h.neighborhoodName,
            houseName        = h.houseName,
            plotID           = h.plotID,
            faction          = _deriveFaction(h.neighborhoodGUID),
        }
    end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.HOUSE_LIST_UPDATED,
        payload = { houses = enriched },
    })
    -- Kick per-house favor fetch; each fires HOUSE_LEVEL_FAVOR_UPDATED async.
    -- Ungated: favor drives the house-level ring (always needed), and HOUSE_LEVEL_FAVOR_UPDATED
    -- does NOT disturb Blizzard's dashboard -- only the reward fetch does (see RequestRewardsForLevel).
    if C_Housing and C_Housing.GetCurrentHouseLevelFavor then
        for _, h in ipairs(houseInfoList) do
            if h.houseGUID then
                local ok, err = pcall(C_Housing.GetCurrentHouseLevelFavor, h.houseGUID)
                if not ok then HDG.Log:Warn("housing_api",
                    "GetCurrentHouseLevelFavor(" .. tostring(h.houseGUID) .. ") failed: " .. tostring(err)) end
            end
        end
    end
end

-- GetActiveNeighborhood is sync but cached info "invalidates immediately" (boundary:
-- stale/nil right after set). Blizzard re-fires NEIGHBORHOOD_INITIATIVE_UPDATED every
-- second; dedup against last-dispatched GUID prevents no-op churn.
function HO:OnActiveNeighborhood()
    local guid
    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetActiveNeighborhood then
        guid = C_NeighborhoodInitiative.GetActiveNeighborhood()
    end
    if guid == HO._lastActiveNeighborhoodGUID then return end
    HO._lastActiveNeighborhoodGUID = guid
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.ACTIVE_NEIGHBORHOOD_UPDATED,
        payload = { neighborhoodGUID = guid },
    })
end

-- HOUSE_LEVEL_FAVOR_UPDATED fires with HouseLevelFavor =
-- { houseGUID, houseLevel, houseFavor }. Fires for ALL owned houses on
-- each request, not just the one we asked about -- the houseGUID lets
-- the reducer target the right entry.
--
-- Thresholds (favor-to-reach-each-level) come from sync API
-- C_Housing.GetHouseLevelFavorForLevel; we compute them once per dispatch
-- and ship in the payload. Fallback table covers headless tests + the
-- 12.0.5 edge where the API returns 0 for unreachable levels.
local FALLBACK_HOUSE_LEVEL_XP = {
    [1] = 0,    [2] = 250,   [3] = 750,   [4] = 1500,  [5] = 2500,
    [6] = 4000, [7] = 6000,  [8] = 9000,  [9] = 12900,
}

local function _buildThresholds()
    local maxLevel = 50
    if C_Housing and C_Housing.GetMaxHouseLevel then
        local max = C_Housing.GetMaxHouseLevel()
        if max then maxLevel = max end
    end
    -- Sparse fallback: trailing nils -> "0 favor needed" (visible cue to extend the table).
    local thresholds = {}
    if C_Housing and C_Housing.GetHouseLevelFavorForLevel then
        for i = 1, maxLevel do
            local ok, val = pcall(C_Housing.GetHouseLevelFavorForLevel, i)
            if not ok then HDG.Log:Warn("housing_api", "GetHouseLevelFavorForLevel(" .. tostring(i) .. ") failed: " .. tostring(val)) end
            thresholds[i] = (ok and val and val > 0) and val
                            or FALLBACK_HOUSE_LEVEL_XP[i] or 0  -- exception(boundary): sparse fallback
        end
    else
        for i = 1, maxLevel do
            thresholds[i] = FALLBACK_HOUSE_LEVEL_XP[i] or 0  -- exception(boundary): sparse fallback
        end
    end
    return maxLevel, thresholds
end

function HO:OnHouseLevelFavor(houseLevelFavor)
    if type(houseLevelFavor) ~= "table" then return end
    -- Capture only: dispatches the house level (drives the ring + My Homes). It does NOT kick a
    -- reward fetch -- rewards are pulled lazily when a House/Projects view is shown (see onEnable),
    -- matching Blizzard's fetch-once-on-open instead of re-fetching on every favor tick.
    local guid = houseLevelFavor.houseGUID
    if type(guid) ~= "string" then return end
    -- Blizz struct; fields may be omitted for brand-new houses.
    local level = houseLevelFavor.houseLevel or 1   -- exception(boundary): Blizz struct
    local favor = houseLevelFavor.houseFavor or 0   -- exception(boundary): Blizz struct
    -- Dedup per-GUID: HOUSE_LEVEL_FAVOR_UPDATED bursts on login with identical payloads.
    -- Skips _buildThresholds + rewards re-fetch on no-op path.
    HO._lastLevelFavor = HO._lastLevelFavor or {}
    local sig = level .. ":" .. favor
    if HO._lastLevelFavor[guid] == sig then return end
    HO._lastLevelFavor[guid] = sig

    local maxLevel, thresholds = _buildThresholds()
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.HOUSE_LEVEL_UPDATED,
        payload = {
            houseGUID  = guid,
            level      = level,
            favor      = favor,
            maxLevel   = maxLevel,
            thresholds = thresholds,
        },
    })
end

-- Lazy reward pull -- the ONLY initiator of reward fetches (the favor handler no longer kicks
-- them). Called when a House/Projects view is shown; fetches each owned house's next-level
-- rewards, once per level (RequestRewardsForLevel dedups on the cache). Self-gates on the view so
-- it stays off Blizzard's dashboard reward track whenever HDG isn't actually displaying rewards.
function HO:RequestRewardsForOwnedHouses()
    if not _houseLevelViewActive() then return end
    for _, h in pairs(HDG.Store:GetState().session.house.ownedHouses) do
        if h.level and h.maxLevel then
            local target = (h.level < h.maxLevel) and (h.level + 1) or h.maxLevel
            HO:RequestRewardsForLevel(target)
        end
    end
end

-- =============================================================================
-- Level rewards channel.
-- =============================================================================

-- GetHouseLevelRewardsForLevel is AllowedWhenUntainted; can throw when tainted -> pcall.
function HO:RequestRewardsForLevel(level)
    if type(level) ~= "number" then return end
    -- Once per level, ever: rewards are level-based + immutable, so a cached level never needs
    -- re-fetching (the HOUSE_REWARDS_RECEIVED reducer comment anticipates exactly this dedup).
    -- Skipping the redundant fetch is also what keeps us off Blizzard's dashboard reward track --
    -- each GetHouseLevelRewardsForLevel fires RECEIVED_HOUSE_LEVEL_REWARDS, which re-inits + blanks it.
    if HDG.Store:GetState().session.house.rewardsByLevel[level] then return end
    if not (C_Housing and C_Housing.GetHouseLevelRewardsForLevel) then return end
    local ok, err = pcall(C_Housing.GetHouseLevelRewardsForLevel, level)
    if not ok then HDG.Log:Warn("housing_api",
        "GetHouseLevelRewardsForLevel(" .. tostring(level) .. ") failed: " .. tostring(err)) end
end

-- RECEIVED_HOUSE_LEVEL_REWARDS fires with (level, rewards) per the global
-- event signature. Reducer caches by level.
function HO:OnHouseLevelRewards(level, rewards)
    if type(level) ~= "number" or type(rewards) ~= "table" then return end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.HOUSE_REWARDS_RECEIVED,
        payload = { level = level, rewards = rewards },
    })
end

-- =============================================================================
-- Projects topology capture channel. Reads LIVE pin frames (impure boundary);
-- pure transforms in HDG.Projects.{Capture,AutoLayout}. One atomic PROJECTS_CAPTURE_COMMIT.
-- =============================================================================

-- Static localizedName -> shapeID FALLBACK (English only, cold-catalog safety net).
-- PRIMARY resolution is the live room catalog (_buildCatalogNameToShape below), which
-- is locale-correct in every client. Kept in sync with ShapeAtlas IDs.
local NAME_TO_SHAPE = {
    ["Closet"]                  = "closet_xs",
    ["Square Room (Tiny)"]      = "square_xs",
    ["Square Room (Small)"]     = "square_s",
    ["Square Room (Medium)"]    = "square_m",
    ["Square Room (Large)"]     = "square_l",
    ["Octagon Room (Small)"]    = "octagon_s",
    ["Octagon Room (Medium)"]   = "octagon_m",
    ["Octagon Room (Large)"]    = "octagon_l",
    ["L-Shaped Room"]           = "l_shape",
    ["T-Shaped Room"]           = "t_shape",
    ["Cross-Shaped Room"]       = "cross_shape",
    ["Hallway"]                 = "hallway",
    ["Entry"]                   = "entry",
    ["Evening Circle Room"]     = "circle_evening",
    ["Daylight Circle Room"]    = "circle_daylight",
    ["Stairwell (Left)"]        = "staircase",
    ["Stairwell (Right)"]       = "staircase_mirror",
    ["Stairwell Room (Empty)"]  = "tall_room",
}

-- Entry = the base room. pin:CanRemove() reports the IsBaseRoom restriction for it (and
-- only it) -- a locale-independent signal read synchronously off the pin. Resolved at load;
-- the headless harness stubs Enum, so fall back to the known enum value there.
local ENTRY_RESTRICTION = (Enum and Enum.HousingLayoutRestriction and Enum.HousingLayoutRestriction.IsBaseRoom) or 4  -- exception(boundary): Enum.HousingLayoutRestriction absent in headless harness

-- localizedName -> shapeID, built fresh per capture from the LIVE room catalog
-- (session.house.roomCatalog). The catalog's localized name is byte-identical to
-- pinFrame:GetRoomName() (same DB2 field -- verified enUS; the recordID->shapeID bridge
-- is locale-independent by construction), so capture resolves shapes in EVERY locale,
-- not just English. Prefab rooms carry nil shapeID -> skipped (catalog iconAtlas renders them).
local function _buildCatalogNameToShape()
    local map = {}
    for _, e in ipairs(HDG.Store:GetState().session.house.roomCatalog.entries) do
        if e.shapeID then map[e.name] = e.shapeID end
    end
    return map
end

-- Pure: resolve a captured room's shapeID. The base room is the Entry anchor -- isBase comes
-- from the pin's IsBaseRoom removal restriction (locale-independent) and Entry is NOT a catalog
-- room, so neither name map can cover it. Then the live-catalog map (locale-correct), then the
-- static English fallback (cold catalog), then the raw name (unknown -> ShapeAtlas renders a
-- generic cell; never crashes).
function HO.ResolveShape(name, isBase, catalogNameToShape)
    if isBase then return "entry" end
    return catalogNameToShape[name] or NAME_TO_SHAPE[name] or name
end

local _capture     -- transient capture buffer for one Layout-mode floor session
local _activeSweep -- active "capture all floors" sweep state (timer-driven)

local function _layoutMode()   return (Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.Layout)   or 3 end  -- exception(boundary): Enum.HouseEditorMode absent in headless harness
local function _decorateMode() return (Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.Decorate) or 1 end  -- exception(boundary): Enum.HouseEditorMode absent in headless harness

-- Stable houseID for the house the player is currently inside: a digest of the
-- neighborhoodName + plotID (the PLOT's identity), NOT the character's faction --
-- so a Horde house captured on an Alliance char keys correctly, and two houses
-- captured on one character don't collide. Name+plot is used (not the neighborhood
-- GUID) because the name is provably stable across sessions; the GUID's cross-session
-- stability is unverified. nil when not inside an owned house.
local function _currentHouseID()
    if not (C_Housing and C_Housing.GetCurrentHouseInfo) then return nil end   -- exception(boundary): C_Housing absent (headless / pre-login)
    local info = C_Housing.GetCurrentHouseInfo()
    if not (info and info.plotID and info.neighborhoodName) then return nil end -- exception(boundary): nil outside an owned house
    local key = info.neighborhoodName .. ":" .. tostring(info.plotID)
    return HDG.Projects.IDs.makeHouseID(HDG.Projects.IDs.hashToken(key))
end

-- Public accessor -- other modules must NOT re-derive house identity (HO owns C_Housing).
function HO:CurrentHouseID() return _currentHouseID() end

function HO:IsCapturing() return _capture and _capture.active or false end
function HO:IsSweeping()  return _activeSweep ~= nil end
function HO:CancelSweep()
    -- Flag AND drop: in-flight C_Timer closures check cancelled/nil; leaving
    -- _activeSweep set wedges CaptureAllFloors ("already in progress") until
    -- reload (review 17 #5).
    if _activeSweep then _activeSweep.cancelled = true; _activeSweep = nil end
end

-- Editor-mode + location accessors for consumers (e.g. HouseEditorCompanion).
-- HO owns C_HouseEditor + C_Housing (invariant 9); boundary: editor C_* exists only while open.
function HO:IsHouseEditorModeActive(mode)
    return (C_HouseEditor and C_HouseEditor.IsHouseEditorModeActive and C_HouseEditor.IsHouseEditorModeActive(mode)) or false  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
end
function HO:ActivateHouseEditorMode(mode)
    if C_HouseEditor and C_HouseEditor.ActivateHouseEditorMode then C_HouseEditor.ActivateHouseEditorMode(mode) end  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
end
function HO:IsInsideHouse()
    return (C_Housing and C_Housing.IsInsideHouse and C_Housing.IsInsideHouse()) or false  -- exception(boundary): C_Housing is a Blizzard API namespace; nil in headless tests
end

function HO:_BeginCapture(floor)
    -- nextIndex stamps capture order per room (surfaced in "Hallway 2" labels).
    _capture = { active = true, floor = floor or 1, rooms = {}, nextIndex = 1 }
end

function HO:_EndCapture()
    if not (_capture and _capture.active) then return nil end
    _capture.active = false
    local snap = _capture
    _capture = nil
    return snap
end

-- _pinPos: diagnostic screen-coord probe (posAdd/posFinal research; not yet driving layout).
-- Gated on HDG_DB.perf so production sweep allocates nothing per pin.
local function _pinPos(pin)
    -- exception(boundary): raw SavedVariable read.
    if not (_G.HDG_DB and _G.HDG_DB.perf) then return nil end
    if not pin then return nil end
    local o = {}
    local function g(k, fn)
        local r = { pcall(fn) }  -- exception(fire-forget): debug-only pin geometry; skip on any error
        if r[1] and r[2] ~= nil then table.remove(r, 1); o[k] = r end
    end
    g("center", function() return pin:GetCenter() end)   -- cx, cy (scaled screen px)
    g("rect",   function() return pin:GetRect() end)      -- x, y, w, h
    g("left",   function() return pin:GetLeft() end)
    g("top",    function() return pin:GetTop() end)
    g("scale",  function() return pin:GetEffectiveScale() end)
    g("numPts", function() return pin:GetNumPoints() end)
    do  -- GetPoint -> point, relativeTo(FRAME -- skip), relativePoint, xOfs, yOfs
        local ok, pt, _rel, rpt, x, y = pcall(function() return pin:GetPoint(1) end)  -- exception(fire-forget): debug-only pin geometry; skip on any error
        if ok and pt ~= nil then o.point = { pt, rpt, x, y } end
    end
    return o
end

-- Ingest one live pin frame into the capture buffer (impure boundary read).
local function _ingestPin(pinFrame)
    if not (_capture and pinFrame and pinFrame.GetPinType) then return end
    local pinType  = pinFrame:GetPinType()
    local roomGUID = pinFrame:GetRoomGUID()
    if not roomGUID then return end
    local room = _capture.rooms[roomGUID]
    if not room then
        room = { roomGUID = roomGUID, capturedID = roomGUID, doors = {}, captureIndex = _capture.nextIndex }
        _capture.rooms[roomGUID] = room
        _capture.nextIndex = _capture.nextIndex + 1
    end
    if pinType == 1 then   -- room pin
        -- Entry = the base room: pin:CanRemove() == IsBaseRoom restriction. Read synchronously
        -- off the pin, NOT via C_HousingLayout.IsBaseRoom(guid) (field-reported unreliable).
        -- Locale-independent -- Entry is not a catalog room and GetRoomName is localized.
        room.isBase = pinFrame:CanRemove() == ENTRY_RESTRICTION
        room.name  = pinFrame:GetRoomName()
        _capture.nameToShape = _capture.nameToShape or _buildCatalogNameToShape()   -- locale-correct map; built once per capture
        room.shape = HO.ResolveShape(room.name, room.isBase, _capture.nameToShape)
        room._roomPin = pinFrame   -- temp ref; restriction flags + final pos read at finalize
        room.posAdd   = _pinPos(pinFrame)   -- diagnostic: screen coords at pin-add time
    elseif pinType == 0 then  -- door pin
        local d = pinFrame:GetDoorConnectionInfo()
        if d then
            room.doors[#room.doors + 1] = {
                doorID         = d.doorID,
                connectionType = d.connectionType,
                facing         = d.doorFacing,
                occupied       = pinFrame:IsOccupiedDoor() and true or false,
            }
        end
    end
end

function HO:OnPinFrameAdded(pinFrame)
    if _capture and _capture.active then _ingestPin(pinFrame) end
end

-- Every existing room ID on a floor -- compared against a recapture's
-- deterministic IDs to find genuinely-removed rooms (see _FinalizeCapture).
local function _existingRoomIDsForFloor(floorID)
    -- Recapture diffs against the live LAYOUT's placements by their captured
    -- identity: slots carry capturedID directly; matched rooms carry it as the
    -- room record's lineage (legacyID). boundary: a never-captured house has
    -- no layout yet -> nothing existing to diff.
    local IDs    = HDG.Projects.IDs
    local parsed = IDs.parsePath(floorID)
    local state  = HDG.Store:GetState()
    local p      = state.account.projects
    local house  = parsed and parsed.houseID and p.houses[parsed.houseID]
    local layout = house and house.currentVersionID and p.layouts[house.currentVersionID]
    local out = {}
    if not layout then return out end
    -- v8: lineage lives on the placement (capturedID) -- direct read.
    for _, pl in pairs(layout.placements) do
        local rp = pl.capturedID and IDs.parsePath(pl.capturedID)
        if rp and rp.floorID == floorID then out[#out + 1] = pl.capturedID end
    end
    return out
end

-- Finalize a captured floor by REPLACING the live layout. Every existing room deleted
-- (crates fall to orphan bay); captured rooms added with fresh deterministic IDs +
-- grid-packed cells. No fingerprint-merge (matching identical shapes was ambiguous).
function HO:_FinalizeCapture(snapshot, houseID)
    if not (snapshot and houseID) then return end
    local floor   = snapshot.floor or 1
    local floorID = HDG.Projects.IDs.makeFloorID(houseID, floor)
    if not floorID then return end

    -- Drop the live pin refs (restriction flags + diagnostics no longer persisted -- Phase 4).
    for _, room in pairs(snapshot.rooms) do
        room._roomPin = nil
    end

    -- DETERMINISTIC room IDs (floor + capture-order) so crates stay attached on recapture.
    -- Old rooms not reproduced -> orphaned crates (recoverable via orphan UI).
    local IDs, Cap, rooms = HDG.Projects.IDs, HDG.Projects.Capture, {}
    -- Multi-floor rooms (stairwell/tall/garden) are enumerated once PER spanned floor
    -- section, each with its own GUID -- so the all-floors sweep would re-add them on
    -- every higher floor. Skip a multi-floor SHAPE already committed on a lower floor
    -- (no position/connectivity API to link the sections) and instead widen the base
    -- room's observed span. Only the sweep dedups; passive single-floor capture doesn't.
    -- LIMIT: two same-shape multi-floor rooms stacked across overlapping floors collapse
    -- into one (shape is the only signal) -- rare, and unsolvable without positions.
    local Atlas   = HDG.Projects.ShapeAtlas
    local seenLow = _activeSweep and _activeSweep.seenLowerMF
    local mfSpan  = _activeSweep and _activeSweep.mfSpan
    for _, r in pairs(snapshot.rooms) do
        local isMF = Atlas.GetFloors(r.shape) > 1
        if isMF and seenLow and seenLow[r.shape] then
            local s = mfSpan and mfSpan[r.shape]
            if s and floor > s.maxFloor then s.maxFloor = floor end   -- projection -> widen span, don't re-add
        else
            local id = IDs.makeRoomID(floorID, tostring(r.captureIndex))   -- captureIndex always stamped at ingest
            if id then
                rooms[id] = Cap.buildRoomRecord(r)
                if isMF and mfSpan and not mfSpan[r.shape] then
                    mfSpan[r.shape] = { floorID = floorID, captureIndex = r.captureIndex, baseFloor = floor, maxFloor = floor }
                end
            end
        end
    end
    -- Mark this floor's multi-floor shapes seen AFTER committing, so two same-shape base
    -- rooms on THIS floor don't skip each other -- only higher floors dedup against them.
    if seenLow then
        for _, r in pairs(snapshot.rooms) do
            if Atlas.GetFloors(r.shape) > 1 then seenLow[r.shape] = true end
        end
    end
    local deleteRoomIDs = {}
    for _, oldID in ipairs(_existingRoomIDsForFloor(floorID)) do
        if not rooms[oldID] then deleteRoomIDs[#deleteRoomIDs + 1] = oldID end
    end
    -- AutoLayout grid-packs each room's cell (no positional API -> a tidy deterministic
    -- starting canvas: rows by capture order, entry at bottom-centre, never overlapping).
    -- Baked into stored cells so rooms render spread; E4-drag re-positions to match reality.
    local packed = HDG.Projects.AutoLayout.compute({ rooms = rooms }).layout
    for roomID, placed in pairs(packed) do
        local rec = rooms[roomID]
        if rec then
            rec.cell = { x = placed.cell.x, y = placed.cell.y, rotation = placed.rotation or 0, locked = false }
        end
    end

    -- Persist ONLY the SSoT fields. doorCardinals fed AutoLayout.InferRotation above
    -- (a capture-time input) -- not stored; doors/occupancy all derive from cell + shape.
    for id, rec in pairs(rooms) do
        rooms[id] = {
            shape  = rec.shape, name = rec.name, cell = rec.cell,
            isBase = rec.isBase, captureIndex = rec.captureIndex,
        }
    end

    -- House identity for display. boundary: C_Housing.GetCurrentHouseInfo() ->
    -- { houseName, plotID, neighborhoodName, houseGUID, ownerName }. houseGUID is
    -- process-scoped (opaque handle) so we KEY by faction; we only LABEL by name.
    local info = (C_Housing and C_Housing.GetCurrentHouseInfo and C_Housing.GetCurrentHouseInfo()) or nil  -- exception(boundary): C_Housing is a Blizzard API namespace; returns nil in headless tests

    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.PROJECTS_CAPTURE_COMMIT,
        payload = {
            houseID = houseID,
            rooms = rooms, deleteRoomIDs = deleteRoomIDs,
            lastCapturedAt = (time and time() or 0),  -- exception(boundary): GetTime/time absent in headless harness  -- conns feeds AutoLayout above, not persisted
            houseName        = info and info.houseName,
            plotID           = info and info.plotID,
            neighborhoodName = info and info.neighborhoodName,
        },
    })
end

-- After an all-floors sweep: each multi-floor room was committed once (its base section)
-- and _FinalizeCapture tracked how high the same shape re-appeared. Stamp that observed
-- span onto the base PLACEMENT's `floors` field so FloorMap projects it to exactly the
-- floors it occupies -- the ShapeAtlas default (tall_room=2, garden=3, ...) is only the
-- fallback when uncaptured, and a stairwell can legitimately run 1->3.
function HO:_ApplyMultiFloorSpans()
    if not (_activeSweep and _activeSweep.mfSpan) then return end
    local IDs, Atlas = HDG.Projects.IDs, HDG.Projects.ShapeAtlas
    local state  = HDG.Store:GetState()
    local p      = state.account.projects
    local house  = _activeSweep.houseID and p.houses[_activeSweep.houseID]
    local lid    = house and house.currentVersionID
    local layout = lid and p.layouts[lid]
    if not layout then return end
    for shape, s in pairs(_activeSweep.mfSpan) do
        local span = s.maxFloor - s.baseFloor + 1
        if span > 1 and span ~= Atlas.GetFloors(shape) then
            local capturedID = IDs.makeRoomID(s.floorID, tostring(s.captureIndex))
            -- Resolve the placement ApplyCapture wrote for this captured room.
            -- v8: every committed placement carries capturedID (tagged or not),
            -- so the lineage match is direct -- no room.legacyID fallback.
            local key
            if capturedID then
                for k, pl in pairs(layout.placements) do
                    if pl.capturedID == capturedID then key = k break end
                end
            end
            if key then
                HDG.Store:Dispatch({
                    type    = HDG.Constants.ACTIONS.LAYOUT_MOVE,
                    payload = { layoutID = lid, key = key, floors = span },
                })
            end
        end
    end
end

-- Passive capture: begin on Layout entry, finalize on exit. Suppressed during active sweep.
function HO:_OnCaptureModeChanged()
    if _activeSweep then return end
    local active = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive() or false  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
    local mode   = (C_HouseEditor and C_HouseEditor.GetActiveHouseEditorMode and C_HouseEditor.GetActiveHouseEditorMode()) or 0  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
    if active and mode == _layoutMode() then
        if not self:IsCapturing() then
            self:_BeginCapture((C_HousingLayout and C_HousingLayout.GetViewedFloor and C_HousingLayout.GetViewedFloor()) or 1)  -- exception(boundary): C_HousingLayout is a Blizzard API namespace; nil in headless tests
        end
    elseif self:IsCapturing() then
        local snap, houseID = self:_EndCapture(), _currentHouseID()
        if snap and houseID then self:_FinalizeCapture(snap, houseID) end
    end
end

function HO:OnLayoutFloorChanged()
    if _activeSweep or not self:IsCapturing() then return end
    local snap, houseID = self:_EndCapture(), _currentHouseID()
    if snap and houseID then self:_FinalizeCapture(snap, houseID) end
    self:_BeginCapture((C_HousingLayout and C_HousingLayout.GetViewedFloor and C_HousingLayout.GetViewedFloor()) or 1)  -- exception(boundary): C_HousingLayout is a Blizzard API namespace; nil in headless tests
end

-- Active sweep: Decorate->Layout (re-emits pins), iterate floors with settle delay.
-- SetViewedFloor is 0-INDEXED.
local function _stepSweep()
    if not _activeSweep or _activeSweep.cancelled then return end
    local nextFloor = _activeSweep.floor + 1
    if HO:IsCapturing() then
        local snap, houseID = HO:_EndCapture(), _currentHouseID()
        if snap and houseID then HO:_FinalizeCapture(snap, houseID) end
    end
    if nextFloor > _activeSweep.maxFloor then
        HO:_ApplyMultiFloorSpans()   -- stamp observed vertical spans onto base rooms before teardown
        if C_HouseEditor and C_HouseEditor.LeaveHouseEditor then C_HouseEditor.LeaveHouseEditor() end
        local floors = _activeSweep.maxFloor
        _activeSweep = nil
        -- Capture summary off the ApplyCapture echo (matched vs to-assign vs
        -- unplaced rooms). Rooms/furnishings persist by construction -- the
        -- "removed" count is placements only, never lost work.
        local cap   = HDG.Store:GetState().session.furn.lastCapture or {}   -- exception(boundary): echo absent pre-first-commit
        local total = (cap.matched or 0) + (cap.slots or 0)
        local msg   = ("House captured (%d floor%s) -- %d room%s"):format(
            floors, floors == 1 and "" or "s", total, total == 1 and "" or "s")
        local parts = {}
        if (cap.matched or 0) > 0 then parts[#parts + 1] = cap.matched .. " matched" end
        if (cap.slots or 0) > 0 then parts[#parts + 1] = cap.slots .. " to assign (click a * room)" end
        if (cap.removed or 0) > 0 then
            parts[#parts + 1] = cap.removed .. " no longer placed (furnishings safe in My Designs)"
        end
        if #parts > 0 then msg = msg .. ": " .. table.concat(parts, ", ") end
        HDG.Log:Success("projects_save", msg)
        return
    end
    _activeSweep.floor = nextFloor
    HO:_BeginCapture(nextFloor)
    if C_HousingLayout and C_HousingLayout.SetViewedFloor then C_HousingLayout.SetViewedFloor(nextFloor - 1) end
    if C_Timer and C_Timer.After then C_Timer.After(_activeSweep.settleSeconds, _stepSweep) end
end

function HO:CaptureAllFloors()
    if _activeSweep then return false, "already in progress" end
    -- exception(boundary): C_Housing.IsInsideHouse() -- external Blizzard API; returns false
    -- outside any house (including neighborhood plot). Must be inside YOUR house for
    -- C_HousingLayout.GetNumFloors / pin enumeration to return meaningful data.
    if not (C_Housing and C_Housing.IsInsideHouse and C_Housing.IsInsideHouse()) then  -- exception(boundary): housing C_API nil off-house-context
        return false, "Enter your house to capture floors"
    end
    if not (C_HouseEditor and C_HouseEditor.IsHouseEditorStatusAvailable and C_HouseEditor.IsHouseEditorStatusAvailable()) then  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
        return false, "house editor not available -- visit your house first"
    end
    local houseID = _currentHouseID()
    if not houseID then return false, "could not determine faction" end
    if self:IsCapturing() then self:_EndCapture() end

    -- Recapture prep (v8): placements persist so tags survive; CLEAR prunes
    -- only capture-owned placements above the current floor count + resets
    -- the capture echo. Per-floor diffs handle removals on surviving floors.
    local maxFloor = (C_HousingLayout and C_HousingLayout.GetNumFloors and C_HousingLayout.GetNumFloors()) or 1  -- exception(boundary): C_HousingLayout is a Blizzard API namespace; nil in headless tests
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.PROJECTS_CLEAR_HOUSE,
        payload = { houseID = houseID, clearedAt = (time and time() or 0), maxFloor = maxFloor },  -- exception(boundary): GetTime/time absent in headless harness
    })

    if C_HouseEditor.EnterHouseEditor then C_HouseEditor.EnterHouseEditor() end  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
    if C_HouseEditor.ActivateHouseEditorMode then C_HouseEditor.ActivateHouseEditorMode(_decorateMode()) end  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
    _activeSweep = {
        houseID = houseID, floor = 1,
        maxFloor = maxFloor,
        settleSeconds = 1.5, cancelled = false,
        seenLowerMF = {},   -- multi-floor SHAPES committed on a lower floor -> skip their upper sections
        mfSpan      = {},    -- shape -> { floorID, captureIndex, baseFloor, maxFloor } observed vertical span
    }
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            if not _activeSweep or _activeSweep.cancelled then return end
            if C_HouseEditor.ActivateHouseEditorMode then C_HouseEditor.ActivateHouseEditorMode(_layoutMode()) end  -- exception(boundary): C_HouseEditor is a Blizzard API namespace; nil in headless tests
            if C_HousingLayout and C_HousingLayout.SetViewedFloor then C_HousingLayout.SetViewedFloor(0) end
            if not self:IsCapturing() then self:_BeginCapture(1) end
            C_Timer.After(_activeSweep.settleSeconds, _stepSweep)
        end)
    end
    return true
end

-- Budget/floor/editor live reads -> PROJECTS_HOUSE_TICK.
function HO:_PushHouseTick()
    local CL, CD, CE = C_HousingLayout, C_HousingDecor, C_HouseEditor
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.PROJECTS_HOUSE_TICK,
        payload = {
            -- live decor spend; placement CAPS come from projects.placementCaps (reward-derived).
            -- exception(boundary): live cap API is layout-editor-state-dependent (returns 9/300 until Edit Layout opens).
            budget = {  -- exception(boundary): live C_HousingDecor reads
                decorSpent = (CD and CD.GetSpentPlacementBudget and CD.GetSpentPlacementBudget()) or 0,  -- exception(boundary): CD = C_HousingDecor, Blizzard API namespace
                decorCount = (CD and CD.GetNumDecorPlaced       and CD.GetNumDecorPlaced())       or 0,  -- exception(boundary): CD = C_HousingDecor, Blizzard API namespace
            },
            numFloors    = (CL and CL.GetNumFloors and CL.GetNumFloors()) or 0,  -- exception(boundary): CL = C_HousingLayout, Blizzard API namespace
            editorActive = (CE and CE.IsHouseEditorActive and CE.IsHouseEditorActive()) or false,  -- exception(boundary): CE = C_HouseEditor, Blizzard API namespace
        },
    })
end

-- =============================================================================
-- Module registration
-- =============================================================================

HDG.Modules:Declare({
    name = "HousingObserver",
    dependencies = {},
    -- ADR-011: this module is the sole owner of the housing C_* namespaces.
    ownsBlizzardNamespaces = {
        "C_Housing", "C_HousingDecor", "C_HouseEditor", "C_NeighborhoodInitiative",
        "C_HousingLayout",   -- Projects topology capture + budget reads
    },
    blizzardEvents = {
        -- Placed-decor channel. Gated on IsHouseEditorActive in the handler
        -- so we only observe while the user has explicitly entered Blizzard's
        -- house editor mode (user-agency proxy). Without the gate, the event
        -- fires for visible decor across the neighborhood (neighbors' houses,
        -- flyovers, loading screens) and produces massive debug-log spam.
        HOUSE_EDITOR_MODE_CHANGED            = { handler = "OnEditorModeChanged" },
        HOUSING_DECOR_CUSTOMIZATION_CHANGED  = { handler = "OnDecorCustomization" },
        HOUSING_DECOR_REMOVED                = { handler = "OnDecorRemoved" },
        HOUSING_DECOR_PLACE_SUCCESS          = { handler = "OnDecorPlaceSuccess" },
        PLAYER_ENTERING_WORLD                = { handler = "OnEnteringWorld" },

        -- House meta channel. Both events spam on login (3-5 fires);
        -- debounce per wow-api MCP gotcha.
        PLAYER_HOUSE_LIST_UPDATED            = { handler = "OnPlayerHouseList",          debounce = 0.3 },
        HOUSE_LEVEL_FAVOR_UPDATED            = { handler = "OnHouseLevelFavor",          debounce = 0.3 },

        -- Active-neighborhood channel. Event fires whenever the
        -- neighborhood initiative cache settles. Handler reads
        -- C_NeighborhoodInitiative.GetActiveNeighborhood (sync) and
        -- dispatches whatever it returns (or nil).
        NEIGHBORHOOD_INITIATIVE_UPDATED      = { handler = "OnActiveNeighborhoodUpdated", debounce = 0.3 },

        -- Async rewards channel. Triggered by GetHouseLevelRewardsForLevel
        -- (called from OnHouseLevelFavor). Fires per-level with rewards.
        RECEIVED_HOUSE_LEVEL_REWARDS         = { handler = "OnHouseLevelRewardsEvent" },

        -- Projects topology capture: pin frames in Layout mode (passive); floor-change finalizes.
        -- Budget events refresh PROJECTS_HOUSE_TICK (debounced: fire per-decor during bulk placement).
        HOUSING_LAYOUT_PIN_FRAME_ADDED       = { handler = "OnPinFrameAddedEvent" },
        HOUSING_LAYOUT_VIEWED_FLOOR_CHANGED  = { handler = "OnLayoutFloorChangedEvent" },
        HOUSING_NUM_DECOR_PLACED_CHANGED     = { handler = "OnHousingBudgetEvent",      debounce = 0.3 },
        HOUSING_LAYOUT_ROOM_RECEIVED         = { handler = "OnHousingBudgetEvent",      debounce = 0.3 },
        HOUSING_LAYOUT_ROOM_REMOVED          = { handler = "OnHousingBudgetEvent",      debounce = 0.3 },
        HOUSING_LAYOUT_NUM_FLOORS_CHANGED    = { handler = "OnHousingBudgetEvent",      debounce = 0.3 },
    },

    OnEditorModeChanged = function(self)
        if C_HouseEditor and C_HouseEditor.IsHouseEditorActive
           and C_HouseEditor.IsHouseEditorActive() then
            HO:ClearPlaced()
        end
        HO:_OnCaptureModeChanged()   -- begin/finalize passive topology capture
        HO:_PushHouseTick()          -- editorActive + budgets may have changed
    end,

    OnDecorCustomization = function(self, decorGUID)
        -- Gate: IsHouseEditorActive = user actively editing their own house.
        -- Without gate, event fires for neighbors/flyovers/loading screens (spams OBSERVED_BATCH).
        if not (C_HouseEditor and C_HouseEditor.IsHouseEditorActive
                and C_HouseEditor.IsHouseEditorActive()) then
            return
        end
        HO:Observe(decorGUID)
    end,

    OnDecorRemoved = function(self, decorGUID)
        HO:RemovePlaced(decorGUID)
    end,

    -- Decor committed. Use pending itemID (PLACE_SUCCESS's decorGUID arg is always nil).
    -- Record here (not StartPlacing) so ESC cancels don't over-count.
    OnDecorPlaceSuccess = function(self)
        local itemID = HO._pendingPlaceItemID
        HO._pendingPlaceItemID = nil
        if not itemID then return end
        local houseID = _currentHouseID()
        if not houseID then return end
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.RECENT_DECOR_PLACED,
            payload = { houseKey = houseID, itemID = itemID },
        })
    end,

    OnEnteringWorld = function(self)
        -- Only clear placed-decor map when leaving a house context.
        -- C_Housing.IsInsideHouse catches both house + plot.
        if C_Housing and not C_Housing.IsInsideHouse() then
            HO:CancelSweep()   -- hearth//reload mid-sweep must not wedge the next capture
            HO:ClearPlaced()
        end
    end,

    OnPlayerHouseList = function(self, houseInfoList)
        HO:OnHouseList(houseInfoList)
    end,

    OnHouseLevelFavor = function(self, houseLevelFavor)
        HO:OnHouseLevelFavor(houseLevelFavor)
    end,

    OnActiveNeighborhoodUpdated = function(self)
        HO:OnActiveNeighborhood()
    end,

    OnHouseLevelRewardsEvent = function(self, level, rewards)
        HO:OnHouseLevelRewards(level, rewards)
    end,

    OnPinFrameAddedEvent = function(self, pinFrame)
        HO:OnPinFrameAdded(pinFrame)
    end,
    OnLayoutFloorChangedEvent = function(self)
        HO:OnLayoutFloorChanged()
    end,
    OnHousingBudgetEvent = function(self)
        HO:_PushHouseTick()
    end,

    onEnable = function(self)
        -- Defer to MAIN_WINDOW_OPENING: housing C_* null-derefs -> CTD on cold client
        -- at PLAYER_LOGIN. Steady-state events still arrive via blizzardEvents.
        -- See docs/COLD_CLIENT_CTD_INVESTIGATION.md.
        local A = HDG.Constants.ACTIONS
        self._kickToken = HDG.Store:Subscribe(function(actionType, invalidation)
            if actionType == A.MAIN_WINDOW_OPENING then
                if not self._kicked then
                    self._kicked = true
                    -- Kick: GetPlayerOwnedHouses -> PLAYER_HOUSE_LIST_UPDATED. Favor fetch
                    -- downstream is view-gated (OnHouseList loop) so it only fires when a
                    -- house-level view is the one being opened onto.
                    if C_Housing and C_Housing.GetPlayerOwnedHouses then
                        C_Housing.GetPlayerOwnedHouses()
                    end
                    -- Seed active-neighborhood (sync; may be nil before initiative settles -> next event updates).
                    HO:OnActiveNeighborhood()
                    -- Seed Projects budget/floor slot (same cold-client gate; C_HousingLayout touches housing C_*).
                    HO:_PushHouseTick()
                else
                    -- Reopen: UI_SET_PERSISTENT won't fire (view unchanged), so pull here. Self-gates.
                    HO:RequestRewardsForOwnedHouses()
                end
            elseif actionType == A.UI_SET_PERSISTENT then
                -- Tab switch -> pull rewards (self-gates to house-level views). Filter on the view write.
                if type(invalidation) == "table" and invalidation[1] ~= "account.ui.view" then return end
                HO:RequestRewardsForOwnedHouses()
            elseif actionType == A.HOUSE_LEVEL_UPDATED then
                -- A house's level just became known (favor captured) -> pull its rewards. Covers
                -- first-open, where favor lands after the House tab is already on screen. Self-gates.
                HO:RequestRewardsForOwnedHouses()
            end
        end)
    end,
    onShutdown = function(self)
        if self._kickToken then
            HDG.Store:Unsubscribe(self._kickToken)
            self._kickToken = nil
        end
    end,
})
