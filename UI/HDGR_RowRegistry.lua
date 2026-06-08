-- HDG.Rows
--
-- Unified row registry for scrollbox-style lists. ONE place to define a row:
-- font + height + key + a factory (built via HDG.UI.MakeRowFactory for simple
-- rows, or hand-written for heterogeneous kind-dispatch rows).
--
-- Each row definition:
--   font   = "body" | "subheading" | ...      (Theme font role; REQUIRED)
--   height = number                            (row pixel height; REQUIRED)
--   spacing = number                           (override scrollbox row spacing;
--                                               optional, defaults to spec.spacing)
--   key    = function(spec, ctx) -> string    (stable per-row identity;
--                                               REQUIRED per spec section 10;
--                                               `spec` is the row's elementData,
--                                               `ctx` is the parent scrollbox
--                                               context table -- nil for now)
--
-- Plus:
--   factory(template) -> { Configure(row, ed), Reset(row) }   (REQUIRED)
--                                              built via HDG.UI.MakeRowFactory
--                                              for simple single-layout rows, or
--                                              hand-written for heterogeneous
--                                              kind-dispatch rows (icons, badges,
--                                              header-OR-card, multi-shape).
--
-- Selection state is conveyed via HDG.UI.PaintRowChrome (accent border + fill);
-- factories don't decorate the row text with prefixes.
--
-- Identity rule (spec section 10): every loop-rendered row MUST declare a
-- key function. WowScrollBoxList tracks elementData by reference today, but
-- the explicit key is the contract surface for future migrations (diffing,
-- animation, focus preservation across re-layouts).

HDG = HDG or {}
HDG.Rows = HDG.Rows or { byName = {} }

local R = HDG.Rows

function R:Register(name, def)
    if type(name) ~= "string" or name == "" then
        error("HDG.Rows: name must be a non-empty string", 2)
    end
    if type(def) ~= "table" then
        error(("HDG.Rows: %q definition must be a table"):format(name), 2)
    end
    if type(def.font) ~= "string" or def.font == "" then
        error(("HDG.Rows: %q.font is required (Theme font role)"):format(name), 2)
    end
    -- height: number for fixed-extent rows, or function(elementData) -> number
    -- for heterogeneous rows (e.g., expandable vendor rows mixed with item
    -- sub-rows at different heights). The scrollbox routes a function-height
    -- through SetElementExtentCalculator instead of SetElementExtent.
    if type(def.height) ~= "number" and type(def.height) ~= "function" then
        error(("HDG.Rows: %q.height must be a number or function(elementData)"):format(name), 2)
    end

    if type(def.factory) ~= "function" then
        error(("HDG.Rows: %q.factory is required (function(template) -> { Configure, Reset })"):format(name), 2)
    end
    -- Spec section 10: every loop-rendered row declares a stable key
    -- function. Validator errors loudly so the omission isn't silent.
    if type(def.key) ~= "function" then
        error(("HDG.Rows: %q.key is required (function(elementData) -> string;"
            .. " spec section 10 -- stable per-row identity)"):format(name), 2)
    end

    self.byName[name] = def
    return true
end

function R:Get(name)
    if type(name) ~= "string" or name == "" then return nil end
    return self.byName[name]
end
