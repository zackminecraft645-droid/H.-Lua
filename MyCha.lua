local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local noclip = false
local expandOthers = false
local speedBoost = false
local fullbright = false

local otherHitboxSize = 5
local policeHitboxEnabled = false
local civilianHitboxEnabled = false
local policeHitboxSize = 5
local civilianHitboxSize = 5

-- Aimlock variables
local aimlockOthers = false
local aimlockPolice = false
local aimlockCivilians = false
local aimlockConnection = nil
local aimlockSensitivity = 0.02 -- Much smoother movement
local aimlockStickiness = 100 -- Increased stickiness to prevent rapid switching

local customSpeed = 16 -- Default walk speed
local scriptRunning = true

-- Performance optimization variables
local lastAimlockCheck = 0
local aimlockCheckInterval = 0.1 -- Slower update for smoother aimlock (reduced frequency)
local lastHitboxUpdate = 0
local hitboxUpdateInterval = 0.2 -- Update hitboxes every 0.2 seconds
local currentAimlockTarget = nil -- Store current target to prevent rapid switching

-- Health bar management
local healthBarEnabled = false
local healthConnections = {} -- Store connections for cleanup

-- Teleport management
local teleportMenuVisible = false
local selectedTeleportPlayer = nil
local teleportEnabled = false

-- Aimlock function
local function getClosestTarget(targetType)
    local closestDistance = math.huge
    local closestTarget = nil
    
    if targetType == "others" then
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            if targetPlayer ~= player and targetPlayer.Character and targetPlayer.Character:FindFirstChild("Head") then
                local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
                -- Check if player is alive (health > 0)
                if humanoid and humanoid.Health > 0 then
                    local distance = (Camera.CFrame.Position - targetPlayer.Character.Head.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestTarget = targetPlayer.Character.Head
                    end
                end
            end
        end
    end
    
    -- Check for NPCs (police and civilians)
    if targetType == "police" or targetType == "civilians" then
        for _, npc in ipairs(workspace:GetDescendants()) do
            if npc:IsA("Model") and npc:FindFirstChild("Head") and npc:FindFirstChildOfClass("Humanoid") then
                local humanoid = npc:FindFirstChildOfClass("Humanoid")
                -- Check if NPC is alive (health > 0)
                if humanoid and humanoid.Health > 0 then
                    local npcName = npc.Name:lower()
                    local isTargetType = false
                    
                    if targetType == "police" and npcName:find("police") then
                        isTargetType = true
                    elseif targetType == "civilians" and npcName:find("civilian") then
                        isTargetType = true
                    end
                    
                    if isTargetType then
                        local distance = (Camera.CFrame.Position - npc.Head.Position).Magnitude
                        if distance < closestDistance then
                            closestDistance = distance
                            closestTarget = npc.Head
                        end
                    end
                end
            end
        end
    end
    
    return closestTarget
end

-- Fullbright function
local function toggleFullbright()
    local lighting = game:GetService("Lighting")
    if fullbright then
        lighting.Brightness = 2
        lighting.ClockTime = 14
        lighting.FogEnd = 100000
        lighting.GlobalShadows = false
        lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    else
        lighting.Brightness = 1
        lighting.ClockTime = 12
        lighting.FogEnd = 100000
        lighting.GlobalShadows = true
        lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 70)
    end
end

local function isTargetVisible(target)
    if not target then return false end
    
    local rayOrigin = Camera.CFrame.Position
    local rayDirection = (target.Position - rayOrigin).Unit * math.min((target.Position - rayOrigin).Magnitude, 500) -- Limit ray distance
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {player.Character}
    
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    
    -- If no hit or hit is close to target, consider visible
    if not raycastResult then
        return true
    end
    
    local hitDistance = (raycastResult.Position - rayOrigin).Magnitude
    local targetDistance = (target.Position - rayOrigin).Magnitude
    
    return hitDistance >= (targetDistance - 5) -- Allow 5 stud tolerance
end

