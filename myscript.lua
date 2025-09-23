-- ====== NoClip + WalkSpeed + SpawnPoint + Infinite Jump + Stun Movement ======
local player = game.Players.LocalPlayer
local uis = game:GetService("UserInputService")
local run = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local ts = game:GetService("TweenService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Настройки
local noclipEnabled = false
local infiniteJumpEnabled = false
local walkSpeed = 16
local jumpPower = 50
local floatAcceleration = 1.5
local maxFloatSpeed = 30
local stunnedMovementSpeed = 65
local stunnedAcceleration = 5.0

-- Переменные
local character, hrp, humanoid
local isDragging = false
local dragStart = nil
local startPos = nil
local wasDragging = false
local dragConnection = nil
local activeSlider = nil
local mainFrameStartPos = nil
local savedWalkSpeed = walkSpeed
local lastSpeedCheck = 0
local speedCheckInterval = 0.2
local originalGravity = workspace.Gravity
local lastGroundPosition = nil
local noClipParts = {}

-- Переменные для точки спавна
local spawnPoint = nil
local isDead = false

-- Переменные для бесконечного прыжка
local jumpHeld = false
local noclipConnection = nil
local jumpConnection = nil
local floatVelocity = 0

-- Переменные для движения в оглушении
local isStunned = false
local stunnedVelocity = Vector3.new(0, 0, 0)
local stunnedMovementConnection = nil

-- Функция для проверки клавиш прыжка
local function isJumpKey(keyCode)
    return keyCode == Enum.KeyCode.Space or 
           keyCode == Enum.KeyCode.ButtonA or 
           keyCode == Enum.KeyCode.ButtonL3
end

-- Функция для отображения неярких уведомлений
local function showNotification(text)
    local notificationGui = Instance.new("ScreenGui")
    notificationGui.Name = "NotificationGui"
    notificationGui.Parent = player.PlayerGui
    notificationGui.ResetOnSpawn = false
    notificationGui.IgnoreGuiInset = true
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 50)
    frame.Position = UDim2.new(0.5, -150, 0.85, 0)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = notificationGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Text = text
    label.TextColor3 = Color3.fromRGB(180, 180, 180)
    label.TextScaled = true
    label.Font = Enum.Font.SourceSans
    label.BackgroundTransparency = 1
    label.TextStrokeTransparency = 0.8
    label.Parent = frame
    
    frame.BackgroundTransparency = 0.5
    local fadeIn = ts:Create(frame, TweenInfo.new(0.3), {BackgroundTransparency = 0.2})
    fadeIn:Play()
    
    debris:AddItem(notificationGui, 3)
end

-- Безопасная функция для получения персонажа
local function getCharacter()
    return player.Character
end

-- Улучшенная функция для телепортации на точку спавна
local function teleportToSpawnPoint()
    if not spawnPoint or not character or not hrp then return end
    
    for i = 1, 3 do
        if hrp and hrp:IsDescendantOf(workspace) then
            local randomOffset = Vector3.new(
                math.random(-1, 1),
                0,
                math.random(-1, 1)
            )
            local newPosition = spawnPoint + randomOffset
            hrp.CFrame = CFrame.new(newPosition)
            print("🐉 Телепортация на точку спавна: " .. tostring(newPosition))
            showNotification("Телепортирован на точку спавна")
            return
        end
        wait(0.5)
    end
    print("🐉 Не удалось телепортироваться на точку спавна")
end

-- Функция для безопасного применения скорости
local function applyWalkSpeed()
    if not humanoid or not humanoid:IsDescendantOf(workspace) then return end
    
    if humanoid.WalkSpeed ~= savedWalkSpeed then
        humanoid.WalkSpeed = savedWalkSpeed
    end
    
    if humanoid.WalkSpeed ~= savedWalkSpeed then
        ts:Create(humanoid, TweenInfo.new(0.1), {WalkSpeed = savedWalkSpeed}):Play()
    end
    
    spawn(function()
        wait(0.05)
        if humanoid and humanoid.WalkSpeed ~= savedWalkSpeed then
            humanoid.WalkSpeed = savedWalkSpeed
        end
    end)
