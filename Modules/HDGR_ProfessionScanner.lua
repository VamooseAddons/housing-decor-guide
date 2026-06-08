-- HDG.ProfessionScanner
-- ============================================================================
-- Per-character profession scanner. Snapshots skill ladder + learned recipes
-- on TRADE_SKILL_LIST_UPDATE and dispatches CHARACTER_PROFESSION_UPDATED so
-- the reducer upserts account.characters[charKey].professions[profName].
--
-- Coverage: only the OPENED profession is scanned; both professions require
-- two visits (WoW doesn't expose alt profession data cross-character).
--
-- Debounce: TRADE_SKILL_LIST_UPDATE bursts 3-5 times during initial load;
-- 0.5s coalesces cleanly. Scan walk is ~1ms for a full profession (~900 recipes).

HDG = HDG or {}
HDG.ProfessionScanner = HDG.ProfessionScanner or {}
local PS = HDG.ProfessionScanner

-- Returns nil if SessionIdentity hasn't dispatched yet (boot window).
local function getCharIdentity(state)
    local id = state.session.identity
    if id.charKey == "" then return nil end
    return id
end

-- True if the player PERSONALLY OWNS this profession -- its skillLineID is one of
-- their GetProfessions() slots. The ownership gate for Scan: without it, opening a
-- GUILD / LINKED / inspected profession window (e.g. VGC's guild crafter opens
-- professions you don't know) records that profession against THIS character at
-- skill 0 -- the "professions you don't know" rows. This is old HDG's GetProfessions
-- gate (HDG_Data.lua `charHasProfession`) that the Lattice rewrite dropped.
-- base.professionID and GetProfessionInfo's 7th return (skillLine) share an ID space.
local function playerOwnsProfession(professionID)
    if not professionID then return false end
    -- exception(boundary): legacy GetProfessions absent (headless tests) -> can't
    -- verify ownership, so don't block recording.
    if not (_G.GetProfessions and _G.GetProfessionInfo) then return true end
    local function slotOwns(idx)
        if not idx then return false end
        local _, _, _, _, _, _, skillLine = _G.GetProfessionInfo(idx)
        return skillLine == professionID
    end
    local p1, p2, arch, fish, cook = _G.GetProfessions()
    return slotOwns(p1) or slotOwns(p2) or slotOwns(cook) or slotOwns(arch) or slotOwns(fish)
end

-- Pull {current, max} skill levels per expansion child of the open root profession.
local function readSkillLines()
    local out = {}
    local CT = _G.C_TradeSkillUI
    if not (CT and CT.GetChildProfessionInfos) then return out end
    local children = CT.GetChildProfessionInfos()
    if type(children) ~= "table" then return out end
    for _, info in ipairs(children) do
        local expName = info.expansionName or info.professionName
        if expName then
            out[expName] = {
                current = info.skillLevel    or 0,  -- exception(boundary): Blizz C_TradeSkillUI struct
                max     = info.maxSkillLevel or 0,  -- exception(boundary): Blizz C_TradeSkillUI struct
            }
        end
    end
    return out
end

-- Collect learned recipe IDs for the open profession. O(recipes); no memoization needed.
local function readKnownRecipes()
    local out = {}
    local CT = _G.C_TradeSkillUI
    if not (CT and CT.GetAllRecipeIDs and CT.GetRecipeInfo) then return out end
    local ids = CT.GetAllRecipeIDs()
    if type(ids) ~= "table" then return out end
    for _, recipeID in ipairs(ids) do
        local info = CT.GetRecipeInfo(recipeID)
        if info and info.learned then
            out[recipeID] = true
        end
    end
    return out
end

function PS:Scan()
    local CT = _G.C_TradeSkillUI
    if not (CT and CT.IsTradeSkillReady and CT.IsTradeSkillReady()) then return end  -- exception(boundary): profession window not open
    if not (CT.GetBaseProfessionInfo) then return end
    local base = CT.GetBaseProfessionInfo()
    if not (base and base.professionName and base.professionName ~= "") then return end
    -- Ownership gate (old HDG parity): only record professions THIS character
    -- actually owns. Skips guild/linked/inspected profession windows -- otherwise
    -- viewing someone else's profession records it against the player at skill 0.
    if not playerOwnsProfession(base.professionID) then return end
    local ident = getCharIdentity(HDG.Store:GetState())
    if not ident then return end
    -- Find Lumber awareness stamped here (profession-window context) to avoid
    -- a dedicated SPELLS_CHANGED listener for a single spell. Stale until the
    -- next scan if learned after the last profession open. Spell ID 1256697.
    local knowsFindLumber = false
    if _G.C_SpellBook and _G.C_SpellBook.IsSpellKnown then
        knowsFindLumber = _G.C_SpellBook.IsSpellKnown(1256697) or false
    end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.CHARACTER_PROFESSION_UPDATED,
        payload = {
            charKey         = ident.charKey,
            name            = ident.name,
            realm           = ident.realm,
            class           = ident.class,
            classFile       = ident.classFile,
            profName        = base.professionName,
            skillLines      = readSkillLines(),
            knownRecipes    = readKnownRecipes(),
            knowsFindLumber = knowsFindLumber,
        },
    })
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name = "ProfessionScanner",
    dependencies = {},
    -- per ADR-011: sole owner of C_TradeSkillUI. C_SpellBook.IsSpellKnown
    -- below is a stateless shared read; RecipeKnowledgeScanner owns it.
    ownsBlizzardNamespaces = { "C_TradeSkillUI" },
    blizzardEvents = {
        -- Initial list ready + recipe-learned updates.
        TRADE_SKILL_LIST_UPDATE         = { handler = "OnListUpdate", debounce = 0.5 },
        -- Expansion sub-tab switch inside one profession; re-scan so skill
        -- ladder reflects the active child.
        TRADE_SKILL_DATA_SOURCE_CHANGED = { handler = "OnListUpdate", debounce = 0.5 },
    },
    OnListUpdate = function(self)
        PS:Scan()
    end,
})
