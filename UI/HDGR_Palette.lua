-- HDG.Palette
-- ============================================================================
-- Scheme-INVARIANT color source. Sits parallel to HDG.Theme:
--
--   HDG.Theme    -> scheme-driven colors (Solarized, Gruvbox, ...).
--                    Tokens repaint on `/hdgr theme <name>`.
--   HDG.Palette  -> game-brand colors (expansion, faction). Tokens are
--                    FIXED across schemes -- Midnight is purple whether
--                    you're on Solarized Dark or Light.
--
-- Same call surface as Theme (`:GetColor` / `:ColorCode`) so call sites
-- don't have to learn two APIs for the same "give me a color string"
-- intent. Zero overlap between Theme and Palette namespaces -- you'd
-- never see `text.dim` in Palette or `expansion.Midnight` in Theme.
--
-- Token namespaces (parsed as `<namespace>.<key>`):
--   expansion.<display name>  -- e.g. "Midnight", "The War Within"
--                                resolves via Constants.EXPANSION_DATA
--   faction.<name>            -- empty until faction-tint design lands
--                                ("Alliance" / "Horde" reserved)
--
-- See HDGR_ARCHITECTURE.md ADR-023 for the parallel-source rationale.

HDG = HDG or {}
HDG.Palette = HDG.Palette or {}

-- Palette's owned token namespaces. Used by Theme + Palette to enforce
-- the disjoint-namespace contract from ADR-023 at runtime: a call to
-- Theme:ColorCode("expansion.X") errors loud and points the caller to
-- Palette, and vice versa.
HDG.Palette.OWNED_NAMESPACES = {
    expansion = true,
    faction   = true,
    source    = true,
}

local function _checkPaletteNamespace(token)
    local ns = token:match("^([^.]+)")
    if not ns then
        error(("Palette:ColorCode: malformed token %q (expected <namespace>.<key>)"):format(tostring(token)), 3)
    end
    if not HDG.Palette.OWNED_NAMESPACES[ns] then
        local hint = ""
        if HDG.Theme and HDG.Theme.OWNED_COLOR_NAMESPACES   -- exception(boundary): cross-module load-order
           and HDG.Theme.OWNED_COLOR_NAMESPACES[ns] then
            hint = " -- use HDG.Theme:ColorCode instead"
        end
        error(("Palette:ColorCode: namespace %q not owned by Palette (ADR-023)%s"):format(ns, hint), 3)
    end
end

-- Build expansion-name -> {r,g,b} index from Constants.EXPANSION_DATA.
-- EXPANSION_DATA stores colors as array {r, g, b}; we convert to the
-- keyed table shape so callers can use `.r / .g / .b` like Theme does.
-- Built lazily on first access (Constants.lua loads before this file,
-- but tests may stub the order).
local _expansionCache = nil
local function _buildExpansionCache()
    -- HDG.Constants is a load-order-guaranteed engine singleton -- strict
    -- read; if it's missing that's a TOC bug to surface, not paper over.
    local data = HDG.Constants.EXPANSION_DATA
    local out = {}
    for _, e in ipairs(data) do
        local c = e.color
        if e.display and c then
            out[e.display] = { r = c[1], g = c[2], b = c[3] }
        end
    end
    return out
end

local function _getExpansionColor(displayName)
    if not _expansionCache then _expansionCache = _buildExpansionCache() end
    return _expansionCache[displayName]
end

-- Source-type brand colors. Indexed by either the integer sourceType
-- (e.g. `source.5` -> Vendor green) OR the name (`source.VENDOR`).
-- Built lazily from Constants.SOURCE_TYPE_COLOR.
local _sourceCache = nil
local function _buildSourceCache()
    local data = HDG.Constants.SOURCE_TYPE_COLOR or {}
    local out = {}
    for id, e in pairs(data) do
        local c = e.color
        if c then
            local entry = { r = c[1], g = c[2], b = c[3] }
            out[tostring(id)] = entry
            if e.name then out[e.name] = entry end
        end
    end
    return out
end

local function _getSourceColor(key)
    if not _sourceCache then _sourceCache = _buildSourceCache() end
    return _sourceCache[key]
end

-- Faction brand colors -- scheme-invariant. Keyed by UnitFactionGroup's return
-- ("Alliance"/"Horde") + "Neutral". Single brand source for all consumers.
local FACTION_COLORS = {
    Alliance = { r = 0.20, g = 0.50, b = 0.95 },
    Horde    = { r = 0.85, g = 0.20, b = 0.20 },
    Neutral  = { r = 0.55, g = 0.55, b = 0.55 },
}

-- ============================================================================
-- Public API: GetColor + ColorCode (mirrors Theme's surface)
-- ============================================================================

function HDG.Palette:GetColor(token)
    local ns, key = token:match("^([^.]+)%.(.+)$")
    if not ns then return nil end
    if ns == "expansion" then
        return _getExpansionColor(key)
    elseif ns == "faction" then
        return FACTION_COLORS[key]
    elseif ns == "source" then
        return _getSourceColor(key)
    end
    return nil
end

-- ColorCode mirrors Theme:ColorCode. Loud-fail on unknown token so a
-- typo like "expansion.Midnigh" surfaces immediately instead of
-- crashing later on a nil index (same lesson as Theme:ColorCode).
function HDG.Palette:ColorCode(token)
    _checkPaletteNamespace(token)
    local c = self:GetColor(token)
    if not c then
        error(("Palette:ColorCode: token %q does not resolve"):format(tostring(token)), 2)
    end
    return string.format("|cFF%02X%02X%02X",
        math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5))
end

-- Test seam: lets the smoke tests reset the cache between cases. No
-- production caller needs this; safe to leave on the namespace.
function HDG.Palette:_ResetCache()
    _expansionCache = nil
    _sourceCache    = nil
end
