-- ==============================================================================
-- [ SYNTAX HUB - MODULE: Safety.lua ]
-- ==============================================================================
return function(S)
    local Services, LocalPlayer, PlayerGui, State, CONFIG = S.Services, S.LocalPlayer, S.PlayerGui, S.State, S.CONFIG
    local cleanName, isBlacklisted, Remotes, EggState = S.cleanName, S.isBlacklisted, S.Remotes, S.EggState

    -- ==============================================================================
    -- [ CHARACTER RIG, GODMODE, & RECOVERY PIPELINE ]
    -- ==============================================================================
    local function getAliveRig()
        local char = LocalPlayer.Character
        if not char then return nil, nil, nil end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if root and hum and hum.Health > 0 then
            return char, root, hum
        end
        return nil, nil, nil
    end

    local function applyGodMode(character)
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end

        -- Respect server ragdoll duration (BAC-10518 protection): never destroy constraints while server ragdoll timer is active
        local ragdollEndTime = tonumber(LocalPlayer:GetAttribute("RagdollEndTime")) or 0
        if ragdollEndTime > workspace:GetServerTimeNow() then
            return
        end

        local blockedStates = {
            Enum.HumanoidStateType.FallingDown,
            Enum.HumanoidStateType.Ragdoll,
            Enum.HumanoidStateType.Physics
        }
        for _, state in ipairs(blockedStates) do
            pcall(function() humanoid:SetStateEnabled(state, false) end)
        end
        pcall(function() humanoid.BreakJointsOnDeath = false end)

        -- BAC-7516 protection: Never touch constraints or Motor6Ds inside a Tool (preserves egg/weapon welds)
        for _, desc in ipairs(character:GetDescendants()) do
            if not desc:FindFirstAncestorWhichIsA("Tool") then
                if desc:IsA("BallSocketConstraint") or desc:IsA("HingeConstraint") or 
                  (desc:IsA("NoCollisionConstraint") and string.find(desc.Name, "Ragdoll", 1, true)) then
                    pcall(function() desc:Destroy() end)
                elseif desc:IsA("Motor6D") and not desc.Enabled then
                    desc.Enabled = true
                end
            end
        end
    end

    local function setCollisions(enabled)
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = enabled
            end
        end
    end

    local function cleanupFlightState()
        if State.activeFlightConnection then
            pcall(function() State.activeFlightConnection:Disconnect() end)
            State.activeFlightConnection = nil
        end

        local _, root, hum = getAliveRig()
        if hum then
            pcall(function()
                hum.PlatformStand = false
                hum.Sit = false
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
        if root then
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end

        for part, _ in pairs(State.activeCollisionsDisabled) do
            if part and part.Parent then
                pcall(function() part.CanCollide = true end)
            end
        end
        table.clear(State.activeCollisionsDisabled)
        setCollisions(true)
    end

    -- ==============================================================================
    -- [ AUDIO & HUD SUPPRESSION MANAGERS ]
    -- ==============================================================================
    local ChaseAudioManager = {
        ActiveSiren = nil,
        SavedTimePos = 0,
        HeartbeatConn = nil,
        NewSoundConn = nil
    }

    function ChaseAudioManager:LockAudio()
        self:UnlockAudio()
        task.spawn(function()
            for _ = 1, 15 do
                if not getgenv().StealUILocked then break end
                local runGui = PlayerGui:FindFirstChild("RunBackEffects")
                if runGui then
                    for _, s in ipairs(runGui:GetDescendants()) do
                        if s:IsA("Sound") and s.IsPlaying then
                            self.ActiveSiren = s
                            break
                        end
                    end
                end
                if self.ActiveSiren then break end
                task.wait(0.1)
            end

            if self.ActiveSiren then
                local siren = self.ActiveSiren
                local sId = siren.SoundId
                local sName = siren.Name

                if self.HeartbeatConn then self.HeartbeatConn:Disconnect() end
                self.HeartbeatConn = Services.RunService.Heartbeat:Connect(function()
                    if not getgenv().StealUILocked then return end
                    if siren and siren.Parent then
                        if siren.IsPlaying and siren.TimePosition > 0.15 then
                            self.SavedTimePos = siren.TimePosition
                        elseif not siren.IsPlaying and self.SavedTimePos > 0.1 then
                            siren.TimePosition = self.SavedTimePos
                            siren.Playing = true
                        elseif siren.IsPlaying and siren.TimePosition < 0.2 and self.SavedTimePos > 0.5 then
                            siren.TimePosition = self.SavedTimePos
                        end
                    end
                end)

                if self.NewSoundConn then self.NewSoundConn:Disconnect() end
                self.NewSoundConn = Services.SoundService.DescendantAdded:Connect(function(newSnd)
                    if getgenv().StealUILocked and newSnd:IsA("Sound") and newSnd ~= siren then
                        if newSnd.SoundId == sId or newSnd.Name == sName then
                            newSnd.Volume = 0
                            task.defer(function() pcall(function() newSnd:Stop() end) end)
                        end
                    end
                end)
            end
        end)
    end

    function ChaseAudioManager:UnlockAudio()
        if self.HeartbeatConn then self.HeartbeatConn:Disconnect(); self.HeartbeatConn = nil end
        if self.NewSoundConn then self.NewSoundConn:Disconnect(); self.NewSoundConn = nil end
        if self.ActiveSiren and self.ActiveSiren.Parent then
            pcall(function() self.ActiveSiren:Stop() end)
        end
        self.ActiveSiren = nil
        self.SavedTimePos = 0
    end

    local StealUIManager = {
        Connections = {},
        NormalGameplayGuis = {}
    }

    function StealUIManager:SnapshotNormalHUD()
        table.clear(self.NormalGameplayGuis)
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled == true then
                if gui.Name ~= "SyntaxHubGUI" and gui.Name ~= "RunBackEffects" and gui.Name ~= "DropHeldEgg" then
                    self.NormalGameplayGuis[gui] = true
                end
            end
        end
    end

    function StealUIManager:Lock()
        if getgenv().StealUILocked then return end
        getgenv().StealUILocked = true

        for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
        table.clear(self.Connections)

        for gui, _ in pairs(self.NormalGameplayGuis) do
            if gui and gui.Parent then
                gui.Enabled = false
                local c = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if getgenv().StealUILocked and gui.Enabled then
                        gui.Enabled = false
                    end
                end)
                table.insert(self.Connections, c)
            end
        end
        ChaseAudioManager:LockAudio()
    end

    function StealUIManager:Unlock()
        getgenv().StealUILocked = false

        for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
        table.clear(self.Connections)

        for gui, _ in pairs(self.NormalGameplayGuis) do
            if gui and gui.Parent then
                gui.Enabled = true
            end
        end
        table.clear(self.NormalGameplayGuis)
        ChaseAudioManager:UnlockAudio()
    end

    -- ==============================================================================
    -- [ ANTI-CHEAT & UGI SHIELD CONTROLLER ]
    -- ==============================================================================
    local ShieldManager = {
        OriginalHumanoid = nil,
        CloneHumanoid = nil,
        Links = {},
        DisabledUGI = {}
    }

    function ShieldManager:RebindControls(humanoid)
        pcall(function()
            local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
            local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
            if playerModule then
                local controls = require(playerModule):GetControls()
                if type(controls) == "table" then
                    controls.humanoid = humanoid
                end
            end
        end)
    end

    function ShieldManager:CleanupLinks()
        for _, conn in ipairs(self.Links) do pcall(function() conn:Disconnect() end) end
        table.clear(self.Links)
    end

    function ShieldManager:ApplyHumanoidSwap(character)
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        if self.CloneHumanoid and self.CloneHumanoid.Parent == character then return end

        self:CleanupLinks()
        local clone = humanoid:Clone()
        humanoid.Parent = nil
        clone.Parent = character
        Services.Workspace.CurrentCamera.CameraSubject = clone
        self:RebindControls(clone)

        self.OriginalHumanoid = humanoid
        self.CloneHumanoid = clone

        table.insert(self.Links, clone:GetPropertyChangedSignal("Health"):Connect(function()
            if clone and clone.Parent and clone.Health < clone.MaxHealth then
                clone.Health = clone.MaxHealth
            end
        end))

        table.insert(self.Links, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if clone and clone.Parent then
                clone.WalkSpeed = humanoid.WalkSpeed
            end
        end))

        table.insert(self.Links, clone.Died:Connect(function()
            self:UndoSwap()
        end))
    end

    function ShieldManager:UndoSwap()
        self:CleanupLinks()
        local char = LocalPlayer.Character
        local orig = self.OriginalHumanoid
        local clone = self.CloneHumanoid
        self.OriginalHumanoid = nil
        self.CloneHumanoid = nil

        if orig and clone and char and orig.Parent == nil and clone.Parent == char then
            orig.Parent = char
            Services.Workspace.CurrentCamera.CameraSubject = orig
            self:RebindControls(orig)
            pcall(function() clone:Destroy() end)
        end
    end

    local function isMonitorAction(fn)
        if not debug or not debug.getconstants then return false end
        local ok, consts = pcall(debug.getconstants, fn)
        if not ok or type(consts) ~= "table" then return false end
        for _, val in pairs(consts) do
            if val == "Relocate" or val == "SetWalkSpeed" or val == "BeginRagdoll" or val == "BeginImpulse" then
                return true
            end
        end
        return false
    end

    function ShieldManager:MuteUGI()
        if type(getconnections) ~= "function" then return end
        for _, event in ipairs({ Services.RunService.Heartbeat, Services.RunService.PreSimulation, Services.RunService.PostSimulation }) do
            for _, conn in ipairs(getconnections(event)) do
                local fn = conn.Function
                if typeof(fn) == "function" then
                    local ok, src = pcall(debug.info, fn, "s")
                    if ok and src and string.find(tostring(src), "UGI", 1, true) then
                        if not isMonitorAction(fn) and conn.Enabled then
                            if pcall(function() conn:Disable() end) then
                                table.insert(self.DisabledUGI, conn)
                            end
                        end
                    end
                end
            end
        end
    end

    function ShieldManager:UnmuteUGI()
        for _, conn in ipairs(self.DisabledUGI) do
            pcall(function() conn:Enable() end)
        end
        table.clear(self.DisabledUGI)
    end

    -- Cleanly resets character on server if flagged or blocked from treadmill
    local function resetFlaggedCharacter()
        if os.clock() - State.lastResetTime < 15 then return end
        State.lastResetTime = os.clock()
        State.treadmillFailCount = 0

        pcall(function() ShieldManager:UndoSwap() end)
        if Remotes.AskDoff then
            pcall(function() Remotes.AskDoff:InvokeServer() end)
        end

        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum then
            pcall(function()
                hum:UnequipTools()
                hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
                hum.BreakJointsOnDeath = true
                hum.RequiresNeck = true
                hum.Health = 0
                hum:ChangeState(Enum.HumanoidStateType.Dead)
                char:BreakJoints()
            end)
            if Remotes.AskRigWipe then
                pcall(function() Remotes.AskRigWipe:FireServer(char) end)
            end
        end
    end

    local function abortStealRoutine()
        State.currentStealSession = State.currentStealSession + 1
        State.isStealingActive = false
        if State.targetedSpecificUid then
            if State.activeStealButtons[State.targetedSpecificUid] then
                State.activeStealButtons[State.targetedSpecificUid].BackgroundColor3 = S.activeTheme and S.activeTheme.Accent or Color3.fromRGB(92, 170, 255)
                State.activeStealButtons[State.targetedSpecificUid].Text = "Steal"
            end
            State.targetedSpecificUid = nil
        end

        if S.PriorityManager then
            S.PriorityManager:Release("Steal")
            S.PriorityManager:Release("Auto Steal")
        end

        ShieldManager:UnmuteUGI()
        ShieldManager:UndoSwap()
        StealUIManager:Unlock()
        cleanupFlightState()
        setCollisions(true)

        local _, root, hum = getAliveRig()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        if hum then
            hum.PlatformStand = false
            hum.Sit = false
        end
    end

    local function isAtBasePlot()
        local _, root = getAliveRig()
        if not root then return false end
        return (root.Position - CONFIG.BaseDropPosition).Magnitude <= 45
    end

    LocalPlayer.CharacterAdded:Connect(function(newChar)
        task.wait(0.3)
        abortStealRoutine()
        applyGodMode(newChar)
    end)

    if LocalPlayer.Character then
        applyGodMode(LocalPlayer.Character)
    end

    -- ==============================================================================
    -- [ PET & RARITY MASTER REGISTRY ]
    -- ==============================================================================
    local MasterRegistry = {
        RarityRanks = {},
        PetDatabase = {},
        IsReady = false
    }

    function MasterRegistry:Build()
        local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
        if not dataFolder then return false end

        self.RarityRanks = {
            Common = 1, Uncommon = 2, SuperRare = 2, Rare = 3, Epic = 4,
            Legendary = 5, Mythic = 6, Rainbow = 6, Cosmic = 7, Secret = 8,
            Limited = 9, Eternal = 9, Divine = 10, Transcendent = 10
        }

        local assetsModule = dataFolder:FindFirstChild("Assets")
        if assetsModule and assetsModule:IsA("ModuleScript") then
            local s, assets = pcall(require, assetsModule)
            if s and type(assets) == "table" and type(assets.Directory) == "table" then
                for pName, pData in pairs(assets.Directory) do
                    if type(pData) == "table" and pData.Rarity and type(pData.Rarity) == "table" then
                        local rId = pData.Rarity._id or pData.Rarity.DisplayName
                        local rRank = tonumber(pData.Rarity.RarityNumber or pData.Rarity.Rank) or (rId and self.RarityRanks[rId]) or 1
                        self.PetDatabase[tostring(pName)] = {
                            Rarity = tostring(rId or "Unknown"),
                            Rank = rRank,
                            Icon = pData.Icon or "",
                            EarningRate = tonumber(pData.EarningRate) or 0
                        }
                    end
                end
            end
        end

        self.IsReady = true
        return true
    end

    function MasterRegistry:Lookup(rawName)
        if not rawName then return "Common", 1 end
        rawName = tostring(rawName)
        local direct = self.PetDatabase[rawName]
        if direct then return direct.Rarity, direct.Rank end
        if self.RarityRanks[rawName] then return rawName, self.RarityRanks[rawName] end

        local clean = rawName:gsub("[Ee]gg", ""):gsub("[Pp]ure", ""):gsub("[Gg]olden", ""):gsub("[Ss]hiny", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local cleaned = self.PetDatabase[clean]
        if cleaned then return cleaned.Rarity, cleaned.Rank end

        for petName, data in pairs(self.PetDatabase) do
            if string.find(rawName, petName, 1, true) then
                return data.Rarity, data.Rank
            end
        end
        return "Common", 1
    end

    MasterRegistry:Build()

    local NameResolver = { Aliases = {} }
    function NameResolver:Register(name1, name2)
        if not name1 then return end
        local c1 = cleanName(name1)
        self.Aliases[c1] = c1
        if name2 then
            local c2 = cleanName(name2)
            self.Aliases[c2] = c1
        end
    end

    function NameResolver:Build()
        local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
        local assetsModule = dataFolder and dataFolder:FindFirstChild("Assets")
        if assetsModule and assetsModule:IsA("ModuleScript") then
            local s, assets = pcall(require, assetsModule)
            if s and type(assets) == "table" and type(assets.Directory) == "table" then
                for id, data in pairs(assets.Directory) do
                    self:Register(id, type(data) == "table" and data.DisplayName or nil)
                end
            end
        end
        self:Register("Kaiju Spider", "Spideron")
        self:Register("Blade Head", "Bladehide")
        self:Register("Snowy Owl", "Snowy Owl")
        self:Register("Salamander", "Salamander")
        self:Register("Cosmic Fox", "Cosmic Fox")
        self:Register("Spirit Hare", "Spirit Hare")
        self:Register("Demon Hound", "Demon Hound")
        self:Register("Spirit Panda", "Spirit Panda")
    end

    function NameResolver:Matches(name1, name2)
        if not name1 or not name2 then return false end
        local c1, c2 = cleanName(name1), cleanName(name2)
        if c1 == c2 then return true end
        if self.Aliases[c1] and self.Aliases[c2] and self.Aliases[c1] == self.Aliases[c2] then return true end
        if self.Aliases[c1] and self.Aliases[c1] == c2 then return true end
        if self.Aliases[c2] and self.Aliases[c2] == c1 then return true end
        if c1:find(c2, 1, true) or c2:find(c1, 1, true) then return true end
        return false
    end

    NameResolver:Build()

    local EggDetector = { IsHolding = false }
    function EggDetector:CheckHolding()
        if EggState and typeof(EggState) == "table" then
            if EggState.Carrying == true or (EggState.CarryUid ~= nil and EggState.CarryUid ~= "") then
                return true
            end
        end
        local dropGui = PlayerGui:FindFirstChild("DropHeldEgg")
        local runGui = PlayerGui:FindFirstChild("RunBackEffects")
        if (dropGui and dropGui:IsA("ScreenGui") and dropGui.Enabled) or 
           (runGui and runGui:IsA("ScreenGui") and runGui.Enabled) then
            return true
        end

        return false
    end

    local function isHoldingEgg()
        return EggDetector:CheckHolding()
    end

    local function hopOffTreadmill()
        pcall(function()
            if Remotes.AskDoff then Remotes.AskDoff:InvokeServer() end
        end)
        local _, root, hum = getAliveRig()
        if root then
            root.Anchored = false
            root.CFrame = root.CFrame + root.CFrame.LookVector * 6
        end
        if hum then
            hum.PlatformStand = false
            hum.Sit = false
            pcall(function()
                hum.Jump = true
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
    end

    local function dropHeldEggDirect()
        if EggState and typeof(EggState.DropFieldEgg) == "function" then
            pcall(function() EggState.DropFieldEgg("PlayerRequest") end)
        end
        if Remotes.AskFieldEggDrop then
            pcall(function() Remotes.AskFieldEggDrop:InvokeServer({ Reason = "PlayerRequest" }) end)
        end
    end

    local function getPlayerMoney()
        local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
        if leaderstats then
            for _, child in ipairs(leaderstats:GetChildren()) do
                local lName = string.lower(child.Name)
                if lName:find("money") or lName:find("cash") or lName:find("coin") or lName:find("currency") or lName:find("gold") then
                    if child:IsA("ValueBase") then return tonumber(child.Value) or 0 end
                end
            end
        end
        return 0
    end

    local function getSaveData()
        local saveMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Save")
        if saveMod and saveMod:IsA("ModuleScript") then
            local s, mod = pcall(require, saveMod)
            if s and type(mod) == "table" then
                local getter = type(mod.Get) == "function" and mod.Get or (type(mod.Peek) == "function" and mod.Peek)
                if getter then
                    local ok, res = pcall(getter)
                    if ok and type(res) == "table" then return res end
                end
            end
        end
        return nil
    end

    local function getPhysicalEggPosition(uid, fallbackPos)
        local eggModel = Services.Workspace:FindFirstChild(uid)
        if eggModel then
            local ok, pivot = pcall(function() return eggModel:GetPivot().Position end)
            if ok and pivot then return pivot end
        end
        local slots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
        local slotModel = slots and slots:FindFirstChild(uid)
        if slotModel then
            local ok, pivot = pcall(function() return slotModel:GetPivot().Position end)
            if ok and pivot then return pivot end
        end
        return fallbackPos
    end

    local function isEggStillValid(uid)
        if not uid then return false end
        if isBlacklisted(uid) then return false end
        if not EggState or type(EggState.ReadFieldEggs) ~= "function" then return true end

        local data = nil
        pcall(function() data = EggState.ReadFieldEggs() end)
        if not data or not data.Records then return true end

        for rUid, record in pairs(data.Records) do
            if type(record) == "table" then
                if rUid == uid or record.Uid == uid then
                    if record.State == "Claimed" or record.State == "Carried" then return false end
                    return true
                end
            end
        end
        return false
    end

    local function getMinRequiredScore()
        local sel = getgenv().config.minRarity or "All"
        if sel == "All" then return 1 end
        local num = tonumber(string.match(tostring(sel), "^(%d+)"))
        return num or (MasterRegistry.RarityRanks[sel] or 1)
    end

    -- Export shared bindings to module context
    S.getAliveRig = getAliveRig
    S.setCollisions = setCollisions
    S.cleanupFlightState = cleanupFlightState
    S.StealUIManager = StealUIManager
    S.ShieldManager = ShieldManager
    S.resetFlaggedCharacter = resetFlaggedCharacter
    S.abortStealRoutine = abortStealRoutine
    S.MasterRegistry = MasterRegistry
    S.isHoldingEgg = isHoldingEgg
    S.hopOffTreadmill = hopOffTreadmill
    S.dropHeldEggDirect = dropHeldEggDirect
    S.getPlayerMoney = getPlayerMoney
    S.getSaveData = getSaveData
    S.getPhysicalEggPosition = getPhysicalEggPosition
    S.isEggStillValid = isEggStillValid
    S.getMinRequiredScore = getMinRequiredScore
end
