-- Cards.lua (Shikamaru_4)

local ShikamaruCards = {}

-- Card definitions for Shikamaru_4
ShikamaruCards.Definitions = {
	Epic = {
		{
			id = "Shikamaru_ExplosiveScroll",
			name = "Explosive Scrolls",
			description = "Places explosive scrolls that detonate when enemies approach.",
			-- maxLevel will be read from the card module, but keep hint here
			stackable = true,
			maxLevel = 3,
			module = "Shikamaru_ExplosiveScroll",
			image = "rbxassetid://123109783942533",
		}
	}
}

return ShikamaruCards
