-- HDGR_HouseTab_DailyTitles.lua
-- ============================================================================
-- 50-entry table of bestowed-title personas + quotes. One title is selected
-- per real-world day via deterministic date hash so every character on the
-- account sees the same title on the same day. Loaded as shipped data;
-- consumed by Modules/HDGR_Vamoose.lua at addon enable.
--
-- Verbatim port from HousingDecorGuide/modules/HDG_Vamoose.lua DAILY_TITLES
-- table. Edits to either copy should be mirrored.

HDGR_HouseTab_DailyTitles = {
    { name = "Twilight Court Architect",  quote = "Sleeps with one eye open. The other is admiring the moonlight." },
    { name = "Velvet Dawn Curator",       quote = "Wakes before the sun. Decorates before the coffee." },
    { name = "Lumber Baron",              quote = "Has opinions about wood. Strong ones. Probably wrong." },
    { name = "Wallpaper Whisperer",       quote = "Knows the secrets of every pattern. Most aren't worth the asking price." },
    { name = "Mantle Magnate",            quote = "More candlesticks than a chandler's guild. Counts them nightly." },
    { name = "Cobblestone Connoisseur",   quote = "Tested every path stone for foot comfort. Personally. In bare feet." },
    { name = "Topiary Tyrant",            quote = "Hedge clippers sharper than wit. Both deployed daily." },
    { name = "Lantern Luminary",          quote = "Lit up rooms before it was fashionable. Hasn't stopped." },
    { name = "Banner Bannermarshal",      quote = "Hangs flags at precise angles. Approves of pageantry. Loudly." },
    { name = "Hearth Herald",             quote = "Believes every room needs a fire. And someone to admire it." },
    { name = "Drapery Despot",            quote = "Curtains closed, deals open. Negotiates by candlelight." },
    { name = "Sconce Savant",             quote = "Pronounces it correctly. Will correct you. Politely. Once." },
    { name = "Cushion Cultist",           quote = "Worships the throw pillow. Performs daily devotions of fluffing." },
    { name = "Tapestry Tactician",        quote = "Reads battle scenes for fun. Knows who lost. Has theories." },
    { name = "Floorboard Footnoter",      quote = "Spreadsheet of every plank. Squeaks cross-referenced. Rankings exist." },
    { name = "Shelf Sheriff",             quote = "Books in strict order. Don't try anything. Don't even try." },
    { name = "Vase Voyager",              quote = "Travels for ceramics. Returns with three more than necessary." },
    { name = "Curtain Call Captain",      quote = "Drama in every room. Insists on the proper exit." },
    { name = "Tankard Trustee",           quote = "Each mug named. Refuses to lend any. Especially the favourites." },
    { name = "Pillow Plenipotentiary",    quote = "International peace via cushion arrangement. Treaties pending." },
    { name = "Hourglass Hierophant",      quote = "Counts time differently. Sand falls slower for the deserving." },
    { name = "Garden Gargoyle Inspector", quote = "Each statue judged. Most found wanting. None told." },
    { name = "Rune Rug Reader",           quote = "Sees stories in carpet patterns. The carpet has heard things." },
    { name = "Goblet Gourmand",           quote = "Prefers vintage. Of glassware. The contents are negotiable." },
    { name = "Mirror Magus",              quote = "All mirrors angled with intent. The reasons remain undisclosed." },
    { name = "Tile Trafficker",           quote = "Knows exactly where each tile came from. Will tell you. Twice." },
    { name = "Iron Lattice Lord",         quote = "Wrought metal in every doorway. None of it ironic. All of it heavy." },
    { name = "Crystal Cartographer",      quote = "Maps the manor by chandelier-light alone. Ink optional." },
    { name = "Marble Maven",              quote = "Veins matter. The stone variety AND the conversational." },
    { name = "Bronze Bench Beneficiary",  quote = "Sat on every garden bench in the kingdom. Reviews pending." },
    { name = "Stained Glass Statesman",   quote = "Each pane a treaty. The light through it the seal." },
    { name = "Birdbath Bureaucrat",       quote = "Incident reports filed for each visiting sparrow. In triplicate." },
    { name = "Hayloft Hierarch",          quote = "Bales arranged with theological precision. Cattle approve." },
    { name = "Forge Founder",             quote = "Soot stains as design choice. The craft is never done. Never." },
    { name = "Treasurer of Trinkets",     quote = "Each bauble catalogued. The insurance assessor wept." },
    { name = "Astrolabe Auteur",          quote = "Schedules dinner by celestial alignment. Insists the carrots agree." },
    { name = "Brewmaster of Ambiance",    quote = "Air pressure calibrated room by room. The mood obeys." },
    { name = "Chandelier Czar",           quote = "Counts crystals mid-conversation. Tracks the distractions afterward." },
    { name = "Bookcase Bishop",           quote = "Ordains the order. Dewey Decimal is merely a starting point." },
    { name = "Doorknob Decretist",        quote = "Opinions on each handle. Will share. Especially the brass." },
    { name = "Foyer Philosopher",         quote = "Greets every visitor with an existential question. None expected answers." },
    { name = "Wreath Wright",             quote = "Each one bound by hand. The callouses confirm it." },
    { name = "Plinth Patron",             quote = "Statues need pedestals. Pedestals need names. All named. Personally." },
    { name = "Carpet Curator-General",    quote = "Threads counted. Twice. Then once more for confidence." },
    { name = "Aquarium Almoner",          quote = "The fish are fed first. Always. Nothing else gets started." },
    { name = "Privy Provost",             quote = "Even the outhouse is themed. Especially the outhouse." },
    { name = "Knickknack Sovereign",      quote = "Crown of clutter. Throne of pillows. Robe woven from receipts." },
    { name = "Quilt Quartermaster",       quote = "Stitched the inventory by candlelight. The cat helped, mostly." },
    { name = "Coat-Stand Connoisseur",    quote = "One hat per hook. No exceptions. The cloak gets a pole." },
    { name = "Mosaic Margrave",           quote = "Tiles tell tales. Knows them all. Recites unprompted." },
}
