-- WaveManager
-- Server-only module to control enemy waves, spawning, and simple scaling hooks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local WaveManager = {}
WaveManager.__index = WaveManager

-- Helper: shallow copy table
local function cloneTable(t)
    local n = {}
    for k, v in pairs(t) do n[k] = v end
    return n
end

-- Helper: get spawn points
local function getDefaultSpawnPoints()
    local spawns = {}
    local folder = workspace:FindFirstChild("EnemySpawns")
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("BasePart") then
                table.insert(spawns, child)
            elseif child:IsA("Model") then
                -- Procurar PrimaryPart ou primeiro BasePart descendente
                local primary = child.PrimaryPart
                if not primary then
                    for _, d in ipairs(child:GetDescendants()) do
                        if d:IsA("BasePart") then primary = d break end
                    end
                end
                if primary then table.insert(spawns, primary) end
            end
        end
    end
    if #spawns == 0 then
        local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
        if spawnLocation then
            table.insert(spawns, spawnLocation)
        end
    end
    return spawns
end

-- Helper: resolve an enemy template Instance by id
local function resolveEnemyTemplate(id)
    -- Try exact name under ReplicatedStorage.Enemys (without accents to match folder)
    local enemiesFolder = ReplicatedStorage:FindFirstChild("Enemys")
    if enemiesFolder then
        -- Exact match
        local exact = enemiesFolder:FindFirstChild(id)
        if exact then return exact end
        -- Try match ignoring spaces / underscore variants
        local normId = id:gsub("%s+", ""):lower()
        for _, child in ipairs(enemiesFolder:GetChildren()) do
            local normName = child.Name:gsub("%s+", ""):lower()
            if normName == normId then
                return child
            end
        end
    end
    return nil
end

-- Create a very simple dummy enemy if no template is found
local function createFallbackEnemy(name)
    local model = Instance.new("Model")
    model.Name = name or "Enemy"

    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size = Vector3.new(2, 2, 1)
    root.Anchored = false
    root.TopSurface = Enum.SurfaceType.Smooth
    root.BottomSurface = Enum.SurfaceType.Smooth
    root.Parent = model

    local humanoid = Instance.new("Humanoid")
    humanoid.Name = "Humanoid"
    humanoid.Parent = model

    return model
end

-- Clone and place enemy at a CFrame
local function spawnEnemyFromTemplate(template, groundCFrame)
    local enemy
    if template then
        local modelToClone
        if template:IsA("Model") then
            modelToClone = template
        elseif template:IsA("Folder") then
            -- Find a model inside the folder
            for _, ch in ipairs(template:GetChildren()) do
                if ch:IsA("Model") then
                    modelToClone = ch
                    if ch.Name == "Enemy" then break end
                end
            end
        end
        if modelToClone then
            enemy = modelToClone:Clone()
        else
            enemy = createFallbackEnemy(template.Name)
        end
    else
        enemy = createFallbackEnemy("Enemy")
    end

    enemy.Parent = workspace
    -- Compute an upward offset so the bottom of the model sits on the ground
    local _, size = enemy:GetBoundingBox()
    local upOffset = Vector3.new(0, (size and size.Y or 4) * 0.5, 0)
    local targetCFrame = groundCFrame + upOffset
    -- Prefer modern PivotTo; fall back to PrimaryPart placement
    local ok = pcall(function()
        enemy:PivotTo(targetCFrame)
    end)
    if not ok then
        local primary = enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart")
        if not enemy.PrimaryPart and primary then
            enemy.PrimaryPart = primary
        end
        if enemy.PrimaryPart then
            enemy:SetPrimaryPartCFrame(targetCFrame)
        end
    end
    return enemy
end

-- Try to attach an AI Script from ReplicatedStorage.Enemys[id] if the spawned model doesn't already include one
local function attachEnemyAI(enemy, enemyId)
    if not enemy or not enemyId then return end
    if enemy:FindFirstChild("AI") then return end
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local enemiesFolder = ReplicatedStorage:FindFirstChild("Enemys")
    local enemyFolder = enemiesFolder and enemiesFolder:FindFirstChild(enemyId)
    if not enemyFolder then return end
    local candidate
    -- Prefer any descendant Script named "AI"
    for _, d in ipairs(enemyFolder:GetDescendants()) do
        local ok, isScript = pcall(function() return d:IsA("Script") end)
        if ok and isScript and d.Name == "AI" then
            candidate = d
            break
        end
    end
    if not candidate then
        -- Fallback: direct child named AI
        local child = enemyFolder:FindFirstChild("AI")
        local ok, isScript = child and pcall(function() return child:IsA("Script") end)
        if ok and isScript then
            candidate = child
        end
    end
    if candidate then
        local clone = candidate:Clone()
        clone.Parent = enemy
    end
