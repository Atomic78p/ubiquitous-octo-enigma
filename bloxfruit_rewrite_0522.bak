-- // Blox Fruits Auto-Farm — Clean & Refactored Build
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer

-- ================= CONFIG =================
local CONFIG = {
    AutoQuest       = true,
    AutoFarm        = true,
    FruitSniper     = true,
    Debug           = true,
    EatFruit        = true,
    QuestTurnIn     = true,
    AntiAfk         = true,
    AntiAfkInterval = 120,
    AttackCooldown  = 0.08,
    FastAttack      = true,
    RemoteAttack    = true,
    HitboxMagnitude = 120,
    WeaponMode      = "Melee",
    MeleeRange      = 10,
    GunRange        = 60,
    MeleeHover      = 4,
    BringMob        = true,
    BringMobRange   = 40,
    BigHitbox       = true,
    HitboxSize      = 16,
    HeadHover       = 2,
    AutoAttack      = true,
    AutoStore       = false,
    StoreFruitMin   = 3,
    HoverHeight     = 8,
    FruitScanRadius = 5000,
    MovementMode    = "Tween",
    MoveSpeed       = 250,
    QuestRetry      = 5,
    FruitPickupTries = 4,
    FruitTouchInterval = 0.35,
    SafeY           = -300,
    StuckTimeout    = 5,
    StuckIgnore     = 10,

    QuestList = {
        {1,   9,   "BanditQuest1",  1, "Bandit"},
        {10,  14,  "JungleQuest",   1, "Monkey"},
        {15,  29,  "JungleQuest",   2, "Gorilla"},
        {30,  39,  "BuggyQuest1",   1, "Pirate"},
        {40,  59,  "BuggyQuest1",   2, "Brute"},
        {60,  74,  "DesertQuest",   1, "Desert Bandit"},
        {75,  89,  "DesertQuest",   2, "Desert Officer"},
        {90,  99,  "SnowQuest",     1, "Snow Bandit"},
        {100, 119, "SnowQuest",     2, "Snowman"},
        {120, 149, "MarineQuest2",  1, "Chief Petty Officer"},
        {150, 174, "SkyQuest",      1, "Sky Bandit"},
    },
}

local state = {
    enabled       = true,
    currentQuest  = nil,
    questSentAt   = 0,
    lastQuestTry  = 0,
    lastAttack    = 0,
    lastFruitScan = 0,
    fruit         = nil,
    fruitStart    = 0,
    fruitTries    = 0,
    fruitLastTry  = 0,
    fruitsFound   = 0,
    farming       = false,
    status        = "Idle",
    debugLine     = "",
    debugMsg      = "",
    debugCount    = 0,
    lastPrinted   = "",
    lastSafe      = nil,
    lastPos       = nil,
    movedAt       = 0,
    recoverUntil  = 0,
    equipRetryAt  = 0,
    fruitToolCount = 0,
    lastTarget    = nil,
    targetHealth  = nil,
    targetAt      = 0,
    targetDist    = nil,
    travelAt      = 0,
    afkTimer      = 0,
    afkSign       = 1,
    fruitTools    = nil,
}

local grabbedFruits = setmetatable({}, {__mode = "k"})

local function dbg(msg)
    if msg == state.debugMsg then
        state.debugCount += 1
        state.debugLine = msg .. " (x" .. state.debugCount .. ")"
    else
        state.debugMsg = msg
        state.debugCount = 1
        state.debugLine = msg
    end
    if CONFIG.Debug and msg ~= state.lastPrinted then
        state.lastPrinted = msg
        print("[Farm] " .. msg)
    end
end

-- ================= THEME =================
local THEME = {
    bg      = Color3.fromRGB(22,22,30),
    panel   = Color3.fromRGB(30,30,42),
    accent  = Color3.fromRGB(122,162,247),
    danger  = Color3.fromRGB(240,120,120),
    ok      = Color3.fromRGB(158,206,106),
    off     = Color3.fromRGB(58,58,76),
    text    = Color3.fromRGB(220,220,235),
    subtext = Color3.fromRGB(140,140,165),
    font    = Enum.Font.GothamMedium,
    fontBold= Enum.Font.GothamBold,
}

