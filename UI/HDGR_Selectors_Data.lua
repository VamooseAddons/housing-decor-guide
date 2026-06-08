-- HDG.Selectors -- Your Data tab
-- ============================================================================
-- Section feeds for the data.allRows scrollbox:
--   1. Achievements  -- decor + coupon + lumber farming milestone rows
--   2. Craft history -- account.craft.history.entries ring buffer
--
-- All selectors are PURE. Blizzard achievement API reads flow through
-- AchievementObserver:GetCriteria(id, idx) -> {qty, reqQty} | nil.

HDG = HDG or {}
HDG.Selectors = HDG.Selectors or {}
local Selectors = HDG.Selectors

-- ============================================================================
-- Helpers
-- ============================================================================

local function _formatTimestamp(ts)
    if not ts or ts == 0 then return "" end
    -- exception(boundary): legacy farming sessions stored GetTime() (client uptime) not epoch;
    -- real epochs are > 1e9 (Sep 2001), smaller values treated as undated.
    if ts < 1e9 then return "" end
    if _G.date then return _G.date("%Y-%m-%d %H:%M", ts) end
    return tostring(ts)
end

local function _formatDuration(secs)
    if not secs or secs <= 0 then return "0s" end
    if secs < 60 then return string.format("%ds", math.floor(secs)) end
    if secs < 3600 then
        return string.format("%dm %ds", math.floor(secs / 60), math.floor(secs % 60))
    end
    return string.format("%dh %dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
end

-- Build O(1) lumberID->row map from LUMBER_DATA array.
local function _lumberByID()
    local out = {}
    for _, row in ipairs(HDG.Constants.LUMBER_DATA) do
        out[row.id] = row
    end
    return out
end

-- ============================================================================
-- Section 1: Achievements (collapsible groups)
-- ============================================================================
-- collapse tri-state per group (session.ui.data.collapse_<group>):
--   nil -> AUTO: fully-earned group starts collapsed
--   true -> user collapsed   false -> user expanded
-- User override always wins over AUTO.

local function _groupCollapsed(state, groupKey, earnedCount, totalCount)
    local override = state.session.ui.data["collapse_" .. groupKey]
    if override ~= nil then return override end
    return totalCount > 0 and earnedCount == totalCount   -- AUTO: done -> collapsed
end

-- Emit one collapsible group: header + (optionally) child rows. `buildChild`
-- returns the child ed for one source entry and whether it is earned.
local function _emitGroup(rows, state, groupKey, label, sourceList, buildChild)
    local children, earnedCount = {}, 0
    for _, src in ipairs(sourceList) do
        local child, earned = buildChild(src)
        if child then
            children[#children + 1] = child
            if earned then earnedCount = earnedCount + 1 end
        end
    end
    local total     = #children
    local collapsed = _groupCollapsed(state, groupKey, earnedCount, total)
    rows[#rows + 1] = {
        kind        = "achieveHeader",
        label       = label,
        groupKey    = groupKey,
        collapsed   = collapsed,
        earnedCount = earnedCount,
        totalCount  = total,
    }
    if not collapsed then
        for _, c in ipairs(children) do rows[#rows + 1] = c end
    end
end

local function _decorChild(a)
    local obs      = HDG.AchievementObserver
    local earned   = obs:IsEarned(a.id)
    local criteria = obs:GetCriteria(a.id, 1)
    return {
        kind = "achieveRow", group = "decor", id = a.id, threshold = a.threshold,
        earned = earned,
        qty    = criteria and criteria.qty    or 0,
        reqQty = criteria and criteria.reqQty or a.threshold,
    }, earned
end

local function _couponChild(a)
    local obs      = HDG.AchievementObserver
    local earned   = obs:IsEarned(a.id)
    local criteria = obs:GetCriteria(a.id, 1)
    return {
        kind = "achieveRow", group = "coupon", id = a.id, threshold = a.threshold,
        earned = earned,
        qty    = criteria and criteria.qty    or 0,
        reqQty = criteria and criteria.reqQty or a.threshold,
    }, earned
end

local function _lumberChild(lumber)
    if not lumber.achieveID then return nil, false end
    local obs      = HDG.AchievementObserver
    local earned   = obs:IsEarned(lumber.achieveID)
    local criteria = obs:GetCriteria(lumber.achieveID, 1)
    return {
        kind = "lumberAchieveRow", group = "lumber", id = lumber.achieveID,
        lumberID = lumber.id, lumberName = lumber.shortName or lumber.name,
        expansion = lumber.expansion, earned = earned,
        qty    = criteria and criteria.qty    or 0,
        reqQty = criteria and criteria.reqQty or 250,
    }, earned
end

Selectors:Register("data.achievementsData", {
    reads = { "session.achievementStatus.tick", "session.ui.data" },
    fn = function(state)
        local rows = {}
        rows[#rows + 1] = { kind = "sectionHeader", label = "Achievements" }
        _emitGroup(rows, state, "decor",  "Housing Decor Milestones",
                   HDG.Constants.DECOR_ACHIEVEMENTS,  _decorChild)
        _emitGroup(rows, state, "coupon", "Community Coupon Milestones",
                   HDG.Constants.COUPON_ACHIEVEMENTS, _couponChild)
        _emitGroup(rows, state, "lumber", "Lumber Farming Milestones",
                   HDG.Constants.LUMBER_DATA,         _lumberChild)
        return rows
    end,
})

-- ============================================================================
-- Dashboard KPI value selectors (statCard `value` bindings; labels static in
-- LayoutConfig). Collection/catalog stats live on the House tab, not here.
-- ============================================================================

local function _achievementTotals(state)
    local _ = state.session.achievementStatus.tick
    local obs = HDG.AchievementObserver
    local earned, total = 0, 0
    for _, a in ipairs(HDG.Constants.DECOR_ACHIEVEMENTS) do
        total = total + 1; if obs:IsEarned(a.id) then earned = earned + 1 end
    end
    for _, a in ipairs(HDG.Constants.COUPON_ACHIEVEMENTS) do
        total = total + 1; if obs:IsEarned(a.id) then earned = earned + 1 end
    end
    for _, l in ipairs(HDG.Constants.LUMBER_DATA) do
        if l.achieveID then
            total = total + 1; if obs:IsEarned(l.achieveID) then earned = earned + 1 end
        end
    end
    return earned, total
end

Selectors:Register("data.kpiAchievements", {
    reads = { "session.achievementStatus.tick" },
    fn = function(state)
        local earned, total = _achievementTotals(state)
        return string.format("%d / %d", earned, total)
    end,
})

Selectors:Register("data.kpiAcquired", {
    reads = { "account.craft.history.entries" },
    fn = function(state)
        local n = 0
        for _, e in ipairs(state.account.craft.history.entries) do
            n = n + ((e.qty and e.qty > 0) and e.qty or 1)
        end
        return HDG.Format.FormatAmount(n)
    end,
})

Selectors:Register("data.kpiFarmSessions", {
    reads = { "account.lumber.history.entries" },
    fn = function(state)
        return tostring(#state.account.lumber.history.entries)
    end,
})

Selectors:Register("data.kpiLumber", {
    reads = { "account.lumber.history.entries" },
    fn = function(state)
        local n = 0
        for _, e in ipairs(state.account.lumber.history.entries) do
            n = n + (e.sessionTotal or 0)
        end
        return HDG.Format.FormatAmount(n)
    end,
})

-- ============================================================================
-- Section 2: Craft / acquisition history
-- ============================================================================

Selectors:Register("data.craftHistoryRows", {
    reads = { "account.craft.history.entries" },
    fn = function(state)
        local rows  = {}
        rows[#rows + 1] = { kind = "sectionHeader", label = "Craft & Acquisition History" }
        local entries = state.account.craft.history.entries
        -- qty=N emits N rows (flat log, newest first). Ring buffer is oldest-first;
        -- `idx` makes keys unique across qty-expanded duplicates of the same entry.
        local idx = 0
        for i = #entries, 1, -1 do
            local e = entries[i]
            local qty = (e.qty and e.qty > 0) and e.qty or 1
            local dateStr = _formatTimestamp(e.timestamp)
            for _ = 1, qty do
                idx = idx + 1
                rows[#rows + 1] = {
                    kind      = "craftHistRow",
                    eventType = e.eventType,
                    itemID    = e.itemID,
                    recipeID  = e.recipeID,
                    dateStr   = dateStr,
                    idx       = idx,
                }
            end
        end
        if #entries == 0 then
            rows[#rows + 1] = { kind = "emptyRow", label = "No craft history recorded yet." }
        end
        return rows
    end,
})

-- ============================================================================
-- Section 3: Farming history (kept for allRows sub-selector; not in allRows' output)
-- ============================================================================

Selectors:Register("data.farmingHistoryRows", {
    reads = { "account.lumber.history.entries" },
    fn = function(state)
        local rows  = {}
        rows[#rows + 1] = { kind = "sectionHeader", label = "Lumber Farming History" }
        local entries = state.account.lumber.history.entries
        local byID    = _lumberByID()
        -- Render newest first.
        for i = #entries, 1, -1 do
            local e    = entries[i]
            local info = byID[e.lumberID]
            local dur  = (e.finalizedAt and e.startedAt)
                         and _formatDuration(e.finalizedAt - e.startedAt) or ""
            rows[#rows + 1] = {
                kind         = "farmHistRow",
                id           = e.id,   -- unique row key (lumberName+minute collides)
                lumberName   = info and (info.shortName or info.name) or tostring(e.lumberID),
                expansion    = info and info.expansion or "",
                sessionTotal = e.sessionTotal or 0,
                duration     = dur,
                zone         = e.zone or "",
                character    = e.character or "",
                dateStr      = _formatTimestamp(e.startedAt),
            }
        end
        if #entries == 0 then
            rows[#rows + 1] = { kind = "emptyRow", label = "No farming sessions recorded yet." }
        end
        return rows
    end,
})

-- ============================================================================
-- Composite: achievements + craft history for the scrollbox.
-- Dashboard KPIs carry headline activity numbers.
-- ============================================================================

Selectors:Register("data.allRows", {
    reads = {
        "session.achievementStatus.tick",
        "session.ui.data",
        "account.craft.history.entries",
    },
    calls = {
        "data.achievementsData",
        "data.craftHistoryRows",
    },
    fn = function(state, ctx)
        local out = {}
        for _, r in ipairs(Selectors:Call("data.achievementsData",  state, ctx)) do out[#out + 1] = r end
        for _, r in ipairs(Selectors:Call("data.craftHistoryRows",  state, ctx)) do out[#out + 1] = r end
        return out
    end,
})
