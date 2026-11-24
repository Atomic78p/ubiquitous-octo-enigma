local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRoot(char)
    char = char or getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(char)
    char = char or getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(model)
    if not model or not model.Parent then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    return hum ~= nil and root ~= nil and hum.Health > 0
end

local runtime = runtime or {
    config = {
        AutoFarm = false,
        BringMob = true,
        BringMobCount = 8,
        BringMobRadius = 35,
        BringPullRadius = 350,
        BringPullOffset = 7,
        BringMobVerticalRange = 60,
        BringAvoidWater = false, -- เปิดได้ แต่ตั้งเป็น false เริ่มต้นเพื่อไม่ให้พลาดมอนที่อยู่ใกล้น้ำ
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
        walkingMode = false,
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
-- 1. SCANNER: MOB / BOSS / QUEST (รวม GuideModule & Spawns)
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
    local mobSet, bossSet = {}, {}
    local mobList, bossList = {}, {}

    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if enemiesFolder then
        for _, obj in ipairs(enemiesFolder:GetChildren()) do
            if obj:IsA("Model") and obj.Name ~= "" then
                if looksLikeBoss(obj.Name) then
                    if not bossSet[obj.Name] then
                        bossSet[obj.Name] = true
                        table.insert(bossList, obj.Name)
                    end
                else
                    if not mobSet[obj.Name] then
                        mobSet[obj.Name] = true
                        table.insert(mobList, obj.Name)
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
                local cleanName = string.gsub(tostring(sp.Name or ""), "%s*Sp[a-zA-Z]*%d*$", "")
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

    local function addName(n)
        n = tostring(n or "")
        if n ~= "" and not seen[n] then
            seen[n] = true
            table.insert(questNames, n)
        end
    end

    local function scanContainer(container)
        if not container then return end
        for _, child in ipairs(container:GetDescendants()) do
            if child:IsA("ModuleScript") or child:IsA("Folder") then
                addName(child.Name)
            end
        end
    end

    scanContainer(ReplicatedStorage:FindFirstChild("Quests"))
    scanContainer(ReplicatedStorage:FindFirstChild("QuestData"))

    local guide = ReplicatedStorage:FindFirstChild("GuideModule")
    if guide and guide:IsA("ModuleScript") then
        pcall(function()
            local data = require(guide)
            if type(data) == "table" then
                for k, v in pairs(data) do
                    if type(k) == "string" then
                        addName(k)
                    elseif type(v) == "table" and type(v.Name) == "string" then
                        addName(v.Name)
                    end
                end
            end
        end)
    end

    table.sort(questNames)
    runtime.scanned.Quests = questNames

    if runtime.config.SelectedQuest == "" and #questNames > 0 then
        runtime.config.SelectedQuest = questNames[1]
    end

    return questNames
end

-- =========================================================
-- 2. MOVEMENT / WALKING / TWEEN FOLLOWER / RECOVER FALL
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

local function setWalking(enabled)
    runtime.state.walkingMode = not not enabled
    local hum = getHumanoid()
    local root = getRoot()
    if not hum or not root then return end

    if runtime.state.walkingMode then
        runtime.state.tweenActive = false
        hum.PlatformStand = false
        if hum:GetState() == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    else
        hum.PlatformStand = true
        hum:ChangeState(Enum.HumanoidStateType.Physics)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

local function releaseTweenHold()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    runtime.state.tweenActive = false
end

local function startTweenFollower(targetCFrame, speed)
    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum or hum.Health <= 0 then
        return false
    end

    setWalking(false)
    speed = math.max(tonumber(speed) or runtime.config.TweenSpeed or 280, 40)
    local dist = (root.Position - targetCFrame.Position).Magnitude

    if dist <= 3.5 then
        root.CFrame = targetCFrame
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    releaseTweenHold()
    runtime.state.tweenActive = true

    local proxy = ensureTweenProxy()
    proxy.CFrame = root.CFrame

    local duration = math.clamp(dist / speed, 0.03, 12)
    local tween = TweenService:Create(
        proxy,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { CFrame = targetCFrame }
    )
    activeTween = tween

    local done = false
    tween.Completed:Connect(function()
        done = true
    end)

    tween:Play()
    while not done do
        if not runtime.config.AutoFarm then
            tween:Cancel()
            break
        end
        root = getRoot()
        hum = getHumanoid()
        if not root or not hum or hum.Health <= 0 then
            tween:Cancel()
            break
        end
        hum.PlatformStand = true
        hum:ChangeState(Enum.HumanoidStateType.Physics)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = proxy.CFrame
        RunService.Heartbeat:Wait()
    end

    if activeTween == tween then
        activeTween = nil
    end
    runtime.state.tweenActive = false

    root = getRoot()
    hum = getHumanoid()
    if root and hum and done then
        hum.PlatformStand = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = targetCFrame
    end

    return done
end

local function recoverFall()
    if not runtime.config.AntiFall then return end
    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum or hum.Health <= 0 then return end

    if runtime.config.AutoFarm or runtime.state.tweenActive then
        hum.PlatformStand = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if root.Position.Y < -280 then
        hum.PlatformStand = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = CFrame.new(root.Position.X, 60, root.Position.Z)
        runtime.state.statusText = "Recovered Fall"
    end
end

-- =========================================================
-- 3. BRING MOB (คงแนวคิด isnetworkowner & bringPathOverWater แบบไม่ตัดทิ้งมั่ว)
-- =========================================================
local function bringPathOverWater(fromPos, toPos)
    if not runtime.config.BringAvoidWater then
        return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = getCharacter()
    if char then
        params.FilterDescendantsInstances = { char }
    end

    local dir = toPos - fromPos
    if dir.Magnitude < 1 then return false end

    local result = Workspace:Raycast(fromPos + Vector3.new(0, 2, 0), dir, params)
    if result and result.Material == Enum.Material.Water then
        return true
    end
    return false
end

local function hasLocalOwnership(part)
    if not part or not part:IsA("BasePart") then return false end
    local ok, owned = pcall(function()
        if type(isnetworkowner) == "function" then
            return isnetworkowner(part)
        end
        return part:GetNetworkOwner() == LocalPlayer
    end)
    return ok and owned == true
end

local function getEnemyRoot(mob)
    if not isAlive(mob) then return nil end
    return mob:FindFirstChild("HumanoidRootPart")
        or mob:FindFirstChild("Torso")
        or mob:FindFirstChild("UpperTorso")
end

local function findTargetEnemy()
    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return nil end

    local root = getRoot()
    local origin = root and root.Position or Vector3.zero
    local bestMob, bestDist = nil, math.huge

    for _, mob in ipairs(enemiesFolder:GetChildren()) do
        local eRoot = getEnemyRoot(mob)
        if eRoot then
            local nameLower = string.lower(mob.Name)
            local matched = false

            if runtime.config.TargetBossMode then
                if runtime.config.SelectedBoss ~= "" then
                    matched = string.find(nameLower, string.lower(runtime.config.SelectedBoss), 1, true) ~= nil
                else
                    matched = looksLikeBoss(mob.Name)
                end
            elseif not runtime.config.UseNearestMob and runtime.config.SelectedMob ~= "" then
                matched = string.find(nameLower, string.lower(runtime.config.SelectedMob), 1, true) ~= nil
            else
                matched = not looksLikeBoss(mob.Name)
            end

            if matched then
                local d = (eRoot.Position - origin).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestMob = mob
                end
            end
        end
    end

    if not bestMob and not runtime.config.TargetBossMode then
        for _, mob in ipairs(enemiesFolder:GetChildren()) do
            local eRoot = getEnemyRoot(mob)
            if eRoot then
                local d = (eRoot.Position - origin).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestMob = mob
                end
            end
        end
    end

    return bestMob
end

local function bringMob(anchorPos, primaryTarget)
    if not runtime.config.BringMob then return end
    local now = os.clock()
    if now - runtime.state.lastBringTick < 0.2 then return end
    runtime.state.lastBringTick = now

    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return end

    local list = {}
    for _, mob in ipairs(enemiesFolder:GetChildren()) do
        local eRoot = getEnemyRoot(mob)
        if eRoot then
            local horizDist = (Vector3.new(eRoot.Position.X, 0, eRoot.Position.Z) - Vector3.new(anchorPos.X, 0, anchorPos.Z)).Magnitude
            local vertDiff = math.abs(eRoot.Position.Y - anchorPos.Y)
            local withinRange = (mob == primaryTarget) or (horizDist <= runtime.config.BringPullRadius and vertDiff <= runtime.config.BringMobVerticalRange)

            if withinRange and not bringPathOverWater(eRoot.Position, anchorPos) then
                table.insert(list, {
                    model = mob,
                    root = eRoot,
                    dist = horizDist,
                    owned = hasLocalOwnership(eRoot),
                })
            end
        end
    end

    table.sort(list, function(a, b)
        if a.model == primaryTarget then return true end
        if b.model == primaryTarget then return false end
        if a.owned ~= b.owned then return a.owned end
        return a.dist < b.dist
    end)

    local maxCount = math.clamp(tonumber(runtime.config.BringMobCount) or 8, 1, 30)
    local total = math.min(#list, maxCount)
    local stackCenter = Vector3.new(anchorPos.X, anchorPos.Y - runtime.config.FarmHeight, anchorPos.Z)

    for i = 1, total do
        local item = list[i]
        local eRoot = item.root
        if eRoot and eRoot.Parent then
            local angle = (i / math.max(1, total)) * math.pi * 2
            local offset = (i == 1) and 0 or math.min(runtime.config.BringPullOffset, 10)
            local targetPos = stackCenter + Vector3.new(math.cos(angle) * offset, 0, math.sin(angle) * offset)

            pcall(function()
                if sethiddenproperty then
                    sethiddenproperty(LocalPlayer, "SimulationRadius", 1000)
                end
                for _, part in ipairs(item.model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                        part.AssemblyLinearVelocity = Vector3.zero
                        part.AssemblyAngularVelocity = Vector3.zero
                    end
                end
                eRoot.CFrame = CFrame.lookAt(targetPos, stackCenter)
                runtime.pulledMobs[item.model] = now
            end)
        end
    end
end

-- =========================================================
-- 4. FAST ATTACK, AUTO QUEST, AUTO STATS, AUTO SABER
-- =========================================================
local function equipWeapon()
    local char = getCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not char or not backpack then return end

    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then return end
    end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and (
            tool.ToolTip == "Melee"
            or tool.ToolTip == "Sword"
            or string.find(string.lower(tool.Name), "combat")
            or string.find(string.lower(tool.Name), "blade")
            or string.find(string.lower(tool.Name), "sword")
        ) then
            tool.Parent = char
            return
        end
    end

    local anyTool = backpack:FindFirstChildOfClass("Tool")
    if anyTool then
        anyTool.Parent = char
    end
end

local function fastAttack(target)
    if not runtime.config.FastAttack or not target then return end
    local now = os.clock()
    if now - runtime.state.lastAttack < runtime.config.AttackCooldown then return end
    runtime.state.lastAttack = now

    equipWeapon()
    local char = getCharacter()
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function()
            tool:Activate()
        end)
    end

    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            commF:InvokeServer("Attack")
        end
    end)
end

local function autoQuestTick()
    if not runtime.config.AutoQuest or runtime.config.SelectedQuest == "" then return end
    local now = os.clock()
    if now - runtime.state.lastQuestTick < 3 then return end
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
    if not runtime.config.AutoStats then return end
    local now = os.clock()
    if now - runtime.state.lastStatTick < 1.2 then return end
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
    if not runtime.config.AutoSaber then return end
    local now = os.clock()
    if now - runtime.state.lastSaberTick < 4 then return end
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
-- 5. STEP LOOP
-- =========================================================
local function step()
    recoverFall()

    if runtime.config.AutoStats then
        tryUpgradeStats()
    end

    if runtime.config.AutoSaber then
        tryAutoSaber()
    end

    if not runtime.config.AutoFarm then
        if not runtime.state.walkingMode and not runtime.state.tweenActive then
            setWalking(true)
        end
        runtime.state.statusText = "Idle"
        return
    end

    autoQuestTick()

    local target = findTargetEnemy()
    runtime.state.currentTarget = target
    if not target then
        runtime.state.statusText = "Waiting Target..."
        return
    end

    local eRoot = getEnemyRoot(target)
    local root = getRoot()
    local hum = getHumanoid()
    if not eRoot or not root or not hum then return end

    local destCFrame = CFrame.lookAt(
        eRoot.Position + Vector3.new(0, runtime.config.FarmHeight, -runtime.config.FarmDistance),
        eRoot.Position
    )

    if (root.Position - destCFrame.Position).Magnitude > 6 then
        runtime.state.statusText = "Tween -> " .. target.Name
        startTweenFollower(destCFrame, runtime.config.TweenSpeed)
    else
        setWalking(false)
        root.CFrame = destCFrame
        runtime.state.statusText = "Farm: " .. target.Name
    end

    bringMob(eRoot.Position, target)
    fastAttack(target)
end

-- =========================================================
-- 6. GUI (สแกนและเลือก Mob / Boss / Quest + Farm Controls)
-- =========================================================
local function buildGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("X86_FarmScanner_GUI")
    if old then old:Destroy() end

    runtime.scanWorld()
    runtime.scanQuests()

    local gui = Instance.new("ScreenGui")
    gui.Name = "X86_FarmScanner_GUI"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 336, 0, 385)
    main.Position = UDim2.new(0.04, 0, 0.14, 0)
    main.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui

    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(215, 45, 55)
    stroke.Thickness = 1.4

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(26, 20, 24)
    header.BorderSizePixel = 0
    header.Parent = main
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -76, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "BLOX FRUITS • TARGET & SCANNER"
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 30, 0, 24)
    minBtn.Position = UDim2.new(1, -40, 0.5, -12)
    minBtn.BackgroundColor3 = Color3.fromRGB(45, 24, 28)
    minBtn.Text = "—"
    minBtn.TextColor3 = Color3.fromRGB(255, 120, 125)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 13
    minBtn.Parent = header
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1, -20, 0, 18)
    statusLbl.Position = UDim2.new(0, 10, 0, 40)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text = "Status: Idle"
    statusLbl.TextColor3 = Color3.fromRGB(165, 170, 185)
    statusLbl.Font = Enum.Font.Code
    statusLbl.TextSize = 11
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Parent = main

    local body = Instance.new("ScrollingFrame")
    body.Size = UDim2.new(1, -16, 1, -66)
    body.Position = UDim2.new(0, 8, 0, 60)
    body.BackgroundTransparency = 1
    body.ScrollBarThickness = 4
    body.CanvasSize = UDim2.new(0, 0, 0, 640)
    body.Parent = main

    local layout = Instance.new("UIListLayout", body)
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local function addToggle(order, label, init, cb)
        local btn = Instance.new("TextButton")
        btn.LayoutOrder = order
        btn.Size = UDim2.new(1, -4, 0, 30)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.Parent = body
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)

        local st = not not init
        local function paint()
            btn.Text = (st and "[ON]  " or "[OFF] ") .. label
            btn.BackgroundColor3 = st and Color3.fromRGB(145, 26, 36) or Color3.fromRGB(28, 30, 38)
            btn.TextColor3 = st and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 195, 210)
        end
        paint()

        btn.MouseButton1Click:Connect(function()
            st = not st
            paint()
            cb(st)
        end)
    end

    local function addBtn(order, label, color, cb)
        local btn = Instance.new("TextButton")
        btn.LayoutOrder = order
        btn.Size = UDim2.new(1, -4, 0, 30)
        btn.BackgroundColor3 = color
        btn.Text = label
        btn.TextColor3 = Color3.fromRGB(240, 242, 248)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.Parent = body
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
        btn.MouseButton1Click:Connect(cb)
    end

    local function addBox(order, placeholder, defVal, cb)
        local box = Instance.new("TextBox")
        box.LayoutOrder = order
        box.Size = UDim2.new(1, -4, 0, 28)
        box.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
        box.Text = tostring(defVal or "")
        box.PlaceholderText = placeholder
        box.TextColor3 = Color3.fromRGB(240, 245, 255)
        box.PlaceholderColor3 = Color3.fromRGB(120, 126, 145)
        box.Font = Enum.Font.Code
        box.TextSize = 12
        box.ClearTextOnFocus = false
        box.Parent = body
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
        local s = Instance.new("UIStroke", box)
        s.Color = Color3.fromRGB(52, 56, 72)
        s.Thickness = 1
        box.FocusLost:Connect(function()
            cb(box.Text)
        end)
        return function(v) box.Text = tostring(v or "") end
    end

    local picker = Instance.new("Frame")
    picker.LayoutOrder = 99
    picker.Size = UDim2.new(1, -4, 0, 140)
    picker.BackgroundColor3 = Color3.fromRGB(21, 23, 30)
    picker.Visible = false
    picker.Parent = body
    Instance.new("UICorner", picker).CornerRadius = UDim.new(0, 8)

    local pScroll = Instance.new("ScrollingFrame")
    pScroll.Size = UDim2.new(1, -8, 1, -8)
    pScroll.Position = UDim2.new(0, 4, 0, 4)
    pScroll.BackgroundTransparency = 1
    pScroll.ScrollBarThickness = 3
    pScroll.Parent = picker
    Instance.new("UIListLayout", pScroll).Padding = UDim.new(0, 4)

    local function openList(items, onSelect)
        for _, c in ipairs(pScroll:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
        end
        if not items or #items == 0 then
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 0, 24)
            lbl.BackgroundTransparency = 1
            lbl.Text = "ไม่พบรายชื่อในตอนนี้ ลองกด Scan ใหม่"
            lbl.TextColor3 = Color3.fromRGB(165, 170, 185)
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 11
            lbl.Parent = pScroll
        else
            for i, name in ipairs(items) do
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1, 0, 0, 25)
                b.BackgroundColor3 = Color3.fromRGB(32, 35, 46)
                b.Text = string.format("%d. %s", i, tostring(name))
                b.TextColor3 = Color3.fromRGB(235, 238, 248)
                b.Font = Enum.Font.Gotham
                b.TextSize = 11
                b.TextXAlignment = Enum.TextXAlignment.Left
                b.Parent = pScroll
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
                b.MouseButton1Click:Connect(function()
                    onSelect(name)
                    picker.Visible = false
                end)
            end
        end
        pScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(1, #items) * 29)
        picker.Visible = true
    end

    addToggle(1, "Auto Farm", runtime.config.AutoFarm, function(v)
        runtime.config.AutoFarm = v
        if not v then
            releaseTweenHold()
            setWalking(true)
        end
    end)

    addToggle(2, "Bring Mob", runtime.config.BringMob, function(v)
        runtime.config.BringMob = v
    end)

    addToggle(3, "Use Nearest Mob", runtime.config.UseNearestMob, function(v)
        runtime.config.UseNearestMob = v
    end)

    addToggle(4, "Boss Target Mode", runtime.config.TargetBossMode, function(v)
        runtime.config.TargetBossMode = v
    end)

    local setMobText = addBox(5, "Selected Mob", runtime.config.SelectedMob, function(t)
        runtime.config.SelectedMob = t
        runtime.config.UseNearestMob = (t == "")
    end)

    addBtn(6, "Scan & Select Mob", Color3.fromRGB(42, 46, 62), function()
        local mobs = runtime.scanWorld()
        openList(mobs, function(chosen)
            runtime.config.SelectedMob = chosen
            runtime.config.UseNearestMob = false
            runtime.config.TargetBossMode = false
            setMobText(chosen)
        end)
    end)

    local setBossText = addBox(7, "Boss Target", runtime.config.SelectedBoss, function(t)
        runtime.config.SelectedBoss = t
    end)

    addBtn(8, "Scan & Select Boss", Color3.fromRGB(78, 30, 38), function()
        local _, bosses = runtime.scanWorld()
        openList(bosses, function(chosen)
            runtime.config.SelectedBoss = chosen
            runtime.config.TargetBossMode = true
            setBossText(chosen)
        end)
    end)

    local setQuestText = addBox(9, "Manual / Selected Quest", runtime.config.SelectedQuest, function(t)
        runtime.config.SelectedQuest = t
        runtime.config.ManualQuest = (t ~= "")
    end)

    addBtn(10, "Scan & Select Quest", Color3.fromRGB(36, 52, 68), function()
        local quests = runtime.scanQuests()
        openList(quests, function(chosen)
            runtime.config.SelectedQuest = chosen
            runtime.config.ManualQuest = true
            runtime.config.AutoQuest = true
            setQuestText(chosen)
        end)
    end)

    addBox(11, "Tween Speed", runtime.config.TweenSpeed, function(t)
        local n = tonumber(t)
        if n and n >= 40 and n <= 1000 then
            runtime.config.TweenSpeed = n
        end
    end)

    addBox(12, "Bring Mob Count", runtime.config.BringMobCount, function(t)
        local n = tonumber(t)
        if n then
            runtime.config.BringMobCount = math.clamp(math.floor(n), 1, 30)
        end
    end)

    addToggle(13, "Fast Attack", runtime.config.FastAttack, function(v)
        runtime.config.FastAttack = v
    end)

    addToggle(14, "Anti-Fall", runtime.config.AntiFall, function(v)
        runtime.config.AntiFall = v
    end)

    local mini = false
    minBtn.MouseButton1Click:Connect(function()
        mini = not mini
        body.Visible = not mini
        statusLbl.Visible = not mini
        main.Size = mini and UDim2.new(0, 336, 0, 40) or UDim2.new(0, 336, 0, 385)
        minBtn.Text = mini and "+" or "—"
    end)

    RunService.RenderStepped:Connect(function()
        if gui.Parent then
            statusLbl.Text = string.format(
                "Status: %s | M:%d B:%d Q:%d",
                runtime.state.statusText,
                #runtime.scanned.Mobs,
                #runtime.scanned.Bosses,
                #runtime.scanned.Quests
            )
        end
    end)
end

buildGUI()
RunService.Heartbeat:Connect(function()
    pcall(step)
end)

getgenv().FarmRuntime = runtime
return runtime
