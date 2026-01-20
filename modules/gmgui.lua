--*> gmgui.lua <*--
--*> main gmgui file <*--
--*> made by eyoko1 <*--

--> TODO:
    --> ability to collapse window (+ disabling rendering for them)
    --> gmgui.combo({string, ...})

--> this code is a little messy, and might be hard to read which is mainly due to the optimisations i made so sorry about that

--> this uses my ljeutil library so make sure that has been included before this is ran

--> arguments prefixed with op_ are optional

--> elements are drawn by putting them into a buffer where they are represented by a fast rendering function, and a pre-allocated table
--> this buffer is not 'cleared' per frame, but instead the length which is used for reading from it is reset back to 0 - this saves tons of time and memory

local SCROLL_SENSITIVITY = 12

local surface_DrawText = surface.DrawText
local surface_SetDrawColor = surface.SetDrawColor
local surface_SetTextPos = surface.SetTextPos
local surface_SetFont = surface.SetFont
local surface_GetTextSize = surface.GetTextSize
local surface_DrawOutlinedRect = surface.DrawOutlinedRect
local surface_SetTextColor = surface.SetTextColor
local surface_DrawRect = surface.DrawRect
local surface_CreateFont = surface.CreateFont
local surface_DrawLine = surface.DrawLine
local surface_SetTexture = surface.SetTexture
local surface_DrawTexturedRectRotated = surface.DrawTexturedRectRotated

local render_SetScissorRect = render.SetScissorRect

local input_IsMouseDown = input.IsMouseDown
local input_WasMousePressed = input.WasMousePressed
local input_WasMouseDoublePressed = input.WasMouseDoublePressed

local table_sort = table.sort

local gui_MouseX = gui.MouseX
local gui_MouseY = gui.MouseY

local math_min = math.min
local math_max = math.max

local render_PushRenderTarget = render.PushRenderTarget
local render_PopRenderTarget = render.PopRenderTarget

local bit_lshift = bit.lshift
local bit_bor = bit.bor
local bit_band = bit.band

local MOUSE_LEFT = MOUSE_LEFT
local MOUSE_RIGHT = MOUSE_RIGHT
local MOUSE_MIDDLE = MOUSE_MIDDLE

local blanktexture = surface.GetTextureID("vgui/white")

local environment = lje.env.get()

local function __log(info, ...)
    lje.con_print(string.format(info, ...))
end

local fonts = {}
local fontdata = {}
local function __font(name, data) --> creates a font with the given name, then returns the generated name. if the font already exists, it returns the cached name
    local cached = fonts[name]
    if (cached) then
        return cached
    end

    local id = lje.util.random_string()
    surface_CreateFont(id, data)
    fonts[name] = id
    fontdata[id] = data

    return id
end

local function __color(r, g, b, a) --> fast implementation of Color
    return {r, g, b, a}
end

local gmgui = {
    style = {
        fonts = {
            text = __font("Text", {
                font = "DinaRemasterII",
                size = 16,
                antialias = false
            }),
            small = __font("Small", {
                font = "DinaRemasterII",
                size = 14,
                antialias = false
            })
        },
        general = {
            text = __color(255, 255, 255, 255),
            textdisabled = __color(128, 128, 128, 255),
            border = __color(110, 110, 128, 128),
            inset = 6,
            gap = 6
        },
        window = {
            title = __color(41, 74, 122, 255),
            background = __color(38, 38, 38, 240),
            titleheight = 24
        },
        frame = {
            background = __color(41, 74, 122, 138),
            hovered = __color(66, 150, 250, 102),
            enabled = __color(66, 150, 255, 200), --> used for checkboxes
            disabled = __color(16, 50, 105, 102) --> used for buttons
        },
        child = {
            background = __color(28, 28, 28, 200),
            border = __color(110, 110, 128, 128)
        }
    },
    flags = {
        window = {
            minimized = bit_lshift(1, 0)
        },
        scrollablearea = {
            invert = bit_lshift(1, 0)
        }
    },
    drawlist = {
        buffer = {}, --> array of window draw buffers
        length = 0, --> the number of windows in use
        target = 0, --> the index of the window currently being operated on
        size = 0 --> size of the array
    },
    states = {} -- key: window name, value => see createstate()
}
environment.gmgui = gmgui