local function aimAtTarget()
    if not scriptRunning then return end
    
    local newTarget = nil
    
    if aimlockOthers then
        newTarget = getClosestTarget("others")
    elseif aimlockPolice then
        newTarget = getClosestTarget("police")
    elseif aimlockCivilians then
        newTarget = getClosestTarget("civilians")
    end
    
    -- More stable target switching logic
    if currentAimlockTarget and newTarget then
        local currentTargetPos, currentOnScreen = Camera:WorldToViewportPoint(currentAimlockTarget.Position)
        
        if currentOnScreen and isTargetVisible(currentAimlockTarget) then
            local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
            local currentDistance = (Vector2.new(currentTargetPos.X, currentTargetPos.Y) - screenCenter).Magnitude
            
            -- Keep current target if it's reasonably close to center
            if currentDistance < aimlockStickiness then
                newTarget = currentAimlockTarget -- Stick to current target
            end
        end
    end
    
    currentAimlockTarget = newTarget
    
    if currentAimlockTarget then
        -- Check if target is visible and alive
        local targetPos, onScreen = Camera:WorldToViewportPoint(currentAimlockTarget.Position)
        if onScreen and isTargetVisible(currentAimlockTarget) then
            -- Get target's parent to check health
            local targetChar = currentAimlockTarget.Parent
            local humanoid = targetChar:FindFirstChildOfClass("Humanoid")
            
            -- Only aim at alive targets
            if humanoid and humanoid.Health > 0 then
                local targetPosition = currentAimlockTarget.Position
                local cameraPosition = Camera.CFrame.Position
                
                -- Calculate smooth look direction
                local direction = (targetPosition - cameraPosition).Unit
                local targetCFrame = CFrame.lookAt(cameraPosition, cameraPosition + direction)
                
                -- Apply very smooth interpolation to prevent shaking
                Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, aimlockSensitivity)
            else
                -- Clear target if dead
                currentAimlockTarget = nil
            end
        else
            -- Clear target if not visible
            currentAimlockTarget = nil
        end
    end
end

-- Health bar functions
local function removeAllHealthDisplays()
    -- Clean up all existing health displays and connections
    for _, connection in pairs(healthConnections) do
        if connection then
            connection:Disconnect()
        end
    end
    healthConnections = {}
    
    -- Remove all health displays from workspace
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "HealthDisplay" and obj:IsA("BillboardGui") then
            obj:Destroy()
        end
    end
end

local function addHealthDisplay(char)
    if not scriptRunning or not healthBarEnabled then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid and not char:FindFirstChild("HealthDisplay") then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "HealthDisplay"
        billboard.Size = UDim2.new(0, 100, 0, 30)
        billboard.Adornee = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        billboard.AlwaysOnTop = true
        billboard.ResetOnSpawn = false

        local background = Instance.new("Frame")
        background.Size = UDim2.new(1, 0, 0.4, 0)
        background.Position = UDim2.new(0, 0, 0.6, 0)
        background.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        background.BackgroundTransparency = 0.5
        background.Parent = billboard

        local healthBar = Instance.new("Frame")
        healthBar.Size = UDim2.new(1, 0, 1, 0)
        healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        healthBar.BorderSizePixel = 0
        healthBar.Parent = background

        local healthLabel = Instance.new("TextLabel")
        healthLabel.Size = UDim2.new(1, 0, 1, 0)
        healthLabel.BackgroundTransparency = 1
        healthLabel.TextColor3 = Color3.new(1, 1, 1)
        healthLabel.TextScaled = true
        healthLabel.Font = Enum.Font.SourceSansBold
        healthLabel.Parent = background

        local function updateHealth()
            if not scriptRunning or not healthBarEnabled then return end
            local healthPercent = humanoid.Health / humanoid.MaxHealth
            healthBar.Size = UDim2.new(math.clamp(healthPercent, 0, 1), 0, 1, 0)
            healthLabel.Text = math.floor(humanoid.Health) .. " / " .. math.floor(humanoid.MaxHealth)
        end

        local healthConnection = humanoid.HealthChanged:Connect(updateHealth)
        table.insert(healthConnections, healthConnection)
        updateHealth()

        -- Hide if not visible in camera
        local visibilityConnection = RunService.RenderStepped:Connect(function()
            if not scriptRunning or not healthBarEnabled then
                visibilityConnection:Disconnect()
                return
            end
            if billboard.Parent and billboard.Adornee then
                local adorneePos, onScreen = Camera:WorldToViewportPoint(billboard.Adornee.Position)
                billboard.Enabled = onScreen
            else
                billboard.Enabled = false
            end
        end)
        
        table.insert(healthConnections, visibilityConnection)
        billboard.Parent = char
    end
