-- HDG.RecipeKnowledgeScanner
-- ============================================================================
-- Snapshots `C_SpellBook.IsSpellKnown(spellID)` for every recipe in
-- HDGR_DecorDB and writes the result into `account.recipes[itemID]`.
-- Selectors (decor.craftableState) read account.recipes -- never call the
-- Blizzard API directly (ADR-003: selectors are pure).
--
-- Row shape produced per recipe:
--   selfKnown = bool   -- current character's spellbook
--   altKnown  = bool   -- OR'd from account.characters[charKey ~= current]
--                         .professions[*].knownRecipes (filled by alt scanner
--                         after CHARACTER_PROFESSION_UPDATED fires)
--
-- Two scan triggers:
--   1. DECOR_CATALOG_READY -- runs Scan() (full selfKnown + altKnown pass).
--      Once per session unless explicit reset.
--   2. CHARACTER_PROFESSION_UPDATED -- runs RecomputeAltKnown() which keeps
--      existing selfKnown but re-derives altKnown from the fresh
--      account.characters subtree.

HDG = HDG or {}
HDG.RecipeKnowledgeScanner = HDG.RecipeKnowledgeScanner or {}
local R = HDG.RecipeKnowledgeScanner

-- Built once per Scan(); avoids O(N) DB walk per row in decor.matchesTag
-- topFilter='crafted'. Keyed by spellID -> profession.
R._spellIDToProfession = R._spellIDToProfession or {}

function R:GetSpellIDToProfession()
    return self._spellIDToProfession
end

-- currentCharKey excluded from altKnown so self's knownRecipes don't OR in.

-- Reset altKnown + build spellID -> itemID reverse lookup. Single pass per computeAltKnown.
local function _resetAndIndexEntries(entries)
    local spellToItem = {}
    for itemID, entry in pairs(entries) do
        entry.altKnown = false
        if entry.spellID then spellToItem[entry.spellID] = itemID end
    end
    return spellToItem
end

-- Excludes current char (selfKnown is on the entry) and user-hidden chars.
local function _isAltContributor(char, charKey, current)
    return charKey ~= current
       and not char.hidden
       and type(char.professions) == "table"
end

-- OR one char's knownRecipes across all its professions into entries.
local function _orCharContributions(char, spellToItem, entries)
    for _, prof in pairs(char.professions) do
        local known = prof.knownRecipes
        if type(known) == "table" then
            for spellID in pairs(known) do
                local itemID = spellToItem[spellID]
                if itemID and entries[itemID] then
                    entries[itemID].altKnown = true
                end
            end
        end
    end
end

-- OR knownRecipes from all alts (excluding current + hidden) into entries[itemID].altKnown.
-- Reset before OR-ing so removed alts drop their contributions.
local function computeAltKnown(entries)
    local state      = HDG.Store:GetState()
    local characters = state.account.characters
    local current    = HDG.SessionIdentity.GetCharKey(state)

    local spellToItem = _resetAndIndexEntries(entries)
    for charKey, char in pairs(characters) do
        if _isAltContributor(char, charKey, current) then
            _orCharContributions(char, spellToItem, entries)
        end
    end
end

function R:Scan()
    -- Re-scan guard: DECOR_CATALOG_READY can fire twice (cold+warm paths).
    -- Subsequent fires are no-ops until _scanned is explicitly reset.
    if self._scanned then return 0 end
    local db = HDG.StaticData.Recipes:GetAll()
    if not (db and _G.C_SpellBook and _G.C_SpellBook.IsSpellKnown) then
        return 0
    end
    -- HDGR_DecorDB keyed by recipe item ID; recipe.itemID is the crafted decor
    -- item ID. account.recipes keyed by decor itemID for O(1) craftableState lookup.
    local entries = {}
    local spellMap = {}
    for _, recipe in pairs(db) do
        if type(recipe) == "table" and recipe.itemID and recipe.spellID then
            entries[recipe.itemID] = {
                spellID   = recipe.spellID,
                selfKnown = _G.C_SpellBook.IsSpellKnown(recipe.spellID) == true,
                altKnown  = false,   -- computeAltKnown below fills this
            }
            -- spellID never appears under two professions; last-writer-wins is safe.
            if recipe.profession then
                spellMap[recipe.spellID] = recipe.profession
            end
        end
    end
    computeAltKnown(entries)
    self._spellIDToProfession = spellMap
    self._scanned = true
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.RECIPE_KNOWLEDGE_UPDATED,
        payload = { entries = entries },
    })
    HDG.Log:Success("recipes_scanned",
        string.format("Recipe scan complete -- %d decor recipes indexed", count))
    -- One-shot per session: recipe vendors missing from VendorAugment (generated
    -- tables out of step). The facade computes (pure); this module logs -- the
    -- selectors that consume the join skip such vendors silently.
    if not self._driftChecked then
        self._driftChecked = true
        local n, sample = HDG.StaticData.Recipes:VendorAugmentGaps()
        if n > 0 then
            HDG.Log:Warn("data_drift", ("%d recipe vendor(s) missing from VendorAugment: %s%s")
                :format(n, table.concat(sample, ", "), n > 8 and ", ..." or ""))
        end
    end
    return count
end

-- Re-derive altKnown when an alt's knownRecipes update. Reads entries
-- directly from state.account.recipes (Scan wrote them there; by-reference
-- Flush means HDG_DB.account.recipes is the same table).
function R:RecomputeAltKnown()
    local state = HDG.Store:GetState()
    local entries = state.account.recipes
    if not entries or next(entries) == nil then return end
    computeAltKnown(entries)
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.RECIPE_KNOWLEDGE_UPDATED,
        payload = { entries = entries },
    })
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name = "RecipeKnowledgeScanner",
    dependencies = { "HousingCatalogObserver" },
    -- per ADR-011: declared owner of C_SpellBook.IsSpellKnown. ProfessionScanner
    -- + Mogul do stateless shared reads (sync, not event subscriptions).
    ownsBlizzardNamespaces = { "C_SpellBook.IsSpellKnown" },
    logTags = {
        recipes_scanned = { user = true, level = "success", duration = 3 },
        data_drift      = { user = false, level = "warn" },
    },
    onEnable = function(self)
        -- Run on DECOR_CATALOG_READY (fires after both cold+warm paths;
        -- spellbook is populated by then). Token captured for onShutdown.
        self._storeToken = HDG.Store:Subscribe(function(actionType)
            if actionType == HDG.Constants.ACTIONS.DECOR_CATALOG_READY then
                R:Scan()
            elseif actionType == HDG.Constants.ACTIONS.CHARACTER_PROFESSION_UPDATED then
                -- Alt's professions updated: re-derive altKnown.
                R:RecomputeAltKnown()
            end
        end)
    end,
    onShutdown = function(self)
        if self._storeToken then
            HDG.Store:Unsubscribe(self._storeToken)
            self._storeToken = nil
        end
    end,
})
