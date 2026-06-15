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

-- ===== Shared codec primitives =============================================
-- Base64 + URL + ASCII helpers are the ONE copy in HDG.Codec (Core/HDGR_Codec.lua,
-- loaded first in the TOC), shared with ProjectsCrateCodec. These were previously
-- duplicated here verbatim from the HDG donor port -- folded back into HDG.Codec.
local b64encode, b64decode = HDG.Codec.b64encode, HDG.Codec.b64decode
local urlencode, urldecode = HDG.Codec.urlencode, HDG.Codec.urldecode
local asciiOnly            = HDG.Codec.AsciiOnly

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
    local droppedCount = 0   -- entries the live catalog couldn't match (surfaced in the import status)
    if obs:IsReady() then
        local resolved, dropped = {}, {}
        for _, e in ipairs(items) do
            local mapped = obs:GetItemIDByDecorID(e.itemID)
            if mapped then
                e.itemID = mapped
                resolved[#resolved + 1] = e
            elseif obs:GetRow(e.itemID) then
                resolved[#resolved + 1] = e
            else
                dropped[#dropped + 1] = e.itemID   -- neither a known decorID nor itemID
            end
        end
        droppedCount = #dropped
        -- Diagnostic (Debug tab only): which IDs the live catalog couldn't match.
        -- Lets us tell wowhead ID-mismatch / removed decor apart from real gaps.
        if #dropped > 0 then
            HDG.Log:Warn("import", ("ShoppingCodec: %d of %d entries matched the catalog; unmatched IDs: %s")
                :format(#resolved, #items, table.concat(dropped, ", ")))
        end
        items = resolved
    end

    -- meta.desc carries the list name; strip emoji/unicode (Lua 5.1 / ASCII DBs).
    local name = asciiOnly(meta.desc or "")
    if name == "" then name = "Imported list" end

    local createdAt = tonumber(meta.date) or time()  -- meta.date > now

    return {
        name         = name,
        items        = items,
        meta         = meta,
        createdAt    = createdAt,
        droppedCount = droppedCount,   -- entries not in the live catalog (e.g. unreleased)
    }
end
