--*> achievements.lua <*--
--*> gets you most of the achievements in gmod - useful for making accounts look more legit <*--
--*> made by eyoko1 <*--

--> achievements obtainable with achievements.*
local achievementids = {
    BalloonPopped = 20,
    EatBall = 18,
    IncBaddies = 8,
    IncBystander = 16,
    IncGoodies = 17,
    Remover = 21,
    SpawnedNPC = 24,
    SpawnedProp = 19,
    SpawnedRagdoll = 25,
    SpawnMenuOpen = 22
}

local otherachievements = {
    SecretPhrase = 4,
    BadCoder = 23
}

local names = {}
for _, id in pairs(achievementids) do
    names[id] = achievements.GetName(id)
end
for _, id in pairs(otherachievements) do
    names[id] = achievements.GetName(id)
end

local function achievementbutton(name, id)
    if (achievements.IsAchieved(id)) then
        gmgui.button(names[id], true)
    else
        if (gmgui.button(names[id])) then
            timer.Simple(0, achievements[name])
            print(achievements[name])
        end
    end
end

hook.pre("PostRender", "Achievement Manager", function()
    gmgui.startwindow("Achievement Manager", 1100, 600, 500, 160)
        gmgui.text("Most of the achievements in the game are here.")
        gmgui.text("Use this to make accounts looks more legit, or to save time.")

        gmgui.beginchild("Achievements", 0, 0, 0, 0)
            local index = 1
            for name, id in pairs(achievementids) do
                achievementbutton(name, id)

                if (index % 4 ~= 0) then
                    gmgui.sameline()
                end

                index = index + 1
            end
            
            for name, id in pairs(otherachievements) do
                achievementbutton(name, id) --> implement additional logic for this later

                if (index % 4 ~= 0) then
                    gmgui.sameline()
                end

                index = index + 1
            end
        gmgui.endchild()
    gmgui.endwindow()
end)