end

local function restartHealthBars()
    if not scriptRunning then return end
    
    -- Remove all existing health displays
    removeAllHealthDisplays()
    
    -- Add health displays to PLAYERS ONLY if enabled
    if healthBarEnabled then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then
                addHealthDisplay(plr.Character)
            end
        end
    end
end

-- GUI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = player:WaitForChild("PlayerGui")
ScreenGui.ResetOnSpawn = false

local MenuFrame = Instance.new("Frame")
MenuFrame.Size = UDim2.new(0, 800, 0, 400) -- Made taller for teleport menu
MenuFrame.Position = UDim2.new(0.5, -400, 0.3, 0)
MenuFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
MenuFrame.BorderSizePixel = 2
MenuFrame.BorderColor3 = Color3.fromRGB(100, 100, 100)
MenuFrame.Visible = true
MenuFrame.Parent = ScreenGui

local function makeButton(text, posX, posY)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 140, 0, 40)
    btn.Position = UDim2.new(0, posX, 0, posY)
    btn.Text = text
    btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.BorderSizePixel = 1
    btn.BorderColor3 = Color3.fromRGB(80, 80, 80)
    btn.Parent = MenuFrame
    return btn
end

-- Close button (kills script)
local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.new(0, 30, 0, 30)
CloseButton.Position = UDim2.new(1, -35, 0, 5)
CloseButton.Text = "X"
CloseButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseButton.TextColor3 = Color3.new(1, 1, 1)
CloseButton.BorderSizePixel = 1
CloseButton.BorderColor3 = Color3.fromRGB(150, 40, 40)
CloseButton.Parent = MenuFrame

-- Top Icon (fixed positioning)
local TopIcon = Instance.new("TextButton")
TopIcon.Size = UDim2.new(0, 80, 0, 40)
TopIcon.Position = UDim2.new(0, 10, 0, 10)
TopIcon.Text = "Menu"
TopIcon.BackgroundColor3 = Color3.fromRGB(50, 50, 200)
TopIcon.TextColor3 = Color3.new(1, 1, 1)
TopIcon.BorderSizePixel = 1
TopIcon.BorderColor3 = Color3.fromRGB(70, 70, 220)
TopIcon.Visible = false
TopIcon.Parent = ScreenGui

-- Close button functionality (kills the script)
CloseButton.MouseButton1Click:Connect(function()
    scriptRunning = false
    removeAllHealthDisplays() -- Clean up health displays
    if aimlockConnection then
        aimlockConnection:Disconnect()
    end
    if playerAddedConnection then
        playerAddedConnection:Disconnect()
    end
    if playerRemovingConnection then
        playerRemovingConnection:Disconnect()
    end
    ScreenGui:Destroy()
    script:Destroy()
end)

TopIcon.MouseButton1Click:Connect(function()
    MenuFrame.Visible = true
    TopIcon.Visible = false
    -- Reset teleport menu state when reopening
    if teleportMenuVisible and teleportEnabled then
        TeleportDropdown.Visible = true
    end
end)

