local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRoot(char)
    char = char or getCharacter()
    return char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(char)
    char = char or getCharacter()
    return char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(model)
    if not model or not model.Parent then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    return hum ~= nil and root ~= nil and hum.Health > 0
end

local runtime = {
    config = {
        AutoFarm = false,
        BringMob = true,
        BringMobCount = 8,
        BringMobRadius = 28,
        BringPullRadius = 350,
        BringPullOffset = 7,
        FastAttack = true,
        AttackCooldown = 0.08,
        TweenSpeed = 280,
        FarmDistance = 8,
        FarmHeight = 14,
        UseNearestMob = true,
        SelectedMob = "",
        SelectedBoss = "",
        TargetBossMode = false,
        SelectedQuest = "",
        ManualQuest = false,
        AutoQuest = false,
        AutoStats = false,
        SelectedStat = "Melee",
        AutoSaber = false,
        AntiFall = true,
    },
    state = {
        lastAttack = 0,
        lastStatTick = 0,
        lastQuestTick = 0,
        lastSaberTick = 0,
        lastBringTick = 0,
        tweenActive = false,
        currentTarget = nil,
        statusText = "Idle",
    },
    pulledMobs = {},
    scanned = {
        Mobs = {},
        Bosses = {},
        Quests = {},
    },
    hooks = {},
}

-- =========================================================
-- 1. LIVE SCANNER (MOB / BOSS / QUEST)
-- =========================================================
local BOSS_KEYWORDS = {
    "boss", "greybeard", "vice admiral", "warden", "magma admiral",
    "diamond", "jeremy", "fajt", "mob leader", "wyvern", "cyborg",
    "smoke admiral", "toga", "gol", "captain", "tide keeper",
    "rip_indra", "dough king", "cake queen", "soul reaper", "darkbeard",
    "indra", "katakuri", "beard", "king", "queen", "admiral"
}

local function looksLikeBoss(name)
    local lower = string.lower(tostring(name or ""))
    for _, kw in ipairs(BOSS_KEYWORDS) do
        if string.find(lower, kw, 1, true) then
            return true
        end
    end
    return false
end

function runtime.scanWorld()
    local mobSet = {}
    local bossSet = {}
    local mobList = {}
    local bossList = {}

    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if enemiesFolder then
        for _, obj in ipairs(enemiesFolder:GetChildren()) do
            if obj:IsA("Model") and obj.Name ~= "" then
                local cleanName = obj.Name
                if looksLikeBoss(cleanName) then
                    if not bossSet[cleanName] then
                        bossSet[cleanName] = true
                        table.insert(bossList, cleanName)
                    end
                else
                    if not mobSet[cleanName] then
                        mobSet[cleanName] = true
                        table.insert(mobList, cleanName)
                    end
                end
            end
        end
    end

    local worldOrigin = Workspace:FindFirstChild("_WorldOrigin")
    local spawnsFolder = worldOrigin and worldOrigin:FindFirstChild("EnemySpawns")
    if spawnsFolder then
        for _, sp in ipairs(spawnsFolder:GetDescendants()) do
            if sp:IsA("BasePart") or sp:IsA("Model") then
                local rawName = tostring(sp.Name or "")
                local cleanName = string.gsub(rawName, "%s*Sp[a-zA-Z]*%d*$", "")
                cleanName = string.gsub(cleanName, "^%s*(.-)%s*$", "%1")
                if cleanName ~= "" and cleanName ~= "EnemySpawns" then
                    if looksLikeBoss(cleanName) then
                        if not bossSet[cleanName] then
                            bossSet[cleanName] = true
                            table.insert(bossList, cleanName)
                        end
                    else
                        if not mobSet[cleanName] then
                            mobSet[cleanName] = true
                            table.insert(mobList, cleanName)
                        end
                    end
                end
            end
        end
    end

    table.sort(mobList)
    table.sort(bossList)

    runtime.scanned.Mobs = mobList
    runtime.scanned.Bosses = bossList

    if runtime.config.SelectedMob == "" and #mobList > 0 then
        runtime.config.SelectedMob = mobList[1]
    end
    if runtime.config.SelectedBoss == "" and #bossList > 0 then
        runtime.config.SelectedBoss = bossList[1]
    end

    return mobList, bossList
