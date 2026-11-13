-- ==============================================================================
-- [ SYNTAX HUB - MODULE: UFO.lua ]
-- ==============================================================================
return function(S)
    local Services, LocalPlayer, UniversalCompat, State, isMapClosed = S.Services, S.LocalPlayer, S.UniversalCompat, S.State, S.isMapClosed
    local getRemote, invokeRemote, fireRemote, getAliveRig, isHoldingEgg = S.getRemote, S.invokeRemote, S.fireRemote, S.getAliveRig, S.isHoldingEgg

    -- ==============================================================================
    -- [ UFO EVENT MANAGER (hot.lua reference implementation) ]
    -- ==============================================================================
    S.UFOManager = {
        IsBusy = false,
        State = {
            st = {},
            sus = {},
            eggs = 0,
            no = 0,
            left = nil
        },
        Codes = { "4827", "0327" },
        PipeValueMap = { Straight = 5, Elbow = 3, Cross = 15 },
        PipeDirs = {
            { 1, -1, 0, 4 },
            { 2, 0, 1, 8 },
            { 4, 1, 0, 1 },
            { 8, 0, -1, 2 }
        }
    }

    pcall(function()
        local reState = getRemote("RE/UFOSightings/State")
        if reState and reState:IsA("RemoteEvent") then
            reState.OnClientEvent:Connect(function(st)
                if type(st) == "table" then
                    S.UFOManager.State.st = st
                    S.UFOManager.State.sus = {}
                    for _, uid in ipairs(st.Suspicious or {}) do
                        S.UFOManager.State.sus[uid] = true
                    end
                end
            end)
        end
    end)

    function S.UFOManager:FetchState()
        local fetchRemote = getRemote("RF/UFOSightings/Fetch")
        if fetchRemote and fetchRemote:IsA("RemoteFunction") then
            local ok, st = pcall(function() return fetchRemote:InvokeServer() end)
            if ok and type(st) == "table" then
                self.State.st = st
                self.State.sus = {}
                for _, uid in ipairs(st.Suspicious or {}) do
                    self.State.sus[uid] = true
                end
                return st
            end
        end
        return nil
    end

    function S.UFOManager:GetUfoPosition()
        local ufo = self.State.st and self.State.st.Ufo
        if not ufo then return nil end
        if typeof(ufo) == "Instance" then
            if ufo:IsA("Model") then
                return ufo:GetPivot().Position
            elseif ufo:IsA("BasePart") then
                return ufo.Position
            end
        elseif typeof(ufo) == "Vector3" then
            return ufo
        end
        return nil
    end

    task.spawn(function()
        task.wait(1.0)
        pcall(function() S.UFOManager:FetchState() end)
    end)

    function S.UFOManager:RotateMask(mask, steps)
        for i = 1, steps do
            mask = bit32.band(bit32.bor(bit32.lshift(mask, 1), bit32.rshift(mask, 3)), 15)
        end
        return mask
    end

    function S.UFOManager:SolvePipePuzzle(seed)
        local puzzleMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Modules") and Services.ReplicatedStorage.Shared.Modules:FindFirstChild("UFOSightingsPipePuzzle")
        if not puzzleMod then return nil end
        local ok, puzzleLib = pcall(require, puzzleMod)
        if not ok or not puzzleLib or typeof(puzzleLib.Generate) ~= "function" then return nil end

        local grid = puzzleLib.Generate(seed)
        local visited = {}
        local rotations = {}

        for r = 1, 5 do
            for c = 1, 5 do
                rotations[((r - 1) * 5) + c] = grid[r][c].Rotation
            end
        end

        local function dfs(r, c, enterBit)
            local idx = ((r - 1) * 5) + c
            visited[idx] = true

            for rot = 0, 3 do
                local basePiece = grid[r][c].Piece
                local pieceMask = self.PipeValueMap[basePiece] or 5
                local rotated = self:RotateMask(pieceMask, rot)

                if bit32.band(rotated, enterBit) ~= 0 then
                    rotations[idx] = rot
                    if r == 4 and c == 5 and bit32.band(rotated, 2) ~= 0 then
                        return true
                    end

                    for _, dirData in ipairs(self.PipeDirs) do
                        local outBit, dr, dc, oppBit = dirData[1], dirData[2], dirData[3], dirData[4]
                        if outBit ~= enterBit and bit32.band(rotated, outBit) ~= 0 then
                            local nr, nc = r + dr, c + dc
                            if nr >= 1 and nr <= 5 and nc >= 1 and nc <= 5 then
                                local nIdx = ((nr - 1) * 5) + nc
                                if not visited[nIdx] then
                                    if dfs(nr, nc, oppBit) then return true end
                                end
                            end
                        end
                    end
                end
            end

            visited[idx] = nil
            return false
        end

        if dfs(2, 1, 8) then
            return rotations
        end
        return nil
    end

    function S.UFOManager:IsInRareUFO()
        local interior = self.State.st and self.State.st.Interior
        if interior and (tonumber(interior.EndsAt) or 0) > 0 then return true end
        local rareModel = Services.Workspace:FindFirstChild("RareUFOInterior")
        return rareModel ~= nil
    end

    function S.UFOManager:HasWork()
        local anyUfo = getgenv().config.autoUFO or getgenv().config.ufoRocks or getgenv().config.ufoTrade or getgenv().config.ufoRare
        if not anyUfo then return nil end
        local st = self.State.st or {}

        -- Strict hot.lua event gate (lines 20295-20330): if UFO event is not available or locked, do NOTHING
        if not st.Available then return nil end
        if st.SpeedLocked or st.Tutorial then return nil end
        if State.isStealingActive or isHoldingEgg() then return nil end

        if self:IsInRareUFO() then return "inside" end
        if os.clock() < (self.State.no or 0) then return nil end
        if isMapClosed() then return nil end

        if getgenv().config.autoUFO then
            if not st.Unlocked then return "repair" end
            if st.Reward then return "reward" end
        end
        if getgenv().config.ufoRocks and st.Rocks and st.Rocks.List and #st.Rocks.List > 0 then return "rocks" end
        if getgenv().config.ufoTrade and (st.SpaceRocks or 0) >= (st.RockCost or math.huge) then return "trade" end
        if getgenv().config.ufoRare and st.Event and st.Event.Variant == "Rare" and st.Decoded and st.Event.Id ~= self.State.left then
            return "board"
        end
        if getgenv().config.autoUFO then
            if st.Event and st.Required and not st.Decoded and not st.Complete then return "decode" end
            if st.Event and st.Decoded and not st.Complete and st.Event.Variant ~= "Rare" then return "hold" end
        end
        return nil
    end

    function S.UFOManager:IsUfoEgg(eggRecord, uid)
        if not getgenv().config.autoUFO then return false end
        local st = self.State.st
        if not (st and st.Available and st.Event and st.Decoded and not st.Complete and st.Event.Variant ~= "Rare") then
            return false
        end
        if uid and self.State.sus[uid] then return true end
        if next(self.State.sus) == nil and eggRecord then
            local area = eggRecord.AreaId or (eggRecord.Record and eggRecord.Record.AreaId)
            if tostring(area) == tostring(st.Biome) then return true end
        end
        return false
    end

    function S.UFOManager:Process()
        local work = self:HasWork()
        if not work then return end
        local _, root, hum = getAliveRig()
        if not root or not hum then return end
        self.IsBusy = true

        -- 1. REPAIR (NPC talk + 5x5 Pipe Puzzle with direct return unpacking)
        if work == "repair" then
            local camp = Services.Workspace:FindFirstChild("UFOSightingsCamp")
            local repairSuccess = false
            if camp then
                if not self.State.st.MetChaser then
                    local chaser = camp:FindFirstChild("AlienChaser")
                    local cRoot = chaser and chaser:FindFirstChild("HumanoidRootPart")
                    if cRoot then
                        root.CFrame = CFrame.new(cRoot.Position + Vector3.new(0, 2, -4))
                        root.AssemblyLinearVelocity = Vector3.zero
                        task.wait(0.3)
                        invokeRemote("RF/UFOSightings/Talk")
                        self:FetchState()
                    end
                end

                local repairPoint = camp:FindFirstChild("Root") and camp.Root:FindFirstChild("RepairPoint")
                local rPos = repairPoint and (repairPoint:IsA("Attachment") and repairPoint.WorldPosition or repairPoint.Position)
                if rPos then
                    root.CFrame = CFrame.new(rPos + Vector3.new(0, 2, 0))
                    root.AssemblyLinearVelocity = Vector3.zero
                    task.wait(0.2)
                    local ok, success, puzzleData = invokeRemote("RF/UFOSightings/Repair", "Begin")

                    if ok and success and type(puzzleData) == "table" and puzzleData.Seed then
                        local solvedRotations = self:SolvePipePuzzle(puzzleData.Seed)
                        if solvedRotations then
                            task.wait(3.4)
                            invokeRemote("RF/UFOSightings/Repair", "Finish", { Id = puzzleData.Id, Rotations = solvedRotations })
                            self:FetchState()
                            repairSuccess = true
                        end
                    end
                end
            end
            -- Back off 60s if repair was not ready or failed (matching hot.lua line 21045)
            if not repairSuccess then
                self.State.no = os.clock() + 60
            end

        -- 2. DECODE (Equip signal decoder, locate UFO with preserved gravity & runway alignment)
        elseif work == "decode" then
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            local function getDecoder()
                for _, t in ipairs(root.Parent:GetChildren()) do
                    if t:IsA("Tool") and t:GetAttribute("UFOSignalDecoder") == true then return t end
                end
                if backpack then
                    for _, t in ipairs(backpack:GetChildren()) do
                        if t:IsA("Tool") and t:GetAttribute("UFOSignalDecoder") == true then return t end
                    end
                end
                return nil
            end

            local decoder = getDecoder()
            if decoder and hum then
                pcall(function() hum:EquipTool(decoder) end)
                local timeout = os.clock() + 60.0
                local bestSignal = 0
                local bestX = root.Position.X
                local dir = 1
                local nextEquipCheck = os.clock() + 0.5

                while os.clock() < timeout do
                    if not self.State.st.Event or self.State.st.Decoded then break end

                    -- Re-equip check every 0.5s (matching hot.lua line 20706-20714)
                    if os.clock() >= nextEquipCheck then
                        nextEquipCheck = os.clock() + 0.5
                        local curDecoder = getDecoder()
                        if curDecoder and curDecoder.Parent ~= root.Parent then
                            pcall(function() hum:EquipTool(curDecoder) end)
                        end
                    end

                    local signal = tonumber(self.State.st.Signal) or 0
                    local curX = root.Position.X
                    if signal > bestSignal then
                        bestSignal = signal
                        bestX = curX
                    end

                    if curX > 6950 and dir > 0 then
                        dir = -1
                    elseif curX < 650 and dir < 0 then
                        dir = 1
                    end

                    local speed = (signal < 2 and 180) or 80
                    local targetVelX = dir * speed

                    -- Peak-overshoot tracking and direction reversal matching hot.lua lines 20726-20736
                    if bestSignal >= 4 then
                        targetVelX = math.clamp((bestX - curX) * 5, -60, 60)
                    else
                        if signal < bestSignal then
                            if math.abs(bestX - curX) < 20 then
                                bestSignal = signal
                                dir = -dir
                            else
                                targetVelX = math.sign(bestX - curX) * math.min(speed, 120)
                            end
                        end
                    end

                    -- Preserves AssemblyLinearVelocity.Y so Roblox gravity acts naturally (NO FLOATING!)
                    -- Actively steers character along runway at Z = -365 (matching hot.lua line 20735)
                    root.AssemblyLinearVelocity = Vector3.new(
                        targetVelX,
                        root.AssemblyLinearVelocity.Y,
                        math.clamp((-365 - root.Position.Z) * 5, -50, 50)
                    )
                    task.wait(0.05)
                end
                root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
                pcall(function() hum:UnequipTools() end)
                self:FetchState()
            end

        -- 3. BOARD RARE UFO MOTHERSHIP
        elseif work == "board" then
            local uPos = self:GetUfoPosition()
            if uPos then
                local targetPos = uPos - Vector3.new(0, 85, 0)
                -- Smooth approach over up to 2 seconds to avoid raw CFrame rubberbanding
                local approachTimeout = os.clock() + 2.0
                while os.clock() < approachTimeout and not self:IsInRareUFO() do
                    local diff = targetPos - root.Position
                    if diff.Magnitude <= 8 then break end
                    root.CFrame = CFrame.new(root.Position + diff.Unit * math.min(diff.Magnitude, 30))
                    root.AssemblyLinearVelocity = Vector3.zero
                    task.wait(0.08)
                end
                root.CFrame = CFrame.new(targetPos)
                root.AssemblyLinearVelocity = Vector3.zero

                local timeout = os.clock() + 8.0
                while os.clock() < timeout and not self:IsInRareUFO() do
                    task.wait(0.1)
                end
            end

        -- 4. INSIDE RARE UFO (Smash capsules, crack keypad 4827/0327, claim staff, exit)
        elseif work == "inside" then
            local rareInterior = Services.Workspace:FindFirstChild("RareUFOInterior")
            local capsules = rareInterior and rareInterior:FindFirstChild("Interactables") and rareInterior.Interactables:FindFirstChild("Capsules")

            -- Smash capsules with equipped melee bat weapon
            local function getWeapon()
                for _, t in ipairs(root.Parent:GetChildren()) do
                    if t:IsA("Tool") and t.Name ~= "UFOSignalDecoder" and t.Name ~= "Butterfly Net" then return t end
                end
                local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
                if bp then
                    for _, t in ipairs(bp:GetChildren()) do
                        if t:IsA("Tool") and t.Name ~= "UFOSignalDecoder" and t.Name ~= "Butterfly Net" then return t end
                    end
                end
                return nil
            end

            local weapon = getWeapon()
            if weapon and hum and weapon.Parent ~= root.Parent then
                pcall(function() hum:EquipTool(weapon) end)
            end

            if capsules then
                for _, cap in ipairs(capsules:GetChildren()) do
                    if cap:IsA("Model") and not (self.State.st.Interior and self.State.st.Interior.Broken and table.find(self.State.st.Interior.Broken, cap.Name)) then
                        -- Collect rocks inside interior (matching hot.lua line 20839)
                        local intRocks = self.State.st.Rocks
                        if intRocks and intRocks.List then
                            for _, r in ipairs(intRocks.List) do
                                pcall(function() fireRemote("RE/UFOSightings/CollectRock", intRocks.Id, r.Index) end)
                            end
                        end

                        local capPos = cap:GetPivot().Position
                        root.CFrame = CFrame.new(capPos + Vector3.new(0, 1, 3))
                        root.AssemblyLinearVelocity = Vector3.zero
                        if weapon then
                            if weapon.Parent ~= root.Parent then pcall(function() hum:EquipTool(weapon) end) end
                            pcall(function() weapon:Activate() end)
                        end
                        task.wait(0.4)
                    end
                end
            end

            -- Keypad & Vault Code
            local vault = rareInterior and rareInterior:FindFirstChild("Interactables") and rareInterior.Interactables:FindFirstChild("Vault")
            if vault and self.State.st.Interior and not self.State.st.Interior.VaultOpen then
                local keypad = vault:FindFirstChild("Keypad", true)
                if keypad then
                    root.CFrame = CFrame.new(keypad.Position + Vector3.new(0, 0, 3))
                    root.AssemblyLinearVelocity = Vector3.zero
                    task.wait(0.3)
                    for _, codeStr in ipairs(self.Codes) do
                        local ok, success = invokeRemote("RF/UFOSightings/VaultCode", codeStr)
                        if ok and success == true then break end
                        task.wait(0.3)
                    end
                    task.wait(1.5)
                    self:FetchState()
                end
            end

            -- Claim Alien Staff
            local alienStaff = vault and vault:FindFirstChild("AlienStaff")
            local staffRoot = alienStaff and alienStaff:FindFirstChild("Root")
            if staffRoot and self.State.st.Interior and self.State.st.Interior.VaultOpen and not self.State.st.Interior.VaultClaimed then
                root.CFrame = CFrame.new(staffRoot.Position + Vector3.new(0, 1, 0))
                root.AssemblyLinearVelocity = Vector3.zero
                task.wait(0.3)
                invokeRemote("RF/UFOSightings/VaultClaim")
                task.wait(0.5)
                self:FetchState()
            end

            -- Exit Rare UFO
            local leavePart = rareInterior and rareInterior:FindFirstChild("LeavePart")
            if leavePart then
                root.CFrame = CFrame.new(leavePart.Position)
                root.AssemblyLinearVelocity = Vector3.zero
                local prompt = leavePart:FindFirstChild("LeaveUFO") or leavePart:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then
                    pcall(function()
                        prompt.HoldDuration = 0
                        UniversalCompat.FireProximityPrompt(prompt)
                    end)
                end
                local exitWait = os.clock() + 5.0
                while os.clock() < exitWait and self:IsInRareUFO() do
                    task.wait(0.2)
                end
            end
            self.State.left = self.State.st.Event and self.State.st.Event.Id
            self:FetchState()

        -- 5. ROCKS (Collect space rocks with distance check)
        elseif work == "rocks" then
            local rocks = self.State.st.Rocks
            if rocks and rocks.List and #rocks.List > 0 then
                for _, rock in ipairs(rocks.List) do
                    if rock and rock.Position then
                        local dist = (root.Position - rock.Position).Magnitude
                        if dist > 20 then
                            root.CFrame = CFrame.new(rock.Position + Vector3.new(0, 2, 0))
                            root.AssemblyLinearVelocity = Vector3.zero
                            task.wait(0.08)
                        end
                        pcall(function() fireRemote("RE/UFOSightings/CollectRock", rocks.Id, rock.Index) end)
                        task.wait(0.12)
                    end
                end
                task.wait(0.3)
                self:FetchState()
            end

        -- 6. TRADE (Trade space rocks at Alien Camp - PRESERVED 100%)
        elseif work == "trade" then
            local camp = Services.Workspace:FindFirstChild("UFOSightingsCamp")
            local chaser = camp and camp:FindFirstChild("AlienChaser")
            local tradePoint = chaser and chaser:FindFirstChild("HumanoidRootPart") and chaser.HumanoidRootPart:FindFirstChild("TradePoint")
            local tPos = tradePoint and (tradePoint:IsA("Attachment") and tradePoint.WorldPosition or tradePoint.Position)
            local tradeSuccess = false
            if tPos then
                root.CFrame = CFrame.new(tPos + Vector3.new(0, 2, 0))
                root.AssemblyLinearVelocity = Vector3.zero
                task.wait(0.2)
                while (self.State.st.SpaceRocks or 0) >= (self.State.st.RockCost or math.huge) do
                    local ok, traded = pcall(function() return invokeRemote("RF/UFOSightings/Trade", self.State.st.RockCost) end)
                    if not ok or not traded then break end
                    tradeSuccess = true
                    self:FetchState()
                    task.wait(0.3)
                end
            end
            -- Back off 60s if trade was not ready or failed (matching hot.lua line 21045)
            if not tradeSuccess then
                self.State.no = os.clock() + 60
            end

        -- 7. REWARD (Collect decoded/event reward)
        elseif work == "reward" then
            local reward = self.State.st.Reward
            if reward and reward.Position and reward.Id then
                local dist = (root.Position - reward.Position).Magnitude
                if dist > 20 then
                    root.CFrame = CFrame.new(reward.Position + Vector3.new(0, 2, 0))
                    root.AssemblyLinearVelocity = Vector3.zero
                    task.wait(0.15)
                end
                invokeRemote("RF/UFOSightings/Collect", reward.Id)
                self:FetchState()
            end

        -- 8. HOLD (Wait for tractor beam egg delivery without hogging character)
        elseif work == "hold" then
            root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
            local holdTimeout = os.clock() + 5.0
            while os.clock() < holdTimeout do
                local st = self.State.st
                if not (st and st.Available and st.Event and st.Decoded and not st.Complete and st.Event.Variant ~= "Rare") then
                    break
                end
                task.wait(0.2)
            end
            self:FetchState()
        end

        self.IsBusy = false
    end
end