-- Minimize button
local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size = UDim2.new(0, 30, 0, 30)
MinimizeButton.Position = UDim2.new(1, -70, 0, 5)
MinimizeButton.Text = "_"
MinimizeButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
MinimizeButton.TextColor3 = Color3.new(1, 1, 1)
MinimizeButton.BorderSizePixel = 1
MinimizeButton.BorderColor3 = Color3.fromRGB(120, 120, 120)
MinimizeButton.Parent = MenuFrame

MinimizeButton.MouseButton1Click:Connect(function()
    MenuFrame.Visible = false
    TopIcon.Visible = true
    -- Also hide teleport dropdown when minimizing
    if teleportMenuVisible then
        TeleportDropdown.Visible = false
    end
end)

-- Buttons
local NoclipButton = makeButton("Noclip: OFF", 10, 40)
NoclipButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    noclip = not noclip
    NoclipButton.Text = noclip and "Noclip: ON" or "Noclip: OFF"
end)

local ExpandOthersButton = makeButton("Expand Others: OFF", 170, 40)
ExpandOthersButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    expandOthers = not expandOthers
    ExpandOthersButton.Text = expandOthers and "Expand Others: ON" or "Expand Others: OFF"
end)

local SpeedButton = makeButton("Speed: OFF", 330, 40)
SpeedButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    speedBoost = not speedBoost
    SpeedButton.Text = speedBoost and "Speed: ON" or "Speed: OFF"
    if not speedBoost and player.Character then
        player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = 16
    end
end)

local PoliceHitboxButton = makeButton("Police Hitbox: OFF", 490, 40)
PoliceHitboxButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    policeHitboxEnabled = not policeHitboxEnabled
    PoliceHitboxButton.Text = policeHitboxEnabled and "Police Hitbox: ON" or "Police Hitbox: OFF"
end)

local CivilianHitboxButton = makeButton("Civilian Hitbox: OFF", 650, 40)
CivilianHitboxButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    civilianHitboxEnabled = not civilianHitboxEnabled
    CivilianHitboxButton.Text = civilianHitboxEnabled and "Civilian Hitbox: ON" or "Civilian Hitbox: OFF"
end)

local FullbrightButton = makeButton("Fullbright: OFF", 490, 100)
FullbrightButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    fullbright = not fullbright
    FullbrightButton.Text = fullbright and "Fullbright: ON" or "Fullbright: OFF"
    toggleFullbright()
end)

-- Health Bar Button
local HealthBarButton = makeButton("Health Bars: OFF", 650, 100)
HealthBarButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    healthBarEnabled = not healthBarEnabled
    HealthBarButton.Text = healthBarEnabled and "Health Bars: ON" or "Health Bars: OFF"
    restartHealthBars()
end)

-- Restart Health Bars Button
local RestartHealthButton = makeButton("Restart HP Bars", 10, 260)
RestartHealthButton.BackgroundColor3 = Color3.fromRGB(80, 120, 80) -- Green color
RestartHealthButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    restartHealthBars()
end)

-- Teleport Toggle Button
local TeleportToggleButton = makeButton("Teleport: OFF", 330, 260)
TeleportToggleButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100) -- Red when off
TeleportToggleButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    teleportEnabled = not teleportEnabled
    if teleportEnabled then
        TeleportToggleButton.Text = "Teleport: ON"
        TeleportToggleButton.BackgroundColor3 = Color3.fromRGB(100, 200, 100) -- Green when on
        TeleportButton.Visible = true
    else
        TeleportToggleButton.Text = "Teleport: OFF"
        TeleportToggleButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100) -- Red when off
        TeleportButton.Visible = false
        -- Hide dropdown if open
        if teleportMenuVisible then
            TeleportDropdown.Visible = false
            teleportMenuVisible = false
        end
    end
end)

-- Teleport to Player Button
local TeleportButton = makeButton("Select Player to TP", 490, 260)
TeleportButton.BackgroundColor3 = Color3.fromRGB(120, 80, 200) -- Purple color
TeleportButton.Visible = false -- Hidden by default
TeleportButton.MouseButton1Click:Connect(function()
    if not scriptRunning or not teleportEnabled then return end
    teleportMenuVisible = not teleportMenuVisible
    if teleportMenuVisible then
        updateTeleportMenu()
        TeleportDropdown.Visible = true
        TeleportButton.Text = "Close TP Menu"
    else
        TeleportDropdown.Visible = false
        TeleportButton.Text = "Select Player to TP"
    end
end)

