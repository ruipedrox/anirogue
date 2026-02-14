local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent
local label = gui.Wave.Text

-- Infinite mode: show current wave only (no total/limit)
local function updateWaveLabel()
	-- If a restart countdown is active, show it instead
	local restarting = ReplicatedStorage:GetAttribute("Restarting")
	if restarting then
		local left = tonumber(ReplicatedStorage:GetAttribute("RestartCountdown")) or 0
		if left > 0 then
			label.Text = ("Restarting in %ds..."):format(left)
			return
		end
	end

	local current = ReplicatedStorage:GetAttribute("CurrentWave")
	if typeof(current) ~= "number" then
		label.Text = "Wave: ?"
		return
	end
	-- Infinite mode: show only current wave number
	label.Text = ("Wave: %d"):format(math.max(current, 0))
end

-- Initial update
updateWaveLabel()

-- React to server attribute changes
ReplicatedStorage:GetAttributeChangedSignal("CurrentWave"):Connect(updateWaveLabel)
ReplicatedStorage:GetAttributeChangedSignal("Restarting"):Connect(updateWaveLabel)
ReplicatedStorage:GetAttributeChangedSignal("RestartCountdown"):Connect(updateWaveLabel)