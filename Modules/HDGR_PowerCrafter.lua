-- HDG.PowerCrafter
-- ============================================================================
-- Pure-function DAG resolver for the Recipes tab.
--
-- The "PowerCrafter" name follows the VPC heritage -- it's the engine that
-- turns a queue snapshot into:
--   * a direct material list (one entry per slot, per queue row)
--   * a raw-DAG-expanded leaf list (intermediate crafted reagents recurse
--     down to their root materials when the player knows the sub-recipe)
--   * a per-queue-entry rollup (no cross-row merging)
--   * a "Craft These First" list (subsidiary recipes the queue depends on)
--
-- Architecture rules (locked in):
--   * Pure functions. Inputs: (queue, knownRecipeItemIDs). No Store reads,
--     no Blizzard API. Selectors handle state-snapshotting -- this module
--     just transforms data. (ADR-013 explicit-parameter substitution.)
--   * knownRecipeItemIDs is a set: `{ [itemID] = true }`. The CALLER decides
--     whether to filter by selfKnown, altKnown, or both -- PowerCrafter
--     just applies the set as the "auto-expand intermediate" gate.
--   * Recipe data comes from `HDG.StaticData.Professions:GetAll()` via the
--     ADR-003a deterministic-module-read carve-out (post-init, idempotent,
--     no Blizzard API call). The reverse index `itemID -> recipeIDs[]` is
--     built lazily on first call and cached for the life of the session.
--
-- Output schemas:
--   CalculateRawMaterials(queue) ->
--     { [itemID] = { itemID, qty, fromIntermediate = bool } }
--   AggregateByRecipe(queue, knownRecipeItemIDs) ->
--     { [position] = { recipeID, materials = { [itemID] = qty } } }   (direct)
--   AggregateByRecipeRaw(queue) -> same shape, raw-expanded (known-agnostic)
--   GetSubsidiaryRecipes(recipeID, knownRecipeItemIDs) ->
--     { [itemID] = recipeID }   -- itemID is the intermediate; recipeID is
--                                  one matching recipe (lowest by ID for
--                                  determinism; UI surfaces all ranks via
--                                  the recipe panel)

HDG = HDG or {}
HDG.PowerCrafter = HDG.PowerCrafter or {}
local PC = HDG.PowerCrafter

PC.MAX_DEPTH = 6   -- depth cap for DAG recursion (safety net for cycles + deep chains)

-- ===== Reverse index =========================================================
-- [itemID] = { recipeID, ... } (rank variants share itemID). Lowest recipeID = deterministic primary.