end

-- Функция для включения/выключения NoClip
local function toggleNoClip(enabled)
    noclipEnabled = enabled
    
    if enabled then
        noClipParts = {}
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                    table.insert(noClipParts, part)
                end
            end
        end
        
        noclipConnection = run.Heartbeat:Connect(function()
            if character and noclipEnabled then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                        local found = false
                        for _, existingPart in ipairs(noClipParts) do
                            if existingPart == part then
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(noClipParts, part)
                        end
                    end
                end
            end
        end)
    else
        for _, part in ipairs(noClipParts) do
            if part and part:IsDescendantOf(workspace) then
                part.CanCollide = true
            end
        end
        noClipParts = {}
        
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
    end
end

-- Функция для обработки движения в оглушении
local function handleStunnedMovement()
    if not (isStunned and humanoid and hrp and not isDead) then return end
    
    local moveDirection = Vector3.new(0, 0, 0)
    
    local cameraCFrame = workspace.CurrentCamera.CFrame
    local forwardVector = cameraCFrame.LookVector
    local rightVector = cameraCFrame.RightVector
    
    forwardVector = Vector3.new(forwardVector.X, 0, forwardVector.Z).Unit
    rightVector = Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    
    if uis:IsKeyDown(Enum.KeyCode.W) then
        moveDirection = moveDirection + forwardVector
    end
    if uis:IsKeyDown(Enum.KeyCode.S) then
        moveDirection = moveDirection - forwardVector
    end
    if uis:IsKeyDown(Enum.KeyCode.A) then
        moveDirection = moveDirection - rightVector
    end
    if uis:IsKeyDown(Enum.KeyCode.D) then
        moveDirection = moveDirection + rightVector
    end
    
    if uis:IsKeyDown(Enum.KeyCode.Space) then
        moveDirection = moveDirection + Vector3.new(0, 1, 0)
    end
    if uis:IsKeyDown(Enum.KeyCode.LeftShift) or uis:IsKeyDown(Enum.KeyCode.RightShift) then
        moveDirection = moveDirection + Vector3.new(0, -1, 0)
    end
    
    if moveDirection.Magnitude > 0 then
        moveDirection = moveDirection.Unit
        
        stunnedVelocity = stunnedVelocity + (moveDirection * stunnedAcceleration)
        
        if stunnedVelocity.Magnitude > stunnedMovementSpeed then
            stunnedVelocity = stunnedVelocity.Unit * stunnedMovementSpeed
        end
    else
        stunnedVelocity = stunnedVelocity * 0.9
    end
    
    hrp.Velocity = stunnedVelocity
end

-- Функция для обработки бесконечного прыжка
local function handleInfiniteJump()
    if infiniteJumpEnabled and humanoid and hrp and not isDead and not isStunned then
        local currentVelocity = hrp.Velocity
        
        if jumpHeld then
            if humanoid:GetState() == Enum.HumanoidStateType.Running or 
               humanoid:GetState() == Enum.HumanoidStateType.Landed then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                floatVelocity = humanoid.JumpPower
            else
                floatVelocity = math.min(floatVelocity + floatAcceleration, maxFloatSpeed)
            end
        else
            if floatVelocity > 0 then
                floatVelocity = math.max(floatVelocity - floatAcceleration * 1.5, 0)
            else
                floatVelocity = math.max(floatVelocity - floatAcceleration, -maxFloatSpeed/2)
            end
        end
        
        hrp.Velocity = Vector3.new(currentVelocity.X, floatVelocity, currentVelocity.Z)
    end
end