-- Toggle GUI Button
local ToggleButton = makeButton("Toggle GUI", 650, 260)
ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 150, 50) -- Gold color
ToggleButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    MenuFrame.Visible = not MenuFrame.Visible
    if not MenuFrame.Visible then
        TopIcon.Visible = true
        -- Also hide teleport dropdown if open
        TeleportDropdown.Visible = false
        teleportMenuVisible = false
        TeleportButton.Text = "Select Player to TP"
    else
        TopIcon.Visible = false
    end
end)

-- Aimlock buttons
local AimlockOthersButton = makeButton("Aimlock Others: OFF", 10, 100)
local AimlockPoliceButton = makeButton("Aimlock Police: OFF", 170, 100)
local AimlockCiviliansButton = makeButton("Aimlock Civilians: OFF", 330, 100)

AimlockOthersButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    aimlockOthers = not aimlockOthers
    if aimlockOthers then
        aimlockPolice = false
        aimlockCivilians = false
        AimlockPoliceButton.Text = "Aimlock Police: OFF"
        AimlockCiviliansButton.Text = "Aimlock Civilians: OFF"
    end
    AimlockOthersButton.Text = aimlockOthers and "Aimlock Others: ON" or "Aimlock Others: OFF"
end)

AimlockPoliceButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    aimlockPolice = not aimlockPolice
    if aimlockPolice then
        aimlockOthers = false
        aimlockCivilians = false
        AimlockOthersButton.Text = "Aimlock Others: OFF"
        AimlockCiviliansButton.Text = "Aimlock Civilians: OFF"
    end
    AimlockPoliceButton.Text = aimlockPolice and "Aimlock Police: ON" or "Aimlock Police: OFF"
end)

AimlockCiviliansButton.MouseButton1Click:Connect(function()
    if not scriptRunning then return end
    aimlockCivilians = not aimlockCivilians
    if aimlockCivilians then
        aimlockOthers = false
        aimlockPolice = false
        AimlockOthersButton.Text = "Aimlock Others: OFF"
        AimlockPoliceButton.Text = "Aimlock Police: OFF"
    end
    AimlockCiviliansButton.Text = aimlockCivilians and "Aimlock Civilians: ON" or "Aimlock Civilians: OFF"
end)

-- Text inputs
local function makeLabelBox(labelText, defaultVal, posX, posY, callback)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 140, 0, 20)
    label.Position = UDim2.new(0, posX, 0, posY)
    label.Text = labelText
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundTransparency = 1
    label.Parent = MenuFrame

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, 140, 0, 30)
    box.Position = UDim2.new(0, posX, 0, posY + 20)
    box.Text = tostring(defaultVal)
    box.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    box.TextColor3 = Color3.new(1, 1, 1)
    box.BorderSizePixel = 1
    box.BorderColor3 = Color3.fromRGB(100, 100, 100)
    box.ClearTextOnFocus = false
    box.Parent = MenuFrame

    box.FocusLost:Connect(function()
        if not scriptRunning then return end
        local val = tonumber(box.Text)
        if val and val > 0 then
            callback(val)
        else
            box.Text = tostring(defaultVal)
        end
    end)
end

makeLabelBox("Civilian Hitbox Size", civilianHitboxSize, 650, 160, function(val)
    civilianHitboxSize = val
end)

makeLabelBox("Others' Hitbox Size", otherHitboxSize, 10, 160, function(val)
    otherHitboxSize = val
end)

makeLabelBox("My Speed", customSpeed, 490, 160, function(val)
    customSpeed = val
    if speedBoost and player.Character then
        player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = customSpeed
    end
end)

