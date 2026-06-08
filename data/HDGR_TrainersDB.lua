-- HDG (HousingDecorGuide) - Trainer Locations Reference
-- This file contains all trainer locations for housing decoration recipes across all professions
-- Format: {npcID=ID, name="Cached Name", location="Zone [x, y]"}
-- Array format (multiple trainers): { {npcID=..., ...}, {npcID=..., ...} }
-- npcID: Used for runtime name lookup via WoW API (NPCNameFromID pattern)
-- name: Cached fallback name if API lookup fails

HDGR_TrainersDB = {
    Alchemy = {
        Classic = {
            Alliance = {npcID=1215, name="Alchemist Mallory", location="Elwynn Forest [39.8, 48.3]"},
            Horde = {npcID=3347, name="Yelmak", location="Orgrimmar [55.6, 46.6]"},
        },
        ["The Burning Crusade"] = {
            Alliance = {npcID=18802, name="Alchemist Gribble", location="Hellfire Peninsula [53.8, 65.8]"},
            Horde = {npcID=16588, name="Apothecary Antonivich", location="Hellfire Peninsula [52.4, 36.5]"},
            Both = {
                {npcID=33630, name="Aelthin", location="Shattrath City [38.2, 71.1]", note="Scryers"},
                {npcID=33674, name="Alchemist Kanhu", location="Shattrath City [38.7, 30.1]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28703, name="Linzy Blackbolt", location="Dalaran (Northrend) [42.4, 32.0]"},
        },
        Cataclysm = {
            Alliance = {npcID=1215, name="Alchemist Mallory", location="Elwynn Forest [39.8, 48.3]"},
            Horde = {npcID=3347, name="Yelmak", location="Orgrimmar [55.6, 46.6]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=56777, name="Ni Gentlepaw", location="Jade Forest [46.5, 45.9]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85905, name="Jaiden Trask", location="Stormshield [36.4, 69.2]"},
            Horde = {npcID=87542, name="Joshua Alvarez", location="Warspear [60.6, 27.2]"},
        },
        Legion = {
            Both = {npcID=92458, name="Deucus Valdera", location="Dalaran (Broken Isles) [41.3, 33.4]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=132228, name="Elric Whalgrene", location="Boralus [54.1, 89.2]"},
            Horde = {npcID=122703, name="Clever Kumali", location="Dazar'alor [42.2, 38.0]"},
        },
        Shadowlands = {
            Both = {npcID=156687, name="Elixirist Au'pyr", location="Oribos [39.2, 40.4]"},
        },
        Dragonflight = {
            Both = {npcID=185545, name="Conflago", location="Valdrakken [36.4, 71.4]"},
        },
        ["The War Within"] = {
            Both = {npcID=226868, name="Tarig", location="Dornogal [47.4, 70.6]"},
        },
    },

    Blacksmithing = {
        Classic = {
            Alliance = {npcID=514, name="Smith Argus", location="Stormwind City [64.8, 48.2]"},
            Horde = {npcID=3355, name="Saru Steelfury", location="Orgrimmar [76.4, 34.4]"},
        },
        ["The Burning Crusade"] = {
            Both = {
                {npcID=16823, name="Kradu Grimblade", location="Shattrath City [69.8, 42.4]", note="Lower City"},
                {npcID=33631, name="Barien", location="Shattrath City [43.3, 64.8]", note="Scryers"},
                {npcID=33675, name="Onodo", location="Shattrath City [37.6, 31.2]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28694, name="Alard Schmied", location="Dalaran (Northrend) [45.8, 27.4]"},
        },
        Cataclysm = {
            Alliance = {npcID=514, name="Smith Argus", location="Stormwind City [64.8, 48.2]"},
            Horde = {npcID=3355, name="Saru Steelfury", location="Orgrimmar [76.4, 34.4]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=65114, name="Len the Hammer", location="Jade Forest [48.4, 36.8]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85908, name="Aimee Goldforge", location="Stormshield [48.8, 48.2]"},
            Horde = {npcID=87550, name="Nonn Threeratchet", location="Warspear [75.2, 37.6]"},
        },
        Legion = {
            Both = {npcID=92183, name="Alard Schmied", location="Dalaran (Broken Isles) [45.0, 29.6]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=121193, name="Grix \"Ironfists\" Barlow", location="Boralus [73.4, 8.4]"},
            Horde = {npcID=127112, name="Forgemaster Zak'aal", location="Dazar'alor [43.6, 38.6]"},
        },
        Shadowlands = {
            Both = {npcID=156666, name="Smith Au'berk", location="Oribos [40.5, 31.4]"},
        },
        Dragonflight = {
            Both = {npcID=185546, name="Metalshaper Kuroko", location="Valdrakken [37.0, 47.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=223644, name="Darean", location="Dornogal [49.1, 63.5]"},
        },
    },

    Cooking = {
        ["Mists of Pandaria"] = {
            Both = {npcID=58715, name="Yan Ironpaw", location="Valley of the Four Winds [52.6, 51.6]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=77364, name="Elton Black", location="Stormshield [51.8, 59.4]"},
            Horde = {npcID=79823, name="Guy Fireeye", location="Warspear [42.6, 54.8]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=136052, name="\"Cap'n\" Byron Mehlsack", location="Boralus [71.2, 10.8]"},
            Horde = {npcID=122704, name="T'sarah the Royal Chef", location="Dazar'alor [42.2, 35.6]"},
        },
        Shadowlands = {
            Both = {npcID=156672, name="Chef Au'krut", location="Oribos [47.0, 23.6]"},
        },
        Dragonflight = {
            Both = {npcID=185553, name="Erugosa", location="Valdrakken [46.0, 46.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=229110, name="Athodas", location="Dornogal [44.3, 45.6]"},
        },
    },

    Enchanting = {
        Classic = {
            Alliance = {npcID=1317, name="Lucan Cordell", location="Stormwind City [53.0, 74.4]"},
            Horde = {npcID=3345, name="Godan", location="Orgrimmar [53.4, 49.4]"},
        },
        ["The Burning Crusade"] = {
            Both = {
                {npcID=19251, name="Johan Barnes", location="Hellfire Peninsula [53.6, 66.0]"},
                {npcID=33633, name="Enchantress Andiala", location="Shattrath City [55.7, 74.8]", note="Scryers"},
                {npcID=33676, name="Zurii", location="Shattrath City [36.4, 44.4]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28693, name="Enchanter Nalthanis", location="Dalaran (Northrend) [39.4, 41.2]"},
        },
        Cataclysm = {
            Alliance = {npcID=1317, name="Lucan Cordell", location="Stormwind City [53.0, 74.4]"},
            Horde = {npcID=3345, name="Godan", location="Orgrimmar [53.4, 49.4]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=65127, name="Lai the Spellpaw", location="Jade Forest [46.8, 42.9]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85914, name="Bil Sparktonic", location="Stormshield [56.4, 64.4]"},
            Horde = {npcID=86027, name="Hane'ke", location="Warspear [78.4, 52.4]"},
        },
        Legion = {
            Both = {npcID=93531, name="Enchanter Nalthanis", location="Dalaran (Broken Isles) [38.5, 41.2]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=136041, name="Emily Fairweather", location="Boralus [74.0, 11.4]"},
            Horde = {npcID=122702, name="Enchantress Quinni", location="Dazar'alor [47.0, 35.4]"},
        },
        Shadowlands = {
            Both = {npcID=156683, name="Imbuer Au'vresh", location="Oribos [48.2, 29.0]"},
        },
        Dragonflight = {
            Both = {npcID=185549, name="Soragosa", location="Valdrakken [30.0, 61.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=219085, name="Nagad", location="Dornogal [52.5, 71.2]"},
        },
    },

    Engineering = {
        Classic = {
            Alliance = {npcID=5174, name="Lilliam Sparkspindle", location="Stormwind City [62.8, 32.0]"},
            Horde = {npcID=11017, name="Roxxik", location="Orgrimmar [56.6, 56.5]"},
        },
        ["The Burning Crusade"] = {
            Both = {
                {npcID=19576, name="Zebig", location="Shattrath City [37.6, 42.4]"},
                {npcID=33634, name="Engineer Sinbei", location="Shattrath City [43.7, 65.1]", note="Scryers"},
                {npcID=33677, name="Technician Mihila", location="Shattrath City [37.7, 31.7]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28697, name="Timofey Oshenko", location="Dalaran (Northrend) [38.8, 25.8]"},
        },
        Cataclysm = {
            Alliance = {npcID=5174, name="Lilliam Sparkspindle", location="Stormwind City [62.8, 32.0]"},
            Horde = {npcID=11017, name="Roxxik", location="Orgrimmar [56.6, 56.5]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=55143, name="Sally Fizzlefury", location="Valley of the Four Winds [16.1, 83.3]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85916, name="Hilda Copperfuze", location="Stormshield [59.8, 38.4]"},
            Horde = {npcID=87552, name="Nik Steelrings", location="Warspear [70.5, 39.0]"},
        },
        Legion = {
            Both = {npcID=93520, name="Timofey Oshenko", location="Dalaran (Broken Isles) [38.2, 26.5]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=122709, name="Layla Evenkeel", location="Boralus [56.2, 85.0]"},
            Horde = {npcID=131840, name="Shuga Blastcaps", location="Dazar'alor [45.0, 40.0]"},
        },
        Shadowlands = {
            Both = {npcID=156691, name="Machinist Au'gur", location="Oribos [38.0, 44.7]"},
        },
        Dragonflight = {
            Both = {npcID=185548, name="Clinkyclick Shatterboom", location="Valdrakken [42.0, 48.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=219099, name="Thermalseer Arhdas", location="Dornogal [49.1, 56.1]"},
        },
    },

    Inscription = {
        Classic = {
            Alliance = {npcID=30713, name="Catarina Stanford", location="Stormwind City [49.5, 74.9]"},
            Horde = {npcID=30706, name="Jo'mah", location="Orgrimmar [35.6, 69.2]"},
        },
        ["The Burning Crusade"] = {
            Both = {
                {npcID=33638, name="Scribe Lanloer", location="Shattrath City [56.0, 74.4]", note="Scryers"},
                {npcID=33679, name="Recorder Lidio", location="Shattrath City [36.1, 43.9]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28702, name="Professor Pallin", location="Dalaran (Northrend) [42.6, 37.8]"},
        },
        Cataclysm = {
            Alliance = {npcID=30713, name="Catarina Stanford", location="Stormwind City [49.5, 74.9]"},
            Horde = {npcID=30706, name="Jo'mah", location="Orgrimmar [35.6, 69.2]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=64691, name="Inkmaster Wei", location="Jade Forest [55.0, 45.0]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85911, name="Scribe Chi-Yuan", location="Stormshield [62.6, 34.0]"},
            Horde = {npcID=86015, name="Joro'man", location="Warspear [73.8, 31.2]"},
        },
        Legion = {
            Both = {npcID=92195, name="Professor Pallin", location="Dalaran (Broken Isles) [41.3, 37.0]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=130399, name="Zooey Inksprocket", location="Boralus [73.4, 6.3]"},
            Horde = {npcID=122711, name="Chronicler Kizani", location="Dazar'alor [42.3, 39.6]"},
        },
        Shadowlands = {
            Both = {npcID=156685, name="Scribe Au'tehshi", location="Oribos [36.8, 36.4]"},
        },
        Dragonflight = {
            Both = {npcID=185552, name="Talendara", location="Valdrakken [38.0, 73.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=217128, name="Brrigan", location="Dornogal [48.6, 71.2]"},
        },
    },

    Jewelcrafting = {
        Classic = {
            Alliance = {npcID=15501, name="Theresa Denman", location="Stormwind City [63.5, 61.6]"},
            Horde = {npcID=15512, name="Lugrah", location="Orgrimmar [72.5, 34.3]"},
        },
        ["The Burning Crusade"] = {
            Both = {
                {npcID=19539, name="Hamanar", location="Shattrath City [35.7, 20.6]", note="Lower City"},
                {npcID=33637, name="Kirembri Silverman", location="Shattrath City [58.2, 75.0]", note="Scryers"},
                {npcID=33680, name="Nemiha", location="Shattrath City [36.0, 47.8]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28701, name="Timothy Jones", location="Dalaran (Northrend) [40.3, 35.1]"},
        },
        Cataclysm = {
            Alliance = {npcID=15501, name="Theresa Denman", location="Stormwind City [63.5, 61.6]"},
            Horde = {npcID=15512, name="Lugrah", location="Orgrimmar [72.5, 34.3]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=65098, name="Mai the Jade Shaper", location="Jade Forest [48.0, 35.0]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85916, name="Artificer Nissea", location="Stormshield [43.8, 34.2]"},
            Horde = {npcID=86022, name="Alixander Swiftsteel", location="Warspear [73.6, 35.4]"},
        },
        Legion = {
            Both = {npcID=93527, name="Timothy Jones", location="Dalaran (Broken Isles) [40.1, 35.3]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=122694, name="Samuel D. Colton III", location="Boralus [54.6, 86.1]"},
            Horde = {npcID=122695, name="Seshuli", location="Dazar'alor [47.0, 37.8]"},
        },
        Shadowlands = {
            Both = {npcID=156663, name="Appraiser Au'vesk", location="Oribos [35.2, 41.8]"},
        },
        Dragonflight = {
            Both = {npcID=185550, name="Tuluradormi", location="Valdrakken [40.0, 61.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=217129, name="Makir", location="Dornogal [49.7, 71.2]"},
        },
    },

    Leatherworking = {
        Classic = {
            Alliance = {npcID=7866, name="Simon Tanner", location="Stormwind City [71.8, 62.8]"},
            Horde = {npcID=3365, name="Karolek", location="Orgrimmar [60.8, 54.8]"},
        },
        ["The Burning Crusade"] = {
            Both = {
                {npcID=18771, name="Darmari", location="Shattrath City [67.2, 67.6]", note="Lower City"},
                {npcID=33635, name="Daenril", location="Shattrath City [41.4, 63.3]", note="Scryers"},
                {npcID=33681, name="Korim", location="Shattrath City [37.6, 27.8]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28700, name="Diane Cannings", location="Dalaran (Northrend) [35.0, 28.6]"},
        },
        Cataclysm = {
            Alliance = {npcID=7866, name="Simon Tanner", location="Stormwind City [71.8, 62.8]"},
            Horde = {npcID=3365, name="Karolek", location="Orgrimmar [60.8, 54.8]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=65121, name="Clean Pelt", location="Kun-Lai Summit [64.6, 60.8]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85909, name="Jistun Sharpfeather", location="Stormshield [51.4, 41.8]"},
            Horde = {npcID=87549, name="Garm Gladestride", location="Warspear [50.3, 27.5]"},
        },
        Legion = {
            Both = {npcID=93523, name="Namha Moonwater", location="Dalaran (Broken Isles) [35.4, 29.6]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=136062, name="Cassandra Brennor", location="Boralus [75.5, 12.6]"},
            Horde = {npcID=122698, name="Xanjo", location="Dazar'alor [44.0, 34.6]"},
        },
        Shadowlands = {
            Both = {npcID=156669, name="Tanner Au'qil", location="Oribos [42.6, 26.8]"},
        },
        Dragonflight = {
            Both = {npcID=185551, name="Hideshaper Koruz", location="Valdrakken [28.0, 61.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=219080, name="Marbb", location="Dornogal [54.6, 58.0]"},
        },
    },

    Tailoring = {
        Classic = {
            Alliance = {npcID=1346, name="Georgio Bolero", location="Stormwind City [53.2, 81.6]"},
            Horde = {npcID=3363, name="Magar", location="Orgrimmar [60.8, 59.1]"},
        },
        ["The Burning Crusade"] = {
            Both = {
                {npcID=33636, name="Miralisse", location="Shattrath City [41.3, 63.6]", note="Scryers"},
                {npcID=33684, name="Weaver Aoa", location="Shattrath City [37.7, 27.1]", note="Aldor"},
            },
        },
        ["Wrath of the Lich King"] = {
            Both = {npcID=28699, name="Charles Worth", location="Dalaran (Northrend) [36.3, 33.4]"},
        },
        Cataclysm = {
            Alliance = {npcID=1346, name="Georgio Bolero", location="Stormwind City [53.2, 81.6]"},
            Horde = {npcID=3363, name="Magar", location="Orgrimmar [60.8, 59.1]"},
        },
        ["Mists of Pandaria"] = {
            Both = {npcID=57405, name="Silkmaster Tsai", location="Valley of the Four Winds [62.6, 59.6]"},
        },
        ["Warlords of Draenor"] = {
            Alliance = {npcID=85910, name="Joshua Fuesting", location="Stormshield [51.6, 37.2]"},
            Horde = {npcID=86004, name="Saesha Silverblood", location="Warspear [73.8, 36.8]"},
        },
        Legion = {
            Both = {npcID=93542, name="Tanithria", location="Dalaran (Broken Isles) [44.2, 31.8]"},
        },
        ["Battle for Azeroth"] = {
            Alliance = {npcID=136071, name="Daniel Brineweaver", location="Boralus [53.4, 85.5]"},
            Horde = {npcID=122700, name="Pin'jin the Patient", location="Dazar'alor [44.4, 33.8]"},
        },
        Shadowlands = {
            Both = {npcID=156681, name="Stitcher Au'phes", location="Oribos [45.4, 31.8]"},
        },
        Dragonflight = {
            Both = {npcID=195850, name="Threadfinder Pax", location="Valdrakken [32.0, 67.0]"},
        },
        ["The War Within"] = {
            Both = {npcID=219094, name="Kotag", location="Dornogal [54.8, 63.6]"},
        },
    },
}