-- Функция для проверки состояния оглушения
local function checkStunnedState()
    if not humanoid then return end
    
    local stunnedStates = {
        Enum.HumanoidStateType.Physics,
        Enum.HumanoidStateType.Ragdoll,
    }
    
    local currentState = humanoid:GetState()
    local wasStunned = isStunned
    
    for _, stunnedState in ipairs(stunnedStates) do
        if currentState == stunnedState then
            isStunned = true
            break
        else
            isStunned = false
        end
    end
    
    if wasStunned ~= isStunned then
        if isStunned then
            stunnedVelocity = hrp.Velocity
            showNotification("Вы оглушены! Используйте WASD и Пробел/Shift для СВЕРХБЫСТРОГО полета.")
            
            if not stunnedMovementConnection then
                stunnedMovementConnection = run.Heartbeat:Connect(handleStunnedMovement)
            end
        else
            showNotification("Вы вышли из состояния оглушения.")
            
            if stunnedMovementConnection then
                stunnedMovementConnection:Disconnect()
                stunnedMovementConnection = nil
            end
            
            stunnedVelocity = Vector3.new(0, 0, 0)
        end
    end
end

-- Функция для инициализации персонажа
local function setupCharacter()
    local success = pcall(function()
        character = getCharacter()
        if character and character:IsDescendantOf(workspace) then
            hrp = character:WaitForChild("HumanoidRootPart", 2)
            humanoid = character:WaitForChild("Humanoid", 2)
            if humanoid then
                applyWalkSpeed()
                
                humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
                    applyWalkSpeed()
                end)
                
                humanoid.StateChanged:Connect(function(oldState, newState)
                    checkStunnedState()
                end)
                
                if hrp then
                    lastGroundPosition = hrp.Position
                end
                
                if noclipEnabled then
                    toggleNoClip(true)
                end
                
                if infiniteJumpEnabled and not jumpConnection then
                    jumpConnection = run.Heartbeat:Connect(handleInfiniteJump)
                end
                
                checkStunnedState()
            end
        end
    end)
    if not success then
        character, hrp, humanoid = nil, nil, nil
    end
end

-- Обработчик появления нового персонажа
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    isDead = false
    
    wait(0.5)
    
    if character and character:IsDescendantOf(workspace) then
        hrp = character:WaitForChild("HumanoidRootPart", 2)
        humanoid = character:WaitForChild("Humanoid", 2)
        
        if humanoid then
            applyWalkSpeed()
            
            humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
                applyWalkSpeed()
            end)
            
            humanoid.StateChanged:Connect(function(oldState, newState)
                checkStunnedState()
            end)
            
            if hrp then
                lastGroundPosition = hrp.Position
            end
            
            humanoid.Died:Connect(function()
                isDead = true
                print("🐉 Игрок умер")
            end)
            
            if noclipEnabled then
                toggleNoClip(true)
            end
            
            if infiniteJumpEnabled and not jumpConnection then
                jumpConnection = run.Heartbeat:Connect(handleInfiniteJump)
            end
            
            checkStunnedState()
        end
        
        if spawnPoint then
            wait(0.2)
            teleportToSpawnPoint()
        end
    end
end)

-- Инициализация при запуске
setupCharacter()

-- Создание GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DragonHubGui"
screenGui.Parent = player:WaitForChild("PlayerGui")
screenGui.ResetOnSpawn = false

-- Стилизованная панелька
local hubPanel = Instance.new("TextButton")
hubPanel.Name = "HubPanel"
hubPanel.Size = UDim2.new(0, 140, 0, 35)
hubPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
hubPanel.Active = true
hubPanel.Draggable = false
hubPanel.Position = UDim2.new(0.5, 80, 0.5, -60)
hubPanel.Parent = screenGui
hubPanel.Text = ""

local hubCorner = Instance.new("UICorner")
hubCorner.CornerRadius = UDim.new(0, 8)
hubCorner.Parent = hubPanel

local hubGradient = Instance.new("UIGradient")
hubGradient.Rotation = 90
hubGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 45, 65)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 35))
})
hubGradient.Parent = hubPanel

