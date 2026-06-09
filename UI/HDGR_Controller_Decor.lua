-- HDG.DecorController
-- ============================================================================
-- Decor browser: filter strip (top chips, toggles, search, tag slots),
-- decorRow factory, note editbox, variant swatches, wishlist + destroy dialog.

HDG = HDG or {}
HDG.DecorController = HDG.DecorController or {}

local DecorController = HDG.DecorController
local CH = HDG.ControllerHelpers

-- ===== Row factory ==========================================================
-- [fav 14x14] [name] ... [collected 12x12] [craftable 12x12]
-- MakeRowFactory row: layout builds texture children; paint writes per-paint values.

local ATLAS_FAV_FILLED   = "delves-scenario-heart-icon"        -- ships pre-tinted red
local ATLAS_CHECK        = "common-icon-checkmark"
local ATLAS_CRAFT_STAR   = "auctionhouse-icon-favorite-off"    -- outline variant; accepts SetVertexColor (filled = baked gold)

-- ===== decorRowFactory primitives ============================================

local function _layoutDecorRow(row)
    HDG.TooltipEngine:Attach(row, HDG.TooltipRecipes.DecorRow)

    local fav = row:CreateTexture(nil, "OVERLAY")
    fav:SetSize(14, 14)
    fav:SetPoint("LEFT", row, "LEFT", 4, 0)
    fav:SetAtlas(ATLAS_FAV_FILLED)
    row._favStar = fav

    -- Stored-count badge: swapped in over the fav slot when ed.inStoredMode.
    local storedFs = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(storedFs, "small")
    HDG.Theme:Register(storedFs, "Text")
    storedFs:SetPoint("LEFT", row, "LEFT", 2, 0)
    storedFs:SetWidth(18)
    storedFs:SetJustifyH("CENTER")
    row._storedCountFs = storedFs

    local name = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(name, "subheading")
    HDG.Theme:Register(name, "Text")
    name:SetPoint("LEFT",  fav, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    name:SetJustifyH("LEFT")
    row._nameFs = name

    -- Collected check (right -- second column from edge)
    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(12, 12)
    check:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    check:SetAtlas(ATLAS_CHECK)
    row._checkIcon = check

    -- Craftable star (right edge)
    local star = row:CreateTexture(nil, "OVERLAY")
    star:SetSize(12, 12)
    star:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    star:SetAtlas(ATLAS_CRAFT_STAR)
    row._craftStar = star

    -- Dye droplets (up to 3): NOT Theme:Register'd (the dye color IS the color; a skinner would clobber it).
    row._droplets = {}
    for i = 1, 3 do
        local d = row:CreateTexture(nil, "OVERLAY")
        d:SetSize(8, 10)
        d:SetAtlas("dye-drop_32")
        d:Hide()
        row._droplets[i] = d
    end
end

-- Left-edge column: stored-count badge (Stored mode) or favorite heart. Badge takes priority.
local function _paintFavOrStored(row, ed)
    if ed.inStoredMode and (ed.destroyableCount or 0) > 0 then  -- exception(boundary): sparse decor struct field
        if row._favStar       then row._favStar:Hide() end
        if row._storedCountFs then
            row._storedCountFs:SetText(tostring(ed.destroyableCount))
            row._storedCountFs:Show()
        end
        return
    end
    if row._storedCountFs then row._storedCountFs:Hide() end
    if row._favStar then
        if ed.isFavorite then row._favStar:Show() else row._favStar:Hide() end
    end
end

-- Collected checkmark from ed.isCollected (canonical predicate via decor.isCollected).
local function _paintCheckmark(row, ed)
    if not row._checkIcon then return end
    if ed.isCollected then row._checkIcon:Show() else row._checkIcon:Hide() end
end

-- Name: uncollected -> accent, collected -> normal text. ed.name stays raw for search/toasts.
local function _paintName(row, ed)
    if not row._nameFs then return end
    row._nameFs:SetText(HDG.Theme:CollectionLabel(ed.isCollected, ed.name))
end

-- Dye droplets: ed.dyeColorIDs is the flat channel-ordered list (sparse 0/1/2, bake-collapsed).
-- Tinted via swatchColorStart; name right bound tightened to reserve the droplet zone.
local function _paintDroplets(row, ed)
    local ids = ed.dyeColorIDs
    local n   = (ids and #ids) or 0
    for i = 1, 3 do
        local d = row._droplets[i]
        local dyeColorID = ids and ids[i]
        if dyeColorID then
            d:ClearAllPoints()
            d:SetPoint("RIGHT", row, "RIGHT", -34 - (i - 1) * 9, 0)
            local info = HDG.HousingCatalogObserver:GetDyeColorInfo(dyeColorID)
            if info and info.swatchColorStart then
                HDG.UI._TintTexture(d, info.swatchColorStart); d:SetAlpha(1)  -- data: the dye's actual swatch color (runtime)
            else
                HDG.UI._TintTexture(d, { r = 1, g = 1, b = 1 }); d:SetAlpha(0.2)  -- data: no dye -> blank swatch
            end
            d:Show()
        else
            d:Hide()
        end
    end
    -- Reserve name space when droplets present (-34 default; -34 each paint is
    -- a harmless no-op for the common non-variant row).
    row._nameFs:SetPoint("RIGHT", row, "RIGHT", n > 0 and (-34 - n * 9 - 2) or -34, 0)
end

-- Left = select, right = favorite toggle. Toast reads state BEFORE dispatch (sync Store; order matters).
local function _wireDecorClicks(row, ed)
    local itemID = ed.itemID
    if not itemID then
        HDG.UI.WireLeftRightClick(row, nil, nil)
        return
    end
    local variantKey = ed.variantKey
    HDG.UI.WireLeftRightClick(row,
        function()
            -- Shift-click queues the item's recipe (decor rows carry no recipeID,
            -- so resolve it via the Professions reverse index); non-craftable
            -- decor toasts a "no recipe" note instead. A plain click selects.
            if IsShiftKeyDown() then
                local rid = HDG.StaticData.Recipes:Get(itemID) and itemID
                if rid then
                    HDG.UI.QueueRecipe(rid, itemID, ed.name)
                else
                    HDG.Log:Debug("queue", ed.name .. " has no recipe")
                end
                return
            end
            -- selectedItemID drives the detail pane (base item data); the
            -- separate selectedVariantKey drives the list highlight + the dyed
            -- model preview (which specific owned variant was clicked).
            CH.Mechanics.SetUITransientView("decor", "selectedItemID", itemID)
            CH.Mechanics.SetUITransientView("decor", "selectedVariantKey", variantKey)
        end,
        function()
            local wasFav = HDG.Store:GetState().account.favorites[itemID]  -- exception(false-positive): top-level controller read
            HDG.Store:Dispatch({
                type    = HDG.Constants.ACTIONS.FAVORITE_TOGGLE,
                payload = { itemID = itemID },
            })
            HDG.Log:Info("decor_action",
                (wasFav and "Unfavorited: " or "Favorited: ") .. ((ed and ed.name) or "item"))
        end)
end

local function _paintDecorRow(row, ed)
    row._itemID, row._name = ed.itemID, ed.name   -- R2 tooltip stamps
    _paintName(row, ed)
    _paintDroplets(row, ed)
    _paintFavOrStored(row, ed)
    _paintCheckmark(row, ed)
    if row._craftStar then
        HDG.UI:PaintCraftStar(row._craftStar, ed.craftableState,
            HDG.Constants.RECIPE_STATE.NotARecipe)
    end
end

HDG.Rows:Register("decorRow", {
    font    = "body",
    height  = 24,
    factory = HDG.UI.MakeRowFactory({
        layout     = _layoutDecorRow,
        paint      = _paintDecorRow,
        laidOutTag = "_decorLaidOut",
        selectable = true,
        wire       = _wireDecorClicks,
        resetText  = { "_nameFs" },
        reset      = function(row)
            row._itemID, row._name = nil, nil  -- clear R2 tooltip stamps
            if row._favStar   then row._favStar:Hide()   end
            if row._checkIcon then row._checkIcon:Hide() end
            if row._craftStar then row._craftStar:Hide() end
            -- pre-layout: _droplets nil until _layoutDecorRow runs on a fresh slot.
            if row._droplets then for i = 1, 3 do row._droplets[i]:Hide() end end
        end,
    }),
    -- variantKey = itemID:<variant>|base (stamped by decor.items); itemID alone collides for variant rows.
    key     = function(ed) return ed.variantKey end,
})

-- ===== Controller lifecycle ==================================================

-- ===== Destroy stored-copies dialog =========================================
-- Custom modal with 1-99 stepper. Destruction is irreversible; layered guards:
--   1. Show: refuse without valid entryID + count.
--   2. Show: clamp max to min(99, destroyableInstanceCount).
--   3. +/-: re-check bounds before mutating qty.
--   4. Render: refreshDestroyDialog re-clamps qty each paint.
--   5. Click: snapshot entryID/name/q into locals (HOUSING_STORAGE_ENTRY_UPDATED
--      dispatches synchronously inside DestroyEntry -- can't read stale state).
--   6. Click: type-validate q; math.floor.
--   7. Click: re-resolve live destroyable count; clamp DOWN only.
--   8. Click: disable Destroy button for the loop (double-click guard).
--   9. Loop: pcall each DestroyEntry; API bounds naturally limit over-loop.
--  10. Hide: clear entryID + name to prevent stale reuse.

local _destroyDialog
local _destroyState = { qty = 1, max = 1, entryID = nil, name = nil }

-- Snapshot destroy params; returns nil on any invalid input (destruction must not proceed ambiguously).
local function validateDestroyArgs(entryID, q, max)
    if entryID == nil then return nil end
    if type(q)   ~= "number" or q ~= q then return nil end   -- nil / NaN
    if type(max) ~= "number" or max < 1 then return nil end
    q = math.floor(q)
    if q < 1 then return nil end
    if q > max then q = max end
    return q
end

-- Live destroyable count: final gate before the loop (player may have destroyed copies elsewhere).
local function liveDestroyableCount(entryID)
    if not entryID then return 0 end
    local cat = _G.C_HousingCatalog
    if not (cat and cat.GetCatalogEntryInfo) then return 0 end
    local ok, info = pcall(cat.GetCatalogEntryInfo, entryID)
    if not ok then
        HDG.Log:Warn("decor", "GetCatalogEntryInfo failed: " .. tostring(info))
        return 0
    end
    if type(info) ~= "table" then return 0 end
    return info.destroyableInstanceCount or 0   -- exception(boundary): Blizz C_HousingCatalog struct sparse
end

local function buildDestroyDialog()
    local f = CreateFrame("Frame", "HDGR_DestroyConfirmDialog", _G.UIParent, "BackdropTemplate")   -- exception(boundary): UIParent strata; global name for WoW frame-stacking
    f:SetSize(440, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- The Frame skinner paints surface.panel + border.default via
    -- setBackdrop (Theme.lua:253). HDG.UI:CopyDialog uses the same.
    -- There is no "Panel" skinner registered -- that silently no-ops.
    HDG.Theme:Register(f, "Frame")
    f:Hide()

    f.titleFs = f:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(f.titleFs, "heading")
    HDG.Theme:Register(f.titleFs, "Text")
    f.titleFs:SetPoint("TOP", 0, -18)
    f.titleFs:SetWidth(400)
    f.titleFs:SetJustifyH("CENTER")
    f.titleFs:SetSpacing(2)

    f.bigWarnFs = f:CreateFontString(nil, "OVERLAY")   -- semantic.error; destructive-action emphasis
    HDG.UI.applyFontRole(f.bigWarnFs, "subheading")
    HDG.Theme:Register(f.bigWarnFs, "Text")
    f.bigWarnFs:SetPoint("TOP", f.titleFs, "BOTTOM", 0, -16)
    f.bigWarnFs:SetWidth(400)
    f.bigWarnFs:SetJustifyH("CENTER")

    -- Sub note: friendly elaboration on the irreversibility.
    f.subNoteFs = f:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(f.subNoteFs, "body")
    HDG.Theme:Register(f.subNoteFs, "TextDim")
    f.subNoteFs:SetPoint("TOP", f.bigWarnFs, "BOTTOM", 0, -6)
    f.subNoteFs:SetWidth(400)
    f.subNoteFs:SetJustifyH("CENTER")
    f.subNoteFs:SetSpacing(2)

    -- Stepper row: anchored from BOTTOM so position is fixed regardless of warning text wrap.
    local stepperRow = CreateFrame("Frame", nil, f)
    stepperRow:SetSize(200, 32)
    stepperRow:SetPoint("BOTTOM", 0, 76)
    f.stepperRow = stepperRow

    f.minusBtn = HDG.UI:Button(stepperRow, "-", "heading")
    f.minusBtn._hdgrVariant = "tertiary"
    HDG.Theme:Register(f.minusBtn, "Button")
    f.minusBtn:SetSize(32, 32)
    f.minusBtn:ClearAllPoints()
    f.minusBtn:SetPoint("CENTER", stepperRow, "CENTER", -56, 0)

    f.qtyFs = stepperRow:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(f.qtyFs, "heading")
    HDG.Theme:Register(f.qtyFs, "Text")
    f.qtyFs:SetPoint("CENTER", stepperRow, "CENTER", 0, 0)
    f.qtyFs:SetWidth(80)
    f.qtyFs:SetJustifyH("CENTER")

    f.plusBtn = HDG.UI:Button(stepperRow, "+", "heading")
    f.plusBtn._hdgrVariant = "tertiary"
    HDG.Theme:Register(f.plusBtn, "Button")
    f.plusBtn:SetSize(32, 32)
    f.plusBtn:SetPoint("CENTER", stepperRow, "CENTER", 56, 0)

    f.stepperMaxFs = f:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(f.stepperMaxFs, "small")
    HDG.Theme:Register(f.stepperMaxFs, "TextDim")
    f.stepperMaxFs:SetPoint("TOP", stepperRow, "BOTTOM", 0, -4)
    f.stepperMaxFs:SetWidth(400)
    f.stepperMaxFs:SetJustifyH("CENTER")

    f.destroyBtn = HDG.UI:Button(f, "Destroy", "body")
    f.destroyBtn._hdgrVariant = "tertiary"
    f.destroyBtn._textTone = "error"
    HDG.Theme:Register(f.destroyBtn, "Button")
    f.destroyBtn:SetSize(140, 30)
    f.destroyBtn:SetPoint("BOTTOMLEFT", 50, 24)

    f.cancelBtn = HDG.UI:Button(f, "Cancel", "body")
    f.cancelBtn._hdgrVariant = "tertiary"
    HDG.Theme:Register(f.cancelBtn, "Button")
    f.cancelBtn:SetSize(140, 30)
    f.cancelBtn:SetPoint("BOTTOMRIGHT", -50, 24)
    f.cancelBtn:SetScript("OnClick", function() f:Hide() end)

    -- OnHide: clear state + re-enable Destroy button (prevents stale reuse by future Show).
    f:SetScript("OnHide", function()
        _destroyState.entryID = nil
        _destroyState.name    = nil
        _destroyState.qty     = 1
        if f.destroyBtn and f.destroyBtn.SetEnabled then
            f.destroyBtn:SetEnabled(true)
        end
    end)

    return f
end

local function refreshDestroyDialog()
    if not _destroyDialog then return end
    local f   = _destroyDialog
    local st  = _destroyState
    -- Coerce garbage state: shouldn't happen via Show/+/- paths but guards future callers.
    if type(st.qty) ~= "number" then st.qty = 1 end
    if type(st.max) ~= "number" or st.max < 1 then st.max = 1 end
    if st.qty < 1       then st.qty = 1       end
    if st.qty > st.max  then st.qty = st.max  end
    local accentCC  = HDG.Theme:ColorCode("semantic.accent")
    local errorCC   = HDG.Theme:ColorCode("semantic.error")
    -- Title: "Destroy N copy/copies of <Name>?"
    f.titleFs:SetText(string.format("Destroy %d %s of\n%s%s|r?",
        st.qty,
        st.qty == 1 and "copy" or "copies",
        accentCC, st.name or "this decor"))
    -- Big warning + sub-note. The warning is colored error and the sub-
    -- note remains dim so the hierarchy reads loud-then-quiet.
    f.bigWarnFs:SetText(errorCC .. "WARNING: This cannot be undone.|r")
    f.subNoteFs:SetText(
        "Destroyed decor is gone permanently.\n" ..
        "If this was a mistake, Vamoose is very sorry -- there is nothing he can do.")
    -- Stepper qty + live max caption.
    f.qtyFs:SetText(tostring(st.qty))
    local maxPlural = st.max == 1 and "copy" or "copies"
    f.stepperMaxFs:SetText(string.format("of %d stored %s", st.max, maxPlural))
    f.minusBtn:SetEnabled(st.qty > 1)
    f.plusBtn:SetEnabled(st.qty < st.max)
end

local function ShowDestroyStepperDialog(sel)
    if type(sel) ~= "table" then return end
    local entryID = sel.entryID
    local name    = sel.name or "this decor"
    -- Guard: nothing destroyable -> refuse. Belt-and-braces with decor.showDestroyButton binding.
    local liveMax = math.min(99, math.floor(sel.destroyableInstanceCount or 0))
    if not entryID or liveMax < 1 then return end

    if not _destroyDialog then _destroyDialog = buildDestroyDialog() end
    local f  = _destroyDialog
    local st = _destroyState
    st.max     = liveMax
    st.qty     = 1
    st.entryID = entryID
    st.name    = name

    f.minusBtn:SetScript("OnClick", function()
        if _destroyState.qty > 1 then   -- re-check: disabled state should prevent this, but input race possible
            _destroyState.qty = _destroyState.qty - 1
            refreshDestroyDialog()
        end
    end)
    f.plusBtn:SetScript("OnClick", function()
        if _destroyState.qty < _destroyState.max then
            _destroyState.qty = _destroyState.qty + 1
            refreshDestroyDialog()
        end
    end)
    f.destroyBtn:SetScript("OnClick", function()
        -- Snapshot ALL params: HOUSING_STORAGE_ENTRY_UPDATED fires synchronously inside DestroyEntry.
        local entryID_ = _destroyState.entryID
        local name_    = _destroyState.name
        local qRaw     = _destroyState.qty
        local maxRaw   = _destroyState.max

        local q = validateDestroyArgs(entryID_, qRaw, maxRaw)
        if not q then f:Hide(); return end

        local liveCount = liveDestroyableCount(entryID_)   -- re-resolve; clamp DOWN only
        if liveCount < 1 then f:Hide(); return end
        if q > liveCount then q = liveCount end

        local cat = _G.C_HousingCatalog
        if not (cat and cat.DestroyEntry) then f:Hide(); return end

        f.destroyBtn:SetEnabled(false)   -- guard 8: disable for loop; Hide() below is belt+braces
        -- Hide first so user sees immediate response; 99-iteration loop can stutter a frame.
        f:Hide()

        local firstErr   -- collect first DestroyEntry failure; warn once, not N times
        for _ = 1, q do
            local ok, err = pcall(cat.DestroyEntry, entryID_, false)
            if not ok and not firstErr then firstErr = err end
        end
        if firstErr then HDG.Log:Warn("decor", "DestroyEntry failed: " .. tostring(firstErr)) end

        -- Clear selection: if all copies destroyed, the item falls out of filter;
        -- the row at the same visual position shows a DIFFERENT item without this clear.
        CH.Mechanics.SetUITransientView("decor", "selectedItemID", nil)
        CH.Mechanics.SetUITransientView("decor", "selectedVariantKey", nil)

        HDG.Log:Info("decor_action",
            string.format("Destroyed %d %s of %s",
                q, q == 1 and "copy" or "copies", name_ or "decor"))
    end)
    refreshDestroyDialog()
    f:Show(); f:Raise()
end

local function SetTopFilter(value)
    -- per ADR-018: 'all' -> UI_FILTER_RESET (atomic clear); others -> DECOR_SET_TOP_FILTER (preserves toggles + search).
    if value == "all" then
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.UI_FILTER_RESET,
            payload = { tab = "decor" },
        })
    else
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.DECOR_SET_TOP_FILTER,
            payload = { value = value },
        })
    end
