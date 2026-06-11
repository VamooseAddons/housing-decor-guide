-- HDG.Selectors -- Mogul tab
-- ============================================================================
-- Wraps HDG.Mogul:BuildPlan. plan-rows is the single heavy producer;
-- smaller selectors (title, totals, button booleans) compose cheaply.

HDG = HDG or {}
HDG.Selectors = HDG.Selectors or {}
local Selectors = HDG.Selectors

-- File-local lazy index: lumberType itemID -> shortName. Built once on first use.
local _lumberShortByID = nil
local function lumberShortByID()
    if _lumberShortByID then return _lumberShortByID end
    _lumberShortByID = {}
    for _, l in ipairs(HDG.Constants.LUMBER_DATA) do
        _lumberShortByID[l.id] = l.shortName or l.name or ""
    end
    return _lumberShortByID
end

-- Mogul tab grows to 950px when Goblin sub-view is active AND TSM is the effective
-- price source. source preference + prices tick so Config changes trigger resize.
local function effectiveSourceIsTSM(state)
    local pref = state.account.config.preferredPriceAddon
    if pref == "TSM" then return true end
    if pref == nil then return HDG.PriceSource:IsTSMAvailable() end
    return false
end

Selectors:Register("goblin.isTSMActive", {
    reads = {"account.config.preferredPriceAddon", "session.prices.tick"},
    fn = effectiveSourceIsTSM,
})

Selectors:Register("mogul.dynamicColumns", {
    reads = {"session.ui.mogul.subView",
             "account.config.preferredPriceAddon", "session.prices.tick"},
    fn = function(state)
        local subView = state.session.ui.mogul.subView
        if subView == "goblin" then
            -- #AH (40) is always shown in Goblin -> base widens 700 -> 745.
            -- TSM active adds Server/Market/Region/TSM% (260) + Rate/+Day (100) + gaps -> ~1135.
            if effectiveSourceIsTSM(state) then return { 1135 } end
            return { 745 }
        end
        return { 700 }   -- mogul craft-optimizer subview
    end,
})

-- Row-click detail expansion: view grows by 150px for the material-breakdown panel.
-- Body row only (chrome + status via window slots per HDG-ADR-025).
Selectors:Register("mogul.dynamicRows", {
    reads = {"session.ui.mogul.subView", "session.ui.mogul.goblin.expandedItemID"},
    fn = function(state)
        local subView  = state.session.ui.mogul.subView
        local expanded = state.session.ui.mogul.goblin.expandedItemID
        -- Body row only -- chrome + status come from the window's slots now
        -- (HDG-ADR-025). body row is index 1 (was index 2 under chrome).
        if subView == "goblin" and expanded then
            return { 650 }   -- +150 for the goblin detail panel
        end
        return { 600 }
    end,
})

Selectors:Register("goblin.isDetailVisible", {
    reads = {"session.ui.mogul.subView", "session.ui.mogul.goblin.expandedItemID"},
    fn = function(state)
        return state.session.ui.mogul.subView == "goblin"
           and state.session.ui.mogul.goblin.expandedItemID ~= nil
    end,
})

-- ADR-003a inside-closure read: Mogul's lazy O(1) index (GetDecorByOutputItemID).
local function expandedRecipe(state)
    local id = state.session.ui.mogul.goblin.expandedItemID
    if not id then return nil end
    return HDG.Mogul:GetDecorByOutputItemID()[id]
end

Selectors:Register("goblin.detailTitle", {
    reads = {"session.ui.mogul.goblin.expandedItemID"},
    fn = function(state)
        local r = expandedRecipe(state)
        if not r then return "" end
        return string.format("Materials for %s", r.name or "?")
    end,
})

-- Per-material breakdown for the expanded recipe. Sorted by total cost DESC (budget driver first).
Selectors:Register("goblin.detailRows", {
    reads = {"session.ui.mogul.goblin.expandedItemID",
             "session.prices.tick", "session.bag.tick"},
    fn = function(state)
        local r = expandedRecipe(state)
        if not r or type(r.reagents) ~= "table" then return {} end
        local out = {}
        for reagentID, info in pairs(r.reagents) do
            local qty   = info.qty   -- recipe schema guarantees qty per reagent slot
            local price = HDG.PriceSource:GetItemPrice(reagentID)
            local owned = HDG.BagObserver:GetTotal(reagentID)
            out[#out + 1] = {
                kind       = "goblinDetailRow",
                itemID     = reagentID,
                name       = info.name or "?",
                qty        = qty,
                owned      = owned,
                price      = price,
                totalCost  = (price or 0) * qty,
                sufficient = owned >= qty,
            }
        end
        table.sort(out, function(a, b) return (a.totalCost or 0) > (b.totalCost or 0) end)
        return out
    end,
})