-- ================= HELPERS =================
local function sameName(a, b) return a:lower() == b:lower() end

local function anchorOf(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    local hrp = obj:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    if obj:IsA("Model") and obj.PrimaryPart then return obj.PrimaryPart end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function getRoot() local c = LocalPlayer.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function getHumanoid() local c = LocalPlayer.Character; return c and c:FindFirstChildOfClass("Humanoid") end

local function getMyLevel()
    local data = LocalPlayer:FindFirstChild("Data")
    local level = data and data:FindFirstChild("Level")
    if level then return math.floor(level.Value) end
    return 1
end

local function isFruit(t)
    return t.Name:lower():find("fruit", 1, true) ~= nil
end

local WEAPON_GROUPS = {
    Melee = {"combat", "melee", "style", "fist", "black leg", "electro", "water kung fu", "dragon claw", "superhuman", "death step", "sharkman karate", "electric claw", "dragon talon", "godhuman", "sanguine art"},
    Sword = {"sword", "cutlass", "saber", "katana", "blade", "claymore", "greatsword", "dagger", "scythe", "triple katana", "pole", "pipe", "bisento", "yoru"},
    Gun   = {"gun", "flintlock", "musket", "cannon", "pistol", "revolver", "shotgun", "rifle", "bow", "crossbow", "slingshot", "kabucha"},
}

local function isGun(tool)
    local n = tool.Name:lower()
    for _, w in ipairs(WEAPON_GROUPS.Gun) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

local function matchesMode(tool)
    local mode = CONFIG.WeaponMode
    if mode == "Fruit" then return isFruit(tool) end
    local n = tool.Name:lower()
    local group = WEAPON_GROUPS[mode] or WEAPON_GROUPS.Melee
    for _, w in ipairs(group) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

local function attackRange(tool)
    if tool and isGun(tool) then return CONFIG.GunRange end
    return CONFIG.MeleeRange
end

local function equipWeapon()
    local char = LocalPlayer.Character
    if not char then return nil end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local hum = getHumanoid()
    if not hum then return nil end

    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and matchesMode(equipped) then return equipped end

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and matchesMode(item) then
                pcall(function() hum:EquipTool(item) end)
                return item
            end
        end
        -- Fallback
        local fallback = backpack:FindFirstChildOfClass("Tool")
        if fallback then
            pcall(function() hum:EquipTool(fallback) end)
            return fallback
        end
    end
    return equipped
end

-- ================= CLEAN BRING MOB (POSITION ONLY) =================
local function findEnemiesFolder()
    return Workspace:FindFirstChild("Enemies") or Workspace
end

local stuckTargets = setmetatable({}, {__mode = "k"})
local enemyCache, enemyCacheAt = {}, -999

local function collectEnemies(now)
    if now - enemyCacheAt < 0.2 then return enemyCache end
    local list = {}
    local folder = findEnemiesFolder()
    for _, e in ipairs(folder:GetChildren()) do
        if e:IsA("Model") then
            local hum = e:FindFirstChildOfClass("Humanoid")
            local stuck = stuckTargets[e]
            if hum and hum.Health > 0 and (not stuck or stuck < now) then
                table.insert(list, e)
            end
        end
    end
    enemyCache, enemyCacheAt = list, now
    return list
end

local function bringMob(target, root)
    if not CONFIG.BringMob or not target then return end
    local targetAnchor = anchorOf(target)
    if not targetAnchor then return end

    local allEnemies = collectEnemies(tick())
    for _, mob in ipairs(allEnemies) do
        if mob ~= target and mob.Name == target.Name then
            local anchor = anchorOf(mob)
            if anchor then
                local dist = (anchor.Position - targetAnchor.Position).Magnitude
                if dist <= CONFIG.BringMobRange then
                    pcall(function()
                        anchor.CanCollide = false
                        anchor.CFrame = targetAnchor.CFrame
                    end)
                end
            end
        end
    end
end

local function enlargeHitbox(target)
    local anchor = anchorOf(target)
    if not anchor or not anchor.Size then return end
    local size = CONFIG.HitboxSize or 16
    if anchor.Size.X >= size then return end
    pcall(function() anchor.Size = Vector3.new(size, size, size) end)
end

-- ================= QUEST CHECK (SIMPLIFIED & FAST) =================
local function questFor(level)
    for _, q in ipairs(CONFIG.QuestList) do
        if level >= q[1] and level <= q[2] then
            return {name = q[3], index = q[4], mob = q[5]}
        end
    end
    return nil
end

local function hasActiveQuest()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local mainFrame = pg and pg:FindFirstChild("Main")
    local questFrame = mainFrame and mainFrame:FindFirstChild("Quest")
    return questFrame and questFrame.Visible == true
end

local function tryAcceptQuest()
    if hasActiveQuest() then return end
    local now = tick()
    if now - state.lastQuestTry < CONFIG.QuestRetry then return end
    state.lastQuestTry = now

    local q = questFor(getMyLevel())
    if not q then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then return end

    pcall(function() commF:InvokeServer("StartQuest", q.name, q.index) end)
    dbg("Quest accepted: " .. q.name)
end

local function getTarget(mobName)
    local root = getRoot()
    if not root then return nil end
    local best, bestD = nil, math.huge
    for _, mob in ipairs(collectEnemies(tick())) do
        if not mobName or mob.Name:lower():find(mobName:lower(), 1, true) then
            local anchor = anchorOf(mob)
            if anchor then
                local d = (root.Position - anchor.Position).Magnitude
                if d < bestD then best, bestD = mob, d end
            end
        end
    end
    return best
end

local function findSpawn(mobName)
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    local root = getRoot()
    if not spawns or not root then return nil end

    for _, p in ipairs(spawns:GetChildren()) do
        if mobName and p.Name:lower():find(mobName:lower(), 1, true) then
            return p
        end
    end
    return nil
end

-- ================= MOVEMENT =================
local activeTween, tweenGoal

local function stopTween()
    if activeTween then activeTween:Cancel(); activeTween = nil end
    tweenGoal = nil
end

local function moveTo(cf)
    local root = getRoot()
    if not root then return end
    local mode = CONFIG.MovementMode

    if mode == "Teleport" then
        root.CFrame = cf
    elseif mode == "Tween" then
        local dist = (root.Position - cf.Position).Magnitude
        if dist < 6 then
            stopTween()
            root.CFrame = cf
            return
        end
        if activeTween and tweenGoal and (tweenGoal.Position - cf.Position).Magnitude < 3
            and activeTween.PlaybackState == Enum.PlaybackState.Playing then
            return
        end
        stopTween()
        tweenGoal = cf
        activeTween = TweenService:Create(root,
            TweenInfo.new(math.max(dist / CONFIG.MoveSpeed, 0.03), Enum.EasingStyle.Linear),
            {CFrame = cf})
        activeTween:Play()
    else
        local hum = getHumanoid()
        if hum then hum:MoveTo(cf.Position) end
    end
end

-- ================= NOCLIP =================
RunService.Stepped:Connect(function()
    pcall(function()
        local char = LocalPlayer.Character
        if CONFIG.AutoFarm and state.farming and char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end)
end)

-- ================= ATTACK =================
local function fastAttack()
    local ps = LocalPlayer and LocalPlayer.PlayerScripts
    local mod = ps and ps:FindFirstChild("CombatFramework")
    if not mod then return end
    local ok, cf = pcall(require, mod)
    if not ok or not cf then return end
    pcall(function()
        local ctrl = cf.activeController
        if ctrl then
            ctrl.attacking = false
            ctrl.timeToNextAttack = 0
            ctrl.hitboxMagnitude = CONFIG.HitboxMagnitude or 120
        end
    end)
end

local function doAttack(tool, target)
    if CONFIG.FastAttack then fastAttack() end
    pcall(function() tool:Activate() end)
end

-- ================= MAIN LOOP =================
local function step()
    local root, hum = getRoot(), getHumanoid()
    local now = tick()
    if not root or not hum or hum.Health <= 0 then
        state.farming = false
        state.status = "Respawning..."
        return
    end

    if CONFIG.AutoQuest then
        tryAcceptQuest()
    end

    if not CONFIG.AutoFarm then
        state.farming = false
        state.status = "Idle"
        return
    end
    state.farming = true

    local quest = questFor(getMyLevel())
    local mobName = quest and quest.mob or nil

    local target = getTarget(mobName)
    if not target then
        local sp = findSpawn(mobName)
        local anchor = sp and anchorOf(sp)
        if anchor then
            state.status = "Waiting/Travelling to " .. (mobName or "mobs")
            moveTo(anchor.CFrame + Vector3.new(0, CONFIG.HoverHeight, 0))
        else
            state.status = "No targets found"
        end
        return
    end

    local er = anchorOf(target)
    if not er then return end

    local tool = equipWeapon()
    local reach = attackRange(tool)
    
    -- Bring Mob
    bringMob(target, root)

    if CONFIG.BigHitbox then enlargeHitbox(target) end

    -- Hover Position
    local hoverPos = er.Position + Vector3.new(0, CONFIG.HoverHeight, 0)
    moveTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))

    if now - state.lastAttack >= CONFIG.AttackCooldown then
        if tool then
            doAttack(tool, target)
            state.lastAttack = now
            state.status = "Attacking " .. target.Name
        end
    end
