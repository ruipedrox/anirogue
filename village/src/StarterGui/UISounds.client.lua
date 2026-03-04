-- UISounds.client.lua (Infinite mode)
-- Auto-wires click sound to every GuiButton in PlayerGui.
-- Mirrors lobby UISounds but without panel-open tracking (infinite has no lobby panels).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Load sounds ────────────────────────────────────────────────────────────
local soundsOk, sounds = pcall(function()
	return require(
		ReplicatedStorage:WaitForChild("Shared")
			:WaitForChild("Sounds")
			:WaitForChild("Sounds")
	)
end)
if not soundsOk then sounds = {} end

local CLICK_ID = (sounds and type(sounds) == "table" and sounds.UI_CLICK) or 87437544236708

-- ── Play helper ────────────────────────────────────────────────────────────
local function play(id, vol)
	if not id or id == 0 then return end
	local sfxAttr = player:GetAttribute("SFXVolume")
	local sfxMult = (type(sfxAttr) == "number") and math.clamp(sfxAttr / 100, 0, 1) or 0.5
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume  = (vol or 0.6) * sfxMult
	s.Parent  = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

-- ── Button auto-hook ───────────────────────────────────────────────────────
local hookedButtons = {}

local function hookButton(btn)
	if hookedButtons[btn] then return end
	hookedButtons[btn] = true
	btn.MouseButton1Click:Connect(function()
		play(CLICK_ID)
	end)
	btn.AncestryChanged:Connect(function()
		if not btn:IsDescendantOf(game) then
			hookedButtons[btn] = nil
		end
	end)
end

local function hookDescendants(obj)
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("GuiButton") then
			hookButton(d)
		end
	end
	obj.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then
			hookButton(d)
		end
	end)
end

-- ── Hook existing & future ScreenGuis ─────────────────────────────────────
for _, sg in ipairs(playerGui:GetChildren()) do
	hookDescendants(sg)
end

playerGui.ChildAdded:Connect(function(sg)
	hookDescendants(sg)
end)
