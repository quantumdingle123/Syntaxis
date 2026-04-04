if _G.AsylumFarmKill then _G.AsylumFarmKill() end

-- grab all the standard roblox services we need
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- simulate dummy clicks so roblox doesn't kick us for being afk
player.Idled:Connect(function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

-- The exact staging coordinate we walk to for the feeder/safe roles
local DEST = CFrame.new(-10.1279593, 255.272766, -611.696594)

-- safe zone ring setup
local RING_POSITION = Vector3.new(-19.12, 256.01, -595.00)
local RING_SIZE = Vector3.new(26, 12, 26)
local RING_ROTATION_Y = -30
local ringCFrame = CFrame.new(RING_POSITION) * CFrame.Angles(0, math.rad(RING_ROTATION_Y), 0)

-- drawing the safe zone box so we can actually see where it is
local ringVisualsFolder = workspace:FindFirstChild("RingVisuals")
if not ringVisualsFolder then
	ringVisualsFolder = Instance.new("Folder")
	ringVisualsFolder.Name = "RingVisuals"
	ringVisualsFolder.Parent = workspace
	
	local boxPart = Instance.new("Part")
	boxPart.Name = "DetectionBox"
	boxPart.Size = RING_SIZE
	boxPart.CFrame = ringCFrame
	boxPart.Anchored = true
	boxPart.CanCollide = false
	boxPart.CanTouch = false
	boxPart.CanQuery = false
	boxPart.Transparency = 1
	boxPart.Parent = ringVisualsFolder

	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee = boxPart
	selectionBox.LineThickness = 0
	selectionBox.Transparency = 1
	selectionBox.Parent = boxPart
end

-- the neon highlight that glows on whatever player we are currently chasing
local targetHighlight = Instance.new("Highlight")
targetHighlight.Name = "TargetHighlight"
targetHighlight.FillColor = Color3.fromRGB(86, 220, 156) 
targetHighlight.FillTransparency = 0.5
targetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
targetHighlight.OutlineTransparency = 0.2
targetHighlight.Parent = ringVisualsFolder
targetHighlight.Adornee = nil

-- master states and target trackers
local dead = false
local role = nil
local running = false
local isPausedForSafety = false
local savedRole = nil
local currentHealTarget = nil 
local currentArrestTarget = nil
local isInteracting = false 
local aimbotTarget = nil

-- AUTO GEN ENGINE GLOBALS
getgenv().AutoGenEnabled = false
getgenv().AutoBatteryEnabled = false
getgenv().IsUnderground = false 
getgenv().SafeToBypass = false
getgenv().CurrentPlatform = nil

-- placeholders for ui functions that are built further down
local setStatus = function(txt) end
local updateFarmBtns = function() end

local function destroyVirtualPlatform()
    if getgenv().CurrentPlatform then
        getgenv().CurrentPlatform:Destroy()
        getgenv().CurrentPlatform = nil
    end
end

-- clears out map doors so they don't break our pathfinding routes
local function removeDoors()
	local count = 0
	for _, object in pairs(workspace:GetDescendants()) do
		if string.find(string.lower(object.Name), "door") then
			pcall(function() object:Destroy() end)
			count += 1
		end
	end
end

-- all 7 stunning ui themes
local Themes = {
	Dark = {
		Main = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 18, 24)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(28, 28, 36)), ColorSequenceKeypoint.new(1, Color3.fromRGB(38, 38, 48))},
		Topbar = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 24, 32)), ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 52))},
		Button = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 42, 56)), ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 58, 74))},
		ButtonHover = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 60, 78)), ColorSequenceKeypoint.new(1, Color3.fromRGB(84, 84, 104))},
		Accent = Color3.fromRGB(120, 125, 145), Accent2 = Color3.fromRGB(170, 175, 195),
		Text = Color3.fromRGB(240, 240, 245), SubText = Color3.fromRGB(180, 180, 195), Stroke = Color3.fromRGB(85, 85, 105), Glow = Color3.fromRGB(130, 135, 160)
	},
	Red = {
		Main = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(36, 12, 18)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(54, 18, 26)), ColorSequenceKeypoint.new(1, Color3.fromRGB(78, 28, 38))},
		Topbar = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 15, 24)), ColorSequenceKeypoint.new(1, Color3.fromRGB(86, 28, 40))},
		Button = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(94, 32, 44)), ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 44, 58))},
		ButtonHover = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(122, 42, 56)), ColorSequenceKeypoint.new(1, Color3.fromRGB(168, 58, 74))},
		Accent = Color3.fromRGB(220, 78, 98), Accent2 = Color3.fromRGB(255, 130, 145),
		Text = Color3.fromRGB(255, 238, 240), SubText = Color3.fromRGB(232, 185, 192), Stroke = Color3.fromRGB(160, 68, 82), Glow = Color3.fromRGB(255, 95, 115)
	},
	Sapphire = {
		Main = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 24, 50)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 40, 78)), ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 58, 108))},
		Topbar = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 36, 70)), ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 62, 110))},
		Button = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 78, 132)), ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 102, 166))},
		ButtonHover = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 110, 176)), ColorSequenceKeypoint.new(1, Color3.fromRGB(86, 142, 215))},
		Accent = Color3.fromRGB(92, 170, 255), Accent2 = Color3.fromRGB(160, 215, 255),
		Text = Color3.fromRGB(240, 248, 255), SubText = Color3.fromRGB(180, 210, 235), Stroke = Color3.fromRGB(88, 132, 185), Glow = Color3.fromRGB(96, 180, 255)
	},
	Emerald = {
		Main = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 32, 24)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 52, 38)), ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 76, 54))},
		Topbar = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 46, 34)), ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 72, 52))},
		Button = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 92, 66)), ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 124, 88))},
		ButtonHover = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 136, 98)), ColorSequenceKeypoint.new(1, Color3.fromRGB(78, 170, 125))},
		Accent = Color3.fromRGB(86, 220, 156), Accent2 = Color3.fromRGB(152, 255, 204),
		Text = Color3.fromRGB(236, 255, 245), SubText = Color3.fromRGB(176, 220, 196), Stroke = Color3.fromRGB(72, 150, 112), Glow = Color3.fromRGB(100, 255, 180)
	},
	Amethyst = {
		Main = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 14, 42)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(44, 24, 66)), ColorSequenceKeypoint.new(1, Color3.fromRGB(62, 34, 94))},
		Topbar = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 20, 62)), ColorSequenceKeypoint.new(1, Color3.fromRGB(68, 32, 98))},
		Button = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(82, 42, 120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(108, 58, 154))},
		ButtonHover = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(122, 72, 176)), ColorSequenceKeypoint.new(1, Color3.fromRGB(152, 102, 212))},
		Accent = Color3.fromRGB(190, 110, 255), Accent2 = Color3.fromRGB(225, 180, 255),
		Text = Color3.fromRGB(249, 242, 255), SubText = Color3.fromRGB(212, 188, 230), Stroke = Color3.fromRGB(134, 92, 180), Glow = Color3.fromRGB(205, 120, 255)
	},
	Gold = {
		Main = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 30, 10)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(66, 46, 16)), ColorSequenceKeypoint.new(1, Color3.fromRGB(92, 68, 24))},
		Topbar = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(68, 46, 14)), ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 78, 26))},
		Button = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(132, 96, 32)), ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 126, 44))},
		ButtonHover = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(182, 140, 52)), ColorSequenceKeypoint.new(1, Color3.fromRGB(224, 178, 74))},
		Accent = Color3.fromRGB(255, 204, 82), Accent2 = Color3.fromRGB(255, 232, 145),
		Text = Color3.fromRGB(255, 248, 232), SubText = Color3.fromRGB(228, 210, 170), Stroke = Color3.fromRGB(190, 148, 62), Glow = Color3.fromRGB(255, 214, 92)
	},
	Rose = {
		Main = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 18, 28)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 28, 44)), ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 42, 62))},
		Topbar = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(62, 24, 38)), ColorSequenceKeypoint.new(1, Color3.fromRGB(98, 40, 58))},
		Button = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 52, 76)), ColorSequenceKeypoint.new(1, Color3.fromRGB(162, 70, 104))},
		ButtonHover = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(186, 90, 124)), ColorSequenceKeypoint.new(1, Color3.fromRGB(224, 118, 154))},
		Accent = Color3.fromRGB(255, 126, 170), Accent2 = Color3.fromRGB(255, 188, 212),
		Text = Color3.fromRGB(255, 242, 247), SubText = Color3.fromRGB(234, 190, 205), Stroke = Color3.fromRGB(190, 96, 132), Glow = Color3.fromRGB(255, 135, 180)
	}
}

local currentThemeName = "Emerald"
local currentTheme = Themes[currentThemeName]

local function getLatest()
	local c = player.Character
	if not c then return nil, nil, nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	return c, h, r
end

local function alive()
	local c, h, r = getLatest()
	return (c ~= nil and h ~= nil and r ~= nil and h.Health > 0 and c.Parent ~= nil)
end

local function inRing()
	local c, h, r = getLatest()
	if not (c and h and r and h.Health > 0) then return false end
	local relative = ringCFrame:PointToObjectSpace(r.Position)
	local halfSize = RING_SIZE / 2
	return math.abs(relative.X) <= halfSize.X and math.abs(relative.Y) <= halfSize.Y and math.abs(relative.Z) <= halfSize.Z
end

local function getClosestPlayerInRing()
	local closest, minDist = nil, math.huge
	local c, h, r = getLatest()
	if not r then return nil end

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			local th = p.Character:FindFirstChildOfClass("Humanoid")
			local tr = p.Character:FindFirstChild("HumanoidRootPart")
			
			if th and tr and th.Health > 0 then
				local relative = ringCFrame:PointToObjectSpace(tr.Position)
				local halfSize = RING_SIZE / 2
				local pInRing = math.abs(relative.X) <= halfSize.X and math.abs(relative.Y) <= halfSize.Y and math.abs(relative.Z) <= halfSize.Z
				
				if pInRing then
					local dist = (r.Position - tr.Position).Magnitude
					if dist < minDist then minDist = dist; closest = p end
				end
			end
		end
	end
	return closest
end

local function isHostile(targetChar)
	local pGui = player:FindFirstChild("PlayerGui")
	local overheadGuis = pGui and pGui:FindFirstChild("OverheadGuis")
	if not overheadGuis then return false end
	
	for _, gui in ipairs(overheadGuis:GetChildren()) do
		if gui:IsA("BillboardGui") and gui.Adornee and gui.Adornee:IsDescendantOf(targetChar) then
			local holder = gui:FindFirstChild("Holder")
			local hostileTag = holder and holder:FindFirstChild("Hostile")
			
			if hostileTag and hostileTag:IsA("TextLabel") and hostileTag.Visible then
				if string.find(string.lower(hostileTag.Text), "hostile") then return true end
			end
		end
	end
	return false
end

local function getClosestHurtPlayer()
	local closest, minDist = nil, math.huge
	local c, h, r = getLatest()
	if not r then return nil end

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			local th = p.Character:FindFirstChildOfClass("Humanoid")
			local tr = p.Character:FindFirstChild("HumanoidRootPart")
			
			if th and tr and th.Health > 0 and th.Health < th.MaxHealth then
				local dist = (r.Position - tr.Position).Magnitude
				if dist < minDist then minDist = dist; closest = p end
			end
		end
	end
	return closest
end

local function getClosestHostilePlayer()
	local closest, minDist = nil, math.huge
	local c, h, r = getLatest()
	if not r then return nil end

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			local th = p.Character:FindFirstChildOfClass("Humanoid")
			local tr = p.Character:FindFirstChild("HumanoidRootPart")
			
			if th and tr and th.Health > 0 and isHostile(p.Character) then
				local dist = (r.Position - tr.Position).Magnitude
				if dist < minDist then minDist = dist; closest = p end
			end
		end
	end
	return closest
end

local function isToolReady(toolName)
	local bp = player:FindFirstChild("Backpack")
	local c = player.Character
	
	local searchName = toolName
	if toolName == "Box" then
		if (bp and bp:FindFirstChild("Arrest")) or (c and c:FindFirstChild("Arrest")) then
			searchName = "Arrest"
		end
	end
	
	local tool = (c and c:FindFirstChild(searchName)) or (bp and bp:FindFirstChild(searchName))
	
	if tool then
		local readyAttr = tool:GetAttribute("Ready")
		if readyAttr ~= nil then
			return readyAttr == true
		end
		return true 
	end
	return false
