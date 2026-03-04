-- PlaySounds.lua
-- Client-side sound player helper. Require this from client LocalScripts and call PlayClick/PlayOpen/PlayClose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Player = Players.LocalPlayer

local soundsOk, sounds = pcall(function()
    return require(
        ReplicatedStorage:WaitForChild("Shared")
            :WaitForChild("Sounds")
            :WaitForChild("Sounds")
    )
end)
if not soundsOk or type(sounds) ~= "table" then sounds = {} end

local function playSoundId(id, volume)
    if not id or id == 0 then return end
    -- escala pelo volume SFX do player (0-100)
    local sfxAttr = Player and Player:GetAttribute("SFXVolume")
    local sfxMult = (type(sfxAttr) == "number") and math.clamp(sfxAttr / 100, 0, 1) or 0.5
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(id)
    sound.Volume = (volume or 0.6) * sfxMult
    sound.Parent = SoundService
    sound.PlayOnRemove = false
    sound:Play()
    Debris:AddItem(sound, 5)
end

local API = {}

function API.PlayClick(volume)
    playSoundId(sounds.UI_CLICK, volume or 0.6)
end

function API.PlayOpen(volume)
    playSoundId(sounds.UI_OPEN, volume or 0.6)
end

function API.PlayError(volume)
    playSoundId(sounds.UI_ERROR, volume or 0.6)
end

function API.PlayByName(key, volume)
    if type(key) ~= "string" then return end
    local id = sounds[key]
    if id then playSoundId(id, volume) end
end

return API
