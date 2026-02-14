-- SeriousTraining.lua
-- Saitama's unique training card - unlocks true power at level 10
-- Grants massive base stat multipliers when fully trained

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local def = {
	Name = "Serious Training",
	Rarity = "Legendary",
	Type = "Passive",
	MaxLevel = 10,
	Description = "100 push-ups, 100 sit-ups, 100 squats, and 10km running EVERY DAY!"
}

-- Track training progress per player
local TrainingByUserId = {}

local function addUpgrade(player, name, delta)
	if type(delta) ~= "number" or delta == 0 then return end
	local upgrades = player:FindFirstChild("Upgrades")
	if not upgrades then
		upgrades = Instance.new("Folder")
		upgrades.Name = "Upgrades"
		upgrades.Parent = player
	end
	local u = upgrades:FindFirstChild(name)
	if not u then
		u = Instance.new("NumberValue")
		u.Name = name
		u.Value = 0
		u.Parent = upgrades
	end
	u.Value = u.Value + delta
	-- Mirror to Stats
	local stats = player:FindFirstChild("Stats")
	if stats then
		local s = stats:FindFirstChild(name)
		if not s then
			s = Instance.new("NumberValue")
			s.Name = name
			s.Value = 0
			s.Parent = stats
		end
		s.Value = s.Value + delta
	end
end

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	local level = math.clamp(currentLevel or 1, 1, def.MaxLevel)
	
	-- Store level
	if not TrainingByUserId[player.UserId] then
		TrainingByUserId[player.UserId] = {}
	end
	
	-- Remove old multipliers if downgrading from level 10
	local oldLevel = TrainingByUserId[player.UserId].level
	if oldLevel == 10 and level < 10 then
		player:SetAttribute("SaitamaDamageMult", nil)
		player:SetAttribute("SaitamaHealthMult", nil)
	end
	
	TrainingByUserId[player.UserId].level = level
	
	-- Level 10 = AWAKENING (1000x damage, 3000x health)
	if level == 10 then
		-- Store multipliers for Saitama's base stats only
		-- These are applied in PlayerStats:Calculate to Saitama's Passives
		player:SetAttribute("SaitamaDamageMult", 1000)
		player:SetAttribute("SaitamaHealthMult", 3000)
		
		-- Unlock Serious Punch in card pool
		player:SetAttribute("SaitamaAwakened", true)
		
		print(string.format("[Serious Training] Player %s has AWAKENED! 100x damage, 300x health, Serious Punch unlocked!",
			player.Name
		))
		
		-- Reapply stats and heal to new max HP
		pcall(function()
			local ApplyStats = require(ReplicatedStorage.Scripts.ApplyStats)
			local EquippedItems = require(ReplicatedStorage.Scripts.EquipedItems)
			local CharEquipped = require(ReplicatedStorage.Scripts.CharEquiped)
			local items = EquippedItems:GetEquipped(player)
			local chars = CharEquipped:GetEquipped(player)
			ApplyStats:Apply(player, items, chars)
			
			-- Heal player to new max HP
			local char = player.Character
			if char then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.Health = hum.MaxHealth
				end
			end
		end)
	else
		print(string.format("[Serious Training] Player %s training level %d/10...",
			player.Name,
			level
		))
	end
end

function def.OnCardRemoved(player: Player, cardData)
	local data = TrainingByUserId[player.UserId]
	if not data then return end
	
	local level = data.level
	
	-- Remove level 10 buffs if active
	if level == 10 then
		player:SetAttribute("SaitamaDamageMult", nil)
		player:SetAttribute("SaitamaHealthMult", nil)
		
		-- Remove awakening flag
		player:SetAttribute("SaitamaAwakened", nil)
	end
	
	-- Cleanup
	TrainingByUserId[player.UserId] = nil
	
	print(string.format("[Serious Training] Player %s stopped training", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	TrainingByUserId[player.UserId] = nil
end)

return def