end

task.spawn(function()
	while not dead do
		task.wait(0.1)
		if running and alive() and (role == "SAFE FARMER" or role == "SAFE FEEDER") then
			local c = player.Character
			if c and inRing() then
				local target = getClosestPlayerInRing()
				local tool = c:FindFirstChildOfClass("Tool")
				
				if target and target.Character then
					local targetHum = target.Character:FindFirstChild("Humanoid")
					if targetHum and targetHum.Health > 0 then
						local hpPercent = targetHum.Health / targetHum.MaxHealth
						
						if role == "SAFE FARMER" then
							if tool then tool:Activate() end
							VirtualUser:ClickButton1(Vector2.new())
							
						elseif role == "SAFE FEEDER" then
							if hpPercent <= 0.30 then
								if tool then tool:Deactivate() end
							else
								if tool then tool:Activate() end
								VirtualUser:ClickButton1(Vector2.new())
							end
						end
					else
						if tool then tool:Deactivate() end
					end
				else
					if tool then tool:Deactivate() end
				end
			end
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if aimbotTarget and aimbotTarget.Parent and alive() then
		local c, h, r = getLatest()
		local targetHrp = aimbotTarget:FindFirstChild("HumanoidRootPart")
		
		if r and targetHrp then
			camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetHrp.Position)
			r.CFrame = CFrame.lookAt(r.Position, Vector3.new(targetHrp.Position.X, r.Position.Y, targetHrp.Position.Z))
		end
	end
end)

task.spawn(function()
	while not dead do
		task.wait(1.5) 
		for _, obj in pairs(workspace:GetDescendants()) do
			if obj:IsA("ProximityPrompt") then
				if obj.ActionText == "Box" or obj.Name == "Box" or obj.ObjectText == "Box" or obj.ActionText == "Arrest" or obj.ActionText == "Heal" then
					obj.MaxActivationDistance = 30
				else
					obj.MaxActivationDistance = 10
				end
				obj.RequiresLineOfSight = false
			end
		end
	end
end)

local pathParams = { AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 }
local path = PathfindingService:CreatePath(pathParams)

local visualsFolder = workspace:FindFirstChild("PathVisuals")
if not visualsFolder then
	visualsFolder = Instance.new("Folder")
	visualsFolder.Name = "PathVisuals"
	visualsFolder.Parent = workspace
end

local partPool = {}
local jointPool = {}

