-- Wrapper para ModuleScript verdadeiro em ReplicatedStorage.Scripts.CharacterService
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local CharacterService = require(ScriptsFolder:WaitForChild("CharacterService"))
print("[CharacterService.server] Wrapper ativo -> usando módulo em ReplicatedStorage.Scripts")
return CharacterService