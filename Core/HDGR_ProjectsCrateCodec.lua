-- HDG.Projects.CrateCodec -- export / import codec for decor crates.
--
-- Format: "HDGRCRATE:1:<base64>". Decoded payload is newline-separated:
--   Line 1: header -- "name=<urlencoded>"  (the crate's display name)
--   Lines 2..N: itemID,count
--
--   Encode(crateRecord) -> "HDGRCRATE:1:..."   pure encoder
--   Decode(encoded)     -> { name, decor = {{id,count},...} } | nil
--     -- nil on empty / wrong magic / unparseable. NEVER errors -- untrusted
--     -- input boundary by design (the Import controller no-ops a nil). Mirrors
--     -- HDG.ShoppingCodec exactly (same pure-Lua base64, header-vs-line split).
--
-- crate decor `id` is the ITEMID (the value crateDetail's ResolveName/Icon take),
-- so a round-trip is itemID-faithful; the importer feeds FURN_SET_ITEM_ADD{itemID=id}.

HDG = HDG or {}
HDG.Projects = HDG.Projects or {}
HDG.Projects.CrateCodec = HDG.Projects.CrateCodec or {}
local C = HDG.Projects.CrateCodec

local MAGIC, VER, MAX = "HDGRCRATE", "1", 500

-- Base64 + url helpers shared via HDG.Codec (loads first in the TOC).
local b64encode, b64decode = HDG.Codec.b64encode, HDG.Codec.b64decode
local urlencode, urldecode = HDG.Codec.urlencode, HDG.Codec.urldecode

-- ===== Encode ===============================================================
function C.Encode(crate)
    if type(crate) ~= "table" then return nil end
    local decor = type(crate.decor) == "table" and crate.decor or {}
    local lines = { "name=" .. urlencode(crate.name or "Crate") }
    for _, d in ipairs(decor) do
        if type(d) == "table" and type(d.id) == "number" then
            local cnt = (type(d.count) == "number" and d.count) or 1
            lines[#lines + 1] = d.id .. "," .. cnt
        end
    end
    return MAGIC .. ":" .. VER .. ":" .. b64encode(table.concat(lines, "\n"))
end

-- ===== Decode ===============================================================
local function parseDecorLine(line)
    local id, cnt = line:match("^(%-?%d+),(%-?%d+)$")
    id = tonumber(id)
    if not id then return nil end
    return { id = id, count = tonumber(cnt) or 1 }   -- exception(boundary): codec parse
end

function C.Decode(encoded)
    if type(encoded) ~= "string" or #encoded == 0 then return nil end
    local prefix, ver, payload = encoded:match("^(HDGRCRATE):(%d+):(.+)$")
    if prefix ~= MAGIC or ver ~= VER then return nil end
    local decoded = b64decode(payload)
    if not decoded or #decoded == 0 then return nil end

    local name, decor, first = "Imported crate", {}, true
    for line in decoded:gmatch("[^\n]+") do
        if first then
            first = false
            -- letter-leading first field => header; else a headerless decor line.
            if line:match("^%a") then
                local nm = line:match("^name=(.*)$")
                if nm then name = urldecode(nm) end
            else
                local e = parseDecorLine(line)
                if e then decor[#decor + 1] = e end
            end
        else
            if #decor >= MAX then break end
            local e = parseDecorLine(line)
            if e then decor[#decor + 1] = e end
        end
    end
    name = HDG.Codec.AsciiOnly(name)  -- strip emoji/unicode (Lua 5.1 / ASCII DBs)
    if name == "" then name = "Imported crate" end
    return { name = name, decor = decor }
end
