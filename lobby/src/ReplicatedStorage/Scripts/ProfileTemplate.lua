-- ProfileTemplate.lua
-- Estrutura base de dados persistentes do jogador no lobby.
-- NOTA: Valores podem ser migrados via ProfileService.Version se precisares alterar no futuro.

local ProfileTemplate = {
    Version = 2, -- bump para suportar Items per-instância
    Account = {
        Level = 1,
        XP = 0,
        Coins = 1000000,
        Gems = 1000000,
        Materials = {
            Essence = 0,
        },
        Boosts = nil, -- e.g., { XP = 1.5, Coins = 2.0, EndsAt = os.time()+3600 }
        RunsCompleted = 0,
        BestDepth = 0,
        HighInfWave = 0, -- maior wave alcançada no modo infinito
        RedeemedCodes = {}, -- ["CODE_NAME"] = timestamp when redeemed
    },
    Characters = {
        -- Instâncias iniciais: usar raridades 3 estrelas (Goku_3, Naruto_3)
        -- IDs estáticos de seed; podem ser substituídos por geração dinâmica na criação real do profile.
        Capacity = 50, -- capacidade máxima inicial de personagens
        Instances = {
            -- Cada instância inclui: TemplateName, Level, XP, Tier (progressão de quality dos stats)
            Goku_3_seed = { TemplateName = "Goku_3", Level = 1, XP = 0, Tier = "B-" },
            Naruto_3_seed = { TemplateName = "Naruto_3", Level = 1, XP = 0, Tier = "B-" },
        }, -- [InstanceId] = { TemplateName=..., Level=..., XP=..., Tier=... }
        EquippedOrder = { "Goku_3_seed", "Naruto_3_seed" }, -- dois slots base sempre ativos
        UnlockedTemplates = { "Goku_3", "Naruto_3" }, -- default desbloqueados (3 estrelas)
    },
    -- Mantemos formato antigo aqui (pré-migração) para que CreateOrLoad converta para novo modelo Instances.
    -- Novo modelo (após migração):
    -- Items = {
    --   Owned = {
    --     Weapons = { Instances = { [id] = { Template="Kunai", Level=1 } } },
    --     Armors  = { Instances = { ... } },
    --     Rings   = { Instances = { ... } },
    --   },
    --   Equipped = { Weapon = instanceId, Armor = instanceId, Ring = instanceId }
    -- }
    Items = {
        Owned = {
            -- Cada entry antigo (antes de migração p/ Instances) agora inclui Quality default 'rusty'
            Weapons = { Kunai = { Level = 1, Quality = "rusty" } },
            Armors = { ClothArmor = { Level = 1, Quality = "rusty" } },
            Rings = { IronRing = { Level = 1, Quality = "rusty" } },
        },
        Equipped = { Weapon = "Kunai", Armor = "ClothArmor", Ring = "IronRing" },
    },
    Unlocks = {
        CardsPermanent = {}, -- futuras melhorias meta persistentes
    },
    -- Progresso do modo Story (desbloqueio de mapas/níveis)
    Story = {
        -- Maps[MapId] = { MaxUnlockedLevel = 0..3, LevelsCompleted = { [1]=true, [2]=true, ... } }
        Maps = {},
    },
    -- Progresso do modo Infinite
    Infinite = {
        HighestWave = 0, -- maior wave alcançada
        MilestonesReached = {}, -- [10]=true, [20]=true, [30]=true ... para first time bonus tracking
    },
    -- Sistema de Missões
    Missions = {
        Progress = {
            -- Tracking de progresso para cada tipo de missão
            StoryLevelsCompleted = 0,    -- Total de levels de story completados
            TotalDamageDealt = 0,         -- Dano total causado (todas as runs)
            HighestInfiniteWave = 0,      -- Maior wave alcançada no infinite
            TotalEvolves = 0,             -- Total de evolves feitos
            TotalSummons = 0,             -- Total de summons feitos
        },
        -- Para missões infinitas, guardamos o último tier resgatado
        InfiniteTiersClaimed = {
            -- ["total_damage"] = 5,  -- tier 5 já foi resgatado
            -- ["infinite_waves"] = 3, -- tier 3 já foi resgatado
            -- ["evolves_infinite"] = 2,
            -- ["summons_infinite"] = 1,
        },
    },
    Meta = {
        Settings = { Language = "en", MusicVolume = 50, SFXVolume = 50 },
    }
}

return ProfileTemplate