HDG = HDG or {}

-- Action metadata for the middleware chain. Single source of truth that the
-- CombatMiddleware + PersistenceMiddleware consult. Keep aligned with the
-- reducer chain in Core/Store.lua:_RawDispatch -- when an action mutates
-- account state, mark it persists=true; when it touches secure frames,
-- combatUnsafe=true. HDG's UI is non-secure today, so no actions are
-- combat-unsafe at the state-mutation level (the combat queue applies to
-- UI refresh in MainFrame, not to dispatches).
local function BuildActionMeta()
    local A = HDG.Constants.ACTIONS
    local P = HDG.Paths
    -- T: common-case meta (persists=false, combatUnsafe=false). Accepts static list, fn, or "*".
    local function T(invalidates)
        return { persists = false, combatUnsafe = false,
                 invalidates = invalidates }
    end
    -- TR: same as T but retainsScroll -- scrollbox dispatchers pass RetainScrollPosition.
    local function TR(invalidates)
        return { persists = false, combatUnsafe = false,
                 retainsScroll = true, invalidates = invalidates }
    end
    -- TN: same as T but noisy -- suppresses LoggerMiddleware chat for high-frequency actions.
    local function TN(invalidates)
        return { persists = false, combatUnsafe = false,
                 noisy = true, invalidates = invalidates }
    end
    -- TRC: TR + treeCollapseOnly -- dispatchTreeList mutates SetCollapsed in-place instead of rebuilding.
    local function TRC(invalidates)
        return { persists = false, combatUnsafe = false,
                 retainsScroll = true, treeCollapseOnly = true,
                 invalidates = invalidates }
    end
    -- joinKey: dynamic single-path invalidation keyed by one payload field.
    -- Collapses ~17 identical function(action) bodies; Paths.Join drops nil/"" safely.
    local function joinKey(base, field)
        return function(action)
            return { P.Join(base, action.payload and action.payload[field]) }
        end
    end
    return {
        -- Shape: { persists, combatUnsafe, invalidates }
        -- invalidates: list of dotted paths | fn(action)->list | "*" (broad). Defaults to "*" if absent.
        [A.CONFIG_SET]                   = { persists = true,  combatUnsafe = false,
            invalidates = joinKey("account.config", "key") },
        [A.CONFIG_SCALE_STEP]            = { persists = true,  combatUnsafe = false,
            invalidates = { "account.config.scale" } },
        [A.HARD_RESET]                   = { persists = true,  combatUnsafe = false,
            invalidates = "*" },

        -- PROFILE_SWITCH is "*": swapping the active profile re-keys every Config:Get value.
        [A.PROFILE_CREATE]               = { persists = true,  combatUnsafe = false,
            invalidates = { "account.profileList" } },
        [A.PROFILE_SWITCH]               = { persists = true,  combatUnsafe = false,
            invalidates = "*" },
        [A.PROFILE_DELETE]               = { persists = true,  combatUnsafe = false,
            invalidates = { "account.profileList" } },
        [A.UI_SET_PERSISTENT]            = { persists = true,  combatUnsafe = false,
            invalidates = joinKey("account.ui", "key") },
        [A.UI_SET_TRANSIENT]             = { persists = false, combatUnsafe = false,
            invalidates = function(action)
                local p = action.payload or {}
                if p.view then
                    return { P.Join("session.ui", p.view, p.key) }
                end
                return { P.Join("session.ui", p.key) }
            end },
        [A.REMOVALIST_PICK_PLOT]         = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.removalist.sourcePlot", "session.ui.removalist.targetPlot" } },
        [A.REMOVALIST_SWAP]              = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.removalist.sourcePlot", "session.ui.removalist.targetPlot" } },
        [A.REMOVALIST_CLEAR]             = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.removalist.sourcePlot", "session.ui.removalist.targetPlot" } },
        [A.REMOVALIST_SET_LETTER_FILTER] = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.removalist.letterFilter" } },
        [A.REMOVALIST_SET_PLOT]          = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.removalist.sourcePlot", "session.ui.removalist.targetPlot" } },
        [A.MAIN_WINDOW_TOGGLE]           = { persists = true,  combatUnsafe = false,
            invalidates = { "account.ui.mainWindowShown" } },
        [A.NAV_TOGGLE_GROUP]             = { persists = true,  combatUnsafe = false,
            invalidates = { "account.ui.nav.collapsedGroups" } },
        [A.SESSION_END]                  = { persists = true,  combatUnsafe = false,
            invalidates = { "account.ui.mainWindowShown",
                            "account.ui.shoppingWidgetShown",
                            "account.ui.zonePopupShown",
                            "account.lumber.config.windowVisible" } },
        [A.COMBAT_ENTER] = T({ "session.combat.inLockdown" }),
        [A.COMBAT_EXIT] = T({ "session.combat.inLockdown", "session.combat.queued" }),
        [A.COMBAT_QUEUE_ACTION] = T({ "session.combat.queued" }),
        [A.ACQ_SET_ITEMS_VIEW_MODE] = T({ "account.ui.acquisition.itemsViewMode" }),
        [A.ACQ_SET_PRESET] = T({ "session.ui.acquisition.preset" }),
        [A.ACQ_TOGGLE_ADVANCED_FILTERS] = T({ "session.ui.acquisition.advancedFiltersOpen" }),
        [A.ACQ_TOGGLE_MISSING] = T({ "session.ui.acquisition.missingOnly" }),
        -- Pure signal; actual data changes carried by the narrow delta actions.
        [A.DECOR_CATALOG_READY]          = { persists = false, combatUnsafe = false,
            invalidates = { "session.catalog.sweepGeneration" } },

        -- Structured logging. Each scoped to its sub-path so log churn never invalidates unrelated selectors.
        [A.LOG_PUSH] = T({ "session.log.entries" }),
        [A.LOG_CLEAR] = T({ "session.log.entries" }),
        [A.LOG_SET_FILTER] = T({ "session.log.tabFilter" }),
        [A.LOG_TOGGLE_AUTOSCROLL] = T({ "session.log.tabFilter" }),
        [A.LOG_TRACE_TOGGLE] = T({ "session.log.activeTraces" }),

        -- Catalog reconciliation. Persisted (cache survives /reload via HDG_DB.account.collection).
        [A.COLLECTION_BULK_LOAD]           = { persists = true,  combatUnsafe = false,
            invalidates = { "account.collection" } },
        [A.COLLECTION_RESET]               = { persists = true,  combatUnsafe = false,
            invalidates = { "account.collection" } },
        [A.COLLECTION_ITEM_LEARNED]        = { persists = true,  combatUnsafe = false,
            invalidates = { "account.collection.ownedDecorIDs" } },
        [A.COLLECTION_ITEM_REMOVED]        = { persists = true,  combatUnsafe = false,
            invalidates = { "account.collection.ownedDecorIDs" } },
        -- No-ops in reducer; observer's Subscribe handler calls UpsertRow/RemoveRow/PatchCounts.
        [A.COLLECTION_CATALOG_ROW_ADDED]   = { persists = false, combatUnsafe = false,
            invalidates = { "session.catalog.sweepGeneration" } },
        [A.COLLECTION_CATALOG_ROW_REMOVED] = { persists = false, combatUnsafe = false,
            invalidates = { "session.catalog.sweepGeneration",
                            "account.collection.ownedDecorIDs" } },
        [A.COLLECTION_CATALOG_ROW_COUNTS_UPDATED] = { persists = false, combatUnsafe = false,
            invalidates = { "session.catalog.sweepGeneration" } },

        -- ===== Decor filter actions ================================
        -- All session-scoped; never invalidate cold catalog memos (per ADR-012).
        [A.DECOR_SET_TOP_FILTER] = T({
                "session.ui.decor.filters.topFilter",
                "session.ui.decor.filters.activeTag",
            }),
        [A.DECOR_SET_TAG] = T({ "session.ui.decor.filters.activeTag" }),
        [A.DECOR_TOGGLE_ONLY_UNCOLLECTED] = T({ "session.ui.decor.filters.onlyUncollected" }),
        [A.DECOR_TOGGLE_ONLY_STORED] = T({ "session.ui.decor.filters.onlyStored" }),
        [A.DECOR_SET_SEARCH] = TN({ "session.ui.decor.searchQuery" }),

        -- ===== Favorites / Notes ====================================
        [A.FAVORITE_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.favorites" } },
        -- Per-itemID invalidation so editing one note refreshes only that note's selectors.
        [A.NOTE_SET]   = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.userNotes", "itemID") },
        [A.NOTE_CLEAR] = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.userNotes", "itemID") },

        -- ===== Vendor notes =========================================
        [A.VENDOR_NOTE_SET]   = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.vendorNotes", "npcID") },
        [A.VENDOR_NOTE_CLEAR] = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.vendorNotes", "npcID") },

        -- ===== Recipe knowledge =====================================
        [A.RECIPE_KNOWLEDGE_UPDATED] = { persists = true, combatUnsafe = false,
            invalidates = { "account.recipes" } },

        -- ===== Per-character roster (alts) =========================
        [A.CHARACTER_PROFESSION_UPDATED] = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.characters", "charKey") },
        [A.CHARACTER_DELETED]            = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.characters", "charKey") },
        [A.CHARACTER_HIDDEN] = { persists = true, combatUnsafe = false,
            invalidates = function(action)
                local key = action.payload and action.payload.charKey
                if key then
                    return { P.Join("account.characters", tostring(key), "hidden") }
                end
                return { "account.characters" }
            end },
        [A.CHARACTER_HIDDEN_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = function(action)
                local key = action.payload and action.payload.charKey
                if key then
                    return { P.Join("account.characters", tostring(key), "hidden") }
                end
                return { "account.characters" }
            end },

        -- invalidates "*": FrameVisibility paints nothing while hidden, so catch-up must repaint everything.
        [A.MAIN_WINDOW_OPENING] = { persists = false, combatUnsafe = false,
            invalidates = "*" },

        [A.ALTS_SET_CHARS_POPULATION] = T({ "session.ui.alts.charsPopulation" }),

        -- HouseEditor companion. Standalone window; path-level invalidation for precise dirty flags.
        [A.COMPANION_TOGGLE]                = T({ "session.ui.companion.windowShown" }),
        [A.COMPANION_SET_MODE]              = T({ "session.ui.companion.mode", "session.ui.companion.selectedItemID" }),
        [A.COMPANION_SELECT_ITEM]           = T({ "session.ui.companion.selectedItemID" }),
        [A.COMPANION_TOGGLE_COST]           = T({ "session.ui.companion.showCost" }),
        [A.COMPANION_CYCLE_IO]              = T({ "session.ui.companion.ioFilter" }),
        [A.COMPANION_SET_POSITION]          = { persists = true, combatUnsafe = false,
            invalidates = { "account.ui.companion.window" } },
        [A.COMPANION_SET_LAUNCHER_POSITION] = { persists = true, combatUnsafe = false,
            invalidates = { "account.ui.companion.launcher" } },

        -- HouseTab. Snapshot bumps snapshotTick (broad); per-widget overrides invalidate their specific path.
        [A.HOUSE_SNAPSHOT_UPDATED]          = T({ "session.house.snapshot", "session.house.snapshotTick" }),
        [A.HOUSE_LIST_UPDATED]              = T({ "session.house.ownedHouses" }),
        [A.HOUSE_LEVEL_UPDATED]             = T({ "session.house.ownedHouses" }),
        [A.ACTIVE_NEIGHBORHOOD_UPDATED]     = T({ "session.house.activeNeighborhoodGUID" }),
        [A.HOUSE_REWARDS_RECEIVED]          = T({ "session.house.rewardsByLevel" }),
        [A.DAILY_BESTOWED_UPDATED]          = T({ "session.daily.bestowed" }),
        [A.DAILY_ORC_QUOTE_SET]             = T({ "session.daily.orcQuote" }),
        [A.HOUSETAB_TOGGLE_WIDGET]          = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.ui.houseTab.enabled", "widgetID") },
        [A.HOUSETAB_SET_ORDER]              = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.ui.houseTab.order", "widgetID") },
        [A.HOUSETAB_SET_ORDERS]             = { persists = true, combatUnsafe = false,
            invalidates = { "account.ui.houseTab.order" } },
        [A.HOUSETAB_REORDER_WIDGET]         = { persists = true, combatUnsafe = false,
            invalidates = { "account.ui.houseTab.order" } },
        [A.HOUSETAB_SET_WIDTH]              = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.ui.houseTab.width", "widgetID") },
        [A.HOUSETAB_RESIZE_WIDGET]          = { persists = true, combatUnsafe = false,
            invalidates = joinKey("account.ui.houseTab.layoutOverrides", "widgetID") },
        [A.HOUSETAB_RESET_LAYOUT]           = { persists = true, combatUnsafe = false,
            invalidates = { "account.ui.houseTab.enabled", "account.ui.houseTab.order",
                            "account.ui.houseTab.width", "account.ui.houseTab.layoutOverrides" } },
        [A.HOUSETAB_TOGGLE_PICKER]          = T({ "session.ui.houseTab.pickerOpen" }),
        [A.HOUSETAB_TOGGLE_DESIGN_MODE]     = T({ "session.ui.houseTab.designMode" }),
        [A.SESSION_IDENTITY_SET]            = T({ "session.identity" }),

        -- Trainers. TR not TRC: bound as `scrollbox`, so treeCollapseOnly would be a no-op.
        [A.TRAINERS_TOGGLE_PROFESSION]       = TR(joinKey("session.ui.trainers.expandedProfessions", "profession")),
        [A.TRAINERS_TOGGLE_MIDNIGHT_SECTION] = TR({ "session.ui.trainers.midnightExpanded" }),
        [A.TRAINERS_SELECT_TRAINER]          = T({ "session.ui.trainers.selectedNpcID" }),

        -- Mogul. All session-scoped, narrow path-level invalidation.
        [A.MOGUL_SET_MODE] = T({ "session.ui.mogul.mode" }),
        [A.MOGUL_SET_VIEW] = T({ "session.ui.mogul.viewMode" }),
        [A.MOGUL_SET_OPTIMIZE_BY] = T({ "session.ui.mogul.optimizeBy" }),
        [A.MOGUL_SET_SUBVIEW] = T({ "session.ui.mogul.subView" }),
        -- Supply Impact: all three invalidate the full sub-tree so mogul.plan re-runs.
        [A.MOGUL_SET_SUPPLY_MODE]   = T({ "session.ui.mogul.supplyImpact.mode",
                                          "session.ui.mogul.supplyImpact.smoothPct",
                                          "session.ui.mogul.supplyImpact.capN" }),
        [A.MOGUL_SET_SUPPLY_SMOOTH] = T({ "session.ui.mogul.supplyImpact.smoothPct" }),
        [A.MOGUL_SET_SUPPLY_CAP]    = T({ "session.ui.mogul.supplyImpact.capN" }),
        -- Frugal mode: re-rank planner by dampened lumber cost so smaller crafts outweigh big-lumber ones.
        [A.MOGUL_SET_FRUGAL]        = T({ "session.ui.mogul.frugal" }),
        [A.MOGUL_TOGGLE_FRUGAL]     = T({ "session.ui.mogul.frugal" }),
        [A.GOBLIN_SET_PROFESSION] = T({ "session.ui.mogul.goblin.profession" }),
        [A.GOBLIN_SET_SEARCH] = TN({ "session.ui.mogul.goblin.search" }),
        [A.GOBLIN_SET_KNOWLEDGE] = T({ "session.ui.mogul.goblin.knowledge" }),
        [A.GOBLIN_SET_QUEUE] = T({ "session.ui.mogul.goblin.queue" }),
        [A.GOBLIN_TOGGLE_AUCTIONS] = T({ "session.ui.mogul.goblin.auctionsOnly" }),
        -- Column sort: both sortCol + sortDir flip on a single click.
        [A.GOBLIN_SET_SORT] = T({ "session.ui.mogul.goblin.sortCol",
                            "session.ui.mogul.goblin.sortDir" }),
        [A.GOBLIN_TOGGLE_ROW_EXPAND] = T({ "session.ui.mogul.goblin.expandedItemID" }),
        -- Both bump session.prices.tick so Mogul + Goblin selectors repaint.
        [A.PRICES_SET_PREFERRED_SOURCE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.config.preferredPriceAddon", "session.prices.tick" } },
        [A.PRICES_SET_TSM_MODE]         = { persists = true, combatUnsafe = false,
            invalidates = { "account.config.tsmPriceMode", "session.prices.tick" } },

        -- ===== Crafting queue + history ============================
        [A.CRAFT_QUEUE_ADD]       = { persists = true, combatUnsafe = false,
            invalidates = { "account.craft.queue" } },
        [A.CRAFT_QUEUE_REMOVE]    = { persists = true, combatUnsafe = false,
            invalidates = { "account.craft.queue" } },
        [A.CRAFT_QUEUE_CLEAR]     = { persists = true, combatUnsafe = false,
            invalidates = { "account.craft.queue" } },
        [A.CRAFT_QUEUE_DECREMENT] = { persists = true, combatUnsafe = false,
            invalidates = { "account.craft.queue" } },
        [A.CRAFT_HISTORY_PUSH]    = { persists = true, combatUnsafe = false,
            invalidates = { "account.craft.history.entries", "session.styles.cacheTick" } },

        -- ===== Recipes tab session UI ==============================
        [A.RECIPES_SET_SEARCH] = TN({ "session.ui.recipes.searchQuery" }),
        [A.RECIPES_SET_SECTION_EXPAND] = { persists = false, combatUnsafe = false,
            invalidates = joinKey("session.ui.recipes.expandedSections", "key") },
        [A.RECIPES_SET_MATERIALS_DEPTH]       = T({ "session.ui.recipes.materialsDepth" }),
        [A.RECIPES_TOGGLE_MATERIALS_GROUPING] = T({ "session.ui.recipes.materialsGrouping" }),
        [A.RECIPES_TOGGLE_FILTER]      = { persists = false, combatUnsafe = false,
            invalidates = joinKey("session.ui.recipes.filters", "filter") },
        [A.RECIPES_SELECT_RECIPE] = T({ "session.ui.recipes.selectedRecipeID", "session.ui.recipes.queueSelectedRecipeID" }),
        [A.RECIPES_TOGGLE_QUEUE_SELECTION] = T({ "session.ui.recipes.queueSelectedRecipeID" }),
        [A.RECIPES_TOGGLE_PROFESSION] = T({ "account.ui.recipes.professionFilterByChar" }),
        [A.RECIPES_TOGGLE_EXPANSION] = T({ "account.ui.recipes.expansionFilter" }),
        [A.RECIPES_SET_LIST_FILTER] = T({ "session.ui.recipes.listFilter" }),
        [A.RECIPES_SELECT_MATERIAL] = T({ "session.ui.warehouse.selectedMaterialID" }),
        [A.RECIPES_SET_WH_MAT_SEARCH] = TN({ "session.ui.warehouse.matSearch" }),
        -- Atomic per-tab filter reset. recipes also touches its account.ui.* filters.
        [A.UI_FILTER_RESET] = { persists = false, combatUnsafe = false,
            invalidates = function(action)
                local tab = action.payload and action.payload.tab
                if tab and tab ~= "" then
                    if tab == "recipes" then
                        -- recipes' expansion + profession filters are persisted in
                        -- account.ui, outside the session.ui.recipes subtree --
                        -- invalidate all three so the dropdowns + run repaint
                        -- after a reset.
                        return { "session.ui.recipes",
                                 "account.ui.recipes.expansionFilter",
                                 "account.ui.recipes.professionFilterByChar" }
                    end
                    return { "session.ui." .. tab }
                end
                return { "session.ui" }  -- fallback: no tab payload -> broad invalidate
            end },

        -- ===== Cross-feature observer dispatches ===================
        [A.ITEM_INFO_RESOLVED] = T({ "session.itemNames.tick",
                                     "session.itemNames.names",
                                     "account.craft.queue" }),
        [A.QUEST_INFO_RESOLVED] = T({ "session.questNames.tick" }),
        [A.QUEST_STATUS_RESOLVED] = T({ "session.questStatus.tick" }),
        [A.QUEST_COMPLETION_RECORDED] = { persists = true, combatUnsafe = false,
            invalidates = { "account.questCompletions" } },
        [A.ACHIEVEMENT_STATUS_RESOLVED] = T({ "session.achievementStatus.tick" }),
        [A.BAG_INVENTORY_UPDATED] = T({ "session.bag.tick" }),

        -- ===== PriceSource ========================================
        -- All PRICES_* bump session.prices.tick. SCAN_STARTED also wipes directCache (replace-on-scan).
        [A.PRICES_CONFIG_CHANGED] = T({ "session.prices.tick" }),
        [A.PRICES_DIRECT_SCAN_STARTED] = { persists = true, combatUnsafe = false,
            invalidates = { "session.prices.scanning", "session.prices.scanTotal",
                            "session.prices.tick",
                            "account.prices.directCache", "account.prices.directQtyCache",
                            "account.prices.directCacheTime" } },
        [A.PRICES_DIRECT_SCAN_PROGRESS] = T({ "session.prices.scanFound" }),
        [A.PRICES_DIRECT_SCAN_BATCH]      = { persists = true,  combatUnsafe = false,
            invalidates = { "account.prices.directCache", "account.prices.directQtyCache",
                            "session.prices.tick" } },
        [A.PRICES_DIRECT_SCAN_COMPLETED]  = { persists = true,  combatUnsafe = false,
            invalidates = { "account.prices.directCache", "account.prices.directQtyCache",
                            "account.prices.directCacheTime",
                            "session.prices.scanning",  "session.prices.tick" } },
        [A.PRICES_DIRECT_CACHE_CLEARED]   = { persists = true,  combatUnsafe = false,
            invalidates = { "account.prices.directCache", "account.prices.directQtyCache",
                            "account.prices.directCacheTime",
                            "session.prices.tick" } },
        [A.PRICES_OWNED_AUCTIONS_UPDATED] = { persists = true,  combatUnsafe = false,
            invalidates = { "account.prices.ownedAuctions", "session.prices.tick" } },
        [A.PRICES_ADDONS_AVAILABILITY_CHANGED] = T({ "session.prices.tsmLoaded", "session.prices.auctionatorLoaded",
                            "session.prices.tick" }),

        -- ===== Styles =================================================
        [A.STYLES_SET_VIEW] = T({ "session.ui.styles.view",
                                  "session.ui.styles.smartset.draft.displayName" }),
        [A.STYLES_INVALIDATE_CACHE] = T({ "session.styles.cacheTick" }),
        [A.STYLES_LANDING_SET_FILTER]    = T({ "session.ui.styles.landing.filter" }),
        [A.STYLES_LANDING_SET_SEARCH]    = TN({ "session.ui.styles.landing.search" }),
        [A.STYLES_LANDING_TOGGLE_SECTION] = T(joinKey("session.ui.styles.landing.expandedSections", "type")),
        [A.STYLES_SELECT_COLLECTION]     = T({ "session.ui.styles.selectedID" }),
        [A.STYLES_DETAIL_SELECT_ITEM]    = TR({ "session.ui.styles.detail.selectedItemID" }),
        [A.STYLES_DETAIL_SET_SEARCH]     = TN({ "session.ui.styles.detail.search" }),
        -- Detail actions registered now so the boot validator catches typos when dispatched.
        [A.STYLES_DETAIL_SET_VIEWMODE]   = T({ "session.ui.styles.detail.viewMode" }),
        [A.STYLES_DETAIL_SET_FILTER]     = T({ "session.ui.styles.detail.sourceFilter" }),
        [A.STYLES_DETAIL_SET_SUBCAT]     = T({ "session.ui.styles.detail.subcatFilter" }),
        [A.STYLES_INVALIDATE_STYLE]      = T({ "session.styles.cacheTick" }),
        [A.STYLES_CACHE_BUILDING_STARTED]  = T({ "session.styles.cacheTick" }),  -- notification-only; pin to cacheTick for now
        [A.STYLES_CACHE_BUILDING_FINISHED] = T({ "session.styles.cacheTick" }),
        [A.STYLES_CURATOR_SET_SOURCE]    = T({ "session.ui.styles.curator.sourceMode",
                                               "session.ui.styles.curator.selectedItems",
                                               "session.ui.styles.curator.selectedCount" }),
        [A.STYLES_CURATOR_SET_CATEGORY]  = T({ "session.ui.styles.curator.focusedCategoryID",
                                                "session.ui.styles.curator.focusedSubcategoryID" }),
        [A.STYLES_CURATOR_SET_SUBCATEGORY] = T({ "session.ui.styles.curator.focusedSubcategoryID" }),
        [A.STYLES_CURATOR_TOGGLE_SELECT] = TR({ "session.ui.styles.curator.selectedItems" }),
        [A.STYLES_CURATOR_CLEAR_SELECT]  = TR({ "session.ui.styles.curator.selectedItems",
                                                "session.ui.styles.curator.selectedCount" }),
        -- Move + undo invalidate both source + target collections (payload only mentions targetID).
        [A.STYLES_CURATOR_MOVE]          = T({ "account.collections",
                                               "session.ui.styles.curator.selectedItems",
                                               "session.ui.styles.curator.recentUndo" }),
        [A.STYLES_CURATOR_UNDO]          = T({ "account.collections",
                                               "session.ui.styles.curator.recentUndo" }),
        [A.STYLES_CURATOR_UNDO_AT]       = T({ "account.collections",
                                               "session.ui.styles.curator.recentUndo" }),
        -- HOVER fires ~50+/sec; noisy suppresses chat-print while dispatch still runs.
        [A.STYLES_CURATOR_HOVER]         = { persists = false, combatUnsafe = false,
            noisy = true, retainsScroll = true,
            invalidates = { "session.ui.styles.curator.hoverItemID" } },
        [A.STYLES_CURATOR_SELECT_TARGET] = TR({ "session.ui.styles.curator.selectedTargetID" }),
        [A.STYLES_CREATE_STYLE]          = T({ "account.collections",
                                               "session.ui.styles.curator.selectedTargetID" }),
        [A.STYLES_RENAME_STYLE]          = T({ "account.collections" }),
        [A.STYLES_DUPLICATE_STYLE]       = T({ "account.collections",
                                               "session.ui.styles.curator.selectedTargetID" }),
        [A.STYLES_DELETE_STYLE]          = T({ "account.collections",
                                               "account.vendorShoppingLists",   -- shopping lists live here; deleted via the "vsl:" id prefix
                                               "session.ui.styles.curator.selectedTargetID" }),
        -- Wired for boot-validator exhaustiveness; no state mutation.
        [A.STYLES_EDIT_STYLE]            = T({ "session.ui.styles.view",
                                               "session.ui.styles.curator.sourceMode",
                                               "session.ui.styles.curator.selectedItems",
                                               "session.ui.styles.curator.selectedCount",
                                               "session.ui.styles.curator.selectedTargetID" }),
        -- Smart Set Builder. SAVE writes account.collections.
        [A.STYLES_SMARTSET_BEGIN]            = T({ "session.ui.styles.smartset" }),
        [A.STYLES_SMARTSET_SET_FIELD]        = T(joinKey("session.ui.styles.smartset.draft", "field")),
        [A.STYLES_SMARTSET_SET_AXIS]         = T({ "session.ui.styles.smartset.activeAxis" }),
        [A.STYLES_SMARTSET_SET_SEVERITY_TAB] = T({ "session.ui.styles.smartset.activeSeverity" }),
        [A.STYLES_SMARTSET_TOGGLE_TAG]       = T({ "session.ui.styles.smartset.rules",
                                                   "session.ui.styles.smartset.dirty",
                                                   "session.ui.styles.smartset.draft.description" }),
        [A.STYLES_SMARTSET_CLEAR_ALL]        = T({ "session.ui.styles.smartset.rules",
                                                   "session.ui.styles.smartset.dirty",
                                                   "session.ui.styles.smartset.draft.description" }),
        [A.STYLES_SMARTSET_SAVE]             = T({ "account.collections",
                                                   "session.ui.styles.smartset" }),
        [A.STYLES_SMARTSET_CANCEL]           = T({ "session.ui.styles.smartset" }),
        -- Snapshot + Import. Both write account.collections; persists=true for immediate SV save.
        [A.STYLES_SNAPSHOT_PLACED]           = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.STYLES_PLACED_DECOR_OBSERVED]       = T({ "session.styles.placedDecor" }),
        [A.STYLES_PLACED_DECOR_OBSERVED_BATCH] = T({ "session.styles.placedDecor" }),
        -- Removal also appends a "removed" RecentActivity event.
        [A.STYLES_PLACED_DECOR_REMOVED]        = { persists = true, combatUnsafe = false,
            invalidates = { "session.styles.placedDecor", "account.recentActivity" } },
        [A.STYLES_PLACED_DECOR_CLEAR]          = T({ "session.styles.placedDecor" }),
        -- Recent Activity: persisted per-house edit-session history.
        [A.RECENT_SESSION_START] = { persists = true, combatUnsafe = false,
            invalidates = { "account.recentActivity" } },
        [A.RECENT_DECOR_PLACED]  = { persists = true, combatUnsafe = false,
            invalidates = { "account.recentActivity" } },
        [A.STYLES_IMPORT_SET_URL]            = T({ "session.ui.styles.import.urlText",
                                                   "session.ui.styles.import.parseDisplayName",
                                                   "session.ui.styles.import.parseSource",
                                                   "session.ui.styles.import.previewItems",
                                                   "session.ui.styles.import.parseError" }),
        [A.STYLES_IMPORT_PARSE]              = T({ "session.ui.styles.import.previewItems",
                                                   "session.ui.styles.import.parseError",
                                                   "session.ui.styles.import.parseDisplayName",
                                                   "session.ui.styles.import.parseSource" }),
        [A.STYLES_IMPORT_COMMIT]             = T({ "account.collections",
                                                   "session.ui.styles.import" }),
        [A.STYLES_IMPORT_RESET]              = T({ "session.ui.styles.import" }),
        [A.COLLECTION_STYLE_ITEM_ADDED]   = { persists = true,  combatUnsafe = false,
            retainsScroll = true,  -- mid-curate item move; don't yank user to top
            invalidates = function(action)
                local id = action.payload and action.payload.collectionID
                if id then
                    return { P.Join("account.collections", id, "items") }
                end
                return { "account.collections" }
            end },
        [A.COLLECTION_STYLE_ITEM_REMOVED] = { persists = true,  combatUnsafe = false,
            retainsScroll = true,
            invalidates = function(action)
                local id = action.payload and action.payload.collectionID
                if id then
                    return { P.Join("account.collections", id, "items") }
                end
                return { "account.collections" }
            end },

        -- ===== Shopping list ==========================================
        [A.SHOPPING_WIDGET_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.ui.shoppingWidgetShown" } },
        [A.SHOPPING_LIST_CREATE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists", "account.activeShoppingListId",
                            "account.shoppingListSeq" } },
        [A.SHOPPING_LIST_DELETE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists", "account.activeShoppingListId" } },
        [A.SHOPPING_LIST_RENAME] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists" } },
        [A.SHOPPING_LIST_DUPLICATE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists", "account.shoppingListSeq" } },
        [A.SHOPPING_LIST_ACTIVATE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.activeShoppingListId" } },
        [A.SHOPPING_LIST_CLEAR] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists" } },
        [A.SHOPPING_TOGGLE_EXPANDED] = T({ "session.ui.shoppingList.expanded" }),
        [A.SHOPPING_LIST_SET_META] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists" } },
        [A.SHOPPING_LIST_IMPORT] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists", "account.activeShoppingListId",
                            "account.shoppingListSeq" } },
        [A.SHOPPING_ITEM_ADD] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists" } },
        [A.SHOPPING_ITEM_REMOVE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists" } },
        [A.SHOPPING_ITEM_SET_QTY] = { persists = true, combatUnsafe = false,
            invalidates = { "account.vendorShoppingLists" } },

        -- ===== Zone Scanner ===========================================
        [A.ZONE_CHANGED] = { persists = false, combatUnsafe = false,
            invalidates = { "session.zone.currentMapID",
                            "session.zone.currentZoneName",
                            "session.ui.zoneScanner.expanded" } },
        [A.ZONE_POPUP_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.ui.zonePopupShown" } },
        [A.ZONE_TOGGLE_VENDOR] = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.zoneScanner.expanded" } },
        [A.ZONE_SET_SEARCH] = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.zoneScanner.searchQuery" } },
        [A.ZONE_TOGGLE_COLLECTED] = { persists = false, combatUnsafe = false,
            invalidates = { "session.ui.zoneScanner.showCollected" } },

        -- ===== Lumber Tracker =========================================
        [A.LUMBER_HARVESTED] = { persists = false, combatUnsafe = false,
            invalidates = { "session.lumber.blips", "session.lumber.tick",
                            "account.lumber.sessions" } },
        [A.LUMBER_SESSION_START] = { persists = true, combatUnsafe = false,
            invalidates = { "session.lumber.activeFarmingID",
                            "account.lumber.sessions" } },
        [A.LUMBER_SESSION_END] = { persists = true, combatUnsafe = false,
            invalidates = { "session.lumber.activeFarmingID",
                            "account.lumber.sessions" } },
        [A.LUMBER_HISTORY_PUSH] = { persists = true, combatUnsafe = false,
            invalidates = { "account.lumber.history" } },   -- reducer writes both .entries AND .nextID
        [A.LUMBER_BLIP_GC] = { persists = false, combatUnsafe = false,
            invalidates = { "session.lumber.blips" } },
        [A.LUMBER_WINDOW_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.lumber.config.windowVisible" } },
        [A.LUMBER_WINDOW_POSITION_SET] = { persists = true, combatUnsafe = false,
            invalidates = { "account.lumber.config.position" } },
        [A.LUMBER_RADAR_COLLAPSE_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.lumber.config.radarCollapsed" } },
        [A.LUMBER_AUTOSHOW_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.lumber.config.autoShowOnHarvest" } },
        [A.LUMBER_LIST_COLLAPSE_TOGGLE] = { persists = true, combatUnsafe = false,
            invalidates = { "account.lumber.config.listCollapsed" } },
        [A.LUMBER_RADAR_SCALE_SET] = { persists = true, combatUnsafe = false,
            invalidates = { "account.lumber.config.radarScale" } },
        [A.LUMBER_TICK] = { persists = false, combatUnsafe = false,
            noisy = true,  -- 1s heartbeat while farming; would flood the dispatch log otherwise
            invalidates = { "session.lumber.tick" } },
        [A.REP_PROGRESS_TICK] = { persists = false, combatUnsafe = false,
            noisy = true,  -- UPDATE_FACTION fires in bursts (debounced, but still chatty)
            invalidates = { "session.rep.tick" } },

        -- ===== Catalog lifecycle ======================================
        [A.CATALOG_LOAD_REQUESTED]    = T({ "session.catalog" }),
        -- refreshPending explicitly listed -- reducer clears it here too (fix for tab-switch re-sweep loop).
        [A.CATALOG_LOAD_COMPLETED]    = T({ "session.catalog", "session.catalog.refreshPending" }),
        [A.CATALOG_LOAD_FAILED]       = T({ "session.catalog.status" }),
        [A.CATALOG_REFRESH_QUEUED]    = T({ "session.catalog.refreshPending",
                                            "session.catalog.variantsLoaded" }),
        [A.CATALOG_REFRESH_COMPLETED] = T({ "session.catalog" }),
        [A.CATALOG_VARIANTS_LOADED]   = T({ "session.catalog.variantsLoaded" }),

        [A.UI_SET_VIEW] = T({ "session.ui.view" }),

        -- ===== Projects: house topology =====
        [A.PROJECTS_UPSERT_HOUSE]        = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.houses" } },
        [A.PROJECTS_UPSERT_ROOM]         = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.versions" } },
        [A.PROJECTS_MOVE_ROOM]           = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.versions" } },
        [A.PROJECTS_DELETE_ROOM]         = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.versions", "account.collections" } },
        -- Switching the shown version re-keys every canvas read; "*" until reads-set settles.
        [A.PROJECTS_SET_ACTIVE_VERSION]  = { persists = true, combatUnsafe = false,
            invalidates = "*" },
        [A.PROJECTS_CREATE_VERSION]      = { persists = true, combatUnsafe = false,
            invalidates = "*" },
        [A.PROJECTS_DELETE_VERSION]      = { persists = true, combatUnsafe = false,
            invalidates = "*" },
        [A.PROJECTS_CAPTURE_COMMIT]      = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.houses", "account.projects.versions", "account.collections" } },
        [A.PROJECTS_HOUSE_TICK]          = T({ "session.house.budget", "session.house.numFloors", "session.house.editorActive" }),
        [A.PROJECTS_ROOM_CATALOG_UPDATED] = T({ "session.house.roomCatalog" }),
        [A.CATALOG_CATEGORY_TREE_UPDATED] = T({ "session.house.categoryTree" }),
        [A.PROJECTS_REMAP_ROOM]          = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.versions", "account.collections" } },
        [A.PROJECTS_CLEAR_HOUSE]         = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.versions", "account.collections" } },
        [A.PROJECTS_SET_VERSION_FLOORS]  = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.versions" } },
        [A.PROJECTS_RENAME_VERSION]      = { persists = true, combatUnsafe = false,
            invalidates = { "account.projects.versions" } },
        -- Import mints a new version + activates it -> re-keys canvas reads; "*".
        [A.PROJECTS_IMPORT_LAYOUT]       = { persists = true, combatUnsafe = false,
            invalidates = "*" },
        -- Switching the focused house re-keys every canvas read (new active version); "*".
        [A.PROJECTS_FOCUS_HOUSE]         = { persists = true, combatUnsafe = false,
            invalidates = "*" },
        -- Crates live in account.collections (own write family).
        [A.CRATE_UPSERT]                 = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.CRATE_ADD_DECOR]              = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.CRATE_DECREMENT_DECOR]        = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.CRATE_REMOVE_DECOR]           = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.CRATE_SET_FIELD]              = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.CRATE_REATTACH]               = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.CRATE_DETACH]                 = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.CRATE_DELETE]                 = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.LIBRARY_STAMP]                = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.SHIPPING_CRATE_PACK]          = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
        [A.SHIPPING_CRATE_DELETE]        = { persists = true, combatUnsafe = false, invalidates = { "account.collections" } },
    }
