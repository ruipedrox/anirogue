local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes")
local OpenRemote = Remotes:FindFirstChild("Open_Story") or Remotes:FindFirstChild("Open_Story")

local part = script.Parent
-- Ensure portal Part has Mode attribute so server logic can detect Infinite portals
pcall(function()
	if part and part.SetAttribute then
		local m = part:GetAttribute("Mode")
		if not m or tostring(m) == "" then
			part:SetAttribute("Mode", "Infinite")
			print(string.format("[StoryPortal] Set attribute Mode='Infinite' on %s", part:GetFullName()))
		else
			print(string.format("[StoryPortal] Mode attribute already set on %s: %s", part:GetFullName(), tostring(m)))
		end
	end
end)

local function onTouched(hit)
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	if not player then return end
	-- Fire the Story UI remote with 'Infinite' to indicate infinite maps mode
	pcall(function()
		if OpenRemote and OpenRemote.FireClient then
			OpenRemote:FireClient(player, "Infinite")
		end
	end)
end

if part and part:IsA("BasePart") then
	part.Touched:Connect(onTouched)
end