local hubLabel = Instance.new("TextLabel")
hubLabel.Size = UDim2.new(1, 0, 1, 0)
hubLabel.Position = UDim2.new(0, 0, 0, 0)
hubLabel.Text = "🐉 Dragon Hub"
hubLabel.BackgroundTransparency = 1
hubLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
hubLabel.TextXAlignment = Enum.TextXAlignment.Center
hubLabel.TextYAlignment = Enum.TextYAlignment.Center
hubLabel.Font = Enum.Font.SourceSansBold
hubLabel.TextSize = 16
hubLabel.TextStrokeTransparency = 0.8
hubLabel.Parent = hubPanel

-- Основной фрейм (уменьшенный без God Mode)
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 250, 0, 230) -- Уменьшили высоту
mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Visible = false
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

local mainGradient = Instance.new("UIGradient")
mainGradient.Rotation = 90
mainGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 20)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
mainGradient.Parent = mainFrame

-- Заголовок с драконом
local titleBackground = Instance.new("Frame")
titleBackground.Size = UDim2.new(1, 0, 0, 40)
titleBackground.Position = UDim2.new(0, 0, 0, 0)
titleBackground.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
titleBackground.BorderSizePixel = 0
titleBackground.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 12)
titleCorner.Parent = titleBackground

local titleGradient = Instance.new("UIGradient")
titleGradient.Rotation = 90
titleGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 50)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 0))
})
titleGradient.Parent = titleBackground

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 0, 30)
titleLabel.Position = UDim2.new(0, 15, 0, 5)
titleLabel.Text = "🐉 DRAGON HUB 🐉"
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextYAlignment = Enum.TextYAlignment.Center
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 18
titleLabel.TextStrokeTransparency = 0.8
titleLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Parent = mainFrame

-- Крестик закрытия
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -35, 0, 5)
closeButton.Text = "×"
closeButton.BackgroundColor3 = Color3.fromRGB(220, 100, 100)
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 24
closeButton.Parent = mainFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeButton

closeButton.MouseEnter:Connect(function()
    ts:Create(closeButton, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(240, 120, 120)}):Play()
end)

closeButton.MouseLeave:Connect(function()
    ts:Create(closeButton, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(220, 100, 100)}):Play()
end)

-- Функция создания кнопок
local function createButton(text, position, icon)
    -- Создаем контейнер для кнопки
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Size = UDim2.new(0, 220, 0, 35)
    buttonContainer.Position = position
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.Parent = mainFrame
    
    -- Создаем фон кнопки
    local buttonBackground = Instance.new("Frame")
    buttonBackground.Size = UDim2.new(1, 0, 1, 0)
    buttonBackground.Position = UDim2.new(0, 0, 0, 0)
    buttonBackground.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    buttonBackground.BorderSizePixel = 0
    buttonBackground.Parent = buttonContainer
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = buttonBackground
    
    -- Создаем рамку для подсветки
    local highlightFrame = Instance.new("Frame")
    highlightFrame.Size = UDim2.new(1, 0, 1, 0)
    highlightFrame.Position = UDim2.new(0, 0, 0, 0)
    highlightFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    highlightFrame.BackgroundTransparency = 1
    highlightFrame.BorderSizePixel = 0
    highlightFrame.ZIndex = 2
    highlightFrame.Parent = buttonContainer
    
    local highlightCorner = Instance.new("UICorner")
    highlightCorner.CornerRadius = UDim.new(0, 8)
    highlightCorner.Parent = highlightFrame
    
    -- Создаем текст кнопки
    local buttonText = Instance.new("TextLabel")
    buttonText.Size = UDim2.new(1, 0, 1, 0)
    buttonText.Position = UDim2.new(0, 0, 0, 0)
    buttonText.Text = icon .. " " .. text
    buttonText.BackgroundTransparency = 1
    buttonText.TextColor3 = Color3.fromRGB(255, 255, 255)
    buttonText.TextXAlignment = Enum.TextXAlignment.Center
    buttonText.TextYAlignment = Enum.TextYAlignment.Center
    buttonText.Font = Enum.Font.SourceSansBold
    buttonText.TextSize = 14
    buttonText.ZIndex = 3
    buttonText.Parent = buttonContainer
    
    -- Создаем невидимую кнопку для обработки кликов
    local clickButton = Instance.new("TextButton")
    clickButton.Size = UDim2.new(1, 0, 1, 0)
    clickButton.Position = UDim2.new(0, 0, 0, 0)
    clickButton.BackgroundTransparency = 1
    clickButton.Text = ""
    clickButton.ZIndex = 4
    clickButton.Parent = buttonContainer
    
    -- Обработчики наведения для подсветки рамки
    clickButton.MouseEnter:Connect(function()
        highlightFrame.BackgroundTransparency = 0.7
    end)
    
    clickButton.MouseLeave:Connect(function()
        highlightFrame.BackgroundTransparency = 1
    end)
    
    return buttonContainer, buttonBackground, buttonText, clickButton
