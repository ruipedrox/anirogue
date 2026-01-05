-- Gaara AI
-- Ranged boss that stays in place with 3 abilities:
-- 1) Sand Shield: Creates protective sand shield (extra HP), has animations for on/off
-- 2) Sand Coffin: Traps player in sand ball, lifts them, then crushes for damage
-- 3) Sand Wave: Fires 3 waves of sand projectiles with intervals

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))
if not humanoid or not root then return end

-- Load Stats
local STATS do
	local statsModule = enemyModel:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
end

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

-- Stats com defaults
local MOVE_SPEED = 0 -- Gaara não se mexe (ranged boss)
local COFFIN_INTERVAL = (STATS and STATS.SandCoffinInterval) or 25 -- Cooldown muito alto (25 segundos)
local COFFIN_DAMAGE = (STATS and STATS.SandCoffinDamage) or 400 -- Dano muito alto (sem dodge possível)
local COFFIN_RANGE = (STATS and STATS.SandCoffinRange) or 60

local SHIELD_HP = (STATS and STATS.SandShieldHP) or 500 -- HP do shield
local SHIELD_ACTIVATION_PERCENT = 0.5 -- Ativa shield aos 50% HP

local WAVE_INTERVAL = (STATS and STATS.SandWaveInterval) or 10
local WAVE_DAMAGE = (STATS and STATS.SandWaveDamage) or 100
local WAVE_SPEED = (STATS and STATS.SandWaveSpeed) or 80
local WAVE_LIFETIME = (STATS and STATS.SandWaveLifetime) or 3

local SPAWN_TIME = os.clock()
local INITIAL_ATTACK_COOLDOWN = 3
local running = true

-- Shield state
local shieldActive = false
local shieldUsed = false
local shieldBall = nil
local currentShieldHP = 0

humanoid.Died:Connect(function() running = false end)
enemyModel.AncestryChanged:Connect(function(_, parent) if not parent then running = false end end)

-- Gaara não se mexe
humanoid.WalkSpeed = 0
humanoid.AutoRotate = false -- Desligar rotação automática para controlar manualmente

-- Animation system
local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end
local animTracks: { [string]: AnimationTrack } = {}

local function loadAnimationByName(name: string): AnimationTrack?
	if animTracks[name] then return animTracks[name] end
	local folder = enemyModel:FindFirstChild("Animations")
	local animObj: Animation? = nil
	if folder then
		animObj = folder:FindFirstChild(name)
		if animObj and not animObj:IsA("Animation") then animObj = nil end
	end
	if animObj and animator then
		local track = animator:LoadAnimation(animObj)
		animTracks[name] = track
		return track
	end
	return nil
end

local function playAnim(name: string, fade: number?, weight: number?, speed: number?)
	local tr = loadAnimationByName(name)
	if tr then
		-- Esperar até a animação estar carregada
		if tr.Length == 0 then
			local timeout = 0
			while tr.Length == 0 and timeout < 50 do
				task.wait(0.05)
				timeout = timeout + 1
			end
		end
		tr:Play(fade or 0.1, weight or 1.0, speed or 1.0)
		return tr
	end
end

-- Pré-carregar animações no início
task.spawn(function()
	task.wait(0.5) -- Esperar um pouco após spawn
	loadAnimationByName("Sand Coffin")
	loadAnimationByName("Sand Shield")
	loadAnimationByName("Sand Shield Off")
	loadAnimationByName("Sand Wave")
	print("[Gaara] Animações pré-carregadas")
end)

-- Pause utility
local function isPaused()
	return ReplicatedStorage:GetAttribute("GamePaused") == true
end

local function pauseAwareWait(seconds)
	local remaining = seconds
	while remaining > 0 and running do
		if isPaused() then
			task.wait(0.05)
		else
			local dt = math.min(0.05, remaining)
			task.wait(dt)
			remaining -= dt
		end
	end
end

