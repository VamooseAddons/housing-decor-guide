-- HDG.Format
-- ============================================================================
-- Presentation render-primitives. Pure functions; no data of its own.
-- Loads after Constants; consumed by the observer bake and by selectors.
-- FormatCurrency's C_CurrencyInfo fallback is a legitimate boundary call (observer bake, not selector).

HDG = HDG or {}
HDG.Format = HDG.Format or {}

local F = HDG.Format

-- Scheme-invariant brand prefix (shaman class blue, |cff0070dd). The universal
-- chat tag: every HDG chat line from any source opens with it. Single
-- definition -- Log.lua and Init.lua reference this so the token can never
-- drift between surfaces.
F.BRAND_PREFIX = "|cff0070dd[HDG]|r"

-- Import dates arrive as a unix timestamp (wowdb: 1777074521) or an already-
-- formatted string (wowhead: "2026-03-10"). Render both as YYYY-MM-DD; a string
-- date (has dashes -> tonumber nil) passes through unchanged. nil/empty -> nil.
function F.FriendlyDate(d)
    if d == nil or d == "" then return nil end
    local n = tonumber(d)
    if n and n > 1000000000 and _G.date then  -- exception(boundary): unix ts -> date(); date() absent in headless tests
        return _G.date("%Y-%m-%d", n)
    end
    return tostring(d)
end

-- Returns "" for zero/nil. FormatGoldZero is the zero-visible variant (column-aligned tables).
--   FormatAmount(n)              -> "1,234"  (commas, suppress zero)
--   FormatCurrency(amount, cid)  -> "1,234 <icon>"
--   FormatGold(copper)           -> FormatCurrency(gold, CURRENCY_GOLD)

function F.FormatAmount(n)
    if not n or n <= 0 then return "" end
    return _G.BreakUpLargeNumbers and _G.BreakUpLargeNumbers(n) or tostring(n)
end

local _trackedCurrencyIcon
function F.FormatCurrency(amount, currencyID, iconOverride)
    local n = F.FormatAmount(amount)
    if n == "" then return "" end
    if currencyID == HDG.Constants.CURRENCY_GOLD then
        return n .. " " .. HDG.Constants.COIN_ATLAS
    end
    -- Catalog icon wins (always correct). Curated table + live API are fallbacks for ItemAugment costs.
    local icon = iconOverride
    if not icon then
        if not _trackedCurrencyIcon then
            _trackedCurrencyIcon = {}
            for _, c in ipairs(HDG.Constants.HOUSING_DECOR_CURRENCY_DATA) do
                _trackedCurrencyIcon[c.id] = c.icon
            end
        end
        icon = _trackedCurrencyIcon[currencyID]
        if not icon and _G.C_CurrencyInfo and _G.C_CurrencyInfo.GetCurrencyInfo then
            local info = _G.C_CurrencyInfo.GetCurrencyInfo(currencyID)
            icon = info and info.iconFileID
        end
    end
    if icon then return n .. " |T" .. icon .. ":14:14|t" end
    -- Final fallback: bare number with the raw id so missing tracking is
    -- visible at the UI seam instead of silently rendering as "1234".
    return n .. " (#" .. tostring(currencyID) .. ")"
end

function F.FormatGold(copper)
    return F.FormatCurrency(
        math.floor((copper or 0) / 10000),
        HDG.Constants.CURRENCY_GOLD)
end

-- Like FormatGold but renders ZERO as "0 <coin>" for column-aligned tables (Mogul).
function F.FormatGoldZero(copper)
    if not copper or copper <= 0 then return "0 " .. HDG.Constants.COIN_ATLAS end
    return F.FormatGold(copper)
end

-- Relative-time label from a PRE-COMPUTED elapsed-seconds value (impure subtraction stays at call site).
-- Returns "just now" / "Nm ago" / "Nh ago" / "Nd ago".
function F.RelativeTime(elapsedSeconds)
    local d = elapsedSeconds or 0
    if d < 60    then return "just now" end
    if d < 3600  then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

-- "(|cAARRGGBB Name|r)" with class color from Constants (white fallback).
function F.ClassColorName(name, class)
    local hex = HDG.Constants.CLASS_COLORS[class] or "ffffffff"
    return "(|c" .. hex .. name .. "|r)"
end

