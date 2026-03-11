local Template = require(script.Parent.Parent.MapTemplate)

local M = Template.New()
M.Type = "hub" -- lobby behaves as hub/return destination
M.Id = "Lobby"
-- Only PlaceId is required for hub maps (set to your actual Lobby place)
M.PlaceId = 93669123476184

return M
