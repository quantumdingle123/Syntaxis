-- ==============================================================================
-- [ SYNTAX HUB - MODULE: Scheduler.lua ]
-- ==============================================================================
return function(S)
    local Services, LocalPlayer, currentSettings, State, isMapClosed = S.Services, S.LocalPlayer, S.currentSettings, S.State, S.isMapClosed
    local isNormalStealPanelTarget, isStealEnabled, Remotes, isHoldingEgg, hopOffTreadmill = S.isNormalStealPanelTarget, S.isStealEnabled, S.Remotes, S.isHoldingEgg, S.hopOffTreadmill
    local getPlayerMoney, getSaveData, BloomManager = S.getPlayerMoney, S.getSaveData, S.BloomManager

    -- [ TASK PRIORITY ARBITRATOR ]
    -- ==============================================================================
    S.PriorityManager = {
        ActiveTask = nil,
        ActiveTaskExpiresAt = 0,
        List = {
            "Auto Steal",
            "UFO Event",
            "Enchanted / Bloom Event",
            "Auto Treadmill"
        },
        TaskAliases = {
            ["Steal"] = "Auto Steal",
            ["Auto Steal"] = "Auto Steal",
            ["UFO"] = "UFO Event",
            ["Auto UFO"] = "UFO Event",
            ["UFO Event"] = "UFO Event",
            ["Bloom"] = "Enchanted / Bloom Event",
            ["Bloom Event"] = "Enchanted / Bloom Event",
            ["Enchanted"] = "Enchanted / Bloom Event",
            ["Enchanted / Bloom Event"] = "Enchanted / Bloom Event",
            ["Treadmill"] = "Auto Treadmill",
            ["Auto Treadmill"] = "Auto Treadmill"
        }
    }

    function S.PriorityManager:Initialize(savedPriorities)
        local canonicalList = {
            "Auto Steal",
            "UFO Event",
            "Enchanted / Bloom Event",
            "Auto Treadmill"
        }

        local valid = {}
        for _, name in ipairs(canonicalList) do valid[name] = true end

        if type(savedPriorities) == "table" and #savedPriorities > 0 then
            local newList = {}
            for _, rawName in ipairs(savedPriorities) do
                local name = self.TaskAliases[rawName] or rawName
                if valid[name] then
                    table.insert(newList, name)
                    valid[name] = nil
                end
            end
            for canonIndex, name in ipairs(canonicalList) do
                if valid[name] then
                    table.insert(newList, math.min(canonIndex, #newList + 1), name)
                end
            end
            self.List = newList
        else
            self.List = canonicalList
        end
    end

    function S.PriorityManager:GetRank(taskName)
        local resolved = self.TaskAliases[taskName] or taskName
        for index, name in ipairs(self.List) do
            if name == resolved then
                return index
            end
        end
        return 999
    end

    function S.PriorityManager:IsLocked()
        if self.ActiveTask ~= nil then
            if os.clock() < self.ActiveTaskExpiresAt then
                return true
            else
                self.ActiveTask = nil
                self.ActiveTaskExpiresAt = 0
                return false
            end
        end
        return false
    end

    function S.PriorityManager:Acquire(taskName, maxDuration)
        local resolved = self.TaskAliases[taskName] or taskName
        maxDuration = maxDuration or 15.0

        if not self:IsLocked() then
            if resolved ~= "Auto Treadmill" and resolved ~= "Treadmill" then
                hopOffTreadmill()
            end
            self.ActiveTask = resolved
            self.ActiveTaskExpiresAt = os.clock() + maxDuration
            self:InvalidateCache()
            return true
        elseif self.ActiveTask == resolved then
            self.ActiveTaskExpiresAt = math.max(self.ActiveTaskExpiresAt, os.clock() + maxDuration)
            return true
        end
        return false
    end

    function S.PriorityManager:Claim(taskName)
        return self:Acquire(taskName, 15.0)
    end

    function S.PriorityManager:Release(taskName)
        local resolved = self.TaskAliases[taskName] or taskName
        if self.ActiveTask == resolved or self.ActiveTask == taskName then
            self.ActiveTask = nil
            self.ActiveTaskExpiresAt = 0
            self:InvalidateCache()
        end
    end

    function S.PriorityManager:GetTaskDimension(taskName)
        return "Normal"
    end

    function S.PriorityManager:IsTaskEnabled(taskName)
        local resolved = self.TaskAliases[taskName] or taskName
        if resolved == "Auto Steal" then
            return isStealEnabled() and not isMapClosed()
        elseif resolved == "UFO Event" then
            return (getgenv().config.autoUFO == true or getgenv().config.ufoRocks == true or getgenv().config.ufoTrade == true or getgenv().config.ufoRare == true)
        elseif resolved == "Enchanted / Bloom Event" then
            return (getgenv().config.autoCatchButterfly == true or getgenv().config.autoWispQuest == true or getgenv().config.autoTradeUp == true or getgenv().config.autoCraftEssence == true) and not isMapClosed()
        elseif resolved == "Auto Treadmill" then
            return getgenv().config.autoTreadmill == true
        end
        return false
    end

    function S.PriorityManager:HasWork(taskName)
        local resolved = self.TaskAliases[taskName] or taskName

        if resolved == "Auto Steal" then
            if isMapClosed() or not isStealEnabled() then return false end
            if isNormalStealPanelTarget() then return true end
            if State.isStealingActive or isHoldingEgg() then return true end
            local best = S.getBestEgg and S.getBestEgg()
            return best ~= nil

        elseif resolved == "UFO Event" then
            return S.UFOManager ~= nil and S.UFOManager:HasWork() ~= nil

        elseif resolved == "Enchanted / Bloom Event" then
            if isMapClosed() then return false end
            return BloomManager ~= nil and BloomManager:HasWork()

        elseif resolved == "Auto Treadmill" then
            return getgenv().config.autoTreadmill == true
        end

        return false
    end

    S.PriorityManager._lastTopTask = nil
    S.PriorityManager._lastTopTaskTime = 0

    function S.PriorityManager:InvalidateCache()
        self._lastTopTask = nil
        self._lastTopTaskTime = 0
    end

    function S.PriorityManager:GetTopWantedTask()
        -- ActiveTask mutex lock ownership
        if self:IsLocked() and self.ActiveTask then
            return self.ActiveTask
        end

        local now = os.clock()
        if self._lastTopTaskTime > 0 and (now - self._lastTopTaskTime) < 0.15 then
            return self._lastTopTask
        end

        local topTask = nil

        if isNormalStealPanelTarget() then
            topTask = "Auto Steal"
        elseif isHoldingEgg() or State.isStealingActive then
            topTask = "Auto Steal"
        else
            for _, taskName in ipairs(self.List) do
                if self:IsTaskEnabled(taskName) and self:HasWork(taskName) then
                    topTask = taskName
                    break
                end
            end
        end

        self._lastTopTask = topTask
        self._lastTopTaskTime = now
        return topTask
    end

    function S.PriorityManager:CanRun(taskName)
        local inRace = LocalPlayer:GetAttribute("RaceId") ~= nil
        if inRace and taskName ~= "Race" then
            return false
        end

        local resolved = self.TaskAliases[taskName] or taskName

        -- If another task holds the character lock, no other task can run
        if self:IsLocked() and self.ActiveTask ~= resolved then
            return false
        end

        local topTask = self:GetTopWantedTask()
        if not topTask then
            return false
        end

        return (resolved == topTask)
    end

    function S.PriorityManager:MoveUp(index, saveCallback)
        if index > 1 then
            local item = table.remove(self.List, index)
            table.insert(self.List, index - 1, item)
            if saveCallback then saveCallback(self.List) end
            return true
        end
        return false
    end

    function S.PriorityManager:MoveDown(index, saveCallback)
        if index < #self.List then
            local item = table.remove(self.List, index)
            table.insert(self.List, index + 1, item)
            if saveCallback then saveCallback(self.List) end
            return true
        end
        return false
    end

    S.PriorityManager:Initialize(currentSettings.TaskPriorities)

    -- ==============================================================================
    -- [ CENTRALIZED HEARTBEAT WORKER SCHEDULER (NON-OVERLAPPING) ]
    -- ==============================================================================
    local WorkerScheduler = {
        Tasks = {},
        Connection = nil,
        IsActive = true
    }

    function WorkerScheduler:Register(name, interval, runFn)
        local item = { Name = name, Gap = 0, Interval = interval or 0.35, Hold = 0, Running = false, Run = runFn }
        table.insert(self.Tasks, item)
        return item
    end

    function WorkerScheduler:Start()
        if self.IsRunningLoop then return end
        self.IsRunningLoop = true
        task.spawn(function()
            local lastPrune = 0
            while self.IsActive do
                local dt = task.wait(0.05)
                local now = os.clock()

                -- Periodic Blacklist Memory Pruning (every 30s)
                if now - lastPrune >= 30.0 then
                    lastPrune = now
                    if State and State.blacklistedEggs then
                        for uid, exp in pairs(State.blacklistedEggs) do
                            if now > exp then
                                State.blacklistedEggs[uid] = nil
                            end
                        end
                    end
                end

                for _, t in ipairs(self.Tasks) do
                    t.Gap = t.Gap + dt
                    if t.Hold > 0 then
                        t.Hold = t.Hold - dt
                    elseif not t.Running and t.Gap >= t.Interval then
                        t.Gap = 0
                        t.Running = true
                        task.spawn(function()
                            local ok, err = pcall(t.Run)
                            t.Running = false
                            if not ok and err then
                                t.Hold = 3
                            end
                        end)
                    end
                end
            end
            self.IsRunningLoop = false
        end)
    end

    -- ==============================================================================
    -- [ AUTOMATED UPGRADE CONTROLLERS ]
    -- ==============================================================================
    local function tryUpgradeTreadmill()
        if not Remotes.TierRaise or os.clock() < State.treadmillUpgradeCooldown then return end
        State.treadmillUpgradeCooldown = os.clock() + 5

        local save = getSaveData()
        local myMoney = math.max(getPlayerMoney(), tonumber(save and save.Money) or 0)

        local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
        local treadmillsModule = dataFolder and dataFolder:FindFirstChild("Treadmills")
        if not treadmillsModule then return end

        local ok, tData = pcall(require, treadmillsModule)
        if not ok or type(tData) ~= "table" then return end

        local currentLevel = tonumber(save and save.TreadmillUpgradeLevel) or 0
        if type(tData.GetByUpgradeLevel) == "function" then
            local okNext, nextTier = pcall(tData.GetByUpgradeLevel, currentLevel + 1)
            if okNext and type(nextTier) == "table" then
                local nextId = nextTier._id
                local price = tonumber(nextTier.Price) or math.huge
                if type(nextId) == "string" and myMoney >= price then
                    pcall(function() Remotes.TierRaise:InvokeServer(nextId) end)
                    return
                end
            end
        end

        if type(tData.Directory) == "table" then
            local sorted = {}
            for name, cfg in pairs(tData.Directory) do
                table.insert(sorted, { Name = tostring(name), Price = tonumber(cfg.Price) or 0, Level = tonumber(cfg.UpgradeLevel) or tonumber(cfg.Level) or 0 })
            end
            table.sort(sorted, function(a, b) return a.Price < b.Price end)
            for _, item in ipairs(sorted) do
                if item.Level > currentLevel and myMoney >= item.Price then
                    pcall(function() Remotes.TierRaise:InvokeServer(item.Name) end)
                    break
                end
            end
        end
    end

    local function tryUpgradeBase()
        if not Remotes.BaseTierRaise or os.clock() < State.baseUpgradeCooldown then return end
        State.baseUpgradeCooldown = os.clock() + 5

        local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
        local basesModule = dataFolder and dataFolder:FindFirstChild("Bases")
        if not basesModule then return end

        local ok, bData = pcall(require, basesModule)
        if not ok or type(bData) ~= "table" or type(bData.BASES) ~= "table" then return end

        local save = getSaveData()
        local currentLevel = tonumber(save and save.BaseUpgradeLevel) or 0
        local maxLevel = type(bData.GetMaxBaseLevel) == "function" and tonumber(bData.GetMaxBaseLevel()) or #bData.BASES

        if currentLevel >= maxLevel then return end

        local nextTier = bData.BASES[currentLevel + 1]
        local cost = nextTier and (tonumber(nextTier.Cost) or tonumber(nextTier.Price)) or nil
        local myMoney = math.max(getPlayerMoney(), tonumber(save and save.Money) or 0)

        if cost and myMoney >= cost then
            pcall(function() Remotes.BaseTierRaise:FireServer() end)
        end
    end

    -- Export shared bindings to module context
    S.WorkerScheduler = WorkerScheduler
    S.tryUpgradeTreadmill = tryUpgradeTreadmill
    S.tryUpgradeBase = tryUpgradeBase
end
