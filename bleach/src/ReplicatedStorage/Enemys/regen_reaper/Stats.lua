local RegenReaperStats = {}

-- Base stats for Regen Reaper (Bleach enemy with regeneration - Third Story Map)
-- Tank unit with moderate health regen - requires focus fire to kill
RegenReaperStats.Health = 350      -- High health tank (almost 2x Meele Reaper)
RegenReaperStats.MoveSpeed = 14    -- slower than other reapers
RegenReaperStats.WalkSpeed = 14    -- kept for compatibility
RegenReaperStats.Damage = 12       -- lower damage than Meele Reaper
RegenReaperStats.XPDrop = 25       -- bonus XP for harder enemy (25% more)
RegenReaperStats.GoldDrop = 0      -- unused (rewards at end-of-run)
RegenReaperStats.HealthRegen = 8   -- 8 HP/sec regen (requires focus to kill)

return RegenReaperStats