Selectors:DefineEnum("mogul.isMode",    "session.ui.mogul.mode",       { "profit", "collection" })
Selectors:DefineEnum("mogul.isView",    "session.ui.mogul.viewMode",   { "char", "account" })
Selectors:DefineEnum("mogul.isOpt",     "session.ui.mogul.optimizeBy", { "lumberOnly", "lumberPlusMats" })
-- "config" sub-view removed -- moved to Config tab.
Selectors:DefineEnum("mogul.isSubView", "session.ui.mogul.subView",    { "mogul", "goblin" })

-- ===== Supply Impact selectors ==============================================
Selectors:DefineEnum("mogul.isSupplyMode", "session.ui.mogul.supplyImpact.mode",
    { "off", "smooth", "cap" })

-- Frugal toggle: planner re-ranks by dampened lumber cost so low-lumber crafts surface.
Selectors:Register("mogul.frugal", {
    reads = { "session.ui.mogul.frugal" },
    fn = function(state) return state.session.ui.mogul.frugal == true end,
})

-- Scalar current-mode selector for radioGroup `current` binding.
Selectors:Register("mogul.supplyMode", {
    reads = { "session.ui.mogul.supplyImpact.mode" },
    fn    = function(state) return state.session.ui.mogul.supplyImpact.mode end,
})

-- Static menu items for the supply-impact radioGroup. Memoized (constant).
Selectors:Register("mogul.supplyMenuItems", {
    reads    = {},
    memoized = true,
    fn = function()
        return {
            { text = "Off",     value = "off"    },
            { text = "Smooth%", value = "smooth" },
            { text = "Cap",     value = "cap"    },
        }
    end,
})


-- The editable numeric value (smoothPct or capN) shown when the mode is not Off.
Selectors:Register("mogul.supplyParamVisible", {
    reads = { "session.ui.mogul.supplyImpact.mode" },
    fn = function(state)
        return state.session.ui.mogul.supplyImpact.mode ~= "off"
    end,
})

Selectors:Register("mogul.supplyParamText", {
    reads = { "session.ui.mogul.supplyImpact.mode",
              "session.ui.mogul.supplyImpact.smoothPct",
              "session.ui.mogul.supplyImpact.capN" },
    fn = function(state)
        local si = state.session.ui.mogul.supplyImpact
        if si.mode == "smooth" then return tostring(si.smoothPct) end
        if si.mode == "cap"    then return tostring(si.capN)      end
        return ""
    end,
})

-- ===== Plan (the heavy producer) ============================================
-- Rebuilds the plan from current settings + account state (reads cover all
-- Mogul module inputs for correct invalidation).

Selectors:Register("mogul.plan", {
    memoized = true,
    reads = {
        "session.ui.mogul.mode",
        "session.ui.mogul.viewMode",
        "session.ui.mogul.optimizeBy",
        "session.ui.mogul.supplyImpact.mode",
        "session.ui.mogul.supplyImpact.smoothPct",
        "session.ui.mogul.supplyImpact.capN",
        "session.ui.mogul.frugal",
        "account.recipes",                       -- decor-known authority
        "account.characters",                    -- alt-hint derivation
        "account.collection.ownedDecorIDs",
        "session.bag.tick",
        "session.prices.tick",
        "session.itemNames.tick",
    },
    fn = function(state)
        local m = state.session.ui.mogul
        return HDG.Mogul:BuildPlan({
            mode       = m.mode,
            viewMode   = m.viewMode,
            optimizeBy = m.optimizeBy,
            frugal     = m.frugal == true,
        })
    end,
})

-- Plan rows -> scrollbox element list.
local function expansionShort(display) return HDG.Expansion.GetShort(display) end

