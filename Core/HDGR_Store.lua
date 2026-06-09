-- HDG.Store
-- ============================================================================
-- Single Source of Truth for refactor state. Pure-dispatch architecture (no
-- imperative setters -- everything flows through Dispatch -> reducer).
--
-- State shape:
--   account.* -- persisted to HDG_DB. PersistenceMiddleware writes on every
--                dispatch whose action declares `persists = true` in
--                Core/HDGR_Init's BuildActionMeta.
--   session.* -- transient. Reset on every /reload.
--
-- Pure-dispatch architecture (no imperative setters -- everything flows
-- through Dispatch -> reducer). See HDGR_ARCHITECTURE.md for ADRs.

HDG = HDG or {}

-- ===== State constructors =====================================================

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = DeepCopy(v) end
    return out
end

local function NewConfig()
    return {
        debug              = false,
        mockTSM            = false,   -- debug: mock TSM as the price source (flat 100g)
        -- showMinimapButton: show/hide the LibDBIcon minimap button. Toggled by BOTH
        -- the Settings-panel checkbox and /hdgr minimap; subscriber in
        -- HDGR_MinimapButton forwards to LibDBIcon. (Single flag -- the old separate
        -- showMinimap flag was an oversight; collapsed 2026-06-07.)
        showMinimapButton  = true,
        scheme             = HDG.Constants.DEFAULT_SCHEME,
        -- decorPreviewBg: 3D-preview background for the decor browser. "default" =
        -- the dark bgTile backdrop (no atlas); other values are housing-bg atlas names.
        decorPreviewBg     = "default",
        -- UI scale: HDG window only (NOT the global UI scale CVar).
        -- Subscriber in HDGR_Window forwards account.config.scale changes
        -- to MainFrame:SetScale. Range 0.5 -- 1.5 (clamped at write).
        scale              = 1.0,
        -- Locale follows the same generic CONFIG_SET { key, value } dispatch
        -- pattern as scheme. HDGR_Locale subscribes to invalidation on this
        -- path and forwards to Locale:SetLocale + RefreshMainWindow.
        -- Default sentinel "" means "use GetLocale() at first read"; a
        -- player picking a locale from the Config dropdown stamps a real
        -- value here that survives /reload.
        locale             = "",
        -- Price source preference.
        -- preferredPriceAddon: nil | "TSM" | "Auctionator" | "Direct"
        --   nil  -- fall back chain: TSM > Auctionator > Direct cache > Vendor
        --   "X"  -- force a specific source (with vendor fallback at the end)
        -- tsmPriceMode: "min" | "market" | "region"
        --   "min"     -> DBMinBuyout       (cheapest current)
        --   "market"  -> DBMarket          (TSM-derived market)
        --   "region"  -> DBRegionSaleAvg   (cross-realm sale average)
        preferredPriceAddon = nil,
        tsmPriceMode        = "min",
        -- Zone Scanner config. Master toggle gates the alert engine entirely;
        -- the sub-flags fan out which surfaces fire on a hit.
        zoneScannerEnabled = true,
        zoneScannerPopup   = false,
        zoneScannerPopupShopping = false,   -- popup for shopping-list items specifically
        zoneScannerChat    = true,
        zoneScannerSound   = false,
        -- tooltipDecorTag: show the HDG catalog line on item tooltips.
        tooltipDecorTag        = true,
        -- hideInCombat: auto-hide all HDG windows on entering combat (restore on exit).
        hideInCombat           = true,
        -- showCompartment: gate the AddonCompartment click/enter handlers.
        -- NOTE: the TOC AddonCompartmentFunc directive always registers the
        -- icon in Blizzard's compartment drawer; this flag only disables the
        -- click and tooltip handlers. Users who want the icon removed must
        -- use Blizzard's own Edit Mode. Documented limitation.
        showCompartment        = true,
        -- showProfessionButtons: inject "Decor Guide" + "Filter Decor"
        -- buttons into ProfessionsFrame. Subscriber in HDGR_ProfessionButtons.
        showProfessionButtons  = true,
        -- waypointProvider: "auto" | "tomtom" | "blizzard"
        --   "auto"     -> TomTom if loaded, else Blizzard (existing behaviour)
        --   "tomtom"   -> TomTom if available; warns and falls back to Blizzard
        --   "blizzard" -> always Blizzard, TomTom ignored
        waypointProvider       = "auto",
        -- minimapPos: LibDBIcon's own db table (position angle + .hide flag).
        -- Seeded here so MinimapButton hands LibDBIcon a stable, HDG_DB-
        -- persisted table with no lazy `or {}` guard. LibDBIcon writes
        -- .minimapPos on drag and reads .hide on login -- external boundary;
        -- HDG only syncs .hide for visibility (the one write it makes).
        minimapPos             = {},
    }
end

local function NewAccountUI()
    return {
        mainWindowShown = false,
        -- Active tab. Matches a window.views[X] key in LayoutConfig. Persists
        -- across /reload so the user reopens to the same tab. nil falls
        -- back to window.defaultView in MainFrame's PrepareContext stage.
        view            = "decor",
        -- Shopping list widget visibility (parallel slot to mainWindowShown).
        -- Flipped by SHOPPING_WIDGET_TOGGLE; the MainFrame reconciler
        -- subscriber overrides `view` to "shoppingList" when this is true.
        shoppingWidgetShown = false,
        -- Zone Scanner popup visibility (parallel slot to shoppingWidgetShown).
        -- Flipped by ZONE_POPUP_TOGGLE; also set true by HDGR_ZoneAlertEngine
        -- when a zone-entry alert fires AND zoneScannerPopup is true. Persists
        -- across /reload so users who keep it open get it back automatically.
        zonePopupShown = false,
        -- Per-tab persistent UI bits. Promoted from session.ui when the
        -- user's expectation is that the setting survives /reload.
        acquisition     = {
            -- itemsViewMode persisted: player's grid/list preference for
            -- the vendor's items area. Survives /reload.
            itemsViewMode = "grid",
        },
        -- Recipes tab persistent filter SETs keyed by display name / profession name.
        -- Empty = "all". Persist across /reload.
        recipes         = {
            expansionFilter  = {},
            -- Profession filter is PER CHARACTER (keyed by charKey -> set). A nil
            -- entry = pristine -> selector defaults to that char's professions.
            professionFilterByChar = {},
        },
        -- Sidebar nav: collapsed parent groups, keyed by hub view -> true.
        -- Persisted so a collapsed group stays collapsed across /reload.
        nav             = {
            collapsedGroups = {},
        },
    }
end

-- Per-tab session.ui sub-view shapes. Pre-seeded by NewSessionUI so
-- selectors can read state.session.ui.<view>.<key> directly. Shape is
-- guaranteed; selectors fail loudly on typos (strict reads, ADR-005).

-- Forward-declared; real definition further down (SSoT shared with DECOR_FILTER_RESET).
local NewDecorFilters

-- Forward-declared; defined alongside the shopping factories further down.
local NewShoppingSessionUI

local function NewDecorSessionUI()
    return {
        searchQuery     = "",
        selectedItemID  = nil,
        filters         = NewDecorFilters(),
    }
end

local function NewAcquisitionSessionUI()
    return {
        searchQuery         = "",
        selectedNpcID       = nil,
        selectedItemID      = nil,
        -- expandedVendors moved to account.ui.acquisition.expandedVendors
        -- (persistent across /reload) -- see NewAccountUI.
        viewMode            = "vendor",
        -- itemsViewMode persisted at account.ui.acquisition.itemsViewMode --
        -- the player's grid/list preference survives /reload.
        advancedFiltersOpen = false,
        preset              = nil,     -- source axis (achievement|reputation|endeavor|quest)
        missingOnly         = false,   -- collection axis -- ANDs with preset (orthogonal toggle)
        -- Advanced filters are multi-select SETs (empty = "All"). ACQ_TOGGLE_* flip membership.
        factionFilter       = {},
        expansionFilter     = {},
        zoneFilter          = {},
        repFilter           = {},
        sourceFilter        = {},
    }
end

-- Recipes tab session UI. Filters block shared with RECIPES_FILTER_RESET (ADR-018).
local function NewRecipesFilters()
    return {
        expansionFilter = "all",   -- string|"all"
        knownOnly       = false,
        uncollectedOnly = false,
        searchReagents  = false,
    }
end

local function NewRecipesSessionUI()
    return {
        searchQuery        = "",
        selectedRecipeID   = nil,
        -- Queue-row selection: when set, the queue row for this recipeID
        -- is highlighted AND the materials list filters down to only
        -- THIS recipe's mats (overrides the queue-wide aggregation
        -- normally driven by recipes.materials.* selectors via
        -- effectiveQueue). Toggle on second click via Deselectable flag
        -- on the queue scrollbox + RECIPES_TOGGLE_QUEUE_SELECTION action.
        queueSelectedRecipeID = nil,
        -- focusedItemID: set by clicking a recipe or queue row. Last click wins.
        focusedItemID      = nil,
        expandedSections   = {},        -- [sectionKey] = true (open) / nil (closed)
        materialsGrouping  = "totals",  -- "totals"|"byRecipe"  (organization axis)
        materialsDepth     = "direct",  -- "direct"|"raw"       (expansion-depth axis)
        -- expansionFilter + professionFilter live in account.ui.recipes (persisted SETs).
        listFilter         = "all",     -- "all"|"known"|"ready"
        -- Real wrapped height of the active-filter chip strip, published by the
        -- chipStrip widget after FlowContainer layout (via UI_SET_TRANSIENT).
        -- recipes.gridRows reads it to size the strip cell EXACTLY to the chips
        -- (no estimate, no clip, no slack). 0 until the first measurement.
        runHeight          = 0,
        filters            = NewRecipesFilters(),
    }
end

-- Warehouse view session state.
local function NewWarehouseSessionUI()
    return {
        selectedMaterialID = nil,   -- All Materials panel selection
        matSearch          = "",    -- All Materials search
    }
end

-- "Your Data" tab session UI. Holds collapse overrides for the three
-- achievement groups (decor / coupon / lumber). Tri-state per group key
-- "collapse_<group>":
--   absent (nil) -> AUTO: collapse a fully-earned group on first open
--   true         -> user collapsed
--   false        -> user expanded
-- Keys are deliberately ABSENT at seed time so the auto-collapse default
-- applies until the user clicks a group header (UI_SET_TRANSIENT writes
-- session.ui.data.collapse_<group>). data.achievementsData reads this bucket.
local function NewDataSessionUI()
    return {}
end

-- Bag inventory cache. BagObserver dispatches
-- BAG_INVENTORY_UPDATED { tick } whenever the debounced bag scan
-- completes; the reducer bumps session.bag.tick so inputs-memo selectors
-- (recipes.bagCounts) invalidate cleanly. The real count map lives in
-- HDG.BagObserver._counts -- selectors read it via the ADR-003a
-- inside-closure deterministic-module-read carve-out (the read is
-- post-init and pure).
local function NewBagSession()
    return {
        tick = 0,
    }
end

-- Item name cache. Resolved names are written into `names` by the
-- ITEM_INFO_RESOLVED reducer (which receives entries from
-- ItemNameResolver:Drain). Consumers (selectors / row factories) read via
-- ItemNameResolver:ResolveName which Peeks this cache before re-querying
-- Blizzard -- avoids redundant GetItemInfo calls on the hot path and
-- survives Blizzard cache eviction across long sessions. `tick` is the
-- invalidation signal for selectors that subscribe via reads. Mirror of
-- VDS's session.items.{names, tick} (VDS_Store.lua:472-499). Earlier shape
-- had tick only (no names cache) -- selectors had to call Blizzard inline
-- on every paint, which lost resolutions if Blizzard's cache cycled.
local function NewItemNamesSession()
    return {
        tick  = 0,
        names = {},  -- [itemID] = "resolved name"; written by reducer, Peeked by ResolveName
    }
end

-- Quest title cache tick. Mirror of itemNames.tick for quest-data async
-- loads. Bumped by QUEST_INFO_RESOLVED when HDG.QuestNameResolver drains
-- a QUEST_DATA_LOAD_RESULT batch. Selectors that show quest gate names
-- (acq.selectedItem.ribbonText) subscribe via `session.questNames.tick`.
local function NewQuestNamesSession()
    return {
        tick = 0,
    }
end

-- Quest-completion invalidation tick. Bumped by QUEST_STATUS_RESOLVED when
-- QuestNameResolver sees QUEST_TURNED_IN, so selectors showing quest-completion
-- (acq.selectedItem.sourceLine [QUST] checkmark) repaint live.
local function NewQuestStatusSession()
    return {
        tick = 0,
    }
end

-- Achievement-earned invalidation tick. Bumped by ACHIEVEMENT_STATUS_RESOLVED
-- when AchievementObserver sees ACHIEVEMENT_EARNED, so the [ACH] earned
-- checkmark (acq.selectedItem.sourceLine) repaints live -- same shape as
-- questStatus. Earned state is dynamic per-character; NOT baked at sweep.
local function NewAchievementStatusSession()
    return {
        tick = 0,
    }
end

-- Static data invalidation tick. Always 0 today -- shipped data tables
-- (HDGR_VendorDB / HDGR_AllDecorDB / etc.) wrapped by HDG.StaticData are
-- IMMUTABLE within a session. Reserved for hot-reload / dev-tool override
-- features. Selectors that call HDG.StaticData.<X>:<accessor>(...) declare
-- reads = {"session.staticData.tick"} so the framework's read-tracking can
-- treat shipped-data dependencies the same as any other state path.
-- Supersedes ADR-003a's "module-singleton read carve-out" for these reads.
-- See docs/HDGR_ARCHITECTURE.md ADR-003c.
local function NewStaticDataSession()
    return {
        tick = 0,
    }
end

-- Price-source invalidation tick. PriceSource is a stateful
-- module (caches, scan progress); selectors that resolve item prices via
-- the module subscribe to `session.prices.tick` for invalidation. Bumped
-- by every PRICES_* action that mutates the cache so Mogul plan repaints
-- when direct scan finishes, TSM mode flips, etc.
local function NewPricesSession()
    return {
        tick      = 0,
        -- Live scan progress (transient -- not persisted). Drives the
        -- Config sub-tab's progress strip.
        scanning  = false,
        scanFound = 0,
        scanTotal = 0,
        -- Snapshot of price-addon availability, refreshed on every
        -- MAIN_WINDOW_OPENING by PriceSource:RefreshAddonAvailability.
        -- Selectors read these directly so they stay pure (no _G probes).
        tsmLoaded         = false,
        auctionatorLoaded = false,
    }
end

-- Alts tab session UI. Account Summary always renders;
-- Characters section is a single panel with two pill buttons in the
-- header that toggle which population is shown. `charsPopulation` =
-- "active" (default) or "hidden" -- the latter includes both manually-
-- hidden chars and chars that have never been profession-scanned.
local function NewAltsSessionUI()
    return {
        charsPopulation = "active",
    }
end

-- Mogul tab session UI. Three dimensions drive the plan builder,
-- plus a sub-view switcher (13.F.2) that splits the tab into three panels:
--   "mogul"  -- craft optimizer plan + lumber tracker (the original view)
--   "goblin" -- per-decor profit table with AH/TSM integration
--   "config" -- price source preferences, AH scan controls, cache stats
-- 13.F.3.b: goblin sub-view filter dimensions. "All" sentinel skips the
-- filter. Profession matches PROFESSION_DATA[i].name verbatim.
local function NewMogulSessionUI()
    return {
        mode       = "profit",       -- profit | collection
        viewMode   = "char",         -- char | account
        optimizeBy = "lumberOnly",   -- lumberOnly | lumberPlusMats
        subView    = "goblin",       -- goblin | mogul (Goblin is the default sub-view)
        -- Supply Impact: market-pressure model for the planner.
        -- mode: "off" = original greedy; "smooth" = per-unit decay; "cap" = hard ceiling N.
        supplyImpact = {
            mode      = "off",   -- "off" | "smooth" | "cap"
            smoothPct = 7,       -- decay % per craft (7 = 7% decay)
            capN      = 10,      -- max crafts per recipe in cap mode
        },
        -- Frugal mode: biases planner toward low-lumber crafts by re-ranking as
        -- `effProfit / bindingLumberQty^1.5` (dampens high-lumber recipes).
        frugal = false,
        goblin     = {
            profession   = "All",    -- "All" | PROFESSION_DATA[i].name
            search       = "",       -- substring filter on item name (case-insensitive)
            knowledge    = "all",    -- all | known (char) | alt (account-known)
            queue        = "all",    -- all | only (queued only) | hide (hide queued)
            auctionsOnly = false,    -- true: only show items with active player AH listings
            sortCol         = "profit", -- name | lumber | perLum | cost | sell | tsmMin | tsmMarket | tsmRegion | tsmPct | profit | pct
            sortDir         = "desc",   -- "asc" | "desc"
            expandedItemID  = nil,      -- itemID of the row whose detail panel is showing (nil = collapsed)
        },
    }
end

-- Styles tab session UI. 14.0 scaffold only seeds the
-- top-level view discriminator + sub-slot scaffolding; per-surface
-- session state (landing filters, curator selectedItems set, smartset
-- draft, etc.) lands as each surface is wired in 14.1-14.6.
local function NewStylesSessionUI()
    return {
        view       = "landing",   -- "landing" | "detail" | "curator" | "smartset" | "import"
        selectedID = nil,         -- collectionID currently viewed in Detail
        landing    = { filter = "all", search = "", expandedSections = {} },
        detail     = {
            selectedItemID = nil,
            search         = "",
            viewMode       = "cards",   -- "list"|"cards"|"split" -- 14.2.b
            sourceFilter   = "all",     -- "all"|<sourceType> -- 14.2.b filter chips
            subcatFilter   = "all",     -- "all"|<subcategoryID> -- 14.2.b for Room Concepts
        },
        curator    = {
            sourceMode        = "all",          -- "unassigned" | "all" | "style:<id>" (default: browse everything)
            -- Blizzard category-nav focus (icon rail). nil = "All". Drives the icon
            -- strip + the grid filter (sourceItems) via row.categoryID / subcategoryID.
            focusedCategoryID    = nil,
            focusedSubcategoryID = nil,
            selectedItems     = {},             -- set: [itemID] = true
            selectedCount     = 0,              -- cached count of selectedItems
            selectedTargetID  = nil,            -- highlighted FILE INTO target
            recentUndo        = {},             -- LIFO stack of move records
            hoverItemID       = nil,
        },
        -- 14.4 Smart Set Builder draft state. `draft` holds the working
        -- collection record (id, displayName, description). `rules` is a
        -- nested map [axis][tag] = severity ("signature"|"accent"|"clashing").
        -- `activeAxis` drives the middle-column tag list; `activeSeverity`
        -- drives the preview's severity-tab filter. `dirty` flags unsaved
        -- changes so SAVE/CANCEL can no-op the no-edit case.
        smartset   = {
            draftKey       = nil,    -- existing collectionID if editing, nil for new
            draft          = { id = nil, displayName = "", description = "", type = "smartset", descAuto = true },
            activeAxis     = "room", -- current facet axis being edited
            activeSeverity = "all",  -- "all" | "signature" | "accent" | "versatile" | "clashing"
            rules          = {},     -- { [axis] = { [tag] = severity } }
            dirty          = false,
        },
        import     = { urlText = "", parseError = nil, previewItems = nil },
    }
end

-- Smart Set auto-description: title-cased signature-tag names, sorted + comma-joined
-- (mirrors HDG BuildAutoDescription). Pure; used by the SMARTSET reducer cases.
local function _prettyTag(tag)
    tag = tag:gsub("%-", " ")
    return (tag:gsub("(%a)([%w']*)", function(h, t) return h:upper() .. t end))
end

