-- HDG.UI Components
--
-- The curated palette of standard UI elements. Two responsibilities, kept in
-- one file per element so they always change together:
--
--   1. Constructor (HDG.UI:Button, :EditBox, :ScrollBox, ...) -- WoW-aware
--      build of the widget with theme registration and sane defaults.
--   2. HDG.WidgetTypes:Register("kind", { build, skin, dispatch, ... }) --
--      closed-taxonomy registration; Layout:BuildAll routes by spec.kind.
--
-- Build the addon around this standard. The bar for adding a new component
-- is high: prefer extending an existing one (more spec fields) over a new
-- kind. New kinds should represent a genuinely new visual / interactive
-- shape, not a configuration of an existing one.

HDG = HDG or {}
HDG.UI = HDG.UI or {}

-- Log tag for optional Blizzard widget templates that vary by client build
-- (ModelSceneControlFrameTemplate etc.). Failures here are expected on
-- older/non-retail clients; logged at warn so we notice if they break on
-- retail too.
HDG.Log:RegisterTags({ ui_optional = { user = false, level = "warn" } })

local CreateScrollBoxListLinearView = _G.CreateScrollBoxListLinearView
local ScrollUtil = _G.ScrollUtil
local CreateDataProvider = _G.CreateDataProvider
local ScrollBoxConstants = _G.ScrollBoxConstants

local function SetDataProvider(scrollBox, provider, retainScroll)
    -- The headless test mock doesn't implement SetDataProvider; the else-branch
    -- stashes the provider on the frame so tests read it back without mocking
    -- the full ScrollBox API. Production always has the method.
    if scrollBox.SetDataProvider then   -- exception(boundary): mock lacks this method (intentional dual path)
        scrollBox:SetDataProvider(provider, retainScroll)
    else
        scrollBox.provider = provider
        scrollBox.retainScroll = retainScroll
    end
end

-- Apply a Theme font role to a widget. Errors loudly if role is missing.
-- No-ops when SetFontObject is absent (test mock; production always has it).
local function applyFontRole(widget, role)
    if not widget then return end
    if not role then
        error("applyFontRole: font role is required (validator should have caught this)", 2)
    end
    local fo = HDG.Theme:GetFont(role)
    if not fo then
        error(("applyFontRole: unknown font role %q"):format(tostring(role)), 2)
    end
    if widget.SetFontObject and type(fo) == "table" and fo.GetFont then
        widget:SetFontObject(fo)
    elseif widget.SetFont and type(fo) == "table" and fo.file then
        widget:SetFont(fo.file, fo.size, fo.flags or "")
    end
end
HDG.UI.applyFontRole = applyFontRole

-- Column header backdrop: surface.panel_header rect behind a FontString cell.
-- Hidden by default; caller calls bg:Show() for header rows.
function HDG.UI.makeColumnHeaderBg(parent, anchor)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     anchor, "TOPLEFT",     -2, 1)
    bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT",  2, -1)
    local c = HDG.Theme:GetColor("surface.panel_header")
    bg:SetColorTexture(c.r, c.g, c.b, c.a)
    bg:Hide()
    return bg
end

-- Tertiary inline row button (32x18) for per-row shortcuts (Wpt / Map).
-- Atlas skinner doesn't paint hover for tertiary variant, so hover is inline.
function HDG.UI.RowButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 32, h or 18)
    b._hdgrVariant = "tertiary"
    HDG.Theme:Register(b, "Button")
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    local ac = HDG.Theme:GetColor("semantic.accent")
    hover:SetColorTexture(ac.r, ac.g, ac.b, 0.20)
    b._hoverTex = hover   -- the "Button" skinner re-tints this on scheme switch (Theme.lua)
    local label = HDG.UI.RowText(b, "caption", "Text", "CENTER")
    label:SetAllPoints()
    label:SetText(text)
    b:SetFontString(label)   -- register so b:SetText() re-labels (callers that set text post-create)
    return b
end

-- Apply a theme color to a texture's vertex tint. No-op if SetVertexColor is absent or color is nil.
function HDG.UI._TintTexture(texture, color, alpha)
    if not (texture and texture.SetVertexColor and color) then return end
    texture:SetVertexColor(color.r, color.g, color.b, alpha or color.a or 1)
end

local function applyFontToFS(fs, role)
    applyFontRole(fs, role)
end

-- ===== Binding-dispatcher primitives ======================================

-- Pass-through: call widget:Method(value) when both exist.
local function _applyBoundValue(widget, value, methodName)
    if value == nil or not widget[methodName] then return end
    widget[methodName](widget, value)
end

-- Tostring-coerced (for SetText / SetChipText / SetLabel etc.).
local function _applyBoundString(widget, value, methodName)
    if value == nil or not widget[methodName] then return end
    widget[methodName](widget, tostring(value))
end

-- Boolean-coerced (for SetEnabled / SetActive that want strict true/false).
local function _applyBoundBool(widget, value, methodName)
    if value == nil or not widget[methodName] then return end
    widget[methodName](widget, value and true or false)
end

-- ===== dispatchText helpers ===============================================

-- GetUnboundedStringWidthForText (verified 12.0.5) measures against the FS's font
-- without SetText or render -- correct on hidden/never-rendered FontStrings.
-- Plain GetUnboundedStringWidth() returns 0 until the FS has drawn once.
-- Both are pure reads; Layout stays the sole writer of geometry.
local function _naturalTextWidth(fs, text)
    if not (fs and fs.GetUnboundedStringWidthForText) then return 0 end   -- exception(boundary): headless mock only
    return fs:GetUnboundedStringWidthForText(text or "")
end

local function _updateLabelIntrinsicWidth(widget)
    if not widget.GetUnboundedStringWidth then return end
    local w = _naturalTextWidth(widget, widget.GetText and widget:GetText())
    -- Stamp ALWAYS, incl. 0 for empty text. Leaving a nil/stale intrinsic when a
    -- label empties makes its "auto" slot fall back to "fill" (getAlong) -- a
    -- phantom flex track that splits slack with real fills (e.g. an emptied
    -- expansion badge stealing half the header and parking the milestone at
    -- panel-center). 0 collapses the slot so sibling fills get the full width.
    widget._intrinsicWidth = (w > 0) and (math.ceil(w) + 4) or 0
end

-- Flag when bound text grows past the allocated slot. DEBUG-level (trace-gated):
-- routes to the Debug tab + `/hdgr trace layout` only, NEVER end-user chat. A
-- hot-path Log:Warn here always-printed and spammed testers (2026-06-05) -- this
-- is developer layout instrumentation, not a user-actionable warning.
-- Skipped for wrap-enabled labels (no-wrap width would false-fire) and
-- elastic-width labels ("auto"/"content" slots resize on next LAYOUT pass).
-- Fixed / fill / nil slots are checked -- they won't grow to rescue overruns.
local function _warnLabelOverflow(widget, text)
    if not widget._intrinsicWidth then return end  -- nothing measured
    if widget._hdgrWrap then return end
    local specWidth = widget._hdgrSpecWidth
    if specWidth == "auto" or specWidth == "content" then return end
    local alloc = widget._lastRect and widget._lastRect.width
    if not (alloc and alloc > 0) then return end
    if widget._intrinsicWidth <= alloc + 2 then return end
    if widget._overflowWarnedAt == widget._intrinsicWidth then return end
    widget._overflowWarnedAt = widget._intrinsicWidth
    -- Name the exact widget (LayoutConfig id, stamped by BindingEngine) + its
    -- data binding so the warning points straight at the offending element +
    -- the selector field feeding it, not just the rendered text.
    local bindingSel = widget._hdgrBinding and widget._hdgrBinding.text
    HDG.Log:Debug("layout", string.format(
        "label text overflows allocated width: %dpx in %dpx slot -- widget %s%s -- %q",
        widget._intrinsicWidth, math.floor(alloc + 0.5),
        tostring(widget._hdgrId or "?"),
        (type(bindingSel) == "string") and (" <- " .. bindingSel) or "",
        tostring(text):sub(1, 60)))
end

local function dispatchText(widget, values)
    if values.text == nil or not widget.SetText then return end
    widget:SetText(tostring(values.text))
    _updateLabelIntrinsicWidth(widget)
    _warnLabelOverflow(widget, values.text)
end

local function dispatchButton(widget, values)
    if values.text ~= nil then
        if widget.RefreshIntrinsicWidth then  -- exception(boundary): RefreshIntrinsicWidth only on AutoSizeButton template; other button types lack it
            widget:SetText(tostring(values.text))
            widget:RefreshIntrinsicWidth()
        else
            _applyBoundString(widget, values.text, "SetText")
        end
    end
    _applyBoundBool(widget, values.enabled, "SetEnabled")
    _applyBoundBool(widget, values.active,  "SetActive")
end

local function dispatchEditbox(widget, values)
    if values.text == nil or not widget.SetText then return end
    -- Skip the SetText if the current widget text already matches the desired
    -- value -- prevents cursor resets and OnTextChanged loops when the user
    -- is mid-typing and a state notify fires.
    local current = widget.GetText and widget:GetText() or nil
    if current ~= tostring(values.text) then
        widget:SetText(tostring(values.text))
        if widget._hdgrPlaceholderRefresh then widget._hdgrPlaceholderRefresh() end
    end
end

local function dispatchStatCard(widget, values)
    _applyBoundString(widget, values.value, "SetValue")
    _applyBoundString(widget, values.label, "SetLabel")
end

-- Key-contract check: each item must produce a non-nil unique key (spec section 10).
local function _assertScrollboxKeyContract(widget, items, def)
    local seen = {}
    for i, ed in ipairs(items) do
        local k = def.key(ed, nil)  -- ctx nil today; reserved for future
        if k == nil then
            error(("scrollbox %s: row factory %q produced nil key at index %d"):format(
                tostring(widget.rowKind or "?"), tostring(widget.rowKind), i), 2)
        end
        if seen[k] then
            error(("scrollbox %s: key collision %q at index %d (also at index %d)"):format(
                tostring(widget.rowKind or "?"), tostring(k), i, seen[k]), 2)
        end
        seen[k] = i
    end
end

local function dispatchScrollbox(widget, values)
    if values.items == nil or not widget.SetItems then return end
    -- Key-contract check is debug-only: O(N) walk is meaningful at ~2000 items.
    local def = widget._hdgrRowDef
    if def and def.key then
        local cfg = HDG.Store:GetState().account.config
        if cfg and cfg.debug then
            _assertScrollboxKeyContract(widget, values.items, def)
        end
    end
    widget:SetItems(values.items, true)
end

-- Universal destroy: clears standard scripts + UnregisterAllEvents (per spec 3.6).
-- Theme registry uses weak keys; no manual unregister needed there.
local DESTROY_SCRIPTS = {
    "OnClick", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp",
    "OnEnterPressed", "OnEscapePressed", "OnTabPressed", "OnChar",
    "OnTextChanged", "OnEditFocusGained", "OnEditFocusLost",
    "OnKeyDown", "OnKeyUp", "OnDragStart", "OnDragStop",
    "OnShow", "OnHide", "OnUpdate", "OnEvent",
}

local function destroyWidget(widget)
    if not widget then return end
    -- Blizzard widget methods (SetScript / UnregisterAllEvents) are
    -- guaranteed-present on any widget that has them in its prototype;
    -- no pcall needed. Fail loud if a non-widget table gets passed.
    if widget.SetScript then  -- exception(false-positive): Frame always has SetScript; mock-fidelity guard against partial test widgets
        for _, ev in ipairs(DESTROY_SCRIPTS) do
            widget:SetScript(ev, nil)
        end
    end
    if widget.UnregisterAllEvents then widget:UnregisterAllEvents() end  -- exception(false-positive): Frame always has UnregisterAllEvents; mock-fidelity guard
end

-- ===== Frame: bare-minimum primitive (used as a fallback container) =====

function HDG.UI:Frame(parent)
    return CreateFrame("Frame", nil, parent, "BackdropTemplate")
end

HDG.WidgetTypes:Register("frame", {
    build = function(parent, _spec) return HDG.UI:Frame(parent) end,
    skin  = "Frame",
    specFields = {},                   -- container; nothing kind-specific
})

-- ===== Spacer: invisible flex Frame =====

function HDG.UI:Spacer(parent)
    return CreateFrame("Frame", nil, parent)
end

HDG.WidgetTypes:Register("spacer", {
    build = function(parent, _spec) return HDG.UI:Spacer(parent) end,
    specFields = {},                   -- pure layout filler
})

-- ===== Label: regular text FontString =====

function HDG.UI:Label(parent, text, font, justifyH, optsTable)
    if not parent or not parent.CreateFontString then return nil end
    local fs = parent:CreateFontString(nil, "OVERLAY")
    -- Font MUST be set before SetText (no inheritsFrom -> "Font not set" error otherwise).
    applyFontToFS(fs, font)
    fs:SetText(text or "")
    fs:SetJustifyH(justifyH or "LEFT")

    local opts = optsTable or {}
    -- `role` names a Theme text role directly (Text/TextDim/TextHeading/...);
    -- Theme:Register loud-warns if the role doesn't exist. No-role -> Text.
    local role = opts.role or "Text"   -- exception(optional): spec.role optional, label defaults to Text

    -- TextDim implies TOP justify (multi-line descriptions) unless overridden.
    local justifyV = opts.justifyV
    if justifyV == nil and role == "TextDim" and fs.SetJustifyV then justifyV = "TOP" end
    if justifyV and fs.SetJustifyV then fs:SetJustifyV(justifyV) end
    if opts.wrap and fs.SetWordWrap then
        fs:SetWordWrap(true)
        fs._hdgrWrap = true   -- dispatchText skips overflow detection on wrap-enabled labels.
    end

    HDG.Theme:Register(fs, role)
    _updateLabelIntrinsicWidth(fs)   -- seed _intrinsicWidth for "auto" layout sizing
    return fs
end

-- `skin` omitted: label names its Theme role directly via spec.role at build time;
-- statCard owns two FontStrings with independent roles. Theme:Register on each.
HDG.WidgetTypes:Register("label", {
    build = function(parent, spec)
        local fs = HDG.UI:Label(parent, spec.text or "", spec.font, spec.justifyH, {
            role     = spec.role,
            wrap     = spec.wrap,
            justifyV = spec.justifyV,
        })
        -- Stash the spec.width so dispatchText can distinguish a FIXED slot
        -- (number -> warn loud on overflow) from an auto/fill slot (skip the
        -- overflow check -- the BIND -> LAYOUT pipeline will resize the slot
        -- on the next pass using the freshly-stamped _intrinsicWidth).
        if fs then fs._hdgrSpecWidth = spec.width end
        return fs
    end,
    dispatch = { fields = { "text" }, push = dispatchText },
    specFields = { "text", "font", "justifyH", "justifyV", "wrap", "role" },
})

-- ===== Divider: 1px horizontal hairline rule, theme-coloured ==============

function HDG.UI:Divider(parent)
    if not (parent and CreateFrame) then return nil end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(1)
    if frame.CreateTexture then  -- exception(false-positive): Frame always has CreateTexture; mock-fidelity guard
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        -- Register with Theme.Skinners.Divider so theme repaints flow through.
        HDG.Theme:Register(tex, "Divider")
    end
    return frame
end

HDG.WidgetTypes:Register("divider", {
    build = function(parent, _spec) return HDG.UI:Divider(parent) end,
    skin  = "Divider",
    specFields = {},                   -- pure separator; nothing kind-specific
})

-- ===== VDivider: 1px VERTICAL hairline -- sibling of Divider for separating
-- items inside a horizontal strip (e.g. acq source chips | Missing toggle).
-- Width fixed at 1; the layout slot supplies the height.
function HDG.UI:VDivider(parent)
    if not (parent and CreateFrame) then return nil end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(1)
    if frame.CreateTexture then  -- exception(false-positive): Frame always has CreateTexture; mock-fidelity guard
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        HDG.Theme:Register(tex, "Divider")
    end
    return frame
end

HDG.WidgetTypes:Register("vdivider", {
    build = function(parent, _spec) return HDG.UI:VDivider(parent) end,
    skin  = "Divider",
    specFields = {},                   -- pure separator; nothing kind-specific
})

-- ===== ProgressBar: thin horizontal coverage indicator ====================
-- SetProgress(p) accepts 0..1 (clamped); binding pushes `progress` updates.
function HDG.UI:ProgressBar(parent)
    if not (parent and CreateFrame) then return nil end
    local frame = CreateFrame("Frame", nil, parent)
    if frame.CreateTexture then  -- exception(false-positive): Frame always has CreateTexture; mock-fidelity guard
        local trough = frame:CreateTexture(nil, "BACKGROUND")
        trough:SetAllPoints()
        HDG.Theme:Register(trough, "InsetBg")
        frame._hdgrBarTrough = trough

        local fill = frame:CreateTexture(nil, "ARTWORK")
        if fill.SetPoint then  -- exception(false-positive): Texture always has SetPoint; mock-fidelity guard
            fill:SetPoint("TOPLEFT", 0, 0)
            fill:SetPoint("BOTTOMLEFT", 0, 0)
        end
        HDG.Theme:Register(fill, "ProgressBarFill")
        frame._hdgrBarFill = fill
    end
    function frame:SetProgress(p)
        if type(p) ~= "number" then p = 0 end
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        self._hdgrProgress = p
        local w = self:GetWidth() or 0  -- exception(boundary): frame geometry nil before first layout
        if self._hdgrBarFill and self._hdgrBarFill.SetWidth then
            self._hdgrBarFill:SetWidth(math.max(1, w * p))
        end
    end
    frame:SetScript("OnSizeChanged", function(self)
        if self._hdgrProgress then self:SetProgress(self._hdgrProgress) end
    end)
    return frame
end

HDG.WidgetTypes:Register("progressbar", {
    build = function(parent, _spec) return HDG.UI:ProgressBar(parent) end,
    dispatch = {
        fields = { "progress" },
        push   = function(widget, updates)
            if updates.progress ~= nil and widget.SetProgress then
                widget:SetProgress(updates.progress)
            end
        end,
    },
    -- font: declarative no-op for the progress bar -- it has no text region,
    -- but Curator surfaces declare `font = "caption"` alongside their other
    -- widgets for consistency. Accepted + ignored.
    specFields = { "font" },
})

-- ===== LinkRow: 24x24 icon (atlas > fileID) + optional label + read-only URL EditBox ====
-- HighlightText on focus for one-click select-all.