end

-- Создаем кнопки (без God Mode)
local noclipButton, noclipBackground, noclipText, noclipClick = createButton("NoClip: OFF", UDim2.new(0, 15, 0, 50), "🚷")
local infiniteJumpButton, infiniteJumpBackground, infiniteJumpText, infiniteJumpClick = createButton("Infinite Jump: OFF", UDim2.new(0, 15, 0, 90), "🦘")
local setSpawnButton, setSpawnBackground, setSpawnText, setSpawnClick = createButton("Set Spawn Point", UDim2.new(0, 15, 0, 130), "📍")

-- Функция для слайдеров
local function createSlider(name, position, minValue, maxValue, defaultValue)
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 220, 0, 50)
    sliderFrame.Position = position
    sliderFrame.BackgroundTransparency = 1
    sliderFrame.Parent = mainFrame
    
    local sliderLabel = Instance.new("TextLabel")
    sliderLabel.Size = UDim2.new(1, 0, 0, 25)
    sliderLabel.Position = UDim2.new(0, 0, 0, 0)
    sliderLabel.Text = name
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    sliderLabel.TextXAlignment = Enum.TextXAlignment.Left
    sliderLabel.Font = Enum.Font.GothamBold
    sliderLabel.TextSize = 16
    sliderLabel.TextStrokeTransparency = 0.7
    sliderLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    sliderLabel.Parent = sliderFrame
    
    local sliderBackground = Instance.new("Frame")
    sliderBackground.Size = UDim2.new(1, 0, 0, 10)
    sliderBackground.Position = UDim2.new(0, 0, 0, 30)
    sliderBackground.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    sliderBackground.BorderSizePixel = 0
    sliderBackground.Parent = sliderFrame
    
    local sliderCorner = Instance.new("UICorner")
    sliderCorner.CornerRadius = UDim.new(0, 5)
    sliderCorner.Parent = sliderBackground
    
    local sliderFill = Instance.new("Frame")
    sliderFill.Size = UDim2.new((defaultValue - minValue) / (maxValue - minValue), 0, 1, 0)
    sliderFill.Position = UDim2.new(0, 0, 0, 0)
    sliderFill.BackgroundColor3 = Color3.fromRGB(255, 180, 0)
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderBackground
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 5)
    fillCorner.Parent = sliderFill
    
    local fillGradient = Instance.new("UIGradient")
    fillGradient.Rotation = 90
    fillGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 0))
    })
    fillGradient.Parent = sliderFill
    
    local sliderValue = Instance.new("TextLabel")
    sliderValue.Size = UDim2.new(0, 50, 0, 25)
    sliderValue.Position = UDim2.new(1, -50, 0, 0)
    sliderValue.Text = tostring(defaultValue)
    sliderValue.BackgroundTransparency = 1
    sliderValue.TextColor3 = Color3.fromRGB(255, 215, 0)
    sliderValue.TextXAlignment = Enum.TextXAlignment.Right
    sliderValue.Font = Enum.Font.GothamBold
    sliderValue.TextSize = 16
    sliderValue.TextStrokeTransparency = 0.7
    sliderValue.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    sliderValue.Parent = sliderFrame
    
    return sliderFrame, sliderFill, sliderValue, sliderBackground
end