--> references to the drawlist / buffer so we don't need to index gmgui every time we need these commonly used things
local drawlist = gmgui.drawlist
local buffer = drawlist.buffer
local flags = gmgui.flags

--> internal flag used during stuff like minimizing windows - note that this does not register gui elements at all, and doesn't just ignore them during the drawing phase
local __DISABLE_RENDERING = false

--> internal variables - be careful when editing these as you could accidentally break rendering
local __lastoffsetx = 0
local __lastoffsety = 0
local __drawsectionx = 0
local __drawsectiony = 0
local __style = gmgui.style
local __windowhovered = false
local __windowwidth = 0
local __windowheight = 0
local __lastwidth = 0
local __scissorx = 0
local __scissory = 0
local __scissorw = 0
local __scissorh = 0
local __invertscroll = false
local __scrollfirst = false --> if false, the first element for an inverted scroll hasnt been added yet
local __firstoffset = 0
local __scroll = 0
local __lastscroll = 0

local __addarg1 = nil
local __addarg2 = nil
local __addarg3 = nil
local __addarg4 = nil

local __orderedwindows = {}
local __windoworder = {}
local __zindexorder = {}
local __sameorder = true
local __lastlength = 0
for i = 1, 8 do
    __windoworder[i] = ""
    __zindexorder[i] = 0
end

local __offsetx = 0
local __offsety = 0
local __cursorstacksize = 0
local __cursorstacklength = 0
local __cursorstack = {}
local __activecursor = nil
for i = 1, 8 do
    __cursorstack[i] = {nil, 0, 0} --> element 1 is the parent state / frame, elements 2 and 3 are the offsetx and offsety respectively
    __cursorstacksize = i
end

local addtowindow = nil --> function - defined later

local function pushcursor(state, drawx, drawy)
    local inset = __style.general.inset

    local target = __cursorstacklength + 1
    if (__cursorstacklength == __cursorstacksize) then
        local allocated = {state, inset, inset, drawx, drawy}
        __cursorstack[target] = allocated
        __cursorstacksize = target
        __activecursor = allocated

        __log("Allocated cursor buffer for: '%s'", state.name)
    else
        local targetelement = __cursorstack[target]
        targetelement[1] = state
        targetelement[2] = inset
        targetelement[3] = inset
        targetelement[4] = drawx
        targetelement[5] = drawy
        __activecursor = targetelement
    end
    __cursorstacklength = target

    __offsetx = inset
    __offsety = inset
    __drawsectionx = drawx
    __drawsectiony = drawy
end

local function getcursor()
    return __activecursor
end

local function popcursor()
    __cursorstacklength = __cursorstacklength - 1
    __activecursor = __cursorstack[__cursorstacklength]
    if (__activecursor) then
        __offsetx = __activecursor[2]
        __offsety = __activecursor[3]
        __drawsectionx = __activecursor[4]
        __drawsectiony = __activecursor[5]
    end
end

local function changeoffsetx(change)
    __lastoffsetx = __activecursor[2]
    local new = __lastoffsetx + change
    __activecursor[2] = new
    __offsetx = new
end

local function resetoffsetx()
    local offset = __style.general.inset
    __lastoffsetx = offset
    __activecursor[2] = offset
    __offsetx = offset
end

local function changeoffsety(change)
    __lastoffsety = __activecursor[3]
    local new = 0
    if (__invertscroll) then
        new = __lastoffsety - change

        if (not __scrollfirst and __addarg1) then
            __scrollfirst = true
            __firstoffset = change
            addtowindow(__addarg1, __addarg2, __addarg3, __addarg4)
            __addarg1 = nil

            --new = new - change
        end
    else
        new = __lastoffsety + change
    end
    __activecursor[3] = new
    __offsety = new
end

local function resetoffsety()
    local offset = __style.general.inset
    __lastoffsety = offset
    __activecursor[3] = offset
    __offsety = offset
end

local function registerlastwidth(width)
    __lastwidth = width

    local offset = __style.general.inset
    __lastoffsetx = __offsetx
    __activecursor[2] = offset
    __offsetx = offset
