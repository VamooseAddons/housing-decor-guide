-- HDG.ZoneController -- wirings + row factory for the Zone Scanner view.
--
-- Two row kinds:
--   vendor   "Vendor Name (3 unc / 1 wish)" header + pin button
--   item     icon + name + gold + collected/shopping markers + chips strip
--
-- Click on vendor row toggles expanded state (dispatches ZONE_TOGGLE_VENDOR).
-- Click on item row resolves a primary vendor + opens map at the vendor's
-- coordinates (waypoints chain).

HDG = HDG or {}
HDG.ZoneController = HDG.ZoneController or {}
local ZoneController = HDG.ZoneController
local CH = HDG.ControllerHelpers

local A = HDG.Constants.ACTIONS

-- ===== Item-name / icon resolvers ===========================================
-- Resolve* returns nil on cache miss + queues warm-up; session.itemNames.tick
-- re-fires the selector once name/icon lands. -- engine-internal
local function resolveItemIcon(itemID)
    return HDG.ItemNameResolver:ResolveIcon(itemID)
end

-- ===== Row factory =========================================================

local function _ensureItemChrome(row)
    if row._zoneItemChromeBuilt then return end

    -- ARTWORK: above EnsureRowChrome's BACKGROUND fills (zebra/selectedBg).
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 24, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row._iconTex = icon

    -- Chips strip (re-uses HDG.UI.GateChips -- single palette across Acquire
    -- + Shopping + Zone).
    local chips = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(chips, "caption")
    chips:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    chips:SetJustifyH("RIGHT")
    row._chipsFs = chips

    -- Collected / on-shopping-list mini-markers right of chips. Pure icons
    -- (no atlas button -- non-interactive). Visible/hidden per row.
    local collMark = row:CreateTexture(nil, "OVERLAY")
    collMark:SetSize(12, 12)
    collMark:SetPoint("RIGHT", row, "RIGHT", -32, 0)
    collMark:SetAtlas("checkmark-minimal")
    collMark:Hide()
    row._collMark = collMark

    local cartMark = row:CreateTexture(nil, "OVERLAY")
    cartMark:SetSize(12, 12)
    cartMark:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    cartMark:SetAtlas("communities-chat-icon-plus")
    cartMark:Hide()
    row._cartMark = cartMark

    row._zoneItemChromeBuilt = true
end

local function _ensureVendorChrome(row)
    if row._zoneVendorChromeBuilt then return end
    -- Pin button at RIGHT -4 (waypoint atlas).
    local pin = HDG.UI:AtlasButton(row, "Waypoint-MapPin-ChatIcon", 14)
    pin:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    pin:Hide()
    row._zonePinBtn = pin
    row._zoneVendorChromeBuilt = true
end

local function _hideAllChrome(row)
    if row._zoneItemChromeBuilt then
        row._iconTex:Hide()
        row._chipsFs:SetText("")
        row._collMark:Hide()
        row._cartMark:Hide()
    end
    if row._zoneVendorChromeBuilt then
        row._zonePinBtn:Hide()
    end
end

local function _showItemChrome(row, ed)
    _ensureItemChrome(row)
    row._iconTex:SetTexture(resolveItemIcon(ed.itemID) or HDG.Constants.PLACEHOLDER_ICON)  -- exception(boundary): item-icon resolver cold cache
    row._iconTex:Show()
    -- Chips strip omitted in compact mode (320px) -- clips the name.
    -- The fontstring stays in the pool to keep layout uniform across reuses.
    row._chipsFs:SetText("")
    -- Mini-markers: collected (checkmark) + on-shopping-list (cart-plus).
    if ed.collected then row._collMark:Show() end
    if ed.onShoppingList then row._cartMark:Show() end
end

local function _showVendorPin(row, ed)
    _ensureVendorChrome(row)
    local mapID, x, y, name = ed.mapID, ed.x, ed.y, ed.name
    row._zonePinBtn:SetScript("OnClick", function()
        if mapID and mapID > 0 and x and y and HDG.Waypoints then
            HDG.Waypoints:Set(mapID, x, y, name)   -- :Set emits the chat message
        end
    end)
    row._zonePinBtn:Show()
end

-- Lazy chrome: name (left, body) + right caption stat. One-time per pooled row.
local function _layoutZoneRow(row)
    HDG.UI:EnsureRowChrome(row)
    local name = HDG.UI.RowText(row, "body", "Text", "LEFT")
    row._nameFs = name

    local right = HDG.UI.RowText(row, "caption", "TextDim", "RIGHT")
    row._rightFs = right

    row._zoneLaidOut = true
end

-- Scrub prior paint before re-binding to this acquire's entry.
local function _resetZoneRow(row)
    row._nameFs:SetText("")
    row._rightFs:SetText("")
    row._nameFs:ClearAllPoints()
    row._rightFs:ClearAllPoints()
    row:SetScript("OnClick", nil)
    row:RegisterForClicks("LeftButtonUp")
    _hideAllChrome(row)
end

