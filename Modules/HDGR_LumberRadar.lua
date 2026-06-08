-- HDG.LumberRadar
-- ============================================================================
-- Circular radar widget. Owns frame construction (rings, player dot, cardinal
-- labels, blip pool) and per-frame render (player coords + blip projection).
-- State input via Components' dispatchLumberRadar (selector values from BindingEngine).
-- Player coords + facing are Blizzard boundaries re-fetched each OnUpdate tick.

HDG = HDG or {}
HDG.LumberRadar = HDG.LumberRadar or {}
local R = HDG.LumberRadar

-- ===== Tunables ==============================================================
local CONFIG = {
    SIZE              = 200,    -- pixel diameter of the radar frame
    RANGE_YARDS       = 450,    -- world radius the radar covers
    RING_DISTANCES    = { 150, 300 },  -- distance rings in yards
    UPDATE_FREQUENCY  = 0.05,   -- 20 fps render tick
    BLIP_SIZE         = 5,      -- pixel size of each blip dot
    PLAYER_DOT_SIZE   = 7,
    DIRECTION_LINE_LEN = 22,
    BG_TEXTURE        = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    OUTER_GLOW_OFFSET = 4,      -- px the outer halo extends past the radar
    -- Pool cap: GC sweep keeps blips bounded; this cap prevents render-time spikes.
    MAX_BLIPS         = 100,
    -- RESPAWN = node respawn window (10 min). Age ratios: 0-50% red, 50-90% yellow, 90%+ green, 1hr+ grey.
    RESPAWN_SECONDS   = 600,
}
R.CONFIG = CONFIG

-- Decay-threshold ratios (age / RESPAWN_SECONDS).
local DECAY = {
    FRESH      = 0.5,   -- 0-50% of respawn: red (just cut)
    RESPAWNING = 0.9,   -- 50-90%: yellow (warming up)
    -- 90%+ up to OLD: green (ready to gather)
    OLD        = 3600,  -- after 1 hour: grey (stale)
}

-- Heatmap colors (matched to HDG for visual parity).
local COLOR = {
    FRESH      = { 1.0, 0.2, 0.2, 1.0   },  -- red
    RESPAWNING = { 1.0, 1.0, 0.0, 0.9   },  -- yellow
    READY      = { 0.0, 1.0, 0.0, 1.0   },  -- green
    OLD        = { 0.5, 0.5, 0.5, 0.3   },  -- grey
}

-- Localize hot-path math to avoid table lookups at 20 fps.
local sin, cos, sqrt, atan2, pi = math.sin, math.cos, math.sqrt, math.atan2, math.pi
local TWO_PI = 2 * pi

-- ===== World coord boundary ==================================================
-- GetWorldPosFromMapPos converts map-relative coords to world yards.
-- Reusable Vector2D avoids per-call allocation. Returns (worldX, worldY, instanceID).
local _reusableVec = _G.CreateVector2D and _G.CreateVector2D(0, 0) or nil

local function _mapToWorld(mapID, mapX, mapY)
    if not (mapID and _G.C_Map and _G.C_Map.GetWorldPosFromMapPos) then
        return nil
    end
    if not _reusableVec then
        if not _G.CreateVector2D then return nil end
        _reusableVec = _G.CreateVector2D(0, 0)
    end
    _reusableVec.x, _reusableVec.y = mapX, mapY
    local instance, worldPos = _G.C_Map.GetWorldPosFromMapPos(mapID, _reusableVec)  -- exception(boundary): C_Map nil off-map / no zone
    if not worldPos then return nil end
    local x, y = worldPos:GetXY()
    return x, y, instance
end

