-- HDG.UI (controller-side helpers)
-- Widget access (W/OnClick/WireSearchBox), workflow dialogs (Confirm/ShowMenu),
-- the unified row factory builder (MakeRowFactory), row chrome/badge,
-- chip rendering (GateChips), click wiring, row helpers.
-- Components.lua (loaded first) owns: widget factory methods + _TintTexture + applyFontRole.

HDG = HDG or {}
HDG.UI = HDG.UI or {}

local UI = HDG.UI

-- StaticPopupDialogs / StaticPopup_Show / MenuUtil read from _G inline (test fixtures swap mocks after load).

-- ===== Widget access =====================================================

function UI.W(rootFrame, id)
    return rootFrame.widgets[id]
end

-- Wire LMB+RMB on a row Button. Either handler may be nil.
-- Both handlers receive the row Button as `self`.
function UI.WireLeftRightClick(row, lmbHandler, rmbHandler)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if rmbHandler then rmbHandler(self) end
        elseif lmbHandler then
            lmbHandler(self)
        end
    end)
end

function UI.OnClick(rootFrame, widgetId, fn)
    local w = UI.W(rootFrame, widgetId)
    if w and w.SetScript then w:SetScript("OnClick", fn) end
end

-- Standard search editbox wiring: userInput guard prevents dispatch on programmatic SetText.
function UI.WireSearchBox(rootFrame, widgetId, tabName, stateKey)
    local searchBox = UI.W(rootFrame, widgetId)
    if not (searchBox and searchBox.SetScript) then return end
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = (self.GetText and self:GetText()) or ""
        HDG.ControllerHelpers.Mechanics.SetUITransientView(tabName, stateKey, text)
    end)
end

