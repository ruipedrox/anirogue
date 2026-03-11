-- This script is disabled because AI.server.lua handles all movement
-- Original code attempted to load walk animation which doesn't exist
--[[
local animation = script:WaitForChild('walk')
local humanoid = script.Parent:WaitForChild('Humanoid')
local idle = humanoid:LoadAnimation(animation)
idle:play()
idle.Looped = true
]]