local function getFloorPosition(basePos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local c = player.Character
	params.FilterDescendantsInstances = c and {c, visualsFolder, ringVisualsFolder} or {visualsFolder, ringVisualsFolder}
	
	local result = workspace:Raycast(basePos + Vector3.new(0, 3, 0), Vector3.new(0, -15, 0), params)
	if result then return result.Position + Vector3.new(0, 0.2, 0) end
	return basePos - Vector3.new(0, 2, 0) 
end

local function drawWaypoints(waypoints)
	if not visualsFolder or not visualsFolder.Parent then
		visualsFolder = Instance.new("Folder")
		visualsFolder.Name = "PathVisuals"
		visualsFolder.Parent = workspace
	end

	local maxWpToDraw = #waypoints 
	local floorPositions = {}
	
	for i = 1, maxWpToDraw do
		floorPositions[i] = getFloorPosition(waypoints[i].Position)
		local pos = floorPositions[i]
		local joint = jointPool[i]
		
		if not joint or not joint.Parent then
			if not joint then
				joint = Instance.new("Part"); joint.Shape = Enum.PartType.Ball; joint.Anchored = true; joint.CanCollide = false; joint.CanQuery = false; joint.Material = Enum.Material.Neon; jointPool[i] = joint
			end
			joint.Parent = visualsFolder
		end
		
		joint.Size = Vector3.new(1.2, 1.2, 1.2); joint.Position = pos
		if waypoints[i].Action == Enum.PathWaypointAction.Jump then joint.Color = Color3.fromRGB(255, 100, 100) else joint.Color = currentTheme.Accent end
		
		if i < maxWpToDraw then
			if not floorPositions[i+1] then floorPositions[i+1] = getFloorPosition(waypoints[i+1].Position) end
			local nextPos = floorPositions[i+1]
			local dist = (pos - nextPos).Magnitude
			local line = partPool[i]
			
			if not line or not line.Parent then
				if not line then
					line = Instance.new("Part"); line.Shape = Enum.PartType.Cylinder; line.Anchored = true; line.CanCollide = false; line.CanQuery = false; line.Material = Enum.Material.Neon; partPool[i] = line
				end
				line.Parent = visualsFolder
			end
			
			line.Size = Vector3.new(dist, 0.8, 0.8) 
			line.CFrame = CFrame.lookAt(pos, nextPos) * CFrame.new(0, 0, -dist/2) * CFrame.Angles(0, math.rad(90), 0)
			
			if waypoints[i+1].Action == Enum.PathWaypointAction.Jump then line.Color = Color3.fromRGB(255, 100, 100) else line.Color = currentTheme.Accent end
		end
	end
	for i = maxWpToDraw + 1, #jointPool do if jointPool[i] then jointPool[i].Parent = nil end end
	for i = maxWpToDraw, #partPool do if partPool[i] then partPool[i].Parent = nil end end
end

local currentWaypoints = {}
local currentWpIndex = 1
local isNoclipping = false

RunService.Stepped:Connect(function()
	if alive() then
		local c, h, r = getLatest()
		if isNoclipping and c then
			for _, v in ipairs(c:GetDescendants()) do
				if v:IsA("BasePart") then v.CanCollide = false end
			end
		end
	end
end)

local lastComputedTargetPos = nil
local forceRecalculateTimer = 0

task.spawn(function()
	while not dead do
		task.wait(0.2) 
		if running and alive() and not isPausedForSafety then
			local c, h, r = getLatest()
			if r then
				local targetPos = DEST.Position
				local shouldPath = false
				
				if role == "HEALER" then
					currentHealTarget = getClosestHurtPlayer()
					if currentHealTarget and currentHealTarget.Character then
						targetHighlight.Adornee = currentHealTarget.Character
						local tr = currentHealTarget.Character:FindFirstChild("HumanoidRootPart")
						if tr then targetPos = tr.Position; shouldPath = true end
					else
						targetHighlight.Adornee = nil
					end
				elseif role == "ARREST" then
					currentArrestTarget = getClosestHostilePlayer()
					if currentArrestTarget and currentArrestTarget.Character then
						targetHighlight.Adornee = currentArrestTarget.Character
						local tr = currentArrestTarget.Character:FindFirstChild("HumanoidRootPart")
						if tr then targetPos = tr.Position; shouldPath = true end
					else
						targetHighlight.Adornee = nil
					end
				elseif role == "SAFE FARMER" or role == "SAFE FEEDER" then
					if not inRing() then
						targetPos = DEST.Position
						shouldPath = true
						targetHighlight.Adornee = nil
						aimbotTarget = nil 
					else
						shouldPath = false 
						local target = getClosestPlayerInRing()
						if target and target.Character then
							targetHighlight.Adornee = target.Character
							aimbotTarget = target.Character 
						else
							targetHighlight.Adornee = nil
							aimbotTarget = nil
						end
					end
				else
					targetHighlight.Adornee = nil
					if not inRing() then shouldPath = true end
				end
				
				if shouldPath and targetPos then
					forceRecalculateTimer += 0.2
					if not lastComputedTargetPos or (lastComputedTargetPos - targetPos).Magnitude > 2 or forceRecalculateTimer >= 0.8 or #currentWaypoints == 0 then
						forceRecalculateTimer = 0 
						local success = pcall(function() path:ComputeAsync(r.Position, targetPos) end)
						if success and path.Status == Enum.PathStatus.Success then
							local wps = path:GetWaypoints()
							if #wps > 1 then
								lastComputedTargetPos = targetPos; currentWaypoints = wps; currentWpIndex = 2; drawWaypoints(currentWaypoints)
							end
						else
							lastComputedTargetPos = nil
						end
					end
				end
			end
		end
	end
end)

task.spawn(function()
	while not dead do
		task.wait(0.05) 
		if running and alive() and not isPausedForSafety then
			local c, h, r = getLatest()
			if h and r then
				local haltMovement = false
				local directWalkTarget = nil
				
				if role == "HEALER" and currentHealTarget and currentHealTarget.Character then
					local tr = currentHealTarget.Character:FindFirstChild("HumanoidRootPart")
					if tr and (r.Position - tr.Position).Magnitude <= 2.5 then haltMovement = true end
				elseif role == "ARREST" and currentArrestTarget and currentArrestTarget.Character then
					local tr = currentArrestTarget.Character:FindFirstChild("HumanoidRootPart")
					if tr and (r.Position - tr.Position).Magnitude <= 2.5 then haltMovement = true end
				elseif role == "FARMER" or role == "FEEDER" then
					local distToDest = (r.Position - DEST.Position).Magnitude
					if distToDest <= 3.5 or inRing() then haltMovement = true end
				elseif role == "SAFE FARMER" or role == "SAFE FEEDER" then
					if not inRing() then
						local distToDest = (r.Position - DEST.Position).Magnitude
						if distToDest <= 3.5 then haltMovement = true end
					else
						local target = getClosestPlayerInRing()
						if target and target.Character then
							local tr = target.Character:FindFirstChild("HumanoidRootPart")
							if tr then directWalkTarget = tr.Position end
						end
					end
				end
				
				if haltMovement then pcall(function() h:MoveTo(r.Position) end); continue end
				
				if directWalkTarget then
					pcall(function() h:MoveTo(directWalkTarget) end)
					local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {c, visualsFolder, ringVisualsFolder}
					local frontHit = workspace:Raycast(r.Position, r.CFrame.LookVector * 3.5, params)
					if frontHit and frontHit.Instance and frontHit.Instance.CanCollide then h.Jump = true end
					continue
				end
				
				local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {c, visualsFolder, ringVisualsFolder}
				local frontHit = workspace:Raycast(r.Position, r.CFrame.LookVector * 3.5, params)
				if frontHit and frontHit.Instance and frontHit.Instance.CanCollide then h.Jump = true end
				
				if #currentWaypoints > 0 and currentWpIndex <= #currentWaypoints then
					local wp = currentWaypoints[currentWpIndex]
					if wp.Action == Enum.PathWaypointAction.Jump then h.Jump = true end
					pcall(function() h:MoveTo(wp.Position) end)
					local dist = (r.Position * Vector3.new(1,0,1) - wp.Position * Vector3.new(1,0,1)).Magnitude
					if dist < 4.0 then currentWpIndex += 1 end
				end
			end
		end
	end
end)

local checkPos = Vector3.new()
local timeStuck = 0
task.spawn(function()
	while not dead do
		task.wait(1)
		if running and alive() and not isPausedForSafety then
			local c, h, r = getLatest()
			if r then
				local destPos = DEST.Position
				local isPathingToTarget = false
				
				if role == "FARMER" or role == "FEEDER" then
					local distToDest = (r.Position - DEST.Position).Magnitude
					if inRing() or distToDest <= 3.5 then continue end
				elseif role == "HEALER" and currentHealTarget and currentHealTarget.Character then
					local tr = currentHealTarget.Character:FindFirstChild("HumanoidRootPart")
					if tr then destPos = tr.Position; isPathingToTarget = true end
				elseif role == "ARREST" and currentArrestTarget and currentArrestTarget.Character then
					local tr = currentArrestTarget.Character:FindFirstChild("HumanoidRootPart")
					if tr then destPos = tr.Position; isPathingToTarget = true end
				elseif (role == "SAFE FARMER" or role == "SAFE FEEDER") then
					if inRing() then
						local target = getClosestPlayerInRing()
						if target and target.Character then
							local tr = target.Character:FindFirstChild("HumanoidRootPart")
							if tr then destPos = tr.Position; isPathingToTarget = true end
						end
					else
						local distToDest = (r.Position - DEST.Position).Magnitude
						if distToDest <= 3.5 then continue end
					end
				end
				
				if (role == "HEALER" or role == "ARREST") and not isPathingToTarget then checkPos = r.Position; timeStuck = 0; continue end
				
				local distMoved = (r.Position * Vector3.new(1,0,1) - checkPos * Vector3.new(1,0,1)).Magnitude
				local distToDest = (r.Position * Vector3.new(1,0,1) - destPos * Vector3.new(1,0,1)).Magnitude
				
				if distToDest > 6 then
					if distMoved < 2 then
						timeStuck += 1
						if timeStuck >= 4 then
							setStatus("stuck! popping noclip and pushing forward...")
							h.Jump = true; isNoclipping = true
							pcall(function() r.CFrame = r.CFrame + (r.CFrame.LookVector * 4) end)
							task.delay(1.5, function() isNoclipping = false end)
							timeStuck = 0; checkPos = r.Position
						end
					else
						timeStuck = 0; checkPos = r.Position
					end
				end
			end
		end
	end
end)

local function equipToolTarget(toolName)
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChild("Humanoid")
	local bp = player:FindFirstChild("Backpack")
	
	local searchName = toolName
	if toolName == "Box" then
		if (bp and bp:FindFirstChild("Arrest")) or (char:FindFirstChild("Arrest")) then searchName = "Arrest" end
	end
	
	if char:FindFirstChild(searchName) then return true, searchName end
	if bp and hum then
		local tool = bp:FindFirstChild(searchName)
		if tool then hum:EquipTool(tool); return true, searchName end
	end
	return false, toolName
end

local function holdInteraction(targetChar, toolName, remoteName, targetPlayer)
	local char = player.Character
	if not char or not targetChar then return false end
	
	local success, actualToolName = equipToolTarget(toolName)
	if success then
		task.wait(0.25)
		local tool = char:FindFirstChild(actualToolName)
		local prompt = nil
		
		for _, obj in pairs(targetChar:GetDescendants()) do
			if obj:IsA("ProximityPrompt") then prompt = obj; break end
		end
		
		local remote = ReplicatedStorage:FindFirstChild("Remote") and ReplicatedStorage.Remote:FindFirstChild(remoteName)
		local startRemote = ReplicatedStorage:FindFirstChild("Remote") and ReplicatedStorage.Remote:FindFirstChild("StartHeal")
		
		local startTime = tick()
		local maxFailSafe = tick() 
		local remoteFired = false
		
		if prompt then prompt.MaxActivationDistance = 25; prompt.RequiresLineOfSight = false; pcall(function() prompt:InputHoldBegin() end) end
		if tool then pcall(function() tool:Activate() end) end

		while isToolReady(actualToolName) and targetChar.Parent and alive() do
			local tr = targetChar:FindFirstChild("HumanoidRootPart")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			
			if not tr or not hrp or (hrp.Position - tr.Position).Magnitude > 20 then break end
			if tick() - maxFailSafe > 8 then break end 
			
			if not remoteFired and (tick() - startTime >= 3) then
				remoteFired = true
				if toolName ~= "Box" and startRemote and targetPlayer then task.spawn(function() pcall(function() startRemote:FireServer(targetPlayer) end) end) end
				if remote and targetPlayer then task.spawn(function() pcall(function() remote:FireServer(targetPlayer) end) end) end
			end
			task.wait(0.1)
		end
		
		if prompt then pcall(function() prompt:InputHoldEnd() end) end
		if tool then pcall(function() tool:Deactivate() end) end
		return true
	end
	return false
end

local function performHealSequence(targetPlayer)
	local char = player.Character
	if not char or not targetPlayer.Character then return end
	aimbotTarget = targetPlayer.Character
	
	if isToolReady("Medical Kit") then holdInteraction(targetPlayer.Character, "Medical Kit", "AttemptHeal", targetPlayer)
	elseif isToolReady("Quick-Fix") then holdInteraction(targetPlayer.Character, "Quick-Fix", "AttemptHeal", targetPlayer)
	else task.wait(0.2) end

	aimbotTarget = nil
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:UnequipTools() end
end

local function performArrestSequence(targetPlayer)
	local c, h = getLatest()
	if not c or not targetPlayer.Character then return end
	aimbotTarget = targetPlayer.Character
	
	if isToolReady("Box") then holdInteraction(targetPlayer.Character, "Box", "Detainment", targetPlayer) end
	aimbotTarget = nil
	if h then h:UnequipTools() end
end

task.spawn(function()
	while not dead do
		task.wait(0.1) 
		pcall(function()
			if running then
				if not alive() then
					setStatus("waiting to respawn...")
					currentWaypoints = {}; lastComputedTargetPos = nil; currentWpIndex = 1
					drawWaypoints({}) 
					task.wait(1.5) 
					return 
				end

				if role == "FARMER" then
					local distToDest = 999
					local c, h, r = getLatest()
					if r then distToDest = (r.Position - DEST.Position).Magnitude end
					
					if inRing() then
						if #currentWaypoints > 0 then currentWaypoints = {}; lastComputedTargetPos = nil; currentWpIndex = 1 end
						setStatus("in ring — idling")
					elseif distToDest <= 3.5 then
						if #currentWaypoints > 0 then currentWaypoints = {}; lastComputedTargetPos = nil; currentWpIndex = 1 end
						setStatus("at destination — waiting")
					else setStatus("walking to safe zone...") end
				elseif role == "FEEDER" then
					local distToDest = 999
					local c, h, r = getLatest()
					if r then distToDest = (r.Position - DEST.Position).Magnitude end
					
					if inRing() then
						currentWaypoints = {}; lastComputedTargetPos = nil; currentWpIndex = 1
						setStatus("resetting character...")
						if h then h.Health = 0 end
						task.wait(1)
					elseif distToDest <= 3.5 then
						currentWaypoints = {}; lastComputedTargetPos = nil; currentWpIndex = 1
						setStatus("waiting to be farmed...")
					else setStatus("walking to destination...") end
				elseif role == "SAFE FARMER" or role == "SAFE FEEDER" then
					if inRing() then
						local target = getClosestPlayerInRing()
						if target then setStatus("In Ring: Combat Engaged") else setStatus("In Ring: Waiting for Target") end
					else
						local distToDest = 999
						local c, h, r = getLatest()
						if r then distToDest = (r.Position - DEST.Position).Magnitude end
						if distToDest <= 3.5 then setStatus("Staging Area: Waiting...") else setStatus("Walking to Staging Area (-10)...") end
					end
				elseif role == "HEALER" then
					if currentHealTarget and currentHealTarget.Character then
						local tr = currentHealTarget.Character:FindFirstChild("HumanoidRootPart")
						local c, h, r = getLatest()
						if r and tr then
							local dist = (r.Position - tr.Position).Magnitude
							if dist <= 20 then
								if not isInteracting then
									isInteracting = true
									task.spawn(function() pcall(function() performHealSequence(currentHealTarget) end); isInteracting = false end)
								end
								setStatus("Healing: " .. currentHealTarget.DisplayName)
							else setStatus("Chasing: " .. currentHealTarget.DisplayName) end
						end
					else setStatus("looking for hurt players...") end
				elseif role == "ARREST" then
					if currentArrestTarget and currentArrestTarget.Character then
						local tr = currentArrestTarget.Character:FindFirstChild("HumanoidRootPart")
						local c, h, r = getLatest()
						if r and tr then
							local dist = (r.Position - tr.Position).Magnitude
							if dist <= 20 then
								if not isInteracting then
									isInteracting = true
									task.spawn(function() pcall(function() performArrestSequence(currentArrestTarget) end); isInteracting = false end)
								end
								setStatus("Arresting: " .. currentArrestTarget.DisplayName)
							else
								if dist <= 30 and isToolReady("Taser") and not isInteracting then
									task.spawn(function()
										if equipToolTarget("Taser") then
											local taser = c:FindFirstChild("Taser")
											local taserEvent = taser and taser:FindFirstChild("TaserEvent")
											local torso = tr.Parent:FindFirstChild("Torso") or tr.Parent:FindFirstChild("UpperTorso")
											if taserEvent and torso then
												aimbotTarget = tr.Parent
												local startTime = tick()
												while tick() - startTime < 1 and tr.Parent and alive() do
													pcall(function() taserEvent:InvokeServer("Tase", torso) end); task.wait(0.1)
												end
												aimbotTarget = nil
											end
										end
										equipToolTarget("Box")
									end)
								end
								setStatus("Pursuing hostile: " .. currentArrestTarget.DisplayName)
							end
						end
					else setStatus("Scanning for hostiles...") end
				end
			end
		end)
	end
end)

-- ui stuff down below
local mobileMode = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local tweenFast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local tweenSmooth = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local WHITELIST = {}
local whitelistButtons = {}
local activeNotifications = {}

local DETECTION_CHECK_DELAY = 0.15
local DETECTION_RANGE = 60
local DETECTION_CFRAME = CFrame.new(4.31565142, 255.272766, -627.21637)
local detectionEnabled = true
local detectedPlayers = {}
local lastCheck = 0
local detectionPosition = DETECTION_CFRAME.Position
local notificationHolder

local function tweenObject(obj, info, props)
	local tween = TweenService:Create(obj, info, props)
	tween:Play()
	return tween
end

local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function makeGradient(parent, rotation)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 0
	g.Parent = parent
	return g
end

local function createGlow(parent, size, pos, transparency, rotation)
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = pos
	glow.Size = size
	glow.BackgroundTransparency = transparency
	glow.BorderSizePixel = 0
	glow.Parent = parent
	makeCorner(glow, 999)

	local grad = makeGradient(glow, rotation)
	grad.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 1)
	}
	return glow, grad
end

local function isWhitelisted(targetPlayer)
	if not targetPlayer then return false end
	return WHITELIST[targetPlayer.Name] == true
end

local function notify(titleText, bodyText)
	if not notificationHolder then return end

	local notif = Instance.new("Frame")
	notif.Parent = notificationHolder
	notif.Size = UDim2.new(1, 0, 0, 0)
	notif.BackgroundTransparency = 1
	notif.BorderSizePixel = 0
	notif.ClipsDescendants = true
	makeCorner(notif, 12)

	local notifGradient = makeGradient(notif, 135)
	local notifStroke = Instance.new("UIStroke")
	notifStroke.Parent = notif
	notifStroke.Thickness = 1
	notifStroke.Transparency = 1

	local accentBar = Instance.new("Frame")
	accentBar.Parent = notif
	accentBar.Size = UDim2.new(0, 4, 1, 0)
	accentBar.BorderSizePixel = 0
	accentBar.BackgroundTransparency = 1
	makeCorner(accentBar, 12)

	local notifTitle = Instance.new("TextLabel")
	notifTitle.Parent = notif
	notifTitle.BackgroundTransparency = 1
	notifTitle.Position = UDim2.new(0, 14, 0, 8)
	notifTitle.Size = UDim2.new(1, -22, 0, 18)
	notifTitle.Font = Enum.Font.GothamBold
	notifTitle.TextSize = 14
	notifTitle.TextXAlignment = Enum.TextXAlignment.Left
	notifTitle.TextTransparency = 1
	notifTitle.Text = tostring(titleText)

	local notifBody = Instance.new("TextLabel")
	notifBody.Parent = notif
	notifBody.BackgroundTransparency = 1
	notifBody.Position = UDim2.new(0, 14, 0, 26)
	notifBody.Size = UDim2.new(1, -22, 0, 30)
	notifBody.Font = Enum.Font.Gotham
	notifBody.TextSize = 12
	notifBody.TextWrapped = true
	notifBody.TextXAlignment = Enum.TextXAlignment.Left
	notifBody.TextYAlignment = Enum.TextYAlignment.Top
	notifBody.TextTransparency = 1
	notifBody.Text = tostring(bodyText)

	notifGradient.Color = currentTheme.Button
	notifStroke.Color = currentTheme.Stroke
	accentBar.BackgroundColor3 = currentTheme.Accent
	notifTitle.TextColor3 = currentTheme.Text
	notifBody.TextColor3 = currentTheme.SubText

	table.insert(activeNotifications, {
		Frame = notif, Gradient = notifGradient, Stroke = notifStroke,
		Accent = accentBar, Title = notifTitle, Body = notifBody
	})

	tweenObject(notif, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 0})
	tweenObject(notifStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0})
	tweenObject(accentBar, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
	tweenObject(notifTitle, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0})
	tweenObject(notifBody, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0})

	task.delay(2.4, function()
		if notif and notif.Parent then
			tweenObject(notifTitle, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
			tweenObject(notifBody, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
			tweenObject(notifStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1})
			tweenObject(accentBar, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})

			local closeTween = tweenObject(notif, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1})
			closeTween.Completed:Connect(function()
				for i, data in ipairs(activeNotifications) do
					if data.Frame == notif then table.remove(activeNotifications, i); break end
				end
				notif:Destroy()
			end)
		end
	end)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AsylumHubGUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999999999 
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.Parent = playerGui