end

local function setcolor(color) --> this is used instead for surface_SetDrawColor when using gmgui colors
    return surface_SetDrawColor(color[1], color[2], color[3], color[4])
end

local function settextcolor(color) --> this is used instead for surface_SetTextColor when using gmgui colors
    return surface_SetTextColor(color[1], color[2], color[3], color[4])
end

local function allocateelement() --> one ui element
    return {false, {false, false}, 0, 0} --> function, data, offsetx, offsety
end

local function allocatewindow(elements) --> a whole window
    --> false is used because it is a small data type
    local window = {{1, 0}, {false, {false, false, false}, 0, 0}} --> first element is the length and the z-index, second element is the z-index and the third element is always the call to __drawwindow
    for i = 3, elements + 2 do --> allocates elements inside the of window
        window[i] = allocateelement()
    end

    return window
end

local __queuedcycle = false
local __cyclewindows = 2
local __cycleallocations = 6
local function __cyclememory() --> if __cyclewindows is less than 1, indexing the buffer will fail so don't set it that low
    drawlist.buffer = {}
    buffer = drawlist.buffer
    __orderedwindows = {}
    __windoworder = {}
    __zindexorder = {}
    __lastlength = 0
    --> pre-allocate space in the drawbuffer
    for i = 1, __cyclewindows do --> allocates initial windows
        local window = allocatewindow(__cycleallocations)
        buffer[i] = window
        __orderedwindows[i] = window
    end

    drawlist.size = __cyclewindows

    __queuedcycle = false
    __log("Performed a memory cycle")
end

local function __queuecycle(windows, allocations) --> performs a sort of garbage collection, where the old buffer is wiped and a new one is created
    __queuedcycle = true
    __cyclewindows = windows
    __cycleallocations = allocations
    __log("Queued a memory cycle")
end

__cyclememory()

local function getlastwindow()
    return buffer[drawlist.target]
end

local abuf = {false, false, false, false, false, false, false, false} --> add buffer - this is cloned into window data
function addtowindow(func, argcount, drawx, drawy, __bypassfirst)
    if (not __bypassfirst and (__invertscroll and not __scrollfirst)) then
        __addarg1 = func
        __addarg2 = argcount
        __addarg3 = drawx
        __addarg4 = drawy
        return
    end
    
    local window = getlastwindow()
    local windowdata = window[1]
    local length = windowdata[1] + 1
    windowdata[1] = length
    
    local element = window[length]
    if (not element) then
        element = allocateelement()
        window[length] = element
        --__log("Window lacked space, so an element was allocated! Length: %i", length)
    end

    element[1] = func
    
    local data = element[2]
    if (argcount ~= 0) then
        local i = 1
        ::fast_add::
        data[i] = abuf[i]
        if (i ~= argcount) then
            i = i + 1
            goto fast_add
        end
    end

    element[3] = drawx
    element[4] = drawy
end

local __clicked = false
local function didclick()
    return __clicked
end

local function mousedown()
    return input_IsMouseDown(MOUSE_LEFT)
end

local function getmousepos()
    return gui_MouseX(), gui_MouseY()
end

local function ishovered(x, y, width, height, __rawhover)
    if (not __rawhover and not __windowhovered) then
        return false
    end

    local mx, my = getmousepos()
    return (mx >= x and mx <= x + width) and (my >= y and my <= y + height)
end

local function createstate(name, x, y, width, height)
    local state = {
        name = name,
        x = x,
        y = y,
        width = width,
        height = height,

        framehovered = false,

        dragoffsetx = 0,
        dragoffsety = 0,
        dragging = false,

        inner = {} --> inner states
    }

    __log("Created state for: '%s'", name)

    gmgui.states[name] = state
    return state
end

local __statestack = {} --> pre-allocation doesn't matter for something this small - it is just an array of pointers to states
local __statestacklength = 0
local function pushstate(state)
    __statestacklength = __statestacklength + 1
    __statestack[__statestacklength] = state
end

local function getstate()
    return __statestack[__statestacklength]
end

local function popstate()
    __statestacklength = __statestacklength - 1
end