-- ===== Workflow dialogs ==================================================
-- StaticPopup confirm: id, text, accept, cancel, onAccept, input (bool), maxLetters, data.
function UI.Confirm(opts)
    if type(opts) ~= "table" then return end
    local popupDialogs = _G.StaticPopupDialogs
    local popupShow    = _G.StaticPopup_Show
    if not (popupDialogs and popupShow) then return end
    local id = opts.id or "HDGR_CONFIRM"
    popupDialogs[id] = popupDialogs[id] or {
        text       = opts.text   or "Confirm?",
        button1    = opts.accept or "OK",
        button2    = opts.cancel or "Cancel",
        hasEditBox = opts.input == true,
        maxLetters = opts.maxLetters or 64,  -- exception(boundary): opts API default
        OnAccept   = function(self, data)
            if opts.input then
                local box = self.editBox or (self.GetEditBox and self:GetEditBox())
                local val = box and box.GetText and box:GetText() or ""
                if opts.onAccept then opts.onAccept(val, data) end
            else
                if opts.onAccept then opts.onAccept(nil, data) end
            end
        end,
        EditBoxOnEnterPressed = opts.input and function(self)
            local val = self:GetText() or ""
            if opts.onAccept then opts.onAccept(val) end
            self:GetParent():Hide()
        end or nil,
        EditBoxOnEscapePressed = opts.input and function(self)
            self:GetParent():Hide()
        end or nil,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    popupShow(id, opts.textArg1, opts.textArg2, opts.data)
end

-- Modern MenuUtil-based context menu. Auto-scroll cap at 20 items (480px default).
-- items: { text, callback } | { isTitle } | { isDivider } | { kind="radio", text, value, selected, callback }
-- opts: maxHeight (explicit cap), noAutoScroll.
local SCROLL_AUTO_THRESHOLD  = 20
local SCROLL_AUTO_MAX_HEIGHT = 480
function UI.ShowMenu(owner, items, opts)
    local menuUtil = _G.MenuUtil
    if not (menuUtil and menuUtil.CreateContextMenu) then return end
    opts = opts or {}
    menuUtil.CreateContextMenu(owner, function(_, root)
        for _, item in ipairs(items or {}) do
            if item.isDivider then
                root:CreateDivider()
            elseif item.isTitle then
                root:CreateTitle(item.text or "")
            elseif item.kind == "radio" and root.CreateRadio then
                root:CreateRadio(item.text or "",
                    function() return item.selected == true end,
                    item.callback or function() end,
                    item.value)
            else
                local btn = root:CreateButton(item.text or "", item.callback or function() end)
                if item.disabled and btn and btn.SetEnabled then btn:SetEnabled(false) end
            end
        end
        if root.SetScrollMode then  -- exception(boundary): SetScrollMode only on WowScrollBox frames; root varies by caller
            local maxH = opts.maxHeight
            if not maxH and not opts.noAutoScroll
                and items and #items > SCROLL_AUTO_THRESHOLD then
                maxH = SCROLL_AUTO_MAX_HEIGHT
            end
            if maxH then root:SetScrollMode(maxH) end
        end
    end)
end

-- ===== Row factory builders ==============================================

-- Lazily create a row FontString. Font MUST be applied before SetText (no inheritsFrom -> error).
function UI.ensureRowText(row, font)
    if row.vfnText or not row.CreateFontString then return end
    row.vfnText = row:CreateFontString(nil, "OVERLAY")
    if row.vfnText.SetPoint then  -- exception(false-positive): FontString always has SetPoint; mock-fidelity guard
        row.vfnText:SetPoint("LEFT", 8, 0); row.vfnText:SetPoint("RIGHT", -8, 0)
    end
    row.vfnText:SetJustifyH("LEFT")
    row.vfnText:SetWordWrap(false)
    HDG.UI.applyFontRole(row.vfnText, font)
    HDG.Theme:Register(row.vfnText, "Text")
end

function UI.clearRow(row)
    row:SetScript("OnClick", nil)
    if row.vfnText then row.vfnText:SetText("") end
    row:SetText("")
end

-- Create + theme a row FontString in one call (create-role-register triple).
-- Anchoring/width/wrap stay at call site; justify is optional 4th arg.
function UI.RowText(row, fontRole, themeRole, justify)
    local fs = row:CreateFontString(nil, "OVERLAY")
    HDG.UI.applyFontRole(fs, fontRole)
    HDG.Theme:Register(fs, themeRole)
    if justify then fs:SetJustifyH(justify) end
    return fs
end

-- Blank N row FontStrings by field key. Nil-guarded (pooled row may be Reset before layout).
function UI.ClearRowText(row, ...)
    for i = 1, select("#", ...) do
        local fs = row[select(i, ...)]
        if fs then fs:SetText("") end
    end
end

-- SetAtlas silently no-ops on an invalid name. GetAtlasInfo returns nil; warn once.
-- Memoized per name (at most one C_Texture call per unique atlas, always-on).
local _atlasChecked = {}
function UI.WarnIfBadAtlas(name)
    if not (name and name ~= "") or _atlasChecked[name] then return end
    _atlasChecked[name] = true
    local CT = _G.C_Texture
    if CT and CT.GetAtlasInfo and CT.GetAtlasInfo(name) == nil and HDG.Log then  -- exception(boundary): CT = _G.C_Texture, Blizzard global; may be absent in headless tests
        HDG.Log:Warn("layout", "invalid atlas (SetAtlas is a silent no-op): " .. tostring(name))
    end
end

-- Atlas-or-texture icon with a clean switch: SetAtlas stamps texcoords that crop a later SetTexture
-- on the same pooled texture; always clear the atlas before switching to a file path.
function UI.PaintIcon(tex, atlas, texture, fallback)
    if atlas and atlas ~= "" then
        UI.WarnIfBadAtlas(atlas)
        tex:SetAtlas(atlas)           -- SetAtlas resets texcoords + replaces any prior file
    elseif texture and texture ~= "" then
        tex:SetAtlas("")              -- drop a prior atlas so its texcoords don't crop the file
        tex:SetTexture(texture)
    elseif fallback then
        tex:SetAtlas("")
        tex:SetTexture(fallback)
    end
end

-- ===== MakeRowFactory: the unified row-lifecycle builder ====================
-- Every simple list row is the same skeleton: idempotent first-paint laydown ->
-- RowChrome (zebra/hover/selected) -> per-paint writes -> optional click wire,
-- with a Reset that clears scripts + text. This builder OWNS that lifecycle, so
-- a factory declares only what is UNIQUE to it: its column layout + paint, plus
-- a few per-row bits. Heterogeneous kind-dispatch rows (header-OR-card,
-- multi-shape) stay BESPOKE -- they are not "the same skeleton".
--
-- opts:
--   layout       fn(row)               first-paint laydown (REQUIRED)
--   paint        fn(row, ed, template)  per-paint writes    (REQUIRED)
--   laidOutTag   string                 first-paint flag (default "_rowLaidOut")
--   selectable   bool                   true -> selection driven by ed.selected
--   selectedFn   fn(ed) -> bool         custom selection predicate (e.g. ed.isActive) for
--                                        envelopes whose selection field isn't `selected`.
--                                        Use INSTEAD of selectable; omit both -> never selected.
--   clicks       string                 RegisterForClicks arg (e.g. "LeftButtonUp")
--   wire         fn(row, ed)            per-paint click/script wiring
--   resetText    {string,...}           FontString keys to blank on Reset
--   reset        fn(row)                extra Reset cleanup (e.g. row._id = nil)
function UI.MakeRowFactory(opts)
    if type(opts) ~= "table" then error("MakeRowFactory: opts table required", 2) end
    if type(opts.layout) ~= "function" then error("MakeRowFactory: opts.layout required", 2) end
    if type(opts.paint)  ~= "function" then error("MakeRowFactory: opts.paint required", 2) end
    local tag = opts.laidOutTag or "_rowLaidOut"

    return function(template)
        return {
            Configure = function(row, ed)
                HDG.UI:RowFirstPaint(row, tag, opts.layout)
                local selected = false
                if opts.selectedFn then selected = opts.selectedFn(ed) and true or false
                elseif opts.selectable then selected = ed.selected and true or false end
                HDG.UI.PaintRowChrome(row, selected)
                if opts.clicks then row:RegisterForClicks(opts.clicks) end
                opts.paint(row, ed, template)
                row:SetHeight(template.height)
                if opts.wire then opts.wire(row, ed) end
            end,
            Reset = function(row)
                if row.SetScript then row:SetScript("OnClick", nil) end  -- exception(false-positive): Frame/Button rows always have SetScript; mock-fidelity guard
                if opts.resetText then HDG.UI.ClearRowText(row, unpack(opts.resetText)) end
                if opts.reset then opts.reset(row) end
            end,
        }
    end
end

-- Craftable-state star paint via atlas swap. White vertex reset for pooled rows.
-- defaultState: UnknownOnAccount (Recipes) or NotARecipe (Decor).
function UI:PaintCraftStar(star, state, defaultState)
    local cs    = state or defaultState
    local atlas = HDG.Constants.RECIPE_STATE_STAR_ATLAS[cs]
    if not atlas then star:Hide(); return end
    star:SetAtlas(atlas)
    star:SetVertexColor(1, 1, 1, 1)
    star:Show()
end

-- ===== Row chrome + badge paint facades ==================================
-- Construction in Components; paint in Theme.Skinners. Wrappers stash state + register.

function UI.PaintRowChrome(row, selected)
    if not row then return end
    HDG.UI:EnsureRowChrome(row)
    HDG.Theme:Register(row, "RowChrome", { selected = selected and true or false })
end

function UI.PaintRowBadge(row, text)
    if not row then return end
    HDG.UI:EnsureRowBadge(row)
    HDG.Theme:Register(row, "BadgePill", {
        text = (text ~= nil and text ~= "") and text or nil,
        variant = "count",
    })
end

-- ===== Source-type chip strip =============================================
-- Delegates to HDG.Format.SourceChip (Palette-backed SSoT). `dimmed` fades not-met gate chips.
-- questDone/achEarned/repMet = false fades the matching chip; nil = full brightness.
function UI.GateChips(itemID, questDone, achEarned, repMet)
    if not itemID then return "" end
    local row = HDG.HousingCatalogObserver:GetRow(itemID)
    if not row or not row.sourceTags then return "" end
    local out = {}
    for _, tag in ipairs(row.sourceTags) do
        local dimmed = (tag.kind == "QUEST" and questDone == false)
                    or (tag.kind == "ACH"   and achEarned == false)
                    or (tag.kind == "REP"   and repMet    == false)
        out[#out+1] = HDG.Format.SourceChip(tag.kind, dimmed)
    end
    return table.concat(out, " ")
end

-- Send a reagent buy-list to Auctionator as a shopping list. Each reagent is
-- { id = itemID, qty = stillNeeded } (qty = the gap between what's needed and held).
-- When Auctionator exposes ConvertToSearchString we emit an exact-name search that
-- carries that quantity, so the list reflects the buy gap (not a fuzzy name search) --
-- parity with HDG v2.45. Bare-name fallback (older Auctionator). "item:<id>" fallback
-- so the list is never silently empty. Returns (count, present).
function UI.SendReagentsToAuctionator(listName, reagents)
    local API = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1  -- exception(boundary): optional addon
    if not (API and API.CreateShoppingList) then return 0, false end
    local callerID = HDG.Constants.ADDON_NAME
    local hasQty   = API.ConvertToSearchString ~= nil
    local terms = {}
    for _, mat in ipairs(reagents) do
        local name = HDG.ItemNameResolver:ResolveName(mat.id)
        if (not name or name == "") and C_Item and C_Item.GetItemInfo then  -- exception(boundary): uncached item
            name = (C_Item.GetItemInfo(mat.id))
        end
        if not name or name == "" then name = "item:" .. tostring(mat.id) end
        if hasQty then
            terms[#terms + 1] = API.ConvertToSearchString(callerID, {
                searchString = name,
                isExact      = true,
                quantity     = (mat.qty and mat.qty > 0) and mat.qty or nil,
            })
        else
            terms[#terms + 1] = name
        end
    end
    if #terms > 0 then
        API.CreateShoppingList(callerID, listName, terms)
    end
    return #terms, true
end

-- ===== Composer primitives =====================================================

-- "+ " / "- " collapse-glyph prefix for a collapsible group-header label.
function UI.CollapsePrefix(collapsed)
    return collapsed and "+ " or "- "
end

-- { accent, dim, success } ColorCode set. Fresh table per call.
function UI.SemanticCC()
    return {
        accent  = HDG.Theme:ColorCode("semantic.accent"),
        dim     = HDG.Theme:ColorCode("text.dim"),
        success = HDG.Theme:ColorCode("semantic.success"),
    }
end

-- Square icon texture with standard 0.08-0.92 crop. Caller sets :SetTexture and :SetPoint.
function UI.MakeCellIcon(parent, size)
    local s = size or 18
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(s, s)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

-- Right-anchored [- nn +] stepper. Stamps _minusBtn/_qtyFs/_plusBtn; caller wires clicks.
-- opts: rightInset(-4), size(16), qtyWidth(22), qtyFont("caption"), plusAtlas, minusAtlas.
function UI.WireStepperCluster(row, opts)
    opts = opts or {}
    local size = opts.size or 16  -- exception(optional): option default
    local plus = HDG.UI:AtlasButton(row, opts.plusAtlas or "communities-chat-icon-plus", size)
    plus:SetPoint("RIGHT", row, "RIGHT", opts.rightInset or -4, 0)
    local qty = UI.RowText(row, opts.qtyFont or "caption", "Text", "CENTER")
    qty:SetPoint("RIGHT", plus, "LEFT", -3, 0)
    qty:SetWidth(opts.qtyWidth or 22)  -- exception(optional): option default
    qty:SetWordWrap(false)
    local minus = HDG.UI:AtlasButton(row, opts.minusAtlas or "communities-chat-icon-minus", size)
    minus:SetPoint("RIGHT", qty, "LEFT", -3, 0)
    row._plusBtn, row._qtyFs, row._minusBtn = plus, qty, minus
    return plus, qty, minus
end

-- Two-column name LEFT / meta dim RIGHT. Stamps _nameFs/_metaFs.
-- opts: nameRole("body"), metaRole("caption"), leftInset(10), rightInset(-8), gap(6).
function UI.LayoutNameMetaRow(row, opts)
    opts = opts or {}
    local meta = UI.RowText(row, opts.metaRole or "caption", opts.metaTheme or "TextDim", "RIGHT")
    meta:SetPoint("RIGHT", row, "RIGHT", opts.rightInset or -8, 0)
    meta:SetWordWrap(false)
    local name = UI.RowText(row, opts.nameRole or "body", opts.nameTheme or "Text", "LEFT")
    name:SetPoint("LEFT", row, "LEFT", opts.leftInset or 10, 0)  -- exception(optional): option default
    name:SetPoint("RIGHT", meta, "LEFT", -(opts.gap or 6), 0)  -- exception(optional): option default
    name:SetWordWrap(false)
    row._nameFs, row._metaFs = name, meta
    return name, meta
end

-- Resolved item name with "item N" fallback (uncached items).
function UI.ItemName(itemID)
    local n = HDG.ItemNameResolver:ResolveName(itemID)
    return (n and n ~= "") and n or ("item " .. tostring(itemID))
end
