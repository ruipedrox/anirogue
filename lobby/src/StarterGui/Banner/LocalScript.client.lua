-- LocalScript.client.lua (Banner renderer)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BannerUpdated = Remotes:WaitForChild("BannerUpdated")

-- Ensure PlayerGui exists and prepare attribute storage
local playerGui = player:WaitForChild("PlayerGui")

-- Connect to server broadcast for banner updates and cache banner JSON for other client scripts
BannerUpdated.OnClientEvent:Connect(function(banner)
    pcall(function()
        if not banner or type(banner) ~= "table" then return end
        local ok, json = pcall(function() return HttpService:JSONEncode(banner) end)
        if ok and json then
            playerGui:SetAttribute("CurrentBanner", json)
            print("[BannerClient] Received banner with " .. tostring(#(banner.entries or {})) .. " entries. First entry:", banner.entries and banner.entries[1] and banner.entries[1].id)
        end
    end)
end)

-- If another script already set CurrentBanner attribute earlier, keep it; otherwise nothing to do.