--[[
data structure:
[1]-> name
[2]-> x
[3]-> y
[4]-> width
[5]-> height
]]--
local function __drawwindow(data, style)
    local x = data[2]
    local y = data[3]
    local width = data[4]
    local height = data[5]

    local stylewindow = __style.window
    local stylegeneral = __style.general
    local styleheight = stylewindow.titleheight

    setcolor(stylewindow.background)
    surface_DrawRect(x, y, width, height)

    setcolor(stylewindow.title)
    surface_DrawRect(x, y - styleheight, width, styleheight)

    setcolor(stylegeneral.border)
    surface_DrawOutlinedRect(x, y - styleheight, width, height + styleheight, 1)

    surface_SetFont(__style.fonts.text)
    settextcolor(stylegeneral.text)
    surface_SetTextPos(x + stylegeneral.inset, y - ((stylewindow.titleheight * 0.5) + (fontdata[__style.fonts.text].size * 0.5)))
    surface_DrawText(data[1])
end

function gmgui.startwindow(name, x, y, width, height, op_zindex)
    local target = drawlist.target
    local newtarget = target + 1
    local length = drawlist.length
    local size = drawlist.size
    if (target == size) then
        local allocated = allocatewindow(6)
        buffer[newtarget] = allocated
        __orderedwindows[newtarget] = allocated
        drawlist.size = size + 1
        __log("Allocated window buffer for: '%s'", name)
    end

    local state = gmgui.states[name]
    if (not state) then
        state = createstate(name, x, y, width, height)
        __orderedwindows[newtarget] = buffer[newtarget]
    end
    pushstate(state)

    op_zindex = op_zindex or 0

    if (--[[__windoworder[newtarget] ~= name or ]]__zindexorder[newtarget] ~= op_zindex) then
        __windoworder[newtarget] = name
        __zindexorder[newtarget] = op_zindex
        __sameorder = false
    end

    local styleheight = __style.window.titleheight
    __windowhovered = ishovered(state.x, state.y - styleheight, width, height + styleheight, true)
    __style = gmgui.style
    __windowwidth = width
    __windowheight = height
    --__drawsectionx = state.x
    --__drawsectiony = state.y

    drawlist.target = newtarget
    drawlist.length = length + 1

    --local a = buffer[newtarget][1]
    --local b = buffer[newtarget][1][2]
    --__log("%s", newtarget)
    local windowdata = buffer[newtarget][1]
    windowdata[2] = op_zindex

    state.framehovered = false

    pushcursor(state, state.x, state.y)

    abuf[1] = name
    abuf[2] = state.x
    abuf[3] = state.y
    abuf[4] = state.width
    abuf[5] = state.height
    addtowindow(__drawwindow, 5)
end

function gmgui.endwindow()
    local state = getstate()

    local dragging = state.dragging
    if (not dragging and didclick() and not state.framehovered and __windowhovered) then
        local mx, my = getmousepos()
        state.dragoffsetx = mx - state.x
        state.dragoffsety = my - state.y
        state.dragging = true
    end

    if (dragging) then
        if (mousedown()) then
            local mx, my = getmousepos()
            state.x = math.max(math.min(mx - state.dragoffsetx, ScrW()), 0)
            state.y = math.max(math.min(my - state.dragoffsety, ScrH()), 0)
        else
            state.dragging = false
        end
    end

    popcursor(state)
    popstate()
end

--[[
data structure:
[1]-> text
]]--
local function __drawtext(data, x, y)
    surface_SetFont(__style.fonts.text)
    settextcolor(__style.general.text)
    surface_SetTextPos(x, y)
    surface_DrawText(data[1])
end

function gmgui.text(text)
    if (__DISABLE_RENDERING) then return end

    local font = __style.fonts.text

    abuf[1] = text
    addtowindow(__drawtext, 1, __drawsectionx + __offsetx, __drawsectiony + __offsety)

    changeoffsety(fontdata[font].size + __style.general.gap)

    surface_SetFont(font)
    registerlastwidth(surface_GetTextSize(text))
end

--[[
data structure:
[1]-> text
]]--
local function __drawtextdisabled(data, x, y)
    surface_SetFont(__style.fonts.text)
    settextcolor(__style.general.textdisabled)
    surface_SetTextPos(x, y)
    surface_DrawText(data[1])
