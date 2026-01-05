-- ZabuzaSwordControl.server.lua
-- Listens to animation keyframe markers on Zabuza to detach/reattach the sword.
-- Marker names supported: "SwordDown"/"SwordUp" and also "detach"/"attach", "dettatch"/"attatch".

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- Identify Zabuza models
local USE_TAG = false
local ZABUZA_TAG = "Enemy_Zabuza"
local ZABUZA_NAME = "Zabuza"

local function getHumanoid(model)
	return model:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function getRightHand(model)
	-- Procurar variações de nome do braço direito
	local candidates = {
		model:FindFirstChild("Right Arm", true),
		model:FindFirstChild("RightHand", true),
		model:FindFirstChild("RightArm", true),
	}
	for _, c in ipairs(candidates) do
		if c and c:IsA("BasePart") then 
			print("[ZabuzaSwordControl] Right Arm encontrado:", c:GetFullName())
			return c 
		end
	end
	warn("[ZabuzaSwordControl] Right Arm NÃO encontrado no modelo")
	return nil
end

local function findSwordHandle(model)
	local candidates = {
		model:FindFirstChild("Zabuza's Sword", true),
		model:FindFirstChild("Sword", true),
		model:FindFirstChild("Katana", true),
		model:FindFirstChild("Weapon", true),
	}
	for _, c in ipairs(candidates) do
		if c then
			print("[ZabuzaSwordControl] Candidato de espada encontrado:", c.Name, c.ClassName)
			if c:IsA("Accessory") then
				local h = c:FindFirstChild("Handle")
				if h and h:IsA("BasePart") then 
					print("[ZabuzaSwordControl] Espada Handle encontrado:", h:GetFullName())
					return h 
				end
			elseif c:IsA("Model") then
				local h = c:FindFirstChild("Handle") or c:FindFirstChildWhichIsA("BasePart")
				if h and h:IsA("BasePart") then 
					print("[ZabuzaSwordControl] Espada Handle encontrado:", h:GetFullName())
					return h 
				end
			elseif c:IsA("BasePart") then
				print("[ZabuzaSwordControl] Espada BasePart encontrado:", c:GetFullName())
				return c
			end
		end
	end
	local h = model:FindFirstChild("Handle", true)
	if h and h:IsA("BasePart") then 
		print("[ZabuzaSwordControl] Espada Handle genérico encontrado:", h:GetFullName())
		return h 
	end
	warn("[ZabuzaSwordControl] Espada NÃO encontrada no modelo")
	return nil
end

local function ensureGripAttachments(rightHand, handle)
	local handAtt = rightHand:FindFirstChild("RightGripAttachment")
	if not handAtt then
		handAtt = Instance.new("Attachment")
		handAtt.Name = "RightGripAttachment"
		-- Don't impose an arbitrary offset; let current relative orientation be preserved via Motor6D C0/C1
		handAtt.CFrame = CFrame.new()
		handAtt.Parent = rightHand
	end
	local handleAtt = handle:FindFirstChild("RightGripAttachment") or handle:FindFirstChild("HandleAttachment")
	if not handleAtt then
		handleAtt = Instance.new("Attachment")
		handleAtt.Name = "RightGripAttachment"
		-- Identity; current pose will be captured into Motor6D offsets instead
		handleAtt.CFrame = CFrame.new()
		handleAtt.Parent = handle
	end
	return handAtt, handleAtt
end

