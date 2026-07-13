-- HDG.Debug
-- ============================================================================
-- Dev half of the /hdgr slash REPL. Explicit multi-line dumps; prints raw (not Log:Notify).
-- Each command is a named function so it's callable directly, not only via the slash string.

HDG = HDG or {}
HDG.Debug = HDG.Debug or {}

local D = HDG.Debug

-- Header: "[HDG] <line>". Detail/code-gen lines print bare (tables stay aligned / copy-pasteable).
local function _print(line) _G.print("|cff666666[HDG]|r " .. line) end

-- /hdgr help -- SSoT for the slash surface. Keep in sync when commands are added/removed.
local function _cmd(cmd, desc) _G.print(("  |cffcdd6f4%-24s|r |cff999999%s|r"):format(cmd, desc)) end
function D:Help()
    _print("commands -- user:")
    _cmd("/hdgr",              "open / close the main window")
    _cmd("/hdgr help",         "this listing (also /hdgr ?)")
    _cmd("/hdgr theme [name]", "list themes / switch theme (case-insensitive prefix)")
    _cmd("/hdgr view [name]",  "list views / switch the main window's active view")
    _cmd("/hdgr minimap",      "toggle the minimap button")
    _cmd("/hdgr resetlayout",  "reset the HouseTab dashboard layout to defaults")
    _cmd("/hdgr hardreset",    "wipe all saved HDG data (full reset)")
    _cmd("/hdgr refresh",      "force a fresh housing-catalog sweep")
    _G.print("|cff666666[HDG]|r commands -- developer:")
    _cmd("/hdgr debug",            "toggle debug logging mode (the dispatch firehose etc.)")
    _cmd("/hdgr mocktsm",          "toggle Mock TSM (flat 100g prices, no TSM) -- same as the Advanced checkbox")
    _cmd("/hdgr trace [tag/off]",  "list active traces / toggle a log-tag trace / disable all")
    _cmd("/hdgr log [tag/clear]",  "last 10 log entries (opt. filtered by tag) / clear the log")
    _cmd("/hdgr house",            "dump the HouseTab dashboard runtime state (widget/data chain)")
    _cmd("/hdgr costdump <id>",    "dump a catalog row's parsed cost + sourceTags for an itemID")
    _cmd("/hdgr dumpdecor <ids>",  "emit AllDecorDB-ready Lua rows for decorIDs (copy-paste)")
    _cmd("/hdgr sl <cmd>",         "selector call-count profiler: start / stop / dump / clear")
    _cmd("/hdgr perf [on/off/reset]", "performance profiler (bare opens the window)")
    _cmd("/hdgr doors",            "door audit for the OPEN Architect canvas (ShapeAtlas verify)")
end

-- ===== Config toggles =======================================================

function D:Toggle()
    local cfg = HDG.Store:GetState().account.config
    HDG.Store:Dispatch({
        type = HDG.Constants.ACTIONS.CONFIG_SET,
        payload = { key = "debug", value = not cfg.debug },
    })
end

function D:MockTSM()
    -- Flat 100g prices; exercises the TSM code path without installing TSM.
    local on = HDG.PriceSource:ToggleMockTSM()
    HDG.Log:Notify("info", ("mock TSM = %s"):format(on and "on" or "off"))
end

-- ===== Trace toggling =======================================================
-- /hdgr trace            -- list active traces
-- /hdgr trace <tag>      -- toggle trace for tag
-- /hdgr trace off        -- disable all traces
function D:Trace(rest)
    local arg = (rest or ""):gsub("%s", "")
    if arg == "" then
        local active = HDG.Store:GetState().session.log.activeTraces or {}
        local any = false
        for tag, on in pairs(active) do
            if on then
                if not any then _print("Active traces:"); any = true end
                _G.print(("  |cff14b8a6%s|r"):format(tag))
            end
        end
        if not any then _print("no active traces") end
        _G.print("|cff666666Usage: /hdgr trace <tag>  -  /hdgr trace off|r")
    elseif arg == "off" then
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.LOG_TRACE_TOGGLE, payload = { tag = "*" } })
        _print("all traces disabled")
    else
        if not HDG.Log:HasTag(arg) then
            _print(("unknown tag %q -- registered tags:"):format(arg))
            for name in pairs(HDG.Log.TAGS) do _G.print(("  |cff14b8a6%s|r"):format(name)) end
        else
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.LOG_TRACE_TOGGLE,
                payload = { tag = arg },   -- omitting `on` toggles
            })
            local nowActive = HDG.Store:GetState().session.log.activeTraces[arg]
            _print(("trace %q -> %s"):format(arg, nowActive and "on" or "off"))
        end
    end