end

function gmgui.textdisabled(text)
    if (__DISABLE_RENDERING) then return end

    local font = __style.fonts.text

    abuf[1] = text
    addtowindow(__drawtextdisabled, 1, __drawsectionx + __offsetx, __drawsectiony + __offsety)

    changeoffsety(fontdata[font].size + __style.general.gap)

    surface_SetFont(font)
    registerlastwidth(surface_GetTextSize(text))
end

--[[
data structure:
[1]-> text
[2]-> width
[3]-> hovered (reference to style)
]]--
local function __drawbutton_autosize(data, x, y)
    local width = data[2]
    local height = fontdata[__style.fonts.text].size + 4

    local packed = data[3]
    if (packed) then
        setcolor(__style.frame.hovered)
        settextcolor(__style.general.text)
    elseif (packed == false) then
        setcolor(__style.frame.background)
        settextcolor(__style.general.text)
    else
        setcolor(__style.frame.disabled)
        settextcolor(__style.general.textdisabled)
    end

    surface_DrawRect(x, y, width, height)

    surface_SetTextPos(x + 10, y + 2)
    surface_SetFont(__style.fonts.text)
    surface_DrawText(data[1])
end

local function __drawbutton_noautosize(data, x, y)
    local width = data[2]
    local height = fontdata[__style.fonts.text].size + 4

    local packed = data[3]
    if (packed) then
        setcolor(__style.frame.hovered)
        settextcolor(__style.general.text)
    elseif (packed == false) then
        setcolor(__style.frame.background)
        settextcolor(__style.general.text)
    else
        setcolor(__style.frame.disabled)
        settextcolor(__style.general.textdisabled)
    end

    local text = data[1]

    surface_DrawRect(x, y, width, height)

    surface_SetFont(__style.fonts.text)
    surface_SetTextPos(x + (width * 0.5) - (surface_GetTextSize(text) * 0.5), y + 2)
    surface_DrawText(text)
end

function gmgui.button(text, op_disabled, op_width)
    if (__DISABLE_RENDERING) then return end

    local font = __style.fonts.text
    surface_SetFont(font)
    local width = op_width or surface_GetTextSize(text) + 20
    local height = fontdata[font].size + 4
    local x = __drawsectionx + __offsetx
    local y = __drawsectiony + __offsety
    local hovered = false
    if (op_disabled) then
        abuf[3] = nil
    else
        hovered = ishovered(x, y, width, height)
        if (hovered) then
            getstate().framehovered = true
        end

        abuf[3] = hovered
    end

    abuf[1] = text
    abuf[2] = width
    --abuf[3] = hovered
    if (op_width) then
        addtowindow(__drawbutton_noautosize, 3, x, y)
    else
        addtowindow(__drawbutton_autosize, 3, x, y)
    end

    changeoffsety(height + __style.general.gap)

    registerlastwidth(width)

    return not op_disabled and (didclick() and hovered)
end

local function __drawcheckmark(x, y)
    surface_SetTexture(blanktexture)
    surface_DrawTexturedRectRotated(x + 8, y + 16, 8, 3, -45)
    surface_DrawTexturedRectRotated(x + 15, y + 12, 12, 3, 45)
end

--[[
data structure:
[1]-> text
[2]-> hovered / checked ("b" = clicked + hovered, "c" = clicked, "h" = hovered, "n" = none)
]]--
local function __drawcheckbox(data, x, y)
    local font = __style.fonts.text

    local packed = data[2]
    if (packed == "ch") then
        setcolor(__style.frame.hovered)
        surface_DrawRect(x, y, 25, 25)

        setcolor(__style.frame.enabled)
        __drawcheckmark(x, y)
    elseif (packed == "c") then
        setcolor(__style.frame.background)
        surface_DrawRect(x, y, 25, 25)

        setcolor(__style.frame.enabled)
        __drawcheckmark(x, y)
    elseif (packed == "h") then
        setcolor(__style.frame.hovered)
        surface_DrawRect(x, y, 25, 25)
    else
        setcolor(__style.frame.background)
        surface_DrawRect(x, y, 25, 25)
    end

    settextcolor(__style.general.text)
    surface_SetFont(font)
    surface_SetTextPos(x + 25 + __style.general.gap, y + 12.5 - fontdata[font].size * 0.5)
    surface_DrawText(data[1])