local function buildPlanRowElement(planRow, viewMode, isRunnerUp)
    local r = planRow.recipe
    local s = planRow.score
    local knownState = HDG.Mogul:KnownStateForItemID(r.itemID)
    local bestAlt
    if viewMode == "account"
       and knownState == HDG.Constants.RECIPE_STATE.KnownByAlt then
        bestAlt = HDG.Mogul:BestAltForSpellID(r.spellID)
    end
    local expShort = expansionShort(r.expansion) or ""
    return {
        kind         = "mogulRow",
        spellID      = r.spellID,
        itemID       = r.itemID,
        name         = r.name,
        profession   = r.profession,
        expansion    = r.expansion,
        expShort     = expShort,
        crafts       = planRow.crafts,
        lumberPerCraft = s.bindingLumberQty or 0,  -- exception(boundary): binding qty nil for non-binding recipes
        lumberTotal  = (planRow.crafts or 0) * s.lumberCost,
        salePrice    = s.salePrice,
        revenuePerCraft = s.salePrice,
        netPerCraft     = s.netProfitPerCraft,
        revenueTotal = (planRow.crafts or 0) * s.salePrice,
        netTotal     = (planRow.crafts or 0) * s.netProfitPerCraft,
        knownState   = knownState,
        bestAlt      = bestAlt,
        isRunnerUp   = isRunnerUp and true or false,
    }
end

