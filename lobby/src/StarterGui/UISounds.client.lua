-- UISounds.client.lua
-- Auto-wires UI sounds to every button and panel open/close in PlayerGui.
-- No need to touch individual LocalScripts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Load sounds ─────────────────────────────────────────────────────────────
local soundsOk, sounds = pcall(function()
	return require(
		ReplicatedStorage:WaitForChild("Shared")
			:WaitForChild("Sounds")
			:WaitForChild("Sounds")
	)
end)
if not soundsOk then sounds = {} end

local IDS = {
	click = sounds.UI_CLICK or 0,
	open  = sounds.UI_OPEN  or 0,
	error = sounds.UI_ERROR or 0,
}

-- Only these ScreenGuis play the open sound
local OPEN_SOUND_GUIS = {
	Summon  = true,  -- gacha/banner UI
	Chest   = true,
	Story   = true,
	Upgrade = true,
}

local function play(id, vol)
	if not id or id == 0 then return end
	local sfxAttr = player:GetAttribute("SFXVolume")
	local sfxMult = (type(sfxAttr) == "number") and math.clamp(sfxAttr / 100, 0, 1) or 0.5
	local s = Instance.new("Sound")
	s.SoundId   = "rbxassetid://" .. tostring(id)
	s.Volume    = (vol or 0.6) * sfxMult
	s.Parent    = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

-- ── Button auto-hook ─────────────────────────────────────────────────────────
local hookedButtons = {}

local function hookButton(btn)
	if hookedButtons[btn] then return end
	hookedButtons[btn] = true
	btn.MouseButton1Click:Connect(function()
		play(IDS.click)
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

-- ── Panel open/close detection ───────────────────────────────────────────────
-- Watches the first Frame/ScrollingFrame child of each ScreenGui for Visible changes.
-- Ignores this script's own ScreenGui and LobbyMusic.

local IGNORE_GUIS = { UISounds = true, LobbyMusic = true }
local trackedFrames = {}

local function trackScreenGui(sg)
	if not sg:IsA("ScreenGui") then return end
	if IGNORE_GUIS[sg.Name] then return end
	if trackedFrames[sg] then return end

	if not OPEN_SOUND_GUIS[sg.Name] then return end

	-- Method 1: watch first Frame/ScrollingFrame child Visible
	local mainFrame
	for _, c in ipairs(sg:GetChildren()) do
		if c:IsA("Frame") or c:IsA("ScrollingFrame") then
			mainFrame = c
			break
		end
	end

	if mainFrame then
		trackedFrames[sg] = mainFrame.Visible
		mainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			local now = mainFrame.Visible
			if now == trackedFrames[sg] then return end
			trackedFrames[sg] = now
			if now then play(IDS.open) end
		end)
	end

	-- Method 2 (fallback): watch ScreenGui.Enabled — some UIs toggle this instead
	local trackedEnabled = sg.Enabled
	sg:GetPropertyChangedSignal("Enabled"):Connect(function()
		local now = sg.Enabled
		if now == trackedEnabled then return end
		trackedEnabled = now
		if now then play(IDS.open) end
	end)
end

-- hook existing guis
for _, sg in ipairs(playerGui:GetChildren()) do
	hookDescendants(sg)
	trackScreenGui(sg)
end

-- hook guis added later
playerGui.ChildAdded:Connect(function(sg)
	hookDescendants(sg)
	trackScreenGui(sg)
end)
