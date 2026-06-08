-- HDG.DataController
-- ============================================================================
-- Your Data tab: KPI dashboard strip + scrollbox of Achievements / Craft
-- History / Farming History. Achievement groups are collapsible via
-- UI_SET_TRANSIENT. "dataRow" factory dispatches on ed.kind (7 shapes).

HDG = HDG or {}
HDG.Rows = HDG.Rows or {}
HDG.DataController = HDG.DataController or {}

local DataController = HDG.DataController

-- ===== Controller wiring =====================================================

function DataController:Wire(rootFrame)
    -- No interactive controls on this tab; all data flows from state.
end

function DataController:Refresh(rootFrame, ctx)
    -- Rendering flows through bindings + row factory.
end

HDG.Controllers:Register("data", DataController)

local function _pctStr(collected, total)
    if not total or total == 0 then return "0%" end
    return string.format("%.1f%%", 100 * collected / total)
end

local function _rowFirstPaint(row)
    HDG.UI:RowFirstPaint(row, "_dataLaidOut", function()
        local label = HDG.UI.RowText(row, "body", "Text", "LEFT")
        label:SetPoint("LEFT", row, "LEFT", 10, 0)
        label:SetWordWrap(false)
        row._labelFs = label

        local sub = HDG.UI.RowText(row, "small", "TextDim", "LEFT")
        sub:SetPoint("LEFT", label, "RIGHT", 8, 0)
        sub:SetWordWrap(false)
        row._subFs = sub

        -- Fixed-width count column: pinned width so the progress bar (anchored LEFT) doesn't drift.
        local right = HDG.UI.RowText(row, "small", "TextDim", "RIGHT")
        right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        right:SetWidth(150)
        right:SetWordWrap(false)
        row._rightFs = right

        -- Progress bar: shown on achieve rows only (HDG.UI:ProgressBar).
        local bar = HDG.UI:ProgressBar(row)
        if bar then
            bar:SetSize(120, 8)
            bar:SetPoint("RIGHT", right, "LEFT", -10, 0)
            bar:Hide()
            row._achBar = bar
        end
    end)
end

-- ===== Per-kind paint helpers ================================================

local function _layoutSectionHeader(row, ed, cc)
    HDG.UI.applyFontRole(row._labelFs, "heading")
    row._labelFs:SetText(cc.accent .. (ed.label or "") .. "|r")
    HDG.Theme:Register(row, "RowChrome", { header = true })
    row:SetHeight(32)
end

-- Collapsible group header: glyph + name left, "N/M done" right. Click dispatches UI_SET_TRANSIENT.
local function _layoutAchieveHeader(row, ed, cc)
    HDG.UI.applyFontRole(row._labelFs, "subheading")
    row._labelFs:ClearAllPoints()
    row._labelFs:SetPoint("LEFT", row, "LEFT", 16, 0)
    local glyph = ed.collapsed and "+ " or "- "
    row._labelFs:SetText(cc.dim .. glyph .. (ed.label or "") .. "|r")
    local done       = ed.totalCount > 0 and ed.earnedCount == ed.totalCount
    local countColor = done and cc.success or cc.dim
    row._rightFs:SetText(string.format("%s%d / %d done|r", countColor, ed.earnedCount, ed.totalCount))
    HDG.Theme:Register(row, "RowChrome", { header = true })
    row:SetHeight(26)
    row:SetScript("OnClick", function()
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.UI_SET_TRANSIENT,
            payload = { view = "data", key = "collapse_" .. ed.groupKey, value = not ed.collapsed },
        })
    end)
end

local function _layoutAchieveRow(row, ed, cc)
    HDG.UI.applyFontRole(row._labelFs, "body")
    row._labelFs:ClearAllPoints()
    row._labelFs:SetPoint("LEFT", row, "LEFT", 24, 0)
    local earnedColor = ed.earned and cc.success or cc.dim
    local label = string.format("%s%d items|r", earnedColor, ed.threshold)
    row._labelFs:SetText(label)
    local pct = (ed.reqQty and ed.reqQty > 0) and math.min(ed.qty / ed.reqQty, 1.0) or 0
    if row._achBar then
        row._achBar:SetProgress(pct)
        row._achBar:Show()
    end
    -- Color the pct text with success when 100%.
    local pctColor = (pct >= 1.0) and cc.success or ""
    local pctClose = (pct >= 1.0) and "|r" or ""
    row._rightFs:SetText(string.format("%s%d / %d  (%s)%s", pctColor, ed.qty, ed.reqQty, _pctStr(ed.qty, ed.reqQty), pctClose))
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    row:SetHeight(24)
end

local function _layoutLumberAchieveRow(row, ed, cc)
    HDG.UI.applyFontRole(row._labelFs, "body")
    row._labelFs:ClearAllPoints()
    row._labelFs:SetPoint("LEFT", row, "LEFT", 24, 0)
    local earnedColor = ed.earned and cc.success or cc.dim
    local label = earnedColor .. (ed.lumberName or "?") .. "|r"
    if ed.expansion and ed.expansion ~= "" then
        label = label .. cc.dim .. "  " .. ed.expansion .. "|r"
    end
    row._labelFs:SetText(label)
    -- Color pct text with success at 100%.
    local pct = (ed.reqQty and ed.reqQty > 0) and math.min(ed.qty / ed.reqQty, 1.0) or 0
    if row._achBar then
        row._achBar:SetProgress(pct)
        row._achBar:Show()
    end
    local pctColor = (pct >= 1.0) and cc.success or ""
    local pctClose = (pct >= 1.0) and "|r" or ""
    row._rightFs:SetText(string.format("%s%d / %d  (%s)%s", pctColor, ed.qty, ed.reqQty, _pctStr(ed.qty, ed.reqQty), pctClose))
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    row:SetHeight(24)
end