end

-- Keyboard nav: host:SelectByArrow handles selection + ScrollToElementData.

function DecorController:Wire(rootFrame)
    local searchBox = HDG.UI.WireSearchBox(rootFrame, "decorPanel.search", "decor", "searchQuery")

    self:_wireListBox(rootFrame)

    -- Top filter chips (SSoT: HDG.Constants.TOP_FILTERS used by both LayoutConfig and here).
    for _, entry in ipairs(HDG.Constants.TOP_FILTERS or {}) do
        local captured = entry.value
        HDG.UI.OnClick(rootFrame, "decorPanel.topFilter_" .. captured, function()
            SetTopFilter(captured)
        end)
    end

    self:_wireTagSlots(rootFrame)

    -- Right-side toggles
    HDG.UI.OnClick(rootFrame, "decorPanel.onlyUncollectedToggle", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.DECOR_TOGGLE_ONLY_UNCOLLECTED })
    end)
    HDG.UI.OnClick(rootFrame, "decorPanel.onlyStoredToggle", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.DECOR_TOGGLE_ONLY_STORED })
    end)

    -- Reset: atomic clear via UI_FILTER_RESET (mirrors the 'all' chip).
    HDG.UI.OnClick(rootFrame, "decorPanel.resetFilters", function()
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.UI_FILTER_RESET,
            payload = { tab = "decor" },
        })
        if searchBox and searchBox.SetText then searchBox:SetText("") end
    end)

    self:_wireNoteBox(rootFrame)

    -- Destroy button: opens the 1-99 stepper dialog.
    local destroyBtn = HDG.UI.W(rootFrame, "decorDetailPanel.destroyBtn")
    if destroyBtn and destroyBtn.SetScript then
        destroyBtn:SetScript("OnClick", function()
            local state = HDG.Store:GetState()  -- exception(false-positive): top-level controller method (not a row factory)
            local sel = HDG.Selectors:Call("decor.selectedItem", state, {})
            if not (sel and sel.entryID and (sel.destroyableInstanceCount or 0) > 0) then return end
            ShowDestroyStepperDialog(sel)
        end)
    end

    self:_wireWishlist(rootFrame)
