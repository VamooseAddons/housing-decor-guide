-- HDG.Expansion
-- ============================================================================
-- Single source of truth for expansion lookups + color decoration. Built over
-- HDG.Constants.EXPANSION_DATA, which is the authoritative ordered list
-- (Classic -> TBC -> ... -> Midnight). Every consumer that previously walked
-- EXPANSION_DATA with its own lazy cache (Selectors_Mogul, Controller_Mogul,
-- Selectors_Decor, Modules_Goblin, Selectors_Recipes, Selectors_Alts) calls
-- through here instead.
--
-- Caches are file-local + lazy: first lookup builds the map, subsequent
-- lookups are O(1). Constants is loaded before this file in the TOC so the
-- build is always safe at first call time.
--
-- API:
--   HDG.Expansion.Each()                      iterator over EXPANSION_DATA
--   HDG.Expansion.GetByDisplay(displayName)   entry table or nil
--   HDG.Expansion.GetByApi(apiName)           entry table or nil
--   HDG.Expansion.GetIndex(name)              1-based canonical sort index
--   HDG.Expansion.GetColor(name)              {r,g,b}    (text / vertex tint)
--   HDG.Expansion.GetColorHex(name)           "|cFFRRGGBB"  (inline color)
--   HDG.Expansion.GetBgTint(name, alpha)      {r,g,b,a}  (row backdrop tint)
--   HDG.Expansion.GetFull(name)               canonical display name (full
--                                              form, e.g. "Mists of Pandaria")
--   HDG.Expansion.GetShort(name)              3-char fixed-width form,
--                                              e.g. "MOP" / "TWW"
--   HDG.Expansion.NormalizeAlias(rawName)     canonical display or nil --
--                                              accepts display/api/short/alias
--                                              forms (localized strings too).
-- Every GetX accepts ANY of those name forms; the helper normalizes via
-- the alias map before resolving. The mixed-case `abbr` field (MoP/TWW)
-- is intentionally not exposed -- consumers should use GetShort (MOP/TWW)
-- for fixed-width column rendering, or GetFull for the full display.

HDG = HDG or {}
HDG.Expansion = HDG.Expansion or {}
local E = HDG.Expansion

-- ===== Lazy index builders ==================================================

local _byDisplay   -- [display]  = entry
local _byApi       -- [apiName]  = entry
local _byAlias     -- [aliasStr] = entry  -- combines display/api/abbr/short/aliases/apiTags
local _indexByDisplay  -- [display] = 1-based canonical order
local _colorHex    -- [display]  = "|cFFRRGGBB"

local function ensureIndexes()
    if _byDisplay then return end
    _byDisplay      = {}
    _byApi          = {}
    _byAlias        = {}
    _indexByDisplay = {}
    for i, e in ipairs(HDG.Constants.EXPANSION_DATA) do
        _byDisplay[e.display]      = e
        _byApi[e.api]              = e
        _indexByDisplay[e.display] = i
        -- Alias map: cover every form a caller might pass.
        _byAlias[e.display] = e
        _byAlias[e.api]     = e
        if e.abbr  then _byAlias[e.abbr]  = e end
        if e.short then _byAlias[e.short] = e end
        if e.aliases then
            for _, a in ipairs(e.aliases) do _byAlias[a] = e end
        end
        if e.apiTags then
            for _, t in ipairs(e.apiTags) do _byAlias[t] = e end
        end
    end
end

-- Hex color cache. "|cFFRRGGBB" format; callers concat text and append "|r".
local function buildColorHex()
    if _colorHex then return end
    ensureIndexes()
    _colorHex = {}
    for _, e in ipairs(HDG.Constants.EXPANSION_DATA) do
        local c = e.color
        _colorHex[e.display] = string.format("|cFF%02x%02x%02x",
            math.floor((c[1] or 1) * 255 + 0.5),
            math.floor((c[2] or 1) * 255 + 0.5),
            math.floor((c[3] or 1) * 255 + 0.5))
    end
end

-- ===== Public API ===========================================================

-- Iterator. for i, entry in HDG.Expansion.Each() do ... end
function E.Each()
    return ipairs(HDG.Constants.EXPANSION_DATA)
end

function E.GetByDisplay(displayName)
    if not displayName then return nil end
    ensureIndexes()
    return _byDisplay[displayName]
end

function E.GetByApi(apiName)
    if not apiName then return nil end
    ensureIndexes()
    return _byApi[apiName]
end

-- Resolve any alias form (display/api/short/abbr/localized/apiTag) to its EXPANSION_DATA entry.
local function resolveEntry(name)
    if not name then return nil end
    ensureIndexes()
    return _byAlias[name]
end

function E.GetIndex(name)
    local entry = resolveEntry(name)
    return entry and _indexByDisplay[entry.display] or nil
end

function E.GetColor(name)
    local entry = resolveEntry(name)
    return entry and entry.color or nil
end

function E.GetColorHex(name)
    local entry = resolveEntry(name)
    if not entry then return nil end
    buildColorHex()
    return _colorHex[entry.display]
end

-- Row backdrop tint {r,g,b,a}. Returns nil for unknown expansion (callers fall back to scheme tint).
function E.GetBgTint(name, alpha)
    local c = E.GetColor(name)
    if not c then return nil end
    return { r = c[1] or 1, g = c[2] or 1, b = c[3] or 1, a = alpha or 0.18 }  -- exception(boundary): palette factory optional alpha arg
end

-- Full canonical display name. Accepts any alias form. Mirrors NormalizeAlias semantically.
function E.GetFull(name)
    local entry = resolveEntry(name)
    return entry and entry.display or nil
end

-- 3-character fixed-width form (e.g. "MOP" / "TWW") for column UIs.
function E.GetShort(name)
    local entry = resolveEntry(name)
    return entry and entry.short or nil
end

-- NormalizeAlias: explicit alternate spelling of GetFull. Accept any name
-- form and return the canonical display name (or nil for unknown).
function E.NormalizeAlias(rawName) return E.GetFull(rawName) end
