HDG = HDG or {}
HDG.Constants = {
    ADDON_NAME = "HousingDecorGuide",
    DB_NAME = "HDG_DB",
    -- HDG->HDGR migration schema. Bumps force the migration to RE-RUN (its steps
    -- are idempotent + self-repairing): v2 = per-char professions skillLevels->skillLines
    -- + name/realm parse; v3 = craft/lumber history ordered oldest-first (newest renders
    -- at top, matching the live *_HISTORY_PUSH append-at-end convention);
    -- v4 = collections transformed to the HDGR style model (curatedItems->items array,
    -- snapshot->snapshot type, query-only->smartset, crates dropped);
    -- v5 = re-key migrated snapshots/smartsets to the "snapshot:"/"smartset:" id prefix
    -- (the landing + Detail route by id prefix, not def.type);
    -- v6 = drop library-type collections (empty curated templates + player saves);
    -- v7 = Furnishings model: crates -> sets, version.rooms -> account.rooms +
    --      layout placements (docs/crate-redesign/10-FINAL-MODEL.md).
    SCHEMA_VERSION = 8,
    -- Catalog row schema version. Bump when the observer row shape changes.
    -- No migration needed -- catalog is fully re-fetched from C_HousingCatalog on every sweep.
    CATALOG_SCHEMA_VERSION = 3,
    -- Atlas for snapshot ("All Placed Decor") cards -- the decorate-mode house glyph.
    SNAPSHOT_ICON_ATLAS = "decor-controls-decoratemode-active",
    -- Atlas for empty shopping-list cards -- the shopping-cart glyph (matches the
    -- Shopping tab header) instead of the red "?" placeholder.
    SHOPPING_LIST_ICON_ATLAS = "Perks-ShoppingCart",

    -- Default scheme name. SchemeConstants registers it; Theme:Initialize
    -- consumes it on first load. Config.scheme overrides at runtime.
    DEFAULT_SCHEME = "ColorblindSafe",

    -- Professions that produce decor recipes. Alphabetical -- order drives chip visual order.
    -- New professions appear in DecorDB -> append here.
    DECOR_PROFESSIONS = {
        "Alchemy",
        "Blacksmithing",
        "Cooking",
        "Enchanting",
        "Engineering",
        "Inscription",
        "Jewelcrafting",
        "Leatherworking",
        "Tailoring",
    },

    -- ========================================================================
    -- Expansion / Profession / Lumber master tables. DATA ONLY -- consumers
    -- build whatever index they need at their own site.
    -- ========================================================================

    -- Expansion master data. Each entry: display name, api tag, short code, color, localized aliases.
    -- IMPORTANT: DO NOT CHANGE the `abbr` values -- they're keys in cross-tab quote tables and savedvars.
    EXPANSION_DATA = {
        { display = "Classic",              api = "Classic",      abbr = "Classic", short = "CLS", color = { 0.6, 0.6, 0.6 },
          aliases = { "Klassisch", "Clasico", "Classique", "Classico", "Clássico", "Классика", "经典", "经典旧世", "經典", "经典版", "經典版", "클래식" } },
        { display = "The Burning Crusade",  api = "Outland",      abbr = "TBC",     short = "TBC", color = { 0.4, 0.7, 0.4 },
          apiTags = { "Burning Crusade", "Scherbenwelt", "Terrallende", "Outreterre", "Terre Esterne", "Terralém", "Запределье", "外域", "燃烧的远征", "燃燒的遠征", "아웃랜드", "불타는 성전" } },
        { display = "Wrath of the Lich King", api = "Northrend",  abbr = "WotLK",   short = "WLK", color = { 0.4, 0.6, 0.8 },
          aliases = { "WotLK", "Nordend", "Rasganorte", "Norfendre", "Nordania", "Nortúndria", "Нордскол", "诺森德", "巫妖王之怒", "北裂境", "노스렌드", "리치 왕의 분노" } },
        { display = "Cataclysm",            api = "Cataclysm",    abbr = "Cata",    short = "CAT", color = { 0.8, 0.5, 0.2 },
          aliases = { "Cataclysme", "Kataklysmus", "Cataclismo", "Cataclisma", "Катаклизм", "大地的裂变", "浩劫與重生", "대격변" } },
        { display = "Mists of Pandaria",    api = "Pandaria",     abbr = "MoP",     short = "MOP", color = { 0.3, 0.7, 0.5 },
          aliases = { "MoP", "Pandarie", "Pandária", "Пандария", "潘达利亚", "熊猫人之谜", "潘達利亞", "潘達利亞之謎", "판다리아", "판다리아의 안개" } },
        { display = "Warlords of Draenor",  api = "Draenor",      abbr = "WoD",     short = "WOD", color = { 0.7, 0.5, 0.3 },
          aliases = { "WoD", "Дренор", "德拉诺", "德拉诺之王", "德拉諾", "德拉諾之霸", "드레노어", "드레노어의 전쟁군주" } },
        { display = "Legion",               api = "Legion",       abbr = "Legion",  short = "LEG", color = { 0.5, 0.9, 0.3 },
          aliases = { "Légion", "Легион", "军团再临", "軍臨天下", "군단" } },
        { display = "Battle for Azeroth",   api = "BfA",          abbr = "BfA",     short = "BFA", color = { 0.8, 0.7, 0.2 },
          aliases = { "Kul", "Kul Tiran", "Zandalari", "Zandalar", "Kul Tiras", "Культирас", "Кул-Тирас", "Кул-тирас", "Зандалари", "Зандалар", "库尔提拉斯", "争霸艾泽拉斯", "庫爾提拉斯", "決戰艾澤拉斯", "赞达拉", "贊達拉", "쿨 티란", "잔달라", "격전의 아제로스" } },
        { display = "Shadowlands",          api = "Shadowlands",  abbr = "SL",      short = "SL",  color = { 0.6, 0.4, 0.8 },
          aliases = { "Schattenlande", "Ombreterre", "Tierras Sombrías", "Terre Ombrose", "Terras Sombrias", "Темные Земли", "暗影国度", "暗影之境", "暗影界", "어둠땅" } },
        { display = "Dragonflight",         api = "Dragon Isles", abbr = "DF",      short = "DF",  color = { 0.2, 0.6, 1.0 },
          aliases = { "Dragon", "Dracheninseln", "Islas del Dragón", "Islas Dragón", "Îles aux Dragons", "Isole dei Draghi", "Ilhas do Dragão", "Драконьи острова", "巨龙群岛", "巨龙时代", "巨龍群島", "巨龍崛起", "용의 섬", "용군단" } },
        { display = "The War Within",       api = "Khaz Algar",   abbr = "TWW",     short = "TWW", color = { 1.0, 0.5, 0.2 },
          aliases = { "Khaz", "Каз'Алгар", "Каз-Алгар", "Каз-алгар", "Каз Алгар", "卡兹阿加", "地心之战", "卡茲阿爾加", "地心之戰", "카즈 알가르", "내부 전쟁" } },
        { display = "Midnight",             api = "Midnight",     abbr = "MN",      short = "MN",  color = { 0.6, 0.2, 0.8 },
          aliases = { "至暗之夜", "한밤" } },
    },

    -- Profession master data. Each entry: name, TradeSkillLineID, 2-letter code, atlas, shortLabel.
    -- shortLabel trims the longer names for cramped strips (Goblin filter pills).
    -- First 9 are crafting professions; last 3 are gathering. "Mobile-*" atlases have transparent backgrounds.
    PROFESSION_DATA = {
        { name = "Alchemy",       shortLabel = "Alchemy",      id = 171, code = "AL", atlas = "Mobile-Alchemy"        },
        { name = "Blacksmithing", shortLabel = "Blacksmith",   id = 164, code = "BS", atlas = "Mobile-Blacksmithing"  },
        { name = "Cooking",       shortLabel = "Cooking",      id = 185, code = "CK", atlas = "Mobile-Cooking"        },
        { name = "Enchanting",    shortLabel = "Enchanting",   id = 333, code = "EN", atlas = "Mobile-Enchanting"     },
        { name = "Engineering",   shortLabel = "Engineering",  id = 202, code = "EG", atlas = "Mobile-Enginnering"    },  -- Blizzard typo preserved
        { name = "Inscription",   shortLabel = "Inscription",  id = 773, code = "IN", atlas = "Mobile-Inscription"    },
        { name = "Jewelcrafting", shortLabel = "Jewelcraft",   id = 755, code = "JC", atlas = "Mobile-Jewelcrafting"  },
        { name = "Leatherworking",shortLabel = "Leatherwork",  id = 165, code = "LW", atlas = "Mobile-Leatherworking" },
        { name = "Tailoring",     shortLabel = "Tailoring",    id = 197, code = "TL", atlas = "Mobile-Tailoring"      },
        { name = "Herbalism",     shortLabel = "Herbalism",    id = 182, code = "HB", atlas = "Mobile-Herbalism"      },
        { name = "Mining",        shortLabel = "Mining",       id = 186, code = "MN", atlas = "Mobile-Mining"         },
        { name = "Skinning",      shortLabel = "Skinning",     id = 393, code = "SK", atlas = "Mobile-Skinning"       },
    },

    -- Source-type brand colors. Indexed by sourceType integer ID from AllDecorDB entry[2].
    -- Consumed by Palette.source.<typeName> tokens for HouseTab sourceDonut legend swatches.
    SOURCE_TYPE_COLOR = {
        [0]   = { name = "UNKNOWN",     color = { 0.53, 0.53, 0.53 } },
        [1]   = { name = "ACHIEVEMENT", color = { 1.00, 0.82, 0.29 } },
        [2]   = { name = "QUEST",       color = { 0.45, 0.78, 0.95 } },  -- chip-canonical (SOURCE_KINDS QUEST)
        [3]   = { name = "WORLD_QUEST", color = { 0.24, 0.62, 0.90 } },
        [4]   = { name = "DROP",        color = { 0.91, 0.78, 0.36 } },  -- chip-canonical (SOURCE_KINDS DROP)
        [5]   = { name = "VENDOR",      color = { 0.36, 0.70, 0.41 } },
        [6]   = { name = "CRAFTED",     color = { 0.88, 0.39, 0.24 } },
        [7]   = { name = "LEARNED",     color = { 0.55, 0.75, 0.90 } },
        [8]   = { name = "GATHERING",   color = { 0.61, 0.48, 0.29 } },
        [9]   = { name = "TREASURE",    color = { 0.95, 0.86, 0.30 } },  -- chip-canonical (SOURCE_KINDS TREASURE)
        [10]  = { name = "PROMOTION",   color = { 0.78, 0.43, 0.75 } },
        [11]  = { name = "PROFESSION",  color = { 0.36, 0.66, 0.71 } },
        [12]  = { name = "SHOP",        color = { 0.91, 0.43, 0.62 } },
        [13]  = { name = "REP",         color = { 1.00, 0.69, 0.38 } },  -- chip-canonical; also un-hides the rep donut wedge (was source.13 -> nil)
        [14]  = { name = "EVENT",       color = { 0.30, 0.74, 0.80 } },
        [101] = { name = "ENDEAVOR",    color = { 0.30, 0.70, 0.62 } },
        [102] = { name = "GOLD_ONLY",   color = { 0.95, 0.78, 0.35 } },
    },

    -- Midnight initiative event-vendor NPC IDs. One per HouseTab event card widget.
    EVENT_VENDOR_NPCS = {
        ritualSites  = 255495,   -- Rae'ana (Silvermoon, Voidlight Marl)
        abyssAnglers = 260180,   -- Depthdiver Tu'nakit (Zul'Aman, Angler Pearls)
        decorDuels   = 264056,   -- Disguised Decor Duel Vendor (Silvermoon, Illusionary Coins)
    },

    -- Lumber master data. Each entry: itemID, names, expansion, mounted-harvesting achieveID.
    LUMBER_DATA = {
        { id = 245586, name = "Ironwood Lumber",     shortName = "Ironwood",    expansion = "Classic",                achieveID = 62357 },
        { id = 242691, name = "Olemba Lumber",       shortName = "Olemba",      expansion = "The Burning Crusade",    achieveID = 62358 },
        { id = 251762, name = "Coldwind Lumber",     shortName = "Coldwind",    expansion = "Wrath of the Lich King", achieveID = 62359 },
        { id = 251764, name = "Ashwood Lumber",      shortName = "Ashwood",     expansion = "Cataclysm",              achieveID = 62360 },
        { id = 251763, name = "Bamboo Lumber",       shortName = "Bamboo",      expansion = "Mists of Pandaria",      achieveID = 62361 },
        { id = 251766, name = "Shadowmoon Lumber",   shortName = "Shadowmoon",  expansion = "Warlords of Draenor",    achieveID = 62362 },
        { id = 251767, name = "Fel-Touched Lumber",  shortName = "Fel-Touched", expansion = "Legion",                 achieveID = 62363 },
        { id = 251768, name = "Darkpine Lumber",     shortName = "Darkpine",    expansion = "Battle for Azeroth",     achieveID = 62364 },
        { id = 251772, name = "Arden Lumber",        shortName = "Arden",       expansion = "Shadowlands",            achieveID = 62365 },
        { id = 251773, name = "Dragonpine Lumber",   shortName = "Dragonpine",  expansion = "Dragonflight",           achieveID = 62366 },
        { id = 248012, name = "Dornic Fir Lumber",   shortName = "Dornic Fir",  expansion = "The War Within",         achieveID = 62369 },
        { id = 256963, name = "Thalassian Lumber",   shortName = "Thalassian",  expansion = "Midnight",               achieveID = 62370 },
    },

    -- Housing decor currencies. Hand-curated; iconFileIDs captured live.
    -- Expansion string must match a Palette `expansion.<name>` color key.
    HOUSING_DECOR_CURRENCY_DATA = {
        { id =  823, name = "Apexis Crystal",       icon = 1061300, expansion = "Warlords of Draenor" },
        { id =  824, name = "Garrison Resources",   icon = 1397630, expansion = "Warlords of Draenor" },
        { id = 1155, name = "Ancient Mana",         icon = 1377394, expansion = "Legion"              },
        { id = 1220, name = "Order Resources",      icon = 1397630, expansion = "Legion"              },
        { id = 1508, name = "Veiled Argunite",      icon = 1064188, expansion = "Legion"              },
        { id = 1560, name = "War Resources",        icon = 2032600, expansion = "Battle for Azeroth"  },
        { id = 1710, name = "Seafarer's Dubloon",   icon = 1604167, expansion = "Battle for Azeroth"  },
        { id = 1767, name = "Stygia",               icon = 3743739, expansion = "Shadowlands"         },
        { id = 1792, name = "Honor",                icon = 1455894, expansion = "Classic"             },
        { id = 1803, name = "Echoes of Ny'alotha",  icon = 3069889, expansion = "Battle for Azeroth"  },
        { id = 1813, name = "Reservoir Anima",      icon = 3528288, expansion = "Shadowlands"         },
        { id = 2003, name = "Dragon Isles Supplies",icon = 2006578, expansion = "Dragonflight"        },
        { id = 2118, name = "Elemental Overflow",   icon =  134388, expansion = "Dragonflight"        },
        { id = 2657, name = "Mysterious Fragment",  icon = 1362650, expansion = "Dragonflight"        },
        { id = 2803, name = "Undercoin",            icon =  133858, expansion = "Midnight"            },
        { id = 2815, name = "Resonance Crystals",   icon = 2967113, expansion = "Classic"             },
        { id = 3056, name = "Kej",                  icon = 4549280, expansion = "The War Within"      },
        { id = 3316, name = "Voidlight Marl",       icon = 7137586, expansion = "Midnight"            },
        { id = 3363, name = "Community Coupons",    icon =  134495, expansion = "Midnight"            },
        { id = 3373, name = "Angler Pearls",        icon =  348545, expansion = "Midnight"            },
        { id = 3377, name = "Unalloyed Abundance",  icon = 5041790, expansion = "Midnight"            },
        { id = 3379, name = "Brimming Arcana",      icon =  132849, expansion = "Midnight"            },
        { id = 3392, name = "Remnant of Anguish",   icon = 4554435, expansion = "Midnight"            },
        { id = 3393, name = "Illusionary Coin",     icon = 1717106, expansion = "Midnight"            },
    },

    -- Top-row filter chip values. SSoT for Selectors, LayoutConfig, Controller_Decor, and the reducer.
    -- Adding or removing a bucket is one edit here.
    TOP_FILTERS = {
        { value = "all",        label = "All"        },
        { value = "crafted",    label = "Crafted"    },
        { value = "sizes",      label = "Size |A:house-decor-budget-icon:12:12|a" },
        { value = "styles",     label = "Styles"     },
        { value = "expansions", label = "Expansions" },
        { value = "other",      label = "Other"      },
        { value = "sources",    label = "Sources"    },
    },

    -- Crafting history ring-buffer cap. ~110KB worst case in SV.
    CRAFT_HISTORY_CAP = 500,

    -- Lumber farming history ring-buffer cap. Capped lower than craft history (sessions are richer records).
    LUMBER_HISTORY_CAP = 200,

    -- Decor achievement milestone IDs (Items Acquired achievements).
    DECOR_ACHIEVEMENTS = {
        { id = 61308, threshold = 1   },
        { id = 61309, threshold = 5   },
        { id = 61310, threshold = 25  },
        { id = 61311, threshold = 50  },
        { id = 61312, threshold = 100 },
        { id = 61313, threshold = 150 },
        { id = 61314, threshold = 200 },
        { id = 61315, threshold = 250 },
        { id = 61316, threshold = 300 },
        { id = 61317, threshold = 400 },
        { id = 61318, threshold = 500 },
    },

    -- Community Coupon achievement milestone IDs.
    COUPON_ACHIEVEMENTS = {
        { id = 62371, threshold = 50    }, -- Couponing for Beginners
        { id = 62373, threshold = 250   }, -- Coupon Collector
        { id = 62374, threshold = 500   }, -- You Get The Best Deals Anywhere
        { id = 62375, threshold = 1000  }, -- Buying in Bulk
        { id = 62376, threshold = 2000  }, -- Extreme Couponing
        { id = 62377, threshold = 5000  }, -- A Fist Full of Coupons
        { id = 62378, threshold = 10000 }, -- A Few Coupons More
    },

    -- LUMBER_TYPES is an O(1) keyed-by-itemID view built lazily by selectors that need per-ID lookup.

    -- Recipe knowledge state -- 4-state enum returned by decor.craftableState.
    -- String values are the wire-format; codebase preference is the constant form.
    RECIPE_STATE = {
        KnownByCharacter = "known_self",
        KnownByAlt       = "known_alt",
        UnknownOnAccount = "recipe_exists",
        NotARecipe       = "not_a_recipe",
    },

    -- Closed taxonomy of text-color states. SSoT for collection, recipe-knowledge, and severity states.
    -- Keys match RECIPE_STATE so the same value flows into Theme lookup.
    -- Theme:GetTextStateColor / :GetTextStateColorToken consume these.
    TEXT_STATE = {
        Collected        = "collected",
        Uncollected      = "uncollected",
        KnownByCharacter = "known_self",
        KnownByAlt       = "known_alt",
        UnknownOnAccount = "recipe_exists",
        NotARecipe       = "not_a_recipe",
        Success          = "success",
        Warning          = "warning",
        Error            = "error",
        ErrorDeep        = "error_deep",
    },

    -- Atlas per recipe-state for the craft star. Shape AND color both carry the state (colorblind-safe).
    -- All three atlases are line-art over transparent -- SetVertexColor paints cleanly.
    RECIPE_STATE_STAR_ATLAS = {
        known_self    = "tradeskills-star",
        known_alt     = "tradeskills-star-off",
        recipe_exists = "auctionhouse-icon-favorite-off",
    },

    -- Acquire-tab preset chips. SSoT for Selectors, LayoutConfig, Controller, and the reducer.
    -- Single-select source axis; missingOnly is an orthogonal toggle that ANDs with any preset.
    ACQ_PRESETS = {
        { value = "achievement", label = "Achieve"     },
        { value = "reputation",  label = "Rep"         },
        { value = "endeavor",    label = "Endeavor"    },
        { value = "quest",       label = "Quest"       },
        { value = "recipes",     label = "Recipes"     },  -- vendor-level: sells >=1 recipe
    },

    -- ACQ_SOURCES (Advanced Filters > Source dropdown) is DERIVED from SOURCE_KINDS.
    -- See "Acquisition source-filter options" near the bottom of this file.

    -- Views that show the catalog refresh badge and trigger a re-sweep on visit.
    -- NOTE: the INITIAL catalog load is not gated by this set -- it runs on the
    -- first main-window open. View-gating the load left session.catalog.status "idle"
    -- on non-set views until the user happened to visit decor/house.
    -- Keys must match the `view` strings in TABS below.
    CATALOG_CONSUMING_TAB_VIEWS = {
        decor        = true,
        acquisition  = true,
        shoppingList = true,
        zoneScanner  = true,
        houseTab     = true,
    },

    -- Top-level tabs. Each entry maps to a `view` in LayoutConfig.window.views.
    -- Chrome strip generates one button per entry. Adding a tab = one line here + a matching window.views block.
    TABS = {
        { view = "decor",        label = "Decor" },
        { view = "acquisition",  label = "Acquire" },
        { view = "shoppingList", label = "Shopping" },
        { view = "zoneScanner",  label = "Zone" },
        { view = "recipes",      label = "Recipes" },
        { view = "warehouse",    label = "Warehouse" },
        { view = "trainers",     label = "Trainers" },
        { view = "alts",         label = "Alts" },
        { view = "mogul",        label = "Mogul" },
        { view = "styles",       label = "Styles" },
        { view = "houseTab",     label = "House" },
        { view = "projectsLanding",   label = "Projects" },
        { view = "projectsArchitect", label = "Architect" },
        { view = "projectsLayouts",   label = "Layouts" },
        { view = "removalist",        label = "Move Planner" },
        { view = "projectsPicker",    label = "Add Decor" },       -- opened via "+ Add decor"; not in NAV_TREE
        { view = "data",         label = "Your Data" },
        { view = "debug",        label = "Debug" },
        { view = "config",       label = "Config" },
    },

    -- Sidebar nav tree (flat, always-expanded). Generated by LayoutConfig_Nav + wired by Controller_Nav.
    -- Node kinds: home | parent | header | launcher | config | divider.
    -- Child leaf kinds: mode-leaf (dispatches an action, activePath drives highlight) | view-leaf (plain view switch).
    NAV_TREE = {
        { kind = "home",   view = "houseTab", label = "House", icon = "housing-map-plot-player-house" },
        { kind = "divider" },
        { kind = "parent", view = "decor",    label = "Decor", icon = "house-decor-budget-icon" },
        { kind = "parent", view = "acquisition", label = "Acquire", icon = "housing-decor-vendor_32", children = {
            { label = "Shop by Vendor", transient = { view = "acquisition", key = "viewMode", value = "vendor" }, activePath = "session.ui.acquisition.viewMode", activeValue = "vendor" },
            { label = "Find Decor",     transient = { view = "acquisition", key = "viewMode", value = "item"   }, activePath = "session.ui.acquisition.viewMode", activeValue = "item"   },
        }},
        { kind = "parent", view = "recipes", label = "Crafting", icon = "Professions-Crafting-Orders-Icon", children = {
            { label = "Recipes",   view = "recipes" },
            { label = "Warehouse", view = "warehouse" },
            { label = "Trainers",  view = "trainers" },
            { label = "Alts",      view = "alts" },
        }},
        { kind = "parent", view = "mogul", label = "Mogul", icon = "housing-map-deed", children = {
            { label = "Goblin",    action = "MOGUL_SET_SUBVIEW", payload = { subView = "goblin" }, activePath = "session.ui.mogul.subView", activeValue = "goblin" },
            { label = "Optimizer", action = "MOGUL_SET_SUBVIEW", payload = { subView = "mogul"  }, activePath = "session.ui.mogul.subView", activeValue = "mogul"  },
        }},
        { kind = "parent", view = "styles",   label = "Styles", icon = "catalog-palette-icon", children = {
            { label = "Browse",        action = "STYLES_SET_VIEW", payload = { view = "landing"  }, activePath = "session.ui.styles.view", activeValue = "landing"  },
            { label = "Style Curator", action = "STYLES_SET_VIEW", payload = { view = "curator"  }, activePath = "session.ui.styles.view", activeValue = "curator"  },
            { label = "Smart Sets",    action = "STYLES_SET_VIEW", payload = { view = "smartset" }, activePath = "session.ui.styles.view", activeValue = "smartset" },
        }},
        { kind = "parent", view = "projectsLanding", label = "Projects",
          icon = "decor-ability-layoutmode-default", iconActive = "decor-ability-layoutmode-active",
          iconPressed = "decor-ability-layoutmode-pressed", children = {
            { label = "Architect", view = "projectsArchitect" },
            { label = "Layouts",   view = "projectsLayouts" },
            { label = "Move Planner", view = "removalist" },
        }},
        { kind = "divider" },
        -- Tools: a collapsible group (like the hubs above) but with NO navigable
        -- view -- collapseKey "tools" backs its collapse state; noNavigate -> the
        -- label doesn't switch views (only the icon toggles collapse). Children are
        -- launcher (dispatch-only) + config view-switches + the debug-gated row.
        { kind = "parent", collapseKey = "tools", noNavigate = true, label = "Tools",
          icon = "decor-controls-inspect-default", iconActive = "decor-controls-inspect-active",
          iconPressed = "decor-controls-inspect-pressed", children = {
            { label = "Shopping",  launcher = "SHOPPING_WIDGET_TOGGLE" },
            { label = "Zone",      launcher = "ZONE_POPUP_TOGGLE" },
            { label = "Config",    view = "config" },
            { label = "Your Data", view = "data" },
            -- Debug leaf: shown only in debug mode (gatedBy selector -> omitted when false).
            { label = "Debug",     view = "debug", gatedBy = "config.debug" },
        }},
    },

    -- ===== Action types =====
    -- Every dispatched action's `type` must be a value from this table (typos error at load).
    -- Config scope enum (HDG.Config layer). Reducer routes CONFIG_SET to the right SV slot.
    ConfigScope = {
        Profile   = "profile",      -- per-active-profile (default for most settings)
        Character = "character",    -- per-character (keyed by UnitGUID at write time)
        Account   = "account",      -- cross-profile, account-wide (migration flags etc.)
    },

    ACTIONS = {
        CONFIG_SET          = "HDGR_CONFIG_SET",
        CONFIG_SCALE_STEP   = "HDGR_CONFIG_SCALE_STEP",   -- payload: { direction = "inc"|"dec" }
        -- PROFILE_SWITCH triggers a wildcard invalidate (re-keys every Config:Get value).
        PROFILE_CREATE      = "HDGR_PROFILE_CREATE",
        PROFILE_SWITCH      = "HDGR_PROFILE_SWITCH",
        PROFILE_DELETE      = "HDGR_PROFILE_DELETE",
        HARD_RESET          = "HDGR_HARD_RESET",
        COLLECTION_RESET    = "HDGR_COLLECTION_RESET",    -- wipes ownedDecorIDs; triggers fresh sweep
        UI_SET_PERSISTENT   = "HDGR_UI_SET_PERSISTENT",   -- writes account.ui[key]
        UI_SET_TRANSIENT    = "HDGR_UI_SET_TRANSIENT",    -- writes session.ui[key] (or session.ui[view][key] if payload.view)
        REMOVALIST_PICK_PLOT = "HDGR_REMOVALIST_PICK_PLOT", -- Removalist 2-click cycle: source -> target -> restart
        REMOVALIST_SWAP     = "HDGR_REMOVALIST_SWAP",     -- swap source <-> target
        REMOVALIST_CLEAR    = "HDGR_REMOVALIST_CLEAR",    -- clear both picks
        REMOVALIST_SET_LETTER_FILTER = "HDGR_REMOVALIST_SET_LETTER_FILTER", -- filter plot list by A/B/C/D (nil = all)
        REMOVALIST_SET_PLOT = "HDGR_REMOVALIST_SET_PLOT", -- map-click: payload.role "source"/"target" sets that pick
        -- Atomic per-tab filter reset (per ADR-018). payload.tab discriminates which tab.
        UI_FILTER_RESET     = "HDGR_UI_FILTER_RESET",     -- payload: { tab = "decor"|"acquisition"|"recipes" }
        MAIN_WINDOW_TOGGLE  = "HDGR_MAIN_WINDOW_TOGGLE",  -- flips account.ui.mainWindowShown
        NAV_TOGGLE_GROUP    = "HDGR_NAV_TOGGLE_GROUP",     -- payload: { view }; flips account.ui.nav.collapsedGroups[view]
        SESSION_END         = "HDGR_SESSION_END",          -- PLAYER_LOGOUT; reducer closes window

        -- Combat lifecycle (driven by CombatMiddleware via PLAYER_REGEN_*).
        COMBAT_ENTER        = "HDGR_COMBAT_ENTER",
        COMBAT_EXIT         = "HDGR_COMBAT_EXIT",
        -- Reducer-mediated queuing (not direct middleware mutation). COMBAT_EXIT
        -- drains the queue after snapshotting it.
        COMBAT_QUEUE_ACTION = "HDGR_COMBAT_QUEUE_ACTION",

        -- Vendor-view items area view mode. payload: { mode = "grid"|"list" }.
        ACQ_SET_ITEMS_VIEW_MODE = "HDGR_ACQ_SET_ITEMS_VIEW_MODE",

        -- Source-preset chip strip. Single-select; dispatching the active preset deselects.
        ACQ_SET_PRESET              = "HDGR_ACQ_SET_PRESET",
        ACQ_TOGGLE_ADVANCED_FILTERS = "HDGR_ACQ_TOGGLE_ADVANCED_FILTERS",
        -- Missing toggle is orthogonal to ACQ_SET_PRESET (ANDs with active source).
        ACQ_TOGGLE_MISSING          = "HDGR_ACQ_TOGGLE_MISSING",
        -- Advanced-filter multi-select toggles. payload: { <axis> = value }; value=="all"
        -- clears the axis set (empty set = "All"). Clone of RECIPES_TOGGLE_EXPANSION.
        ACQ_TOGGLE_EXPANSION        = "HDGR_ACQ_TOGGLE_EXPANSION",   -- payload: { expansion }
        ACQ_TOGGLE_ZONE             = "HDGR_ACQ_TOGGLE_ZONE",        -- payload: { zone }
        ACQ_TOGGLE_REP              = "HDGR_ACQ_TOGGLE_REP",         -- payload: { rep }
        ACQ_TOGGLE_SOURCE           = "HDGR_ACQ_TOGGLE_SOURCE",      -- payload: { source }
        ACQ_TOGGLE_FACTION          = "HDGR_ACQ_TOGGLE_FACTION",     -- payload: { faction }

        -- ===== Structured logging =====
        LOG_PUSH            = "HDGR_LOG_PUSH",            -- payload: { tag, level, text, timestamp, duration, metadata }
        LOG_CLEAR           = "HDGR_LOG_CLEAR",           -- payload: { tag? }  (omit = clear all)
        LOG_SET_FILTER      = "HDGR_LOG_SET_FILTER",      -- payload: { tag?, level?, autoScroll? }
        LOG_TOGGLE_AUTOSCROLL = "HDGR_LOG_TOGGLE_AUTOSCROLL",
        LOG_TRACE_TOGGLE    = "HDGR_LOG_TRACE_TOGGLE",    -- payload: { tag, on }  (tag="*" disables all)

        -- ===== Catalog reconciliation =====
        -- Fine-grained mutations dispatched by HousingCatalogObserver (per ADR-012).
        -- Hot UI actions never invalidate the catalog cache.
        COLLECTION_BULK_LOAD           = "HDGR_COLLECTION_BULK_LOAD",           -- payload: { owned, swept_at, clientVer, catalogSchemaVersion }
        COLLECTION_ITEM_LEARNED        = "HDGR_COLLECTION_ITEM_LEARNED",        -- payload: { decorID }
        COLLECTION_ITEM_REMOVED        = "HDGR_COLLECTION_ITEM_REMOVED",        -- payload: { decorID }
        COLLECTION_CATALOG_ROW_ADDED   = "HDGR_COLLECTION_CATALOG_ROW_ADDED",   -- payload: { decorID, entry }
        COLLECTION_CATALOG_ROW_REMOVED = "HDGR_COLLECTION_CATALOG_ROW_REMOVED", -- payload: { decorID }
        -- Mutable count fields changed; static row fields stay. Reducer patches 6 fields in place.
        COLLECTION_CATALOG_ROW_COUNTS_UPDATED = "HDGR_COLLECTION_CATALOG_ROW_COUNTS_UPDATED", -- payload: { decorID, counts = { quantity, numPlaced, numStored, remainingRedeemable, destroyableInstanceCount, firstAcquisitionBonus } }

        -- Pure signal: catalog searcher results hot; BindingEngine re-resolves modelPreview bindings.
        DECOR_CATALOG_READY = "HDGR_DECOR_CATALOG_READY",

        -- ===== Filter + collection actions =====
        DECOR_SET_TOP_FILTER          = "HDGR_DECOR_SET_TOP_FILTER",   -- payload: { value = "all"|... }
        DECOR_SET_TAG                 = "HDGR_DECOR_SET_TAG",           -- payload: { tag = string|nil }
        DECOR_TOGGLE_ONLY_UNCOLLECTED = "HDGR_DECOR_TOGGLE_ONLY_UNCOLLECTED",
        DECOR_TOGGLE_ONLY_STORED      = "HDGR_DECOR_TOGGLE_ONLY_STORED",
        DECOR_SET_SEARCH              = "HDGR_DECOR_SET_SEARCH",        -- payload: { query = string }
        FAVORITE_TOGGLE               = "HDGR_FAVORITE_TOGGLE",         -- payload: { itemID }
        NOTE_SET                      = "HDGR_NOTE_SET",                -- payload: { itemID, text, ts? }
        NOTE_CLEAR                    = "HDGR_NOTE_CLEAR",              -- payload: { itemID }
        VENDOR_NOTE_SET               = "HDGR_VENDOR_NOTE_SET",         -- payload: { npcID, text, ts? }
        VENDOR_NOTE_CLEAR             = "HDGR_VENDOR_NOTE_CLEAR",       -- payload: { npcID }
        -- payload: { entries = { [itemID] = { spellID, selfKnown, altKnown } } }
        RECIPE_KNOWLEDGE_UPDATED   = "HDGR_RECIPE_KNOWLEDGE_UPDATED",

        -- ===== Per-character roster (alts data layer) ===============
        -- account.characters[charKey] holds per-char professions + known recipes.
        -- CHARACTER_PROFESSION_UPDATED payload: { charKey, name, realm, class, classFile, profName,
        --   skillLines = { [expName] = { current, max } }, knownRecipes = { [recipeID] = true } }
        CHARACTER_PROFESSION_UPDATED = "HDGR_CHARACTER_PROFESSION_UPDATED",
        CHARACTER_DELETED            = "HDGR_CHARACTER_DELETED",            -- payload: { charKey }
        CHARACTER_HIDDEN             = "HDGR_CHARACTER_HIDDEN",             -- payload: { charKey, hidden }
        CHARACTER_HIDDEN_TOGGLE      = "HDGR_CHARACTER_HIDDEN_TOGGLE",      -- payload: { charKey }

        -- Pure signal; gated modules (CollectionReconciler, BagObserver) catch up after sleeping.
        MAIN_WINDOW_OPENING          = "HDGR_MAIN_WINDOW_OPENING",

        ALTS_SET_CHARS_POPULATION    = "HDGR_ALTS_SET_CHARS_POPULATION",  -- payload: { population = "active"|"hidden" }

        -- ===== HouseTab dashboard =====
        HOUSE_SNAPSHOT_UPDATED          = "HDGR_HOUSE_SNAPSHOT_UPDATED",          -- payload: { snapshot = table }
        HOUSE_LIST_UPDATED              = "HDGR_HOUSE_LIST_UPDATED",              -- payload: { houses = [{houseGUID, neighborhoodName, faction, ...}] }
        HOUSE_LEVEL_UPDATED             = "HDGR_HOUSE_LEVEL_UPDATED",             -- payload: { houseGUID, level, favor, maxLevel, thresholds }
        ACTIVE_NEIGHBORHOOD_UPDATED     = "HDGR_ACTIVE_NEIGHBORHOOD_UPDATED",     -- payload: { neighborhoodGUID = string|nil }
        HOUSE_REWARDS_RECEIVED          = "HDGR_HOUSE_REWARDS_RECEIVED",          -- payload: { level, rewards = {...} }
        DAILY_BESTOWED_UPDATED          = "HDGR_DAILY_BESTOWED_UPDATED",          -- payload: { name, quote, dateKey }
        DAILY_ORC_QUOTE_SET             = "HDGR_DAILY_ORC_QUOTE_SET",             -- payload: { quote = string }
        -- Account-side layout customizations. Persist across sessions; nil = use WIDGET_DEFAULTS.
        HOUSETAB_TOGGLE_WIDGET          = "HDGR_HOUSETAB_TOGGLE_WIDGET",          -- payload: { widgetID = string }
        HOUSETAB_SET_ORDER              = "HDGR_HOUSETAB_SET_ORDER",              -- payload: { widgetID = string, order = number }
        HOUSETAB_SET_ORDERS             = "HDGR_HOUSETAB_SET_ORDERS",             -- payload: { orders = { [widgetID] = number } }  -- bulk replace
        HOUSETAB_REORDER_WIDGET         = "HDGR_HOUSETAB_REORDER_WIDGET",         -- payload: { orderedIDs = {id,...}, srcID, insertIdx }
        HOUSETAB_SET_WIDTH              = "HDGR_HOUSETAB_SET_WIDTH",              -- payload: { widgetID = string, width = "third"|"twoThirds"|"full" }
        HOUSETAB_RESIZE_WIDGET          = "HDGR_HOUSETAB_RESIZE_WIDGET",          -- payload: { widgetID = string, height = number }
        HOUSETAB_RESET_LAYOUT           = "HDGR_HOUSETAB_RESET_LAYOUT",
        HOUSETAB_TOGGLE_PICKER          = "HDGR_HOUSETAB_TOGGLE_PICKER",
        HOUSETAB_TOGGLE_DESIGN_MODE     = "HDGR_HOUSETAB_TOGGLE_DESIGN_MODE",

        -- ===== HouseEditor companion =====
        -- Taint-safe standalone window; parents to HouseEditorFrame for visibility cascade.
        COMPANION_TOGGLE             = "HDGR_COMPANION_TOGGLE",
        COMPANION_SET_MODE           = "HDGR_COMPANION_SET_MODE",           -- payload: { mode = "styles"|"shopping"|"snapshots"|"themes"|"collections"|"recent" }
        COMPANION_SELECT_ITEM        = "HDGR_COMPANION_SELECT_ITEM",        -- payload: { itemID = number|string }
        COMPANION_SET_POSITION       = "HDGR_COMPANION_SET_POSITION",       -- payload: { x, y } -- persists window placement
        COMPANION_TOGGLE_COST        = "HDGR_COMPANION_TOGGLE_COST",        -- flips the cost-badge visibility
        COMPANION_CYCLE_IO           = "HDGR_COMPANION_CYCLE_IO",           -- cycles ioFilter all->indoor->outdoor
        COMPANION_SET_LAUNCHER_POSITION = "HDGR_COMPANION_SET_LAUNCHER_POSITION", -- payload: { x, y }

        -- Once per session; lets all consumers read strictly instead of calling UnitName/GetRealmName/UnitClass independently.
        SESSION_IDENTITY_SET         = "HDGR_SESSION_IDENTITY_SET",         -- payload: { name, realm, class, classFile }; reducer computes charKey

        -- ===== Trainers tab =====
        TRAINERS_TOGGLE_PROFESSION       = "HDGR_TRAINERS_TOGGLE_PROFESSION",       -- payload: { profession = string }
        TRAINERS_TOGGLE_MIDNIGHT_SECTION = "HDGR_TRAINERS_TOGGLE_MIDNIGHT_SECTION",
        TRAINERS_SELECT_TRAINER          = "HDGR_TRAINERS_SELECT_TRAINER",          -- payload: { npcID = number }

        -- Mogul tab UI state (mode = "profit"|"collection"; viewMode = "char"|"account"; optimizeBy).
        MOGUL_SET_MODE               = "HDGR_MOGUL_SET_MODE",
        MOGUL_SET_VIEW               = "HDGR_MOGUL_SET_VIEW",
        MOGUL_SET_OPTIMIZE_BY        = "HDGR_MOGUL_SET_OPTIMIZE_BY",
        MOGUL_SET_SUBVIEW            = "HDGR_MOGUL_SET_SUBVIEW",           -- payload: { subView = "mogul"|"goblin"|"config" }
        -- Supply Impact: mode = "off"|"smooth"|"cap"
        MOGUL_SET_SUPPLY_MODE        = "HDGR_MOGUL_SET_SUPPLY_MODE",
        MOGUL_SET_SUPPLY_SMOOTH      = "HDGR_MOGUL_SET_SUPPLY_SMOOTH",     -- payload: { pct = number }
        MOGUL_SET_SUPPLY_CAP         = "HDGR_MOGUL_SET_SUPPLY_CAP",        -- payload: { n = number }
        -- Frugal mode: bias planner toward low-lumber crafts.
        MOGUL_SET_FRUGAL             = "HDGR_MOGUL_SET_FRUGAL",            -- payload: { on = bool }
        MOGUL_TOGGLE_FRUGAL          = "HDGR_MOGUL_TOGGLE_FRUGAL",
        -- ===== Goblin sub-view =====
        GOBLIN_SET_PROFESSION        = "HDGR_GOBLIN_SET_PROFESSION",
        GOBLIN_SET_SEARCH            = "HDGR_GOBLIN_SET_SEARCH",
        GOBLIN_SET_KNOWLEDGE         = "HDGR_GOBLIN_SET_KNOWLEDGE",        -- payload: { mode = "all"|"known"|"alt" }
        GOBLIN_SET_QUEUE             = "HDGR_GOBLIN_SET_QUEUE",            -- payload: { mode = "all"|"only"|"hide" }
        GOBLIN_TOGGLE_AUCTIONS       = "HDGR_GOBLIN_TOGGLE_AUCTIONS",
        GOBLIN_SET_SORT              = "HDGR_GOBLIN_SET_SORT",             -- payload: { col = "name"|"lumber"|... }
        GOBLIN_TOGGLE_ROW_EXPAND     = "HDGR_GOBLIN_TOGGLE_ROW_EXPAND",   -- payload: { itemID }
        PRICES_SET_PREFERRED_SOURCE  = "HDGR_PRICES_SET_PREFERRED_SOURCE", -- payload: { source = "TSM"|"Auctionator"|"Direct"|nil }
        PRICES_SET_TSM_MODE          = "HDGR_PRICES_SET_TSM_MODE",         -- payload: { mode = "min"|"market"|"region" }

        -- ===== Crafting queue + history =====
        -- CRAFT_QUEUE_DECREMENT matches by (position, recipeID) -- both needed for uniqueness.
        CRAFT_QUEUE_ADD       = "HDGR_CRAFT_QUEUE_ADD",       -- payload: { recipeID, itemID, qty }
        CRAFT_QUEUE_REMOVE    = "HDGR_CRAFT_QUEUE_REMOVE",    -- payload: { position }
        CRAFT_QUEUE_CLEAR     = "HDGR_CRAFT_QUEUE_CLEAR",
        CRAFT_QUEUE_DECREMENT = "HDGR_CRAFT_QUEUE_DECREMENT", -- payload: { recipeID, qty, position }
        -- `completed` field guards against phantom entries from multi-craft DECREMENT no-ops.
        CRAFT_HISTORY_PUSH    = "HDGR_CRAFT_HISTORY_PUSH",    -- payload: { eventType, recipeID, itemID, qty, completed, timestamp? }
        LUMBER_HISTORY_PUSH   = "HDGR_LUMBER_HISTORY_PUSH",   -- payload: { lumberID, charKey, startedAt, finalizedAt, sessionTotal, zone?, character?, realm? }

        -- ===== Recipes tab session UI =====
        RECIPES_TOGGLE_PROFESSION  = "HDGR_RECIPES_TOGGLE_PROFESSION",  -- payload: { profession = <name>|"all" }
        RECIPES_TOGGLE_EXPANSION   = "HDGR_RECIPES_TOGGLE_EXPANSION",   -- payload: { expansion = <display>|"all" }
        -- filter chips: "all"|"known"|"ready"
        RECIPES_SET_LIST_FILTER    = "HDGR_RECIPES_SET_LIST_FILTER",    -- payload: { filter }
        RECIPES_SELECT_MATERIAL     = "HDGR_RECIPES_SELECT_MATERIAL",    -- payload: { itemID|nil }
        RECIPES_SET_WH_MAT_SEARCH   = "HDGR_RECIPES_SET_WH_MAT_SEARCH",  -- payload: { query }
        RECIPES_SET_SEARCH         = "HDGR_RECIPES_SET_SEARCH",         -- payload: { query }
        RECIPES_SET_SECTION_EXPAND = "HDGR_RECIPES_SET_SECTION_EXPAND", -- payload: { key, expanded }
        RECIPES_SET_MATERIALS_DEPTH       = "HDGR_RECIPES_SET_MATERIALS_DEPTH",       -- payload: { value = "direct"|"raw" }
        RECIPES_TOGGLE_MATERIALS_GROUPING = "HDGR_RECIPES_TOGGLE_MATERIALS_GROUPING",
        RECIPES_TOGGLE_FILTER      = "HDGR_RECIPES_TOGGLE_FILTER",      -- payload: { filter }
        RECIPES_SELECT_RECIPE      = "HDGR_RECIPES_SELECT_RECIPE",      -- payload: { recipeID }
        -- Queue-row toggle: nil if recipeID matches current, else set. Scopes the materials list when set.
        RECIPES_TOGGLE_QUEUE_SELECTION = "HDGR_RECIPES_TOGGLE_QUEUE_SELECTION", -- payload: { recipeID }

        -- ===== Cross-feature observer dispatches =====
        -- Bulk payload avoids per-item dispatch spam in debug mode.
        ITEM_INFO_RESOLVED         = "HDGR_ITEM_INFO_RESOLVED",         -- payload: { itemIDs = { [n] = itemID }, count = n }
        QUEST_INFO_RESOLVED        = "HDGR_QUEST_INFO_RESOLVED",        -- payload: { questIDs, titles = { [questID]=title }, count }
        QUEST_STATUS_RESOLVED      = "HDGR_QUEST_STATUS_RESOLVED",      -- payload: { questID = N }
        -- First character to record a completion wins; stored account-wide.
        QUEST_COMPLETION_RECORDED  = "HDGR_QUEST_COMPLETION_RECORDED",  -- payload: { completions = { [questID]={name,class} } }
        ACHIEVEMENT_STATUS_RESOLVED = "HDGR_ACHIEVEMENT_STATUS_RESOLVED", -- payload: { achievementID = N }
        BAG_INVENTORY_UPDATED      = "HDGR_BAG_INVENTORY_UPDATED",      -- payload: { tick }

        -- ===== PriceSource =====
        PRICES_CONFIG_CHANGED         = "HDGR_PRICES_CONFIG_CHANGED",
        PRICES_DIRECT_SCAN_STARTED    = "HDGR_PRICES_DIRECT_SCAN_STARTED",  -- payload: { total }
        PRICES_DIRECT_SCAN_PROGRESS   = "HDGR_PRICES_DIRECT_SCAN_PROGRESS", -- payload: { found, total }
        PRICES_DIRECT_SCAN_BATCH      = "HDGR_PRICES_DIRECT_SCAN_BATCH",    -- payload: { prices = { [itemID] = copper } }
        PRICES_DIRECT_SCAN_COMPLETED  = "HDGR_PRICES_DIRECT_SCAN_COMPLETED",-- payload: { neededItems = {[itemID]=true}, now = ts }
        PRICES_DIRECT_CACHE_CLEARED   = "HDGR_PRICES_DIRECT_CACHE_CLEARED",
        PRICES_OWNED_AUCTIONS_UPDATED = "HDGR_PRICES_OWNED_AUCTIONS_UPDATED",-- payload: { auctions = { [itemID] = { qty, buyout } } }
        -- Written on MAIN_WINDOW_OPENING + ToggleMockTSM so Config selectors stay pure.
        PRICES_ADDONS_AVAILABILITY_CHANGED = "HDGR_PRICES_ADDONS_AVAILABILITY_CHANGED",-- payload: { tsm = bool, auctionator = bool }

        -- ===== Styles =====
        STYLES_SET_VIEW              = "HDGR_STYLES_SET_VIEW",              -- payload: { view = "landing"|"detail"|"curator"|"smartset"|"import" }
        STYLES_INVALIDATE_CACHE      = "HDGR_STYLES_INVALIDATE_CACHE",
        STYLES_LANDING_SET_FILTER    = "HDGR_STYLES_LANDING_SET_FILTER",    -- payload: { filter = "all"|"style"|"smartset"|"shopping"|"snapshot"|"concept"|"collection" }
        STYLES_LANDING_SET_SEARCH    = "HDGR_STYLES_LANDING_SET_SEARCH",    -- payload: { text = string }
        STYLES_LANDING_TOGGLE_SECTION = "HDGR_STYLES_LANDING_TOGGLE_SECTION", -- payload: { type = string }
        STYLES_SELECT_COLLECTION     = "HDGR_STYLES_SELECT_COLLECTION",     -- payload: { collectionID = string }
        STYLES_DETAIL_SELECT_ITEM    = "HDGR_STYLES_DETAIL_SELECT_ITEM",    -- payload: { itemID = number }
        STYLES_DETAIL_SET_SEARCH     = "HDGR_STYLES_DETAIL_SET_SEARCH",     -- payload: { text = string }
        STYLES_DETAIL_SET_VIEWMODE       = "HDGR_STYLES_DETAIL_SET_VIEWMODE",       -- payload: { mode = "list"|"cards"|"split" }
        STYLES_DETAIL_SET_FILTER         = "HDGR_STYLES_DETAIL_SET_FILTER",         -- payload: { source = "all"|"vendor"|"recipe"|... }
        STYLES_DETAIL_SET_SUBCAT         = "HDGR_STYLES_DETAIL_SET_SUBCAT",         -- payload: { subcat = "all"|<subcategoryID> }
        STYLES_INVALIDATE_STYLE          = "HDGR_STYLES_INVALIDATE_STYLE",          -- payload: { collectionID = string }
        STYLES_CACHE_BUILDING_STARTED    = "HDGR_STYLES_CACHE_BUILDING_STARTED",    -- payload: { collectionID = string? }
        STYLES_CACHE_BUILDING_FINISHED   = "HDGR_STYLES_CACHE_BUILDING_FINISHED",   -- payload: { collectionID = string?, durationMs = number? }
        STYLES_CURATOR_SET_SOURCE    = "HDGR_STYLES_CURATOR_SET_SOURCE",    -- payload: { mode = "unassigned"|"all"|"style:<id>" }
        STYLES_CURATOR_SET_CATEGORY  = "HDGR_STYLES_CURATOR_SET_CATEGORY",  -- payload: { categoryID = number|nil }
        STYLES_CURATOR_SET_SUBCATEGORY = "HDGR_STYLES_CURATOR_SET_SUBCATEGORY", -- payload: { subcategoryID = number|nil }
        STYLES_CURATOR_TOGGLE_SELECT = "HDGR_STYLES_CURATOR_TOGGLE_SELECT", -- payload: { itemID = number }
        STYLES_CURATOR_CLEAR_SELECT  = "HDGR_STYLES_CURATOR_CLEAR_SELECT",
        STYLES_CURATOR_MOVE          = "HDGR_STYLES_CURATOR_MOVE",          -- payload: { targetID = string }
        STYLES_CURATOR_UNDO          = "HDGR_STYLES_CURATOR_UNDO",
        STYLES_CURATOR_UNDO_AT       = "HDGR_STYLES_CURATOR_UNDO_AT",       -- payload: { ord = N } -- cascade-undo from top to ord
        STYLES_CURATOR_HOVER         = "HDGR_STYLES_CURATOR_HOVER",         -- payload: { itemID = number? }
        STYLES_CURATOR_SELECT_TARGET = "HDGR_STYLES_CURATOR_SELECT_TARGET", -- payload: { targetID = string? }
        STYLES_CREATE_STYLE          = "HDGR_STYLES_CREATE_STYLE",          -- payload: { displayName = string }
        STYLES_RENAME_STYLE          = "HDGR_STYLES_RENAME_STYLE",          -- payload: { collectionID, displayName }
        STYLES_DUPLICATE_STYLE       = "HDGR_STYLES_DUPLICATE_STYLE",       -- payload: { collectionID }
        STYLES_DELETE_STYLE          = "HDGR_STYLES_DELETE_STYLE",          -- payload: { collectionID }
        -- Export is a controller side-effect; Delete reuses STYLES_DELETE_STYLE.
        STYLES_EDIT_STYLE            = "HDGR_STYLES_EDIT_STYLE",            -- payload: { collectionID }
        STYLES_SMARTSET_BEGIN          = "HDGR_STYLES_SMARTSET_BEGIN",          -- payload: { id? = string }
        STYLES_SMARTSET_SET_FIELD      = "HDGR_STYLES_SMARTSET_SET_FIELD",      -- payload: { field = "displayName"|"description", value = string }
        STYLES_SMARTSET_SET_AXIS       = "HDGR_STYLES_SMARTSET_SET_AXIS",       -- payload: { axis = string }
        STYLES_SMARTSET_SET_SEVERITY_TAB = "HDGR_STYLES_SMARTSET_SET_SEVERITY_TAB", -- payload: { sev = "all"|"signature"|"accent"|"versatile"|"clashing" }
        STYLES_SMARTSET_TOGGLE_TAG     = "HDGR_STYLES_SMARTSET_TOGGLE_TAG",     -- payload: { axis, tag, severity }
        STYLES_SMARTSET_CLEAR_ALL      = "HDGR_STYLES_SMARTSET_CLEAR_ALL",
        STYLES_SMARTSET_SAVE           = "HDGR_STYLES_SMARTSET_SAVE",
        STYLES_SMARTSET_CANCEL         = "HDGR_STYLES_SMARTSET_CANCEL",
        STYLES_SNAPSHOT_PLACED         = "HDGR_STYLES_SNAPSHOT_PLACED",         -- payload: { items=[itemID...], takenAt, displayName }
        STYLES_PLACED_DECOR_OBSERVED       = "HDGR_STYLES_PLACED_DECOR_OBSERVED",       -- payload: { decorGUID, decorID, itemID?, name? }
        STYLES_PLACED_DECOR_OBSERVED_BATCH = "HDGR_STYLES_PLACED_DECOR_OBSERVED_BATCH", -- payload: { entries = [{decorGUID, decorID, itemID?, name?}] }
        STYLES_PLACED_DECOR_REMOVED        = "HDGR_STYLES_PLACED_DECOR_REMOVED",        -- payload: { decorGUID } -- also appends a "removed" RecentActivity event
        STYLES_PLACED_DECOR_CLEAR          = "HDGR_STYLES_PLACED_DECOR_CLEAR",
        -- Recent Activity: persisted per-house edit-session history.
        RECENT_SESSION_START           = "HDGR_RECENT_SESSION_START",           -- payload: { houseKey }
        RECENT_DECOR_PLACED            = "HDGR_RECENT_DECOR_PLACED",            -- payload: { houseKey, itemID }
        STYLES_IMPORT_SET_URL          = "HDGR_STYLES_IMPORT_SET_URL",          -- payload: { text = string }
        STYLES_IMPORT_PARSE            = "HDGR_STYLES_IMPORT_PARSE",
        STYLES_IMPORT_COMMIT           = "HDGR_STYLES_IMPORT_COMMIT",           -- payload: { displayName? = string }
        STYLES_IMPORT_RESET            = "HDGR_STYLES_IMPORT_RESET",
        COLLECTION_STYLE_ITEM_ADDED  = "HDGR_COLLECTION_STYLE_ITEM_ADDED",  -- payload: { collectionID, itemID }
        COLLECTION_STYLE_ITEM_REMOVED = "HDGR_COLLECTION_STYLE_ITEM_REMOVED",-- payload: { collectionID, itemID }

        -- ===== Shopping list =====
        -- List IDs are monotonic "L1"/"L2"/... from shoppingListSeq. listID optional on item-scoped actions.
        SHOPPING_LIST_CREATE       = "HDGR_SHOPPING_LIST_CREATE",       -- payload: { name }
        SHOPPING_LIST_DELETE       = "HDGR_SHOPPING_LIST_DELETE",       -- payload: { id }
        SHOPPING_LIST_RENAME       = "HDGR_SHOPPING_LIST_RENAME",       -- payload: { id, name }
        SHOPPING_LIST_DUPLICATE    = "HDGR_SHOPPING_LIST_DUPLICATE",    -- payload: { id, name? }
        SHOPPING_LIST_ACTIVATE     = "HDGR_SHOPPING_LIST_ACTIVATE",     -- payload: { id }
        SHOPPING_LIST_CLEAR        = "HDGR_SHOPPING_LIST_CLEAR",        -- payload: { id }
        SHOPPING_LIST_SET_META     = "HDGR_SHOPPING_LIST_SET_META",     -- payload: { id, key, value }
        SHOPPING_LIST_IMPORT       = "HDGR_SHOPPING_LIST_IMPORT",       -- payload: { encoded }
        SHOPPING_ITEM_ADD          = "HDGR_SHOPPING_ITEM_ADD",          -- payload: { listID?, itemID, npcID?, qty? }
        SHOPPING_TOGGLE_EXPANDED   = "HDGR_SHOPPING_TOGGLE_EXPANDED",   -- payload: { bucket = "zones"|"vendors"|"wishList", key? }
        SHOPPING_ITEM_REMOVE       = "HDGR_SHOPPING_ITEM_REMOVE",       -- payload: { listID?, itemID, npcID? }
        SHOPPING_ITEM_SET_QTY      = "HDGR_SHOPPING_ITEM_SET_QTY",      -- payload: { listID?, itemID, npcID?, qty }  (absolute; EditBox direct entry)
        SHOPPING_ITEM_ADJUST_QTY   = "HDGR_SHOPPING_ITEM_ADJUST_QTY",   -- payload: { listID?, itemID, npcID?, delta }  (relative; +/- buttons, removes at <=0)
        SHOPPING_RESOLVE_VENDORS   = "HDGR_SHOPPING_RESOLVE_VENDORS",   -- payload: { listID, resolutions = {[itemID]=npcID} }
        SHOPPING_WIDGET_TOGGLE     = "HDGR_SHOPPING_WIDGET_TOGGLE",

        -- ===== Zone Scanner =====
        -- ZONE_CHANGED dispatched by ZoneObserver after debouncing ZONE_CHANGED_NEW_AREA.
        ZONE_CHANGED               = "HDGR_ZONE_CHANGED",               -- payload: { mapID }
        ZONE_POPUP_TOGGLE          = "HDGR_ZONE_POPUP_TOGGLE",
        ZONE_TOGGLE_VENDOR         = "HDGR_ZONE_TOGGLE_VENDOR",         -- payload: { npcID }
        ZONE_SET_SEARCH            = "HDGR_ZONE_SET_SEARCH",            -- payload: { text }
        ZONE_TOGGLE_COLLECTED      = "HDGR_ZONE_TOGGLE_COLLECTED",

        -- ===== Lumber Tracker =====
        -- BLIP_GC: periodic sweep that drops blips older than the respawn window.
        LUMBER_HARVESTED            = "HDGR_LUMBER_HARVESTED",            -- payload: { lumberID, qty, x, y, mapID, timestamp }
        LUMBER_SESSION_START        = "HDGR_LUMBER_SESSION_START",        -- payload: { lumberID, timestamp, startCount }
        LUMBER_SESSION_END          = "HDGR_LUMBER_SESSION_END",
        LUMBER_BLIP_GC              = "HDGR_LUMBER_BLIP_GC",              -- payload: { now }
        LUMBER_WINDOW_TOGGLE        = "HDGR_LUMBER_WINDOW_TOGGLE",        -- payload: { visible }
        LUMBER_WINDOW_POSITION_SET  = "HDGR_LUMBER_WINDOW_POSITION_SET",  -- payload: { x, y }
        LUMBER_RADAR_COLLAPSE_TOGGLE = "HDGR_LUMBER_RADAR_COLLAPSE_TOGGLE",
        LUMBER_AUTOSHOW_TOGGLE      = "HDGR_LUMBER_AUTOSHOW_TOGGLE",      -- toggle account.lumber.config.autoShowOnHarvest
        LUMBER_RADAR_SCALE_SET      = "HDGR_LUMBER_RADAR_SCALE_SET",      -- payload: { scale } (0.5..2.0)
        LUMBER_LIST_COLLAPSE_TOGGLE = "HDGR_LUMBER_LIST_COLLAPSE_TOGGLE",
        LUMBER_TICK                 = "HDGR_LUMBER_TICK",                 -- 1s heartbeat while farming; bumps session.lumber.tick
        REP_PROGRESS_TICK           = "HDGR_REP_PROGRESS_TICK",           -- UPDATE_FACTION/renown; bumps session.resolvers.rep.tick

        -- ===== Catalog lifecycle =====
        CATALOG_LOAD_REQUESTED    = "HDGR_CATALOG_LOAD_REQUESTED",
        CATALOG_LOAD_COMPLETED    = "HDGR_CATALOG_LOAD_COMPLETED",    -- payload: { rowCount }
        CATALOG_LOAD_FAILED       = "HDGR_CATALOG_LOAD_FAILED",       -- payload: { reason }
        CATALOG_REFRESH_QUEUED    = "HDGR_CATALOG_REFRESH_QUEUED",
        CATALOG_REFRESH_COMPLETED = "HDGR_CATALOG_REFRESH_COMPLETED", -- payload: { rowCount }
        -- Blizzard category/subcategory nav tree; shared by Style Curator + Projects decor picker.
        CATALOG_CATEGORY_TREE_UPDATED = "HDGR_CATALOG_CATEGORY_TREE_UPDATED", -- payload: { byID, subcatByID, rootIDs }
        CATALOG_VARIANTS_LOADED   = "HDGR_CATALOG_VARIANTS_LOADED",   -- payload: { count }
        CATALOG_VINTAGE_UPDATE    = "HDGR_CATALOG_VINTAGE_UPDATE",    -- payload: { ids = {itemID,...}, build, label, isSeed } -- observer snapshot diff; drives "New in <patch>" chip

        UI_SET_VIEW               = "HDGR_UI_SET_VIEW",  -- payload: { view }

        -- ===== Projects: house topology =====
        -- house -> version -> room model. EDITOR writers carry versionID; CAPTURE writers carry houseID.
        PROJECTS_UPSERT_HOUSE      = "HDGR_PROJECTS_UPSERT_HOUSE",      -- payload: { houseID, fields }
        -- Multi-floor rooms (stairs/tall=2, garden=3) are ONE record; FloorMap derives the
        -- vertical span + projects it up. "Expand stairwell" sets a per-placement `floors` override (LAYOUT_MOVE).
        PROJECTS_SET_ACTIVE_VERSION = "HDGR_PROJECTS_SET_ACTIVE_VERSION", -- payload: { houseID, versionID }
        PROJECTS_CREATE_VERSION    = "HDGR_PROJECTS_CREATE_VERSION",    -- payload: { houseID, versionID, name?, basedOn?, createdAt? }
        PROJECTS_DELETE_VERSION    = "HDGR_PROJECTS_DELETE_VERSION",    -- payload: { houseID, versionID, ts? }
        PROJECTS_CAPTURE_COMMIT    = "HDGR_PROJECTS_CAPTURE_COMMIT",    -- payload: { houseID, rooms, deleteRoomIDs, lastCapturedAt }
        PROJECTS_HOUSE_TICK        = "HDGR_PROJECTS_HOUSE_TICK",        -- payload: { budget?, numFloors?, editorActive? }
        PROJECTS_ROOM_CATALOG_UPDATED = "HDGR_PROJECTS_ROOM_CATALOG_UPDATED", -- payload: { byShapeID, entries }
        PROJECTS_CLEAR_HOUSE       = "HDGR_PROJECTS_CLEAR_HOUSE",       -- payload: { houseID, maxFloor? } (v8 recapture prep: prune capture-owned placements above maxFloor + reset echo; tags survive)
        PROJECTS_SET_VERSION_FLOORS = "HDGR_PROJECTS_SET_VERSION_FLOORS", -- payload: { versionID, numFloors }
        PROJECTS_RENAME_VERSION    = "HDGR_PROJECTS_RENAME_VERSION",    -- payload: { versionID, name }
        PROJECTS_IMPORT_LAYOUT     = "HDGR_PROJECTS_IMPORT_LAYOUT",     -- payload: { houseID, version, houseName? } (controller-built record; reducer mints id + activates; houseName stamps an uncaptured house)
        PROJECTS_FOCUS_HOUSE       = "HDGR_PROJECTS_FOCUS_HOUSE",       -- payload: { houseID } (which house the Architect/Projects views focus)
        PROJECTS_PICKER_SET_SOURCE = "HDGR_PROJECTS_PICKER_SET_SOURCE", -- payload: { source } ("all" | "style:<id>" | "shop:<id>")
        PROJECTS_FURN_TOGGLE_COLLAPSE = "HDGR_PROJECTS_FURN_TOGGLE_COLLAPSE", -- payload: { setID } (fold/unfold a set group in the room detail)

        -- ===== Projects: shipping crates =====
        -- Whole-house manifest snapshot. Controller builds the record; reducer just writes it.
        SHIPPING_CRATE_PACK        = "HDGR_SHIPPING_CRATE_PACK",        -- payload: { shipID, record }
        SHIPPING_CRATE_DELETE      = "HDGR_SHIPPING_CRATE_DELETE",      -- payload: { shipID }

        -- ===== Furnishings (v7 model: docs/crate-redesign/10-FINAL-MODEL.md) =====
        -- Sets are free-standing quantified plans; rooms are persistent identities;
        -- layouts hold placements. IDs counter-minted reducer-side (set:N / room:N / slot:N).
        FURN_SET_CREATE            = "HDGR_FURN_SET_CREATE",            -- payload: { name, items?, isLocal?, ownerRoom? }
        FURN_SET_RENAME            = "HDGR_FURN_SET_RENAME",            -- payload: { setID, name }
        FURN_SET_DELETE            = "HDGR_FURN_SET_DELETE",            -- payload: { setID } (cascades out of every room's equip list)
        FURN_SET_ITEM_ADD          = "HDGR_FURN_SET_ITEM_ADD",          -- payload: { setID, itemID, count? } (count sets; absent increments)
        FURN_SET_ITEM_REMOVE       = "HDGR_FURN_SET_ITEM_REMOVE",       -- payload: { setID, itemID, all? } (decrement; 0 or all removes)
        FURN_SET_PROMOTE           = "HDGR_FURN_SET_PROMOTE",           -- payload: { setID, name } (local -> library)
        FURN_ROOM_CREATE           = "HDGR_FURN_ROOM_CREATE",           -- payload: { shape, name?, layoutID?, slotKey? } (slotKey: create-in-place from an unassigned slot)
        FURN_ROOM_RENAME           = "HDGR_FURN_ROOM_RENAME",           -- payload: { roomID, name }
        FURN_ROOM_DELETE           = "HDGR_FURN_ROOM_DELETE",           -- payload: { roomID } (cascades placements across ALL layouts; local sets demote to library)
        FURN_ROOM_EQUIP            = "HDGR_FURN_ROOM_EQUIP",            -- payload: { roomID, setID }
        FURN_ROOM_UNEQUIP          = "HDGR_FURN_ROOM_UNEQUIP",          -- payload: { roomID, setID }
        FURN_ROOM_DUPLICATE        = "HDGR_FURN_ROOM_DUPLICATE",        -- payload: { roomID, layoutID?, swap?, ts? } (variant: library sets shared, local pieces cloned; swap takes the source's placement in layoutID)
        LAYOUT_PLACE               = "HDGR_LAYOUT_PLACE",               -- payload: { layoutID, floor, x, y, rotation?, roomID? | shape? } (roomID places a room; shape places an unassigned slot)
        LAYOUT_MOVE                = "HDGR_LAYOUT_MOVE",                -- payload: { layoutID, key, floor?, x?, y?, rotation? }
        LAYOUT_REMOVE_PLACEMENT    = "HDGR_LAYOUT_REMOVE_PLACEMENT",    -- payload: { layoutID, key }
        LAYOUT_ASSIGN              = "HDGR_LAYOUT_ASSIGN",              -- payload: { layoutID, slotKey, roomID } (tag a slot with a room; multi-assign OK)
        LAYOUT_UNASSIGN            = "HDGR_LAYOUT_UNASSIGN",            -- payload: { layoutID, key } (clear the tag; spot reverts to a bare shape)
        LAYOUT_SWAP_ROOM           = "HDGR_LAYOUT_SWAP_ROOM",           -- payload: { layoutID, fromRoomID, toRoomID } (the placement changes hands; once-per-layout enforced)
    },

    -- ===== UI sizing constants =====
    -- Per CLAUDE.md rule #9: hardcoded sizes / spacing go here, not inlined.
    STYLE = {
        CARD_GRID = {
            CELL_SIZE     = 80,
            CELLS_PER_ROW = 6,
            CELL_SPACING  = 1,
            ROW_SPACING   = 1,
        },
        CARD_GRID_DETAIL  = { CELLS_PER_ROW = 8, CELL_SIZE = 80 },
        CARD_GRID_PREVIEW = { CELLS_PER_ROW = 8, CELL_SIZE = 80 },
        CARD_GRID_BASKET  = { CELLS_PER_ROW = 2, CELL_SIZE = 60 },
        TREE_LIST = {
            INDENT      = 18,    -- px offset per nesting level
            ROW_HEIGHT  = 22,
            ROW_SPACING = 1,
        },
    },
}

-- ===== Source-kind master table =====
-- Canonical source-of-truth for source/gate kinds. Priority-ordered (most-binding first).
-- All lookups (chip color, labels, chipLabels, filter values, donor codes) derive from this.
-- Adding a new kind: one row here. Every consumer picks it up automatically.
-- Schema: key (uppercase), donorCode (HDG compat), filterValue, label, chipLabel, useInFilter.

-- Class color hex ("AARRGGBB"), mirroring GetClassColorObj():GenerateHexColor() -- pure data.
HDG.Constants.CLASS_COLORS = {
    DEATHKNIGHT = "ffc41e3a", DEMONHUNTER = "ffa330c9", DRUID   = "ffff7c0a",
    EVOKER      = "ff33937f", HUNTER      = "ffaad372", MAGE    = "ff3fc7eb",
    MONK        = "ff00ff98", PALADIN     = "fff48cba", PRIEST  = "ffffffff",
    ROGUE       = "fffff468", SHAMAN      = "ff0070dd", WARLOCK = "ff8788ee",
    WARRIOR     = "ffc69b6d",
}

HDG.Constants.SOURCE_KINDS = {
    { key="REP",      donorCode=13, filterValue="reputation",  label="Reputation",   chipLabel="REP",  useInFilter=true },
    { key="CRAFT",    donorCode=6,  filterValue="crafted",     label="Crafted",      chipLabel="PROF", useInFilter=true },
    { key="QUEST",    donorCode=2,  filterValue="quest",       label="Quest",        chipLabel="QUST", useInFilter=true },
    { key="ACH",      donorCode=1,  filterValue="achievement", label="Achievement",  chipLabel="ACH",  useInFilter=true },
    -- PROMO ranks above VENDOR: for promo-reward items also buyable, the promo IS the acquisition.
    { key="PROMO",    donorCode=10, filterValue="promotional", label="Promotional",  chipLabel="PROM", useInFilter=true },
    { key="VENDOR",   donorCode=5,  filterValue="vendor",      label="Vendor",       chipLabel="VEND", useInFilter=false },
    { key="SHOP",     donorCode=12, filterValue="shop",        label="In-Game Shop", chipLabel="SHOP", useInFilter=true },
    -- EVENT (donor 14): catalog "Event:" prefix; distinct from PROMO (out-of-game promos).
    { key="EVENT",    donorCode=14, filterValue="event",       label="Event",        chipLabel="EVNT", useInFilter=true },
    { key="TREASURE", donorCode=9,  filterValue="treasure",    label="Treasure",     chipLabel="TREA", useInFilter=true },
    { key="DROP",     donorCode=4,  filterValue="drop",        label="Drop",         chipLabel="DROP", useInFilter=true },
}

-- Derived indexes -- built once, O(1) lookup thereafter.
HDG.Constants.SOURCE_KIND_BY_KEY    = {}  -- "CRAFT" → entry
HDG.Constants.SOURCE_KIND_BY_DONOR  = {}  -- 6       → entry
HDG.Constants.SOURCE_KIND_BY_FILTER = {}  -- "crafted" → entry
HDG.Constants.SOURCE_KIND_PRIORITY  = {}  -- {"REP","CRAFT","QUEST",...} priority-order keys
for i, k in ipairs(HDG.Constants.SOURCE_KINDS) do
    HDG.Constants.SOURCE_KIND_BY_KEY[k.key]            = k
    HDG.Constants.SOURCE_KIND_BY_DONOR[k.donorCode]    = k
    HDG.Constants.SOURCE_KIND_BY_FILTER[k.filterValue] = k
    HDG.Constants.SOURCE_KIND_PRIORITY[i]              = k.key
end

-- Catalog sourceText token -> SOURCE_KINDS key. Used by _ParseSourceText.
-- `Profession` ABSENT: CRAFT comes only from the recipe DB, not catalog strings.
-- `Faction`/`Renown` not here -- they feed row.factionGate -> REP.
HDG.Constants.CATALOG_SOURCE_TOKENS = {
    ["Vendor"]       = "VENDOR",
    ["Vendors"]      = "VENDOR",   -- plural variant (catalog emits both)
    ["Quest"]        = "QUEST",
    ["Achievement"]  = "ACH",
    ["Drop"]         = "DROP",
    ["Treasure"]     = "TREASURE",
    ["Event"]        = "EVENT",
    ["Shop"]         = "SHOP",      -- bare line, no colon
    ["In-Game Shop"] = "SHOP",      -- bare line, no colon
}

-- Acquisition source-filter options. Derived from SOURCE_KINDS where useInFilter.
-- Tail: cost-based pseudo-filters (endeavor/gold) not backed by a kind.
HDG.Constants.ACQ_SOURCES = { { value = "all", label = "All Sources" } }
for _, k in ipairs(HDG.Constants.SOURCE_KINDS) do
    if k.useInFilter then
        HDG.Constants.ACQ_SOURCES[#HDG.Constants.ACQ_SOURCES + 1] =
            { value = k.filterValue, label = k.label }
    end
end
HDG.Constants.ACQ_SOURCES[#HDG.Constants.ACQ_SOURCES + 1] = { value = "endeavor", label = "Endeavor"  }
HDG.Constants.ACQ_SOURCES[#HDG.Constants.ACQ_SOURCES + 1] = { value = "gold",     label = "Gold Only" }

-- Gold has no Blizzard currency ID; CURRENCY_GOLD sentinel lets cost-entry tables iterate uniformly.
HDG.Constants.COIN_ATLAS    = "|A:auctionhouse-icon-coin-gold:14:14|a"
HDG.Constants.CURRENCY_GOLD = -1   -- sentinel; real currency IDs are positive

-- 134400 = INV_Misc_QuestionMark.blp -- canonical "?" placeholder for missing icons.
HDG.Constants.PLACEHOLDER_ICON = 134400

-- Outreach URLs (Config tab About section).
HDG.Constants.DISCORD_URL = "https://discord.gg/RWZaxJaHFP"
HDG.Constants.COFFEE_URL  = "https://buymeacoffee.com/vamoose"
HDG.Constants.DISCORD_TEXTURE = "Interface\\AddOns\\HousingDecorGuide\\textures\\discord.tga"
-- Wowhead logo: shopping-list row icon + detail URL-box icon for wowhead-sourced lists.
HDG.Constants.WOWHEAD_TEXTURE = "Interface\\AddOns\\HousingDecorGuide\\textures\\wowhead_logo"

-- REP_FACTIONS: every reputation faction referenced by a row.factionGate.
-- .faction = player faction restriction ("A"/"H"/"N") -- lets _bakeGates skip wrong-side gates.
-- Static map avoids C_Reputation.GetFactionDataByIndex (skips collapsed/legacy factions, taint risk).
HDG.Constants.REP_FACTIONS = {
    -- Alliance-only
    [47]   = { name = "Ironforge",                  faction = "A" },
    [72]   = { name = "Stormwind",                  faction = "A" },
    [1134] = { name = "Gilneas",                    faction = "A" },
    [1174] = { name = "Wildhammer Clan",            faction = "A" },
    [1731] = { name = "Council of Exarchs",         faction = "A" },
    [2160] = { name = "Proudmoore Admiralty",       faction = "A" },
    [2162] = { name = "Storm's Wake",               faction = "A" },

    -- Horde-only
    [922]  = { name = "Tranquillien",               faction = "H" },
    [1708] = { name = "Laughing Skull Orcs",        faction = "H" },
    [2103] = { name = "Zandalari Empire",           faction = "H" },
    [2156] = { name = "Talanji's Expedition",       faction = "H" },
    [2157] = { name = "The Honorbound",             faction = "H" },

    -- Neutral (both factions)
    [1271] = { name = "Order of the Cloud Serpent", faction = "N" },
    [1273] = { name = "Jogu the Drunk",             faction = "N" },
    [1275] = { name = "Ella",                       faction = "N" },
    [1280] = { name = "Tina Mudclaw",               faction = "N" },
    [1283] = { name = "Farmer Fung",                faction = "N" },
    [1345] = { name = "The Lorewalkers",            faction = "N" },
    [1515] = { name = "Arakkoa Outcasts",           faction = "N" },
    [1828] = { name = "Highmountain Tribe",         faction = "N" },
    [1859] = { name = "The Nightfallen",            faction = "N" },
    [1883] = { name = "Dreamweavers",               faction = "N" },
    [2391] = { name = "Rustbolt Resistance",        faction = "N" },
    [2507] = { name = "Dragonscale Expedition",     faction = "N" },
    [2510] = { name = "Valdrakken Accord",          faction = "N" },
    [2669] = { name = "Darkfuse Solutions",         faction = "N" },
    [2671] = { name = "Venture Company",            faction = "N" },
    [2673] = { name = "Bilgewater Cartel",          faction = "N" }, -- TWW Undermine (NOT 1133 Cata Horde-only)
    [2675] = { name = "Blackwater Cartel",          faction = "N" },
    [2677] = { name = "Steamwheedle Cartel",        faction = "N" },
    [2770] = { name = "Slayer's Duellum",           faction = "N" },

    -- Midnight (verified Faction.db2 12.0.5)
    [2699] = { name = "The Singularity",            faction = "N" },
    [2704] = { name = "Hara'ti",                    faction = "N" },
    [2710] = { name = "Silvermoon Court",           faction = "N" },
    [2764] = { name = "Prey: Season 1",             faction = "N" },
    -- Silvermoon Court subsidiaries (friendship reps, MoP-Tillers-style; parent 2710).
    -- friendship=true -> rep gates render as "reputation", not "Renown N".
    [2711] = { name = "Magisters",                  faction = "N", friendship = true },
    [2712] = { name = "Blood Knights",              faction = "N", friendship = true },
    [2713] = { name = "Farstriders",                faction = "N", friendship = true },
    [2714] = { name = "Shades of the Row",          faction = "N", friendship = true },
}

-- Reverse index: name -> factionID. Lowercase aliases absorb catalog casing drift ("the Honorbound").
HDG.Constants.REP_FACTION_BY_NAME = {}
for id, e in pairs(HDG.Constants.REP_FACTIONS) do
    HDG.Constants.REP_FACTION_BY_NAME[e.name] = id
    HDG.Constants.REP_FACTION_BY_NAME[string.lower(e.name)] = id
end
