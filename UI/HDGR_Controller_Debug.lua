-- HDG.DebugController
-- ============================================================================
-- Debug Log tab: tag/level filter dropdowns, clear, copy, mem/perf profile,
-- auto-scroll toggle, layout describer. Refresh empty (binding-driven).

HDG = HDG or {}
HDG.DebugController = HDG.DebugController or {}

local DebugController = HDG.DebugController

-- ===== Memory profile helpers ================================================
-- approxBytes: recursive serializable-bytes proxy (closer to on-disk SV size).
-- entryCount + leafCount: summary metrics; "leaves" = total recursive leaf count.

local function _approxBytes(v, seen)
    local t = type(v)
    if t == "string"  then return #v + 2 end
    if t == "number"  then return 8 end
    if t == "boolean" then return 5 end
    if t == "nil"     then return 3 end
    if t == "table" then
        if seen[v] then return 0 end
        seen[v] = true
        local n = 2
        for k, val in pairs(v) do
            n = n + _approxBytes(k, seen) + _approxBytes(val, seen) + 4
        end
        return n
    end
    return 0
end

local function _entryCount(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function _leafCount(t, seen)
    if type(t) ~= "table" then return 1 end
    if seen[t] then return 0 end
    seen[t] = true
    local n = 0
    for _, v in pairs(t) do n = n + _leafCount(v, seen) end
    return n
end

-- { name, entries, leaves, bytes } sorted desc by bytes.
local function _profileChildren(src)
    local rows = {}
    if type(src) ~= "table" then return rows end
    for k, v in pairs(src) do
        if type(k) == "string" then
            rows[#rows + 1] = {
                name    = k,
                entries = _entryCount(v),
                leaves  = _leafCount(v, {}),
                bytes   = _approxBytes(v, {}),
            }
        end
    end
    table.sort(rows, function(a, b) return a.bytes > b.bytes end)
    return rows
end

-- Catalog observer mirror rows.
local OBSERVER_MIRRORS = {"byDecorID","byItemID","byVendor","byZone","byNpc","byRecipe","bySource"}
local function _collectObserverRows()
    local obs = HDG.HousingCatalogObserver
    local rows = {}
    for _, key in ipairs(OBSERVER_MIRRORS) do
        local t = obs and obs[key]
        if type(t) == "table" then
            rows[#rows + 1] = {
                name    = key,
                entries = _entryCount(t),
                bytes   = _approxBytes(t, {}),
            }
        end
    end
    table.sort(rows, function(a, b) return a.bytes > b.bytes end)
    return rows
end

-- Static-data globals (_G.HDGR_*DB): tables with >=5 entries, excluding HDG/HDG_DB.
local function _collectStaticDataRows()
    local rows = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^HDGR_") and type(v) == "table"
           and k ~= "HDG" and k ~= "HDG_DB" then
            local n = _entryCount(v)
            if n >= 5 then
                rows[#rows + 1] = {
                    name    = k,
                    entries = n,
                    bytes   = _approxBytes(v, {}),
                }
            end
        end
    end
    table.sort(rows, function(a, b) return a.bytes > b.bytes end)
    return rows
end

-- Profile every top-level HDG.X subtable; drill one level into any >50 KB.
local HDGR_DEEP_EXCLUDE = {
    Store = true, HousingCatalogObserver = true, Constants = true,
    Selectors = true,  -- separately reported
}
-- Append sub-tables >=10 KB into `deep` for rows >=50 KB.
local function _expandDeepNamespace(r, deep)
    if r.bytes < 50 * 1024 then return end
    for sk, sv in pairs(r.ref) do
        if type(sk) == "string" and type(sv) == "table" then
            local sb = _approxBytes(sv, {})
            if sb >= 10 * 1024 then
                deep[#deep + 1] = {
                    name    = "HDG." .. r.name .. "." .. sk,
                    entries = _entryCount(sv),
                    bytes   = sb,
                }
            end
        end
    end
end

local function _collectHdgrNamespaceRows()
    local rows, deep = {}, {}
    for k, v in pairs(HDG or {}) do
        if type(k) == "string" and type(v) == "table" and not HDGR_DEEP_EXCLUDE[k] then
            rows[#rows + 1] = { name = k, entries = _entryCount(v),
                                bytes = _approxBytes(v, {}), ref = v }
        end
    end
    table.sort(rows, function(a, b) return a.bytes > b.bytes end)
    -- For any HDG.X >=50 KB, expand one level for any sub-table >=10 KB.
    for _, r in ipairs(rows) do
        _expandDeepNamespace(r, deep)
    end
    table.sort(deep, function(a, b) return a.bytes > b.bytes end)
    return rows, deep
end

-- Subscriber + selector cache stats.
local function _collectSubscriberStats()
    local subN = 0
    local subT = HDG.Store._subscribers
    if type(subT) == "table" then for _ in pairs(subT) do subN = subN + 1 end end
    local selBytes, selEntries = 0, 0
    local selCache = HDG.Selectors and (HDG.Selectors._cache or HDG.Selectors.cache)
    if type(selCache) == "table" then
        selEntries = _entryCount(selCache)
        selBytes   = _approxBytes(selCache, {})
    end
    return subN, selEntries, selBytes
end

-- Format the assembled memory snapshot into a copy-dialog-ready string.
local function _formatMemoryReport(snap)
    local lines = {}
    local function kb(n) return n / 1024 end
    local function add(fmt, ...) lines[#lines+1] = string.format(fmt, ...) end

    add("HDG Memory Profile")
    add("====================================================================")
    add("Runtime totals:")
    add("  GetAddOnMemoryUsage('HousingDecorGuide'): %10.1f KB", snap.addonMem)
    add("  Lua heap (collectgarbage 'count'):   %10.1f KB", snap.heap)
    add("  HDG_DB approx bytes (SV proxy):     %10.1f KB  (real size: check on-disk file)", kb(snap.svBytes))
    add("")
    add("Catalog observer (HDG.HousingCatalogObserver):")
    add("  status: %s   sweepGeneration: %d", tostring(snap.catalogStatus), snap.catalogSweep)
    add("  %-20s %10s %12s", "mirror", "entries", "approx KB")
    for _, r in ipairs(snap.observer) do
        add("  %-20s %10d %12.1f", r.name, r.entries, kb(r.bytes))
    end
    add("")
    add("Store state -- account.* (sorted by approx bytes):")
    add("  %-26s %10s %10s %12s", "key", "entries", "leaves", "approx KB")
    for _, r in ipairs(snap.account) do
        add("  %-26s %10d %10d %12.1f", r.name, r.entries, r.leaves, kb(r.bytes))
    end
    add("")
    add("Store state -- session.* (sorted by approx bytes):")
    add("  %-26s %10s %10s %12s", "key", "entries", "leaves", "approx KB")
    for _, r in ipairs(snap.session) do
        add("  %-26s %10d %10d %12.1f", r.name, r.entries, r.leaves, kb(r.bytes))
    end
    add("")
    add("Static data globals (_G.HDGR_*, sorted by approx bytes):")
    add("  %-32s %10s %12s", "global", "entries", "approx KB")
    for _, r in ipairs(snap.globals) do
        add("  %-32s %10d %12.1f", r.name, r.entries, kb(r.bytes))
    end
    add("")
    add("Subscribers + selector cache:")
    add("  Store._subscribers entries:          %d", snap.subN)
    add("  Selectors._cache entries:            %d   (approx %.1f KB)", snap.selEntries, kb(snap.selBytes))
    add("")
    add("HDG.* namespace deep dive (sorted by approx bytes):")
    add("  %-40s %10s %12s", "subsystem", "entries", "approx KB")
    for _, r in ipairs(snap.hdgrRows) do
        if r.bytes >= 1024 then
            add("  HDG.%-35s %10d %12.1f", r.name, r.entries, kb(r.bytes))
        end
    end
    if #snap.hdgrDeep > 0 then
        add("")
        add("HDG.* deep-dive into >50KB subsystems (any sub-table >=10 KB):")
        add("  %-50s %10s %12s", "path", "entries", "approx KB")
        for _, r in ipairs(snap.hdgrDeep) do
            add("  %-50s %10d %12.1f", r.name, r.entries, kb(r.bytes))
        end
    end
    add("")
    add("Notes:")
    add("  - 'leaves' is total recursive leaf count (deep entry count).")
    add("  - 'approx KB' is serializable-bytes proxy; in-memory table overhead is 2-4x higher.")
    add("  - Lua heap includes ALL addons + Blizzard UI; per-addon mem is just HousingDecorGuide.")
    return table.concat(lines, "\n")
end

local function _snapshotMemory()
    if _G.UpdateAddOnMemoryUsage then _G.UpdateAddOnMemoryUsage() end  -- exception(boundary): UpdateAddOnMemoryUsage removed in Midnight; guard is API-version check
    local state = HDG.Store:GetState()  -- exception(false-positive): top-level debug helper, not a row factory
    local subN, selEntries, selBytes = _collectSubscriberStats()
    local hdgrRows, hdgrDeep         = _collectHdgrNamespaceRows()
    return {
        addonMem      = (_G.GetAddOnMemoryUsage and _G.GetAddOnMemoryUsage("HousingDecorGuide")) or 0,
        heap          = collectgarbage("count"),
        svBytes       = _G.HDG_DB and _approxBytes(_G.HDG_DB, {}) or 0,
        catalogStatus = state.session.catalog.status,
        catalogSweep  = state.session.resolvers.catalog.tick or 0,
        observer      = _collectObserverRows(),
        account       = _profileChildren(state.account),
        session       = _profileChildren(state.session),
        globals       = _collectStaticDataRows(),
        subN          = subN,
        selEntries    = selEntries,
        selBytes      = selBytes,
        hdgrRows      = hdgrRows,
        hdgrDeep      = hdgrDeep,
    }
end

-- ===== Per-button handlers ===================================================

local function _onClearClick()
    local state  = HDG.Store:GetState()  -- exception(false-positive): top-level controller method (not a row factory)
    local filter = state.session.log.tabFilter or {}
    local payload = {}
    if filter.tag and filter.tag ~= "all" then payload.tag = filter.tag end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.LOG_CLEAR,
        payload = payload,
    })
    HDG.Log:Info("debug_tab", payload.tag
        and ("Cleared log entries tagged " .. payload.tag)
        or "Cleared all log entries")
