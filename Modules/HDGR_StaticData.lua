-- HDG.StaticData
-- ============================================================================
-- Facade for build-pipeline-generated data tables shipped in TOC-loaded Lua
-- files (immutable within a session). See ADR-003c.
--
-- Rules:
--   1. Selectors call HDG.StaticData.<Domain>:<accessor>() -- never _G.HDGR_*DB directly.
--   2. Selectors declare reads = {"session.staticData.tick"} (always 0 today;
--      reserves space for future hot-reload override).
--   3. Tests stub HDG.StaticData.<Domain> to inject fixtures.
--
-- Wrapped tables (all loaded via TOC before this module):
--   HDGR_VendorAugment         -> VendorAugment:Get / ResolveName / GetVendorsByMap
--   HDGR_ItemAugment           -> ItemAugment:Get  (sparse; rep gates + sourceType)
--   HDGR_DecorDB               -> Recipes:Get / GetAll  (recipe-backed subset)
--   HDGR_ProfessionsDB         -> Professions:GetRecipe / GetAll
--   HDGR_ProfessionThresholds  -> Professions:GetThresholds
--   HDGR_ReagentsDB            -> Reagents:Get / GetAll
--   HDGR_FacetDB               -> Facets:Get / GetAll
--   HDGR_FacetVocab            -> Facets:GetVocab
--   HDGR_StyleDefinitions      -> Styles:GetDefinitions
--   HDGR_CollectionDefinitions -> Collections:GetDefinitions
--   HDGR_TrainersDB            -> Trainers:GetAll / GetByProfession / GetByProfessionAndExpansion
--   HDGR_HouseTab_TitleTiers     -> TitleTiers:GetAll
--   HDGR_HouseTab_WidgetDefaults -> WidgetDefaults:GetAll
--   HDGR_ExpansionData         -> Expansions:GetAll  (also in HDG.Constants)
--   HDGR_SchemeMeta            -> Schemes:GetMeta

HDG = HDG or {}
HDG.StaticData = HDG.StaticData or {}

local S = HDG.StaticData

-- Tiny helper. Fail loud on missing data file (TOC misconfiguration / load
-- order error) rather than returning empty tables that silently produce
-- "vendor not found" / "decor not in catalog" UI states.
local function _table(globalName)
    local t = _G[globalName]
    if type(t) ~= "table" then
        error("HDG.StaticData: _G." .. globalName .. " missing or not a table "
              .. "(got " .. type(t) .. "). Is the data file in <Addon>.toc "
              .. "before HDGR_StaticData.lua?", 2)
    end
    return t
end

-- ============================================================================
-- VendorAugment  (HDGR_VendorAugment)
-- ============================================================================
---@class HDG.StaticData.VendorAugment
S.VendorAugment = S.VendorAugment or {}
S.VendorAugment._byName = nil    -- built at OnInitialize
S.VendorAugment._byMapID = nil   -- built at OnInitialize

function S.VendorAugment:Get(npcID)
    local t = _table("HDGR_VendorAugment")  -- exception(boundary): _table fails loud if HDGR_VendorAugment DB missing
    return t[npcID]
end

function S.VendorAugment:ResolveName(name, zone)
    self:_EnsureIndexes()
    if zone then
        -- Try "Name/Zone" form first, then "Name (Zone)" curator form
        local r = self._byName[name .. "/" .. zone]
                  or self._byName[name .. " (" .. zone .. ")"]
        if r then return r end
    end
    return self._byName[name]
end

function S.VendorAugment:GetVendorsByMap(mapID)
    self:_EnsureIndexes()
    return self._byMapID[mapID]
end

function S.VendorAugment:_EnsureIndexes()
    if self._byName then return end
    local byName, byMapID = {}, {}
    local t = _table("HDGR_VendorAugment")
    for npcID, v in pairs(t) do
        -- Name index: first occurrence wins for unqualified name; later
        -- collisions become zone-suffixed.
        if byName[v.name] then
            byName[v.name .. "/" .. v.zone] = npcID
            byName[v.name .. " (" .. v.zone .. ")"] = npcID
        else
            byName[v.name] = npcID
        end
        -- Base-name index: curator names use "Name (Zone)" but the housing
        -- catalog reports the bare in-game name. Key base name by zone so a
        -- bare catalog name resolves to the right npcID (additive, never
        -- overrides an exact-name key).
        local base = v.name:gsub("%s*%b()%s*$", "")
        if base ~= v.name and base ~= "" then
            byName[base .. "/" .. v.zone]         = byName[base .. "/" .. v.zone] or npcID
            byName[base .. " (" .. v.zone .. ")"] = byName[base .. " (" .. v.zone .. ")"] or npcID
            if not byName[base] then byName[base] = npcID end
        end
        -- MapID index: list of vendors per mapID
        if v.mapID then
            byMapID[v.mapID] = byMapID[v.mapID] or {}
            table.insert(byMapID[v.mapID], npcID)
        end
    end
    self._byName = byName
    self._byMapID = byMapID
