-- HDG.Perf
-- ============================================================================
-- Engine-internal performance instrumentation (debugprofilestop, ms).
-- FLUSH cost: deferred subscriber fan-out (C_Timer.After(0)), not the reducer.
-- SELECTOR cost: per-selector call time (populated by HDG.Selectors:Call probe).
-- GATE: HDG_DB.perf (raw SV root, NOT Store/Config -- must be readable at boot
-- before Config hydrates; profile-scoped field didn't persist on fresh accounts).
-- Toggle: /hdgr perf on|off. Dump: /hdgr perf. Clear: /hdgr perf reset.

HDG = HDG or {}
HDG.Perf = HDG.Perf or {}
local P = HDG.Perf

-- Probe sites use debugprofilestop() (sub-ms); GetTime() is frame-granular -> 0ms per-frame.

-- Accumulators. Keyed for aggregation across many samples.
--   _flush[actionKey] = { count, total, max, subs }
--   _sel[name]        = { count, total, max }
--   _op[name]         = { count, total, max }  -- module ops outside the dispatch path
--   _stage[name]      = { count, total, max }  -- per-pipeline-stage cost (runPipeline)
P._flush = P._flush or {}
P._sel   = P._sel   or {}
P._op    = P._op    or {}
P._stage = P._stage or {}

-- Ordered timeline: chronological list of marks from the boot epoch, so the
-- startup chain (login -> ... -> decor browser visible) reads top-to-bottom.
--   _timeline[i] = { t = ms-since-epoch, label, ms = cost?, kind }
--     kind: "flush" | "op" | "rtt" | "event"
--   ms is the CPU cost of the step (nil for pure event markers); the GAP
--   between consecutive `t` values is wall-clock (includes async/idle waits --
--   NOT necessarily our cost). RTT marks carry ms = the external round-trip.
-- Capped so a long session doesn't grow unbounded; the boot chain is what
-- matters and it's all at the front.
P._timeline    = P._timeline or {}
P._epoch       = P._epoch    -- debugprofilestop() at OnInitialize; nil until set
P.TIMELINE_CAP = 400

-- ===== Gate ================================================================

-- exception(boundary): HDG_DB may be nil in tests / very early boot; missing = disabled (never load-bearing).
function P:Enabled()
    return _G.HDG_DB ~= nil and _G.HDG_DB.perf == true
end

-- ===== Recording ===========================================================

local function _bump(bucket, key, ms, subs)
    local e = bucket[key]
    if not e then
        e = { count = 0, total = 0, max = 0 }
        bucket[key] = e
    end
    e.count = e.count + 1
    e.total = e.total + ms
    if ms > e.max then e.max = ms end
    if subs ~= nil then e.subs = subs end
    return e
end

-- Record one Store flush. Attributed to distinct action types in the batch ("A+B" when batched).
function P:RecordFlush(pending, ms, subCount)
    local seen, types = {}, {}
    local viewTarget
    for _, n in ipairs(pending) do
        local t = n.type or "?"
        if not seen[t] then
            seen[t] = true
            types[#types + 1] = t
        end
        -- Surface destination tab for view switches so per-tab cost separates.
        local p = n.action and n.action.payload
        if p and p.key == "view" and p.value then
            viewTarget = tostring(p.value)
        end
    end
    table.sort(types)
    local key = table.concat(types, "+")
    if viewTarget then key = key .. "  ->" .. viewTarget end
    _bump(self._flush, key, ms, subCount)
    self:Mark(key, ms, "flush")   -- also land it on the chronological boot timeline
end

-- Record one selector call. Called by the HDG.Selectors:Call probe (later).
function P:RecordSelector(name, ms)
    _bump(self._sel, name, ms)
end

-- Module op outside dispatch path (catalog sweep, aggregator snapshot, etc).
function P:RecordOp(name, ms)
    _bump(self._op, name, ms)
    self:Mark(name, ms, "op")   -- also land it on the chronological boot timeline
end

-- Refresh-pipeline stage (PrepareContext/Bind/Layout/...). Not added to timeline (many-per-flush).
function P:RecordStage(name, ms)
    _bump(self._stage, name, ms)
end

-- SetEpoch: t-zero for the boot timeline. Called once from Init:OnInitialize. Idempotent.
function P:SetEpoch()
    if self._epoch then return end
    self._epoch = _G.debugprofilestop and _G.debugprofilestop() or 0
end

-- Append a chronological mark. No-op until epoch is set. Ring-capped at TIMELINE_CAP.
function P:Mark(label, ms, kind)
    if not self._epoch then return end
    local t = (_G.debugprofilestop and _G.debugprofilestop() or 0) - self._epoch
    local tl = self._timeline
    tl[#tl + 1] = { t = t, label = label, ms = ms, kind = kind or "flush" }
    -- Drop the oldest if over cap (boot chain stays -- it's at the front, and
    -- we only trim once well past it).
    if #tl > self.TIMELINE_CAP then
        table.remove(tl, 1)
    end
end

function P:Reset()
    self._flush    = {}
    self._sel      = {}
    self._op       = {}
    self._stage    = {}
    self._timeline = {}
    -- epoch NOT cleared: fixed t-zero for the session even after Reset.
end

-- ===== Report ==============================================================

-- Sort a bucket's entries into a list ordered by total time descending.
local function _sortedEntries(bucket)
    local list = {}
    for key, e in pairs(bucket) do
        list[#list + 1] = { key = key, count = e.count, total = e.total,
                            max = e.max, subs = e.subs }
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end

-- minTotal: optional ms floor; rows below it are hidden (noise). Hidden count summarized.
local function _appendSection(lines, title, bucket, showSubs, minTotal)
    local entries = _sortedEntries(bucket)
    lines[#lines + 1] = title
    if #entries == 0 then
        lines[#lines + 1] = "  (no samples)"
        return
    end
    -- Header. Columns: total ms, count, avg ms, max ms, [subs], key.
    lines[#lines + 1] = showSubs
        and string.format("  %9s %6s %8s %8s %5s  %s", "total", "n", "avg", "max", "subs", "action")
        or  string.format("  %9s %6s %8s %8s  %s", "total", "n", "avg", "max", "selector")
    local hidden = 0
    for _, e in ipairs(entries) do
        if minTotal and e.total < minTotal then
            hidden = hidden + 1
        else
            local avg = e.total / e.count
            if showSubs then
                lines[#lines + 1] = string.format("  %8.1fms %6d %7.2fms %7.2fms %5s  %s",
                    e.total, e.count, avg, e.max, tostring(e.subs or "?"), e.key)
            else
                lines[#lines + 1] = string.format("  %8.1fms %6d %7.2fms %7.2fms  %s",
                    e.total, e.count, avg, e.max, e.key)
            end
        end
    end
    if hidden > 0 then
        lines[#lines + 1] = string.format("  (+%d more under %.2fms total -- hidden)", hidden, minTotal)
    end
end

-- Boot timeline: t+ = wall-clock since epoch (includes idle/async gaps); [cost] = step CPU.
-- rtt rows show external round-trip. Split lets you distinguish wait vs our processing.
local function _appendTimeline(lines, timeline)
    lines[#lines + 1] = "Boot timeline (epoch = OnInitialize; t+ = wall-clock, [..] = step cost):"
    if #timeline == 0 then
        lines[#lines + 1] = "  (no marks -- enable before login + /reload to capture boot)"
        return
    end
    local prevT = 0
    for _, m in ipairs(timeline) do
        local gap = m.t - prevT
        prevT = m.t
        -- Flag the rows that are mostly external/idle wait (big gap, little cost)
        -- so a 500ms catalog round-trip doesn't read as our cost.
        local costStr = m.ms and string.format("[%7.2fms]", m.ms) or "[   event ]"
        local tag = (m.kind == "rtt") and "  <ext RTT>"
                 or ((gap > 50 and (not m.ms or m.ms < gap * 0.25)) and "  <waited>" or "")
        lines[#lines + 1] = string.format("  t+%8.1fms (+%6.1f)  %s  %s%s",
            m.t, gap, costStr, m.label, tag)
    end
    lines[#lines + 1] = string.format("  --- %.1fms total from epoch to last mark ---", prevT)
end

-- Build the full perf report as a newline-joined string.
function P:Report()
    local lines = { "HDG Performance Profile",
                    "====================================================================" }
    if not self:Enabled() then
        lines[#lines + 1] = "(perf timing is OFF -- enable with: /hdgr perf on)"
    end
    _appendTimeline(lines, self._timeline)
    lines[#lines + 1] = ""
    _appendSection(lines, "Dispatch flush cost (deferred selector+binding+layout+paint):",
                   self._flush, true)
    lines[#lines + 1] = ""
    -- 0.05ms floor: anything below rounds to 0.0ms total -- pure noise, hidden.
    _appendSection(lines, "Per-selector cost (HDG.Selectors:Call):", self._sel, false, 0.05)
    lines[#lines + 1] = ""
    _appendSection(lines, "Module ops (work OUTSIDE the dispatch path -- catalog sweep, etc.):",
                   self._op, false)
    lines[#lines + 1] = ""
    _appendSection(lines, "Refresh pipeline stages (per-stage cost inside runPipeline):",
                   self._stage, false)
    return table.concat(lines, "\n")
end

-- ===== Dedicated window ====================================================
-- Large/tall scrollable report (lazy-singleton, themed, draggable, InputScrollFrame).
-- No C_Timer auto-refresh: user clicks Refresh after an action, or Reset + Refresh.

-- Repaint the window's edit box from the current report.
function P:_RepaintWindow()
    local w = self._window
    if w and w._edit then
        w._edit:SetText(self:Report())
        w._edit:SetCursorPosition(0)
    end
end

function P:Window()
    if self._window then return self._window end
    if not (_G.CreateFrame and _G.UIParent) then return nil end  -- exception(boundary): headless tests

    local f = _G.CreateFrame("Frame", "HDGR_PerfWindow", _G.UIParent, "BackdropTemplate")
    f:SetSize(870, 600)   -- large + tall, per request (+150w for long action keys)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    HDG.Theme:Register(f, "Frame")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 12, -10)
    HDG.UI.applyFontRole(title, "heading")
    HDG.Theme:Register(title, "Text")
    title:SetText("HDG Performance Profile")

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    HDG.UI.applyFontRole(hint, "small")
    hint:SetText("Click something in HDG, then Refresh. Reset zeros the stats. Ctrl+C to copy.")
    HDG.Theme:Register(hint, "TextDim")

    -- Scrollable report body; bottom edge leaves room for button row.
    local sf = _G.CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -50)
    sf:SetPoint("BOTTOMRIGHT", -12, 44)
    if sf.CharCount then sf.CharCount:Hide() end  -- exception(boundary): CharCount is an InputScrollFrameTemplate sub-widget; absent in some Blizzard template versions
    HDG.Theme:Register(sf, "EditBox")
    local edit = sf.EditBox
    if edit then
        edit:SetAutoFocus(false)
        edit:SetMultiLine(true)
        edit:SetMaxLetters(0)
        edit:SetJustifyH("LEFT")
        HDG.UI.applyFontRole(edit, "body")
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
    end
    sf:HookScript("OnSizeChanged", function(self_, w)
        if self_.EditBox and self_.EditBox.SetWidth then
            self_.EditBox:SetWidth(math.max(1, (w or 0) - 24))
        end
    end)
    f._edit = edit

    -- Button row: Refresh | Reset | Close (right-aligned).
    local close = HDG.UI:Button(f, "Close", "small")
    close:SetSize(80, 22); close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() f:Hide() end)

    local reset = HDG.UI:Button(f, "Reset", "small")
    reset:SetSize(80, 22); reset:SetPoint("RIGHT", close, "LEFT", -8, 0)
    reset:SetScript("OnClick", function() P:Reset(); P:_RepaintWindow() end)

    local refresh = HDG.UI:Button(f, "Refresh", "small")
    refresh:SetSize(80, 22); refresh:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    refresh:SetScript("OnClick", function() P:_RepaintWindow() end)

    self._window = f
    return f
end

-- Open (or re-open) the perf window, repainting with current stats.
function P:OpenWindow()
    local w = self:Window()
    if not w then return end
    self:_RepaintWindow()
    w:Show()
end

-- ===== Slash command =======================================================
-- /hdgr perf [on|off|reset]. Writes HDG_DB.perf directly (survives /reload).
-- Routed via Init's slash handler.

local function _print(msg)
    if _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[HDG Perf]|r " .. msg)
    end
end

local function _setPerf(on)
    _G.HDG_DB = _G.HDG_DB or {}  -- exception(boundary): SV lazy-created on fresh accounts
    _G.HDG_DB.perf = on or nil    -- nil when off (no lingering flag)
end

function P:Command(msg)
    local arg = HDG.Format.Trim((msg or ""):lower())
    if arg == "on" then
        _setPerf(true)
        _print("perf ON")
    elseif arg == "off" then
        _setPerf(false)
        _print("perf OFF")
    elseif arg == "reset" then
        P:Reset()
        if P._window and P._window:IsShown() then P:_RepaintWindow() end  -- exception(nullable): P._window is nil until first perf window open
        _print("stats cleared")
    else
        -- Bare /hdgr perf -> open window; chat dump fallback if frames unavailable.
        if _G.CreateFrame then
            P:OpenWindow()
        else
            for line in (P:Report() .. "\n"):gmatch("(.-)\n") do _print(line) end
        end
    end
end
