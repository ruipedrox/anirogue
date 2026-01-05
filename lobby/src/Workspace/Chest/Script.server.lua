-- Server: Part touch -> open Chest UI (robusto, com timestamps e logs)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Ensure the Remotes folder exists
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

-- RemoteEvent to open the UI
local openRemote = remotes:FindFirstChild("Open_Chest")
if not openRemote then
	openRemote = Instance.new("RemoteEvent")
	openRemote.Name = "Open_Chest"
	openRemote.Parent = remotes
end

-- Client readiness RemoteEvent
local ChestClientReadyRE = remotes:FindFirstChild("ChestClientReady")
if not ChestClientReadyRE then
	ChestClientReadyRE = Instance.new("RemoteEvent")
	ChestClientReadyRE.Name = "ChestClientReady"
	ChestClientReadyRE.Parent = remotes
end

-- RemoteFunction for explicit client confirmation
local openChestFunction = remotes:FindFirstChild("OpenChestFunction")
if not openChestFunction then
	openChestFunction = Instance.new("RemoteFunction")
	openChestFunction.Name = "OpenChestFunction"
	openChestFunction.Parent = remotes
end

local clientReady = {} -- map<userId, boolean>

print(string.format("[ChestBlock] Remotes: Open_Chest=%s OpenChestFunction=%s", tostring(openRemote and openRemote:GetFullName()), tostring(openChestFunction and openChestFunction:GetFullName())))

local function findTouchable(base)
	if not base then return nil end
	if base:IsA("BasePart") then return base end
	for _, d in ipairs(base:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local part = findTouchable(script.Parent)
if not part then
	warn("[ChestBlock] Nenhuma BasePart encontrada para conectar Touched (parent=", script.Parent and script.Parent:GetFullName(), ")")
end
local debounce = {}
local DEBOUNCE_SECONDS = 0.8

ChestClientReadyRE.OnServerEvent:Connect(function(player)
	clientReady[player.UserId] = true
	print("[ChestBlock] Cliente pronto para Chest:", player.Name)
end)

Players.PlayerRemoving:Connect(function(player)
	if not player then return end
	debounce[player.UserId] = nil
	clientReady[player.UserId] = nil
end)

local function playerFromHit(hit)
	local char = hit and hit:FindFirstAncestorOfClass("Model")
	if not char then return nil end
	return Players:GetPlayerFromCharacter(char)
end

if part and part.Touched then part.Touched:Connect(function(hit)
	local player = playerFromHit(hit)
	print("[ChestBlock] playerFromHit:", player, player and player.Name)
	if not player then return end
	local uid = player.UserId
	local now = os.clock()
	if debounce[uid] and now - debounce[uid] < DEBOUNCE_SECONDS then
		print(string.format("[ChestBlock] Debounce ativo para %s (%.2fs)", player.Name, now - debounce[uid]))
		return
	end
	debounce[uid] = now

	print(string.format("[ChestBlock] Estado clientReady[%s]=%s", tostring(uid), tostring(clientReady[uid])))

	if clientReady[uid] ~= true then
		print("[ChestBlock] Cliente ainda não sinalizou pronto, ignorando.")
		return
	end

	if openRemote and openRemote:IsA("RemoteEvent") then
		print("[ChestBlock] Disparando evento para:", player, player and player.Name, "Remote:", openRemote)
		local ok, err = pcall(function()
			openRemote:FireClient(player, "Chest")
		end)
		if ok then
			print(string.format("[ChestBlock] Fired Open_Chest to %s", tostring(player.Name)))
		else
			warn(string.format("[ChestBlock] Failed to FireClient Open_Chest for %s: %s", tostring(player.Name), tostring(err)))
		end
	else
		warn("Remote Open_Chest não encontrado em ReplicatedStorage.Remotes")
	end

	if openChestFunction then
		print("[ChestBlock] Invocando RemoteFunction para:", player, player and player.Name)
		local ok, result = pcall(function()
			return openChestFunction:InvokeClient(player, "Chest")
		end)
		if ok and result == true then
			print(string.format("[ChestBlock] Cliente confirmou abertura da UI: %s", tostring(player.Name)))
		else
			warn(string.format("[ChestBlock] Cliente NÃO confirmou abertura da UI: %s", tostring(player.Name)))
		end
	else
		warn("RemoteFunction OpenChestFunction não encontrado em ReplicatedStorage.Remotes")
	end
end end)
