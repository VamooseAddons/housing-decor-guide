-- HDGR_DecorWidgets.lua
-- =============================================================================
-- Registry of per-item custom detail blocks ("special-case" decor). It is a
-- GATE + DATA registry, NOT a widget mounter: HDGR's detail pane is binding-
-- driven (declarative LayoutConfig + pure selectors), so LayoutConfig can't be
-- mounted dynamically. The registry maps an itemID -> a "special" key plus that
-- special's own constants; the detail pane's pure selectors consult KeyFor/Get,
-- and each special's WIDGET is declared per-kind in LayoutConfig + driven by its
-- own selectors. Adding a future special (e.g. an entire quest chain) is one
-- Register{} call here + its own selector/LayoutConfig block.
HDG = HDG or {}
HDG.DecorWidgets = HDG.DecorWidgets or {}
local DW = HDG.DecorWidgets
DW._byItem = DW._byItem or {}
DW._byKey  = DW._byKey  or {}

function DW:Register(entry)
    self._byItem[entry.itemID] = entry
    self._byKey[entry.key]     = entry
end

-- itemID -> special key (or nil). The vast majority of decor has no special
-- widget, so a miss is a valid state, not drift.
function DW:KeyFor(itemID)
    local e = self._byItem[itemID]
    return e and e.key   -- exception(nullable): most items have no special widget
end

function DW:Get(key) return self._byKey[key] end

-- ===== Shu'halo Perspective -- Sargle's Fortunes collect-set =================
-- Cravitz Lorent (Murder Row dungeon, first boss room) sells the painting
-- (246857) for gold cap, OR 999g if you hold all 13 of Sargle's Fortunes in your
-- bags. The 13 fortune itemIDs are LOCAL to this entry (special-purpose, not
-- global Constants). Verified 2026-06-19 in-game: itemID-ascending order == the
-- in-name "#N" (236359 = #1 ... 236387 = #13), so the array index IS the number.
DW:Register({
    itemID = 246857,
    key    = "shuhalo_fortunes",
    title  = "Sargle's Fortunes",
    note   = "999g if all owned, can be purchased from AH",
    items  = { 236359, 236365, 236366, 236367, 236368, 236369, 236370,
               236371, 236372, 236373, 236377, 236381, 236387 },
})
