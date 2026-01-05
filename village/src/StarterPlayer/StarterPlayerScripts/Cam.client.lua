task.wait(0.25)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Runtime references, rebound on respawn
local character: Model? = nil
local humanoidRootPart: BasePart? = nil
local humanoid: Humanoid? = nil

-- Parâmetros da câmara
local baseOffsetDirection = Vector3.new(1, 0.9, 0) -- direção da câmara (normalizada + altura)
baseOffsetDirection = baseOffsetDirection.Unit

local zoom = 40 -- zoom inicial (distância da câmara)
local minZoom = 20
local maxZoom = 50
local zoomStep = 5

-- Helper: recenter/retarget camera to current character
local function attachCharacter(char: Model)
	character = char
	-- Wait for essential parts
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if not hrp or not hum then return end
	humanoidRootPart = hrp
	humanoid = hum :: Humanoid
	-- Ensure manual camera control after respawn and rebind subject
	camera.CameraSubject = hum
	camera.CameraType = Enum.CameraType.Scriptable
	-- Optionally reset zoom a bit after revive
	zoom = math.clamp(zoom, minZoom, maxZoom)
	-- Hard snap camera to new character once
	local targetPosition = humanoidRootPart.Position
	local cameraOffset = baseOffsetDirection * zoom
	camera.CFrame = CFrame.new(targetPosition + cameraOffset, targetPosition)
end

-- Initial bind (handles CharacterAutoLoads=false + manual LoadCharacter)
if player.Character then
	attachCharacter(player.Character)
end
player.CharacterAdded:Connect(function(char)
	attachCharacter(char)
end)

-- Ajustar zoom com o scroll do rato
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		zoom -= input.Position.Z * zoomStep
		zoom = math.clamp(zoom, minZoom, maxZoom)
	end
end)

-- Atualizar a câmara constantemente
RunService.RenderStepped:Connect(function(dt)
	-- Keep camera in Scriptable mode to prevent default scripts taking over
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if not (humanoidRootPart and humanoidRootPart.Parent) then return end
	local targetPosition = humanoidRootPart.Position
	local cameraOffset = baseOffsetDirection * zoom
	local cameraPosition = targetPosition + cameraOffset

	-- Define a posição da câmara
	camera.CFrame = CFrame.new(cameraPosition, targetPosition)

	-- Player rotates based on movement direction, not attack direction
	if humanoid then
		humanoid.AutoRotate = true
	end
end)
