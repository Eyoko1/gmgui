local ENTITY = cloned_mts.Entity
local PLAYER = cloned_mts.Player
local VECTOR = cloned_mts.Vector

local occluded = CreateMaterial(lje.util.random_string(), "VertexLitGeneric", {
    ["$basetexture"] = "vgui/white_additive",
    ["$model"] = 1,
    ["$translucent"] = 1,
    ["$color2"] = "{ 96 96 192 }",
    ["$supressedenginelighting"] = 1
    --["$wireframe"] = 1
})

local visible = CreateMaterial(lje.util.random_string(), "VertexLitGeneric", {
    ["$basetexture"] = "vgui/white_additive",
    ["$bumpmap"] = "vgui/white_additive",
    ["$model"] = 1,
    ["$nocull"] = 0,
    ["$selfillum"] = 1,
    ["$selfIllumFresnel"] = 1,
    ["$supressedenginelighting"] = 1,
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
    ["$supressedenginelighting"] = 1,
    ["$selfIllumFresnelMinMaxExp"] = "[ 0 0 1 ]",
    ["$selfillumtint"] = "[ 0 0 0 ]",
    ["$translucent"] = 1,
    ["$ignorez"] = 0
})

local chamsflags = bit.bor(STUDIO_RENDER, STUDIO_NOSHADOWS, STUDIO_STATIC_LIGHTING)

hook.post("PreDrawViewModels", "Chams", function()
    cam.Start3D(MainEyePos(), MainEyeAngles())
        render.PushRenderTarget(lje.util.rendertarget)
            render.SetWriteDepthToDestAlpha(false)
            render.SuppressEngineLighting(true)

            lje.util.iterate_players(function(target)
                cam.IgnoreZ(true)
                render.OverrideDepthEnable(true, false)
                    render.MaterialOverride(occluded)
                    lje.util.safe_draw_model(target, chamsflags)
                render.OverrideDepthEnable(false)
                cam.IgnoreZ(false)

                render.MaterialOverride(visible)
                lje.util.safe_draw_model(target, chamsflags)
            end)

            render.MaterialOverride(nil)
            render.SuppressEngineLighting(false)
        render.PopRenderTarget()
    cam.End3D()
end)

hook.post("PreDrawViewModel", "ViewModel", function(vm)
    render.PushRenderTarget(lje.util.rendertarget)
        render.MaterialOverride(weapon)
        lje.util.safe_draw_model(vm, chamsflags)
        render.MaterialOverride(nil)
    render.PopRenderTarget()
end)