end

function runtime.scanQuests()
    local questNames = {}
    local seen = {}

    local function collectFromContainer(container)
        if not container then
            return
        end
        for _, child in ipairs(container:GetDescendants()) do
            if child:IsA("ModuleScript") or child:IsA("Folder") then
                local n = tostring(child.Name or "")
                if n ~= "" and not seen[n] then
                    seen[n] = true
                    table.insert(questNames, n)
                end
            end
        end
    end

    collectFromContainer(ReplicatedStorage:FindFirstChild("Quests"))
    collectFromContainer(ReplicatedStorage:FindFirstChild("QuestData"))

    table.sort(questNames)
    runtime.scanned.Quests = questNames

    if runtime.config.SelectedQuest == "" and #questNames > 0 then
        runtime.config.SelectedQuest = questNames[1]
    end

    return questNames
end

-- =========================================================
-- 2. ANTI-FALL & STABLE TWEEN FLIGHT
-- =========================================================
local activeTween = nil
local tweenProxy = nil

local function ensureTweenProxy()
    if tweenProxy and tweenProxy.Parent then
        return tweenProxy
    end
    local p = Instance.new("Part")
    p.Name = "FarmRuntimeTweenProxy"
    p.Anchored = true
    p.CanCollide = false
    p.Transparency = 1
    p.Size = Vector3.new(2, 2, 2)
    p.Parent = Workspace
    tweenProxy = p
    return p
end

local function holdCharacterPhysics(root, hum)
    if not root or not hum then
        return
    end
    hum.PlatformStand = true
    hum:ChangeState(Enum.HumanoidStateType.Physics)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function releaseCharacterPhysics(root, hum)
    if not root or not hum then
        return
    end
    hum.PlatformStand = false
    if hum:GetState() == Enum.HumanoidStateType.Physics then
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function stopTween()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    runtime.state.tweenActive = false
end

local function tweenTo(targetCFrame, speed)
    local char = getCharacter()
    local root = getRoot(char)
    local hum = getHumanoid(char)
    if not root or not hum or hum.Health <= 0 then
        return false
    end

    speed = math.max(tonumber(speed) or runtime.config.TweenSpeed or 250, 40)
    local dist = (root.Position - targetCFrame.Position).Magnitude
    if dist <= 3.5 then
        holdCharacterPhysics(root, hum)
        root.CFrame = targetCFrame
        return true
    end

    stopTween()
    runtime.state.tweenActive = true

    local proxy = ensureTweenProxy()
    proxy.CFrame = root.CFrame

    local duration = math.clamp(dist / speed, 0.03, 12)
    local info = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    local tween = TweenService:Create(proxy, info, { CFrame = targetCFrame })
    activeTween = tween

    local finished = false
    tween.Completed:Connect(function()
        finished = true
    end)

    tween:Play()

    while not finished do
        if not runtime.config.AutoFarm and runtime.state.statusText ~= "Tweening" then
            tween:Cancel()
            break
        end
        char = getCharacter()
        root = getRoot(char)
        hum = getHumanoid(char)
        if not root or not hum or hum.Health <= 0 then
            tween:Cancel()
            break
        end
        holdCharacterPhysics(root, hum)
        root.CFrame = proxy.CFrame
        RunService.Heartbeat:Wait()
    end

    if activeTween == tween then
        activeTween = nil
    end
    runtime.state.tweenActive = false

    root = getRoot(getCharacter())
    hum = getHumanoid(getCharacter())
    if root and hum and finished then
        holdCharacterPhysics(root, hum)
        root.CFrame = targetCFrame
    end

    return finished
end

local function preventFalling()
    if not runtime.config.AntiFall then
        return
    end
    local char = getCharacter()
    local root = getRoot(char)
    local hum = getHumanoid(char)
    if not root or not hum or hum.Health <= 0 then
        return
    end

    if runtime.state.tweenActive or runtime.config.AutoFarm then
        holdCharacterPhysics(root, hum)
    end

    if root.Position.Y < -280 then
        holdCharacterPhysics(root, hum)
        root.CFrame = CFrame.new(root.Position.X, 60, root.Position.Z)
        runtime.state.statusText = "Recovered Fall"
    end
