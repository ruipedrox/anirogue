-- RunResult.server.lua
-- Apply run results sent back via TeleportData from dungeon (vila) to persistent profile in lobby.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local ProfileService = require(ScriptsFolder:WaitForChild("ProfileService"))
local AccountLeveling = require(ScriptsFolder:WaitForChild("AccountLeveling"))
local CharacterService = require(ScriptsFolder:WaitForChild("CharacterService"))
local ItemsRegistry = nil
pcall(function()
    ItemsRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"):WaitForChild("Registry"))
end)

local DataStoreService = game:GetService("DataStoreService")
-- Matches vila's helper: CompletedLevels:<UserId>
local CompletedDS = DataStoreService:GetDataStore("PlayerCompletedLevels_v1")
-- Run results DS for fallback reward application
local RunResultsDS = DataStoreService:GetDataStore("PlayerRunResults_v1")

local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local ProfileUpdatedRE = remotes:FindFirstChild("ProfileUpdated") or Instance.new("RemoteEvent")
ProfileUpdatedRE.Name = "ProfileUpdated"
ProfileUpdatedRE.Parent = remotes

-- Forward declaration so earlier closures capture the local (not _G)
local applyRunResult

-- Helper to consume and apply any saved RunResults from the run place (DS fallback)
local function consumeAllSavedRunResults(player)
    task.spawn(function()
        local key = "RunResults:" .. tostring(player.UserId)
        local ok, tbl = pcall(function() return RunResultsDS:GetAsync(key) end)
        if ok and type(tbl) == "table" then
            -- New shape: { RunId, RunResult }
            if type(tbl.RunId) == "string" and type(tbl.RunResult) == "table" then
                local rid = tbl.RunId
                local shouldApply = true
                pcall(function()
                    local prof = ProfileService:Get(player)
                    if prof and prof.Meta and prof.Meta.AppliedRuns and prof.Meta.AppliedRuns[rid] then
                        shouldApply = false
                    end
                end)
                if shouldApply then
                    pcall(function() applyRunResult(player, tbl.RunResult) end)
                end
                -- Clear saved latest to avoid re-applying
                pcall(function() RunResultsDS:SetAsync(key, {}) end)
                pcall(function() ProfileService:Save(player) end)
            elseif type(tbl.Results) == "table" then
                -- Backward-compat: if old map exists, pick the newest we can (undefined order; we will apply and then clear)
                for runId, runRes in pairs(tbl.Results) do
                    pcall(function() applyRunResult(player, runRes) end)
                end
                -- Clear old structure to prevent cumulative re-application and reduce space
                pcall(function() RunResultsDS:SetAsync(key, {}) end)
                pcall(function() ProfileService:Save(player) end)
            end
        end

        -- Mirror fallback: read last summary and then the per-run mirror payload
        local summaryKey = "LastWriteSummary:" .. tostring(player.UserId)
        local okS, summary = pcall(function() return RunResultsDS:GetAsync(summaryKey) end)
        if okS and type(summary) == "table" and type(summary.RunId) == "string" and summary.RunId ~= "" then
            local rid = summary.RunId
            local shouldApply = true
            pcall(function()
                local prof = ProfileService:Get(player)
                if prof and prof.Meta and prof.Meta.AppliedRuns and prof.Meta.AppliedRuns[rid] then
                    shouldApply = false
                end
            end)
            if shouldApply then
                -- New compact mirror uses a single key RR:<uid> (still support old RR:<uid>:<shortId>)
                local mirrorKey = string.format("RR:%s", tostring(player.UserId))
                local okM, runRes = pcall(function() return RunResultsDS:GetAsync(mirrorKey) end)
                if okM and type(runRes) == "table" then
                    print(string.format("[RunResult] Applying mirrored RunId=%s for %s via DS mirror fallback", rid, player.Name))
                    pcall(function() applyRunResult(player, runRes) end)
                else
                    -- Try legacy short-key mirror once
                    local short = (type(summary.ShortId) == "string" and summary.ShortId ~= "") and summary.ShortId or string.gsub(rid, "-", ""):sub(1,8)
                    local legacyKey = string.format("RR:%s:%s", tostring(player.UserId), tostring(short))
                    local okL, runRes2 = pcall(function() return RunResultsDS:GetAsync(legacyKey) end)
                    if okL and type(runRes2) == "table" then
                        print(string.format("[RunResult] Applying legacy mirrored RunId=%s for %s via DS mirror fallback", rid, player.Name))
                        pcall(function() applyRunResult(player, runRes2) end)
                    end
                end
            end
        end
    end)
end