-- Targeting
local function getNearestPlayer(maxRange)
	local best, bestDist
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if hum and r and hum.Health > 0 then
			local d = (r.Position - root.Position).Magnitude
			if (not maxRange or d <= maxRange) and (not bestDist or d < bestDist) then
				bestDist = d
				best = r
			end
		end
	end
	return best, bestDist
end

-- Sistema de rotação contínua para olhar o player
task.spawn(function()
	while running do
		if isPaused() then
			task.wait(0.05)
			continue
		end
		
		local targetRoot = getNearestPlayer()
		if targetRoot and root and root.Parent then
			local direction = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1) -- Ignorar Y
			if direction.Magnitude > 0.1 then
				local lookCFrame = CFrame.lookAt(root.Position, root.Position + direction)
				root.CFrame = lookCFrame
			end
		end
		
		task.wait(0.1)
	end
end)

-- ========================================
-- SAND SHIELD
-- ========================================
local function activateSandShield()
	if shieldUsed or shieldActive then return end
	shieldUsed = true
	shieldActive = true
	
	print("[Gaara] Ativando Sand Shield")
	
	-- Procurar SandBall
	local enemysFolder = ReplicatedStorage:FindFirstChild("Enemys")
	local sandBallTemplate = enemysFolder and enemysFolder:FindFirstChild("SandBall")
	if not sandBallTemplate or not sandBallTemplate:IsA("BasePart") then
		warn("[Gaara] SandBall não encontrado para Shield!")
		return
	end
	
	-- Tocar animação Sand Shield
	local shieldTrack = playAnim("Sand Shield", 0.2, 1.0, 1.0)
	if not shieldTrack then
		warn("[Gaara] Animação 'Sand Shield' não encontrada!")
		return
	end
	
	-- Criar shield ball à volta do Gaara
	shieldBall = sandBallTemplate:Clone()
	shieldBall.Parent = workspace
	shieldBall.Anchored = true
	shieldBall.CanCollide = false
	shieldBall.CanTouch = false
	shieldBall.CanQuery = false
	shieldBall.CFrame = root.CFrame
	shieldBall.Transparency = 1 -- Começa invisível
	
	-- Aumentar tamanho do shield (maior que o Gaara)
	local originalSize = shieldBall.Size
	shieldBall.Size = originalSize * 2.5
	
	-- Criar BillboardGui para mostrar HP do shield
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "ShieldHealthBar"
	billboardGui.Size = UDim2.new(4, 0, 0.5, 0)
	billboardGui.StudsOffset = Vector3.new(0, 3, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Parent = shieldBall
	
	-- Background da barra
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.Position = UDim2.new(0, 0, 0, 0)
	background.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	background.BorderSizePixel = 2
	background.BorderColor3 = Color3.fromRGB(0, 0, 0)
	background.Parent = billboardGui
	
	-- Barra de HP
	local healthBar = Instance.new("Frame")
	healthBar.Name = "HealthBar"
	healthBar.Size = UDim2.new(1, 0, 1, 0)
	healthBar.Position = UDim2.new(0, 0, 0, 0)
	healthBar.BackgroundColor3 = Color3.fromRGB(194, 178, 128) -- Cor de areia
	healthBar.BorderSizePixel = 0
	healthBar.Parent = background
	
	-- Texto do HP
	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.Text = "Shield: " .. SHIELD_HP
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.TextStrokeTransparency = 0.5
	hpText.TextScaled = true
	hpText.Font = Enum.Font.GothamBold
	hpText.Parent = background
	
	-- Fade in do shield (0 -> 0.4 transparency em 1 segundo)
	task.spawn(function()
		local FADE_DURATION = 1.0
		local startTime = os.clock()
		while os.clock() - startTime < FADE_DURATION do
			local alpha = (os.clock() - startTime) / FADE_DURATION
			shieldBall.Transparency = 1 - (alpha * 0.6) -- De 1.0 para 0.4
			
			-- Seguir Gaara
			if root and root.Parent and shieldBall and shieldBall.Parent then
				shieldBall.CFrame = root.CFrame
			end
			
			task.wait()
		end
		
		-- Garantir transparência final
		if shieldBall and shieldBall.Parent then
			shieldBall.Transparency = 0.4
		end
	end)
	
	-- Sistema de seguir Gaara continuamente
	local RunService = game:GetService("RunService")
	local followConnection
	followConnection = RunService.Heartbeat:Connect(function()
		if shieldBall and shieldBall.Parent and root and root.Parent and shieldActive then
			shieldBall.CFrame = root.CFrame
		else
			if followConnection then
				followConnection:Disconnect()
			end
		end
	end)
	
	-- Ativar shield HP imediatamente (não esperar evento)
	currentShieldHP = SHIELD_HP
	enemyModel:SetAttribute("ShieldHP", currentShieldHP)
	print("[Gaara] Shield HP ativado:", currentShieldHP)
	
	-- Conectar evento "shield" (opcional, para efeitos visuais extras)
	local ok, sig = pcall(function() return shieldTrack:GetMarkerReachedSignal("shield") end)
	if ok and sig then
		sig:Connect(function()
			print("[Gaara] Evento 'shield' disparado na animação")
		end)
	else
		print("[Gaara] Marker 'shield' não encontrado (usando ativação imediata)")
	end
end

local function deactivateSandShield()
	if not shieldActive then return end
	shieldActive = false
	currentShieldHP = 0
	enemyModel:SetAttribute("ShieldHP", 0)
	
	print("[Gaara] Desativando Sand Shield")
	
	-- Tocar animação Sand Shield Off
	local shieldOffTrack = playAnim("Sand Shield Off", 0.2, 1.0, 1.0)
	
	-- Destruir shield ball
	if shieldBall and shieldBall.Parent then
		-- Fade out rápido
		local fadeTween = TweenService:Create(
			shieldBall,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)
		fadeTween:Play()
		fadeTween.Completed:Connect(function()
			if shieldBall and shieldBall.Parent then
				shieldBall:Destroy()
			end
			shieldBall = nil
		end)
	end
	
	-- Esperar animação Off terminar
	if shieldOffTrack then
		local animLength = shieldOffTrack.Length or 1.0
		pauseAwareWait(animLength)
		if shieldOffTrack.IsPlaying then
			shieldOffTrack:Stop(0.2)
		end
	end
end

-- Sistema de monitoramento de HP para ativar shield
task.spawn(function()
	while running do
		if isPaused() then
			task.wait(0.05)
			continue
		end
		
		-- Verificar se chegou aos 50% HP
		if not shieldUsed and humanoid and humanoid.Health > 0 then
			local healthPercent = humanoid.Health / humanoid.MaxHealth
			if healthPercent <= SHIELD_ACTIVATION_PERCENT then
				activateSandShield()
			end
		end
		
		task.wait(0.2)
	end
end)

-- Sistema de dano do shield (interceta dano do Gaara)
local lastGaaraHealth = humanoid.Health
humanoid.HealthChanged:Connect(function(newHealth)
	print("[Gaara] HealthChanged - shieldActive:", shieldActive, "currentShieldHP:", currentShieldHP, "lastHealth:", lastGaaraHealth, "newHealth:", newHealth)
	
	if not shieldActive or currentShieldHP <= 0 then 
		lastGaaraHealth = newHealth
		return 
	end
	
	local damage = lastGaaraHealth - newHealth
	if damage > 0 then -- Tomou dano
		print("[Gaara] Dano detectado:", damage)
		
		-- Absorver dano no shield
		local damageToShield = math.min(damage, currentShieldHP)
		currentShieldHP = currentShieldHP - damageToShield
		enemyModel:SetAttribute("ShieldHP", currentShieldHP)
		
		-- Restaurar HP do Gaara (shield absorveu)
		humanoid.Health = lastGaaraHealth
		lastGaaraHealth = humanoid.Health
		
		print("[Gaara] Shield absorveu", damageToShield, "dano. Shield HP restante:", currentShieldHP)
		
		-- Atualizar barra de HP visual
		if shieldBall and shieldBall.Parent then
			local gui = shieldBall:FindFirstChild("ShieldHealthBar")
			if gui then
				local background = gui:FindFirstChild("Background")
				if background then
					local healthBar = background:FindFirstChild("HealthBar")
					local hpText = background:FindFirstChild("HPText")
					if healthBar then
						local hpPercent = math.max(0, currentShieldHP / SHIELD_HP)
						healthBar.Size = UDim2.new(hpPercent, 0, 1, 0)
					end
					if hpText then
						hpText.Text = "Shield: " .. math.floor(math.max(0, currentShieldHP))
					end
				end
			end
		end
		
		-- Shield destruído?
		if currentShieldHP <= 0 then
			deactivateSandShield()
		end
	else
		lastGaaraHealth = newHealth
	end
end)

-- ========================================
-- SAND COFFIN
-- ========================================
local lastCoffin = 0

local function trySandCoffin(now)
	if now - lastCoffin < COFFIN_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	
	local targetRoot, dist = getNearestPlayer(COFFIN_RANGE)
	if not targetRoot or not dist then return end
	lastCoffin = now
	
	print("[Gaara] Sand Coffin iniciado no alvo:", targetRoot.Parent.Name)
	
	-- Procurar SandBall na pasta Enemys (BasePart)
	local enemysFolder = ReplicatedStorage:FindFirstChild("Enemys")
	print("[Gaara] Enemys folder:", enemysFolder)
	local sandBallTemplate = enemysFolder and enemysFolder:FindFirstChild("SandBall")
	print("[Gaara] SandBall template:", sandBallTemplate)
	if not sandBallTemplate or not sandBallTemplate:IsA("BasePart") then
		warn("[Gaara] SandBall não encontrado em ReplicatedStorage.Enemys!")
		if enemysFolder then
			print("[Gaara] Conteúdo da pasta Enemys:")
			for _, child in ipairs(enemysFolder:GetChildren()) do
				print("  -", child.Name, child.ClassName)
			end
		end
		return
	end
	print("[Gaara] SandBall encontrado! Clonando...")
	
	-- Tocar animação Sand Coffin
	local coffinTrack = playAnim("Sand Coffin", 0.1, 1.0, 1.0)
	print("[Gaara] Animation track:", coffinTrack)
	if not coffinTrack then
		warn("[Gaara] Animação 'Sand Coffin' não encontrada!")
		local animFolder = enemyModel:FindFirstChild("Animations")
		if animFolder then
			print("[Gaara] Conteúdo da pasta Animations:")
			for _, child in ipairs(animFolder:GetChildren()) do
				print("  -", child.Name, child.ClassName)
			end
		else
			print("[Gaara] Pasta Animations não existe!")
		end
		return
	end
	print("[Gaara] Animação carregada, tocando...")
	
	-- Clonar SandBall e posicionar no player
	local sandBall = sandBallTemplate:Clone()
	sandBall.Parent = workspace
	sandBall.Anchored = true
	sandBall.CanCollide = false
	sandBall.Transparency = 0 -- Visível desde o início
	
	-- Levantar player ligeiramente
	local LIFT_HEIGHT = 3
	local playerChar = targetRoot.Parent
	local playerHum = playerChar and playerChar:FindFirstChildOfClass("Humanoid")
	local originalPlayerCFrame = targetRoot.CFrame
	
	-- Congelar player (preso na bola)
	if playerHum then
		playerHum.WalkSpeed = 0
		playerHum.JumpPower = 0
		playerHum.AutoRotate = false
	end
	if targetRoot then
		targetRoot.Anchored = true
	end
	
	-- Posicionar bola e player levantados
	local liftedPosition = originalPlayerCFrame.Position + Vector3.new(0, LIFT_HEIGHT, 0)
	sandBall.Position = liftedPosition
	if targetRoot then
		targetRoot.CFrame = CFrame.new(liftedPosition)
	end
	
	-- Sistema de seguir player (manter bola e player juntos)
	local followConnection
	followConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if sandBall and sandBall.Parent and targetRoot and targetRoot.Parent then
			sandBall.Position = targetRoot.Position
		else
			if followConnection then
				followConnection:Disconnect()
			end
		end
	end)
	
	-- Conectar evento "hit" na animação para dar dano e implodir
	local damageDealt = false
	local ok, sig = pcall(function() return coffinTrack:GetMarkerReachedSignal("hit") end)
	if ok and sig then
		sig:Connect(function()
			if damageDealt then return end
			damageDealt = true
			print("[Gaara] Evento 'hit' - Sand Coffin implodindo e causando dano")
			
			-- Aplicar dano ao player
			if targetRoot and targetRoot.Parent then
				local char = targetRoot.Parent
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
					Damage.Apply(hum, COFFIN_DAMAGE * waveMult)
				end
			end
			
			-- Implodir bola (encolher até desaparecer)
			local IMPLODE_DURATION = 0.3
			
			local implodeTween = TweenService:Create(
				sandBall,
				TweenInfo.new(IMPLODE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 }
			)
			
			implodeTween:Play()
			
			-- Descongelar player
			if followConnection then
				followConnection:Disconnect()
			end
			
			if targetRoot and targetRoot.Parent then
				targetRoot.Anchored = false
			end
			
			if playerHum and playerHum.Parent then
				playerHum.WalkSpeed = 16
				playerHum.JumpPower = 50
				playerHum.AutoRotate = true
			end
			
			-- Destruir bola após implosão
			task.delay(IMPLODE_DURATION, function()
				if sandBall and sandBall.Parent then
					sandBall:Destroy()
				end
			end)
		end)
	else
		warn("[Gaara] Marker 'hit' não encontrado na animação Sand Coffin!")
		-- Fallback: destruir bola depois da animação
		task.delay(coffinTrack.Length or 2.0, function()
			if sandBall and sandBall.Parent then
				sandBall:Destroy()
			end
		end)
	end
	
	-- Esperar animação completa
	local animLength = coffinTrack.Length or 2.0
	pauseAwareWait(animLength)
	
	if coffinTrack and coffinTrack.IsPlaying then
		coffinTrack:Stop(0.2)
	end
	
	-- Garantir que player foi descongelado e bola removida
	if followConnection then
		followConnection:Disconnect()
	end
	
	if targetRoot and targetRoot.Parent then
		targetRoot.Anchored = false
	end
	
	if playerHum and playerHum.Parent then
		playerHum.WalkSpeed = 16
		playerHum.JumpPower = 50
		playerHum.AutoRotate = true
	end
	
	if sandBall and sandBall.Parent then
		sandBall:Destroy()
	end
