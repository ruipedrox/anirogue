-- DamageNumbers.client.lua
-- Initialize damage numbers system on client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Require the module to initialize the client listener
local DamageNumbers = require(ReplicatedStorage.Scripts.Combat.DamageNumbers)

print("[DamageNumbers] Client initialized, ready to display damage")
