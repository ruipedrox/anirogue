-- Shared Sounds registry (lobby)
-- Populate numeric values with your uploaded audio asset ids.

local Sounds = {
    UI_CONFIRM = 0,
    UI_CANCEL = 0,
    EXPLOSION = 0,
    AMBIENT_LOBBY = 114567915893133,
    -- UI sounds
    UI_CLICK = 87437544236708,
    UI_OPEN  = 129250286828723,
    UI_ERROR = 110870343804166,
    -- Roll / Summon / Chest SFX
    ROLL_START  = 138498992667102,  -- animation start (card flip begins)
    ROLL_RARE   = 9045122943,       -- 5-star char or Legendary item reveal
    ROLL_COMMON = 109727714379123,  -- any other rarity reveal
    ROLL_SKIP   = 140172825268473,  -- skip button
}

return Sounds
