-- HDG.TooltipDecorator
-- ============================================================================
-- per ADR-014: hook TooltipDataProcessor to append HDG lines to item tooltips.
-- Selectors stay pure; state reads happen inside the post-call hook boundary.
--
-- Three line families appended (best-effort; each skipped if data missing):
--   1. Decor catalog row -> "HDG: Decor (<expansion>) - <source>"
--   2. Queue presence    -> "HDG: In craft queue (Nx remaining)"
--   3. Reagent usage     -> "HDG: Used in N decor recipes"
-- Work per item: O(1) table lookups + O(queue-length) walk (queue caps ~30).

HDG = HDG or {}
HDG.TooltipDecorator = HDG.TooltipDecorator or {}
local TD = HDG.TooltipDecorator

-- HDG-branded prefix for tooltip lines: the addon icon inline (same glyph as the
-- bag-slot decor-reagent badge), replacing the old "HDG:" text tag. 14px matches
-- the COIN_ATLAS inline-icon convention. Kept as a function for call-site parity.
local HDG_ICON_INLINE = "|TInterface\\AddOns\\HousingDecorGuide\\textures\\Vamoose_HDG_400_trans:14:14|t "
local function ACCENT_PREFIX()
    return HDG_ICON_INLINE
end

-- Decor catalog line. row.vendors[1].name = first vendor (empty if none).
-- Expansion via GetExpansionForItem(dataTagsByID walk). nil = skip line.
local function decorLine(itemID)
    local row = HDG.HousingCatalogObserver:GetRow(itemID)
    if not row then return nil end
    local exp = HDG.HousingCatalogObserver:GetExpansionForItem(itemID)
    if not exp then return nil end
    local src = (row.vendors and row.vendors[1] and row.vendors[1].name) or ""
    if src ~= "" then
        return string.format("%sDecor (%s) - %s", ACCENT_PREFIX(), exp, src)
    end
    return string.format("%sDecor (%s)", ACCENT_PREFIX(), exp)
end

-- Queue presence line. Walks queue once; first match wins.
local function queueLine(itemID)
    local state = HDG.Store:GetState()
    local queue = state.account.craft.queue
    if not queue then return nil end
    for _, row in ipairs(queue) do
        if row.itemID == itemID and (row.remaining or 0) > 0 then  -- exception(boundary): queue row from SVars may lack remaining
            return string.format("%sIn craft queue (%dx remaining)",
                ACCENT_PREFIX(), row.remaining)
        end
    end
    return nil
end

-- Reagent-usage line. Shows count of housing-decor recipes using this item,
-- regardless of whether learned (flags useful bag reagents before recipe known).
-- Counted live from DecorDB's reagent lists (ReagentsDB has no usedIn field).
local function reagentLine(itemID)
    local R = HDG.StaticData.Recipes
    local seen, n = {}, 0
    local function count(id)
        local users = R:RecipesUsingReagent(id)
        if not users then return end
        for _, r in ipairs(users) do
            if not seen[r] then seen[r] = true; n = n + 1 end
        end
    end
    count(itemID)
    -- Tiered reagents: recipes list one quality tier, the player may hold another --
    -- union across the quality group so any tier shows the count (e.g. Dawn Crystal).
    local variants = HDG.StaticData.Professions:GetQualityVariants(itemID)
    if variants then for _, v in ipairs(variants) do count(v) end end
    if n == 0 then return nil end
    return string.format("%sUsed in %d decor recipe%s", ACCENT_PREFIX(), n, n == 1 and "" or "s")
end

function TD:DecorateItemTooltip(tooltip, tooltipData)
    if not (tooltip and tooltipData and tooltipData.id) then return end
    if not tooltip.AddLine then return end
    local itemID = tooltipData.id
    local lines = {}
    -- Decor + reagent lines gated on TOOLTIP_DECOR_TAG config.
    -- Queue line is a live craft helper and is always shown.
    if HDG.Config:Get("TOOLTIP_DECOR_TAG") then
        local d = decorLine(itemID);   if d then lines[#lines + 1] = d end
        local r = reagentLine(itemID); if r then lines[#lines + 1] = r end
    end
    local q = queueLine(itemID); if q then lines[#lines + 1] = q end
    for _, line in ipairs(lines) do
        tooltip:AddLine(line, 1, 1, 1, false)   -- white, no wrap
    end
end

function TD:Install()
    if self._installed then return end
    local tdp  = _G.TooltipDataProcessor
    local enum = _G.Enum and _G.Enum.TooltipDataType
    if not (tdp and tdp.AddTooltipPostCall and enum and enum.Item) then return end
    tdp.AddTooltipPostCall(enum.Item, function(tooltip, data)
        -- Gotcha: C_TooltipInfo can leak secret-string taint in 12.0.5;
        -- string-ops on tainted data poison the caller. pcall isolates us.
        local ok, err = pcall(function() TD:DecorateItemTooltip(tooltip, data) end)
        if not ok then HDG.Log:Warn("tooltip", tostring(err)) end
    end)
    self._installed = true
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name = "TooltipDecorator",
    dependencies = {},
    onEnable = function(self)
        TD:Install()
    end,
})
