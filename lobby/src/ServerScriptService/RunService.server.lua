-- Wrapper para ModuleScript RunService (ReplicatedStorage.Scripts.RunService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local RunService = require(ScriptsFolder:WaitForChild("RunService"))
print("[RunService.server] Wrapper ativo -> usando módulo em ReplicatedStorage.Scripts")
return RunService