_G.AsylumFarmKill = function()
	dead = true
	running = false
	role = nil
	aimbotTarget = nil
	
	if getgenv().MyESPLoop then task.cancel(getgenv().MyESPLoop) end
	if getgenv().MyBypassLoop then task.cancel(getgenv().MyBypassLoop) end
	if getgenv().MyStaminaLoop then task.cancel(getgenv().MyStaminaLoop) end
	if getgenv().MyAutoGenLoop then task.cancel(getgenv().MyAutoGenLoop) end 
	if getgenv().MyDoorHoldConnection then getgenv().MyDoorHoldConnection:Disconnect() end 
	if getgenv().NoclipConnection then getgenv().NoclipConnection:Disconnect() end
	destroyVirtualPlatform()
	
	if targetHighlight then targetHighlight:Destroy() end
	if screenGui and screenGui.Parent then screenGui:Destroy() end
	_G.AsylumFarmKill = nil
end

notificationHolder = Instance.new("Frame")
notificationHolder.Name = "NotificationHolder"
notificationHolder.Parent = screenGui
notificationHolder.AnchorPoint = Vector2.new(1, 0)
notificationHolder.Position = UDim2.new(1, -16, 0, 16)
notificationHolder.Size = UDim2.new(0, 280, 1, -32)
notificationHolder.BackgroundTransparency = 1

local notifLayout = Instance.new("UIListLayout")
notifLayout.Parent = notificationHolder
notifLayout.Padding = UDim.new(0, 8)
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.VerticalAlignment = Enum.VerticalAlignment.Top

local glowHolder = Instance.new("Frame")
glowHolder.Name = "GlowHolder"
glowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
glowHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
glowHolder.Size = UDim2.new(0, 640, 0, 400)
glowHolder.BackgroundTransparency = 1
glowHolder.Parent = screenGui

local glow1, glow1Gradient = createGlow(glowHolder, UDim2.new(0, 180, 0, 180), UDim2.new(0.25, 0, 0.28, 0), 0.86, 45)
local glow2, glow2Gradient = createGlow(glowHolder, UDim2.new(0, 220, 0, 220), UDim2.new(0.76, 0, 0.72, 0), 0.9, 120)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.Size = mobileMode and UDim2.new(0, 480, 0, 320) or UDim2.new(0, 600, 0, 360)
mainFrame.ClipsDescendants = true
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
makeCorner(mainFrame, 18)

local mainGradient = makeGradient(mainFrame, 135)

local glassOverlay = Instance.new("Frame")
glassOverlay.Size = UDim2.new(1, 0, 0.45, 0)
glassOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
glassOverlay.BorderSizePixel = 0
glassOverlay.ZIndex = 0 
glassOverlay.Parent = mainFrame
makeCorner(glassOverlay, 18)
local glassOverlayGradient = makeGradient(glassOverlay, 90)
glassOverlayGradient.Transparency = NumberSequence.new{
	NumberSequenceKeypoint.new(0, 0.92),
	NumberSequenceKeypoint.new(1, 1)
}

local mainStroke = Instance.new("UIStroke")
mainStroke.Thickness = 1.3
mainStroke.Parent = mainFrame

local innerLight = Instance.new("Frame")
innerLight.BackgroundTransparency = 1
innerLight.Size = UDim2.new(1, -2, 1, -2)
innerLight.Position = UDim2.new(0, 1, 0, 1)
innerLight.BorderSizePixel = 0
innerLight.Parent = mainFrame
makeCorner(innerLight, 17)

local innerGradient = makeGradient(innerLight, 90)
innerGradient.Transparency = NumberSequence.new{
	NumberSequenceKeypoint.new(0, 0.72),
	NumberSequenceKeypoint.new(0.45, 0.9),
	NumberSequenceKeypoint.new(1, 1)
}

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Parent = mainFrame
titleBar.Size = UDim2.new(1, 0, 0, 48)
titleBar.BorderSizePixel = 0
makeCorner(titleBar, 18)

local titleFix = Instance.new("Frame")
titleFix.Parent = titleBar
titleFix.BorderSizePixel = 0
titleFix.Size = UDim2.new(1, 0, 0, 18)
titleFix.Position = UDim2.new(0, 0, 1, -18)
local topGradient = makeGradient(titleBar, 0)