-- Render {{currencyID, amount}, ...} cost as an inline icon line ("150 <icon>  +  1,500 <icon>").
function F.FormatVendorCost(cost)
    if not cost or #cost == 0 then return "" end
    local out = {}
    for _, c in ipairs(cost) do
        out[#out + 1] = F.FormatCurrency(c[2], c[1])  -- c = {currencyID, amount}
    end
    return table.concat(out, "  +  ")
end

-- Profession display name -> atlas (PROFESSION_DATA). Lazy reverse map. nil when unknown.
local _profAtlasByName
function F.ProfessionAtlas(name)
    if not _profAtlasByName then
        _profAtlasByName = {}
        for _, p in ipairs(HDG.Constants.PROFESSION_DATA) do
            if p.name and p.atlas then _profAtlasByName[p.name] = p.atlas end
        end
    end
    return name and _profAtlasByName[name] or nil
end

-- ===== Icon totality ========================================================
-- Coerce (iconTexture, iconAtlas) to a total pair (at least one non-nil).
-- Empty strings treated as nil (Blizzard catalog returns "" for ungenerated preview renders).
-- NOT a defensive guard -- totality is the selector's data contract, not the painter's job.
function F.CoerceIconPair(iconTexture, iconAtlas)
    local hasIcon  = iconTexture and iconTexture ~= ""
    local hasAtlas = iconAtlas   and iconAtlas   ~= ""
    if hasIcon then  return iconTexture, hasAtlas and iconAtlas or nil end
    if hasAtlas then return nil,         iconAtlas end
    return HDG.Constants.PLACEHOLDER_ICON, nil
end

-- Rep-gate progress suffix for the detail-panel gate line. Returns nil when progress is nil.
local _REP_CHECK_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local _REP_CROSS_ICON = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"
function F.ComposeRepProgressSuffix(progress)
    if not progress then return nil end
    local glyph = progress.met and _REP_CHECK_ICON or _REP_CROSS_ICON
    if progress.met or progress.isMax then
        return string.format("%s %s", glyph, progress.label)
    end
    return string.format("%s %s (%d/%d)",
        glyph, progress.label, progress.current or 0, progress.max or 0)
end

-- "|cffRRGGBB[LABEL]|r" chip. `dimmed` halves RGB (WoW ignores |c alpha byte; darkening RGB is the only option).
-- Strict Palette read: nil means a donorCode gap -- a real bug, not something to paper over.
function F.SourceChip(key, dimmed)
    local kind = HDG.Constants.SOURCE_KIND_BY_KEY[key]
    if not kind then return "[" .. tostring(key) .. "]" end
    local c = HDG.Palette:GetColor("source." .. kind.donorCode)
    local r, g, b = c.r, c.g, c.b
    if dimmed then r, g, b = r * 0.5, g * 0.5, b * 0.5 end
    return string.format("|cff%02x%02x%02x[%s]|r",
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), kind.chipLabel)
end

-- ===== Log level color + line ===============================================
-- Fixed / scheme-invariant: error must read red everywhere, and Debug rows are
-- in a PURE selector (can't read mutable Theme state).
--   LogColor(level) -> r, g, b   (for SetTextColor)
--   LogLine(entry)  -> string    ("[tag] text" with color escape)
-- (The numeric color and the "|cff" text escape are the same color in the two
-- forms WoW's two APIs need; the escape is internal to LogLine, not exposed.)
local LOG_LEVEL_COLOR = {
    debug   = { 0.53, 0.53, 0.53 },  -- muted gray (~text.dim)
    info    = { 0.31, 0.64, 0.95 },  -- accent blue
    warn    = { 0.95, 0.79, 0.30 },  -- amber
    error   = { 0.85, 0.30, 0.55 },  -- magenta
    success = { 0.00, 0.66, 0.59 },  -- teal
}
function F.LogColor(level)
    local c = LOG_LEVEL_COLOR[level] or LOG_LEVEL_COLOR.info
    return c[1], c[2], c[3]
end
-- Private: level color as "|cffRRGGBB" escape. Text surfaces use LogLine, not bare color codes.
local function logColorCode(level)
    local c = LOG_LEVEL_COLOR[level] or LOG_LEVEL_COLOR.info
    return string.format("|cff%02x%02x%02x",
        math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- Canonical "log entry -> colored line". Shared by chat + Debug-tab rows. Surface chrome prepended by caller.
function F.LogLine(entry)
    local body = entry.text or ""
    local payload = entry.metadata and entry.metadata.payloadStr
    if type(payload) == "string" and payload ~= "" then
        body = body .. "  " .. payload
    end
    return logColorCode(entry.level) .. "[" .. (entry.tag or "?") .. "] " .. body .. "|r"
end