-- Создаем слайдер для WalkSpeed
local walkSpeedSlider, walkSpeedFill, walkSpeedValue, walkSpeedBg = createSlider("Walk Speed:", UDim2.new(0, 15, 0, 170), 16, 200, walkSpeed)

-- Обработчики интерфейса
hubPanel.MouseButton1Click:Connect(function()
    if wasDragging then
        wasDragging = false
        return
    end
    mainFrame.Visible = true
    hubPanel.Visible = false
    mainFrame.Position = UDim2.new(0.5, 100, 0.5, -mainFrame.AbsoluteSize.Y/2)
end)

closeButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
    hubPanel.Visible = true
end)

hubPanel.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isDragging = true
        wasDragging = false
        dragStart = input.Position
        startPos = hubPanel.Position
        
        if mainFrame.Visible then
            mainFrame.Draggable = false
        end
        
        if dragConnection then
            dragConnection:Disconnect()
        end
        
        dragConnection = uis.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement and isDragging then
                local delta = input.Position - dragStart
                hubPanel.Position = UDim2.new(
                    startPos.X.Scale, 
                    startPos.X.Offset + delta.X, 
                    startPos.Y.Scale, 
                    startPos.Y.Offset + delta.Y
                )
                if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 then
                    wasDragging = true
                end
            end
        end)
    end
end)

uis.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and isDragging then
        isDragging = false
        if mainFrame.Visible then
            mainFrame.Draggable = true
        end
        if dragConnection then
            dragConnection:Disconnect()
            dragConnection = nil
        end
    end
end)

-- Обработчики кнопок
noclipClick.MouseButton1Click:Connect(function()
    noclipEnabled = not noclipEnabled
    toggleNoClip(noclipEnabled)
    
    if noclipEnabled then
        noclipText.Text = "🚷 NoClip: ON"
        noclipBackground.BackgroundColor3 = Color3.fromRGB(0, 100, 0) -- Мгновенный темно-зеленый
        showNotification("NoClip активирован! Проходи сквозь стены.")
    else
        noclipText.Text = "🚷 NoClip: OFF"
        noclipBackground.BackgroundColor3 = Color3.fromRGB(80, 80, 80) -- Мгновенный серый
        showNotification("NoClip деактивирован.")
    end
    
    -- Обновляем настройки
    local settings = player:WaitForChild("PlayerGui"):FindFirstChild("DragonHubSettings")
    if settings then
        local noClipValue = settings:FindFirstChild("NoClipEnabled")
        if noClipValue then
            noClipValue.Value = noclipEnabled
        end
    end
end)

infiniteJumpClick.MouseButton1Click:Connect(function()
    infiniteJumpEnabled = not infiniteJumpEnabled
    if infiniteJumpEnabled then
        infiniteJumpText.Text = "🦘 Infinite Jump: ON"
        infiniteJumpBackground.BackgroundColor3 = Color3.fromRGB(0, 100, 0) -- Мгновенный темно-зеленый
        showNotification("Infinite Jump активирован!")
        
        if not jumpConnection then
            jumpConnection = run.Heartbeat:Connect(handleInfiniteJump)
        end
    else
        infiniteJumpText.Text = "🦘 Infinite Jump: OFF"
        infiniteJumpBackground.BackgroundColor3 = Color3.fromRGB(80, 80, 80) -- Мгновенный серый
        showNotification("Infinite Jump деактивирован.")
        
        if jumpConnection then
            jumpConnection:Disconnect()
            jumpConnection = nil
        end
        
        floatVelocity = 0
    end
    
    -- Обновляем настройки
    local settings = player:WaitForChild("PlayerGui"):FindFirstChild("DragonHubSettings")
    if settings then
        local infiniteJumpValue = settings:FindFirstChild("InfiniteJumpEnabled")
        if infiniteJumpValue then
            infiniteJumpValue.Value = infiniteJumpEnabled
        end
    end
end)