local title = Instance.new("TextLabel")
title.Parent = titleBar
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 14, 0, 11)
title.Size = UDim2.new(1, -120, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Syntax Hub"

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Parent = screenGui
toggleButton.Size = mobileMode and UDim2.new(0, 130, 0, 50) or UDim2.new(0, 120, 0, 44)
toggleButton.Position = UDim2.new(0, 20, 0.5, -22)
toggleButton.BorderSizePixel = 0
toggleButton.Text = "Syntax"
toggleButton.TextSize = 15
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.AutoButtonColor = false
makeCorner(toggleButton, 12)

local toggleGradient = makeGradient(toggleButton, 135)
local toggleStroke = Instance.new("UIStroke")
toggleStroke.Thickness = 1.1
toggleStroke.Parent = toggleButton

local sidebar = Instance.new("Frame")
sidebar.Parent = mainFrame
sidebar.BorderSizePixel = 0
sidebar.Position = UDim2.new(0, 10, 0, 62)
sidebar.Size = mobileMode and UDim2.new(0, 145, 1, -72) or UDim2.new(0, 150, 1, -72)
makeCorner(sidebar, 14)

local sidebarGradient = makeGradient(sidebar, 135)
local sidebarStroke = Instance.new("UIStroke")
sidebarStroke.Thickness = 1
sidebarStroke.Parent = sidebar

local sidebarPadding = Instance.new("UIPadding")
sidebarPadding.Parent = sidebar
sidebarPadding.PaddingTop = UDim.new(0, 10)
sidebarPadding.PaddingLeft = UDim.new(0, 10)
sidebarPadding.PaddingRight = UDim.new(0, 10)

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.Parent = sidebar
sidebarLayout.Padding = UDim.new(0, 8)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder

local contentFrame = Instance.new("Frame")
contentFrame.Parent = mainFrame
contentFrame.BorderSizePixel = 0
contentFrame.Position = mobileMode and UDim2.new(0, 163, 0, 62) or UDim2.new(0, 170, 0, 62)
contentFrame.Size = mobileMode and UDim2.new(1, -173, 1, -72) or UDim2.new(1, -180, 1, -72)
makeCorner(contentFrame, 14)

local contentGradient = makeGradient(contentFrame, 135)
local contentStroke = Instance.new("UIStroke")
contentStroke.Thickness = 1
contentStroke.Parent = contentFrame

local pageTitle = Instance.new("TextLabel")
pageTitle.Parent = contentFrame
pageTitle.BackgroundTransparency = 1
pageTitle.Position = UDim2.new(0, 14, 0, 17)
pageTitle.Size = UDim2.new(1, -28, 0, 26)
pageTitle.Font = Enum.Font.GothamBold
pageTitle.TextSize = 18
pageTitle.TextXAlignment = Enum.TextXAlignment.Left
pageTitle.Text = ""

local titleUnderline = Instance.new("Frame")
titleUnderline.Parent = contentFrame
titleUnderline.Size = UDim2.new(0, 32, 0, 3)
titleUnderline.Position = UDim2.new(0, 14, 0, 42)
titleUnderline.BorderSizePixel = 0
makeCorner(titleUnderline, 2)

local pagesHolder = Instance.new("Frame")
pagesHolder.Parent = contentFrame
pagesHolder.BackgroundTransparency = 1
pagesHolder.Position = UDim2.new(0, 12, 0, 64)
pagesHolder.Size = UDim2.new(1, -24, 1, -76)

local page1 = Instance.new("Frame")
page1.Name = "Page1"
page1.Parent = pagesHolder
page1.Size = UDim2.new(1, 0, 1, 0)
page1.BackgroundTransparency = 1

local farmerBtn = Instance.new("TextButton")
farmerBtn.Parent = page1
farmerBtn.Size = UDim2.new(0, 120, 0, 42)
farmerBtn.Position = UDim2.new(0, 10, 0, 10)
farmerBtn.Font = Enum.Font.GothamBold
farmerBtn.TextSize = 13
farmerBtn.Text = "FARMER"
farmerBtn.AutoButtonColor = false
makeCorner(farmerBtn, 8)
local farmerGrad = makeGradient(farmerBtn, 135)
local farmerStroke = Instance.new("UIStroke", farmerBtn)
farmerStroke.Thickness = 1

local feederBtn = Instance.new("TextButton")
feederBtn.Parent = page1
feederBtn.Size = UDim2.new(0, 120, 0, 42)
feederBtn.Position = UDim2.new(0, 140, 0, 10)
feederBtn.Font = Enum.Font.GothamBold
feederBtn.TextSize = 13
feederBtn.Text = "FEEDER"
feederBtn.AutoButtonColor = false
makeCorner(feederBtn, 8)
local feederGrad = makeGradient(feederBtn, 135)
local feederStroke = Instance.new("UIStroke", feederBtn)
feederStroke.Thickness = 1

local healerBtn = Instance.new("TextButton")
healerBtn.Parent = page1
healerBtn.Size = UDim2.new(0, 120, 0, 42)
healerBtn.Position = UDim2.new(0, 10, 0, 60)
healerBtn.Font = Enum.Font.GothamBold
healerBtn.TextSize = 13
healerBtn.Text = "HEALER"
healerBtn.AutoButtonColor = false
makeCorner(healerBtn, 8)
local healerGrad = makeGradient(healerBtn, 135)
local healerStroke = Instance.new("UIStroke", healerBtn)
healerStroke.Thickness = 1

local arrestBtn = Instance.new("TextButton")
arrestBtn.Parent = page1
arrestBtn.Size = UDim2.new(0, 120, 0, 42)
arrestBtn.Position = UDim2.new(0, 140, 0, 60)
arrestBtn.Font = Enum.Font.GothamBold
arrestBtn.TextSize = 13
arrestBtn.Text = "ARREST"
arrestBtn.AutoButtonColor = false
makeCorner(arrestBtn, 8)
local arrestGrad = makeGradient(arrestBtn, 135)
local arrestStroke = Instance.new("UIStroke", arrestBtn)
arrestStroke.Thickness = 1

local safeFarmerBtn = Instance.new("TextButton")
safeFarmerBtn.Parent = page1
safeFarmerBtn.Size = UDim2.new(0, 120, 0, 42)
safeFarmerBtn.Position = UDim2.new(0, 10, 0, 110)
safeFarmerBtn.Font = Enum.Font.GothamBold
safeFarmerBtn.TextSize = 13
safeFarmerBtn.Text = "SAFE FARMER"
safeFarmerBtn.AutoButtonColor = false
makeCorner(safeFarmerBtn, 8)
local safeFarmerGrad = makeGradient(safeFarmerBtn, 135)
local safeFarmerStroke = Instance.new("UIStroke", safeFarmerBtn)
safeFarmerStroke.Thickness = 1

local safeFeederBtn = Instance.new("TextButton")
safeFeederBtn.Parent = page1
safeFeederBtn.Size = UDim2.new(0, 120, 0, 42)
safeFeederBtn.Position = UDim2.new(0, 140, 0, 110)
safeFeederBtn.Font = Enum.Font.GothamBold
safeFeederBtn.TextSize = 13
safeFeederBtn.Text = "SAFE FEEDER"
safeFeederBtn.AutoButtonColor = false
makeCorner(safeFeederBtn, 8)
local safeFeederGrad = makeGradient(safeFeederBtn, 135)
local safeFeederStroke = Instance.new("UIStroke", safeFeederBtn)
safeFeederStroke.Thickness = 1

local statusLbl = Instance.new("TextLabel")
statusLbl.Parent = page1
statusLbl.BackgroundTransparency = 1
statusLbl.Position = UDim2.new(0, 12, 0, 160) 
statusLbl.Size = UDim2.new(1, -20, 0, 20)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 13
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = "Status: idle"

-- THE NEW PUZZLE AUTO SOLVER PAGE
local puzzlesPage = Instance.new("Frame")
puzzlesPage.Name = "PuzzlesPage"
puzzlesPage.Parent = pagesHolder
puzzlesPage.Size = UDim2.new(1, 0, 1, 0)
puzzlesPage.BackgroundTransparency = 1
puzzlesPage.Visible = false

local autoGenBtn = Instance.new("TextButton")
autoGenBtn.Parent = puzzlesPage
autoGenBtn.Size = UDim2.new(0, 120, 0, 42)
autoGenBtn.Position = UDim2.new(0, 10, 0, 10)
autoGenBtn.Font = Enum.Font.GothamBold
autoGenBtn.TextSize = 12
autoGenBtn.Text = "AUTO GEN"
autoGenBtn.AutoButtonColor = false
makeCorner(autoGenBtn, 8)
local autoGenGrad = makeGradient(autoGenBtn, 135)
local autoGenStroke = Instance.new("UIStroke", autoGenBtn)
autoGenStroke.Thickness = 1

local autoBatteryBtn = Instance.new("TextButton")
autoBatteryBtn.Parent = puzzlesPage
autoBatteryBtn.Size = UDim2.new(0, 120, 0, 42)
autoBatteryBtn.Position = UDim2.new(0, 140, 0, 10)
autoBatteryBtn.Font = Enum.Font.GothamBold
autoBatteryBtn.TextSize = 12
autoBatteryBtn.Text = "AUTO BATTERY"
autoBatteryBtn.AutoButtonColor = false
makeCorner(autoBatteryBtn, 8)
local autoBatteryGrad = makeGradient(autoBatteryBtn, 135)
local autoBatteryStroke = Instance.new("UIStroke", autoBatteryBtn)
autoBatteryStroke.Thickness = 1


local GREEN_ACTIVE = Color3.fromRGB(38, 155, 65)

updateFarmBtns = function()
	farmerGrad.Color = currentTheme.Button
	feederGrad.Color = currentTheme.Button
	healerGrad.Color = currentTheme.Button
	arrestGrad.Color = currentTheme.Button
	safeFarmerGrad.Color = currentTheme.Button
	safeFeederGrad.Color = currentTheme.Button
	
	autoGenGrad.Color = currentTheme.Button
	autoBatteryGrad.Color = currentTheme.Button
	
	farmerBtn.Text = "FARMER"
	feederBtn.Text = "FEEDER"
	healerBtn.Text = "HEALER"
	arrestBtn.Text = "ARREST"
	safeFarmerBtn.Text = "SAFE FARMER"
	safeFeederBtn.Text = "SAFE FEEDER"
	autoGenBtn.Text = "AUTO GEN"
	autoBatteryBtn.Text = "AUTO BATTERY"

	if running then
		if role == "FARMER" then 
			farmerGrad.Color = ColorSequence.new(GREEN_ACTIVE)
			farmerBtn.Text = "FARMER ●"
		elseif role == "FEEDER" then 
			feederGrad.Color = ColorSequence.new(GREEN_ACTIVE)
			feederBtn.Text = "FEEDER ●"
		elseif role == "HEALER" then 
			healerGrad.Color = ColorSequence.new(GREEN_ACTIVE)
			healerBtn.Text = "HEALER ●"
		elseif role == "ARREST" then 
			arrestGrad.Color = ColorSequence.new(GREEN_ACTIVE)
			arrestBtn.Text = "ARRESTING ●" 
		elseif role == "SAFE FARMER" then 
			safeFarmerGrad.Color = ColorSequence.new(GREEN_ACTIVE)
			safeFarmerBtn.Text = "SAFE FARMER ●"
		elseif role == "SAFE FEEDER" then 
			safeFeederGrad.Color = ColorSequence.new(GREEN_ACTIVE)
			safeFeederBtn.Text = "SAFE FEEDER ●"
		end
	end
	
	if getgenv().AutoGenEnabled then
	    autoGenGrad.Color = ColorSequence.new(GREEN_ACTIVE)
	    autoGenBtn.Text = "AUTO GEN ●"
	end
	if getgenv().AutoBatteryEnabled then
	    autoBatteryGrad.Color = ColorSequence.new(GREEN_ACTIVE)
	    autoBatteryBtn.Text = "AUTO BATTERY ●"
	end
end

setStatus = function(txt) if statusLbl then statusLbl.Text = "Status: " .. txt end end

local function resetBotState()
	running = false; role = nil; targetHighlight.Adornee = nil; isInteracting = false
	currentWaypoints = {}; lastComputedTargetPos = nil; currentWpIndex = 1
	aimbotTarget = nil
	drawWaypoints({}) 
	setStatus("Idle")
end

farmerBtn.MouseButton1Click:Connect(function()
	if role == "FARMER" and running then resetBotState() else role = "FARMER"; running = true; setStatus("Initializing...") end
	updateFarmBtns()
end)

feederBtn.MouseButton1Click:Connect(function()
	if role == "FEEDER" and running then resetBotState() else role = "FEEDER"; running = true; setStatus("Initializing...") end
	updateFarmBtns()
end)

healerBtn.MouseButton1Click:Connect(function()
	if role == "HEALER" and running then resetBotState() else role = "HEALER"; running = true; setStatus("Initializing Auto-Heal..."); removeDoors() end
	updateFarmBtns()
end)

arrestBtn.MouseButton1Click:Connect(function()
	if role == "ARREST" and running then resetBotState() else role = "ARREST"; running = true; setStatus("Initializing Arrest..."); removeDoors() end
	updateFarmBtns()
end)

safeFarmerBtn.MouseButton1Click:Connect(function()
	if role == "SAFE FARMER" and running then resetBotState() else role = "SAFE FARMER"; running = true; setStatus("Initializing Safe Farm...") end
	updateFarmBtns()
end)

safeFeederBtn.MouseButton1Click:Connect(function()
	if role == "SAFE FEEDER" and running then resetBotState() else role = "SAFE FEEDER"; running = true; setStatus("Initializing Safe Feed...") end
	updateFarmBtns()
end)

-- The New Puzzle Actions
autoGenBtn.MouseButton1Click:Connect(function()
    getgenv().AutoGenEnabled = not getgenv().AutoGenEnabled
    updateFarmBtns()
    if not getgenv().AutoGenEnabled and not getgenv().AutoBatteryEnabled then
        cleanup()
    end
end)

autoBatteryBtn.MouseButton1Click:Connect(function()
    getgenv().AutoBatteryEnabled = not getgenv().AutoBatteryEnabled
    updateFarmBtns()
    if not getgenv().AutoGenEnabled and not getgenv().AutoBatteryEnabled then
        cleanup()
    end
end)

local whitelistPage = Instance.new("Frame")
whitelistPage.Name = "WhitelistPage"
whitelistPage.Parent = pagesHolder
whitelistPage.Size = UDim2.new(1, 0, 1, 0)
whitelistPage.BackgroundTransparency = 1
whitelistPage.Visible = false

local searchBox = Instance.new("TextBox")
searchBox.Parent = whitelistPage
searchBox.Size = UDim2.new(1, 0, 0, 40)
searchBox.Position = UDim2.new(0, 0, 0, 0)
searchBox.ClearTextOnFocus = false
searchBox.PlaceholderText = "Search server players..."
searchBox.Text = ""
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 14
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.BorderSizePixel = 0
makeCorner(searchBox, 12)

local searchPadding = Instance.new("UIPadding")
searchPadding.Parent = searchBox
searchPadding.PaddingLeft = UDim.new(0, 12)
searchPadding.PaddingRight = UDim.new(0, 12)

local searchGradient = makeGradient(searchBox, 135)
local searchStroke = Instance.new("UIStroke")
searchStroke.Thickness = 1
searchStroke.Parent = searchBox

local whitelistListHolder = Instance.new("Frame")
whitelistListHolder.Parent = whitelistPage
whitelistListHolder.Position = UDim2.new(0, 0, 0, 48)
whitelistListHolder.Size = UDim2.new(1, 0, 1, -48)
whitelistListHolder.BorderSizePixel = 0
makeCorner(whitelistListHolder, 12)

local whitelistListGradient = makeGradient(whitelistListHolder, 135)
local whitelistListStroke = Instance.new("UIStroke")
whitelistListStroke.Thickness = 1
whitelistListStroke.Parent = whitelistListHolder

local whitelistScroll = Instance.new("ScrollingFrame")
whitelistScroll.Parent = whitelistListHolder
whitelistScroll.BackgroundTransparency = 1
whitelistScroll.BorderSizePixel = 0
whitelistScroll.Position = UDim2.new(0, 6, 0, 6)
whitelistScroll.Size = UDim2.new(1, -12, 1, -12)
whitelistScroll.ScrollBarThickness = 4
whitelistScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
whitelistScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local whitelistLayout = Instance.new("UIListLayout")
whitelistLayout.Parent = whitelistScroll
whitelistLayout.Padding = UDim.new(0, 6)
whitelistLayout.SortOrder = Enum.SortOrder.LayoutOrder

local themePage = Instance.new("Frame")
themePage.Name = "ThemePage"
themePage.Parent = pagesHolder
themePage.Size = UDim2.new(1, 0, 1, 0)
themePage.BackgroundTransparency = 1
themePage.Visible = false

local themeScroll = Instance.new("ScrollingFrame")
themeScroll.Parent = themePage
themeScroll.Position = UDim2.new(0, 0, 0, 0)
themeScroll.Size = UDim2.new(1, 0, 1, -100)
themeScroll.BackgroundTransparency = 1
themeScroll.BorderSizePixel = 0
themeScroll.ScrollBarThickness = 4
themeScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
themeScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local themeGrid = Instance.new("UIGridLayout")
themeGrid.Parent = themeScroll
themeGrid.CellPadding = UDim2.new(0, 8, 0, 8)
themeGrid.CellSize = UDim2.new(0.5, -4, 0, 34) 
themeGrid.SortOrder = Enum.SortOrder.LayoutOrder

local sliderContainer = Instance.new("Frame")
sliderContainer.Parent = themePage
sliderContainer.Position = UDim2.new(0, 0, 1, -90)
sliderContainer.Size = UDim2.new(1, 0, 0, 44)
sliderContainer.BorderSizePixel = 0
makeCorner(sliderContainer, 12)
local sliderGradient = makeGradient(sliderContainer, 135)
local sliderStroke = Instance.new("UIStroke")
sliderStroke.Thickness = 1
sliderStroke.Parent = sliderContainer

local sliderTitle = Instance.new("TextLabel")
sliderTitle.Parent = sliderContainer
sliderTitle.BackgroundTransparency = 1
sliderTitle.Position = UDim2.new(0, 10, 0, 4)
sliderTitle.Size = UDim2.new(1, -20, 0, 16)
sliderTitle.Font = Enum.Font.GothamMedium
sliderTitle.TextSize = 13
sliderTitle.TextXAlignment = Enum.TextXAlignment.Left
sliderTitle.Text = "Transparency: 0%"

local sliderTrack = Instance.new("Frame")
sliderTrack.Parent = sliderContainer
sliderTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 50) 
sliderTrack.BorderSizePixel = 0
sliderTrack.Position = UDim2.new(0, 10, 0, 26)
sliderTrack.Size = UDim2.new(1, -20, 0, 6)
makeCorner(sliderTrack, 3)

local sliderFill = Instance.new("Frame")
sliderFill.Parent = sliderTrack
sliderFill.BorderSizePixel = 0
sliderFill.Size = UDim2.new(0, 0, 1, 0)
makeCorner(sliderFill, 3)