end

-- Apply basic scaling (health, walkspeed) if available
local function applyEnemyScaling(enemy, scale)
    scale = scale or {}
    local humanoid = enemy:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if scale.HealthMultiplier then
            local base = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 100
            humanoid.MaxHealth = base * scale.HealthMultiplier
            humanoid.Health = humanoid.MaxHealth
        end
        if scale.WalkSpeed then
            humanoid.WalkSpeed = scale.WalkSpeed
        end
    end
    -- Store attributes for downstream AI/damage systems
    for k, v in pairs(scale) do
        if typeof(v) ~= "table" then
            enemy:SetAttribute(k, v)
        end
    end
end

-- Ensure enemies are non-colliding to avoid pushing players/clones
local function disableEnemyCollisions(enemy)
    for _, d in ipairs(enemy:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = true -- keep query ON so raycasts can hit
            d.Massless = true
        end
    end
end

-- Try to get base stats ModuleScript for an enemy id or template
local function getEnemyBaseStats(enemyId, template)
    -- Prefer a child ModuleScript named "Stats" under the template
    if template then
        local statsModule = template:FindFirstChild("Stats")
        if statsModule and statsModule:IsA("ModuleScript") then
            local ok, stats = pcall(require, statsModule)
            if ok and type(stats) == "table" then return stats end
        end
    end
    -- Fallback: look under ReplicatedStorage.Enemys[enemyId].Stats
    local enemiesFolder = ReplicatedStorage:FindFirstChild("Enemys")
    local enemyFolder = enemiesFolder and enemiesFolder:FindFirstChild(enemyId)
    if enemyFolder then
        local statsModule = enemyFolder:FindFirstChild("Stats")
        if statsModule and statsModule:IsA("ModuleScript") then
            local ok, stats = pcall(require, statsModule)
            if ok and type(stats) == "table" then return stats end
        end
    end
    return nil
end

local function applyEnemyBaseStats(enemy, baseStats)
    if not baseStats then return end
    local humanoid = enemy:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if typeof(baseStats.Health) == "number" then
            humanoid.MaxHealth = baseStats.Health
            humanoid.Health = baseStats.Health
            -- Store unscaled base health for AI / debugging / recomputation
            pcall(function()
                if enemy:GetAttribute("BaseHealth") == nil then
                    enemy:SetAttribute("BaseHealth", baseStats.Health)
                end
            end)
        end
        local move = baseStats.MoveSpeed or baseStats.WalkSpeed
        if typeof(move) == "number" then
            humanoid.WalkSpeed = move
        end
    end
    if typeof(baseStats.Damage) == "number" then
        enemy:SetAttribute("Damage", baseStats.Damage) -- legacy direct damage value (will be overwritten by scaling below)
        pcall(function()
            if enemy:GetAttribute("BaseDamage") == nil then
                enemy:SetAttribute("BaseDamage", baseStats.Damage)
            end
        end)
    end
    if typeof(baseStats.XPDrop) == "number" then
        enemy:SetAttribute("XPDrop", baseStats.XPDrop)
    end
    if typeof(baseStats.GoldDrop) == "number" then
        enemy:SetAttribute("GoldDrop", baseStats.GoldDrop)
    end
end

-- Constructor
function WaveManager.new(config)
    local self = setmetatable({}, WaveManager)
    self.Config = config or {}
    local levelName = self.Config.LevelName or "lvl1"
    local repScripts = ReplicatedStorage:FindFirstChild("Scripts")
    local lvlFolder = repScripts and repScripts:FindFirstChild(levelName)
    local candidate = lvlFolder and lvlFolder:FindFirstChild("WaveConfig")
    local loadedCfg
    if candidate then
        local ok, cfg = pcall(function() return require(candidate) end)
        if ok and type(cfg) == "table" then
            loadedCfg = cfg
        end
    end
    if not loadedCfg then
        warn(string.format("[WaveManager] WaveConfig not found for level '%s' in ReplicatedStorage.Scripts.%s.WaveConfig; no waves will run.", levelName, levelName))
        loadedCfg = { Waves = {}, Rates = {} }
    end
    -- STRICT: Only use loadedCfg (ignore fields passed in 'config' except LevelName & callbacks)
    self.Waves = loadedCfg.Waves or {}
    self.Config.Rates = loadedCfg.Rates or {}
    -- Allow user-provided callbacks (if any) to override loaded ones
    if loadedCfg.OnWaveStarted and not self.Config.OnWaveStarted then self.Config.OnWaveStarted = loadedCfg.OnWaveStarted end
    if loadedCfg.OnWaveCleared and not self.Config.OnWaveCleared then self.Config.OnWaveCleared = loadedCfg.OnWaveCleared end
    if loadedCfg.OnAllWavesCleared and not self.Config.OnAllWavesCleared then self.Config.OnAllWavesCleared = loadedCfg.OnAllWavesCleared end
    if loadedCfg.OnEnemySpawned and not self.Config.OnEnemySpawned then self.Config.OnEnemySpawned = loadedCfg.OnEnemySpawned end
    if loadedCfg.OnEnemyDied and not self.Config.OnEnemyDied then self.Config.OnEnemyDied = loadedCfg.OnEnemyDied end
    self.SpawnPoints = self.Config.SpawnPoints or getDefaultSpawnPoints()
    -- Optional rectangular/quad areas (array of areas), each area is a table describing a rectangle in world space
    -- Two ways to define each area:
    -- 1) { p1 = Vector3, p2 = Vector3 }             -- axis-aligned rectangle from min to max (Y will be used as height)
    -- 2) { corners = { v1, v2, v3, v4 } }           -- quad (v1..v4), we will pick a random point via bilinear interpolation
    -- Optional: area.Y or area.HeightOverride to set spawn Y
    -- SpawnAreas: pode vir da config externa ou do WaveConfig carregado.
    -- Prioridade (para cada enemy): entry.position / entry.positions / entry.area > self.SpawnAreas > self.SpawnPoints > self.ArenaBounds
    self.SpawnAreas = self.Config.SpawnAreas or loadedCfg.SpawnAreas or nil
    -- ArenaBounds: fallback final se nada acima disponível
    self.ArenaBounds = self.Config.ArenaBounds or loadedCfg.ArenaBounds
    -- Telegraph: red circle before spawn
    self.TelegraphDelay = self.Config.TelegraphDelay or 1.0    -- seconds to wait showing the warning
    self.TelegraphRadius = self.Config.TelegraphRadius or 3.0  -- circle radius
    self.TelegraphColor = self.Config.TelegraphColor or Color3.new(1, 0, 0)
    self.TelegraphTransparency = self.Config.TelegraphTransparency or 0.4
    self.TelegraphMaterial = self.Config.TelegraphMaterial or Enum.Material.Neon
    -- Economy: gold increase per wave (e.g., 0.02 = +2% per wave after the first)
    local rates = self.Config.Rates or {}
    self.GoldPerWavePercent = (self.Config.GoldPerWavePercent ~= nil) and self.Config.GoldPerWavePercent or (rates.GoldPerWavePercent or 0.02)
    self.XPPerWavePercent = rates.XPPerWavePercent or 0.05
    self.HealthPerWavePercent = rates.HealthPerWavePercent or 0 -- multiplicative per wave
    self.DamagePerWavePercent = rates.DamagePerWavePercent or 0
    -- Spawn separation: minimum distance between spawn points in a wave
    self.SeparationRadius = self.Config.SeparationRadius or 2.0
    self.MaxSpawnAttempts = self.Config.MaxSpawnAttempts or 20
    self.SpawnInterval = self.Config.SpawnInterval or 0.4 -- seconds between spawns
    self.BetweenWavesDelay = self.Config.BetweenWavesDelay or 3
    -- Burst spawning config: can be defined externally in WaveConfig (Burst = { StartWave=, Min=, Max= })
    local burstCfg = self.Config.Burst or loadedCfg.Burst or {}
    self.BurstStartWave = burstCfg.StartWave or math.huge
    self.BurstMin = math.max(1, burstCfg.Min or 1)
    self.BurstMax = math.max(self.BurstMin, burstCfg.Max or self.BurstMin)
    self.LoadEnemy = self.Config.LoadEnemy or resolveEnemyTemplate
    self.Scale = self.Config.Scale -- function(enemyId, waveIndex, spawnIndex) -> table
    self.OnWaveStarted = self.Config.OnWaveStarted
    self.OnWaveCleared = self.Config.OnWaveCleared
    self.OnAllWavesCleared = self.Config.OnAllWavesCleared
    self.OnEnemySpawned = self.Config.OnEnemySpawned
    self.OnEnemyDied = self.Config.OnEnemyDied

    self._running = false
    self._waveIndex = 0
    self._activeEnemies = {} -- [instance] = true
    self._telegraphs = {}    -- track active telegraph parts for cleanup
    self._spawnedInWave = 0
    self._toSpawnInWave = 0
    self._clearing = false -- guard to avoid double-scheduling wave clear
    self._lastPauseState = ReplicatedStorage:GetAttribute("GamePaused") == true
    -- Replicate total waves & reset current wave for client UIs
    pcall(function()
        ReplicatedStorage:SetAttribute("TotalWaves", #self.Waves)
        if ReplicatedStorage:GetAttribute("CurrentWave") == nil then
            ReplicatedStorage:SetAttribute("CurrentWave", 0)
        end
    end)
    return self
end

function WaveManager:IsRunning()
    return self._running
end

function WaveManager:GetWaveIndex()
    return self._waveIndex
end

function WaveManager:CleanupTelegraphs()
    if self._telegraphs then
        for i, part in ipairs(self._telegraphs) do
            if part and part.Parent then
                pcall(function() part:Destroy() end)
            end
            self._telegraphs[i] = nil
        end
    end
    -- Failsafe: also destroy any stray parts named SpawnTelegraph in workspace
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("BasePart") and child.Name == "SpawnTelegraph" then
            pcall(function() child:Destroy() end)
        end
    end
end

function WaveManager:Stop()
    self._running = false
    -- Cleanup any remaining telegraph visuals
    self:CleanupTelegraphs()
end

local function pickSpawnPoint(spawnPoints, i)
    if #spawnPoints == 0 then
        return CFrame.new(0, 5, 0)
    end
    -- Se houver vários pontos, escolher aleatoriamente para maior dispersão;
    -- se apenas 1 ponto, aplicar pequeno offset radial aleatório para evitar "empilhamento" perfeito.
    local part
    if #spawnPoints == 1 then
        part = spawnPoints[1]
        if part:IsA("BasePart") then
            local radius = math.max(part.Size.X, part.Size.Z) * 0.5
            local angle = math.random() * math.pi * 2
            local r = radius * math.sqrt(math.random()) -- distribuição mais uniforme no disco
            local offset = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
            local basePos = part.Position + offset
            return CFrame.new(basePos + Vector3.new(0, 3, 0))
        end
    else
        part = spawnPoints[math.random(1, #spawnPoints)]
        if part:IsA("BasePart") then
            -- Offset leve dentro da área do part
            local ox = (math.random() - 0.5) * part.Size.X * 0.8
            local oz = (math.random() - 0.5) * part.Size.Z * 0.8
            local basePos = part.Position + Vector3.new(ox, 0, oz)
            return CFrame.new(basePos + Vector3.new(0, 3, 0))
        end
    end
    return CFrame.new(0, 5, 0)
end

local function randomBetween(a, b)
    return a + (b - a) * math.random()
end

-- Sample a random position inside an axis-aligned rectangle (p1, p2)
local function sampleInAABB(p1, p2, yOverride)
    local minX, maxX = math.min(p1.X, p2.X), math.max(p1.X, p2.X)
    local minZ, maxZ = math.min(p1.Z, p2.Z), math.max(p1.Z, p2.Z)
    local x = randomBetween(minX, maxX)
    local z = randomBetween(minZ, maxZ)
    local y = yOverride or p1.Y
    return Vector3.new(x, y, z)
end

-- Bilinear interpolation inside a quad (corners v1..v4)
local function sampleInQuad(corners, yOverride)
    local v1, v2, v3, v4 = corners[1], corners[2], corners[3], corners[4]
    local u = math.random()
    local v = math.random()
    -- Bilinear interpolate: P(u,v) = (1-u)(1-v)v1 + u(1-v)v2 + (1-u)v v3 + uv v4
    local p = (v1 * (1 - u) * (1 - v))
        + (v2 * u * (1 - v))
        + (v3 * (1 - u) * v)
        + (v4 * u * v)
    if yOverride then
        p = Vector3.new(p.X, yOverride, p.Z)
    end
    return p
end

local function pickRandomAreaCFrame(areas)
    if not areas or #areas == 0 then return nil end
    local area = areas[math.random(1, #areas)]
    local pos
    if area.p1 and area.p2 then
        pos = sampleInAABB(area.p1, area.p2, area.Y or area.HeightOverride)
    elseif area.corners and #area.corners >= 4 then
        pos = sampleInQuad(area.corners, area.Y or area.HeightOverride)
    end
    if not pos then return nil end
    return CFrame.new(pos)
end

-- Fallback: sample inside arena bounds (axis-aligned box) se definido
local function sampleInArena(bounds)
    if not bounds or not bounds.min or not bounds.max then return nil end
    local mn, mx = bounds.min, bounds.max
    local function rb(a,b) return a + (b-a)*math.random() end
    local x = rb(math.min(mn.X, mx.X), math.max(mn.X, mx.X))
    local y = rb(math.min(mn.Y, mx.Y), math.max(mn.Y, mx.Y))
    local z = rb(math.min(mn.Z, mx.Z), math.max(mn.Z, mx.Z))
    return CFrame.new(Vector3.new(x,y,z))
end

-- Find ground height under/near a position and return an aligned CFrame
local function alignToGround(position, upOffset)
    upOffset = upOffset or 0
    local origin = position + Vector3.new(0, 100, 0)
    local direction = Vector3.new(0, -500, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {}
    local result = workspace:Raycast(origin, direction, params)
    if result then
        local y = result.Position.Y + upOffset
        return CFrame.new(Vector3.new(position.X, y, position.Z))
    end
    return CFrame.new(position)
end

-- Internal: listen for enemy death/removal
function WaveManager:_trackEnemy(enemy, meta)
    self._activeEnemies[enemy] = true
    local debugWaves = false
    pcall(function()
        debugWaves = game:GetService("ReplicatedStorage"):GetAttribute("DebugWaves") or false
    end)
    if debugWaves then
        print(string.format("[WaveManager] _trackEnemy wave=%d id=%s spawnIndex=%s", self._waveIndex, tostring(meta and meta.id), tostring(meta and meta.spawnIndex)))
    end
    local humanoid = enemy:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Died:Connect(function()
            if self._activeEnemies[enemy] then
                self._activeEnemies[enemy] = nil
                if debugWaves then print(string.format("[WaveManager] OnEnemyDied fired for id=%s wave=%d", tostring(meta and meta.id), self._waveIndex)) end
                if typeof(self.OnEnemyDied) == "function" then
                    local info = {
                        enemy = enemy,
                        id = meta and meta.id or nil,
                        waveIndex = self._waveIndex,
                        spawnIndex = meta and meta.spawnIndex or nil,
                        drops = {
                            XP = enemy:GetAttribute("XPDrop"),
                            Gold = enemy:GetAttribute("GoldDrop"),
                        }
                    }
                    task.spawn(self.OnEnemyDied, info)
                end
                -- Despawn enemy immediately to avoid ragdoll bodies lingering
                task.defer(function()
                    if enemy and enemy.Parent then
                        pcall(disableEnemyCollisions, enemy)
                        enemy:Destroy()
                    end
                end)
                self:_checkWaveCleared()
            end
        end)
        -- Failsafe: if health drops to 0 and Died didn't fire, clean up
        humanoid.HealthChanged:Connect(function(h)
            if h <= 0 and self._activeEnemies[enemy] then
                self._activeEnemies[enemy] = nil
                if typeof(self.OnEnemyDied) == "function" then
                    local info = {
                        enemy = enemy,
                        id = meta and meta.id or nil,
                        waveIndex = self._waveIndex,
                        spawnIndex = meta and meta.spawnIndex or nil,
                        drops = {
                            XP = enemy:GetAttribute("XPDrop"),
                            Gold = enemy:GetAttribute("GoldDrop"),
                        }
                    }
                    task.spawn(self.OnEnemyDied, info)
                end
                task.defer(function()
                    if enemy and enemy.Parent then
                        pcall(disableEnemyCollisions, enemy)
                        enemy:Destroy()
                    end
                end)
                self:_checkWaveCleared()
            end
        end)
    end
    enemy.AncestryChanged:Connect(function(_, parent)
        if not parent and self._activeEnemies[enemy] then
            self._activeEnemies[enemy] = nil
            self:_checkWaveCleared()
        end
    end)
end

function WaveManager:_checkWaveCleared()
    local alive = 0
    for _ in pairs(self._activeEnemies) do alive += 1 end
    local debugWaves = false
    pcall(function()
        debugWaves = game:GetService("ReplicatedStorage"):GetAttribute("DebugWaves") or false
    end)
    if debugWaves then
        print(string.format("[WaveManager] _checkWaveCleared wave=%d alive=%d spawnedInWave=%d toSpawnInWave=%d running=%s",
            self._waveIndex, alive, self._spawnedInWave or 0, self._toSpawnInWave or 0, tostring(self._running)))
    end
    if alive == 0 and self._spawnedInWave >= self._toSpawnInWave then
        -- Avoid racing: schedule a short verification to ensure this isn't a transient state
        if self._clearing then
            if debugWaves then print(string.format("[WaveManager] _checkWaveCleared: already scheduling verify for wave=%d", self._waveIndex)) end
            return
        end
        self._clearing = true
        if debugWaves then print(string.format("[WaveManager] _checkWaveCleared: candidate cleared, scheduling verify for wave=%d", self._waveIndex)) end
        task.spawn(function()
            -- small debounce to allow any in-flight death/ancestry handlers to settle
            task.wait(0.12)
            local alive2 = 0
            for _ in pairs(self._activeEnemies) do alive2 += 1 end
            if debugWaves then
                print(string.format("[WaveManager] verifyClear wave=%d aliveAfterWait=%d spawnedInWave=%d toSpawnInWave=%d running=%s",
                    self._waveIndex, alive2, self._spawnedInWave or 0, self._toSpawnInWave or 0, tostring(self._running)))
            end
            if alive2 == 0 and self._spawnedInWave >= self._toSpawnInWave then
                if typeof(self.OnWaveCleared) == "function" then
                    if debugWaves then print(string.format("[WaveManager] OnWaveCleared firing for wave %d", self._waveIndex)) end
                    task.spawn(self.OnWaveCleared, self._waveIndex)
                end
                if self._running then
                    -- Pause-aware delay before next wave
                    local remaining = self.BetweenWavesDelay
                    task.spawn(function()
                        while self._running and remaining > 0 do
                            if ReplicatedStorage:GetAttribute("GamePaused") then
                                task.wait(0.05)
                            else
                                local dt = math.min(0.05, remaining)
                                task.wait(dt)
                                remaining -= dt
                            end
                        end
                        if self._running then
                            self:_nextWave()
                        end
                    end)
                end
            else
                if debugWaves then print(string.format("[WaveManager] verifyClear: not cleared for wave=%d (alive=%d) -- deferring", self._waveIndex, alive2)) end
                self._clearing = false
            end
        end)
    end
end

function WaveManager:_nextWave()
    -- Reset clearing guard when moving to next wave
    self._clearing = false
    self._waveIndex += 1
    if self._waveIndex > #self.Waves then
        self._running = false
        -- Mark completion for clients
        pcall(function()
            ReplicatedStorage:SetAttribute("CurrentWave", #self.Waves)
            ReplicatedStorage:SetAttribute("WavesCompleted", true)
        end)
        if typeof(self.OnAllWavesCleared) == "function" then
            task.spawn(self.OnAllWavesCleared)
        end
        return
    end
    -- Update replicated current wave index
    pcall(function()
        ReplicatedStorage:SetAttribute("CurrentWave", self._waveIndex)
    end)

    local wave = self.Waves[self._waveIndex]
    self._activeEnemies = {}
    self._spawnedInWave = 0
    self._toSpawnInWave = 0
    self._waveReservedSpawns = {}

    if typeof(self.OnWaveStarted) == "function" then
        task.spawn(self.OnWaveStarted, self._waveIndex, wave)
    end

    -- Count total to spawn
    for _, entry in ipairs(wave.enemies or {}) do
        self._toSpawnInWave += (entry.count or 0)
    end

    -- Spawn enemies with a small interval
    task.spawn(function()
        local spawnIdx = 0
        for _, entry in ipairs(wave.enemies or {}) do
            local id = entry.id
            local count = entry.count or 0
            local spawnedForEntry = 0
            while spawnedForEntry < count do
                if not self._running then return end
                -- Respect global pause: wait while GamePaused is true
                while ReplicatedStorage:GetAttribute("GamePaused") do
                    task.wait(0.05)
                    if not self._running then return end
                end

                -- Determine burst size for this tick
                local remaining = count - spawnedForEntry
                local burstSize = 1
                if self._waveIndex >= self.BurstStartWave then
                    burstSize = math.clamp(math.random(self.BurstMin, self.BurstMax), 1, remaining)
                else
                    burstSize = 1
                end

                -- Precompute separated positions and telegraphs for the burst
                local planned = {} -- { {groundCFrame, telePart} }
                local function getActiveEnemyPositions()
                    local positions = {}
                    for enemy, _ in pairs(self._activeEnemies) do
                        if enemy and enemy.Parent then
                            local ok, cf = pcall(function() return enemy:GetPivot() end)
                            local pos
                            if ok and typeof(cf) == "CFrame" then
                                pos = cf.Position
                            else
                                local pp = enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart")
                                pos = pp and pp.Position or nil
                            end
                            if pos then table.insert(positions, pos) end
                        end
                    end
                    return positions
                end

                local function isTooClose(pos)
                    local radius = self.SeparationRadius or 0
                    if radius <= 0 then return false end
                    -- Check against reserved spawn points in this wave
                    for _, p in ipairs(self._waveReservedSpawns) do
                        if (pos - p).Magnitude < radius then return true end
                    end
                    -- Check against current alive enemies
                    for _, p in ipairs(getActiveEnemyPositions()) do
                        if (pos - p).Magnitude < radius then return true end
                    end
                    return false
                end

                local function sampleSeparatedCFrame()
                    local lastCF
                    local attempts = self.MaxSpawnAttempts or 20
                    for _ = 1, attempts do
                        local baseCF = pickRandomAreaCFrame(self.SpawnAreas)
                        if not baseCF then
                            baseCF = pickSpawnPoint(self.SpawnPoints, spawnIdx)
                        end
                        if (not baseCF or (baseCF.Position == Vector3.new(0,5,0))) and self.ArenaBounds then
                            baseCF = sampleInArena(self.ArenaBounds) or baseCF
                        end
                        local groundCF = alignToGround(baseCF.Position, 0.05)
                        lastCF = groundCF
                        if not isTooClose(groundCF.Position) then
                            return groundCF
                        end
                    end
                    return lastCF
                end

                for b = 1, burstSize do
                    spawnIdx += 1
                    local groundCFrame
                    -- Per-entry overrides (fixed position / list / area)
                    if entry.position and typeof(entry.position) == "Vector3" then
                        groundCFrame = alignToGround(entry.position, 0.05)
                    elseif entry.positions and typeof(entry.positions) == "table" and #entry.positions > 0 then
                        local posIndex = ((spawnedForEntry + b - 1) % #entry.positions) + 1
                        local v = entry.positions[posIndex]
                        if typeof(v) == "Vector3" then
                            groundCFrame = alignToGround(v, 0.05)
                        end
                    elseif entry.area and typeof(entry.area) == "table" and entry.area.p1 and entry.area.p2 then
                        local sampled = sampleInAABB(entry.area.p1, entry.area.p2, entry.area.Y or entry.area.HeightOverride)
                        groundCFrame = CFrame.new(sampled)
                    end
                    if not groundCFrame then
                        groundCFrame = sampleSeparatedCFrame()
                    end
                    table.insert(self._waveReservedSpawns, groundCFrame.Position)

                    local telePart = Instance.new("Part")
                    telePart.Name = "SpawnTelegraph"
                    telePart.Anchored = true
                    telePart.CanCollide = false
                    local teleHeight = 0.2
                    local diameter = self.TelegraphRadius * 2
                    telePart.Size = Vector3.new(teleHeight, diameter, diameter)
                    telePart.Material = self.TelegraphMaterial
                    telePart.Color = self.TelegraphColor
                    telePart.Transparency = self.TelegraphTransparency
                    telePart.Shape = Enum.PartType.Cylinder
                    telePart.CFrame = (groundCFrame + Vector3.new(0, teleHeight/2, 0)) * CFrame.Angles(0, 0, math.rad(90))
                    telePart.Parent = workspace
                    table.insert(self._telegraphs, telePart)

                    table.insert(planned, { cf = groundCFrame, tele = telePart, sidx = spawnIdx })
                end

                -- Pause-aware telegraph delay
                do
                    local remaining = self.TelegraphDelay
                    while remaining > 0 do
                        while ReplicatedStorage:GetAttribute("GamePaused") do
                            task.wait(0.05)
                            if not self._running then return end
                        end
                        local dt = math.min(0.05, remaining)
                        task.wait(dt)
                        remaining -= dt
                        if not self._running then return end
                    end
                end

                -- Respect pause before actual spawn
                while ReplicatedStorage:GetAttribute("GamePaused") do
                    task.wait(0.05)
                    if not self._running then return end
                end

                -- Spawn the burst
                for _, p in ipairs(planned) do
                    if p.tele and p.tele.Parent then
                        p.tele:Destroy()
                    end
                    -- Remove from tracking list (lazy linear removal is fine for small counts)
                    for ti, tp in ipairs(self._telegraphs) do
                        if tp == p.tele then
                            table.remove(self._telegraphs, ti)
                            break
                        end
                    end
                    local template = self.LoadEnemy and self.LoadEnemy(id) or nil
                    local enemy = spawnEnemyFromTemplate(template, p.cf)
                    local baseStats = getEnemyBaseStats(id, template)
                    applyEnemyBaseStats(enemy, baseStats)
                    -- Disable collisions on all parts
                    pcall(disableEnemyCollisions, enemy)
                    do
                        local hum = enemy:FindFirstChildOfClass("Humanoid")
                        if hum then hum.BreakJointsOnDeath = false end
                    end
                    pcall(function()
                        enemy:SetAttribute("IsEnemy", true)
                        enemy:SetAttribute("EnemyId", id)
                        CollectionService:AddTag(enemy, "Enemy")
                    end)
                    do
                        local waveFactor = math.max(0, self._waveIndex - 1)
                        local gold = enemy:GetAttribute("GoldDrop")
                        if typeof(gold) == "number" and gold > 0 then
                            local multiplier = 1 + (self.GoldPerWavePercent or 0) * waveFactor
                            enemy:SetAttribute("GoldDrop", math.floor(gold * multiplier + 0.5))
                            enemy:SetAttribute("GoldDropMultiplier", multiplier)
                        end
                        local xp = enemy:GetAttribute("XPDrop")
                        if typeof(xp) == "number" and xp > 0 then
                            local xpMultiplier = 1 + (self.XPPerWavePercent or 0) * waveFactor
                            enemy:SetAttribute("XPDrop", math.floor(xp * xpMultiplier + 0.5))
                            enemy:SetAttribute("XPDropMultiplier", xpMultiplier)
                        end
                        -- Health scaling
                        if self.HealthPerWavePercent > 0 then
                            local hum = enemy:FindFirstChildOfClass("Humanoid")
                            if hum then
                                local healthMult = (1 + self.HealthPerWavePercent) ^ waveFactor
                                hum.MaxHealth = math.floor(hum.MaxHealth * healthMult + 0.5)
                                hum.Health = hum.MaxHealth
                                enemy:SetAttribute("HealthWaveMultiplier", healthMult)
                            end
                        end
                        -- Damage scaling
                        if self.DamagePerWavePercent > 0 then
                            local base = enemy:GetAttribute("BaseDamage") or enemy:GetAttribute("Damage")
                            if typeof(base) == "number" and base > 0 then
                                local dmgMult = (1 + self.DamagePerWavePercent) ^ waveFactor
                                enemy:SetAttribute("DamageWaveMultiplier", dmgMult)
                                -- Keep legacy scaled Damage attribute for any old code paths
                                enemy:SetAttribute("Damage", math.floor(base * dmgMult + 0.5))
                            end
                        end
                    end
                    self._spawnedInWave += 1
                    local meta = { id = id, spawnIndex = p.sidx }
                    self:_trackEnemy(enemy, meta)
                    -- Attach AI if needed (for folders without embedded model scripts)
                    pcall(function() attachEnemyAI(enemy, id) end)
                    if debugWaves then
                        local alive2 = 0
                        for _ in pairs(self._activeEnemies) do alive2 += 1 end
                        print(string.format("[WaveManager] spawned enemy id=%s wave=%d spawnIndex=%d spawnedInWave=%d active=%d",
                            tostring(id), self._waveIndex, p.sidx, self._spawnedInWave, alive2))
                    end

                    if typeof(self.OnEnemySpawned) == "function" then
                        local info = {
                            enemy = enemy,
                            id = id,
                            waveIndex = self._waveIndex,
                            spawnIndex = p.sidx,
                            drops = {
                                XP = enemy:GetAttribute("XPDrop"),
                                Gold = enemy:GetAttribute("GoldDrop"),
                            }
                        }
                        task.spawn(self.OnEnemySpawned, info)
                    end

                    local scale = nil
                    if typeof(self.Scale) == "function" then
                        local ok, result = pcall(self.Scale, id, self._waveIndex, p.sidx, entry)
                        if ok then scale = result end
                    end
                    applyEnemyScaling(enemy, scale)
                end

                spawnedForEntry += burstSize
                -- Pause-aware spawn interval
                do
                    local remaining = self.SpawnInterval
                    while remaining > 0 do
                        while ReplicatedStorage:GetAttribute("GamePaused") do
                            task.wait(0.05)
                            if not self._running then return end
                        end
                        local dt = math.min(0.05, remaining)
                        task.wait(dt)
                        remaining -= dt
                        if not self._running then return end
                    end
                end
            end
        end
        -- After all spawned, check if already cleared
        self:_checkWaveCleared()
    end)
end

function WaveManager:Start()
    if self._running then return end
    self._running = true
    self._waveIndex = 0
    self:_nextWave()
end

return WaveManager