-- Heterogeneous row stream: mogulSection headers + mogulRow entries.
Selectors:Register("mogul.planRows", {
    reads = { "session.ui.mogul.viewMode" },   -- read directly in fn (also in mogul.plan's closure)
    calls = {"mogul.plan"},
    fn = function(state, ctx)
        local plan = Selectors:Call("mogul.plan", state, ctx)
        if not plan then return {} end
        local viewMode = state.session.ui.mogul.viewMode
        local totals = plan.totals or {}
        local hasPlanRows = plan.rows and #plan.rows > 0
        local out = {}

        -- Plan section header + rows.
        local planSection
        if hasPlanRows then
            planSection = string.format("Plan -- %d crafts, %d lumber used",
                totals.crafts or 0, totals.lumberUsed or 0)
        else
            planSection = "Plan -- no crafts fit current budget"
        end
        out[#out + 1] = { kind = "mogulSection", title = planSection }
        if hasPlanRows then
            for _, row in ipairs(plan.rows) do
                out[#out + 1] = buildPlanRowElement(row, viewMode, false)
            end
        end

        -- Runners-up: candidates that scored but weren't picked.
        local picked = {}
        for _, row in ipairs(plan.rows or {}) do
            if row.recipe and row.recipe.itemID then
                picked[row.recipe.itemID] = true
            end
        end
        local runners = {}
        for _, score in ipairs(plan.candidates or {}) do
            local rid = score.recipe and score.recipe.itemID
            if rid and not picked[rid] then runners[#runners + 1] = score end
        end
        if #runners > 0 then
            out[#out + 1] = {
                kind  = "mogulSection",
                title = string.format("Runners-up -- did not fit (%d)", #runners),
            }
            for _, score in ipairs(runners) do
                -- crafts=0 (didn't make budget); row factory uses per-craft figures.
                out[#out + 1] = buildPlanRowElement(
                    { recipe = score.recipe, crafts = 0, score = score },
                    viewMode, true)
            end
        end

        return out
    end,
})

Selectors:Register("mogul.title", {
    reads = {"session.ui.mogul.subView"},
    calls = {"mogul.plan"},
    fn = function(state, ctx)
        local subView = state.session.ui.mogul.subView
        if subView == "goblin" then return "Goblin" end
        local plan = Selectors:Call("mogul.plan", state, ctx)
        if not plan or #plan.rows == 0 then return "Mogul" end
        return string.format("Mogul (%d crafts planned)", plan.totals.crafts or 0)
    end,
})

-- Source-chip visibility in the Goblin header: shown only in the goblin subview,
-- and only when the addon is installed (Auctionator + TSM are gated; Auto + Direct
-- are always available). The active source is shown by the highlighted chip itself
-- (config.sourceActive_*), which is why the old static goblin.headerLabel is gone.
Selectors:Register("goblin.showSourceAuctionator", {
    calls = { "mogul.isSubView_goblin", "config.auctionatorAvailable" },
    fn = function(state, ctx)
        return Selectors:Call("mogul.isSubView_goblin", state, ctx)
           and Selectors:Call("config.auctionatorAvailable", state, ctx)
    end,
})
Selectors:Register("goblin.showSourceTSM", {
    calls = { "mogul.isSubView_goblin", "config.tsmAvailable" },
    fn = function(state, ctx)
        return Selectors:Call("mogul.isSubView_goblin", state, ctx)
           and Selectors:Call("config.tsmAvailable", state, ctx)
    end,
})

-- Column-aligned gold (zero shown as "0 <coin>"); shared formatter.
local moneyText = HDG.Format.FormatGoldZero

Selectors:Register("mogul.totalsLabel", {
    reads = { "session.ui.mogul.mode" },   -- read directly in fn (also in mogul.plan's closure)
    calls = {"mogul.plan"},
    fn = function(state, ctx)
        local plan = Selectors:Call("mogul.plan", state, ctx)
        if not plan then return "" end
        local t = plan.totals
        if t.crafts == 0 then
            return "No crafts planned -- no lumber, no learned recipes, or filters too tight."
        end
        local mode = state.session.ui.mogul.mode
        if mode == "collection" then
            return string.format("New appearances: %d  |  Mat cost: %s",
                t.uniqueDiscoveries or 0, moneyText(t.matSpend or 0))
        end
        -- Plain text: widget applies Theme:ColorCode at render time.
        return string.format("Revenue (mats free): +%s     Net profit (mats bought): +%s",
            moneyText(t.revenue or 0), moneyText(t.netProfit or 0))
    end,
})

-- ===== Lumber tracker rows =================================================
-- One row per lumber type; isActive marks tiers the plan consumed.
Selectors:Register("mogul.lumberRows", {
    reads = {"session.bag.tick"},   -- numbers paint via Theme:Register roles -> ApplyAll repaints on scheme swap
    calls = {"mogul.plan"},
    fn = function(state, ctx)
        local plan = Selectors:Call("mogul.plan", state, ctx)
        local out = {}
        if not (plan and HDG.Constants.LUMBER_DATA) then return out end

        -- Sum per-tier usage from plan rows.
        local used = {}
        for _, row in ipairs(plan.rows or {}) do
            for _, lr in ipairs(row.score and row.score.lumberReagents or {}) do
                used[lr.id] = (used[lr.id] or 0) + row.crafts * (lr.qty or 0)  -- exception(false-positive): used[] accumulator lazy-init (crafts/lr.qty numeric)
            end
        end

        for _, l in ipairs(HDG.Constants.LUMBER_DATA) do
            local have = HDG.BagObserver:GetTotal(l.id)
            local u = used[l.id] or 0  -- exception(boundary): sparse map
            out[#out + 1] = {
                kind      = "mogulLumberRow",
                id        = l.id,
                short     = l.shortName or l.name,
                expansion = l.expansion,
                have      = have,
                used      = u,
                leftover  = have - u,
                isActive  = u > 0,
            }
        end
        return out
    end,
})

-- Lumber section header: "Lumber used in plan: U / H held".
Selectors:Register("mogul.lumberHeaderLabel", {
    calls = { "mogul.lumberRows" },
    fn = function(state, ctx)
        local rows = Selectors:Call("mogul.lumberRows", state, ctx)
        local used, have = 0, 0
        for _, r in ipairs(rows) do
            used = used + (r.used or 0)
            have = have + (r.have or 0)
        end
        if used == 0 then
            return string.format("Lumber  -  %d held, none used", have)
        end
        return string.format("Lumber used in plan: %d / %d held", used, have)
    end,
})

-- Paired lumber rows: 2-up shape for the 2-column bottom layout (no scroll).
Selectors:Register("mogul.lumberRowsPaired", {
    calls = { "mogul.lumberRows" },
    fn = function(state, ctx)
        local rows = Selectors:Call("mogul.lumberRows", state, ctx)
        local out  = {}
        local half = math.ceil(#rows / 2)
        for i = 1, half do
            out[#out + 1] = {
                kind  = "mogulLumberRow2x",
                left  = rows[i],
                right = rows[i + half],   -- nil on last row if odd count
            }
        end
        return out
    end,
})

-- ===== Reagents to buy =====================================================
-- Shopping list rows from plan.shoppingList. Reads itemNames.tick so
-- ITEM_INFO_RESOLVED repaints names after async cache fills.
Selectors:Register("mogul.matsRows", {
    reads = {"session.itemNames.tick", "session.prices.tick"},
    calls = {"mogul.plan"},
    fn = function(state, ctx)
        local plan = Selectors:Call("mogul.plan", state, ctx)
        local out = {}
        if not (plan and plan.shoppingList) then return out end
        for _, mat in ipairs(plan.shoppingList) do
            local name = (HDG.ItemNameResolver:ResolveName(mat.id))
            out[#out + 1] = {
                kind      = "mogulMatRow",
                itemID    = mat.id,
                name      = name,
                qty       = mat.qty,
                unitPrice = mat.unitPrice,
                totalCost = mat.totalCost,
            }
        end
        return out
    end,
})

-- ===== Goblin sub-view =====================================================
-- Per-decor profit table with profession/knowledge/queue/auction filters + sortable columns.
Selectors:Register("goblin.rows", {
    memoized = true,
    calls = { "goblin.isTSMActive" },
    reads = {
        "account.config.scheme",   -- lumber column bakes Theme color codes -> re-emit on scheme swap to repaint
        "account.recipes",
        "account.collection.ownedDecorIDs",
        "account.craft.queue",
        "account.prices.ownedAuctions",
        "session.prices.tick",
        "session.bag.tick",
        "session.ui.mogul.goblin.profession",
        "session.ui.mogul.goblin.search",
        "session.ui.mogul.goblin.knowledge",
        "session.ui.mogul.goblin.queue",
        "session.ui.mogul.goblin.auctionsOnly",
        "session.ui.mogul.goblin.sortCol",
        "session.ui.mogul.goblin.sortDir",
        "account.config.preferredPriceAddon",
    },
    fn = function(state, ctx)
        local g = state.session.ui.mogul.goblin
        local profFilter   = g.profession
        local search       = g.search:lower()
        local knowledge    = g.knowledge
        local queue        = g.queue
        local auctionsOnly = g.auctionsOnly == true
        local sortCol      = g.sortCol
        local sortDir      = g.sortDir
        local isTSMActive  = Selectors:Call("goblin.isTSMActive", state, ctx)

        local recipesByItem = state.account.recipes
        -- Pre-build queue/auction sets for O(1) lookup per row.
        local queueSet = {}
        for _, q in ipairs(state.account.craft.queue) do
            if q.itemID then queueSet[q.itemID] = true end
        end
        local auctionSet = state.account.prices.ownedAuctions

        local data = HDG.Goblin:BuildProfitData()
        local out = {}
        for _, row in ipairs(data) do
            local keep = true
            -- Profession filter ("All" passes).
            if keep and profFilter ~= "All" and row.profession ~= profFilter then
                keep = false
            end
            -- Search filter (substring on name, case-insensitive).
            if keep and search ~= "" then
                if not (row.name and row.name:lower():find(search, 1, true)) then
                    keep = false
                end
            end
            -- Knowledge filter.
            if keep and knowledge ~= "all" then
                local rec = recipesByItem[row.itemID]
                if knowledge == "known" then
                    keep = rec and rec.selfKnown == true
                elseif knowledge == "alt" then
                    keep = rec and (rec.selfKnown == true or rec.altKnown == true)
                end
            end
            -- Queue filter.
            if keep and queue == "only" then
                keep = queueSet[row.itemID] == true
            elseif keep and queue == "hide" then
                keep = not queueSet[row.itemID]
            end
            -- Auctions filter.
            if keep and auctionsOnly then
                keep = auctionSet[row.itemID] ~= nil
            end
            if keep then out[#out + 1] = row end
        end

        -- Sort by user column; nil values sink to bottom regardless of direction.
        -- lumber column sorts by resolved shortName via file-local lazy index.
        local lumberShort = lumberShortByID()
        local function keyFor(row, col)
            if col == "name"      then return row.name end
            if col == "lumber"    then return lumberShort[row.lumberType] end
            if col == "perLum"    then return row.lumberValue end
            if col == "cost"      then return row.materialCost end
            if col == "sell"      then return row.sellPrice end
            if col == "tsmMin"    then return row.tsmMin end
            if col == "tsmMarket" then return row.tsmMarket end
            if col == "tsmRegion" then return row.tsmRegion end
            if col == "tsmPct"    then return row.tsmPct end
            if col == "saleRate"  then return row.saleRate end
            if col == "soldPerDay" then return row.soldPerDay end
            if col == "ahQty"     then return row.ahQty end
            if col == "profit"    then return row.profit end
            if col == "pct"       then return row.margin end
            return row.profit
        end
        local descMul = (sortDir == "desc") and 1 or -1
        table.sort(out, function(a, b)
            local av, bv = keyFor(a, sortCol), keyFor(b, sortCol)
            if av == nil and bv == nil then
                return (a.name or "") < (b.name or "")
            end
            if av == nil then return false end
            if bv == nil then return true  end
            if type(av) == "string" then
                if av == bv then return (a.name or "") < (b.name or "") end
                if descMul == 1 then return av > bv else return av < bv end
            end
            if av == bv then return (a.name or "") < (b.name or "") end
            if descMul == 1 then return av > bv else return av < bv end
        end)
        for i = 1, #out do
            out[i].kind        = "goblinRow"
            out[i].isTSMActive = isTSMActive
            -- Stamp ownedLumber into row so Configure reads ed (not BagObserver mid-paint). per ADR-041.
            out[i].ownedLumber = HDG.BagObserver:GetTotal(out[i].lumberType)
        end
        return out
    end,
})

-- Per-profession active-state selectors for pill `active` bindings.
do
    local function activeProf(target)
        return function(state)
            return state.session.ui.mogul.goblin.profession == target
        end
    end
    Selectors:Register("goblin.profActive_All",
        { reads = {"session.ui.mogul.goblin.profession"}, fn = activeProf("All") })
    -- entries 10-12 = gathering; skip
    for i, p in ipairs(HDG.Constants.PROFESSION_DATA or {}) do
        if i <= 9 and p.name then
            Selectors:Register("goblin.profActive_" .. p.name,
                { reads = {"session.ui.mogul.goblin.profession"}, fn = activeProf(p.name) })
        end
    end
end

-- Knowledge + queue tri-state pill active selectors, auctions toggle.
do
    local function activeKnow(target)
        return function(state)
            return state.session.ui.mogul.goblin.knowledge == target
        end
    end
    local function activeQueue(target)
        return function(state)
            return state.session.ui.mogul.goblin.queue == target
        end
    end
    Selectors:Register("goblin.knowActive_all",
        { reads = {"session.ui.mogul.goblin.knowledge"}, fn = activeKnow("all")   })
    Selectors:Register("goblin.knowActive_known",
        { reads = {"session.ui.mogul.goblin.knowledge"}, fn = activeKnow("known") })
    Selectors:Register("goblin.knowActive_alt",
        { reads = {"session.ui.mogul.goblin.knowledge"}, fn = activeKnow("alt")   })
    Selectors:Register("goblin.queueActive_all",
        { reads = {"session.ui.mogul.goblin.queue"}, fn = activeQueue("all")  })
    Selectors:Register("goblin.queueActive_only",
        { reads = {"session.ui.mogul.goblin.queue"}, fn = activeQueue("only") })
    Selectors:Register("goblin.queueActive_hide",
        { reads = {"session.ui.mogul.goblin.queue"}, fn = activeQueue("hide") })
    Selectors:Register("goblin.auctionsActive", {
        reads = {"session.ui.mogul.goblin.auctionsOnly"},
        fn = function(state)
            return state.session.ui.mogul.goblin.auctionsOnly == true
        end,
    })

    -- Bare-value selectors for the dropdown generator's isSelected computation.
    -- (knowledgeLabel / queueLabel retired: kind="dropdown" auto-renders selection text.)
    Selectors:Register("goblin.knowledge", {
        reads = {"session.ui.mogul.goblin.knowledge"},
        fn    = function(state) return state.session.ui.mogul.goblin.knowledge or "all" end,
    })
    Selectors:Register("goblin.queue", {
        reads = {"session.ui.mogul.goblin.queue"},
        fn    = function(state) return state.session.ui.mogul.goblin.queue or "all" end,
    })
    Selectors:Register("goblin.knowledgeMenuItems", {
        reads    = {},
        memoized = true,
        fn = function()
            return {
                { text = "All",         value = "all"   },
                { text = "Known",       value = "known" },
                { text = "Known + Alt", value = "alt"   },
            }
        end,
    })
    Selectors:Register("goblin.queueMenuItems", {
        reads    = {},
        memoized = true,
        fn = function()
            return {
                { text = "All",  value = "all"  },
                { text = "Only", value = "only" },
                { text = "Hide", value = "hide" },
            }
        end,
    })
end

-- (goblin.tsmPriceType removed: table renders all 3 TSM columns at once now.
--  account.config.tsmPriceMode still feeds the profit calc + TSM % column.)

-- Per-column header text + active-state selectors.
-- Active column gets ASCII arrow suffix (" v" / " ^"); inactive renders plain label.
do
    local labels = {
        name      = "Item Name", lumber    = "Lumber",    perLum    = "$/Lum",
        cost      = "Cost",      sell      = "Sell",
        tsmMin    = "Server",    tsmMarket = "Market",    tsmRegion = "Region",
        tsmPct    = "TSM %",     profit    = "Profit",    pct       = "%",
        ahQty     = "#AH",       saleRate  = "Rate",      soldPerDay = "/Day",
    }
    local function headerFn(col)
        return function(state)
            local g = state.session.ui.mogul.goblin
            local label = labels[col] or col
            if g.sortCol == col then
                return label .. ((g.sortDir == "asc") and " ^" or " v")
            end
            return label
        end
    end
    local function activeFn(col)
        return function(state)
            return state.session.ui.mogul.goblin.sortCol == col
        end
    end
    for col, _ in pairs(labels) do
        Selectors:Register("goblin.sortHeader_" .. col, {
            reads = {"session.ui.mogul.goblin.sortCol", "session.ui.mogul.goblin.sortDir"},
            fn = headerFn(col),
        })
        Selectors:Register("goblin.sortActive_" .. col, {
            reads = {"session.ui.mogul.goblin.sortCol"},
            fn = activeFn(col),
        })
    end
end

-- Footer label: "N items" (post-filter count).
-- Cold-start CTA gate: Direct cache never scanned AND no external price addon
-- to fall back to -> every profit column renders "-" with no guidance. Drives
-- the scan-hint banner above the Goblin list (UX review 2026-06-10 #3).
Selectors:Register("goblin.needsScanHint", {
    reads = { "account.prices.directCacheTime",
              "session.prices.auctionatorLoaded", "session.prices.tsmLoaded" },
    fn = function(state)
        if state.account.prices.directCacheTime then return false end
        if state.session.prices.auctionatorLoaded then return false end
        if state.session.prices.tsmLoaded then return false end
        return true
    end,
})

Selectors:Register("goblin.statusLabel", {
    calls = {"goblin.rows"},
    fn = function(state, ctx)
        local rows = Selectors:Call("goblin.rows", state, ctx)
        return string.format("%d items", #rows)
    end,
})

-- "Queue All" enabled when plan has at least one row.
Selectors:Register("mogul.queueAllEnabled", {
    calls = { "mogul.plan" },
    fn = function(state, ctx)
        local plan = Selectors:Call("mogul.plan", state, ctx)
        return plan and plan.rows and #plan.rows > 0
    end,
})

-- "Send to Auctionator" enabled when Auctionator is loaded AND plan has a shopping list.
Selectors:Register("mogul.auctionatorEnabled", {
    reads = { "session.prices.auctionatorLoaded" },
    calls = { "mogul.plan" },
    fn = function(state, ctx)
        if not state.session.prices.auctionatorLoaded then return false end
        local plan = Selectors:Call("mogul.plan", state, ctx)
        return plan and plan.shoppingList and #plan.shoppingList > 0
    end,
})

Selectors:Register("mogul.matsTitle", {
    calls = {"mogul.plan"},
    fn = function(state, ctx)
        local plan = Selectors:Call("mogul.plan", state, ctx)
        if not plan or not plan.shoppingList or #plan.shoppingList == 0 then
            return "Reagents to buy: none"
        end
        local total = 0
        for _, m in ipairs(plan.shoppingList) do total = total + (m.totalCost or 0) end
        return string.format("Reagents to buy: %d items, total %s",
            #plan.shoppingList, moneyText(total))
    end,
})