local function _layoutCraftHistRow(row, ed, cc)
    HDG.UI.applyFontRole(row._labelFs, "body")
    row._labelFs:ClearAllPoints()
    row._labelFs:SetPoint("LEFT", row, "LEFT", 10, 0)
    local typeLabel = ed.eventType == "learned" and (cc.success .. "[Learned]|r ")
                   or (cc.accent  .. "[Crafted]|r ")
    local name = HDG.ItemNameResolver:ResolveName(ed.itemID) or ("item " .. tostring(ed.itemID or "?"))
    row._labelFs:SetText(typeLabel .. name)
    row._rightFs:SetText(cc.dim .. (ed.dateStr or "") .. "|r")
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    row:SetHeight(24)
end

local function _layoutFarmHistRow(row, ed, cc)
    HDG.UI.applyFontRole(row._labelFs, "body")
    row._labelFs:ClearAllPoints()
    row._labelFs:SetPoint("LEFT", row, "LEFT", 10, 0)
    local exHex = HDG.Expansion.GetColorHex(ed.expansion)   -- lumber expansion brand color
    local lname = (exHex or cc.accent) .. (ed.lumberName or "?") .. "|r"
    local qty   = ed.sessionTotal > 0 and (" +" .. ed.sessionTotal) or ""
    row._labelFs:SetText(lname .. cc.dim .. qty .. "|r")
    local detail = {}
    if ed.duration and ed.duration ~= "" then detail[#detail + 1] = ed.duration end
    if ed.zone     and ed.zone     ~= "" then detail[#detail + 1] = ed.zone     end
    if ed.character and ed.character ~= "" then detail[#detail + 1] = ed.character end
    row._subFs:SetText(cc.dim .. table.concat(detail, "  ") .. "|r")
    row._rightFs:SetText(cc.dim .. (ed.dateStr or "") .. "|r")
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    row:SetHeight(24)
end

local function _layoutEmptyRow(row, ed, cc)
    HDG.UI.applyFontRole(row._labelFs, "small")
    row._labelFs:ClearAllPoints()
    row._labelFs:SetPoint("LEFT", row, "LEFT", 20, 0)
    row._labelFs:SetText(cc.dim .. (ed.label or "") .. "|r")
    HDG.Theme:Register(row, "RowChrome", { selected = false })
    row:SetHeight(24)
end

local function _resetRowFields(row)
    row._labelFs:SetText("")
    row._labelFs:ClearAllPoints()
    row._labelFs:SetPoint("LEFT", row, "LEFT", 10, 0)
    row._subFs:SetText("")
    row._rightFs:SetText("")
    if row._achBar then row._achBar:Hide() end
    row:SetScript("OnClick", nil)   -- achieveHeader rebinds; clear so recycled rows don't carry it
end

-- ===== Dispatch table ========================================================

local _CONFIGURE_BY_KIND = {
    sectionHeader        = _layoutSectionHeader,
    achieveHeader        = _layoutAchieveHeader,
    achieveRow           = _layoutAchieveRow,
    lumberAchieveRow     = _layoutLumberAchieveRow,
    craftHistRow         = _layoutCraftHistRow,
    farmHistRow          = _layoutFarmHistRow,
    emptyRow             = _layoutEmptyRow,
}

local function _dataRowFactory(_template)
    return {
        Configure = function(row, ed)
            _rowFirstPaint(row)
            _resetRowFields(row)
            local handler = _CONFIGURE_BY_KIND[ed.kind]
            if handler then
                local cc = HDG.UI.SemanticCC()
                handler(row, ed, cc)
            end
        end,
        Reset = function(row)
            row:SetScript("OnClick", nil)
            HDG.UI.ClearRowText(row, "_labelFs")
            if row._subFs   then row._subFs:SetText("")   end
            HDG.UI.ClearRowText(row, "_rightFs")
        end,
    }
end

HDG.Rows:Register("dataRow", {
    font    = "body",
    height  = 26,
    factory = _dataRowFactory,
    key     = function(ed)
        if not ed then return "?" end
        local k = ed.kind or "?"
        if k == "sectionHeader"       then return "sh:" .. tostring(ed.label or "?") end
        if k == "achieveHeader"       then return "ah:" .. tostring(ed.label or "?") end
        if k == "achieveRow"          then return "ar:" .. tostring(ed.id or "?") end
        if k == "lumberAchieveRow"    then return "la:" .. tostring(ed.id or "?") end
        -- craftHistRow: per-item-instance after qty expansion; idx disambiguates same-entry duplicates.
        if k == "craftHistRow"        then return "ch:" .. tostring(ed.idx or "?") end   -- idx disambiguates qty-expanded duplicates
        if k == "farmHistRow"         then return "fh:" .. tostring(ed.id or "?") end   -- unique entry id (name+minute collides)
        if k == "emptyRow"            then return "er:" .. tostring(ed.label or "?") end
        return "?"
    end,
})