end

-- ===== Wire sub-wirings (extracted from DecorController:Wire) ===============

-- List box: arrow-key navigation + SelectionBehaviorMixin store-sync.
function DecorController:_wireListBox(rootFrame)
    local listBox = HDG.UI.W(rootFrame, "decorPanel.list")
    if listBox and listBox.EnableKeyboard then
        listBox:EnableKeyboard(true)
        listBox:SetScript("OnKeyDown", function(self, key)
                if key ~= "UP" and key ~= "DOWN" then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                self:SetPropagateKeyboardInput(false)
                local ed = self.SelectByArrow and self:SelectByArrow(key)
                if ed and ed.itemID then
                    CH.Mechanics.SetUITransientView("decor", "selectedItemID", ed.itemID)
                    CH.Mechanics.SetUITransientView("decor", "selectedVariantKey", ed.variantKey)
                end
            end)
    end

    -- SelectionBehaviorMixin sync. Highlight syncs on variantKey (variant rows share an itemID).
    if listBox and listBox.WireStoreSelectionSync then
        listBox:WireStoreSelectionSync("session.ui.decor.selectedVariantKey",
            function(ed, key) return ed.variantKey == key end)
    end
end

-- Tag chip slots: click reads decor.tagsForFilter at click-time (live slot text).
-- Dynamic tag-chip tooltips. Tag slots are pooled (the live sub-tag list maps
-- onto fixed slots), so the def is a FUNCTION resolved live at hover -- it keys
-- off the slot's CURRENT tag. Only tags in TAG_TOOLTIP_RECIPE get a tip.
local TAG_TOOLTIP_RECIPE = { Redeemable = "RedeemableTag" }
local function _makeTagTooltipDef(slot)
    return function()
        -- exception(false-positive): top-level controller def fn (not a row factory)
        local tags = HDG.Selectors:Call("decor.tagsForFilter", HDG.Store:GetState(), {}) or {}
        local name = tags[slot] and TAG_TOOLTIP_RECIPE[tags[slot]]
        return name and { recipe = name } or nil
    end