function HDG.UI:LinkRow(parent, spec)
    if not (parent and CreateFrame) then return nil end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(spec.height or 28)  -- exception(optional): spec field default (validator-guarded)

    -- Icon: 24x24. Atlas (Blizzard atlas name) takes priority over fileID.
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    if spec.iconAtlas and icon.SetAtlas then
        icon:SetAtlas(spec.iconAtlas, false)
    elseif spec.icon and icon.SetTexture then
        icon:SetTexture(spec.icon)
    end
    frame.icon = icon

    -- Optional label fontstring above the editbox (small/dim text).
    local labelFS
    if spec.label and spec.label ~= "" then
        labelFS = frame:CreateFontString(nil, "OVERLAY")
        labelFS:SetPoint("BOTTOMLEFT", icon, "TOPRIGHT", 8, -22)
        applyFontRole(labelFS, "small")
        labelFS:SetText(spec.label)
        local dim = HDG.Theme:GetColor("text.dim")
        if dim and labelFS.SetTextColor then
            labelFS:SetTextColor(dim.r, dim.g, dim.b, dim.a)
        end
        frame.label = labelFS
    end

    -- URL EditBox: read-only via OnTextChanged restore. HighlightText on focus
    -- so user gets one-click select-all for Ctrl+C.
    local urlText = spec.url or ""
    local edit = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    edit:SetHeight(20)
    edit:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    edit:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    edit:SetAutoFocus(false)
    edit:SetText(urlText)
    edit:SetCursorPosition(0)
    edit:SetTextInsets(6, 6, 0, 0)
    applyFontRole(edit, spec.font or "body")
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    edit:SetScript("OnEscapePressed",  function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed",   function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= urlText then
            self:SetText(urlText)
            self:SetCursorPosition(0)
        end
    end)
    frame.editbox = edit

    -- Theme-paint the EditBox via the LinkRow skin role.
    HDG.Theme:Register(edit, "LinkRow")

    -- Dynamic setters: binding can drive url/label/icon per-selection.
    -- SetLinkURL must update urlText or the read-only restore reverts it.
    function frame:SetLinkURL(url)
        urlText = url or ""
        edit:SetText(urlText)
        edit:SetCursorPosition(0)
    end
    function frame:SetLinkLabel(text)
        if labelFS then labelFS:SetText(text or "") end
    end
    function frame:SetLinkIcon(path)
        if path and path ~= "" then icon:SetTexture(path) else icon:SetTexture(nil) end
    end

    return frame
end

-- Partial binding: act only on the fields actually bound (icon/label may stay
-- static while url is data-driven).
local function dispatchLinkRow(widget, values)
    if values.url   ~= nil and widget.SetLinkURL   then widget:SetLinkURL(values.url)     end
    if values.label ~= nil and widget.SetLinkLabel then widget:SetLinkLabel(values.label) end
    if values.icon  ~= nil and widget.SetLinkIcon  then widget:SetLinkIcon(values.icon)   end
end

HDG.WidgetTypes:Register("linkRow", {
    build = function(parent, spec) return HDG.UI:LinkRow(parent, spec) end,
    dispatch = { fields = { "url", "label", "icon" }, push = dispatchLinkRow },
    specFields = { "icon", "iconAtlas", "label", "url", "font", "height" },
})

-- ===== Atlas: Frame with a single Texture set to a Blizzard atlas =====

function HDG.UI:Atlas(parent, atlasName, texturePath)
    local frame = CreateFrame("Frame", nil, parent)
    if frame.CreateTexture then  -- exception(false-positive): Frame always has CreateTexture; mock-fidelity guard
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        if tex.SetAtlas and atlasName then
            HDG.UI.WarnIfBadAtlas(atlasName)
            tex:SetAtlas(atlasName, false)
        elseif tex.SetTexture and texturePath then
            tex:SetTexture(texturePath)
        end
        frame.texture = tex
    end
    return frame
end

-- Dark backdrop: one stretched copy of the abstract-waves texture, darkened via vertex
-- multiply (scheme-invariant). Tiling creates hard seams; one stretched copy is correct.
function HDG.UI:ModelBackdrop(parent, sublayer)
    local tex = parent:CreateTexture(nil, "BACKGROUND", nil, sublayer or 0)
    tex:SetAllPoints()  -- one copy, stretched to fill (default texcoord 0,1,0,1)
    tex:SetTexture("Interface\\AddOns\\HousingDecorGuide\\textures\\model_bg_tile")
    tex:SetVertexColor(0.45, 0.45, 0.45, 1)  -- darken pass (VDS-style); tune brightness here
    return tex
end

HDG.WidgetTypes:Register("atlas", {
    specFields = { "atlas", "texture", "tone" },
    build = function(parent, spec)
        local frame = HDG.UI:Atlas(parent, spec.atlas, spec.texture)
        -- Optional tone: tint a white atlas (e.g. the PlayerPartyBlip state dot)
        -- to a scheme token. Scheme-switch-safe via the ToneTexture skinner,
        -- which reads the token stamped on the texture.
        if spec.tone then
            frame.texture._hdgrToneToken = spec.tone
            HDG.Theme:Register(frame.texture, "ToneTexture")
        end
        return frame
    end,
})

-- ===== iconToggle: bare atlas glyph, tinted full (active) vs dim (inactive) =====
-- The atlas IS the chrome. Click + tooltip are controller-wired.
local function dispatchIconToggle(widget, values)
    if values.active ~= nil then   -- partial binding: only act when `active` is bound
        widget:SetActive(values.active)
    end
end

HDG.WidgetTypes:Register("iconToggle", {
    build = function(parent, spec)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(spec.size, spec.size)   -- size is a required iconToggle specField (every widget declares it); strict-read
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        HDG.UI.WarnIfBadAtlas(spec.glyph)
        tex:SetAtlas(spec.glyph)
        btn._glyphTex = tex
        -- dim (default ON): full color = active, dimmed = inactive.
        -- rotate (opt-in via rotateActive/rotateInactive): swaps glyph rotation.
        -- Keep button SQUARE when rotating, else 90deg turns skew the icon.
        local dim = spec.dimWhenInactive ~= false  -- exception(optional): dimWhenInactive declared in iconToggle specFields; validator catches typos; absent = default-on
        local rotA, rotI = spec.rotateActive, spec.rotateInactive
        function btn:SetActive(state)
            if dim then
                local v = state and 1 or 0.45   -- full = on, dim = off (HDG parity)
                self._glyphTex:SetVertexColor(v, v, v)
            end
            if (rotA ~= nil or rotI ~= nil) and self._glyphTex.SetRotation then
                self._glyphTex:SetRotation(state and (rotA or 0) or (rotI or 0))
            end
        end
        btn:SetActive(false)   -- inactive treatment until the active binding pushes the real value
        return btn
    end,
    dispatch = { fields = { "active" }, push = dispatchIconToggle },
    -- OnClick + the dynamic tooltip are attached by the owning controller.
    input = { events = { OnClick = true, OnEnter = true, OnLeave = true } },
    destroy = destroyWidget,
    requiresFont = function() return false end,
    specFields = { "glyph", "size", "dimWhenInactive", "rotateActive", "rotateInactive" },
})

-- ===== clickHints: housing-hotkey click glyphs + hover tooltip =====
-- Declare leftText/rightText/dragText (omit to hide). Drag shares the left-button glyph
-- (no separate drag icon on the housing-hotkey sheet).
local CLICKHINT_GLYPH = 16
local CLICKHINT_GAP   = 2