local sliderKnob = Instance.new("TextButton")
sliderKnob.Parent = sliderTrack
sliderKnob.Text = ""
sliderKnob.AutoButtonColor = false
sliderKnob.BorderSizePixel = 0
sliderKnob.Size = UDim2.new(0, 14, 0, 14)
sliderKnob.Position = UDim2.new(0, -7, 0.5, -7)
makeCorner(sliderKnob, 7)

local preview = Instance.new("Frame")
preview.Parent = themePage
preview.Position = UDim2.new(0, 0, 1, -38)
preview.Size = UDim2.new(1, 0, 0, 38)
preview.BorderSizePixel = 0
makeCorner(preview, 12)

local previewGradient = makeGradient(preview, 135)
local previewStroke = Instance.new("UIStroke")
previewStroke.Thickness = 1.1
previewStroke.Parent = preview

local previewLabel = Instance.new("TextLabel")
previewLabel.Parent = preview
previewLabel.BackgroundTransparency = 1
previewLabel.Position = UDim2.new(0, 10, 0, 0)
previewLabel.Size = UDim2.new(1, -20, 1, 0)
previewLabel.Font = Enum.Font.GothamMedium
previewLabel.TextSize = 14
previewLabel.TextXAlignment = Enum.TextXAlignment.Left
previewLabel.Text = "Current Theme: Dark"

local categoryButtons = {}
local themeButtons = {}

local categories = {
	{Name = "Home", Page = page1, Title = "Home"},
	{Name = "Puzzles", Page = puzzlesPage, Title = "Puzzle Auto-Solver"},
	{Name = "Whitelist", Page = whitelistPage, Title = "Whitelist"},
	{Name = "Settings", Page = themePage, Title = "Settings"}
}

local function applyGlobalTransparency(val)
	val = math.clamp(val, 0, 100)
	local alpha = val / 100
	
	sliderTitle.Text = "Transparency: " .. math.floor(val) .. "%"
	sliderFill.Size = UDim2.new(alpha, 0, 1, 0)
	sliderKnob.Position = UDim2.new(alpha, -7, 0.5, -7)

	local function setTrans(inst)
		if inst:IsA("GuiObject") then
			if inst:GetAttribute("OrigBg") == nil then inst:SetAttribute("OrigBg", inst.BackgroundTransparency) end
			inst.BackgroundTransparency = inst:GetAttribute("OrigBg") + ((1 - inst:GetAttribute("OrigBg")) * (alpha * 0.90))
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			if inst:GetAttribute("OrigTxt") == nil then inst:SetAttribute("OrigTxt", inst.TextTransparency) end
			inst.TextTransparency = inst:GetAttribute("OrigTxt") + ((1 - inst:GetAttribute("OrigTxt")) * (alpha * 0.2))
		end
		if inst:IsA("UIStroke") then
			if inst:GetAttribute("OrigStr") == nil then inst:SetAttribute("OrigStr", inst.Transparency) end
			inst.Transparency = inst:GetAttribute("OrigStr") + ((1 - inst:GetAttribute("OrigStr")) * (alpha * 0.4))
		end
	end

	setTrans(mainFrame)
	for _, child in ipairs(mainFrame:GetDescendants()) do setTrans(child) end
end

local draggingSlider = false
sliderKnob.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingSlider = true end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingSlider = false end
end)
UserInputService.InputChanged:Connect(function(input)
	if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local relativeX = math.clamp(input.Position.X - sliderTrack.AbsolutePosition.X, 0, sliderTrack.AbsoluteSize.X)
		local percentage = relativeX / sliderTrack.AbsoluteSize.X
		applyGlobalTransparency(percentage * 100)
	end
end)

local function createCategoryButton(data, index)
	local button = Instance.new("TextButton")
	button.Parent = sidebar; button.Size = UDim2.new(1, 0, 0, 40); button.BorderSizePixel = 0; button.Text = ""; button.AutoButtonColor = false; button.LayoutOrder = index
	makeCorner(button, 12)
	local gradient = makeGradient(button, 135); local stroke = Instance.new("UIStroke"); stroke.Thickness = 1; stroke.Parent = button
	local indicator = Instance.new("Frame"); indicator.Size = UDim2.new(0, 0, 0, 18); indicator.Position = UDim2.new(0, 4, 0.5, -9); indicator.BorderSizePixel = 0; indicator.Parent = button; makeCorner(indicator, 4)
	local label = Instance.new("TextLabel"); label.Parent = button; label.BackgroundTransparency = 1; label.Position = UDim2.new(0, 14, 0, 12); label.Size = UDim2.new(1, -20, 0, 16); label.Font = Enum.Font.GothamBold; label.TextSize = 13; label.TextXAlignment = Enum.TextXAlignment.Left; label.Text = data.Name
	categoryButtons[index] = {Button = button, Gradient = gradient, Stroke = stroke, Label = label, Indicator = indicator}
	return button
end

local function createThemeButton(themeName)
	local themeData = Themes[themeName]
	local button = Instance.new("TextButton"); button.Name = themeName .. "Button"; button.Text = themeName; button.Font = Enum.Font.GothamSemibold; button.TextSize = 13; button.AutoButtonColor = false; button.BorderSizePixel = 0; button.TextXAlignment = Enum.TextXAlignment.Left; button.Parent = themeScroll
	makeCorner(button, 10)
	local padding = Instance.new("UIPadding"); padding.PaddingLeft = UDim.new(0, 36); padding.Parent = button
	local colorTint = Instance.new("Frame"); colorTint.Size = UDim2.new(1, 0, 1, 0); colorTint.BackgroundColor3 = themeData.Accent; colorTint.BackgroundTransparency = 0.88; colorTint.BorderSizePixel = 0; colorTint.Parent = button; makeCorner(colorTint, 10)
	local dot = Instance.new("Frame"); dot.Size = UDim2.new(0, 12, 0, 12); dot.Position = UDim2.new(0, -23, 0.5, -6); dot.BackgroundColor3 = themeData.Main.Keypoints[#themeData.Main.Keypoints].Value; dot.BorderSizePixel = 0; dot.Parent = button; makeCorner(dot, 6)
	local dotUIStroke = Instance.new("UIStroke"); dotUIStroke.Color = themeData.Accent; dotUIStroke.Thickness = 1.5; dotUIStroke.Parent = dot
	local gradient = makeGradient(button, 135); local stroke = Instance.new("UIStroke"); stroke.Thickness = 1; stroke.Parent = button
	themeButtons[themeName] = {Button = button, Gradient = gradient, Stroke = stroke, Padding = padding, DotStroke = dotUIStroke, Tint = colorTint}
	return button
end

for i, data in ipairs(categories) do createCategoryButton(data, i) end
for themeName in pairs(Themes) do createThemeButton(themeName) end

local function refreshWhitelistCanvas() task.defer(function() whitelistScroll.CanvasSize = UDim2.new(0, 0, 0, whitelistLayout.AbsoluteContentSize.Y + 8) end) end

local function matchesSearch(targetPlayer, query)
	if query == "" then return true end
	local loweredQuery = string.lower(query)
	return string.find(string.lower(targetPlayer.Name), loweredQuery, 1, true) ~= nil or string.find(string.lower(targetPlayer.DisplayName), loweredQuery, 1, true) ~= nil
end

local function updateWhitelistButtonTheme(button, whitelisted, stroke)
	if whitelisted then
		button.BackgroundColor3 = currentTheme.Accent; button.TextColor3 = Color3.fromRGB(255, 255, 255); stroke.Color = currentTheme.Accent2
	else
		button.BackgroundColor3 = currentTheme.Button.Keypoints[1].Value; button.TextColor3 = currentTheme.Text; stroke.Color = currentTheme.Stroke
	end
end

local function refreshPlayerList()
	for _, child in ipairs(whitelistScroll:GetChildren()) do if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end end
	table.clear(whitelistButtons)

	local query = string.gsub(searchBox.Text or "", "^%s*(.-)%s*$", "%1")
	local layoutOrder = 0

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player and matchesSearch(targetPlayer, query) then
			layoutOrder += 1
			local button = Instance.new("TextButton"); button.Parent = whitelistScroll; button.Size = UDim2.new(1, 0, 0, 42); button.BorderSizePixel = 0; button.AutoButtonColor = false; button.LayoutOrder = layoutOrder; button.Font = Enum.Font.GothamBold; button.TextSize = 13; makeCorner(button, 10)
			local stroke = Instance.new("UIStroke"); stroke.Parent = button; stroke.Thickness = 1

			local function updateButton()
				local stateText = isWhitelisted(targetPlayer) and "WHITELISTED" or "DETECT"
				button.Text = targetPlayer.Name .. "  |  " .. targetPlayer.DisplayName .. "  |  " .. stateText
				updateWhitelistButtonTheme(button, isWhitelisted(targetPlayer), stroke)
			end
			updateButton()

			button.MouseEnter:Connect(function() if not isWhitelisted(targetPlayer) then tweenObject(button, tweenFast, {BackgroundColor3 = currentTheme.ButtonHover.Keypoints[1].Value}) end end)
			button.MouseLeave:Connect(function() updateButton() end)
			button.MouseButton1Click:Connect(function()
				if isWhitelisted(targetPlayer) then
					WHITELIST[targetPlayer.Name] = nil; detectedPlayers[targetPlayer] = nil; notify("Whitelist", targetPlayer.Name .. " removed from whitelist")
				else
					WHITELIST[targetPlayer.Name] = true; detectedPlayers[targetPlayer] = nil; notify("Whitelist", targetPlayer.Name .. " added to whitelist")
				end
				updateButton()
			end)
			whitelistButtons[targetPlayer] = {Button = button, Update = updateButton}
		end
	end

	if layoutOrder == 0 then
		local emptyLabel = Instance.new("TextLabel"); emptyLabel.Parent = whitelistScroll; emptyLabel.BackgroundTransparency = 1; emptyLabel.Size = UDim2.new(1, 0, 0, 40); emptyLabel.LayoutOrder = 1; emptyLabel.Font = Enum.Font.Gotham; emptyLabel.TextSize = 13; emptyLabel.Text = "No matching players found"; emptyLabel.TextColor3 = currentTheme.SubText
	end
	refreshWhitelistCanvas()
end

whitelistLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshWhitelistCanvas)
searchBox:GetPropertyChangedSignal("Text"):Connect(refreshPlayerList)
Players.PlayerAdded:Connect(function() task.wait(0.15); refreshPlayerList() end)
Players.PlayerRemoving:Connect(function(targetPlayer) detectedPlayers[targetPlayer] = nil; WHITELIST[targetPlayer.Name] = nil; task.wait(0.15); refreshPlayerList() end)

local selectedCategory = 1
local function setCategoryVisual(index, hovering)
	local data = categoryButtons[index]
	if not data then return end
	if selectedCategory == index then
		data.Gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, currentTheme.Accent), ColorSequenceKeypoint.new(1, currentTheme.Accent2)}
		data.Stroke.Color = currentTheme.Accent2; data.Label.TextColor3 = Color3.fromRGB(255, 255, 255); data.Indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tweenObject(data.Indicator, tweenFast, {Size = UDim2.new(0, 4, 0, 18)}); tweenObject(data.Label, tweenFast, {Position = UDim2.new(0, 18, 0, 12)})
	else
		data.Gradient.Color = hovering and currentTheme.ButtonHover or currentTheme.Button; data.Stroke.Color = currentTheme.Stroke; data.Label.TextColor3 = currentTheme.Text
		tweenObject(data.Indicator, tweenFast, {Size = UDim2.new(0, 0, 0, 18)}); tweenObject(data.Label, tweenFast, {Position = UDim2.new(0, 14, 0, 12)})
	end
end

