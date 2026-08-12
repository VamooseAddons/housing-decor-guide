-- HDG.CaptureTap
-- ============================================================================
-- Debug-gated PASSIVE recorder for the raw Layout-mode capture stream. Rides
-- the HousingObserver capture session (HO calls OnBegin/OnPin/OnEnd) and
-- records everything a pin exposes -- unfiltered, nothing stripped -- plus
-- timed late re-probes of the live pin pools, to answer the auto-layout data
-- questions offline:
--   1. Do pins EVER expose readable geometry (C++ positions them async after
--      PIN_FRAME_ADDED -- we only ever probed AT add time)?
--   2. Do the Blizzard pool MIXIN wrappers carry position fields the frame
--      doesn't (map-pin style normalizedX/Y)?
--   3. Is ADDED-event order spatially meaningful?
--   4. Full raw door table (doorID/type/facing/occupied) per room, as a
--      solver fixture.
--
-- Enable:  /run HDG_DB.captureTap = true
-- Capture: enter Layout mode (or Capture All Floors), wait ~6s, /reload.
-- Output:  HDG_DB.debugCapture.sessions (ring of last 6 tap sessions).
--
-- PASSIVE: no Select()/Drag()/SetUpdateCallback, no editor writes, no store
-- writes. Inert unless the flag is set. External surface: pin frames handed
-- over by HO, HouseEditorFrame layout pin pools (late probes), C_Timer.

HDG = HDG or {}
HDG.CaptureTap = HDG.CaptureTap or {}
local M = HDG.CaptureTap

HDG.Log:RegisterTags({ capture_tap = { user = false, level = "info" } })

local PROBE_DELAYS = { 0.5, 1.0, 2.5, 5.0 }   -- seconds after session begin
local MAX_SESSIONS = 6

local _session   -- active tap session buffer, nil when idle

local function _enabled()
    return (_G.HDG_DB and _G.HDG_DB.captureTap) and true or false  -- exception(boundary): raw SavedVariable read; debug gate, mirrors HDG_DB.perf
end