local function buildClickHints(parent, spec)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(spec.height)   -- strict: every clickHints widget declares height
    local count = 0
    local function addGlyph(atlas)
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAtlas(atlas, false)
        tex:SetSize(CLICKHINT_GLYPH, CLICKHINT_GLYPH)
        tex:SetPoint("LEFT", frame, "LEFT", count * (CLICKHINT_GLYPH + CLICKHINT_GAP), 0)
        count = count + 1
    end
    -- Left button covers click, drag, AND shift-click (shift is a left-button modifier),
    -- so one leftclick glyph serves all three (shift-only hints still get a glyph).
    if spec.leftText or spec.dragText or spec.shiftText then addGlyph("housing-hotkey-icon-leftclick")  end
    if spec.rightText                                    then addGlyph("housing-hotkey-icon-rightclick") end
    frame:SetWidth(math.max(1, count * CLICKHINT_GLYPH + math.max(0, count - 1) * CLICKHINT_GAP))

    -- Shared with row tooltips so wording never drifts. Shift is a keyboard
    -- modifier: it adds a tooltip line but no mouse glyph (handled above).
    local lines = HDG.TooltipEngine.ClickHintLines(spec)
    if spec.noteText  then lines[#lines + 1] = spec.noteText end   -- plain extra line (e.g. a button hint)
    HDG.TooltipEngine:Attach(frame, {
        title      = spec.title or "Mouse actions",
        extraLines = lines,
        anchor     = "ANCHOR_BOTTOMRIGHT",
    })
    return frame
end

HDG.WidgetTypes:Register("clickHints", {
    specFields = { "leftText", "rightText", "dragText", "shiftText", "noteText", "title" },
    build = function(parent, spec) return buildClickHints(parent, spec) end,
})

-- Tertiary-button chrome: the shared build for every "common-button-tertiary"
-- widget (HDG.UI:Button / EnsureChipChrome / buildChipButton). Sets the 4 state
-- atlases + the _active*Atlas tags the Skinner reads, re-anchors the state
-- textures (some Blizzard builds default them to atlas-native size, clipping wide
-- buttons), and seeds a centered FontString (atlas buttons have no inherited Text
-- region). Returns the FontString so callers can apply their own font role / text.
local function _applyTertiaryButtonChrome(button)
    button:SetNormalAtlas("common-button-tertiary-normal")
    button:SetHighlightAtlas("common-button-tertiary-hover")
    button:SetPushedAtlas("common-button-tertiary-pressed")
    button:SetDisabledAtlas("common-button-tertiary-disabled")
    button._normalAtlas          = "common-button-tertiary-normal"
    button._activeNormalAtlas    = "common-button-tertiary-depressed-normal"
    button._highlightAtlas       = "common-button-tertiary-hover"
    button._activeHighlightAtlas = "common-button-tertiary-depressed-hover"
    for _, getter in ipairs({"GetNormalTexture", "GetHighlightTexture",
                             "GetPushedTexture", "GetDisabledTexture"}) do
        local t = button[getter] and button[getter](button)
        if t and t.ClearAllPoints and t.SetAllPoints then
            t:ClearAllPoints()
            t:SetAllPoints(button)
        end
    end
    -- y=1: atlas interior shades upward; nudge text to visual center.
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", 0, 1)
    button:SetFontString(fs)
    return fs
end

function HDG.UI:Button(parent, text, font)
    -- BlizzardUI (scheme.nativeButtons): build the NATIVE Blizzard button
    -- (UIPanelButtonTemplate), left unskinned -- the real Blizzard look the dark
    -- atlas only approximated. The Button Skinner no-ops on _hdgrNative, so Blizzard
    -- owns the art + font + state textures.
    local scheme = HDG.Theme.currentScheme
    if scheme and scheme.nativeButtons then   -- exception(nullable): currentScheme unset until Theme:Initialize (headless tests build first)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(60, 22)  -- placeholder; layout supplies real width/height
        button._hdgrNative = true
        button:SetText(text or "")
        function button:SetState(updates) HDG.Theme:SetState(self, updates) end
        function button:SetActive(value) HDG.Theme:SetState(self, { active = value and true or false }) end
        button.RefreshIntrinsicWidth = function(btn)
            local fs = btn.GetFontString and btn:GetFontString()
            local w  = _naturalTextWidth(fs, btn.GetText and btn:GetText())
            if w > 0 then btn._intrinsicWidth = math.ceil(w) + 28 end
        end
        button:RefreshIntrinsicWidth()
        return button
    end
    -- common-button-tertiary: dark fill + white border (tints cleanly).
    -- Hand-built (no template) so the FontString + state textures stay under direct control.
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(60, 22)  -- placeholder; layout supplies real width/height
    _applyTertiaryButtonChrome(button)
    button:SetText(text or "")
    applyFontRole(button, font)
    function button:SetState(updates) HDG.Theme:SetState(self, updates) end
    function button:SetActive(value) HDG.Theme:SetState(self, { active = value and true or false }) end
    -- Intrinsic width = text width + ~28px chrome. layout reads _intrinsicWidth for "auto" spec.width.
    button.RefreshIntrinsicWidth = function(btn)
        local fs = (btn.GetFontString and btn:GetFontString()) or btn.Text
        local w = _naturalTextWidth(fs, btn.GetText and btn:GetText())
        if w > 0 then btn._intrinsicWidth = math.ceil(w) + 28 end
    end
    button:RefreshIntrinsicWidth()
    return button
end

-- Bare atlas-glyph button: atlas IS the button (no nine-slice), crisp at small sizes.
-- Alpha lifts 0.7 -> 1.0 on hover.
function HDG.UI:AtlasButton(parent, atlas, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetAtlas(atlas)
    tex:SetAlpha(0.7)
    btn._iconTex = tex
    btn:SetScript("OnEnter", function() tex:SetAlpha(1) end)
    btn:SetScript("OnLeave", function() tex:SetAlpha(0.7) end)
    return btn
end

-- Apply chip chrome to pooled/bare Button frames. Idempotent via _chipChromeBuilt.
function HDG.UI:EnsureChipChrome(chip)
    if chip._chipChromeBuilt then return end
    chip:EnableMouse(true)
    _applyTertiaryButtonChrome(chip)
    chip._chipChromeBuilt = true
end

-- ===== ChipButton: compact toggleable filter chip =========================
-- Built bare (no template) so font role applies directly and layout measures actual width.
local function buildChipButton(parent, text, font)
    -- Same tertiary atlas family as regular buttons, scaled down.
    -- No -depressed-small variant for active; Skinner's accent tint signals "on".
    local btn = CreateFrame("Button", nil, parent)
    btn:EnableMouse(true)
    btn:SetSize(60, 18)   -- placeholder; RefreshIntrinsicWidth computes real width
    local fs = _applyTertiaryButtonChrome(btn)
    if font then applyFontRole(fs, font) end
    if text then fs:SetText(text) end

    btn.RefreshIntrinsicWidth = function(b)
        local w = _naturalTextWidth(fs, fs.GetText and fs:GetText())
        if w > 0 then b._intrinsicWidth = math.ceil(w) + 12 end
    end
    btn:RefreshIntrinsicWidth()

    function btn:SetState(updates) HDG.Theme:SetState(self, updates) end
    function btn:SetActive(value) HDG.Theme:SetState(self, { active = value and true or false }) end

    return btn
end

-- ===== Dropdown: WowStyle1/Style2/Filter trigger backed by MenuUtil ==========
-- Self-wired via binding = { menu, current } + one of setTransient/setConfig/dispatch.
-- Menu items: { text, value } (radio default) + { kind="title"|"divider"|"checkbox" }.
-- See Reference/UI_HOW_TO.md s34 for the full spec.

local function buildDropdownOnSelect(spec)
    -- Exactly one dispatch shortcut required (closed-schema, loud at build time).
    local hasTransient = spec.setTransient ~= nil
    local hasConfig    = spec.setConfig    ~= nil
    local hasDispatch  = spec.dispatch     ~= nil
    local count = (hasTransient and 1 or 0) + (hasConfig and 1 or 0) + (hasDispatch and 1 or 0)
    if count ~= 1 then
        error("dropdown spec: exactly one of {setTransient, setConfig, dispatch} required", 2)
    end
    if hasTransient then
        local view = spec.setTransient.view
        local key  = spec.setTransient.key
        if type(view) ~= "string" or type(key) ~= "string" then
            error("dropdown spec: setTransient requires { view = string, key = string }", 2)
        end
        return function(value)
            HDG.ControllerHelpers.Mechanics.SetUITransientView(view, key, value)
        end
    end
    if hasConfig then
        local key = spec.setConfig.key
        if type(key) ~= "string" then
            error("dropdown spec: setConfig requires { key = string }", 2)
        end
        local resolved = HDG.Constants.ACTIONS.CONFIG_SET
        return function(value)
            HDG.Store:Dispatch({
                type    = resolved,
                payload = { key = key, value = value },
            })
        end
    end
    local actType    = spec.dispatch.type
    local payloadKey = spec.dispatch.payloadKey
    if type(actType) ~= "string" or type(payloadKey) ~= "string" then
        error("dropdown spec: dispatch requires { type = string, payloadKey = string }", 2)
    end
    -- Resolve the canonical ACTION string at build time -- crashes loud here
    -- if the constant doesn't exist, not silently on first click.
    local resolved = HDG.Constants.ACTIONS[actType]
    if not resolved then
        error(("dropdown spec: dispatch.type %q is not in HDG.Constants.ACTIONS"):format(
            tostring(actType)), 2)
    end
    return function(value)
        HDG.Store:Dispatch({
            type    = resolved,
            payload = { [payloadKey] = value },
        })
    end
end

-- Cap visible rows. Longer lists get a native scrollbar via SetScrollMode.
local DROPDOWN_VISIBLE_ROWS = 20
local DROPDOWN_ROW_EXTENT   = 20

-- Add one menu item. checkbox: isSelected re-reads live state per poll (stays open).
-- radio: compares against `current` snapshot (picking closes the menu).
local function _addDropdownItem(root, opt, current, currentSelector, onSelect)
    local kind = opt.kind or "radio"
    if kind == "divider" then
        root:CreateDivider()
    elseif kind == "title" then
        root:CreateTitle(opt.text or "")
    elseif kind == "checkbox" then
        local value = opt.value
        local isAll = opt.isAll == true
        root:CreateCheckbox(opt.text or "",
            function()
                local set = HDG.Selectors:Call(currentSelector, HDG.Store:GetState(), {})
                if isAll then return next(set) == nil end
                return set[value] == true
            end,
            function() onSelect(value) end,
            value)
    else  -- radio
        local value = opt.value
        root:CreateRadio(opt.text or "",
            function() return current == value end,
            function() onSelect(value) end,
            value)
    end
end

-- SetupMenu generator closure. Reads fresh state inside the closure.
local function buildDropdownGenerator(menuSelector, currentSelector, onSelect)
    return function(_owner, root)
        local state   = HDG.Store:GetState()
        local items   = HDG.Selectors:Call(menuSelector,    state, {})
        local current = HDG.Selectors:Call(currentSelector, state, {})
        -- Cap menu height before adding items. Per Reference/UI_HOW_TO.md s34,
        -- SetScrollMode + SetGridMode interact unpredictably; no grid here, so
        -- scroll alone is safe + cheap. Pixel-based cap; short lists render
        -- below it with no scrollbar.
        root:SetScrollMode(DROPDOWN_VISIBLE_ROWS * DROPDOWN_ROW_EXTENT)
        for _, opt in ipairs(items) do
            _addDropdownItem(root, opt, current, currentSelector, onSelect)
        end
    end
end

-- Default Style2: `common-dropdown-c-button` atlas + MenuStyle2 dark popup.
-- Has DropdownSelectionTextMixin so the trigger auto-renders from the
-- selected radio. Style1 = lighter chrome; Filter = filter-chip semantics
-- (no auto-render -- dispatchDropdown manually SetTexts the label).
local _DROPDOWN_VARIANT_TEMPLATES = {
    style2 = "WowStyle2DropdownTemplate",
    style1 = "WowStyle1DropdownTemplate",
    filter = "WowStyle1FilterDropdownTemplate",
}

-- Resolve variant string -> Blizzard template. Errors loudly on unknown
-- variant so typos surface at boot rather than silent fallback render.
local function _resolveDropdownTemplate(variant)
    local template = _DROPDOWN_VARIANT_TEMPLATES[variant]
    if not template then
        error(("dropdown: unknown variant %q (expected style2, style1, or filter)"):format(
            tostring(variant)), 3)
    end
    return template
end

-- Validate `spec.binding` shape. Errors loudly if the binding is missing
-- or malformed -- dropdowns require selector names for both the menu
-- contents and the current-value lookup.
local function _validateDropdownBinding(binding)
    if type(binding) ~= "table"
       or type(binding.menu) ~= "string"
       or type(binding.current) ~= "string" then
        error("dropdown widget requires binding = { menu = <selector>, current = <selector> }", 3)
    end
end

-- For style1/style2 dropdowns, attach a SelectionTranslator that prefixes
-- the auto-rendered selection text. Filter variant doesn't get this --
-- it manually SetTexts the label via dispatchDropdown.
-- SetSelectionTranslator's fn is called ONCE PER selected element with the single
-- element description (NOT an array) -- read its label via MenuUtil.GetElementText
-- (same accessor Blizzard's DefaultSelectionTranslator uses).
local function _attachDropdownSelectionPrefix(dd, prefix)
    if not (prefix and dd.SetSelectionTranslator) then return end
    dd:SetSelectionTranslator(function(selection)
        return prefix .. tostring(MenuUtil.GetElementText(selection) or "")
    end)
end

-- Strip a dim trailing description from the closed trigger. Menu rows bake the
-- description into the radio text as "label   |cXXXXXXXX desc|r"; the trigger
-- auto-renders that, which clutters the button. This translator drops everything
-- from the 2+space + color-code separator onward, so the trigger shows the label
-- alone while the open rows keep the description. (A label that is colored from
-- its START -- e.g. themeMenuItems' gold "Housing" -- has no leading double-space
-- before its |c, so it is left intact.)
local function _attachDropdownSuffixStrip(dd)
    if not dd.SetSelectionTranslator then return end
    dd:SetSelectionTranslator(function(selection)
        local label = MenuUtil.GetElementText(selection) or ""
        return (label:gsub("%s%s+|c.*$", ""))
    end)
end

local function buildDropdown(parent, spec)
    local variant  = spec.variant or "style2"
    local template = _resolveDropdownTemplate(variant)
    _validateDropdownBinding(spec.binding)

    -- Multi-select (checkbox menu) requires the filter variant: its label is
    -- manually stamped (count-based), whereas style1/2 auto-render a single
    -- selection. Loud error on misuse per closed-schema discipline.
    if spec.multi and variant ~= "filter" then
        error("dropdown spec: multi = true requires variant = \"filter\"", 2)
    end

    local dd = CreateFrame("DropdownButton", nil, parent, template)
    dd._hdgrVariant         = variant
    dd._hdgrMulti           = spec.multi == true
    dd._hdgrSelectionPrefix = spec.selectionPrefix
    dd._hdgrPlaceholder     = spec.placeholder or ""

    -- Placeholder + selection rendering split per template:
    --   filter:           DropdownTextMixin only; dispatchDropdown resolves
    --                     the label from the menu items each push.
    --   style2 / style1:  DropdownSelectionTextMixin auto-renders;
    --                     SetDefaultText is the no-selection fallback;
    --                     selectionPrefix wraps via SetSelectionTranslator.
    if variant == "filter" then
        dd:SetText(dd._hdgrPlaceholder)
    else
        dd:SetDefaultText(dd._hdgrPlaceholder)
        _attachDropdownSelectionPrefix(dd, spec.selectionPrefix)
        if spec.selectionStripSuffix and not spec.selectionPrefix then
            _attachDropdownSuffixStrip(dd)
        end
    end

    if spec.minWidth then dd.resizeToTextMinWidth = spec.minWidth end
    if spec.height and dd.SetHeight then dd:SetHeight(spec.height) end

    -- width="auto" dropdowns: the filter/style template auto-sizes its own
    -- width to the selection text (resizeToTextMinWidth), so a fixed declared
    -- width under-reports the real render and the NEXT widget in a horizontal
    -- section overlaps it. Report the live width as _intrinsicWidth + nudge a
    -- relayout when it changes (mirrors the chipStrip OnSizeChanged pattern) so
    -- the layout positions neighbours after the real right edge. Scoped to
    -- opt-in (width="auto") -- fixed-width dropdowns elsewhere are untouched.
    if spec.width == "auto" then
        dd._intrinsicWidth = spec.minWidth or 100  -- exception(optional): spec field default (validator-guarded)
        dd:HookScript("OnSizeChanged", function(self)
            local w = math.ceil(self:GetWidth() or 0)
            if w > 0 and w ~= self._intrinsicWidth then
                self._intrinsicWidth = w
                if HDG.RequestReflow then HDG:RequestReflow() end   -- exception(nullable): RequestReflow registered at init time; nil in headless mock + early boot
            end
        end)
    elseif variant == "filter" then
        -- width="fill"/fixed FILTER dropdowns: the template's resizeToText shrinks the
        -- button to its label, leaving uneven gaps across the row. Don't DISABLE
        -- resizeToText (that corrupts the FontString layout it co-manages) -- keep it ON
        -- and CLAMP its min/max to the slot the layout assigns, so it fills the slot while
        -- text still renders cleanly. ApplyLayout is the Layout-engine placement override
        -- (Layout:ApplyOne calls it instead of the default SetPoint/SetSize).
        function dd:ApplyLayout(region)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", region.x, -region.y)
            self:SetHeight(region.height)
            self.resizeToTextMinWidth = region.width
            self.resizeToTextMaxWidth = region.width
            self:SetWidth(region.width)
        end
    end

    local onSelect = buildDropdownOnSelect(spec)
    dd:SetupMenu(buildDropdownGenerator(spec.binding.menu, spec.binding.current, onSelect))
    return dd
end

-- Find the menu item whose value matches `current` and return its display
-- text. Used only by the Filter variant -- Style1 and Style2 auto-render via
-- DropdownSelectionTextMixin and don't need the manual lookup.
local function resolveFilterLabel(menu, current)
    if type(menu) ~= "table" then return nil end
    for _, opt in ipairs(menu) do
        if opt.value == current and (opt.kind or "radio") == "radio" then
            return opt.text
        end
    end
    return nil
end

-- Multi-select filter label: empty set -> placeholder ("All Expansions"); one
-- selected -> that option's text; several -> "<Noun> [N]" where Noun is the
-- placeholder minus its leading "All " ("All Professions" -> "Professions [3]").
-- `set` is the bound `current` selector value (a { [value]=true } table).
local function resolveMultiFilterLabel(menu, set, placeholder)
    if type(set) ~= "table" then return placeholder end
    local n, only = 0, nil
    for value in pairs(set) do n = n + 1; only = value end
    if n == 0 then return placeholder end
    if n == 1 and type(menu) == "table" then
        for _, opt in ipairs(menu) do
            if opt.value == only then return opt.text end
        end
    end
    local noun = tostring(placeholder):gsub("^All%s+", "")
    return noun .. " [" .. n .. "]"
end

local function dispatchDropdown(widget, values)
    if not widget then return end
    -- RADIO (single-select) menus snapshot `current` at generate time, so they need a
    -- rebuild to repaint the selected dot when state changes externally. CHECKBOX (multi)
    -- menus poll their isSelected fn live (MenuTemplates), so they self-update on click
    -- WITHOUT a rebuild -- and rebuilding an OPEN *scrolling* checkbox menu re-lays-out the
    -- scrollbox on every toggle, which re-fires UpdateToMenuSelections -> UpdateText and
    -- garbles the trigger text (the scroll-bar-only corruption). So skip it for multi.
    if not widget._hdgrMulti then
        widget:GenerateMenu()
    end
    if widget._hdgrVariant == "filter" then
        -- Filter chrome is static-label: resolve the label from the menu items
        -- + current value and stamp via SetText. Multi dropdowns count the set
        -- ("Expansions [2]"); single dropdowns match the one selected value.
        local label
        if widget._hdgrMulti then
            label = resolveMultiFilterLabel(values.menu, values.current, widget._hdgrPlaceholder)
        else
            label = resolveFilterLabel(values.menu, values.current) or widget._hdgrPlaceholder
        end
        if widget._hdgrSelectionPrefix then
            label = widget._hdgrSelectionPrefix .. tostring(label)
        end
        widget:SetText(tostring(label))
    end
end

-- ===== ModelPreview: housing decor 3D preview ===============================
-- Chrome only: atlas bg + PanningModelScene + optional controls/corbels + 2D icon fallback.
-- Widget knows nothing about catalog/dye state; dispatcher resolves itemID at widget seam
-- (keeps selectors pure per spec section 4).

-- Cover-fit a background atlas to `frame` preserving the atlas's native aspect ratio:
-- scale to the larger axis so the pane is fully covered, anchor centered, let the frame
-- clip the overflow. SetAllPoints would stretch + distort the landscape housing atlases.
-- Scale-to-cover: oversize the texture so it fills the frame (aspect preserved);
-- the frame's SetClipsChildren crops the overflow. Centered.
local function _fitCoverSize(tex, frame, tw, th)
    local fw, fh = frame:GetWidth(), frame:GetHeight()
    if fw <= 0 or fh <= 0 then return end  -- exception(boundary): pre-layout; OnSizeChanged re-fits
    local scale = math.max(fw / tw, fh / th)
    tex:SetSize(tw * scale, th * scale)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER")
end

local LOGO_BG_SIZE = 400   -- textures/Vamoose_HDG_400.tga is 400x400
local function _fitCoverAtlas(tex, frame, atlasName)
    if atlasName == "__logo__" then return _fitCoverSize(tex, frame, LOGO_BG_SIZE, LOGO_BG_SIZE) end
    local info = C_Texture.GetAtlasInfo(atlasName)  -- exception(boundary): nil on unknown atlas (patch removal)
    if not info then return end
    _fitCoverSize(tex, frame, info.width, info.height)
end

local function buildModelPreview(parent, spec)
    local showControls   = spec.showControls
    local showCorbels    = spec.showCorbels
    local showAtlas      = spec.showAtlas
    local bgTile         = spec.bgTile
    local insets         = spec.sceneInsets
    local placeholderStr = spec.placeholder

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")

    -- Dark backdrop (shared helper): one stretched copy of the abstract
    -- texture, no tiling. Sublayer 0 -> below the optional parchment atlas.
    if bgTile then
        frame._bgTile = HDG.UI:ModelBackdrop(frame, 0)
    end

    -- Atlas background. Blizzard's Housing Catalog uses this same atlas
    -- for the model preview pane, so we get the parchment-style chrome
    -- for free. Gated by showAtlas so we can drop it on surfaces that
    -- want the model on a clean background.
    if showAtlas then
        local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        bgTex:SetAllPoints()
        bgTex:SetAtlas("catalog-list-preview-bg")
    end

    -- Configurable background atlas (decor preview-bg dropdown). Sits above bgTile;
    -- hidden until a non-"default" atlas is picked, so the dark tile shows by default.
    if spec.configurableBg then
        local bgAtlas = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        bgAtlas:Hide()
        frame._bgAtlas = bgAtlas
        frame:SetClipsChildren(true)  -- crop the cover-fit overflow to the pane bounds
        frame:HookScript("OnSizeChanged", function(self)
            if self._bgAtlasName then _fitCoverAtlas(self._bgAtlas, self, self._bgAtlasName) end
        end)
    end

    -- PanningModelSceneMixinTemplate: left-drag rotate, right-drag pan, scroll zoom.
    local modelScene = CreateFrame("ModelScene", nil, frame, "PanningModelSceneMixinTemplate")
    modelScene:SetPoint("TOPLEFT", insets.left, -insets.top)
    modelScene:SetPoint("BOTTOMRIGHT", -insets.right, insets.bottom)
    modelScene:Hide()
    frame.modelScene = modelScene

    -- ModelSceneControlFrameTemplate: pcall because existence isn't guaranteed across builds.
    if showControls then
        local ok, ctrl = pcall(CreateFrame, "Frame", nil, frame, "ModelSceneControlFrameTemplate")
        if not ok then
            HDG.Log:Warn("ui_optional",
                "ModelSceneControlFrameTemplate unavailable on this client: " .. tostring(ctrl))
        elseif ctrl then
            ctrl:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
            local okSc, errSc = pcall(ctrl.SetModelScene, ctrl, modelScene)
            if not okSc then
                HDG.Log:Warn("ui_optional",
                    "ModelSceneControl:SetModelScene failed: " .. tostring(errSc))
            end
            ctrl:Hide()
            frame.controls = ctrl
        end
    end

    -- Decorative corbels: matches Blizzard housing chrome. Pure cosmetic.
    if showCorbels then
        local cl = frame:CreateTexture(nil, "OVERLAY")
        cl:SetSize(66, 50); cl:SetPoint("BOTTOMLEFT", -2, -2)
        cl:SetAtlas("catalog-corbel-bottom-left")
        local cr = frame:CreateTexture(nil, "OVERLAY")
        cr:SetSize(66, 50); cr:SetPoint("BOTTOMRIGHT", 2, -2)
        cr:SetAtlas("catalog-corbel-bottom-right")
    end

    -- 2D icon fallback for items the catalog doesn't have a 3D asset for
    -- (WMO fixtures, achievement decor, items not in live searcher).
    local iconFallback = frame:CreateTexture(nil, "ARTWORK")
    iconFallback:SetSize(128, 128); iconFallback:SetPoint("CENTER")
    iconFallback:Hide()
    frame.iconFallback = iconFallback

    -- "Preview unavailable" text when there's data but no 3D asset and
    -- no icon -- distinct from "Select an item" (which is the empty state).
    local unavail = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    unavail:SetPoint("CENTER", 0, -50)
    unavail:SetText("Preview unavailable")
    unavail:Hide()
    frame.unavail = unavail

    -- Empty-state placeholder. Shown when previewInfo is nil entirely
    -- (no selection yet).
    local placeholder = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    placeholder:SetPoint("CENTER")
    placeholder:SetText(placeholderStr)
    frame.placeholder = placeholder

    -- Default scene ID -- Blizzard's HOUSING_CATALOG_DECOR_MODELSCENEID_DEFAULT
    -- is 859 in current builds. Constants.HousingCatalogConsts is the
    -- forward-compatible source.
    local function GetDefaultSceneID()
        -- exception(boundary): Blizzard has form for renaming Constants.* between expansions
        return Constants.HousingCatalogConsts.HOUSING_CATALOG_DECOR_MODELSCENEID_DEFAULT
            or spec.defaultSceneID
    end

    -- Invert pitch so drag-UP tilts UP (PanningModelScene default is reversed).
    -- Idempotent via _hdgrPitchHooked. boundary: retain-orig wrapper, NOT a monkey-patch --
    -- hooksecurefunc can't modify args before the original runs; arg-rewrite is the sanctioned case.
    local function _installInvertedPitchHook(camera)
        if camera._hdgrPitchHooked then return end
        local origHandle = camera.HandleMouseMovement
        camera.HandleMouseMovement = function(self, mode, delta, snap)
            if mode == _G.ORBIT_CAMERA_MOUSE_MODE_PITCH_ROTATION then
                delta = -delta
            end
            return origHandle(self, mode, delta, snap)
        end
        camera._hdgrPitchHooked = true
    end

    -- Enable pitch on left-drag (default = yaw only). Matches Blizzard housing-catalog preview.
    local function _enable3DCameraPitch()
        local camera = modelScene.GetActiveCamera and modelScene:GetActiveCamera()
        if not (camera and camera.SetLeftMouseButtonYMode
                       and _G.ORBIT_CAMERA_MOUSE_MODE_PITCH_ROTATION) then
            return
        end
        camera:SetLeftMouseButtonYMode(_G.ORBIT_CAMERA_MOUSE_MODE_PITCH_ROTATION, true)
        _installInvertedPitchHook(camera)
    end

    local function _pointActorAtAsset(asset, dyes)
        local actor = modelScene.GetActorByTag and modelScene:GetActorByTag("decor")
        if not actor then return end
        actor:SetPreferModelCollisionBounds(true)
        actor:SetModelByFileID(asset)
        -- exception(boundary): SetGradientMaskWithDyes absent on non-dyeable actors
        if dyes and actor.SetGradientMaskWithDyes then
            actor:SetGradientMaskWithDyes(dyes[0], dyes[1], dyes[2])
        end
    end

    -- Try the 3D path: transition to scene ID, configure camera, point
    -- actor. Returns true on success (scene shown), false on Blizzard
    -- failure (caller drops to 2D fallback).
    local function _try3DLoad(info, dyes)
        local sceneID = info.uiModelSceneID or GetDefaultSceneID()
        local sceneOk, sceneErr = pcall(function()
            modelScene:TransitionToModelSceneID(
                sceneID,
                _G.CAMERA_TRANSITION_TYPE_IMMEDIATE,
                _G.CAMERA_MODIFICATION_TYPE_DISCARD,
                true)
        end)
        if not sceneOk then
            HDG.Log:Warn("model_preview",
                "TransitionToModelSceneID(" .. tostring(sceneID) .. ") failed: " .. tostring(sceneErr))
            return false
        end
        _enable3DCameraPitch()
        _pointActorAtAsset(info.asset, dyes)
        modelScene:Show()
        if frame.controls then frame.controls:Show() end
        return true
    end

    -- 2D fallback: prefer iconTexture, then iconAtlas; always show the
    -- "Preview unavailable" line so the user sees this isn't a 3D miss.
    local function _show2DFallback(info)
        if info.iconTexture then
            iconFallback:SetTexture(info.iconTexture)
            iconFallback:Show()
        elseif info.iconAtlas and iconFallback.SetAtlas then
            iconFallback:SetAtlas(info.iconAtlas)
            iconFallback:Show()
        end
        unavail:Show()
    end

    -- Reset every per-state widget to its hidden default. Called at the
    -- top of LoadPreviewInfo so the new state paints over a known base.
    local function _resetPreviewState()
        placeholder:Hide()
        modelScene:Hide()
        if frame.controls then frame.controls:Hide() end
        unavail:Hide()
        iconFallback:Hide()
        iconFallback:SetTexture(nil)
        iconFallback:SetAtlas(nil)
    end

    -- Idempotent: same info+dyes = no-op. dyes is part of the cache key (variant switch).
    function frame:LoadPreviewInfo(info, dyes)
        if frame._lastInfo == info and frame._lastDyes == dyes then return end
        frame._lastInfo = info
        frame._lastDyes = dyes

        _resetPreviewState()
        if not info then
            placeholder:Show()
            return
        end
        if info.asset and _try3DLoad(info, dyes) then return end
        _show2DFallback(info)
    end

    -- Initial empty state.
    frame:LoadPreviewInfo(nil)

    return frame
end

local function dispatchModelPreview(widget, values)
    if not widget or not widget.LoadPreviewInfo then return end
    local itemID = values.itemID
    local info = nil
    if itemID and HDG.HousingCatalogObserver and HDG.HousingCatalogObserver.Resolve then  -- exception(boundary): optional module / not yet built
        info = HDG.HousingCatalogObserver:Resolve(itemID)
    end
    local dyes = nil
    if itemID and values.variantKey and HDG.HousingCatalogObserver and HDG.HousingCatalogObserver.GetVariantDyes then  -- exception(boundary): optional module / not yet built; resolved at widget seam for selector purity
        dyes = HDG.HousingCatalogObserver:GetVariantDyes(itemID, values.variantKey)
    end
    -- Configurable preview background (decor-browser dropdown): apply the chosen
    -- atlas over the dark bgTile; "default"/nil hides the override so the tile shows.
    if widget._bgAtlas then
        local bg = values.bg
        if bg == "black" then
            widget._bgAtlas:SetColorTexture(0, 0, 0, 1)  -- plain fill: no aspect ratio, fill the pane
            widget._bgAtlas:ClearAllPoints()
            widget._bgAtlas:SetAllPoints()
            widget._bgAtlasName = nil
            widget._bgAtlas:Show()
        elseif bg == "logo" then
            -- Vamoose emblem (textures/Vamoose_HDG_400, on black). Fills the pane via the
            -- same scale-to-cover as the atlas backgrounds; sentinel "__logo__" so the
            -- OnSizeChanged hook re-fits it. SetTexCoord resets any prior atlas texcoords.
            widget._bgAtlas:SetTexture("Interface\\AddOns\\HousingDecorGuide\\textures\\Vamoose_HDG_400")
            widget._bgAtlas:SetTexCoord(0, 1, 0, 1)
            widget._bgAtlasName = "__logo__"
            _fitCoverAtlas(widget._bgAtlas, widget, "__logo__")
            widget._bgAtlas:Show()
        elseif bg and bg ~= "" and bg ~= "default" then
            widget._bgAtlas:SetAtlas(bg)
            widget._bgAtlasName = bg
            _fitCoverAtlas(widget._bgAtlas, widget, bg)
            widget._bgAtlas:Show()
        else
            widget._bgAtlasName = nil
            widget._bgAtlas:Hide()
        end
    end
    widget:LoadPreviewInfo(info, dyes)
end

HDG.WidgetTypes:Register("modelPreview", {
    build    = function(parent, spec) return buildModelPreview(parent, spec) end,
    dispatch = { fields = { "itemID", "variantKey", "bg" }, push = dispatchModelPreview },
    -- No skin: atlas bg owns the chrome; theme tinting would fight catalog-list atlas.
    requiresFont = function() return false end,
    destroy = destroyWidget,
    specFields = { "showControls", "showCorbels", "showAtlas", "bgTile",
                   "sceneInsets", "placeholder", "defaultSceneID", "configurableBg" },
})

HDG.WidgetTypes:Register("dropdown", {
    build = buildDropdown,
    -- Both fields trigger GenerateMenu so the open popup repaints on external state change.
    dispatch = { fields = { "menu", "current" }, push = dispatchDropdown },
    destroy = destroyWidget,
    requiresFont = function() return false end,
    specFields = {
        "placeholder", "selectionPrefix", "selectionStripSuffix", "variant", "multi",
        "minWidth", "width", "height",
        "setTransient", "setConfig", "dispatch",
    },
})

-- ============================================================================
-- radioGroup: inline always-visible radio buttons, { menu, current } binding.
-- Hand-rolled on common-radiobutton-circle/-dot (stacked pair, not a swap --
-- see reference_wow_radio_atlas_stacking.md). UIRadioButtonTemplate uses different atlases.
-- ============================================================================
local RADIO_ATLAS_OFF = "common-radiobutton-circle"
local RADIO_ATLAS_ON  = "common-radiobutton-dot"

local function _makeRadio(group, value, label)
    local btn = CreateFrame("Button", nil, group)
    btn._value = value
    btn:SetHeight(group._radioHeight)
    btn:RegisterForClicks("LeftButtonUp")
    -- Ring always present; dot overlays on top when selected (stacked pair, not a swap).
    local check = btn:CreateTexture(nil, "ARTWORK")
    check:SetSize(16, 16)
    check:SetPoint("LEFT", 0, 0)
    check:SetAtlas(RADIO_ATLAS_OFF)
    btn.check = check
    local dot = btn:CreateTexture(nil, "OVERLAY")
    dot:SetAllPoints(check)
    dot:SetAtlas(RADIO_ATLAS_ON)
    dot:Hide()
    btn.dot = dot
    local fs = btn:CreateFontString(nil, "OVERLAY")
    applyFontRole(fs, group._font)
    fs:SetPoint("LEFT", check, "RIGHT", 4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(label or "")
    HDG.Theme:Register(fs, "Text")
    btn.label = fs
    btn:SetScript("OnClick", function() group._onSelect(value) end)
    return btn
end

-- Build radios once (static options), then only repaint dots.
local function _ensureRadios(group, items)
    if group._built then return end
    local x = 0
    for _, opt in ipairs(items) do
        local r = _makeRadio(group, opt.value, opt.text)
        r:ClearAllPoints()
        r:SetPoint("LEFT", group, "LEFT", x, 0)
        local w = 16 + 4 + (_naturalTextWidth(r.label, opt.text) or 30)
        r:SetWidth(w)
        x = x + w + group._spacing
        group._radios[#group._radios + 1] = r
    end
    group._built = true
    -- Stamp the content width (item widths + inter-item gaps, no trailing gap) so a
    -- width="auto" radioGroup gets a real slot on the next layout pass. Without this,
    -- getAlong treats an unreported intrinsic as "fill". Fixed-width radios ignore it.
    group._intrinsicWidth = (x > 0) and (x - group._spacing) or 0
end

local function buildRadioGroup(parent, spec)
    local group = CreateFrame("Frame", nil, parent)
    group._onSelect    = buildDropdownOnSelect(spec)   -- reuse dropdown's dispatch shortcut
    group._radios      = {}
    group._font        = spec.font
    group._spacing     = spec.spacing or 12  -- exception(optional): spec field default (validator-guarded)
    group._radioHeight = spec.height or 20  -- exception(optional): spec field default (validator-guarded)
    return group
end

local function dispatchRadioGroup(widget, values)
    if not values.menu then return end   -- partial binding: nothing to render without a menu
    _ensureRadios(widget, values.menu)
    for _, radio in ipairs(widget._radios) do
        radio.dot:SetShown(radio._value == values.current)  -- circle stays; dot overlays when selected
    end
end

HDG.WidgetTypes:Register("radioGroup", {
    build    = buildRadioGroup,
    dispatch = { fields = { "menu", "current" }, push = dispatchRadioGroup },
    destroy  = destroyWidget,
    requiresFont = function() return true end,   -- radio labels need a font role
    specFields = {
        "orientation", "spacing", "font", "width", "height",
        "dispatch", "setTransient", "setConfig",
    },
})

-- ============================================================================
-- statusRail: bottom-of-window log surface. Shows most-recent user-visible entry.
-- Auto-dismisses via OnUpdate ticker (no state dispatch needed for expiry).
-- Binding: { entry = "status.current" } -> entry table or nil.
-- ============================================================================

local function buildStatusRail(parent, spec)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")

    -- Subtle background tint -- semi-transparent so the window's backdrop
    -- still reads through.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.25)
    frame.bg = bg

    -- Severity stripe on the left -- 3px wide vertical bar tinted to the
    -- entry's level. Loud visual cue without taking up width.
    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 0, 0)
    stripe:SetPoint("BOTTOMLEFT", 0, 0)
    stripe:SetWidth(3)
    stripe:SetColorTexture(0.5, 0.5, 0.5, 1)
    frame.stripe = stripe

    -- Text label. Single-line; truncates if too long.
    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 10, 0)
    text:SetPoint("RIGHT", -10, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    text:SetText("")
    frame.text = text

    -- Initial state: empty rail is hidden so the bottom row collapses
    -- visually until the first user-tagged entry lands.
    frame:Hide()

    function frame:SetEntry(entry)
        self._currentEntry = entry
        if not entry then
            self:Hide()
            return
        end
        local r, g, b = HDG.Format.LogColor(entry.level)
        self.stripe:SetColorTexture(r, g, b, 1)
        self.text:SetTextColor(r, g, b, 1)
        self.text:SetText(entry.text or "")
        self:Show()
    end

    -- OnUpdate ticker: 0.5s throttle; hides when entry's duration elapses.
    frame:HookScript("OnUpdate", function(self, elapsed)
        self._tickAccum = (self._tickAccum or 0) + elapsed
        if self._tickAccum < 0.5 then return end
        self._tickAccum = 0
        local entry = self._currentEntry
        if not entry or not entry.duration then return end
        local now = _G.GetTime and _G.GetTime() or 0
        if (now - (entry.timestamp or 0)) >= entry.duration then
            self._currentEntry = nil
            self:Hide()
        end
    end)

    return frame
end

local function dispatchStatusRail(widget, values)
    if not widget or not widget.SetEntry then return end
    widget:SetEntry(values.entry)
end

HDG.WidgetTypes:Register("statusRail", {
    build    = function(parent, spec) return buildStatusRail(parent, spec) end,
    dispatch = { fields = { "entry" }, push = dispatchStatusRail },
    requiresFont = function() return false end,
    destroy = destroyWidget,
    specFields = {},                   -- entry flows via binding; no kind-specific fields
})

-- ============================================================================
-- scrollingTextBox: multi-line read-only EditBox (select-all + Ctrl+C).
-- ============================================================================

-- Deferred scroll-to-bottom: one frame for the EditBox to auto-grow before reading scroll range.
-- Self-clearing OnUpdate (no C_Timer per feedback_no_ui_timers).
local function _scheduleScrollToBottom(container)
    if not (container.SetScript and container.SetVerticalScroll) then return end
    container:SetScript("OnUpdate", function(sf)
        sf:SetScript("OnUpdate", nil)
        if sf.GetVerticalScrollRange and sf.SetVerticalScroll then  -- exception(boundary): legacy ScrollFrame API; may be absent on non-ScrollFrame containers
            sf:SetVerticalScroll(sf:GetVerticalScrollRange() or 0)  -- exception(boundary): frame geometry nil before first layout
        end
    end)
end

local function buildScrollingTextBox(parent, spec)
    local maxLetters = spec.maxLetters

    local container = CreateFrame("ScrollFrame", nil, parent, "InputScrollFrameTemplate")
    container.multiLine = true   -- marker for tests + introspection
    if container.CharCount then container.CharCount:Hide() end  -- exception(boundary): CharCount is an InputScrollFrameTemplate sub-widget; absent in some Blizzard template versions
    container:EnableMouse(true)
    local edit = container.EditBox
    if not edit then return container end   -- mock environments without the template

    -- EditBox setup: multi-line, big maxLetters, left-justified.
    edit:SetAutoFocus(false)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(maxLetters)
    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("TOP")

    -- Read-only behavior: still selectable + copyable, but typing doesn't
    -- actually mutate text. We swallow OnChar / OnTextChanged in a way that
    -- preserves Ctrl+A / Ctrl+C accelerators (handled by Blizzard before
    -- our scripts fire). The simplest robust approach: store the canonical
    -- text on the container, restore it on every TextChanged.
    container._canonical = ""
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and container._canonical and self:GetText() ~= container._canonical then
            self:SetText(container._canonical)
        end
    end)

    -- Container resize -> propagate width to the editbox (template doesn't
    -- always forward, copied from VFN's fix).
    container:HookScript("OnSizeChanged", function(sf, w)
        if sf.EditBox and sf.EditBox.SetWidth then  -- exception(boundary): EditBox is an InputScrollFrameTemplate sub-widget; SetWidth absent on some template versions
            sf.EditBox:SetWidth(math.max(1, (w or 0) - 24))
        end
    end)
    container:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- Public API: SetText updates canonical text, optionally auto-scrolls
    -- to bottom (otherwise resets scroll to top).
    function container:SetText(text, optsArg)
        local s = text or ""
        self._canonical = s
        edit:SetText(s)
        if not self.SetVerticalScroll then return end
        local autoScroll = (optsArg and optsArg.autoScroll) or spec.autoScroll
        if autoScroll then
            _scheduleScrollToBottom(self)
        else
            self:SetVerticalScroll(0)
        end
    end
    function container:GetText() return edit:GetText() end
    function container:SetFocus() edit:SetFocus() end
    function container:ClearFocus() edit:ClearFocus() end

    return container
end

local function dispatchScrollingTextBox(widget, values)
    if not widget or not widget.SetText then return end
    widget:SetText(values.text or "")
end

HDG.WidgetTypes:Register("scrollingTextBox", {
    build    = function(parent, spec) return buildScrollingTextBox(parent, spec) end,
    dispatch = { fields = { "text" }, push = dispatchScrollingTextBox },
    skin     = "EditBox",
    destroy  = destroyWidget,
    specFields = { "font", "maxLetters", "autoScroll" },
})

-- ============================================================================
-- checkbox: UICheckButtonTemplate + text label (right). Binding drives checked state;
-- controller wires OnClick to dispatch. Visual state is purely reactive.
-- ============================================================================
--
-- Spec:
--   { kind = "checkbox", ["in"] = "...",
--     text = "Debug mode",
--     binding = { checked = "config.debug" },
--     options = { width = 24 } }

local function buildCheckbox(parent, spec)
    -- Wrapping Frame fills the layout slot's full width. The inner CheckButton
    -- stays at its template's natural size (24x24) so the textures don't
    -- stretch into smeared squiggles. The label sits to the right of the
    -- check and runs to the row edge. OnClick + SetChecked/GetChecked are
    -- forwarded so controllers + dispatch.push work transparently on the
    -- wrapper. (Earlier flat-CheckButton version stretched the texture when
    -- the layout engine resized it past 24px.)
    local container = CreateFrame("Frame", nil, parent)
    local check = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("LEFT", container, "LEFT", 0, 0)

    local labelText = spec.text
    local label = container:CreateFontString(nil, "OVERLAY")
    -- Theme the label (scheme font + Text color via the registry) instead of
    -- the Blizzard GameFontNormal default, which renders gold and ignores the
    -- scheme. Font role from spec.font, defaulting to "body".
    applyFontToFS(label, spec.font or "body")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetPoint("RIGHT", container, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)
    HDG.Theme:Register(label, "Text")

    container._check = check
    container._label = label

    -- Forwarders -- dispatch.push and controller :SetScript("OnClick", ...)
    -- both target the wrapper but should land on the inner CheckButton.
    function container:SetChecked(v) check:SetChecked(v) end
    function container:GetChecked()  return check:GetChecked() end

    local origSetScript = container.SetScript
    function container:SetScript(event, fn)
        if event == "OnClick" then
            check:SetScript("OnClick", fn)
        else
            origSetScript(self, event, fn)
        end
    end

    -- Click also lands on the label
    check:SetHitRectInsets(0, -label:GetStringWidth() - 8, 0, 0)

    return container
end

local function dispatchCheckbox(widget, values)
    if values.checked ~= nil and widget.SetChecked then
        widget:SetChecked(values.checked == true)
    end
end

HDG.WidgetTypes:Register("checkbox", {
    build    = function(parent, spec) return buildCheckbox(parent, spec) end,
    dispatch = { fields = { "checked" }, push = dispatchCheckbox },
    -- input.events advertises the OnClick handler controllers attach.
    input    = { events = { OnClick = true } },
    destroy  = destroyWidget,
    specFields = { "text", "label", "font" },
})

-- (Unified `button` WidgetTypes registration lives below buildToggleButton
--  so all four internal builders are in scope when the closure is created.)

-- ===== Button-factory primitives =========================================

-- Create a square Button with explicit size. Used by close/atlas/toggle
-- button factories that don't inherit a template.
local function _makeSquareButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    return btn
end

-- Apply the standard 3-atlas trio (normal / pressed / highlight) on a
-- Button. No-op if the widget doesn't expose SetNormalAtlas (mock
-- environments). Boundary check at the entry, then strict reads inside.
local function _setButtonAtlases(button, normalAtlas, pushedAtlas, highlightAtlas)
    if not button.SetNormalAtlas then return end
    button:SetNormalAtlas(normalAtlas)
    button:SetPushedAtlas(pushedAtlas)
    button:SetHighlightAtlas(highlightAtlas)
end

-- Wire hover-state tinting on a button-owned texture (icon, glyph, etc).
-- OnEnter paints with hoverToken, OnLeave restores idleToken. Both tokens
-- are Theme color tokens (e.g. "text.heading" / "text.dim"). Re-reads
-- on each hover so /hdgr theme swaps repaint correctly.
local function _attachIconHoverTint(button, getIconFn, idleToken, hoverToken)
    button:SetScript("OnEnter", function(btn)
        HDG.UI._TintTexture(getIconFn(btn), HDG.Theme:GetColor(hoverToken))
    end)
    button:SetScript("OnLeave", function(btn)
        HDG.UI._TintTexture(getIconFn(btn), HDG.Theme:GetColor(idleToken))
    end)
end

-- ===== CloseButton: bare button with atlas-icon child (VSS pattern) =====
-- Use for X close buttons in panel headers. Different SHAPE from a standard
-- button (no text label, square icon child), so it gets its own kind rather
-- than being a button variant.

local function buildCloseButton(parent, spec)
    local button = _makeSquareButton(parent, spec.size)
    if not button.CreateTexture then return button end   -- mock env

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(spec.iconSize, spec.iconSize)
    icon:SetPoint("CENTER")
    -- Close-button atlas is fixed by the `close = true` variant; not a
    -- defensive fallback. A close button that wasn't `XMarksTheSpot`
    -- would be a different kind (atlas button), not a config of this one.
    icon:SetAtlas("XMarksTheSpot")
    HDG.UI._TintTexture(icon, HDG.Theme:GetColor("text.dim"))
    button.icon = icon

    _attachIconHoverTint(button, function(btn) return btn.icon end,
        "text.dim", "text.heading")
    return button
end

-- (Legacy `closebutton` kind retired in #10.6 -- use kind="button" with
--  options.close = true. The HDG.UI:CloseButton constructor stays as an
--  internal helper called by the unified `button` WidgetTypes entry.)

-- ===== IconButton: 3-state Blizzard atlas button (HDG MakeIconButton pattern)
-- Use for header tab toggles where an icon reads cleaner than a text label.
-- Spec atlasBase = "decor-controls-settings" expects three atlases to exist:
--   <base>-default | <base>-pressed | <base>-active
-- SetActive(bool) swaps the normal atlas to -active so the button reads
-- its toggle state without relying on text prefixes.

-- Tooltip wiring shared by both icon-button factories. Delegates to the
-- TooltipEngine (HookScripts -- composes with the atlas hover-color OnEnter
-- in buildAtlasButton). Per spec section 17.3, this is the standard shape:
-- declare the tooltip data, engine drives GameTooltip.
local function attachIconTooltip(button, spec)
    local tip = spec.tooltip
    if not tip then return end
    if type(tip) == "string" then
        HDG.TooltipEngine:Attach(button, { title = tip, anchor = "ANCHOR_BOTTOMRIGHT" })
    else
        HDG.TooltipEngine:Attach(button, {
            title  = tip.title,
            body   = tip.body,
            anchor = tip.anchor or "ANCHOR_BOTTOMRIGHT",
        })
    end
end

-- AtlasButton: SINGLE-base Blizzard atlas button (3 suffixes:
-- -default / -pressed / -active). SetActive(bool) swaps the normal atlas
-- to "<base>-active". Use for tab-toggles where one atlas family covers
-- both states (e.g. decor-controls-settings, decor-placement-list).
local function buildAtlasButton(parent, spec)
    local button = _makeSquareButton(parent, spec.size)
    local base = spec.atlas
    button._iconBase   = base
    button._iconActive = false
    _setButtonAtlases(button, base .. "-default", base .. "-pressed", base .. "-active")

    function button:SetActive(state)
        self._iconActive = state and true or false
        self:SetNormalAtlas(self._iconBase .. (self._iconActive and "-active" or "-default"))
    end

    attachIconTooltip(button, spec)
    return button
end

-- IconButton: explicit normal/highlight atlas names (NOT the
-- -default/-pressed/-active suffix convention buildAtlasButton uses). The
-- atlases ARE the art (e.g. a minimap POI glyph), so `_ownedArt` tells the
-- Button Skinner to skip vertex-tinting -- otherwise the scheme would recolour
-- the coloured glyph. Normal = default state; highlight shows on hover/press.
local function buildIconButton(parent, spec)
    local button = _makeSquareButton(parent, spec.size)
    button._ownedArt = true
    _setButtonAtlases(button, spec.normalAtlas,
        spec.highlightAtlas or spec.normalAtlas,
        spec.highlightAtlas or spec.normalAtlas)
    -- Tooltip is wired centrally by the Layout build chokepoint (recipe-only).
    return button
end

-- ToggleButton: TWO-base Blizzard atlas button. Default state uses
-- spec.atlas; active state swaps to spec.activeAtlas entirely. Both bases
-- ship with -default and -highlight suffixes (no -pressed; pressed falls
-- back to highlight). Optional rotation in radians applies to all three
-- texture states. Use for direction toggles (arrow-down <-> arrow-up,
-- expanded <-> collapsed, etc).
local function buildToggleButton(parent, spec)
    local button = _makeSquareButton(parent, spec.size)
    button._iconBase       = spec.atlas
    button._iconActiveBase = spec.activeAtlas
    button._iconRotation   = spec.rotation
    button._iconActive     = false

    local function applyRotation(tex)
        if tex and button._iconRotation and tex.SetRotation then
            tex:SetRotation(button._iconRotation)
        end
    end
    local function applyAtlases(self)
        local current = self._iconActive and self._iconActiveBase or self._iconBase
        _setButtonAtlases(self, current .. "-default", current .. "-highlight", current .. "-highlight")
        -- SetAtlas resets the texture state; reapply rotation each time.
        applyRotation(self.GetNormalTexture    and self:GetNormalTexture())
        applyRotation(self.GetPushedTexture    and self:GetPushedTexture())
        applyRotation(self.GetHighlightTexture and self:GetHighlightTexture())
    end
    applyAtlases(button)

    function button:SetActive(state)
        self._iconActive = state and true or false
        applyAtlases(self)
    end

    attachIconTooltip(button, spec)
    return button
end

-- slotButton: Blizzard's "stretched dark slot" chrome -- the same visual
-- as keybinding slots in Settings > Controls. Underlying template is
-- UIMenuButtonStretchTemplate from Blizzard_SharedXML/Mainline/
-- SharedUIPanelTemplates.xml (the same 9-slice that
-- KeyBindingFrameBindingButtonTemplate inherits). No key-capture
-- behavior -- this is pure chrome; consumers wire OnClick themselves.
--
-- spec.tone (optional): scheme-aware tint via Theme.Skinners.SlotButton.
--   nil / "default" -> native silver
--   "accent"        -> scheme accent
--   "warning"       -> amber
--   "success"       -> green
--   "danger"        -> red
-- Theme:Register lets scheme swaps auto-repaint without rebuilding.
local function buildSlotButton(parent, spec)
    local btn = CreateFrame("Button", nil, parent, "UIMenuButtonStretchTemplate")
    -- Layout normally provides width/height; the defaults below let the
    -- factory work for direct callers (debug surfaces, ad-hoc tests).
    btn:SetSize(spec.width or 160, spec.height or 22)  -- exception(optional): factory defaults
    btn:SetText(spec.text or "")
    -- applyFontRole works on UIMenuButtonStretchTemplate too -- its
    -- ButtonText region accepts SetFontObject.
    if spec.font then applyFontRole(btn, spec.font) end
    -- Y=1 nudge -- same correction HDG.UI:Button applies. The silver
    -- chrome's highlight stripe at the top makes geometric center read as
    -- visually too-low; lifting the text 1px puts it on the chrome's
    -- visual center. SetText creates the font string; we re-anchor it.
    -- (Blizzard's KeyBinding template uses y=-1 because its rendering
    -- pipeline differs -- the silver chrome reads cleaner with y=+1 in
    -- our slot heights.)
    local fs = btn.GetFontString and btn:GetFontString()
    if fs and fs.ClearAllPoints then
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", btn, "CENTER", 0, 1)
    end
    -- Theme registration with tone + muted + textTone + active state.
    -- Defaults: tone="default" (no chrome tint), muted=false (full silver
    -- chrome), textTone=nil (text follows text.primary), active=false.
    HDG.Theme:Register(btn, "SlotButton", {
        tone     = spec.tone or "default",
        muted    = spec.muted == true,
        textTone = spec.textTone,
        active   = false,
    })
    return btn
end

HDG.WidgetTypes:Register("slotButton", {
    build    = buildSlotButton,
    -- Theme paints via the SlotButton skinner above. dispatch carries
    -- text + tone + muted + textTone + active so bindings can recolor /
    -- toggle a slot at runtime. active flips chrome to accent + match
    -- text -- mirrors the button kind's `active` semantics so toggle
    -- groups (sub-tabs, mode chips) can use the same binding shape.
    dispatch = { fields = { "text", "tone", "muted", "textTone", "active" },
                 push = function(widget, values)
        _applyBoundString(widget, values.text, "SetText")
        -- Theme state update -- only fire if at least one paint field
        -- changed (avoids unnecessary Skinner re-paint on text-only updates).
        if values.tone == nil and values.muted == nil
           and values.textTone == nil and values.active == nil then return end
        local update = {}
        if values.tone     ~= nil then update.tone     = values.tone     end
        if values.muted    ~= nil then update.muted    = values.muted    end
        if values.textTone ~= nil then update.textTone = values.textTone end
        if values.active   ~= nil then update.active   = values.active and true or false end
        HDG.Theme:SetState(widget, update)
    end },
    specFields = { "binding", "width", "height", "text", "font",
                   "tone", "muted", "textTone" },
})

-- navItem retired; sidebar nav is a TreeList (navNode + NavRow skinner).
-- NavRegion (Theme) is kept -- paints the nav panel background (panel_soft).

-- lumberRadar: circular live-render widget. Construction + per-frame
-- paint live in Modules/HDGR_LumberRadar.lua so this file stays focused
-- on widget-type registration. The build callback constructs the frame
-- chrome (rings, player dot, direction line, blip pool); the dispatch
-- callback feeds the latest blip array + scale into the render module;
-- a throttled OnUpdate ticks the live render at 20fps.
--
-- Binding shape (per spec):
--   binding = { blips = "lumber.blipsForRadar", scale = "lumber.radarScale" }
local function buildLumberRadar(parent, spec)
    local frame = CreateFrame("Frame", nil, parent)
    -- The radar paint module owns sizing internally via R.CONFIG.SIZE;
    -- spec.width/height come from the LayoutConfig and let Layout slot
    -- it correctly in the surrounding cells. SetSize gets called again
    -- inside R:Build to make sure the actual paint surface matches the
    -- radar geometry the projection math expects.
    if spec.width and spec.height then
        frame:SetSize(spec.width, spec.height)
    end
    -- Stash the handles table on the frame so dispatch + OnUpdate can
    -- reach the paint state without a closure over `frame` for each.
    frame._radarHandles = HDG.LumberRadar:Build(frame, { size = spec.width })
    -- Throttled render: accumulate elapsed, fire R:Render when over UPDATE_FREQUENCY.
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        self._updateAccum = (self._updateAccum or 0) + elapsed
        if self._updateAccum < HDG.LumberRadar.UPDATE_FREQUENCY then return end
        self._updateAccum = 0
        HDG.LumberRadar:Render(self._radarHandles)
    end)
    return frame
end

local function dispatchLumberRadar(widget, values)
    if not widget._radarHandles then return end
    HDG.LumberRadar:UpdateData(widget._radarHandles, values)
end

HDG.WidgetTypes:Register("lumberRadar", {
    build    = buildLumberRadar,
    dispatch = { fields = { "blips", "scale" }, push = dispatchLumberRadar },
    -- specFields: binding (selector map for blips + scale), width/height
    -- (from LayoutConfig; passed to R:Build for the paint surface).
    specFields = { "binding", "width", "height" },
})

-- Unified `button` WidgetTypes entry. One spec kind, four internal
-- shapes routed by spec fields:
--
--   spec.close = true              -> close-style (X icon, no template)
--   spec.atlas + spec.activeAtlas  -> toggle (two-base atlas swap)
--   spec.atlas (no activeAtlas)    -> atlas (single-base, 3-suffix atlases)
--   (no spec.atlas)                -> text button (UIPanelButtonTemplate)
--
-- Text buttons participate in the variant + state.active model from #10.3.
-- Icon buttons keep their existing SetActive (atlas swap) -- different
-- physical mechanism but the same conceptual flag.
HDG.WidgetTypes:Register("button", {
    build = function(parent, spec)
        if spec.close then
            return buildCloseButton(parent, spec)
        elseif spec.normalAtlas then
            return buildIconButton(parent, spec)
        elseif spec.atlas and spec.activeAtlas then
            return buildToggleButton(parent, spec)
        elseif spec.atlas then
            return buildAtlasButton(parent, spec)
        end
        -- Chip variant: compact tag-style button, custom factory so font
        -- + padding are first-class instead of fighting UIPanelButtonTemplate.
        if spec.variant == "chip" then
            local button = buildChipButton(parent, spec.text, spec.font)
            button._hdgrVariant = "chip"
            button._textTone   = spec.textTone
            return button
        end
        -- Text-button path: standard template + variant identity.
        local button = HDG.UI:Button(parent, spec.text, spec.font)
        button._hdgrVariant = spec.variant
        -- Optional semantic text tone (e.g. textTone = "error" for the
        -- Hard Reset destructive button). Atlas-path Skinner overrides
        -- the default tertiary text color with semantic.<tone> so the
        -- treatment survives theme swaps without imperative SetTextColor.
        button._textTone = spec.textTone
        -- Declarative `tooltip` works for text buttons too (was icon-only):
        -- no-op when tooltip is nil/false, so existing buttons are unaffected.
        attachIconTooltip(button, spec)
        return button
    end,
    dispatch = { fields = { "text", "enabled", "active", "attention" }, push = dispatchButton },
    skin = "Button",
    -- Close variant SetScripts OnEnter/OnLeave internally; controllers attach
    -- OnClick to every button. Declaring input.events makes the script surface
    -- visible to the validator and triggers the mandatory-destroy check.
    input = { events = { OnClick = true, OnEnter = true, OnLeave = true } },
    destroy = destroyWidget,
    -- Icon-only variants (spec.close / spec.atlas) render an atlas
    -- instead of text -- no `font` role required. Text-button paths (no
    -- atlas/close) do need a font. The validator (Layout) consults this
    -- predicate instead of peeking at the spec itself; spec section 5.
    requiresFont = function(spec)
        return not (spec.close == true or spec.atlas ~= nil or spec.normalAtlas ~= nil)
    end,
    specFields = {
        "text", "font", "variant", "textTone",         -- text-button path
        "close", "atlas", "activeAtlas", "rotation",   -- icon paths
        "normalAtlas", "highlightAtlas",               -- explicit content-icon (no suffix convention)
        "size", "iconSize", "tooltip",                 -- icon sizing + tooltip
        -- Controller-side identifiers. LayoutConfig stamps these on
        -- dynamically-generated button clusters so the matching Controller
        -- can iterate them by tag at Wire() time (chrome tab buttons,
        -- decor tag rows, top-filter size strip, alts population pills,
        -- active-filter chip strip, decor toggle pair, Mogul profession
        -- pill strip). Pure data; the build path doesn't read them.
        "view", "tagSlot", "topFilter", "population", "axis",
        "toggle", "profession",
    },
})

function HDG.UI:EditBox(parent, opts, font)
    opts = opts or {}

    -- Local helper: attach a placeholder FontString to an editbox-shaped
    -- widget. The placeholder shows when the editbox is empty and not
    -- focused; it hides on focus or as soon as the user types. WoW EditBox
    -- has no native placeholder, so we paint one as an OVERLAY FontString.
    local function attachPlaceholder(host, edit, text, placeFn)
        if not (text and text ~= "" and host.CreateFontString) then return end
        local ph = host:CreateFontString(nil, "OVERLAY")
        applyFontToFS(ph, font)
        ph:SetText(text)
        ph:SetWordWrap(true)
        ph:SetJustifyH("LEFT")
        ph:SetJustifyV("TOP")
        HDG.Theme:Register(ph, "TextDim")
        placeFn(ph)
        local function refresh()
            local hasText = (edit.GetText and edit:GetText() or "") ~= ""
            local focused = edit.HasFocus and edit:HasFocus()
            if hasText or focused then ph:Hide() else ph:Show() end
        end
        if edit.HookScript then  -- exception(false-positive): Frame always has HookScript; mock-fidelity guard
            edit:HookScript("OnEditFocusGained", refresh)
            edit:HookScript("OnEditFocusLost",   refresh)
            edit:HookScript("OnTextChanged",     refresh)
        end
        -- Stash a direct refresh handle so callers can force a re-evaluation
        -- after programmatic SetText. OnTextChanged-via-SetText is not
        -- guaranteed across all WoW client versions, so this is the belt
        -- to the hook's suspenders.
        host._hdgrPlaceholderRefresh = refresh
        edit._hdgrPlaceholderRefresh = refresh
        refresh()
    end

    -- SINGLE-LINE: bare EditBox with backdrop. Standard WoW pattern -- one
    -- frame, native cursor behaviour, no template wrappers. Chrome comes
    -- from the EditBox theme skinner (canvas bg + visible border).
    if opts.multiline ~= true then
        local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        box:SetAutoFocus(false)
        box:SetMultiLine(false)
        box:SetMaxLetters(opts.maxLetters or 4000)  -- exception(optional): option default
        box:SetJustifyH(opts.justifyH or "LEFT")
        box:SetJustifyV(opts.justifyV or "MIDDLE")
        box:EnableMouse(true)
        box:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
        -- Theme:Register owned by Layout via WidgetType.skin = "EditBox".
        applyFontRole(box, font)
        box:SetTextInsets(8, 8, 4, 4)
        -- Focus ring: flip the EditBox skinner to border.focus while focused.
        if box.HookScript then  -- exception(false-positive): Frame always has HookScript; mock-fidelity guard
            box:HookScript("OnEditFocusGained", function() HDG.Theme:SetState(box, { focused = true }) end)
            box:HookScript("OnEditFocusLost",   function() HDG.Theme:SetState(box, { focused = false }) end)
        end
        attachPlaceholder(box, box, opts.placeholder, function(ph)
            ph:SetPoint("LEFT", 8, 0)
            ph:SetPoint("RIGHT", -8, 0)
        end)
        return box
    end

    -- MULTI-LINE: ScrollFrame container + auto-growing inner EditBox. Without
    -- the wrapper a multi-line WoW EditBox auto-grows to fit content (no
    -- fixed size, no scroll). InputScrollFrameTemplate is Blizzard's standard
    -- multi-line text input -- ScrollFrame clips to a fixed size, EditBox
    -- inside grows, scrollbar appears when content overflows.
    --
    -- This template is multi-line-only by design. Don't try to use it for
    -- single-line inputs (cursor positioning misbehaves; see git history).
    local container = CreateFrame("ScrollFrame", nil, parent, "InputScrollFrameTemplate")
    container.multiLine = true  -- marker for tests + introspection
    if container.CharCount then container.CharCount:Hide() end  -- exception(boundary): CharCount is an InputScrollFrameTemplate sub-widget; absent in some Blizzard template versions
    -- Theme:Register owned by Layout via WidgetType.skin = "EditBox".
    container:EnableMouse(true)
    local edit = container.EditBox
    if not edit then return container end  -- mock environments without the template

    container:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- Force EditBox width on container resize. The template's OnSizeChanged
    -- updates the ScrollChild but the EditBox anchored inside doesn't always
    -- propagate -- without this, the EditBox stays at its template default
    -- width (~100px) and any non-space char wraps to the next line. Use
    -- HookScript so we don't overwrite the template's own handler.
    container:HookScript("OnSizeChanged", function(sf, w)
        if sf.EditBox and sf.EditBox.SetWidth then
            sf.EditBox:SetWidth(math.max(1, (w or 0) - 24))  -- room for scrollbar
        end
    end)

    edit:SetAutoFocus(false)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(opts.maxLetters or 4000)  -- exception(optional): option default
    edit:SetJustifyH(opts.justifyH or "LEFT")
    edit:SetJustifyV(opts.justifyV or "TOP")
    applyFontRole(edit, font)

    -- Focus ring: the container is the skinned (EditBox) frame; the inner edit
    -- owns focus, so route SetState to the container.
    if edit.HookScript then  -- exception(false-positive): Frame always has HookScript; mock-fidelity guard
        edit:HookScript("OnEditFocusGained", function() HDG.Theme:SetState(container, { focused = true }) end)
        edit:HookScript("OnEditFocusLost",   function() HDG.Theme:SetState(container, { focused = false }) end)
    end

    attachPlaceholder(container, edit, opts.placeholder, function(ph)
        ph:SetPoint("TOPLEFT", 8, -8)
        ph:SetPoint("RIGHT", -24, 0)  -- leave room for the scrollbar
    end)

    -- Forward SetText / GetText / SetScript / SetFocus / ClearFocus to the
    -- inner editbox so controllers can treat the container as the editbox.
    -- (Layout:Apply still calls SetSize on the container, which is what we
    -- want -- the visible viewport stays the spec'd size.)
    function container:SetText(text)
        edit:SetText(text or "")
        -- Reset scroll so loading a short value after a long one doesn't leave
        -- the viewport scrolled past the new content (would render as a
        -- mostly-empty box with stale top region from the previous content).
        container:SetVerticalScroll(0)
    end
    function container:GetText() return edit:GetText() end
    function container:SetFocus() edit:SetFocus() end
    function container:ClearFocus() edit:ClearFocus() end
    function container:HasFocus() return edit:HasFocus() end
    -- Forward script handlers to the inner edit (where text events fire).
    -- OnSizeChanged stays on the container so the engine's SetSize works.
    local TEXT_EVENTS = {
        OnTextChanged = true, OnEditFocusGained = true, OnEditFocusLost = true,
        OnEnterPressed = true, OnEscapePressed = true, OnTabPressed = true,
        OnTextSet = true, OnChar = true,
    }
    local containerSetScript = container.SetScript
    function container:SetScript(name, fn)
        if TEXT_EVENTS[name] then return edit:SetScript(name, fn) end
        return containerSetScript(self, name, fn)
    end

    return container
end

HDG.WidgetTypes:Register("editbox", {
    build = function(parent, spec)
        return HDG.UI:EditBox(parent, spec, spec.font)
    end,
    dispatch = { fields = { "text" }, push = dispatchEditbox },
    skin = "EditBox",
    -- HDG.UI:EditBox SetScripts OnEnterPressed/OnEscapePressed/OnTextChanged
    -- and OnMouseDown (container focus delegate). Declaring input.events
    -- engages the validator's mandatory-destroy check.
    input = {
        events = {
            OnEnterPressed = true, OnEscapePressed = true, OnTextChanged = true,
            OnEditFocusGained = true, OnEditFocusLost = true, OnMouseDown = true,
        },
    },
    destroy = destroyWidget,
    specFields = { "text", "font", "multiline", "placeholder", "maxLetters",
                   "justifyH", "justifyV", "wrap", "tags" },
})

-- Shared MinimalScrollBar polish: hide arrows, refit the track, auto-hide
-- when content fits, theme-tint the thumb. Every scrollbox factory in
-- HDG (the legacy HDG.UI:ScrollBox + the newer CardGrid / ChipStrip /
-- TreeList modules) should call this so scrollbars look consistent
-- across tabs. Vamoose flagged that Styles tab bars looked different --
-- they were skipping these steps because the new modules didn't share
-- the polish path.
function HDG.UI:PolishMinimalScrollBar(scrollBar)
    if not scrollBar then return end
    -- Hide the up/down arrows. Mouse-wheel + drag handles all scrolling.
    if scrollBar.Back    then scrollBar.Back:Hide()    end  -- exception(boundary): Back/Forward/Track are MinimalScrollBar template sub-widgets; absent in some Blizzard template versions
    if scrollBar.Forward then scrollBar.Forward:Hide() end  -- exception(boundary): see scrollBar.Back above
    -- Track is normally anchored between the arrow buttons; with arrows
    -- hidden the track inherits that dead space -- re-anchor to fill the
    -- whole bar height.
    if scrollBar.Track and scrollBar.Track.ClearAllPoints then  -- exception(boundary): Track sub-widget; ClearAllPoints guard = template variant check
        scrollBar.Track:ClearAllPoints()
        scrollBar.Track:SetPoint("TOPLEFT",     scrollBar, "TOPLEFT",     0, 0)
        scrollBar.Track:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
    end
    -- Visibility (hide when content fits) is owned by the managed-visibility
    -- behavior wired in CreateScrollBoxSkeleton, which ALSO reclaims the
    -- scrollbar gutter -- so SetHideIfUnscrollable is no longer set here (it
    -- would only hide the bar, leaving the dead gutter). noScrollBar surfaces
    -- hide the bar manually in the skeleton.
    -- Theme-driven thumb tint: ScrollThumb Skinner reads semantic.accent
    -- and tints the three texture children (Begin/Middle/End). Repaints on
    -- Theme:Reload via the registry.
    if scrollBar.Track and scrollBar.Track.Thumb then  -- exception(boundary): Track.Thumb is a MinimalScrollBar template sub-widget; absent in some Blizzard template versions
        HDG.Theme:Register(scrollBar.Track.Thumb, "ScrollThumb")
    end
end

-- Shared scrollbox+scrollbar skeleton. Returns (host, scrollBox, scrollBar)
-- with the bar already polished. Every HDG scrollbox factory builds on
-- this -- the legacy HDG.UI:ScrollBox (LinearView), HDG.CardGrid
-- (LinearView + multi-cell rows), HDG.ChipStrip (SequenceView), and
-- HDG.TreeList (TreeListView). Each adds its OWN view + initializer
-- on top of the shared frame setup.
--
-- Layout:
--   parent
--     host       (fills parent rect)
--       scrollBox  (TOPLEFT 0,0 -- BOTTOMRIGHT -6, 0 -- 6px gutter for the bar
--                   OR BOTTOMRIGHT 0, 0 when opts.noScrollBar = true)
--       scrollBar  (anchored to scrollBox's right edge, +2 x offset;
--                   permanently hidden when opts.noScrollBar = true)
--
-- opts.noScrollBar (default false): for surfaces where scrolling is
--     never appropriate (chip strips that should wrap, not scroll). The
--     bar is still constructed (some Blizzard ScrollBox internals expect
--     it to exist) but hidden + zero-width + given OnShow no-op so any
--     framework re-show is squashed. The scrollBox claims the gutter
--     too so chips can use the full width.
-- Width reserved at scrollBox.BOTTOMRIGHT for the MinimalScrollBar (anchored
-- at scrollBox.TOPRIGHT + 2). Exported so layout math (and the
-- `/hdgr layout` debug helper) can reason about effective scrollbox width
-- without re-reading the SetPoint magic number.
HDG.UI.SCROLLBOX_SCROLLBAR_RESERVE = 6

function HDG.UI:CreateScrollBoxSkeleton(parent, opts)
    opts = opts or {}
    local host = CreateFrame("Frame", nil, parent)
    local scrollBox = CreateFrame("Frame", nil, host, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, 0)
    if opts.noScrollBar then
        scrollBox:SetPoint("BOTTOMRIGHT", 0, 0)
    else
        scrollBox:SetPoint("BOTTOMRIGHT", -HDG.UI.SCROLLBOX_SCROLLBAR_RESERVE, 0)
    end
    local scrollBar = CreateFrame("EventFrame", nil, host, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
    self:PolishMinimalScrollBar(scrollBar)
    if opts.noScrollBar then
        scrollBar:Hide()
        scrollBar:SetWidth(1)
        -- Defend against ScrollBox internals re-showing the bar
        -- (SetHideIfUnscrollable + AddManagedScrollBarVisibilityBehavior
        -- + RegisterCallback all try to toggle visibility).
        scrollBar:SetScript("OnShow", function(self) self:Hide() end)
    elseif opts.fixedGutter then
        -- Constant-gutter mode (fixed-width sidebars, e.g. the nav). The
        -- scrollBox keeps its static -RESERVE BOTTOMRIGHT (set above) FOREVER --
        -- no managed reclaim swap -- so the content width never changes when the
        -- bar shows/hides. This kills the horizontal "flap" (content reflowing
        -- 6px wider/narrower as HasScrollableExtent crosses the threshold during
        -- boot) that wrapped fixed-width nav labels to two lines. The bar still
        -- auto-hides when the list fits (SetHideIfUnscrollable); the leftover
        -- 6px gutter is invisible on a dark chrome panel. Use ONLY for
        -- fixed-width surfaces -- content panels want the reclaim (else branch).
        if scrollBar.SetHideIfUnscrollable then scrollBar:SetHideIfUnscrollable(true) end  -- exception(boundary): SetHideIfUnscrollable absent in some Blizzard scrollbar template versions
    else
        -- Managed scrollbar visibility + GUTTER RECLAIM. The behavior owns the
        -- bar's show/hide (from HasScrollableExtent) AND swaps the scrollBox
        -- anchors: `withBar` reserves the gutter so rows clear the bar; when
        -- content fits and the bar hides, `withoutBar` extends the scrollBox to
        -- the full host width (no dead gutter). Pattern from
        -- Blizzard_Communities/GuildPerks.lua. Safe to wire pre-view: the Init
        -- force-eval reads GetDerivedExtent (0 with no view) -> not scrollable
        -- -> withoutBar; it re-evaluates on OnLayout once the factory sets the
        -- view + data.
        if _G.CreateAnchor and _G.ScrollUtil and _G.ScrollUtil.AddManagedScrollBarVisibilityBehavior then  -- exception(boundary): CreateAnchor + ScrollUtil are FrameXML globals; absent in headless test mock
            local R = HDG.UI.SCROLLBOX_SCROLLBAR_RESERVE
            local withBar = {
                _G.CreateAnchor("TOPLEFT",     host, "TOPLEFT",      0, 0),
                _G.CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", -R, 0),
            }
            local withoutBar = {
                _G.CreateAnchor("TOPLEFT",     host, "TOPLEFT",     0, 0),
                _G.CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0),
            }
            _G.ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, withBar, withoutBar)
        end
    end
    -- Stash scrollBox on host so module consumers (which receive the host
    -- as their public "widget" surface) can reach the scrollBox for
    -- SetDataProvider / view operations without an extra arg.
    host._scrollBox = scrollBox
    host._scrollBar = scrollBar
    return host, scrollBox, scrollBar
end

-- Re-initialize a single row whose selection state just changed. Walks
-- the active view to find the registered initializer for elementData and
-- re-invokes it on the row frame. Falls back to ReinitializeFrames() when
-- (a) the frame isn't currently visible (scrolled out of view), or (b)
-- the view doesn't expose the initializer API. The fallback is cheap --
-- bounded by visible viewport row count.
--
-- Public on HDG.UI so SelectionBehavior consumers (ScrollBox, TreeList,
-- future list widgets) share one implementation.
function HDG.UI._ReinitSelectionRow(scrollBox, elementData)
    local frame = scrollBox:FindFrame(elementData)
    if not (frame and scrollBox.GetView) then
        scrollBox:ReinitializeFrames()
        return
    end
    local view = scrollBox:GetView()
    if not (view and view.InvokeInitializer and view.GetElementInitializer) then
        scrollBox:ReinitializeFrames()
        return
    end
    local initializer = view:GetElementInitializer(elementData)
    if not initializer then
        scrollBox:ReinitializeFrames()
        return
    end
    view:InvokeInitializer(frame, initializer)
end

function HDG.UI:ScrollBox(parent, opts)
    opts = opts or {}

    -- 6px gutter -- the scrollBox is inset just enough that row content
    -- (with its own 4px right padding) doesn't reach under the scrollbar
    -- thumb. The MinimalScrollBar template is ~10px wide so the bar
    -- bleeds a few pixels past the host's right edge into the panel's
    -- inset chrome area; visually acceptable given how subtle the bar is.
    -- Tighter than the 14px reservation we used initially -- more content
    -- per scrollbox, no clipped text.
    local host, scrollBox, scrollBar = self:CreateScrollBoxSkeleton(parent)

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, opts.spacing or 0)  -- exception(optional): no spacing default
    if type(opts.rowHeight) == "function" then
        view:SetElementExtentCalculator(opts.rowHeight)
    elseif type(opts.rowHeight) == "number" then
        view:SetElementExtent(opts.rowHeight)
    else
        error("ScrollBox: opts.rowHeight is required (number or function)", 2)
    end

    view:SetElementInitializer(opts.template or "Button", function(row, elementData)
        if row.SetWidth and scrollBox.GetWidth then  -- exception(false-positive): Frame always has SetWidth/GetWidth; mock-fidelity guard
            row:SetWidth(scrollBox:GetWidth())
        end
        -- Centralized zebra parity (HDG-ADR-025 row painting): stamp the row's
        -- 1-based DATA-index parity so the RowChrome skinner can stripe even
        -- rows. Runs before the consumer Configure so its
        -- Theme:Register(row, "RowChrome", ...) repaints with the right parity.
        -- Rows built on other paths (TreeList/nav, CardGrid) never reach here,
        -- so they stay flat -- which is the intended scope (data lists only).
        -- exception(boundary): GetDataProvider/FindIndex are Blizzard ScrollBox APIs and
        -- are absent under the headless test mock.
        local provider = scrollBox.GetDataProvider and scrollBox:GetDataProvider()
        local idx = provider and provider.FindIndex and provider:FindIndex(elementData)
        row._zebraAlt = (idx ~= nil and idx % 2 == 0) and true or false
        if opts.initializer then
            opts.initializer(row, elementData)
        end
    end)

    if opts.resetter then
        view:SetElementResetter(opts.resetter)
    end

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local provider = CreateDataProvider()
    SetDataProvider(scrollBox, provider)

    host.scrollBox = scrollBox
    host.scrollBar = scrollBar
    host.view = view
    host.provider = provider

    -- Optional SelectionBehaviorMixin. Caller passes `opts.selection = true`
    -- or `opts.selection = { deselectable = true, multi = false }`. We always
    -- run Intrusive so `elementData.selected` is stamped directly -- row
    -- initializers can branch on `ed.selected` without consulting the
    -- behavior, matching how `isFavorite` / `isCollected` flow through
    -- decor.items today. Replaces the Store-round-trip-per-click highlight:
    -- the data provider no longer needs to be invalidated to repaint the
    -- selected row, so the items selector can drop `selectedItemID` from its
    -- reads. See TODO 'SelectionBehaviorMixin migration' for the broader plan.
    if opts.selection and _G.ScrollUtil and _G.ScrollUtil.AddSelectionBehavior then
        local selOpts = type(opts.selection) == "table" and opts.selection or {}
        local Flags   = _G.SelectionBehaviorFlags or {}
        local flagArgs = { Flags.Intrusive }
        -- opts default: deselectable is on unless the caller explicitly opts out.
        if selOpts.deselectable == nil or selOpts.deselectable then flagArgs[#flagArgs+1] = Flags.Deselectable end
        if selOpts.multi then flagArgs[#flagArgs+1] = Flags.MultiSelect end
        host.selectionBehavior = _G.ScrollUtil.AddSelectionBehavior(scrollBox, unpack(flagArgs))

        -- Mirror Blizzard's ProfessionsRecipeList pattern: when selection
        -- changes the behavior fires OnSelectionChanged (twice on swap --
        -- once with selected=false for the old ed, once selected=true for
        -- the new). Find the affected frame and re-run the row initializer
        -- so Configure re-reads ed.selected and repaints chrome. Without
        -- this hook the click only updates the ed.selected stamp -- the
        -- row's visuals stay stale until something else triggers a refresh
        -- (filter change, scroll, etc.).
        if _G.SelectionBehaviorMixin and _G.SelectionBehaviorMixin.Event then  -- exception(boundary): SelectionBehaviorMixin is FrameXML; nil in headless test mock
            host.selectionBehavior:RegisterCallback(
                _G.SelectionBehaviorMixin.Event.OnSelectionChanged,
                function(_, elementData, _selected)
                    HDG.UI._ReinitSelectionRow(scrollBox, elementData)
                end, host)
        end
    end

    function host:SetItems(items, retainScroll)
        local newProvider = CreateDataProvider(items or {})
        SetDataProvider(self.scrollBox, newProvider, retainScroll and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil)
        self.provider = newProvider
        -- Selection re-sync: behavior's internal pointer is now stale (old
        -- eds gone, new eds in their place). Controllers that want to restore
        -- a Store-tracked selection after a filter change call
        -- host:SyncSelection(predicate) below.
        return newProvider
    end

    -- Re-apply a Store-tracked selection after a data-provider replacement.
    -- `predicate(ed) -> bool` walks the new provider; the first match is
    -- handed to SelectElementData (Intrusive flag stamps ed.selected so the
    -- next row Configure sees it). Returns the matched ed or nil. Caller is
    -- responsible for choosing what to do on nil (clear, keep stale, etc).
    function host:SyncSelection(predicate)
        if not (self.selectionBehavior and self.provider and predicate) then return nil end
        local match
        self.provider:ForEach(function(ed)
            if not match and predicate(ed) then match = ed end
        end)
        if match then
            self.selectionBehavior:SelectElementData(match)
        else
            self.selectionBehavior:ClearSelections()
        end
        return match
    end

    -- Arrow-key navigation with wrap-around. Returns the newly-selected ed
    -- or nil if the provider is empty. Caller dispatches its own Store
    -- update with the returned ed (the behavior-side selection already
    -- happened atomically; Store-side dispatch then re-syncs us via
    -- WireStoreSelectionSync, which is a no-op because ed is unchanged).
    -- Auto-scrolls the new selection into view via ScrollToElementData
    -- (cheaper than ScrollToNearest -- ScrollBox handles the visibility
    -- check internally). Replaces hand-rolled navigateList helpers.
    --
    -- Wrap policy: at the first item, Up jumps to the last; at the last
    -- item, Down jumps to the first. Matches HDG_DecorPreviewTab legacy
    -- behaviour. Pass wrap=false to disable.
    function host:SelectByArrow(direction, wrap)
        local b = self.selectionBehavior
        if not b then return nil end
        local sb = self.scrollBox
        if not (sb and sb.HasDataProvider and sb:HasDataProvider()) then return nil end
        local provider = sb:GetDataProvider()
        if not provider or provider:GetSize() == 0 then return nil end
        if wrap == nil then wrap = true end   -- arg default: wrap on unless caller passes false
        local ed
        if not b:HasSelection() then
            -- Nothing selected -- prime with first item regardless of direction.
            ed = provider:Find(1)
            if ed then b:SelectElementData(ed) end
        elseif direction == "down" or direction == "DOWN" then
            if wrap and b:IsLastElementDataSelected() then
                ed = provider:Find(1)
                if ed then b:SelectElementData(ed) end
            else
                ed = b:SelectNextElementData()
            end
        elseif direction == "up" or direction == "UP" then
            if wrap and b:IsFirstElementDataSelected() then
                ed = provider:Find(provider:GetSize())
                if ed then b:SelectElementData(ed) end
            else
                ed = b:SelectPreviousElementData()
            end
        end
        if ed and sb.ScrollToElementData then
            local ok, err = pcall(sb.ScrollToElementData, sb, ed)
            if not ok then HDG.Log:Warn("scroll", "ScrollToElementData failed: " .. tostring(err)) end
        end
        return ed
    end

    -- Bind the SelectionBehavior to a Store-tracked id. Wires both seams:
    --   (a) every SetItems/Refresh re-syncs the behavior to the current
    --       Store id (handles filter changes that replace the provider).
    --   (b) every Store invalidation of `statePath` re-syncs the behavior
    --       (handles a Store-driven selection change without a data refresh
    --       -- e.g. row click -> dispatch action -> we land here).
    -- `statePath` is the dotted Store path (e.g. "session.ui.decor.selectedItemID").
    -- `matchFn(ed, id)` returns true if the elementData represents the id.
    -- Caller pins the returned subscribe token to a frame's lifetime via
    -- the host frame itself (the closure keeps `host` alive; teardown
    -- happens when the addon unloads).
    function host:WireStoreSelectionSync(statePath, matchFn)
        if not (self.selectionBehavior and statePath and matchFn) then return end
        local function read()
            local node = HDG.Store:GetState()
            for segment in statePath:gmatch("[^.]+") do
                node = node and node[segment]
                if node == nil then return nil end
            end
            return node
        end
        local function sync()
            local id = read()
            self:SyncSelection(function(ed) return matchFn(ed, id) end)
        end
        -- (a) Hook the provider-swap path. hooksecurefunc on the host method.
        hooksecurefunc(self, "SetItems", sync)
        hooksecurefunc(self, "Refresh", sync)
        -- (b) Store invalidation path. HDG.Paths.MatchesAny handles "*" too.
        self._selectionStoreToken = HDG.Store:Subscribe(function(_, invalidation)
            if HDG.Paths.MatchesAny({ statePath }, invalidation) then sync() end
        end)
    end

    function host:Refresh(items)
        if self.provider and self.provider.Flush and self.provider.InsertTable then
            self.provider:Flush()
            if items and #items > 0 then
                self.provider:InsertTable(items)
            end
            return self.provider
        end

        return self:SetItems(items, true)
    end

    -- Custom ApplyLayout: position + force the inner WowScrollBoxList to
    -- recompute its viewport. WowScrollBoxList listens to OnSizeChanged on
    -- its own frame, but the host -> scrollBox propagation can lag a frame;
    -- calling :Update() (or re-applying the data provider) here guarantees
    -- the visible row range expands to fill the new rect immediately.
    function host:ApplyLayout(region)
        if not region then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", region.x, -region.y)
        self:SetSize(region.width, region.height)
        local sb = self.scrollBox
        if sb then
            if sb.Update then sb:Update()  -- exception(boundary): scrollBox exposes Update or FullUpdate depending on Blizzard template version
            elseif sb.FullUpdate then sb:FullUpdate() end
        end
    end

    return host
end

HDG.WidgetTypes:Register("scrollbox", {
    build = function(parent, spec)
        local rowKind = spec.rowKind

        -- Single source for row definition: HDG.Rows registry contains the
        -- full shape (font, height) + behaviour (factory) in one entry. The
        -- validator guarantees the entry + its factory exist when rowKind set.
        local row, def
        if rowKind then
            def = HDG.Rows:Get(rowKind)
            if not def then
                error(("scrollbox factory: row %q not registered in HDG.Rows"):format(rowKind), 2)
            end
            row = def.factory(def)
        end

        local scrollOpts = {
            rowHeight = (def and def.height) or spec.rowHeight,
            spacing   = spec.spacing,
            template  = spec.template,
            -- Propagate SelectionBehavior from the spec. Without this
            -- `selection = true` would silently no-op because HDG.UI:ScrollBox
            -- never sees the flag.
            selection = spec.selection,
        }
        if not scrollOpts.rowHeight then
            error("scrollbox factory: rowHeight required (set via row entry in HDG.Rows or spec.rowHeight)", 2)
        end
        if row then
            scrollOpts.initializer = row.Configure
            scrollOpts.resetter    = row.Reset
        end

        local box = HDG.UI:ScrollBox(parent, scrollOpts)
        if box then
            box.rowKind = rowKind
            -- Stash the row def so dispatchScrollbox can call its key()
            -- function for nil + collision detection (spec section 10
            -- rules 5 + 6). Layout's BindingEngine.Apply pushes items
            -- through dispatchScrollbox -> SetItems; we validate there.
            box._hdgrRowDef = def
            -- Theme:Register owned by Layout via WidgetType.skin = "Frame".
        end
        return box
    end,
    dispatch = { fields = { "items" }, push = dispatchScrollbox },
    skin = "Frame",
    specFields = { "rowKind", "rowHeight", "spacing", "template", "selection" },
})

-- ===== cardGrid: multi-cell-per-row scrollbox =============================
-- Wraps HDG.CardGrid (Modules/HDGR_CardGrid.lua) so LayoutConfig can
-- declare a card-grid the same way it declares a scrollbox. The grid
-- behaves like a scrollbox but each scrollbox row holds N cells.
--
-- Spec shape:
--   kind = "cardGrid",
--   binding = "<selector returning flat items[]>",
--   options = {
--       cellKind     = "stylesCuratorTile",  -- registered via
--                                            -- HDG.CardGrid:RegisterCellKind
--       cellsPerRow  = 6,
--       cellSize     = 80,
--       cellSpacing  = 4,
--       rowSpacing   = 4,
--   }
--
-- Like the scrollbox widget, the binding pushes `items` through
-- dispatchCardGrid which calls scrollBox:SetItemsCardGrid(items).
-- Action-meta-driven scroll-retain decision. Default = reset to top (HDG's
-- canonical behavior; "tier / filter / style changes can leave the user
-- staring at an empty region"). Actions opt into retain via
-- `retainsScroll = true` in their Init.lua meta entry -- typically those
-- that tweak in-place (select item, toggle multi-select, hover, etc.)
-- without changing the underlying dataset.
local function _shouldRetainScroll(dispatchCtx)
    local actionType = dispatchCtx and dispatchCtx.actionType
    if not actionType then return false end
    local meta = HDG.Store:GetActionMeta(actionType)
    return meta and meta.retainsScroll == true
end

local function dispatchCardGrid(widget, values, dispatchCtx)
    if values.items == nil or not widget._cardGridCfg then return end
    HDG.CardGrid:SetItems(widget, values.items, _shouldRetainScroll(dispatchCtx))
end

HDG.WidgetTypes:Register("cardGrid", {
    build = function(parent, spec)
        if not (HDG.CardGrid.Create) then
            error("cardGrid factory: HDG.CardGrid module not loaded", 2)
        end
        local box, _bar = HDG.CardGrid:Create(parent, {
            cellKind    = spec.cellKind,
            cellSize    = spec.cellSize,
            cellSpacing = spec.cellSpacing,
            rowSpacing  = spec.rowSpacing,
            -- cellsPerRow is now advisory (SequenceView wraps based on
            -- actual container width + per-element cellSize). LayoutConfig
            -- entries that still pass it are no-ops.
        })
        return box
    end,
    dispatch = { fields = { "items" }, push = dispatchCardGrid },
    skin = "Frame",
    specFields = { "cellKind", "cellSize", "cellSpacing", "rowSpacing", "cellsPerRow" },
})

-- ===== filmstrip: horizontal single-row scrollable cell strip ==============
-- A horizontal filmstrip for a small ORDERED list where wrapping into rows is
-- wrong -- e.g. the companion's "Recent placements" (newest on the LEFT). Plain
-- ScrollFrame (mouse-wheel scrolls one cell at a time -- the proven HouseTab
-- trophy-shelf pattern), laying each item out left-to-right instead of the
-- cardGrid's wrap-and-vertical-scroll. Renders each item via a registered
-- CardGrid cellKind so it reuses companionGridCell's icon/tooltip/chrome; cells
-- are cached + reused across pushes (the list is small + capped).
local function dispatchFilmstrip(widget, values)
    if values.items == nil or not widget._filmContent then return end
    local kindDef = HDG.CardGrid:GetCellKind(widget._filmCellKind)
    if not kindDef then return end
    local content, cells, cfg = widget._filmContent, widget._filmCells, widget._filmCfg
    local pitch = cfg.cellSize + cfg.cellSpacing
    local items = values.items
    for i, ed in ipairs(items) do
        local cell = cells[i]
        local isNew = not cell
        if isNew then
            cell = CreateFrame("Button", nil, content)
            cells[i] = cell
        end
        cell:SetSize(cfg.cellSize, cfg.cellSize)
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", content, "LEFT", (i - 1) * pitch, 0)  -- index 1 (newest) -> leftmost
        -- resetFunc only on REUSED cells (clears stale desaturate/scripts/border);
        -- a brand-new cell has no anatomy yet -- initFunc builds it. Mirrors
        -- CardGrid's `if not new` resetter contract.
        if not isNew and kindDef.resetFunc then kindDef.resetFunc(nil, cell) end
        kindDef.initFunc(cell, ed, cfg)
        cell:Show()
    end
    for i = #items + 1, #cells do cells[i]:Hide() end
    content:SetWidth(math.max(1, #items * pitch))
    content:SetHeight(cfg.cellSize)
    widget:SetHorizontalScroll(0)   -- newest-left: snap back to the start on a fresh push
    if widget._filmSyncBar then widget._filmSyncBar() end
end

HDG.WidgetTypes:Register("filmstrip", {
    build = function(parent, spec)
        local scroll  = CreateFrame("ScrollFrame", nil, parent)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(1, spec.cellSize or 60)  -- exception(optional): spec field default (validator-guarded)
        scroll:SetScrollChild(content)
        scroll._filmContent  = content
        scroll._filmCells    = {}
        scroll._filmCellKind = spec.cellKind
        scroll._filmCfg      = { cellSize = spec.cellSize or 60, cellSpacing = spec.cellSpacing or 5 }  -- exception(optional): spec field default (validator-guarded)
        local step = (spec.cellSize or 60) + (spec.cellSpacing or 5)  -- exception(optional): spec field default (validator-guarded)

        -- Thin auto-hiding horizontal scrollbar along the bottom: a track + a
        -- draggable thumb (width = viewport/content ratio). Hidden when nothing
        -- overflows. The cells sit at the top of the viewport (content is shorter
        -- than the frame), so the 3px track at the bottom never overlaps them.
        local track = CreateFrame("Frame", nil, scroll)
        track:SetHeight(3)
        track:SetPoint("BOTTOMLEFT", 0, 0)
        track:SetPoint("BOTTOMRIGHT", 0, 0)
        local trackTex = track:CreateTexture(nil, "BACKGROUND")
        trackTex:SetAllPoints()
        trackTex:SetColorTexture(1, 1, 1, 0.08)
        local thumb = CreateFrame("Frame", nil, track)
        thumb:SetWidth(20)
        local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(1, 1, 1, 0.35)
        thumb:EnableMouse(true)

        local function syncBar()
            local viewportW = scroll:GetWidth() or 0
            local contentW  = content:GetWidth() or 1
            local range     = scroll:GetHorizontalScrollRange() or 0
            if range <= 0 or viewportW <= 1 then track:Hide(); return end
            track:Show()
            local trackW = track:GetWidth() or viewportW
            local thumbW = math.max(20, math.floor(trackW * viewportW / contentW))
            thumb._maxX  = math.max(0, trackW - thumbW)
            thumb:SetWidth(thumbW)
            local s = scroll:GetHorizontalScroll() or 0
            thumb._x = range > 0 and (s / range) * thumb._maxX or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP"); thumb:SetPoint("BOTTOM")
            thumb:SetPoint("LEFT", track, "LEFT", thumb._x, 0)
        end
        scroll._filmSyncBar = syncBar

        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = self:GetHorizontalScrollRange() or 0  -- exception(boundary): frame geometry nil before first layout
            self:SetHorizontalScroll(math.max(0, math.min(max, self:GetHorizontalScroll() - delta * step)))
            syncBar()
        end)

        -- Thumb drag: track the cursor in the thumb's local (effective-scale)
        -- space and map its X back to a scroll offset.
        thumb:SetScript("OnMouseDown", function(self) self._drag = { cx = _G.GetCursorPosition(), x = self._x or 0 } end)
        thumb:SetScript("OnMouseUp",   function(self) self._drag = nil end)
        thumb:SetScript("OnHide",      function(self) self._drag = nil end)
        thumb:SetScript("OnUpdate", function(self)
            if not self._drag then return end
            local sc    = track:GetEffectiveScale()
            local newX  = math.max(0, math.min(self._maxX or 0,
                self._drag.x + (_G.GetCursorPosition() / sc - self._drag.cx / sc)))
            local range = scroll:GetHorizontalScrollRange() or 0
            scroll:SetHorizontalScroll((self._maxX or 0) > 0 and (newX / self._maxX) * range or 0)
            syncBar()
        end)

        return scroll
    end,
    dispatch = { fields = { "items" }, push = dispatchFilmstrip },
    input = { events = { OnMouseWheel = true } },
    destroy = destroyWidget,
    -- No skin: the enclosing inset section provides the chrome; the cells carry
    -- their own visuals (a ScrollFrame has no SetBackdrop for the Frame skin).
    specFields = { "cellKind", "cellSize", "cellSpacing" },
})

-- ===== treeList: 2-level expandable list ==================================
-- Wraps HDG.TreeList (Modules/HDGR_TreeList.lua) so LayoutConfig can
-- declare a TreeListView-backed expandable list the same way it declares
-- scrollbox / cardGrid / chipStrip. Each tree node carries .kind so the
-- view's element factory routes to the right cell kind.
--
-- Spec shape:
--   kind = "treeList",
--   binding = "<selector returning root nodes (each with .children)>",
--   options = {
--       indent     = N,    -- px per nesting level (override)
--       rowHeight  = N,    -- uniform row height
--       rowSpacing = N,
--   }
local function dispatchTreeList(widget, values, dispatchCtx)
    if values.items == nil or not widget._treeListCfg then return end
    if HDG.TreeList then  -- exception(false-positive): HDG.TreeList is TOC-guaranteed at runtime; headless test mock omits it
        local actionType = dispatchCtx and dispatchCtx.actionType
        local meta = actionType and HDG.Store:GetActionMeta(actionType)
        HDG.TreeList:SetItems(widget, values.items, {
            retainScroll = _shouldRetainScroll(dispatchCtx),
            collapseOnly = meta and meta.treeCollapseOnly == true,
        })
    end
end

HDG.WidgetTypes:Register("treeList", {
    build = function(parent, spec)
        if not (HDG.TreeList.Create) then
            error("treeList factory: HDG.TreeList module not loaded", 2)
        end
        local box, _bar = HDG.TreeList:Create(parent, {
            indent     = spec.indent,
            rowHeight  = spec.rowHeight,
            rowSpacing = spec.rowSpacing,
            -- Propagate SelectionBehavior (same as scrollbox factory).
            selection  = spec.selection,
            -- Constant-width scrollbar gutter (no reclaim flap) for fixed-width
            -- surfaces. fixedGutter reserves the 6px bar gutter permanently;
            -- noScrollBar drops the bar entirely + claims the full width (for
            -- surfaces sized to never scroll, e.g. the height-tuned sidebar nav).
            fixedGutter = spec.fixedGutter,
            noScrollBar = spec.noScrollBar,
        })
        return box
    end,
    dispatch = { fields = { "items" }, push = dispatchTreeList },
    skin = "Frame",
    specFields = { "indent", "rowHeight", "rowSpacing", "selection", "fixedGutter", "noScrollBar" },
})

-- ===== chipStrip: wrap-and-flow chip row ==================================
-- Wraps HDG.ChipStrip (Modules/HDGR_ChipStrip.lua) so LayoutConfig can
-- declare a SequenceView-backed chip row the same way it declares a
-- scrollbox or cardGrid. Items push through dispatchChipStrip ->
-- HDG.ChipStrip:SetItems.
--
-- Spec shape:
--   kind = "chipStrip",
--   binding = "<selector returning flat items[]>",
--   options = {
--       cellKind  = "<registered cell kind>",  -- optional
--       horizontalSpacing = N, verticalSpacing = N,  -- optional
--       chipHeight = N,  -- optional
--   }
local function dispatchChipStrip(widget, values, dispatchCtx)
    if values.items == nil or not widget._chipStripCfg then return end
    if HDG.ChipStrip then  -- exception(false-positive): HDG.ChipStrip is TOC-guaranteed at runtime; headless test mock omits it
        HDG.ChipStrip:SetItems(widget, values.items, _shouldRetainScroll(dispatchCtx))
    end
end

HDG.WidgetTypes:Register("chipStrip", {
    build = function(parent, spec)
        if not (HDG.ChipStrip.Create) then
            error("chipStrip factory: HDG.ChipStrip module not loaded", 2)
        end
        local box, _bar = HDG.ChipStrip:Create(parent, {
            cellKind          = spec.cellKind,
            chipHeight        = spec.chipHeight,
            chipMinWidth      = spec.chipMinWidth,
            chipPadH          = spec.chipPadH,
            horizontalSpacing = spec.horizontalSpacing,
            verticalSpacing   = spec.verticalSpacing,
            orientation       = spec.orientation,
            chipConstructor   = spec.chipConstructor,
            chipBinder        = spec.chipBinder,
            chipSizer         = spec.chipSizer,
        })
        return box
    end,
    dispatch = { fields = { "items" }, push = dispatchChipStrip },
    skin = "Frame",
    specFields = { "cellKind", "chipHeight", "chipMinWidth", "chipPadH",
                   "horizontalSpacing", "verticalSpacing", "orientation",
                   "chipConstructor", "chipBinder", "chipSizer" },
})

-- ===== StatCard: big-number + dim-label stat tile ========================
-- Used in the library curator's COORDS / MAP / STATUS row at the top of
-- the right column. Two FontStrings stacked: big number/value on top
-- (heading font, text.primary), dim label below (small, text.dim).
-- SetValue(s) / SetLabel(s) for runtime updates.
function HDG.UI:StatCard(parent, value, label)
    if not (parent and CreateFrame) then return nil end
    local frame = CreateFrame("Frame", nil, parent)
    -- Raised tile (surface.raised) lifts the card off its panel (surface ramp rule 4).
    HDG.Theme:Register(frame, "Raised")
    if frame.CreateFontString then  -- exception(false-positive): Frame always has CreateFontString; mock-fidelity guard
        -- Value + label are anchored as one tight pair, vertically centred in the
        -- tile: value sits just above centre, label directly beneath it. Number stays
        -- on top; the old top/bottom-edge split left a big mid-card gap that made it
        -- ambiguous which label belonged to which number.
        local v = frame:CreateFontString(nil, "OVERLAY")
        if v.SetPoint then  -- exception(false-positive): FontString always has SetPoint; mock-fidelity guard
            v:SetPoint("BOTTOMLEFT",  frame, "LEFT", 8, 1)
            v:SetPoint("BOTTOMRIGHT", frame, "RIGHT", -8, 1)
        end
        v:SetJustifyH("LEFT")
        applyFontRole(v, "heading")
        v:SetText(tostring(value or ""))
        HDG.Theme:Register(v, "Text")
        frame._hdgrStatValue = v

        local l = frame:CreateFontString(nil, "OVERLAY")
        if l.SetPoint then  -- exception(false-positive): FontString always has SetPoint; mock-fidelity guard
            l:SetPoint("TOPLEFT",  v, "BOTTOMLEFT", 0, -2)
            l:SetPoint("TOPRIGHT", v, "BOTTOMRIGHT", 0, -2)
        end
        l:SetJustifyH("LEFT")
        applyFontRole(l, "caption")
        l:SetText(tostring(label or ""))
        HDG.Theme:Register(l, "TextDim")
        frame._hdgrStatLabel = l
    end
    function frame:SetValue(s)
        if self._hdgrStatValue and self._hdgrStatValue.SetText then
            self._hdgrStatValue:SetText(tostring(s or ""))
        end
    end
    function frame:SetLabel(s)
        if self._hdgrStatLabel and self._hdgrStatLabel.SetText then
            self._hdgrStatLabel:SetText(tostring(s or ""))
        end
    end
    return frame
end

HDG.WidgetTypes:Register("statCard", {
    build = function(parent, spec)
        return HDG.UI:StatCard(parent, spec.value, spec.label)
    end,
    dispatch = { fields = { "value", "label" }, push = dispatchStatCard },
    specFields = { "value", "label" },
})

-- (Swatch widget kind removed with the Decor dye-variant strip -- it was the
-- strip's only consumer.)

-- ===== RegisterInputDialog: shared single-line text-input StaticPopup =======
-- Stamps the boilerplate every text-input popup repeated by hand (ACCEPT /
-- CANCEL, no-timeout, exclusive, enter-to-accept, escape + auto-focus on show)
-- and normalizes Midnight's PascalCase `self.EditBox` (was `self.editBox`
-- pre-11.x) in one place. Callers supply only what differs.
--
-- spec:
--   text          -- prompt above the edit box
--   accept         -- accept button label (default ACCEPT)
--   maxLetters     -- edit-box char cap (default 256)
--   editBoxWidth   -- optional fixed width (Blizzard default if omitted)
--   initialText    -- pre-filled + selected on show (default "")
--   onAccept(value, data) -- value is the TRIMMED edit-box text; data is the
--                            StaticPopup_Show data arg. Do validation here.
--
-- Idempotent. Show via StaticPopup_Show(key, textArg, nil, data).
function HDG.UI:RegisterInputDialog(key, spec)
    if _G.StaticPopupDialogs[key] then return end
    local onAccept = spec.onAccept
    local function editBoxOf(self) return self.EditBox or self.editBox end
    _G.StaticPopupDialogs[key] = {
        text         = spec.text or "",
        button1      = spec.accept or _G.ACCEPT,
        button2      = _G.CANCEL,
        timeout      = 0,
        exclusive    = 1,
        whileDead    = 1,
        hideOnEscape = 1,
        hasEditBox   = true,
        maxLetters   = spec.maxLetters or 256,  -- exception(optional): spec field default (validator-guarded)
        editBoxWidth = spec.editBoxWidth,
        OnShow = function(self)
            local eb = editBoxOf(self)
            eb:SetText(spec.initialText or "")
            eb:HighlightText()
            eb:SetFocus()
        end,
        OnAccept = function(self, data)
            local value = (editBoxOf(self):GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if onAccept then onAccept(value, data) end
        end,
        EditBoxOnEnterPressed = function(self)
            _G.StaticPopup_OnClick(self:GetParent(), 1)
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
    }
end

-- ===== CopyDialog: shared multi-line "Ctrl+C to copy" popup =================
--
-- WoW's StaticPopup edit field is single-line, so any time we need the user
-- to copy multi-line text (waypoint lists, source paste, exports, etc) we
-- pop this dialog instead. Lazy-singleton: first call builds the frame and
-- caches it on HDG.UI; subsequent calls just populate + show.
--
-- Usage:
--     HDG.UI:CopyDialog():Show("Copy coordinates", text)

function HDG.UI:CopyDialog()
    if self._copyDialog then return self._copyDialog end
    if not (CreateFrame and UIParent) then return nil end

    local f = CreateFrame("Frame", "HDGR_CopyDialog", UIParent, "BackdropTemplate")
    f:SetSize(420, 280)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    HDG.Theme:Register(f, "Frame")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 12, -10)
    applyFontRole(title, "heading")
    HDG.Theme:Register(title, "Text")
    f._title = title

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    applyFontRole(hint, "small")
    hint:SetText("Ctrl+C to copy. Esc to close.")
    HDG.Theme:Register(hint, "TextDim")

    local sf = CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -50)
    sf:SetPoint("BOTTOMRIGHT", -12, 40)
    if sf.CharCount then sf.CharCount:Hide() end  -- exception(boundary): CharCount is an InputScrollFrameTemplate sub-widget; absent in some Blizzard template versions
    HDG.Theme:Register(sf, "EditBox")
    local edit = sf.EditBox
    if edit then
        edit:SetAutoFocus(false)
        edit:SetMultiLine(true)
        edit:SetMaxLetters(0)
        edit:SetJustifyH("LEFT")
        applyFontRole(edit, "body")
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
    end
    sf:HookScript("OnSizeChanged", function(self_, w)
        if self_.EditBox and self_.EditBox.SetWidth then
            self_.EditBox:SetWidth(math.max(1, (w or 0) - 24))
        end
    end)
    f._edit = edit

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(80, 22); close:SetPoint("BOTTOMRIGHT", -12, 10)
    close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    local rawShow = f.Show
    function f:Open(titleText, bodyText)
        if self._title and self._title.SetText then self._title:SetText(titleText or "Copy") end
        if self._edit then
            self._edit:SetText(bodyText or "")
            self._edit:HighlightText()
            self._edit:SetFocus()
        end
        rawShow(self)
    end

    self._copyDialog = f
    return f
end

-- ===== InputDialog: shared multi-line paste-in dialog =======================
--
-- Editable sibling of CopyDialog: same themed frame + multi-line
-- InputScrollFrameTemplate, but with Accept/Cancel buttons + an onAccept
-- callback. For pasting long text IN (shopping-list imports, etc.) where
-- Blizzard's single-line StaticPopup edit box can't show the multi-line blob --
-- so Export (CopyDialog) and Import (InputDialog) now share one look.
-- Lazy-singleton, like CopyDialog.
--
-- Usage:
--     HDG.UI:InputDialog():Open("Import list", {
--         hint = "Paste, then Import.", acceptText = "Import",
--         onAccept = function(text) ... end })

function HDG.UI:InputDialog()
    if self._inputDialog then return self._inputDialog end
    if not (CreateFrame and UIParent) then return nil end

    local f = CreateFrame("Frame", "HDGR_InputDialog", UIParent, "BackdropTemplate")
    f:SetSize(420, 280)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    HDG.Theme:Register(f, "Frame")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 12, -10)
    applyFontRole(title, "heading")
    HDG.Theme:Register(title, "Text")
    f._title = title

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    applyFontRole(hint, "small")
    HDG.Theme:Register(hint, "TextDim")
    f._hint = hint

    local sf = CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -50)
    sf:SetPoint("BOTTOMRIGHT", -12, 40)
    if sf.CharCount then sf.CharCount:Hide() end  -- exception(boundary): CharCount is an InputScrollFrameTemplate sub-widget; absent in some Blizzard template versions
    HDG.Theme:Register(sf, "EditBox")
    local edit = sf.EditBox
    if edit then
        edit:SetAutoFocus(false)
        edit:SetMultiLine(true)
        edit:SetMaxLetters(0)
        edit:SetJustifyH("LEFT")
        applyFontRole(edit, "body")
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
    end
    sf:HookScript("OnSizeChanged", function(self_, w)
        if self_.EditBox and self_.EditBox.SetWidth then
            self_.EditBox:SetWidth(math.max(1, (w or 0) - 24))
        end
    end)
    f._edit = edit

    local function commit()
        -- Capture the callback before Hide() (OnHide clears _onAccept).
        local text = ((f._edit and f._edit:GetText()) or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local cb = f._onAccept
        f:Hide()
        if cb and text ~= "" then cb(text) end
    end

    local accept = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    accept:SetSize(90, 22); accept:SetPoint("BOTTOMRIGHT", -12, 10)
    accept:SetText("Accept")
    accept:SetScript("OnClick", commit)
    f._acceptBtn = accept

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(80, 22); cancel:SetPoint("RIGHT", accept, "LEFT", -8, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() f:Hide() end)

    -- Drop the callback on hide so a stale closure can't fire on the next open.
    f:SetScript("OnHide", function(self_) self_._onAccept = nil end)

    local rawShow = f.Show
    -- opts = { hint, onAccept, acceptText, initialText }
    function f:Open(titleText, opts)
        opts = opts or {}
        self._title:SetText(titleText or "Paste")
        self._hint:SetText(opts.hint or "Paste, then Accept. Esc to cancel.")
        self._acceptBtn:SetText(opts.acceptText or "Accept")
        self._onAccept = opts.onAccept
        if self._edit then   -- exception(boundary): InputScrollFrameTemplate.EditBox
            self._edit:SetText(opts.initialText or "")
            self._edit:HighlightText()
            self._edit:SetFocus()
        end
        rawShow(self)
    end

    self._inputDialog = f
    return f
end

-- Convenience: open the shared InputDialog. One-liner for the "paste X, then
-- Import" handlers (shopping / crate / layout imports) -- centralizes the
-- pre-first-open boundary guard so each call site stays a single line.
function HDG.UI:PromptInput(titleText, opts)
    local dialog = self:InputDialog()
    if not (dialog and dialog.Open) then return end  -- exception(boundary): UI helper may be unbuilt pre-first-open
    dialog:Open(titleText, opts)
end

-- ===== UrlCopyPopup: shared slimline "Ctrl+C to copy" anchored URL field ====
--
-- Single-line sibling of CopyDialog. For contextual URL copies (wowhead links,
-- shopping-list source URLs, style sources) a heavy centered modal is overkill
-- -- we want a slimline field that pops directly under the clicked anchor with
-- the URL pre-selected for one keystroke. Lazy-singleton, like CopyDialog.
--
-- Usage:
--     HDG.UI:UrlCopyPopup():ShowAt(anchorFrame, url)

function HDG.UI:UrlCopyPopup()
    if self._urlCopyPopup then return self._urlCopyPopup end
    if not (CreateFrame and UIParent) then return nil end

    local f = CreateFrame("Frame", "HDGR_UrlCopyPopup", UIParent, "BackdropTemplate")
    f:SetSize(340, 28)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    HDG.Theme:Register(f, "Frame")

    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("TOPLEFT",     4, -4)
    eb:SetPoint("BOTTOMRIGHT", -4, 4)
    applyFontRole(eb, "small")
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus(); f:Hide() end)
    eb:SetScript("OnEnterPressed",  function(s) s:ClearFocus(); f:Hide() end)
    eb:SetScript("OnEditFocusLost", function() f:Hide() end)
    f._edit = eb

    -- Hidden measuring FontString (same font role as the EditBox) so ShowAt can
    -- fit the box to the URL's natural width via the render-independent
    -- GetUnboundedStringWidthForText (no SetWidth probe; Layout stays sole writer).
    local measure = f:CreateFontString(nil, "OVERLAY")
    applyFontRole(measure, "small")
    measure:Hide()
    f._measure = measure

    -- Box sizing: fit the URL, clamp to a sane band. Long URLs cap at MAX and
    -- the EditBox scrolls horizontally -- HighlightText still selects the full
    -- string, so Ctrl+C copies everything regardless of the visible width.
    local BOX_MIN, BOX_MAX, BOX_PAD = 160, 540, 24

    -- Pop under `anchor` with `url` pre-selected. No-op on empty url so callers
    -- can wire it unconditionally and let the selector gate visibility.
    function f:ShowAt(anchor, url)
        if not (anchor and url and url ~= "") then return end
        local w = _naturalTextWidth(self._measure, url)
        self:SetWidth(math.max(BOX_MIN, math.min(BOX_MAX, math.ceil(w) + BOX_PAD)))
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        self._edit:SetText(url)
        self:Show()
        self._edit:HighlightText()
        self._edit:SetFocus()
    end

    self._urlCopyPopup = f
    return f