end

function DecorController:_wireTagSlots(rootFrame)
    for slot = 1, (HDG.Constants.TAG_SLOT_COUNT or 12) do
        local captured = slot
        -- Dynamic tooltip: shows the Redeemable explainer when this slot holds it.
        HDG.TooltipEngine:Attach(
            HDG.UI.W(rootFrame, "decorPanel.tagSlot_" .. captured),
            _makeTagTooltipDef(captured))
        HDG.UI.OnClick(rootFrame, "decorPanel.tagSlot_" .. captured, function()
            local tags = HDG.Selectors:Call("decor.tagsForFilter",
                HDG.Store:GetState(), {}) or {}  -- exception(false-positive): top-level controller method (not a row factory)
            local tag = tags[captured]
            if tag then
                -- Real branch, NOT `(current==tag) and nil or tag` -- Lua 5.1 trap returns tag when equal.
                local current = HDG.Selectors:Call("decor.activeTag",
                    HDG.Store:GetState(), {})  -- exception(false-positive): top-level controller method (not a row factory)
                local nextTag = tag
                if current == tag then nextTag = nil end
                HDG.Store:Dispatch({
                    type    = HDG.Constants.ACTIONS.DECOR_SET_TAG,
                    payload = { tag = nextTag },
                })
            end
        end)
    end
