-- HDG.Projects.Fingerprint
-- ============================================================================
-- Pure facing -> player-cardinal conversion. (Room fingerprinting + re-association
-- were RETIRED with the single-record SSoT: recaptures match by the deterministic
-- captureIndex roomID, and doors/occupancy/connectivity derive from cell-adjacency.
-- Only the facing converter remains -- a capture-time input for Capture + AutoLayout.)
-- No WoW API.
--
-- N<->S axis flip: Blizzard's data compass is flipped vs the player-facing view --
-- data-facing 0 (compass-N) = player sees it on the SOUTH side (verified in-game).

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.Fingerprint = HDG.Projects.Fingerprint or {}
local M = HDG.Projects.Fingerprint

local TWO_PI  = 2 * math.pi
local QUARTER = math.pi / 2
-- bucket: data-N(0)->player"S", data-E(pi/2)->"E", data-S(pi)->"N", data-W(3pi/2)->"W"
local DIRS = { "S", "E", "N", "W" }

function M.facingToCardinal(rad)
    if type(rad) ~= "number" then return nil end
    local r = rad % TWO_PI
    if r < 0 then r = r + TWO_PI end
    local q = math.floor((r + QUARTER / 2) / QUARTER) % 4
    return DIRS[q + 1]
end