end

-- ========================================
-- SAND WAVE
-- ========================================
local lastWave = 0

local function trySandWave(now)
	if now - lastWave < WAVE_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	
	local targetRoot = getNearestPlayer(100)
	if not targetRoot then return end
	lastWave = now
	
	print("[Gaara] Sand Wave iniciado")
	
	-- Procurar TsunamiWave na pasta Enemys
	local enemysFolder = ReplicatedStorage:FindFirstChild("Enemys")
	local tsunamiTemplate = enemysFolder and enemysFolder:FindFirstChild("TsunamiWave")
	if not tsunamiTemplate then
		warn("[Gaara] TsunamiWave não encontrado em ReplicatedStorage.Enemys!")
		return
	end
	
	-- Tocar animação Sand Wave
	local waveTrack = playAnim("Sand Wave", 0.1, 1.0, 1.0)
	if not waveTrack then
		warn("[Gaara] Animação 'Sand Wave' não encontrada!")
		return
	end
	
	print("[Gaara] Animação Sand Wave tocando")
	
	-- Função para lançar uma wave
	local function fireWave()
		print("[Gaara] Disparando tsunami wave")
		
		-- Clonar tsunami wave
		local wave = tsunamiTemplate:Clone()
		wave.Parent = workspace
		
		-- Se for um Model, configurar todas as partes
		if wave:IsA("Model") then
			for _, part in ipairs(wave:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
				end
			end
		elseif wave:IsA("BasePart") then
			wave.Anchored = true
			wave.CanCollide = false
		end
		
		-- Posicionar no Gaara
		local startPos = root.Position
		local direction = root.CFrame.LookVector
		
		-- Posicionar o Model/Part com rotação de -90º
		local orientation = CFrame.new(startPos, startPos + direction) * CFrame.Angles(0, math.rad(-90), 0)
		
		if wave:IsA("Model") then
			wave:PivotTo(orientation)
		else
			wave.CFrame = orientation
		end
		
		print("[Gaara] Wave criada em:", startPos, "direção:", direction)
		
		-- Mover a wave para frente rapidamente
		local RunService = game:GetService("RunService")
		local startTime = os.clock()
		local connection
		
		-- Lista de players já atingidos por esta wave
		local hitPlayers = {}
		
		connection = RunService.Heartbeat:Connect(function(dt)
			if not wave or not wave.Parent then
				if connection then connection:Disconnect() end
				return
			end
			
			-- Verificar tempo de vida
			if os.clock() - startTime > WAVE_LIFETIME then
				print("[Gaara] Wave destruída por timeout")
				wave:Destroy()
				if connection then connection:Disconnect() end
				return
			end
			
			-- Mover wave para frente (sempre na mesma direção)
			local currentCF
			if wave:IsA("Model") then
				currentCF = wave:GetPivot()
				wave:PivotTo(currentCF + (direction * WAVE_SPEED * dt))
			else
				currentCF = wave.CFrame
				wave.CFrame = currentCF + (direction * WAVE_SPEED * dt)
			end
			
			-- Detectar colisões com players (usando magnitude simples)
			local wavePos = wave:IsA("Model") and wave:GetPivot().Position or wave.Position
			
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				if char and not hitPlayers[char] then
					local hum = char:FindFirstChildOfClass("Humanoid")
					local charRoot = char:FindFirstChild("HumanoidRootPart")
					
					if hum and hum.Health > 0 and charRoot then
						local distance = (wavePos - charRoot.Position).Magnitude
						
						-- Se player está perto da wave (dentro do raio)
						local waveRadius = 10 -- Raio de detecção padrão
						if wave:IsA("Model") and wave.PrimaryPart then
							waveRadius = wave.PrimaryPart.Size.X / 2 + 3
						elseif wave:IsA("BasePart") then
							waveRadius = wave.Size.X / 2 + 3
						end
						
						if distance < waveRadius then
							hitPlayers[char] = true
							
							-- Aplicar dano
							local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
							Damage.Apply(hum, WAVE_DAMAGE * waveMult)
							print("[Gaara] Sand Wave atingiu:", char.Name, "distância:", distance)
						end
					end
				end
			end
		end)
	end
	
	-- Conectar eventos wave1, wave2, wave3 na animação
	local wavesFired = 0
	for i = 1, 3 do
		local eventName = "wave" .. i
		local ok, sig = pcall(function() return waveTrack:GetMarkerReachedSignal(eventName) end)
		if ok and sig then
			sig:Connect(function()
				print("[Gaara] Evento '" .. eventName .. "' disparado")
				fireWave()
				wavesFired = wavesFired + 1
			end)
		else
			warn("[Gaara] Marker '" .. eventName .. "' não encontrado na animação Sand Wave!")
		end
	end
	
	-- Esperar animação completa
	local animLength = waveTrack.Length or 3.0
	pauseAwareWait(animLength)
	
	if waveTrack and waveTrack.IsPlaying then
		waveTrack:Stop(0.2)
	end
	
	print("[Gaara] Sand Wave concluído. Waves disparadas:", wavesFired)
end

-- ========================================
-- ABILITY SCHEDULER
-- ========================================
task.spawn(function()
	while running do
		if isPaused() then
			task.wait(0.05)
			continue
		end
		
		local now = os.clock()
		if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then
			task.wait(0.1)
			continue
		end
		
		-- Tentar habilidades
		trySandCoffin(now)
		trySandWave(now)
		
		task.wait(0.2)
	end
end)

return true