end

-- (Dye-variant swatch wiring removed with the in-card variant strip. Owned
-- dyed-variant ROWS still select via selectedVariantKey in the row factory above.)

-- Note editbox: per-keystroke dispatch. Race guard: _lastBoundItemID tracks which item
-- is displayed; OnTextChanged skips when displayed item doesn't match selection.
function DecorController:_wireNoteBox(rootFrame)
    local noteBox = HDG.UI.W(rootFrame, "decorDetailPanel.note")
    if noteBox and noteBox.SetScript then
        noteBox._lastBoundItemID = nil
        if not noteBox._setTextHooked then
            hooksecurefunc(noteBox, "SetText", function(self)
                -- HDG.Store + session.ui.decor are guaranteed post-init.
                self._lastBoundItemID = HDG.Store:GetState().session.ui.decor.selectedItemID  -- exception(false-positive): top-level controller read
            end)
            noteBox._setTextHooked = true
        end
        noteBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local id = HDG.Store:GetState().session.ui.decor.selectedItemID  -- exception(false-positive): top-level controller read
            if not id then return end
            if self._lastBoundItemID ~= nil and self._lastBoundItemID ~= id then   -- item switch in progress
                return
            end
            local text = (self.GetText and self:GetText()) or ""
            if text == "" then
                HDG.Store:Dispatch({
                    type = HDG.Constants.ACTIONS.NOTE_CLEAR,
                    payload = { itemID = id },
                })
            else
                HDG.Store:Dispatch({
                    type = HDG.Constants.ACTIONS.NOTE_SET,
                    payload = { itemID = id, text = text },
                })
            end
        end)
    end
end

-- Wishlist: adds selected item (npcID nil) to shopping list (surfaces in Wishlist section).
function DecorController:_wireWishlist(rootFrame)
    HDG.UI.OnClick(rootFrame, "decorDetailPanel.wishlistBtn", function()
        local state = HDG.Store:GetState()  -- exception(false-positive): top-level controller method (not a row factory)
        local item  = HDG.Selectors:Call("decor.selectedItem", state, {})
        if not item then return end
        if state.account.activeShoppingListId == "" then
            HDG.Log:Warn("shopping",
                "No active shopping list -- open the Shopping tab to create one")
            return
        end
        HDG.Store:Dispatch({
            type    = HDG.Constants.ACTIONS.SHOPPING_ITEM_ADD,
            payload = { itemID = item.itemID, qty = 1 },   -- npcID nil = wishlist
        })
        HDG.Log:Success("shopping",
            (item.name or "Item") .. " added to wishlist")
    end)
end

function DecorController:Refresh(rootFrame, ctx)
    -- Bindings push values; nothing imperative needed.
end

HDG.Controllers:Register("decor", DecorController)