end

-- ===== Row chrome / badge / map pin constructors ==========================
-- These build the textures + child frames for a scrollbox row (or map pin)
-- ONCE and cache them on the row. They DO NOT read theme colours -- that's
-- the Theme.Skinners.RowChrome / .RowBadge layer. Idempotent: re-calling on
-- an already-built row returns the cached struct.

-- Flat white texture for theme-tinted row chrome (zebra/selected/hover fills).
local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"

-- HDG.UI:RowFirstPaint(row, laidOutTag, layoutFn) -> bool
-- Idempotent first-paint helper for row factories. Wraps the standard
-- `if not row._<tag>LaidOut then ... row._<tag>LaidOut = true end` block that
-- every row factory's Configure() opens with. Returns true on the FIRST call
-- for this pooled row slot (when layoutFn was just executed), false on
-- subsequent calls.
--
-- Used by every HDG.Rows:Register factory. Replaces ~5 lines of boilerplate
-- per factory with one call that takes the per-factory tag string + a layout
-- callback. The callback creates child widgets + registers fonts once.
function HDG.UI:RowFirstPaint(row, laidOutTag, layoutFn)
    if not row or row[laidOutTag] then return false end
    if not row.CreateFontString then return false end
    self:EnsureRowChrome(row)
    layoutFn(row)
    -- NOTE: deliberately does NOT register a theme role for the row. Every
    -- factory declares its OWN row role in paint (RowChrome / RowWoodBeam /
    -- Button) -- there is no implicit default. The prior unconditional
    -- `Theme:Register(row, "Button")` painted a flat backdrop nobody asked for
    -- AND went stale on theme switch wherever a factory then overwrote the
    -- registry with RowChrome (ApplyAll re-runs only the last-registered role).
    row[laidOutTag] = true
    return true
