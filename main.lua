--*> main.lua <*--
--*> gmod imgui implementation <*--
--*> made by eyoko1 <*--

local lje = lje or nil
if (not lje) then
    print("couldn't find lje, aborting execution of gmgui")
    return nil
end

lje.con_print("loading gmgui")

local m_util = lje.include("modules/ljeutil/main.lua").init("modules/ljeutil/")
local m_gmgui = lje.include("modules/gmgui.lua")

--lje.include("dbg_achievements.lua")
lje.include("dbg_chams.lua")

lje.con_print("loaded gmgui successfully!")