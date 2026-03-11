local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local OpenRemote = Remotes:WaitForChild("Open_Story")

-- Ensure StoryClientReady exists (may be created by Portal/Script.server.lua first)
local StoryClientReadyRE = Remotes:FindFirstChild("StoryClientReady")
if not StoryClientReadyRE then
	StoryClientReadyRE = Instance.new("RemoteEvent")
	StoryClientReadyRE.Name = "StoryClientReady"
	StoryClientReadyRE.Parent = Remotes
end

local part = script.Parent
pcall(function()
	if part and part.SetAttribute then
		local m = part:GetAttribute("Mode")
		if not m or tostring(m) == "" then
			part:SetAttribute("Mode", "Infinite")
		end
	end
end)

local debounce       = {}  -- [userId] = os.clock()
local pendingOpen    = {}  -- [userId] = true  — touched but client not ready yet (first load only)
local clientEverReady = {} -- [userId] = true  — client sent StoryClientReady at least once
local DEBOUNCE_SECONDS = 2

-- Fire "Infinite" open to a player. Always clears pendingOpen so StoryClientReady
-- can't accidentally re-fire after the client closes and keepReady restarts.
local function fireOpen(player)
	pendingOpen[player.UserId] = nil
	pcall(function()
		OpenRemote:FireClient(player, "Infinite")
	end)
	print(string.format("[InfPortal] Fired Open_Story Infinite -> %s", player.Name))
end

-- StoryClientReady is sent by keepReady on the client:
-- • On first load, before the client listener is registered → use pendingOpen to catch missed events
-- • On subsequent resets (after UI closes) → clientEverReady is already true, never re-fire
StoryClientReadyRE.OnServerEvent:Connect(function(player)
	local uid = player.UserId
	if not clientEverReady[uid] then
		clientEverReady[uid] = true
		-- First time client is ready: deliver any pending open from a touch that arrived early
		if pendingOpen[uid] then
			fireOpen(player)
		end
	end
	-- If clientEverReady already, do nothing — keepReady re-runs after UI close but
	-- we do NOT want to re-open the Infinite UI automatically; debounce+touch drives that.
end)

Players.PlayerRemoving:Connect(function(player)
	debounce[player.UserId]        = nil
	pendingOpen[player.UserId]     = nil
	clientEverReady[player.UserId] = nil
end)

local function onTouched(hit)
	local char = hit and hit:FindFirstAncestorOfClass("Model")
	local player = char and Players:GetPlayerFromCharacter(char)
	if not player then return end

	local uid = player.UserId
	local now = os.clock()
	if debounce[uid] and now - debounce[uid] < DEBOUNCE_SECONDS then return end
	debounce[uid] = now

	if clientEverReady[uid] then
		-- Client listener is confirmed up: fire directly, no pending needed
		fireOpen(player)
	else
		-- Client might not have registered .OnClientEvent yet; set pending so
		-- the first StoryClientReady signal delivers the event
		pendingOpen[uid] = true
		fireOpen(player)  -- also attempt immediately
	end
end

if part and part:IsA("BasePart") then
	part.Touched:Connect(onTouched)
end