end

-- =========================================================
-- 3. TARGET FINDER & BRING MOB (STABLE)
-- =========================================================
local function getEnemyRoot(enemyModel)
    if not isAlive(enemyModel) then
        return nil
    end
    return enemyModel:FindFirstChild("HumanoidRootPart")
        or enemyModel:FindFirstChild("Torso")
        or enemyModel:FindFirstChild("UpperTorso")
end

local function findTargetEnemy()
    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if not enemiesFolder then
        return nil
    end

    local root = getRoot()
    local originPos = root and root.Position or Vector3.zero

    local bestModel = nil
    local bestDist = math.huge

    for _, mob in ipairs(enemiesFolder:GetChildren()) do
        local eRoot = getEnemyRoot(mob)
        if eRoot then
            local nameLower = string.lower(mob.Name)
            local matched = false

            if runtime.config.TargetBossMode and runtime.config.SelectedBoss ~= "" then
                local bossLower = string.lower(runtime.config.SelectedBoss)
                if string.find(nameLower, bossLower, 1, true) or looksLikeBoss(mob.Name) then
                    matched = (runtime.config.SelectedBoss == "" or string.find(nameLower, bossLower, 1, true) ~= nil)
                end
            elseif not runtime.config.UseNearestMob and runtime.config.SelectedMob ~= "" then
                local selLower = string.lower(runtime.config.SelectedMob)
                matched = string.find(nameLower, selLower, 1, true) ~= nil
            else
                matched = not looksLikeBoss(mob.Name)
            end

            if matched then
                local d = (eRoot.Position - originPos).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestModel = mob
                end
            end
        end
    end

    -- Fallback ถ้าเลือกชื่อเฉพาะแล้วหาไม่เจอในวินาทีนั้น ให้ดึงตัวใกล้สุดแทน
    if not bestModel and not runtime.config.TargetBossMode then
        for _, mob in ipairs(enemiesFolder:GetChildren()) do
            local eRoot = getEnemyRoot(mob)
            if eRoot then
                local d = (eRoot.Position - originPos).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestModel = mob
                end
            end
        end
    end

    return bestModel
end

