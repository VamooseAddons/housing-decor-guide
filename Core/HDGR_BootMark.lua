-- HDGR_BootMark: the Lua heap before HDG's first file runs. FIRST in the TOC on
-- purpose. Init.lua stamps the same reading at each boot step (files loaded,
-- saved variables, engines, main window frames, satellite windows), and the
-- Perf profile prints the deltas as "Boot memory" -- the answer to "why is HDG
-- N MB before the window has opened".
--
-- NO collector hold here. Init.lua holds it across OnInitialize and the window
-- builds in OnEnable, and only for a developer with the profiler on (a mid-span
-- collection once freed 45 MB of other addons' load garbage and read as
-- "engines: -45 MB"). This span cannot know that: saved variables, and so the
-- perf flag, load after every file has run. A hold here would pause collection
-- for every player across every addon's file load, and a boot that aborted
-- before Init released it would strand the whole client's collector for the
-- session. So the files step reads net heap movement, and a collection landing
-- inside it reads low.
HDG = HDG or {}
HDG._bootHeap = { files0 = collectgarbage("count") }