end

-- Exhaustiveness check: every action in Constants.ACTIONS must have a meta row with `invalidates`.
local function ValidateActionMetaExhaustiveness(actionMeta)
    local A = HDG.Constants.ACTIONS
    local missingMeta, missingInvalidates = {}, {}
    for name, value in pairs(A) do
        local row = actionMeta[value]
        if row == nil then
            missingMeta[#missingMeta + 1] = name
        else
            local inv = row.invalidates
            local invType = type(inv)
            -- Valid: table (list), function (dynamic), or sentinel "*".
            if not (invType == "table" or invType == "function"
                    or (invType == "string" and inv == "*")) then
                missingInvalidates[#missingInvalidates + 1] = name
            end
        end
    end
    if #missingMeta > 0 then
        error(("HDG action meta missing entries for: %s"):format(
            table.concat(missingMeta, ", ")), 2)
    end
    if #missingInvalidates > 0 then
        error(("HDG action meta missing `invalidates` field for: %s"):format(
            table.concat(missingInvalidates, ", ")), 2)
    end
end

-- Central environment slot catalog. Addon-level slots here; modules may add module-specific
-- slots via Environment:Declare in their onInitialize.
HDG.Environment.SLOTS = {
    {
        name        = "scheme",
        default     = (HDG.Theme:GetScheme()) or {},
        validator   = function(v) return type(v) == "table" end,
        description = "Active colour scheme + fonts + backdrops",
    },
    {
        name        = "locale",
        default     = HDG.L or {},
        validator   = function(v) return type(v) == "table" end,
        description = "Localisation strings (GetLocale-keyed)",
    },
    {
        name        = "debug",
        default     = function()
            local cfg = HDG.Store:GetState().account.config
            return cfg and cfg.debug == true or false
        end,
        validator   = function(v) return type(v) == "function" end,
        description = "Live debug-mode predicate read from account.config.debug",
    },
    {
        name        = "layer",
        default     = "main",
        validator   = function(v) return type(v) == "string" end,
        description = "Render layer identifier (main / preview / tooltip)",
    },
}

function HDG:OnInitialize()
    -- Stamp t-zero for perf timeline. Marks self-gate on the perf SV internally.
    if HDG.Perf then  -- exception(false-positive): boot orchestrator; Perf is removable instrumentation, absent in minimal/headless test harnesses
        HDG.Perf:SetEpoch()
        HDG.Perf:Mark("HDG:OnInitialize (boot start)", nil, "event")
    end
    HDG_DB = HDG_DB or {}
    HDG.Store:LoadFromSavedVariables()
    HDG.Theme:Initialize()
    -- Snapshot WoW client locale for `binding = "locale:KEY"` resolution.
    HDG.Locale:Initialize()

    -- Boot-time ADR-023 backstop: Theme + Palette must own disjoint color namespaces.
    if HDG.Theme.OWNED_COLOR_NAMESPACES and HDG.Palette and HDG.Palette.OWNED_NAMESPACES then   -- exception(boundary): ADR-023 validator; both modules must be loaded
        for ns in pairs(HDG.Theme.OWNED_COLOR_NAMESPACES) do
            if HDG.Palette.OWNED_NAMESPACES[ns] then
                error(("Theme/Palette namespace collision: %q owned by both (ADR-023)"):format(ns))
            end
        end
    end

    -- Build + validate action metadata. Exhaustiveness check: every action must have a meta entry.
    local actionMeta = BuildActionMeta()
    ValidateActionMetaExhaustiveness(actionMeta)
    -- Stash on Store so _RawDispatch can read `invalidates` per action.
    HDG.Store._actionMeta = actionMeta

    -- Config layer. MUST run after actionMeta stash: _RunMigrations dispatches CONFIG_SET
    -- and the reducer needs meta. Theme already initialized; Config re-hydrates from Profiles.
    HDG.Config:Initialize()

    -- Boot sequence (spec section 15.4):
    --   1. BlizzardEvents:OnInitialize  2. Modules:Topo  3. BlizzardEvents:Boot
    --   4. Environment.DeclareAll       5. Modules:Phase1 (onInitialize)
    --   6. Environment:Build            7. Middleware.Apply
    --   8. Modules:Phase2 (onEnable)    9. WidgetTypes:Flush  10. FlowRunner:Boot

    HDG.BlizzardEvents:OnInitialize()

    HDG.Modules:Topo()

    -- Pass module data explicitly (engine-to-engine isolation).
    do
        local order = HDG.Modules:GetOrder()
        local defs  = {}
        for _, name in ipairs(order) do defs[name] = HDG.Modules:Get(name) end
        HDG.BlizzardEvents:Boot({ order = order, defs = defs })
    end

    HDG.Environment:DeclareAll()

    HDG.Modules:Phase1()

    local env = HDG.Environment:Build()

    HDG.Middleware.Apply(HDG.Store, HDG.Middleware.StandardChain({
        actionMeta = actionMeta,
        env        = env,
    }))

    -- Trace consumer subscribes after middleware so its own log entries flow through the chain.
    HDG.Log:AttachTraceConsumer()

    HDG.Modules:Phase2()

    HDG.WidgetTypes:Flush()
    if HDG.FlowRunner and HDG.FlowRunner.Boot then  -- optional; not in TOC  -- exception(boundary): optional module / not yet built
        HDG.FlowRunner:Boot()
    end

    -- Apply the saved scheme before any widgets are built.
    local cfg = HDG.Store:GetState().account.config
    local schemeName = cfg.scheme
    if schemeName and schemeName ~= "" and HDGR_SchemeConstants[schemeName] then
        HDG.Theme:LoadScheme(schemeName)
    end

    -- Register Blizzard Settings panel at ADDON_LOADED (infra is ready; no PLAYER_LOGIN race).
    if HDG.InitSettingsPanel then  -- exception(boundary): file may not be loaded in minimal test builds
        HDG.InitSettingsPanel()
    end
end

function HDG:OnEnable()
    HDG:CreateMainWindow()
    -- Floating windows: CreateAll builds one frame per registered entry, wires Store for
    -- visibility/position reconciliation, and does an initial paint from SavedVariables state.
    if HDG.Window then HDG.Window:CreateAll() end  -- exception(false-positive): boot orchestrator; the UI/Window engine is absent in minimal/headless test harnesses, strict-read would force every boot-test to load the full UI stack
    -- Restore main window open/closed state (FrameVisibility reads account.ui.mainWindowShown).
    HDG:RefreshMainWindow()

    -- One-time HDG->HDGR v3.0 upgrade notice. Migration.lastResult is a table only when a
    -- migration actually ran this load; gate on a RAW SV flag (not reactive state) so it
    -- shows ONCE ever -- surviving reloads AND future schema-bump re-runs.
    local mig = HDG.Migration and HDG.Migration.lastResult
    if mig and _G.HDG_DB and not _G.HDG_DB.upgradeNoticeShown then  -- exception(boundary): one-time raw SV marker
        local P = HDG.Format.BRAND_PREFIX
        print(P .. " Updated to |cFF14b8a6v3.0|r -- your favorites, notes, styles, shopping lists and history all carried over.")
        print(P .. " Settings were reset to new defaults; saved snapshots and smart-sets now live in their own tabs. Type /hdg to explore.")
        _G.HDG_DB.upgradeNoticeShown = true  -- exception(boundary): one-time raw SV marker, not reactive state
    end

    -- Housing catalog work is gated by HousingCatalogObserver's MAIN_WINDOW_OPENING subscriber.
    -- Per ADR-043: no work at PLAYER_LOGIN.

    -- Deferred AddDataProvider: without the 2s defer, it runs inside a click trace
    -- which taints WorldMapFrame -> AreaPOI tooltip errors after combat. boundary
    if HDG.Waypoints and HDG.Waypoints.InitMapPins then  -- exception(boundary): optional module / not yet built
        C_Timer.After(2, function() HDG.Waypoints:InitMapPins() end)
    end
end

-- Lifecycle bootstrap via BlizzardEvents._internalSubscribe (spec section 15).
-- Lifecycle events (ADDON_LOADED/PLAYER_LOGIN/LOGOUT) can't use declarative
-- blizzardEvents because BE:Boot() runs inside OnInitialize.
HDG.BlizzardEvents:_internalSubscribe("ADDON_LOADED", function(name)
    if name == "HousingDecorGuide" then HDG:OnInitialize() end
end)
HDG.BlizzardEvents:_internalSubscribe("PLAYER_LOGIN", function()
    HDG:OnEnable()
end)
-- Scale/display changes: re-run the layout pipeline so "auto"-width widgets repaint at new dimensions.
local function _refreshOnScale()
    HDG:RefreshMainWindow("*")
end
HDG.BlizzardEvents:_internalSubscribe("UI_SCALE_CHANGED",   _refreshOnScale)
HDG.BlizzardEvents:_internalSubscribe("DISPLAY_SIZE_CHANGED", _refreshOnScale)
HDG.BlizzardEvents:_internalSubscribe("PLAYER_LOGOUT", function()
    -- Finalize active lumber session so its haul is recorded to history, not left dangling.
    if HDG.LumberObserver then HDG.LumberObserver:FinalizeSession() end  -- exception(boundary): module optional
    -- SESSION_END closes every window. FlushNotifications drains the deferred queue
    -- synchronously so subscribers actually run before client unloads.
    HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.SESSION_END })
    HDG.Store:FlushNotifications()
    -- Shutdown in reverse dependency order, before Store:Flush so teardown state lands in SavedVars.
    HDG.Modules:Shutdown()
    HDG.Store:Flush()
end)

