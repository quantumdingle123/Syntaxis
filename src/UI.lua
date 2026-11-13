-- ==============================================================================
-- [ SYNTAX HUB - MODULE: UI.lua ]
-- ==============================================================================
return function(S)
    local currentSettings, saveStuff, State, formatMoneyPerSec, isBlacklisted = S.currentSettings, S.saveStuff, S.State, S.formatMoneyPerSec, S.isBlacklisted
    local GameModules, getFieldEggRecords, abortStealRoutine, MasterRegistry, isHoldingEgg = S.GameModules, S.getFieldEggRecords, S.abortStealRoutine, S.MasterRegistry, S.isHoldingEgg

    -- [ GUI INITIALIZATION & CONTROLS BINDINGS VIA GUILIB ]
    -- ==============================================================================
    local SyntaxisLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/quantumdingle123/GUILib/main/SyntaxisLib.lua"))()

    S.Window = SyntaxisLib:CreateWindow({
        Title = "Syntaxis",
        GameName = "Steal An Egg",
        GuiName = "SyntaxHubGUI",
        ShowLoader = true,
        Theme = currentSettings.Theme or "Sapphire",
        Transparency = currentSettings.Transparency or 0,
        State = State,
        OnThemeChanged = function(themeName, themePalette)
            S.activeTheme = themePalette
            currentSettings.Theme = themeName
            saveStuff()
        end
    })

    S.activeTheme = S.Window:GetActiveTheme()

    -- ==============================================================================
    -- [ TAB 1: FARM CONTROLS & EVENT CATEGORIES ]
    -- ==============================================================================
    local FarmTab = S.Window:CreateTab("Farm", "Farm")

    -- Automation Steal Category
    local stealCategory = FarmTab:CreateCategory("Automation Steal", false, 1)

    stealCategory:CreateToggle("Auto Steal", "Automatically steal eggs from areas", currentSettings.AutoFarm, function(state)
        getgenv().config.autoFarm = state
        currentSettings.AutoFarm = state
        saveStuff()
        table.clear(State.blacklistedEggs)
        if not state then
            abortStealRoutine()
        end
    end)

    stealCategory:CreateToggle("Fast Steal", "Only works on Titan temple and above areas.", currentSettings.FastSteal, function(state)
        getgenv().config.fastSteal = state
        currentSettings.FastSteal = state
        saveStuff()
        if state then
            S.Window:ShowWarningModal("Fast Steal Warning", "Fast Steal is unreliable. Do not use if you are lagging or AFK farming.")
        else
            if State.isStealingActive and not isHoldingEgg() then
                abortStealRoutine()
            end
        end
    end)

    local areaList = {
        "All", "Forest", "Lake", "Desert", "Jungle", "Snow", 
        "Volcano", "Abyss Ocean", "Prehistoric", "Cosmic", 
        "Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest"
    }

    stealCategory:CreateMultiDropdown("Target Areas", "Select one or multiple areas (empty = all)", areaList, currentSettings.TargetAreas, function(selectedMap)
        getgenv().config.targetAreas = selectedMap
        currentSettings.TargetAreas = selectedMap
        saveStuff()
        table.clear(State.blacklistedEggs)
    end)

    local rarityList = {
        "All", "1 - Common", "2 - Uncommon", "3 - Rare", "4 - Epic",
        "5 - Legendary", "6 - Mythic", "7 - Cosmic", "8 - Secret",
        "9 - Eternal", "10 - Divine"
    }

    stealCategory:CreateDropdown("Min Rarity", "Only steal eggs with rarity >= this", rarityList, currentSettings.MinRarity, function(selected)
        getgenv().config.minRarity = selected
        currentSettings.MinRarity = selected
        saveStuff()
        table.clear(State.blacklistedEggs)
    end)

    -- Automation Treadmill Category
    local treadmillCategory = FarmTab:CreateCategory("Automation Treadmill", false, 2)

    treadmillCategory:CreateToggle("Auto Treadmill", "Gain treadmill speed when idle", currentSettings.AutoTreadmill, function(state)
        getgenv().config.autoTreadmill = state
        currentSettings.AutoTreadmill = state
        saveStuff()
    end)

    -- UFO Event Category
    local ufoCategory = FarmTab:CreateCategory("UFO Event", false, 3)

    ufoCategory:CreateToggle("Auto UFO", "Automate decoding, tractor beam delivery & rewards", currentSettings.AutoUFO, function(state)
        getgenv().config.autoUFO = state
        currentSettings.AutoUFO = state
        saveStuff()
        if state and S.UFOManager and S.UFOManager.FetchState then
            pcall(function() S.UFOManager:FetchState() end)
        end
    end)

    ufoCategory:CreateToggle("Collect UFO Debris", "Collect space rocks across the world", currentSettings.UFORocks, function(state)
        getgenv().config.ufoRocks = state
        currentSettings.UFORocks = state
        saveStuff()
        if state and S.UFOManager and S.UFOManager.FetchState then
            pcall(function() S.UFOManager:FetchState() end)
        end
    end)

    ufoCategory:CreateToggle("Farm Rare UFO", "Board mothership, smash capsules, vault & alien staff", currentSettings.UFORare, function(state)
        getgenv().config.ufoRare = state
        currentSettings.UFORare = state
        saveStuff()
        if state and S.UFOManager and S.UFOManager.FetchState then
            pcall(function() S.UFOManager:FetchState() end)
        end
    end)

    ufoCategory:CreateToggle("Auto Trade Debris", "Trade space rocks at Alien Camp", currentSettings.UFOTrade, function(state)
        getgenv().config.ufoTrade = state
        currentSettings.UFOTrade = state
        saveStuff()
        if state and S.UFOManager and S.UFOManager.FetchState then
            pcall(function() S.UFOManager:FetchState() end)
        end
    end)

    ufoCategory:CreateToggle("Teleport If Far From Egg", "Rapid travel to distant UFO eggs", currentSettings.UFOTp, function(state)
        getgenv().config.ufoTp = state
        currentSettings.UFOTp = state
        saveStuff()
    end)

    -- Enchanted / Bloom Event Category
    local bloomCategory = FarmTab:CreateCategory("Enchanted / Bloom Event", false, 4)

    bloomCategory:CreateToggle("Auto Butterfly Bloom", "Safe ground-level butterfly catching", currentSettings.AutoCatchButterfly, function(state)
        getgenv().config.autoCatchButterfly = state
        currentSettings.AutoCatchButterfly = state
        saveStuff()
    end)

    bloomCategory:CreateDropdown("Catch Mode", "Stand in center or ground chase", {"Stand", "Chase"}, currentSettings.BloomCatchMode or "Stand", function(selected)
        getgenv().config.bloomCatchMode = selected
        currentSettings.BloomCatchMode = selected
        saveStuff()
    end)

    bloomCategory:CreateDropdown("Catch Priority", "Priority order for Chase mode", {"Rarest", "Nearest"}, currentSettings.BloomCatchPriority or "Rarest", function(selected)
        getgenv().config.bloomCatchPriority = selected
        currentSettings.BloomCatchPriority = selected
        saveStuff()
    end)

    bloomCategory:CreateSlider("Catch Speed", "Ground movement speed for Chase mode", 100, 600, currentSettings.ButterflySpeed, function(val)
        getgenv().config.butterflySpeed = val
        currentSettings.ButterflySpeed = val
        saveStuff()
    end)

    bloomCategory:CreateToggle("Auto Trade Up", "Trade butterflies at station inside tree", currentSettings.AutoTradeUp, function(state)
        getgenv().config.autoTradeUp = state
        currentSettings.AutoTradeUp = state
        saveStuff()
    end)

    bloomCategory:CreateToggle("Smart Trade For Essence", "Only trade exact counts needed for essence", currentSettings.BloomSmartTrade ~= false, function(state)
        getgenv().config.bloomSmartTrade = state
        currentSettings.BloomSmartTrade = state
        saveStuff()
    end)

    bloomCategory:CreateToggle("Auto Craft Essence", "Craft mutation essence at shrine inside tree", currentSettings.AutoCraftEssence, function(state)
        getgenv().config.autoCraftEssence = state
        currentSettings.AutoCraftEssence = state
        saveStuff()
    end)

    bloomCategory:CreateToggle("Auto Wisp Quest", "Accept, progress & claim wisp companion quests", currentSettings.AutoWispQuest, function(state)
        getgenv().config.autoWispQuest = state
        currentSettings.AutoWispQuest = state
        saveStuff()
    end)

    -- Automation Upgrades Category
    local upgradesCategory = FarmTab:CreateCategory("Automation Upgrades", false, 5)

    upgradesCategory:CreateToggle("Auto Upgrade Treadmill", "Auto buy next tier treadmill", currentSettings.AutoUpgradeTreadmill, function(state)
        getgenv().config.autoUpgradeTreadmill = state
        currentSettings.AutoUpgradeTreadmill = state
        saveStuff()
    end)

    upgradesCategory:CreateToggle("Auto Upgrade Base", "Auto buy homestead base expansion", currentSettings.AutoUpgradeBase, function(state)
        getgenv().config.autoUpgradeBase = state
        currentSettings.AutoUpgradeBase = state
        saveStuff()
    end)

    -- ==============================================================================
    -- [ TAB 2: TASK PRIORITY MANAGER ]
    -- ==============================================================================
    local PriorityTab = S.Window:CreatePriorityTab("Priority", "Task Priority", {
        GetList = function()
            return S.PriorityManager.List
        end,
        OnMoveUp = function(index)
            S.PriorityManager:MoveUp(index, function(list)
                currentSettings.TaskPriorities = list
                saveStuff()
            end)
        end,
        OnMoveDown = function(index)
            S.PriorityManager:MoveDown(index, function(list)
                currentSettings.TaskPriorities = list
                saveStuff()
            end)
        end
    })

    -- ==============================================================================
    -- [ TAB 3: STEAL SCANNER PANEL ]
    -- ==============================================================================
    local function getStealPanelEggItems()
        local records = getFieldEggRecords()
        if not records or type(records) ~= "table" or next(records) == nil then
            return State.cachedStealPanelItems or {}
        end

        if State.targetedSpecificUid and not isHoldingEgg() and not State.isStealingActive then
            local found = false
            for uid, record in pairs(records) do
                if type(record) == "table" then
                    if uid == State.targetedSpecificUid or record.Uid == State.targetedSpecificUid then
                        found = true
                        break
                    end
                end
            end
            if not found then
                State.targetedSpecificUid = nil
            end
        end

        -- Lazy load game Assets and Mutations modules via GameModules
        local assetsMod = GameModules:Get("Assets")
        local assetsDir = assetsMod and assetsMod.Directory
        local mutationsMod = GameModules:Get("Mutations")

        local eggItems = {}

        for keyUid, record in pairs(records) do
            if type(record) == "table" then
                local uid = (type(record.Uid) == "string" and record.Uid) or (type(keyUid) == "string" and keyUid) or nil
                record.Uid = uid

                if type(uid) == "string" and string.sub(uid, 1, 12) ~= "FirstAreaEgg" and not isBlacklisted(uid) then
                    local state = record.State
                    -- Support Slot, Dropped, Carried, Placed and nil states (matching hot.lua line 7755)
                    if state == "Slot" or state == "Dropped" or state == "Carried" or state == "Placed" or state == nil then
                        local cat = tostring(record.AssetCategory or record.Category or record.Name or "Unknown")
                        local assetData = (assetsDir and assetsDir[cat]) or MasterRegistry.PetDatabase[cat] or {}

                        local displayName = tostring(assetData.DisplayName or cat)
                        local rarityData = (type(assetData.Rarity) == "table" and assetData.Rarity) or {}
                        local rarityName = tostring(rarityData.DisplayName or rarityData._id or assetData.Rarity or "Common")
                        local rarityRank = tonumber(rarityData.RarityNumber or rarityData.Rank or assetData.Rank) or (MasterRegistry.RarityRanks and MasterRegistry.RarityRanks[rarityName]) or 1

                        local scale = tonumber(record.AssetScale) or 1
                        local scaleFactor = (scale > 5) and (((scale / 5) ^ 1.2) * 19.637875755794113) or (scale ^ 1.85)

                        local mutationMultiplier = 1
                        if mutationsMod and typeof(mutationsMod.EarningsFor) == "function" and type(record.Mutations) == "table" then
                            local ok, mul = pcall(mutationsMod.EarningsFor, record.Mutations)
                            if ok and type(mul) == "number" and mul > 0 then
                                mutationMultiplier = mul
                            end
                        elseif record.Mutations and #record.Mutations > 0 then
                            mutationMultiplier = 2.5
                        end

                        local baseRate = tonumber(assetData.EarningRate) or 0
                        local valuePerSec = baseRate * scaleFactor * mutationMultiplier

                        local iconId = tostring(assetData.Icon or assetData.Thumbnail or "")
                        if iconId ~= "" and tonumber(iconId) then iconId = "rbxassetid://" .. iconId end

                        table.insert(eggItems, {
                            Uid = uid,
                            Name = displayName,
                            Area = tostring(record.AreaId or "Unknown"),
                            Scale = scale,
                            Rarity = rarityName,
                            Rank = rarityRank,
                            Value = valuePerSec,
                            Icon = iconId,
                            Record = record
                        })
                    end
                end
            end
        end

        if #eggItems > 0 then
            State.cachedStealPanelItems = eggItems
        end

        return (#eggItems > 0 and eggItems) or State.cachedStealPanelItems or {}
    end

    local StealPanelTab, renderStealPanel = S.Window:CreateStealPanelTab("Steal Panel", "Steal Panel", {
        FormatValue = formatMoneyPerSec,
        GetItems = getStealPanelEggItems,
        OnSelectItem = function(item, actBtn)
            local curTheme = S.Window:GetActiveTheme()
            if State.targetedSpecificUid == item.Uid then
                State.targetedSpecificUid = nil
                abortStealRoutine()
                actBtn.BackgroundColor3 = curTheme.Accent
                actBtn.Text = "Steal"
            else
                if State.isStealingActive then
                    abortStealRoutine()
                end
                State.targetedSpecificUid = item.Uid
                State.blacklistedEggs[item.Uid] = nil
                for u, b in pairs(State.activeStealButtons) do
                    if u == item.Uid then
                        b.BackgroundColor3 = Color3.fromRGB(240, 65, 60)
                        b.Text = "Stop Steal"
                    else
                        b.BackgroundColor3 = curTheme.Accent
                        b.Text = "Steal"
                    end
                end
            end
        end
    })

    -- ==============================================================================
    -- [ TAB 4: SETTINGS & THEME CUSTOMIZATION ]
    -- ==============================================================================
    local SettingsTab = S.Window:CreateSettingsTab("Settings", "Settings", {
        OnThemeSelected = function(themeName)
            currentSettings.Theme = themeName
            saveStuff()
        end,
        OnTransparencyChanged = function(val)
            currentSettings.Transparency = val
            saveStuff()
        end
    })

    -- Background Refresh for Steal Panel (every 1.5s while panel is visible)
    task.spawn(function()
        while true do
            task.wait(1.5)
            if StealPanelTab.Page and StealPanelTab.Page.Visible and (not S.Window.MainFrame or S.Window.MainFrame.Visible) and not State.isStealingActive and renderStealPanel then
                pcall(renderStealPanel)
            end
        end
    end)

    -- Initialize Window
    S.Window:Initialize()

    -- Show Community Discord Popup after initial launch / loader completes
    local function showStartupDiscordModal()
        task.delay(0.15, function()
            if S.Window and S.Window.Context and S.Window.Context.IsAlive then
                S.Window:ShowDiscordModal()
            end
        end)
    end

    if S.Window._ActiveLoader and typeof(S.Window._ActiveLoader.OnComplete) == "function" then
        S.Window._ActiveLoader:OnComplete(showStartupDiscordModal)
    else
        task.defer(function()
            task.wait(0.5)
            if S.Window and S.Window.Context and S.Window.Context.IsAlive then
                S.Window:ShowDiscordModal()
            end
        end)
    end
end