local function setThemeButtonVisual(selectedThemeName, buttonName, hovering)
	local selectedThemeData = Themes[selectedThemeName]; local btnData = themeButtons[buttonName]
	if not btnData then return end
	if selectedThemeName == buttonName then
		btnData.Gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, selectedThemeData.Accent), ColorSequenceKeypoint.new(1, selectedThemeData.Accent2)}
		btnData.Stroke.Color = selectedThemeData.Accent2; btnData.Button.TextColor3 = Color3.fromRGB(255, 255, 255); btnData.DotStroke.Color = Color3.fromRGB(255, 255, 255); btnData.Tint.BackgroundTransparency = 0.5 
	else
		btnData.Gradient.Color = hovering and selectedThemeData.ButtonHover or selectedThemeData.Button; btnData.Stroke.Color = selectedThemeData.Stroke; btnData.Button.TextColor3 = selectedThemeData.Text; btnData.DotStroke.Color = Themes[buttonName].Accent; btnData.Tint.BackgroundTransparency = 0.88 
	end
end

local function switchCategory(index)
	selectedCategory = index
	for i, data in ipairs(categories) do data.Page.Visible = (i == index); setCategoryVisual(i, false) end
	pageTitle.Text = categories[index].Title; RunService.RenderStepped:Wait()
	local titleWidth = pageTitle.TextBounds.X; titleUnderline.Size = UDim2.new(0, 0, 0, 3)
	tweenObject(titleUnderline, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0, titleWidth, 0, 3)})
end

local function applyTheme(themeName)
	local theme = Themes[themeName]
	if not theme then return end

	currentThemeName = themeName; currentTheme = theme
	mainGradient.Color = theme.Main; topGradient.Color = theme.Topbar; titleFix.BackgroundColor3 = theme.Topbar.Keypoints[#theme.Topbar.Keypoints].Value; sidebarGradient.Color = theme.Main; contentGradient.Color = theme.Main; mainStroke.Color = theme.Stroke; sidebarStroke.Color = theme.Stroke; contentStroke.Color = theme.Stroke; toggleGradient.Color = theme.Button; toggleStroke.Color = theme.Stroke; searchGradient.Color = theme.Button; searchStroke.Color = theme.Stroke; whitelistListGradient.Color = theme.Main; whitelistListStroke.Color = theme.Stroke; titleUnderline.BackgroundColor3 = theme.Accent; innerGradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, theme.Accent2), ColorSequenceKeypoint.new(1, theme.Accent)}
	title.TextColor3 = theme.Text; pageTitle.TextColor3 = theme.Text; searchBox.TextColor3 = theme.Text; searchBox.PlaceholderColor3 = theme.SubText; previewLabel.TextColor3 = theme.Text; toggleButton.TextColor3 = theme.Text; sliderGradient.Color = theme.Topbar; sliderStroke.Color = theme.Stroke; sliderTitle.TextColor3 = theme.Text; sliderFill.BackgroundColor3 = theme.Accent; sliderKnob.BackgroundColor3 = theme.Text
	
	if role ~= "FARMER" then farmerGrad.Color = theme.Button end
	if role ~= "FEEDER" then feederGrad.Color = theme.Button end
	if role ~= "HEALER" then healerGrad.Color = theme.Button end
	if role ~= "ARREST" then arrestGrad.Color = theme.Button end
	if role ~= "SAFE FARMER" then safeFarmerGrad.Color = theme.Button end
	if role ~= "SAFE FEEDER" then safeFeederGrad.Color = theme.Button end
	
	if not getgenv().AutoGenEnabled then autoGenGrad.Color = theme.Button end
	if not getgenv().AutoBatteryEnabled then autoBatteryGrad.Color = theme.Button end
	
	farmerStroke.Color = theme.Stroke; feederStroke.Color = theme.Stroke; healerStroke.Color = theme.Stroke; arrestStroke.Color = theme.Stroke; safeFarmerStroke.Color = theme.Stroke; safeFeederStroke.Color = theme.Stroke;
	autoGenStroke.Color = theme.Stroke; autoBatteryStroke.Color = theme.Stroke
	
	farmerBtn.TextColor3 = theme.Text; feederBtn.TextColor3 = theme.Text; healerBtn.TextColor3 = theme.Text; arrestBtn.TextColor3 = theme.Text; safeFarmerBtn.TextColor3 = theme.Text; safeFeederBtn.TextColor3 = theme.Text;
	autoGenBtn.TextColor3 = theme.Text; autoBatteryBtn.TextColor3 = theme.Text
	
	statusLbl.TextColor3 = theme.SubText
	
	previewGradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, theme.Accent), ColorSequenceKeypoint.new(1, theme.Accent2)}; previewStroke.Color = theme.Accent2; previewLabel.Text = "Current Theme: " .. themeName
	glow1Gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, theme.Glow), ColorSequenceKeypoint.new(1, theme.Accent2)}; glow2Gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, theme.Accent), ColorSequenceKeypoint.new(1, theme.Glow)}; glow1.BackgroundColor3 = theme.Glow; glow2.BackgroundColor3 = theme.Accent

	for i = 1, #categories do setCategoryVisual(i, false) end
	for name in pairs(themeButtons) do setThemeButtonVisual(themeName, name, false) end
	for _, notifData in ipairs(activeNotifications) do
		if notifData.Frame and notifData.Frame.Parent then notifData.Gradient.Color = theme.Button; notifData.Stroke.Color = theme.Stroke; notifData.Accent.BackgroundColor3 = theme.Accent; notifData.Title.TextColor3 = theme.Text; notifData.Body.TextColor3 = theme.SubText end
	end
	for _, data in pairs(whitelistButtons) do if data.Update then data.Update() end end
	
	if visualsFolder then 
		for _, part in ipairs(visualsFolder:GetChildren()) do 
			if part:IsA("BasePart") and part.Color ~= Color3.fromRGB(255, 100, 100) then part.Color = theme.Accent end 
		end 
	end
	if targetHighlight then targetHighlight.FillColor = theme.Accent end
	
	refreshPlayerList()
	local percentage = (math.clamp(tonumber(string.match(sliderTitle.Text, "%d+")) or 0, 0, 100)) / 100
	applyGlobalTransparency(percentage * 100)
end

for i, data in ipairs(categoryButtons) do
	data.Button.MouseEnter:Connect(function() setCategoryVisual(i, true) end); data.Button.MouseLeave:Connect(function() setCategoryVisual(i, false) end); data.Button.MouseButton1Click:Connect(function() switchCategory(i) end)
end
for name, data in pairs(themeButtons) do
	data.Button.MouseEnter:Connect(function() setThemeButtonVisual(currentThemeName, name, true); tweenObject(data.Padding, tweenFast, {PaddingLeft = UDim.new(0, 42)}) end)
	data.Button.MouseLeave:Connect(function() setThemeButtonVisual(currentThemeName, name, false); tweenObject(data.Padding, tweenFast, {PaddingLeft = UDim.new(0, 36)}) end)
	data.Button.MouseButton1Click:Connect(function()
		applyTheme(name); local baseSize = mobileMode and UDim2.new(0, 480, 0, 320) or UDim2.new(0, 600, 0, 360)
		tweenObject(mainFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, baseSize.X.Offset + 12, 0, baseSize.Y.Offset + 10)})
		task.delay(0.16, function() tweenObject(mainFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = baseSize}) end)
	end)
end

local isOpen = true; local openSize = mainFrame.Size
local function openGui()
	mainFrame.Visible = true; glowHolder.Visible = true; mainFrame.Size = UDim2.new(0, 0, 0, 0); glow1.BackgroundTransparency = 1; glow2.BackgroundTransparency = 1
	tweenObject(mainFrame, tweenSmooth, {Size = openSize}); tweenObject(glow1, tweenSmooth, {BackgroundTransparency = 0.86}); tweenObject(glow2, tweenSmooth, {BackgroundTransparency = 0.90}); isOpen = true
end
local function closeGui()
	local closeTween = tweenObject(mainFrame, tweenSmooth, {Size = UDim2.new(0, 0, 0, 0)}); tweenObject(glow1, tweenSmooth, {BackgroundTransparency = 1}); tweenObject(glow2, tweenSmooth, {BackgroundTransparency = 1})
	closeTween.Completed:Connect(function() if not isOpen then mainFrame.Visible = false; glowHolder.Visible = false end end); isOpen = false
end

toggleButton.MouseButton1Click:Connect(function()
	local baseSize = mobileMode and UDim2.new(0, 130, 0, 50) or UDim2.new(0, 120, 0, 44)
	tweenObject(toggleButton, tweenFast, {Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset - 4, baseSize.Y.Scale, baseSize.Y.Offset - 4)})
	task.delay(0.08, function() tweenObject(toggleButton, tweenFast, {Size = baseSize}) end)
	if isOpen then closeGui() else openGui() end
end)

local draggingToggle, dragToggleInput, dragToggleStart, toggleStartPos = false, nil, nil, nil
toggleButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingToggle = true; dragToggleStart = input.Position; toggleStartPos = toggleButton.Position; input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then draggingToggle = false end end) end
end)
toggleButton.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragToggleInput = input end end)
UserInputService.InputChanged:Connect(function(input) if draggingToggle and input == dragToggleInput then local delta = input.Position - dragToggleStart; toggleButton.Position = UDim2.new(toggleStartPos.X.Scale, toggleStartPos.X.Offset + delta.X, toggleStartPos.Y.Scale, toggleStartPos.Y.Offset + delta.Y) end end)

local draggingMain, dragMainStart, mainStartPos, mainDragInput = false, nil, nil, nil
titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingMain = true; dragMainStart = input.Position; mainStartPos = mainFrame.Position; input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then draggingMain = false end end) end
end)
titleBar.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then mainDragInput = input end end)
UserInputService.InputChanged:Connect(function(input) if draggingMain and input == mainDragInput then local delta = input.Position - dragMainStart; mainFrame.Position = UDim2.new(mainStartPos.X.Scale, mainStartPos.X.Offset + delta.X, mainStartPos.Y.Scale, mainStartPos.Y.Offset + delta.Y); glowHolder.Position = mainFrame.Position end end)

local function getRaycastParams()
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {}; params.IgnoreWater = true; return params
end
local function playerIsInsideWallAwareArea(otherHRP)
	if not detectionPosition or not otherHRP then return false end
	local origin = detectionPosition + Vector3.new(0, 2, 0); local target = otherHRP.Position + Vector3.new(0, 2, 0); local offset = target - origin; local distance = offset.Magnitude
	if distance > DETECTION_RANGE then return false end
	local result = workspace:Raycast(origin, offset, getRaycastParams())
	if result then local hitInstance = result.Instance; if hitInstance and otherHRP:IsDescendantOf(hitInstance.Parent) then return true end; return false end
	return true
end

task.spawn(function() task.wait(0.35); notify("Detection", "Detection active at fixed location"); notify("Detection", "Range: " .. tostring(DETECTION_RANGE)) end)

RunService.Heartbeat:Connect(function(deltaTime)
	if role == "HEALER" or role == "ARREST" then return end
	if not detectionEnabled or not detectionPosition then return end
	lastCheck += deltaTime; if lastCheck < DETECTION_CHECK_DELAY then return end; lastCheck = 0
	local dangerFound = false
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player then
			if isWhitelisted(targetPlayer) then
				if detectedPlayers[targetPlayer] then detectedPlayers[targetPlayer] = nil end
			else
				local otherCharacter = targetPlayer.Character
				if otherCharacter then
					local otherHRP = otherCharacter:FindFirstChild("HumanoidRootPart"); local otherHumanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
					if otherHRP and otherHumanoid and otherHumanoid.Health > 0 then
						local inside = playerIsInsideWallAwareArea(otherHRP)
						if inside then
							dangerFound = true
							if not detectedPlayers[targetPlayer] then detectedPlayers[targetPlayer] = true; notify("Player Detected", targetPlayer.Name .. " entered! Terminating...") end
						elseif not inside and detectedPlayers[targetPlayer] then detectedPlayers[targetPlayer] = nil; notify("Player Left", targetPlayer.Name .. " left the area") end
					else
						if detectedPlayers[targetPlayer] then detectedPlayers[targetPlayer] = nil end
					end
				else
					if detectedPlayers[targetPlayer] then detectedPlayers[targetPlayer] = nil end
				end
			end
		end
	end
	if dangerFound then
		if running then
			savedRole = role; running = false; isPausedForSafety = true; currentWaypoints = {}; lastComputedTargetPos = nil; currentWpIndex = 1; updateFarmBtns(); setStatus("TERMINATING")
			local c, h = getLatest(); if h then h.Health = 0 end
		end
	else
		if isPausedForSafety and not dangerFound then
			isPausedForSafety = false; notify("Safe", "Area clear. Resuming in 5s...")
			task.delay(5, function() if not isPausedForSafety and savedRole then role = savedRole; running = true; updateFarmBtns(); setStatus("Resumed") end end)
		end
	end
end)

