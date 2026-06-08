-- HDG.ChromeController
-- ============================================================================
-- Wires chrome-level controls: close button (X).
-- Tab/view navigation lives in NavController (sidebar nav).

HDG = HDG or {}
HDG.ChromeController = HDG.ChromeController or {}

local ChromeController = HDG.ChromeController

function ChromeController:Wire(rootFrame)
    -- Close [X]: dispatches MAIN_WINDOW_TOGGLE. Shopping + Zone satellites own their own close.
    HDG.UI.OnClick(rootFrame, "chromePanel.close", function()
        HDG.Store:Dispatch({ type = HDG.Constants.ACTIONS.MAIN_WINDOW_TOGGLE })
    end)
end

function ChromeController:Refresh(rootFrame, ctx)
    -- Tab active state flows through bindings (chrome.isTabActive_*).
    -- Nothing imperative.
end

HDG.Controllers:Register("chrome", ChromeController)
