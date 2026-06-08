-- HDG.Parsers
-- ============================================================================
-- Format dispatch for both INPUT (Parse) and OUTPUT (Format) sides of the
-- Import / Export flows. Naming convention: the registries handle pluggable
-- per-format codecs; HDG.StyleSerializer remains the heavy-lift blob
-- primitives layer (Base64, HDG:1: / HDGVL:1: protocol structure).
--
-- Each parser inspects raw pasted text and either:
--   - returns nil  (this parser doesn't recognize the input; try the next)
--   - returns { ok = true, items = {...}, displayName? = string,
--               source? = string, parserName = string }
--   - returns { ok = false, error = "<reason>" }   (definitively rejected)
--
-- The registry tries parsers in declared order; the first non-nil result
-- wins. The fallback "digits" parser matches anything containing digits,
-- so it always sits LAST.
--
-- Adding a new parser:
--   table.insert(HDG.Parsers._parsers, N, {
--       name = "myparser",
--       parse = function(text) ... end,
--   })
-- where N is its priority (lower = earlier).
--
-- Export side (incoming as more formats land):
--   HDG.Parsers._formatters[name] = function(payload) -> string
--   HDG.Parsers:Format(name, payload) -> string | nil, err
-- Today there are no formatters registered; the export-side dispatch
-- shell is reserved so the addition is mechanical.
--
-- Result fields:
--   items       array of itemIDs (or decorIDs for snapshot blobs)
--   displayName optional pretty name; controller / reducer uses for the
--               imported collection's displayName when committed
--   source      optional source descriptor (URL / "snapshot" / "smartset")

HDG = HDG or {}
HDG.Parsers = HDG.Parsers or {}
local Parsers = HDG.Parsers

Parsers._parsers    = Parsers._parsers    or {}
Parsers._formatters = Parsers._formatters or {}

-- ===== Helpers ============================================================

local function _dedupe(items)
    local seen, out = {}, {}
    for _, id in ipairs(items or {}) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

-- ===== Parser 1: HDG:1:<base64> style blob ================================
-- Recognized but not importable as a shopping list (rule-based, not item-based).
-- Surfaces a clear error pointing to the Smart Set Builder.
table.insert(Parsers._parsers, {
    name = "styleBlob",
    parse = function(text)
        if not (text and text:match("^HDG:1:")) then return nil end
        if not (HDG.StyleSerializer and HDG.StyleSerializer.Import) then  -- exception(boundary): optional module / not yet built
            return { ok = false, error = "Style importer unavailable" }
        end
        local def, err = HDG.StyleSerializer:Import(text)
        if not def then
            return { ok = false, error = err or "Style blob decode failed" }
        end
        -- Rule-based, not item-based: importing as a shopping list doesn't make sense.
        return { ok = false,
                 error = "This is a style blob -- import via Smart Set Builder",
                 styleDef = def }
    end,
})

-- ===== Parser 2: HDGVL:1:<base64> shopping list / snapshot blob ===========
-- These are item-bearing blobs and CAN be imported as a shopping list.
table.insert(Parsers._parsers, {
    name = "shoppingListBlob",
    parse = function(text)
        if not (text and text:match("^HDGVL:1:")) then return nil end
        if not (HDG.StyleSerializer and HDG.StyleSerializer.ImportShoppingList) then  -- exception(boundary): optional module / not yet built
            return { ok = false, error = "Shopping list importer unavailable" }
        end
        local result, err = HDG.StyleSerializer:ImportShoppingList(text)
        if not result then
            return { ok = false, error = err or "Shopping list decode failed" }
        end
        -- result is a snapshot or { items = { [id] = { placed, stored } } }; flatten to array.
        local itemIDs = {}
        if type(result.items) == "table" then
            for itemID in pairs(result.items) do itemIDs[#itemIDs + 1] = itemID end
        end
        return {
            ok          = true,
            items       = _dedupe(itemIDs),
            displayName = result.displayName or result.name,
            source      = (result.source == "snapshot") and "snapshot blob" or "shopping list blob",
            parserName  = "shoppingListBlob",
        }
    end,
})

-- ===== Parser 3: Blizzard item chat-link extraction =======================
-- |Hitem:NNNNN:... from shift-clicked items; itemID is first arg after "item:".
table.insert(Parsers._parsers, {
    name = "itemLinks",
    parse = function(text)
        if not text or not text:find("|Hitem:") then return nil end
        local items = {}
        for idStr in text:gmatch("|Hitem:(%d+)") do
            local n = tonumber(idStr)
            if n and n > 0 then items[#items + 1] = n end
        end
        if #items == 0 then return nil end
        return {
            ok         = true,
            items      = _dedupe(items),
            source     = "chat item links",
            parserName = "itemLinks",
        }
    end,
})

-- ===== Parser 4: URL items query param ====================================
-- ?items=NNN,NNN or ?item=NNN. Digits extracted; ignores other URL parts.
table.insert(Parsers._parsers, {
    name = "urlItemsParam",
    parse = function(text)
        if not text then return nil end
        local block = text:match("[%?&]items=([%d,]+)")
                   or text:match("[%?&]item=([%d,]+)")
        if not block then return nil end
        local items = {}
        for idStr in block:gmatch("%d+") do
            local n = tonumber(idStr)
            if n and n > 0 then items[#items + 1] = n end
        end
        if #items == 0 then return nil end
        local source = "url query"
        if text:find("wowhead.com", 1, true) then
            source = "wowhead"
        elseif text:find("housing.wowdb.com", 1, true) then
            source = "housing.wowdb.com"
        end
        return {
            ok         = true,
            items      = _dedupe(items),
            source     = source,
            parserName = "urlItemsParam",
        }
    end,
})

-- ===== Parser 5 (fallback): plain digit run ==============================
-- Accepts any digit run. Bottom of registry; domain-specific parsers always win.
table.insert(Parsers._parsers, {
    name = "digits",
    parse = function(text)
        if not text or text == "" then
            return { ok = false, error = "No item IDs found" }
        end
        local items = {}
        for digits in text:gmatch("%d+") do
            local n = tonumber(digits)
            if n and n > 0 then items[#items + 1] = n end
        end
        if #items == 0 then
            return { ok = false, error = "No item IDs found" }
        end
        return {
            ok         = true,
            items      = _dedupe(items),
            source     = "manual paste",
            parserName = "digits",
        }
    end,
})

-- ===== Public API =========================================================

-- Parse: first parser that recognizes the input wins. Returns result or { ok=false, error }.
function Parsers:Parse(text)
    text = text or ""
    for _, entry in ipairs(self._parsers) do
        local result = entry.parse(text)
        if result ~= nil then return result end
    end
    return { ok = false, error = "No parser matched" }
end

-- Format: emit a string via the named formatter. Reserved for export-side parity.
function Parsers:Format(name, payload)
    local fn = self._formatters[name]
    if not fn then return nil, "No formatter registered for " .. tostring(name) end
    return fn(payload)
end

-- Register a formatter from outside the module.
function Parsers:RegisterFormatter(name, fn)
    self._formatters[name] = fn
end
