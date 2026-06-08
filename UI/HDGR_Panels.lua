-- HDG.Panels
--
-- Registers the "panel" widget kind. A panel is a chrome container --
-- a Frame whose internal regions (header / body / footer) are declared
-- via slots in LayoutConfig.panels[panelId].slots.
--
-- The panel factory only creates the outer Frame (with theme backdrop). All
-- header content -- title, subtitle, icons, chips, action buttons -- lives
-- in LayoutConfig.widgets with `slot = "header"` and is built/positioned by
-- the layout engine like any other widget.

HDG = HDG or {}
HDG.Panels = HDG.Panels or {}

local function PanelFactory(parent, spec)
    if not CreateFrame then return nil end
    return CreateFrame("Frame", spec.frameName, parent, "BackdropTemplate")
    -- Theme:Register is owned by Layout's buildKind helper (spec section 5);
    -- the kind's `skin = "Frame"` declaration drives paint role assignment.
end

-- `panel` is consumed at LayoutConfig.panels (not config.widgets); the
-- closed-schema for panel specs lives in HDGR_Layout.lua's PANEL_SPEC_FIELDS
-- (kind/cell/slots/slotsRows/etc.). specFields here is a no-op since the
-- validator routes panel specs through PANEL_SPEC_FIELDS instead.
HDG.WidgetTypes:Register("panel", {
    build = PanelFactory,
    skin = "Frame",
    specFields = { "frameName" },      -- builder reads spec.frameName
})
