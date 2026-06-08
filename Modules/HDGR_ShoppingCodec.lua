-- HDG.ShoppingCodec -- export / import codec for vendor shopping lists.
--
-- Format: "HDGVL:1:<base64>" -- INTEROP with HDG (donor). HDG users can
-- export from HDG and import into HDG (and vice-versa); our SHOPPING_LIST_
-- IMPORT reducer accepts either side's encoded blob.
--
-- Decoded payload is newline-separated:
--   Line 1: header  -- comma-separated key=value pairs (source, url, desc,
--                       date, author, idtype). desc is URL-encoded so it can
--                       carry commas / equals safely.
--   Lines 2..N: itemID,npcID,qty  -- npcID=0 means wishlist (no vendor).
--
-- Two functions:
--   Encode(listRecord) -> "HDGVL:1:..."   pure encoder
--   Decode(encoded)    -> listRecord | nil
--     -- returns nil on: empty / wrong magic / unparseable payload. Caller
--     -- (SHOPPING_LIST_IMPORT reducer) checks the return for nil and
--     -- silently no-ops bad payloads. NEVER errors -- untrusted input
--     -- exception(boundary): by design.
--
-- Decoded record shape matches Store's vendorShoppingLists[id] shape so the
-- reducer can drop it straight in:
--   { name, items = {{itemID, npcID, qty}, ...}, meta = {...}, createdAt }

HDG = HDG or {}
HDG.ShoppingCodec = HDG.ShoppingCodec or {}
local C = HDG.ShoppingCodec

local MAGIC_PREFIX = "HDGVL"
local FORMAT_VERSION = "1"
local MAX_IMPORT_ENTRIES = 500   -- HDG cap; protects against pathological imports

-- ===== Base64 codec ========================================================
-- Pure Lua 5.1 (no bit library) so it runs in WoW + headless tests.
-- Standard alphabet with "=" padding; interop-safe with HDG.
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return b64chars:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function b64decode(data)
    data = string.gsub(data, '[^' .. b64chars .. '=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r, f = '', (b64chars:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

-- ===== URL encode / decode (for meta.desc which may contain "," or "=") ====
local function urlencode(str)
    if type(str) ~= "string" then return "" end
    return (str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function urldecode(str)
    if type(str) ~= "string" then return "" end
    return (str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- ===== Encode ===============================================================
function C.Encode(listRecord)
    if type(listRecord) ~= "table" then return nil end
    local meta  = type(listRecord.meta) == "table" and listRecord.meta or {}
    local items = type(listRecord.items) == "table" and listRecord.items or {}

    local lines = {}
    local headerParts = {}
    -- source defaults to "player" when this is a locally-authored list.
    local source = type(meta.source) == "string" and meta.source or "player"
    headerParts[#headerParts + 1] = "source=" .. source
    if type(meta.url) == "string" and meta.url ~= "" then
        headerParts[#headerParts + 1] = "url=" .. meta.url
    end
    -- desc carries the human-readable list name. URL-encode so commas / equals
    -- in the name don't corrupt the header.
    local desc = (type(meta.desc) == "string" and meta.desc) or listRecord.name
    if type(desc) == "string" and desc ~= "" then
        headerParts[#headerParts + 1] = "desc=" .. urlencode(desc)
    end
    local date = (type(meta.date) == "string" or type(meta.date) == "number")
        and meta.date or listRecord.createdAt
    if date then headerParts[#headerParts + 1] = "date=" .. tostring(date) end
    if type(meta.author) == "string" and meta.author ~= "" then
        headerParts[#headerParts + 1] = "author=" .. meta.author
    end
    lines[#lines + 1] = table.concat(headerParts, ",")

    -- Item lines. npcID=0 sentinel = wishlist (HDG convention).
    for _, entry in ipairs(items) do
        if type(entry) == "table" and type(entry.itemID) == "number" then
            local npc = (type(entry.npcID) == "number" and entry.npcID) or 0
            local qty = (type(entry.qty)   == "number" and entry.qty)   or 1
            lines[#lines + 1] = entry.itemID .. "," .. npc .. "," .. qty
        end
    end

    return MAGIC_PREFIX .. ":" .. FORMAT_VERSION .. ":" .. b64encode(table.concat(lines, "\n"))
end

-- ===== Decode ===============================================================
local function parseHeader(line)
    local meta = {}
    -- The header is recognisable when its first field starts with a letter
    -- (key=value vs item lines which start with a digit). Caller pre-checks.
    for kv in line:gmatch("[^,]+") do
        local k, v = kv:match("^(%w+)=(.*)$")
        if k and v then meta[k] = v end
    end
    if meta.desc then meta.desc = urldecode(meta.desc) end
    return meta
end

local function parseItemLine(line)
    local id, npc, qty = line:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
    id  = tonumber(id)
    npc = tonumber(npc)
    qty = tonumber(qty) or 1   -- exception(boundary): codec parse
    if not id then return nil end
    return {
        itemID = id,
        npcID  = (npc and npc ~= 0) and npc or nil,
        qty    = qty,
    }
end

function C.Decode(encoded)
    if type(encoded) ~= "string" or #encoded == 0 then return nil end
    -- Accept HDGVL:1:... only. Format version gates future migrations.
    local prefix, ver, payload = encoded:match("^(HDGVL):(%d+):(.+)$")
    if prefix ~= MAGIC_PREFIX or ver ~= FORMAT_VERSION then return nil end

    local decoded = b64decode(payload)
    if not decoded or #decoded == 0 then return nil end

    local items = {}
    local meta  = {}
    local first = true
    for line in decoded:gmatch("[^\n]+") do
        if first then
            first = false
            -- First field begins with a letter => header; otherwise treat as
            -- an item line (legacy / headerless HDG exports).
            local firstField = line:match("^([^,]+)")
            if firstField and firstField:match("^%a") then
                meta = parseHeader(line)
            else
                local entry = parseItemLine(line)
                if entry then items[#items + 1] = entry end
            end
        else
            if #items >= MAX_IMPORT_ENTRIES then break end
            local entry = parseItemLine(line)
            if entry then items[#items + 1] = entry end
        end
    end

    -- Classify each imported ID via HousingCatalogObserver (exact, not magnitude
    -- heuristic). Wowhead exports use decorID; HDG exports use decor itemID; mixed ok.
    --   GetItemIDByDecorID -> decorID; swap to itemID.
    --   GetRow             -> already a decor itemID; keep.
    --   else               -> non-decor (reagent/junk from 3rd-party); drop.
    -- Cold import (catalog not swept): keep as-is; selector drops non-decor on sweep.
    local obs = HDG.HousingCatalogObserver
    if obs:IsReady() then
        local resolved = {}
        for _, e in ipairs(items) do
            local mapped = obs:GetItemIDByDecorID(e.itemID)
            if mapped then
                e.itemID = mapped
                resolved[#resolved + 1] = e
            elseif obs:GetRow(e.itemID) then
                resolved[#resolved + 1] = e
            end
        end
        items = resolved
    end

    local name = meta.desc  -- meta.desc > "Imported list"
    if type(name) ~= "string" or name == "" then name = "Imported list" end

    local createdAt = tonumber(meta.date) or time()  -- meta.date > now

    return {
        name      = name,
        items     = items,
        meta      = meta,
        createdAt = createdAt,
    }
end
