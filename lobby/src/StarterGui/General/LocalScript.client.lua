-- General UI Controller
-- Controla botões laterais (Left_gui) para abrir painéis específicos.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local generalRoot = script.Parent
local leftGui = generalRoot:WaitForChild("Left_gui")
local btnChars = leftGui:WaitForChild("Chars")

-- Referência ao GUI de personagens (StarterGui/Chars)
local function getCharsGui()
	-- Pode estar replicado como ScreenGui ou Folder dependendo da tua hierarquia.
	return playerGui:FindFirstChild("Chars") or playerGui:FindFirstChild("Chars", true)
end

local function findCharsScript(charsGui)
	if not charsGui then return nil end
	-- Tenta nomes prováveis
	local candidates = {"Chars_Inv.client", "Chars_Inv", "LocalScript"}
	for _, name in ipairs(candidates) do
		local f = charsGui:FindFirstChild(name) or charsGui:FindFirstChild(name, true)
		if f and f:IsA("LocalScript") then return f end
	end
	-- Fallback: qualquer LocalScript direto
	for _, child in ipairs(charsGui:GetChildren()) do
		if child:IsA("LocalScript") then return child end
	end
	return nil
end

-- Toggle inventário de personagens usando atributos Show/Hide definidos no LocalScript desse GUI.
local toggleDebounce = false
local lastToggle = 0
local toggleCooldown = 0.25

local function toggleChars()
	if toggleDebounce then return end
	local now = tick()
	if (now - lastToggle) < toggleCooldown then return end
	lastToggle = now
	toggleDebounce = true

	local charsGui = getCharsGui()
	if not charsGui then
		warn("[GeneralUI] Chars GUI não encontrado")
		toggleDebounce = false
		return
	end
	local localScript = findCharsScript(charsGui)
	if not localScript then
		warn("[GeneralUI] LocalScript de Chars não encontrado")
		toggleDebounce = false
		return
	end
	local frame = charsGui:FindFirstChild("Frame") or charsGui:FindFirstChild("Frame", true)
	local isVisible = frame and frame.Visible
	print("[GeneralUI] Toggle Chars -> estado atual vis=", isVisible, "script=", localScript.Name)
	if isVisible then
		localScript:SetAttribute("Hide", true)
		localScript:SetAttribute("Show", false)
		print("[GeneralUI] Fechando Chars (Hide=true Show=false)")
	else
		-- Pulso: garante que o evento Show dispara mesmo se já estava true
		localScript:SetAttribute("Show", false)
		localScript:SetAttribute("Hide", false)
		print("[GeneralUI] Preparando pulso Show...")
		task.delay(0.02, function()
			if not (frame and frame.Visible) then
				localScript:SetAttribute("Show", true)
				print("[GeneralUI] Abrindo Chars (pulso Show=true)")
			end
		end)
	end
	task.delay(0.05, function() toggleDebounce = false end)
end

btnChars.MouseButton1Click:Connect(toggleChars)

-- FUTURO: adicionar restantes botões (Equip, Inv, Quests, etc.)