-- ---------------------------------------------------------------------------
-- Geometry probe. Shared with HousingObserver's perf-gated posAdd diagnostic.
-- Pin frames are C++ mixins positioned asynchronously; most getters return
-- nil at ADDED time -- record whatever IS readable at the probe moment.
-- ---------------------------------------------------------------------------
function M.ProbeGeometry(pin)
    if not pin then return nil end
    local o = {}
    local function g(k, fn)
        local r = { pcall(fn) }  -- exception(fire-forget): debug-only pin geometry; skip on any error
        if r[1] and r[2] ~= nil then table.remove(r, 1); o[k] = r end
    end
    g("center",  function() return pin:GetCenter() end)   -- cx, cy (scaled screen px)
    g("rect",    function() return pin:GetRect() end)      -- x, y, w, h
    g("left",    function() return pin:GetLeft() end)
    g("top",     function() return pin:GetTop() end)
    g("scale",   function() return pin:GetEffectiveScale() end)
    g("numPts",  function() return pin:GetNumPoints() end)
    g("shown",   function() return pin:IsShown() end)
    g("visible", function() return pin:IsVisible() end)
    do  -- GetPoint -> point, relativeTo(FRAME -- name only), relativePoint, xOfs, yOfs
        local ok, pt, rel, rpt, x, y = pcall(function() return pin:GetPoint(1) end)  -- exception(fire-forget): debug-only pin geometry; skip on any error
        if ok and pt ~= nil then
            o.point = { pt, rel and (rel:GetName() or "<anon>") or nil, rpt, x, y }
        end
    end
    g("parents", function()   -- who owns/positions the pin -- 3-level parent chain
        local names, p = {}, pin:GetParent()
        for _ = 1, 3 do
            if not p then break end
            names[#names + 1] = p:GetName() or "<anon>"
            p = p:GetParent()
        end
        return table.concat(names, " < ")
    end)
    return next(o) and o or nil
end

-- Shallow scalar dump of a Blizzard pool-mixin wrapper: position fields would
-- live HERE (map-pin style), not on the C++ frame. Non-scalars recorded as
-- "<type>" so the key inventory is complete without serializing frames.
local function _shallowDump(t)
    local out, n = {}, 0
    for k, v in pairs(t) do
        n = n + 1
        if n > 60 then out["OVERFLOW"] = true; break end
        local tv = type(v)
        if tv == "string" or tv == "number" or tv == "boolean" then
            out[tostring(k)] = v
        else
            out[tostring(k)] = "<" .. tv .. ">"
        end
    end
    return next(out) and out or nil
end

-- ---------------------------------------------------------------------------
-- Session lifecycle (called by HousingObserver at its capture seams).
-- ---------------------------------------------------------------------------
function M.OnBegin(floor)
    if not _enabled() then return end
    if _session then M.OnEnd() end   -- overlapping begin: close the old session first
    local v, build, bdate, toc = GetBuildInfo()
    _session = {
        floor = floor, startedAt = GetTime(), wallClock = time(),
        build = { version = v, build = build, date = bdate, toc = toc },
        pins = {}, probes = {}, seq = 0,
    }
    local s = _session
    for _, delay in ipairs(PROBE_DELAYS) do
        C_Timer.After(delay, function() M._LateProbe(s, delay) end)
    end
    HDG.Log:Info("capture_tap", ("tap: session started (floor %s)"):format(tostring(floor)))
end

-- Raw ADDED-stream record: called for EVERY pin event, before HO's ingest
-- filters (nil roomGUID pins included -- the tap sees the unfiltered stream).
function M.OnPin(pinFrame)
    if not _session then return end
    _session.seq = _session.seq + 1
    local pinType = pinFrame:GetPinType()
    local rec = {
        seq = _session.seq, t = GetTime() - _session.startedAt,
        pinType = pinType,
        roomGUID = pinFrame:GetRoomGUID(),
        geo = M.ProbeGeometry(pinFrame),
    }
    if pinType == 1 then       -- room pin
        rec.name           = pinFrame:GetRoomName()
        rec.canRemove      = pinFrame:CanRemove()
        rec.canMove        = pinFrame:CanMove()
        rec.canRotate      = pinFrame:CanRotate()
        rec.validFloorplan = pinFrame:IsValidForSelectedFloorplan()
    elseif pinType == 0 then   -- door pin
        local d = pinFrame:GetDoorConnectionInfo()
        if d then
            rec.doorID         = d.doorID
            rec.connectionType = d.connectionType
            rec.facing         = d.doorFacing
        end
        rec.occupied = pinFrame:IsOccupiedDoor()
    end
    _session.pins[#_session.pins + 1] = rec
end

function M.OnEnd()
    if not _session then return end
    local s = _session
    _session = nil
    s.endedAt = GetTime() - s.startedAt
    -- exception(boundary): raw SavedVariable write; debug instrumentation output, store never sees it
    local db = _G.HDG_DB
    if not db then return end
    db.debugCapture = db.debugCapture or { sessions = {} }
    local list = db.debugCapture.sessions
    list[#list + 1] = s
    while #list > MAX_SESSIONS do table.remove(list, 1) end
    HDG.Log:Info("capture_tap", ("tap: recorded %d pins on floor %s (probes land up to %ds in)")
        :format(#s.pins, tostring(s.floor), PROBE_DELAYS[#PROBE_DELAYS]))
end

-- ---------------------------------------------------------------------------
-- Timed late probe: re-read geometry + identity for every ACTIVE pin via the
-- live pools. Runs off a per-session closure; a probe firing after the session
-- ended (sweep floor-advance) still lands in ITS session, flagged afterEnd --
-- the pool then holds the NEXT floor's pins, correlate by roomGUID offline.
-- ---------------------------------------------------------------------------

-- One active pool entry -> probe record. Pool kind tells us door vs room, so
-- door fields are strict reads -- an unexpected pool shape errors into the
-- _LateProbe pcall and lands as probe.err (that IS the finding).
local function _probeActivePin(poolName, mixin)
    local pin = mixin.pin or mixin   -- exception(boundary): Blizzard pin pools yield mixin wrappers with the real Frame on .pin; bare frames observed too
    local rec = {
        pool     = poolName,
        roomGUID = pin:GetRoomGUID(),
        geo      = M.ProbeGeometry(pin),
    }
    if mixin ~= pin then
        rec.mixin    = _shallowDump(mixin)
        rec.mixinGeo = M.ProbeGeometry(mixin)   -- wrapper may be its own positioned frame
    end
    if poolName == "doorPinPool" then
        local d = pin:GetDoorConnectionInfo()
        if d then
            rec.doorID         = d.doorID
            rec.connectionType = d.connectionType
            rec.facing         = d.doorFacing
        end
        rec.occupied = pin:IsOccupiedDoor()
    end
    return rec
end

local function _probePools(probe)
    local lm = _G.HouseEditorFrame and _G.HouseEditorFrame.LayoutModeFrame   -- exception(boundary): Blizzard editor frame; absent when the editor is closed
    if not lm then probe.note = "no LayoutModeFrame"; return end
    for _, poolName in ipairs({ "roomPinPool", "doorPinPool" }) do
        local pool = lm[poolName]   -- exception(boundary): pool fields are Blizzard-private internals; absence is a recorded finding
        if pool then
            for mixin in pool:EnumerateActive() do
                probe.pins[#probe.pins + 1] = _probeActivePin(poolName, mixin)
            end
        else
            probe.note = (probe.note and (probe.note .. "; ") or "") .. "no " .. poolName
        end
    end
end

function M._LateProbe(s, delay)
    local probe = { delay = delay, t = GetTime() - s.startedAt,
                    afterEnd = (s.endedAt ~= nil) or nil, pins = {} }
    s.probes[#s.probes + 1] = probe
    local ok, err = pcall(_probePools, probe)  -- exception(fire-forget): pool internals are Blizzard-private + exist only while the Layout view shows; failure is recorded on the probe + warned
    if not ok then
        probe.err = tostring(err)
        HDG.Log:Warn("capture_tap", "late probe failed: " .. tostring(err))
    end
end
