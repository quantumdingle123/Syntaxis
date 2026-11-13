-- ==============================================================================
-- [ SYNTAX HUB - MODULE: Bloom.lua ]
-- ==============================================================================
return function(S)
    local Services, LocalPlayer, UniversalCompat, State, isMapClosed = S.Services, S.LocalPlayer, S.UniversalCompat, S.State, S.isMapClosed
    local getRemote, Remotes, GameModules, getAliveRig, isHoldingEgg = S.getRemote, S.Remotes, S.GameModules, S.getAliveRig, S.isHoldingEgg
    local getSaveData = S.getSaveData

    -- [ ENCHANTED / BLOOM EVENT MANAGER (hot.lua anti-cheat safe implementation) ]
    -- ==============================================================================
    local BloomManager = {
        IsBusy = false,
        LastTradeCraft = 0,
        LastWispAction = 0,
        LastWispFailure = 0,
        TrackedButterflies = {},
        NetReach = 14,
        CenterPosition = Vector3.new(6700, 74, -364),
        TradeTiers = { "Green", "Blue", "Purple" },
        CostMap = { Green = 10, Blue = 10, Purple = 50 },
        EssenceCost = { Green = 240, Blue = 115, Purple = 40, Golden = 1 }
    }

    -- Initialize event-driven butterfly tracking from remotes
    pcall(function()
        local flagsMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Flags") and Services.ReplicatedStorage.Shared.Flags:FindFirstChild("ButterflyFlags")
        if flagsMod then
            local ok, flags = pcall(require, flagsMod)
            if ok and flags and flags.NetReach and flags.NetReach.Get then
                BloomManager.NetReach = tonumber(flags.NetReach:Get()) or 14
            end
            if ok and flags then
                if flags.GreenToBlueCost and flags.GreenToBlueCost.Get then BloomManager.CostMap.Green = tonumber(flags.GreenToBlueCost:Get()) or 10 end
                if flags.BlueToPurpleCost and flags.BlueToPurpleCost.Get then BloomManager.CostMap.Blue = tonumber(flags.BlueToPurpleCost:Get()) or 10 end
                if flags.PurpleToGoldenCost and flags.PurpleToGoldenCost.Get then BloomManager.CostMap.Purple = tonumber(flags.PurpleToGoldenCost:Get()) or 50 end
                if flags.EssenceGreen and flags.EssenceGreen.Get then BloomManager.EssenceCost.Green = tonumber(flags.EssenceGreen:Get()) or 240 end
                if flags.EssenceBlue and flags.EssenceBlue.Get then BloomManager.EssenceCost.Blue = tonumber(flags.EssenceBlue:Get()) or 115 end
                if flags.EssencePurple and flags.EssencePurple.Get then BloomManager.EssenceCost.Purple = tonumber(flags.EssencePurple:Get()) or 40 end
                if flags.EssenceGolden and flags.EssenceGolden.Get then BloomManager.EssenceCost.Golden = tonumber(flags.EssenceGolden:Get()) or 1 end
            end
        end
    end)

    pcall(function()
        local reSpawned = getRemote("RE/Butterflies/Spawned")
        if reSpawned and reSpawned:IsA("RemoteEvent") then
            reSpawned.OnClientEvent:Connect(function(arg1, arg2)
                local bf = (type(arg1) == "table" and arg1) or (type(arg2) == "table" and arg2)
                if bf and bf.Id then
                    BloomManager.TrackedButterflies[bf.Id] = bf
                end
            end)
        end
        local reRemoved = getRemote("RE/Butterflies/Removed")
        if reRemoved and reRemoved:IsA("RemoteEvent") then
            reRemoved.OnClientEvent:Connect(function(id)
                if id then BloomManager.TrackedButterflies[id] = nil end
            end)
        end
        local reEscaped = getRemote("RE/Butterflies/Escaped")
        if reEscaped and reEscaped:IsA("RemoteEvent") then
            reEscaped.OnClientEvent:Connect(function(id)
                if id then BloomManager.TrackedButterflies[id] = nil end
            end)
        end
    end)

    function BloomManager:IsEventActive()
        local endsAt = tonumber(workspace:GetAttribute("ButterflyBloomEndsAt"))
        local isEvent = (workspace:GetAttribute("Event_ButterflyBloom") == true)
        if isEvent then
            if endsAt then return workspace:GetServerTimeNow() < endsAt end
            return true
        end
        return false
    end

    function BloomManager:GetButterflyNet()
        local char = LocalPlayer.Character
        if not char then return nil end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and (item:GetAttribute("ButterflyNet") == true or tostring(item:GetAttribute("ItemType")) == "ButterflyNet" or item.Name == "Butterfly Net") then
                return item
            end
        end
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") and (item:GetAttribute("ButterflyNet") == true or tostring(item:GetAttribute("ItemType")) == "ButterflyNet" or item.Name == "Butterfly Net") then
                    return item
                end
            end
        end
        return nil
    end

    function BloomManager:EnsureNetEquipped()
        local tool = self:GetButterflyNet()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if tool and char and hum then
            if tool.Parent ~= char then
                pcall(function() hum:EquipTool(tool) end)
            end
            return tool
        end
        if Remotes.ClaimNet then
            pcall(function() Remotes.ClaimNet:InvokeServer() end)
            task.wait(0.2)
            local claimed = self:GetButterflyNet()
            if claimed and char and hum and claimed.Parent ~= char then
                pcall(function() hum:EquipTool(claimed) end)
            end
            return claimed
        end
        return nil
    end

    function BloomManager:GetGroundPosition(targetPos)
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local filter = {}
        local char = LocalPlayer.Character
        if char then table.insert(filter, char) end
        local swarm = Services.Workspace:FindFirstChild("ButterflyBloomSwarm")
        if swarm then table.insert(filter, swarm) end
        rayParams.FilterDescendantsInstances = filter

        local hit = Services.Workspace:Raycast(targetPos + Vector3.new(0, 25, 0), Vector3.new(0, -120, 0), rayParams)
        local _, _, hum = getAliveRig()
        local hipHeight = (hum and hum.HipHeight) or 2
        if hit then
            return Vector3.new(targetPos.X, hit.Position.Y + hipHeight + 1, targetPos.Z)
        end
        return targetPos
    end

    function BloomManager:GetLiveButterflies()
        local list = {}
        local swarm = Services.Workspace:FindFirstChild("ButterflyBloomSwarm")
        if swarm then
            for _, b in ipairs(swarm:GetChildren()) do
                if b:IsA("Model") or b:IsA("BasePart") then
                    table.insert(list, b)
                end
            end
        end
        if #list == 0 then
            for id, data in pairs(self.TrackedButterflies) do
                if data and data.Position then
                    table.insert(list, data)
                end
            end
        end
        return list
    end

    function BloomManager:HasWork()
        if isMapClosed() then return false end
        if getgenv().config.autoCatchButterfly and self:IsEventActive() then
            return true
        end
        if getgenv().config.autoWispQuest and self:HasWispWork() then
            return true
        end
        if (getgenv().config.autoTradeUp or getgenv().config.autoCraftEssence) and self:HasMachineWork() then
            return true
        end
        return false
    end

    local function getWispTargetPosition(kind)
        local world = Services.Workspace:FindFirstChild("World") or Services.Workspace:FindFirstChild("__OBJECTS") or Services.Workspace
        local build = world:FindFirstChild("Build") or Services.Workspace:FindFirstChild("Build")

        if kind == "WispSpawn" then
            local p = build and build:FindFirstChild("EnchantedForestZone") and build.EnchantedForestZone:FindFirstChild("WispSpawn")
            if not p then p = Services.Workspace:FindFirstChild("WispSpawn", true) end
            if p then
                return (p:IsA("BasePart") and p.Position) or (p:IsA("Model") and p:GetPivot().Position) or (p:IsA("Attachment") and p.WorldPosition)
            end
        elseif kind == "WispAnchor" then
            local p = build and build:FindFirstChild("EnchantedForestZone")
            local anchor = p and p:FindFirstChild("Zone13Props") and p.Zone13Props:FindFirstChild("EnchantedTree") and p.Zone13Props.EnchantedTree:FindFirstChild("WispAnchor")
            if not anchor and p then anchor = p:FindFirstChild("WispAnchor") end
            if not anchor then anchor = Services.Workspace:FindFirstChild("WispAnchor", true) end
            if anchor then
                return (anchor:IsA("BasePart") and anchor.Position) or (anchor:IsA("Model") and anchor:GetPivot().Position) or (anchor:IsA("Attachment") and anchor.WorldPosition)
            end
        end
        return nil
    end

    function BloomManager:StepTowards(targetPos, maxDuration)
        local _, root, hum = getAliveRig()
        if not root or not hum then return false end

        pcall(function() LocalPlayer:RequestStreamAroundAsync(targetPos) end)
        local deadline = os.clock() + (maxDuration or 10.0)

        while os.clock() < deadline do
            local _, curRoot, curHum = getAliveRig()
            if not curRoot or not curHum then return false end

            local horizDiff = Vector3.new(targetPos.X - curRoot.Position.X, 0, targetPos.Z - curRoot.Position.Z)
            local dist = horizDiff.Magnitude
            if dist <= 6 then
                return true
            end

            if dist > 35 then
                -- Smooth horizontal waypoint stepping (matching hot.lua stepTo)
                local speed = tonumber(getgenv().config.butterflySpeed) or 320
                local stepSize = math.clamp(speed * 0.1, 15, 45)
                local stepTarget = curRoot.Position + horizDiff.Unit * math.min(dist, stepSize)

                -- Raycast to align with ground altitude
                local ground = self:GetGroundPosition(stepTarget)
                curRoot.CFrame = CFrame.new(Vector3.new(stepTarget.X, ground.Y, stepTarget.Z))
                -- Preserve gravity / zero horizontal velocity
                curRoot.AssemblyLinearVelocity = Vector3.new(0, math.clamp(curRoot.AssemblyLinearVelocity.Y, -50, 50), 0)
                task.wait(0.08)
            else
                -- Close proximity: walk with Humanoid:MoveTo for natural arrival
                curHum:MoveTo(targetPos)
                task.wait(0.15)
            end
        end

        local _, endRoot = getAliveRig()
        return endRoot and (targetPos - endRoot.Position).Magnitude <= 10
    end

    function BloomManager:HandleFusery(quest)
        local save = getSaveData()
        if not save then return end

        local finishRevealRemote = getRemote("RF/Fusery/FinishReveal")
        if save.FusionLocked then
            if type(save.FusionEggReward) == "table" and finishRevealRemote then
                pcall(function() finishRevealRemote:InvokeServer() end)
            end
            return
        end

        local areaId = type(quest.Match) == "table" and quest.Match.AreaId
        local areaConfigs = Services.ReplicatedStorage:FindFirstChild("Data") and Services.ReplicatedStorage.Data:FindFirstChild("Areas") and Services.ReplicatedStorage.Data.Areas:FindFirstChild("Configs")
        local dropCategories = {}
        if areaConfigs and areaId then
            local cfgMod = areaConfigs:FindFirstChild(tostring(areaId))
            if cfgMod and cfgMod:IsA("ModuleScript") then
                local ok, cfg = pcall(require, cfgMod)
                if ok and cfg and type(cfg.DropTable) == "table" then
                    for _, row in ipairs(cfg.DropTable) do
                        local cat = row[1] or row.Category
                        if cat then dropCategories[tostring(cat)] = true end
                    end
                end
            end
        end

        local readyPets = {}
        if type(save.Inventory) == "table" then
            for petUid, petData in pairs(save.Inventory) do
                if type(petData) == "table" and not petData.IsFavorite and not petData.InFuse then
                    local cat = tostring(petData.AssetCategory)
                    if dropCategories[cat] or not areaId then
                        table.insert(readyPets, petUid)
                        if #readyPets >= 3 then break end
                    end
                end
            end
        end

        if #readyPets >= 3 then
            local ejectRemote = getRemote("RF/Fusery/EjectPet")
            local briefingRemote = getRemote("RF/Fusery/ConfirmBriefing")
            local loadRemote = getRemote("RF/Fusery/LoadPet")
            local fuseRemote = getRemote("RF/Fusery/BeginFuse")

            local fusionSlots = (type(save.FusionSlots) == "table" and save.FusionSlots) or {}
            local readyMap = { [readyPets[1]] = true, [readyPets[2]] = true, [readyPets[3]] = true }
            local loadedMap = {}

            for _, slotPet in ipairs(fusionSlots) do
                if readyMap[slotPet] then
                    loadedMap[slotPet] = true
                elseif ejectRemote then
                    pcall(function() ejectRemote:InvokeServer(slotPet) end)
                    task.wait(0.2)
                end
            end

            if save.FusionInfoAcknowledged == false and briefingRemote then
                pcall(function() briefingRemote:InvokeServer() end)
                task.wait(0.2)
            end

            for _, pUid in ipairs(readyPets) do
                if not loadedMap[pUid] and loadRemote then
                    pcall(function() loadRemote:InvokeServer(pUid) end)
                    task.wait(0.2)
                end
            end

            if fuseRemote then
                pcall(function() fuseRemote:InvokeServer() end)
                task.wait(0.3)
            end
        end
    end

    function BloomManager:HasWispWork()
        if isMapClosed() then return false end
        if os.clock() - self.LastWispAction < 2.0 then return false end
        if os.clock() - self.LastWispFailure < 15.0 then return false end

        local save = getSaveData()
        local wispComp = save and save.WispCompanion
        if type(wispComp) ~= "table" then return false end
        if wispComp.Unlocked == true then return false end

        local wispData = GameModules:Get("Wisp")
        local reqSpeed = (wispData and tonumber(wispData.RequiredSpeedPower)) or 50000000000
        local stageCount = (wispData and tonumber(wispData.StageCount)) or 4

        if not wispComp.Accepted then
            if (tonumber(save.SpeedPower) or 0) < reqSpeed then return false end
            local build = Services.Workspace:FindFirstChild("Build")
            if not (build and build:GetAttribute("EnchantedForestZoneRevealed") == true) then return false end
            return true
        end

        local stage = tonumber(wispComp.Stage) or 1
        if stage >= stageCount then
            return true
        end

        local quest = wispData and wispData.List and wispData.List[stage]
        if quest then
            local isClaimed = type(wispComp.Claimed) == "table" and wispComp.Claimed[quest.Id]
            local progress = type(wispComp.Progress) == "table" and tonumber(wispComp.Progress[quest.Id]) or 0
            local target = tonumber(quest.Target) or 1
            if not isClaimed and progress >= target then
                return true
            end

            if quest.Event == "PetFused" then
                if save.FusionLocked then return true end
                local count = 0
                if type(save.Inventory) == "table" then
                    for _, pet in pairs(save.Inventory) do
                        if type(pet) == "table" and not pet.IsFavorite and not pet.InFuse then
                            count = count + 1
                        end
                    end
                end
                if count >= 3 then return true end
            end
        end

        return false
    end

    function BloomManager:ProcessWisp()
        local save = getSaveData()
        local wispComp = save and save.WispCompanion
        if type(wispComp) ~= "table" or wispComp.Unlocked == true then return end

        local remote = getRemote("RF/WispCompanion/Request")
        if not remote then return end

        local wispData = GameModules:Get("Wisp")
        local reqSpeed = (wispData and tonumber(wispData.RequiredSpeedPower)) or 50000000000
        local stageCount = (wispData and tonumber(wispData.StageCount)) or 4

        -- 1. Unaccepted Quest -> Meet Wisp at WispSpawn
        if not wispComp.Accepted then
            if (tonumber(save.SpeedPower) or 0) < reqSpeed then
                self.LastWispFailure = os.clock()
                return
            end
            local build = Services.Workspace:FindFirstChild("Build")
            if not (build and build:GetAttribute("EnchantedForestZoneRevealed") == true) then
                self.LastWispFailure = os.clock()
                return
            end

            local spawnPos = getWispTargetPosition("WispSpawn")
            if not spawnPos then
                self.LastWispFailure = os.clock()
                return
            end

            if self:StepTowards(spawnPos, 12.0) then
                task.wait(0.5)
                local ok = pcall(function() remote:InvokeServer("Accept") end)
                if ok then
                    self.LastWispAction = os.clock()
                else
                    self.LastWispFailure = os.clock()
                end
            else
                self.LastWispFailure = os.clock()
            end
            return
        end

        local stage = tonumber(wispComp.Stage) or 1
        local quest = wispData and wispData.List and wispData.List[stage]

        -- 2. Stage Objective Completed -> Claim Reward
        if quest then
            local isClaimed = type(wispComp.Claimed) == "table" and wispComp.Claimed[quest.Id]
            local progress = type(wispComp.Progress) == "table" and tonumber(wispComp.Progress[quest.Id]) or 0
            local target = tonumber(quest.Target) or 1

            if not isClaimed and progress >= target then
                local ok = pcall(function() remote:InvokeServer("Claim", quest.Id) end)
                if ok then
                    self.LastWispAction = os.clock()
                else
                    self.LastWispFailure = os.clock()
                end
                return
            end
        end

        -- 3. All Stages Complete -> Return Wisp to Outdoor WispAnchor
        if stage >= stageCount then
            if not wispComp.Returning then
                pcall(function() remote:InvokeServer("BeginReturn") end)
                task.wait(0.3)
            end

            local anchorPos = getWispTargetPosition("WispAnchor")
            if not anchorPos then
                self.LastWispFailure = os.clock()
                return
            end

            if self:StepTowards(anchorPos, 12.0) then
                task.wait(0.5)
                local ok = pcall(function() remote:InvokeServer("Return") end)
                if ok then
                    self.LastWispAction = os.clock()
                else
                    self.LastWispFailure = os.clock()
                end
            else
                self.LastWispFailure = os.clock()
            end
            return
        end

        -- 4. In-Progress Pet Fusing
        if quest and quest.Event == "PetFused" then
            self:HandleFusery(quest)
            self.LastWispAction = os.clock()
        end
    end

    function BloomManager:HasMachineWork()
        local save = getSaveData()
        local counts = (save and type(save.Butterflies) == "table" and save.Butterflies.Counts) or {}
        if getgenv().config.autoCraftEssence then
            local canCraft = true
            for k, req in pairs(self.EssenceCost) do
                if (counts[k] or 0) < req then canCraft = false break end
            end
            if canCraft then return true end
        end
        if getgenv().config.autoTradeUp then
            for _, tier in ipairs(self.TradeTiers) do
                if (counts[tier] or 0) >= (self.CostMap[tier] or 10) then
                    return true
                end
            end
        end
        return false
    end

    function BloomManager:EnterEnchantedTree()
        if LocalPlayer:GetAttribute("InEnchantedTree") == true then return true end
        local world = Services.Workspace:FindFirstChild("World") or Services.Workspace
        local enterTrigger = world:FindFirstChild("EnchantedTreeEntrance", true) or world:FindFirstChild("EnterTrigger", true)
        local prompt = enterTrigger and enterTrigger:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and prompt.Parent then
            local tPos = prompt.Parent:IsA("BasePart") and prompt.Parent.Position or prompt.Parent:GetPivot().Position
            local _, root, hum = getAliveRig()
            if root then
                root.CFrame = CFrame.new(tPos + Vector3.new(0, 2, -4))
                root.AssemblyLinearVelocity = Vector3.zero
                task.wait(0.2)
                UniversalCompat.FireProximityPrompt(prompt)
                local timeout = os.clock() + 4.0
                while os.clock() < timeout do
                    if LocalPlayer:GetAttribute("InEnchantedTree") == true then return true end
                    task.wait(0.1)
                end
            end
        end
        return LocalPlayer:GetAttribute("InEnchantedTree") == true
    end

    function BloomManager:LeaveEnchantedTree()
        if LocalPlayer:GetAttribute("InEnchantedTree") ~= true then return true end
        local interior = Services.Workspace:FindFirstChild("EnchantedTreeInterior", true)
        local exitPart = interior and interior:FindFirstChild("ExitTrigger", true)
        if exitPart and exitPart:IsA("BasePart") then
            local _, root = getAliveRig()
            if root then
                root.CFrame = exitPart.CFrame
                root.AssemblyLinearVelocity = Vector3.zero
                UniversalCompat.FireTouch(root, exitPart)
                local prompt = exitPart:FindFirstChildWhichIsA("ProximityPrompt")
                if prompt then UniversalCompat.FireProximityPrompt(prompt) end
                local timeout = os.clock() + 3.0
                while os.clock() < timeout do
                    if LocalPlayer:GetAttribute("InEnchantedTree") ~= true then return true end
                    task.wait(0.1)
                end
            end
        end
        return true
    end

    function BloomManager:Process()
        if State.isStealingActive or isHoldingEgg() then return end
        self.IsBusy = true

        -- 1. Catch Butterflies
        if getgenv().config.autoCatchButterfly and self:IsEventActive() then
            self:EnsureNetEquipped()
            local _, root, hum = getAliveRig()
            if root and hum then
                local mode = getgenv().config.bloomCatchMode or "Stand"
                local butterflies = self:GetLiveButterflies()

                if mode == "Stand" then
                    -- Safely stand at Bloom center, swing at butterflies in NetReach (14 studs)
                    local distToCenter = (root.Position - self.CenterPosition).Magnitude
                    if distToCenter > 12 then
                        local groundCenter = self:GetGroundPosition(self.CenterPosition)
                        root.CFrame = CFrame.new(groundCenter)
                        root.AssemblyLinearVelocity = Vector3.zero
                        task.wait(0.2)
                    end

                    for _, b in ipairs(butterflies) do
                        local bPos = (typeof(b.Position) == "Vector3" and b.Position) or (b:IsA("BasePart") and b.Position) or (b:IsA("Model") and b:GetPivot().Position)
                        if bPos and (bPos - root.Position).Magnitude <= (self.NetReach + 4) then
                            local tool = self:EnsureNetEquipped()
                            if tool then pcall(function() tool:Activate() end) end
                            task.wait(0.1)
                        end
                    end
                else
                    -- Chase mode: smooth ground navigation to nearest or rarest butterfly
                    local bestB = nil
                    local bestDist = math.huge
                    for _, b in ipairs(butterflies) do
                        local bPos = (typeof(b.Position) == "Vector3" and b.Position) or (b:IsA("BasePart") and b.Position) or (b:IsA("Model") and b:GetPivot().Position)
                        if bPos then
                            local d = (bPos - root.Position).Magnitude
                            if d < bestDist and d <= 250 then
                                bestDist = d
                                bestB = b
                            end
                        end
                    end

                    if bestB then
                        local bPos = (typeof(bestB.Position) == "Vector3" and bestB.Position) or (bestB:IsA("BasePart") and bestB.Position) or (bestB:GetPivot().Position)
                        local groundPos = self:GetGroundPosition(bPos)
                        local speed = tonumber(getgenv().config.butterflySpeed) or 320
                        local dir = (groundPos - root.Position)
                        if dir.Magnitude > 6 then
                            root.CFrame = CFrame.new(root.Position + dir.Unit * math.min(dir.Magnitude, speed * 0.05))
                        end
                        local tool = self:EnsureNetEquipped()
                        if tool and (bPos - root.Position).Magnitude <= self.NetReach then
                            pcall(function() tool:Activate() end)
                        end
                    end
                end
            end
        end

        -- 2. Wisp Quests & Progression (hot.lua event-gated architecture)
        if getgenv().config.autoWispQuest and self:HasWispWork() then
            self:ProcessWisp()
        end

        -- 3. In-Tree Machine Trade Up & Essence Crafting
        if (getgenv().config.autoTradeUp or getgenv().config.autoCraftEssence) and self:HasMachineWork() then
            if os.clock() - self.LastTradeCraft >= 2.0 then
                self.LastTradeCraft = os.clock()
                if self:EnterEnchantedTree() then
                    local tradeRemote = getRemote("RF/Butterflies/AskTradeUp")
                    local craftRemote = getRemote("RF/Butterflies/AskCraftEssence")

                    if getgenv().config.autoTradeUp and tradeRemote then
                        local save = getSaveData()
                        local counts = (save and type(save.Butterflies) == "table" and save.Butterflies.Counts) or {}
                        for _, tier in ipairs(self.TradeTiers) do
                            local req = self.CostMap[tier] or 10
                            if (counts[tier] or 0) >= req then
                                pcall(function() tradeRemote:InvokeServer("ButterflyMachine", tier) end)
                                task.wait(0.2)
                            end
                        end
                    end

                    if getgenv().config.autoCraftEssence and craftRemote then
                        pcall(function() craftRemote:InvokeServer("MutationShrine") end)
                        task.wait(0.2)
                    end

                    self:LeaveEnchantedTree()
                end
            end
        end

        self.IsBusy = false
    end

    -- Export shared bindings to module context
    S.BloomManager = BloomManager
end