-- Vendor header row: "+/- name" left, "(N unc / M wish)" right, toggles collapse.
local function _paintZoneVendor(row, ed)
    row:SetHeight(22)
    row._nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._nameFs:SetPoint("RIGHT", row, "RIGHT", -120, 0)
    row._rightFs:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row._nameFs:SetText(HDG.UI.CollapsePrefix(ed.collapsed) .. ed.name)
    -- "3 unc / 1 wish" -- skip the slash + wish part when no SL hits.
    local parts = { tostring(ed.uncollectedCount) .. " unc" }
    if ed.shoppingListCount > 0 then
        parts[#parts + 1] = tostring(ed.shoppingListCount) .. " wish"
    end
    row._rightFs:SetText("(" .. table.concat(parts, " / ") .. ")")
    row:SetScript("OnClick", function()
        HDG.Store:Dispatch({
            type    = A.ZONE_TOGGLE_VENDOR,
            payload = { npcID = ed.npcID },
        })
    end)
    _showVendorPin(row, ed)
end

-- Item child row: name + collected/cart mini-markers. Compact 320px popup.
local function _paintZoneItem(row, ed)
    row:SetHeight(20)
    -- 320px-wide popup: tight anchor budget. Name starts after
    -- the icon (LEFT 44 = LEFT 24 indent + 16 icon + 4 gap),
    -- right-capped at -50 to leave room for the 2 mini-markers
    -- (collMark + cartMark, each 12 wide). Gold cost omitted in
    -- compact mode -- too noisy at 280 content px; user gets
    -- gold in the tooltip when they need it.
    row._nameFs:SetPoint("LEFT", row, "LEFT", 44, 0)
    row._nameFs:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    row._rightFs:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    row._nameFs:SetText(HDG.UI.ItemName(ed.itemID))
    row._rightFs:SetText("")
    _showItemChrome(row, ed)
end

local function _zoneRowFactory(template)
    return {
        Configure = function(row, ed)
            if not row._zoneLaidOut then _layoutZoneRow(row) end
            _resetZoneRow(row)
            if ed.kind == "vendor" then
                _paintZoneVendor(row, ed)
            elseif ed.kind == "item" then
                _paintZoneItem(row, ed)
            end
            HDG.Theme:Register(row, "RowChrome", { selected = false })
        end,
        Reset = function(row)
            if row._nameFs  then row._nameFs:SetText("")  end
            HDG.UI.ClearRowText(row, "_rightFs")
            row:SetScript("OnClick", nil)
            _hideAllChrome(row)
        end,
    }
end

HDG.Rows:Register("zoneRow", {
    font    = "body",
    height  = 20,
    factory = _zoneRowFactory,
    key     = function(ed)
        if ed.kind == "vendor" then return "v_" .. tostring(ed.npcID) end
        if ed.kind == "item"   then return "i_" .. tostring(ed.npcID) .. "_" .. tostring(ed.itemID) end
        return "?"
    end,
})

-- ===== Controller wirings ===================================================

function ZoneController:Wire(rootFrame)
    -- Window chrome close [X]. Dismisses the zone floating window by
    -- flipping account.ui.zonePopupShown off. HDG.Window's reconciler
    -- owns the resulting Hide() via visibilityBinding (zone.popupShown).
    HDG.UI.OnClick(rootFrame, "zoneHeaderPanel.close", function()
        HDG.Store:Dispatch({ type = A.ZONE_POPUP_TOGGLE })
    end)

    -- Controllers:WireAll fires against every frame; bail early when
    -- zonePanel widgets are absent (standalone lumber/shopping windows).
    local sb = HDG.UI.W(rootFrame, "zonePanel.searchBox")
    if not sb then return end
    sb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = (self.GetText and self:GetText()) or ""
        HDG.Store:Dispatch({
            type    = A.ZONE_SET_SEARCH,
            payload = { text = text },
        })
    end)

    -- Show-collected toggle: flips session.ui.zoneScanner.showCollected.
    HDG.UI.OnClick(rootFrame, "zonePanel.showCollectedBtn", function()
        HDG.Store:Dispatch({ type = A.ZONE_TOGGLE_COLLECTED, payload = nil })
    end)
    -- Dynamic tooltip: reads showCollected at hover so the text never goes stale.
    local scBtn = HDG.UI.W(rootFrame, "zonePanel.showCollectedBtn")
    if scBtn then HDG.TooltipEngine:Attach(scBtn, HDG.TooltipRecipes.ZoneShowCollected) end

    -- Map All -- set waypoints for every visible vendor.
    HDG.UI.OnClick(rootFrame, "zonePanel.mapAllBtn", function()
        local state = HDG.Store:GetState()  -- exception(false-positive): top-level controller method (not a row factory)
        local vendors = HDG.Selectors:Call("zone.filteredVendors", state, {})
        -- RunBatch emits ONE consolidated chat line for the whole batch.
        HDG.Waypoints:RunBatch(function()
            for _, v in ipairs(vendors) do
                if v.mapID > 0 and v.x and v.y and HDG.Waypoints then
                    HDG.Waypoints:Set(v.mapID, v.x, v.y, v.name)
                end
            end
        end)
    end)
end

function ZoneController:Refresh(rootFrame, ctx)
    -- Bindings handle paint; nothing imperative.
end

HDG.Controllers:Register("zoneScanner", ZoneController)
