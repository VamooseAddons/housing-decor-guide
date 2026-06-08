-- HDG.Projects.LayoutCodec -- export / import codec for build LAYOUTS (geometry).
--
-- Format: "HDGRLAYOUT:2:<base64>". Decoded payload is newline-separated:
--   Line 1: header -- "name=<urlencoded>;floors=<n?>"
--   Lines 2..N: one room each, HOUSE-AGNOSTIC (no roomID / no faction baked in):
--     floor,shape,x,y,rotation,floors
--   floors = per-room vertical-span override (0 = use the shape default). One record
--   per room -- multi-floor rooms derive their span, so there are no stack links.
--
--   Encode(version) -> "HDGRLAYOUT:2:..."    pure encoder (reads a version table)
--   Decode(encoded) -> { name, numFloors, rooms = { {floor,shape,x,y,rotation,floors}, ... } } | nil
--     -- nil on empty / wrong magic / unparseable. NEVER errors (untrusted input).
--
-- Codes carry NO house/faction -- the importer mints fresh roomIDs under the TARGET
-- house, so a layout shared from an Alliance house imports cleanly into a Horde one.
-- Geometry only (no decor), by design.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.LayoutCodec = HDG.Projects.LayoutCodec or {}
local C = HDG.Projects.LayoutCodec

local MAGIC, VER, MAX = "HDGRLAYOUT", "2", 300

local b64encode, b64decode = HDG.Codec.b64encode, HDG.Codec.b64decode
local urlencode, urldecode = HDG.Codec.urlencode, HDG.Codec.urldecode

-- ===== Encode ===============================================================
function C.Encode(version)
    if type(version) ~= "table" or type(version.rooms) ~= "table" then return nil end
    local IDs = HDG.Projects.IDs
    local ids = {}                              -- sorted -> deterministic output (memo/tests)
    for rid in pairs(version.rooms) do ids[#ids + 1] = rid end
    table.sort(ids)

    local lines = { "name=" .. urlencode(version.name or "Layout")
                    .. ";floors=" .. tostring(version.numFloors or "") }
    for _, rid in ipairs(ids) do
        local room = version.rooms[rid]
        local p    = IDs.parsePath(rid)
        local cell = room.cell or {}
        lines[#lines + 1] = table.concat({
            (p and p.floor) or 1, room.shape, cell.x or 0, cell.y or 0, cell.rotation or 0,
            room.floors or 0,   -- per-room span override; 0 = shape default
        }, ",")
    end
    return MAGIC .. ":" .. VER .. ":" .. b64encode(table.concat(lines, "\n"))
end

-- ===== Decode ===============================================================
function C.Decode(encoded)
    if type(encoded) ~= "string" or #encoded == 0 then return nil end
    local prefix, ver, payload = encoded:match("^(HDGRLAYOUT):(%d+):(.+)$")
    if prefix ~= MAGIC or ver ~= VER then return nil end
    local decoded = b64decode(payload)
    if not decoded or #decoded == 0 then return nil end

    local name, numFloors, rooms, first = "Imported layout", nil, {}, true
    for line in decoded:gmatch("[^\n]+") do
        if first then
            first = false
            local nm = line:match("name=([^;]*)")
            if nm then name = urldecode(nm) end
            local fl = line:match("floors=(%d+)")
            if fl then numFloors = tonumber(fl) end
        else
            if #rooms >= MAX then break end
            local floor, shape, x, y, rot, floors =
                line:match("^(%-?%d+),([%w_]+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
            if floor and shape then
                local f = tonumber(floors)
                rooms[#rooms + 1] = {                                    -- exception(boundary): codec parse
                    floor = tonumber(floor), shape = shape,
                    x = tonumber(x), y = tonumber(y), rotation = tonumber(rot),
                    floors = (f and f ~= 0) and f or nil,
                }
            end
        end
    end
    if #rooms == 0 then return nil end
    return { name = name, numFloors = numFloors, rooms = rooms }
end
