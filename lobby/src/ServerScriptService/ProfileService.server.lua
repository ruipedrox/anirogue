-- Converte para simples wrapper do ModuleScript em ReplicatedStorage.Scripts.ProfileService
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local ProfileService = require(ScriptsFolder:WaitForChild("ProfileService"))
print("[ProfileService.server] Wrapper loaded -> usando módulo em ReplicatedStorage.Scripts")
return ProfileService