end

-- ===== Log dump / clear =====================================================
-- /hdgr log                -- last 10 entries
-- /hdgr log <tag>          -- last 10 of that tag
-- /hdgr log clear [<tag>]  -- clear all or one tag
function D:Log(rest)
    local arg = HDG.Format.Trim(rest)
    if arg:match("^clear") then
        local tag = arg:match("^clear%s+(%S+)$")
        if tag then
            HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.LOG_CLEAR, payload = { tag = tag } })
            _print(("cleared log entries tagged %q"):format(tag))
        else
            HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.LOG_CLEAR })
            _print("log cleared")
        end
        return
    end
    local tagFilter = arg ~= "" and arg or nil
    local entries = HDG.Store:GetState().session.log.entries or {}
    local matched = {}
    for _, e in ipairs(entries) do
        if not tagFilter or e.tag == tagFilter then matched[#matched + 1] = e end
    end
    local start = math.max(1, #matched - 9)
    _print(("log (last %d of %d%s):"):format(
        math.min(10, #matched), #matched, tagFilter and (" tagged " .. tagFilter) or ""))
    for i = start, #matched do
        local e = matched[i]
        _G.print(("  |cff666666%.1f|r |cff14b8a6%-12s|r |cff999999%-7s|r %s"):format(
            e.timestamp or 0, e.tag, e.level, e.text))  -- migration (legacy log entries)
    end
end

-- Dump dashboard runtime state (selector empty? widget not built? data not pushed?).
function D:House()
    local root = HDG.mainFrame
    _print("house diagnostic dump:")
    _G.print(("  view:           %s"):format(tostring(HDG.Store:GetState().account.ui.view)))
    _G.print(("  mainFrame:      %s"):format(root and "exists" or "MISSING"))
    if root then
        local pnl = root.panels and root.panels["houseTabPanel"]
        local pkr = root.widgets and root.widgets["houseTabPanel.pickerBtn"]
        local dsn = root.widgets and root.widgets["houseTabPanel.designBtn"]
        local lst = root.widgets and root.widgets["houseTabPanel.list"]
        _G.print(("  panel frame:    %s"):format(pnl and "built" or "MISSING"))
        _G.print(("  pickerBtn:      %s"):format(pkr and "built" or "MISSING"))
        _G.print(("  designBtn:      %s"):format(dsn and "built" or "MISSING"))
        _G.print(("  list widget:    %s"):format(lst and "built" or "MISSING"))
        if lst then
            _G.print(("    bound:        %s"):format(lst._hdgrBound and "yes" or "NO"))
            _G.print(("    rowKind:      %s"):format(tostring(lst.rowKind)))
            _G.print(("    parent type:  %s"):format(lst:GetParent() and lst:GetParent():GetName() or "?"))
            _G.print(("    visible:      %s, sz=%dx%d"):format(
                tostring(lst:IsVisible()), lst:GetWidth() or 0, lst:GetHeight() or 0))  -- exception(boundary): debug print, WoW API
            _G.print(("    provider sz:  %d"):format(lst.provider and lst.provider:GetSize() or -1))
        end
        if root.widgets then
            local count = 0
            for id in pairs(root.widgets) do
                if id:match("^houseTabPanel") then count = count + 1 end
            end
            _G.print(("  houseTab widgets in rootFrame.widgets: %d"):format(count))
        end
    end
    local snap = HDG.Store:GetState().session.house and HDG.Store:GetState().session.house.snapshot or nil
    _G.print(("  snapshotChangeSeq:   %s"):format(tostring(HDG.Store:GetState().session.house and HDG.Store:GetState().session.house.snapshotChangeSeq)))
    _G.print(("  snapshot keys:  %s"):format(snap and tostring(next(snap) or "EMPTY") or "nil"))
    local items = HDG.Selectors:Call("house.widgetList", HDG.Store:GetState(), {})  -- exception(false-positive): debug dump function, not a row factory
    _G.print(("  widgetList:     %d items"):format(#items))
    if #items > 0 then
        _G.print(("    [1] id=%s height=%s data=%s"):format(
            tostring(items[1].id), tostring(items[1].height),
            items[1].data and tostring(next(items[1].data) or "empty-data-table") or "nil"))
    end
    local placements = root and root.placements or {}
    local p = placements["houseTabPanel"]
    _G.print(("  panel placed:   %s"):format(p and ("%dx%d at (%d,%d)"):format(p.width or 0, p.height or 0, p.x or 0, p.y or 0) or "(not placed)"))
    local pl = placements["houseTabPanel.list"]
    _G.print(("  list placed:    %s"):format(pl and ("%dx%d at (%d,%d)"):format(pl.width or 0, pl.height or 0, pl.x or 0, pl.y or 0) or "(not placed)"))
end

-- Dump row's parsed cost + source table for an itemID. Diagnostic for endeavor/gold.
function D:CostDump(rest)
    local id = tonumber((rest or ""):match("%d+"))
    if not id then _G.print("|cff666666Usage: /hdgr costdump <itemID>|r"); return end
    local row = HDG.HousingCatalogObserver:GetRow(id)
    if not row then
        _print(("no catalog row for %d (catalog ready? item matches searcher?)"):format(id))
        return
    end
    local function ceStr(list)
        if not list or #list == 0 then return "EMPTY" end
        local s = ""
        for _, e in ipairs(list) do s = s .. ("[id=%s x%s]"):format(tostring(e.currencyID), tostring(e.amount)) end
        return s
    end
    _print(("costdump %d: %s"):format(id, row.name or "?"))
    _G.print(("  vendors: %d"):format(row.vendors and #row.vendors or 0))  -- exception(nullable): vendors list optional
    for i, v in ipairs(row.vendors or {}) do
        _G.print(("    [%d] %s | cost=%q | costEntries=%s"):format(i, tostring(v.name), tostring(v.cost), ceStr(v.costEntries)))
    end
    _G.print("  row.costEntries: " .. ceStr(row.costEntries))
    _G.print("  row.costLine: " .. tostring(row.costLine))
    _G.print("  row.shop: " .. tostring(row.shop))
    local tags = ""
    for _, t in ipairs(row.sourceTags or {}) do tags = tags .. "[" .. tostring(t.kind) .. "]" end
    _G.print("  sourceTags: " .. (tags ~= "" and tags or "none"))
    local info = row.decorID and _G.C_HousingCatalog
             and _G.C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, row.decorID)
    if info and info.sourceText and info.sourceText ~= "" then
        local st = info.sourceText
        _G.print("  live sourceText: " .. (st:gsub("|", "||")))
        _G.print("  find 'Cost:': " .. tostring(st:find("Cost:") ~= nil))
        _G.print("  amt  Cost:[^digit]*(digits): " .. tostring(st:match("Cost:[^%d]*([%d,]+)")))
        _G.print("  curr currency:(digits): " .. tostring(st:match("currency:(%d+)")))
    else
        _G.print("  live sourceText: (empty / unavailable)")
    end
end

-- Emit AllDecorDB-ready Lua rows for decorIDs. Code lines print bare (paste into HDG_AllDecorDB.lua).
function D:DumpDecor(rest)
    rest = rest or ""
    if rest == "" then _G.print("|cff666666Usage: /hdgr dumpdecor <id1>,<id2>,...|r"); return end
    local ids = {}
    for s in rest:gmatch("%d+") do ids[#ids + 1] = tonumber(s) end
    if #ids == 0 then _G.print("|cff666666Usage: /hdgr dumpdecor <id1>,<id2>,...|r"); return end
    _print(("Dumping %d decorID rows -- copy lines into HDG_AllDecorDB.lua:"):format(#ids))
    local exp = "Midnight"   -- caller can re-tag per row as needed
    local now = time()
    for _, decorID in ipairs(ids) do
        local info = _G.C_HousingCatalog
                 and _G.C_HousingCatalog.GetCatalogEntryInfoByRecordID
                 and _G.C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, decorID)
        if info and info.itemID then
            local subcat = (info.subcategoryIDs and info.subcategoryIDs[1]) or 0
            _G.print(("    [%d] = {%d, 12, \"Blizzard Shop\", \"\", %d, exp = %q, name = %q, placementCost = 0, quality = %d, subcats = {%d}, ver = 120001},"):format(
                info.itemID, decorID, now, exp,
                info.name or "?", info.quality or 1, subcat))  -- exception(boundary): debug print, info from cold cache
        else
            _G.print(("    -- decorID %d: GetCatalogEntryInfoByRecordID returned nil"):format(decorID))
        end
    end
    _G.print("|cff666666(sourceType=12 = Shop is the default guess; adjust per item if it came from elsewhere.)|r")
end