-- ===== Player coords boundary ===============================================
-- Returns map-coords + facing + world-coords + instance in one boundary call per tick.
-- nil on mid-loading-screen or sub-map with no resolvable world coords.
local function _getPlayerSnapshot()
    if not (_G.C_Map and _G.C_Map.GetBestMapForUnit
        and _G.C_Map.GetPlayerMapPosition and _G.GetPlayerFacing) then
        return nil
    end
    local mapID = _G.C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = _G.C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local facing = _G.GetPlayerFacing()
    if not facing then return nil end
    local wx, wy, instance = _mapToWorld(mapID, pos.x, pos.y)
    -- World-conversion failure -> degraded mode (chrome stays, blips skipped).
    return { mapX = pos.x, mapY = pos.y, mapID = mapID, facing = facing,
             worldX = wx, worldY = wy, instance = instance }  -- exception(boundary): worldX/Y nil when C_Map world-conversion fails
end

-- ===== Construction ==========================================================
function R:Build(parent, opts)
    opts = opts or {}
    local size = opts.size or CONFIG.SIZE
    parent:SetSize(size, size)

    -- Outer edge glow: subtle green halo slightly larger than the radar.
    -- Pure decorative aesthetic from the HDG donor; sits at BACKGROUND
    -- sublayer 0 (below everything else).
    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(size + CONFIG.OUTER_GLOW_OFFSET, size + CONFIG.OUTER_GLOW_OFFSET)
    glow:SetPoint("CENTER")
    glow:SetTexture(CONFIG.BG_TEXTURE)
    glow:SetVertexColor(0, 0.25, 0, 0.35)

    -- Circular background mask -- BACKGROUND sublayer 1 (above glow).
    local bg = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetTexture(CONFIG.BG_TEXTURE)
    bg:SetVertexColor(0.02, 0.02, 0.05, 0.65)

    -- Distance rings: outer + cutout = ring outline. "<N>y" label at 6 o'clock.
    local ringHandles = {}
    for _, radiusYards in ipairs(CONFIG.RING_DISTANCES) do
        local px = (radiusYards / CONFIG.RANGE_YARDS) * size
        local ring = parent:CreateTexture(nil, "BORDER")
        ring:SetTexture(CONFIG.BG_TEXTURE)
        ring:SetVertexColor(0.3, 0.6, 0.3, 0.30)
        ring:SetSize(px, px)
        ring:SetPoint("CENTER")
        local cutout = parent:CreateTexture(nil, "BORDER", nil, 1)
        cutout:SetTexture(CONFIG.BG_TEXTURE)
        cutout:SetVertexColor(0.02, 0.02, 0.05, 0.65)
        cutout:SetSize(px - 4, px - 4)
        cutout:SetPoint("CENTER")
        -- Distance label at 6 o'clock on the ring line.
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", parent, "CENTER", 0, -(px / 2))
        label:SetText(radiusYards .. "y")
        label:SetTextColor(0, 1, 0, 0.5)
        ringHandles[#ringHandles + 1] = { ring = ring, cutout = cutout,
                                          label = label, radiusYards = radiusYards }
    end

    -- Cardinal labels: built once with world angles; repositioned each tick by player facing.
    local cardinalOffset = (size / 2) - 12
    local function _makeCardinal(text, baseAngle)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetText(text)
        fs:SetTextColor(0.7, 0.7, 0.7, 0.85)
        return { fs = fs, baseAngle = baseAngle }
    end
    local cardinals = {
        N = _makeCardinal("N",          0),
        W = _makeCardinal("W",  pi /  2),
        S = _makeCardinal("S",  pi),
        E = _makeCardinal("E", -pi /  2),
    }

    -- Player dot (always at exact center)
    local playerDot = parent:CreateTexture(nil, "OVERLAY")
    playerDot:SetSize(CONFIG.PLAYER_DOT_SIZE, CONFIG.PLAYER_DOT_SIZE)
    playerDot:SetTexture(CONFIG.BG_TEXTURE)
    playerDot:SetVertexColor(0.4, 1.0, 0.4, 1)
    playerDot:SetPoint("CENTER")

    -- Direction line: SetRotation around center; BOTTOM->CENTER so it extends upward.
    local directionLine = parent:CreateTexture(nil, "ARTWORK")
    directionLine:SetSize(2, CONFIG.DIRECTION_LINE_LEN)
    directionLine:SetTexture(CONFIG.BG_TEXTURE)
    directionLine:SetVertexColor(0.4, 1.0, 0.4, 0.85)
    directionLine:SetPoint("BOTTOM", parent, "CENTER", 0, 2)

    parent._updateAccum = 0

    return {
        parent          = parent,
        size            = size,
        ringHandles     = ringHandles,
        playerDot       = playerDot,
        directionLine   = directionLine,
        cardinals       = cardinals,
        cardinalOffset  = cardinalOffset,
        -- Blip pool: live keys -> Texture; freeBlips for re-acquire; allocatedCount caps.
        blipPool        = {},
        freeBlips       = {},
        allocatedCount  = 0,
        -- worldCache keyed by blip identity; invalidated on mapID change (new world-coord origin).
        worldCache      = {},
        cachedForMapID  = nil,
        -- Latest data from BindingEngine (dispatchLumberRadar writes these)
        blips           = {},
        scale           = 1.0,
    }
