-- HDG.Projects.Capture
-- ============================================================================
-- Pure transform: raw captured pin data -> RoomRecord. The impure half
-- (reading pinFrame:GetRoomGUID()/GetDoorConnectionInfo()) lives in HousingObserver.
-- This module maps raw door facings -> player-cardinal doors (with occupancy) and
-- parses the structured roomGUID -- the capture-TRANSIENT inputs to the
-- Connectivity solver + AutoLayout rotation. The observer strips them after the
-- solve, so only { shape, name, cell, isBase, captureIndex } persist (nothing new
-- is stored; see HDGR_AUTOLAYOUT_SOLVER_SPEC_2026-08-10). Unit-testable in
-- vanilla Lua. No WoW API.
--
-- Raw captured room (from the observer's pin enumeration):
--   { roomGUID?, name, shape, isBase?,
--     doors = { { doorID, connectionType, facing (radians), occupied }, ... } }

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.Capture = HDG.Projects.Capture or {}
local M = HDG.Projects.Capture

local FP = HDG.Projects.Fingerprint   -- load order: Fingerprint before Capture (TOC + tests)

-- roomGUID "Housing-2-<HouseRoom recordID>-<placement counter, hex>" (verified live
-- 2026-08-10, spec SS2.2). The counter is chronological: every room's tree-parent
-- has a smaller counter (placement = clicking an existing room's door node), which
-- is the Connectivity solver's spine.
function M.parseRoomGUID(guid)
    if type(guid) ~= "string" then return nil, nil end
    local rid, pidx = guid:match("^Housing%-%d+%-(%d+)%-(%x+)$")
    if not rid then return nil, nil end   -- exception(boundary): GUID format is Blizzard-internal; a miss degrades to grid-pack + name-based shape resolution
    return tonumber(rid), tonumber(pidx, 16)
end

-- One raw captured room -> a RoomRecord (minus cell/plannedOnly, which the layout
-- + plan-mode own). Door facings become player-cardinals via the Fingerprint
-- N<->S flip; same-cardinal duplicates collapse with occupied-wins (any occupied
-- duplicate marks the cardinal occupied).
function M.buildRoomRecord(raw)
    if type(raw) ~= "table" then return nil end
    local byCard = {}
    if type(raw.doors) == "table" then
        for _, d in ipairs(raw.doors) do
            local card = FP.facingToCardinal(d.facing)
            if card then
                if byCard[card] == nil then byCard[card] = (d.occupied and true or false)
                elseif d.occupied then byCard[card] = true end
            end
        end
    end
    local doors = {}
    for card, occupied in pairs(byCard) do
        doors[#doors + 1] = { cardinal = card, occupied = occupied }
    end
    table.sort(doors, function(a, b) return a.cardinal < b.cardinal end)
    local recordID, placementIndex = M.parseRoomGUID(raw.roomGUID)
    -- Capture-transient record: recordID/placementIndex/doors feed the solver at
    -- commit time and are stripped before persistence (single-pipeline SSoT).
    return {
        shape          = raw.shape,
        name           = raw.name,
        recordID       = recordID,       -- -> locale-proof shape resolution + provenance
        placementIndex = placementIndex, -- -> solver chronological order
        doors          = doors,          -- -> solver stubs + AutoLayout.InferRotation
        isBase         = raw.isBase and true or false,
        captureIndex   = raw.captureIndex, -- room-label disambiguation + deterministic roomID
    }
end

-- Batch: { [key] = rawRoom } -> { [key] = RoomRecord }. Key is whatever the
-- caller keys by; the observer re-keys to stable internal roomIDs by deterministic
-- captureIndex (floor + capture order).
function M.buildRoomRecords(rawRooms)
    local out = {}
    for key, raw in pairs(rawRooms or {}) do
        out[key] = M.buildRoomRecord(raw)
    end
    return out
end