SLASH_HDG1 = "/hdg"
SLASH_HDG2 = "/hdgr"
SlashCmdList["HDG"] = function(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()
    local first, rest = lower:match("^(%S+)%s*(.*)$")
    local D = HDG.Debug
    if lower == "help" or lower == "?" then
        D:Help()
    -- ===== Developer / debug commands -> HDG.Debug + folded dev tools =======
    elseif lower == "debug" then
        D:Toggle()
    elseif lower == "mocktsm" then
        D:MockTSM()
    elseif first == "trace" then
        D:Trace(rest)
    elseif first == "log" then
        D:Log(rest)
    elseif lower == "house" then
        D:House()
    elseif first == "costdump" then
        D:CostDump(rest)
    elseif first == "dumpdecor" then
        D:DumpDecor(rest)
    elseif first == "sl" then
        HDG.SelectorCallLog:Command(rest)   -- was /hdgrsl
    elseif first == "perf" then
        HDG.Perf:Command(rest)              -- was /hdgr perf
    elseif lower == "doors" then
        HDG.ProjectsCanvasController:DoorAudit()  -- was /hdgr doors
    -- ===== User-facing features (stay in Init) ==============================
    elseif lower == "minimap" then
        local cfg = HDG.Store:GetState().account.config
        HDG.Store:Dispatch({
            type = HDG.Constants.ACTIONS.CONFIG_SET,
            payload = { key = "showMinimapButton", value = not cfg.showMinimapButton },
        })
    elseif lower == "hardreset" then
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.HARD_RESET })
    elseif lower == "resetlayout" then
        -- Clears account.ui.houseTab.* overrides; dashboard renders from WidgetDefaults.
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.HOUSETAB_RESET_LAYOUT })
        HDG.Log:Notify("info", "HouseTab layout reset to defaults")
    elseif lower == "refresh" then
        -- Force a fresh catalog sweep.
        HDG.HousingCatalogObserver:ReconcileFull()
        HDG.Log:Notify("info", "catalog refresh started")
    elseif first == "theme" then
        -- /hdgr theme         -- list available themes
        -- /hdgr theme <name>  -- switch theme (case-insensitive prefix match)
        local meta = HDGR_SchemeMeta
        if rest == "" then
            print(HDG.Format.BRAND_PREFIX .. " Available themes:")
            local cur = HDG.Store:GetState().account.config.scheme
            for _, name in ipairs(meta.order) do
                local marker = (name == cur) and "|cffffb060*|r " or "  "
                print(("%s|cffcdd6f4%s|r  |cff999999%s|r"):format(marker, name, meta.labels[name] or ""))
            end
            print("|cff666666Usage: /hdgr theme <Name>|r")
        else
            local match
            local lowerArg = rest:lower():gsub("%s", "")
            for _, name in ipairs(meta.order) do
                if name:lower():sub(1, #lowerArg) == lowerArg then match = name; break end
            end
            if not match then
                HDG.Log:Notify("error", ("unknown theme %q -- run /hdgr theme to list"):format(rest))
            else
                HDG.Store:Dispatch({
                    type = HDG.Constants.ACTIONS.CONFIG_SET,
                    payload = { key = "scheme", value = match },
                })
                HDG.Theme:LoadScheme(match)
                HDG.Log:Notify("info", ("theme -> %s"):format(match))
                HDG.Log:Info("theme", "Theme changed to " .. match)  -- status-rail toast
            end
        end
    elseif first == "view" then
        local views   = HDG.LayoutConfig.window.views
        local current = HDG.Store:GetState().account.ui.view
        local arg     = rest:gsub("%s", "")
        if arg == "" then
            print(HDG.Format.BRAND_PREFIX .. " Views:")
            for name in pairs(views) do
                local marker = (name == current) and "|cffffb060*|r " or "  "
                print(("%s|cffcdd6f4%s|r"):format(marker, name))
            end
            print("|cff666666Usage: /hdgr view <name>|r")
        elseif not views[arg] then
            HDG.Log:Notify("error", ("unknown view %q -- run /hdgr view to list"):format(arg))
        else
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.UI_SET_PERSISTENT,
                payload = { key = "view", value = arg },
            })
            print((HDG.Format.BRAND_PREFIX .. " view -> |cffcdd6f4%s|r"):format(arg))
        end
    else
        HDG:ToggleMainWindow()
    end
end