setSpawnClick.MouseButton1Click:Connect(function()
    if hrp then
        spawnPoint = hrp.Position
        lastGroundPosition = hrp.Position
        showNotification("Точка спавна установлена")
        print("🐉 Точка спавна установлена: " .. tostring(spawnPoint))
    else
        showNotification("Персонаж не найден")
    end
end)

-- Обработка слайдера
walkSpeedBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        activeSlider = "walkSpeed"
        mainFrameStartPos = mainFrame.Position
        mainFrame.Draggable = false
    end
end)

uis.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and activeSlider then
        if mainFrameStartPos and mainFrame.Position ~= mainFrameStartPos then
            mainFrame.Position = mainFrameStartPos
        end
        
        local mousePos = uis:GetMouseLocation()
        local sliderBg = walkSpeedBg
        local sliderFill = walkSpeedFill
        local sliderValue = walkSpeedValue
        local minValue = 16
        local maxValue = 200
        
        local relativeX = (mousePos.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X
        relativeX = math.clamp(relativeX, 0, 1)
        
        ts:Create(sliderFill, TweenInfo.new(0.1), {Size = UDim2.new(relativeX, 0, 1, 0)}):Play()
        
        local value = math.floor(minValue + relativeX * (maxValue - minValue))
        sliderValue.Text = tostring(value)
        
        walkSpeed = value
        savedWalkSpeed = value
        applyWalkSpeed()
    end
end)

uis.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        activeSlider = nil
        mainFrameStartPos = nil
        mainFrame.Draggable = true
        
        -- Обновляем настройки при изменении скорости
        if activeSlider == "walkSpeed" then
            local settings = player:WaitForChild("PlayerGui"):FindFirstChild("DragonHubSettings")
            if settings then
                local walkSpeedValue = settings:FindFirstChild("WalkSpeed")
                if walkSpeedValue then
                    walkSpeedValue.Value = walkSpeed
                end
            end
        end
    end
end)

-- Отслеживание нажатия клавиш прыжка
uis.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and isJumpKey(input.KeyCode) then
        jumpHeld = true
        
        if infiniteJumpEnabled and humanoid and not isStunned then
            if humanoid:GetState() == Enum.HumanoidStateType.Running or 
               humanoid:GetState() == Enum.HumanoidStateType.Landed then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end
end)

uis.InputEnded:Connect(function(input, gameProcessed)
    if not gameProcessed and isJumpKey(input.KeyCode) then
        jumpHeld = false
    end
end)

-- Функция для проверки нахождения на поверхности
local function isOnSurface()
    if not hrp or not humanoid then return false end
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {character}
    
    local origin = hrp.Position
    local direction = Vector3.new(0, -1, 0)
    local rayLength = humanoid.HipHeight + 0.1
    local rayResult = workspace:Raycast(origin, direction * rayLength, raycastParams)
    
    return rayResult ~= nil
end

-- Функция для безопасного приземления
local function safeLanding()
    if not hrp or not humanoid then return end
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {character}
    
    local origin = hrp.Position
    local direction = Vector3.new(0, -1, 0)
    local rayLength = humanoid.HipHeight + 5
    local rayResult = workspace:Raycast(origin, direction * rayLength, raycastParams)
    
    if rayResult then
        local targetPosition = rayResult.Position + Vector3.new(0, humanoid.HipHeight, 0)
        local lookDirection = hrp.CFrame.LookVector
        hrp.CFrame = CFrame.new(targetPosition, targetPosition + lookDirection)
        
        lastGroundPosition = targetPosition
        return true
    end
    
    return false
end

-- Функция для проверки, не застрял ли персонаж в объекте
local function checkIfStuck()
    if not hrp or not humanoid then return false end
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {character}
    
    local directions = {
        Vector3.new(1, 0, 0),
        Vector3.new(-1, 0, 0),
        Vector3.new(0, 0, 1),
        Vector3.new(0, 0, -1),
        Vector3.new(0, 1, 0),
        Vector3.new(0, -1, 0)
    }
    
    local stuckCount = 0
    for _, dir in pairs(directions) do
        local rayResult = workspace:Raycast(hrp.Position, dir * 3, raycastParams)
        if rayResult then
            stuckCount = stuckCount + 1
        end
    end
    
    return stuckCount >= 4
