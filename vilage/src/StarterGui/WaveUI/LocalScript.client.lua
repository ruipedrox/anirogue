local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent
local label = gui.Wave.Text

-- Formata o texto
local function updateWaveLabel()
	-- If a restart countdown is active, show it instead of the wave counter
	local restarting = ReplicatedStorage:GetAttribute("Restarting")
	if restarting then
		local left = tonumber(ReplicatedStorage:GetAttribute("RestartCountdown")) or 0
		if left > 0 then
			label.Text = ("Restarting in %ds..."):format(left)
			return
		end
	end

	local current = ReplicatedStorage:GetAttribute("CurrentWave")
	local total = ReplicatedStorage:GetAttribute("TotalWaves")
	if typeof(current) ~= "number" or typeof(total) ~= "number" or total <= 0 then
		label.Text = "Wave: ?/?"
		return
	end
	label.Text = ("Wave: %d/%d"):format(math.clamp(current, 0, total), total)
end

-- Atualização inicial
updateWaveLabel()

-- Reage quando o servidor atualizar os atributos
ReplicatedStorage:GetAttributeChangedSignal("CurrentWave"):Connect(updateWaveLabel)
ReplicatedStorage:GetAttributeChangedSignal("TotalWaves"):Connect(updateWaveLabel)
ReplicatedStorage:GetAttributeChangedSignal("Restarting"):Connect(updateWaveLabel)
ReplicatedStorage:GetAttributeChangedSignal("RestartCountdown"):Connect(updateWaveLabel)