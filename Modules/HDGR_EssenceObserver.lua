-- HDG.EssenceObserver
-- ============================================================================
-- Per-character Essence of Lumber snapshot. On BAG_UPDATE (and bank open),
-- reads the current character's bag/bank count via BagObserver and dispatches
-- CHARACTER_ESSENCE_UPDATED so the reducer persists it under
-- account.characters[charKey].essenceStock. That per-char snapshot feeds the
-- chrome badge (account-wide total) + its cross-character hover.
--
-- Cross-character truth: WoW can't read another character's bags remotely, so
-- alts stay at their last-login snapshot; only the logged-in char is live.
--
-- Scope: Essence of Lumber is Soulbound -> it can never enter the Warband Bank,
-- so the split is bag/bank only (BagObserver's warband return is discarded).
--
-- Dedup: BAG_UPDATE fires on every slot change; only dispatch when this char's
-- (bag, bank) actually changed, so a decor loot / craft doesn't spam the store.
-- Debounce 0.3s coalesces the multi-event burst of a single stack move.

HDG = HDG or {}
HDG.EssenceObserver = HDG.EssenceObserver or {}
local EO = HDG.EssenceObserver

-- Returns nil during the boot window before SessionIdentity has dispatched.
local function getCharIdentity(state)
    local id = state.session.identity
    if id.charKey == "" then return nil end
    return id
end

function EO:Scan()
    local ident = getCharIdentity(HDG.Store:GetState())
    if not ident then return end
    local bag, bank = HDG.BagObserver:GetSplit(HDG.Constants.ESSENCE_OF_LUMBER_ITEMID)
    -- Dedup on the current char's last snapshot: skip an unchanged split.
    if self._lastKey == ident.charKey and self._lastBag == bag and self._lastBank == bank then
        return
    end
    self._lastKey, self._lastBag, self._lastBank = ident.charKey, bag, bank
    HDG.Store:Dispatch({
        type    = HDG.Constants.ACTIONS.CHARACTER_ESSENCE_UPDATED,
        payload = {
            charKey   = ident.charKey,
            name      = ident.name,
            realm     = ident.realm,
            class     = ident.class,
            classFile = ident.classFile,
            bag       = bag,
            bank      = bank,
        },
    })
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name = "EssenceObserver",
    dependencies = { "BagObserver" },
    -- No ownsBlizzardNamespaces: counts come through BagObserver (owner of
    -- C_Item.GetItemCount); this module only listens for bag/bank change events.
    blizzardEvents = {
        -- Burst on loot/craft/stack-split -> dirty-flag debounce, dedup catches
        -- the no-op case. Also covers the login bag-load burst (initial snapshot).
        BAG_UPDATE        = { handler = "OnChange", debounce = 0.3 },
        -- Bank open refreshes the cached bank count for an accurate split.
        BANKFRAME_OPENED  = { handler = "OnChange", debounce = 0.3 },
    },
    OnChange = function(self)
        EO:Scan()
    end,
})
