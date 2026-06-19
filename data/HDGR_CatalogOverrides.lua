-- HDGR_CatalogOverrides -- itemID-keyed field-level overrides applied to
-- catalog rows at HousingCatalogObserver:BuildRow time.
--
-- Two override categories supported per entry:
--
--   1. Field-level field corrections -- correct KNOWN-WRONG values the
--      catalog ships (typo, mis-tagged zone, faction-gate the catalog claims
--      but the actual mob requires different rep, etc).
--        [258667] = { factionGate = nil, zone = "K'aresh" }
--
--   2. Source classification -- ordered list of how the player can acquire
--      the item. Layered on top of catalog vendor data so the UI shows
--      curator-known sources catalog doesn't classify (CATALOG_EMPTY items,
--      World Vendors () synthetic placeholders, shop items, etc).
--      Source type codes (from HDG.Constants.HDG_SOURCE_TYPE):
--        1=Ach 2=Quest 3=WQ 4=Drop 5=Vendor 6=Craft
--        9=Treasure 10=Promo 12=Shop 13=Rep
--        [256923] = { sources = { { type = 5, name = "Chel the Chip",
--                                    detail = "Found at active Abundant Harvest" } } }
--
-- Both can coexist on the same itemID. Sparse: items without overrides have
-- no entry. Override application is transparent to selectors -- observer
-- applies inside BuildRow so downstream sees the corrected row directly.

