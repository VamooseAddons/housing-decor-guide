-- HDG.RepObserver
-- ============================================================================
-- Owns C_Reputation / C_MajorFactions / C_GossipInfo. Rep standing is
-- dynamic (advances on quest turn-in / token open) so live reads are gated
-- behind a tick: UPDATE_FACTION -> REP_PROGRESS_TICK -> session.rep.tick++
-- -> rep selectors re-run -> call GetProgress() (live read).
--
-- GetProgress(factionID, requiredCode)
--   -> { type, label, current, max, met, [isMax], [reaction] } | nil
--   type: "friendship" / "renown" / "standard"
--   met : true if standing >= requiredCode
--   isMax: renown-only -- true at max renown (gate always met)
-- Selectors declare reads = {"session.rep.tick"}.

HDG = HDG or {}
HDG.RepObserver = HDG.RepObserver or {}
local R = HDG.RepObserver

-- Log tag for the rep-API boundary (SECRET-value returns / cold-cache nil).
HDG.Log:RegisterTags({ rep_api = { user = false, level = "warn" } })

-- Priority: Friendship -> MajorFaction -> Standard (Blizzard's order).
-- Paragon intentionally skipped: decor gates are all <= Exalted.
-- Returns nil if factionID is invalid for all three types.
-- exception(boundary): Blizzard read-only APIs; consumers re-read via REP_PROGRESS_TICK.
function R:GetProgress(factionID, requiredCode)
    if not factionID then return nil end

    -- Friendship: some factions overlay friendship on a classic faction; API takes precedence.
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local fr = C_GossipInfo.GetFriendshipReputation(factionID)  -- exception(boundary): reputation API nil for non-rep / invalid faction
        if fr and fr.friendshipFactionID and fr.friendshipFactionID > 0 then
            -- Ranks are 1-based; requiredCode 9+ encodes rank as (code-8),
            -- matching the renown encoding (housing data uniform "13" = rank 5).
            local ranks = C_GossipInfo.GetFriendshipReputationRanks
                          and C_GossipInfo.GetFriendshipReputationRanks(factionID)  -- exception(boundary): reputation API nil for non-rep / invalid faction
            local level        = (ranks and ranks.currentLevel) or 0
            local maxLevel     = (ranks and ranks.maxLevel) or 0
            local requiredRank = (requiredCode and requiredCode >= 9) and (requiredCode - 8) or requiredCode or 0
            return {
                type    = "friendship",
                label   = fr.reaction or "",   -- current rank name (e.g. "Cordial")
                current = level,
                max     = maxLevel,
                met     = level >= requiredRank,
            }
        end
    end

    -- Renown
    if C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) then  -- exception(boundary): reputation API nil for non-rep / invalid faction
        local mf = C_MajorFactions and C_MajorFactions.GetMajorFactionData(factionID)  -- exception(boundary): reputation API nil for non-rep / invalid faction
        local level = (mf and mf.renownLevel) or 0
        -- requiredCode 9+ encodes Renown N where N = code-8. 0 = no requirement.
        local requiredRenown = (requiredCode and requiredCode >= 9) and (requiredCode - 8) or 0
        local isMax = C_MajorFactions and C_MajorFactions.HasMaximumRenown
                      and C_MajorFactions.HasMaximumRenown(factionID)
        return {
            type    = "renown",
            label   = "Renown " .. tostring(level),
            current = (mf and mf.renownReputationEarned) or 0,
            max     = (mf and mf.renownLevelThreshold) or 0,
            met     = isMax or level >= requiredRenown,
            isMax   = isMax,
        }
    end

    -- Standard 1-8
    local f = C_Reputation.GetFactionDataByID(factionID)  -- exception(boundary): reputation API nil for non-rep / invalid faction
    if not f then return nil end
    local thresh  = f.currentReactionThreshold or 0
    local nextThr = f.nextReactionThreshold or thresh
    return {
        type     = "standard",
        reaction = f.reaction or 0,
        label    = _G["FACTION_STANDING_LABEL" .. (f.reaction or 0)] or "",
        current  = (f.currentStanding or 0) - thresh,
        max      = nextThr - thresh,
        met      = (f.reaction or 0) >= (requiredCode or 0),
    }
end

-- ============================================================================
HDG.Modules:Declare({
    name = "RepObserver",
    ownsBlizzardNamespaces = { "C_Reputation", "C_MajorFactions", "C_GossipInfo" },
    dependencies = {},
    logTags = {
        rep_changed = { user = false, level = "debug" },
    },
    blizzardEvents = {
        -- Debounce the UPDATE_FACTION firehose (fires repeatedly per rep gain).
        UPDATE_FACTION                        = { handler = "OnRepChanged", debounce = 0.5 },
        MAJOR_FACTION_RENOWN_LEVEL_CHANGED    = { handler = "OnRepChanged" },
    },
    OnRepChanged = function(self)
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.REP_PROGRESS_TICK })
    end,
})
