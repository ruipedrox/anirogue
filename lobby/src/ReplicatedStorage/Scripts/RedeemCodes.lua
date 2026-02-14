-- RedeemCodes Module
-- Define all available and expired codes with their rewards

local RedeemCodes = {}

-- Active codes: { Code = { Rewards, ExpiresAt (optional) } }
RedeemCodes.ActiveCodes = {
	["RELEASE"] = {
		Gold = 500,
		Gems = 500,
		Description = "Release celebration code!",
		-- ExpiresAt = os.time() + (7 * 24 * 60 * 60), -- 7 days from now (optional)
	},
	["WELCOME"] = {
		Gold = 250,
		Gems = 250,
		Description = "Welcome to the game!",
	},
	["1KVISITS"] = {
		Gold = 1000,
		Gems = 300,
		Description = "Thanks for 1K visits!",
	},
}

-- Expired codes (for reference/history)
RedeemCodes.ExpiredCodes = {
	-- ["OLDCODE"] = {
	-- 	Gold = 100,
	-- 	Gems = 100,
	-- 	Description = "This code has expired",
	-- 	ExpiredAt = 1234567890,
	-- },
}

-- Check if a code is valid and active
function RedeemCodes:IsValidCode(code)
	if not code or type(code) ~= "string" then return false end
	code = string.upper(code) -- Case insensitive
	
	local codeData = self.ActiveCodes[code]
	if not codeData then return false, "Invalid code" end
	
	-- Check if code has expired
	if codeData.ExpiresAt and os.time() >= codeData.ExpiresAt then
		return false, "Code has expired"
	end
	
	return true, codeData
end

-- Get rewards for a code
function RedeemCodes:GetRewards(code)
	code = string.upper(code)
	local codeData = self.ActiveCodes[code]
	if not codeData then return nil end
	
	return {
		Gold = codeData.Gold or 0,
		Gems = codeData.Gems or 0,
		-- Add more reward types here as needed (e.g., Characters, Items, etc.)
	}
end

return RedeemCodes