HDGR_CatalogOverrides = {
    -- Wooden Mug
    [239162] = { sources = { { type = 5, name = 'Peter', detail = 'Lunarfall', cost = { gold = 500000, currencies = { { id = 824, amount = 100 } } } }, { type = 5, name = 'Vora Strongarm', detail = 'Frostwall' } } },
    -- Elodor Barrel
    [241043] = { sources = { { type = 2, name = 'Missive: Assault on Shattrath Harbor', detail = 'Tanaan Jungle' } } },
    -- Orcish Lumberjack's Stool
    [244321] = { sources = { { type = 5, name = 'Krixel Pinchwhistle', detail = 'Lunarfall', cost = { currencies = { { id = 824, amount = 100 } } } }, { type = 5, name = 'Ribchewer', detail = 'Frostwall' } } },
    -- Frostwolf Banded Stool
    [244322] = { sources = { { type = 5, name = 'Krixel Pinchwhistle', detail = 'Lunarfall', cost = { currencies = { { id = 824, amount = 100 } } } }, { type = 5, name = 'Ribchewer', detail = 'Frostwall' } } },
    -- Small Val'sharah Bookcase
    [245259] = { sources = { { type = 2, name = 'Dreamy Inspiration', detail = 'Stormwind City' }, { type = 5, name = 'Second Chair Pawdo', detail = 'Dornogal', cost = { gold = 500000 } } } },
    -- Councilward's Jeweled Goblet
    [245294] = { sources = { { type = 4, name = "Distinguished Actor's Chest", detail = 'Isle of Dorn' } } },
    -- Very Reliable Undermine Lamppost
    [245320] = { sources = { { type = 3, name = '10-Job Streak Bonus', detail = 'Undermine' } } },
    -- Draenic Storage Chest
    [245424] = { sources = { { type = 5, name = 'Maaria', detail = 'Lunarfall', cost = { gold = 5000000, currencies = { { id = 823, amount = 1000 } } } } } },
    -- Draenor Cookpot
    [245431] = { sources = { { type = 5, name = "Kil'rip", detail = 'Frostwall', cost = { currencies = { { id = 823, amount = 1000 } } } } } },
    -- Blackrock Strongbox
    [245433] = { sources = { { type = 5, name = "Kil'rip", detail = 'Frostwall', cost = { currencies = { { id = 823, amount = 1000 } } } } } },
    -- Horde Battle Emblem
    [245435] = { sources = { { type = 4, name = 'Warlord Zaela', detail = 'Upper Blackrock Spire' } } },
    -- Orc-Forged Weaponry
    [245437] = { sources = { { type = 5, name = "Moz'def", detail = 'Frostwall' } } },
    -- Warsong Footrest
    [245442] = { sources = { { type = 5, name = "Moz'def", detail = 'Frostwall', cost = { currencies = { { id = 824, amount = 100 } } } } } },
    -- Orcish Communal Stove
    [245444] = { sources = { { type = 5, name = 'Krixel Pinchwhistle', detail = 'Lunarfall', cost = { currencies = { { id = 824, amount = 250 } } } }, { type = 5, name = 'Ribchewer', detail = 'Frostwall' } } },
    -- Frostwolf Axe-Dart Board
    [245445] = { sources = { { type = 5, name = 'Krixel Pinchwhistle', detail = 'Lunarfall', cost = { currencies = { { id = 824, amount = 150 } } } }, { type = 5, name = 'Ribchewer', detail = 'Frostwall' } } },
    -- Orgrimmar Round Platform
    [246260] = { sources = { { type = 5, name = '"High Tides" Ren', detail = "Founder's Point", cost = { gold = 1000000 } }, { type = 5, name = 'Gronthul', detail = 'Razorwind Shores' } } },
    -- Square Stormpike Table
    [246424] = { sources = { { type = 5, name = 'Thanthaldis Snowgleam', detail = 'Hillsbrad Foothills' } } },
    -- Retired Industrial Gnomegrabber
    [246481] = { sources = { { type = 3, name = 'Self-Assembling Homeware Kit', detail = 'Mechagon' } } },
    -- Mechanical Gnomish Lamppost (Junkyard Tinkering -- Pascal-K1N6 in Mechagon, NOT the Endeavor Pascal; catalog ships these as "Profession: Junkyard Tinkering")
    [246482] = { sources = { { type = 5, name = 'Pascal-K1N6', detail = 'Mechagon' } } },
    -- Mechagnome Sustenance Distributor (Junkyard Tinkering)
    [246485] = { sources = { { type = 5, name = 'Pascal-K1N6', detail = 'Mechagon' } } },
    -- Gnomish Tesla Coil
    [246487] = { sources = { { type = 2, name = 'Spare A Chair', detail = 'Stormwind City' }, { type = 5, name = 'Second Chair Pawdo', detail = 'Dornogal', cost = { gold = 750000 } } } },
    -- Gnomish Fencepost (Junkyard Tinkering)
    [246595] = { sources = { { type = 5, name = 'Pascal-K1N6', detail = 'Mechagon' } } },
    -- Gnomish Fence (Junkyard Tinkering)
    [246596] = { sources = { { type = 5, name = 'Pascal-K1N6', detail = 'Mechagon' } } },
    -- Perpetual Motion Crate (Junkyard Tinkering)
    [246597] = { sources = { { type = 5, name = 'Pascal-K1N6', detail = 'Mechagon' } } },
    -- Self-Sealing Stembarrel
    [246599] = { sources = { { type = 3, name = 'Self-Assembling Homeware Kit', detail = 'Mechagon' } } },
    -- Small Mechanical Crate
    [246600] = { sources = { { type = 3, name = 'Self-Assembling Homeware Kit', detail = 'Mechagon' } } },
    -- Small H.O.M.E. Cog
    [246602] = { sources = { { type = 3, name = 'Self-Assembling Homeware Kit', detail = 'Mechagon' } } },
    -- Mechagon Armory Rack (Junkyard Tinkering)
    [246606] = { sources = { { type = 5, name = 'Pascal-K1N6', detail = 'Mechagon' } } },
    -- "Shu'halo Perspective" Painting (Cravitz Lorent in the Murder Row dungeon -- catalog-empty, not a catalog vendor). Sargle's Fortunes tracker: HDGR_DecorWidgets / decor.fortune.*
    [246857] = { sources = { { type = 5, name = 'Cravitz Lorent', detail = 'Murder Row' } } },
    -- Square Suramar Table
    [247915] = { sources = { { type = 2, name = 'Last Light', detail = 'Stormwind City' }, { type = 5, name = 'Second Chair Pawdo', detail = 'Dornogal', cost = { gold = 1000000 } } } },
    -- Valdrakken Chandelier
    [248116] = { sources = { { type = 2, name = 'Draconic Decor', detail = 'Stormwind City' }, { type = 5, name = 'Second Chair Pawdo', detail = 'Dornogal', cost = { gold = 750000 } } } },
    -- Round-Top Boulder
    [248337] = { sources = { { type = 5, name = 'Trevor Grenner', detail = "Founder's Point", cost = { gold = 500000 } } } },
    -- Flat Boulder
    [248338] = { sources = { { type = 5, name = 'Trevor Grenner', detail = "Founder's Point", cost = { gold = 500000 } } } },
    -- Hilltop Boulder
    [248339] = { sources = { { type = 5, name = 'Trevor Grenner', detail = "Founder's Point", cost = { gold = 500000 } } } },
    -- Goldshire Food Cart
    [248796] = { sources = { { type = 5, name = 'Fiona', detail = 'Eastern Plaguelands', cost = { gold = 30000000 } }, { type = 1, name = 'Full Caravan' } } },
    -- Lush Garden Trellis
    [250793] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Colorful Shroomic Egg
    [250794] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Colorful Dotted Egg
    [250795] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Colorful Striped Egg
    [250796] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Ceiling Light
    [250797] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Shelf
    [250798] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Shadowmoon Open-Air Shed
    [251329] = { sources = { { type = 2, name = "Missive: Assault on Socrethar's Rise", detail = 'Tanaan Jungle' } } },
    -- Draenic Ottoman
    [251331] = { sources = { { type = 4, name = "Teron'gor", detail = 'Auchindoun' } } },
    -- Telredor Recliner
    [251544] = { sources = { { type = 5, name = 'Maaria', detail = 'Lunarfall', cost = { gold = 5000000, currencies = { { id = 823, amount = 1000 } } } } } },
    -- Draenei Farmer's Trellis
    [251547] = { sources = { { type = 2, name = 'Assault on the Heart of Shattrath', detail = 'Tanaan Jungle' } } },
    -- Lush Garden Fungal Basin -- Battle.net Shop only (250 Hearthsteel / Lush Garden
    -- Decor Pack). Catalog ships a spurious "Quest: Learn From the Best" line (players
    -- confirm that quest grants no decor); quest = false suppresses the bad [QUEST] chip.
    [252419] = { quest = false, sources = { { type = 12, name = 'In-Game Shop', detail = '250 Hearthsteel' }, { type = 12, name = 'In-Game Shop', detail = 'Lush Garden Decor Pack (Bundle)' } } },
    -- Meadery Storage Barrel
    [253173] = { sources = { { type = 2, name = 'Furniture Favor', detail = 'Stormwind City' }, { type = 5, name = 'Second Chair Pawdo', detail = 'Dornogal', cost = { gold = 200000 } } } },
    -- Lush Garden Butterfly Sconce
    [253546] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Wreath
    [253547] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Hanging Chair
    [254417] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Gnomish Tesla Tower
    [255672] = { sources = { { type = 4, name = 'King Mechagon', detail = 'Operation: Mechagon' } } },
    -- Valdrakken Hanging Lamp
    [256428] = { sources = { { type = 4, name = 'Kyrakka and Erkhart Stormvein', detail = 'Ruby Life Pools' } } },
    -- Amani Crafter's Tool Rack
    [256923] = { sources = { { type = 5, name = 'Chel the Chip', detail = 'Found at active Abundant Harvest', cost = { currencies = { { id = 3377, amount = 800 } } } } } },
    -- Bloodtotem Banner
    [257724] = { sources = { { type = 1, name = 'Highmountain Tribe', detail = 'Paragon Cache' } } },
    -- Gnomeregan Recyli-Kiln
    [257928] = { sources = { { type = 2, name = 'Even More Recycling', detail = 'Mechagon' } } },
    -- Waxmaster's Candle Rack
    [258268] = { sources = { { type = 4, name = 'The Darkness', detail = 'Darkflame Cleft' } } },
    -- Lush Garden Gnome-Like Statue
    [258294] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Lush Garden Fungal Chair
    [258567] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Window
    [258568] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Gazebo
    [258569] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Lush Garden Fungal Fountain
    [258888] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Paw Pal Water Dish
    [259044] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Paw Pal Bed and Blanket
    [259045] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Paw Pal Bed
    [259046] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Sanctuary's Chess Match
    [259057] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary's Chess Board
    [259058] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Dark Bishop
    [259059] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Dark Rook
    [259060] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Dark Queen
    [259061] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Dark Pawn
    [259062] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Dark Knight
    [259063] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Dark King
    [259064] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Light Bishop
    [259065] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Light Rook
    [259066] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Light Queen
    [259067] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Light Pawn
    [259068] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Light Knight
    [259069] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Sanctuary Chess Light King
    [259070] = { sources = { { type = 10, name = 'Promotional', detail = 'Diablo IV: Lord of Hatred' } } },
    -- Paw Pal Dog House Frame
    [259093] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Paw Pal Dog House Elwynn Roof
    [259094] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Miniature Replica Dark Portal
    [260785] = { sources = { { type = 5, name = 'Gabbi', detail = 'Orgrimmar', cost = { gold = 15000000 } }, { type = 5, name = 'Tuuran', detail = 'Stormwind City' }, { type = 5, name = 'Dennia Silvertongue', detail = 'Silvermoon City' } } },
    -- Spring Blossom Tree
    [263290] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Tree Pond
    [263291] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Corked Bottle of Liquid Mystery (promo, NOT Shop -- catalog mis-tags as Shop/World Vendors)
    [263383] = { shop = false, sources = { { type = 10, name = 'Promotional' } } },
    -- Midnight Alchemist's Shop Sign
    [263997] = { sources = { { type = 5, name = 'Melaris', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Alchemizing at Midnight', detail = 'Professions' } } },
    -- Midnight Blacksmith's Shop Sign
    [263998] = { sources = { { type = 5, name = 'Eriden', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Blacksmithing at Midnight', detail = 'Professions' } } },
    -- Midnight Cook's Shop Sign
    [263999] = { sources = { { type = 5, name = 'Quelis', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Cooking at Midnight', detail = 'Professions' } } },
    -- Midnight Enchanter's Shop Sign
    [264000] = { sources = { { type = 5, name = 'Lyna', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Enchanting at Midnight', detail = 'Professions' } } },
    -- Midnight Engineer's Shop Sign
    [264001] = { sources = { { type = 5, name = 'Yatheon', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Engineering at Midnight', detail = 'Professions' } } },
    -- Midnight Fisher's Shop Sign
    [264002] = { sources = { { type = 5, name = 'Mowaia', detail = 'Harandar', cost = { gold = 50000 } }, { type = 1, name = 'Fishing at Midnight', detail = 'Professions' } } },
    -- Midnight Scribe's Shop Sign
    [264004] = { sources = { { type = 5, name = 'Lelorian', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Inscribing at Midnight', detail = 'Professions' } } },
    -- Midnight Jewelcrafter's Shop Sign
    [264005] = { sources = { { type = 5, name = "Amwa'ana", detail = 'Harandar', cost = { gold = 50000 } }, { type = 1, name = 'Jewelcrafting at Midnight', detail = 'Professions' } } },
    -- Midnight Leatherworker's Shop Sign
    [264006] = { sources = { { type = 5, name = 'Zaralda', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Leatherworking at Midnight', detail = 'Professions' } } },
    -- Midnight Tailor's Shop Sign
    [264174] = { sources = { { type = 5, name = 'Deynna', detail = 'Silvermoon City', cost = { gold = 50000 } }, { type = 1, name = 'Tailoring at Midnight', detail = 'Professions' } } },
    -- Woodblock Stool
    [264249] = { sources = { { type = 5, name = 'Chel the Chip', detail = 'Found at active Abundant Harvest', cost = { currencies = { { id = 3377, amount = 1600 } } } } } },
    -- Three-Tier Zul'Aman Shelf
    [264254] = { sources = { { type = 5, name = 'Chel the Chip', detail = 'Found at active Abundant Harvest', cost = { currencies = { { id = 3377, amount = 800 } } } } } },
    -- Paw Pal Dog House Durotar Roof
    [264275] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Paw Pal Dog House Eversong Roof
    [264276] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Paw Pal Dog House Shadowglen Roof
    [264277] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Sturdy Portable Ice Chest (promo, NOT Shop -- catalog mis-tags as Shop/World Vendors)
    [264278] = { shop = false, sources = { { type = 10, name = 'Promotional' } } },
    -- Tall Corked Bottle of Liquid Mystery (promo)
    [264279] = { shop = false, sources = { { type = 10, name = 'Promotional' } } },
    -- Short Corked Bottle of Liquid Mystery (promo)
    [264280] = { shop = false, sources = { { type = 10, name = 'Promotional' } } },
    -- Bluebird's Golden Cage
    [264282] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Amani Ritual Altar
    [264332] = { sources = { { type = 4, name = 'Nalorakk', detail = 'Den of Nalarakk' } } },
    -- Cosmic Void Campfire
    [264483] = { sources = { { type = 4, name = 'Voidstorm Mob', detail = 'Voidstorm' } } },
    -- Amani Slate Bench
    [264655] = { sources = { { type = 5, name = 'Chel the Chip', detail = 'Found at active Abundant Harvest', cost = { currencies = { { id = 3377, amount = 3200 } } } } } },
    -- Spring Blossom Stepping Stone Collection
    [265559] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Table
    [266069] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Lush Garden Hedge
    [266162] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Lush Garden Fungal Picnic
    [266164] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Lantern
    [266165] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Spring Blossom Tranquility Garden
    [266166] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Granite Cobblestone Path Corner
    [266244] = { sources = { { type = 5, name = 'Trevor Grenner', detail = "Founder's Point", cost = { gold = 750000 } } } },
    -- Granite Cobblestone Path Arc
    [266245] = { sources = { { type = 5, name = 'Trevor Grenner', detail = "Founder's Point", cost = { gold = 750000 } } } },
    -- Granite Cobblestone Long Path
    [266443] = { sources = { { type = 5, name = 'Trevor Grenner', detail = "Founder's Point", cost = { gold = 500000 } } } },
    -- Granite Cobblestone Path
    [266444] = { sources = { { type = 5, name = 'Trevor Grenner', detail = "Founder's Point", cost = { gold = 750000 } } } },
    -- Lush Garden Stable
    [267203] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Sin'dorei Tiffin-Style Lamp
    [268457] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 50 } } } } } },
    -- Lush Garden Rug
    [268550] = { sources = { { type = 12, name = 'In-Game Shop' } } },
    -- Bartender Bob's "No Weapons Allowed" Rack (Highly Decorated achievement; extra copies from Morta Gage in Arcantina). Achievement+ID lives in ItemAugment.
    [269316] = { sources = { { type = 5, name = 'Morta Gage', detail = 'Arcantina', cost = { currencies = { { id = 3316, amount = 2500 } } } } } },
    -- Sin'dorei Covered Cookpot
    [269613] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 30 } } } } } },
    -- Sin'dorei Open Cookpot
    [269614] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 15 } } } } } },
    -- Sin'dorei Cookpot Lid
    [269636] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 15 } } } } } },
    -- Sin'dorei Display Case
    [269641] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 50 } } } } } },
    -- Sin'dorei Garden Swing
    [271162] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 120 } } } } } },
    -- Small Lumber Pile
    [272441] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 10 } } } } } },
    -- Empty Wooden Toolbox
    [272442] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 20 } } } } } },
    -- Suramar Arcfruit Bowl
    [272443] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 20 } } } } } },
    -- Small Decorative Dornogal Opal
    [272444] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 10 } } } } } },
    -- Decorative Dornogal Opal
    [272445] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 10 } } } } } },
    -- Large Decorative Dornogal Opal
    [272446] = { sources = { { type = 5, name = 'Disguised Decor Duel Vendor', detail = 'Silvermoon City', cost = { currencies = { { id = 3393, amount = 10 } } } } } },
}