local function gatherMobsAroundAnchor(anchorPos, primaryTarget)
    if not runtime.config.BringMob then
        return
    end
    local now = os.clock()
    if now - runtime.state.lastBringTick < 0.22 then
        return
    end
    runtime.state.lastBringTick = now

    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if not enemiesFolder then
        return
    end

    local candidates = {}
    for _, mob in ipairs(enemiesFolder:GetChildren()) do
        local eRoot = getEnemyRoot(mob)
        if eRoot then
            local distToAnchor = (eRoot.Position - anchorPos).Magnitude
            if mob == primaryTarget or distToAnchor <= runtime.config.BringPullRadius then
                table.insert(candidates, {
                    model = mob,
                    root = eRoot,
                    dist = distToAnchor,
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.model == primaryTarget then
            return true
        elseif b.model == primaryTarget then
            return false
        end
        return a.dist < b.dist
    end)

    local maxCount = math.clamp(tonumber(runtime.config.BringMobCount) or 8, 1, 25)
    local pulled = 0
    local pullCenter = Vector3.new(anchorPos.X, anchorPos.Y - runtime.config.FarmHeight, anchorPos.Z)

    for i = 1, math.min(#candidates, maxCount) do
        local item = candidates[i]
        local eRoot = item.root
        if eRoot and eRoot.Parent then
            local angle = (i / math.max(1, math.min(#candidates, maxCount))) * math.pi * 2
            local ringRadius = (i == 1) and 0 or math.min(runtime.config.BringPullOffset, 9)
            local destPos = pullCenter + Vector3.new(
                math.cos(angle) * ringRadius,
                0,
                math.sin(angle) * ringRadius
            )

            pcall(function()
                if sethiddenproperty then
                    sethiddenproperty(LocalPlayer, "SimulationRadius", 1000)
                end
            end)

            pcall(function()
                for _, part in ipairs(item.model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                        part.AssemblyLinearVelocity = Vector3.zero
                        part.AssemblyAngularVelocity = Vector3.zero
                    end
                end
                eRoot.CFrame = CFrame.lookAt(destPos, pullCenter)
                runtime.pulledMobs[item.model] = now
            end)

            pulled += 1
        end
    end

    return pulled
end

-- =========================================================
-- 4. FAST ATTACK & AUTO QUEST / AUTO STATS / AUTO SABER
-- =========================================================
local function equipWeaponIfAny()
    local char = getCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not char or not backpack then
        return
    end
    local hasEquipped = false
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            hasEquipped = true
            break
        end
    end
    if not hasEquipped then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and (tool.ToolTip == "Melee" or tool.ToolTip == "Sword" or string.find(string.lower(tool.Name), "combat") or string.find(string.lower(tool.Name), "blade") or string.find(string.lower(tool.Name), "sword") or string.find(string.lower(tool.Name), "style")) then
                tool.Parent = char
                break
            end
        end
        if not char:FindFirstChildOfClass("Tool") then
            local firstTool = backpack:FindFirstChildOfClass("Tool")
            if firstTool then
                firstTool.Parent = char
            end
        end
    end
end

local function performFastAttack(targetModel)
    if not runtime.config.FastAttack then
        return
    end
    local now = os.clock()
    if now - runtime.state.lastAttack < runtime.config.AttackCooldown then
        return
    end
    runtime.state.lastAttack = now

    equipWeaponIfAny()

    local char = getCharacter()
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function()
            tool:Activate()
        end)
    end

    local eRoot = getEnemyRoot(targetModel)
    if eRoot then
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local commF = remotes and remotes:FindFirstChild("CommF_")
            if commF then
                commF:InvokeServer("Attack")
            end
        end)
    end
end

local function tryTakeSelectedQuest()
    if not runtime.config.AutoQuest or runtime.config.SelectedQuest == "" then
        return
    end
    local now = os.clock()
    if now - runtime.state.lastQuestTick < 3 then
        return
    end
    runtime.state.lastQuestTick = now

    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            commF:InvokeServer("StartQuest", runtime.config.SelectedQuest, 1)
        end
    end)
end

local function tryUpgradeStats()
    if not runtime.config.AutoStats then
        return
    end
    local now = os.clock()
    if now - runtime.state.lastStatTick < 1.2 then
        return
    end
    runtime.state.lastStatTick = now

    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            commF:InvokeServer("AddPoint", runtime.config.SelectedStat, 1)
        end
    end)
end

local function setAutoSaberToggle(state)
    runtime.config.AutoSaber = not not state
end

local function tryAutoSaber()
    if not runtime.config.AutoSaber then
        return
    end
    local now = os.clock()
    if now - runtime.state.lastSaberTick < 4 then
        return
    end
    runtime.state.lastSaberTick = now

    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            commF:InvokeServer("ProquestProgress", "Check")
            commF:InvokeServer("ProquestProgress", "Begin")
            commF:InvokeServer("ProquestProgress", "Complete")
        end
    end)
end

runtime.setAutoSaberToggle = setAutoSaberToggle

-- =========================================================
-- 5. MAIN FARM LOOP (STEP)
-- =========================================================
local function step()
    preventFalling()

    if runtime.config.AutoStats then
        tryUpgradeStats()
    end

    if runtime.config.AutoSaber then
        tryAutoSaber()
    end

    if not runtime.config.AutoFarm then
        if not runtime.state.tweenActive then
            local hum = getHumanoid()
            local root = getRoot()
            if hum and root and hum.PlatformStand then
                releaseCharacterPhysics(root, hum)
            end
        end
        runtime.state.statusText = "Idle"
        return
    end

    tryTakeSelectedQuest()

    local target = findTargetEnemy()
    runtime.state.currentTarget = target

    if not target then
        runtime.state.statusText = "Scanning / Waiting Mob..."
        return
    end

    local eRoot = getEnemyRoot(target)
    local root = getRoot()
    local hum = getHumanoid()
    if not eRoot or not root or not hum then
        return
    end

    local hoverPos = eRoot.Position + Vector3.new(0, runtime.config.FarmHeight, -runtime.config.FarmDistance)
    local lookCFrame = CFrame.lookAt(hoverPos, eRoot.Position)

    local dist = (root.Position - hoverPos).Magnitude
    if dist > 6 then
        runtime.state.statusText = "Flying -> " .. target.Name
        tweenTo(lookCFrame, runtime.config.TweenSpeed)
    else
        holdCharacterPhysics(root, hum)
        root.CFrame = lookCFrame
        runtime.state.statusText = "Farming: " .. target.Name
    end

    gatherMobsAroundAnchor(eRoot.Position, target)
    performFastAttack(target)
end

-- =========================================================
-- 6. COMPACT SCANNER GUI (MOB / BOSS / QUEST / FARM)
-- =========================================================
local function buildGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("X86_FarmScanner_GUI")
    if existing then
        existing:Destroy()
    end

    runtime.scanWorld()
    runtime.scanQuests()

    local gui = Instance.new("ScreenGui")
    gui.Name = "X86_FarmScanner_GUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 340, 0, 390)
    main.Position = UDim2.new(0.04, 0, 0.14, 0)
    main.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(215, 45, 55)
    stroke.Thickness = 1.4
    stroke.Parent = main

    -- Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 38)
    header.BackgroundColor3 = Color3.fromRGB(26, 20, 24)
    header.BorderSizePixel = 0
    header.Parent = main

    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 10)
    hCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -80, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "BLOX FRUITS • AUTO & SCANNER"
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 32, 0, 24)
    minBtn.Position = UDim2.new(1, -42, 0.5, -12)
    minBtn.BackgroundColor3 = Color3.fromRGB(45, 24, 28)
    minBtn.Text = "—"
    minBtn.TextColor3 = Color3.fromRGB(255, 120, 125)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 13
    minBtn.Parent = header

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0, 6)
    minCorner.Parent = minBtn

    local statusBar = Instance.new("TextLabel")
    statusBar.Size = UDim2.new(1, -20, 0, 20)
    statusBar.Position = UDim2.new(0, 10, 0, 42)
    statusBar.BackgroundTransparency = 1
    statusBar.Text = "Status: Idle"
    statusBar.TextColor3 = Color3.fromRGB(165, 170, 185)
    statusBar.Font = Enum.Font.Code
    statusBar.TextSize = 11
    statusBar.TextXAlignment = Enum.TextXAlignment.Left
    statusBar.Parent = main

    local body = Instance.new("ScrollingFrame")
    body.Size = UDim2.new(1, -16, 1, -70)
    body.Position = UDim2.new(0, 8, 0, 64)
    body.BackgroundTransparency = 1
    body.ScrollBarThickness = 4
    body.CanvasSize = UDim2.new(0, 0, 0, 620)
    body.Parent = main

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = body

    local function makeToggle(order, labelText, initial, callback)
        local btn = Instance.new("TextButton")
        btn.LayoutOrder = order
        btn.Size = UDim2.new(1, -4, 0, 32)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.Parent = body

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 7)
        c.Parent = btn

        local state = not not initial
        local function refresh()
            btn.Text = (state and "[ON]  " or "[OFF] ") .. labelText
            btn.BackgroundColor3 = state and Color3.fromRGB(145, 26, 36) or Color3.fromRGB(28, 30, 38)
            btn.TextColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 195, 210)
        end
        refresh()

        btn.MouseButton1Click:Connect(function()
            state = not state
            refresh()
            callback(state)
        end)
        return btn, function(v)
            state = not not v
            refresh()
        end
    end

    local function makeActionBtn(order, text, bgColor, callback)
        local btn = Instance.new("TextButton")
        btn.LayoutOrder = order
        btn.Size = UDim2.new(1, -4, 0, 30)
        btn.BackgroundColor3 = bgColor or Color3.fromRGB(36, 39, 50)
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(240, 242, 248)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.Parent = body

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 7)
        c.Parent = btn

        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    local function makeInputBox(order, placeholder, defaultVal, callback)
        local box = Instance.new("TextBox")
        box.LayoutOrder = order
        box.Size = UDim2.new(1, -4, 0, 30)
        box.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
        box.Text = tostring(defaultVal or "")
        box.PlaceholderText = placeholder
        box.TextColor3 = Color3.fromRGB(240, 245, 255)
        box.PlaceholderColor3 = Color3.fromRGB(120, 126, 145)
        box.Font = Enum.Font.Code
        box.TextSize = 12
        box.ClearTextOnFocus = false
        box.Parent = body

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 7)
        c.Parent = box

        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(52, 56, 72)
        s.Thickness = 1
        s.Parent = box

        box.FocusLost:Connect(function()
            callback(box.Text)
        end)
        return box, function(txt)
            box.Text = tostring(txt or "")
        end
    end

    -- Picker List สำหรับเลือก Mob / Boss / Quest ที่สแกนเจอจริง
    local pickerFrame = Instance.new("Frame")
    pickerFrame.LayoutOrder = 99
    pickerFrame.Size = UDim2.new(1, -4, 0, 145)
    pickerFrame.BackgroundColor3 = Color3.fromRGB(21, 23, 30)
    pickerFrame.Visible = false
    pickerFrame.Parent = body

    local pCorner = Instance.new("UICorner")
    pCorner.CornerRadius = UDim.new(0, 8)
    pCorner.Parent = pickerFrame

    local pScroll = Instance.new("ScrollingFrame")
    pScroll.Size = UDim2.new(1, -8, 1, -8)
    pScroll.Position = UDim2.new(0, 4, 0, 4)
    pScroll.BackgroundTransparency = 1
    pScroll.ScrollBarThickness = 3
    pScroll.Parent = pickerFrame

    local pLayout = Instance.new("UIListLayout")
    pLayout.Padding = UDim.new(0, 4)
    pLayout.Parent = pScroll

    local function openPicker(items, onPick)
        for _, child in ipairs(pScroll:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("TextLabel") then
                child:Destroy()
            end
        end

        if not items or #items == 0 then
            local emptyLbl = Instance.new("TextLabel")
            emptyLbl.Size = UDim2.new(1, 0, 0, 26)
            emptyLbl.BackgroundTransparency = 1
            emptyLbl.Text = "ไม่พบรายการในพื้นที่ตอนนี้ กด Scan อีกครั้ง"
            emptyLbl.TextColor3 = Color3.fromRGB(160, 165, 180)
            emptyLbl.Font = Enum.Font.Gotham
            emptyLbl.TextSize = 11
            emptyLbl.Parent = pScroll
        else
            for idx, itemName in ipairs(items) do
                local itemBtn = Instance.new("TextButton")
                itemBtn.Size = UDim2.new(1, 0, 0, 26)
                itemBtn.BackgroundColor3 = Color3.fromRGB(32, 35, 46)
                itemBtn.Text = idx .. ". " .. tostring(itemName)
                itemBtn.TextColor3 = Color3.fromRGB(235, 238, 248)
                itemBtn.Font = Enum.Font.Gotham
                itemBtn.TextSize = 11
                itemBtn.TextXAlignment = Enum.TextXAlignment.Left
                itemBtn.Parent = pScroll

                local ic = Instance.new("UICorner")
                ic.CornerRadius = UDim.new(0, 5)
                ic.Parent = itemBtn

                itemBtn.MouseButton1Click:Connect(function()
                    onPick(itemName)
                    pickerFrame.Visible = false
                end)
            end
        end

        pScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(1, #items) * 30)
        pickerFrame.Visible = true
    end

    makeToggle(1, "Auto Farm (Tween + Fast Attack)", runtime.config.AutoFarm, function(v)
        runtime.config.AutoFarm = v
        if not v then
            stopTween()
        end
    end)

    makeToggle(2, "Bring Mob (Pull & Stack)", runtime.config.BringMob, function(v)
        runtime.config.BringMob = v
    end)

    makeToggle(3, "Use Nearest Mob", runtime.config.UseNearestMob, function(v)
        runtime.config.UseNearestMob = v
    end)

    makeToggle(4, "Boss Target Mode", runtime.config.TargetBossMode, function(v)
        runtime.config.TargetBossMode = v
    end)

    local _, setMobBoxText = makeInputBox(5, "Selected Mob (หรือกดเลือกด้านล่าง)", runtime.config.SelectedMob, function(txt)
        runtime.config.SelectedMob = txt
        runtime.config.UseNearestMob = (txt == "")
    end)

    makeActionBtn(6, "Scan & Select Mob", Color3.fromRGB(42, 46, 62), function()
        local mobs = runtime.scanWorld()
        openPicker(mobs, function(chosen)
            runtime.config.SelectedMob = chosen
            runtime.config.UseNearestMob = false
            runtime.config.TargetBossMode = false
            setMobBoxText(chosen)
        end)
    end)

    local _, setBossBoxText = makeInputBox(7, "Boss Target (เช่น Greybeard)", runtime.config.SelectedBoss, function(txt)
        runtime.config.SelectedBoss = txt
    end)

    makeActionBtn(8, "Scan & Select Boss", Color3.fromRGB(78, 30, 38), function()
        local _, bosses = runtime.scanWorld()
        openPicker(bosses, function(chosen)
            runtime.config.SelectedBoss = chosen
            runtime.config.TargetBossMode = true
            setBossBoxText(chosen)
        end)
    end)

    local _, setQuestBoxText = makeInputBox(9, "Manual / Selected Quest", runtime.config.SelectedQuest, function(txt)
        runtime.config.SelectedQuest = txt
        runtime.config.ManualQuest = (txt ~= "")
    end)

    makeActionBtn(10, "Scan & Select Quest + Auto Quest", Color3.fromRGB(36, 52, 68), function()
        local quests = runtime.scanQuests()
        openPicker(quests, function(chosen)
            runtime.config.SelectedQuest = chosen
            runtime.config.ManualQuest = true
            runtime.config.AutoQuest = true
            setQuestBoxText(chosen)
            tryTakeSelectedQuest()
        end)
    end)

    makeInputBox(11, "Tween Speed (default 280)", runtime.config.TweenSpeed, function(txt)
        local n = tonumber(txt)
        if n and n >= 40 and n <= 1000 then
            runtime.config.TweenSpeed = n
        end
    end)

    makeInputBox(12, "Bring Mob Count (1-25)", runtime.config.BringMobCount, function(txt)
        local n = tonumber(txt)
        if n then
            runtime.config.BringMobCount = math.clamp(math.floor(n), 1, 25)
        end
    end)

    makeToggle(13, "Fast Attack", runtime.config.FastAttack, function(v)
        runtime.config.FastAttack = v
    end)

    makeToggle(14, "Anti-Fall Lock", runtime.config.AntiFall, function(v)
        runtime.config.AntiFall = v
    end)

    makeToggle(15, "Auto Saber Quest", runtime.config.AutoSaber, function(v)
        setAutoSaberToggle(v)
    end)

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        body.Visible = not minimized
        statusBar.Visible = not minimized
        main.Size = minimized and UDim2.new(0, 340, 0, 42) or UDim2.new(0, 340, 0, 390)
        minBtn.Text = minimized and "+" or "—"
    end)

    RunService.RenderStepped:Connect(function()
        if gui.Parent then
            statusBar.Text = string.format(
                "Status: %s | Mobs:%d Boss:%d Q:%d",
                runtime.state.statusText,
                #runtime.scanned.Mobs,
                #runtime.scanned.Bosses,
                #runtime.scanned.Quests
            )
        end
    end)
end

-- =========================================================
-- 7. INIT & RUNTIME LOOP
-- =========================================================
buildGUI()

RunService.Heartbeat:Connect(function()
    pcall(step)
end)

getgenv().FarmRuntime = runtime
return runtime
