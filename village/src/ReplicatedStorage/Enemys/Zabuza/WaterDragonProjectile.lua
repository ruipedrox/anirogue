-- WaterDragonProjectile.lua
-- Defines a helper to spawn a traveling water dragon effect that damages on impact + small splash.
-- For now this is a simple fast projectile with a cylinder trail; can be replaced with an asset later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local WaterDragon = {}

-- Fire a water dragon from origin towards targetPos.
-- params:
--  origin: Vector3
--  targetPos: Vector3
--  damage: number (direct hit damage)
--  splashRadius: number (AoE radius at impact)
--  splashDamage: number (damage to players within splashRadius)
--  speed: number (studs/sec)
--  pierce: number (default 1)
--  lifetime: number (seconds) optional
function WaterDragon.Fire(params)
	assert(params and typeof(params.origin)=="Vector3", "WaterDragon.Fire missing origin")
	assert(typeof(params.targetPos)=="Vector3", "WaterDragon.Fire missing targetPos")
	local origin = params.origin
	local targetPos = params.targetPos
	local dir = (targetPos - origin)
	local distance = dir.Magnitude
	local direction = distance > 0 and dir.Unit or Vector3.new(0,0,-1)
	local speed = params.speed or 90
	local lifetime = params.lifetime or math.max(2, distance / speed + 0.5)
	local pierce = params.pierce or 1
	local damage = params.damage or 50
	local splashRadius = params.splashRadius or 12
	local splashDamage = params.splashDamage or math.floor(damage * 0.6)

	-- Build a simple water dragon primitive (cylinder + particle aura)
	local model = Instance.new("Model")
	model.Name = "WaterDragon"
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = Vector3.new(2, 2, 12)
	part.Color = Color3.fromRGB(70, 120, 255)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = model
	model.PrimaryPart = part
	-- Particle ring for visual flair
	local attach = Instance.new("Attachment")
	attach.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://241837157" -- generic splash texture placeholder
	emitter.LightEmission = 0.8
	emitter.Rate = 40
	emitter.Lifetime = NumberRange.new(0.3, 0.5)
	emitter.Speed = NumberRange.new(2,4)
	emitter.SpreadAngle = Vector2.new(10,10)
	emitter.Parent = attach

	local function onHit(hitPart, enemyModel)
		-- On direct hit spawn splash
		local pos
		if enemyModel and enemyModel.PrimaryPart then
			pos = enemyModel.PrimaryPart.Position
		elseif hitPart and hitPart:IsA("BasePart") then
			pos = hitPart.Position
		else
			pos = part.Position
		end
		-- Splash telegraph (quick)
		local splashPart = Instance.new("Part")
		splashPart.Name = "WaterSplash"
		splashPart.Anchored = true
		splashPart.CanCollide = false
		splashPart.CanQuery = false
		splashPart.CanTouch = false
		splashPart.Shape = Enum.PartType.Cylinder
		splashPart.Material = Enum.Material.Neon
		splashPart.Color = Color3.fromRGB(100,140,255)
		splashPart.Transparency = 0.6
		splashPart.Size = Vector3.new(0.35, splashRadius*2, splashRadius*2)
		splashPart.CFrame = CFrame.new(pos) * CFrame.Angles(0,0,math.rad(90))
		splashPart.Parent = workspace
		-- Damage players in radius
		local PlayersService = game:GetService("Players")
		for _, plr in ipairs(PlayersService:GetPlayers()) do
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				local dist = (root.Position - pos).Magnitude
				if dist <= splashRadius then
					Damage.Apply(hum, splashDamage)
				end
			end
		end
		-- Fade splash
		task.spawn(function()
			local t=0
			local dur=0.5
			while t < dur and splashPart.Parent do
				local dt=0.05
				splashPart.Transparency = 0.6 + (t/dur)*0.4
				task.wait(dt)
				t = t + dt
			end
			if splashPart and splashPart.Parent then splashPart:Destroy() end
		end)
	end

	Projectile.Fire({
		origin = origin,
		direction = direction,
		speed = speed,
		lifetime = lifetime,
		pierce = pierce,
		damage = damage,
		model = model,
		owner = nil,
		onHit = onHit,
		orientationOffset = CFrame.new(),
		contactRadius = 0,
	})
end

return WaterDragon