-- ==============================================================================
-- [ SYNTAX HUB - MODULE: StealMovement.lua ]
-- ==============================================================================
return function(S)
    local Services, LocalPlayer, UniversalCompat, State, CONFIG = S.Services, S.LocalPlayer, S.UniversalCompat, S.State, S.CONFIG
    local blacklistEgg, isMapClosed, isStealEnabled, Remotes, EggState = S.blacklistEgg, S.isMapClosed, S.isStealEnabled, S.Remotes, S.EggState
    local getAliveRig, setCollisions, cleanupFlightState, StealUIManager, ShieldManager = S.getAliveRig, S.setCollisions, S.cleanupFlightState, S.StealUIManager, S.ShieldManager
    local isHoldingEgg, dropHeldEggDirect, getPhysicalEggPosition, isEggStillValid = S.isHoldingEgg, S.dropHeldEggDirect, S.getPhysicalEggPosition, S.isEggStillValid

    -- ==============================================================================
    -- [ FAST STEAL PIPELINE (TITAN / LIGHT DARK / ENCHANTED) ]
    -- ==============================================================================
    -- ==============================================================================
    -- [ DYNAMIC SPEED IDENTIFIER ]
    -- ==============================================================================
    local function getPlayerCurrentSpeed()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        -- 1. Check live Humanoid WalkSpeed (handling ShieldManager clone if active)
        if hum and typeof(hum.WalkSpeed) == "number" and hum.WalkSpeed > 0 then
            if ShieldManager and ShieldManager.OriginalHumanoid and ShieldManager.OriginalHumanoid.Parent == nil then
                if ShieldManager.OriginalHumanoid.WalkSpeed > hum.WalkSpeed then
                    return ShieldManager.OriginalHumanoid.WalkSpeed
                end
            end
            return hum.WalkSpeed
        end

        -- 2. Check Character & Player Attributes
        if char then
            for _, attrName in ipairs({"WalkSpeed", "Speed", "CurrentSpeed", "MovementSpeed"}) do
                local val = char:GetAttribute(attrName)
                if typeof(val) == "number" and val > 0 then return val end
            end
        end
        for _, attrName in ipairs({"WalkSpeed", "Speed", "CurrentSpeed", "MovementSpeed"}) do
            local val = LocalPlayer:GetAttribute(attrName)
            if typeof(val) == "number" and val > 0 then return val end
        end

        -- 3. Check leaderstats
        local lstats = LocalPlayer:FindFirstChild("leaderstats")
        if lstats then
            for _, child in ipairs(lstats:GetChildren()) do
                local lName = child.Name:lower()
                if (lName == "speed" or lName == "walkspeed") and typeof(child.Value) == "number" and child.Value > 0 then
                    return child.Value
                end
            end
        end

        -- 4. Check Save module peek
        local saveMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Save")
        if saveMod and saveMod:IsA("ModuleScript") then
            local ok, mod = pcall(require, saveMod)
            if ok and type(mod) == "table" then
                local getter = type(mod.Get) == "function" and mod.Get or (type(mod.Peek) == "function" and mod.Peek)
                if getter then
                    local resOk, res = pcall(getter)
                    if resOk and type(res) == "table" then
                        for k, v in pairs(res) do
                            local lk = tostring(k):lower()
                            if (lk == "speed" or lk == "walkspeed") and typeof(v) == "number" and v > 0 then
                                return v
                            end
                        end
                    end
                end
            end
        end

        return 16
    end
    getgenv().getPlayerCurrentSpeed = getPlayerCurrentSpeed

    local function getStandingPosition(basePos)
        local _, root, hum = getAliveRig()
        local hipHeight = hum and hum.HipHeight or 2
        local rootSizeY = root and (root.Size.Y / 2) or 1
        return Vector3.new(basePos.X, basePos.Y + hipHeight + rootSizeY, basePos.Z)
    end

    local function runAlongGroundSegment(targetPos, stopDist, sessionId, targetUid)
        local char, root, hum = getAliveRig()
        if not root or not hum then return false end
        stopDist = stopDist or 3.5

        local liveSpeed = getPlayerCurrentSpeed()
        setCollisions(false)
        if hum then hum.PlatformStand = false end

        local delta = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
        local timeout = os.clock() + math.max(8, (delta.Magnitude / math.max(liveSpeed, 16)) + 5)
        local arrived = false
        local lastLiveCheck = 0

        local conn
        conn = Services.RunService.Heartbeat:Connect(function()
            if sessionId ~= State.currentStealSession or not isStealEnabled() or isMapClosed() then
                if conn then conn:Disconnect() conn = nil end
                return
            end

            local _, cRoot = getAliveRig()
            if not cRoot or os.clock() > timeout then
                if conn then conn:Disconnect() conn = nil end
                return
            end

            if targetUid and (os.clock() - lastLiveCheck >= 0.25) then
                lastLiveCheck = os.clock()
                if not isEggStillValid(targetUid) then
                    blacklistEgg(targetUid, 15)
                    if conn then conn:Disconnect() conn = nil end
                    return
                end
            end

            local currentPos = cRoot.Position
            local flatDiff = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
            if flatDiff.Magnitude <= stopDist then
                arrived = true
                cRoot.AssemblyLinearVelocity = Vector3.zero
                cRoot.AssemblyAngularVelocity = Vector3.zero
                if conn then conn:Disconnect() conn = nil end
                return
            end

            local curSpeed = getPlayerCurrentSpeed()
            local dir = flatDiff.Unit
            -- Pure physics velocity using player's own speed, keeping character naturally grounded
            cRoot.AssemblyLinearVelocity = Vector3.new(dir.X * curSpeed, cRoot.AssemblyLinearVelocity.Y, dir.Z * curSpeed)
            cRoot.CFrame = CFrame.new(currentPos.X, currentPos.Y, currentPos.Z) * CFrame.lookAt(Vector3.zero, dir)
        end)

        while conn and conn.Connected do
            Services.RunService.Heartbeat:Wait()
        end

        local _, fRoot = getAliveRig()
        if fRoot then
            fRoot.AssemblyLinearVelocity = Vector3.zero
            fRoot.AssemblyAngularVelocity = Vector3.zero
        end

        return arrived and (sessionId == State.currentStealSession) and isStealEnabled()
    end

    local function runAlongGroundToEgg(targetPos, speed, sessionId, targetUid)
        local char, root, hum = getAliveRig()
        if not root or not hum then return false end

        local currentPosInit = root.Position
        local groundY = CONFIG.GroundAltitude + 1.0

        -- Safe Zone T-Shape Routing:
        -- If inside safe zone (X < BoundaryCheckpointX), route via delivery center & corridor mouth
        -- to prevent clipping through corner walls and getting killed!
        if currentPosInit.X < CONFIG.BoundaryCheckpointX then
            local centerDeliveryPos = Vector3.new(CONFIG.BaseDropPosition.X, groundY, CONFIG.BaseDropPosition.Z)
            local mouthPos = Vector3.new(CONFIG.BoundaryCheckpointX, groundY, CONFIG.BaseDropPosition.Z)

            local lateralDist = math.abs(currentPosInit.Z - CONFIG.BaseDropPosition.Z)
            if lateralDist > 12 or currentPosInit.X < CONFIG.BaseDropPosition.X then
                local ok = runAlongGroundSegment(centerDeliveryPos, 4.0, sessionId, targetUid)
                if not ok or sessionId ~= State.currentStealSession or not isStealEnabled() then
                    return false
                end
            end

            local ok2 = runAlongGroundSegment(mouthPos, 4.0, sessionId, targetUid)
            if not ok2 or sessionId ~= State.currentStealSession or not isStealEnabled() then
                return false
            end
        end

        -- From corridor mouth, travel directly down the corridor to the target egg
        local targetStandPos = getStandingPosition(targetPos)
        local reached = runAlongGroundSegment(targetStandPos, 3.5, sessionId, targetUid)
        if not reached or sessionId ~= State.currentStealSession or not isStealEnabled() then
            return false
        end

        -- Only align facing when successfully arrived and steal is still actively enabled!
        local _, fRoot = getAliveRig()
        if fRoot then
            fRoot.CFrame = CFrame.lookAt(targetStandPos, targetPos)
            fRoot.AssemblyLinearVelocity = Vector3.zero
            fRoot.AssemblyAngularVelocity = Vector3.zero
        end
        task.wait(0.04)
        return true
    end

    local function executeFastStealOutbound(targetPos, sessionId, targetUid)
        local world = Services.Workspace:FindFirstChild("World") or Services.Workspace:FindFirstChild("__OBJECTS")
        local build = world and world:FindFirstChild("Build")
        local portals = build and build:FindFirstChild("FuseBiomeLanePortals")
        local entrance = portals and portals:FindFirstChildWhichIsA("BasePart")
        local zone = build and build:FindFirstChild("FuseBiomeZone")
        local exitPart = zone and zone:FindFirstChild("ExitPart", true)

        if not entrance or not exitPart then
            return runAlongGroundToEgg(targetPos, nil, sessionId, targetUid)
        end

        local _, root = getAliveRig()
        if not root then return false end

        root.CFrame = CFrame.new(CONFIG.BaseDropPosition)
        root.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.12)

        local inSky = false
        local entranceTimeout = os.clock() + 4.0

        while os.clock() < entranceTimeout do
            if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
            local _, cRoot = getAliveRig()
            if not cRoot then return false end

            cRoot.CFrame = CFrame.new(entrance.Position)
            cRoot.AssemblyLinearVelocity = Vector3.new(0, -0.5, 0)
            UniversalCompat.FireTouch(cRoot, entrance)

            if cRoot.Position.Y > 10000 then
                inSky = true
                break
            end
            Services.RunService.Heartbeat:Wait()
        end

        if not inSky then
            return runAlongGroundToEgg(targetPos, nil, sessionId, targetUid)
        end

        local exitedSky = false
        local exitDeadline = os.clock() + 5.0

        while os.clock() < exitDeadline do
            if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
            local _, cRoot = getAliveRig()
            if not cRoot then return false end

            cRoot.CFrame = CFrame.new(exitPart.Position)
            cRoot.AssemblyLinearVelocity = Vector3.new(0, -0.5, 0)
            UniversalCompat.FireTouch(cRoot, exitPart)

            if cRoot.Position.Y < 10000 then
                exitedSky = true
                break
            end
            Services.RunService.Heartbeat:Wait()
        end

        if not exitedSky then return false end
        task.wait(0.12)

        local _, cRoot = getAliveRig()
        if not cRoot then return false end

        local remainingDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(cRoot.Position.X, 0, cRoot.Position.Z)).Magnitude
        if remainingDist <= CONFIG.FastStealDirectSnapRadius then
            setCollisions(false)
            local standPos = getStandingPosition(targetPos)
            cRoot.CFrame = CFrame.lookAt(standPos, targetPos)
            cRoot.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.05)
            return true
        else
            return runAlongGroundToEgg(targetPos, nil, sessionId, targetUid)
        end
    end

    local function findMyPlot()
        if State.myPlot and State.myPlot.Parent and State.myTreadmill and State.myTreadmill.Parent then
            return State.myPlot
        end

        local myName = LocalPlayer.Name:lower()
        local myDisplayName = LocalPlayer.DisplayName:lower()
        local myUserId = LocalPlayer.UserId

        local plotsFolder = Services.Workspace:FindFirstChild("Plots")
        local candidates = plotsFolder and plotsFolder:GetChildren() or Services.Workspace:GetChildren()

        for _, plot in ipairs(candidates) do
            local ownerAttr = plot:GetAttribute("Owner") or plot:GetAttribute("OwnerUserId") or plot:GetAttribute("Player")
            if ownerAttr and (tostring(ownerAttr):lower() == myName or tonumber(ownerAttr) == myUserId) then
                State.myPlot = plot
                break
            end

            local sign = plot:FindFirstChild("PlotSign") or plot:FindFirstChild("Sign")
            if sign then
                for _, desc in ipairs(sign:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local txt = desc.Text:lower()
                        if txt:find(myName, 1, true) or txt:find(myDisplayName, 1, true) then
                            State.myPlot = plot
                            break
                        end
                    end
                end
            end
            if State.myPlot then break end
        end

        if State.myPlot then
            for _, desc in ipairs(State.myPlot:GetDescendants()) do
                if desc.Name:lower():find("treadmill") then
                    if desc:IsA("BasePart") then
                        State.myTreadmill = desc
                        break
                    elseif desc:IsA("Model") then
                        State.myTreadmill = desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")
                        if State.myTreadmill then break end
                    end
                end
            end
            if not State.myTreadmill then
                for _, child in ipairs(State.myPlot:GetChildren()) do
                    if child.Name:lower():find("treadmill") then
                        State.myTreadmill = child:IsA("BasePart") and child or (child:IsA("Model") and (child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")))
                        if State.myTreadmill then break end
                    end
                end
            end
        end

        if not State.myTreadmill then
            for _, obj in ipairs(Services.Workspace:GetDescendants()) do
                if obj.Name == "TreadmillBottom" and obj:IsA("BasePart") then
                    State.myTreadmill = obj
                    break
                end
            end
        end
        return State.myPlot
    end

    local function instantGrabAtPosition(uid, targetPos, sessionId, isNest)
        if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
        local _, root = getAliveRig()
        if root and targetPos then
            local offsetY = isNest and CONFIG.AirGrabOffset or 1.0
            local safeY = (targetPos.Y or CONFIG.GroundAltitude) + offsetY
            root.CFrame = CFrame.new(Vector3.new(targetPos.X, safeY, targetPos.Z))
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end

        local targetPrompt = nil
        local eggModel = uid and (Services.Workspace:FindFirstChild(uid) or (Services.Workspace:FindFirstChild("AreaEggSlotsClient") and Services.Workspace.AreaEggSlotsClient:FindFirstChild(uid)))
        if eggModel then
            targetPrompt = eggModel:FindFirstChildWhichIsA("ProximityPrompt", true)
        end
        if not targetPrompt and targetPos then
            local parts = Services.Workspace:GetPartBoundsInRadius(targetPos, 12)
            for _, part in ipairs(parts) do
                local p = part:FindFirstChildWhichIsA("ProximityPrompt", true)
                if p and p.Enabled then
                    targetPrompt = p
                    break
                end
            end
        end

        local grabTimeout = os.clock() + 3.0
        local nextRemoteDispatch = 0

        while os.clock() < grabTimeout do
            if sessionId ~= State.currentStealSession or not isStealEnabled() then break end
            local _, cRoot = getAliveRig()
            if not cRoot then break end

            if uid and not isHoldingEgg() and not isEggStillValid(uid) then
                blacklistEgg(uid, 15)
                return false
            end

            if os.clock() >= nextRemoteDispatch then
                nextRemoteDispatch = os.clock() + 0.3
                if Remotes.AskFieldEggCarry and uid then
                    task.spawn(function() pcall(function() Remotes.AskFieldEggCarry:InvokeServer({ Uid = uid }) end) end)
                end
                if typeof(EggState.CarryFieldEgg) == "function" and uid then
                    pcall(function() EggState.CarryFieldEgg(uid) end)
                end
            end

            if targetPrompt and targetPrompt.Enabled then
                UniversalCompat.FireProximityPrompt(targetPrompt)
            end

            for _ = 1, 3 do
                Services.RunService.Heartbeat:Wait()
                if isHoldingEgg() then return true end
            end
        end
        return isHoldingEgg()
    end

    local function performGroundCheckpoint(targetEgg, currentX, laneZ, sessionId)
        if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
        local _, root, humanoid = getAliveRig()
        if not root then return false end
        if humanoid then humanoid.PlatformStand = false end

        local uid = (targetEgg and targetEgg.Uid) or (EggState and EggState.CarryUid)
        local checkY = CONFIG.GroundAltitude + 1.0

        pcall(function()
            root.CFrame = CFrame.new(currentX, checkY, laneZ) * CFrame.Angles(0, math.rad(90), 0)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        task.wait(0.06)

        dropHeldEggDirect()
        local dropWait = os.clock() + 0.6
        while os.clock() < dropWait and isHoldingEgg() do
            if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
            dropHeldEggDirect()
            task.wait(0.08)
        end
        task.wait(0.04)

        -- Regrab: try client EggState.CarryFieldEgg first, then physical grab
        if uid and EggState and typeof(EggState.CarryFieldEgg) == "function" then
            pcall(function() EggState.CarryFieldEgg(uid) end)
            task.wait(0.12)
        end

        if not isHoldingEgg() then
            local eggFloorPos = getPhysicalEggPosition(uid, Vector3.new(currentX, checkY, laneZ))
            local grabSuccess = false
            local retryTimeout = os.clock() + 3.0

            while os.clock() < retryTimeout do
                if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
                grabSuccess = instantGrabAtPosition(uid, eggFloorPos, sessionId, false)
                if grabSuccess and isHoldingEgg() then break end
                Services.RunService.Heartbeat:Wait()
            end
        end
        task.wait(0.04)
        return isHoldingEgg()
    end

    local function executeCheckpointedHopsHome(targetEgg, sessionId)
        local _, root, humanoid = getAliveRig()
        if not root then return false end

        local boundaryX = CONFIG.BoundaryCheckpointX
        local playerSpeed = getPlayerCurrentSpeed()
        local baseStep = CONFIG.HopDistance
        local stepSize = (playerSpeed < 100) and math.max(34, playerSpeed * 0.45) or math.min(baseStep, math.max(60, playerSpeed * 0.75))
        local interval = CONFIG.CheckpointInterval
        local safeTarget = CONFIG.BaseDropPosition

        local laneZ = math.clamp(root.Position.Z, -425, -300)
        local currentX = root.Position.X
        local lastCheckpointX = currentX

        StealUIManager:Lock()
        ShieldManager:MuteUGI()
        if humanoid then humanoid.PlatformStand = false end

        local groundY = CONFIG.GroundAltitude + 1.0

        -- Phase 1: Hop along lane towards boundary with periodic checkpoints
        while currentX - stepSize > boundaryX do
            if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then
                ShieldManager:UnmuteUGI()
                StealUIManager:Unlock()
                cleanupFlightState()
                return false
            end

            local _, cRoot = getAliveRig()
            if not cRoot then 
                ShieldManager:UnmuteUGI()
                StealUIManager:Unlock()
                cleanupFlightState() 
                return false 
            end

            local nextX = currentX - stepSize
            local preHopTime = os.clock()

            pcall(function()
                cRoot.CFrame = CFrame.new(nextX, groundY, laneZ) * CFrame.Angles(0, math.rad(90), 0)
                cRoot.AssemblyLinearVelocity = Vector3.zero
            end)
            task.wait(CONFIG.HopGap)

            local _, postRoot = getAliveRig()
            local pulled = (State.lastServerRollbackTime > preHopTime) or (postRoot ~= nil and (postRoot.Position.X - nextX > 15))

            if pulled then
                CONFIG.HopGap = math.min(CONFIG.HopGapMax, CONFIG.HopGap + 0.02)
                stepSize = math.max(34, stepSize * 0.75)
                task.wait(0.1)
            else
                currentX = nextX
                CONFIG.HopGap = math.max(CONFIG.HopGapMin, CONFIG.HopGap - 0.005)
            end

            -- Intermediate ground checkpoint at configured interval
            if math.abs(lastCheckpointX - currentX) >= interval then
                lastCheckpointX = currentX
                local ok = performGroundCheckpoint(targetEgg, currentX, laneZ, sessionId)
                if not ok and not isHoldingEgg() then
                    ShieldManager:UnmuteUGI()
                    StealUIManager:Unlock()
                    cleanupFlightState()
                    return false
                end
            end
        end

        -- Phase 2: Mandatory Boundary Checkpoint right at boundaryX before crossing into base
        if isHoldingEgg() then
            currentX = boundaryX
            pcall(function()
                local _, bRoot = getAliveRig()
                if bRoot then
                    bRoot.CFrame = CFrame.new(boundaryX, groundY, laneZ) * CFrame.Angles(0, math.rad(90), 0)
                    bRoot.AssemblyLinearVelocity = Vector3.zero
                end
            end)
            task.wait(0.08)
            local boundaryOk = performGroundCheckpoint(targetEgg, boundaryX, laneZ, sessionId)
            if not boundaryOk and not isHoldingEgg() then
                ShieldManager:UnmuteUGI()
                StealUIManager:Unlock()
                cleanupFlightState()
                return false
            end
        end

        -- Phase 3: Safe Zone Corridor Micro-Hops into Base (progressive hops, NEVER jump 450 studs in one step!)
        local corridorStep = 45
        while currentX - corridorStep > safeTarget.X do
            if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then
                break
            end

            local nextX = currentX - corridorStep
            local _, cRoot = getAliveRig()
            if cRoot then
                pcall(function()
                    cRoot.CFrame = CFrame.new(nextX, groundY, safeTarget.Z) * CFrame.Angles(0, math.rad(90), 0)
                    cRoot.AssemblyLinearVelocity = Vector3.zero
                end)
            end
            task.wait(CONFIG.HopGap)
            currentX = nextX
        end

        -- Phase 4: Delivery Location Drop & Settle Sequence
        local _, fRoot, fHum = getAliveRig()
        if fRoot then
            pcall(function()
                fRoot.CFrame = CFrame.new(safeTarget.X, CONFIG.GroundAltitude + 1.2, safeTarget.Z)
                fRoot.AssemblyLinearVelocity = Vector3.zero
            end)
        end
        task.wait(0.15)
        if fHum then fHum.PlatformStand = false end

        dropHeldEggDirect()
        task.wait(0.25)

        local dropVerifyTimeout = os.clock() + 2.0
        while os.clock() < dropVerifyTimeout and isHoldingEgg() do
            dropHeldEggDirect()
            task.wait(0.2)
        end

        StealUIManager:Unlock()
        ShieldManager:UnmuteUGI()
        cleanupFlightState()
        return not isHoldingEgg()
    end

    local function executeFastStealDelivery(targetEgg, sessionId)
        local _, root, hum = getAliveRig()
        if not root or not hum then return false end

        local uid = targetEgg.Uid
        local laneZ = math.clamp(root.Position.Z, -425, -300)
        local dropTargetPos = Vector3.new(CONFIG.SeparationLineX + CONFIG.FastStealLineDropOffset, CONFIG.GroundAltitude + 1.0, laneZ)
        local playerSpeed = getPlayerCurrentSpeed()

        setCollisions(false)
        ShieldManager:MuteUGI()

        local startTime = os.clock()
        local travelTimeout = math.max(12, ((root.Position.X - dropTargetPos.X) / playerSpeed) + 6)

        -- Phase 1: High speed glide along ground towards separation line
        while root.Position.X > dropTargetPos.X + 2.0 and (os.clock() - startTime) < travelTimeout do
            Services.RunService.Heartbeat:Wait()
            if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then
                setCollisions(true)
                ShieldManager:UnmuteUGI()
                return false
            end

            local _, cRoot = getAliveRig()
            if not cRoot then break end
            cRoot.AssemblyLinearVelocity = Vector3.new(-playerSpeed, cRoot.AssemblyLinearVelocity.Y, 0)
            cRoot.CFrame = CFrame.new(cRoot.Position.X, CONFIG.GroundAltitude + 1.0, laneZ) * CFrame.Angles(0, math.rad(90), 0)
        end

        local _, cRoot = getAliveRig()
        if cRoot then
            cRoot.CFrame = CFrame.new(dropTargetPos) * CFrame.Angles(0, math.rad(90), 0)
            cRoot.AssemblyLinearVelocity = Vector3.zero
        end
        task.wait(0.1)

        -- Phase 2: Separation line drop and regrab checkpoint
        local checkpointOk = performGroundCheckpoint(targetEgg, dropTargetPos.X, laneZ, sessionId)
        if not checkpointOk and not isHoldingEgg() then
            setCollisions(true)
            ShieldManager:UnmuteUGI()
            return false
        end

        -- Phase 3: Fast micro-hops from separation line to base drop position
        local currentX = dropTargetPos.X
        local safeTarget = CONFIG.BaseDropPosition
        local corridorStep = 55

        while currentX - corridorStep > safeTarget.X do
            if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then break end
            local nextX = currentX - corridorStep
            local _, hRoot = getAliveRig()
            if hRoot then
                pcall(function()
                    hRoot.CFrame = CFrame.new(nextX, CONFIG.GroundAltitude + 1.0, safeTarget.Z) * CFrame.Angles(0, math.rad(90), 0)
                    hRoot.AssemblyLinearVelocity = Vector3.zero
                end)
            end
            task.wait(CONFIG.HopGap)
            currentX = nextX
        end

        -- Phase 4: Final delivery drop at hopper
        local _, fRoot, fHum = getAliveRig()
        if fRoot then
            fRoot.CFrame = CFrame.new(safeTarget.X, CONFIG.GroundAltitude + 1.2, safeTarget.Z)
            fRoot.AssemblyLinearVelocity = Vector3.zero
        end
        task.wait(0.15)
        if fHum then fHum.PlatformStand = false end

        dropHeldEggDirect()
        task.wait(0.25)

        local dropVerifyTimeout = os.clock() + 2.0
        while os.clock() < dropVerifyTimeout and isHoldingEgg() do
            dropHeldEggDirect()
            task.wait(0.2)
        end

        setCollisions(true)
        ShieldManager:UnmuteUGI()
        return not isHoldingEgg()
    end

    local function executeGroundDeliveryHome(targetEgg, sessionId)
        return executeCheckpointedHopsHome(targetEgg, sessionId)
    end

    -- Export shared bindings to module context
    S.runAlongGroundToEgg = runAlongGroundToEgg
    S.executeFastStealOutbound = executeFastStealOutbound
    S.findMyPlot = findMyPlot
    S.instantGrabAtPosition = instantGrabAtPosition
    S.executeCheckpointedHopsHome = executeCheckpointedHopsHome
    S.executeFastStealDelivery = executeFastStealDelivery
end
