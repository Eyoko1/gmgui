local _R = lje.util.get_registry()

local ENTITY = _R.Entity
local PLAYER = _R.Player
local VECTOR = _R.Vector

local occluded = CreateMaterial(lje.util.random_string(), "VertexLitGeneric", {
    ["$basetexture"] = "vgui/white_additive",
    ["$model"] = 1,
    ["$translucent"] = 1,
    ["$color2"] = "{ 96 96 192 }"
    --["$wireframe"] = 1
})

local visible = CreateMaterial(lje.util.random_string(), "VertexLitGeneric", {
    ["$basetexture"] = "vgui/white_additive",
    ["$bumpmap"] = "vgui/white_additive",
    ["$model"] = 1,
    ["$nocull"] = 0,
    ["$selfillum"] = 1,
    ["$selfIllumFresnel"] = 1,
    ["$selfIllumFresnelMinMaxExp"] = "[ 0 1 1 ]",
    ["$selfillumtint"] = "[ 255 0 0 ]",
    ["$translucent"] = 1,
    ["$ignorez"] = 0
})

local weapon = CreateMaterial(lje.util.random_string(), "VertexLitGeneric", {
    ["$basetexture"] = "vgui/white_additive",
    ["$bumpmap"] = "vgui/white_additive",
    ["$model"] = 1,
    ["$nocull"] = 0,
    ["$selfillum"] = 1,
    ["$selfIllumFresnel"] = 1,
    ["$selfIllumFresnelMinMaxExp"] = "[ 0 0 1 ]",
    ["$selfillumtint"] = "[ 0 0 0 ]",
    ["$translucent"] = 1,
    ["$ignorez"] = 0
})

local chamsflags = bit.bor(STUDIO_RENDER, STUDIO_NOSHADOWS, STUDIO_STATIC_LIGHTING)

local function renderplayerchams(target)
    cam.IgnoreZ(true)
    render.OverrideDepthEnable(true, false)
        render.MaterialOverride(occluded)
        target:DrawModel(chamsflags)
    render.OverrideDepthEnable(false, false)
    cam.IgnoreZ(false)

    render.MaterialOverride(visible)
    target:DrawModel(chamsflags)
end

hook.post("PreDrawViewModels", "Chams", function()
    cam.Start3D(MainEyePos(), MainEyeAngles())
        render.PushRenderTarget(lje.util.rendertarget)
            render.SetWriteDepthToDestAlpha(false)
            render.SuppressEngineLighting(true)

            lje.util.iterate_players(renderplayerchams)

            render.MaterialOverride(nil)
            render.SuppressEngineLighting(false)
        render.PopRenderTarget()
    cam.End3D()
end)

hook.post("PreDrawViewModel", "ViewModel", function(vm, localplayer)
    render.PushRenderTarget(lje.util.rendertarget)
        render.MaterialOverride(weapon)
        vm:DrawModel(chamsflags)
        localplayer:GetHands():DrawModel()
        render.MaterialOverride(nil)
    render.PopRenderTarget()
end)