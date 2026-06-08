-- HDG.ChipStrip
-- ============================================================================
-- Wrap-and-flow chip strip backed by Blizzard's FlowContainer API.
-- SequenceView = WowScrollBoxList baggage (wants a scrollbar, can't auto-grow).
-- GridLayoutFrame = uniform-width assumption. FlowContainer wraps on actual
-- child width + exposes GetUsedBounds for section sizing.
--
-- Public API:
--   HDG.ChipStrip:Create(parent, cfg) -> container
--   HDG.ChipStrip:SetItems(container, items)
--   HDG.ChipStrip:Clear(container)
--   HDG.ChipStrip:RegisterCellKind(name, { constructor, binder, sizer })
-- Item shape: { label, displayLabel?, isActive?, key?, onClick?, ...customFields }

HDG = HDG or {}
HDG.ChipStrip = HDG.ChipStrip or {}
local M = HDG.ChipStrip

M._cellKinds = M._cellKinds or {}

local DEFAULT_CFG = {
    chipHeight        = 20,
    chipMinWidth      = 40,
    chipPadH          = 12,
    horizontalSpacing = 4,
    verticalSpacing   = 4,
    orientation       = "horizontal",
}
M.DEFAULT_CFG = DEFAULT_CFG

-- ===== Cell kind registry =================================================
function M:RegisterCellKind(name, def)
    if not (name and def and def.binder) then return end
    self._cellKinds[name] = {
        constructor = def.constructor,
        binder      = def.binder,
        sizer       = def.sizer,
    }
end

function M:GetCellKind(name) return self._cellKinds[name] end

-- ===== Default chip constructor ==========================================
-- Bare Button; EnsureChipChrome installs atlas chrome on first paint. Pooled per-container.
function M:DefaultChipConstructor(parent, cfg)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(cfg.chipHeight)
    HDG.UI:EnsureChipChrome(btn)
    return btn
end

-- ===== Icon chip constructor =============================================
-- Atlas-only cells (category/subcategory nav). No button chrome (atlas ships its own).
-- Selection via atlas state suffix (_active/_active-parent). Binders: no EnsureChipChrome.
function M:IconChipConstructor(parent, cfg)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(cfg.chipHeight)
    btn:EnableMouse(true)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", 0, 0)
    btn:SetFontString(fs)
    return btn
end

-- ===== Default binder =====================================================
function M:DefaultChipBinder(chip, item, cfg)
    if not item then
        chip:Hide()
        chip:SetScript("OnClick", nil)
        return
    end
    HDG.UI:EnsureChipChrome(chip)
    chip:Show()
    local label = item.displayLabel or item.label or ""
    chip:SetText(label)
    HDG.Theme:Register(chip, "Button",
        { variant = "chip", active = item.isActive == true })
    if chip.SetScript then  -- exception(false-positive): Frame always has SetScript; mock-fidelity guard
        chip:RegisterForClicks("LeftButtonUp")
        local onClick = item.onClick
        chip:SetScript("OnClick", function() if onClick then onClick(item) end end)
    end
end

-- ===== Default sizer ======================================================
-- Measures label width via a shared invisible FontString; result set before FlowContainer_DoLayout.
local _measureFS
local function _ensureMeasure()
    if _measureFS then return _measureFS end
    if not (UIParent and UIParent.CreateFontString) then return nil end
    _measureFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    _measureFS:Hide()
    return _measureFS
end

function M:DefaultChipSizer(item, cfg)
    local label = (item and item.displayLabel) or (item and item.label) or ""
    local fs = _ensureMeasure()
    local textW
    if fs then
        fs:SetText(label)
        textW = fs:GetUnboundedStringWidth() or 0  -- exception(boundary): natural width (clamp-independent)
    else
        textW = #label * 7
    end
    local w = math.max(cfg.chipMinWidth, textW + cfg.chipPadH)
    return w, cfg.chipHeight
end

-- ===== Build the container ================================================
-- Returns a bare Frame as a FlowContainer (public widget surface). Private chip pool on container.
function M:Create(parent, cfg)
    cfg = cfg or {}
    local merged = {}
    for k, v in pairs(DEFAULT_CFG) do merged[k] = v end
    for k, v in pairs(cfg) do merged[k] = v end

    local kindDef = merged.cellKind and self:GetCellKind(merged.cellKind)
    if kindDef then
        merged.chipConstructor = merged.chipConstructor or kindDef.constructor
        merged.chipBinder      = merged.chipBinder      or kindDef.binder
        merged.chipSizer       = merged.chipSizer       or kindDef.sizer
    end
    merged.chipConstructor = merged.chipConstructor
        or function(p, c) return M:DefaultChipConstructor(p, c) end
    merged.chipBinder      = merged.chipBinder
        or function(chip, item, c) return M:DefaultChipBinder(chip, item, c) end
    merged.chipSizer       = merged.chipSizer
        or function(item, c) return M:DefaultChipSizer(item, c) end

    local container = CreateFrame("Frame", nil, parent)
    FlowContainer_Initialize(container)
    -- orientation: "horizontal" (default, wraps to rows) or "vertical" (stacks into
    -- a column, e.g. the decor-picker category rail). cfg.orientation overrides.
    FlowContainer_SetOrientation(container, merged.orientation or "horizontal")
    FlowContainer_SetHorizontalSpacing(container, merged.horizontalSpacing)
    FlowContainer_SetVerticalSpacing(container,   merged.verticalSpacing)

    container._chipStripCfg  = merged
    container._chipPool      = { active = {}, free = {} }

    -- Re-wrap on parent resize. Cold layout (0-width) wraps every chip to its own line
    -- and mis-reports intrinsic height. OnSizeChanged forces a re-layout once width settles
    -- (2-3 iteration convergence; <1ms for 20 chips).
    container:SetScript("OnSizeChanged", function(self)
        if not self._chipStripCfg or self._reflowing then return end
        self._reflowing = true
        FlowContainer_DoLayout(self)
        local _w, h = FlowContainer_GetUsedBounds(self)
        local newH = h or 0   -- exception(boundary): FlowContainer_GetUsedBounds nil-on-empty
        if newH ~= self._intrinsicHeight then
            self._intrinsicHeight = newH
            self._usedHeight      = newH
            -- Publish re-wrapped height (Recipes strip dynamicRows selector re-sizes grid row).
            if self._chipStripCfg.onMeasure then self._chipStripCfg.onMeasure(newH) end
            -- Re-solve the layout (deferred; avoids recursion inside OnSizeChanged).
            if HDG.RequestReflow then HDG:RequestReflow() end  -- exception(nullable): RequestReflow registered at init time; nil in headless mock + early boot
        end
        self._reflowing = false
    end)
    return container
end

-- ===== Chip pool ==========================================================
-- Acquire/release across SetItems calls. Atlas + FontString reused; text + OnClick change per bind.
local function acquireChip(container, cfg)
    local chip = table.remove(container._chipPool.free)
    if not chip then
        chip = cfg.chipConstructor(container, cfg)
    end
    container._chipPool.active[#container._chipPool.active + 1] = chip
    return chip
end

local function releaseAll(container)
    -- FlowContainer_RemoveAllObjects clears flowFrames but doesn't hide objects; hide manually.
    for _, chip in ipairs(container._chipPool.active) do
        chip:Hide()
        chip:ClearAllPoints()
        chip:SetScript("OnClick", nil)
        container._chipPool.free[#container._chipPool.free + 1] = chip
    end
    container._chipPool.active = {}
    FlowContainer_RemoveAllObjects(container)
end

-- ===== SetItems ===========================================================
-- Recycle + bind chips, hand to FlowContainer. Reports used height via container._usedHeight.
function M:SetItems(container, items)
    if not container._chipStripCfg then return end
    local cfg = container._chipStripCfg

    FlowContainer_PauseUpdates(container)
    releaseAll(container)

    for _, item in ipairs(items or {}) do
        local chip = acquireChip(container, cfg)
        cfg.chipBinder(chip, item, cfg)
        local w, h = cfg.chipSizer(item, cfg)
        chip:SetSize(w, h)
        FlowContainer_AddObject(container, chip)
    end

    FlowContainer_ResumeUpdates(container)  -- triggers DoLayout

    local _usedW, usedH = FlowContainer_GetUsedBounds(container)
    container._usedHeight = usedH or 0        -- exception(boundary): nil on empty
    container._intrinsicHeight = usedH or 0   -- exception(boundary): variable-height signal for layout engine
    -- Optional measure callback (Recipes strip dynamicRows sizing).
    if cfg.onMeasure then cfg.onMeasure(container._usedHeight) end
end

function M:Clear(container)
    if not container._chipStripCfg then return end
    FlowContainer_PauseUpdates(container)
    releaseAll(container)
    FlowContainer_ResumeUpdates(container)
    container._usedHeight      = 0
    container._intrinsicHeight = 0
end
