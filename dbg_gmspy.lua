--*> gmspy.lua <*--
--*> process monitor for gmod <*--
--*> made by eyoko1 <*--

local NET_LIMIT = 50

local netmessages = {}
local activenetmessage = nil

_G.net.Start = lje.detour(_G.net.Start, function(message, unreliable)
    activenetmessage = message

    return net.Start(message, unreliable)
end)

_G.net.SendToServer = lje.detour(_G.net.SendToServer, function()
    if (activenetmessage) then
        table.insert(netmessages, 1, activenetmessage)
        if (#netmessages > NET_LIMIT) then
            netmessages[NET_LIMIT] = nil
        end
    end
    activenetmessage = nil

    return net.SendToServer()
end)

hook.pre("PostRender", "__gmgui_test", function()
    gmgui.startwindow("GmSpy", 500, 900, 500, 300, 100)
        gmgui.beginscrollingarea("Net", 0, 0, 0, 0, gmgui.flags.scrollablearea.invert)
            local messagecount = #netmessages
            if (messagecount ~= 0) then
                local i = 1
                ::net_draw::
                gmgui.button(netmessages[i])
                if (i ~= messagecount) then
                    i = i + 1
                    goto net_draw
                end
            end
        gmgui.endscrollingarea()
    gmgui.endwindow()
end)