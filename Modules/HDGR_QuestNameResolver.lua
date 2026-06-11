-- HDG.QuestNameResolver
-- ============================================================================
-- Mirror of HDG.ItemNameResolver for quest titles. C_QuestLog.GetTitleForQuestID
-- returns nil for quests whose data hasn't been client-loaded yet; calling
-- C_QuestLog.RequestLoadQuestByID fires QUEST_DATA_LOAD_RESULT once the title
-- is available.
--
-- Selectors that read quest titles route through ResolveTitle so the impure
-- API call is localized here. Cache misses queue an async load + return the
-- "quest N" fallback. When the QUEST_DATA_LOAD_RESULT batch drains, we
-- dispatch QUEST_INFO_RESOLVED which bumps session.resolvers.questNames.tick;
-- consumers listing that path in `reads` invalidate + repaint with the
-- now-cached title.

HDG = HDG or {}
HDG.QuestNameResolver = HDG.QuestNameResolver or {}
local R = HDG.QuestNameResolver

R._cache            = R._cache            or {}     -- [questID] = title (resolved)
R._pending          = R._pending          or {}     -- [questID] = true (deduped batch)
R._requested        = R._requested        or {}     -- [questID] = true (load already requested)
R._tick             = R._tick             or 0  -- exception(false-positive): idempotent module-load init
R._timerScheduled   = R._timerScheduled   or false

R.BATCH_WINDOW = 0.5

function R:GetTick() return self._tick end

-- Returns (title, resolved). `resolved` is true when the title came from
-- the cache / live API; false when we returned the "quest N" placeholder
-- and queued an async load.
function R:ResolveTitle(questID)
    if not questID or questID == 0 then return "", false end
    local cached = self._cache[questID]
    if cached then return cached, true end
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then
        self._cache[questID] = title
        return title, true
    end
    if not self._requested[questID] then
        self._requested[questID] = true
        C_QuestLog.RequestLoadQuestByID(questID)
    end
    return "quest " .. tostring(questID), false
end

-- QUEST_DATA_LOAD_RESULT subscriber. Two-arg event: (questID, success).
-- Gotcha: QUEST_DATA_LOAD_RESULT fires for EVERY quest any system loads
-- (Blizzard UI, other addons, world quests). Filter to _requested only.
function R:OnQuestDataLoadResult(questID, success)
    if not (questID and success) then return end
    if not self._requested[questID] then return end
    self._pending[questID] = true
    if self._timerScheduled then return end
    self._timerScheduled = true
    C_Timer.After(self.BATCH_WINDOW, function() R:Drain() end)
end

function R:Drain()
    self._timerScheduled = false
    local batch = self._pending
    self._pending = {}
    self._tick = self._tick + 1
    local list, titles, count = {}, {}, 0
    for questID in pairs(batch) do
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if title and title ~= "" then self._cache[questID] = title end
        count = count + 1
        list[count] = questID
        -- titles is log-only (reducer ignores payload, just bumps tick).
        -- "<loading>" until RequestLoadQuestByID fills on a later drain.
        titles[questID] = self._cache[questID] or "<loading>"
    end
    if count > 0 then
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.QUEST_INFO_RESOLVED,
            payload = { questIDs = list, titles = titles, count = count },
        })
    end
    return batch
end

-- IsComplete: is this quest flagged completed for the player? questID is a
-- single number OR { ids } variant set (A/H / version / campaign-per-zone);
-- any variant completing = true. C_QuestLog.IsQuestFlaggedCompleted is sync
-- + cheap; QUEST_TURNED_IN bumps session.resolvers.questStatus.tick for repaint.
-- Selectors MUST declare reads = { "session.resolvers.questStatus.tick" }.
function R:IsComplete(questID)
    if not questID then return nil end
    if type(questID) == "table" then
        for _, id in ipairs(questID) do
            if C_QuestLog.IsQuestFlaggedCompleted(id) then return true end
        end
        return false
    end
    return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
end

-- Scan quest-sourced decor for completed quests; persist unattributed ones
-- (first char to record wins). Per-character -- builds account-wide set as
-- you log onto alts. row.questID is a number OR {ids} variant set.
function R:RecordCompletions()
    local obs = HDG.HousingCatalogObserver
    if not (obs and obs.byDecorID) then return end
    local state    = HDG.Store:GetState()
    local identity = state.session.identity
    local name     = identity.name               -- session.identity is factory-seeded (strict read)
    if not name or name == "" then return end   -- exception(boundary): empty until SessionIdentity resolves
    local class    = identity.classFile
    local recorded = state.account.questCompletions
    local batch
    local function tryRecord(qid)
        if qid and not recorded[qid] and C_QuestLog.IsQuestFlaggedCompleted(qid) then
            batch = batch or {}
            batch[qid] = { name = name, class = class }
        end
    end
    for _, row in pairs(obs.byDecorID) do
        local qid = row.questID
        if type(qid) == "table" then
            for _, id in ipairs(qid) do tryRecord(id) end
        else
            tryRecord(qid)
        end
    end
    if batch then
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.QUEST_COMPLETION_RECORDED,
            payload = { completions = batch },
        })
    end
end

-- QUEST_TURNED_IN(questID, ...) -> repaint open quest-completion surfaces, then
-- record the (possibly newly-completed) decor quests for this character.
function R:OnQuestTurnedIn(questID)
    if not questID then return end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.QUEST_STATUS_RESOLVED,
        payload = { questID = questID },
    })
    R:RecordCompletions()
end

HDG.Modules:Declare({
    name = "QuestNameResolver",
    dependencies = {},
    ownsBlizzardNamespaces = { "C_QuestLog" },   -- ADR-011: sole owner
    blizzardEvents = {
        QUEST_DATA_LOAD_RESULT = { handler = "OnQuestDataLoadResult",
                                   requiresMainWindow = true },
        QUEST_TURNED_IN        = { handler = "OnQuestTurnedIn",
                                   requiresMainWindow = true },
    },
    OnQuestDataLoadResult = function(self, questID, success)
        R:OnQuestDataLoadResult(questID, success)
    end,
    OnQuestTurnedIn = function(self, questID)
        R:OnQuestTurnedIn(questID)
    end,
    onEnable = function(self)
        -- Scan on catalog-ready, then re-scan on each turn-in.
        -- Together they build the account-wide completion set across alts.
        HDG.Store:Subscribe(function(actionType)
            if actionType == HDG.Constants.ACTIONS.DECOR_CATALOG_READY then
                R:RecordCompletions()
            end
        end)
    end,
})