end

-- ===== Blip pool helpers ====================================================
local function _blipKey(blip)
    -- Positional key: same-node harvests share the key (refreshes blip to red);
    -- different positions get distinct keys. ts:lumberID caused same-frame collapse
    -- (GetTime() quantizes per frame -> identical ts -> single blip entry).
    return string.format("%d_%.6f_%.6f", blip.mapID, blip.x, blip.y)
end

local function _acquireBlip(handles)
    local b = table.remove(handles.freeBlips)
    if not b then
        if handles.allocatedCount >= CONFIG.MAX_BLIPS then  -- pool cap: bail to prevent frame leaks
            return nil
        end
        b = handles.parent:CreateTexture(nil, "OVERLAY")
        b:SetTexture(CONFIG.BG_TEXTURE)
        b:SetSize(CONFIG.BLIP_SIZE, CONFIG.BLIP_SIZE)
        handles.allocatedCount = handles.allocatedCount + 1
    end
    b:Show()
    return b
end

local function _releaseBlip(handles, b)
    b:Hide()
    b:ClearAllPoints()
    handles.freeBlips[#handles.freeBlips + 1] = b
end

-- Resolve blip world coords via cache; invalidated on mapID change (world-coord origin shifts).
local function _resolveBlipWorld(handles, mapID, blip)
    if handles.cachedForMapID ~= mapID then
        handles.worldCache = {}
        handles.cachedForMapID = mapID
    end
    local key = _blipKey(blip)
    local entry = handles.worldCache[key]
    if entry then
        return entry.wx, entry.wy, entry.instance
    end
    local wx, wy, instance = _mapToWorld(blip.mapID, blip.x, blip.y)
    if wx then
        handles.worldCache[key] = { wx = wx, wy = wy, instance = instance }
    end
    return wx, wy, instance
end

-- Pick the heatmap color for a blip based on its age in seconds.
local function _ageColor(ageSec)
    if ageSec > DECAY.OLD then
        return COLOR.OLD
    end
    local ratio = ageSec / CONFIG.RESPAWN_SECONDS
    if ratio < DECAY.FRESH then
        return COLOR.FRESH
    elseif ratio < DECAY.RESPAWNING then
        return COLOR.RESPAWNING
    else
        return COLOR.READY
    end
end

-- ===== Render primitives =====================================================

-- Mid-loading-screen / API unavailable: hide all pooled blips, retry next tick.
local function _clearAllBlips(handles)
    for key, h in pairs(handles.blipPool) do
        _releaseBlip(handles, h)
        handles.blipPool[key] = nil
    end
end

-- Rotate cardinal labels. baseAngle = world angle (0=N, pi/2=W); subtract facing for screen angle.
local function _orientCardinals(handles, facing)
    local off = handles.cardinalOffset
    for _, card in pairs(handles.cardinals) do
        local rel = card.baseAngle - facing
        card.fs:ClearAllPoints()
        card.fs:SetPoint("CENTER", handles.parent, "CENTER",
            -sin(rel) * off, cos(rel) * off)
    end
end

-- Wrap to [-pi, pi] (single-valued across the +/-pi discontinuity).
local function _normalizeAngle(a)
    if a >  pi then return a - TWO_PI end
    if a < -pi then return a + TWO_PI end
    return a
end

-- Project blip to screen. WoW: +X=north, +Y=west.
-- 1. atan2(dy,dx) = world bearing. 2. Subtract facing = relative angle. 3. Normalize [-pi,pi].
-- 4. screenX = -sin(rel)*r, screenY = cos(rel)*r (blip ahead = top of radar).
-- Note: 2D rotation matrix approach swaps axes; this verbatim atan2 form is correct.
local function _projectToScreen(dx, dy, dist, facing, halfRadar, rangeYards)
    local rel = _normalizeAngle(atan2(dy, dx) - facing)
    local r   = (dist / rangeYards) * halfRadar
    return -sin(rel) * r, cos(rel) * r
end

-- Acquire/reuse blip handle; place at (screenX, screenY) tinted by age. No-op if pool exhausted.
local function _placeBlip(handles, key, blip, screenX, screenY, now, seen)
    local handle = handles.blipPool[key]
    if not handle then
        handle = _acquireBlip(handles)
        if not handle then return end                  -- pool exhausted
        handles.blipPool[key] = handle
    end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", handles.parent, "CENTER", screenX, screenY)
    -- blip.ts = GetTime() at harvest; age = now - blip.ts.
    local c = _ageColor(now - (blip.ts or now))
    handle:SetVertexColor(c[1], c[2], c[3], c[4])
    seen[key] = true
end

-- Per-blip: filter by zone+instance, gate on range, project + place.
local function _renderBlip(handles, blip, snap, halfRadar, rangeYards, now, seen)
    if blip.mapID ~= snap.mapID then return end
    local bwx, bwy, bInstance = _resolveBlipWorld(handles, snap.mapID, blip)
    if not bwx or bInstance ~= snap.instance then return end
    local dx, dy = bwx - snap.worldX, bwy - snap.worldY
    local dist   = sqrt(dx * dx + dy * dy)
    if dist >= rangeYards then return end
    local screenX, screenY = _projectToScreen(dx, dy, dist, snap.facing, halfRadar, rangeYards)
    _placeBlip(handles, _blipKey(blip), blip, screenX, screenY, now, seen)
end

-- Release blips not placed this tick (dropped by selector, out-of-range, or world conversion failed).
local function _releaseUnseen(handles, seen)
    for key, h in pairs(handles.blipPool) do
        if not seen[key] then
            _releaseBlip(handles, h)
            handles.blipPool[key] = nil
        end
    end
end

function R:Render(handles)
    local snap = _getPlayerSnapshot()
    if not snap then
        _clearAllBlips(handles)
        return
    end

    -- Direction line stays static (pointing up). Blip math subtracts facing; ahead = top.
    -- Note: SetRotation(-facing) on the line caused double-rotation (was wrong).
    _orientCardinals(handles, snap.facing)

    local seen       = {}
    local halfRadar  = handles.size / 2
    local rangeYards = CONFIG.RANGE_YARDS
    local now        = _G.GetTime and _G.GetTime() or 0  -- exception(boundary): age recalc

    -- World-coord path: snap.worldX must be non-nil; instanced maps skip blip render (chrome stays).
    if snap.worldX then
        for _, blip in ipairs(handles.blips) do
            _renderBlip(handles, blip, snap, halfRadar, rangeYards, now, seen)
        end
    end

    _releaseUnseen(handles, seen)
end

-- Called from Components' dispatchLumberRadar when binding values change.
function R:UpdateData(handles, values)
    if values.blips ~= nil then handles.blips = values.blips end
    if values.scale ~= nil then
        handles.scale = values.scale
        handles.parent:SetScale(values.scale)
    end
end

-- Throttle interval for Components' OnUpdate.
R.UPDATE_FREQUENCY = CONFIG.UPDATE_FREQUENCY