end

function gmgui.checkbox(text, op_state)
    if (__DISABLE_RENDERING) then return end

    local state = getstate()

    local inner = state.inner

    local x = __drawsectionx + __offsetx
    local y = __drawsectiony + __offsety
    local hovered = ishovered(x, y, 25, 25)
    local checked = inner[text]
    if (checked == nil) then
        checked = op_state
    end

    if (hovered) then
        state.framehovered = true
        if (didclick()) then
            checked = not checked
            inner[text] = checked
        end
    end

    local packed = hovered and false or checked and true
    if (not packed and not hovered) then
        packed = nil
    end

    if (hovered) then
        if (checked) then
            packed = "ch"
        else
            packed = "h"
        end
    elseif (checked) then
        packed = "c"
    else
        packed = "n"
    end

    abuf[1] = text
    abuf[2] = packed
    addtowindow(__drawcheckbox, 2, x, y)

    changeoffsety(25 + __style.general.gap)

    surface_SetFont(__style.fonts.text)
    registerlastwidth(25 + surface_GetTextSize(text))

    return checked
end

function gmgui.sameline()
    if (__DISABLE_RENDERING) then return end

    changeoffsetx(__lastwidth + __lastoffsetx)
    changeoffsety(__lastoffsety - __offsety)
end

--[[
data structure:
[1]-> name
[2]-> width
[3]-> height
]]--
local function __drawchild(data, x, y)
    local text = data[1]
    local width = data[2]
    local height = data[3]

    setcolor(__style.child.background)
    surface_DrawRect(x, y, width, height)

    setcolor(__style.child.border)
    if (text == "") then
        surface_DrawOutlinedRect(x, y, width, height)
    else
        local font = __style.fonts.small
        surface_DrawLine(x, y, x, y + height) --> tl -> bl
        surface_DrawLine(x + width - 1, y, x + width - 1, y + height - 1) --> tr -> br
        surface_DrawLine(x + 1, y + height - 1, x + width, y + height - 1) --> bl -> br
        surface_DrawLine(x + 1, y, x + 20, y) --> tl -> text
        surface_SetFont(font)
        settextcolor(__style.general.text)
        surface_SetTextPos(x + 28, y - (fontdata[font].size * 0.5))
        surface_DrawText(text)
        local textwidth = surface_GetTextSize(text)
        surface_DrawLine(x + 36 + textwidth, y, x + width - 1, y) --> text -> tr
    end
end

function gmgui.beginchild(name, x, y, width, height) --> returns the x, y, width, height
    if (__DISABLE_RENDERING) then return end

    if (x <= 0) then
        x = __style.general.inset
    end

    if (y <= 0) then
        y = __offsety + __style.general.inset
    end

    if (width <= 0) then
        width = __windowwidth - x - __style.general.inset
    end

    if (height <= 0) then
        height = __windowheight - y - __style.general.inset
    end

    local state = gmgui.states[name] or createstate(name, x, y, width, height)
    pushstate(state)

    local drawx = __drawsectionx + x
    local drawy = __drawsectiony + y

    abuf[1] = name
    abuf[2] = width
    abuf[3] = height
    addtowindow(__drawchild, 3, drawx, drawy)

    changeoffsety(height + __style.general.gap)

    pushcursor(state, drawx, drawy)
    changeoffsety(__style.general.gap)

    registerlastwidth(width)

    return x, y, width, height
end

function gmgui.endchild()
    if (__DISABLE_RENDERING) then return end

    popcursor()

    changeoffsety(__style.general.gap)
    popstate()
end

local function __drawbeginscrollingarea(data, x, y)
    render_SetScissorRect(x, y + __style.general.gap, x + data[1], y + data[2], true)
end