end

task.spawn(function()
    while true do
        if state.enabled then
            local ok, err = pcall(step)
            if not ok then dbg("Loop error: " .. tostring(err)) end
        else
            state.farming = false
            state.status = "Stopped"
            stopTween()
        end
        task.wait(0.05)
    end
end)

-- ================= GUI HELPERS =================
local function corner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p; return c end
local function stroke(p) local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(50,50,65); s.Thickness=1; s.Parent=p; return s end

local gui = Instance.new("ScreenGui")
gui.Name = "CustomFarmGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 320, 0, 480)
main.Position = UDim2.new(0, 20, 0, 20)
main.BackgroundColor3 = THEME.bg
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
corner(main, 10); stroke(main)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 34)
titleBar.BackgroundColor3 = THEME.panel
titleBar.BorderSizePixel = 0
titleBar.Parent = main
corner(titleBar, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Blox Fruits • Fast Farm"
title.TextColor3 = THEME.text
title.Font = THEME.fontBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -16, 1, -100)
content.Position = UDim2.new(0, 8, 0, 42)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = THEME.accent
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = content

local function makeToggle(text, default, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,32); row.BackgroundTransparency = 1
    row.LayoutOrder = #content:GetChildren(); row.Parent = content

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,-60,1,0); label.BackgroundTransparency = 1
    label.Text = text; label.TextColor3 = THEME.text
    label.Font = THEME.font; label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = row

    local switch = Instance.new("Frame")
    switch.Size = UDim2.new(0,38,0,20)
    switch.Position = UDim2.new(1,-38,0.5,-10)
    switch.BackgroundColor3 = default and THEME.accent or THEME.off
    switch.Parent = row; corner(switch, 10)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,16,0,16)
    knob.Position = default and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
    knob.BackgroundColor3 = Color3.fromRGB(245,245,250)
    knob.Parent = switch; corner(knob, 8)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1
    btn.Text = ""; btn.Parent = row

    local v = default
    btn.MouseButton1Click:Connect(function()
        v = not v
        switch.BackgroundColor3 = v and THEME.accent or THEME.off
        knob.Position = v and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
        cb(v)
    end)
end

makeToggle("Bot Enabled", state.enabled, function(v) state.enabled = v end)
makeToggle("Auto Quest", CONFIG.AutoQuest, function(v) CONFIG.AutoQuest = v end)
makeToggle("Auto Farm", CONFIG.AutoFarm, function(v) CONFIG.AutoFarm = v end)
makeToggle("Bring Mob", CONFIG.BringMob, function(v) CONFIG.BringMob = v end)
makeToggle("Fast Attack", CONFIG.FastAttack, function(v) CONFIG.FastAttack = v end)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 40)
statusLabel.Position = UDim2.new(0, 8, 1, -50)
statusLabel.BackgroundColor3 = THEME.panel
statusLabel.Text = "Status: Idle"; statusLabel.TextColor3 = THEME.text
statusLabel.Font = THEME.fontBold; statusLabel.TextSize = 11
statusLabel.Parent = main; corner(statusLabel, 6)

task.spawn(function()
    while gui.Parent do
        statusLabel.Text = "Status: " .. (state.enabled and state.status or "Stopped")
        task.wait(0.3)
    end
end)

print("[Farm] Clean version loaded successfully!")
