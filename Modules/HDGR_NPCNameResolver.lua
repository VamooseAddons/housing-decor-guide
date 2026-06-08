-- HDG.NPCNameResolver
-- ============================================================================
-- Localized NPC name via C_TooltipInfo.GetHyperlink. No async event for
-- arbitrary creature IDs; retry sync, memoize successes, fallback to DB name.
-- exception(boundary): GetHyperlink can return tainted secret-string objects under combat;
-- the full probe MUST be pcall-wrapped (not just the API call) -- 12.0.5+.
-- Selectors declare calls = {"NPCNameResolver:ResolveName"}.

HDG = HDG or {}
HDG.NPCNameResolver = HDG.NPCNameResolver or {}
local R = HDG.NPCNameResolver

-- Log tag for C_TooltipInfo.GetHyperlink boundary failures (secret-string
-- taint per Reference/MIDNIGHT_SECRET_VALUES.md).
HDG.Log:RegisterTags({ npc_resolver = { user = false, level = "warn" } })

R._cache = R._cache or {}   -- [npcID] = resolvedLocalizedName

-- ResolveName: cached localized name -> fresh API probe -> fallbackName -> "npc <id>".
function R:ResolveName(npcID, fallbackName)
    if not npcID then return fallbackName or "?" end
    local cached = self._cache[npcID]
    if cached then return cached end

    -- Full pcall: accessing .lines/.leftText on a secret-string-backed table also throws.
    local ok, result = pcall(function()
        local data = C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-0-" .. npcID)
        if data and data.lines and data.lines[1] then
            return data.lines[1].leftText
        end
        return nil
    end)
    if not ok then
        HDG.Log:Warn("npc_resolver",
            "GetHyperlink secret-taint for npcID=" .. tostring(npcID) .. ": " .. tostring(result))
    end

    if ok and result and result ~= "" then
        self._cache[npcID] = result
        return result
    end

    -- Don't cache fallback (next session may have client data).
    return fallbackName or ("npc " .. tostring(npcID))
end

HDG.Modules:Declare({
    name = "NPCNameResolver",
    dependencies = {},
})
