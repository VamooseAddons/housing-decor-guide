-- HDG.SelectorCallLog
-- ============================================================================
-- One-shot debug instrumentation. Wraps Selectors:Call to record which
-- selectors actually fire at runtime, so we can validate the audit script's
-- "dead selectors" list against real usage.
--
-- The audit script (scripts/audit_selectors.py) flags ~57 selectors as
-- having no detected consumers, but static analysis misses dynamic patterns
-- (loop-generated bindings, string-concatenated Selectors:Call("prefix"..k)).
-- Runtime logging closes that gap: a selector with ZERO call counts after a
-- thorough play session is high-confidence-dead.
--
-- Usage:
--   /hdgr sl start    -- begin recording call counts
--   /hdgr sl stop     -- stop recording (counts preserved until next start)
--   /hdgr sl dump     -- print summary + save snapshot to HDG_DB
--   /hdgr sl clear    -- zero the counts
--
-- Workflow:
--   1. /hdgr sl start
--   2. Use the addon thoroughly -- open every tab, click everything, change
--      filters, switch schemes, place decor, etc.
--   3. /hdgr sl dump
--   4. Cross-reference HDG_DB._selectorCallLog.counts vs the audit's
--      selectors.csv -- selectors with 0 counts AND 0 static consumers are
--      high-confidence dead.
--
-- ZERO overhead when not enabled (no hook installed).
-- Removable -- delete this file + TOC line; no other code depends on it.

HDG = HDG or {}
HDG.SelectorCallLog = HDG.SelectorCallLog or {}
local SCL = HDG.SelectorCallLog

SCL.counts  = {}
SCL.enabled = false
SCL._origCall = nil

local function _ensureSelectors()
    return HDG.Selectors and type(HDG.Selectors.Call) == "function"
end

function SCL:Start()
    if self.enabled then
        print("HDG: selector call log already running")
        return
    end
    if not _ensureSelectors() then
        print("HDG: Selectors not loaded yet -- /hdgr sl start aborted")
        return
    end
    self.enabled = true
    -- Hook Selectors:Call. Preserve original; wrapper bumps counter.
    self._origCall = HDG.Selectors.Call
    HDG.Selectors.Call = function(slf, name, state, ctx)
        local counts = SCL.counts
        counts[name] = (counts[name] or 0) + 1
        return SCL._origCall(slf, name, state, ctx)
    end
    print("HDG: selector call log STARTED (use /hdgr sl dump to view + save)")
end

function SCL:Stop()
    if not self.enabled then
        print("HDG: selector call log not running")
        return
    end
    self.enabled = false
    if self._origCall then
        HDG.Selectors.Call = self._origCall
        self._origCall = nil
    end
    print("HDG: selector call log STOPPED (counts preserved)")
end

function SCL:Clear()
    self.counts = {}
    print("HDG: selector call log counts cleared")
end

function SCL:Dump()
    -- Sort by call count desc for readability.
    local rows = {}
    for name, n in pairs(self.counts) do rows[#rows + 1] = { name, n } end
    table.sort(rows, function(a, b)
        if a[2] == b[2] then return a[1] < b[1] end
        return a[2] > b[2]
    end)
    local total_calls = 0
    for _, r in ipairs(rows) do total_calls = total_calls + r[2] end
    print(string.format("HDG: %d distinct selectors called, %d total calls", #rows, total_calls))
    print("Top 10 most-called:")
    for i = 1, math.min(10, #rows) do
        print(string.format("  %5d  %s", rows[i][2], rows[i][1]))
    end
    -- Save snapshot to HDG_DB for offline analysis. Survives /reload.
    if HDG_DB then
        HDG_DB._selectorCallLog = {
            counts = self.counts,
            total_calls = total_calls,
            distinct_called = #rows,
            timestamp = (time and time()) or 0,
        }
        print("Saved to HDG_DB._selectorCallLog -- inspect after /reload via SavedVariables file:")
        print("  /Applications/World of Warcraft/_retail_/WTF/Account/<acct>/SavedVariables/HousingDecorGuide.lua")
    end
end

-- Routed via /hdgr sl <cmd> from Init's slash handler (no own registration).
function SCL:Command(cmd)
    cmd = (cmd or ""):lower():match("^%s*(%S*)") or ""
    if cmd == "start" then SCL:Start()
    elseif cmd == "stop"  then SCL:Stop()
    elseif cmd == "dump"  then SCL:Dump()
    elseif cmd == "clear" then SCL:Clear()
    else
        print("HDG Selector Call Log:")
        print("  /hdgr sl start   -- begin recording")
        print("  /hdgr sl stop    -- stop recording")
        print("  /hdgr sl dump    -- show summary + save to HDG_DB._selectorCallLog")
        print("  /hdgr sl clear   -- zero the counts")
    end
end