function PC:_GetIndex()
    if self._itemIDToRecipeIDs then return self._itemIDToRecipeIDs end
    local db = HDG.StaticData.Professions:GetAll()
    local index = {}
    if type(db) == "table" then
        for recipeID, recipe in pairs(db) do
            local outID = recipe.itemID
            if outID then
                index[outID] = index[outID] or {}
                index[outID][#index[outID] + 1] = recipeID
            end
        end
        -- Sort each bucket so the "primary" recipeID is stable.
        for _, bucket in pairs(index) do
            table.sort(bucket)
        end
    end
    self._itemIDToRecipeIDs = index
    return index
end

-- Test seam: clear cached index between DB-double swaps.
function PC:_ResetIndex()
    self._itemIDToRecipeIDs = nil
end

-- ===== Recipe lookup ========================================================

-- Primary = lowest recipeID (typically rank 1; worst-case reagent count for shopping list).
function PC:_GetPrimaryRecipeForItem(itemID)
    local index = self:_GetIndex()
    local bucket = index[itemID]
    if not bucket then return nil end
    local recipeID = bucket[1]
    local db = HDG.StaticData.Professions:GetAll()
    return db and db[recipeID]
end

function PC:_GetRecipe(recipeID)
    local db = HDG.StaticData.Professions:GetAll()
    return db and db[recipeID]
end

-- IsCraftedReagent: source category "Crafted" in ReagentsDB (drives craft-order list, not knowledge).
-- "Crafted:N" hint suffix also matched via prefix.
function PC:IsCraftedReagent(itemID)
    if not itemID then return false end
    local db = HDG.StaticData.Reagents:GetAll()
    local row = db and db[itemID]
    local source = row and row[1]
    if not source then return false end
    return source == "Crafted" or source:match("^Crafted") ~= nil
end

-- Required slots: type=="basic" with itemID+qty (modifying/finishing/automatic are optional embellishments).
local function basicSlots(recipe)
    local out = {}
    HDG.StaticData.Professions:VisitBasicSlots(recipe, function(slot)
        if slot.itemID and slot.qty then out[#out + 1] = slot end
    end)
    return out
end

-- ===== Per-queue-entry direct materials =====================================

-- Direct mode: one entry per basic slot, qty = slot.qty * queueRow.remaining.
-- Returns { [itemID] = qty } keyed by reagent itemID.
function PC:_DirectMaterialsForRow(recipeID, qty)
    local recipe = self:_GetRecipe(recipeID)
    local out = {}
    for _, slot in ipairs(basicSlots(recipe)) do
        out[slot.itemID] = (out[slot.itemID] or 0) + slot.qty * qty
    end
    return out
end

-- ===== Public API ===========================================================

-- AggregateByRecipe: per-position rollup, no cross-row merging, direct depth (no expansion).
function PC:AggregateByRecipe(queue)
    local out = {}
    if type(queue) ~= "table" then return out end
    for pos, row in ipairs(queue) do
        if row.recipeID and (row.remaining or 0) > 0 then  -- exception(boundary): queue row from SVars may lack remaining
            out[pos] = {
                recipeID  = row.recipeID,
                itemID    = row.itemID,
                materials = self:_DirectMaterialsForRow(row.recipeID, row.remaining),
            }
        end
    end
    return out
end

-- AggregateByRecipeRaw: per-position rollup DAG-expanded to base mats (By-Recipe + Raw).
function PC:AggregateByRecipeRaw(queue)
    local out = {}
    if type(queue) ~= "table" then return out end
    for pos, row in ipairs(queue) do
        if row.recipeID and (row.remaining or 0) > 0 then  -- exception(boundary): queue row from SVars may lack remaining
            out[pos] = {
                recipeID  = row.recipeID,
                itemID    = row.itemID,
                materials = self:_RawMaterialsForRow(row.recipeID, row.remaining),
            }
        end
    end
    return out
end

-- Milling/prospecting convert raw mats in BULK with RNG output -- there's no fixed
-- yield to divide by, and the products (pigments / gems) are AH-buyable. The raw DAG
-- STOPS at them: expanding to herbs/ore over-counts wildly (one decor needing 145
-- pigment would otherwise demand ~2900 Yseralline Seeds).
local RNG_BULK_CATEGORY = { ["Mass Milling"] = true, ["Mass Prospecting"] = true }

-- _RawMaterialsForRow: DAG-walk to base mats. Crafted reagents recurse (known-agnostic).
-- Cycle defense: per-branch visited set + MAX_DEPTH cap. Milled/prospected products are
-- treated as leaves (RNG_BULK_CATEGORY) -- raw stops at the pigment/gem.
function PC:_RawMaterialsForRow(recipeID, qty)
    local out = {}
    local function expand(itemID, q, depth, visited)
        if depth > PC.MAX_DEPTH then  -- depth cap: treat as leaf
            out[itemID] = (out[itemID] or 0) + q; return
        end
        if visited[itemID] then       -- cycle: treat as leaf
            out[itemID] = (out[itemID] or 0) + q; return
        end
        local subRecipe = self:IsCraftedReagent(itemID) and self:_GetPrimaryRecipeForItem(itemID)
        if not subRecipe or RNG_BULK_CATEGORY[subRecipe.categoryName] then  -- leaf: gathering/vendor/no recipe, or milled/prospected (stop at pigment/gem)
            out[itemID] = (out[itemID] or 0) + q; return
        end
        -- Intermediate: expand slots. Mark visited per-branch (siblings with
        -- shared upstream intermediates stay unblocked).
        visited[itemID] = true
        for _, slot in ipairs(basicSlots(subRecipe)) do
            expand(slot.itemID, slot.qty * q, depth + 1, visited)
        end
        visited[itemID] = nil
    end
    local recipe = self:_GetRecipe(recipeID)
    for _, slot in ipairs(basicSlots(recipe)) do
        expand(slot.itemID, slot.qty * qty, 1, {})
    end
    return out
end

-- CalculateRawMaterials: queue-wide sum of every row's raw materials.
function PC:CalculateRawMaterials(queue)
    local out = {}
    if type(queue) ~= "table" then return out end
    for _, row in ipairs(queue) do
        if row.recipeID and (row.remaining or 0) > 0 then  -- exception(boundary): queue row from SVars may lack remaining
            local rowMats = self:_RawMaterialsForRow(row.recipeID, row.remaining)
            for itemID, q in pairs(rowMats) do
                out[itemID] = (out[itemID] or 0) + q
            end
        end
    end
    return out
end

-- GetSubsidiaryRecipes: intermediates the player can craft (knownRecipeItemIDs gate).
function PC:GetSubsidiaryRecipes(recipeID, knownRecipeItemIDs)
    local out = {}
    local recipe = self:_GetRecipe(recipeID)
    if not recipe then return out end
    local knownSet = knownRecipeItemIDs or {}
    for _, slot in ipairs(basicSlots(recipe)) do
        if knownSet[slot.itemID] then
            local sub = self:_GetPrimaryRecipeForItem(slot.itemID)
            if sub then out[slot.itemID] = sub.recipeID end
        end
    end
    return out
end

-- GetCraftingOrder: consolidated "Crafted" sub-recipes across the queue (informational;
-- knownRecipeItemIDs gate is OPTIONAL). Output: { itemID, recipeID, name, qty } summed.
-- _addOrMergeSlotOrder: O(1) merge via `index` table.
local function _addOrMergeSlotOrder(out, index, slot, addQty, subRecipe)
    local existing = index[slot.itemID]
    if existing then
        out[existing].qty = out[existing].qty + addQty
        return
    end
    out[#out + 1] = {
        itemID   = slot.itemID,
        recipeID = subRecipe and subRecipe.recipeID,
        name     = (subRecipe and subRecipe.name)
                or slot.name
                or ("item " .. tostring(slot.itemID)),
        qty      = addQty,
    }
    index[slot.itemID] = #out
end

-- Collect craftable-basic slots into the order, weighted by multiplier.
function PC:_collectCraftSlots(recipe, multiplier, out, index)
    local pc = self
    HDG.StaticData.Professions:VisitBasicSlots(recipe, function(slot)
        if not (slot.itemID and slot.qty and pc:IsCraftedReagent(slot.itemID)) then return end
        local subRecipe = pc:_GetPrimaryRecipeForItem(slot.itemID)
        _addOrMergeSlotOrder(out, index, slot, slot.qty * multiplier, subRecipe)
    end)
end

function PC:GetCraftingOrder(queue, _knownRecipeItemIDs)
    local out, index = {}, {}    -- index[itemID] = position in out (dedupe)
    if type(queue) ~= "table" then return out end
    for _, row in ipairs(queue) do
        if row.recipeID and (row.remaining or 0) > 0 then  -- exception(boundary): queue row from SVars may lack remaining
            local recipe = self:_GetRecipe(row.recipeID)
            self:_collectCraftSlots(recipe, row.remaining or 1, out, index)  -- exception(boundary): queue row from SVars may lack remaining
        end
    end
    return out
end

-- GetCraftReadiness: 0..1 materials coverage ratio (drives the "Ready" filter bucket).
function PC:GetCraftReadiness(recipeID, bagCounts)
    local recipe = self:_GetRecipe(recipeID)
    bagCounts = bagCounts or {}
    local totalNeed, totalHave = 0, 0
    HDG.StaticData.Professions:VisitBasicSlots(recipe, function(slot)
        if not (slot.itemID and slot.qty) then return end
        local have = bagCounts[slot.itemID] or 0  -- exception(boundary): sparse bag map
        if have > slot.qty then have = slot.qty end
        totalNeed = totalNeed + slot.qty
        totalHave = totalHave + have
    end)
    if totalNeed == 0 then return 0 end
    return totalHave / totalNeed
end

-- GetRecipeShortage: coverage ratio + bottleneck reagent (largest absolute shortage).
-- qty multiplies every slot. Returns { pct, bottleneckItemID, missingQty }.
function PC:GetRecipeShortage(recipeID, qty, bagCounts)
    local recipe = self:_GetRecipe(recipeID)
    qty       = qty or 1   -- exception(boundary): caller may omit qty for single-craft shortage check
    bagCounts = bagCounts or {}
    local totalNeed, totalHave = 0, 0
    local worstShortageItem, worstShortageQty = nil, 0
    HDG.StaticData.Professions:VisitBasicSlots(recipe, function(slot)
        if not (slot.itemID and slot.qty) then return end
        local need = slot.qty * qty
        local have = bagCounts[slot.itemID] or 0  -- exception(boundary): sparse bag map
        local cappedHave = have
        if cappedHave > need then cappedHave = need end
        totalNeed = totalNeed + need
        totalHave = totalHave + cappedHave
        local shortage = need - have
        if shortage > worstShortageQty then
            worstShortageQty  = shortage
            worstShortageItem = slot.itemID
        end
    end)
    local pct = 0
    if totalNeed > 0 then pct = totalHave / totalNeed end
    return {
        pct              = pct,
        bottleneckItemID = worstShortageItem,
        missingQty       = worstShortageQty,
    }
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name = "PowerCrafter",
    dependencies = {},  -- pure stateless transform; no event subscriptions
})
