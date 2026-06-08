-- HDG.AchievementObserver
-- ============================================================================
-- Owns the player achievement-completion read and exposes a live "earned"
-- check for an achievementID. Mirror of HDG.QuestNameResolver's status half:
-- achievement completion is DYNAMIC per-character game state (the player earns
-- it mid-session with no catalog event), so it is NOT baked at catalog sweep --
-- it is read live in the selector, gated by a tick this module bumps.
--
--   ACHIEVEMENT_EARNED  -> OnAchievementEarned -> dispatch ACHIEVEMENT_STATUS_RESOLVED
--      -> session.achievementStatus.tick++  -> [ACH] earned-checkmark selectors re-run
--      -> selector calls AchievementObserver:IsEarned(achievementID)  (live read)
--
-- This is the §1 boundary pattern: selectors stay pure (they read the tick +
-- call this observer method); the live GetAchievementInfo read happens behind
-- this module's boundary. §13: sole owner of the C_AchievementInfo namespace.
--
-- Public API:
--   HDG.AchievementObserver:IsEarned(achievementID) -> bool
--   Selectors that show the earned checkmark declare
--   reads = { "session.achievementStatus.tick" } and call IsEarned(...).

HDG = HDG or {}
HDG.AchievementObserver = HDG.AchievementObserver or {}
local R = HDG.AchievementObserver

-- Live earned-state for an achievement. `achievementID` is a single number
-- (ItemAugment type=1 carries one inline). IsValidAchievement guards
-- fabricated / wrong-faction IDs -> false (no checkmark) rather than a
-- GetAchievementInfo error. Sync + cheap, so no cache; ACHIEVEMENT_EARNED
-- bumps session.achievementStatus.tick to repaint.
function R:IsEarned(achievementID)
    if not achievementID then return false end
    -- exception(boundary): invalid / cross-faction IDs are "not earned" for our purposes.
    if not C_AchievementInfo.IsValidAchievement(achievementID) then return false end
    local completed = select(4, GetAchievementInfo(achievementID))  -- exception(boundary): achievement API nil for invalid ID
    return completed and true or false
end

-- Progress query for one achievement criteria (criteriaIndex 1-based).
-- Returns { qty, reqQty } or nil when the achievement is unknown / invalid.
-- GetAchievementCriteriaInfo(achievementID, criteriaIndex) ->
--   criteriaString, criteriaType, completed, quantity, reqQuantity, ...
-- exception(boundary): pcall because the global can return nil on invalid IDs; caller
-- should treat nil return as "no data available".
function R:GetCriteria(achievementID, criteriaIndex)
    if not achievementID then return nil end
    -- exception(boundary): invalid / cross-faction IDs -- treat as no data.
    if not _G.C_AchievementInfo.IsValidAchievement(achievementID) then return nil end
    local ok, _, _, _, qty, reqQty = pcall(_G.GetAchievementCriteriaInfo, achievementID, criteriaIndex or 1)  -- exception(boundary): GetAchievementCriteriaInfo can error on cross-faction / invalid IDs
    if not ok or qty == nil then return nil end
    return { qty = qty, reqQty = reqQty or 0 }
end

-- Achievement display name (for tooltips). nil on invalid / cross-faction IDs.
function R:GetName(achievementID)
    if not achievementID then return nil end
    if not C_AchievementInfo.IsValidAchievement(achievementID) then return nil end  -- exception(boundary): achievement API nil for invalid ID
    return (select(2, GetAchievementInfo(achievementID)))   -- exception(boundary): index 2 = name
end

-- ACHIEVEMENT_EARNED(achievementID, alreadyEarned) -> repaint open
-- achievement-completion surfaces. Bump on any earn; selectors re-read live.
function R:OnAchievementEarned(achievementID)
    if not achievementID then return end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.ACHIEVEMENT_STATUS_RESOLVED,
        payload = { achievementID = achievementID },
    })
end

HDG.Modules:Declare({
    name = "AchievementObserver",
    ownsBlizzardNamespaces = { "C_AchievementInfo" },
    dependencies = {},
    blizzardEvents = {
        ACHIEVEMENT_EARNED = { handler = "OnAchievementEarned",
                               requiresMainWindow = true },
    },
    OnAchievementEarned = function(self, achievementID)
        R:OnAchievementEarned(achievementID)
    end,
})
