-- HDG.CraftEventCollector
-- ============================================================================
-- Auto-decrement queue rows when crafts complete in-game.
--
-- Subscribes to TRADE_SKILL_ITEM_CRAFTED_RESULT. The event fires once per
-- completed craft with a CraftingItemResultData struct carrying:
--   itemID     -- item that was produced (matches queue row.itemID)
--   quantity   -- how many output items (may differ from craft count due
--                to multicraft procs; we still decrement by ONE craft)
--   multicraft -- extra count from multicraft proc (informational)
--
-- Matching strategy: walk the queue, find the FIRST row whose itemID equals
-- the event's itemID and whose remaining > 0. Dispatch CRAFT_QUEUE_DECREMENT
-- with that row's (position, recipeID) -- the reducer's match-by-tuple guards
-- against stale dispatches if the queue mutated between event + dispatch.
--
-- Why itemID match: the event doesn't expose recipeID directly. If two queue
-- rows share an itemID (e.g. different recipe ranks of the same output), the
-- first non-empty row wins. Edge case; CRAFT_QUEUE_ADD coalesces by recipeID
-- so duplicates only arise from rank variants.

HDG = HDG or {}
HDG.CraftEventCollector = HDG.CraftEventCollector or {}
local CEC = HDG.CraftEventCollector

function CEC:OnCraftResult(data)
    if not (data and data.itemID) then return end   -- exception(boundary): data is the Blizzard craft-result payload
    local state    = HDG.Store:GetState()
    local queue    = state.account.craft.queue
    if not queue then return end
    for position, row in ipairs(queue) do
        if row.itemID == data.itemID and (row.remaining or 0) > 0 then  -- exception(boundary): queue row from SVars may lack remaining
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.CRAFT_QUEUE_DECREMENT,
                payload = { position = position, recipeID = row.recipeID, qty = 1 },
            })
            -- Push a crafted history record alongside the decrement (one craft event -> one history entry).
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.CRAFT_HISTORY_PUSH,
                payload = {
                    eventType = "crafted",
                    recipeID  = row.recipeID,
                    itemID    = data.itemID,
                    qty       = 1,
                    completed = true,
                    timestamp = (_G.time and _G.time()) or 0,
                },
            })
            return
        end
    end
end

-- ===== Module registration ===================================================
HDG.Modules:Declare({
    name = "CraftEventCollector",
    dependencies = {},
    blizzardEvents = {
        TRADE_SKILL_ITEM_CRAFTED_RESULT = { handler = "OnCraftResult" },
    },
    OnCraftResult = function(self, data)
        CEC:OnCraftResult(data)
    end,
})
