-- ==============================================================================
-- [ SYNTAX HUB - MODULE: Workers.lua ]
-- ==============================================================================
return function(S)
    local Services, LocalPlayer, State, CONFIG, isBlacklisted = S.Services, S.LocalPlayer, S.State, S.CONFIG, S.isBlacklisted
    local blacklistEgg, isMapClosed, isNormalStealPanelTarget, isStealEnabled, isFastStealArea = S.blacklistEgg, S.isMapClosed, S.isNormalStealPanelTarget, S.isStealEnabled, S.isFastStealArea
    local matchesTargetArea, Remotes, getFieldEggRecords, getAliveRig, cleanupFlightState = S.matchesTargetArea, S.Remotes, S.getFieldEggRecords, S.getAliveRig, S.cleanupFlightState
    local StealUIManager, ShieldManager, resetFlaggedCharacter, MasterRegistry, isHoldingEgg = S.StealUIManager, S.ShieldManager, S.resetFlaggedCharacter, S.MasterRegistry, S.isHoldingEgg
    local hopOffTreadmill, getPhysicalEggPosition, isEggStillValid, getMinRequiredScore, BloomManager = S.hopOffTreadmill, S.getPhysicalEggPosition, S.isEggStillValid, S.getMinRequiredScore, S.BloomManager
    local WorkerScheduler, tryUpgradeTreadmill, tryUpgradeBase, runAlongGroundToEgg, executeFastStealOutbound = S.WorkerScheduler, S.tryUpgradeTreadmill, S.tryUpgradeBase, S.runAlongGroundToEgg, S.executeFastStealOutbound
    local findMyPlot, instantGrabAtPosition, executeCheckpointedHopsHome, executeFastStealDelivery = S.findMyPlot, S.instantGrabAtPosition, S.executeCheckpointedHopsHome, S.executeFastStealDelivery

    local function travelPlaneSegment(targetPos, stopDist, speed, timeout, sessionId, targetUid)
        local char, root = getAliveRig()
        if not root then return false end

        stopDist = stopDist or 4
        local startTime = os.clock()
        local reached = false
        local lastLiveCheck = 0

        State.activeFlightConnection = Services.RunService.Heartbeat:Connect(function()
            if sessionId ~= State.currentStealSession or not isStealEnabled() or isMapClosed() then
                if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
                return
            end

            local _, cRoot = getAliveRig()
            if not cRoot then
                if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
                return
            end

            if targetUid and (os.clock() - lastLiveCheck >= 0.25) then
                lastLiveCheck = os.clock()
                if not isEggStillValid(targetUid) then
                    blacklistEgg(targetUid, 15)
                    if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
                    return
                end
            end

            local currentPos = cRoot.Position
            local delta = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
            local dist = delta.Magnitude

            if dist <= stopDist then
                reached = true
                cRoot.AssemblyLinearVelocity = Vector3.zero
                if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
                return
            end

            if (os.clock() - startTime) > timeout then
                cRoot.AssemblyLinearVelocity = Vector3.zero
                if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
                return
            end

            local moveDir = delta.Unit
            cRoot.AssemblyLinearVelocity = Vector3.new(moveDir.X * speed, 0, moveDir.Z * speed)
            cRoot.CFrame = CFrame.new(currentPos.X, CONFIG.FlightAltitude, currentPos.Z) * CFrame.lookAt(Vector3.zero, moveDir)
        end)

        while State.activeFlightConnection and State.activeFlightConnection.Connected do
            Services.RunService.Heartbeat:Wait()
        end

        return reached and (sessionId == State.currentStealSession) and isStealEnabled() and not isMapClosed()
    end

    local function flyOutboundElevated(targetPosition, stopDistance, sessionId, targetUid)
        local char, root, humanoid = getAliveRig()
        if not root or not humanoid then return false end

        StealUIManager:SnapshotNormalHUD()
        stopDistance = stopDistance or 4

        local playerSpeed = humanoid.WalkSpeed
        if not playerSpeed or playerSpeed <= 0 then playerSpeed = 16 end

        table.clear(State.activeCollisionsDisabled)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                State.activeCollisionsDisabled[part] = true
                part.CanCollide = false
            end
        end

        humanoid.PlatformStand = true

        local function snapAltitude(targetY)
            local _, cRoot = getAliveRig()
            if cRoot then
                pcall(function()
                    cRoot.CFrame = CFrame.new(cRoot.Position.X, targetY, cRoot.Position.Z) * cRoot.CFrame.Rotation
                    cRoot.AssemblyLinearVelocity = Vector3.zero
                end)
                task.wait(0.03)
            end
        end
        snapAltitude(CONFIG.FlightAltitude)

        local currentPosInit = root.Position
        if currentPosInit.X < CONFIG.BoundaryCheckpointX then
            local centerDeliveryPos = Vector3.new(CONFIG.BaseDropPosition.X, CONFIG.FlightAltitude, CONFIG.BaseDropPosition.Z)
            local mouthPos = Vector3.new(CONFIG.BoundaryCheckpointX, CONFIG.FlightAltitude, CONFIG.BaseDropPosition.Z)

            local lateralDist = math.abs(currentPosInit.Z - CONFIG.BaseDropPosition.Z)
            if lateralDist > 12 or currentPosInit.X < CONFIG.BaseDropPosition.X then
                local ok = travelPlaneSegment(centerDeliveryPos, 4, playerSpeed, 20, sessionId, targetUid)
                if not ok then cleanupFlightState() return false end
            end

            local ok2 = travelPlaneSegment(mouthPos, 4, playerSpeed, 20, sessionId, targetUid)
            if not ok2 then cleanupFlightState() return false end
        end

        local finalDelta = Vector3.new(targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
        local dynamicTimeout = math.max(30, (finalDelta.Magnitude / playerSpeed) + 20)

        local reached = travelPlaneSegment(targetPosition, stopDistance, playerSpeed, dynamicTimeout, sessionId, targetUid)
        if reached and sessionId == State.currentStealSession and isStealEnabled() and not isMapClosed() then
            snapAltitude((targetPosition.Y or CONFIG.GroundAltitude) + CONFIG.AirGrabOffset)
        end

        cleanupFlightState()
        return reached and (sessionId == State.currentStealSession) and isStealEnabled() and not isMapClosed()
    end

    S.getBestEgg = function()
        if isMapClosed() then return nil end
        local records = getFieldEggRecords()
        if not records or next(records) == nil then return nil end
        local data = { Records = records }

        -- Steal Panel Target Handling (Normal Dimension only; never clear while actively stealing or holding an egg!)
        if isNormalStealPanelTarget() then
            for uid, record in pairs(data.Records) do
                if type(record) == "table" then
                    if uid == State.targetedSpecificUid or record.Uid == State.targetedSpecificUid then
                        record.Uid = record.Uid or uid
                        if State.isStealingActive or isHoldingEgg() or (record.State ~= "Claimed" and record.State ~= "Carried") then
                            return record
                        end
                    end
                end
            end

            local directFloorPos = getPhysicalEggPosition(State.targetedSpecificUid, nil)
            if directFloorPos and (State.isStealingActive or isHoldingEgg() or isEggStillValid(State.targetedSpecificUid)) then
                return {
                    Uid = State.targetedSpecificUid,
                    BottomCFrame = CFrame.new(directFloorPos),
                    AssetCategory = "TargetedEgg"
                }
            end

            if not State.isStealingActive and not isHoldingEgg() then
                if State.activeStealButtons[State.targetedSpecificUid] then
                    State.activeStealButtons[State.targetedSpecificUid].BackgroundColor3 = S.activeTheme and S.activeTheme.Accent or Color3.fromRGB(92, 170, 255)
                    State.activeStealButtons[State.targetedSpecificUid].Text = "Steal"
                end
                State.targetedSpecificUid = nil
            end
        end

        local minScore = getMinRequiredScore()
        local bestEgg = nil
        local highestScore = -math.huge
        local normalStealEnabled = getgenv().config.autoFarm == true

        for keyUid, record in pairs(data.Records) do
            if type(record) == "table" then
                local uid = (type(record.Uid) == "string" and record.Uid) or (type(keyUid) == "string" and keyUid) or nil
                record.Uid = uid
                if uid and not isBlacklisted(uid) then
                    if record.State == "Slot" or record.State == "Dropped" or record.State == nil then
                        local posX = nil
                        local cf = record.BottomCFrame or record.BoundsCFrame or record.CFrame
                        if typeof(cf) == "CFrame" then posX = cf.Position.X
                        elseif typeof(cf) == "Vector3" then posX = cf.X
                        elseif typeof(record.Position) == "Vector3" then posX = record.Position.X end

                        if not posX or posX >= 560 then
                            local rawName = record.AssetCategory or record.Category or record.Name or "Unknown"
                        
                        if isLabNeeded then
                            local scale = tonumber(record.AssetScale) or 1
                            local mutationBonus = (record.Mutations and #record.Mutations > 0) and 2.5 or 1
                            local score = 100000000 + ((scale ^ 1.85) * mutationBonus)

                            if score > highestScore then
                                highestScore = score
                                bestEgg = record
                            end
                        elseif normalStealEnabled then
                            local areaIdStr = tostring(record.AreaId or "")
                            if matchesTargetArea(areaIdStr) then
                                local _, rank = MasterRegistry:Lookup(rawName)
                                if rank >= minScore then
                                    local scale = tonumber(record.AssetScale) or 1
                                    local mutationBonus = (record.Mutations and #record.Mutations > 0) and 2.5 or 1
                                    local score = (rank * 1000) + ((scale ^ 1.85) * mutationBonus)

                                    if score > highestScore then
                                        highestScore = score
                                        bestEgg = record
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        end
        return bestEgg
    end

    -- ==============================================================================
    -- [ WORKER SCHEDULER TASK REGISTRATIONS ]
    -- ==============================================================================

    WorkerScheduler:Register("AutoUpgrades", 6.0, function()
        if getgenv().config.autoUpgradeTreadmill then tryUpgradeTreadmill() end
        if getgenv().config.autoUpgradeBase then tryUpgradeBase() end
    end)

    WorkerScheduler:Register("UFOEvent", 0.25, function()
        if State.isStealingActive or isHoldingEgg() then return end
        if not S.PriorityManager:CanRun("UFO") then return end

        S.UFOManager.tick = (S.UFOManager.tick or 0) + 1
        if (S.UFOManager.tick % 40) == 1 then
            pcall(function() S.UFOManager:FetchState() end)
        end

        if S.PriorityManager:Acquire("UFO", 25.0) then
            pcall(function() S.UFOManager:Process() end)
            S.PriorityManager:Release("UFO")
        end
    end)

    WorkerScheduler:Register("EventsCombat", 0.35, function()
        if State.isStealingActive or isHoldingEgg() then return end
        if not S.PriorityManager:CanRun("Bloom") then return end

        if S.PriorityManager:Acquire("Bloom", 15.0) then
            pcall(function() BloomManager:Process() end)
            S.PriorityManager:Release("Bloom")
        end
    end)

    WorkerScheduler:Register("StealAndTreadmill", 0.25, function()
        local char = LocalPlayer.Character
        if not char then return end

        -- 1. Auto Steal & Steal Panel Execution
        if isStealEnabled() and not State.isStealingActive and not isMapClosed() and S.PriorityManager:CanRun("Steal") then
            local currentTargetEgg = S.getBestEgg()
            if currentTargetEgg then
                local targetUid = currentTargetEgg.Uid
                if not isEggStillValid(targetUid) then
                    blacklistEgg(targetUid, 15)
                    if State.targetedSpecificUid == targetUid then
                        if State.activeStealButtons[targetUid] then
                            State.activeStealButtons[targetUid].BackgroundColor3 = S.activeTheme and S.activeTheme.Accent or Color3.fromRGB(92, 170, 255)
                            State.activeStealButtons[targetUid].Text = "Steal"
                        end
                        State.targetedSpecificUid = nil
                    end
                    return
                end

                S.PriorityManager:Claim("Steal")
                State.isStealingActive = true
                State.treadmillFailCount = 0
                State.currentStealSession = State.currentStealSession + 1
                local session = State.currentStealSession

                hopOffTreadmill()
                ShieldManager:ApplyHumanoidSwap(char)
                task.wait(0.08)

                local targetCFrame = currentTargetEgg.BottomCFrame or currentTargetEgg.BoundsCFrame or currentTargetEgg.CFrame
                local eggTargetPos = nil
                if typeof(targetCFrame) == "CFrame" then eggTargetPos = targetCFrame.Position
                elseif typeof(targetCFrame) == "Vector3" then eggTargetPos = targetCFrame
                elseif typeof(currentTargetEgg.Position) == "Vector3" then eggTargetPos = currentTargetEgg.Position end

                if not eggTargetPos and targetUid then
                    eggTargetPos = getPhysicalEggPosition(targetUid, nil)
                end

                local stealSuccess = false
                if eggTargetPos then
                    local areaId = currentTargetEgg.AreaId
                    local isUfoEgg = S.UFOManager and S.UFOManager.IsUfoEgg and S.UFOManager:IsUfoEgg(currentTargetEgg, targetUid)
                    local canUfoTp = (getgenv().config.ufoTp == true) and isUfoEgg and root and ((root.Position - eggTargetPos).Magnitude >= 1000)
                    local canUseFastSteal = ((getgenv().config.fastSteal == true and isFastStealArea(areaId)) or canUfoTp)

                    local function tryDeliverToUfo()
                        if not isUfoEgg then return false end
                        local ufoPos = S.UFOManager:GetUfoPosition()
                        if not ufoPos then return false end
                        local d0 = S.UFOManager.State.st and S.UFOManager.State.st.Delivered or 0
                        local _, cRoot = getAliveRig()
                        if not cRoot then return false end

                        -- Glide directly under UFO beam without teleporting back home
                        local beamTarget = Vector3.new(ufoPos.X, math.max(ufoPos.Y - 60, cRoot.Position.Y), ufoPos.Z)
                        local arriveTimeout = os.clock() + 4.0
                        while os.clock() < arriveTimeout and isHoldingEgg() and (S.UFOManager.State.st.Delivered or 0) <= d0 do
                            local _, curR = getAliveRig()
                            if not curR then break end
                            local diff = beamTarget - curR.Position
                            if diff.Magnitude <= 15 then break end
                            curR.CFrame = CFrame.new(curR.Position + diff.Unit * math.min(diff.Magnitude, 35))
                            curR.AssemblyLinearVelocity = Vector3.zero
                            task.wait(0.08)
                        end

                        -- Wait for UFO tractor beam suck-up
                        local waitTimeout = os.clock() + 5.0
                        while os.clock() < waitTimeout and isHoldingEgg() and (S.UFOManager.State.st.Delivered or 0) <= d0 do
                            task.wait(0.1)
                        end

                        return (S.UFOManager.State.st.Delivered or 0) > d0
                    end

                    if canUseFastSteal then
                        local arrived = executeFastStealOutbound(eggTargetPos, session, targetUid)
                        if not arrived and session == State.currentStealSession and isStealEnabled() and isEggStillValid(targetUid) then
                            arrived = runAlongGroundToEgg(eggTargetPos, nil, session, targetUid)
                        end

                        if arrived and session == State.currentStealSession and isStealEnabled() then
                            task.wait(0.04)
                            local grabbed = instantGrabAtPosition(targetUid, eggTargetPos, session, false)

                            if (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
                                stealSuccess = tryDeliverToUfo()

                                if not stealSuccess and (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
                                    stealSuccess = executeFastStealDelivery(currentTargetEgg, session)
                                    if not stealSuccess and isHoldingEgg() and session == State.currentStealSession and isStealEnabled() then
                                        stealSuccess = executeCheckpointedHopsHome(currentTargetEgg, session)
                                    end
                                end
                            end
                        end
                    else
                        local arrived = runAlongGroundToEgg(eggTargetPos, nil, session, targetUid)
                        if arrived and session == State.currentStealSession and isStealEnabled() then
                            task.wait(0.04)
                            local grabbed = instantGrabAtPosition(targetUid, eggTargetPos, session, false)
                            if (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
                                stealSuccess = tryDeliverToUfo()

                                if not stealSuccess and (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
                                    stealSuccess = executeCheckpointedHopsHome(currentTargetEgg, session)
                                end
                            end
                        end
                    end
                end

                if session == State.currentStealSession then
                    State.isStealingActive = false
                    ShieldManager:UndoSwap()
                    cleanupFlightState()
                    S.PriorityManager:Release("Steal")

                    if State.targetedSpecificUid == targetUid and (stealSuccess or not isEggStillValid(targetUid)) then
                        if State.activeStealButtons[targetUid] then
                            State.activeStealButtons[targetUid].BackgroundColor3 = S.activeTheme and S.activeTheme.Accent or Color3.fromRGB(92, 170, 255)
                            State.activeStealButtons[targetUid].Text = "Steal"
                        end
                        State.targetedSpecificUid = nil
                    end
                else
                    State.isStealingActive = false
                    ShieldManager:UndoSwap()
                    cleanupFlightState()
                    if S.PriorityManager then
                        S.PriorityManager:Release("Steal")
                        S.PriorityManager:Release("Auto Steal")
                    end
                end
            end
        end

        -- 2. Treadmill Idle Execution (Normal Dimension on Plot Treadmill)
        local isStealBusy = State.isStealingActive or isHoldingEgg()
        local canTreadmill = getgenv().config.autoTreadmill and not isStealBusy and S.PriorityManager:CanRun("Treadmill")

        if canTreadmill and getAliveRig() then
            ShieldManager:UndoSwap()
            findMyPlot()
            local _, cRoot, cHum = getAliveRig()
            if cRoot and cHum then
                if State.myTreadmill then
                    local tPos = State.myTreadmill.Position + Vector3.new(0, 3, 0)
                    local dist = (cRoot.Position - tPos).Magnitude
                    if dist > 4 then
                        cHum.PlatformStand = false
                        cHum.Sit = false
                        local speed = cHum.WalkSpeed
                        if not speed or speed <= 0 then speed = 16 end
                        local travelDuration = math.clamp(dist / math.max(speed, 16), 0.3, 3)
                        local tw = Services.TweenService:Create(cRoot, TweenInfo.new(travelDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            CFrame = CFrame.new(tPos) * cRoot.CFrame.Rotation
                        })
                        tw:Play()
                        tw.Completed:Wait()
                    end

                    local _, postRoot, postHum = getAliveRig()
                    if postRoot and not postRoot.Anchored then
                        if postHum then
                            postHum.PlatformStand = false
                            postHum.Sit = false
                        end
                        if Remotes.AskWearStill and not isStealBusy and S.PriorityManager:CanRun("Treadmill") then
                            pcall(function() Remotes.AskWearStill:InvokeServer() end)
                        end
                        task.wait(0.35)
                        local _, verifyRoot = getAliveRig()
                        if verifyRoot and not verifyRoot.Anchored then
                            State.treadmillFailCount = State.treadmillFailCount + 1
                            if State.treadmillFailCount >= 8 then
                                resetFlaggedCharacter()
                            elseif State.treadmillFailCount == 4 and Remotes.AskDoff then
                                pcall(function() Remotes.AskDoff:InvokeServer() end)
                            end
                        else
                            State.treadmillFailCount = 0
                        end
                    else
                        State.treadmillFailCount = 0
                    end
                else
                    State.treadmillFailCount = 0
                end
            end
        else
            -- Clean dismount when treadmill is no longer active but character is still anchored
            if not canTreadmill and getgenv().config.autoTreadmill then
                local _, curRoot = getAliveRig()
                if curRoot and curRoot.Anchored then
                    hopOffTreadmill()
                end
            end
        end
    end)

    WorkerScheduler:Start()

    -- ==============================================================================
end
