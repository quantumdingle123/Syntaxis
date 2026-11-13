-- ==============================================================================
-- [ SYNTAX HUB - MODULE: Core.lua ]
-- ==============================================================================
return function(S)
    -- ==============================================================================
    -- [ SYNTAX HUB - COMPLETE FINAL UNIFIED SCRIPT ]
    -- ==============================================================================

    local Services = {
        Players = game:GetService("Players"),
        Workspace = game:GetService("Workspace"),
        RunService = game:GetService("RunService"),
        ReplicatedStorage = game:GetService("ReplicatedStorage"),
        TweenService = game:GetService("TweenService"),
        TeleportService = game:GetService("TeleportService"),
        SoundService = game:GetService("SoundService"),
        CollectionService = game:GetService("CollectionService"),
        HttpService = game:GetService("HttpService"),
        UserInputService = game:GetService("UserInputService")
    }

    local LocalPlayer = Services.Players.LocalPlayer or Services.Players.PlayerAdded:Wait()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- ==============================================================================
    -- [ UNIVERSAL EXECUTOR COMPATIBILITY & POLYFILL LAYER ]
    -- Multi-executor support for Mobile (Delta) & PC (Wave, Synapse Z, Solara, Celery, MacSploit, etc.)
    -- ==============================================================================

    local UniversalCompat = {}

    function UniversalCompat.FireProximityPrompt(prompt)
        if not prompt or not prompt.Parent then return false end

        -- Method A: Native exploit C-closure fireproximityprompt (zero synthetic input, zero property tampering)
        if typeof(fireproximityprompt) == "function" then
            local ok = pcall(fireproximityprompt, prompt, 0)
            if not ok then ok = pcall(fireproximityprompt, prompt, 1) end
            if not ok then ok = pcall(fireproximityprompt, prompt) end
            if ok then return true end
        end

        -- Method B: Engine input hold simulation matching prompt duration (no VIM, no property alteration)
        local triggered = false
        pcall(function()
            prompt:InputHoldBegin()
            local duration = tonumber(prompt.HoldDuration) or 0
            if duration > 0 then
                task.wait(duration + 0.05)
            else
                task.wait(0.04)
            end
            prompt:InputHoldEnd()
            triggered = true
        end)

        return triggered
    end

    function UniversalCompat.FireTouch(part1, part2)
        if not part1 or not part2 or not part1.Parent or not part2.Parent then return false end

        -- Method A: Exploit firetouchinterest C-closure
        if typeof(firetouchinterest) == "function" then
            pcall(firetouchinterest, part1, part2, 0)
            task.wait(0.01)
            pcall(firetouchinterest, part1, part2, 1)
        end

        -- Method B: Ensure physical touch properties are enabled
        pcall(function()
            if part1:IsA("BasePart") then part1.CanTouch = true end
            if part2:IsA("BasePart") then part2.CanTouch = true end
        end)

        return true
    end

    function UniversalCompat.ClickButton(btn)
        if not btn or not btn:IsA("GuiButton") then return false end

        -- Method A: firesignal
        if typeof(firesignal) == "function" then
            local ok1 = pcall(firesignal, btn.Activated)
            local ok2 = pcall(firesignal, btn.MouseButton1Click)
            if ok1 or ok2 then return true end
        end

        -- Method B: getconnections
        if typeof(getconnections) == "function" then
            local triggered = false
            local ok1, conns1 = pcall(getconnections, btn.Activated)
            if ok1 and type(conns1) == "table" then
                for _, c in ipairs(conns1) do
                    pcall(function()
                        if c.Fire then c:Fire() elseif c.Function then c.Function() end
                    end)
                    triggered = true
                end
            end
            local ok2, conns2 = pcall(getconnections, btn.MouseButton1Click)
            if ok2 and type(conns2) == "table" then
                for _, c in ipairs(conns2) do
                    pcall(function()
                        if c.Fire then c:Fire() elseif c.Function then c.Function() end
                    end)
                    triggered = true
                end
            end
            if triggered then return true end
        end

        return false
    end

    local saveFile = "SyntaxHub_Config.json"

    local currentSettings = {
        Theme = "Sapphire",
        Transparency = 0,
        AutoFarm = false,
        FastSteal = false,
        AutoTreadmill = false,
        AutoUpgradeTreadmill = false,
        AutoUpgradeBase = false,
        AutoClaimMastery = false,
        AutoCatchButterfly = false,
        AutoWispQuest = false,
        AutoTradeUp = false,
        AutoCraftEssence = false,
        ButterflySpeed = 320,
        TargetAreas = { ["All"] = true },
        MinRarity = "All",
        AutoUFO = false,
        UFORocks = false,
        UFORare = true,
        UFOTrade = false,
        UFOTp = false,
        BloomCatchMode = "Stand",
        BloomCatchPriority = "Rarest",
        BloomSmartTrade = true,
        TaskPriorities = {
            "Auto Steal",
            "UFO Event",
            "Enchanted / Bloom Event",
            "Auto Treadmill"
        }
    }

    local function saveStuff()
        if writefile then
            pcall(function()
                writefile(saveFile, Services.HttpService:JSONEncode(currentSettings))
            end)
        end
    end

    local function loadStuff()
        if isfile and readfile and isfile(saveFile) then
            pcall(function()
                local decoded = Services.HttpService:JSONDecode(readfile(saveFile))
                if decoded and type(decoded) == "table" then
                    for k, v in pairs(decoded) do
                        if k == "TargetAreas" and type(v) == "table" then
                            currentSettings.TargetAreas = v

                        elseif k == "TaskPriorities" and type(v) == "table" then
                            currentSettings.TaskPriorities = v
                        elseif type(v) == "table" and type(currentSettings[k]) == "table" then
                            for k2, v2 in pairs(v) do currentSettings[k][k2] = v2 end
                        else
                            currentSettings[k] = v
                        end
                    end
                end
            end)
        end

        if type(currentSettings.TargetAreas) ~= "table" or next(currentSettings.TargetAreas) == nil then
            currentSettings.TargetAreas = { ["All"] = true }
        end
            if type(currentSettings.MinRarity) ~= "string" or string.find(currentSettings.MinRarity, "table:") then
            currentSettings.MinRarity = "All"
        end

        end

    loadStuff()

    getgenv().config = getgenv().config or {}
    getgenv().config.targetAreas = currentSettings.TargetAreas
    getgenv().config.minRarity = currentSettings.MinRarity
    getgenv().config.autoFarm = currentSettings.AutoFarm
    getgenv().config.fastSteal = currentSettings.FastSteal
    getgenv().config.autoTreadmill = currentSettings.AutoTreadmill
    getgenv().config.autoUpgradeTreadmill = currentSettings.AutoUpgradeTreadmill
    getgenv().config.autoUpgradeBase = currentSettings.AutoUpgradeBase
    getgenv().config.autoClaimMastery = currentSettings.AutoClaimMastery
    getgenv().config.autoCatchButterfly = currentSettings.AutoCatchButterfly
    getgenv().config.autoWispQuest = currentSettings.AutoWispQuest
    getgenv().config.autoTradeUp = currentSettings.AutoTradeUp
    getgenv().config.autoCraftEssence = currentSettings.AutoCraftEssence
    getgenv().config.butterflySpeed = currentSettings.ButterflySpeed
    getgenv().config.autoUFO = currentSettings.AutoUFO == true
    getgenv().config.ufoRocks = currentSettings.UFORocks == true
    getgenv().config.ufoRare = currentSettings.UFORare ~= false
    getgenv().config.ufoTrade = currentSettings.UFOTrade == true
    getgenv().config.ufoTp = currentSettings.UFOTp == true
    getgenv().config.bloomCatchMode = currentSettings.BloomCatchMode or "Stand"
    getgenv().config.bloomCatchPriority = currentSettings.BloomCatchPriority or "Rarest"
    getgenv().config.bloomSmartTrade = currentSettings.BloomSmartTrade ~= false

    local State = {
        currentStealSession = 0,
        isStealingActive = false,
        activeFlightConnection = nil,
        activeCollisionsDisabled = {},
        targetedSpecificUid = nil,
        blacklistedEggs = {},
        lastServerRollbackTime = 0,
        myPlot = nil,
        myTreadmill = nil,
        treadmillFailCount = 0,
        lastResetTime = 0,
        baseUpgradeCooldown = 0,
        treadmillUpgradeCooldown = 0,
        activeStealButtons = {},
        themeSubscribers = {},
        themeName = currentSettings.Theme or "Sapphire",
        isOpn = true,
        curCat = 1,
        cachedFieldEggs = {},
        cachedStealPanelItems = {},
        activeOpenedDropdown = nil,
        spSortChoice = "Value (Money/s)",
        spSortIndex = 1,
    }

    local CONFIG = {
        HopDistance = 230,
        HopGap = 0.06,
        HopGapMin = 0.05,
        HopGapMax = 0.20,
        FlightAltitude = 71.5,
        HopAltitude = 71.8,
        GroundAltitude = 70.8,
        AirGrabOffset = 1.2,
        CheckpointInterval = 1600,
        BoundaryCheckpointX = 600.2,
        SeparationLineX = 552.2,
        FastStealLineDropOffset = 45,
        -- FastStealHopSpeed removed: no air hopping
        -- FastStealGroundSpeed removed: strictly uses natural hum.WalkSpeed
        FastStealDirectSnapRadius = 45,
        BaseDropPosition = Vector3.new(528.7, 70.8, -364.1)
    }

    -- ==============================================================================
    -- [ HELPER FUNCTIONS & NETWORK DISPATCHERS ]
    -- ==============================================================================
    local function formatMoneyPerSec(val)
        local n = tonumber(val) or 0
        if n >= 1e12 then return string.format("$%.2fT/s", n / 1e12) end
        if n >= 1e9 then return string.format("$%.2fB/s", n / 1e9) end
        if n >= 1e6 then return string.format("$%.2fM/s", n / 1e6) end
        if n >= 1e3 then return string.format("$%.2fK/s", n / 1e3) end
        return string.format("$%.1f/s", n)
    end

    local function cleanName(name)
        return tostring(name or ""):lower():gsub("[Ee]gg", ""):gsub("[^%w]", "")
    end

    local function isBlacklisted(uid)
        if not uid then return false end
        local exp = State.blacklistedEggs[uid]
        if exp and exp > os.clock() then return true end
        if exp then State.blacklistedEggs[uid] = nil end
        return false
    end

    local function blacklistEgg(uid, duration)
        if uid then State.blacklistedEggs[uid] = os.clock() + (duration or 15) end
    end

    local function isNightPhase()
        local client = Services.ReplicatedStorage:FindFirstChild("Client")
        local cycleModule = client and client:FindFirstChild("AreaEggCycle")
        if cycleModule and cycleModule:IsA("ModuleScript") then
            local ok, mod = pcall(require, cycleModule)
            if ok and type(mod) == "table" and type(mod.IsNightPhase) == "function" then
                local nightOk, res = pcall(mod.IsNightPhase, workspace:GetServerTimeNow())
                return nightOk and res == true
            end
        end
        return false
    end

    local function isWallSealed()
        local client = Services.ReplicatedStorage:FindFirstChild("Client")
        local wallModule = client and client:FindFirstChild("AreaEggResetWall")
        if wallModule and wallModule:IsA("ModuleScript") then
            local ok, mod = pcall(require, wallModule)
            if ok and type(mod) == "table" and type(mod.IsSealed) == "function" then
                local sealedOk, res = pcall(mod.IsSealed)
                return sealedOk and res == true
            end
        end

        local world = Services.Workspace:FindFirstChild("World") or Services.Workspace:FindFirstChild("__OBJECTS")
        local areas = world and world:FindFirstChild("Areas")
        local wallCol = areas and areas:FindFirstChild("WallStartCollision")
        return (wallCol and wallCol:IsA("BasePart") and wallCol.CanCollide == true) or false
    end

    local function isMapClosed()
        return isNightPhase() or isWallSealed()
    end

    local function isNormalStealPanelTarget()
        return State.targetedSpecificUid ~= nil
    end

    local function isStealEnabled()
        if isMapClosed() then return false end
        return getgenv().config.autoFarm == true or isNormalStealPanelTarget()
    end

    local function isFastStealArea(areaId)
        if not areaId then return false end
        local clean = cleanName(areaId)
        return clean:find("titan", 1, true) ~= nil 
            or clean:find("light", 1, true) ~= nil 
            or clean:find("enchanted", 1, true) ~= nil
    end

    local function matchesTargetArea(areaId)
        local targetAreas = getgenv().config.targetAreas or { ["All"] = true }
        if targetAreas["All"] == true or next(targetAreas) == nil then return true end
        if not areaId then return false end
        local cleanArea = tostring(areaId):lower():gsub("[^%w]", "")
        for selArea, selVal in pairs(targetAreas) do
            if selVal == true and selArea ~= "All" then
                local cleanSel = tostring(selArea):lower():gsub("[^%w]", "")
                if cleanArea == cleanSel or cleanArea:find(cleanSel, 1, true) or cleanSel:find(cleanArea, 1, true) then
                    return true
                end
            end
        end
        return false
    end

    local function getRemote(pathName)
        local packages = Services.ReplicatedStorage:FindFirstChild("Packages") or (Services.ReplicatedStorage.WaitForChild and Services.ReplicatedStorage:WaitForChild("Packages", 3))
        local networking = packages and (packages:FindFirstChild("Networking") or (packages.WaitForChild and packages:WaitForChild("Networking", 3)))
        local remote = networking and networking:FindFirstChild(pathName)
        if not remote then
            for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
                if (desc:IsA("RemoteFunction") or desc:IsA("RemoteEvent")) and desc.Name == pathName then
                    return desc
                end
            end
        end
        return remote
    end

    local Remotes = {
        AskFieldEggDrop = getRemote("RF/EggWorld/AskFieldEggDrop"),
        AskFieldEggCarry = getRemote("RF/EggWorld/AskFieldEggCarry"),
        AskDoff = getRemote("RF/Treadmill/AskDoff"),
        AskWearStill = getRemote("RF/Treadmill/AskWearStill"),
        AskSnapshot = getRemote("RF/EggWorld/AskFieldEggSnapshot"),
        TierRaise = getRemote("RF/Treadmill/AskTierRaise"),
        BaseTierRaise = getRemote("RE/Homestead/AskBaseTierRaise"),
        AskRigWipe = getRemote("RE/RigSync/AskRigWipe"),
        ClaimNet = getRemote("RF/Butterflies/AskClaimNet"),
        TradeUp = getRemote("RF/Butterflies/AskTradeUp"),
        CraftEssence = getRemote("RF/Butterflies/AskCraftEssence"),
        WispRequest = getRemote("RF/WispCompanion/Request")
    }

    local function invokeRemote(pathName, ...)
        local remote = getRemote(pathName)
        if remote and remote:IsA("RemoteFunction") then
            local ok, r1, r2, r3 = pcall(function(...) return remote:InvokeServer(...) end, ...)
            if ok then return true, r1, r2, r3 end
            return false, r1
        end
        return false, "RemoteFunction not found: " .. tostring(pathName)
    end

    local function fireRemote(pathName, ...)
        local remote = getRemote(pathName)
        if remote and remote:IsA("RemoteEvent") then
            pcall(function(...) remote:FireServer(...) end, ...)
            return true
        end
        return false
    end

    local GameModules = {}
    local _moduleCache = {}
    local modulePaths = {
        EggState = { "Client", "EggState" },
        Assets = { "Data", "Assets" },
        Mutations = { "Shared", "Modules", "Mutations" },
        EggRecords = { "Shared", "Util", "EggRecords" },
        AreaEggCycle = { "Shared", "Util", "AreaEggCycle" },
        PlotState = { "Client", "PlotState" },
        UFOSightingsPipePuzzle = { "Shared", "Modules", "UFOSightingsPipePuzzle" },
        Wisp = { "Data", "WispQuests" },
        Areas = { "Data", "Areas" }
    }

    function GameModules:Get(name)
        if _moduleCache[name] then return _moduleCache[name] end
        local path = modulePaths[name]
        if not path then return nil end

        local current = Services.ReplicatedStorage
        for _, part in ipairs(path) do
            current = current and (current:FindFirstChild(part) or (current.WaitForChild and current:WaitForChild(part, 3)))
            if not current then break end
        end

        if current and current:IsA("ModuleScript") then
            local getid = getthreadidentity or get_thread_identity
            local setid = setthreadidentity or set_thread_identity
            local oldId = getid and getid()
            if setid then pcall(setid, 8) end
            local ok, mod = pcall(require, current)
            if setid and oldId then pcall(setid, oldId) end
            if ok and type(mod) == "table" then
                _moduleCache[name] = mod
                return mod
            end
        end
        return nil
    end

    local function getEggState()
        return GameModules:Get("EggState")
    end

    local EggState = getEggState()

    local function getFieldEggRecords()
        -- Path 1: Client EggState.ReadFieldEggs() with elevated identity 8
        local es = GameModules:Get("EggState") or EggState or getEggState()
        if es and typeof(es.ReadFieldEggs) == "function" then
            local getid = getthreadidentity or get_thread_identity
            local setid = setthreadidentity or set_thread_identity
            local oldId = getid and getid()
            if setid then pcall(setid, 8) end
            local ok, data = pcall(es.ReadFieldEggs)
            if setid and oldId then pcall(setid, oldId) end
            if ok and type(data) == "table" and type(data.Records) == "table" and next(data.Records) ~= nil then
                State.cachedFieldEggs = data.Records
                return data.Records
            end
        end

        -- Path 2: Network Snapshot Fallback (RF/EggWorld/AskFieldEggSnapshot)
        local snapshotRemote = getRemote("RF/EggWorld/AskFieldEggSnapshot") or (Remotes and Remotes.AskSnapshot)
        if snapshotRemote and snapshotRemote:IsA("RemoteFunction") then
            local ok, data = pcall(function() return snapshotRemote:InvokeServer() end)
            if ok and type(data) == "table" and type(data.Records) == "table" and next(data.Records) ~= nil then
                State.cachedFieldEggs = data.Records
                return data.Records
            end
        end

        -- Path 3: Fallback to persistent cached eggs if live fetch temporarily yielded nil
        if State.cachedFieldEggs and type(State.cachedFieldEggs) == "table" and next(State.cachedFieldEggs) ~= nil then
            return State.cachedFieldEggs
        end

        return {}
    end

    pcall(function()
        local packages = Services.ReplicatedStorage:WaitForChild("Packages", 5)
        local networking = packages and packages:WaitForChild("Networking", 5)
        local refreshRemote = networking and networking:FindFirstChild("RE/RigSync/Refresh")
        if refreshRemote and refreshRemote:IsA("RemoteEvent") then
            refreshRemote.OnClientEvent:Connect(function(packet)
                if type(packet) == "table" and packet.Action == "Relocate" then
                    State.lastServerRollbackTime = os.clock()
                end
            end)
        end
    end)

    -- Export shared bindings to module context
    S.Services = Services
    S.LocalPlayer = LocalPlayer
    S.PlayerGui = PlayerGui
    S.UniversalCompat = UniversalCompat
    S.currentSettings = currentSettings
    S.saveStuff = saveStuff
    S.State = State
    S.CONFIG = CONFIG
    S.formatMoneyPerSec = formatMoneyPerSec
    S.cleanName = cleanName
    S.isBlacklisted = isBlacklisted
    S.blacklistEgg = blacklistEgg
    S.isMapClosed = isMapClosed
    S.isNormalStealPanelTarget = isNormalStealPanelTarget
    S.isStealEnabled = isStealEnabled
    S.isFastStealArea = isFastStealArea
    S.matchesTargetArea = matchesTargetArea
    S.getRemote = getRemote
    S.Remotes = Remotes
    S.invokeRemote = invokeRemote
    S.fireRemote = fireRemote
    S.GameModules = GameModules
    S.EggState = EggState
    S.getFieldEggRecords = getFieldEggRecords
end
