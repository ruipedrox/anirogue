local RegenReaperStats = {}

-- Base stats for Regen Reaper (Bleach enemy with regeneration - Third Story Map)
-- TESTING: Increased health to test regeneration properly
RegenReaperStats.Health = 1500     -- TEST: Very high health to survive and show regen
RegenReaperStats.MoveSpeed = 13    -- movement speed (slowest of all)
RegenReaperStats.WalkSpeed = 13    -- kept for compatibility
RegenReaperStats.Damage = 24       -- melee damage (lower than meele but still strong)
RegenReaperStats.XPDrop = 20       -- xp awarded when killed (same as Village)
RegenReaperStats.GoldDrop = 0      -- unused (rewards at end-of-run)
RegenReaperStats.HealthRegen = 200 -- HP regen per second (EXTREME - requires DOT/heal reduction to counter!)

return RegenReaperStats