function gmgui.beginscrollingarea(name, x, y, width, height, op_flags)
    if (__DISABLE_RENDERING) then return end

    local __x, __y, __w, __h = gmgui.beginchild(name, x, y, width, height)
    
    local state = gmgui.states[name]
    if (not state.scrollx) then
        state.scrollx = 0
        state.scrolly = 0
        state.drawx = 0
        state.drawy = 0
        state.firstoffset = 0
    end

    __invertscroll = bit_band(op_flags or 0, flags.scrollablearea.invert) ~= 0

    if (__invertscroll) then
        __scrollfirst = false
        changeoffsety(-state.scrolly - __h + __style.general.gap * 2 + state.firstoffset)
    else
        changeoffsety(state.scrolly)
    end

    abuf[1] = __w
    abuf[2] = __h
    addtowindow(__drawbeginscrollingarea, 2, __drawsectionx, __drawsectiony, true)

    state.drawx = __x
    state.drawy = __y
    return __x, __y, __w, __h
end

local function __drawendscrollingarea()
    render_SetScissorRect(__scissorx, __scissory, __scissorw, __scissorh, true)
end

function gmgui.endscrollingarea()
    if (__DISABLE_RENDERING) then return end

    local state = getstate()

    if (ishovered(__drawsectionx, __drawsectiony, state.width, state.height)) then
        if (__scroll < 0) then
            if (__invertscroll) then
                state.scrolly = math_max(0, state.scrolly + __scroll)
            else
                local min = -(__offsety - state.scrolly - state.height)
                state.scrolly = math_max(min, state.scrolly + __scroll)
            end
        elseif (__scroll > 0) then
            if (__invertscroll) then
                local min = -(__offsety - state.scrolly + __style.general.gap * 2)
                state.scrolly = math_min(min, state.scrolly + __scroll)
            else
                state.scrolly = math_min(0, state.scrolly + __scroll)
            end
        end
    end

    state.firstoffset = __firstoffset

    __invertscroll = false

    gmgui.endchild()

    addtowindow(__drawendscrollingarea, 0, 0, 0, true)
end

function gmgui.tabs(tabs, op_autosize)
    local length = #tabs
    if (length == 0) then
        return
    end

    local state = getstate()
    local inner = state.inner
    local widtheach = op_autosize and ((state.width - (__style.general.gap * (length + 1))) / length) or 0

    if (length == 1) then
        local text = tabs[1]
        return gmgui.button(text, false, op_autosize and widtheach or nil) and text
    end

    local currenttab = inner[tabs] or -1
    local selected = nil
    local i = 1
    ::do_tabs::
    local text = tabs[i]
    if (gmgui.button(text, false, op_autosize and widtheach or nil)) then
        selected = text
    end
    if (i ~= length) then
        gmgui.sameline()
        i = i + 1
        goto do_tabs
    end

    inner[tabs] = selected

    return selected
end

--> sorts elements based on their z-index
local function windowsorter(a, b)
    return a[1][2] < b[1][2]
end

--> responsible for rendering the draw buffer elements to the screen - this has been heavily optimised so its a little hard to read
hook.pre("ljeutil/render", "__gmgui_render", function()
    local wlength = drawlist.length
    if (wlength == 0) then
        return
    end

    --> if the windows have shifted around in any way (different z-index, different number) then we need to re-sort the ordered array of windows
    local differentlength = wlength ~= __lastlength
    if (not __sameorder or differentlength) then
        if (differentlength) then
            local olength = #__orderedwindows
            local oi = 1
            ::clear_order::
            __orderedwindows[oi] = nil
            if (oi ~= olength) then
                oi = oi + 1
                goto clear_order
            end

            oi = 1
            ::repopulate_order::
            __orderedwindows[oi] = buffer[oi]
            if (oi ~= wlength) then
                oi = oi + 1
                goto repopulate_order
            end
        end

        table_sort(__orderedwindows, windowsorter)
        __sameorder = true
    end

    render_PushRenderTarget(lje.util.rendertarget)

    --> loop through all windows
    local wi = 1
    ::draw_windows::
    local window = __orderedwindows[wi]
    local windowdata = window[1]
    local startwindowdata = window[2][2]
    __drawsectionx = startwindowdata[2]
    __drawsectiony = startwindowdata[3]

    __scissorx = __drawsectionx
    __scissory = __drawsectiony - __style.window.titleheight
    __scissorw = __drawsectionx + startwindowdata[4]
    __scissorh = __drawsectiony + startwindowdata[5]
    render_SetScissorRect(__scissorx, __scissory, __scissorw, __scissorh, true)
    
    --> loop through all elements and call their associated rendering handler
    local blength = windowdata[1]
    local bi = 2
    ::draw_buffer::
    local element = window[bi]
    element[1](element[2], element[3], element[4])

    if (bi < blength) then
        bi = bi + 1
        goto draw_buffer
    end

    windowdata[1] = 1 --> reset window length

    if (wi ~= wlength) then
        wi = wi + 1
        goto draw_windows
    end

    render_SetScissorRect(0, 0, 0, 0, false)
    render_PopRenderTarget()

    --> prepare the global state for the next frame
    drawlist.length = 0 --> reset draw list length
    drawlist.target = 0
    __lastlength = wlength

    local scroll = input.GetAnalogValue(ANALOG_MOUSE_WHEEL)
    __scroll = (scroll - __lastscroll) * SCROLL_SENSITIVITY
    __lastscroll = scroll

    --> perform a memory cycle if we need to
    if (__queuedcycle) then
        __cyclememory()
    end
end)