end

-- Copy: WoW has no clipboard API; select-all + focus so user follows with Ctrl+C.
local function _onCopyClick(rootFrame)
    local body = HDG.UI.W(rootFrame, "debugPanel.body")
    if not (body and body.SetFocus and body.EditBox) then return end
    body:SetFocus()
    if body.EditBox.HighlightText then  -- exception(false-positive): EditBox always has HighlightText in WoW retail; guard is mock-fidelity
        body.EditBox:HighlightText()  -- no-arg = select all
    end
    HDG.Log:Info("debug_tab", "Selected -- press Ctrl+C to copy")
end

-- Auto-scroll toggle: dispatches LOG_TOGGLE_AUTOSCROLL.
local function _wireAutoScrollCheckbox(rootFrame)
    local box = HDG.UI.W(rootFrame, "debugPanel.autoScroll")
    if not (box and box.SetScript) then return end
    box:SetScript("OnClick", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.LOG_TOGGLE_AUTOSCROLL })
    end)
end

-- Layout describer: pops Layout:DescribeView() in a CopyDialog (button or Enter).
local function _wireLayoutDescriber(rootFrame)
    local input = HDG.UI.W(rootFrame, "debugPanel.layoutInput")
    local function run()
        local viewName = input and input.GetText and input:GetText() or ""
        viewName = HDG.Format.Trim(viewName)
        if viewName == "" then viewName = "styles" end
        local text = HDG.Layout:DescribeView(viewName)
        local dialog = HDG.UI:CopyDialog()
        if dialog and dialog.Open then
            dialog:Open(("Layout: %s"):format(viewName), text)
        end
    end
    HDG.UI.OnClick(rootFrame, "debugPanel.layoutBtn", run)
    if input and input.SetScript then
        input:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            run()
        end)
    end
end

local function _onMemProfileClick()
    local snap   = _snapshotMemory()
    local text   = _formatMemoryReport(snap)
    local dialog = HDG.UI:CopyDialog()
    if dialog and dialog.Open then
        dialog:Open("Memory Profile", text)
    end
end

-- Perf Profile: open HDG.Perf window (separate from CopyDialog; has Refresh + Reset).
local function _onPerfProfileClick()
    HDG.Perf:OpenWindow()
end

function DebugController:Wire(rootFrame)
    HDG.UI.OnClick(rootFrame, "debugPanel.clear",  _onClearClick)
    HDG.UI.OnClick(rootFrame, "debugPanel.copy",   function() _onCopyClick(rootFrame) end)
    HDG.UI.OnClick(rootFrame, "debugPanel.memBtn", _onMemProfileClick)
    HDG.UI.OnClick(rootFrame, "debugPanel.perfBtn", _onPerfProfileClick)
    _wireAutoScrollCheckbox(rootFrame)
    _wireLayoutDescriber(rootFrame)
end

function DebugController:Refresh(rootFrame, ctx)
    -- Bindings handle text + count. Nothing imperative.
end

HDG.Controllers:Register("debug", DebugController)