local function _buildSmartsetAutoDesc(rules)
    local parts = {}
    for _, tags in pairs(rules or {}) do
        for tag, sev in pairs(tags) do
            if sev == "signature" then parts[#parts + 1] = _prettyTag(tag) end
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- Default "<Char> Style <N>" name for a fresh smart-set draft -- N is the
-- monotonic account.collectionSeq+1 (the same N the SAVE id will mint).
local function _seededSmartsetName(account)
    local charName = (UnitName and UnitName("player")) or "My"  -- exception(boundary): player name for default label
    return charName .. " Style " .. ((account.collectionSeq or 0) + 1)  -- exception(boundary): pre-counter saved accounts lack collectionSeq
end

-- Trainers tab session UI.
local function NewTrainersSessionUI()
    return {
        searchQuery         = "",
        expandedProfessions = {},     -- [profName] = true (open) / nil (closed); default = all collapsed
        midnightExpanded    = false,  -- separate boolean for Midnight Recipe Sources section
        selectedNpcID       = nil,    -- highlighted trainer (for TreeList row selection)
    }
end

-- HouseEditor companion session UI. Standalone window (launcher click while HouseEditor open).
local function NewCompanionSessionUI()
    return {
        windowShown      = false,    -- launcher click toggles this
        mode             = "styles", -- "styles"|"shopping"|"snapshots"|"themes"|"collections"|"recent"
        search           = "",
        selectedItemID   = nil,      -- highlighted collection in sidebar (varies by mode)
        showCost         = true,     -- cost-badge visibility toggle (header budget button)
        ioFilter         = "all",    -- "all"|"indoor"|"outdoor" -- 3-state grid filter
    }
end

-- Companion account UI: window position persists across sessions. Default
-- nil means "use HouseEditorFrame anchor"; the user dragging the window
-- records position via COMPANION_SET_POSITION.
local function NewCompanionAccountUI()
    return {
        window   = { x = nil, y = nil },   -- nil = default-anchor; numeric = user-positioned
        launcher = { x = nil, y = nil },   -- in-editor launcher button position (nil = default top-left)
    }
end

-- HouseTab session UI. Picker drawer + design-mode editor are transient.
local function NewHouseTabSessionUI()
    return {
        pickerOpen = false,
        designMode = false,
    }
end

-- HouseTab account-side persistence: per-widget customizations.
local function NewHouseTabAccountUI()
    return {
        enabled         = {},   -- [widgetID] = bool (nil = use default)
        order           = {},   -- [widgetID] = number (nil = use default)
        width           = {},   -- [widgetID] = "third"|"twoThirds"|"full"
        layoutOverrides = {},   -- [widgetID] = { height = N } per-widget size overrides
    }
end

-- HouseTab live snapshot session slot. Aggregator dispatches HOUSE_SNAPSHOT_
-- UPDATED with the precomputed snapshot table. snapshotTick bumps on every
-- dispatch; selectors derived from the snapshot declare reads = {
-- "session.house.snapshotTick" } to invalidate together.
--
-- ownedHouses: { [houseGUID] = { name, faction, level, favor, maxLevel,
-- thresholds } }. Populated by HousingObserver via HOUSE_LIST_UPDATED
-- (identity fields) + HOUSE_LEVEL_UPDATED (level/favor/thresholds).
-- Reducer preserves level/favor across re-fires of the house-list event.
local function NewHouseSession()
    return {
        snapshot               = {},   -- empty until first aggregator run
        snapshotTick           = 0,
        ownedHouses            = {},   -- keyed by houseGUID
        activeNeighborhoodGUID = nil,  -- WOWGUID from C_NeighborhoodInitiative.GetActiveNeighborhood
        -- rewardsByLevel[level] = { rewards = {...} } -- per-level reward
        -- cache populated by RECEIVED_HOUSE_LEVEL_REWARDS via
        -- HOUSE_REWARDS_RECEIVED dispatch. Aggregator reads this to
        -- build the nextRewards snapshot field.
        rewardsByLevel         = {},
        -- Live decor spend bumped by PROJECTS_HOUSE_TICK. Placement caps are
        -- reward-derived; the live cap API is editor-state-dependent.
        budget                 = { decorSpent = 0, decorCount = 0 },
        numFloors              = 0,
        editorActive           = false,
        -- Live room catalog snapshotted by HousingCatalogObserver on HOUSING_STORAGE_UPDATED.
        -- byShapeID[shapeID] = entry; entries = full list.
        -- entry = { recordID, shapeID, name, iconAtlas, iconTexture, placementCost,
        --           numStored, numPlaced, quantity, owned, isAllowedIndoors,
        --           isAllowedOutdoors, isPrefab, quality }.
        roomCatalog            = { tick = 0, byShapeID = {}, entries = {} },
        -- Blizzard category/subcategory nav tree (CATALOG_CATEGORY_TREE_UPDATED),
        -- snapshotted from C_HousingCatalog by HousingCatalogObserver. Shared by the
        -- Style Curator + Projects decor picker. iconBase = atlas with Blizzard's baked
        -- state suffix stripped (selectors append _active/_inactive/_active-parent).
        -- byID[catID]       = { id, name, iconBase, orderIndex, subcategoryIDs, anyStoredEntries }
        -- subcatByID[subID] = { id, name, iconBase, orderIndex, parentCategoryID, anyStoredEntries }
        -- rootIDs = top-level catIDs ordered by orderIndex; selectors filter storedOnly.
        categoryTree           = { tick = 0, byID = {}, subcatByID = {}, rootIDs = {} },
    }
end


-- Zone Scanner session UI -- expand-per-vendor, search text, show-collected
-- toggle, all transient (don't survive /reload by design; the popup itself
-- and the master config flags ARE persistent in account.config / account.ui).
local function NewZoneScannerSessionUI()
    return {
        expanded       = {},      -- [npcID] = true when expanded; absent = collapsed
        searchQuery    = "",
        showCollected  = false,
    }
end

local function NewProjectsSessionUI()
    -- Transient nav for the Projects tab (reset to landing on /reload, per decision).
    return {
        activeView      = "landing",   -- "landing" | "architect"
        selectedFloor   = 1,
        selectedRoomID  = nil,
        selectedCrateID = nil,
        -- Layouts tab: the version whose floors the preview/detail show (NOT the
        -- Architect's activeVersionID -- the Layouts preview is independent of editing).
        layoutSelectedVersionID = nil,
        -- (activeMode removed with the Reflect/Plan reshape -- the canvas always renders
        -- the active version; arrangement is by drag / Auto-fill, not a mode toggle.)
        -- Decor picker: crate being added to + search/selection.
        pickerCrateID        = nil,    -- non-nil while the picker is open (the target crate)
        pickerSearch         = "",     -- catalog name filter
        pickerSelectedItemID = nil,    -- drives the modelPreview right pane
        -- Blizzard category-nav focus (vertical rail in the decor picker). nil = "All".
        focusedCategoryID    = nil,
        focusedSubcategoryID = nil,
        -- Ambiguous recapture matches awaiting manual remap (E8, forward-declared).
        -- Seeded empty so projects.ambiguousMatches strict-reads; the recapture
        -- observer overwrites via UI_SET_TRANSIENT{key="ambiguous"} when E8 lands.
        ambiguous            = {},
    }
end

local function NewRemovalistSessionUI()
    -- Transient for the Removalist plot-move planner (its OWN per-view bucket --
    -- deliberately NOT under session.ui.projects). faction toggle + plot selection.
    return {
        faction      = "alliance",   -- "alliance" | "horde"
        sourcePlot   = nil,          -- selected source plot number (Phase 3)
        targetPlot   = nil,          -- selected target plot number (Phase 3)
        letterFilter = nil,          -- nil = all; "A"|"B"|"C"|"D" filters the plot list
    }
end

local function NewSessionUI()
    return {
        decor        = NewDecorSessionUI(),
        acquisition  = NewAcquisitionSessionUI(),
        recipes      = NewRecipesSessionUI(),
        warehouse    = NewWarehouseSessionUI(),
        alts         = NewAltsSessionUI(),
        mogul        = NewMogulSessionUI(),
        styles       = NewStylesSessionUI(),
        trainers     = NewTrainersSessionUI(),
        companion    = NewCompanionSessionUI(),
        houseTab     = NewHouseTabSessionUI(),
        shoppingList = NewShoppingSessionUI(),
        zoneScanner  = NewZoneScannerSessionUI(),
        projects     = NewProjectsSessionUI(),
        removalist   = NewRemovalistSessionUI(),    -- Removalist plot-move planner
        data         = NewDataSessionUI(),         -- Your Data tab: achievement-group collapse
    }
end

-- Zone state: current mapID (stamped by ZONE_CHANGED; 0 = not yet probed).
-- Lives at session.zone, not session.ui.*, as it's the canonical player-location fact.
local function NewZoneState()
    return { currentMapID = 0, currentZoneName = "" }
end

-- Lumber Tracker state layout:
-- account.lumber.{config, sessions} (persistent); session.lumber.{activeFarmingID, blips, tick} (transient).
--
-- account.lumber.config: user prefs + drag position (survives /reload).
-- account.lumber.sessions: { [charKey] = { [lumberID] = { startedAt, startCount,
--   lastHarvestAt, finalizedAt? } } } -- finalizedAt set on LUMBER_SESSION_END.
-- session.lumber.activeFarmingID: current lumberID; nil = idle.
-- session.lumber.blips: recent gather events; GC-swept by LUMBER_BLIP_GC.
-- session.lumber.tick: monotonic; selector invalidation signal.
local function NewLumberConfig()
    return {
        windowVisible    = false,            -- LUMBER_WINDOW_TOGGLE writes
        position         = { x = 100, y = -150 },  -- TOPLEFT offset
        radarCollapsed   = false,            -- header chevron writes
        listCollapsed    = false,            -- session-only mode: header list-toggle writes (effective only while farming)
        radarScale       = 1.0,              -- 0.5..2.0 (settings slider)
        autoShowOnHarvest = true,            -- opt-out; suppressed for current
                                              -- session when user closes window
    }
end

local function NewLumberSession()
    return {
        activeFarmingID = nil,   -- lumberID currently being farmed
        blips           = {},    -- recent gather events (ring buffer)
        tick            = 0,     -- monotonic bag-observer-driven counter
    }
end

-- session.rep.tick -- monotonic counter bumped by HDG.RepObserver on
-- UPDATE_FACTION / renown change. Rep-gate display selectors read it to re-run
-- live HDG.RepObserver:GetProgress (rep is dynamic; not baked at catalog sweep).
local function NewRepSession()
    return { tick = 0 }
end

-- StyleEngine cache invalidation tick (bumped on STYLES_INVALIDATE_CACHE).
-- placedDecor: live map keyed by decorGUID (only stable handle Blizzard exposes).
local function NewStylesSession()
    return { cacheTick = 0, placedDecor = {} }
end

-- Session log: ring buffer (per ADR-013). dispatchCap sub-caps the "dispatch"
-- tag so user-tagged history isn't drowned by the dispatch firehose.
local function NewSessionLog()
    return {
        entries      = {},
        nextID       = 0,
        cap          = 200,
        dispatchCap  = 50,
        tabFilter    = { tag = "all", level = "all", autoScroll = true },
        activeTraces = {},
    }
end

local function NewSessionCatalog()
    return {
        status          = "idle",   -- "idle" | "loading" | "ready"
        loadedAt        = 0,        -- epoch of last completed load
        itemCount       = 0,
        vendorCount     = 0,
        sweepGeneration = 0,        -- bumps on each completed sweep
        refreshPending  = false,    -- true after a catalog/storage event; clears on next tab open
        variantsLoaded  = false,    -- true once GetAllVariantInfosForEntry has been batched
    }
end

-- identity: canonical player tuple. Stamped once by SESSION_IDENTITY_SET.
-- Stable for the session; selectors read these instead of calling UnitName/etc.
-- Empty defaults allow strict reads during the brief boot window (per ADR-005).
local function NewIdentitySession()
    return {
        charKey      = "",
        name         = "",
        realm        = "",
        class        = "",     -- localized class name (e.g. "Warrior")
        classFile    = "",     -- enUS class token (e.g. "WARRIOR")
        factionGroup = "",     -- "A" / "H" / "N" -- matches HDGR_VendorDB row[6]
    }
end

local function NewDefaultSession()
    return {
        ui             = NewSessionUI(),
        combat         = { inLockdown = false, queued = {} },
        log            = NewSessionLog(),
        bag            = NewBagSession(),
        itemNames      = NewItemNamesSession(),
        questNames     = NewQuestNamesSession(),
        questStatus    = NewQuestStatusSession(),
        achievementStatus = NewAchievementStatusSession(),
        staticData     = NewStaticDataSession(),
        prices         = NewPricesSession(),
        styles         = NewStylesSession(),
        zone           = NewZoneState(),
        catalog        = NewSessionCatalog(),
        lumber         = NewLumberSession(),
        rep            = NewRepSession(),    -- live rep-progress tick (RepObserver)
        identity       = NewIdentitySession(),
        daily          = { bestowed = nil, orcQuote = nil },  -- seeded here; EnsureSession no longer needs or-guard
        house          = NewHouseSession(),  -- seeded here; EnsureSession no longer needs or-guard
    }
end

-- account.prices: persistent AH price cache. directCache survives /reload;
-- ownedAuctions cached on AH open so Goblin can mark "already listed" offline.
local function NewPrices()
    return {
        directCache     = {},   -- [itemID] = copper (0 = scanned, not listed)
        directQtyCache  = {},   -- [itemID] = units currently listed (0 = scanned, none listed; nil = unscanned)
        directCacheTime = nil,  -- unix ts of last full scan
        ownedAuctions   = {},   -- [itemID] = { qty, buyout } from C_AuctionHouse
    }
end

-- account.collection: reconciler-owned ownership cache (per ADR-012).
-- Selectors depend on individual sub-paths to avoid full-bucket invalidation.
local function NewCollection()
    return {
        ownedDecorIDs         = {},   -- [decorID] = true (ownership set; persisted SavedVariables warm-start seam)
    }
end

-- Favorites: keyed by itemID (stable across catalog rebuilds; decorIDs are not).
local function NewFavorites()
    return {}   -- [itemID] = true
end

-- User notes per item. Keyed by itemID; LRU-pruned at 500 in NOTE_SET reducer.
local function NewUserNotes()
    return {}   -- [itemID] = { text = string, ts = number }
end

-- Multi-list shopping system. shoppingListSeq is monotonic -> collision-free IDs ("L1","L2",...).
-- EnsureShopping reseeds past existing IDs so creates can't collide with deleted slots.
local function NewVendorShoppingLists()
    return {}   -- [listID] = { name, items = {{itemID, npcID?, qty, addedAt}, ...}, meta, createdAt }
end

local function NewActiveShoppingListId()
    return ""   -- "" = no list active (first CREATE auto-activates)
end

local function NewShoppingListSeq()
    return 0    -- counter -- IDs are "L" .. (++seq)
end

-- Shopping list view's session-only UI bucket. Holds expand/collapse state
-- for the 3-level grouped scrollbox (zone -> vendor -> items + wishlist).
-- Per-session: cleared on /reload by design; remembering which zones are
-- expanded across sessions has no value -- users open the list, glance,
-- close. Forward-declared above (above NewSessionUI which composes this in).
NewShoppingSessionUI = function()
    return {
        expanded = {
            zones    = {},   -- [zoneName] = true means COLLAPSED
            vendors  = {},   -- [npcID]    = true means COLLAPSED
            wishList = false, -- true means COLLAPSED
            ahList   = false, -- Auction House (crafted/BoE) section; true means COLLAPSED
        },
    }
end

-- Vendor notes. Keyed by npcID; LRU-pruned at 100 in VENDOR_NOTE_SET reducer.
local function NewVendorNotes()
    return {}   -- [npcID] = { text = string, ts = number }
end

-- Recipe knowledge: keyed by itemID for O(1) lookup. selfKnown populated by RecipeKnowledgeScanner.
local function NewRecipes()
    return {}   -- [itemID] = { spellID, selfKnown, altKnown }
end

-- Crafting queue + history. Queue rows persist via SavedVariables; history is a ring buffer
-- (cap = HDG.Constants.CRAFT_HISTORY_CAP). sessionKey disambiguates cross-reload entries.
--
-- Shape:
--   queue   = { [1..n] = { recipeID, itemID, requested, remaining,
--                          source = "tradeskill"|"manual",
--                          ts, sessionKey } }
--   history = { entries = { { id, recipeID, itemID, qty, ts } },
--               nextID  = 0 }
local function NewCraft()
    return {
        queue   = {},
        history = { entries = {}, nextID = 0 },
    }
end

-- Per-character roster. Empty until the first scan dispatches a
-- CHARACTER_PROFESSION_UPDATED. Schema for each entry (keyed by charKey =
-- "Name-Realm"):
--   { name, realm, class, classFile, hidden, lastSeen,
--     professions = { [profName] = {
--         skillLines   = { [expName] = { current, max } },
--         knownRecipes = { [recipeID] = true },
--     } } }
local function NewCharacters()
    return {}
end

-- Defaults for session.ui.decor.filters. Single source of truth referenced
-- by NewDecorSessionUI (above; forward-declared so NewDecorSessionUI's
-- body can call it), by DECOR_FILTER_RESET (atomic write), and by
-- ensureDecorFilters (lazy init inside reducer cases).
NewDecorFilters = function()
    return {
        topFilter        = "all",
        activeTag        = nil,
        onlyUncollected  = false,
        onlyStored       = false,
    }
end

-- Accessor for session.ui.decor.filters from inside a reducer case. session.*
-- is rebuilt fresh from NewDefaultState every boot and never rehydrated from
-- SV (Store:LoadFromSavedVariables adopts only account.*), so decor.filters is
-- guaranteed seeded by NewDecorSessionUI -- strict read, no lazy-init guard
-- (ADR-005). Returns the table so the case can read-modify-write; mutation
-- stays reducer-owned (invoked from _RawDispatch only).
local function ensureDecorFilters(state)
    return state.session.ui.decor.filters
end

-- A house VERSION: one design variant (the CURRENT version mirrors reality; what-if
-- versions branch from it). Rooms live HERE (house -> version -> room), keyed by stable
-- roomID; `cell` is a per-room attribute so dragging updates `.cell` while the id (and
-- its crate FK) survive. See docs/HDGR_PROJECTS_PIVOT.md "Layouts = house VERSIONS".
local function NewVersion(houseID, name, createdAt)
    return {
        houseID   = houseID,
        name      = name or "Live",
        createdAt = createdAt,
        basedOn   = nil,       -- parent versionID when branched (what-if); nil for the live version
        numFloors = nil,       -- what-if floor override (1..3); nil = derive from rooms or session
        rooms     = {},        -- [roomID] = RoomRecord { cell = { x, y, rotation, locked }, shape, ... }
    }
end

-- Monotonic version-ID minting. The counter lives in state (account.projects.versionSeq),
-- so the reducer stays a pure function of (state, action): deterministic, collision-free,
-- replayable -- unlike the old random namespacedID("version") which made the reducer
-- non-deterministic. `or 0` is the one legitimate read: a boundary for saved accounts
-- created before the counter existed.
local function _nextVersionID(p)
    p.versionSeq = (p.versionSeq or 0) + 1   -- exception(boundary): pre-counter saved accounts have no versionSeq
    return "version:" .. p.versionSeq
end

-- Resolve (lazily minting on first sight) a house's CURRENT version; returns its
-- versionID. The capture path + the 1->2 migration both funnel reality into the
-- current version. Mints house.currentVersionID/activeVersionID + the version record
-- the first time a never-seen house needs one.
local function _ensureHouseVersion(p, houseID, createdAt)
    local house = p.houses[houseID]
    if not house then house = {}; p.houses[houseID] = house end
    if not house.currentVersionID then
        local vid = _nextVersionID(p)
        house.currentVersionID = vid
        house.activeVersionID  = house.activeVersionID or vid
        p.versions[vid] = NewVersion(houseID, "Live", createdAt)
    end
    return house.currentVersionID
end

local function NewProjectsState()
    -- Persisted house topology (account-shared). Rooms live under
    -- versions[versionID].rooms (house -> version -> room -> crate); crates + Library
    -- live in account.collections (type="crate"/"library"). connections stay
    -- floor-keyed (captured-reality topology, tied to the current version).
    return {
        schemaVersion = 2,
        versionSeq  = 0,    -- monotonic version-ID counter (reducer-pure, collision-free minting)
        houseFocusSeq = 0,  -- monotonic focus counter: the house with the highest house.focusSeq is the one the Architect shows
        houses      = {},   -- [houseID]   = { name, plotID, neighborhoodName, lastCapturedAt, currentVersionID, activeVersionID, focusSeq }
        versions    = {},   -- [versionID] = { houseID, name, createdAt, basedOn, rooms = { [roomID] = RoomRecord } }
        -- (connectivity is DERIVED from cell-adjacency at render -- not stored)
    }
end

-- ===== Recent Activity (HDG parity) =========================================
-- Persisted per-house edit-session history. Keyed by the STABLE faction house
-- id (makeHouseID) -- NOT the process-scoped C_Housing houseGUID, which changes
-- across reloads. Shape:
--   recentActivity = {
--     lastHouseKey = "house:alliance",        -- house the Recent tab shows
--     houses = { [houseKey] = {
--       sessionOrder = { sid, ... },          -- newest-first
--       sessions = { [sid] = {
--         sessionID, startedAt, endedAt?,     -- endedAt nil => active ("Now")
--         eventCount,                         -- total placed+removed events
--         events = { [itemID] = { itemID, placed, removed, lastTs } },
--       } },
--     } },
--   }
local RECENT_SESSION_CAP = 20   -- keep N most-recent sessions per house
local RECENT_ACTION_CAP  = 40   -- keep N most-recent place/remove ACTIONS per session (strip feed)
local function NewRecentActivity()
    return { houses = {}, lastHouseKey = nil }
end

-- Append a placed/removed event to the active session for houseKey, lazily
-- opening a session if none is active (a placement/removal before an explicit
-- RECENT_SESSION_START). Aggregates by itemID. `kind` is "placed" or "removed".
local function _recentAppend(state, houseKey, itemID, kind)
    if not (houseKey and itemID) then return end
    local ra = state.account.recentActivity
    local house = ra.houses[houseKey]
    if not house then
        house = { sessionOrder = {}, sessions = {} }
        ra.houses[houseKey] = house
        ra.lastHouseKey = ra.lastHouseKey or houseKey
    end
    local sid     = house.sessionOrder[1]
    local session = sid and house.sessions[sid]
    if not (session and not session.endedAt) then
        sid = (_G.time and _G.time()) or 0   -- exception(boundary): session id = wall-clock stamp
        if house.sessions[sid] then sid = sid + 1 end
        session = { sessionID = sid, startedAt = sid, endedAt = nil, eventCount = 0, events = {}, actions = {} }
        house.sessions[sid] = session
        table.insert(house.sessionOrder, 1, sid)
    end
    local ev = session.events[itemID]
    if not ev then
        ev = { itemID = itemID, placed = 0, removed = 0, lastTs = 0 }
        session.events[itemID] = ev
    end
    ev[kind]          = (ev[kind] or 0) + 1
    ev.lastTs         = (_G.time and _G.time()) or 0   -- exception(boundary): last-event wall-clock stamp
    session.eventCount = (session.eventCount or 0) + 1
    -- Per-ACTION log for the recent STRIP (1 card = 1 place/remove action), newest
    -- first, capped. The `events` aggregate above still powers the recent-MODE grid
    -- (per-item multiples). actions seeded on new sessions; or-{} covers pre-existing
    -- persisted sessions (SV migration boundary).
    session.actions = session.actions or {}
    table.insert(session.actions, 1, { itemID = itemID, kind = kind, ts = ev.lastTs })
    for i = #session.actions, RECENT_ACTION_CAP + 1, -1 do session.actions[i] = nil end
end

local function NewDefaultState()
    return {
        account = {
            schemaVersion        = HDG.Constants.SCHEMA_VERSION,
            config               = NewConfig(),
            ui                   = NewAccountUI(),
            collection           = NewCollection(),
            favorites            = NewFavorites(),   -- G2
            userNotes            = NewUserNotes(),    -- G3
            vendorNotes          = NewVendorNotes(),
            recipes              = NewRecipes(),      -- partial; alt scanner fills altKnown on character scan
            craft                = NewCraft(),        -- queue + history
            characters           = NewCharacters(),   -- alts roster
            prices               = NewPrices(),       -- price cache
            collections          = {},                -- Styles / Snapshots / Shopping / Crates / etc., keyed by "<type>:<id>"
            collectionSeq        = 0,                 -- monotonic counter -> collision-free smartset ids + "<Char> Style N" labels
            projects             = NewProjectsState(),
            questCompletions      = {},                -- account-wide quest completions: [questID] = { name, class } (first char to record wins; QUEST_COMPLETION_RECORDED)
                vendorShoppingLists  = NewVendorShoppingLists(),
            activeShoppingListId = NewActiveShoppingListId(),
            shoppingListSeq      = NewShoppingListSeq(),
            lumber               = { config = NewLumberConfig(), sessions = {}, history = { entries = {}, nextID = 0 } },
            -- Recent Activity: persisted per-house edit-session history (HDG parity).
            recentActivity       = NewRecentActivity(),
        },
        session = NewDefaultSession(),
    }
end

-- ===== Shape ensurance ========================================================

local function EnsureConfig(account)
    local defaults = NewConfig()
    account.config = account.config or {}
    for key, value in pairs(defaults) do
        if account.config[key] == nil then account.config[key] = value end
    end
end

local function EnsureUI(account)
    local defaults = NewAccountUI()
    account.ui = account.ui or {}
    for key, value in pairs(defaults) do
        if account.ui[key] == nil then account.ui[key] = DeepCopy(value) end
    end
end

local function EnsureCollection(account)
    local defaults = NewCollection()
    account.collection = account.collection or {}
    for key, value in pairs(defaults) do
        if account.collection[key] == nil then account.collection[key] = DeepCopy(value) end
    end
    -- SV migration: nil out legacy catalog mirrors (now owned by observer).
    local col = account.collection
    col.decorCatalog         = nil
    col.catalogByItem        = nil
    col.liveDecorIDs         = nil
    col.lastSweep            = nil
    col.clientVer            = nil
    col.catalogSchemaVersion = nil
end

-- Key-by-key merge from NewCraft -- matches EnsureConfig/EnsureUI pattern so
-- new sub-fields added to NewCraft() flow to existing users on next load.
-- History.entries + nextID also default-merged.
local function EnsureCraft(account)
    account.craft = account.craft or {}
    local defaults = NewCraft()
    for key, value in pairs(defaults) do
        if account.craft[key] == nil then account.craft[key] = DeepCopy(value) end
    end
    account.craft.history = account.craft.history or {}
    for key, value in pairs(defaults.history) do
        if account.craft.history[key] == nil then account.craft.history[key] = DeepCopy(value) end
    end
end

-- Shopping list shape ensurance. Reseeds the monotonic counter past any
-- existing list ID so a partial DB (deleted entries followed by reload)
-- doesn't risk colliding with a previously-used slot. ID format: "L<n>".
local function EnsureShopping(account)
    if type(account.vendorShoppingLists) ~= "table" then
        account.vendorShoppingLists = NewVendorShoppingLists()
    end
    if type(account.activeShoppingListId) ~= "string" then
        account.activeShoppingListId = NewActiveShoppingListId()
    end
    if type(account.shoppingListSeq) ~= "number" then
        local maxN = 0
        for id in pairs(account.vendorShoppingLists) do
            local n = tonumber(string.match(id, "^L(%d+)$"))
            if n and n > maxN then maxN = n end
        end
        account.shoppingListSeq = maxN
    end
    -- Seed a default list when the account has none, so "Add to Cart" works out
    -- of the box. Covers brand-new accounts AND any account that deleted its last
    -- list (both land at vendorShoppingLists = {} + activeShoppingListId = "" ->
    -- the "No active shopping list" dead-end). Runs after the seq reseed above so
    -- the new ID can't collide with a previously-used slot. Mirrors the
    -- SHOPPING_LIST_CREATE reducer's record shape + auto-activate.
    if next(account.vendorShoppingLists) == nil and account.activeShoppingListId == "" then
        account.shoppingListSeq = account.shoppingListSeq + 1
        local id = "L" .. tostring(account.shoppingListSeq)
        account.vendorShoppingLists[id] = {
            name      = "Shopping List",
            items     = {},
            meta      = {},
            createdAt = time(),
        }
        account.activeShoppingListId = id
    end
end

local function EnsureSession(state)
    state.session         = state.session         or NewDefaultSession()
    state.session.ui      = state.session.ui      or NewSessionUI()
    state.session.ui.projects = state.session.ui.projects or NewProjectsSessionUI()
    state.session.ui.recipes = state.session.ui.recipes or NewRecipesSessionUI()
    state.session.ui.warehouse = state.session.ui.warehouse or NewWarehouseSessionUI()
    state.session.combat  = state.session.combat  or { inLockdown = false, queued = {} }
    state.session.log     = state.session.log     or NewSessionLog()
    state.session.bag     = state.session.bag     or NewBagSession()
    state.session.itemNames  = state.session.itemNames  or NewItemNamesSession()
    state.session.questNames = state.session.questNames or NewQuestNamesSession()
    state.session.questStatus = state.session.questStatus or NewQuestStatusSession()
    state.session.achievementStatus = state.session.achievementStatus or NewAchievementStatusSession()
    state.session.staticData = state.session.staticData or NewStaticDataSession()
    state.session.identity = state.session.identity or NewIdentitySession()
    state.session.prices     = state.session.prices     or NewPricesSession()
    state.session.styles    = state.session.styles    or NewStylesSession()
    state.session.ui.styles = state.session.ui.styles or NewStylesSessionUI()
    state.session.ui.houseTab = state.session.ui.houseTab or NewHouseTabSessionUI()
    state.session.ui.data = state.session.ui.data or NewDataSessionUI()  -- Your Data collapse bucket
    state.session.ui.shoppingList = state.session.ui.shoppingList or NewShoppingSessionUI()
    state.session.ui.zoneScanner  = state.session.ui.zoneScanner  or NewZoneScannerSessionUI()
    state.session.ui.removalist    = state.session.ui.removalist    or NewRemovalistSessionUI()
    state.session.zone      = state.session.zone      or NewZoneState()
    state.session.catalog   = state.session.catalog   or NewSessionCatalog()
    state.session.lumber    = state.session.lumber    or NewLumberSession()
    state.session.rep       = state.session.rep       or NewRepSession()      -- live rep tick (RepObserver)
    -- session.house + session.daily are seeded by NewDefaultSession; EnsureSession
    -- does not need or-guards for them (strict reads from here forward).
end

-- Projects schemaVersion 1 -> 2: the flat `account.projects.rooms[roomID]` map becomes
-- `versions[versionID].rooms[roomID]` (house -> version -> room). Per house, seed a
-- current version; move each flat room (keyed by its parsed houseID) into that version;
-- stamp each crate's versionID from its parent room's house current version; drop the
-- flat `rooms`. boundary: legitimate SV migration -- runs once at LoadFromSavedVariables
-- (ADDON_LOADED), where HDG.Projects.IDs is loaded. Pre-release + cheap (no live users).
local function MigrateProjectsToVersions(state)
    local p = state.account.projects
    p.versions = p.versions or {}
    if (p.schemaVersion or 1) >= 2 then
        p.rooms = nil   -- guarantee the legacy flat map is gone even on an already-migrated DB
        return
    end
    local nowTS = (time and time()) or 0   -- exception(boundary): createdAt stamp for seeded versions
    -- Seed a current version for every known house first, then fold each flat room into
    -- its house's current version (minting the house on demand if a room references a
    -- house that was never UPSERT'd -- parsePath gives a well-formed houseID).
    for houseID in pairs(p.houses) do
        local house = p.houses[houseID]
        _ensureHouseVersion(p, houseID, house.lastCapturedAt or nowTS)
    end
    for roomID, room in pairs(p.rooms or {}) do
        local parsed  = HDG.Projects.IDs.parsePath(roomID)
        local houseID = parsed and parsed.houseID
        if houseID then
            local vid = _ensureHouseVersion(p, houseID, nowTS)
            room.cell = room.cell or { x = 0, y = 0, rotation = 0, locked = false }
            room.plannedOnly = nil   -- the captured/planned split is now WHICH version, not a flag
            p.versions[vid].rooms[roomID] = room
        end
    end
    for _, coll in pairs(state.account.collections) do
        if coll.type == "crate" and coll.parent and not coll.versionID then
            local parsed  = HDG.Projects.IDs.parsePath(coll.parent)
            local houseID = parsed and parsed.houseID
            local house   = houseID and p.houses[houseID]
            if house and house.currentVersionID then coll.versionID = house.currentVersionID end
        end
    end
    p.rooms = nil
    p.schemaVersion = 2
end

local function EnsureStateShape(state)
    state.account = state.account or {}
    state.account.schemaVersion = state.account.schemaVersion or HDG.Constants.SCHEMA_VERSION
    EnsureConfig(state.account)
    EnsureUI(state.account)
    EnsureCollection(state.account)
    state.account.favorites   = state.account.favorites   or NewFavorites()
    state.account.userNotes   = state.account.userNotes   or NewUserNotes()
    state.account.vendorNotes = state.account.vendorNotes or NewVendorNotes()
    state.account.recipes     = state.account.recipes     or NewRecipes()
    EnsureCraft(state.account)
    EnsureShopping(state.account)
    state.account.characters  = state.account.characters  or NewCharacters()
    state.account.prices      = state.account.prices      or NewPrices()
    state.account.prices.directCache    = state.account.prices.directCache    or {}
    state.account.prices.directQtyCache = state.account.prices.directQtyCache or {}
    state.account.prices.ownedAuctions  = state.account.prices.ownedAuctions  or {}
    state.account.collections = state.account.collections or {}   -- exception(boundary): SavedVariables migration for Styles tab + Crates
    -- Projects topology: re-ensure sub-fields so saves predating a field get it backfilled (SV migration).
    state.account.projects = state.account.projects or NewProjectsState()
    state.account.projects.houses      = state.account.projects.houses      or {}
    state.account.projects.versions    = state.account.projects.versions    or {}
    state.account.projects.versionSeq  = state.account.projects.versionSeq  or 0
    state.account.projects.houseFocusSeq = state.account.projects.houseFocusSeq or 0
    MigrateProjectsToVersions(state)   -- schemaVersion 1->2: flat rooms -> versions[current].rooms
    state.account.questCompletions = state.account.questCompletions or {}   -- exception(boundary): SV migration
    -- Lumber tracker config + per-char sessions. Config key-by-key from NewLumberConfig
    -- so new defaults flow to existing users (SV migration).
    state.account.lumber          = state.account.lumber          or {}
    state.account.lumber.config   = state.account.lumber.config   or {}
    state.account.lumber.sessions = state.account.lumber.sessions or {}
    -- exception(boundary): SV migration -- farming history ring buffer added post-initial-release.
    state.account.lumber.history = state.account.lumber.history or {}
    state.account.lumber.history.entries = state.account.lumber.history.entries or {}
    state.account.lumber.history.nextID  = state.account.lumber.history.nextID  or 0
    local lumberDefaults = NewLumberConfig()
    for key, value in pairs(lumberDefaults) do
        if state.account.lumber.config[key] == nil then
            state.account.lumber.config[key] = DeepCopy(value)
        end
    end
    state.account.ui.companion = state.account.ui.companion or NewCompanionAccountUI()
    state.account.ui.companion.window = state.account.ui.companion.window or { x = nil, y = nil }
    state.account.ui.companion.launcher = state.account.ui.companion.launcher or { x = nil, y = nil }
    -- Recent Activity (HDG parity). boundary: SV migration -- guarantees the
    -- slice for saves created before edit-session history existed.
    state.account.recentActivity = state.account.recentActivity or NewRecentActivity()
    state.account.recentActivity.houses = state.account.recentActivity.houses or {}
    state.account.ui.houseTab = state.account.ui.houseTab or NewHouseTabAccountUI()
    state.account.ui.houseTab.enabled         = state.account.ui.houseTab.enabled         or {}
    state.account.ui.houseTab.order           = state.account.ui.houseTab.order           or {}
    state.account.ui.houseTab.width           = state.account.ui.houseTab.width           or {}
    state.account.ui.houseTab.layoutOverrides = state.account.ui.houseTab.layoutOverrides or {}
    -- Recipes persisted filters (SETs; empty = all). boundary: SV migration --
    -- guarantees the tables for saves created before these fields existed.
    state.account.ui.recipes = state.account.ui.recipes or {}
    state.account.ui.recipes.expansionFilter        = state.account.ui.recipes.expansionFilter        or {}
    state.account.ui.recipes.professionFilterByChar  = state.account.ui.recipes.professionFilterByChar or {}
    EnsureSession(state)
end

-- ===== Store object ===========================================================

HDG.Store = {
    state = NewDefaultState(),
    _subscribers = {},
    _pendingNotifications = nil,
    _flushScheduled = false,
    _saveTimer = nil,
    _saveDelay = 1,   -- seconds to coalesce saves
}

-- Public accessor for the action-meta table stamped by HDGR_Init.lua at
-- boot. Encapsulates _actionMeta so external readers (Components dispatcher,
-- tests) don't reach into the underscore-prefixed field. Returns nil for
-- unknown action types -- callers should treat nil as "no meta declared,
-- use defaults" (matches the per-field reads in dispatch hot paths).
function HDG.Store:GetActionMeta(actionType)
    return self._actionMeta and self._actionMeta[actionType] or nil
end

function HDG.Store:GetState()
    return self.state
end

function HDG.Store:GetConfig(key)
    -- Strict read of the canonical path. Loud failure (Lua error) if state
    -- hasn't been initialized -- callers must run after Store:LoadFromSavedVariables.
    return self.state.account.config[key]
end

-- Returns a fresh table of the canonical NewConfig() defaults. Used by the
-- Blizzard Settings panel's "Reset all settings" button: iterate the keys
-- on the panel and dispatch CONFIG_SET per key with defaults[key] as the
-- value. NewConfig is the single source of truth for default values.
function HDG.Store:GetDefaultConfig()
    return NewConfig()
end

-- ===== Subscribe / Notify =====================================================

function HDG.Store:Subscribe(fn)
    if type(fn) ~= "function" then return nil end
    self._subscribers[fn] = true
    return fn
end

function HDG.Store:Unsubscribe(fn)
    self._subscribers[fn] = nil
end

-- Deferred notification: C_Timer.After(0) batches multiple dispatches in the
-- same frame, fanning each accumulated action out to every subscriber on
-- the next frame. Prevents re-entrant-flush corruption (a subscriber that
-- dispatches back into the store cannot perturb the in-progress loop).
--
-- Each notification carries an `invalidation` value (a list of
-- state paths OR the sentinel "*") so subscribers can filter their work
-- by what actually changed. Subscribers that only consume actionType
-- continue to work -- the second arg is additive.
function HDG.Store:_Notify(actionType, invalidation, action)
    invalidation = invalidation or "*"
    self._pendingNotifications = self._pendingNotifications or {}
    self._pendingNotifications[#self._pendingNotifications + 1] = {
        type        = actionType,
        invalidation = invalidation,
        action      = action,
    }
    if self._flushScheduled then return end
    self._flushScheduled = true

    local function flush()
        local pending = self._pendingNotifications
        self._pendingNotifications = nil
        self._flushScheduled = false
        if not pending then return end
        local snapshot = {}
        for fn in pairs(self._subscribers) do snapshot[#snapshot + 1] = fn end
        -- No blanket pcall: real bugs must surface loudly, not silently corrupt state.
        -- ErrorBoundaryMiddleware handles crash-recovery at the outer layer.
        -- exception(boundary): Perf instrumentation is optional, may be absent in early boot / tests.
        local perf = HDG.Perf
        local timed = perf and perf:Enabled()
        local t0 = timed and _G.debugprofilestop() or nil

        for _, n in ipairs(pending) do
            for _, fn in ipairs(snapshot) do
                fn(n.type, n.invalidation, n.action)
            end
        end

        if timed then
            perf:RecordFlush(pending, _G.debugprofilestop() - t0, #snapshot)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, flush)
    else
        flush()
    end
end

-- Synchronous flush. Used at PLAYER_LOGOUT where the deferred C_Timer.After
-- callback won't fire before the client unloads -- subscribers registered
-- on SESSION_END would be silently dropped otherwise. Drains the same
-- pending queue the deferred flush would, with identical fan-out shape.
function HDG.Store:FlushNotifications()
    if not self._pendingNotifications then return end
    local pending = self._pendingNotifications
    self._pendingNotifications = nil
    self._flushScheduled = false
    local snapshot = {}
    for fn in pairs(self._subscribers) do snapshot[#snapshot + 1] = fn end
    -- Same no-blanket-pcall rationale as the deferred flush path.
    for _, n in ipairs(pending) do
        for _, fn in ipairs(snapshot) do
            fn(n.type, n.invalidation, n.action)
        end
    end
end

-- ===== Projects reducer helpers ===============================================
-- Orphan ONE crate off its current room: stamp last-known provenance (so the re-attach
-- UI can suggest a home + the crate ledger can show "was <room>"), then clear .parent +
-- .versionID so it drops to the orphan bay. Shared by the room-delete sweep below and
-- the single-crate CRATE_DETACH action.
local function _orphanCrate(state, coll, nowTS)
    local version = coll.versionID and state.account.projects.versions[coll.versionID]
    local rec     = version and coll.parent and version.rooms[coll.parent]
    coll.lastKnownRoomID    = coll.parent
    coll.lastKnownVersionID = coll.versionID
    coll.lastKnownShape     = rec and rec.shape
    coll.lastKnownRoomName  = rec and rec.name
    coll.orphanedAt         = nowTS
    coll.parent             = nil
    coll.versionID          = nil
end

-- Detach every crate parented to a demolished room. Crates are scoped by (versionID,
-- roomID) -- a room only exists within a version, so the orphan filter must match BOTH
-- (a same-roomID room in a sibling what-if keeps its crate).
local function _orphanCratesForRoom(state, versionID, roomID, nowTS)
    for _, coll in pairs(state.account.collections) do
        if coll.type == "crate" and coll.versionID == versionID and coll.parent == roomID then
            _orphanCrate(state, coll, nowTS)
        end
    end
end

-- Ordered decor-list index lookup for a crate (records deduped by .id).
local function _crateDecorIndex(crate, decorID)
    for i, rec in ipairs(crate.decor or {}) do
        if rec.id == decorID then return i end
    end
end

-- ===== Reducer (pure, no side effects) =======================================
-- Every state mutation in HDG lives here. The middleware chain wraps this
-- call so Logger / Combat / Persistence layers fire at the right edges
-- without the reducer caring.

-- Multi-select filter-set toggle: value=="all" clears the set (-> "All"); else
-- flip membership. Shared by the 5 ACQ_TOGGLE_* cases (empty set = all).
local function _acqToggleFilter(set, value)
    if value == "all" then
        for k in pairs(set) do set[k] = nil end
    else
        set[value] = not (set[value] == true) and true or nil
    end
end

function HDG.Store:_RawDispatch(action)
    if type(action) ~= "table" or not action.type then
        error("HDG.Store:_RawDispatch requires {type=..., payload=?}", 2)
    end
    local A = HDG.Constants.ACTIONS
    local payload = action.payload or {}
    EnsureStateShape(self.state)

    -- Resolve the invalidation set BEFORE running the reducer.
    -- Action meta declares `invalidates` as a static list, a function
    -- (payload-dependent), or "*". Actions without meta or without an
    -- `invalidates` field implicitly default to "*" (refresh-all).
    local invalidation = "*"
    local meta = self._actionMeta and self._actionMeta[action.type]
    if meta then
        local inv = meta.invalidates
        if type(inv) == "function" then
            local ok, result = pcall(inv, action)
            if not ok then
                HDG.Log:Warn("store",
                    ("invalidates fn for %s errored: %s"):format(tostring(action.type), tostring(result)))
            end
            invalidation = (ok and result) or "*"
        elseif inv ~= nil then
            invalidation = inv
        end
    end

    if action.type == A.CONFIG_SET then
        if payload.key ~= nil then
            -- Dual-write: SV slot (profile / character / account, routed
            -- by HDG.Config) AND the in-memory mirror at
            -- state.account.config. Mirror keeps existing selectors with
            -- `reads = { "account.config.X" }` working unchanged.
            -- Scope resolution: explicit payload.scope wins; otherwise
            -- look it up from the schema. Keys absent from both are a
            -- schema-drift bug -- we crash loudly rather than silently
            -- mis-route the write.
            local scope = payload.scope or HDG.ConfigSchema.ScopeBy[payload.key]
            local src = HDG.Config:_GetSourceForScope(scope)
            src[payload.key] = payload.value
            -- Account-scoped settings (one-time migration flags) live at
            -- the top of HDG_DB and don't belong in the per-profile mirror.
            if scope ~= HDG.Constants.ConfigScope.Account then
                self.state.account.config[payload.key] = payload.value
            end
        end

    elseif action.type == A.CONFIG_SCALE_STEP then
        -- Step the UI scale by +/-0.1 within [0.5, 1.5] (bounds mirror the Config controller's
        -- SCALE_MIN/MAX/STEP). Reducer owns the clamp; the view dispatches only a direction.
        -- Same dual-write as CONFIG_SET (SV source + in-memory mirror); scale is profile-scoped.
        local cur = self.state.account.config.scale
        local nxt = cur + (payload.direction == "inc" and 0.1 or -0.1)
        nxt = (payload.direction == "inc") and math.min(1.5, nxt) or math.max(0.5, nxt)
        nxt = math.floor(nxt * 10 + 0.5) / 10
        local scope = HDG.ConfigSchema.ScopeBy["scale"]
        HDG.Config:_GetSourceForScope(scope)["scale"] = nxt
        if scope ~= HDG.Constants.ConfigScope.Account then
            self.state.account.config.scale = nxt
        end

    elseif action.type == A.PROFILE_CREATE then
        local name = payload.name
        if type(name) == "string" and name ~= "" and not HDG_DB.profiles[name] then
            HDG_DB.profiles[name] = {}
            if payload.cloneFrom and HDG_DB.profiles[payload.cloneFrom] then
                for k, v in pairs(HDG_DB.profiles[payload.cloneFrom]) do
                    HDG_DB.profiles[name][k] = v
                end
            end
        end

    elseif action.type == A.PROFILE_SWITCH then
        local name = payload.name
        if type(name) == "string" and HDG_DB.profiles[name] then
            HDG_DB_CURRENT_PROFILE = name
            HDG.Config._activeProfile = name
            HDG.Config:_ImportDefaultsToActiveProfile()
            HDG.Config:_HydrateMirror()
        end

    elseif action.type == A.PROFILE_DELETE then
        local name = payload.name
        if type(name) == "string" and name ~= "DEFAULT" and name ~= HDG.Config._activeProfile then
            HDG_DB.profiles[name] = nil
        end

    elseif action.type == A.UI_SET_PERSISTENT then
        if payload.key ~= nil then self.state.account.ui[payload.key] = payload.value end

    elseif action.type == A.UI_SET_TRANSIENT then
        if payload.view then
            self.state.session.ui[payload.view] = self.state.session.ui[payload.view] or {}
            if payload.key ~= nil then
                self.state.session.ui[payload.view][payload.key] = payload.value
            end
        else
            if payload.key ~= nil then
                self.state.session.ui[payload.key] = payload.value
            end
        end

    elseif action.type == A.REMOVALIST_PICK_PLOT then
        -- Two-click cycle: 1st pick -> source, 2nd (distinct) -> target, else restart.
        local r    = self.state.session.ui.removalist
        local plot = payload.plot
        if not r.sourcePlot then
            r.sourcePlot = plot
        elseif not r.targetPlot and plot ~= r.sourcePlot then
            r.targetPlot = plot
        else
            r.sourcePlot, r.targetPlot = plot, nil
        end

    elseif action.type == A.REMOVALIST_SWAP then
        local r = self.state.session.ui.removalist
        r.sourcePlot, r.targetPlot = r.targetPlot, r.sourcePlot

    elseif action.type == A.REMOVALIST_CLEAR then
        local r = self.state.session.ui.removalist
        r.sourcePlot, r.targetPlot = nil, nil

    elseif action.type == A.REMOVALIST_SET_LETTER_FILTER then
        -- nil payload (refresh) or re-clicking the active letter clears; else set.
        local r = self.state.session.ui.removalist
        local l = payload.letter
        if l == nil or r.letterFilter == l then r.letterFilter = nil else r.letterFilter = l end

    elseif action.type == A.REMOVALIST_SET_PLOT then
        -- Map-click selection: the Source map sets source, the Target map sets target.
        local r = self.state.session.ui.removalist
        if payload.role == "source" then r.sourcePlot = payload.plot
        elseif payload.role == "target" then r.targetPlot = payload.plot end

    elseif action.type == A.MAIN_WINDOW_TOGGLE then
        self.state.account.ui.mainWindowShown = not (self.state.account.ui.mainWindowShown == true)

    elseif action.type == A.NAV_TOGGLE_GROUP then
        -- Flip a sidebar parent group's collapsed state (keyed by hub view).
        -- nil-clear when expanding so the set stays sparse (only collapsed groups present).
        local groups = self.state.account.ui.nav.collapsedGroups
        local v = payload.view
        groups[v] = (not groups[v]) and true or nil

    elseif action.type == A.SESSION_END then
        -- Force all addon windows closed at logout (don't auto-reopen on /reload).
        -- Zone auto-popup fires on ZONE_CHANGED independently (not from these flags).
        self.state.account.ui.mainWindowShown        = false
        self.state.account.ui.shoppingWidgetShown    = false
        self.state.account.ui.zonePopupShown         = false
        self.state.account.lumber.config.windowVisible = false

    elseif action.type == A.HARD_RESET then
        _G.HDG_DB = {}
        self.state = NewDefaultState()

    elseif action.type == A.COLLECTION_RESET then
        -- Wipe the ownership cache so the next reconciler sweep rebuilds from
        -- scratch. The catalog mirror (decorCatalog/catalogByItem/liveDecorIDs)
        -- HousingCatalogObserver owns the row store and clears it on COLLECTION_RESET.
        self.state.account.collection.ownedDecorIDs = {}

    elseif action.type == A.COMBAT_ENTER then
        self.state.session.combat.inLockdown = true

    elseif action.type == A.COMBAT_EXIT then
        self.state.session.combat.inLockdown = false
        -- Reducer empties the queue here so middleware never mutates state
        -- directly. CombatMiddleware snapshots the queue BEFORE dispatching
        -- COMBAT_EXIT and re-dispatches the snapshot through the chain.
        self.state.session.combat.queued = {}

    elseif action.type == A.COMBAT_QUEUE_ACTION then
        -- Append a deferred action to the lockdown queue. Middleware dispatches
        -- this when an inbound combat-unsafe action arrives during lockdown;
        -- the inbound action's payload is wrapped inside payload.action.
        self.state.session.combat.queued = self.state.session.combat.queued or {}
        if payload.action then
            table.insert(self.state.session.combat.queued, payload.action)
        end

    elseif action.type == A.ACQ_SET_ITEMS_VIEW_MODE then
        local mode = payload.mode
        if mode == "grid" or mode == "list" then
            -- account.ui.acquisition seeded by EnsureUI on every dispatch (ADR-005)
            self.state.account.ui.acquisition.itemsViewMode = mode
        end

    elseif action.type == A.ACQ_TOGGLE_ADVANCED_FILTERS then
        local a = self.state.session.ui.acquisition
        a.advancedFiltersOpen = not (a.advancedFiltersOpen == true)

    elseif action.type == A.ACQ_SET_PRESET then
        -- Single-select preset chip; toggling the active value clears it.
        -- Note: Lua 5.1 `(cond) and nil or v` trap -- must use a real branch when value is nil.
        local v = payload.value
        if self.state.session.ui.acquisition.preset == v then
            self.state.session.ui.acquisition.preset = nil
        else
            self.state.session.ui.acquisition.preset = v
        end

    elseif action.type == A.ACQ_TOGGLE_MISSING then
        -- Collection-state toggle, orthogonal to the source preset. Flips so
        -- the Missing checkbox ANDs with whatever source chip is lit.
        self.state.session.ui.acquisition.missingOnly =
            not self.state.session.ui.acquisition.missingOnly

    -- Advanced-filter multi-select set toggles. payload.<axis> == "all" clears the
    -- set (master "All X" -> show every value); else flip membership. Empty = all.
    -- Clone of RECIPES_TOGGLE_EXPANSION; session-scoped (no persistence).
    elseif action.type == A.ACQ_TOGGLE_EXPANSION then
        _acqToggleFilter(self.state.session.ui.acquisition.expansionFilter, payload.expansion)
    elseif action.type == A.ACQ_TOGGLE_ZONE then
        _acqToggleFilter(self.state.session.ui.acquisition.zoneFilter, payload.zone)
    elseif action.type == A.ACQ_TOGGLE_REP then
        _acqToggleFilter(self.state.session.ui.acquisition.repFilter, payload.rep)
    elseif action.type == A.ACQ_TOGGLE_SOURCE then
        _acqToggleFilter(self.state.session.ui.acquisition.sourceFilter, payload.source)
    elseif action.type == A.ACQ_TOGGLE_FACTION then
        _acqToggleFilter(self.state.session.ui.acquisition.factionFilter, payload.faction)

    elseif action.type == A.UI_FILTER_RESET then
        -- Atomic per-tab filter reset (ADR-018). Tab-specific logic lives in
        -- the dispatch table below; no new action enum needed for additional tabs.
        local tab = payload.tab
        if tab == "decor" then
            self.state.session.ui.decor.searchQuery = ""
            self.state.session.ui.decor.filters     = NewDecorFilters()
        elseif tab == "acquisition" then
            local acq = self.state.session.ui.acquisition
            acq.searchQuery     = ""
            acq.preset          = nil
            acq.missingOnly     = false
            acq.factionFilter   = {}
            acq.expansionFilter = {}
            acq.zoneFilter      = {}
            acq.repFilter       = {}
            acq.sourceFilter    = {}
        elseif tab == "recipes" then
            local r = self.state.session.ui.recipes
            r.searchQuery         = ""
            r.listFilter          = "all"
            r.filters             = NewRecipesFilters()
            -- expansionFilter is account-wide: clear in-place -> all expansions.
            local exp = self.state.account.ui.recipes.expansionFilter
            for k in pairs(exp) do exp[k] = nil end
            -- professions are per-character: drop this char's entry so it reverts to
            -- the pristine default (= this character's professions).
            self.state.account.ui.recipes.professionFilterByChar[self.state.session.identity.charKey] = nil
        end

    elseif action.type == A.DECOR_CATALOG_READY then
        -- Notification-only (retained for closed-taxonomy check).

    elseif action.type == A.MAIN_WINDOW_OPENING then
        -- Lifecycle signal; no mutation. Subscribers handle catch-up.

    elseif action.type == A.LOG_PUSH then
        -- Pure append + cap. entry.id is a raw integer (no "log_" prefix needed).
        local log = self.state.session.log
        log.nextID = (log.nextID or 0) + 1
        local entry = {
            id        = log.nextID,
            tag       = payload.tag,
            level     = payload.level,
            text      = payload.text,
            timestamp = payload.timestamp,
            duration  = payload.duration,
            metadata  = payload.metadata,
        }
        log.entries[#log.entries + 1] = entry
        -- Per-tag sub-cap for the "dispatch" tag; removes oldest first.
        if entry.tag == "dispatch" then
            local dispatchCap = log.dispatchCap
            local dispatchCount = 0
            for _, e in ipairs(log.entries) do
                if e.tag == "dispatch" then dispatchCount = dispatchCount + 1 end
            end
            while dispatchCount > dispatchCap do
                for i, e in ipairs(log.entries) do
                    if e.tag == "dispatch" then
                        table.remove(log.entries, i)
                        dispatchCount = dispatchCount - 1
                        break
                    end
                end
            end
        end
        -- Overall ring buffer cap.
        local cap = log.cap
        while #log.entries > cap do
            table.remove(log.entries, 1)
        end

    elseif action.type == A.LOG_CLEAR then
        if payload.tag and payload.tag ~= "all" and payload.tag ~= "*" then
            local entries = self.state.session.log.entries
            for i = #entries, 1, -1 do
                if entries[i].tag == payload.tag then
                    table.remove(entries, i)
                end
            end
        else
            self.state.session.log.entries = {}
        end

    elseif action.type == A.LOG_SET_FILTER then
        local f = self.state.session.log.tabFilter
        if payload.tag        ~= nil then f.tag        = payload.tag        end
        if payload.level      ~= nil then f.level      = payload.level      end
        if payload.autoScroll ~= nil then f.autoScroll = payload.autoScroll end

    elseif action.type == A.LOG_TOGGLE_AUTOSCROLL then
        local f = self.state.session.log.tabFilter
        f.autoScroll = not (f.autoScroll == true)

    elseif action.type == A.COLLECTION_BULK_LOAD then
        -- Wholesale ownership replace. Catalog mirrors are observer-local;
        -- only ownedDecorIDs persists (warm-start fallback seam; not currently read at runtime).
        self.state.account.collection.ownedDecorIDs = payload.owned

    elseif action.type == A.COLLECTION_ITEM_LEARNED then
        if payload.decorID then
            self.state.account.collection.ownedDecorIDs[payload.decorID] = true
        end

    elseif action.type == A.COLLECTION_ITEM_REMOVED then
        if payload.decorID then
            self.state.account.collection.ownedDecorIDs[payload.decorID] = nil
        end

    elseif action.type == A.COLLECTION_CATALOG_ROW_ADDED then
        -- Observer-owned; reducer is a no-op (retained for closed-taxonomy check).

    elseif action.type == A.COLLECTION_CATALOG_ROW_REMOVED then
        -- Observer calls R:RemoveRow; reducer only scrubs ownedDecorIDs for consistency.
        if payload.decorID then
            self.state.account.collection.ownedDecorIDs[payload.decorID] = nil
        end

    elseif action.type == A.COLLECTION_CATALOG_ROW_COUNTS_UPDATED then
        -- Observer calls R:PatchCounts; reducer is a no-op (retained for closed-taxonomy check).

    elseif action.type == A.LOG_TRACE_TOGGLE then
        if payload.tag == "*" or payload.tag == "all" then
            -- Wipe all traces (used by /hdgr trace off)
            self.state.session.log.activeTraces = {}
        elseif payload.tag then
            local on = payload.on
            if on == nil then
                -- Toggle if `on` not provided
                on = not self.state.session.log.activeTraces[payload.tag]
            end
            self.state.session.log.activeTraces[payload.tag] = on or nil
        end

    -- ===== Filter actions ============================================
    -- ensureDecorFilters keeps defaults in NewDecorFilters (SSoT); helpers run only inside _RawDispatch.
    elseif action.type == A.DECOR_SET_TOP_FILTER then
        local f = ensureDecorFilters(self.state)
        local v = payload.value
        -- Validate against HDG.Constants.TOP_FILTERS so the reducer rejects
        -- typo'd values from any caller. Single SSoT for the bucket set.
        local valid = false
        for _, entry in ipairs(HDG.Constants.TOP_FILTERS or {}) do
            if entry.value == v then valid = true; break end
        end
        if valid then
            f.topFilter = v
            -- Switching top filter always clears the active tag (ADR-018).
            f.activeTag = nil
        end

    elseif action.type == A.DECOR_SET_TAG then
        local f = ensureDecorFilters(self.state)
        if payload.tag == nil or type(payload.tag) == "string" then
            f.activeTag = payload.tag
        end

    elseif action.type == A.DECOR_TOGGLE_ONLY_UNCOLLECTED then
        local f = ensureDecorFilters(self.state)
        f.onlyUncollected = not f.onlyUncollected

    elseif action.type == A.DECOR_TOGGLE_ONLY_STORED then
        local f = ensureDecorFilters(self.state)
        f.onlyStored = not f.onlyStored

    elseif action.type == A.DECOR_SET_SEARCH then
        self.state.session.ui.decor.searchQuery = tostring(payload.query)

    -- ===== Favorites (G2) ====================================================
    elseif action.type == A.FAVORITE_TOGGLE then
        if payload.itemID then
            local fav = self.state.account.favorites
            if fav[payload.itemID] then
                fav[payload.itemID] = nil
            else
                fav[payload.itemID] = true
            end
        end

    -- ===== User notes (G3) ===================================================
    elseif action.type == A.NOTE_SET then
        if payload.itemID and payload.text ~= nil then
            self.state.account.userNotes[payload.itemID] = {
                text = payload.text,
                ts   = payload.ts or (_G.GetTime and _G.GetTime() or 0),  -- exception(boundary): GetTime/time absent in headless harness
            }
            -- LRU cap at 500. Iterate to find oldest; cheap at this size.
            local MAX_NOTES = 500
            local notes = self.state.account.userNotes
            local count = 0
            for _ in pairs(notes) do count = count + 1 end
            if count > MAX_NOTES then
                -- `n.ts or 0`: tolerates pre-1.0 savedvar entries that
                -- shipped without timestamps. Treats them as oldest so
                -- they evict first when over cap. Mark boundary so the
                -- sweep recognises the migration intent.
                local oldest_id, oldest_ts = nil, math.huge
                for id, n in pairs(notes) do
                    local ts = n.ts or 0  -- migration
                    if ts < oldest_ts then oldest_ts = ts; oldest_id = id end
                end
                if oldest_id then notes[oldest_id] = nil end
            end
        end

    elseif action.type == A.NOTE_CLEAR then
        if payload.itemID then
            self.state.account.userNotes[payload.itemID] = nil
        end

    -- ===== Vendor notes ======================================================
    elseif action.type == A.VENDOR_NOTE_SET then
        if payload.npcID and payload.text ~= nil then
            self.state.account.vendorNotes[payload.npcID] = {
                text = payload.text,
                ts   = payload.ts or (_G.GetTime and _G.GetTime() or 0),  -- exception(boundary): GetTime/time absent in headless harness
            }
            -- LRU cap at 100 (vendor count is much smaller than item count).
            local MAX_VENDOR_NOTES = 100
            local notes = self.state.account.vendorNotes
            local count = 0
            for _ in pairs(notes) do count = count + 1 end
            if count > MAX_VENDOR_NOTES then
                -- See item-note LRU comment above: `n.ts or 0` covers
                -- pre-1.0 savedvar entries without timestamps. Migration.
                local oldest_id, oldest_ts = nil, math.huge
                for id, n in pairs(notes) do
                    local ts = n.ts or 0  -- migration
                    if ts < oldest_ts then oldest_ts = ts; oldest_id = id end
                end
                if oldest_id then notes[oldest_id] = nil end
            end
        end

    elseif action.type == A.VENDOR_NOTE_CLEAR then
        if payload.npcID then
            self.state.account.vendorNotes[payload.npcID] = nil
        end

    -- ===== Recipe knowledge ==================================================
    elseif action.type == A.RECIPE_KNOWLEDGE_UPDATED then
        -- Bulk replace: RecipeKnowledgeScanner emits the full per-itemID map.
        self.state.account.recipes = payload.entries

    -- ===== Crafting queue + history ==============================
    elseif action.type == A.CRAFT_QUEUE_ADD then
        local q   = self.state.account.craft.queue
        local qty = payload.qty or 1   -- exception(boundary): slash-command dispatcher may omit qty for default-1 add
        -- Coalesce into an existing row with the same recipeID so repeated
        -- Add clicks accumulate qty instead of producing duplicate rows.
        -- Matches HDG's queue semantics + keeps the byRecipe materials view
        -- from showing the same recipe twice. Same recipeID = same craft;
        -- sessionKey is a tiebreaker for cross-reload disambiguation only.
        local merged = false
        for _, row in ipairs(q) do
            if row.recipeID == payload.recipeID then
                row.requested = (row.requested or 0) + qty  -- exception(false-positive): requested accumulator lazy-init
                row.remaining = (row.remaining or 0) + qty  -- exception(boundary): queue row from SVars may lack remaining
                merged = true
                break
            end
        end
        if not merged then
            q[#q + 1] = {
                recipeID   = payload.recipeID,
                itemID     = payload.itemID,
                requested  = qty,
                remaining  = qty,
                source     = payload.source,
                ts         = (_G.time and _G.time()) or 0,
                sessionKey = payload.sessionKey,   -- reviewer C8: cross-reload disambiguator
            }
        end

    elseif action.type == A.CRAFT_QUEUE_REMOVE then
        local q = self.state.account.craft.queue
        if payload.position and q[payload.position] then
            table.remove(q, payload.position)
        end

    elseif action.type == A.CRAFT_QUEUE_CLEAR then
        self.state.account.craft.queue = {}

    elseif action.type == A.CRAFT_QUEUE_DECREMENT then
        -- Match by (position, recipeID) -- reviewer C2/C4: position alone
        -- isn't unique across a queue mutation, recipeID alone isn't unique
        -- because the same item can come from multiple recipes.
        -- List-side steppers dispatch WITHOUT a position -- fall back to the first matching row.
        local q = self.state.account.craft.queue
        local pos = payload.position
        if not pos then
            for i, r in ipairs(q) do
                if r.recipeID == payload.recipeID then pos = i; break end
            end
        end
        local row = pos and q[pos]
        if row and row.recipeID == payload.recipeID then
            row.remaining = (row.remaining or 0) - (payload.qty or 1)  -- exception(boundary): queue row from SVars may lack remaining
            if row.remaining <= 0 then
                table.remove(q, pos)
            end
        end

    elseif action.type == A.CRAFT_HISTORY_PUSH then
        -- Reviewer C2: `completed` flag defends against phantom history
        -- entries when the matching DECREMENT was a no-op (post-removal
        -- events 5..N of a multi-craft batch).
        -- Field names: eventType + timestamp (HouseAggregator contract).
        if payload.completed or payload.eventType == "learned" then
            local hist = self.state.account.craft.history
            hist.nextID = hist.nextID + 1
            hist.entries[#hist.entries + 1] = {
                id        = hist.nextID,
                eventType = payload.eventType,
                recipeID  = payload.recipeID,
                itemID    = payload.itemID,
                qty       = payload.qty,
                timestamp = payload.timestamp or (_G.time and _G.time()) or 0,
            }
            local cap = HDG.Constants.CRAFT_HISTORY_CAP
            while #hist.entries > cap do
                table.remove(hist.entries, 1)
            end
            -- A learned decor changes the "Recently Learned" collection -> bump the
            -- styles cacheTick so its resolver + every cacheTick-bound selector (Styles
            -- tab + companion grid) refresh. Completed crafts don't affect it.
            if payload.eventType == "learned" then
                self.state.session.styles.cacheTick =
                    (self.state.session.styles.cacheTick or 0) + 1
            end
        end

    -- ===== Per-character roster (alts) ============================
    elseif action.type == A.CHARACTER_PROFESSION_UPDATED then
        -- Upsert the character entry, then replace this profession's data
        -- in full (skill ladder + known recipes). Other professions on the
        -- same char survive untouched -- each profession scan only carries
        -- its own data.
        local chars = self.state.account.characters
        local key   = payload.charKey
        if key then
            chars[key] = chars[key] or {
                name        = payload.name,
                realm       = payload.realm,
                class       = payload.class,
                classFile   = payload.classFile,
                hidden      = false,
                lastSeen    = 0,
                professions = {},
            }
            local c = chars[key]
            -- Refresh identity fields on each scan (rename, class change
            -- via faction change service, etc.).
            c.name      = payload.name      or c.name
            c.realm     = payload.realm     or c.realm
            c.class     = payload.class     or c.class
            c.classFile = payload.classFile or c.classFile
            c.lastSeen  = (_G.time and _G.time()) or c.lastSeen or 0
            -- Char-level knowsFindLumber: scanner captures via C_SpellBook
            -- on every prof scan. Tracks per-char awareness of Find Lumber
            -- (the achievement-gated find-spell), surfaced as a cyan
            -- indicator in the Alts char header.
            if payload.knowsFindLumber ~= nil then
                c.knowsFindLumber = payload.knowsFindLumber and true or false
            end
            if payload.profName then
                c.professions[payload.profName] = {
                    skillLines   = payload.skillLines,
                    knownRecipes = payload.knownRecipes,
                }
            end
        end

    elseif action.type == A.CHARACTER_DELETED then
        if payload.charKey then
            self.state.account.characters[payload.charKey] = nil
        end

    elseif action.type == A.CHARACTER_HIDDEN then
        local c = self.state.account.characters[payload.charKey]
        if c then c.hidden = payload.hidden and true or false end

    elseif action.type == A.CHARACTER_HIDDEN_TOGGLE then
        local c = self.state.account.characters[payload.charKey]
        if c then c.hidden = not (c.hidden == true) end

    elseif action.type == A.COMPANION_TOGGLE then
        self.state.session.ui.companion.windowShown =
            not self.state.session.ui.companion.windowShown

    elseif action.type == A.COMPANION_SET_MODE then
        local m = payload.mode
        if m then
            self.state.session.ui.companion.mode = m
            -- Clear selection when switching modes (different collection sets).
            self.state.session.ui.companion.selectedItemID = nil
        end

    elseif action.type == A.COMPANION_SELECT_ITEM then
        self.state.session.ui.companion.selectedItemID = payload.itemID

    elseif action.type == A.COMPANION_TOGGLE_COST then
        self.state.session.ui.companion.showCost =
            not self.state.session.ui.companion.showCost

    elseif action.type == A.COMPANION_CYCLE_IO then
        -- 3-state cycle: all -> indoor -> outdoor -> all.
        local cur = self.state.session.ui.companion.ioFilter
        self.state.session.ui.companion.ioFilter =
            (cur == "all" and "indoor") or (cur == "indoor" and "outdoor") or "all"

    elseif action.type == A.COMPANION_SET_POSITION then
        self.state.account.ui.companion.window.x = payload.x
        self.state.account.ui.companion.window.y = payload.y

    elseif action.type == A.COMPANION_SET_LAUNCHER_POSITION then
        self.state.account.ui.companion.launcher.x = payload.x
        self.state.account.ui.companion.launcher.y = payload.y

    -- ===== HouseTab dashboard =====
    elseif action.type == A.HOUSE_SNAPSHOT_UPDATED then
        self.state.session.house.snapshot     = payload.snapshot
        self.state.session.house.snapshotTick = self.state.session.house.snapshotTick + 1

    elseif action.type == A.HOUSE_LIST_UPDATED then
        -- Identity-only update: ensure an entry exists per houseGUID with
        -- identity fields populated; preserve any previously-captured
        -- level/favor/thresholds across re-fires of the list event
        -- (Blizzard re-fires 3-5 times on login). Faction is derived by
        -- the observer (HouseInfo struct doesn't carry it directly).
        local owned = self.state.session.house.ownedHouses
        for _, h in ipairs(payload.houses or {}) do
            local guid = h.houseGUID
            if guid then
                owned[guid] = owned[guid] or {}
                owned[guid].name             = h.neighborhoodName or owned[guid].name
                owned[guid].faction          = h.faction          or owned[guid].faction
                owned[guid].neighborhoodGUID = h.neighborhoodGUID or owned[guid].neighborhoodGUID
                owned[guid].houseName        = h.houseName        or owned[guid].houseName
                owned[guid].plotID           = h.plotID           or owned[guid].plotID
            end
        end

    elseif action.type == A.ACTIVE_NEIGHBORHOOD_UPDATED then
        -- nil-able: GetActiveNeighborhood returns nil when not in a
        -- neighborhood context. Selector falls back to first owned house.
        self.state.session.house.activeNeighborhoodGUID = payload.neighborhoodGUID

    elseif action.type == A.DAILY_BESTOWED_UPDATED then
        self.state.session.daily.bestowed = {
            name    = payload.name,
            quote   = payload.quote,
            dateKey = payload.dateKey,
        }

    elseif action.type == A.DAILY_ORC_QUOTE_SET then
        self.state.session.daily.orcQuote = payload.quote

    elseif action.type == A.STYLES_EDIT_STYLE then
        -- Deep-link into the Style Curator with this style as the source
        -- (HDG ShowEditor + SetSource parity). collectionID is already the
        -- "style:<uuid>" key the curator's sourceMode consumes; selection
        -- clears (selected itemIDs are meaningless across sources).
        self.state.session.ui.styles.view = "curator"
        self.state.session.ui.styles.curator.sourceMode = payload.collectionID
        self.state.session.ui.styles.curator.selectedItems = {}
        self.state.session.ui.styles.curator.selectedCount = 0
        -- Clear any stale move-target from a prior curator session, else the
        -- Move button would target the wrong style after a landing deep-link.
        self.state.session.ui.styles.curator.selectedTargetID = nil

    elseif action.type == A.HOUSE_LEVEL_UPDATED then
        -- Per-house favor update. Event fires for ALL owned houses on
        -- each request; we target by houseGUID. Ensure an entry exists
        -- (level event may arrive before list event in some replay paths).
        local owned = self.state.session.house.ownedHouses
        local guid  = payload.houseGUID
        if guid then
            owned[guid] = owned[guid] or {}
            owned[guid].level      = payload.level
            owned[guid].favor      = payload.favor
            owned[guid].maxLevel   = payload.maxLevel
            owned[guid].thresholds = payload.thresholds
        end

    elseif action.type == A.HOUSE_REWARDS_RECEIVED then
        -- Cache the per-level rewards array. RECEIVED_HOUSE_LEVEL_REWARDS
        -- fires once per GetHouseLevelRewardsForLevel(level) call; cache
        -- avoids re-requesting the same level repeatedly.
        local level   = payload.level
        local rewards = payload.rewards
        if type(level) == "number" and type(rewards) == "table" then
            self.state.session.house.rewardsByLevel[level] = { rewards = rewards }
        end

    elseif action.type == A.HOUSETAB_TOGGLE_WIDGET then
        local id = payload.widgetID
        local ht = self.state.account.ui.houseTab
        ht.enabled[id] = not (ht.enabled[id] == true) and true or nil

    elseif action.type == A.HOUSETAB_SET_ORDER then
        self.state.account.ui.houseTab.order[payload.widgetID] = payload.order

    elseif action.type == A.HOUSETAB_SET_ORDERS then
        self.state.account.ui.houseTab.order = payload.orders

    elseif action.type == A.HOUSETAB_REORDER_WIDGET then
        -- Remove srcID from the supplied ordered list, reinsert at insertIdx, renumber to
        -- contiguous order ints. This transition used to live in the controller's
        -- _computePickerOrders; it belongs here. The controller passes the current ordered ids
        -- (a legit one-shot selector read on drag-stop, not a render path).
        local ids, srcID, insertIdx = payload.orderedIDs, payload.srcID, payload.insertIdx
        if ids and srcID and insertIdx then
            local out = {}
            for _, id in ipairs(ids) do if id ~= srcID then out[#out + 1] = id end end
            if insertIdx < 1 then insertIdx = 1 end
            if insertIdx > #out + 1 then insertIdx = #out + 1 end
            table.insert(out, insertIdx, srcID)
            local order = {}
            for i, id in ipairs(out) do order[id] = i end
            self.state.account.ui.houseTab.order = order
        end

    elseif action.type == A.HOUSETAB_SET_WIDTH then
        self.state.account.ui.houseTab.width[payload.widgetID] = payload.width

    elseif action.type == A.HOUSETAB_RESIZE_WIDGET then
        local ht = self.state.account.ui.houseTab
        ht.layoutOverrides[payload.widgetID] = ht.layoutOverrides[payload.widgetID] or {}
        ht.layoutOverrides[payload.widgetID].height = payload.height

    elseif action.type == A.HOUSETAB_RESET_LAYOUT then
        local ht = self.state.account.ui.houseTab
        ht.enabled         = {}
        ht.order           = {}
        ht.width           = {}
        ht.layoutOverrides = {}

    elseif action.type == A.HOUSETAB_TOGGLE_PICKER then
        self.state.session.ui.houseTab.pickerOpen =
            not self.state.session.ui.houseTab.pickerOpen

    elseif action.type == A.HOUSETAB_TOGGLE_DESIGN_MODE then
        self.state.session.ui.houseTab.designMode =
            not self.state.session.ui.houseTab.designMode

    elseif action.type == A.SESSION_IDENTITY_SET then
        -- Strict payload reads: SessionIdentity:onEnable already coerces
        -- nil class/classFile to "" before dispatch (single producer; no
        -- defensive `or` defaults at this internal boundary).
        local id = self.state.session.identity
        id.name         = payload.name
        id.realm        = payload.realm
        id.class        = payload.class
        id.classFile    = payload.classFile
        id.factionGroup = payload.factionGroup or ""  -- exception(boundary): SESSION_IDENTITY_SET payload may omit factionGroup
        id.charKey      = id.name .. "-" .. id.realm

    elseif action.type == A.TRAINERS_TOGGLE_PROFESSION then
        local p = payload.profession
        if p then
            local expanded = self.state.session.ui.trainers.expandedProfessions
            expanded[p] = not (expanded[p] == true) and true or nil
        end

    elseif action.type == A.TRAINERS_TOGGLE_MIDNIGHT_SECTION then
        self.state.session.ui.trainers.midnightExpanded =
            not self.state.session.ui.trainers.midnightExpanded

    elseif action.type == A.TRAINERS_SELECT_TRAINER then
        self.state.session.ui.trainers.selectedNpcID = payload.npcID

    elseif action.type == A.ALTS_SET_CHARS_POPULATION then
        -- Validate -- silently coerce unknown values to "active".
        local p = payload.population
        if p ~= "active" and p ~= "hidden" then p = "active" end
        self.state.session.ui.alts.charsPopulation = p

    elseif action.type == A.MOGUL_SET_MODE then
        self.state.session.ui.mogul.mode = payload.mode
    elseif action.type == A.MOGUL_SET_VIEW then
        self.state.session.ui.mogul.viewMode = payload.viewMode
    elseif action.type == A.MOGUL_SET_OPTIMIZE_BY then
        self.state.session.ui.mogul.optimizeBy = payload.optimizeBy
    elseif action.type == A.MOGUL_SET_SUBVIEW then
        self.state.session.ui.mogul.subView = payload.subView
    elseif action.type == A.MOGUL_SET_SUPPLY_MODE then
        local si = self.state.session.ui.mogul.supplyImpact
        si.mode = payload.mode
    elseif action.type == A.MOGUL_SET_SUPPLY_SMOOTH then
        local si = self.state.session.ui.mogul.supplyImpact
        si.smoothPct = payload.pct
    elseif action.type == A.MOGUL_SET_SUPPLY_CAP then
        local si = self.state.session.ui.mogul.supplyImpact
        si.capN = payload.n
    elseif action.type == A.MOGUL_SET_FRUGAL then
        self.state.session.ui.mogul.frugal = payload.on == true
    elseif action.type == A.MOGUL_TOGGLE_FRUGAL then
        self.state.session.ui.mogul.frugal = not (self.state.session.ui.mogul.frugal == true)
    elseif action.type == A.GOBLIN_SET_PROFESSION then
        self.state.session.ui.mogul.goblin.profession = payload.profession
    elseif action.type == A.GOBLIN_SET_SEARCH then
        self.state.session.ui.mogul.goblin.search    = payload.query
    elseif action.type == A.GOBLIN_SET_KNOWLEDGE then
        self.state.session.ui.mogul.goblin.knowledge = payload.mode
    elseif action.type == A.GOBLIN_SET_QUEUE then
        self.state.session.ui.mogul.goblin.queue     = payload.mode
    elseif action.type == A.GOBLIN_TOGGLE_AUCTIONS then
        local g = self.state.session.ui.mogul.goblin
        g.auctionsOnly = not (g.auctionsOnly == true)
    elseif action.type == A.PRICES_SET_PREFERRED_SOURCE then
        -- Config write + price tick in one pass (two dispatches would cost two reducer runs).
        self.state.account.config.preferredPriceAddon = payload.source
        self.state.session.prices.tick =
            self.state.session.prices.tick + 1

    elseif action.type == A.PRICES_SET_TSM_MODE then
        self.state.account.config.tsmPriceMode = payload.mode
        self.state.session.prices.tick =
            self.state.session.prices.tick + 1

    elseif action.type == A.GOBLIN_TOGGLE_ROW_EXPAND then
        -- Click row: toggle expansion. Same itemID as currently expanded
        -- collapses; different/new itemID switches the detail panel to it.
        local g = self.state.session.ui.mogul.goblin
        if g.expandedItemID == payload.itemID then
            g.expandedItemID = nil
        else
            g.expandedItemID = payload.itemID
        end

    elseif action.type == A.GOBLIN_SET_SORT then
        -- Click on header: same column flips direction, new column resets
        -- to the column's natural-desc default (most useful first sort).
        -- Name column defaults to ascending (alphabetical reads better).
        local g = self.state.session.ui.mogul.goblin
        local col = payload.col
        if g.sortCol == col then
            g.sortDir = (g.sortDir == "desc") and "asc" or "desc"
        else
            g.sortCol = col
            g.sortDir = (col == "name" or col == "lumber") and "asc" or "desc"
        end

    -- ===== Recipes tab session UI ================================
    elseif action.type == A.RECIPES_SET_SEARCH then
        self.state.session.ui.recipes.searchQuery = payload.query

    elseif action.type == A.RECIPES_SET_SECTION_EXPAND then
        local sections = self.state.session.ui.recipes.expandedSections
        if payload.expanded then
            sections[payload.key] = true
        else
            sections[payload.key] = nil
        end

    elseif action.type == A.RECIPES_SET_MATERIALS_DEPTH then
        self.state.session.ui.recipes.materialsDepth = payload.value

    elseif action.type == A.RECIPES_TOGGLE_MATERIALS_GROUPING then
        local r = self.state.session.ui.recipes
        r.materialsGrouping = (r.materialsGrouping == "byRecipe") and "totals" or "byRecipe"

    elseif action.type == A.RECIPES_TOGGLE_FILTER then
        local filters = self.state.session.ui.recipes.filters
        local key = payload.filter
        filters[key] = not filters[key]

    elseif action.type == A.RECIPES_SELECT_RECIPE then
        self.state.session.ui.recipes.selectedRecipeID = payload.recipeID
        -- Picking a recipe from the list resets queue scoping: the queue row
        -- deselects + Materials returns to the full-queue aggregate. (Last
        -- selection wins; recipe-list and queue selections are mutually exclusive.)
        self.state.session.ui.recipes.queueSelectedRecipeID = nil

    elseif action.type == A.RECIPES_TOGGLE_QUEUE_SELECTION then
        -- Toggle: click-on-selected clears (so mats list returns to the
        -- full-queue aggregate); click-on-other sets to that recipeID.
        local cur = self.state.session.ui.recipes.queueSelectedRecipeID
        if cur == payload.recipeID then
            self.state.session.ui.recipes.queueSelectedRecipeID = nil
        else
            self.state.session.ui.recipes.queueSelectedRecipeID = payload.recipeID
        end

    elseif action.type == A.RECIPES_TOGGLE_PROFESSION then
        -- Per-character multi-select set toggle (persisted in account.ui, keyed by
        -- charKey). payload.profession == "all" stores an empty set (-> show every
        -- profession); == "mine" presets to THIS character's scanned professions;
        -- otherwise flip that profession's membership.
        local charKey = self.state.session.identity.charKey
        local byChar  = self.state.account.ui.recipes.professionFilterByChar
        local char    = self.state.account.characters[charKey]  -- exception(nullable): char record may not exist yet
        local set     = byChar[charKey]
        if not set then
            -- First explicit choice for this char. Materialize the pristine default
            -- (this char's professions) so a single-profession toggle builds on what
            -- was actually shown -- UNLESS the click is "all" (which wants empty).
            set = {}
            if payload.profession ~= "all" and char and type(char.professions) == "table" then
                for profName in pairs(char.professions) do set[profName] = true end
            end
            byChar[charKey] = set
        end
        if payload.profession == "all" then
            for k in pairs(set) do set[k] = nil end
        elseif payload.profession == "mine" then
            for k in pairs(set) do set[k] = nil end
            if char and type(char.professions) == "table" then
                for profName in pairs(char.professions) do set[profName] = true end
            end
        else
            set[payload.profession] = not (set[payload.profession] == true) and true or nil
        end

    elseif action.type == A.RECIPES_TOGGLE_EXPANSION then
        -- Multi-select set toggle (persisted in account.ui). payload.expansion
        -- == "all" clears the set (master "All Expansions" toggle -> show every
        -- expansion); otherwise flip that expansion's membership. Empty = all.
        local set = self.state.account.ui.recipes.expansionFilter
        if payload.expansion == "all" then
            for k in pairs(set) do set[k] = nil end
        else
            set[payload.expansion] = not (set[payload.expansion] == true) and true or nil
        end

    elseif action.type == A.RECIPES_SET_LIST_FILTER then
        self.state.session.ui.recipes.listFilter = payload.filter

    elseif action.type == A.RECIPES_SELECT_MATERIAL then
        self.state.session.ui.warehouse.selectedMaterialID = payload.itemID

    elseif action.type == A.RECIPES_SET_WH_MAT_SEARCH then
        self.state.session.ui.warehouse.matSearch = payload.query

    -- ===== Cross-feature observer dispatches =====================
    elseif action.type == A.ITEM_INFO_RESOLVED then
        -- Write resolved names to cache + bump tick once (per batch, not per entry).
        local names = self.state.session.itemNames.names
        if payload.entries then
            for _, e in ipairs(payload.entries) do
                if e.itemID and e.name then names[e.itemID] = e.name end
            end
        end
        self.state.session.itemNames.tick = self.state.session.itemNames.tick + 1

    elseif action.type == A.QUEST_INFO_RESOLVED then
        -- Tick bump; selectors showing quest gate names read session.questNames.tick.
        self.state.session.questNames.tick =
            self.state.session.questNames.tick + 1

    elseif action.type == A.QUEST_STATUS_RESOLVED then
        -- Tick bump; [QUST] completion checkmark repaints on the open detail panel.
        self.state.session.questStatus.tick =
            self.state.session.questStatus.tick + 1

    elseif action.type == A.QUEST_COMPLETION_RECORDED then
        -- Merge the scanned completions into the account-wide set. First char to
        -- record a quest wins (stable attribution) -- don't overwrite. payload
        -- entries are { [questID] = { name, class } }.
        local store = self.state.account.questCompletions
        for questID, rec in pairs(payload.completions or {}) do
            if not store[questID] then store[questID] = rec end
        end

    elseif action.type == A.ACHIEVEMENT_STATUS_RESOLVED then
        -- Tick bump; [ACH] earned checkmark repaints on the open detail panel.
        self.state.session.achievementStatus.tick =
            self.state.session.achievementStatus.tick + 1

    elseif action.type == A.BAG_INVENTORY_UPDATED then
        -- Tick for memo invalidation; actual counts in BagObserver._counts (ADR-003a carve-out).
        self.state.session.bag.tick = payload.tick or (self.state.session.bag.tick + 1)

    -- ===== PriceSource ===========================================
    elseif action.type == A.PRICES_CONFIG_CHANGED then
        -- Pure tick bump; actual config write happens via CONFIG_SET.
        self.state.session.prices.tick =
            self.state.session.prices.tick + 1

    elseif action.type == A.PRICES_DIRECT_SCAN_STARTED then
        -- Replace-on-scan: wipe the previous cache so each scan is a fresh snapshot.
        self.state.account.prices.directCache = {}
        self.state.account.prices.directQtyCache = {}
        self.state.account.prices.directCacheTime = nil
        local s = self.state.session.prices
        s.scanning  = true
        s.scanFound = 0
        s.scanTotal = payload.total
        s.tick = s.tick + 1

    elseif action.type == A.PRICES_DIRECT_SCAN_PROGRESS then
        local s = self.state.session.prices
        s.scanFound = payload.found or s.scanFound
        s.scanTotal = payload.total or s.scanTotal

    elseif action.type == A.PRICES_DIRECT_SCAN_BATCH then
        local cache = self.state.account.prices.directCache
        for itemID, copper in pairs(payload.prices) do
            cache[itemID] = copper
        end
        local qty = self.state.account.prices.directQtyCache
        for itemID, n in pairs(payload.quantities or {}) do
            qty[itemID] = n
        end
        self.state.session.prices.tick =
            self.state.session.prices.tick + 1

    elseif action.type == A.PRICES_DIRECT_SCAN_COMPLETED then
        local cache = self.state.account.prices.directCache
        local qty   = self.state.account.prices.directQtyCache
        -- Zero out items we wanted but never saw -- prevents re-scan
        -- attempts every session for items that simply aren't on the AH.
        for itemID in pairs(payload.neededItems) do
            if cache[itemID] == nil then cache[itemID] = 0 end
            if qty[itemID]   == nil then qty[itemID]   = 0 end
        end
        self.state.account.prices.directCacheTime = payload.now
        local s = self.state.session.prices
        s.scanning = false
        s.scanFound = 0
        s.scanTotal = 0
        s.tick = s.tick + 1

    elseif action.type == A.PRICES_DIRECT_CACHE_CLEARED then
        self.state.account.prices.directCache     = {}
        self.state.account.prices.directQtyCache  = {}
        self.state.account.prices.directCacheTime = nil
        self.state.session.prices.tick =
            self.state.session.prices.tick + 1

    elseif action.type == A.PRICES_OWNED_AUCTIONS_UPDATED then
        self.state.account.prices.ownedAuctions = payload.auctions
        self.state.session.prices.tick =
            self.state.session.prices.tick + 1

    elseif action.type == A.PRICES_ADDONS_AVAILABILITY_CHANGED then
        local s = self.state.session.prices
        s.tsmLoaded         = payload.tsm         == true
        s.auctionatorLoaded = payload.auctionator == true
        s.tick = s.tick + 1

    -- ===== Styles ==================================================
    elseif action.type == A.STYLES_SET_VIEW then
        self.state.session.ui.styles.view = payload.view
        -- The "Smart Sets" nav leaf opens this view without running BEGIN, so
        -- seed a fresh draft's default name here. Only when truly fresh (no
        -- draftKey, blank name, no rules) so navigating away + back preserves an
        -- in-progress draft; the button path (BEGIN) owns the explicit reset.
        if payload.view == "smartset" then
            local s = self.state.session.ui.styles.smartset
            local blankName = (s.draft.displayName == nil or s.draft.displayName == "")
            if not s.draftKey and blankName and not next(s.rules) then
                s.draft.displayName = _seededSmartsetName(self.state.account)
                s.draft.descAuto    = true
            end
        end

    elseif action.type == A.STYLES_LANDING_SET_FILTER then
        self.state.session.ui.styles.landing.filter = payload.filter

    elseif action.type == A.STYLES_LANDING_SET_SEARCH then
        self.state.session.ui.styles.landing.search = payload.text

    elseif action.type == A.STYLES_LANDING_TOGGLE_SECTION then
        local t = payload.type
        if t then
            local expanded = self.state.session.ui.styles.landing.expandedSections
            expanded[t] = not (expanded[t] == true) and true or nil
        end

    elseif action.type == A.STYLES_SELECT_COLLECTION then
        self.state.session.ui.styles.selectedID = payload.collectionID

    elseif action.type == A.STYLES_DETAIL_SELECT_ITEM then
        self.state.session.ui.styles.detail.selectedItemID = payload.itemID

    elseif action.type == A.STYLES_DETAIL_SET_VIEWMODE then
        self.state.session.ui.styles.detail.viewMode = payload.mode

    elseif action.type == A.STYLES_DETAIL_SET_FILTER then
        self.state.session.ui.styles.detail.sourceFilter = payload.source

    elseif action.type == A.STYLES_DETAIL_SET_SUBCAT then
        self.state.session.ui.styles.detail.subcatFilter = payload.subcat

    elseif action.type == A.STYLES_INVALIDATE_STYLE then
        -- Bump global cacheTick; per-collection invalidation can layer later
        -- when the engine port surfaces per-collection cache slots.
        self.state.session.styles.cacheTick = self.state.session.styles.cacheTick + 1

    elseif action.type == A.STYLES_CACHE_BUILDING_STARTED then
        -- Notification-only (retained for closed-taxonomy check).

    elseif action.type == A.STYLES_CACHE_BUILDING_FINISHED then
        -- Notification-only (retained for closed-taxonomy check).

    elseif action.type == A.STYLES_DETAIL_SET_SEARCH then
        self.state.session.ui.styles.detail.search = payload.text

    -- ===== 14.3 Curator =====================================================
    elseif action.type == A.STYLES_CURATOR_SET_SOURCE then
        self.state.session.ui.styles.curator.sourceMode = payload.mode
        -- Selection clears when the source changes (selected itemIDs are
        -- meaningless in a different source view).
        self.state.session.ui.styles.curator.selectedItems = {}
        self.state.session.ui.styles.curator.selectedCount = 0

    elseif action.type == A.STYLES_CURATOR_SET_CATEGORY then
        -- nil categoryID = the "All" icon (clears the filter). Subcategory always
        -- resets when the major category changes -- its list is derived from the
        -- focused category, so a carried-over value would point at a gone subcat.
        self.state.session.ui.styles.curator.focusedCategoryID    = payload.categoryID
        self.state.session.ui.styles.curator.focusedSubcategoryID = nil

    elseif action.type == A.STYLES_CURATOR_SET_SUBCATEGORY then
        self.state.session.ui.styles.curator.focusedSubcategoryID = payload.subcategoryID

    elseif action.type == A.STYLES_CURATOR_TOGGLE_SELECT then
        local id = payload.itemID
        if id then
            local cur = self.state.session.ui.styles.curator
            if cur.selectedItems[id] then
                cur.selectedItems[id] = nil
                cur.selectedCount = (cur.selectedCount or 1) - 1
            else
                cur.selectedItems[id] = true
                cur.selectedCount = (cur.selectedCount or 0) + 1
            end
        end

    elseif action.type == A.STYLES_CURATOR_CLEAR_SELECT then
        self.state.session.ui.styles.curator.selectedItems = {}
        self.state.session.ui.styles.curator.selectedCount = 0

    elseif action.type == A.STYLES_CURATOR_HOVER then
        self.state.session.ui.styles.curator.hoverItemID = payload.itemID

    elseif action.type == A.STYLES_CURATOR_SELECT_TARGET then
        self.state.session.ui.styles.curator.selectedTargetID = payload.targetID

    elseif action.type == A.STYLES_CREATE_STYLE then
        -- Create a fresh "style:<slug>" collection in account.collections
        -- and auto-select it as the Curator's active target so the user's
        -- next Move lands there without an extra click.
        local name = payload.displayName
        if not (name and name ~= "" and name:gsub("%s", "") ~= "") then return end
        local slug = name:lower():gsub("[^%w]+", "-")
        if slug == "" or slug == "-" then slug = tostring(_G.time and _G.time() or 0) end
        local id = "style:" .. slug
        -- Disambiguate if a style with this slug already exists.
        local cols = self.state.account.collections or {}
        if cols[id] then
            local suffix = 2
            while cols[id .. "-" .. suffix] do suffix = suffix + 1 end
            id = id .. "-" .. suffix
        end
        self.state.account.collections = cols
        cols[id] = {
            id          = id,
            type        = "style",
            displayName = name,
            description = "",
            items       = {},
            createdAt   = (_G.time and _G.time()) or 0,
        }
        self.state.session.ui.styles.curator.selectedTargetID = id

    elseif action.type == A.STYLES_RENAME_STYLE then
        -- Rename the displayName of a "style:<slug>" collection. ID stays
        -- the same so undo history + memberships keep their links.
        local id   = payload.collectionID
        local name = payload.displayName
        if not (id and name and name ~= "" and name:gsub("%s", "") ~= "") then return end
        local coll = self.state.account.collections and self.state.account.collections[id]
        if coll and coll.type == "style" then
            coll.displayName = name
        end

    elseif action.type == A.STYLES_DUPLICATE_STYLE then
        -- Clone a "style:<slug>" collection. New id is "<src>-copy" with a
        -- numeric suffix if "-copy" is already taken. items[] copied by value.
        local srcID = payload.collectionID
        local cols  = self.state.account.collections or {}
        local src   = cols[srcID]
        if not (src and src.type == "style") then return end
        local baseID = srcID .. "-copy"
        local newID  = baseID
        local suffix = 2
        while cols[newID] do
            newID = baseID .. "-" .. suffix
            suffix = suffix + 1
        end
        local items = {}
        for i, v in ipairs(src.items or {}) do items[i] = v end
        cols[newID] = {
            id          = newID,
            type        = "style",
            displayName = (src.displayName or srcID) .. " (copy)",
            description = src.description or "",
            items       = items,
            createdAt   = (_G.time and _G.time()) or 0,
        }
        self.state.account.collections = cols
        self.state.session.ui.styles.curator.selectedTargetID = newID

    elseif action.type == A.STYLES_DELETE_STYLE then
        -- Delete any user-authored collection -- style / smartset / snapshot
        -- live in account.collections; SHOPPING LISTS live in the separate
        -- account.vendorShoppingLists slot, keyed WITHOUT the "vsl:" prefix the
        -- landing card carries. Route by prefix so shopping-list deletes hit the
        -- right slot (the old account.collections-only path silently no-op'd them
        -- -- cols["vsl:L1"] is always nil). Pre-authored concept/collection sets
        -- aren't deletable (canDelete=false), so they never reach here. Clears
        -- selectedTargetID if this was the active target so the controls row hides.
        local id  = payload.collectionID
        local cur = self.state.session.ui.styles.curator
        local vslID = type(id) == "string" and id:match("^vsl:(.+)$")
        if vslID then
            local lists = self.state.account.vendorShoppingLists
            if not (lists and lists[vslID]) then return end   -- exception(boundary): missing list
            lists[vslID] = nil
        else
            local cols = self.state.account.collections
            if not (id and cols and cols[id]) then return end   -- exception(boundary): missing id / pre-first-save
            cols[id] = nil
        end
        if cur and cur.selectedTargetID == id then
            cur.selectedTargetID = nil
        end

    elseif action.type == A.STYLES_CURATOR_MOVE then
        -- Move every currently-selected item from the active source to
        -- the named target collection. payload.targetID overrides the
        -- session-selected target so legacy callers (click-target-to-move)
        -- still work; spec-aligned callers (explicit Move button) just
        -- read selectedTargetID. Source-tracking + undo recording happens
        -- here so the undo case can fully reverse without requiring the
        -- controller to thread payload data through.
        local cur = self.state.session.ui.styles.curator
        local targetID = payload.targetID or cur.selectedTargetID
        local sourceMode = cur.sourceMode
        local target = targetID and self.state.account.collections[targetID]
        if not target then return end
        target.items = target.items or {}

        -- Source collection (when sourceMode is "style:<id>"); nil for
        -- "unassigned" or "all" -- those modes only ADD to the target.
        local sourceID, sourceColl
        if type(sourceMode) == "string" and sourceMode:sub(1, 6) == "style:" then
            sourceID = sourceMode
            sourceColl = self.state.account.collections[sourceID]
        end

        local movedIDs = {}
        for itemID in pairs(cur.selectedItems) do
            -- Add to target (dedupe).
            local exists = false
            for _, id in ipairs(target.items) do
                if id == itemID then exists = true; break end
            end
            if not exists then
                target.items[#target.items + 1] = itemID
            end
            -- Remove from source if any.
            if sourceColl and sourceColl.items then
                for i, id in ipairs(sourceColl.items) do
                    if id == itemID then
                        table.remove(sourceColl.items, i)
                        break
                    end
                end
            end
            movedIDs[#movedIDs + 1] = itemID
        end
        -- Record an undo entry (capped to 20; older entries silently drop).
        local undo = cur.recentUndo
        undo[#undo + 1] = {
            action   = "move",
            from     = sourceID,    -- may be nil (Unassigned / All source)
            to       = targetID,
            items    = movedIDs,
            ts       = (_G.time and _G.time()) or 0,
        }
        while #undo > 20 do table.remove(undo, 1) end
        -- Clear selection after a successful move.
        cur.selectedItems = {}
        cur.selectedCount = 0

    elseif action.type == A.STYLES_CURATOR_UNDO
        or action.type == A.STYLES_CURATOR_UNDO_AT then
        -- Reverse a single move from the stack.
        -- UNDO     -> pops the topmost entry ("Undo last move" button).
        -- UNDO_AT  -> pops the entry at payload.ord (per-row click in the
        --             RECENT (UNDO) panel).
        -- "from" may be nil (Unassigned source) -- in which case removal
        -- from target is sufficient to put items back in the unassigned set.
        -- Note: undoing an old entry while newer entries above it remain
        -- can leave the moved items in multiple style memberships if the
        -- items were re-moved by those newer entries. That's intentionally
        -- self-recoverable -- the user can resolve via another targeted
        -- undo. The alternative (cascade-undo to clicked row) was felt
        -- to lose user intent ("I clicked ONE row, why did 4 actions undo?").
        local cur = self.state.session.ui.styles.curator
        local collections = self.state.account.collections
        local ord
        if action.type == A.STYLES_CURATOR_UNDO_AT then
            ord = payload and payload.ord
            if type(ord) ~= "number" then return end
        else
            ord = #cur.recentUndo
        end
        if ord < 1 or ord > #cur.recentUndo then return end

        local entry = cur.recentUndo[ord]
        table.remove(cur.recentUndo, ord)
        local target = entry.to and collections[entry.to]
        local source = entry.from and collections[entry.from]
        if target and target.items then
            for _, itemID in ipairs(entry.items or {}) do
                for i, id in ipairs(target.items) do
                    if id == itemID then
                        table.remove(target.items, i)
                        break
                    end
                end
            end
        end
        if source then
            source.items = source.items or {}
            for _, itemID in ipairs(entry.items or {}) do
                local exists = false
                for _, id in ipairs(source.items) do
                    if id == itemID then exists = true; break end
                end
                if not exists then source.items[#source.items + 1] = itemID end
            end
        end

    -- ===== 14.4 Smart Set Builder ===========================================
    elseif action.type == A.STYLES_SMARTSET_BEGIN then
        -- Seed draft from existing collection (when editing) or from scratch.
        -- The view-switch to "smartset" is dispatched separately by the
        -- entry-point CTA / Detail "Edit" button.
        local s = self.state.session.ui.styles.smartset
        local existingID = payload.id
        local existing = existingID and self.state.account.collections
                         and self.state.account.collections[existingID]
        if existing then
            s.draftKey = existingID
            s.draft = {
                id          = existing.id or existingID,
                displayName = existing.displayName or "",
                description = existing.description or "",
                type        = existing.type or "smartset",
                descAuto    = false,   -- editing: preserve the saved description
            }
            -- Deep-copy rules so edits don't mutate the persisted record
            -- until SAVE commits them.
            s.rules = {}
            for axis, tags in pairs(existing.rules or {}) do
                s.rules[axis] = {}
                for tag, sev in pairs(tags) do s.rules[axis][tag] = sev end
            end
        else
            -- New draft: seed "<Char> Style <N>" + descAuto (the description
            -- tracks the signature tags until the player types their own).
            s.draftKey       = nil
            s.draft          = { id = nil, displayName = _seededSmartsetName(self.state.account),
                                 description = "", type = "smartset", descAuto = true }
            s.rules          = {}
        end
        s.activeAxis     = "room"
        s.activeSeverity = "all"
        s.dirty          = false

    elseif action.type == A.STYLES_SMARTSET_SET_FIELD then
        local s = self.state.session.ui.styles.smartset
        if payload.field then
            s.draft[payload.field] = payload.value
            -- User typed in the description -> stop auto-tracking the signature tags.
            if payload.field == "description" then s.draft.descAuto = false end
            s.dirty = true
        end

    elseif action.type == A.STYLES_SMARTSET_SET_AXIS then
        self.state.session.ui.styles.smartset.activeAxis = payload.axis

    elseif action.type == A.STYLES_SMARTSET_SET_SEVERITY_TAB then
        self.state.session.ui.styles.smartset.activeSeverity = payload.sev

    elseif action.type == A.STYLES_SMARTSET_TOGGLE_TAG then
        -- Toggle a tag's severity within an axis. payload.severity nil =
        -- remove the tag (untoggle); else set to that severity (overwrite
        -- if already present at a different severity).
        local s = self.state.session.ui.styles.smartset
        local axis, tag, sev = payload.axis, payload.tag, payload.severity
        if axis and tag then
            s.rules[axis] = s.rules[axis] or {}
            if sev == nil or s.rules[axis][tag] == sev then
                s.rules[axis][tag] = nil
                -- Drop empty axis tables for tidiness (saves serialization size).
                local hasAny = false
                for _ in pairs(s.rules[axis]) do hasAny = true; break end
                if not hasAny then s.rules[axis] = nil end
            else
                s.rules[axis][tag] = sev
            end
            if s.draft.descAuto then s.draft.description = _buildSmartsetAutoDesc(s.rules) end
            s.dirty = true
        end

    elseif action.type == A.STYLES_SMARTSET_CLEAR_ALL then
        local s = self.state.session.ui.styles.smartset
        s.rules = {}
        s.draft.description = ""   -- auto-desc now tracks the (empty) signature set
        s.draft.descAuto    = true
        s.dirty = true

    elseif action.type == A.STYLES_SMARTSET_SAVE then
        -- Commit the draft to account.collections. New drafts get a fresh
        -- "smartset:<sluggedName>" id; edits write through the existing
        -- draftKey. Caller is responsible for view-switching back to
        -- landing post-save (typically via the footer's onClick chain).
        local s = self.state.session.ui.styles.smartset
        if s.dirty or not s.draftKey then
            local id = s.draftKey
            if not id then
                -- Monotonic, collision-free id (feedback_no_random_ids_use_counters);
                -- shares the counter with the "<Char> Style <N>" name seed.
                self.state.account.collectionSeq = (self.state.account.collectionSeq or 0) + 1  -- exception(boundary): pre-counter saved accounts lack collectionSeq
                id = "smartset:" .. self.state.account.collectionSeq
            end
            self.state.account.collections = self.state.account.collections or {}
            self.state.account.collections[id] = {
                id          = id,
                type        = "smartset",
                displayName = s.draft.displayName or "Untitled",
                description = s.draft.description or "",
                rules       = {},
            }
            for axis, tags in pairs(s.rules or {}) do
                self.state.account.collections[id].rules[axis] = {}
                for tag, sev in pairs(tags) do
                    self.state.account.collections[id].rules[axis][tag] = sev
                end
            end
            s.draftKey = id
            s.dirty    = false
        end

    elseif action.type == A.STYLES_SMARTSET_CANCEL then
        -- Discard the draft. The view switch back to landing fires
        -- separately so callers can also choose to return to a different
        -- view (e.g. Detail when editing an existing smartset).
        local s = self.state.session.ui.styles.smartset
        s.draftKey       = nil
        s.draft          = { id = nil, displayName = "", description = "", type = "smartset", descAuto = true }
        s.rules          = {}
        s.activeAxis     = "room"
        s.activeSeverity = "all"
        s.dirty          = false

    -- ===== 14.5 Snapshot + Import =========================================
    elseif action.type == A.STYLES_PLACED_DECOR_OBSERVED then
        local guid = payload.decorGUID
        if guid then
            local now = time()
            local map = self.state.session.styles.placedDecor
            local existing = map[guid]
            map[guid] = {
                decorGUID = guid,
                decorID   = payload.decorID,
                itemID    = payload.itemID,
                name      = payload.name,
                -- placedAt: preserve original on edit re-observe; stamp on first sighting
                placedAt  = (existing and existing.placedAt) or now,
            }
        end

    elseif action.type == A.STYLES_PLACED_DECOR_OBSERVED_BATCH then
        -- Bulk variant used by HousingObserver to coalesce the
        -- HOUSING_DECOR_CUSTOMIZATION_CHANGED burst on edit-mode entry
        -- (~N events in one frame). One reducer pass writes all entries,
        -- one invalidation, one subscriber fan-out -- vs N dispatches in
        -- the unbatched path.
        --
        -- Bulk fills (edit-mode entry) re-enumerate already-placed decor;
        -- they shouldn't reset placedAt (these aren't "new" placements).
        -- The dispatcher sets payload.bulkFill=true so we preserve existing
        -- placedAt timestamps; only assign a fresh placedAt for GUIDs we
        -- haven't seen before this session.
        local now = time()
        local map = self.state.session.styles.placedDecor
        for _, e in ipairs(payload.entries) do
            local guid = e.decorGUID
            if guid then
                local existing = map[guid]
                map[guid] = {
                    decorGUID = guid,
                    decorID   = e.decorID,
                    itemID    = e.itemID,
                    name      = e.name,
                    placedAt  = (existing and existing.placedAt) or now,
                }
            end
        end

    elseif action.type == A.STYLES_PLACED_DECOR_REMOVED then
        local guid = payload.decorGUID
        if guid then
            -- Record the removal in RecentActivity. itemID comes from the live
            -- placedDecor entry when present (decor placed/edited this session), else
            -- from payload.itemID (parsed from the GUID in the observer) so removing
            -- PRE-EXISTING decor still counts. Attributed to the active house.
            local entry  = self.state.session.styles.placedDecor[guid]
            local itemID = (entry and entry.itemID) or payload.itemID
            if itemID then
                _recentAppend(self.state, self.state.account.recentActivity.lastHouseKey,
                              itemID, "removed")
            end
            self.state.session.styles.placedDecor[guid] = nil
        end

    elseif action.type == A.STYLES_PLACED_DECOR_CLEAR then
        self.state.session.styles.placedDecor = {}

    elseif action.type == A.RECENT_SESSION_START then
        -- Seal the active (newest, unsealed) session, open a fresh one. Keyed
        -- by the stable faction house id. Caps history at RECENT_SESSION_CAP.
        -- An active session that recorded NO events is reused (so opening/
        -- closing the editor without placing anything doesn't spam empty
        -- "Now (0)" sessions).
        local key = payload.houseKey
        if key then
            local ra = self.state.account.recentActivity
            ra.lastHouseKey = key
            local house = ra.houses[key]
            if not house then house = { sessionOrder = {}, sessions = {} }; ra.houses[key] = house end
            local newestID = house.sessionOrder[1]
            local newest   = newestID and house.sessions[newestID]
            local reuseEmpty = newest and not newest.endedAt and (newest.eventCount or 0) == 0
            if not reuseEmpty then
                if newest and not newest.endedAt then newest.endedAt = time() end
                local sid = time()
                if house.sessions[sid] then sid = sid + 1 end
                house.sessions[sid] = { sessionID = sid, startedAt = sid, endedAt = nil,
                                        eventCount = 0, events = {}, actions = {} }
                table.insert(house.sessionOrder, 1, sid)
                while #house.sessionOrder > RECENT_SESSION_CAP do
                    local dropID = table.remove(house.sessionOrder)
                    house.sessions[dropID] = nil
                end
            end
        end

    elseif action.type == A.RECENT_DECOR_PLACED then
        _recentAppend(self.state, payload.houseKey, payload.itemID, "placed")

    elseif action.type == A.STYLES_SNAPSHOT_PLACED then
        -- Account-wide snapshot of everything the player has placed. The controller
        -- scans the catalog (numPlaced>0) and passes distinct itemIDs in payload.items
        -- (reducer stays pure -- no observer call here). This is the only taint-safe
        -- full placed-decor list; a per-house split is impossible (GetAllPlacedDecor
        -- taints, editor-frame hooks taint) -- see docs/HDGR_HOUSE_SNAPSHOTS.md.
        -- takenAt + displayName stamped at the dispatch site (date()/time() boundary).
        local items = payload.items or {}  -- exception(boundary): placed-decor list stamped at dispatch site
        if #items == 0 then return end
        local ts = payload.takenAt or 0  -- exception(boundary): takenAt stamped at dispatch site (time() boundary)
        -- Monotonic id (NOT the timestamp) so two snapshots in the same second can't
        -- collide-overwrite; same counter as smartset ids. takenAt stays for display.
        self.state.account.collectionSeq = (self.state.account.collectionSeq or 0) + 1  -- exception(boundary): pre-counter saved accounts lack collectionSeq
        local id = "snapshot:" .. self.state.account.collectionSeq
        self.state.account.collections = self.state.account.collections or {}
        self.state.account.collections[id] = {
            id          = id,
            type        = "snapshot",
            displayName = payload.displayName or ("Snapshot " .. tostring(ts)),
            description = "",
            items       = items,
            takenAt     = ts,
            iconAtlas   = HDG.Constants.SNAPSHOT_ICON_ATLAS,  -- decorate-mode house glyph
        }

    elseif action.type == A.STYLES_IMPORT_SET_URL then
        self.state.session.ui.styles.import.urlText = payload.text
        -- Clear stale preview / error / parser hints on text change so the
        -- user sees a fresh state when they re-Parse.
        self.state.session.ui.styles.import.previewItems      = nil
        self.state.session.ui.styles.import.parseError        = nil
        self.state.session.ui.styles.import.parseSource       = nil
        self.state.session.ui.styles.import.parseDisplayName  = nil

    elseif action.type == A.STYLES_IMPORT_PARSE then
        -- Delegate to HDG.Parsers (Modules/HDGR_Parsers.lua). Walks the
        -- parser registry; first parser to recognize the pasted text wins.
        -- Supports: style blobs (HDG:1:), shopping list blobs (HDGVL:1:),
        -- Blizzard |Hitem chat links, URL ?items=NNN query params (wowhead
        -- / housing.wowdb.com / generic), and a fallback digit-run parser
        -- for raw CSVs.
        local text   = self.state.session.ui.styles.import.urlText or ""
        local result = HDG.Parsers and HDG.Parsers:Parse(text)  -- exception(boundary): optional module / not yet built
                       or { ok = false, error = "Parsers unavailable" }
        if result.ok then
            self.state.session.ui.styles.import.previewItems = result.items
            self.state.session.ui.styles.import.parseError   = nil
            -- Stash hints so the commit step can pick up a parser-suggested
            -- name + source URL.
            self.state.session.ui.styles.import.parseSource     = result.source
            self.state.session.ui.styles.import.parseDisplayName = result.displayName
        else
            self.state.session.ui.styles.import.previewItems = nil
            self.state.session.ui.styles.import.parseError   = result.error or "Parse failed"
        end

    elseif action.type == A.STYLES_IMPORT_COMMIT then
        local preview = self.state.session.ui.styles.import.previewItems
        if not (preview and #preview > 0) then return end
        local ts = (_G.time and _G.time()) or 0
        local id = "shopping:" .. tostring(ts)
        local sessionImport = self.state.session.ui.styles.import
        -- Precedence: explicit payload override > parser-suggested name >
        -- timestamp default.
        local name = payload.displayName
                     or sessionImport.parseDisplayName
                     or ("Shopping List " .. tostring(ts))
        self.state.account.collections = self.state.account.collections or {}
        self.state.account.collections[id] = {
            id          = id,
            type        = "shopping",
            displayName = name,
            description = "",
            items       = preview,
            importedAt  = ts,
            source      = sessionImport.parseSource or sessionImport.urlText,
        }
        -- Reset import session UI after a successful commit so re-entering
        -- the Import view starts clean.
        self.state.session.ui.styles.import.urlText           = ""
        self.state.session.ui.styles.import.previewItems      = nil
        self.state.session.ui.styles.import.parseError        = nil
        self.state.session.ui.styles.import.parseSource       = nil
        self.state.session.ui.styles.import.parseDisplayName  = nil

    elseif action.type == A.STYLES_IMPORT_RESET then
        self.state.session.ui.styles.import.urlText           = ""
        self.state.session.ui.styles.import.previewItems      = nil
        self.state.session.ui.styles.import.parseError        = nil
        self.state.session.ui.styles.import.parseSource       = nil
        self.state.session.ui.styles.import.parseDisplayName  = nil

    elseif action.type == A.STYLES_INVALIDATE_CACHE then
        -- Tick bump; actual cache clear runs via Store subscriber -> StyleEngine:InvalidateCache.
        self.state.session.styles.cacheTick =
            (self.state.session.styles.cacheTick or 0) + 1

    elseif action.type == A.COLLECTION_STYLE_ITEM_ADDED then
        -- Membership write -- adds itemID to collection.items if not present.
        -- 14.0 scaffold: writes through to account.collections directly;
        -- 14.3 (Curator) consumes this when the Move action lands.
        local coll = payload.collectionID and self.state.account.collections
                     and self.state.account.collections[payload.collectionID]
        if coll and payload.itemID then
            coll.items = coll.items or {}
            local already = false
            for _, id in ipairs(coll.items) do
                if id == payload.itemID then already = true; break end
            end
            if not already then coll.items[#coll.items + 1] = payload.itemID end
        end

    elseif action.type == A.COLLECTION_STYLE_ITEM_REMOVED then
        local coll = payload.collectionID and self.state.account.collections
                     and self.state.account.collections[payload.collectionID]
        if coll and coll.items and payload.itemID then
            for i, id in ipairs(coll.items) do
                if id == payload.itemID then
                    table.remove(coll.items, i)
                    break
                end
            end
        end

    -- =====================================================================
    -- Zone Scanner
    -- =====================================================================
    -- ZONE_CHANGED: stamp new mapID, clear expanded set (scrollbox starts collapsed).
    -- Search query intentionally persists across zone changes for multi-zone workflows.
    elseif action.type == A.ZONE_CHANGED then
        -- ZoneObserver:Probe coerces mapID to a number (0 sentinel on
        -- API miss) and mapName to a string ("" sentinel) before dispatch,
        -- so this reducer reads both strictly. Defensive `or 0` / `or ""`
        -- here would mask producer regressions instead of surfacing them.
        self.state.session.zone.currentMapID    = payload.mapID
        self.state.session.zone.currentZoneName = payload.mapName
        self.state.session.ui.zoneScanner.expanded = {}

    elseif action.type == A.ZONE_POPUP_TOGGLE then
        self.state.account.ui.zonePopupShown =
            not (self.state.account.ui.zonePopupShown == true)

    elseif action.type == A.ZONE_TOGGLE_VENDOR then
        local npcID = payload.npcID
        if type(npcID) == "number" then
            local exp = self.state.session.ui.zoneScanner.expanded
            exp[npcID] = not (exp[npcID] == true) and true or nil
        end

    elseif action.type == A.ZONE_SET_SEARCH then
        self.state.session.ui.zoneScanner.searchQuery =
            type(payload.text) == "string" and payload.text or ""

    elseif action.type == A.ZONE_TOGGLE_COLLECTED then
        self.state.session.ui.zoneScanner.showCollected =
            not (self.state.session.ui.zoneScanner.showCollected == true)


    -- =====================================================================
    -- Lumber Tracker
    -- =====================================================================
    elseif action.type == A.LUMBER_HARVESTED then
        -- Append blip + bump tick. Coords nil when observer can't resolve position
        -- (loading screen, sub-map without world origin) -- skip blip, still bump tick.
        local s = self.state.session.lumber
        if payload.x and payload.y and payload.mapID then
            s.blips[#s.blips + 1] = {
                lumberID = payload.lumberID,
                qty      = payload.qty,
                x        = payload.x,
                y        = payload.y,
                mapID    = payload.mapID,
                ts       = payload.timestamp,
            }
        end
        s.tick = s.tick + 1
        -- Append to the per-char session lastHarvestAt + accumulate count
        -- IF a session is active for this lumberID (otherwise this is a
        -- "between sessions" harvest the observer will start a session on).
        local activeID = s.activeFarmingID
        if activeID == payload.lumberID then
            local charKey = self.state.session.identity.charKey
            local charSessions = self.state.account.lumber.sessions[charKey]
            local session = charSessions and charSessions[activeID]
            if session then
                session.lastHarvestAt = payload.timestamp
            end
        end

    elseif action.type == A.LUMBER_SESSION_START then
        -- First harvest after idle window; seeds per-char session record (startCount = bag total at start).
        local s = self.state.session.lumber
        s.activeFarmingID = payload.lumberID
        local charKey = self.state.session.identity.charKey
        self.state.account.lumber.sessions[charKey] =
            self.state.account.lumber.sessions[charKey] or {}
        self.state.account.lumber.sessions[charKey][payload.lumberID] = {
            startedAt     = payload.timestamp,
            startCount    = payload.startCount,
            lastHarvestAt = payload.timestamp,
            finalizedAt   = nil,
        }

    elseif action.type == A.LUMBER_SESSION_END then
        -- Stamps finalizedAt so counter row keeps displaying totals after activeFarmingID clears.
        local s = self.state.session.lumber
        local activeID = s.activeFarmingID
        if activeID then
            local charKey = self.state.session.identity.charKey
            local charSessions = self.state.account.lumber.sessions[charKey]
            local session = charSessions and charSessions[activeID]
            if session then
                session.finalizedAt = payload.timestamp
            end
        end
        s.activeFarmingID = nil

    elseif action.type == A.LUMBER_HISTORY_PUSH then
        -- Per-session summary for the Your Data farming log; ring buffer capped at LUMBER_HISTORY_CAP.
        local hist = self.state.account.lumber.history
        hist.nextID = hist.nextID + 1
        hist.entries[#hist.entries + 1] = {
            id           = hist.nextID,
            lumberID     = payload.lumberID,
            charKey      = payload.charKey,
            startedAt    = payload.startedAt,
            finalizedAt  = payload.finalizedAt,
            sessionTotal = payload.sessionTotal,
            zone         = payload.zone,
            character    = payload.character,
            realm        = payload.realm,
        }
        local cap = HDG.Constants.LUMBER_HISTORY_CAP
        while #hist.entries > cap do
            table.remove(hist.entries, 1)
        end

    elseif action.type == A.LUMBER_BLIP_GC then
        -- Drop blips older than 1 hr (RESPAWN_SECONDS; distinct from the 600s radar color-cycle constant).
        local s   = self.state.session.lumber
        local now = payload.now
        local ttl = 3600  -- mirror of HDG.LumberObserver.RESPAWN_SECONDS
        local kept = {}
        for _, b in ipairs(s.blips) do
            if now - b.ts < ttl then kept[#kept + 1] = b end
        end
        s.blips = kept

    elseif action.type == A.LUMBER_TICK then
        -- 1s heartbeat while farming; invalidates duration+rate selectors without a bag-delta.
        self.state.session.lumber.tick = self.state.session.lumber.tick + 1

    elseif action.type == A.REP_PROGRESS_TICK then
        -- Rep advanced (UPDATE_FACTION / renown change, debounced by RepObserver).
        -- Bump so rep-gate displays re-read live HDG.RepObserver:GetProgress.
        self.state.session.rep.tick = self.state.session.rep.tick + 1

    elseif action.type == A.LUMBER_WINDOW_TOGGLE then
        local c = self.state.account.lumber.config
        if payload and payload.visible ~= nil then
            c.windowVisible = payload.visible and true or false
        else
            c.windowVisible = not (c.windowVisible == true)
        end

    elseif action.type == A.LUMBER_WINDOW_POSITION_SET then
        self.state.account.lumber.config.position = {
            x = payload.x,
            y = payload.y,
        }

    elseif action.type == A.LUMBER_RADAR_COLLAPSE_TOGGLE then
        local c = self.state.account.lumber.config
        c.radarCollapsed = not (c.radarCollapsed == true)

    elseif action.type == A.LUMBER_AUTOSHOW_TOGGLE then
        local c = self.state.account.lumber.config
        c.autoShowOnHarvest = not (c.autoShowOnHarvest == true)

    elseif action.type == A.LUMBER_LIST_COLLAPSE_TOGGLE then
        local c = self.state.account.lumber.config
        c.listCollapsed = not (c.listCollapsed == true)

    elseif action.type == A.LUMBER_RADAR_SCALE_SET then
        local scale = payload.scale
        if type(scale) == "number" and scale > 0 then
            self.state.account.lumber.config.radarScale = scale
        end

    -- =====================================================================
    -- Shopping list
    -- =====================================================================
    elseif action.type == A.SHOPPING_WIDGET_TOGGLE then
        self.state.account.ui.shoppingWidgetShown =
            not (self.state.account.ui.shoppingWidgetShown == true)

    elseif action.type == A.SHOPPING_LIST_CREATE then
        self.state.account.shoppingListSeq = self.state.account.shoppingListSeq + 1
        local id = "L" .. tostring(self.state.account.shoppingListSeq)
        self.state.account.vendorShoppingLists[id] = {
            name      = type(payload.name) == "string" and payload.name or ("List " .. id),
            items     = {},
            meta      = {},
            createdAt = time(),
        }
        -- Auto-activate the first list created (HDG parity).
        if self.state.account.activeShoppingListId == "" then
            self.state.account.activeShoppingListId = id
        end

    elseif action.type == A.SHOPPING_LIST_DELETE then
        local id = payload.id
        self.state.account.vendorShoppingLists[id] = nil
        if self.state.account.activeShoppingListId == id then
            -- Pick any remaining list as new active, or "" if none.
            local nextId = ""
            for other in pairs(self.state.account.vendorShoppingLists) do
                nextId = other; break
            end
            self.state.account.activeShoppingListId = nextId
        end

    elseif action.type == A.SHOPPING_LIST_RENAME then
        local list = self.state.account.vendorShoppingLists[payload.id]
        if list then list.name = tostring(payload.name or list.name) end

    elseif action.type == A.SHOPPING_LIST_DUPLICATE then
        local src = self.state.account.vendorShoppingLists[payload.id]
        if src then
            self.state.account.shoppingListSeq = self.state.account.shoppingListSeq + 1
            local id = "L" .. tostring(self.state.account.shoppingListSeq)
            -- Shallow copy each entry (entries are flat tables; per-entry
            -- copy stops the duplicate from sharing entry references with
            -- the source).
            local copyItems = {}
            for i, entry in ipairs(src.items) do
                copyItems[i] = {
                    itemID  = entry.itemID,
                    npcID   = entry.npcID,
                    qty     = entry.qty,
                    addedAt = entry.addedAt,
                }
            end
            self.state.account.vendorShoppingLists[id] = {
                name      = tostring(payload.name or (src.name .. " (copy)")),
                items     = copyItems,
                meta      = {},   -- duplicates start with fresh meta (no inherited attribution)
                createdAt = time(),
            }
        end

    elseif action.type == A.SHOPPING_LIST_ACTIVATE then
        if self.state.account.vendorShoppingLists[payload.id] then
            self.state.account.activeShoppingListId = payload.id
        end

    elseif action.type == A.SHOPPING_LIST_CLEAR then
        local list = self.state.account.vendorShoppingLists[payload.id]
        if list then list.items = {} end

    elseif action.type == A.SHOPPING_LIST_SET_META then
        local list = self.state.account.vendorShoppingLists[payload.id]
        if list and type(payload.key) == "string" then
            list.meta = list.meta or {}
            list.meta[payload.key] = payload.value
        end

    elseif action.type == A.SHOPPING_LIST_IMPORT then
        -- HDG.ShoppingCodec.Decode returns a sanitized list record or nil
        -- on garbage / format-mismatch / wrong magic header. Strict call --
        -- ShoppingCodec is TOC-load-order guaranteed (Modules/ loads before
        -- any user-driven action fires).
        local decoded = HDG.ShoppingCodec.Decode(payload.encoded)
        if decoded then
            self.state.account.shoppingListSeq = self.state.account.shoppingListSeq + 1
            local id = "L" .. tostring(self.state.account.shoppingListSeq)
            self.state.account.vendorShoppingLists[id] = decoded
            self.state.account.activeShoppingListId = id
        end

    elseif action.type == A.SHOPPING_TOGGLE_EXPANDED then
        -- Flip a collapse flag (true = COLLAPSED). wishList is a scalar; zones/vendors are maps
        -- keyed by zoneName / npcID. Reducer owns the flip; the view dispatches only which bucket
        -- + key. (Replaces the controller's read-clone-flip-write _patchExpanded.)
        local e = self.state.session.ui.shoppingList.expanded
        if payload.bucket == "wishList" or payload.bucket == "ahList" then
            e[payload.bucket] = not (e[payload.bucket] == true)
        elseif payload.bucket and payload.key ~= nil then
            local b = e[payload.bucket]
            b[payload.key] = not (b[payload.key] == true) and true or nil
        end

    elseif action.type == A.SHOPPING_ITEM_ADD then
        local listID = payload.listID or self.state.account.activeShoppingListId
        local list = self.state.account.vendorShoppingLists[listID]
        if list then
            -- Coalesce: same (itemID, npcID) tuple bumps qty instead of
            -- producing a duplicate row.
            local merged
            for _, entry in ipairs(list.items) do
                if entry.itemID == payload.itemID and entry.npcID == payload.npcID then
                    entry.qty = (entry.qty or 1) + (payload.qty or 1)
                    merged = true
                    break
                end
            end
            if not merged then
                list.items[#list.items + 1] = {
                    itemID  = payload.itemID,
                    npcID   = payload.npcID,   -- nil = wishlist
                    qty     = payload.qty or 1,  -- exception(boundary): Shopping ADD may omit qty default-1
                    addedAt = time(),
                }
            end
        end

    elseif action.type == A.SHOPPING_ITEM_REMOVE then
        local listID = payload.listID or self.state.account.activeShoppingListId
        local list = self.state.account.vendorShoppingLists[listID]
        if list then
            for i, entry in ipairs(list.items) do
                if entry.itemID == payload.itemID and entry.npcID == payload.npcID then
                    table.remove(list.items, i)
                    break
                end
            end
        end

    elseif action.type == A.SHOPPING_ITEM_SET_QTY then
        local listID = payload.listID or self.state.account.activeShoppingListId
        local list = self.state.account.vendorShoppingLists[listID]
        if list then
            for _, entry in ipairs(list.items) do
                if entry.itemID == payload.itemID and entry.npcID == payload.npcID then
                    entry.qty = math.max(1, math.floor(tonumber(payload.qty) or 1))  -- exception(boundary): string-input qty from EditBox
                    break
                end
            end
        end

    elseif action.type == A.SHOPPING_RESOLVE_VENDORS then
        -- Persist resolved vendor npcIDs onto wishlist (npcID-less) entries so they
        -- bucket under their vendor + travel with Export. resolutions = {[itemID]=npcID}.
        -- Walk high->low: a resolved row that collides with an existing (itemID, npcID)
        -- vendor row merges its qty in and is removed (coalesce, mirroring ITEM_ADD).
        local list = self.state.account.vendorShoppingLists[payload.listID]
        if list then
            local res = payload.resolutions
            for i = #list.items, 1, -1 do
                local entry = list.items[i]
                local npc = res[entry.itemID]   -- resolved vendor for this itemID, or nil
                if (not entry.npcID) and npc then
                    local mergeInto
                    for _, other in ipairs(list.items) do
                        if other ~= entry and other.itemID == entry.itemID and other.npcID == npc then
                            mergeInto = other; break
                        end
                    end
                    if mergeInto then
                        mergeInto.qty = (mergeInto.qty or 1) + (entry.qty or 1)
                        table.remove(list.items, i)
                    else
                        entry.npcID = npc
                    end
                end
            end
        end

    -- =========================================================================
    -- Catalog lifecycle
    -- =========================================================================
    elseif action.type == A.CATALOG_LOAD_REQUESTED then
        self.state.session.catalog.status = "loading"

    elseif action.type == A.CATALOG_LOAD_FAILED then
        -- Without this, status stays "loading" -> infinite spinner.
        self.state.session.catalog.status = "error"

    elseif action.type == A.CATALOG_LOAD_COMPLETED then
        local c = self.state.session.catalog
        c.status          = "ready"
        c.loadedAt        = action.payload.loadedAt        -- dispatcher stamps GetTime() before dispatch
        c.itemCount       = action.payload.itemCount
        c.vendorCount     = action.payload.vendorCount
        c.sweepGeneration = action.payload.generation
        -- Clear pending on any successful sweep; without this, refreshPending stays true and
        -- every tab switch triggers a full re-sweep.
        c.refreshPending  = false

    elseif action.type == A.CATALOG_REFRESH_QUEUED then
        self.state.session.catalog.refreshPending = true
        self.state.session.catalog.variantsLoaded = false   -- ownership may have changed; force Dyed filter re-batch

    elseif action.type == A.CATALOG_REFRESH_COMPLETED then
        local c = self.state.session.catalog
        c.refreshPending  = false
        c.sweepGeneration = action.payload.generation or (c.sweepGeneration + 1)  -- exception(boundary): generation is optional

    elseif action.type == A.CATALOG_VARIANTS_LOADED then
        self.state.session.catalog.variantsLoaded = true

    elseif action.type == A.UI_SET_VIEW then
        self.state.session.ui.view = action.payload.view   -- dispatcher bug if nil; fail loud

    -- ===== Projects: house topology ==========================================
    -- Payload-key guards: missing key no-ops rather than indexing nil (payload is the input boundary).
    elseif action.type == A.PROJECTS_UPSERT_HOUSE then
        if payload.houseID then
            local p = self.state.account.projects
            local house = p.houses[payload.houseID] or {}
            for k, v in pairs(payload.fields or {}) do house[k] = v end
            p.houses[payload.houseID] = house
        end

    elseif action.type == A.PROJECTS_UPSERT_ROOM then
        -- versionID is required: roomID does NOT encode version (what-if reuses parent roomIDs).
        -- Strict read of versions[versionID]: a bogus id surfaces the controller bug.
        if payload.roomID and payload.versionID then
            local version = self.state.account.projects.versions[payload.versionID]
            local room = version.rooms[payload.roomID] or {}
            for k, v in pairs(payload.fields or {}) do room[k] = v end
            room.cell = room.cell or { x = 0, y = 0, rotation = 0, locked = false }
            version.rooms[payload.roomID] = room
        end

    elseif action.type == A.PROJECTS_MOVE_ROOM then
        -- Mutate an existing room's cell in place: move menu = dx/dy deltas, rotate = drotation,
        -- drag-drop = absolute x/y + locked. Reading the current cell means partial writes never
        -- drop fields (the seed-on-new gap PROJECTS_UPSERT_ROOM has). versionID strict (controller
        -- resolved the active version); room may be nil if the tile points at a removed room.
        if payload.roomID and payload.versionID then
            local version = self.state.account.projects.versions[payload.versionID]
            local room = version.rooms[payload.roomID]
            if room and room.cell then   -- exception(boundary): tile may reference a since-removed room
                local c = room.cell
                if payload.x ~= nil then c.x = payload.x elseif payload.dx ~= nil then c.x = c.x + payload.dx end
                if payload.y ~= nil then c.y = payload.y elseif payload.dy ~= nil then c.y = c.y + payload.dy end
                if payload.drotation ~= nil then c.rotation = ((c.rotation or 0) + payload.drotation) % 4 end
                if payload.locked ~= nil then c.locked = payload.locked end
                -- One record per room (multi-floor span is derived) -> nothing else to move.
            end
        end

    elseif action.type == A.PROJECTS_DELETE_ROOM then
        -- One record per room (multi-floor span is derived) -> delete just this record.
        if payload.roomID and payload.versionID then
            local nowTS   = payload.ts or (_G.GetTime and _G.GetTime() or 0)  -- exception(boundary): GetTime/time absent in headless harness
            local version = self.state.account.projects.versions[payload.versionID]
            _orphanCratesForRoom(self.state, payload.versionID, payload.roomID, nowTS)
            version.rooms[payload.roomID] = nil
        end

    elseif action.type == A.PROJECTS_CAPTURE_COMMIT then
        -- Atomic apply of a finalized capture; observer pre-computes matched/new/orphan + connections.
        local p = self.state.account.projects
        if payload.houseID then
            local house = p.houses[payload.houseID] or {}
            house.lastCapturedAt = payload.lastCapturedAt or house.lastCapturedAt
            if payload.houseName        then house.name             = payload.houseName end
            if payload.plotID           then house.plotID           = payload.plotID end
            if payload.neighborhoodName then house.neighborhoodName  = payload.neighborhoodName end
            p.houses[payload.houseID] = house
        end
        -- CAPTURE path mirrors REALITY -> the house's CURRENT version (never the active
        -- version, so a recapture taken while viewing a what-if can't clobber it).
        if payload.houseID then
            local vid     = _ensureHouseVersion(p, payload.houseID, payload.lastCapturedAt or 0)
            local version = p.versions[vid]
            for roomID, record in pairs(payload.rooms or {}) do
                record.cell = record.cell or { x = 0, y = 0, rotation = 0, locked = false }
                version.rooms[roomID] = record
            end
            for _, roomID in ipairs(payload.deleteRoomIDs or {}) do
                -- Orphan-stamp the room's crates BEFORE deleting (same contract as
                -- PROJECTS_DELETE_ROOM) -- recapture-driven removal is the primary
                -- delete path; without this, crates point at a dead room + vanish
                -- from both crateRows buckets.
                _orphanCratesForRoom(self.state, vid, roomID, payload.lastCapturedAt or 0)
                version.rooms[roomID] = nil
            end
        end

    elseif action.type == A.PROJECTS_HOUSE_TICK then
        -- Partial patch from HousingObserver; each event updates the subset it knows.
        local h = self.state.session.house
        if payload.budget       then h.budget = payload.budget end
        if payload.numFloors    ~= nil then h.numFloors = payload.numFloors end
        if payload.editorActive ~= nil then h.editorActive = payload.editorActive end

    elseif action.type == A.PROJECTS_ROOM_CATALOG_UPDATED then
        -- Atomic replace + tick bump; room-source/stock selectors invalidate together.
        local rc = self.state.session.house.roomCatalog
        rc.byShapeID = payload.byShapeID or {}  -- exception(boundary): atomic-replace; empty keeps table shape if payload omits
        rc.entries   = payload.entries   or {}  -- exception(boundary): atomic-replace; empty keeps table shape if payload omits
        rc.tick      = rc.tick + 1

    elseif action.type == A.CATALOG_CATEGORY_TREE_UPDATED then
        -- Blizzard category/subcategory nav snapshot from the observer. Atomic replace
        -- + tick bump so the curator + projects nav selectors invalidate together.
        local ct = self.state.session.house.categoryTree
        ct.byID       = payload.byID       or {}  -- exception(boundary): atomic-replace; empty keeps table shape if payload omits
        ct.subcatByID = payload.subcatByID or {}  -- exception(boundary): atomic-replace; empty keeps table shape if payload omits
        ct.rootIDs    = payload.rootIDs    or {}  -- exception(boundary): atomic-replace; empty keeps table shape if payload omits
        ct.tick       = ct.tick + 1

    elseif action.type == A.PROJECTS_CLEAR_HOUSE then
        -- Full re-capture wipes the house's stored layout up front (the sweep then
        -- re-adds exactly the floors that currently exist) -- so a deleted floor's
        -- rooms can't linger. Crates fall to the orphan bay (same as DELETE_ROOM).
        if payload.houseID then
            local p     = self.state.account.projects
            local house = p.houses[payload.houseID]
            local vid   = house and house.currentVersionID
            local version = vid and p.versions[vid]
            if version then   -- exception(boundary): first capture fires CLEAR before the house/version exists
                for roomID in pairs(version.rooms) do
                    _orphanCratesForRoom(self.state, vid, roomID, payload.clearedAt or 0)
                end
                version.rooms = {}
            end
        end

    elseif action.type == A.PROJECTS_SET_ACTIVE_VERSION then
        -- Switch active version for a house. Invalidates "*" (canvas reads two-level keys).
        if payload.houseID and payload.versionID then
            local house = self.state.account.projects.houses[payload.houseID]
            if house then house.activeVersionID = payload.versionID end
        end

    elseif action.type == A.PROJECTS_CREATE_VERSION then
        -- Branch a what-if: deep-copy basedOn's rooms (independent tables) + activate.
        -- versionID minted reducer-side from the counter (deterministic, collision-free).
        if payload.houseID then
            local p     = self.state.account.projects
            local house = p.houses[payload.houseID]
            if house then
                local vid   = _nextVersionID(p)
                local src   = payload.basedOn and p.versions[payload.basedOn]
                local rooms = {}
                if src then for rid, room in pairs(src.rooms) do rooms[rid] = DeepCopy(room) end end
                p.versions[vid] = {
                    houseID   = payload.houseID, name = payload.name or "What-if",  -- exception(boundary): CREATE_VERSION payload may omit name
                    createdAt = payload.createdAt, basedOn = payload.basedOn, rooms = rooms,
                }
                house.activeVersionID = vid
            end
        end

    elseif action.type == A.PROJECTS_DELETE_VERSION then
        -- Remove a what-if (NEVER the live/current version). If active, fall back to live.
        if payload.houseID and payload.versionID then
            local p     = self.state.account.projects
            local house = p.houses[payload.houseID]
            if house and payload.versionID ~= house.currentVersionID and p.versions[payload.versionID] then
                for _, coll in pairs(self.state.account.collections) do
                    if coll.type == "crate" and coll.versionID == payload.versionID then
                        coll.parent, coll.versionID, coll.orphanedAt = nil, nil, payload.ts or 0
                    end
                end
                p.versions[payload.versionID] = nil
                if house.activeVersionID == payload.versionID then
                    house.activeVersionID = house.currentVersionID
                end
            end
        end

    elseif action.type == A.PROJECTS_SET_VERSION_FLOORS then
        -- Set the floor count on a what-if version (1..3 cap; enforced here too, not just
        -- the controller, so the store never holds an out-of-range value). nil clears the
        -- override -> floorTabs falls back to scanning room IDs + session.house.numFloors.
        if payload.versionID and payload.numFloors ~= nil then
            local version = self.state.account.projects.versions[payload.versionID]
            if version then
                local n = math.max(1, math.min(3, math.floor(payload.numFloors)))
                version.numFloors = n
            end
        end

    elseif action.type == A.PROJECTS_RENAME_VERSION then
        -- Rename a version (name only; structural fields stay locked).
        if payload.versionID and payload.name then
            local version = self.state.account.projects.versions[payload.versionID]
            if version then version.name = payload.name end
        end

    elseif action.type == A.PROJECTS_IMPORT_LAYOUT then
        -- Thin (matches PROJECTS_PLACE_STACKED): the CONTROLLER builds the version
        -- record from the decoded layout, re-keying roomIDs to the target house. The
        -- reducer only mints the id (the counter is state-resident, so minting must be
        -- reducer-side) + activates it, so the controller can read the id back.
        if payload.houseID and payload.version then
            local p     = self.state.account.projects
            local house = p.houses[payload.houseID]
            -- Importing into an owned-but-uncaptured house creates its record.
            if not house then house = {}; p.houses[payload.houseID] = house end
            local vid = _nextVersionID(p)
            p.versions[vid] = payload.version
            house.activeVersionID = vid
        end

    elseif action.type == A.PROJECTS_FOCUS_HOUSE then
        -- Switch which house the Architect/Projects views show. A monotonic focusSeq
        -- bump makes this house win the house pick (no separate "active" pointer + no
        -- new selector reads -- focusSeq lives under the house record). Focusing an
        -- as-yet-uncaptured house (picked from the owned-houses dropdown) creates a
        -- focus STUB so the pick sticks; capturing it later UPSERTs the same token.
        if payload.houseID then
            local p     = self.state.account.projects
            local house = p.houses[payload.houseID]
            if not house then house = {}; p.houses[payload.houseID] = house end
            p.houseFocusSeq = (p.houseFocusSeq or 0) + 1
            house.focusSeq  = p.houseFocusSeq
        end

    -- ===== Projects: crates ===================================================
    elseif action.type == A.CRATE_UPSERT then
        if payload.crateID then
            local colls = self.state.account.collections
            local crate = colls[payload.crateID] or { id = payload.crateID, type = "crate", decor = {} }
            for k, v in pairs(payload.fields or {}) do
                if k ~= "id" and k ~= "type" and k ~= "decor" then crate[k] = v end
            end
            crate.id, crate.type = payload.crateID, "crate"
            crate.decor = crate.decor or {}   -- exception(boundary): SV-migrated crate may predate the decor field
            colls[payload.crateID] = crate
        end

    elseif action.type == A.CRATE_ADD_DECOR then
        local crate = payload.crateID and self.state.account.collections[payload.crateID]
        if crate and payload.decorID then
            crate.decor = crate.decor or {}   -- exception(boundary): SV-migrated crate may predate the decor field
            local i = _crateDecorIndex(crate, payload.decorID)
            if i then
                -- Existing entry: an explicit count SETS it (import / stepper set);
                -- no count INCREMENTS (re-clicking "+ add" / the stepper plus = +1).
                if payload.count ~= nil then
                    crate.decor[i].count = payload.count
                else
                    crate.decor[i].count = (crate.decor[i].count or 1) + 1
                end
                if payload.notes ~= nil then crate.decor[i].notes = payload.notes end
            else
                local cnt = payload.count
                if cnt == nil then cnt = 1 end   -- default 1; honor an explicit 0
                crate.decor[#crate.decor + 1] = { id = payload.decorID, count = cnt, notes = payload.notes }
            end
        end

    elseif action.type == A.CRATE_DECREMENT_DECOR then
        -- Stepper minus: count - 1, removing the entry when it hits 0.
        local crate = payload.crateID and self.state.account.collections[payload.crateID]
        if crate and payload.decorID and crate.decor then
            local i = _crateDecorIndex(crate, payload.decorID)
            if i then
                local n = (crate.decor[i].count or 1) - 1
                if n <= 0 then table.remove(crate.decor, i) else crate.decor[i].count = n end
            end
        end

    elseif action.type == A.CRATE_REMOVE_DECOR then
        local crate = payload.crateID and self.state.account.collections[payload.crateID]
        if crate and payload.decorID and crate.decor then
            local i = _crateDecorIndex(crate, payload.decorID)
            if i then table.remove(crate.decor, i) end
        end

    elseif action.type == A.CRATE_SET_FIELD then
        local crate = payload.crateID and self.state.account.collections[payload.crateID]
        -- id/type/decor are protected (structural); everything else is free.
        if crate and payload.field and payload.field ~= "id"
           and payload.field ~= "type" and payload.field ~= "decor" then
            crate[payload.field] = payload.value
        end

    elseif action.type == A.CRATE_REATTACH then
        -- Re-scope an orphan crate onto a room in a version. A crate is keyed by BOTH
        -- (versionID, parent), and orphaning stamps orphanedAt (see PROJECTS_DELETE_VERSION ~3364);
        -- re-attach is the exact inverse and must clear all three together. That rule lives HERE,
        -- not in the view. roomID + versionID are both supplied by the caller in the payload --
        -- the reducer derives nothing from ambient session state (self-contained action).
        local crate = payload.crateID and self.state.account.collections[payload.crateID]
        if crate and payload.roomID and payload.versionID then
            crate.parent     = payload.roomID
            crate.versionID  = payload.versionID
            crate.orphanedAt = nil
        end

    elseif action.type == A.CRATE_DETACH then
        -- Orphan a single crate off its room (parent -> nil); it lands in the orphan bay,
        -- reattachable via CRATE_REATTACH. Same provenance-stamp as the room-delete sweep.
        local crate = payload.crateID and self.state.account.collections[payload.crateID]
        if crate and crate.type == "crate" and crate.parent then
            _orphanCrate(self.state, crate, payload.ts or (time and time()) or 0)
        end

    elseif action.type == A.CRATE_DELETE then
        if payload.crateID then self.state.account.collections[payload.crateID] = nil end

    elseif action.type == A.LIBRARY_STAMP then
        -- Clone a library template's decor into a fresh independent crate
        -- (cloning-not-references: editing one never affects another).
        local colls = self.state.account.collections
        local lib = payload.libID and colls[payload.libID]
        if lib and payload.crateID then
            local decorCopy = {}
            for _, rec in ipairs(lib.decor or {}) do
                decorCopy[#decorCopy + 1] = { id = rec.id, count = rec.count, notes = rec.notes }
            end
            colls[payload.crateID] = {
                id = payload.crateID, type = "crate", parent = payload.parent,
                name = payload.name or lib.name, derivedFrom = payload.libID,
                decor = decorCopy, createdAt = payload.ts,
            }
        end

    -- ===== Projects: shipping crates ==========================================
    -- { id, type="shippingCrate", name, houseID, packedAt, captureLevel="manifest",
    --   topology, contents, placementsByRoom=nil, houseLayoutBlob=nil }
    -- placementsByRoom + houseLayoutBlob are reserved-nil (avoid SV migration when placement API ships).
    elseif action.type == A.SHIPPING_CRATE_PACK then
        -- DeepCopy: topology.rooms / connections / contents[].decor are live refs; raw storage
        -- would make the "backup" silently track future mutations.
        if payload.shipID and payload.record then
            self.state.account.collections[payload.shipID] = DeepCopy(payload.record)
        end

    elseif action.type == A.SHIPPING_CRATE_DELETE then
        if payload.shipID then self.state.account.collections[payload.shipID] = nil end

    elseif action.type == A.PROJECTS_REMAP_ROOM then
        -- Re-key captured room to existing ID + re-parent its crates (resolves ambiguous fingerprint matches).
        local p       = self.state.account.projects
        local parsed  = payload.fromRoomID and HDG.Projects.IDs.parsePath(payload.fromRoomID)
        local house   = parsed and parsed.houseID and p.houses[parsed.houseID]
        local vid     = house and house.currentVersionID
        local version = vid and p.versions[vid]
        if payload.fromRoomID and payload.toRoomID and version and version.rooms[payload.fromRoomID] then
            version.rooms[payload.toRoomID] = version.rooms[payload.fromRoomID]
            version.rooms[payload.fromRoomID] = nil
            for _, coll in pairs(self.state.account.collections) do
                if coll.type == "crate" and coll.versionID == vid and coll.parent == payload.fromRoomID then
                    coll.parent = payload.toRoomID
                end
            end
        end

    else
        -- Closed action taxonomy (spec section 12): unknown types are typos; fail loud at dispatch.
        error(("HDG.Store:_RawDispatch: unknown action type %q"):format(
            tostring(action.type)), 2)
    end

    -- Invalidate memos BEFORE _Notify so subscribers re-resolve selectors with fresh values.
    HDG.Selectors:InvalidateMemos(invalidation)
    self:_Notify(action.type, invalidation, action)
end

-- Public Dispatch defaults to _RawDispatch when no middleware chain has
-- been installed. Middleware.Apply (Core/HDGR_Init) wraps this with the
-- Logger / Combat / Persistence layers.
function HDG.Store:Dispatch(action)
    return self:_RawDispatch(action)
end

-- ===== SavedVariables I/O ====================================================

function HDG.Store:LoadFromSavedVariables()
    _G.HDG_DB = _G.HDG_DB or {}
    -- Run in-place migration BEFORE adopting account. For existing HDG users,
    -- HDG_DB is actually the old HDG_DB (same table after the P2 rename);
    -- HDG.Migration:Run transforms flat HDG keys -> HDG account.* shape.
    -- No-op when DB is already at HDG schema or when Migration module is absent.
    if HDG.Migration and HDG.Migration.Run then  -- exception(boundary): module absent in early-boot tests that load only Store
        -- Stash the result so the one-time upgrade notice can fire at OnEnable.
        HDG.Migration.lastResult = HDG.Migration:Run(_G.HDG_DB)
    end
    self.state = NewDefaultState()
    if _G.HDG_DB.account then
        -- Adopt persisted account verbatim, then merge defaults so newly
        -- added keys land for upgraded users (schema migration runs here).
        self.state.account = _G.HDG_DB.account
    end
    EnsureStateShape(self.state)
end

-- Coalesced save: dispatches within a frame share one write.
function HDG.Store:QueueSave()
    if self._saveTimer then return end
    if not (C_Timer and C_Timer.NewTimer) then
        -- Outside WoW (tests). Flush immediately.
        self:Flush()
        return
    end
    self._saveTimer = C_Timer.NewTimer(self._saveDelay, function()
        self._saveTimer = nil
        self:Flush()
    end)
end

-- Flush: by-reference write -- state.account IS HDG_DB.account (no DeepCopy).
-- WoW serializes whatever HDG_DB points at on logout; re-link is a cheap safety check.
function HDG.Store:Flush()
    _G.HDG_DB = _G.HDG_DB or {}
    _G.HDG_DB.account = self.state.account
end
