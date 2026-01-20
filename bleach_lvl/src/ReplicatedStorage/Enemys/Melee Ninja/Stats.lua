local MeleeNinjaStats = {}

-- Base stats for Melee Ninja
MeleeNinjaStats.Health = 120      -- base max health
MeleeNinjaStats.MoveSpeed = 16      -- preferred movement speed stat (used by WaveManager)
MeleeNinjaStats.WalkSpeed = 16      -- kept for compatibility; MoveSpeed takes priority
MeleeNinjaStats.Damage = 10         -- contact/melee damage
MeleeNinjaStats.XPDrop = 20         -- xp awarded to players when killed (run-level XP only)
-- Gold is no longer granted per kill; rewards are given at end-of-run via map Drops
MeleeNinjaStats.GoldDrop = 0        -- keep field for compatibility, but unused by reward logic

return MeleeNinjaStats
