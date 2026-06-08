-- HDG.Projects.IDs
-- ============================================================================
-- Pure path-ID grammar for the Projects feature. No WoW API -- testable in
-- vanilla Lua. The hierarchy IS the key:
--   house:<token>  ->  :f<n>  ->  :r<shortUUID>  ->  :c<shortUUID>
-- <token> is a stable per-PLOT digest (hashToken of the house's neighborhood GUID
-- + plotID), so houses are keyed by their plot identity -- NOT by faction (which a
-- character would stamp wrong). Faction lives as an attribute on the house record.
-- Parent chain is recoverable by colon-split; rollups are prefix scans.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.IDs = HDG.Projects.IDs or {}
local M = HDG.Projects.IDs

-- A house token is any colon-free alphanumeric digest (see hashToken).
function M.makeHouseID(token)
    if type(token) ~= "string" or not token:match("^%w+$") then return nil end
    return "house:" .. token
end

function M.parseHouseID(key)
    if type(key) ~= "string" then return nil end
    return key:match("^house:(%w+)$")
end

-- Stable colon-free digest (djb2; pure arithmetic so it runs on WoW Lua 5.1 AND the
-- 5.4 test harness -- no bit library). Folds a house's neighborhood+plot identity
-- into a grammar-safe 8-hex token.
function M.hashToken(s)
    if type(s) ~= "string" then return nil end
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", math.floor(h))
end

local SHORT_UUID_PATTERN = "^[0-9a-f]+$"

function M.makeFloorID(houseID, floor)
    if type(houseID) ~= "string" then return nil end
    if type(floor) ~= "number" then return nil end
    if floor < 1 or floor ~= math.floor(floor) then return nil end
    if not M.parseHouseID(houseID) then return nil end
    return houseID .. ":f" .. tostring(floor)
end

function M.makeRoomID(floorID, shortUUID)
    if type(floorID) ~= "string" or type(shortUUID) ~= "string" then return nil end
    if shortUUID == "" or not shortUUID:match(SHORT_UUID_PATTERN) then return nil end
    return floorID .. ":r" .. shortUUID
end

function M.makeCrateID(roomID, shortUUID)
    if type(roomID) ~= "string" or type(shortUUID) ~= "string" then return nil end
    if shortUUID == "" or not shortUUID:match(SHORT_UUID_PATTERN) then return nil end
    return roomID .. ":c" .. shortUUID
end

function M.parsePath(key)
    if type(key) ~= "string" then return nil end
    -- Try fullest match first (crate), narrow downward. <token> = the house digest.
    local token, floorStr, roomShort, crateShort =
        key:match("^house:(%w+):f(%d+):r([0-9a-f]+):c([0-9a-f]+)$")
    if token then
        return {
            kind = "crate", floor = tonumber(floorStr),
            roomShortID = roomShort, crateShortID = crateShort,
            houseID = "house:" .. token,
            floorID = "house:" .. token .. ":f" .. floorStr,
            roomID  = "house:" .. token .. ":f" .. floorStr .. ":r" .. roomShort,
            crateID = key,
        }
    end

    token, floorStr, roomShort = key:match("^house:(%w+):f(%d+):r([0-9a-f]+)$")
    if token then
        return {
            kind = "room", floor = tonumber(floorStr), roomShortID = roomShort,
            houseID = "house:" .. token,
            floorID = "house:" .. token .. ":f" .. floorStr,
            roomID  = key,
        }
    end

    token, floorStr = key:match("^house:(%w+):f(%d+)$")
    if token then
        return {
            kind = "floor", floor = tonumber(floorStr),
            houseID = "house:" .. token, floorID = key,
        }
    end

    token = key:match("^house:(%w+)$")
    if token then return { kind = "house", houseID = key } end

    return nil
end

-- 4-char hex UUID is sufficient within a single house (~65k space). Collisions
-- are detected at mint-time and re-rolled by the controller's _mintRoomID helper
-- (HDGR_Controller_Projects.lua) -- NOT the reducer.
local function _hexChar()
    return string.format("%x", math.random(0, 15))
end

function M.shortUUID(len)
    len = len or 4
    if type(len) ~= "number" or len < 1 then return nil end
    local out = {}
    for i = 1, len do out[i] = _hexChar() end
    return table.concat(out)
end

local NAMESPACE_PATTERN = "^[a-z]+$"
local NAMESPACE_DEFAULT_LEN = 8

-- For lib_/ship_/plan_/orphan_ UUID-keyed records (faction- and room-agnostic).
function M.namespacedID(prefix, len)
    if type(prefix) ~= "string" or prefix == "" then return nil end
    if not prefix:match(NAMESPACE_PATTERN) then return nil end
    return prefix .. "_" .. M.shortUUID(len or NAMESPACE_DEFAULT_LEN)
end