makeLabelBox("Police Hitbox Size", policeHitboxSize, 170, 160, function(val)
    policeHitboxSize = val
end)

-- Teleport Dropdown Menu
local TeleportDropdown = Instance.new("ScrollingFrame")
TeleportDropdown.Size = UDim2.new(0, 300, 0, 120)
TeleportDropdown.Position = UDim2.new(0, 490, 0, 310)
TeleportDropdown.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
TeleportDropdown.BorderSizePixel = 2
TeleportDropdown.BorderColor3 = Color3.fromRGB(100, 100, 100)
TeleportDropdown.ScrollBarThickness = 10
TeleportDropdown.Visible = false
TeleportDropdown.CanvasSize = UDim2.new(0, 0, 0, 0)
TeleportDropdown.Parent = MenuFrame

local function updateTeleportMenu()
    if not scriptRunning or not teleportEnabled then return end
    
    -- Clear existing buttons
    for _, child in pairs(TeleportDropdown:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    local yPos = 0
    local buttonHeight = 30
    
    -- Add buttons for each player
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then -- Don't include local player
            local playerButton = Instance.new("TextButton")
            playerButton.Size = UDim2.new(1, -10, 0, buttonHeight)
            playerButton.Position = UDim2.new(0, 5, 0, yPos)
            playerButton.Text = plr.DisplayName .. " (@" .. plr.Name .. ")"
            playerButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
            playerButton.TextColor3 = Color3.new(1, 1, 1)
            playerButton.BorderSizePixel = 1
            playerButton.BorderColor3 = Color3.fromRGB(100, 100, 100)
            playerButton.TextScaled = true
            playerButton.Parent = TeleportDropdown
            
            -- Improved teleport functionality with better positioning
            playerButton.MouseButton1Click:Connect(function()
                if not scriptRunning or not teleportEnabled then return end
                if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    
                    local targetRoot = plr.Character.HumanoidRootPart
                    local myRoot = player.Character.HumanoidRootPart
                    
                    -- Get target position with better height calculation
                    local targetPosition = targetRoot.Position
                    local targetCFrame = targetRoot.CFrame
                    
                    -- Calculate safe position with proper height
                    local raycast = workspace:Raycast(targetPosition + Vector3.new(3, 50, 0), Vector3.new(0, -100, 0))
                    local groundY = raycast and raycast.Position.Y or targetPosition.Y
                    
                    -- Ensure we're at least 5 studs above ground or target
                    local safeY = math.max(groundY + 5, targetPosition.Y + 2)
                    local safePosition = Vector3.new(targetPosition.X + 3, safeY, targetPosition.Z + 3)
                    
                    -- Disable character physics temporarily to prevent glitching
                    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        humanoid.PlatformStand = true
                    end
                    
                    -- Teleport using CFrame for better control
                    myRoot.CFrame = CFrame.new(safePosition, safePosition + targetCFrame.LookVector)
                    
                    -- Wait a moment then re-enable physics
                    spawn(function()
                        wait(0.2)
                        if humanoid then
                            humanoid.PlatformStand = false
                        end
                        
                        -- Final safety check - if still underground, move up
                        wait(0.1)
                        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                            local currentPos = player.Character.HumanoidRootPart.Position
                            if currentPos.Y < groundY then
                                player.Character.HumanoidRootPart.CFrame = CFrame.new(currentPos.X, groundY + 10, currentPos.Z)
                            end
                        end
                    end)
                    
                    -- Close menu and update button text
                    teleportMenuVisible = false
                    TeleportDropdown.Visible = false
                    TeleportButton.Text = "Select Player to TP"
                    
                    -- Visual feedback
                    playerButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
                    spawn(function()
                        wait(0.3)
                        if playerButton and playerButton.Parent then
                            playerButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                        end
                    end)
                end
            end)
            
            yPos = yPos + buttonHeight + 2
        end
    end
    
    -- Update canvas size
    TeleportDropdown.CanvasSize = UDim2.new(0, 0, 0, yPos)
end

-- Main loops
local steppedConnection = RunService.Stepped:Connect(function()
    if not scriptRunning then
        steppedConnection:Disconnect()
        return
    end
    
    if player.Character then
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = not noclip
            end
        end
    end
end)

local renderSteppedConnection = RunService.RenderStepped:Connect(function()
    if not scriptRunning then
        renderSteppedConnection:Disconnect()
        return
    end
    
    local currentTime = tick()
    
    -- Update hitboxes less frequently
    if currentTime - lastHitboxUpdate >= hitboxUpdateInterval then
        lastHitboxUpdate = currentTime
        
        -- Expand other players hitboxes
        if expandOthers then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= player and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                    local root = plr.Character.HumanoidRootPart
                    root.Size = Vector3.new(otherHitboxSize, otherHitboxSize, otherHitboxSize)
                    root.Transparency = 0.7
                    root.BrickColor = BrickColor.new("Bright red")
                end
            end
        end

        -- Police NPC hitbox
        if policeHitboxEnabled then
            for _, npc in ipairs(workspace:GetDescendants()) do
                if npc:IsA("Model") and npc:FindFirstChild("HumanoidRootPart") and npc:FindFirstChildOfClass("Humanoid") then
                    local npcName = npc.Name:lower()
                    if npcName:find("police") then
                        local root = npc.HumanoidRootPart
                        root.Size = Vector3.new(policeHitboxSize, policeHitboxSize, policeHitboxSize)
                        root.Transparency = 0.7
                        root.BrickColor = BrickColor.new("Bright blue")
                    end
                end
            end
        end

        -- Civilian NPC hitbox
        if civilianHitboxEnabled then
            for _, npc in ipairs(workspace:GetDescendants()) do
                if npc:IsA("Model") and npc:FindFirstChild("HumanoidRootPart") and npc:FindFirstChildOfClass("Humanoid") then
                    local npcName = npc.Name:lower()
                    if npcName:find("civilian") then
                        local root = npc.HumanoidRootPart
                        root.Size = Vector3.new(civilianHitboxSize, civilianHitboxSize, civilianHitboxSize)
                        root.Transparency = 0.7
                        root.BrickColor = BrickColor.new("Bright yellow")
                    end
                end
            end
        end
    end

    -- Speed boost (keep this every frame for responsiveness)
    if speedBoost and player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
        player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = customSpeed
    end

    -- Aimlock functionality (less frequent but smoother)
    if currentTime - lastAimlockCheck >= aimlockCheckInterval then
        lastAimlockCheck = currentTime
        if aimlockOthers or aimlockPolice or aimlockCivilians then
            aimAtTarget()
        else
            currentAimlockTarget = nil -- Clear target when aimlock is off
        end
    end
end)

-- Player management for health bars
local playerAddedConnection = Players.PlayerAdded:Connect(function(plr)
    if not scriptRunning then
        playerAddedConnection:Disconnect()
        return
    end
    plr.CharacterAdded:Connect(function(char)
        if healthBarEnabled then
            -- Small delay to ensure character is fully loaded
            wait(0.5)
            addHealthDisplay(char)
        end
    end)
    
    -- Update teleport menu when new player joins
    if teleportMenuVisible and teleportEnabled then
        updateTeleportMenu()
    end
end)

local playerRemovingConnection = Players.PlayerRemoving:Connect(function(plr)
    if not scriptRunning then
        playerRemovingConnection:Disconnect()
        return
    end
    
    -- Update teleport menu when player leaves
    if teleportMenuVisible and teleportEnabled then
        wait(0.1) -- Small delay to ensure player is removed from list
        updateTeleportMenu()
    end
end)

-- Add existing players
for _, plr in ipairs(Players:GetPlayers()) do
    if not scriptRunning then break end
    plr.CharacterAdded:Connect(function(char)
        if healthBarEnabled then
            -- Small delay to ensure character is fully loaded
            wait(0.5)
            addHealthDisplay(char)
        end
    end)
end
