-- HDG.DecorFormat
-- ============================================================================
-- Canonical render-time formatters for decor-item display surfaces. Detail
-- panels + row factories call into here so visual treatments stay consistent
-- across every consumer (Acquire compact detail, Acquire full detail, Decor
-- browser detail, Shopping rows, Zone rows, Styles rows, etc.).
--
-- The complement to BuildRow's bake step: BuildRow stamps stable plain-text
-- labels onto the row (row.expansion, row.placementLabel, row.costLine,
-- row.gateLine, row.vendorLines[]); DecorFormat handles the STATEFUL or
-- THEMED rendering that has to recompute at refresh time:
--   F:Name(row)           -- quality color + collected-tint flip
--   F:GateChip(gate)      -- single chip with completion-state color
--   F:GateChips(row)      -- all chips for row factories
--   F:Collection(row)     -- "Collected (8 [chest]) (1 placed)" with theme colors
--
-- Everything else is a direct row field read (row.costLine, row.placementLabel,
-- row.expansionLabel etc.) -- no helper needed when the bake already produced
-- the final string. Adding a new display dimension = one BuildRow bake line +
-- one panel projection line; no per-surface formatting code.

HDG = HDG or {}
HDG.DecorFormat = HDG.DecorFormat or {}
local F = HDG.DecorFormat

-- ===== Internal helpers ======================================================

-- Item-quality brand color (Blizzard's ITEM_QUALITY_COLORS table; |cffRRGGBB
-- prefix already baked, scheme-invariant). Returns nil for unknown quality so
-- the caller can fall through to plain text.
local function _qualityHex(quality)
    local t = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    return t and t.hex
end

-- Atlas/icon strings reused across surfaces.
-- Icon size standardized at 14:14 to match BUDGET_ICON in BuildRow's
-- _bakePlacement; visual weight consistent across decor labels.
local CHEST_ICON = "|A:house-chest-icon:14:14|a"

-- Muted color for completed chips (single shared gray; reads as "satisfied"
-- without competing with the kind-specific incomplete colors).
local COMPLETE_HEX = "|cff808080"

-- ===== F:Name(row) ===========================================================
-- Item name with display-state coloring. Collected tint wins when owned
-- (Blizzard convention); quality color otherwise. Returns the original name
-- string when no color applies.
function F:Name(row)
    local name = row.name or "?"
    if row.isOwned then
        return HDG.Theme:StateLabel("collected", name)
    end
    local hex = _qualityHex(row.quality)
    if hex then return hex .. name .. "|r" end
    return name
end

-- ===== F:GateChip(gateEntry, row) ============================================
-- Single chip text: "[REP]" / "[QUEST]" / "[ACH]". Color flips by completion
-- state: incomplete -> ACQ_CHIP_PALETTE brand color; complete -> muted gray.
-- Completion comes from the LIVE row (row.isOwned) -- baking it would freeze
-- the state at sweep time and miss in-session learns. When real
-- C_AchievementInfo / C_ReputationInfo lookup lands for uncollected items,
-- this is the seam where it slots in (gate-specific completion override).
function F:GateChip(gateEntry, row)
    local kind = HDG.Constants.SOURCE_KIND_BY_KEY[gateEntry.kind]
    if not kind then return "" end
    if row and row.isOwned then
        return COMPLETE_HEX .. "[" .. kind.chipLabel .. "]|r"
    end
    -- Not-owned: Palette-backed chip color (single SSoT). kind is non-nil here,
    -- so SourceChip resolves -- never hits its unknown-key fallback.
    return HDG.Format.SourceChip(gateEntry.kind)
end

-- ===== F:GateChips(row) ======================================================
-- Concatenated chip strip from row.sourceTags (unified bake field). Used by
-- row factories that show all source/gate kinds inline (Acquire by-item
-- list shows [REP][ACH][VEND] etc.). Returns "" when no tags.
--
-- factionPrefix (Alliance/Horde crest) emitted before its own chip so the
-- crest visually anchors to the REP tag. Only REP carries factionPrefix and
-- REP sorts first via SOURCE_KIND_PRIORITY, so the crest leads the strip.
function F:GateChips(row)
    if not row.sourceTags then return "" end
    local parts = {}
    for _, t in ipairs(row.sourceTags) do
        if t.factionPrefix then parts[#parts+1] = t.factionPrefix end
        local c = F:GateChip(t, row)
        if c ~= "" then parts[#parts+1] = c end
    end
    return table.concat(parts, "")
end

-- ===== F:Collection(row) =====================================================
-- "Collected (8 [chest]) (1 placed)" / "Not Collected" with theme colors.
-- Reads row.quantity (stored) + row.numPlaced + row.isOwned.
-- TODO: switch to row.stored / row.placed when the field-rename sweep lands.
function F:Collection(row)
    local successCC = HDG.Theme:ColorCode("semantic.success")
    local warningCC = HDG.Theme:ColorCode("semantic.warning")
    local textCC    = HDG.Theme:ColorCode("text.primary")
    local dimCC     = HDG.Theme:ColorCode("text.dim")

    local stored = row.quantity  or 0  -- exception(boundary): catalog struct field sparse
    local placed = row.numPlaced or 0  -- exception(boundary): catalog struct field sparse

    local out
    if row.isOwned then
        out = successCC .. "Collected|r"
        if stored > 0 then
            out = out .. " " .. dimCC .. "(|r"
                .. textCC .. tostring(stored) .. "|r "
                .. CHEST_ICON .. dimCC .. ")|r"
        end
    else
        out = warningCC .. "Not Collected|r"
    end
    if placed > 0 then
        out = out .. " " .. dimCC .. "(|r"
            .. textCC .. tostring(placed) .. " placed|r" .. dimCC .. ")|r"
    end
    return out
end
