local PlayerStatsModule = require(game.ReplicatedStorage.Scripts.PlayerStats)

local ApplyStatsModule = {}

-- equipment: {weapon = {...}, armor = {...}, rings = {...}}
-- chars: {FireMageEffects, IceWarriorEffects, ...}
function ApplyStatsModule:Apply(player, equipment, chars)
	-- Calcula stats finais (ainda sem aplicar scaling de nível de personagem)
	local finalStats = PlayerStatsModule:Calculate(equipment, chars)

	--[[
	CHARACTER LEVEL SCALING
	Nível 1: 100% dos passivos originais.
	Nível 80: 200% (2x) dos passivos para stats escaláveis.
	Escala linear por nível: mult = 1 + (level - 1)/(MAX_CHAR_LEVEL - 1)
	Stats escaláveis:
	  * Health
	  * BaseDamage
	  * AttackSpeed
	  * CritDamage
	  * xpgainrate
	Implementação: adicionamos apenas a parte bônus (value * (mult - 1)) porque o valor base já foi inserido no cálculo inicial.
	Para custom curves por personagem, substituir cálculo de 'mult' aqui por uma função por-char futuramente.
	]]
	-- Character level scaling (1 -> 2 linear)
	local SCALABLE = {
		Health = true,
		BaseDamage = true,
		AttackSpeed = true,
		CritDamage = true,
		xpgainrate = true,
	}
	local MAX_CHAR_LEVEL = 80
	if chars and #chars > 0 then
		for _, char in ipairs(chars) do
			if char.Passives then
				-- Usar apenas Level presente na instância (ou default 1 se ausente)
				local level = tonumber(char.Level) or 1
				if level < 1 then level = 1 end
				if level > 1 then
					local mult = 1 + ((level - 1) / (MAX_CHAR_LEVEL - 1)) -- reaches 2 at level 80
					for stat, value in pairs(char.Passives) do
						if SCALABLE[stat] and type(value) == "number" then
							finalStats[stat] = (finalStats[stat] or 0) + (value * (mult - 1))
						end
					end
				end
			end
		end
	end

	-- Cria pasta Stats se não existir; preserva valores persistentes (Level, XP, XPRequired, MaxLevel, LevelGrowth)
	local statsFolder = player:FindFirstChild("Stats")
	local preserve = {}
	if not statsFolder then
		statsFolder = Instance.new("Folder")
		statsFolder.Name = "Stats"
		statsFolder.Parent = player
	else
		for _, ch in ipairs(statsFolder:GetChildren()) do
			if ch:IsA("NumberValue") or ch:IsA("BoolValue") or ch:IsA("Folder") then
				local name = ch.Name
				if name == "Level" or name == "XP" or name == "XPRequired" or name == "MaxLevel" or name == "LevelGrowth" then
					preserve[name] = ch
				end
			end
		end
		-- Remove only non-preserved children (so Level/XP persist through Apply)
		for _, ch in ipairs(statsFolder:GetChildren()) do
			if not preserve[ch.Name] then
				ch:Destroy()
			end
		end
	end

	-- Fold temporary buffs (attributes) into final stats
	do
		local dmgBuff = player:GetAttribute("Buff_Damage")
		if typeof(dmgBuff) == "number" and dmgBuff ~= 0 then
			finalStats.BaseDamage = (finalStats.BaseDamage or 0) + dmgBuff
		end
		local asBuff = player:GetAttribute("Buff_AttackSpeed")
		if typeof(asBuff) == "number" and asBuff ~= 0 then
			finalStats.AttackSpeed = (finalStats.AttackSpeed or 0) + asBuff
		end

		-- Persistent run upgrades (e.g., cards): NumberValues under player.Upgrades
		local upgrades = player:FindFirstChild("Upgrades")
		if upgrades then
			local healthPercent = 0
			local atkSpeedPercent = 0
			local moveSpeedPercent = 0
			for _, child in ipairs(upgrades:GetChildren()) do
				if child:IsA("NumberValue") then
					if child.Name == "HealthPercent" then
						healthPercent += child.Value
					elseif child.Name == "AttackSpeedPercent" then
						atkSpeedPercent += child.Value
					elseif child.Name == "MoveSpeedPercent" then
						moveSpeedPercent += child.Value
					else
						finalStats[child.Name] = (finalStats[child.Name] or 0) + child.Value
					end
				end
			end
			-- After collecting HealthPercent (sum of percents), apply it to Health as a multiplier
			if healthPercent ~= 0 then
				local hpBase = finalStats.Health or 0
				finalStats.Health = hpBase * (1 + math.max(-0.99, healthPercent / 100))
			end
			-- Apply AttackSpeedPercent multiplicatively on the total attack speed
			if atkSpeedPercent ~= 0 then
				local asBase = finalStats.AttackSpeed or 0
				finalStats.AttackSpeed = asBase * (1 + math.max(-0.99, atkSpeedPercent / 100))
			end
			-- Apply MoveSpeedPercent multiplicatively; store absolute MoveSpeed so Humanoid gets updated
			if moveSpeedPercent ~= 0 then
				local baseMove = finalStats.MoveSpeed or finalStats.WalkSpeed or 16
				local target = baseMove * (1 + math.max(-0.99, moveSpeedPercent / 100))
				finalStats.MoveSpeed = target
			end
		end
	end

	-- Adiciona cada stat como NumberValue ou BoolValue (sem sobrescrever Level/XP preservados)
	for statName, value in pairs(finalStats) do
		if not preserve[statName] then
			local statObject
			if type(value) == "number" then
				statObject = Instance.new("NumberValue")
				statObject.Value = value
			elseif type(value) == "boolean" then
				statObject = Instance.new("BoolValue")
				statObject.Value = value
			end
			if statObject then
				statObject.Name = statName
				statObject.Parent = statsFolder
			end
		end
	end

	-- Ensure an OnHit section exists in Stats for auxiliary effects (populated from Upgrades.OnHit)
	local statsOnHit = statsFolder:FindFirstChild("OnHit")
	if statsOnHit then
		statsOnHit:ClearAllChildren()
	else
		statsOnHit = Instance.new("Folder")
		statsOnHit.Name = "OnHit"
		statsOnHit.Parent = statsFolder
	end
	-- Mirror any Upgrades.OnHit definitions into Stats.OnHit (so clearing Stats won't lose source data)
	local upgrades = player:FindFirstChild("Upgrades")
	if upgrades then
		local upOnHit = upgrades:FindFirstChild("OnHit")
		if upOnHit and upOnHit:IsA("Folder") then
			for _, ch in ipairs(upOnHit:GetChildren()) do
				ch:Clone().Parent = statsOnHit
			end
		end
	end
end

-- After stats folder populated, apply to Humanoid (HP, attributes for combat systems)
function ApplyStatsModule:ApplyToHumanoid(player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local statsFolder = player:FindFirstChild("Stats")
	if not statsFolder then return end

	local function getNumber(name)
		local nv = statsFolder:FindFirstChild(name)
		return (nv and nv:IsA("NumberValue") and nv.Value) or nil
	end
	-- MaxHealth
	local hp = getNumber("Health")
	if hp and hp > 0 then
		local ratio = 1
		if hum.MaxHealth > 0 then
			ratio = hum.Health / hum.MaxHealth
		end
		-- clamp ratio 0..1
		if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
		hum.MaxHealth = hp
		-- Só atualiza HP se for revive explícito ou se HP atual > 0 e menor que o novo MaxHealth
		if hum.Health > 0 and hum.Health < hp then
			hum.Health = math.floor(hp * ratio + 0.5)
		end
		-- Se estiver morto, não altera HP
	end
	-- Expose combat attributes
	local expose = { "BaseDamage", "AttackSpeed", "CritChance", "CritDamage", "DamagePercent", "Range", "Pierce", "ProjectileSpeed", "Lifetime", "DoTEnabled", "DoTTime", "DoTEffectiveness", "DoTCrit", "xpgainrate" }
	for _, name in ipairs(expose) do
		local val = getNumber(name)
		if val ~= nil then hum:SetAttribute(name, val) end
	end
	-- Movement speed if provided
	local move = getNumber("MoveSpeed") or getNumber("WalkSpeed")
	if move and move > 0 then
		hum.WalkSpeed = move
	end
end

-- Wrap original apply to also update humanoid automatically
local origApply = ApplyStatsModule.Apply
function ApplyStatsModule:Apply(player, equipment, chars)
	-- DEBUG START
	local debugPrefix = "[ApplyStats]"
	local charCount = chars and #chars or 0
	local eqWeapon = equipment and equipment.weapon and (equipment.weapon.Name or "weaponTbl") or "nil"
	local eqArmor = equipment and equipment.armor and (equipment.armor.Name or "armorTbl") or "nil"
	local eqRing = equipment and equipment.ring and (equipment.ring.Name or "ringTbl") or "nil"
	pcall(function()
		print(debugPrefix, player.Name, "chars=", charCount, "weapon=", eqWeapon, "armor=", eqArmor, "ring=", eqRing)
	end)
	origApply(self, player, equipment, chars)
	-- After populate, inspect Health NumberValue
	local statsFolder = player:FindFirstChild("Stats")
	if statsFolder then
		local hv = statsFolder:FindFirstChild("Health")
		if hv then
			pcall(function() print(debugPrefix, player.Name, "Final Health stat=", hv.Value) end)
		else
			pcall(function() print(debugPrefix, player.Name, "No Health value in Stats folder") end)
		end
	end
	self:ApplyToHumanoid(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function() print(debugPrefix, player.Name, "Humanoid.MaxHealth=", hum.MaxHealth, "Humanoid.Health=", hum.Health) end)
	end
	-- DEBUG END (remover depois)
end

return ApplyStatsModule