end

-- Функция для освобождения персонажа из застревания
local function freeFromStuck()
    if not hrp or not humanoid then return end
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {character}
    
    local directions = {
        Vector3.new(1, 0, 0),
        Vector3.new(-1, 0, 0),
        Vector3.new(0, 0, 1),
        Vector3.new(0, 0, -1),
        Vector3.new(0, 1, 0),
        Vector3.new(0, -1, 0)
    }
    
    for _, dir in pairs(directions) do
        local rayResult = workspace:Raycast(hrp.Position, dir * 10, raycastParams)
        if not rayResult then
            local targetPosition = hrp.Position + dir * 5
            hrp.CFrame = CFrame.new(targetPosition, targetPosition + workspace.CurrentCamera.CFrame.LookVector)
            showNotification("Освобожден из застревания")
            return true
        end
    end
    
    if spawnPoint then
        teleportToSpawnPoint()
        return true
    end
    
    return false
end

-- Периодическая проверка на застревание
spawn(function()
    while true do
        wait(2)
        
        if character and humanoid and not isDead then
            if checkIfStuck() then
                freeFromStuck()
            end
        end
    end
end)

-- Система сохранения настроек
local function saveSettings()
    -- Создаем объект для хранения настроек
    local settings = Instance.new("Folder")
    settings.Name = "DragonHubSettings"
    settings.Parent = player:WaitForChild("PlayerGui")
    
    -- Сохраняем настройки
    local walkSpeedValue = Instance.new("NumberValue")
    walkSpeedValue.Name = "WalkSpeed"
    walkSpeedValue.Value = walkSpeed
    walkSpeedValue.Parent = settings
    
    local infiniteJumpValue = Instance.new("BoolValue")
    infiniteJumpValue.Name = "InfiniteJumpEnabled"
    infiniteJumpValue.Value = infiniteJumpEnabled
    infiniteJumpValue.Parent = settings
    
    local noClipValue = Instance.new("BoolValue")
    noClipValue.Name = "NoClipEnabled"
    noClipValue.Value = noclipEnabled
    noClipValue.Parent = settings
end

-- Загрузка настроек при запуске
local function loadSettings()
    local settings = player:WaitForChild("PlayerGui"):FindFirstChild("DragonHubSettings")
    if settings then
        -- Загружаем настройки
        local walkSpeedValue = settings:FindFirstChild("WalkSpeed")
        if walkSpeedValue then
            walkSpeed = walkSpeedValue.Value
            savedWalkSpeed = walkSpeed
            walkSpeedValue.Text = tostring(walkSpeed)
            
            -- Обновляем слайдер
            local minValue = 16
            local maxValue = 200
            local relativeX = (walkSpeed - minValue) / (maxValue - minValue)
            walkSpeedFill.Size = UDim2.new(relativeX, 0, 1, 0)
        end
        
        local infiniteJumpValue = settings:FindFirstChild("InfiniteJumpEnabled")
        if infiniteJumpValue then
            infiniteJumpEnabled = infiniteJumpValue.Value
            if infiniteJumpEnabled then
                infiniteJumpText.Text = "🦘 Infinite Jump: ON"
                infiniteJumpBackground.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
                
                if not jumpConnection then
                    jumpConnection = run.Heartbeat:Connect(handleInfiniteJump)
                end
            end
        end
        
        local noClipValue = settings:FindFirstChild("NoClipEnabled")
        if noClipValue then
            noclipEnabled = noClipValue.Value
            if noclipEnabled then
                noclipText.Text = "🚷 NoClip: ON"
                noclipBackground.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
                toggleNoClip(true)
            end
        end
    else
        -- Если настроек нет, создаем их по умолчанию
        saveSettings()
    end
end

-- Загружаем настройки при запуске
spawn(function()
    wait(1) -- Ждем, чтобы убедиться, что все загружено
    loadSettings()
end)