task.spawn(function()
	while screenGui.Parent do
		tweenObject(glow1, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Position = UDim2.new(0.3, 0, 0.32, 0)}); tweenObject(glow2, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Position = UDim2.new(0.7, 0, 0.68, 0)}); task.wait(2.6)
		tweenObject(glow1, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Position = UDim2.new(0.25, 0, 0.26, 0)}); tweenObject(glow2, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Position = UDim2.new(0.76, 0, 0.74, 0)}); task.wait(2.6)
	end
end)

switchCategory(1); refreshPlayerList(); applyTheme("Emerald")

---------------------------------------------------------
-- THE PUZZLE ENGINE (Auto-Gen & Auto-Battery)
---------------------------------------------------------
local function scanForPuzzleTarget(charPos)
    local bestPrompt, bestPos, bestDist, bestObject = nil, nil, math.huge, nil
    local targetType = nil
    
    if getgenv().AutoGenEnabled then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if string.find(string.lower(obj.Name), "generator") and not obj:IsA("Folder") then
                for _, child in ipairs(obj:GetDescendants()) do
                    if child:IsA("ProximityPrompt") and child.Enabled then
                        local p = child.Parent
                        local pPos = nil
                        
                        if p and p:IsA("BasePart") then pPos = p.Position
                        elseif p and p:IsA("Attachment") then pPos = p.WorldPosition
                        elseif obj:IsA("Model") then pPos = obj:GetPivot().Position
                        elseif obj:IsA("BasePart") then pPos = obj.Position end
                        
                        if pPos then
                            local dist = (charPos - pPos).Magnitude
                            if dist < bestDist then
                                bestDist = dist; bestPrompt = child; bestPos = pPos; bestObject = obj; targetType = "Generator"
                            end
                        end
                    end
                end
            end
        end
    end
    
    if not bestPrompt and getgenv().AutoBatteryEnabled then
        local holdingBattery = false
        local c = player.Character
        if c then for _, child in ipairs(c:GetDescendants()) do if string.find(string.lower(child.Name), "battery") then holdingBattery = true break end end end
        
        local matchName = holdingBattery and "FuseBox" or "Battery"
        for _, obj in ipairs(workspace:GetDescendants()) do
            if string.find(string.lower(obj.Name), string.lower(matchName)) and not obj:IsA("Folder") then
                for _, child in ipairs(obj:GetDescendants()) do
                    if child:IsA("ProximityPrompt") and child.Enabled then
                        local p = child.Parent
                        local pPos = nil
                        
                        if p and p:IsA("BasePart") then pPos = p.Position
                        elseif p and p:IsA("Attachment") then pPos = p.WorldPosition
                        elseif obj:IsA("Model") then pPos = obj:GetPivot().Position
                        elseif obj:IsA("BasePart") then pPos = obj.Position end
                        
                        if pPos then
                            local dist = (charPos - pPos).Magnitude
                            if dist < bestDist then
                                bestDist = dist; bestPrompt = child; bestPos = pPos; bestObject = obj; targetType = matchName
                            end
                        end
                    end
                end
            end
        end
    end
    
    return bestPrompt, bestPos, bestObject, targetType
end

local function fireAllPromptsNear(charPos, radius)
    if not fireproximityprompt then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local p = obj.Parent
            local pPos = nil
            
            if p and p:IsA("BasePart") then pPos = p.Position
            elseif p and p:IsA("Attachment") then pPos = p.WorldPosition
            elseif obj.Parent and obj.Parent:IsA("Model") then pPos = obj.Parent:GetPivot().Position
            elseif obj.Parent and obj.Parent:IsA("BasePart") then pPos = obj.Parent.Position end
            
            if pPos and (charPos - pPos).Magnitude <= radius then 
                obj.MaxActivationDistance = 100 
                obj.RequiresLineOfSight = false
                fireproximityprompt(obj)
            end
        end
    end
end

getgenv().MyAutoGenLoop = task.spawn(function()
    local function safeLerp(hrp, hum, startPos, endPos, speed)
        local dist = (startPos - endPos).Magnitude
        if dist < 0.5 then return true end
        local timeToTravel = dist / speed
        local bv = hrp:FindFirstChild("SafeHover") or Instance.new("BodyVelocity")
        bv.Name = "SafeHover"; bv.Velocity = Vector3.zero; bv.MaxForce = Vector3.new(1e5, 1e5, 1e5); bv.Parent = hrp
        hum.PlatformStand = true; hrp.Anchored = false 
        
        local startTime = os.clock(); local connection; local success = true
        connection = RunService.Heartbeat:Connect(function()
            if not (getgenv().AutoGenEnabled or getgenv().AutoBatteryEnabled) or hum.Health <= 0 or not hrp.Parent then
                success = false; connection:Disconnect(); return
            end
            local alpha = math.clamp((os.clock() - startTime) / timeToTravel, 0, 1)
            hrp.CFrame = CFrame.new(startPos:Lerp(endPos, alpha)); hrp.Velocity = Vector3.zero 
            if alpha >= 1 then connection:Disconnect() end
        end)
        while connection.Connected do task.wait() end
        if bv then bv:Destroy() end
        return success
    end

    while true do
        task.wait(0.2) 
        pcall(function()
            if getgenv().AutoGenEnabled or getgenv().AutoBatteryEnabled then
                local char = localPlayer.Character
                if not char or not char.Parent then return end 
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChild("Humanoid")
                
                if hrp and hum and hum.Health > 0 then
                    if isInSafeZone(hrp.Position) then cleanup(); getgenv().IsUnderground = false; return end
                    if not getgenv().NoclipConnection then
                        getgenv().NoclipConnection = RunService.Stepped:Connect(function()
                            if player.Character then for _, part in ipairs(player.Character:GetDescendants()) do if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end end end
                        end)
                    end

                    local nearestPrompt, targetPosition, targetObject, targetType = scanForPuzzleTarget(hrp.Position)
                    if not nearestPrompt then cleanup(); return end
                    
                    local surfacePos = targetPosition + Vector3.new(0, 3, 0) 
                    local underPos = targetPosition - Vector3.new(0, 15, 0)
                    local horizontalDistance = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(underPos.X, 0, underPos.Z)).Magnitude
                    
                    if horizontalDistance > 5 then
                        if not getgenv().IsUnderground then
                            safeLerp(hrp, hum, hrp.Position, hrp.Position - Vector3.new(0, 15, 0), 50); getgenv().IsUnderground = true
                        end
                        if not safeLerp(hrp, hum, hrp.Position, Vector3.new(underPos.X, hrp.Position.Y, underPos.Z), 24) then return end
                    end
                    
                    createVirtualPlatform(underPos)
                    getgenv().SafeToBypass = false 
                    
                    hrp.CFrame = CFrame.new(surfacePos); hrp.Anchored = false; hum.PlatformStand = false; hrp.Velocity = Vector3.zero
                    getgenv().IsUnderground = false
                    task.wait(0.3) 
                    
                    local successfullyOpened = false
                    local timeout = 0
                    
                    if targetType == "Generator" then
                        while timeout < 60 do 
                            local genUI = localPlayer:FindFirstChild("PlayerGui") and localPlayer.PlayerGui:FindFirstChild("Gen")
                            if genUI and genUI.Enabled then successfullyOpened = true; break end
                            
                            nearestPrompt.MaxActivationDistance = 100; nearestPrompt.RequiresLineOfSight = false
                            if fireproximityprompt then fireproximityprompt(nearestPrompt) end
                            fireAllPromptsNear(hrp.Position, 50)
                            
                            task.wait(0.05); timeout = timeout + 1
                        end
                    else
                        for _, child in ipairs(targetObject:GetDescendants()) do
                            if child:IsA("ProximityPrompt") and child.Enabled then
                                child.MaxActivationDistance = 100; child.RequiresLineOfSight = false
                                if fireproximityprompt then fireproximityprompt(child) end
                            end
                        end
                        task.wait(0.5) 
                        for _, child in ipairs(targetObject:GetDescendants()) do
                            if child:IsA("ProximityPrompt") and child.Enabled then if fireproximityprompt then fireproximityprompt(child) end end
                        end
                        task.wait(0.5); successfullyOpened = true
                    end
                    
                    if successfullyOpened then
                        hrp.CFrame = CFrame.new(underPos); hrp.Anchored = false; getgenv().IsUnderground = true
                        if targetType == "Generator" then
                            getgenv().SafeToBypass = true 
                            while (getgenv().AutoGenEnabled or getgenv().AutoBatteryEnabled) and hum.Health > 0 do
                                local genUI = localPlayer:FindFirstChild("PlayerGui") and localPlayer.PlayerGui:FindFirstChild("Gen")
                                if not genUI or not genUI.Enabled or not nearestPrompt or not nearestPrompt.Parent or not nearestPrompt.Enabled then break end
                                task.wait(0.1)
                            end
                            getgenv().SafeToBypass = false; task.wait(0.5) 
                        else
                            task.wait(0.5) 
                        end
                    end
                end
            end
        end)
    end
end)

getgenv().MyBypassLoop = task.spawn(function()
    while true do
        task.wait(0.05) 
        pcall(function()
            if getgenv().SafeToBypass then 
                local playerGui = localPlayer:FindFirstChild("PlayerGui")
                if playerGui then
                    local genUI = playerGui:FindFirstChild("Gen")
                    if genUI and genUI.Enabled then
                        local generatorMain = genUI:FindFirstChild("GeneratorMain")
                        local realEvent = generatorMain and generatorMain:FindFirstChild("Event")
                        if realEvent then
                            local payload = {Wires = true, Switches = true, Lever = true}
                            if realEvent:IsA("RemoteEvent") then realEvent:FireServer(payload)
                            elseif realEvent:IsA("BindableEvent") then realEvent:Fire(payload) end
                        end
                    end
                end
            end
        end)
    end
end)

getgenv().MyESPLoop = task.spawn(function()
    while true do
        task.wait(1) 
        pcall(function()
            for _, obj in ipairs(workspace:GetDescendants()) do
                if string.find(obj.Name, "Generator") then
                    local isDone = true 
                    for _, child in ipairs(obj:GetDescendants()) do
                        if child:IsA("ProximityPrompt") and child.Enabled == true then isDone = false break end
                    end
                    if isDone then applyHighlight(obj, "GeneratorHighlight", GENERATOR_DONE) else applyHighlight(obj, "GeneratorHighlight", GENERATOR_NOT_DONE) end
                elseif obj.Name == "Battery" then applyHighlight(obj, "BatteryHighlight", BATTERY_FILL)
                elseif string.find(obj.Name, "FuseBox") then applyHighlight(obj, "FuseBoxHighlight", FUSEBOX_FILL) end
            end
            local killerFolder = workspace:FindFirstChild("KILLER")
            if killerFolder then for _, child in ipairs(killerFolder:GetChildren()) do applyHighlight(child, "KillerHighlight", KILLER_FILL) end end
            for _, p in ipairs(Players:GetPlayers()) do
                if p == localPlayer then continue end 
                local isKiller = false
                for _, child in ipairs(p:GetDescendants()) do if string.find(string.lower(child.Name), "killer") then isKiller = true break end end
                if not isKiller and p.Character then for _, child in ipairs(p.Character:GetDescendants()) do if string.find(string.lower(child.Name), "killer") then isKiller = true break end end end
                if isKiller and p.Character then applyHighlight(p.Character, "KillerHighlight", KILLER_FILL) end
            end
        end)
    end
end)

getgenv().MyStaminaLoop = task.spawn(function()
    while true do
        task.wait(0.1) 
        pcall(function()
            local char = localPlayer.Character
            if char then
                local currentStamina = char:GetAttribute("Stamina")
                if currentStamina and currentStamina < 100 then char:SetAttribute("Stamina", 100) end
            end
        end)
    end
end)