applyRunResult = function(player, runResult)
    if type(runResult) ~= "table" then return end
    -- Diagnostic: print basic runResult summary for debugging
    pcall(function()
        local rid = runResult.RunId and tostring(runResult.RunId) or "(no-id)"
        local acc = tonumber(runResult.AccountXP) or 0
        local keysCount = 0
        local keysList = {}
        if type(runResult.CharacterXP) == "table" then
            for k, _ in pairs(runResult.CharacterXP) do
                keysCount = keysCount + 1
                table.insert(keysList, tostring(k))
            end
        end
        local gold = runResult.Rewards and tonumber(runResult.Rewards.Gold) or 0
        local gems = runResult.Rewards and tonumber(runResult.Rewards.Gems) or 0
        print(string.format("[RunResult] Applying RunId=%s for %s -> AccountXP=%d CharacterKeys=%d [%s] Gold=%d Gems=%d",
            tostring(rid), tostring(player.Name), acc, keysCount, table.concat(keysList, ","), gold, gems))
    end)
    local profile = ProfileService:Get(player)
    if not profile then return end

    -- Idempotency: if RunId provided and already applied on profile, skip
    local runId = runResult.RunId and tostring(runResult.RunId) or nil
    if runId and profile.Meta and profile.Meta.AppliedRuns and profile.Meta.AppliedRuns[runId] then
        warn(string.format("[RunResult] Skipping already-applied RunId=%s for %s", runId, tostring(player.Name)))
        return
    end

    -- 1) Account XP
    local accXP = tonumber(runResult.AccountXP) or 0
    if accXP > 0 then
        local before = profile.Account and profile.Account.Level or nil
        local gained = AccountLeveling:AddXP(profile, accXP)
        local after = profile.Account and profile.Account.Level or nil
        print(string.format("[RunResult] AccountXP applied: +%d (levels +%s) Lv %s -> %s", accXP, tostring(gained or "?"), tostring(before or "?"), tostring(after or "?")))
    else
        warn("[RunResult] AccountXP is 0; skipping account XP application")
    end

    -- 2) Character XP by InstanceId OR TemplateName fallback
    local charMap = runResult.CharacterXP
    if type(charMap) == "table" then
        for key, amt in pairs(charMap) do
            local n = tonumber(amt) or 0
            if n <= 0 then continue end

            local applied = false
            -- Try direct instance id first
            pcall(function()
                local ok, res = pcall(function() return CharacterService:AddCharacterXP(player, tostring(key), n) end)
                if ok and res == true then
                    applied = true
                    print(string.format("[RunResult] Applied %d XP to instanceId=%s for %s", n, tostring(key), player.Name))
                end
            end)

            if not applied then
                -- Fallback: try to match by TemplateName in profile instances
                local foundId = nil
                local prefEquip = nil
                pcall(function()
                    local prof = ProfileService:Get(player)
                    if prof and prof.Characters and prof.Characters.Instances then
                        -- prefer equipped matches
                        local equipped = prof.Characters.EquippedOrder or {}
                        local lowerKey = tostring(key):lower()
                        for _, instId in ipairs(equipped) do
                            local inst = prof.Characters.Instances[instId]
                            if inst and inst.TemplateName and tostring(inst.TemplateName):lower() == lowerKey then
                                foundId = instId
                                prefEquip = true
                                break
                            end
                        end
                        if not foundId then
                            for instId, inst in pairs(prof.Characters.Instances) do
                                if inst and inst.TemplateName then
                                    local tpl = tostring(inst.TemplateName)
                                    if tpl == tostring(key) or tpl:lower() == lowerKey then
                                        foundId = instId
                                        break
                                    end
                                    -- also accept when key contains the template name as prefix (ephemeral ids from run)
                                    if tostring(key):sub(1, #tpl) == tpl then
                                        foundId = instId
                                        break
                                    end
                                end
                            end
                        end
                    end
                end)

                if foundId then
                    local ok2 = false
                    pcall(function()
                        local ok, res = pcall(function() return CharacterService:AddCharacterXP(player, foundId, n) end)
                        if ok and res == true then ok2 = true end
                    end)
                    if ok2 then
                        print(string.format("[RunResult] Applied %d XP to matched Template '%s' -> instanceId=%s for %s", n, tostring(key), tostring(foundId), player.Name))
                        applied = true
                    else
                        warn(string.format("[RunResult] Failed to apply XP to matched instance %s (template=%s) for %s", tostring(foundId), tostring(key), player.Name))
                    end
                else
                    warn(string.format("[RunResult] No matching profile instance for CharacterXP key='%s' for player %s", tostring(key), player.Name))
                end
            end
        end
    end

    -- 3) Rewards: Gold / Gems / Items (optional fields)
    local rewards = runResult.Rewards
    if type(rewards) == "table" then
        local totalItems = 0
        if type(rewards.Items) == "table" then
            for _, it in ipairs(rewards.Items) do
                totalItems = totalItems + (tonumber(it and it.Quantity) or 0)
            end
        end
        print(string.format("[RunResult] Rewards summary -> Gold=%s Gems=%s Items=%d",
            tostring(rewards.Gold or 0), tostring(rewards.Gems or 0), totalItems))
        local acc = profile.Account
        if acc then
            acc.Coins = (acc.Coins or 0) + (tonumber(rewards.Gold) or 0)
            acc.Gems = (acc.Gems or 0) + (tonumber(rewards.Gems) or 0)
        end
        -- Items format from run: { { Id="headband", Quantity=2 }, ... }
        -- These are stackable drop items (category "evolve"). Store them under profile.Drops.evolve.
        local items = rewards.Items
        if type(items) == "table" and #items > 0 then
            for _, it in ipairs(items) do
                local id = tostring(it and it.Id or "")
                local q = tonumber(it and it.Quantity) or 0
                if id ~= "" and q > 0 then
                    -- Validate against Evolve registry if present; otherwise accept
                    local okAdd, errOrRes = pcall(function()
                        return ProfileService:AddDropItem(player, "evolve", id, q)
                    end)
                    if not okAdd then
                        warn("[RunResult] AddDropItem failed:", errOrRes)
                    end
                end
            end
        end
        -- Log post-apply account balances for verification
        if acc then
            print(string.format("[RunResult] Post-apply balances -> Coins=%d Gems=%d", tonumber(acc.Coins) or 0, tonumber(acc.Gems) or 0))
        end
    end

    -- 4) Story progression if provided and win true
    if runResult.Win and type(runResult.Story) == "table" then
        local mapId = tostring(runResult.Story.MapId or "")
        local lvl = tonumber(runResult.Story.Level)
        if mapId ~= "" and lvl and lvl >= 1 then
            pcall(function()
                ProfileService:MarkStoryLevelCompleted(player, mapId, lvl)
            end)
        end
    end

    -- Notify client and persist
    local snapshot = ProfileService:BuildClientSnapshot(profile)
    ProfileUpdatedRE:FireClient(player, { full = snapshot })
    pcall(function() ProfileService:Save(player) end)

    -- Mark applied RunId on profile to avoid duplicate application
    if runId then
        pcall(function()
            profile.Meta = profile.Meta or {}
            profile.Meta.AppliedRuns = profile.Meta.AppliedRuns or {}
            profile.Meta.AppliedRuns[runId] = true
            ProfileService:Save(player)
            print(string.format("[RunResult] Applied and marked RunId=%s for %s", runId, tostring(player.Name)))
        end)
    end