local function destroyDirectWelds(a, b)
	for _, d in ipairs(a:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") then
			local ok = (d.Part0 == a and d.Part1 == b) or (d.Part0 == b and d.Part1 == a)
			if ok then d:Destroy() end
		end
	end
	for _, d in ipairs(b:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") then
			local ok = (d.Part0 == a and d.Part1 == b) or (d.Part0 == b and d.Part1 == a)
			if ok then d:Destroy() end
		end
	end
end

local function ensureSwordGripMotor(model, rightHand, handle)
	local handAtt, handleAtt = ensureGripAttachments(rightHand, handle)
	-- Procurar Motor6D existente no Right Arm
	local motor = nil
	for _, child in ipairs(rightHand:GetChildren()) do
		if child:IsA("Motor6D") then
			print("[ZabuzaSwordControl] Motor6D encontrado:", child.Name, "Part0:", child.Part0 and child.Part0.Name, "Part1:", child.Part1 and child.Part1.Name)
			-- Se já está conectado ao handle, usar esse
			if child.Part1 == handle or child.Name == "SwordGrip" or child.Name:lower():find("sword") then
				motor = child
				break
			end
		end
	end
	
	if motor and motor:IsA("Motor6D") then
		motor.Part0 = rightHand
		motor.Part1 = handle
		local rel = rightHand.CFrame:ToObjectSpace(handle.CFrame)
		motor.C0 = rel
		motor.C1 = CFrame.new()
		motor.Name = "SwordGrip"
		print("[ZabuzaSwordControl] Motor6D reusado e configurado:", motor.Name)
		return motor
	end
	
	-- Criar novo Motor6D
	local rel = rightHand.CFrame:ToObjectSpace(handle.CFrame)
	destroyDirectWelds(rightHand, handle)
	motor = Instance.new("Motor6D")
	motor.Name = "SwordGrip"
	motor.Part0 = rightHand
	motor.Part1 = handle
	motor.C0 = rel
	motor.C1 = CFrame.new()
	motor.Parent = rightHand
	print("[ZabuzaSwordControl] Novo Motor6D criado:", motor.Name)
	return motor
end

local function raycastToGround(fromPos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local result = Workspace:Raycast(fromPos, Vector3.new(0, -200, 0), params)
	return result and result.Position or (fromPos - Vector3.new(0, 5, 0))
end

local stateByModel = setmetatable({}, { __mode = "k" })

local function detachSword(model)
	print("[ZabuzaSwordControl] 🔴 detachSword CHAMADO para", model.Name)
	local st = stateByModel[model]
	if not st then 
		warn("[ZabuzaSwordControl] ❌ State não encontrado!")
		return 
	end
	if st.grip and st.handle then
		print("[ZabuzaSwordControl] Motor6D Enabled antes:", st.grip.Enabled)
		-- Disable Motor6D (espada sai da mão)
		st.grip.Enabled = false
		st.handle.Anchored = true
		print("[ZabuzaSwordControl] Motor6D Enabled depois:", st.grip.Enabled)
		local root = getRoot(model)
		if root then
			-- Posiciona a espada na frente do Zabuza (cravada no chão)
			local forward = root.CFrame.LookVector
			local dropPos = st.handle.Position + forward * 2.0
			local gpos = raycastToGround(dropPos, { model })
			-- Orientação: espada vertical cravada no chão com PONTA PARA BAIXO (180 graus rotação)
			local yaw = math.atan2(forward.X, forward.Z)
			st.handle.CFrame = CFrame.new(gpos) * CFrame.Angles(math.rad(180), yaw, 0)
			print("[ZabuzaSwordControl] Espada posicionada em:", gpos)
		end
		st.detached = true
		print("[ZabuzaSwordControl] ✅ Espada solta (Motor6D disabled)")
	else
		warn("[ZabuzaSwordControl] ❌ Grip ou Handle não encontrado!")
	end
end

local function reattachSword(model)
	local st = stateByModel[model]
	if not st then return end
	if st.grip and st.handle then
		-- Enable Motor6D (espada volta para a mão)
		st.handle.Anchored = false
		st.grip.Enabled = true
		st.detached = false
		print("[ZabuzaSwordControl] Espada recuperada (Motor6D enabled)")
	end
end

local function hookAnimator(model, animator)
	local rightHand = getRightHand(model)
	local handle = findSwordHandle(model)
	if not rightHand or not handle then 
		warn("[ZabuzaSwordControl] Não encontrou RightHand ou Espada para", model.Name)
		return 
	end
	local grip = ensureSwordGripMotor(model, rightHand, handle)
	stateByModel[model] = {
		rightHand = rightHand,
		handle = handle,
		grip = grip,
		detached = false,
	}
	print("[ZabuzaSwordControl] Setup completo para", model.Name, "- Motor6D:", grip.Name)
	
	animator.AnimationPlayed:Connect(function(track)
		print("[ZabuzaSwordControl] Animação tocando:", track.Name or "Unknown", "Animation ID:", track.Animation and track.Animation.AnimationId or "N/A")
		
		-- Listar TODOS os markers disponíveis na animação (debug)
		task.spawn(function()
			task.wait(0.1) -- esperar track carregar
			local markers = {}
			local ok = pcall(function()
				local markerNames = track:GetMarkerReachedSignal(""):Connect(function() end)
				markerNames:Disconnect()
			end)
			-- Tentar descobrir markers testando nomes comuns
			local testNames = {"dettach", "detach", "attach", "dragon", "fire", "start", "end", "impact"}
			for _, testName in ipairs(testNames) do
				local success = pcall(function() 
					track:GetMarkerReachedSignal(testName)
				end)
				if success then
					table.insert(markers, testName)
				end
			end
			if #markers > 0 then
				print("[ZabuzaSwordControl] 📋 Markers encontrados na animação:", table.concat(markers, ", "))
			end
		end)
		
		-- Eventos de detach (largar espada)
		local detachNames = {"dettach", "detach", "SwordDown"}
		for _, name in ipairs(detachNames) do
			local ok, sig = pcall(function() return track:GetMarkerReachedSignal(name) end)
			if ok and sig then 
				print("[ZabuzaSwordControl] Marker '" .. name .. "' encontrado e conectado na animação:", track.Name or "Unknown")
				sig:Connect(function()
					print("[ZabuzaSwordControl] 🔴🔴🔴 EVENTO '" .. name .. "' ACIONADO - largando espada 🔴🔴🔴")
					detachSword(model)
				end)
			else
				print("[ZabuzaSwordControl] ⚠️ Marker '" .. name .. "' NÃO encontrado nesta animação")
			end
		end
		
		-- Eventos de attach (pegar espada)
		local attachNames = {"attach", "attatch", "SwordUp"}
		for _, name in ipairs(attachNames) do
			local ok, sig = pcall(function() return track:GetMarkerReachedSignal(name) end)
			if ok and sig then 
				print("[ZabuzaSwordControl] Marker '" .. name .. "' encontrado e conectado")
				sig:Connect(function()
					print("[ZabuzaSwordControl] ✅ Evento '" .. name .. "' ACIONADO - pegando espada")
					reattachSword(model)
				end)
			else
				print("[ZabuzaSwordControl] ⚠️ Marker '" .. name .. "' NÃO encontrado nesta animação")
			end
		end
	end)
end

local function trySetup(model)
	if not model or not model:IsDescendantOf(Workspace) then return end
	local hum = getHumanoid(model)
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	hookAnimator(model, animator)
end

local function isZabuza(model)
	if not model:IsA("Model") then return false end
	if USE_TAG then
		return CollectionService:HasTag(model, ZABUZA_TAG)
	end
	return model.Name == ZABUZA_NAME
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	if isZabuza(inst) then trySetup(inst) end
end

Workspace.DescendantAdded:Connect(function(inst)
	if isZabuza(inst) then trySetup(inst) end
end)
