-- HDGR_StyleSerializer.lua
-- Import/Export custom styles as encoded strings. Format: HDG:1:<base64_payload>

HDG = HDG or {}

local StyleSerializer = {}
HDG.StyleSerializer = StyleSerializer

-- Matches HDG's STYLE_EDITOR.NAME_MAX_LENGTH (40).
local NAME_MAX_LENGTH = 40

-- ============================================================================
-- BASE64 ENCODE/DECODE
-- ============================================================================

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64enc = {}
local b64dec = {}
for i = 1, 64 do
    local c = b64chars:sub(i, i)
    b64enc[i - 1] = c
    b64dec[c:byte()] = i - 1
end

local function Base64Encode(data)
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local a = data:byte(i)
        local b = i + 1 <= len and data:byte(i + 1) or 0
        local c = i + 2 <= len and data:byte(i + 2) or 0
        out[#out + 1] = b64enc[bit.rshift(a, 2)]
        out[#out + 1] = b64enc[bit.bor(bit.lshift(bit.band(a, 3), 4), bit.rshift(b, 4))]
        out[#out + 1] = (i + 1 <= len) and b64enc[bit.bor(bit.lshift(bit.band(b, 15), 2), bit.rshift(c, 6))] or "="
        out[#out + 1] = (i + 2 <= len) and b64enc[bit.band(c, 63)] or "="
    end
    return table.concat(out)
end

local function Base64Decode(data)
    local out = {}
    data = data:gsub("[^A-Za-z0-9+/=]", "")
    for i = 1, #data, 4 do
        -- b64dec is the base64 alphabet lookup; non-alphabet input has
        -- already been stripped above. The `or 0` here handles the
        -- trailing '=' padding bytes (b64dec[byte("=")] is nil by design).
        local a = b64dec[data:byte(i)] or 0      -- exception(boundary): padding/end
        local b = b64dec[data:byte(i + 1)] or 0  -- exception(boundary): base64 decode of user-pasted import string
        local c = b64dec[data:byte(i + 2)] or 0  -- exception(boundary): base64 decode of user-pasted import string
        local d = b64dec[data:byte(i + 3)] or 0  -- exception(boundary): base64 decode of user-pasted import string
        out[#out + 1] = string.char(bit.bor(bit.lshift(a, 2), bit.rshift(b, 4)))
        if data:sub(i + 2, i + 2) ~= "=" then
            out[#out + 1] = string.char(bit.band(bit.bor(bit.lshift(b, 4), bit.rshift(c, 2)), 0xFF))
        end
        if data:sub(i + 3, i + 3) ~= "=" then
            out[#out + 1] = string.char(bit.band(bit.bor(bit.lshift(c, 6), d), 0xFF))
        end
    end
    return table.concat(out)
end

-- ============================================================================
-- ENCODE / DECODE FACET MAPS
-- ============================================================================

-- Encode a facet map { room = {"kitchen","garden"}, mood = {"cozy"} }
-- into "room=kitchen,garden;mood=cozy"
local function EncodeFacetMap(facetMap)
    if not facetMap or not next(facetMap) then return "" end
    local parts = {}
    local keys = {}
    for k in pairs(facetMap) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local vals = facetMap[k]
        if type(vals) == "table" and #vals > 0 then
            parts[#parts + 1] = k .. "=" .. table.concat(vals, ",")
        end
    end
    return table.concat(parts, ";")
end

-- Decode "room=kitchen,garden;mood=cozy" into { room = {"kitchen","garden"}, mood = {"cozy"} }
local function DecodeFacetMap(str)
    if not str or str == "" then return {} end
    local result = {}
    for part in str:gmatch("[^;]+") do
        local facet, valStr = part:match("^([^=]+)=(.+)$")
        if facet and valStr then
            local vals = {}
            for v in valStr:gmatch("[^,]+") do
                vals[#vals + 1] = v
            end
            if #vals > 0 then
                result[facet] = vals
            end
        end
    end
    return result
end

-- ============================================================================
-- EXPORT
-- ============================================================================

function StyleSerializer:Export(styleDef)
    if not styleDef then return nil, "No style definition" end

    -- Pipe-delimited payload (pipes are safe since they get base64-encoded)
    -- Field 2 (iconIdx) and field 3 (colorStr) kept as placeholders for compat
    local payload = table.concat({
        styleDef.displayName or "Unnamed",
        "0",
        "0.5,0.5,0.5",
        styleDef.description or "",
        EncodeFacetMap(styleDef.query),
        EncodeFacetMap(styleDef.boost),
        EncodeFacetMap(styleDef.anti),
    }, "|")

    return "HDG:1:" .. Base64Encode(payload)
end

-- ============================================================================
-- IMPORT
-- ============================================================================

-- Filter a decoded facet map against HDGR_FacetVocab, silently dropping
-- unknown keys + values. Caller guards on HDGR_FacetVocab being present.
local function _filterValidFacets(facetMap)
    local filtered = {}
    for facetKey, vals in pairs(facetMap) do
        local vocabTable = HDGR_FacetVocab[facetKey]
        if vocabTable then
            -- Build reverse lookup: string value -> true
            local validVals = {}
            for _, v in pairs(vocabTable) do
                validVals[v] = true
            end
            local goodVals = {}
            for _, v in ipairs(vals) do
                if validVals[v] then goodVals[#goodVals + 1] = v end
            end
            if #goodVals > 0 then
                filtered[facetKey] = goodVals
            end
        end
    end
    return filtered
end

-- Return `name` or `name (N)` (lowest N>=2) without colliding with an existing
-- collection displayName (Collections is the SSoT for uniqueness).
local function _dedupeName(name)
    local collections = HDG.Store:GetState().account.collections or {}
    local baseName, suffix = name, 2
    while true do
        local dupe = false
        for _, def in pairs(collections) do
            if def.displayName == name then dupe = true; break end
        end
        if not dupe then break end
        name = baseName .. " (" .. suffix .. ")"
        suffix = suffix + 1
    end
    return name
end

function StyleSerializer:Import(encodedStr)
    if not encodedStr or encodedStr == "" then
        return nil, "Empty string"
    end

    -- Route by version prefix
    if encodedStr:match("^HDGVL:1:") then
        return self:ImportShoppingList(encodedStr)
    end

    -- Check prefix
    if not encodedStr:match("^HDG:1:") then
        return nil, "Invalid format (expected HDG:1: or HDGVL:1:...)"
    end

    local b64 = encodedStr:sub(7)
    -- Base64Decode is internal + pre-sanitizes input -- can't throw. No pcall.
    local payload = Base64Decode(b64)
    if not payload or payload == "" then
        return nil, "Failed to decode"
    end

    -- Split by pipe
    local fields = {}
    for field in (payload .. "|"):gmatch("([^|]*)|") do
        fields[#fields + 1] = field
    end

    if #fields < 5 then
        return nil, "Not enough fields (got " .. #fields .. ")"
    end

    local name = fields[1]
    -- fields[2] (iconIdx) + fields[3] (colorStr) are legacy placeholders
    local desc = fields[4] or ""
    local queryStr = fields[5] or ""
    local boostStr = fields[6] or ""
    local antiStr = fields[7] or ""

    -- Validate name
    if not name or name == "" then
        return nil, "Name is empty"
    end
    local maxLen = NAME_MAX_LENGTH
    if #name > maxLen then
        name = name:sub(1, maxLen)
    end

    -- Icon/color fields are legacy placeholders; use defaults
    local icon = "Interface\\Icons\\INV_Misc_Book_09"

    -- Decode facet maps
    local query = DecodeFacetMap(queryStr)
    local boost = DecodeFacetMap(boostStr)
    local anti = DecodeFacetMap(antiStr)

    -- Validate facets against vocab (silently drop unknown).
    if HDGR_FacetVocab then
        query = _filterValidFacets(query)
        boost = _filterValidFacets(boost)
        anti  = _filterValidFacets(anti)
    end

    -- Must have at least one query or boost tag
    if not next(query) and not next(boost) then
        return nil, "No valid tags (need at least one query or boost)"
    end

    -- Dedup against state.account.collections (SSoT; global uniqueness).
    name = _dedupeName(name)

    local styleDef = {
        displayName = name,
        icon = icon,
        tier = "custom",
        color = { r = 0.5, g = 0.5, b = 0.5 },
        description = desc,
        query = next(query) and query or nil,
        boost = next(boost) and boost or nil,
        anti = next(anti) and anti or nil,
    }

    return styleDef
end

-- ============================================================================
-- DECOR ID RESOLUTION (decorID <-> itemID)
-- ============================================================================

local DECOR_ID_THRESHOLD = 100000  -- decorIDs < 100k, itemIDs > 235k

local function ResolveDecorIDs(dataLines, meta)
    -- Determine if IDs are decorIDs: explicit header flag or auto-detect
    local isDecor = meta and meta.idtype == "decor"
    if not isDecor and #dataLines > 0 then
        local firstID = tonumber(dataLines[1]:match("^(%d+)"))
        if firstID and firstID < DECOR_ID_THRESHOLD then isDecor = true end
    end
    if not isDecor then return dataLines end

    -- GetDecorToItem() is the public accessor (avoids private-field access into StyleEngine).
    local d2i = HDG.StyleEngine:GetDecorToItem()
    if not d2i then return dataLines end

    local resolved = {}
    for i, line in ipairs(dataLines) do
        local decorID, rest = line:match("^(%d+)(,.+)$")
        if decorID then
            local itemID = d2i[tonumber(decorID)]
            resolved[i] = itemID and (itemID .. rest) or line
        else
            resolved[i] = line
        end
    end
    return resolved
end

-- ============================================================================
-- SNAPSHOT EXPORT (HDGVL:1: source=snapshot)
-- ============================================================================

-- URL-encode a string for header values
local function UrlEncode(str)
    if not str then return "" end
    return str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", c:byte())
    end)
end

function StyleSerializer:ExportSnapshot(def, useDecorID)
    if not def or not def.snapshot then return nil, "Not a snapshot" end
    local snap = def.snapshot
    local name = def.displayName or "Snapshot"

    -- Author name from session.identity (SSoT; populated once at onEnable).
    local _authorName = HDG.Store:GetState().session.identity.name
    if _authorName == "" then _authorName = "Unknown" end
    local headerParts = {
        "source=snapshot",
        "author=" .. _authorName,
        "date=" .. (snap.capturedAt or 0),  -- exception(boundary): house snapshot {} until aggregator build
        "desc=" .. UrlEncode(name),
    }
    if useDecorID then
        headerParts[#headerParts + 1] = "idtype=decor"
    end

    -- id,placed,stored lines sorted by itemID. itemID -> decorID via
    -- GetDecorIDByItemIDMap(); empty before sweep -> itemID output.
    local i2d = useDecorID and HDG.HousingCatalogObserver:GetDecorIDByItemIDMap()
    local sortedIDs = {}
    for itemID in pairs(snap.items or {}) do
        sortedIDs[#sortedIDs + 1] = itemID
    end
    table.sort(sortedIDs)
    local lines = { table.concat(headerParts, ",") }
    for _, itemID in ipairs(sortedIDs) do
        local counts = snap.items[itemID]
        local outID = (i2d and i2d[itemID]) or itemID
        lines[#lines + 1] = outID .. "," .. (counts.placed or 0) .. "," .. (counts.stored or 0)  -- exception(boundary): sparse bag/count map
    end

    return "HDGVL:1:" .. Base64Encode(table.concat(lines, "\n"))
end

-- ============================================================================
-- SNAPSHOT IMPORT (HDGVL:1: source=snapshot)
-- ============================================================================

function StyleSerializer:ImportSnapshotFromVL(meta, dataLines)
    -- Parse itemID,placed,stored lines
    local items = {}
    for _, line in ipairs(dataLines) do
        local idStr, placedStr, storedStr = line:match("^(%d+),(%d+),(%d+)$")
        if idStr then
            local itemID = tonumber(idStr)
            local placed = tonumber(placedStr) or 0  -- exception(boundary): parse external string
            local stored = tonumber(storedStr) or 0  -- exception(boundary): parse external string
            if itemID and (placed > 0 or stored > 0) then
                items[itemID] = { placed = placed, stored = stored }
            end
        end
    end

    if not next(items) then
        return nil, "No valid items in snapshot"
    end

    local name = (meta.desc and meta.desc ~= "") and meta.desc or "Imported Snapshot"
    local maxLen = NAME_MAX_LENGTH
    if #name > maxLen then name = name:sub(1, maxLen) end

    name = _dedupeName(name)

    local totalPlaced = 0
    for _, counts in pairs(items) do
        totalPlaced = totalPlaced + (counts.placed or 0)  -- exception(boundary): sparse bag/count map
    end

    local styleDef = {
        displayName = name,
        iconAtlas = HDG.Constants.SNAPSHOT_ICON_ATLAS,
        tier = "snapshot",
        color = { r = 0.4, g = 0.7, b = 1.0 },
        description = totalPlaced .. " placed -- " .. (tonumber(meta.date) and date("%b %d, %Y", tonumber(meta.date)) or "unknown date"),
        snapshot = {
            capturedAt = tonumber(meta.date) or 0,  -- exception(boundary): parse external timestamp string
            items = items,
        },
        meta = meta,
    }

    return styleDef
end

-- ============================================================================
-- SHOPPING LIST IMPORT (HDGVL:1: format -> snapshot style)
-- ============================================================================

-- URL-decode a percent-encoded string
local function UrlDecode(str)
    if not str then return nil end
    return str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

-- Parse a header line of comma-separated k=v pairs into a meta table (the
-- `desc` value is URL-decoded).
local function _parseHeaderKV(line)
    local meta = {}
    for kv in line:gmatch("[^,]+") do
        local k, v = kv:match("^(%w+)=(.+)$")
        if k then meta[k] = v end
    end
    if meta.desc then meta.desc = UrlDecode(meta.desc) end
    return meta
end

-- Parse a decoded HDGVL payload into (meta, dataLines). First line is
-- the header when its first comma-field starts with a letter; otherwise
-- every line is a data line.
local function _parseVLHeaderAndData(payload)
    local meta, dataLines, firstLine = nil, {}, true
    for line in payload:gmatch("[^\n]+") do
        local isHeader = firstLine and ((line:match("^([^,]+)") or ""):match("^%a") ~= nil)
        firstLine = false
        if isHeader then
            meta = _parseHeaderKV(line)
        else
            dataLines[#dataLines + 1] = line
        end
    end
    return meta, dataLines
end

function StyleSerializer:ImportShoppingList(encodedStr)
    if not encodedStr or not encodedStr:match("^HDGVL:1:") then
        return nil, "Invalid format"
    end

    local b64 = encodedStr:sub(9) -- strip "HDGVL:1:" (9 chars)
    local payload = Base64Decode(b64)  -- pre-sanitizes; can't throw
    if not payload or payload == "" then
        return nil, "Failed to decode"
    end

    local meta, dataLines = _parseVLHeaderAndData(payload)

    -- Resolve decorIDs to itemIDs if needed
    dataLines = ResolveDecorIDs(dataLines, meta)

    -- Route snapshots to dedicated importer
    if meta and meta.source == "snapshot" then
        return self:ImportSnapshotFromVL(meta, dataLines)
    end

    local items = {}
    for _, line in ipairs(dataLines) do
        local itemID, _, qty = line:match("^(%d+),(%d+),(%d+)$")
        itemID = tonumber(itemID)
        qty = tonumber(qty) or 1  -- exception(boundary): parse external string
        if itemID then items[itemID] = { placed = (items[itemID] and items[itemID].placed or 0) + qty, stored = 0 } end
    end

    if not next(items) then
        return nil, "No valid items in shopping list"
    end

    local name = (meta and meta.desc and meta.desc ~= "") and meta.desc or "Imported Shopping List"
    local maxLen = NAME_MAX_LENGTH
    if #name > maxLen then name = name:sub(1, maxLen) end

    name = _dedupeName(name)

    local itemCount = 0
    for _ in pairs(items) do itemCount = itemCount + 1 end

    local isWowhead = meta and meta.source == "wowhead"

    local styleDef = {
        displayName = name,
        icon = isWowhead and "Interface\\AddOns\\HousingDecorGuide\\textures\\wowhead_logo" or "Interface\\Icons\\INV_Housing_Blueprint_Rugged",
        tier = "snapshot",
        color = { r = 0.4, g = 0.7, b = 1.0 },
        description = itemCount .. " items from " .. (meta and meta.author or meta and meta.source or "shopping list"),
        snapshot = {
            capturedAt = (meta and tonumber(meta.date)) or time(),
            items = items,
        },
        meta = meta,
    }

    return styleDef
end