end

Players.PlayerAdded:Connect(function(player)
    -- Ensure profile is loaded first
    local profile = ProfileService:CreateOrLoad(player)
    -- Read TeleportData
    local ok, td = pcall(function()
        return TeleportService:GetPlayerTeleportData(player)
    end)
    if ok and type(td) == "table" and td.RunResult then
        print(string.format("[RunResult] TeleportData RunResult present for %s, applying RunId=%s", player.Name, tostring(td.RunResult and td.RunResult.RunId)))
        applyRunResult(player, td.RunResult)
        -- Cleanup saved RunResult in DS if present
        pcall(function()
            local key = "RunResults:" .. tostring(player.UserId)
            -- New behavior: clear the saved latest result entirely after TeleportData apply
            RunResultsDS:SetAsync(key, {})
            print(string.format("[RunResult] Cleared latest saved RunResults DS for %s", player.Name))
        end)
        -- Also consume any other saved results (e.g., previous disconnects)
        consumeAllSavedRunResults(player)
    else
        -- No RunResult via TeleportData. Try fallback: check CompletedLevels DS written by run place
        local doneFallback = false
        local succ, res = pcall(function()
            local key = "CompletedLevels:" .. tostring(player.UserId)
            return CompletedDS:GetAsync(key)
        end)
        if succ and type(res) == "table" and res.Maps then
            -- Apply any completed entries to profile story
            for mapId, lvl in pairs(res.Maps) do
                local n = tonumber(lvl) or 0
                if n >= 1 then
                    pcall(function()
                        ProfileService:MarkStoryLevelCompleted(player, tostring(mapId), n)
                    end)
                    doneFallback = true
                end
            end
            if doneFallback then
                -- Persist the profile after applying fallback progress
                pcall(function() ProfileService:Save(player) end)
            end
        end

        -- still push initial snapshot so UI binds (after fallback application if any)
        local snap = ProfileService:BuildClientSnapshot(profile)
        ProfileUpdatedRE:FireClient(player, { full = snap })
        -- Additionally, try to consume any saved RunResults (full rewards) from the run place
        consumeAllSavedRunResults(player)
    end
end)

print("[RunResult] Handler loaded (lobby)")