end

function HDG.UI:EnsureRowChrome(row)
    if not row then return nil end
    if row._hdgrChrome then return row._hdgrChrome end
    if not row.CreateTexture then return nil end

    -- Zebra fill (BACKGROUND, bottom layer): EVEN data rows tint to
    -- surface.panel_soft, ODD rows stay hidden so the recessed list well shows
    -- through. Parity is stamped per-row by HDG.UI:ScrollBox's element
    -- initializer (row._zebraAlt) and painted by the RowChrome skinner --
    -- nav/card rows use their own factories, so they never get the stamp and
    -- stay flat.
    local zebra = row:CreateTexture(nil, "BACKGROUND", nil, 0)
    zebra:SetAllPoints()
    zebra:SetTexture(WHITE_TEX)
    zebra:Hide()

    -- Selected accent wash (BACKGROUND) + 3px left accent bar.
    -- Both hidden until the skinner sees state.selected.
    local selectedBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    selectedBg:SetAllPoints()
    selectedBg:SetTexture(WHITE_TEX)
    selectedBg:Hide()
    local accentBar = row:CreateTexture(nil, "OVERLAY")
    accentBar:SetPoint("TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(3)
    accentBar:SetTexture(WHITE_TEX)
    accentBar:Hide()

    -- Mouseover overlay -- tinted to surface.hover by the RowChrome skinner so
    -- it tracks the scheme (and re-tints on Theme:Reload).
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetTexture(WHITE_TEX)

    row._hdgrChrome = {
        zebra      = zebra,
        selectedBg = selectedBg,
        accentBar  = accentBar,
        hover      = hover,
    }
    return row._hdgrChrome
end

-- MapPin: pin frame for the drawer map. Pure construction -- positions, sizes,
-- and pin colours are driven by DrawerController at refresh time (via the
-- Theme tokens it reads). Lives in Components so controllers don't construct
-- frames -- they call this factory and decorate the returned frame.
function HDG.UI:MapPin(parent)
    if not (parent and _G.CreateFrame) then return nil end
    local pin = _G.CreateFrame("Frame", nil, parent)
    pin:EnableMouse(true)
    if pin.CreateTexture then  -- exception(false-positive): Frame always has CreateTexture; mock-fidelity guard
        local dot = pin:CreateTexture(nil, "OVERLAY")
        dot:SetPoint("CENTER")
        dot:SetAtlas("WhiteCircle-RaidBlips")
        pin._dot = dot
    end

    -- Index label centred on the dot. FRIZQT__ ascender/descender asymmetry
    -- shifts digits slightly low -- Y offset +1 compensates so "2" looks as
    -- centred as "1".
    if pin.CreateFontString then  -- exception(false-positive): Frame always has CreateFontString; mock-fidelity guard
        local label = pin:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", 0, 1)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        pin._label = label
    end

    return pin
end