--> get mouse inputs
hook.pre("StartCommand", "__gmgui_input", function()
    __clicked = input_WasMousePressed(MOUSE_LEFT) or input_WasMouseDoublePressed(MOUSE_LEFT)
end)

local __lastgc = gcinfo()
local __lastgctime = SysTime()
local __gcincrease = 0
hook.pre("PostRender", "__gmgui_test", function()
    gmgui.startwindow("Test Window", 100, 900, 500, 300, 100)
        --[[
        gmgui.text("Example text.")
        gmgui.textdisabled("Disabled text.")
        if (gmgui.button("Button")) then
            __log("Pressed test button!")
        end
        if (gmgui.checkbox("Checkbox")) then
            __log("Checked!")
        end
        ]]

        local gc = gcinfo()
        local time = SysTime()
        local gctimedelta = time - __lastgctime
        if (gctimedelta > 0.5) then
            __gcincrease = (gc - __lastgc) / (gctimedelta)
            __lastgctime = time
            __lastgc = gc
        end
        gmgui.text(string.format("GC: %sKB (%+iKB/s)", gc, __gcincrease))
        gmgui.text(string.format("Virtual elements: %i | Real elements: %i", buffer[1][1][1], #buffer[1]))

        gmgui.text(string.format("Allocated windows: %s", #buffer))
        local preallocate = gmgui.checkbox("Pre-allocate?", true)
        if (gmgui.button("Cycle Memory")) then
            if (preallocate) then
                __queuecycle(2, 6)
            else
                __queuecycle(1, 0)
            end
            collectgarbage("collect")
        end

        --[[
        gmgui.beginchild("Test Child", 0, 0, 0, 50)
            gmgui.button("Test")
        gmgui.endchild()

        gmgui.beginchild("Test Child 2", 0, 0, 0, 0)
            gmgui.button("Test")
        gmgui.endchild()
        ]]

        --[[
        gmgui.beginchild("Outer", 0, 0, 0, 0)
            gmgui.beginchild("Inner", 0, 0, 100, 50)
                gmgui.button("Test")
            gmgui.endchild()
        gmgui.endchild()
        ]]

        gmgui.beginscrollingarea("Scrolling", 0, 0, 0, 0, flags.scrollablearea.invert)
            for i = 1, 20 do
                gmgui.button(tostring(i))
            end
        gmgui.endscrollingarea()
    gmgui.endwindow()

    --> z-index testing
    --[[
    gmgui.startwindow("Always Above", 300, 100, 300, 50, 9999)
        gmgui.text("This window has the highest z-index.")
    gmgui.endwindow()

    gmgui.startwindow("Always Behind", 700, 100, 300, 50, -9999)
        gmgui.text("This window has the lowest z-index.")
    gmgui.endwindow()

    if (FrameNumber() % 300 == 0) then
        for i = 1, 10 do
            gmgui.startwindow(tostring(i), 1100, 100, 300, 50, i)
                gmgui.text("A.")
            gmgui.endwindow()
        end
    end
    ]]
end)