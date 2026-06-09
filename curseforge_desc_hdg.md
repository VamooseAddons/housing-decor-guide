# Vamoose's Housing Decor Guide

**Every housing decoration in the game, in one addon.** Browse the full catalog with 3D previews, see exactly where each piece comes from, track collection progress across your whole account, plan and craft what you need, design rooms before you build them, and even place decor straight from the House Editor.

---

## Featured on Wowhead & Icy Veins!

> *"Track, Craft, Buy, and Sell Housing Decor"*

[Read the full article on Wowhead](https://www.wowhead.com/news/track-craft-buy-and-sell-housing-decor-with-vamooses-housing-decor-crafting-380335?utm_source=hdg)

---

## What's New in v3.1.1

Since the v3.0 ground-up rebuild, a steady run of additions and fixes:

**New**

- **Localization is back** -- the interface and tooltips are now translatable, with first-pass German, Spanish (Spain & Latin America), French, Italian, Korean, Portuguese (Brazil), Russian, and Chinese (Simplified & Traditional). Leave it on Auto to follow your client or pick a language in the addon options; decoration, vendor, and zone names always come straight from the game.
- **Shift-click to queue** -- Shift-click any recipe, Goblin profit row, or craftable in Find Decor to send it straight to the craft queue.
- **Multi-select Acquire filters** -- tick several values in the Expansion / Zone / Reputation / Sources / faction menus to widen a search (e.g. Cataclysm *and* Pandaria), shared across Shop by Vendor and Find Decor.
- **Shopping List auto-sorts into three lanes** -- vendor-bought (matched to their seller from the live catalog, even on import), a "Crafting / Auction House" section for crafted decor (one-click send the batch to the queue *or* to Auctionator), and a Wishlist for what you truly can't buy.
- **Recipe status at a glance** -- recipe and Goblin tooltips now show whether you already own the decor it makes and whether you've learned the recipe.
- **Goblin auction velocity** -- three new sortable columns: TSM sale Rate and per-day average, plus current #AH listings on your realm.

**Fixes**

- **Non-English clients** now render correct room shapes, labels, and placement cost in the Architect (rooms had been matched by localized name against an English-only table).
- **Lumber Tracker** session and history counts now reflect only what you gather into your bags -- bank/warband stock loading in no longer shows as phantom "+N this session" or fake sessions.
- **Send to Auctionator** again exports the buy *gap* -- each missing reagent with the quantity you still need, as an exact-name search.
- **Find Decor's "Crafted" filter** lists only truly craftable decor, and vendor locations always come from the curated data so Find-by-Item and Shop-by-Vendor agree on where a seller is.
- **Architect captures** no longer duplicate multi-floor rooms (stairwells, gardens), and a room's door points at the room it actually shares a wall with.
- **Vendor waypoints** land in the right place (e.g. Maku now points into The Den, not across Harandar), and primary action buttons keep their label on hover.

> Upgrading from v2.x: your data carries over automatically; settings reset to new defaults (re-apply your theme/minimap in **Config**), and house projects need re-capturing from inside your house.

---

## The Decor Catalog

- **Every piece from the in-game Housing Catalog** in one searchable list -- favorites, a collected check, a craftable-recipe star, and dye-variant color dots at a glance.
- **Compose filters** across Crafted (by profession), Sizes, Styles, Expansions, Sources (vendor / quest / achievement / reputation / crafted / ...), and more -- with a live "collected / shown" status readout and one-click Reset.
- **Uncollected** toggle to focus on what you're missing; **Destroy Decor** toggle to manage stored duplicates (with a safe, confirmed destroy dialog).
- **3D model preview** of any piece -- rotate, zoom, swap the backdrop, and preview specific dye variants.
- **Rich detail card**: category breadcrumb, size, source, owned/stored/placed counts, first-acquisition House XP bonus, and style/faction tags.
- **Private notes** per item and a one-click **+ Wishlist** that adds to your active shopping list.

## Acquire -- where every piece comes from

**Shop by Vendor:** browse every decor vendor (searchable; filter by faction, expansion, zone, reputation, or source). Each vendor shows what they sell -- items *and* recipe scrolls -- with gold/currency costs, multiple payment options, and live **[QUEST] / [ACH] / [REP]** gate chips that brighten as you meet them. A map thumbnail plus **Waypoint** and **Map** buttons get you there; **Map N Vendors** pins a whole filtered list at once.

**Find Decor:** search any piece and see exactly how to get it -- a typed source line with the reputation faction *and your live progress*, a clickable achievement link, the **alt who completed the quest** (account-wide), craft/drop tags, and an "Available from" list of every vendor that sells it. **Add to Cart**, copy Wowhead links, or jump straight to a vendor.

## Crafting

- **Recipes** -- browse craftable decor across professions and expansions. Filter by **Known / Ready / Unknown** -- "Ready" buckets recipes by how much of the materials you already hold, and "Unknown" finds recipes *nobody on your account* has yet. Queue crafts, preview the result in 3D, and see a materials panel (totals or per-recipe, direct or fully raw, bucketed by source) with an AH cost estimate.
- **Warehouse** -- track lumber and every reagent (bag / bank / warband bank, separately), how much you need for your queue *and* for all uncollected recipes, and a "Used In" cross-reference so you know what's worth farming. Lumber tracker auto-pops when you harvest lumber.
- **Trainers** -- a profession trainer directory by expansion and faction, each with location, coordinates, and a one-click waypoint, plus a dedicated **Midnight Recipe Sources** table.
- **Alts** -- an account-wide grid of your best skill in every profession across every expansion, with per-character detail and decor-recipe completeness so you always know which alt to log in.

## Lumber Tracker & Radar

Housing crafting runs on lumber, so there's a dedicated **Lumber Tracker** -- a standalone window with a live **circular radar** that plots nearby lumber nodes as blips around you (with your facing and the cardinal directions), built from the spots the addon records each time you harvest. Start a farming **session** to track how much you've gathered and your rate, see your stock versus what your craft queue still needs per lumber type, and let it pop up automatically when you start cutting. Session history feeds the Warehouse and Your Data tabs.

## Mogul -- make gold (or finish your collection) from decor

- **Goblin** -- a profit table for every craftable: material cost, sell price, profit, margin %, and gold-per-lumber, sortable and filterable, with a per-reagent cost breakdown on each row. Prices from TSM, Auctionator, a live AH scan, or vendor fallback.
- **Optimizer** -- ranks your recipes by **profit** *or* by **new appearances** for collection. Choose owned-mats vs buy-from-AH, scope to one character or the whole account, then **Queue All** or push the shopping list straight to Auctionator.

## Styles -- organize and design

- **Browse** -- all your sets in one place: My Styles, Smart Sets, Shopping Lists, Snapshots, plus pre-authored Room Concepts and Useful Collections, each with a preview strip and collection count.
- **Style Curator** -- a workspace to file your decor into named styles: pick a source, multi-select from a category-browsable grid, move into a target style, with single-step undo and a coverage bar showing how much of your collection is organized.
- **Smart Sets** -- build filter-based sets from a deep tag taxonomy (room, mood, material, color, culture, motif, season, and more). Mark tags **Signature / Accent / Clashing** and watch a live, scored preview update against the whole catalog.
- **Snapshots** -- capture everything you've placed in a house as a saved set.
- **Import** -- paste a Wowhead URL, item IDs, or any list of numbers to build a shopping list instantly.

## Projects -- plan your house before you build

- **Architect** -- a drag-and-drop blueprint canvas: lay out rooms across floors, watch live room and decor budget bars, and assign decor "crates" to each room. Branch "what-if" versions to experiment freely.
- **Layouts** -- manage every saved version, load one into the Architect, and **share** a layout as a compact code (or import someone else's).
- **Move Planner** -- moving plots? Pick source and target and get the exact rotation (degrees + compass direction) your house and yard will need, with neighborhood maps and door-facing diagrams. *(Rotation key courtesy of Blue, Art of Azeroth.)*

## House -- your collection at a glance

A personal dashboard: decorator profile with house level, favor, and Collector title progress; collection donuts by source and by expansion; "close to complete" and themed-set progress; House-XP "hot picks"; acquisition velocity and storage capacity; lumber wallet and decor currencies; favorites, recent activity, and your top uncollected-from vendors. **Fully customizable** -- toggle and drag-reorder every widget.

## Right inside the House Editor

A companion window injects into Blizzard's House Editor so you can **place decor with one click** -- browse by your styles, shopping lists, snapshots, room concepts, or what you've placed recently. Indoor/outdoor filtering, placement-cost display, and dye variants are all handled for you.

## Tools

- **Shopping** -- a floating, multi-list shopping manager grouped by zone and vendor, with "Waypoint All" and share/import codes.
- **Zone alerts** -- entering a zone with a decor vendor (selling something you're missing or have listed) can pop a window, ping chat, and play a sound -- each toggle optional.
- **Your Data** -- collection KPIs, achievement progress (decor, coupons, lumber milestones), and full crafting/farming history.
- **Config** -- multiple color themes with a live preview, UI scaling, and account profiles.

## Integrations (all optional)

- **TradeSkillMaster / Auctionator** for pricing (and push shopping lists straight into Auctionator)
- **TomTom** for waypoints (falls back to Blizzard's native pin)
- **Wowhead / wowdb** build import

## Quick Start

1. Install and log in -- your old HDG data upgrades automatically.
2. Open with `/hdg` (or the minimap button / addon compartment).
3. Start in **Decor** to browse, **Acquire** to find pieces, or **House** for your dashboard.

## Requirements

- World of Warcraft Retail **12.0.5+ (Midnight)**
- No dependencies. TSM, Auctionator, and TomTom are optional enhancers.

---

**Author:** Vamoose
**Version:** 3.1.1
**Game Version:** 12.0.5+ (Midnight)
**Source / Issues:** https://github.com/VamooseAddons/housing-decor-guide
**Discord:** https://discord.gg/RWZaxJaHFP