end

-- ============================================================================
-- StaticData.ItemAugment  (HDGR_ItemAugment)
-- Sparse itemID-keyed augments: rep gates, sourceType, altSourceType.
-- ============================================================================
---@class HDG.StaticData.ItemAugment
S.ItemAugment = S.ItemAugment or {}

function S.ItemAugment:Get(itemID)
    local t = _table("HDGR_ItemAugment")
    return t[itemID]
end

-- ============================================================================
-- StaticData.CatalogOverrides  (HDGR_CatalogOverrides)
-- itemID-keyed field-level overrides applied at BuildRow time; corrects
-- known-wrong catalog fields. Sparse; populated reactively on user reports.
-- ============================================================================
---@class HDG.StaticData.CatalogOverrides
S.CatalogOverrides = S.CatalogOverrides or {}

function S.CatalogOverrides:Get(itemID)
    local t = _table("HDGR_CatalogOverrides")
    return t[itemID]
end

function S:OnInitialize()
    S.VendorAugment:_EnsureIndexes()
end

-- ============================================================================
-- Recipes  (HDGR_DecorDB -- recipe-backed decor only; subset of Decor)
-- ============================================================================

---@class HDG.StaticData.Recipes
S.Recipes = S.Recipes or {}

-- HDGR_DecorDB keyed by spell/recipe ID; `itemID` inside each entry.
-- Two O(1) reverse indexes built lazily on first use (invalidated when the
-- DB table reference changes):
--   _byItemIDCache  itemID -> entry            (:Get)
--   _byNpcCache     npcID  -> { entries sold } (:GetBySourceNpcID, covers recipe-only vendors)
local _byItemIDCache, _byNpcCache, _cachedSource
local function _ensureRecipeIndexes()
    local db = _table("HDGR_DecorDB")
    if _cachedSource == db then return end
    _byItemIDCache, _byNpcCache = {}, {}
    for _, entry in pairs(db) do
        if entry.itemID then _byItemIDCache[entry.itemID] = entry end
        local rs = entry.recipeSource
        if rs and rs.type == "vendor" and rs.vendors then  -- exception(boundary): recipeSource optional + multi-typed
            for _, v in ipairs(rs.vendors) do
                local list = _byNpcCache[v.npcID] or {}
                list[#list + 1] = entry
                _byNpcCache[v.npcID] = list
            end
        end
    end
    _cachedSource = db
end

function S.Recipes:Get(itemID)
    if not itemID then return nil end
    _ensureRecipeIndexes()
    return _byItemIDCache[itemID]
end

-- npcID -> array of recipe entries the vendor sells, or nil.
function S.Recipes:GetBySourceNpcID(npcID)
    if not npcID then return nil end
    _ensureRecipeIndexes()
    return _byNpcCache[npcID]
end

-- npcID -> count of recipes the vendor sells. Drives the acq.allVendors union
-- (recipe-only quartermasters) + the vendor header recipe count.
function S.Recipes:RecipeVendorCounts()
    _ensureRecipeIndexes()
    local out = {}
    for npcID, list in pairs(_byNpcCache) do out[npcID] = #list end
    return out
end

function S.Recipes:GetAll()
    return _table("HDGR_DecorDB")
end

-- Reverse index: reagent itemID -> array of decor recipe itemIDs that use it.
-- Powers the "Used in N decor recipes" reagent tooltip line. Lazy; rebuilt when the
-- DB table reference changes (same pattern as _byItemIDCache).
local _reagentUsersCache, _reagentUsersSource
local function _ensureReagentUsers()
    local db = _table("HDGR_DecorDB")
    if _reagentUsersSource == db then return end
    _reagentUsersCache, _reagentUsersSource = {}, db
    for _, entry in pairs(db) do
        if entry.itemID and entry.reagents then
            for rid in pairs(entry.reagents) do
                local list = _reagentUsersCache[rid] or {}
                list[#list + 1] = entry.itemID
                _reagentUsersCache[rid] = list
            end
        end
    end
end

-- Decor recipe itemIDs that use this exact reagent itemID (nil if none). The
-- caller unions across quality-variant siblings (a tiered reagent's recipes list
-- one tier; the player may hold another) -- keeps this facade DecorDB-only.
function S.Recipes:RecipesUsingReagent(reagentItemID)
    if not reagentItemID then return nil end
    _ensureReagentUsers()
    return _reagentUsersCache[reagentItemID]
end

-- Walk a DecorDB entry's direct reagents, mirroring Professions:VisitBasicSlots so the
-- decor recipe path (queue/materials/lumber/tooltip) can read DecorDB instead of
-- ProfessionsDB. visitor({ itemID, qty, name }); a truthy return stops early. DecorDB
-- has no non-basic slots, so there is no `type` filter. Reagents are pairs()-iterated
-- (unordered) -- fine for the commutative accumulators + any-match early-stop consumers.
function S.Recipes:VisitReagents(entry, visitor)
    if not (entry and entry.reagents) then return end
    for itemID, info in pairs(entry.reagents) do
        if visitor({ itemID = itemID, qty = info.qty, name = info.name }) then return end
    end
end

-- ============================================================================
-- Professions  (HDGR_ProfessionsDB by recipeID + HDGR_ProfessionThresholds)
-- ============================================================================

---@class HDG.StaticData.Professions
S.Professions = S.Professions or {}

function S.Professions:GetRecipe(recipeID)
    if not recipeID then return nil end
    return _table("HDGR_ProfessionsDB")[recipeID]
end

function S.Professions:GetAll()
    return _table("HDGR_ProfessionsDB")
end

function S.Professions:GetThresholds()
    return _table("HDGR_ProfessionThresholds")
end

-- Reverse index: produced itemID -> recipeID. ProfessionsDB is keyed by recipeID
-- with `.itemID` on each entry; this lets decor rows (which carry no recipeID)
-- resolve a craftable item to its recipe for the craft queue. Lazily built;
-- rebuilt when the source table identity changes. Last-wins on the rare
-- item-with-multiple-recipes (any recipe that yields the item suffices).
local _itemToRecipeCache, _itemToRecipeSource
local function _ensureItemToRecipe()
    local db = _table("HDGR_ProfessionsDB")
    if _itemToRecipeSource == db then return end
    _itemToRecipeCache, _itemToRecipeSource = {}, db
    for recipeID, recipe in pairs(db) do
        if recipe.itemID then _itemToRecipeCache[recipe.itemID] = recipeID end
    end
end

function S.Professions:GetByItemID(itemID)
    if not itemID then return nil end
    _ensureItemToRecipe()
    return _itemToRecipeCache[itemID]
end

-- Quality-variant groups: tiered reagents have separate itemIDs per quality
-- tier; `slot.variants` lists the siblings. Reverse map lets material counting
-- sum across the whole quality group (any quality satisfies the slot).
-- Returns { otherSiblingID, ... } or nil. Lazily built; rebuilt when the
-- source table identity changes.
local _qvCache, _qvSource

-- Sibling list for group[i]: every other id in the quality group.
local function _buildSiblings(group, i)
    local others = {}
    for j, other in ipairs(group) do
        if j ~= i then others[#others + 1] = other end
    end
    return others
end

-- Index one variant-bearing slot into _qvCache: each member of the quality
-- group maps to its sibling list.
local function _indexVariantSlot(slot)
    local group = { slot.itemID }
    for _, v in ipairs(slot.variants) do group[#group + 1] = v end
    for i, id in ipairs(group) do
        local others = _buildSiblings(group, i)
        -- A reagent can appear in slots listing partial sibling sets;
        -- keep the largest group seen.
        if not _qvCache[id] or #others > #_qvCache[id] then
            _qvCache[id] = others
        end
    end
end

local function _ensureQualityVariants()
    local db = _table("HDGR_ProfessionsDB")
    if _qvSource == db then return end
    _qvCache, _qvSource = {}, db
    for _, recipe in pairs(db) do
        if recipe.slots then
            for _, slot in ipairs(recipe.slots) do
                if slot.itemID and slot.variants and #slot.variants > 0 then
                    _indexVariantSlot(slot)
                end
            end
        end
    end
end

function S.Professions:GetQualityVariants(itemID)
    if not itemID then return nil end
    _ensureQualityVariants()
    return _qvCache[itemID]
end

-- Walk basic-typed slots on a recipe. visitor(slot) called per slot;
-- returning truthy stops the walk early. No-op on nil recipe or no slots.
function S.Professions:VisitBasicSlots(recipe, visitor)
    if not (recipe and recipe.slots) then return end
    for _, slot in ipairs(recipe.slots) do
        if slot.type == "basic" then
            if visitor(slot) then return end
        end
    end
end

-- ============================================================================
-- Reagents  (HDGR_ReagentsDB -- crafting reagent metadata)
-- ============================================================================

---@class HDG.StaticData.Reagents
S.Reagents = S.Reagents or {}

function S.Reagents:Get(itemID)
    if not itemID then return nil end
    return _table("HDGR_ReagentsDB")[itemID]
end

function S.Reagents:GetAll()
    return _table("HDGR_ReagentsDB")
end

-- ============================================================================
-- Facets  (HDGR_FacetDB + HDGR_FacetVocab for styles tab)
-- ============================================================================

---@class HDG.StaticData.Facets
S.Facets = S.Facets or {}

function S.Facets:Get(itemID)
    if not itemID then return nil end
    return _table("HDGR_FacetDB")[itemID]
end

function S.Facets:GetAll()
    return _table("HDGR_FacetDB")
end

function S.Facets:GetVocab()
    return _table("HDGR_FacetVocab")
end

-- ============================================================================
-- Styles  (HDGR_StyleDefinitions)
-- ============================================================================

---@class HDG.StaticData.Styles
S.Styles = S.Styles or {}

function S.Styles:GetDefinitions()
    return _table("HDGR_StyleDefinitions")
end

-- ============================================================================
-- Collections  (HDGR_CollectionDefinitions)
-- ============================================================================

---@class HDG.StaticData.Collections
S.Collections = S.Collections or {}

function S.Collections:GetDefinitions()
    return _table("HDGR_CollectionDefinitions")
end

-- ============================================================================
-- Trainers  (HDGR_TrainersDB -- profession trainer NPCs by profession + expansion)
-- ============================================================================
--
-- Shape: HDGR_TrainersDB[profName][expName][faction] -> trainerRecord OR
--        HDGR_TrainersDB[profName][expName][faction] -> { trainerRecord, ... }
-- Faction key is one of "Alliance" / "Horde" / "Both".
-- trainerRecord fields: npcID, name, location ("Zone [x, y]"), note? (optional)

---@class HDG.StaticData.Trainers
S.Trainers = S.Trainers or {}

function S.Trainers:GetAll()
    return _table("HDGR_TrainersDB")
end

function S.Trainers:GetByProfession(profName)
    if not profName then return nil end
    return _table("HDGR_TrainersDB")[profName]
end

function S.Trainers:GetByProfessionAndExpansion(profName, expName)
    if not profName or not expName then return nil end
    local p = _table("HDGR_TrainersDB")[profName]
    return p and p[expName] or nil
end

-- ============================================================================
-- TitleTiers  (HDGR_HouseTab_TitleTiers -- decorator title ladder)
-- Shape: ordered array of { threshold, name, vamoose? }, ascending threshold.
-- ============================================================================

---@class HDG.StaticData.TitleTiers
S.TitleTiers = S.TitleTiers or {}

function S.TitleTiers:GetAll()
    return _table("HDGR_HouseTab_TitleTiers")
end

-- ============================================================================
-- WidgetDefaults  (HDGR_HouseTab_WidgetDefaults)
-- Shape: ordered array of { id, title, order, width, enabled, defaultHeight }.
-- ============================================================================

---@class HDG.StaticData.WidgetDefaults
S.WidgetDefaults = S.WidgetDefaults or {}

function S.WidgetDefaults:GetAll()
    return _table("HDGR_HouseTab_WidgetDefaults")
end

-- ============================================================================
-- Expansions  (HDGR_ExpansionData -- mirrored in HDG.Constants.EXPANSION_DATA)
-- ============================================================================

---@class HDG.StaticData.Expansions
S.Expansions = S.Expansions or {}

function S.Expansions:GetAll()
    return _table("HDGR_ExpansionData")
end

-- ============================================================================
-- Schemes  (HDGR_SchemeMeta -- theme scheme definitions)
-- ============================================================================

---@class HDG.StaticData.Schemes
S.Schemes = S.Schemes or {}

function S.Schemes:GetMeta()
    return _table("HDGR_SchemeMeta")
end

-- Get a built scheme by name (nil if the name isn't a registered scheme).
function S.Schemes:Get(name)
    return _table("HDGR_SchemeConstants")[name]
end
