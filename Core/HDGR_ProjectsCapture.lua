-- HDG.Projects.Capture
-- ============================================================================
-- Pure transform: raw captured pin data -> persisted RoomRecord. The impure half
-- (reading pinFrame:GetRoomGUID()/GetDoorConnectionInfo()) lives in HousingObserver.
-- This module maps raw door facings -> player-cardinals (doorCardinals) -- the ONLY
-- capture-time geometry kept, feeding AutoLayout.InferRotation so the grid-pack
-- rotates each room the way its doors faced. Connectivity/occupancy reconstruction
-- was retired with the grid-pack SSoT. Unit-testable in vanilla Lua. No WoW API.
--
-- Raw captured room (from the observer's pin enumeration):
--   { roomGUID?, name, shape, isBase?,
--     doors = { { doorID, connectionType, facing (radians), occupied }, ... } }

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.Capture = HDG.Projects.Capture or {}
local M = HDG.Projects.Capture

local FP = HDG.Projects.Fingerprint   -- load order: Fingerprint before Capture (TOC + tests)

-- One raw captured room -> a persisted RoomRecord (minus cell/plannedOnly,
-- which the layout + plan-mode own). Door facings become player-cardinals via
-- the Fingerprint N<->S flip; doorCardinals is sorted unique.
function M.buildRoomRecord(raw)
    if type(raw) ~= "table" then return nil end
    local doorCards, seen = {}, {}
    if type(raw.doors) == "table" then
        for _, d in ipairs(raw.doors) do
            local card = FP.facingToCardinal(d.facing)
            if card and not seen[card] then seen[card] = true; doorCards[#doorCards + 1] = card end
        end
    end
    table.sort(doorCards)
    -- Capture-time record. doorCardinals is the only geometry kept -- an INPUT to
    -- AutoLayout.InferRotation (grid-pack); the observer strips it after, so only
    -- { shape, name, cell, isBase, captureIndex } persist (single-pipeline SSoT).
    return {
        shape         = raw.shape,
        name          = raw.name,
        doorCardinals = doorCards,        -- -> AutoLayout.InferRotation (capture-time)
        isBase        = raw.isBase and true or false,
        captureIndex  = raw.captureIndex, -- room-label disambiguation + deterministic roomID
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
