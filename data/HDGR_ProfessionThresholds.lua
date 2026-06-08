-- ============================================================================
-- HousingDecorGuide (HDG) -- PROFESSION SKILL THRESHOLDS
-- Minimum skill level required to learn housing decor recipes per profession/expansion
-- Data sourced from Wowhead profession guides (January 2026)
-- ============================================================================

HDGR_ProfessionThresholds = {
    -- Format: [profession][expansion] = { threshold = minSkill, max = maxSkill }
    -- threshold = minimum skill to learn decor recipes
    -- max = maximum skill for that expansion

    ["Alchemy"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 80, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 75, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },

    ["Blacksmithing"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 80, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 75, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },

    ["Cooking"] = {
        -- Cooking has no Classic-Cataclysm or Legion decor recipes
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 80, max = 175 },
        ["Shadowlands"] = { threshold = 60, max = 75 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 80, max = 100 },
    },

    ["Enchanting"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 90, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 80, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },

    ["Engineering"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 80, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 80, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },

    ["Inscription"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 80, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 80, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },

    ["Jewelcrafting"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 80, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 80, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },

    ["Leatherworking"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 80, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 80, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },

    ["Tailoring"] = {
        ["Classic"] = { threshold = 240, max = 300 },
        ["The Burning Crusade"] = { threshold = 60, max = 75 },
        ["Wrath of the Lich King"] = { threshold = 60, max = 75 },
        ["Cataclysm"] = { threshold = 60, max = 75 },
        ["Mists of Pandaria"] = { threshold = 60, max = 75 },
        ["Warlords of Draenor"] = { threshold = 80, max = 100 },
        ["Legion"] = { threshold = 80, max = 100 },
        ["Battle for Azeroth"] = { threshold = 140, max = 175 },
        ["Shadowlands"] = { threshold = 80, max = 100 },
        ["Dragonflight"] = { threshold = 80, max = 100 },
        ["The War Within"] = { threshold = 80, max = 100 },
        ["Midnight"] = { threshold = 50, max = 100 },
    },
}

-- Helper function to get threshold for a profession/expansion
function HDG_GetDecorThreshold(profession, expansion)
    local profData = HDGR_ProfessionThresholds[profession]
    if profData and profData[expansion] then
        return profData[expansion].threshold, profData[expansion].max
    end
    return nil, nil
end
