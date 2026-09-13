-- HDGR_BootMark: the Lua heap before HDG's first file runs. FIRST in the TOC on
-- purpose. Init.lua stamps the same reading at each boot step (files loaded,
-- saved variables, engines, main window frames, satellite windows), and the
-- Perf profile prints the deltas as "Boot memory" -- the answer to "why is HDG
-- N MB before the window has opened".
--
-- The collector is HELD across each measured span (this file to OnInitialize,
-- OnInitialize itself, the window builds in OnEnable) so a delta is that span's
-- gross allocation and nothing else: a collection landing mid-span once freed
-- 45 MB of other addons' load garbage and read as "engines: -45 MB". Init.lua
-- restarts it at each span's end; the timer below is the backstop should boot
-- abort before it does.
HDG = HDG or {}
HDG._bootHeap = { files0 = collectgarbage("count") }
collectgarbage("stop")
C_Timer.After(15, function() collectgarbage("restart") end)
