-- // Blox Fruits Auto-Farm — Fixed Build
print("[Farm] build start")
-- One live copy of the bot is allowed. A second execution first tears the old
-- copy down; the generation check makes every old task leave instead of
-- running a second farm beside the new one.
-- Apex executes injected chunks in an isolated script VM. Keep the registry in
-- the executor's shared environment as well as in this chunk, so a later
-- execution can stop the previous copy and live diagnostics can inspect the
-- same runtime that the farm is actually using.
FarmRuntime = (getgenv and getgenv().FarmRuntime) or _G.FarmRuntime or {}
if getgenv then getgenv().FarmRuntime = FarmRuntime end
if _G then _G.FarmRuntime = FarmRuntime end
local runtime = {
    generation = (FarmRuntime.generation or 0) + 1,
    running = true,
    hookConnections = {},
    characterConnections = {},
    inputConnections = {},
    tasks = {},
    steppedConn = nil,
    gui = nil,
    disposed = false,
    cleanupFns = {},
    characterEpoch = 0,
    state = nil,
    config = nil,
}
runtime.isCurrent = function()
    return runtime.running and FarmRuntime.current == runtime
end
if FarmRuntime.current and FarmRuntime.current.running
    and type(FarmRuntime.stop) == "function" then
    pcall(FarmRuntime.stop)
end
FarmRuntime.generation = runtime.generation
FarmRuntime.current = runtime
-- One idempotent teardown owns the whole run. The gameplay cleanup functions
-- register themselves below, when they exist; the early part still cancels
-- tasks and disconnects listeners if a second execution arrives while this
-- chunk is still being built.
FarmRuntime.stop = function()
    if runtime.disposed then return end
    runtime.disposed = true
    runtime.running = false
    runtime.characterEpoch = (runtime.characterEpoch or 0) + 1
    if runtime.state then runtime.state.enabled = false end
    for _, cleanup in ipairs(runtime.cleanupFns or {}) do
        pcall(cleanup)
    end
    if runtime.hitThread then
        runtime.hitRequest = {stop = true}
        pcall(coroutine.resume, runtime.hitThread)
        runtime.hitThread = nil
        runtime.hitRequest = nil
        runtime.hitResult = nil
    end
    for _, thread in ipairs(runtime.tasks or {}) do pcall(task.cancel, thread) end
    for _, connection in ipairs(runtime.hookConnections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    for _, connection in ipairs(runtime.characterConnections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    for _, connection in ipairs(runtime.inputConnections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    if runtime.steppedConn then pcall(function() runtime.steppedConn:Disconnect() end) end
    if runtime.gui then pcall(function() runtime.gui:Destroy() end) end
    runtime.hookConnections = {}
    runtime.characterConnections = {}
    runtime.inputConnections = {}
    runtime.tasks = {}
    runtime.steppedConn = nil
    runtime.gui = nil
end
-- The services are put in the global table on purpose: the script has a hard
-- limit of 200 locals in one chunk, and it is already close to it.
Players           = game:GetService("Players")
RunService        = game:GetService("RunService")
Workspace         = game:GetService("Workspace")
ReplicatedStorage = game:GetService("ReplicatedStorage")
UserInputService  = game:GetService("UserInputService")
TweenService      = game:GetService("TweenService")
LocalPlayer       = Players.LocalPlayer

-- Streaming and simulation are client-wide settings. Capture the values that
-- were in place before this run changes them and put them back when the farm
-- is stopped. A second execution first stops the old copy, so the old run
-- restores its settings before the new run captures them.
runtime.captureClientGlobals = function()
    local ok, value = pcall(function() return Workspace.StreamingEnabled end)
    if ok then runtime.originalStreamingEnabled = value end
    ok, value = pcall(function() return Workspace.StreamingMinRadius end)
    if ok then runtime.originalStreamingMinRadius = value end
    ok, value = pcall(function() return Workspace.StreamingTargetRadius end)
    if ok then runtime.originalStreamingTargetRadius = value end
    ok, value = pcall(function() return LocalPlayer.SimulationRadius end)
    if ok then runtime.originalSimulationRadius = value end
    ok, value = pcall(function() return LocalPlayer.MaxSimulationRadius end)
    if ok then runtime.originalMaxSimulationRadius = value end
end
runtime.restoreClientGlobals = function()
    if runtime.originalStreamingEnabled ~= nil then
        pcall(function() Workspace.StreamingEnabled = runtime.originalStreamingEnabled end)
    end
    if runtime.originalStreamingMinRadius ~= nil then
        pcall(function() Workspace.StreamingMinRadius = runtime.originalStreamingMinRadius end)
    end
    if runtime.originalStreamingTargetRadius ~= nil then
        pcall(function() Workspace.StreamingTargetRadius = runtime.originalStreamingTargetRadius end)
    end
    if runtime.originalSimulationRadius ~= nil then
        if sethiddenproperty then
            pcall(function() sethiddenproperty(LocalPlayer, "SimulationRadius", runtime.originalSimulationRadius) end)
        end
        pcall(function() LocalPlayer.SimulationRadius = runtime.originalSimulationRadius end)
    end
    if runtime.originalMaxSimulationRadius ~= nil then
        if sethiddenproperty then
            pcall(function() sethiddenproperty(LocalPlayer, "MaxSimulationRadius", runtime.originalMaxSimulationRadius) end)
        end
        pcall(function() LocalPlayer.MaxSimulationRadius = runtime.originalMaxSimulationRadius end)
    end
end
runtime.captureClientGlobals()
pcall(function() Workspace.StreamingEnabled = false end)
pcall(function() Workspace.StreamingMinRadius = 1e8 end)
pcall(function() Workspace.StreamingTargetRadius = 1e8 end)
table.insert(runtime.cleanupFns, function() runtime.restoreClientGlobals() end)

-- ================= CONFIG =================
-- CONFIG and state live in the global table: the chunk is at the limit of
-- 200 locals.
CONFIG = {
    AutoQuest       = true,
    AutoFarm        = true,
    FruitSniper     = true,
    Debug           = true,
    EatFruit        = true,
    QuestTurnIn     = true,
    AntiAfk         = true,
    AntiAfkInterval = 120,
    -- Extra delay only. The normal cadence comes from the real animation.
    AttackCooldown  = 0,
    FastAttack      = true,
    RemoteAttack    = true,
    HitboxMagnitude = 120,
    WeaponMode      = "Melee",
    MeleeRange      = 50,
    GunRange        = 70,
    FruitRange      = 70,
    AutoBuyStyles   = false,
    AutoSaber       = false,
    AutoSaberTimeout = 90,
    MeleeHover      = 4,
    BringMob        = true,
    BringMobRange   = 60,
    BringMobCount   = 5,
    -- The proven Bring Mobs source searches the same-name pack up to 3000
    -- studs away. Ownership and the BringMobMax cap keep that bounded.
    BringMobSearch  = 3000,
    -- A locally owned extra is snapped into its ring slot once. The body
    -- mover then follows the player; the snap is only the fast first step.
    BringMobSnap    = true,
    BringMobSnapDistance = 4,
    -- Carry the target under the player when this client owns it. A
    -- server-owned target keeps the source's reliable layout instead: the
    -- extras are packed around it and the player walks to the target.
    BringMobCarryTarget = true,
    -- "Lock" is the mover of this script and it is what works. "Game" tries
    -- the body mover of the game instead, but that one is made for the local
    -- character, so a mob is left where it stands (kept for testing only).
    BringMover      = "Lock",
    AutoStats       = false,
    AutoStatTarget  = "Melee",
    AutoStatWait    = 3,
    BigHitbox       = true,
    HitboxSize      = 35,
    HeadHover       = 2,
    AutoAttack      = true,
    AutoStore       = true,
    StoreFruitMin   = 3,
    AutoBuso        = true,
    Aoe             = true,
    AoeRange        = 130,
    BringMobMax     = 10,
    BossFarm        = false,
    BossQuestPriority = true,
    BossRange       = 3000,
    BossLevelWindow = 25,
    WarpClose       = true,
    WarpDistance    = 60,
    HoverHeight     = 7,
    Dodge           = true,
    DodgeRadius     = 14,
    DodgeSpeed      = 90,
    FruitScanRadius = 5000,
    MovementMode    = "Tween",
    MoveSpeed       = 200,
    QuestRetry      = 20,
    TurnInTimeout   = 20,
    QuestSeekTimeout = 30,
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

state = {
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
    lastPrompt    = nil,
    promptAt      = 0,
    turnInSince   = nil,
    questDone     = false,
    questDoneMob  = nil,
    questAsked    = nil,
    questAskedAt  = 0,
    questIndexTry = nil,
    questTried    = {},
    questTryKey   = nil,
    questNpc      = nil,
    questPos      = nil,
    statAt        = 0,
    shopping      = false,
    shopInFlight  = false,
    shopToken     = 0,
    shopUnknown   = {},
    flying        = false,
    whirlpooling  = false,
    questing      = false,
    bringHeld     = setmetatable({}, {__mode = "k"}),
    bringSaved    = setmetatable({}, {__mode = "k"}),
    bringSnapped  = setmetatable({}, {__mode = "k"}),
    bringCarryingTarget = setmetatable({}, {__mode = "k"}),
    bringSlot     = setmetatable({}, {__mode = "k"}),
    bringSlotCount = 0,
    bringMoved    = setmetatable({}, {__mode = "k"}),
    bringIgnored  = setmetatable({}, {__mode = "k"}),
    bringHealth   = setmetatable({}, {__mode = "k"}),
    bringOwned    = setmetatable({}, {__mode = "k"}),
    bringPoint    = nil,
    bringTarget   = nil,
    bringCentre   = nil,
    bringMover    = setmetatable({}, {__mode = "k"}),
    bringMoverId  = setmetatable({}, {__mode = "k"}),
    bringMoverSeq = 0,
    questVerified = false,
    questGaveUp   = false,
    hitsConfirmed = 0,
    hitRemoteHooked = false,
    hitUseFallback = false,
    statsHooked   = false,
    attackSpeed   = 1,
    attackCombo   = 0,
    attackComboAt = 0,
    attackComboCount = 1,
    attackNextCombo = 1,
    attackNextAt  = 0,
    attackWeapon  = nil,
    attackAnimLength = 0.5,
    attackDispatched = false,
    attackHitDispatched = false,
    attackConfirmed = false,
    attackFallback = false,
    attackComboSent = false,
    aoeCount      = 0,
    aoeRequested  = 0,
    aoeConfirmed  = 0,
    gunInput      = nil,
    saberActive   = false,
    saberLockAt   = 0,
    saberProgressAt = 0,
    saberKillHealth = nil,
    saberKillDamaged = false,
    saberKillTarget = nil,
    saberProgress = nil,
    saberStateAt = 0,
    saberFingerprint = "",
    saberSickDone = false,
    saberSonDone = false,
    saberAttemptKey = nil,
    saberAttemptAt = 0,
    saberAttempts = {},
    saberCupRequestAt = 0,
    saberCupGranted = false,
    saberFillRequestAt = 0,
    saberRelicRequestAt = 0,
    saberRelicGranted = false,
    saberPlaceRequestAt = 0,
    saberPlaceAccepted = false,
    turnInFailed  = false,
    turnInFailedAt = 0,
    seekSince     = nil,
    seekGaveUp    = false,
    seekGaveUpAt  = 0,
    afkTimer      = 0,
    afkSign       = 1,
    fruitTools    = nil,
}

runtime.config = CONFIG
runtime.state = state

-- Transient state is reset as one unit. A disabled bot, a character change, a
-- Saber timeout and a fresh enable must never inherit an old attack combo,
-- prompt throttle, burst window or half-finished puzzle action.
runtime.resetSaberState = function()
    local s = runtime.state
    s.saberActive = false
    s.saberTarget = nil
    s.saberAt = nil
    s.saberLockAt = 0
    s.saberProgressAt = 0
    s.saberKillHealth = nil
    s.saberKillDamaged = false
    s.saberKillTarget = nil
    s.saberProgress = nil
    s.saberStateAt = 0
    s.saberFingerprint = ""
    s.saberSickDone = false
    s.saberSonDone = false
    s.saberAttemptKey = nil
    s.saberAttemptAt = 0
    s.saberAttempts = {}
    s.saberCupRequestAt = 0
    s.saberCupGranted = false
    s.saberFillRequestAt = 0
    s.saberRelicRequestAt = 0
    s.saberRelicGranted = false
    s.saberPlaceRequestAt = 0
    s.saberPlaceAccepted = false
end

runtime.stopGunInput = function()
    local tracked = runtime.state.gunInput
    if not tracked then return end
    runtime.state.gunInput = nil
    pcall(function() tracked.input.UserInputState = Enum.UserInputState.End end)
    pcall(function() tracked.changed:Fire() end)
    pcall(function() tracked.changed:Destroy() end)
end

runtime.resetCombatState = function()
    local s = runtime.state
    if runtime.stopGunInput then runtime.stopGunInput() end
    if runtime.hitThread then
        runtime.hitRequest = {stop = true}
        pcall(coroutine.resume, runtime.hitThread)
    end
    runtime.hitSessionId, runtime.hitThread, runtime.hitThreadRemote = nil, nil, nil
    runtime.hitRequest, runtime.hitResult = nil, nil
    runtime.hitHandshakeOk, runtime.hitHandshakeError = false, nil
    s.lastAttack, s.attackNextAt = 0, 0
    s.attackCombo, s.attackComboAt, s.attackComboCount = 0, 0, 1
    s.attackNextCombo, s.attackWeapon = 1, nil
    s.attackAnimLength = 0.5
    s.attackDispatched, s.attackHitDispatched = false, false
    s.attackConfirmed, s.attackFallback, s.attackComboSent = false, false, false
    s.aoeCount, s.aoeRequested, s.aoeConfirmed = 0, 0, 0
    s.hitsConfirmed = 0
    s.lastHitAt, s.lastHitMob = nil, nil
    s.combatUtil, s.combatUtilMod = nil, nil
    s.netModule, s.netModuleInstance = nil, nil
    s.hitRemoteCache, s.attackRemoteCache = nil, nil
    s.hitUseFallback = false
end

runtime.resetTransient = function()
    runtime.resetSaberState()
    runtime.resetCombatState()
    local s = runtime.state
    s.lastPrompt, s.promptAt = nil, 0
    s.autoBurst, s.autoBurstCd = 0, 0
    s.questing = false
end

local grabbedFruits = setmetatable({}, {__mode = "k"})

local function dbg(msg)
    if msg == runtime.state.debugMsg then
        runtime.state.debugCount = runtime.state.debugCount + 1
        runtime.state.debugLine = msg .. " (x" .. runtime.state.debugCount .. ")"
    else
        runtime.state.debugMsg = msg
        runtime.state.debugCount = 1
        runtime.state.debugLine = msg
    end
    if runtime.config.Debug and msg ~= runtime.state.lastPrinted then
        runtime.state.lastPrinted = msg
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
local function startsWith(s, p) return s:sub(1, #p) == p end
local function sameName(a, b) return a:lower() == b:lower() end

local function anchorOf(obj)
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

local function readNumber(obj)
    if not obj then return nil end
    local ok, value = pcall(function() return tonumber(obj.Value) end)
    if ok then return value end
    return nil
end

local function getMyLevel()
    local data = LocalPlayer:FindFirstChild("Data")
    local level = data and data:FindFirstChild("Level")
    local value = readNumber(level)
    if value then return math.floor(value) end
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local alt = stats and stats:FindFirstChild("Level")
    value = readNumber(alt)
    if value then return math.floor(value) end
    return 1
end

local function toolKind(tool)
    local tip = tool.ToolTip
    if type(tip) == "string" and tip ~= "" then return tip:lower() end
    return nil
end

local function isFruit(t)
    if t.Name:lower():find("fruit", 1, true) then return true end
    -- the fruits of the game carry their kind in the tooltip, not in the name:
    -- a tool named "Magma" with the tooltip "Fruit" is a fruit all the same
    return toolKind(t) == "fruit"
end

local WEAPON_GROUPS = {
    Melee = {
        "combat", "melee", "style", "fist", "black leg", "electro", "water kung fu",
        "dragon claw", "superhuman", "death step", "sharkman karate", "electric claw",
        "dragon talon", "godhuman", "sanguine art"
    },
    Sword = {
        "sword", "cutlass", "saber", "katana", "blade", "claymore", "greatsword",
        "dagger", "scythe", "triple katana", "pole", "pipe", "bisento", "yoru"
    },
    Gun = {
        "gun", "flintlock", "musket", "cannon", "pistol", "revolver", "shotgun",
        "rifle", "bow", "crossbow", "slingshot", "kabucha"
    },
}

local function isGun(tool)
    if toolKind(tool) == "gun" then return true end
    local n = tool.Name:lower()
    for _, w in ipairs(WEAPON_GROUPS.Gun) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

local function weaponRank(tool)
    local n = tool.Name:lower()
    local group = WEAPON_GROUPS[runtime.config.WeaponMode] or WEAPON_GROUPS.Melee
    for i, w in ipairs(group) do
        if n:find(w, 1, true) then return i end
    end
    return nil
end

local function matchesMode(tool)
    local mode = runtime.config.WeaponMode
    if mode == "Fruit" then
        return toolKind(tool) == "fruit" or isFruit(tool)
    end
    local kind = toolKind(tool)
    if kind then
        if mode == "Melee" and kind == "melee" then return true end
        if mode == "Sword" and kind == "sword" then return true end
        if mode == "Gun" and kind == "gun" then return true end
    end
    return weaponRank(tool) ~= nil
end

local function fallbackRank(tool)
    local kind = toolKind(tool)
    if kind == "sword" then return 1 end
    if kind == "melee" then return 2 end
    if kind == "gun" then return 3 end
    local n = tool.Name:lower()
    for _, w in ipairs(WEAPON_GROUPS.Sword) do
        if n:find(w, 1, true) then return 1 end
    end
    for _, w in ipairs(WEAPON_GROUPS.Melee) do
        if n:find(w, 1, true) then return 2 end
    end
    return 4
end

local function attackRange(tool)
    if not tool then return runtime.config.MeleeRange end
    if isGun(tool) then return runtime.config.GunRange end
    if isFruit(tool) then return runtime.config.FruitRange or runtime.config.GunRange end
    return runtime.config.MeleeRange
end

local function equipWeapon()
    local char = LocalPlayer.Character
    if not char then return nil end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local hum = getHumanoid()
    if not hum then return nil end

    -- The game starts its basic combo at one again whenever another weapon is
    -- equipped. The script keeps the same counter so RegisterAttack carries
    -- the index the server expects.
    local function remember(tool)
        if tool and runtime.state.attackWeapon ~= tool then
            runtime.state.attackWeapon = tool
            runtime.state.attackCombo = 0
            runtime.state.attackComboAt = 0
            runtime.state.attackNextAt = 0
        end
        return tool
    end

    local function equip(item)
        if tick() < runtime.state.equipRetryAt then return nil end
        pcall(function() hum:EquipTool(item) end)
        
        if item.Parent ~= char then
            pcall(function()
                local combat = backpack and backpack:FindFirstChild("Combat")
                local equipRemote = (combat and combat:FindFirstChild("EquipEvent"))
                    or item:FindFirstChild("EquipEvent")
                    or (backpack and backpack:FindFirstChild(item.Name)
                        and backpack[item.Name]:FindFirstChild("EquipEvent"))
                if equipRemote then
                    equipRemote:FireServer(false)
                end
            end)
        end
        -- the plain reparent is what really equips a tool on the client when
        -- the humanoid call of this build did not take it
        if item.Parent ~= char then
            pcall(function() item.Parent = char end)
        end
        
        if item.Parent ~= char then
            runtime.state.equipRetryAt = tick() + 2
            dbg("Could not equip " .. item.Name)
            return nil
        end
        return item
    end

    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and matchesMode(equipped) then return remember(equipped) end

    local carriers = {char}
    if backpack then table.insert(carriers, backpack) end

    local weapons, fallbacks, order = {}, {}, 0
    for _, container in ipairs(carriers) do
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                order = order + 1
                if runtime.config.WeaponMode == "Fruit" then
                    if isFruit(item) then
                        table.insert(weapons, {tool = item, rank = 1, order = order})
                    end
                elseif not isFruit(item) then
                    local rank = weaponRank(item)
                    if matchesMode(item) then
                        table.insert(weapons, {tool = item, rank = rank or 99, order = order})
                    else
                        table.insert(fallbacks, item)
                    end
                end
            end
        end
    end

    table.sort(weapons, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.order < b.order
    end)

    for _, entry in ipairs(weapons) do
        if entry.tool == equipped then return remember(equipped) end
        local weapon = equip(entry.tool)
        if weapon then return remember(weapon) end
    end

    if equipped and not isFruit(equipped) then return remember(equipped) end

    table.sort(fallbacks, function(a, b)
        local ra, rb = fallbackRank(a), fallbackRank(b)
        if ra ~= rb then return ra < rb end
        return a.Name < b.Name
    end)
    local best = fallbacks[1]
    if best then
        local tool = equip(best)
        if tool then return remember(tool) end
    end

    return remember(equipped)
end

-- A mob that was made big for the swing is put back the moment the bot turns
-- to another mob: the size and the collide of the part are only the client's,
-- but a mob left blown up on screen is a bug the player can see.
local function restoreHitbox()
    local part = runtime.state.hitboxPart
    if not part then return end
    runtime.state.hitboxPart = nil
    pcall(function() part.Size = runtime.state.hitboxOrigSize end)
    pcall(function() part.CanCollide = runtime.state.hitboxOrigCollide end)
end

local function enlargeHitbox(target)
    local anchor = anchorOf(target)
    if not anchor or not anchor.Size then return end
    if runtime.state.hitboxPart and runtime.state.hitboxPart ~= anchor then restoreHitbox() end
    local size = runtime.config.HitboxSize or 16
    if anchor.Size.X >= size then return end
    runtime.state.hitboxAt = tick()
    runtime.state.hitboxOrigSize = anchor.Size
    runtime.state.hitboxOrigCollide = anchor.CanCollide
    runtime.state.hitboxPart = anchor
    pcall(function() anchor.Size = Vector3.new(size, size, size) end)
    pcall(function() anchor.CanCollide = false end)
end

-- ================= GAME QUEST DATA =================
local gameQuests
local gameGuideQuests
local gameLevelQuests
local gameGuideNames
local gameQuestIndexes
local gameQuestCache, gameQuestCacheAt

local QUEST_SKIP = {
    BartiloQuest = true,
    Trainees = true,
    MarineQuest = true,
    CitizenQuest = true,
}

local function taskMob(task)
    if type(task) ~= "table" then return nil, 0 end
    local mob, count
    for name, n in pairs(task) do
        if type(n) == "number" and (mob == nil or n > count or (n == count and name < mob)) then
            mob, count = name, n
        end
    end
    return mob, count or 0
end

local function loadGameQuests()
    local okQuests, quests = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Quests", 5))
    end)
    if not okQuests or type(quests) ~= "table" then return nil end

    local okGuide, guide = pcall(function()
        return require(ReplicatedStorage:WaitForChild("GuideModule", 5))
    end)
    local npcList = nil
    if okGuide and type(guide) == "table" and type(guide.Data) == "table" then
        npcList = guide.Data.NPCList
    end
    if type(npcList) ~= "table" then npcList = nil end

    local data = {quests = {}, guide = {}, levels = {}, guideNames = {}, indexes = {}, byKey = {}}

    for questName, questSet in pairs(quests) do
        if type(questSet) == "table" and not QUEST_SKIP[questName] then
            for index, quest in pairs(questSet) do
                if type(quest) == "table" then
                    local mob, count = taskMob(quest.Task)
                    if mob then
                        local req = quest.LevelReq
                        local level = 0
                        if type(req) == "number" then level = req end
                        local entry = {
                            name = questName,
                            index = index,
                            mob = mob,
                            count = count,
                            level = level,
                        }
                        table.insert(data.quests, entry)
                        data.byKey[questName .. "#" .. tostring(index)] = entry
                        if type(req) == "number" then
                            table.insert(data.levels, entry)
                        end
                        local ids = data.indexes[questName]
                        if not ids then
                            ids = {}
                            data.indexes[questName] = ids
                        end
                        table.insert(ids, {index = index, level = level})
                    end
                end
            end
        end
    end
    if #data.quests == 0 then return nil end

    if npcList then
        for npcKey, npc in pairs(npcList) do
            if type(npc) == "table" and type(npc.InternalQuestName) == "string"
                and type(npc.Levels) == "table" and not QUEST_SKIP[npc.InternalQuestName] then
                local questSet = quests[npc.InternalQuestName]
                local known = false
                for index, level in pairs(npc.Levels) do
                    local quest = questSet and questSet[index]
                    if type(quest) == "table" and type(level) == "number" then
                        local mob, count = taskMob(quest.Task)
                        if mob then
                            local need = quest.LevelReq
                            if type(need) ~= "number" or need < level then need = level end
                            table.insert(data.guide, {
                                name = npc.InternalQuestName,
                                index = index,
                                mob = mob,
                                count = count,
                                level = need,
                                npc = npc.NPCName or npcKey,
                                pos = npc.Position,
                            })
                            for _, id in ipairs(data.indexes[npc.InternalQuestName] or {}) do
                                if id.index == index and id.level < need then id.level = need end
                            end
                            local base = data.byKey[npc.InternalQuestName .. "#" .. tostring(index)]
                            if base then
                                base.npc = npc.NPCName or npcKey
                                base.pos = npc.Position
                            end
                            known = true
                        end
                    end
                end
                if known then data.guideNames[npc.InternalQuestName] = true end
            end
        end
    end
    for _, ids in pairs(data.indexes) do
        table.sort(ids, function(a, b) return a.index < b.index end)
    end
    local function byLevel(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.index < b.index
    end
    table.sort(data.levels, byLevel)
    table.sort(data.guide, byLevel)
    return data
end

-- ================= QUEST =================
local function pickQuest(list, level, only, bossAllowedOverride)
    local best, fallback, bossQ, bestLevel, fallbackLevel, bossLevel
    -- A boss quest that just could not be finished is left alone for a while,
    -- or the bot would chase the same boss for ever. With the boss farm off
    -- boss quests are not picked at all: the normal mob quest is used instead.
    local bossAllowed = bossAllowedOverride
    if bossAllowed == nil then
        bossAllowed = runtime.config.BossFarm and runtime.config.BossQuestPriority ~= false
            and (not runtime.state.bossQuestCd or tick() > runtime.state.bossQuestCd)
    end
    local bossWindow = runtime.config.BossLevelWindow or 25
    for _, q in ipairs(list) do
        if type(q.level) == "number" and q.level <= level and (not only or only[q.name]) then
            if bossNameIs(q.mob or "") then
                -- A boss quest is only taken when the boss itself is close to
                -- the player's level, not just when the quest is unlocked.
                local mobLevel = bossLevelOf and bossLevelOf(q.mob)
                local bossOk = bossAllowed and (mobLevel == nil
                    or math.abs(mobLevel - level) <= bossWindow)
                if bossOk and (bossLevel == nil or q.level > bossLevel) then
                    bossQ, bossLevel = q, q.level
                end
            elseif (q.count or 0) > 1 then
                if bestLevel == nil or q.level > bestLevel then
                    best, bestLevel = q, q.level
                end
            elseif (q.count or 0) >= 1 then
                if fallbackLevel == nil or q.level > fallbackLevel then
                    fallback, fallbackLevel = q, q.level
                end
            end
        end
    end
    return bossQ or best or fallback
end

local function gameQuestFor(level)
    -- The chosen quest depends on more than the level: turning boss farming on,
    -- changing its priority or waiting out the boss cooldown must invalidate
    -- the old answer as well.
    local now = tick()
    local bossReady = runtime.config.BossFarm
        and runtime.config.BossQuestPriority ~= false
        and (not runtime.state.bossQuestCd or now > runtime.state.bossQuestCd)
    local cacheKey = tostring(level) .. ":" .. (bossReady and "1" or "0")
        .. ":" .. tostring(runtime.config.BossQuestPriority)
        .. ":" .. tostring(runtime.config.BossLevelWindow)
    if gameQuestCacheAt == cacheKey then return gameQuestCache end
    local best = nil
    if gameGuideQuests and #gameGuideQuests > 0 then
        best = pickQuest(gameGuideQuests, level, nil, bossReady)
        if not best and gameLevelQuests and #gameLevelQuests > 0 then
            best = pickQuest(gameLevelQuests, level, gameGuideNames, bossReady)
        end
    elseif gameLevelQuests and #gameLevelQuests > 0 then
        best = pickQuest(gameLevelQuests, level, nil, bossReady)
    end
    gameQuestCache, gameQuestCacheAt = best, cacheKey
    return best
end

local function questFor(level)
    local best = gameQuestFor(level)
    if best then
        return {name = best.name, index = best.index, mob = best.mob,
                pos = best.pos, npc = best.npc}
    end
    for _, q in ipairs(runtime.config.QuestList) do
        if level >= q[1] and level <= q[2] then
            return {name = q[3], index = q[4], mob = q[5]}
        end
    end
    return nil
end

local function questKey(q) return q.name .. "#" .. q.index end

local function nextQuestIndex(q, level, tried)
    local ids = gameQuestIndexes and gameQuestIndexes[q.name]
    if not ids or #ids == 0 then
        ids = {{index = 1, level = 0}, {index = 2, level = 0}}
    end
    local best, bestLevel = nil, nil
    for _, id in ipairs(ids) do
        if not tried[id.index] then
            local lv = id.level or 0
            if lv <= level then
                if bestLevel == nil or lv > bestLevel then
                    best, bestLevel = id.index, lv
                end
            end
        end
    end
    return best
end

local OTHER_MOBS = {"Bandit Captain", "Desert Bandit Captain"}
local KNOWN_MOBS = {}
local KNOWN_MOB_FORMS = {}
local KNOWN_MOB_PATTERNS = {}
local KNOWN_MOB_LOWER = {}

local function pluralForms(name)
    local base = name:lower()
    local forms = {base, base .. "s"}
    if base:sub(-3) == "man" then
        table.insert(forms, base:sub(1, -4) .. "men")
    end
    return forms
end

local function refreshKnownMobs()
    local seen, list = {}, {}
    local function add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(list, name)
        end
    end
    for _, q in ipairs(runtime.config.QuestList) do add(q[5]) end
    for _, m in ipairs(OTHER_MOBS) do add(m) end
    for _, q in ipairs(gameQuests or {}) do add(q.mob) end
    table.sort(list, function(a, b)
        if #a ~= #b then return #a > #b end
        return a < b
    end)
    local forms, patterns, lower = {}, {}, {}
    for _, name in ipairs(list) do
        local raw = pluralForms(name)
        local escaped = {}
        for _, variant in ipairs(raw) do
            table.insert(escaped, (variant:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")))
        end
        forms[name] = raw
        patterns[name] = escaped
        table.insert(lower, name:lower())
    end
    KNOWN_MOBS = list
    KNOWN_MOB_FORMS = forms
    KNOWN_MOB_PATTERNS = patterns
    KNOWN_MOB_LOWER = lower
end
refreshKnownMobs()

local function containsWord(text, word)
    local t = text:lower()
    local forms = KNOWN_MOB_FORMS[word]
    local patterns = KNOWN_MOB_PATTERNS[word]
    if not forms then
        forms = pluralForms(word)
        patterns = {}
        for _, variant in ipairs(forms) do
            table.insert(patterns, (variant:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")))
        end
    end
    for i, variant in ipairs(forms) do
        if t:find(variant, 1, true) then
            if t:find("%f[%w]" .. patterns[i] .. "%f[^%w]") then return true end
        end
    end
    return false
end

local function isCompoundMob(name, wanted)
    local key = name:lower()
    local want = wanted:lower()
    for _, mob in ipairs(KNOWN_MOB_LOWER) do
        if #mob > #want and key:find(mob, 1, true) then return true end
    end
    return false
end

local function mobInText(text)
    local best
    for _, name in ipairs(KNOWN_MOBS) do
        if containsWord(text, name) and (not best or #name > #best) then best = name end
    end
    return best
end

local function mobAtStart(text)
    local t = text:lower():gsub("^%s+", "")
    for _, name in ipairs(KNOWN_MOBS) do
        for _, variant in ipairs(KNOWN_MOB_FORMS[name]) do
            if t:sub(1, #variant) == variant then
                local rest = t:sub(#variant + 1)
                if rest == "" or rest:match("^[%s,%.%+]") then return name end
            end
        end
    end
    return nil
end

local function mobAtEnd(text)
    local t = text:lower():gsub("[%s,%.%+:]+$", "")
    for _, name in ipairs(KNOWN_MOBS) do
        for _, variant in ipairs(KNOWN_MOB_FORMS[name]) do
            if #t >= #variant and t:sub(-#variant) == variant then
                local before = t:sub(1, #t - #variant)
                if before == "" or before:match("[%s,%.%+]$") then return name end
            end
        end
    end
    return nil
end

table.insert(runtime.tasks, task.spawn(function()
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    local data = loadGameQuests()
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    if data then
        gameQuests = data.quests
        gameGuideQuests = data.guide
        gameLevelQuests = data.levels
        gameGuideNames = data.guideNames
        gameQuestIndexes = data.indexes
        gameQuestCache, gameQuestCacheAt = nil, nil
        runtime.state.questTried = {}
        runtime.state.questTryKey = nil
        runtime.state.questIndexTry = nil
        refreshKnownMobs()
        dbg("Game quest data: " .. #gameQuests .. " quests")
    end
end))

local CONNECTORS = {["and"] = true, ["then"] = true, ["plus"] = true}

local function parseProgress(text)
    local out = {}
    for pos, frac in text:gmatch("()(%d+%s*/%s*%d+)") do
        local count, total = frac:match("(%d+)%s*/%s*(%d+)")
        local after = text:sub(pos + #frac)
        local before = text:sub(1, pos - 1)

        local mob
        local lead = after:lower():match("^%s*(%a+)") or ""
        if not CONNECTORS[lead] then mob = mobAtStart(after) end
        if not mob then mob = mobAtEnd(before) end

        if mob then
            out[mob] = {count = tonumber(count), total = tonumber(total)}
        end
    end
    return out
end

local function parseRequired(text)
    local out = {}
    for num, rest in text:gmatch("(%d+)%s+([%a%s']+)") do
        local mob = mobAtStart(rest)
        if mob then out[mob] = {count = 0, total = tonumber(num), remaining = true} end
    end
    if next(out) == nil then
        for name, num in text:gmatch("([%a%s']+)%s*:%s*(%d+)") do
            local mob = mobInText(name)
            if mob then out[mob] = {count = 0, total = tonumber(num), remaining = true} end
        end
    end
    return out
end

local questRemote, questRemoteState, questRemoteHooked = nil, nil, false

local function hookQuestRemote()
    -- the guard lives in the callback below
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local q = remotes and remotes:FindFirstChild("QuestUpdate")
    if not q then return nil end
    if questRemoteHooked and runtime.questHookRemote == q then return q end
    if runtime.questHookConnection then
        pcall(function() runtime.questHookConnection:Disconnect() end)
        runtime.questHookConnection = nil
        questRemoteHooked = false
    end
    questRemote = q
    if not q.OnClientEvent then return q end
    local connection
    local ok = pcall(function()
        connection = q.OnClientEvent:Connect(function(data, update)
            if not runtime.running or FarmRuntime.current ~= runtime then return end
            if data == nil then
                questRemoteState = nil
                runtime.state.questDone = false
                runtime.state.questDoneMob = nil
                runtime.state.currentQuest = nil
                runtime.state.questSentAt = 0
                local hadQuest = runtime.state.questVerified
                runtime.state.questAsked = nil
                runtime.state.questVerified = false
                runtime.state.questGaveUp = false
                runtime.state.questTryKey = nil
                runtime.state.questNpc = nil
                if hadQuest then
                    runtime.state.questTried = {}
                    runtime.state.questIndexTry = nil
                end
                dbg("Quest cleared by the game")
                return
            end
            if type(data) ~= "table" then
                dbg("The game sent a quest update that is not a table")
                return
            end
            questRemoteState = data
            if type(update) == "table" and update.Context == "Complete" then
                dbg("Quest progress complete: " .. tostring(update.Name))
            end
            runtime.state.questVerified = true
            runtime.state.questGaveUp = false
            if runtime.state.questAsked and data.InternalQuestName ~= runtime.state.questAsked then
                dbg("The game gave us " .. tostring(data.InternalQuestName)
                    .. " instead of " .. tostring(runtime.state.questAsked))
            else
                runtime.state.questTried = {}
                runtime.state.questIndexTry = nil
            end
        end)
    end)
    if ok and connection then
        questRemoteHooked = true
        runtime.questHookRemote = q
        runtime.questHookConnection = connection
        table.insert(runtime.hookConnections or {}, connection)
    end
    return q
end

local function remoteQuestInfo()
    local s = questRemoteState
    if not s or not s.Info then return nil end
    local task = s.Info.Task or {}
    local progress = s.Progress or {}
    local mobs, any = {}, false
    for mob, need in pairs(task) do
        any = true
        mobs[mob] = {count = progress[mob] or 0, total = need, remaining = false}
    end
    if not any then return nil end
    local target, worst = nil, 2
    local names = {}
    for mob in pairs(mobs) do table.insert(names, mob) end
    table.sort(names)
    for _, mob in ipairs(names) do
        local prog = mobs[mob]
        local ratio = prog.total > 0 and (prog.count / prog.total) or 1
        if ratio < 1 then
            if ratio < worst then worst, target = ratio, mob end
        end
    end
    local complete = true
    for _, prog in pairs(mobs) do
        if prog.count < prog.total then complete = false break end
    end
    return {
        mobs = mobs,
        mentioned = s.Info.Name,
        target = target,
        complete = complete,
        confirmed = true,
        questName = s.InternalQuestName,
    }
end

local function hookHitRemote()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    local hit = net and net:FindFirstChild("RE/ReceivedHit")
    if not hit or not hit.OnClientEvent then return end
    if runtime.state.hitRemoteHooked and runtime.hitHookRemote == hit then return end
    if runtime.hitHookConnection then
        pcall(function() runtime.hitHookConnection:Disconnect() end)
        runtime.hitHookConnection = nil
        runtime.state.hitRemoteHooked = false
    end
    local connection
    local ok = pcall(function()
        connection = hit.OnClientEvent:Connect(function(player, mob, kind, weapon, part)
            if not runtime.running or FarmRuntime.current ~= runtime then return end
            runtime.state.hitsConfirmed = runtime.state.hitsConfirmed + 1
            runtime.state.lastHitAt = tick()
            if mob then runtime.state.lastHitMob = mob.Name end
        end)
    end)
    if ok and connection then
        runtime.state.hitRemoteHooked = true
        runtime.hitHookRemote = hit
        runtime.hitHookConnection = connection
        table.insert(runtime.hookConnections or {}, connection)
    end
end

local function hookStatsRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local stats = remotes and remotes:FindFirstChild("Stats")
    if not stats or not stats.OnClientEvent then return end
    if runtime.state.statsHooked and runtime.statsHookRemote == stats then return end
    if runtime.statsHookConnection then
        pcall(function() runtime.statsHookConnection:Disconnect() end)
        runtime.statsHookConnection = nil
        runtime.state.statsHooked = false
    end
    local connection
    local ok = pcall(function()
        connection = stats.OnClientEvent:Connect(function(player, key, value)
            if not runtime.running or FarmRuntime.current ~= runtime then return end
            if key == "AttackSpeedMultiplier" and type(value) == "number" and value > 0 then
                runtime.state.attackSpeed = value
            end
        end)
    end)
    if ok and connection then
        runtime.state.statsHooked = true
        runtime.statsHookRemote = stats
        runtime.statsHookConnection = connection
        table.insert(runtime.hookConnections or {}, connection)
    end
end

local function questProgressText()
    local s = questRemoteState
    if not s or not s.Info then return tostring(runtime.state.currentQuest) end
    local task = s.Info.Task or {}
    local progress = s.Progress or {}
    local parts = {}
    for mob, need in pairs(task) do
        table.insert(parts, mob .. " " .. tostring(progress[mob] or 0) .. "/" .. tostring(need))
    end
    if #parts == 0 then return tostring(s.InternalQuestName or runtime.state.currentQuest) end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function questPanelGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local mainFrame = pg:FindFirstChild("Main")
    local panel = mainFrame and mainFrame:FindFirstChild("Quest")
    if panel and panel.Visible then return panel end
    local tracked = pg:FindFirstChild("TrackedQuestFrame")
    if tracked then
        local on = false
        pcall(function()
            on = (tracked:IsA("ScreenGui") and tracked.Enabled)
                or (tracked:IsA("GuiObject") and tracked.Visible)
        end)
        if on then
            local frame = tracked:FindFirstChild("Frame")
            return frame or tracked
        end
    end
    return panel
end

local function guiShown(gui)
    if gui == nil then return false end
    local ok, v = pcall(function() return gui.Visible end)
    if ok and v ~= nil then return v end
    local ok2, e = pcall(function() return gui.Enabled end)
    if ok2 and e ~= nil then return e end
    return true
end

local function questPanelInfo()
    local qg = questPanelGui()
    if not guiShown(qg) then return nil end

    local texts = {}
    for _, d in ipairs(qg:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text and d.Text ~= "" then
            table.insert(texts, d.Text)
        end
    end
    if #texts == 0 then return nil end

    local mobs, mentioned, saysComplete, saysReturn = {}, nil, false, false
    for _, t in ipairs(texts) do
        local found = parseProgress(t)
        for mob, prog in pairs(found) do mobs[mob] = prog end
        for mob, prog in pairs(parseRequired(t)) do
            if not found[mob] and not mobs[mob] then mobs[mob] = prog end
        end
        local m = mobInText(t)
        local lower = t:lower()
        local giverText = lower:find("quest giver", 1, true) ~= nil
        if m and not giverText and (not mentioned or #m > #mentioned) then mentioned = m end
        if lower:find("complete", 1, true) then saysComplete = true end
        if lower:find("return to", 1, true) then saysReturn = true end
    end
    if not mentioned and not saysComplete and not saysReturn and next(mobs) == nil then return nil end

    local target, worst = nil, 2
    local allDone = next(mobs) ~= nil
    local names = {}
    for mob in pairs(mobs) do table.insert(names, mob) end
    table.sort(names)
    for _, mob in ipairs(names) do
        local prog = mobs[mob]
        local ratio
        if prog.remaining then
            ratio = prog.total > 0 and 0 or 1
        else
            ratio = prog.total > 0 and (prog.count / prog.total) or 0
        end
        if ratio < 1 then allDone = false end
        if ratio < worst then worst, target = ratio, mob end
    end
    if next(mobs) == nil then target = mentioned end

    local complete = saysComplete
    if next(mobs) ~= nil then complete = allDone end
    if saysReturn and next(mobs) == nil then complete = true end

    if target and mobs[target] then mentioned = target end

    return {
        mobs = mobs,
        mentioned = mentioned,
        target = target,
        complete = complete,
        confirmed = next(mobs) ~= nil or mentioned ~= nil or saysReturn or saysComplete,
    }
end

local function tryAcceptQuest(info)
    local now = tick()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch

    if info and info.confirmed then
        runtime.state.questSeenUntil = now + 1
        return
    end
    if now < (runtime.state.questSeenUntil or 0) then return end
    if now - runtime.state.lastQuestTry < 2 then return end
    if runtime.state.questDone then return end

    local q = questFor(getMyLevel())
    if not q then
        dbg("No quest bracket for this level")
        return
    end

    local key = questKey(q) .. "@" .. tostring(getMyLevel())
    if runtime.state.questTryKey ~= key then
        runtime.state.questTryKey = key
        runtime.state.questTried = {}
        runtime.state.questIndexTry = nil
        runtime.state.questGaveUp = false
    end

    if runtime.state.questAsked and not runtime.state.questVerified then
        if now - runtime.state.questAskedAt < 6 then return end
        local nextIndex = nextQuestIndex(q, getMyLevel(), runtime.state.questTried)
        if nextIndex then
            dbg("The game did not take " .. runtime.state.questAsked .. " #" .. tostring(runtime.state.questIndexTry))
            runtime.state.questIndexTry = nextIndex
            runtime.state.currentQuest = nil
            runtime.state.questAskedAt = now
        else
            dbg("The game took no quest of this level, asking a giver")
            runtime.state.questGaveUp = true
            runtime.state.currentQuest = nil
            return
        end
    end
    if runtime.state.questGaveUp then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then dbg("CommF_ remote missing"); return end

    local index = runtime.state.questIndexTry or q.index

    local spawnOk = pcall(function() commF:InvokeServer("SetLastSpawnPoint", "Town") end)
    if not spawnOk or not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return end

    if questRemoteState then
        local abandonOk = pcall(function() commF:InvokeServer("AbandonQuest") end)
        if not abandonOk or not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return end
    end
    local ok, err = pcall(function() commF:InvokeServer("StartQuest", q.name, index) end)
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return end
    if not ok then
        dbg("Quest FAIL: " .. tostring(err))
        return
    end
    runtime.state.currentQuest = q.name .. "#" .. tostring(index)
    runtime.state.questSentAt = tick()
    runtime.state.lastQuestTry = now
    runtime.state.questAsked = q.name
    if bossNameIs(q.mob or "") then
        runtime.state.bossQuestName = q.mob
        runtime.state.bossQuestUntil = tick() + 180
    else
        runtime.state.bossQuestName, runtime.state.bossQuestUntil = nil, nil
    end
    runtime.state.questNpc = q.npc
    runtime.state.questPos = q.pos
    runtime.state.questAskedAt = tick()
    runtime.state.questVerified = false
    runtime.state.questIndexTry = index
    runtime.state.questTried[index] = true
    dbg("Quest sent: " .. q.name .. " #" .. index)
end

local giverCache, giverCacheAt = {}, -999

local function questGivers()
    local now = tick()
    if now - giverCacheAt < 2 then return giverCache end
    local list = {}
    local function collect(container, depth)
        for _, obj in ipairs(container:GetChildren()) do
            local n = obj.Name:lower()
            if obj:IsA("Model") then
                if n:find("quest", 1, true) then
                    table.insert(list, obj)
                elseif depth > 0 and n:find("npc", 1, true) then
                    collect(obj, depth - 1)
                end
            elseif obj:IsA("Folder") and depth > 0 then
                if n:find("npc", 1, true) or n:find("quest", 1, true) then
                    collect(obj, depth - 1)
                end
            end
        end
    end
    collect(Workspace, 2)
    giverCache, giverCacheAt = list, now
    return list
end

local function pickQuestGiver(mobName, npcName)
    local root = getRoot()
    if not root then return nil end
    local best, bestD, exact, exactD, named, namedD = nil, math.huge, nil, math.huge, nil, math.huge
    for _, npc in ipairs(questGivers()) do
        local anchor = anchorOf(npc)
        if anchor then
            local d = (root.Position - anchor.Position).Magnitude
            local n = npc.Name:lower()
            if npcName then
                local fits = true
                for word in npcName:lower():gmatch("%a+") do
                    if not n:find(word, 1, true) then fits = false break end
                end
                if fits and d < namedD then named, namedD = npc, d end
            end
            if mobName then
                if containsWord(n, mobName) and not isCompoundMob(n, mobName) then
                    if d < exactD then exact, exactD = npc, d end
                end
            elseif d < bestD then
                best, bestD = npc, d
            end
        end
    end
    if npcName and not named then
        dbg("No giver named " .. tostring(npcName) .. " found")
    end
    return named or exact or best
end

local function storageNpc()
    local best, bestD = nil, math.huge
    local root = getRoot()
    if not root then return nil end
    local function collect(container, depth)
        if depth > 2 then return end
        for _, obj in ipairs(container:GetChildren()) do
            local n = obj.Name:lower()
            if obj:IsA("Model") or obj:IsA("BasePart") then
                if n:find("storage", 1, true) or n:find("storer", 1, true)
                    or n:find("fruit dealer", 1, true) then
                    local anchor = anchorOf(obj)
                    if anchor then
                        local d = (root.Position - anchor.Position).Magnitude
                        if d < bestD then best, bestD = obj, d end
                    end
                else
                    collect(obj, depth + 1)
                end
            end
        end
    end
    collect(Workspace, 0)
    return best
end

local function promptOf(obj)
    local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
    if prompt then return prompt end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

local function interactWith(obj, prompt)
    prompt = prompt or promptOf(obj)
    if not prompt then return false end
    local now = tick()
    if runtime.state.lastPrompt == prompt and now - runtime.state.promptAt < 3 then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    runtime.state.lastPrompt, runtime.state.promptAt = prompt, now
    if fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function()
            prompt:InputHoldBegin()
            table.insert(runtime.tasks, task.spawn(function()
                task.wait(prompt.HoldDuration or 1)
                if runtime.isCurrent() and runtime.characterEpoch == epoch
                    and LocalPlayer.Character == char then
                    pcall(function() prompt:InputHoldEnd() end)
                end
            end))
        end)
    end
    return true
end

-- ================= ENEMIES =================
local function mobKey(name)
    local base = name
    base = base:gsub("^Lv%.%s*%d+%s*", "")
    local cut = base:find("%s*%[")
    if cut then base = base:sub(1, cut - 1) end
    cut = base:find("%s*%(")
    if cut then base = base:sub(1, cut - 1) end
    base = base:gsub("^%s+", ""):gsub("%s+$", "")
    return base
end

local function startsWithCI(a, b) return a:lower():sub(1, #b) == b:lower() end

local function pickBest(candidates, mobName, origin)
    local exact, exactD = nil, math.huge
    local loose, looseD = nil, math.huge
    for _, obj in ipairs(candidates) do
        local anchor = anchorOf(obj)
        if anchor then
            local d = (origin.Position - anchor.Position).Magnitude
            local display = nil
            pcall(function() display = obj:GetAttribute("DisplayName") end)
            local key = mobKey(display or obj.Name)
            if not mobName then
                if d < exactD then exact, exactD = obj, d end
            elseif sameName(key, mobName) then
                if d < exactD then exact, exactD = obj, d end
            elseif startsWithCI(key, mobName) and not isCompoundMob(key, mobName) then
                if d < looseD then loose, looseD = obj, d end
            end
        end
    end
    return exact or loose
end

local function findEnemiesFolder()
    local direct = Workspace:FindFirstChild("Enemies")
    if direct then return direct end
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            local nested = child:FindFirstChild("Enemies")
            if nested then return nested end
        end
    end
    return nil
end

local stuckTargets = setmetatable({}, {__mode = "k"})
local enemyCache, enemyCacheAt = {}, -999

local function collectEnemies(now)
    if now - enemyCacheAt < 0.2 then return enemyCache end
    local list = {}
    local folder = findEnemiesFolder()
    if folder then
        for _, e in ipairs(folder:GetChildren()) do
            local hum = e:FindFirstChildOfClass("Humanoid")
            local stuck = stuckTargets[e]
            if hum and hum.Health > 0 and (not stuck or stuck < now)
                and not e:FindFirstChild("Ignored") then
                table.insert(list, e)
            end
        end
    else
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model") and not child.Name:lower():find("quest", 1, true) then
                local hum = child:FindFirstChildOfClass("Humanoid")
                local stuck = stuckTargets[child]
                if hum and hum.Health > 0 and (not stuck or stuck < now)
                    and not child:FindFirstChild("Ignored") then
                    table.insert(list, child)
                end
            end
        end
    end
    enemyCache, enemyCacheAt = list, now
    return list
end

-- The bosses of the game (the list BananaHub farms with). With the boss farm
-- on, the nearest one alive is taken over the quest mob: a boss gives far
-- more experience than a normal mob.
local BOSS_NAMES = {
    -- the bosses of the wiki list (First, Second and Third Sea)
    ["the gorilla king"] = true, ["chef"] = true, ["the saw"] = true, ["yeti"] = true,
    ["mob leader"] = true, ["vice admiral"] = true, ["saber expert"] = true,
    ["warden"] = true, ["magma general"] = true, ["fishman lord"] = true,
    ["sky warlord"] = true, ["lightning god"] = true, ["cyborg"] = true,
    ["ice admiral"] = true, ["diamond"] = true, ["jeremy"] = true, ["orbitus"] = true,
    ["don swan"] = true, ["smoke admiral"] = true, ["awakened ice admiral"] = true,
    ["tide keeper"] = true, ["rip_indra"] = true, ["stone"] = true,
    ["hydra leader"] = true, ["kilo admiral"] = true, ["captain elephant"] = true,
    ["beautiful pirate"] = true, ["longma"] = true, ["cursed skeleton boss"] = true,
    ["cake queen"] = true, ["heaven's guardian"] = true, ["hell's messenger"] = true,
    -- the raid bosses the hubs farm as well
    ["darkbeard"] = true, ["soul reaper"] = true, ["dough king"] = true,
    ["cake prince"] = true, ["rip indra"] = true, ["rip indra true form"] = true,
}

-- The level of each boss quest (the table of the wiki), so the boss farm
-- takes one the player can actually beat.
local BOSS_LEVELS = {
    ["the gorilla king"] = 20, ["chef"] = 55, ["yeti"] = 105, ["vice admiral"] = 130,
    ["warden"] = 230, ["magma general"] = 350, ["fishman lord"] = 425,
    ["sky warlord"] = 500, ["lightning god"] = 575, ["cyborg"] = 675,
    ["diamond"] = 750, ["jeremy"] = 850, ["orbitus"] = 925, ["smoke admiral"] = 1150,
    ["awakened ice admiral"] = 1400, ["tide keeper"] = 1475, ["stone"] = 1550,
    ["hydra leader"] = 1675, ["kilo admiral"] = 1750, ["captain elephant"] = 1875,
    ["beautiful pirate"] = 1950, ["cake queen"] = 2175,
}

-- The key of the boss tables for a mob, from its name or its display name.
-- nil when the mob is no boss at all.
local function bossKeyOf(mob)
    if not mob then return nil end
    local key = mobKey(mob.Name):lower()
    if BOSS_NAMES[key] then return key end
    local display = nil
    pcall(function() display = mob:GetAttribute("DisplayName") end)
    if display then
        local dkey = mobKey(display):lower()
        if BOSS_NAMES[dkey] then return dkey end
    end
    return nil
end

-- A quest whose mob is a boss is worth more than a quest of plain mobs, and
-- the picker asks this. It is a global on purpose: the picker sits earlier in
-- the chunk than the boss tables, and the chunk is at the limit of 200 locals.
bossNameIs = function(name)
    if not name or not BOSS_NAMES then return false end
    -- the tables of the bosses write the names both with and without the
    -- leading "the" of the game ("The Gorilla King" / "Gorilla King")
    local key = mobKey(name):lower()
    if BOSS_NAMES[key] then return true end
    if BOSS_NAMES["the " .. key] then return true end
    if key:sub(1, 4) == "the " and BOSS_NAMES[key:sub(5)] then return true end
    return false
end

local function pickBoss(root, range, mobName)
    if not root then return nil end
    local level = getMyLevel()
    local window = runtime.config.BossLevelWindow or 25
    local wanted
    if mobName then
        wanted = mobKey(tostring(mobName)):lower():gsub("^the ", "")
    end
    local best, bestD = nil, math.huge

    for _, mob in ipairs(collectEnemies(tick())) do
        local key = bossKeyOf(mob)
        local matchesName = true

        if key and wanted then
            matchesName = key:lower():gsub("^the ", "") == wanted
        end

        if key and matchesName then
            local anchor = anchorOf(mob)
            if anchor then
                local d = (anchor.Position - root.Position).Magnitude
                if d <= range then
                    local bossLevel = BOSS_LEVELS[key]

                    -- Bosses are only taken when their level is close to the
                    -- player, so a level 700 player is not thrown at a level
                    -- 600 boss. The quest boss itself is always allowed if its
                    -- level table is missing.
                    local levelOk = bossLevel == nil
                        or math.abs(bossLevel - level) <= window

                    if levelOk and d < bestD then
                        best, bestD = mob, d
                    end
                end
            end
        end
    end

    return best
end

-- The level of a boss quest mob, global because the quest picker is defined
-- earlier in the chunk than the boss tables.
bossLevelOf = function(name)
    if not name then return nil end
    local key = mobKey(name):lower()
    if BOSS_LEVELS[key] then return BOSS_LEVELS[key] end
    if key:sub(1, 4) == "the " then
        return BOSS_LEVELS[key:sub(5)]
    end
    return BOSS_LEVELS["the " .. key]
end

-- While the quest boss is dead the bot farms normal mobs around the spawn
-- instead of standing still. Bosses are never returned here.
pickNormal = function(root)
    if not root then return nil end
    local best, bestD = nil, math.huge
    for _, mob in ipairs(collectEnemies(tick())) do
        if not bossKeyOf(mob) then
            local anchor = anchorOf(mob)
            if anchor then
                local d = (anchor.Position - root.Position).Magnitude
                if d < bestD then best, bestD = mob, d end
            end
        end
    end
    return best
end

local function getTarget(mobName)
    local root = getRoot()
    if not root then return nil end
    return pickBest(collectEnemies(tick()), mobName, root)
end

local function findSpawn(mobName)
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    local root = getRoot()
    if not spawns or not root then return nil end

    local candidates = {}
    for _, p in ipairs(spawns:GetChildren()) do
        if p:IsA("BasePart") or p:IsA("Model") then table.insert(candidates, p) end
    end
    return pickBest(candidates, mobName, root)
end

local function ownedByOther(part)
    local chars = Workspace:FindFirstChild("Characters")
    if not chars then return false end
    local now = tick()
    local cache = runtime.state.otherPlayerCache
    if not cache or now - cache.at > 0.1 then
        local list = {}
        for _, c in ipairs(chars:GetChildren()) do
            if c.Name ~= LocalPlayer.Name then
                local hrp = c:FindFirstChild("HumanoidRootPart")
                if hrp then table.insert(list, hrp) end
            end
        end
        cache = {at = now, list = list}
        runtime.state.otherPlayerCache = cache
    end
    for _, hrp in ipairs(cache.list) do
        -- Only a player who is really on top of the mob is fighting it. The
        -- old 300 studs covered the whole camp, so on a populated server every
        -- mob counted as someone else's and Bring Mob let go of everything.
        if (hrp.Position - part.Position).Magnitude <= 12 then return true end
    end
    return false
end

-- The working Bring Mobs source only teleports an extra when this client
-- owns its physics. A server-owned rig would snap straight back, while a
-- locally owned one can be put into the ring immediately and then carried by
-- the body mover. Never guess ownership: no ownership means no snap.
runtime.bringLocallyOwned = function(part)
    if type(isnetworkowner) ~= "function" then return false end
    local ok, owned = pcall(isnetworkowner, part)
    return ok and owned == true
end

runtime.bringSnap = function(mob, part, goal)
    if not runtime.config.BringMobSnap or runtime.state.bringSnapped[mob] then
        return false
    end
    if not runtime.bringLocallyOwned(part) then return false end

    local gap = (part.Position - goal).Magnitude
    if gap < (runtime.config.BringMobSnapDistance or 4) then
        -- It is already close enough. Do not keep testing ownership for this
        -- hold; the mover is responsible from here on.
        runtime.state.bringSnapped[mob] = true
        return false
    end

    local ok = pcall(function()
        -- Keep the facing of the rig, but put its root at the ring slot. The
        -- source uses the same one-step position move for the pack.
        part.CFrame = CFrame.new(goal) * part.CFrame.Rotation
        part.AssemblyLinearVelocity = Vector3.zero
        part.AssemblyAngularVelocity = Vector3.zero
    end)
    if ok then runtime.state.bringSnapped[mob] = true end
    return ok
end

-- The game itself knows how to push a body: the server sends a message and the
-- client module ReplicatedStorage.Util.BodyMover builds a BodyVelocity on a
-- character with a speed, a priority and a duration, then takes it down again.
-- Firing that very handler with our own message is the way to move a mob the
-- game is willing to carry: the game does the work, we only say where. When
-- the remote or the firesignal helper of the executor is not there this says
-- false and the caller keeps its own mover.
gameBodyMove = function(char, velocity, duration, id, action)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local mover = remotes and remotes:FindFirstChild("BodyMover")
    if not mover or not firesignal then return false end
    local message = {
        Character = char, Priority = -10, ID = id,
        Velocity = velocity, Duration = duration, Meta = {},
    }
    local ok = pcall(function()
        firesignal(mover.OnClientEvent, message, action or "Create", "BodyVelocity", message)
    end)
    return ok
end

-- A mob is let go: the drag goes away and every value this run changed is put
-- back exactly as the game had it, so the mob can stand and walk on its own
-- again. Only the mover recorded for this mob is destroyed; a pre-existing
-- instance named "Lock" belongs to somebody else and is never touched.
runtime.letGoMob = function(mob, part)
    part = part or anchorOf(mob)
    if runtime.state.bringMoverId[mob] then
        pcall(function() gameBodyMove(mob, Vector3.zero, 0, runtime.state.bringMoverId[mob], "Destroy") end)
        runtime.state.bringMoverId[mob] = nil
    end
    local mover = runtime.state.bringMover[mob]
    if mover then
        pcall(function() mover:Destroy() end)
        runtime.state.bringMover[mob] = nil
    end

    local saved = runtime.state.bringSaved[mob]
    if saved then
        for d, orig in pairs(saved.parts) do
            if d.Parent then
                pcall(function()
                    d.CanCollide = orig.collide
                    d.CanTouch = orig.touch
                    d.Massless = orig.massless
                end)
            end
        end
        if part and part.Parent then
            pcall(function()
                part.AssemblyLinearVelocity = saved.linear or Vector3.zero
                part.AssemblyAngularVelocity = saved.angular or Vector3.zero
                if saved.hadBeingBrought then
                    part:SetAttribute("BeingBrought", saved.beingBrought)
                else
                    part:SetAttribute("BeingBrought", nil)
                end
            end)
        end
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                if saved.platformStand ~= nil then hum.PlatformStand = saved.platformStand end
                if saved.autoRotate ~= nil then hum.AutoRotate = saved.autoRotate end
                if saved.walk ~= nil then hum.WalkSpeed = saved.walk end
                if saved.jump ~= nil then hum.JumpPower = saved.jump end
                -- Restore the state that was captured before the hold. A
                -- blanket Running change used to overwrite a mob that was
                -- already jumping or lying down before it was picked up.
                if hum.Health > 0 and saved.state then
                    hum:ChangeState(saved.state)
                end
            end)
        end
        runtime.state.bringSaved[mob] = nil
    end
    runtime.state.bringHeld[mob] = nil
    runtime.state.bringMoved[mob] = nil
    runtime.state.bringHealth[mob] = nil
    runtime.state.bringSnapped[mob] = nil
    runtime.state.bringOwned[mob] = nil
    runtime.state.bringCarryingTarget[mob] = nil
    -- the slot is only given back; the counter never walks back, or a new mob
    -- would take a step a mob that is still held already stands on
    runtime.state.bringSlot[mob] = nil
end
letGoMob = runtime.letGoMob

-- Bring Mob uses the reliable layout of the working source with one useful
-- extension. A locally owned target is carried under the player. A
-- server-owned target cannot be moved by a client BodyVelocity, so the extras
-- are packed around that target and the player walks to it, exactly like the
-- source. In both cases the target stays alive and the extras form a ring.
local function bringMob(target, root)
    if not runtime.config.BringMob or not target or not target.Parent or not root then return end
    local anchor = anchorOf(target)
    if not anchor then return end
    local targetHum = target:FindFirstChildOfClass("Humanoid")
    if not targetHum or targetHum.Health <= 0 then
        if runtime.state.bringHeld[target] then runtime.letGoMob(target, anchor) end
        return
    end

    local now = tick()
    local bringRange = tonumber(runtime.config.BringMobRange) or 60
    if bringRange <= 0 or (anchor.Position - root.Position).Magnitude > bringRange then
        return
    end

    -- A held mob that died, vanished or lost network ownership goes free at
    -- once. Ownership is checked per mob: the target and every extra can have
    -- different owners, and a server-owned extra must never be frozen by a
    -- client-side BodyVelocity.
    for mob, part in pairs(runtime.state.bringHeld) do
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        if not mob.Parent or not part.Parent or not hum or hum.Health <= 0
            or not runtime.bringLocallyOwned(part) then
            runtime.letGoMob(mob, part)
        end
    end

    if now < (runtime.state.bringAt or 0) then return end
    runtime.state.bringAt = now + 0.05

    if target:FindFirstChild("Ignored") then
        for mob, part in pairs(runtime.state.bringHeld) do
            runtime.letGoMob(mob, part)
        end
        runtime.state.bringTarget, runtime.state.bringCentre = nil, nil
        return
    end

    -- The source proves that a pack around the target is the reliable part.
    -- When this client owns the target, we can do the nicer thing and carry
    -- it under the player. Otherwise the target is the centre of the ring and
    -- the main loop walks the player to it.
    local carryTarget = runtime.config.BringMobCarryTarget
        and runtime.bringLocallyOwned(anchor)
    if runtime.state.bringTarget ~= target then
        runtime.state.bringCentre = nil
    end

    -- The centre follows its owner with a small dead zone. Refreshing it on
    -- every hover step would drag the pack back and forth, while a point that
    -- lags too far behind is what made the mobs trail after the bot.
    local desired = carryTarget and root.Position or anchor.Position
    local centre = runtime.state.bringCentre
    if not centre or (desired - centre).Magnitude > 3 then
        runtime.state.bringCentre = desired
        centre = desired
    end
    local point = centre
    runtime.state.bringPoint, runtime.state.bringTarget = point, target

    local list = {target}
    local count = runtime.config.BringMobCount or 0
    if count <= 0 then count = math.huge end
    count = math.min(count, runtime.config.BringMobMax or 8)
    local key = mobKey(target.Name)
    if count > 1 then
        local near = {}
        for _, mob in ipairs(collectEnemies(now)) do
            if mob ~= target and not mob:FindFirstChild("Ignored") then
                local part = anchorOf(mob)
                local hum = mob:FindFirstChildOfClass("Humanoid")
                if part and hum and hum.Health > 0 and not ownedByOther(part)
                    and runtime.bringLocallyOwned(part)
                    and mobKey(mob.Name) == key
                    and (part.Position - anchor.Position).Magnitude <= (runtime.config.BringMobSearch or 200) then
                    table.insert(near, {mob = mob, dist = (part.Position - anchor.Position).Magnitude})
                end
            end
        end
        table.sort(near, function(a, b) return a.dist < b.dist end)
        for _, entry in ipairs(near) do
            if #list >= count then break end
            table.insert(list, entry.mob)
        end
    end

    local stillHeld = {}
    for index, mob in ipairs(list) do
        local part = anchorOf(mob)
        if part then
            local isTarget = mob == target
            -- A server-owned target is the centre of the ring but is never
            -- held or changed. Only locally owned extras are packed around
            -- it, and the player walks to the target itself.
            local shouldHold = (not isTarget) or carryTarget
            if not shouldHold then
                if runtime.state.bringHeld[mob] or runtime.state.bringSaved[mob] then
                    runtime.letGoMob(mob, part)
                end
            else
                stillHeld[mob] = true
                -- every mob keeps its own slot, so the pack does not shuffle
                -- around when the order of the list changes
                local slot = runtime.state.bringSlot[mob]
                if not slot then
                    runtime.state.bringSlotCount = (runtime.state.bringSlotCount or 0) + 1
                    slot = runtime.state.bringSlotCount
                    runtime.state.bringSlot[mob] = slot
                end
            -- The target stands in the middle; the extras are spread on a ring
            -- with the golden angle, so any count from one to twelve stands
            -- evenly around the target instead of in one row on one side.
            local goalX, goalZ = point.X, point.Z
            if index > 1 then
                local angle = (slot - 1) * 2.399963229728653
                goalX = point.X + math.cos(angle) * 2.8
                goalZ = point.Z + math.sin(angle) * 2.8
            end
            -- The whole pack stands on the ground of the target, not on the
            -- height each mob happened to have when it was grabbed: a mob
            -- pulled over a slope otherwise floats or sinks into it.
            local goal = Vector3.new(goalX,
                anchor.Position.Y + (part.Size.Y - anchor.Size.Y) * 0.5, goalZ)
            local hum = mob:FindFirstChildOfClass("Humanoid")

            -- The pack keeps the real assembly mass and the real touch
            -- behaviour. Only collision and the walking state are changed,
            -- and every original value is written down before the first
            -- change so release can restore the rig exactly.
            if not runtime.state.bringSaved[mob] then
                local saved = { parts = {} }
                for _, d in ipairs(mob:GetDescendants()) do
                    if d:IsA("BasePart") then
                        saved.parts[d] = {
                            collide = d.CanCollide,
                            touch = d.CanTouch,
                            massless = d.Massless,
                        }
                    end
                end
                saved.linear = part.AssemblyLinearVelocity
                saved.angular = part.AssemblyAngularVelocity
                saved.hadBeingBrought = part:GetAttribute("BeingBrought") ~= nil
                saved.beingBrought = part:GetAttribute("BeingBrought")
                if hum then
                    saved.walk = hum.WalkSpeed
                    saved.jump = hum.JumpPower
                    saved.platformStand = hum.PlatformStand
                    saved.autoRotate = hum.AutoRotate
                    saved.state = nil
                    pcall(function() saved.state = hum:GetState() end)
                end
                runtime.state.bringSaved[mob] = saved
                for d in pairs(saved.parts) do
                    if d.Parent then
                        pcall(function() d.CanCollide = false end)
                    end
                end
                pcall(function()
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                    part:SetAttribute("BeingBrought", true)
                end)
            end

            if hum then
                pcall(function()
                    hum.PlatformStand = true
                    hum.AutoRotate = false
                    hum.WalkSpeed = 0
                    hum.JumpPower = 0
                    hum:ChangeState(Enum.HumanoidStateType.Physics)
                end)
                -- This is the fast first step from the working source. It is
                -- only used when this client owns the rig; otherwise the body
                -- velocity below does the carrying.
                runtime.bringSnap(mob, part, goal)
            end

            -- Move with the mover of the game when it can be had: fire its own
            -- handler with a speed towards the step and a short duration, so
            -- the game carries the mob. Otherwise use a private mover with a
            -- unique name. The script never searches for or destroys a
            -- generic "Lock" instance that it did not create itself.
            local gameMoved = false
            if runtime.config.BringMover == "Game" then
                local private = runtime.state.bringMover[mob]
                if private then
                    pcall(function() private:Destroy() end)
                    runtime.state.bringMover[mob] = nil
                end
                local id = runtime.state.bringMoverId[mob]
                if not id then
                    runtime.state.bringMoverSeq = (runtime.state.bringMoverSeq or 0) + 1
                    id = runtime.state.bringMoverSeq
                    runtime.state.bringMoverId[mob] = id
                end
                local vel = Vector3.zero
                local toGo = goal - part.Position
                local gap = toGo.Magnitude
                if gap > 0.6 then
                    vel = toGo.Unit * math.min(gap * 4, 120)
                end
                gameMoved = gameBodyMove(mob, vel, 0.2, id, "Create")
            end

            if not gameMoved then
                local mover = runtime.state.bringMover[mob]
                if not mover or not mover.Parent then
                    runtime.state.bringMoverSeq = (runtime.state.bringMoverSeq or 0) + 1
                    mover = Instance.new("BodyVelocity")
                    mover.Name = "FarmBringMover_" .. tostring(runtime.generation)
                        .. "_" .. tostring(runtime.state.bringMoverSeq)
                    -- The working source uses 1e9. A finite force is enough
                    -- for every enemy rig and avoids an unbounded force on
                    -- an assembly that is changing ownership.
                    mover.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                    mover.P = 12500
                    mover.Velocity = Vector3.zero
                    pcall(function() mover:SetAttribute("FarmOwned", true) end)
                    mover.Parent = part
                    runtime.state.bringMover[mob] = mover
                end
                -- The hold drags the mob over with the same body velocity
                -- the hubs use. The owned target is carried too, so the bot
                -- fights where it stands instead of walking after a mob
                -- that was never brought.
                local toGo = goal - part.Position
                local gap = toGo.Magnitude
                if gap > 0.6 then
                    -- A speed that closes a fixed fraction of the gap per
                    -- update (the hold is refreshed twenty times a second).
                    -- The old distance times eight with a six-stud floor
                    -- overshot every step, and the mob visibly bounced.
                    mover.Velocity = toGo.Unit * math.min(gap * 4, 120)
                else
                    mover.Velocity = Vector3.zero
                end
            else
                -- the game carries it, no private mover may stay on the rig
                local private = runtime.state.bringMover[mob]
                if private then
                    pcall(function() private:Destroy() end)
                    runtime.state.bringMover[mob] = nil
                end
            end

            runtime.state.bringOwned[mob] = true
            runtime.state.bringHeld[mob] = part
            end
        end
    end

    runtime.state.bringCarryingTarget[target] = carryTarget == true

    -- the mobs of the last pack that are not in this one any more go free
    for mob, part in pairs(runtime.state.bringHeld) do
        if not stillHeld[mob] then
            runtime.letGoMob(mob, part)
        end
    end
end

-- The client only simulates the mobs that stand inside its simulation radius.
-- The hubs raise it, and that is the whole reason their bring mob holds: the
-- mobs far away keep being simulated instead of being dropped by the client.
local function raiseSimulationRadius()
    local player = LocalPlayer
    if not player then return end
    if sethiddenproperty then
        pcall(function() sethiddenproperty(player, "SimulationRadius", math.huge) end)
        pcall(function() sethiddenproperty(player, "MaxSimulationRadius", math.huge) end)
    end
    pcall(function() player.SimulationRadius = math.huge end)
    pcall(function() player.MaxSimulationRadius = math.huge end)
end

-- ================= MOVEMENT =================
local activeTween, tweenGoal

-- The one tween of the script. Every trip of the character goes through here,
-- so the walk to a mob, the flight to an island and the way into the whirlpool
-- all move at exactly runtime.config.MoveSpeed. There is no cap: a longer way simply
-- takes longer, it is never rushed (a rushed flight is what the game undoes).
runtime.tweenTo = function(cf)
    local root = getRoot()
    if not root then return end
    local dist = (root.Position - cf.Position).Magnitude
    if activeTween and tweenGoal
        and activeTween.PlaybackState == Enum.PlaybackState.Playing then
        local moved = (tweenGoal.Position - cf.Position).Magnitude
        local left = (root.Position - tweenGoal.Position).Magnitude
        if moved < math.max(12, left * 0.4) then return end
    end
    if activeTween then activeTween:Cancel() end
    runtime.setFlying()
    tweenGoal = cf
    activeTween = TweenService:Create(root,
        TweenInfo.new(math.max(dist / runtime.config.MoveSpeed, 0.12), Enum.EasingStyle.Linear),
        {CFrame = cf})
    activeTween:Play()
end

runtime.setFlying = function()
    -- While a tween moves the character, its own body (gravity, walking,
    -- getting up) fights the CFrame and the flight looks jerky. The body is
    -- put in the physics state and left alone until the move is over.
    local hum = getHumanoid()
    if not hum then return end
    pcall(function() hum.PlatformStand = true end)
    pcall(function() hum.AutoRotate = false end)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
end

runtime.setWalking = function()
    local hum = getHumanoid()
    if not hum then return end
    pcall(function() hum.PlatformStand = false end)
    pcall(function() hum.AutoRotate = true end)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
end

runtime.stopTween = function()
    if activeTween then activeTween:Cancel(); activeTween = nil end
    tweenGoal = nil
    runtime.setWalking()
end

runtime.moveTo = function(cf, noWarp)
    local root = getRoot()
    if not root then return end
    local mode = runtime.config.MovementMode
    local hop = (root.Position - cf.Position).Magnitude

    -- A short hop inside the same island is accepted by the game, so it is
    -- taken at once instead of being walked. The shop turns that off: the
    -- teacher of a style has to see the player walk up to it.
    if runtime.config.WarpClose and not noWarp and hop <= (runtime.config.WarpDistance or 60) then
        -- The hover asks for the very spot the player already stands on twenty
        -- times a second. Snapping there is what made the view stutter, so a
        -- step under a stud is left alone and a real hop is taken at once.
        if hop > 1 then
            runtime.stopTween()
            root.CFrame = cf
        end
        return
    end

    if mode == "Teleport" then
        runtime.stopTween()
        root.CFrame = cf
    elseif mode == "Tween" then
        local dist = (root.Position - cf.Position).Magnitude
        if dist < 9 and not noWarp then
            runtime.stopTween()
            runtime.setWalking()
            root.CFrame = cf
            return
        end
        runtime.tweenTo(cf)
    else
        runtime.setWalking()
        local hum = getHumanoid()
        if hum then hum:MoveTo(cf.Position) end
    end
end

-- Keep the old global names as compatibility aliases, but every internal
-- call uses the function captured by this runtime. An old execution can
-- therefore never move or restore the character of a newer execution.
tweenTo = runtime.tweenTo
setFlying = runtime.setFlying
setWalking = runtime.setWalking
stopTween = runtime.stopTween
moveTo = runtime.moveTo

-- ================= NOCLIP =================
local noclipChar, noclipParts, noclipConn = nil, {}, nil

local function restoreNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    for _, entry in ipairs(noclipParts) do
        if entry.part.Parent then entry.part.CanCollide = entry.original end
    end
    noclipParts = {}
    noclipChar = nil
end

local function applyNoclip()
    local char = LocalPlayer.Character
    if char ~= noclipChar then
        restoreNoclip()
        noclipChar = char
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    table.insert(noclipParts, {part = p, original = p.CanCollide})
                end
            end
            noclipConn = char.DescendantAdded:Connect(function(obj)
                if not runtime.running or FarmRuntime.current ~= runtime then return end
                if obj:IsA("BasePart") then
                    table.insert(noclipParts, {part = obj, original = obj.CanCollide})
                    if runtime.state.farming then obj.CanCollide = false end
                end
            end)
        end
    end
    for _, entry in ipairs(noclipParts) do
        local p = entry.part
        if p.Parent and p.CanCollide then p.CanCollide = false end
    end
end

runtime.steppedConn = RunService.Stepped:Connect(function()
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    pcall(function()
        local root = getRoot()
        if not runtime.state.enabled or not root then
            if #noclipParts > 0 then restoreNoclip() end
            return
        end
        -- A flight or a quest walk needs no clipping as much as the farm does.
        -- The fruit sniper alone is not a reason to walk through walls.
        if not (runtime.state.flying or runtime.state.saberActive or runtime.state.shopping
            or (runtime.state.farming and runtime.config.AutoFarm)) then
            if #noclipParts > 0 then restoreNoclip() end
            return
        end
        applyNoclip()
        -- A tween is moving the character itself: zeroing its speed here
        -- every frame is what made the flight stutter. In walk mode the
        -- humanoid is the one moving the character, so its speed is left
        -- alone as well.
        local tweenPlaying = activeTween
            and activeTween.PlaybackState == Enum.PlaybackState.Playing
        if not tweenPlaying and runtime.config.MovementMode ~= "Walk" then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end)

local function stopCameraShaker()
    local util = ReplicatedStorage:FindFirstChild("Util")
    local shaker = util and util:FindFirstChild("CameraShaker")
    if not shaker then return false end
    local ok = pcall(function() require(shaker):Stop() end)
    return ok
end

-- ================= ATTACK =================
local combatController

local function getCombatController()
    if combatController then return combatController end
    -- The live client uses this module directly. The old PlayerScripts
    -- "CombatFramework" object does not exist in this build, so looking for it
    -- made every gun attack fall back to a plain tool activation.
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local mod = controllers and controllers:FindFirstChild("CombatController")
    if not mod then return nil end
    local ok, ctrl = pcall(require, mod)
    if not ok or type(ctrl) ~= "table" or type(ctrl.Attack) ~= "function" then
        return nil
    end
    combatController = ctrl
    return combatController
end

local function fastAttack()
    -- The old implementation wrote fields the live CombatController does not
    -- have, so it only pretended to bypass a cooldown. The remote path really
    -- bypasses it; here we only clear the client stun that can block a swing.
    local char = LocalPlayer.Character
    local stun = char and char:FindFirstChild("Stun")
    if stun then
        pcall(function()
            if stun:IsA("BoolValue") then
                stun.Value = false
            else
                stun.Value = 0
            end
        end)
    end
    return true
end

local function combatUtilModule()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local util = modules and modules:FindFirstChild("CombatUtil")
    if not util then return nil end
    -- the module does not change while a server is played: require it once.
    -- The cache lives in state, the chunk is at the limit of 200 locals.
    if runtime.state.combatUtil and runtime.state.combatUtilMod == util then return runtime.state.combatUtil end
    local ok, combatUtil = pcall(require, util)
    if not ok or not combatUtil then return nil end
    runtime.state.combatUtil, runtime.state.combatUtilMod = combatUtil, util
    return combatUtil
end

local function attackAnimLength(tool)
    local combatUtil = combatUtilModule()
    if not combatUtil or not tool then return 0.5, 1 end

    -- The live controller forgets a basic combo after 0.75 seconds without a
    -- new swing. The script uses the same rule instead of keeping a stale
    -- combo index for ever.
    local now = tick()
    if runtime.state.attackComboAt and now - runtime.state.attackComboAt >= 0.75 then
        runtime.state.attackCombo = 0
        runtime.state.attackComboAt = 0
    end

    local length, combo = 0.5, 1
    pcall(function()
        local weaponName = combatUtil:GetWeaponName(tool)
        local weaponData = combatUtil:GetWeaponData(weaponName)
        if weaponData and weaponData.WeaponType == "Gun" then
            -- Guns do not use RegisterAttack or a basic moveset. Their own
            -- cooldown is the timing used by CombatUtil.ShootTypes.
            length = tonumber(weaponData.Cooldown)
                or tonumber(weaponData.ShootInterval) or 0.5
            combo = 0
            runtime.state.attackComboCount = 1
            return
        end

        local basic = weaponData and weaponData.Moveset and weaponData.Moveset.Basic
        local comboCount = (basic and #basic) or 1
        if comboCount < 1 then comboCount = 1 end
        runtime.state.attackComboCount = comboCount

        -- RegisterAttack carries the next basic-move index. It is advanced
        -- only after an attack is really dispatched.
        combo = ((runtime.state.attackCombo or 0) % comboCount) + 1

        -- CombatUtil caches loaded animation tracks by Humanoid, not by the
        -- weapon name. If a particular combo track has not been loaded, basic1
        -- is the matching fallback, but the combo index sent to the server
        -- must still be the real one.
        local hum = getHumanoid()
        local cache = combatUtil:GetMovesetAnimCache(hum)
        local pure = combatUtil:GetPureWeaponName(weaponName)
        local prefix = pure .. "-basic"
        local track = cache and cache[prefix .. combo]
        if not track then track = cache and cache[prefix .. "1"] end
        if not track then
            for key, value in pairs(cache or {}) do
                if startsWith(key, prefix) then
                    track = value
                    break
                end
            end
        end
        if track then
            local speed = track:GetAttribute("SpeedMult") or 1
            if track.Length and speed > 0 then length = track.Length / speed end
        end
    end)
    return length, combo
end

local function hitPartOf(mob)
    if not mob then return nil end
    -- the game registers a hit against any body part of the rig; the head is
    -- what the public hit scripts send, the root is the fallback
    return mob:FindFirstChild("Head")
        or mob:FindFirstChild("HumanoidRootPart")
        or anchorOf(mob)
end

-- Every mob close to the player goes into one swing. Like the hub, each mob
-- goes in as a pair of its rig and the part that was hit, and the target is
-- the first one: the game takes that part on its own and the whole list with
-- it, so a single swing lands on all of them.
local function aoePairs(root, target)
    local range = runtime.config.AoeRange or 80
    local out, seen = {}, {}
    local function add(mob)
        if not mob or seen[mob] then return end
        local part = hitPartOf(mob)
        if not part then return end
        local anchor = anchorOf(mob)
        if root and anchor and (anchor.Position - root.Position).Magnitude > range then return end
        seen[mob] = true
        table.insert(out, {mob, part})
    end
    add(target)
    if runtime.config.Aoe then
        for _, mob in ipairs(collectEnemies(tick())) do add(mob) end
    end
    return out
end

-- Net is a ModuleScript, but the remotes must be obtained through the module
-- itself. RegisterHit is a virtual remote in the current game: firing its raw
-- child skips the virtual-remote encoding and the server silently drops every
-- hit. Requiring Net returns the wrapper that performs that encoding.
local function netFolder()
    if runtime.state.netModule then return runtime.state.netModule end
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local module = modules and modules:FindFirstChild("Net")
    if not module then return nil end
    runtime.state.netModuleInstance = module
    local ok, net = pcall(require, module)
    if ok and type(net) == "table" then
        runtime.state.netModule = net
        return net
    end
    return nil
end

local function hitRemote()
    if runtime.state.hitRemoteCache then return runtime.state.hitRemoteCache end
    local net = netFolder()
    if net then
        local ok, remote = pcall(function() return net:RemoteEvent("RegisterHit", true) end)
        if ok and remote then
            runtime.state.hitRemoteCache = remote
            return remote
        end
    end

    -- A raw RegisterHit is only safe when the game has not marked it virtual.
    local module = runtime.state.netModuleInstance
    local raw = module and module:FindFirstChild("RE/RegisterHit")
    if raw and not raw:GetAttribute("Virtual") then
        runtime.state.hitRemoteCache = raw
        return raw
    end
    return nil
end

local function attackRemote()
    if runtime.state.attackRemoteCache then return runtime.state.attackRemoteCache end
    local net = netFolder()
    if net then
        local ok, remote = pcall(function() return net:RemoteEvent("RegisterAttack") end)
        if ok and remote then
            runtime.state.attackRemoteCache = remote
            return remote
        end
    end
    local module = runtime.state.netModuleInstance
    local raw = module and module:FindFirstChild("RE/RegisterAttack")
    if raw and not raw:GetAttribute("Virtual") then
        runtime.state.attackRemoteCache = raw
        return raw
    end
    return nil
end

-- RegisterHit uses a small session token. The game creates the token inside
-- one dedicated combat coroutine, sends it once as a handshake, and then
-- sends that same token with every hit. A token made in an unrelated thread
-- is not accepted. This fallback mirrors the game exactly and is only used
-- when the game's own SendHitsToServer function is unavailable.
local function hitSessionId()
    local hit = hitRemote()
    if not hit then return nil end
    if runtime.hitSessionId and runtime.hitThread and runtime.hitThreadRemote == hit
        and coroutine.status(runtime.hitThread) == "suspended" then
        return runtime.hitSessionId
    end

    runtime.hitSessionId = nil
    runtime.hitThread = nil
    runtime.hitThreadRemote = hit
    runtime.hitRequest = nil
    runtime.hitResult = nil
    runtime.hitHandshakeOk = false
    local thread = coroutine.create(function()
        local epoch = runtime.characterEpoch
        local token = tostring(LocalPlayer.UserId):sub(2, 4)
            .. tostring(coroutine.running()):sub(11, 15)

        -- Handshake: the server learns the token before the first hit. Its
        -- result is kept for the caller instead of being lost inside this
        -- coroutine.
        local ok, err = pcall(function() hit:FireServer(token) end)
        runtime.hitHandshakeOk = ok
        runtime.hitHandshakeError = err
        runtime.hitSessionId = token
        if not ok then
            dbg("Hit handshake failed: " .. tostring(err))
        end

        while true do
            coroutine.yield()
            if not runtime.isCurrent() or runtime.characterEpoch ~= epoch then return end
            local request = runtime.hitRequest
            runtime.hitRequest = nil
            if request then
                if request.stop then
                    runtime.hitResult = {ok = true}
                    return
                end
                local sent, sendError = pcall(function()
                    hit:FireServer(request.part, request.list, nil, token)
                end)
                runtime.hitResult = {ok = sent, error = sendError}
                if not sent then
                    dbg("Hit remote failed: " .. tostring(sendError))
                end
            end
        end
    end)

    runtime.hitThread = thread
    local resumed, err = coroutine.resume(thread)
    if not resumed then
        runtime.hitThread = nil
        runtime.hitThreadRemote = nil
        runtime.hitSessionId = nil
        dbg("Hit session failed: " .. tostring(err))
        return nil
    end
    if not runtime.hitHandshakeOk then
        runtime.hitThread = nil
        runtime.hitThreadRemote = nil
        runtime.hitSessionId = nil
        return nil
    end
    return runtime.hitSessionId
end

local function remoteAttack(target, tool, animLength, combo, attackPairs)
    runtime.state.attackDispatched = false
    runtime.state.attackHitDispatched = false
    runtime.state.attackComboSent = false

    -- A gun is not a melee hit. RegisterAttack/RegisterHit would send the
    -- wrong protocol. The live CombatController routes guns through
    -- CombatUtil.ShootTypes, which sends ShootGunEvent with the argument
    -- shape of each gun (single shot, shotgun or projectile).
    if isGun(tool) then
        local ctrl = getCombatController()
        local camera = Workspace.CurrentCamera
        local anchor = anchorOf(target)
        if not ctrl or not camera or not anchor then return false end
        local view = camera:WorldToViewportPoint(anchor.Position)
        if not view then return false end
        local inset = game:GetService("GuiService"):GetGuiInset()
        local before = tonumber(tool:GetAttribute("LocalTotalShots")) or 0
        local beforeLeft = tonumber(tool:GetAttribute("LocalShotsLeft"))

        -- CombatController.Attack expects the InputObject that came from the
        -- game. A small compatible object is enough here: the normal guns read
        -- its type and position, while Gatling guns also ask for a property
        -- signal. A BindableEvent supplies that signal and is explicitly ended
        -- when the bot is stopped, so the controller never keeps a dead input.
        if runtime.stopGunInput then runtime.stopGunInput() end
        local changed = Instance.new("BindableEvent")
        local input = {
            UserInputType = Enum.UserInputType.Touch,
            UserInputState = Enum.UserInputState.Begin,
            Position = Vector3.new(view.X - inset.X, view.Y - inset.Y, 0),
        }
        function input:GetPropertyChangedSignal()
            return changed.Event
        end

        local ok, err = pcall(function() ctrl:Attack(tool, input) end)
        local after = tonumber(tool:GetAttribute("LocalTotalShots")) or 0
        local afterLeft = tonumber(tool:GetAttribute("LocalShotsLeft"))
        local dispatched = ok and (after > before
            or (beforeLeft ~= nil and afterLeft ~= nil and afterLeft < beforeLeft))
        runtime.state.attackDispatched = dispatched
        runtime.state.attackHitDispatched = false
        runtime.state.aoeCount = dispatched and 1 or 0
        runtime.state.lastRemoteAttackAt = tick()
        if ok and tool:GetAttribute("IsAutoShooting") then
            runtime.state.gunInput = {tool = tool, input = input, changed = changed}
        else
            pcall(function() changed:Destroy() end)
        end
        if not ok then
            dbg("The gun controller failed: " .. tostring(err))
        end
        return dispatched
    end

    local regAttack = attackRemote()
    if not regAttack then return false end
    local hit = hitRemote()
    if not hit then return false end
    local root = getRoot()
    local pairs_ = attackPairs or aoePairs(root, target)
    if #pairs_ == 0 then return false end

    local primary = pairs_[1][2]
    if not primary then return false end

    -- RegisterAttack takes the real animation length and the current basic
    -- combo index. The old fixed second argument did not match the live
    -- combat controller.
    local attackOk = pcall(function()
        regAttack:FireServer(animLength, combo)
    end)
    if attackOk then
        runtime.state.attackCombo = combo
        runtime.state.attackComboAt = tick()
        runtime.state.attackComboSent = true
    end
    runtime.state.aoeCount = #pairs_

    -- The first part is sent separately. The second argument contains the
    -- remaining {rig, hitPart} pairs, exactly like CombatUtil does.
    local others = {}
    for i = 2, #pairs_ do others[#others + 1] = pairs_[i] end

    local hitOk = false
    if attackOk then
        -- CombatUtil normally installs SendHitsToServer on the game-wide global
        -- table. Apex runs this chunk with RobloxScript identity, where requiring
        -- ReplicatedStorage.Global is forbidden, so look the already-installed
        -- function up in the two visible global tables instead of trying to
        -- require that module again.
        local helper
        if type(_G) == "table" and type(_G.SendHitsToServer) == "function" then
            helper = _G.SendHitsToServer
        elseif type(getgenv) == "function" then
            local shared = getgenv()
            if type(shared) == "table" and type(shared.SendHitsToServer) == "function" then
                helper = shared.SendHitsToServer
            end
        end
        if helper then
            local sent, err = pcall(helper, primary, others)
            hitOk = sent
            if not sent then
                dbg("The game hit helper failed: " .. tostring(err))
            end
        end

        -- Fallback for builds where the global helper is not installed yet. The
        -- dedicated coroutine writes its real send result back to state, so a
        -- failed handshake or FireServer is not mistaken for a successful hit.
        if not hitOk then
            runtime.state.hitUseFallback = true
            local token = hitSessionId()
            if token and runtime.hitThread then
                runtime.hitRequest = {part = primary, list = others}
                runtime.hitResult = nil
                local resumed, err = coroutine.resume(runtime.hitThread)
                if not resumed then
                    hitOk = false
                    dbg("Hit session stopped: " .. tostring(err))
                else
                    local result = runtime.hitResult
                    hitOk = result and result.ok == true
                end
            end
        end
    end

    runtime.state.lastRemoteAttackAt = tick()
    -- FireServer only tells us that the packet was dispatched. It does not
    -- tell us that the server accepted the hit; doAttack waits for the mob's
    -- health to change before it suppresses the normal tool activation.
    runtime.state.attackHitDispatched = hitOk
    runtime.state.aoeRequested = #pairs_
    runtime.state.aoeConfirmed = 0
    runtime.state.attackDispatched = attackOk and hitOk
    return runtime.state.attackDispatched
end

local function doAttack(tool, target)
    if not tool then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return false end
    if runtime.config.FastAttack then fastAttack() end
    -- A fruit is a skill item, not a basic melee swing.
    if isFruit(tool) then return false end

    local animLength, combo = attackAnimLength(tool)
    runtime.state.attackAnimLength = animLength

    local now = tick()
    local gun = isGun(tool)
    local gunAlreadyFiring = gun and tool:GetAttribute("IsAutoShooting")
    if gunAlreadyFiring then
        -- A Gatling gun owns its firing loop. Starting the controller a second
        -- time would run two loops over the same magazine.
        runtime.state.attackNextAt = now + 0.05
        return false
    end

    -- Keep the health of the primary target and of every AOE target. A
    -- successful remote dispatch is not a server acknowledgement; only a real
    -- health decrease proves that a mob was hit.
    local watched = {}
    local attackPairs = nil
    if not gun then
        local root = getRoot()
        attackPairs = aoePairs(root, target)
        for _, entry in ipairs(attackPairs) do
            local mob = entry[1]
            local hum = mob and mob:FindFirstChildOfClass("Humanoid")
            if hum then watched[mob] = hum.Health end
        end
        runtime.state.aoeRequested = #attackPairs
    else
        local targetHum = target and target:FindFirstChildOfClass("Humanoid")
        if targetHum then watched[target] = targetHum.Health end
        runtime.state.aoeRequested = 1
    end

    local function confirmedDamage(deadline)
        local count, primaryConfirmed = 0, false
        while tick() < deadline do
            count, primaryConfirmed = 0, false
            for mob, health in pairs(watched) do
                local hum = mob and mob:FindFirstChildOfClass("Humanoid")
                -- A vanished model is not a health confirmation. The Humanoid
                -- has to still be there with a smaller Health value.
                if hum and hum.Health < health then
                    count = count + 1
                    if mob == target then primaryConfirmed = true end
                end
            end
            if primaryConfirmed then return true, count end
            task.wait(0.02)
            if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                or LocalPlayer.Character ~= char then return false, count end
        end
        return false, count
    end

    local dispatched = false
    if runtime.config.RemoteAttack then
        dispatched = remoteAttack(target, tool, animLength, combo, attackPairs)
    else
        runtime.state.aoeCount = 1
    end
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end

    local speed = tonumber(runtime.state.attackSpeed) or 1
    local charSpeed = char and tonumber(char:GetAttribute("AttackSpeedMultiplier")) or 1
    if charSpeed > speed then speed = charSpeed end
    if speed < 0.1 then speed = 0.1 end

    local delay
    if gun then
        -- A normal gun uses ShootInterval until the magazine is empty and then
        -- Cooldown to reload. Gatling guns use their own automatic cadence.
        local interval = animLength
        pcall(function()
            local combatUtil = combatUtilModule()
            local weaponName = combatUtil and combatUtil:GetWeaponName(tool)
            local data = weaponName and combatUtil:GetWeaponData(weaponName)
            if data then
                local shotsLeft = tonumber(tool:GetAttribute("LocalShotsLeft")) or 0
                local remaining = math.max(0, shotsLeft - 1)
                if data.ShootStyle ~= "Gatling" and remaining > 0 then
                    interval = tonumber(data.ShootInterval) or tonumber(data.Cooldown) or interval
                else
                    interval = tonumber(data.Cooldown) or tonumber(data.ShootInterval) or interval
                end
            end
        end)
        delay = interval / speed + (runtime.config.AttackCooldown or 0)
    else
        -- The live controller can cancel a basic attack at 80% of its
        -- animation. runtime.config.AttackCooldown is only an optional extra delay.
        delay = animLength * 0.8 / speed + (runtime.config.AttackCooldown or 0)
    end
    if delay < 0.05 then delay = 0.05 end

    if dispatched then
        runtime.state.attackNextAt = now + delay
        runtime.state.lastAttack = now
        local deadline = now + (gun and 0.45 or math.max(0.35, animLength * 0.8 + 0.15))
        local confirmed, confirmedCount = confirmedDamage(deadline)
        runtime.state.attackConfirmed = confirmed
        runtime.state.attackFallback = false
        runtime.state.aoeConfirmed = confirmedCount
        runtime.state.aoeCount = confirmedCount
        if confirmed then return true end

        -- A gun has already gone through the game's controller. Activating
        -- the tool again would send a second shot, so the controller is left
        -- to own the next attempt.
        if gun and runtime.config.RemoteAttack then return true end

        -- The melee hit packet was already dispatched. Activating the tool as
        -- a fallback would send the same hit a second time through the game
        -- controller. Wait for the next cadence instead.
        if runtime.state.attackHitDispatched then return true end
    elseif gun and runtime.config.RemoteAttack then
        -- The controller refused this attempt (usually a reload or cooldown).
        -- It must not be bypassed with a raw tool activation.
        runtime.state.attackNextAt = now + math.max(delay, 0.1)
        return false
    end

    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    local activated = pcall(function() tool:Activate() end)
    if not activated then return false end
    runtime.state.attackNextAt = now + delay
    runtime.state.lastAttack = now
    runtime.state.attackFallback = true
    local count = runtime.state.attackComboCount or 1
    if not runtime.state.attackComboSent then
        runtime.state.attackCombo = combo
    elseif count > 0 then
        -- The remote already used one combo index; the controller's fallback
        -- activation is the next one.
        runtime.state.attackCombo = (combo % count) + 1
    end
    runtime.state.attackComboAt = now

    -- The fallback is the game's normal activation, so its result is checked
    -- in exactly the same way as the remote path.
    local confirmed, confirmedCount = confirmedDamage(now + math.max(0.15, math.min(delay, 0.5)))
    runtime.state.attackConfirmed = confirmed
    runtime.state.aoeConfirmed = confirmedCount
    runtime.state.aoeCount = confirmedCount
    return true
end

local function mobInReach(root, reach)
    local best, bestD = nil, math.huge
    for _, mob in ipairs(collectEnemies(tick())) do
        local anchor = anchorOf(mob)
        if anchor then
            local dx = root.Position.X - anchor.Position.X
            local dz = root.Position.Z - anchor.Position.Z
            local d = math.sqrt(dx * dx + dz * dz)
            if d <= reach + 4 and d < bestD then best, bestD = mob, d end
        end
    end
    return best
end

local function autoAttackSwing(current)
    local now = tick()
    if runtime.state.attackNextAt and now < runtime.state.attackNextAt then return false end
    local tool = equipWeapon()
    if not tool or isFruit(tool) then return false end
    local root = getRoot()
    if not root then return false end
    local reach = attackRange(tool)
    local best = mobInReach(root, reach)
    if not best then return false end
    if doAttack(tool, best) then
        runtime.state.lastAttack = now
        if best ~= current then runtime.state.status = "Attacking " .. best.Name end
        return true
    end
    return false
end

-- ================= FRUIT =================
local FRUIT_FOLDERS = {"fruit", "item", "drop", "loot", "spawn", "pickup"}

local function inContainerName(name)
    local n = name:lower()
    for _, f in ipairs(FRUIT_FOLDERS) do
        if n:find(f, 1, true) then return true end
    end
    return false
end

local function toolPart(tool)
    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle end
    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function isFruitTool(obj)
    if not obj:IsA("Tool") then return false end
    if not isFruit(obj) then return false end
    return toolPart(obj) ~= nil
end

local function recentlyFailed(obj, now)
    local t = grabbedFruits[obj]
    return t ~= nil and (now - t) < 90
end

local function scanFruits(root, now)
    local best, bestD = nil, runtime.config.FruitScanRadius
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    local function consider(obj)
        if not obj or recentlyFailed(obj, now) then return end
        if not isFruitTool(obj) then return end
        if char and obj:IsDescendantOf(char) then return end
        if backpack and obj:IsDescendantOf(backpack) then return end
        local parent = obj.Parent
        if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
            return
        end
        local handle = toolPart(obj)
        if not handle then return end
        local d = (root.Position - handle.Position).Magnitude
        if d < bestD then best, bestD = obj, d end
    end

    local function walk(container, depth)
        for _, obj in ipairs(container:GetChildren()) do
            consider(obj)
            if depth > 0 and (obj:IsA("Folder") or obj:IsA("Model")) and inContainerName(obj.Name) then
                walk(obj, depth - 1)
            end
        end
    end

    walk(Workspace, 2)
    return best
end

local function toolCount()
    local count = 0
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if t:IsA("Tool") then count = count + 1 end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then count = count + 1 end
        end
    end
    return count
end

local function ownedTools()
    local set = {}
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then set[t] = true end
        end
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if t:IsA("Tool") then set[t] = true end
        end
    end
    return set
end

local function newTool(before)
    if not before then return nil end
    for t in pairs(ownedTools()) do
        if not before[t] and isFruit(t) then return t end
    end
    return nil
end

local function findFruitTool(name)
    local containers = {}
    local char = LocalPlayer.Character
    if char then table.insert(containers, char) end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then table.insert(containers, backpack) end
    for _, container in ipairs(containers) do
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and isFruit(t) and sameName(t.Name, name) then return t end
        end
    end
    return nil
end

local function useFruitMenu(fruitName, actions)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not runtime.isCurrent() or not char then return false end
    local function press(d)
        -- MouseButton1Click is a signal, not a BindableEvent: it has no
        -- :Fire(). The executor helper is the way to click a game button.
        if firesignal then
            pcall(function() if d.MouseButton1Click then firesignal(d.MouseButton1Click) end end)
            pcall(function() if d.Activated then firesignal(d.Activated) end end)
        end
    end
    local function shown(d) return d.Visible ~= false end
    if fruitName then
        local want = fruitName:lower()
        local compact = want:gsub("%s", "")
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and shown(d) then
                -- an ImageButton has no Text property: reading it threw and
                -- that error stopped every fruit menu action
                local text = ""
                if d:IsA("TextButton") then text = (d.Text or ""):lower() end
                local nm = (d.Name or ""):lower()
                if text == want or nm:find(compact, 1, true) then
                    press(d)
                    break
                end
            end
        end
        task.wait(0.2)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    for _, action in ipairs(actions) do
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and shown(d) then
                local t = ""
                if d:IsA("TextButton") then t = d.Text or "" end
                local text = (t .. " " .. (d.Name or "")):lower()
                if text:find("%f[%w]" .. action .. "%f[^%w]") then
                    press(d)
                    return true
                end
            end
        end
    end
    return false
end

local function carriedFruits()
    local list = {}
    local containers = {}
    local char = LocalPlayer.Character
    if char then table.insert(containers, char) end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then table.insert(containers, backpack) end
    for _, container in ipairs(containers) do
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and isFruit(t) then table.insert(list, t) end
        end
    end
    return list
end

local function eatFruit(tool)
    local char = LocalPlayer.Character
    local hum = getHumanoid()
    local epoch = runtime.characterEpoch
    if not tool or not char or not hum then return false end
    local name = tool.Name
    if tool.Parent ~= char then
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.1)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    if tool.Parent ~= char then
        dbg("Could not equip " .. tool.Name)
        return false
    end
    pcall(function() tool:Activate() end)
    local used = useFruitMenu(name, {"eat"})
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if used then
        dbg("Ate " .. name .. " from the menu")
        return true
    end
    dbg("No eat button for " .. name)
    return false
end

local function storeFruit(tool)
    if not tool then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return false end
    -- The game stores a fruit itself when the remote gets the tool: the server
    -- moves it into the bank at once. This is the path the hubs use; the GUI
    -- of the storage npc is only the fallback for builds without the remote.
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if commF then
        -- some builds want the name of the fruit instead of the tool itself,
        -- so the name is only tried when the call with the tool did not go
        -- through: asking twice can make the game eat or drop the fruit
        local ok = pcall(function() commF:InvokeServer("StoreFruit", tool) end)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
        if not ok then
            ok = pcall(function() commF:InvokeServer("StoreFruit", tool.Name) end)
            if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                or LocalPlayer.Character ~= char then return false end
        end
        if not ok then
            dbg("The store remote refused " .. tool.Name)
            return false
        end
        -- the answer of the invoke is not the proof: the fruit has to leave
        -- the player. The old code returned true here and the farm counted a
        -- store that never happened.
        for _ = 1, 8 do
            if tool.Parent == nil or not tool:IsDescendantOf(LocalPlayer) then
                dbg("Stored " .. tool.Name)
                return true
            end
            task.wait(0.1)
            if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                or LocalPlayer.Character ~= char then return false end
        end
        dbg("The store remote did not take " .. tool.Name)
        return false
    end
    local used = useFruitMenu(tool.Name, {"store", "deposit", "stash"})
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if used then
        dbg("Asked the game to store " .. tool.Name)
        return true
    end
    return false
end

local function fruitWasTaken(fruit)
    local p = fruit.Parent
    if p == nil then
        return toolCount() > runtime.state.fruitToolCount
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack and fruit:IsDescendantOf(backpack) then return true end
    local char = LocalPlayer.Character
    if char and fruit:IsDescendantOf(char) then return true end
    return false
end

local function confirmFruitPickup(fruit)
    runtime.state.fruitsFound = runtime.state.fruitsFound + 1
    local name = fruit.Name
    local tool = newTool(runtime.state.fruitTools) or findFruitTool(name)
    runtime.state.fruit = nil
    runtime.state.fruitTries = 0
    runtime.state.fruitTools = nil
    dbg("Picked up " .. name)
    if runtime.config.EatFruit and tool then
        eatFruit(tool)
        equipWeapon()
    end
    return true
end

local function handleFruit(root)
    local now = tick()

    if now - runtime.state.lastFruitScan >= 1.5 and not runtime.state.fruit then
        runtime.state.lastFruitScan = now
        local best = scanFruits(root, now)
        if best then
            runtime.state.fruit, runtime.state.fruitStart, runtime.state.fruitTries = best, now, 0
            runtime.state.fruitLastTry = 0
            runtime.state.fruitToolCount = toolCount()
            runtime.state.fruitTools = ownedTools()
            dbg("Fruit spotted: " .. best.Name)
        end
    end

    local fruit = runtime.state.fruit
    if not fruit then return false end

    local handle = fruit.Parent and toolPart(fruit)
    if not handle then
        if fruitWasTaken(fruit) then confirmFruitPickup(fruit) end
        runtime.state.fruit = nil
        runtime.state.fruitTools = nil
        return false
    end

    runtime.state.status = "Fruit: " .. fruit.Name
    runtime.moveTo(handle.CFrame)

    if (root.Position - handle.Position).Magnitude < 8 then
        if now - runtime.state.fruitLastTry >= runtime.config.FruitTouchInterval then
            runtime.state.fruitLastTry = now
            pcall(function()
                if firetouchinterest then
                    firetouchinterest(root, handle, 0)
                    firetouchinterest(root, handle, 1)
                end
            end)
            runtime.state.fruitTries = runtime.state.fruitTries + 1
            if fruitWasTaken(fruit) then
                confirmFruitPickup(fruit)
            elseif runtime.state.fruitTries >= runtime.config.FruitPickupTries then
                grabbedFruits[fruit] = now
                runtime.state.fruit = nil
                runtime.state.fruitTries = 0
                runtime.state.fruitTools = nil
                dbg("Could not pick up " .. fruit.Name)
            end
        end
    elseif now - runtime.state.fruitStart > 20 then
        grabbedFruits[fruit] = now
        runtime.state.fruit = nil
        runtime.state.fruitTries = 0
        runtime.state.fruitTools = nil
        dbg("Gave up on " .. fruit.Name)
    end
    return true
end

-- ================= STATS =================
local STAT_LIST = {"Melee", "Defense", "Sword", "Gun", "Demon Fruit"}
local STAT_MAX = 2800
local STAT_TARGETS = {
    Melee = "Melee",
    Sword = "Sword",
    Gun = "Gun",
    Fruit = "Demon Fruit",
    Defense = "Defense",
    All = "All",
}

local function dataSources()
    local list = {}
    local found = LocalPlayer:FindFirstChild("Data")
    if found then table.insert(list, found) end
    local ok, data = pcall(function() return LocalPlayer.Data end)
    if ok and type(data) == "table" and not data.FindFirstChild then
        table.insert(list, data)
    end
    return list
end

local function dataValue(name)
    for _, data in ipairs(dataSources()) do
        local value
        if data.FindFirstChild then
            value = data:FindFirstChild(name)
        else
            value = data[name]
        end
        if value ~= nil then return value end
    end
    return nil
end

local function valueOf(obj)
    if type(obj) == "string" then return obj end
    if type(obj) == "number" then return obj end
    if obj then
        local ok, value = pcall(function() return obj.Value end)
        if ok then return value end
    end
    return nil
end

local function statLevel(stat)
    for _, data in ipairs(dataSources()) do
        local stats
        if data.FindFirstChild then
            stats = data:FindFirstChild("Stats")
        else
            stats = data["Stats"]
        end
        if stats then
            local entry
            if stats.FindFirstChild then
                entry = stats:FindFirstChild(stat)
            else
                entry = stats[stat]
            end
            if entry then
                local level
                if entry.FindFirstChild then
                    level = entry:FindFirstChild("Level")
                else
                    level = entry.Level
                end
                if type(level) == "number" then return level end
                local value = readNumber(level)
                if value then return value end
            end
        end
    end
    return nil
end

local function statPoints()
    return tonumber(valueOf(dataValue("Points"))) or 0
end

local function tryUpgradeStats()
    if not runtime.config.AutoStats then return end
    local now = tick()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return end
    if now - (runtime.state.statAt or 0) < (runtime.config.AutoStatWait or 3) then return end
    local wanted = STAT_TARGETS[runtime.config.AutoStatTarget] or runtime.config.AutoStatTarget
    local targets = {}
    if wanted == "All" then
        for _, stat in ipairs(STAT_LIST) do targets[stat] = true end
    else
        targets[wanted] = true
    end
    if statPoints() <= 0 then return end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then return end
    for _, stat in ipairs(STAT_LIST) do
        if targets[stat] then
            local level = statLevel(stat)
            if level and level >= STAT_MAX then
                dbg(stat .. " is at the maximum")
            elseif level then
                local ok = pcall(function() commF:InvokeServer("AddPoint", stat, 9999) end)
                if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                    or LocalPlayer.Character ~= char then return end
                if ok then
                    runtime.state.statAt = now
                    dbg("Stat up: " .. stat)
                    return
                end
            end
        end
    end
end

runtime.takeWhirlpool = nil
takeWhirlpool = nil

-- Is this destination a place under the sea, and is the player still up here?
-- Then walking or tweening there is hopeless: the whirlpool is the way in.
local function islandPositions()
    -- The map of the game and its island parts do not change while a server
    -- runs, so they are read once a second instead of on every tick of a walk.
    local now = tick()
    local cache = runtime.state.islandCache
    if not cache or now - cache.at >= 1 then
        local list, known = {}, {}
        local ok, map = pcall(function() return Workspace:GetAttribute("MAP") end)
        if ok and type(map) == "table" then
            for name, pos in pairs(map) do
                if pos and pos.X and pos.Y and pos.Z then
                    table.insert(list, {name = tostring(name), pos = pos})
                    known[tostring(name)] = true
                end
            end
        end
        local origin = Workspace:FindFirstChild("_WorldOrigin")
        local locations = origin and origin:FindFirstChild("Locations")
        if locations then
            for _, island in ipairs(locations:GetChildren()) do
                if island:IsA("BasePart") and not known[island.Name] then
                    table.insert(list, {name = island.Name, pos = island.Position})
                    known[island.Name] = true
                end
            end
        end
        cache = {list = list, at = now}
        runtime.state.islandCache = cache
    end
    local list = {}
    for _, entry in ipairs(cache.list) do table.insert(list, entry) end
    local root = getRoot()
    table.sort(list, function(a, b)
        if root then
            local da = (root.Position - a.pos).Magnitude
            local db = (root.Position - b.pos).Magnitude
            if da ~= db then return da < db end
        end
        return a.name < b.name
    end)
    return list
end

local function needsWhirlpool(pos)
    if not (pos and pos.X and pos.Y and pos.Z) then return false end
    local root = getRoot()
    if not root then return false end
    for _, island in ipairs(islandPositions()) do
        local name = island.name:lower()
        if name:find("underwater", 1, true) or name:find("submerged", 1, true) then
            -- the destination is inside that place and we are still up here
            if (island.pos - pos).Magnitude < 4000
                and (root.Position - island.pos).Magnitude > 2000 then
                return true
            end
        end
    end
    return false
end

-- Where the warp door of the sea is: the whirlpool island of the game, with
-- the whirlpool part of the world as the fallback.
function runtime.whirlpoolPos()
    for _, island in ipairs(islandPositions()) do
        if island.name:lower():find("whirlpool", 1, true) then return island.pos end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name:lower():find("whirlpool", 1, true) then
            local a = anchorOf(obj)
            if a then return a.Position end
        end
    end
    return nil
end
whirlpoolPos = runtime.whirlpoolPos

function runtime.travelTo(cf, noWarp)
    -- A farm under the sea goes through the whirlpool of the sea first: fly
    -- there with the tween of the script, let the game drop the player under
    -- the sea, and only then walk the rest of the way. Nothing on this route
    -- is ever warped: a teleport here is what made the character jump around.
    if not noWarp and not runtime.state.whirlpooling and runtime.takeWhirlpool
        and needsWhirlpool(cf.Position) then
        runtime.state.whirlpooling = true
        runtime.takeWhirlpool()
        runtime.state.whirlpooling = false
        noWarp = true
    end
    runtime.moveTo(cf, noWarp)
    return false
end
travelTo = runtime.travelTo


-- ================= WORLD (SEA) TRAVEL =================
local WORLD_TRAVEL = {"TravelMain", "TravelDressrosa", "TravelZou"}

-- The seas are separate places: the game moves the whole character between
-- them, and the remotes are the ones BananaHub uses.
local function travelToWorld(world)
    local what = WORLD_TRAVEL[world]
    if not what then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return false end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    local ok = pcall(function() commF:InvokeServer(what) end)
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if ok then
        dbg("Travelling to world " .. tostring(world))
        return true
    end
    dbg("The game did not take the travel to world " .. tostring(world))
    return false
end

-- ================= FLY TO AN ISLAND =================

-- Some islands cannot be tweened to at all (the sea floor, the islands the
-- game only opens through a door). For those the game itself is asked to move
-- the player. The remotes are the ones BananaHub uses.
-- Fly to a place with the tween of the script: no jump, no portal, just a
-- straight tween across the sea, like the player would glide over.
local function flyTo(position)
    local root = getRoot()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not root or not position or not char then return false end
    if runtime.state.flying then
        dbg("Already flying to an island")
        return false
    end
    runtime.state.flying = true
    runtime.stopTween()
    local here = root.Position
    local distance = (here - position).Magnitude
    dbg("Flying to the island (" .. tostring(math.floor(distance)) .. " studs)")
    runtime.setFlying()
    local stale = false
    local ok, err = pcall(function()
        -- A long flight goes up first, then over, then down. A straight line
        -- across the sea dips into the water, and the game drops a character
        -- that touches it. Each leg is the very same tween as the walk to a mob.
        local high = math.max(here.Y, position.Y) + 60
        local legs = {
            {point = Vector3.new(here.X, high, here.Z), slack = 12},
            {point = Vector3.new(position.X, high, position.Z), slack = 24},
            {point = position + Vector3.new(0, 6, 0), slack = 12},
        }
        for _, leg in ipairs(legs) do
            runtime.tweenTo(CFrame.new(leg.point))
            local deadline = tick() + math.max(distance / runtime.config.MoveSpeed, 0.12) + 8
            while tick() < deadline do
                local now = getRoot()
                if not now then break end
                if (now.Position - leg.point).Magnitude <= leg.slack then break end
                -- a flight that is going somewhere is not a task that got stuck
                runtime.state.blockAt = tick()
                task.wait(0.2)
                if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                    or LocalPlayer.Character ~= char then
                    stale = true
                    break
                end
            end
            if stale then break end
        end
    end)
    runtime.state.flying = false
    if runtime.isCurrent() and runtime.characterEpoch == epoch
        and LocalPlayer.Character == char then
        runtime.setWalking()
    end
    if stale then return false end
    if not ok then
        dbg("The flight failed: " .. tostring(err))
        return false
    end
    return true
end

-- The submarine of the game only takes the player from its own spot at Tiki,
-- so the bot has to tween there first. The point is the one BananaHub uses.
local SUBMERGED_FLY = Vector3.new(-16269.41, 23.98, 1371.66)

local function specialTravel(name)
    local lower = tostring(name):lower()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return false end
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    if not net then
        dbg("The Net module of the game was not found")
        return false
    end
    if lower:find("underwater", 1, true) or lower:find("submerged", 1, true) then
        -- stand at the submarine first, then let it take us down
        dbg("Flying to the submarine of " .. tostring(name))
        flyTo(SUBMERGED_FLY)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
        local sub = net:FindFirstChild("RF/SubmarineWorkerSpeak")
        if not sub then
            dbg("The submarine remote of the game was not found")
            return false
        end
        local ok = pcall(function() sub:InvokeServer("TravelToSubmergedIsland") end)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
        if ok then
            dbg("Asked the submarine to take us to " .. tostring(name))
            return true
        end
        dbg("The submarine refused to take us")
        return false
    end
    return false
end

-- ================= MELEE / ABILITY SHOP =================
-- The styles of the wiki, in the order they can be bought: the first form
-- of a style comes before its second form (Death Step needs Dark Step, and
-- so on), and Superhuman comes before Godhuman.
-- level = the level the player has to be, item = an item the teacher asks for
-- before it takes the buy, needs/mastery = the older form whose mastery is
-- asked for (the wiki). The game itself is the last judge of all of them.
local STYLE_SHOP = {
    {name = "Dark Step",       remote = "BuyBlackLeg",       teacher = "Dark Step Teacher"},
    {name = "Electric",        remote = "BuyElectro",        teacher = "Mad Scientist"},
    {name = "Water Kung Fu",   remote = "BuyFishmanKarate",  teacher = "Water Kung Fu Teacher"},
    {name = "Dragon Breath",   remote = "BuyDragonBreath",   teacher = "Sabi"},
    {name = "Superhuman",      remote = "BuySuperhuman",     teacher = "Martial Arts Master", level = 300},
    {name = "Death Step",      remote = "BuyDeathStep",      teacher = "Phoeyu, the Reformed",
        item = "Library Key", needs = "Dark Step", mastery = 400, cost = 2500000},
    {name = "Electric Claw",   remote = "BuyElectricClaw",   teacher = "Previous Hero",
        level = 1000, needs = "Electric", mastery = 400},
    {name = "Sharkman Karate", remote = "BuySharkmanKarate", teacher = "Sharkman Teacher",
        level = 1000, needs = "Water Kung Fu", mastery = 400},
    {name = "Dragon Talon",    remote = "BuyDragonTalon",    teacher = "Uzoth",
        level = 1500, needs = "Dragon Breath", mastery = 400},
    {name = "Godhuman",        remote = "BuyGodhuman",       teacher = "Ancient Monk", level = 3000},
    {name = "Sanguine Art",    remote = "BuySanguineArt",    teacher = "Shafi", level = 3000},
    {name = "Advanced Combat", remote = "BuyAdvancedCombat", teacher = "Secrets Master"},
}

-- The item a teacher asks for is carried as a tool or kept as a value of the
-- player data: the backpack, the hand and the values are all looked at.
-- The money of the player, wherever this build keeps it: the folder of the
-- player data, a leaderstat or a plain value on the player are all looked at.
-- When none of them is there the number is nil and nothing is blocked.
myBeli = function()
    local player = LocalPlayer
    if not player then return nil end
    local v = nil
    local function read(obj)
        if type(obj) == "number" then return obj end
        if type(obj) == "table" and type(obj.Value) == "number" then return obj.Value end
        return nil
    end
    pcall(function() v = read(player:FindFirstChild("Beli")) end)
    if not v then pcall(function() v = read(player.leaderstats and player.leaderstats:FindFirstChild("Beli")) end) end
    if not v then
        pcall(function()
            local data = player:FindFirstChild("Data")
            v = read(data and data:FindFirstChild("Beli"))
        end)
    end
    if not v then
        pcall(function() v = player:GetAttribute("Beli") end)
    end
    if type(v) ~= "number" then return nil end
    return v
end

hasItem = function(name)
    local wanted = tostring(name):lower()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, folder in ipairs({char, backpack}) do
        if folder then
            for _, t in ipairs(folder:GetChildren()) do
                if t.Name:lower():find(wanted, 1, true) then return true end
            end
        end
    end
    local hit = false
    pcall(function()
        for _, d in ipairs(LocalPlayer:GetDescendants()) do
            if d:IsA("StringValue") and d.Name:lower():find(wanted, 1, true)
                and d.Value ~= nil and d.Value ~= false then
                hit = true
            end
        end
    end)
    return hit
end

local function shopRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_")
end

local function findTeacher(name)
    local folders = {Workspace:FindFirstChild("NPCs"), ReplicatedStorage:FindFirstChild("NPCs")}
    for _, folder in ipairs(folders) do
        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                local ready = true
                pcall(function()
                    if npc:GetAttribute("NPCLoaded") == false or npc:GetAttribute("NPCReady") == false then
                        ready = false
                    end
                end)
                if npc.Name == name and ready and anchorOf(npc) then return npc end
            end
        end
    end
    for _, npc in ipairs(Workspace:GetChildren()) do
        if npc:IsA("Model") and npc.Name == name and anchorOf(npc) then return npc end
    end
    local manager = ReplicatedStorage:FindFirstChild("NPCManager")
    if manager then
        local ok, npc = pcall(function()
            local mod = require(manager)
            local list = mod.getNPCsByName(name)
            local first = list and list[1]
            return first and first._modelState and first._modelState._instance
        end)
        if ok and npc and anchorOf(npc) then return npc end
    end
    return nil
end

-- The teacher of these styles stands under the sea (Underwater): the way
-- there is the whirlpool of the sea, which drops the player in.
local WHIRLPOOL_STYLES = {["Fishman Karate"] = true, ["Water Kung Fu"] = true}


-- Fly to the whirlpool of the sea and wait until the game drops the player
-- under it. That is the way to Underwater (the Water Kung-fu teacher lives
-- there too). Nothing here is warped: it is a normal flight at MoveSpeed.
function runtime.takeWhirlpool()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return false end
    local pos = runtime.whirlpoolPos()
    if not pos then
        dbg("The whirlpool of the sea was not found")
        return false
    end
    dbg("Flying into the whirlpool of the sea")
    flyTo(pos)
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    -- the place to compare against is where the flight left the player: the
    -- jump the game does from here is what puts us under the sea
    local root = getRoot()
    local before = root and root.Position
    local deadline = tick() + 20
    while tick() < deadline do
        local now = getRoot()
        if not now then break end
        runtime.state.blockAt = tick()
        if before and (now.Position - before).Magnitude > 500 then
            dbg("The whirlpool took us under the sea")
            -- the mobs and the givers under the sea are streamed in a moment
            -- later: the farm starts when the place is there
            task.wait(0.8)
            if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                or LocalPlayer.Character ~= char then return false end
            return true
        end
        runtime.travelTo(CFrame.new(pos), true)
        task.wait(0.3)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    dbg("The whirlpool did not take us this time")
    return false
end
takeWhirlpool = runtime.takeWhirlpool

-- The game only takes the buy when the player stands at the teacher of the
-- style, so the bot walks to it first and asks there.
local function buyStyle(style)
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    if runtime.state.shopping or runtime.state.shopInFlight then
        dbg("A buy is already running")
        return false
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return false end

    -- What the style needs is checked before the walk: a teacher that will
    -- refuse is a wasted trip, and the player has to see why nothing happened.
    if style.level and getMyLevel() < style.level then
        dbg("Auto buy: " .. style.name .. " needs level " .. style.level
            .. ", we are " .. getMyLevel())
        return false
    end
    if style.item and not hasItem(style.item) then
        dbg("Auto buy: " .. style.name .. " needs " .. style.item .. " first")
        return false
    end
    -- money first: the walk to the teacher is only worth it when it can be paid
    local beli = myBeli()
    if style.cost and beli and beli < style.cost then
        dbg("Auto buy: " .. style.name .. " costs " .. style.cost
            .. " Beli, we have " .. math.floor(beli))
        return false
    end

    -- An unknown reply is not a refusal, but it is also not permission to send
    -- the same purchase over and over. It gets a short cooldown.
    local unknownAt = runtime.state.shopUnknown[style.remote]
    if unknownAt and tick() - unknownAt < 60 then
        dbg("Auto buy: " .. style.name .. " has an unknown result; waiting before retrying")
        return nil
    end

    local requestToken = (runtime.state.shopToken or 0) + 1
    runtime.state.shopToken = requestToken
    runtime.state.shopping = true
    if WHIRLPOOL_STYLES[style.name] then
        runtime.takeWhirlpool()
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    local npc = findTeacher(style.teacher)
    local near = false
    if npc then
        local deadline = tick() + 25
        pcall(function()
            while tick() < deadline do
                if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                    or LocalPlayer.Character ~= char then return false end
                local root, anchor = getRoot(), anchorOf(npc)
                if not root or not anchor then break end
                runtime.state.blockAt = tick()
                if (root.Position - anchor.Position).Magnitude <= 8 then
                    near = true
                    break
                end
                runtime.travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)), true)
                task.wait(0.2)
            end
        end)
    end
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if runtime.state.shopToken ~= requestToken then return false end

    -- The game's own dialogue asks the same remote with true to learn whether
    -- the style is already owned. Advanced Combat has no such check in the
    -- live dialogue list, so it is never asked with the extra argument.
    if style.remote ~= "BuyAdvancedCombat" then
        local checkOk, owned = pcall(function() return commF:InvokeServer(style.remote, true) end)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
        if runtime.state.shopToken ~= requestToken then return false end
        if checkOk and owned == 1 then
            runtime.state.shopping = false
            runtime.state.shopUnknown[style.remote] = nil
            dbg("Auto buy: " .. style.name .. " is already owned")
            return true
        end
    end

    -- Send the request once. Repeating it can buy the same style more than
    -- once when the server has no reply yet. The live buy RPCs answer 1 for a
    -- successful purchase and 2 when the style is already known.
    runtime.state.shopInFlight = true
    local ok, reply = pcall(function() return commF:InvokeServer(style.remote) end)
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if runtime.state.shopToken ~= requestToken then return false end
    runtime.state.shopInFlight = false
    runtime.state.shopping = false

    local bought
    if not ok then
        bought = false
        runtime.state.shopUnknown[style.remote] = nil
        dbg("The buy request for " .. style.name .. " failed")
    elseif reply == 1 or reply == true then
        bought = true
        runtime.state.shopUnknown[style.remote] = nil
    elseif reply == 2 then
        bought = true
        runtime.state.shopUnknown[style.remote] = nil
        dbg(style.name .. " was already owned")
    elseif reply == nil then
        bought = nil
        runtime.state.shopUnknown[style.remote] = tick()
        dbg("The game did not answer the buy of " .. style.name)
    else
        bought = false
        runtime.state.shopUnknown[style.remote] = nil
        dbg("The game refused the buy of " .. style.name
            .. " (reply " .. tostring(reply) .. ")")
    end
    dbg("Buy " .. style.name .. " from " .. (npc and "the teacher" or "far away")
        .. (npc and (near and " (stood at it)" or " (could not reach it)") or " (no teacher was seen)")
        .. (bought == true and " (the game took it)"
            or (bought == false and " (the game refused it)" or " (result unknown)")))
    return bought
end

local function buyAbility(remote, what)
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    if runtime.state.shopping or runtime.state.shopInFlight then
        dbg("A buy is already running")
        return false
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    if not char then return false end
    local requestToken = (runtime.state.shopToken or 0) + 1
    runtime.state.shopToken = requestToken
    runtime.state.shopping = true
    runtime.state.shopInFlight = true
    local ok, reply = pcall(function() return commF:InvokeServer(remote, what) end)
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if runtime.state.shopToken ~= requestToken then return false end
    runtime.state.shopInFlight = false
    runtime.state.shopping = false
    if not ok then
        dbg("The buy request for " .. tostring(what) .. " failed")
        return false
    end
    if reply == 1 or reply == true then
        dbg("The game took the buy of " .. tostring(what))
        return true
    end
    if reply == 2 then
        dbg(tostring(what) .. " was already owned")
        return true
    end
    if reply == nil then
        dbg("The game did not answer the buy of " .. tostring(what))
        return nil
    end
    dbg("The game refused the buy of " .. tostring(what)
        .. " (reply " .. tostring(reply) .. ")")
    return false
end

-- ================= MAIN LOOP =================
-- The mobs that were frozen for the farm are let go again with this.

local function releaseBringMobs()
    for mob, part in pairs(runtime.state.bringHeld) do
        runtime.letGoMob(mob, part)
    end
    runtime.state.bringHeld = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlot = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlotCount = 0
    -- the point of the last pack dies with it, so the next fight is gathered
    -- where the fight actually is
    runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
    runtime.state.bringMoved = setmetatable({}, {__mode = "k"})
    runtime.state.bringHealth = setmetatable({}, {__mode = "k"})
    runtime.state.bringSaved = setmetatable({}, {__mode = "k"})
    runtime.state.bringSnapped = setmetatable({}, {__mode = "k"})
    runtime.state.bringCarryingTarget = setmetatable({}, {__mode = "k"})
    runtime.state.bringOwned = setmetatable({}, {__mode = "k"})
    runtime.state.bringMover = setmetatable({}, {__mode = "k"})
    runtime.state.bringMoverId = setmetatable({}, {__mode = "k"})
    runtime.state.bringAt = 0
    -- markers left by older builds are removed; nothing creates them any more
    for mob in pairs(runtime.state.bringIgnored) do
        local marker = mob:FindFirstChild("FarmIgnored")
        if marker then pcall(function() marker:Destroy() end) end
    end
    runtime.state.bringIgnored = setmetatable({}, {__mode = "k"})
end


-- Everything that pointed at the character that just died is dropped here.
-- Without this the farm keeps chasing a corpse: the old target, the old
-- bring point, the old fruit and the old tween all stay behind.
local function fullReset(reason)
    -- Every operation that can yield captures this epoch. A respawn or a
    -- character removal invalidates those operations before they can move or
    -- mutate the new character.
    runtime.characterEpoch = (runtime.characterEpoch or 0) + 1
    runtime.stopTween()
    restoreNoclip()
    releaseBringMobs()
    restoreHitbox()
    runtime.resetTransient(reason or "character reset")
    raiseSimulationRadius()
    runtime.state.farming = false
    runtime.state.fruit, runtime.state.fruitTools, runtime.state.fruitTries = nil, nil, 0
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt, runtime.state.targetDist = nil, nil, 0, nil
    runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
    runtime.state.bringMoved = setmetatable({}, {__mode = "k"})
    runtime.state.bringIgnored = setmetatable({}, {__mode = "k"})
    runtime.state.bringHealth = setmetatable({}, {__mode = "k"})
    runtime.state.bringHeld = setmetatable({}, {__mode = "k"})
    runtime.state.bringSaved = setmetatable({}, {__mode = "k"})
    runtime.state.bringSnapped = setmetatable({}, {__mode = "k"})
    runtime.state.bringCarryingTarget = setmetatable({}, {__mode = "k"})
    runtime.state.bringOwned = setmetatable({}, {__mode = "k"})
    runtime.state.bringMover = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlot = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlotCount = 0
    runtime.state.bringAt = 0
    runtime.state.flying, runtime.state.shopping, runtime.state.questing, runtime.state.whirlpooling = false, false, false, false
    runtime.state.shopToken = (runtime.state.shopToken or 0) + 1
    runtime.state.shopInFlight = false
    runtime.state.shopUnknown = {}

    -- A reset starts the quest bookkeeping from scratch. The server may still
    -- know the quest, but the next QuestUpdate is what verifies it again.
    runtime.state.currentQuest = nil
    runtime.state.questSentAt = 0
    runtime.state.lastQuestTry = 0
    runtime.state.questDone = false
    runtime.state.questDoneMob = nil
    runtime.state.questAsked = nil
    runtime.state.questAskedAt = 0
    runtime.state.questSeenUntil = 0
    runtime.state.questVerified = false
    runtime.state.questGaveUp = false
    runtime.state.questTryKey = nil
    runtime.state.questTried = {}
    runtime.state.questIndexTry = nil
    runtime.state.bossQuestName = nil
    runtime.state.bossQuestUntil = nil
    runtime.state.bossQuestCd = 0

    runtime.state.turnInSince, runtime.state.turnInFailed, runtime.state.turnInFailedAt = nil, false, 0
    runtime.state.seekSince, runtime.state.seekGaveUp, runtime.state.seekGaveUpAt = nil, false, 0
    runtime.state.panelInfo, runtime.state.questNpc, runtime.state.questPos = nil, nil, nil
    runtime.state.lastSafe, runtime.state.lastPos, runtime.state.movedAt = nil, nil, 0
    stuckTargets = {}
    enemyCache, enemyCacheAt = {}, 0
    runtime.state.otherPlayerCache = nil
    runtime.state.spawnCentreCache = nil
    gameQuestCache, gameQuestCacheAt = nil, nil
    giverCache, giverCacheAt = {}, -999
    for fruit in pairs(grabbedFruits) do grabbedFruits[fruit] = nil end

    -- Character-bound combat objects must not survive a respawn. The remote
    -- wrappers, the controller and the hit-session coroutine all belong to
    -- the old character.
    if runtime.hitThread then
        runtime.hitRequest = {stop = true}
        pcall(coroutine.resume, runtime.hitThread)
    end
    combatController = nil
    runtime.state.combatUtil, runtime.state.combatUtilMod = nil, nil
    runtime.state.netModule, runtime.state.netModuleInstance = nil, nil
    runtime.state.hitRemoteCache, runtime.state.attackRemoteCache = nil, nil
    runtime.hitSessionId, runtime.hitThread, runtime.hitThreadRemote = nil, nil, nil
    runtime.hitRequest, runtime.hitResult = nil, nil
    runtime.hitHandshakeOk, runtime.hitHandshakeError = false, nil
    runtime.state.hitUseFallback = false
    dbg("Reset after: " .. tostring(reason))
end

-- Register the gameplay cleanup with the one teardown installed at the top.
-- The function values are captured on this runtime, so a later execution can
-- never make this run stop or restore the newer run's movement by name.
if not runtime.disposed then
    runtime.restoreNoclip = restoreNoclip
    runtime.releaseBringMobs = releaseBringMobs
    runtime.restoreHitbox = restoreHitbox
    table.insert(runtime.cleanupFns, function() runtime.stopTween() end)
    table.insert(runtime.cleanupFns, function() runtime.restoreNoclip() end)
    table.insert(runtime.cleanupFns, function() runtime.releaseBringMobs() end)
    table.insert(runtime.cleanupFns, function() runtime.restoreHitbox() end)
    table.insert(runtime.cleanupFns, function() runtime.resetTransient("teardown") end)
end

-- The game makes the player sit on the death screen for a few seconds before
-- it brings the character back, and that is slow when a farm kills the player.
-- The screen has its own respawn button: pressing it brings the character back
-- at once. When that button is not there nothing is done, the game still
-- respawns on its own, only slower.
runtime.pressRespawn = function()
    local pressed = false
    -- Every way a death screen is answered: its own signal, the connections of
    -- that signal, the two mouse signals, a real click at its place on the
    -- screen and the virtual mouse of the game. The screen of the game is not
    -- always the one the script expects, so the gui of the player and the core
    -- gui are both walked.
    local function press(button)
        pcall(function() if firesignal and button.Activated then firesignal(button.Activated) end end)
        pcall(function() if firesignal and button.MouseButton1Click then firesignal(button.MouseButton1Click) end end)
        pcall(function() if firesignal and button.MouseButton1Down then firesignal(button.MouseButton1Down) end end)
        pcall(function()
            if getconnections and button.MouseButton1Click then
                for _, c in ipairs(getconnections(button.MouseButton1Click)) do
                    pcall(function() c.Function() end)
                end
            end
        end)
        pcall(function()
            if mouse1click and button.AbsolutePosition then
                local size = button.AbsoluteSize
                mouse1click(button.AbsolutePosition.X + (size and size.X or 0) / 2,
                    button.AbsolutePosition.Y + (size and size.Y or 0) / 2)
            end
        end)
        pcall(function()
            if button.AbsolutePosition and button.AbsoluteSize then
                local vim = game:GetService("VirtualInputManager")
                local x = button.AbsolutePosition.X + button.AbsoluteSize.X / 2
                local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2
                vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
                vim:SendMouseButtonEvent(x, y, 0, false, game, 1)
            end
        end)
    end
    local function shown(button)
        local node = button
        while node do
            if node:IsA("GuiObject") and node.Visible == false then return false end
            node = node.Parent
        end
        return true
    end
    -- The gui of this script is not a death screen: pressing its own switches
    -- is how the farm got turned off by a respawn press. It lives in CoreGui
    -- when the executor allows that and in PlayerGui otherwise, so both are
    -- looked at before any button is pressed.
    local ownGui = nil
    pcall(function()
        ownGui = game:GetService("CoreGui"):FindFirstChild("CustomFarmGui")
            or (LocalPlayer:FindFirstChild("PlayerGui")
                and LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("CustomFarmGui"))
    end)
    local function look(folder)
        if not folder then return end
        local ok, list = pcall(function() return folder:GetDescendants() end)
        if not ok then return end
        for _, obj in ipairs(list) do
            if obj:IsA("GuiButton") and obj.Visible and shown(obj)
                and not (ownGui ~= nil and obj:IsDescendantOf(ownGui)) then
                local word = (tostring(obj.Text or "") .. " " .. tostring(obj.Name or "")):lower()
                if word:find("respawn", 1, true) or word:find("spawn", 1, true)
                    or word:find("revive", 1, true) or word:find("retry", 1, true)
                    or word:find("play again", 1, true) or word:find("continue", 1, true)
                    or word:find("rebirth", 1, true) or word:find("เกิดใหม่", 1, true) then
                    press(obj)
                    pressed = true
                    dbg("Pressed respawn: " .. tostring(obj.Name))
                end
            end
        end
    end
    local player = LocalPlayer
    look(player and (player.PlayerGui or player:FindFirstChild("PlayerGui")))
    pcall(function() look(game:GetService("CoreGui")) end)
    -- A button with no telling name is never pressed: a blind press over every
    -- button on screen hits the shops and the switches of the game, and the
    -- game respawns the character on its own when no button is found.
    if not pressed then dbg("Death screen: no respawn button found yet") end
    return pressed
end
pressRespawn = runtime.pressRespawn

local function step()
    local root, hum = getRoot(), getHumanoid()
    local now = tick()
    if not root or not hum or hum.Health <= 0 then
        if not runtime.state.dead then
            runtime.state.dead = true
            fullReset("the character died")
        end
        runtime.state.status = "Respawning..."
        -- the death screen is looked at twice a second, not every tick
        -- the death screen is asked twice a second until it answers
        if not runtime.state.respawnAt or now - runtime.state.respawnAt > 0.2 then
            runtime.state.respawnAt = now
            pcall(pressRespawn)
        end
        return
    end
    if runtime.state.dead then
        runtime.state.dead = false
        dbg("The character is back, farming again")
    end

    if runtime.state.shakerAt == nil or now - runtime.state.shakerAt > 30 then
        runtime.state.shakerAt = now
        stopCameraShaker()
    end

    -- A boss that never shows up must not keep the bot away from the mobs:
    -- after the deadline the boss quests are left alone for a while.
    if runtime.state.bossQuestName and runtime.state.bossQuestUntil and now > runtime.state.bossQuestUntil then
        runtime.state.bossQuestCd = now + 300
        runtime.state.bossQuestName, runtime.state.bossQuestUntil = nil, nil
        dbg("Boss quest timed out, back to the mobs for a while")
    end

    if root.Position.Y < runtime.config.SafeY and now >= runtime.state.recoverUntil then
        local y = root.Position.Y
        runtime.stopTween()
        restoreNoclip()
        runtime.state.recoverUntil = now + 2
        runtime.state.status = "Recovering..."
        if runtime.state.lastSafe then
            root.CFrame = CFrame.new(runtime.state.lastSafe)
            dbg(string.format("Recovered from out-of-bounds (Y=%.0f)", y))
        else
            dbg(string.format("Out of bounds (Y=%.0f), no safe spot yet", y))
        end
        return
    end

    -- Auto Saber has its own lock and timeout. During a kill step the farm
    -- is allowed to run so that the boss can actually be attacked; the other
    -- puzzle steps own the movement and pause the ordinary farm.
    if runtime.state.saberActive then
        local timeout = runtime.config.AutoSaberTimeout or 90
        local progressAt = runtime.state.saberProgressAt
        if not progressAt or progressAt <= 0 then progressAt = runtime.state.saberLockAt or now end
        if now - progressAt > timeout then
            runtime.config.AutoSaber = false
            runtime.resetTransient("Saber timeout")
            runtime.state.farming = false
            dbg("Saber made no progress and was stopped")
            return
        elseif not runtime.state.saberTarget then
            runtime.state.farming = false
            return
        else
            -- During a kill step the ordinary quest target must not replace
            -- the Saber boss. The farm is allowed to run only after that boss
            -- is actually present.
            local saberMob = nil
            for _, candidate in ipairs(collectEnemies(now)) do
                if candidate.Name:lower():find(runtime.state.saberTarget:lower(), 1, true) then
                    saberMob = candidate
                    break
                end
            end
            if not saberMob then
                runtime.state.farming = false
                return
            end
        end
    end

    -- A shop buy or a flight owns the movement while it runs. One of them that
    -- never comes back (an error in the middle) is let go after a while, or
    -- the whole farm would stand still for ever.
    if runtime.state.shopping or runtime.state.flying then
        if not runtime.state.blockAt then runtime.state.blockAt = now end
        local timedOut = now - runtime.state.blockAt > 25
        if timedOut and runtime.state.shopping and not runtime.state.shopInFlight then
            runtime.state.shopping = false
            runtime.state.blockAt = nil
            runtime.stopTween()
            dbg("A long shopping walk got stuck, farming again")
        elseif timedOut and runtime.state.flying then
            runtime.state.flying = false
            runtime.state.blockAt = nil
            runtime.stopTween()
            dbg("A long flight got stuck, farming again")
        end
        if runtime.state.shopping or runtime.state.flying then return end
    else
        runtime.state.blockAt = nil
    end

    if not runtime.state.lastPos or (root.Position - runtime.state.lastPos).Magnitude > 1 then
        runtime.state.lastPos = root.Position
        runtime.state.movedAt = now
    end
    if now - runtime.state.movedAt > 0.4 and root.Position.Y > runtime.config.SafeY then
        runtime.state.lastSafe = root.Position
    end

    if runtime.config.FruitSniper then
        runtime.state.farming = true
        if handleFruit(root) then return end
    end

    -- The panel is walked and parsed at its own pace: it changes slowly and
    -- the walk through every text 20 times a second is a waste. Between two
    -- parses the last answer is kept, so nothing flickers.
    local info = nil
    if runtime.config.AutoQuest then
        if not runtime.state.panelAt or now - runtime.state.panelAt > 0.3 then
            runtime.state.panelAt = now
            runtime.state.panelInfo = questPanelInfo()
        end
        info = runtime.state.panelInfo
    end

    if runtime.config.AutoQuest then
        hookQuestRemote()
        local remoteInfo = remoteQuestInfo()
        if remoteInfo then info = remoteInfo end
    end
    hookHitRemote()
    hookStatsRemote()

    if info then
        if info.complete then
            runtime.state.questDone = true
            runtime.state.questDoneMob = info.mentioned or info.target
        elseif info.confirmed then
            runtime.state.questDone = false
            runtime.state.questDoneMob = nil
        end
    end

    if runtime.config.AutoStore and now - (runtime.state.storeAt or 0) > 5 then
        local fruits = carriedFruits()
        if #fruits >= (runtime.config.StoreFruitMin or 3) then
            runtime.state.storeAt = now
            local before = #fruits
            local stored = 0
            for _, f in ipairs(fruits) do
                if stored >= 4 then break end
                if storeFruit(f) then stored = stored + 1 end
            end
            stored = before - #carriedFruits()
            if stored > 0 then
                runtime.state.status = "Stored " .. stored .. " fruit(s)"
                dbg("Stored " .. stored .. " fruit(s)")
            else
                local npc = storageNpc()
                local prompt = npc and promptOf(npc)
                local anchor = (prompt and anchorOf(prompt.Parent)) or (npc and anchorOf(npc))
                if anchor and prompt then
                    runtime.state.status = "Storing fruit"
                    runtime.travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
                    interactWith(npc, prompt)
                    task.wait(0.5)
                    for _, f in ipairs(fruits) do
                        if stored >= 4 then break end
                        if useFruitMenu(f.Name, {"deposit", "store"}) then stored = stored + 1 end
                    end
                    stored = before - #carriedFruits()
                    if stored > 0 then
                        runtime.state.status = "Stored " .. stored .. " fruit(s)"
                        dbg("Stored " .. stored .. " fruit(s) at the npc")
                    else
                        runtime.state.status = "Could not store fruit"
                    end
                else
                    runtime.state.status = "No way to store fruit"
                    dbg("No store button and no storage npc")
                end
            end
            return
        end
    end

    local pendingTurnIn = (info and info.complete) or runtime.state.questDone
    if pendingTurnIn and runtime.config.QuestTurnIn then
        if runtime.state.turnInFailed and now - runtime.state.turnInFailedAt > runtime.config.TurnInTimeout then
            runtime.state.turnInFailed, runtime.state.turnInSince = false, now
            runtime.state.questDone = false
            runtime.state.questDoneMob = nil
        end
        if not runtime.state.turnInFailed then
            local giver = pickQuestGiver((info and info.mentioned) or runtime.state.questDoneMob, runtime.state.questNpc)
            local prompt = giver and promptOf(giver)
            local anchor = (prompt and anchorOf(prompt.Parent)) or (giver and anchorOf(giver))
            if anchor and prompt then
                if runtime.state.turnInSince == nil then runtime.state.turnInSince = now end
                if now - runtime.state.turnInSince <= runtime.config.TurnInTimeout then
                    runtime.state.status = "Turning in quest"
                    runtime.travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
                    interactWith(giver, prompt)
                    return
                end
                dbg("Turn-in timed out, farming instead")
                runtime.state.turnInFailed, runtime.state.turnInFailedAt = true, now
            else
                dbg("No usable quest giver found")
                runtime.state.turnInFailed, runtime.state.turnInFailedAt = true, now
                runtime.state.status = "Quest complete, no giver found"
            end
        end
    else
        runtime.state.turnInSince, runtime.state.turnInFailed, runtime.state.turnInFailedAt = nil, false, 0
    end

    if runtime.config.AutoQuest then tryAcceptQuest(info) end
    if runtime.config.AutoStats then tryUpgradeStats() end

    local needGiver = not questFor(getMyLevel()) or runtime.state.questGaveUp
    if runtime.config.AutoQuest and needGiver and not (info and info.confirmed) then
        if runtime.state.seekSince == nil then runtime.state.seekSince = now end
        if runtime.state.seekGaveUp then
            if now - runtime.state.seekGaveUpAt >= runtime.config.QuestSeekTimeout then
                runtime.state.seekGaveUp = false
                runtime.state.seekSince = now
            end
        elseif now - runtime.state.seekSince > runtime.config.QuestSeekTimeout then
            dbg("No quest giver answered, farming instead")
            runtime.state.seekGaveUp, runtime.state.seekGaveUpAt = true, now
        else
            local giver = pickQuestGiver(nil, runtime.state.questGaveUp and runtime.state.questNpc or nil)
            local prompt = giver and promptOf(giver)
            local anchor = (prompt and anchorOf(prompt.Parent)) or (giver and anchorOf(giver))
            if anchor then
                runtime.state.status = "Looking for a quest"
                runtime.travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
                interactWith(giver, prompt)
                return
            end
        end
    else
        runtime.state.seekSince = nil
        runtime.state.seekGaveUp = false
    end

    if not runtime.config.AutoFarm then
        runtime.state.farming = false
        runtime.state.status = "Idle"
        -- nothing is being farmed: the pack of the last mob is let go and the
        -- hitbox that was made big for the swing is put back
        restoreHitbox()
        if next(runtime.state.bringHeld) ~= nil or next(runtime.state.bringIgnored) ~= nil then releaseBringMobs() end
        runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
        if runtime.config.AutoAttack then autoAttackSwing(nil) end
        return
    end
    runtime.state.farming = true

    local quest = runtime.config.AutoQuest and questFor(getMyLevel()) or nil
    local mob = quest and quest.mob or nil
    local bossWindow = runtime.config.BossLevelWindow or 25
    local function bossAllowedFor(name)
        if not runtime.config.BossFarm or not bossNameIs(name) then return false end
        local level = bossLevelOf and bossLevelOf(name)
        return level == nil or math.abs(level - getMyLevel()) <= bossWindow
    end
    if info and info.target then
        -- The live quest overrides the guide, unless it is a boss the boss
        -- farm is not allowed to take.
        if not bossNameIs(info.target) or bossAllowedFor(info.target) then
            mob = info.target
        end
    end

    local target
    if mob and bossNameIs(mob) then
        if bossAllowedFor(mob) then
            -- Prefer the exact quest boss; no other boss is taken instead.
            target = pickBoss(root, runtime.config.BossRange or 3000, mob)
            -- The boss is dead or out of range: farm normal mobs around the
            -- spawn and pick the boss up again when it respawns.
            if not target then target = pickNormal(root) end
        else
            -- Boss farm off, or the boss is too far from the player's level.
            -- Do not let the normal quest picker walk into it anyway.
            mob = nil
            target = pickNormal(root)
        end
    else
        target = getTarget(mob)
    end
    if runtime.state.saberTarget then
        -- a running quest knows which mob it needs
        for _, m in ipairs(collectEnemies(tick())) do
            if m.Name:lower():find(runtime.state.saberTarget:lower(), 1, true) then
                target = m
                break
            end
        end
    end
    if not target then
        -- there is no mob to farm at this moment: the pack of the last target
        -- is released and the enlarged hitbox restored, or the mobs would stay
        -- frozen and big while the bot only flies to a spawn
        restoreHitbox()
        if next(runtime.state.bringHeld) ~= nil or next(runtime.state.bringIgnored) ~= nil then releaseBringMobs() end
        runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
        local sp = findSpawn(mob)
        local anchor = sp and anchorOf(sp)
        if anchor then
            runtime.state.status = "Travelling to " .. (mob or "mobs")
            runtime.travelTo(anchor.CFrame + Vector3.new(0, runtime.config.HoverHeight, 0))
        else
            runtime.state.status = "No targets"
        end
        return
    end

    -- The mark the game itself puts on a mob is cleared before it is attacked:
    -- a stale one is what left a single mob unkillable. The stuck book of the
    -- script is left alone here, it is what gives up on a mob that cannot be
    -- reached or killed.
    local stale = target:FindFirstChild("Ignored")
    if stale then pcall(function() stale:Destroy() end) end

    local er = anchorOf(target)
    if not er then return end

    local tool = equipWeapon()
    local th = target:FindFirstChildOfClass("Humanoid")
    local dist = (root.Position - er.Position).Magnitude
    local reach = attackRange(tool)
    local inRange = dist <= reach + 6
    if th then
        if target ~= runtime.state.lastTarget then
            runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = target, th.Health, now
            runtime.state.hitsConfirmed = 0
            runtime.state.targetDist, runtime.state.travelAt = dist, now
            if runtime.state.saberTarget and target.Name:lower():find(runtime.state.saberTarget:lower(), 1, true) then
                runtime.state.saberKillHealth = th.Health
            end
        elseif th.Health < (runtime.state.targetHealth or th.Health) then
            runtime.state.targetHealth, runtime.state.targetAt = th.Health, now
            runtime.state.targetDist, runtime.state.travelAt = dist, now
            if runtime.state.saberTarget and target.Name:lower():find(runtime.state.saberTarget:lower(), 1, true) then
                runtime.state.saberKillHealth = th.Health
                runtime.state.saberKillDamaged = true
                runtime.state.saberProgressAt = now
            end
        elseif inRange then
            if now - runtime.state.targetAt > runtime.config.StuckTimeout then
                stuckTargets[target] = now + runtime.config.StuckIgnore
                runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
                enemyCache, enemyCacheAt = {}, 0
                dbg("Ignoring stuck target " .. target.Name)
                return
            end
        elseif dist < (runtime.state.targetDist or dist) - 0.5 then
            runtime.state.targetDist, runtime.state.travelAt = dist, now
        elseif now - (runtime.state.travelAt or now) > runtime.config.StuckTimeout * 3 then
            stuckTargets[target] = now + runtime.config.StuckIgnore
            runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
            enemyCache, enemyCacheAt = {}, 0
            dbg("Cannot reach target " .. target.Name)
            return
        end
    end

    local hover = runtime.config.HoverHeight
    -- The hits go through the remote of the game, so the player can stay high
    -- above the mob where its swings cannot reach. Only the plain swing has to
    -- come down close.
    if reach <= runtime.config.MeleeRange and not runtime.config.RemoteAttack then
        hover = math.min(hover, runtime.config.MeleeHover)
    end

    local dx = root.Position.X - er.Position.X
    local dz = root.Position.Z - er.Position.Z
    local flat = math.sqrt(dx * dx + dz * dz)

    -- The pack is only gathered at the fight. Carrying it while the bot flies
    -- to a mob is what dragged the held mobs across the map behind the player:
    -- they are let go the moment the target is out of reach and picked up
    -- again when the bot has arrived.
    if runtime.config.BringMob then
        local bringRange = tonumber(runtime.config.BringMobRange) or 60
        if bringRange > 0 and flat <= math.min(reach + 10, bringRange) then
            bringMob(target, root)
        elseif next(runtime.state.bringHeld) ~= nil then
            releaseBringMobs()
            restoreHitbox()
        end
    elseif next(runtime.state.bringHeld) ~= nil or next(runtime.state.bringIgnored) ~= nil then
        releaseBringMobs()
        restoreHitbox()
    end

    local swingTarget = target
    if runtime.config.AutoAttack then
        local close = mobInReach(root, reach)
        -- A boss is not given up for a normal mob that happens to stand near:
        -- the boss is what the boss farm went there for.
        local onBoss = runtime.config.BossFarm and bossKeyOf(target)
        local onSaber = runtime.state.saberTarget
            and target.Name:lower():find(runtime.state.saberTarget:lower(), 1, true)
        -- A swipe at a mob that stands in the way is fine, but the window has
        -- to close and then stay closed for a while. If it is armed again on
        -- the next tick the bot farms the mob beside it for ever and never
        -- walks to the mob of the quest at all.
        if close and close ~= target and flat > reach and not onBoss and not onSaber
            and (runtime.state.autoBurstCd or 0) <= now then
            runtime.state.autoBurst = now + 2
            runtime.state.autoBurstCd = now + 8
        end
        if (runtime.state.autoBurst or 0) > now and close and not onSaber then
            swingTarget = close
        elseif onSaber then
            -- A burst that was armed before the Saber boss appeared must not
            -- replace that boss with a normal mob standing beside it.
            runtime.state.autoBurst = 0
        end
    end

    -- The hover and the trip follow the mob of the quest. A swipe at a mob
    -- that stands beside us is only a swipe: it must not pull the trip off
    -- the quest mob, or the bot farms the neighbour beside it for ever.
    local head = target:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        head = nil
        for _, d in ipairs(target:GetDescendants()) do
            if d:IsA("BasePart") and d.Name:lower():find("head", 1, true) then
                head = d
                break
            end
        end
    end
    local hoverPos
    if head then
        local above = runtime.config.RemoteAttack and math.max(hover, runtime.config.HeadHover) or runtime.config.HeadHover
        hoverPos = head.Position + Vector3.new(0, above, 0)
    else
        hoverPos = er.Position + Vector3.new(0, hover, 0)
    end
    local top = er.Position.Y + (er.Size and er.Size.Y or 0) / 2
    hoverPos = Vector3.new(hoverPos.X, math.max(hoverPos.Y, top - 1), hoverPos.Z)

    -- While the target itself is being carried to us, walking to where it used
    -- to be makes the player and the mob cross each other; the distance grows,
    -- the pack is dropped and the bot chases it again. The player holds its
    -- ground and only settles the height while the mob comes over.
    local heldTarget = runtime.state.bringCarryingTarget[target] == true
    if heldTarget then
        local above = runtime.config.RemoteAttack and math.max(hover, runtime.config.HeadHover) or runtime.config.HeadHover
        local base = head and head.Position or er.Position
        hoverPos = Vector3.new(root.Position.X, base.Y + above, root.Position.Z)
    end

    -- The player does not sit on the head of the mob: it slides around it on a
    -- little ring, so the skills that are thrown where the mob is look at the
    -- player and miss. The ring goes the whole way round, it never runs back
    -- and forth over the same line.
    local tweenMoving = activeTween
        and activeTween.PlaybackState == Enum.PlaybackState.Playing
    if runtime.config.Dodge and runtime.config.RemoteAttack and not tweenMoving
        and not heldTarget and flat <= reach + 8 then
        runtime.state.dodgeAngle = ((runtime.state.dodgeAngle or 0) + (runtime.config.DodgeSpeed or 90) * 0.05) % 360
        local a = math.rad(runtime.state.dodgeAngle)
        local ring = runtime.config.DodgeRadius or 14
        local around = Vector3.new(hoverPos.X + math.cos(a) * ring, hoverPos.Y,
            hoverPos.Z + math.sin(a) * ring)
        pcall(function()
            root.CFrame = CFrame.new(around) * CFrame.Angles(math.rad(-90), 0, 0)
        end)
    else
        runtime.travelTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))
    end

    local swingHit = anchorOf(swingTarget) or er
    local sx = root.Position.X - swingHit.Position.X
    local sz = root.Position.Z - swingHit.Position.Z
    local swingFlat = math.sqrt(sx * sx + sz * sz)
    -- The big hitbox is a thing of the swing, not of the trip: a mob left
    -- blown up while the bot flies somewhere else is the giant rig players
    -- see. It is put back the moment there is no swing to make.
    if runtime.config.BigHitbox and swingFlat <= reach then
        enlargeHitbox(swingTarget)
    elseif runtime.state.hitboxPart then
        restoreHitbox()
    end
    if (not runtime.state.attackNextAt or now >= runtime.state.attackNextAt)
        and swingFlat <= reach then
        if not tool then dbg("No weapon in backpack!"); return end
        if doAttack(tool, swingTarget) then
            runtime.state.lastAttack = now
            local many = (runtime.state.aoeCount or 1) > 1 and (" +" .. (runtime.state.aoeCount - 1) .. " close") or ""
            -- ReceivedHit is sent to the damaged player, not to the attacker.
            -- It therefore cannot count outgoing mob hits. The local health
            -- check is the only outgoing confirmation shown here.
            local seen = runtime.state.attackConfirmed and " (confirmed)" or ""
            if swingTarget == target then
                runtime.state.status = "Hitting " .. target.Name .. many .. seen
            else
                runtime.state.status = "Attacking " .. swingTarget.Name .. many
            end
        end
    end
end

raiseSimulationRadius()
pcall(function()
    local added = LocalPlayer.CharacterAdded:Connect(function()
        if not runtime.running or FarmRuntime.current ~= runtime then return end
        fullReset("a new character came in")
        runtime.state.dead = false
        dbg("New character, farming again")
    end)
    table.insert(runtime.characterConnections or {}, added)
    local removing = LocalPlayer.CharacterRemoving:Connect(function()
        if not runtime.running or FarmRuntime.current ~= runtime then return end
        fullReset("the character was removed")
    end)
    table.insert(runtime.characterConnections or {}, removing)
end)

table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        if runtime.state.enabled then
            runtime.state.wasStopped = false
            local ok, err = pcall(step)
            if not runtime.isCurrent() then return end
            if not ok then dbg("Loop error: " .. tostring(err)) end
            -- A pause of the farm (a turn-in, a fruit, a shop) must not leave
            -- the last pack frozen: if the farm has not carried it for a few
            -- seconds, the mobs are let go and the enlarged hitbox is put back.
            if next(runtime.state.bringHeld) ~= nil
                and tick() - (runtime.state.bringAt or 0) > 3 then
                releaseBringMobs()
                restoreHitbox()
            end
        else
            runtime.state.farming = false
            runtime.state.status = "Stopped"
            runtime.stopTween()
            -- let the held mobs go the moment the bot is stopped, once
            if not runtime.state.wasStopped then
                runtime.state.wasStopped = true
                runtime.resetTransient("bot disabled")
                if next(runtime.state.bringHeld) ~= nil or next(runtime.state.bringIgnored) ~= nil then releaseBringMobs() end
                restoreHitbox()
            end
        end
        task.wait(0.05)
        if not runtime.isCurrent() then return end
    end
end))

-- ================= AUTO QUESTS (Saber) =================
-- The live client already owns the first-sea puzzle. Its local script sends
-- the same ProQuestProgress calls that the server understands and stores the
-- confirmed state in a table. The bot now drives that state machine instead
-- of guessing from object names: a button, a pickup or a talk only counts
-- after the server has confirmed it.
local function saberPart(path)
    local current = Workspace
    for name in path:gmatch("[^/]+") do
        current = current and current:FindFirstChild(name)
        if not current then return nil end
    end
    return current
end

local function findMob(text)
    local wanted = text:lower()
    for _, mob in ipairs(collectEnemies(tick())) do
        if mob.Name:lower():find(wanted, 1, true) then return mob end
    end
    return nil
end

-- One pass at the current state of the Saber quest. The return value means
-- that the whole quest is finished; the final reward is still checked by the
-- caller, because the server can mark the boss dead a moment before the
-- Saber reaches the backpack.
local function saberStep(root)
    if not root then return false end
    local now = tick()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local commF = shopRemote()
    if not commF then
        runtime.state.status = "Saber: CommF_ is missing"
        return false
    end

    local ok, progress = pcall(function()
        return commF:InvokeServer("ProQuestProgress")
    end)
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if not ok or type(progress) ~= "table" then
        runtime.state.status = "Saber: could not read the quest state"
        return false
    end
    runtime.state.saberProgress = progress
    runtime.state.saberStateAt = now

    local plates = progress.Plates or {}
    local function plateDone(index)
        return plates[index] == true or plates[tostring(index)] == true
    end
    local plateCount = 0
    for index = 1, 5 do
        if plateDone(index) then plateCount = plateCount + 1 end
    end

    -- Any confirmed server-side change is real progress. The fingerprint also
    -- includes the two dialogue answers, because those are not fields of the
    -- progress table.
    local fingerprint = table.concat({
        tostring(plateCount),
        progress.UsedTorch and "1" or "0",
        progress.UsedCup and "1" or "0",
        runtime.state.saberSickDone and "1" or "0",
        progress.KilledMob and "1" or "0",
        (progress.TalkedSon or runtime.state.saberSonDone) and "1" or "0",
        progress.UsedRelic and "1" or "0",
        progress.KilledShanks and "1" or "0",
    }, ":")
    if fingerprint ~= runtime.state.saberFingerprint then
        runtime.state.saberFingerprint = fingerprint
        runtime.state.saberProgressAt = now
    end

    -- Every mutation uses the same ProQuestProgress action as the official
    -- QuestPro script. A separate cooldown is kept for each action, so a
    -- refused FillCup cannot block the later PlaceRelic request.
    local function callProgress(action, ...)
        local key = action
        if select("#", ...) > 0 then
            key = action .. "#" .. tostring(select(1, ...))
        end
        if now - (runtime.state.saberAttempts[key] or 0) < 2 then
            return nil, nil
        end
        runtime.state.saberAttempts[key] = now
        runtime.state.saberAttemptKey = action
        runtime.state.saberAttemptAt = now
        local args = table.pack(...)
        local called, result = pcall(function()
            return commF:InvokeServer("ProQuestProgress", action,
                table.unpack(args, 1, args.n))
        end)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return nil, nil end
        if called then return true, result end
        return false, result
    end

    local function touch(a, b)
        if not a or not b or not firetouchinterest then return end
        pcall(function()
            firetouchinterest(a, b, 0)
            firetouchinterest(a, b, 1)
        end)
    end

    local function ownedTool(name)
        local wanted = name:lower()
        for tool in pairs(ownedTools()) do
            if tool.Name:lower():find(wanted, 1, true) then return tool end
        end
        return nil
    end

    local function moveToPart(part, distance)
        local anchor = anchorOf(part)
        if not anchor then return false end
        local gap = (root.Position - anchor.Position).Magnitude
        if gap > (distance or 9) then
            runtime.travelTo(CFrame.new(anchor.Position + Vector3.new(0, 2, 0)))
            return false
        end
        return true
    end

    local function useBoss(name, description)
        if runtime.state.saberKillTarget ~= name then
            runtime.state.saberKillTarget = name
            runtime.state.saberKillHealth = nil
            runtime.state.saberKillDamaged = false
        end
        runtime.state.saberTarget = name
        runtime.state.saberAt = description
    end

    local function watchBoss(mob)
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        if runtime.state.saberKillHealth == nil then
            runtime.state.saberKillHealth = hum.Health
        elseif hum.Health < runtime.state.saberKillHealth then
            runtime.state.saberKillHealth = hum.Health
            runtime.state.saberKillDamaged = true
            runtime.state.saberProgressAt = now
        end
    end

    -- Five green buttons. The state table is the only completion test.
    if plateCount < 5 then
        for index = 1, 5 do
            if not plateDone(index) then
                local button = saberPart("Map/Jungle/QuestPlates/Plate" .. index .. "/Button")
                runtime.state.saberAt = "the green buttons of the Jungle"
                if button then
                    if moveToPart(button, 10) then
                        touch(root, anchorOf(button) or button)
                    end
                else
                    runtime.state.status = "Saber: button " .. index .. " is not loaded"
                end
                return false
            end
        end
    end

    -- The torch is a real quest item. UsedTorch is set by the server only
    -- after the torch was picked up and then burnt in the Desert fire.
    if not progress.UsedTorch then
        local torchTool = ownedTool("Torch")
        local fire = saberPart("Map/Desert/Burn/Fire")
        runtime.state.saberAt = "the torch in the hidden Jungle room"
        if torchTool and fire then
            local handle = toolPart(torchTool)
            if handle and moveToPart(fire, 9) then
                touch(handle, fire)
            end
        elseif not torchTool then
            local torch = saberPart("Map/Jungle/Torch")
            if torch then
                if moveToPart(torch, 8) then
                    touch(root, anchorOf(torch) or torch)
                end
            else
                runtime.state.status = "Saber: the torch is not loaded"
            end
        else
            runtime.state.status = "Saber: the Desert fire is not loaded"
        end
        return false
    end

    -- GetCup only gives the empty cup. UsedCup becomes true after FillCup
    -- was accepted. The two official server actions are sent separately and
    -- are not treated as progress until the Cup exists and UsedCup is true.
    if not progress.UsedCup then
        local cupTool = ownedTool("Cup")
        local water = saberPart("Map/Ice/ParticleDrop/Water")
        runtime.state.saberAt = "the cup in the Frozen cave"
        if cupTool then
            runtime.state.saberCupGranted = true
            if water then
                local handle = toolPart(cupTool)
                if handle and moveToPart(water, 9) then
                    local called, result = callProgress("FillCup", cupTool)
                    runtime.state.saberFillRequestAt = now
                    if called and result ~= false then
                        runtime.state.status = "Saber: FillCup was accepted, waiting for the server"
                    elseif called then
                        runtime.state.status = "Saber: the server refused FillCup"
                    else
                        runtime.state.status = "Saber: FillCup did not reach the server"
                    end
                end
            else
                runtime.state.status = "Saber: the water is not loaded"
            end
        else
            local desert = saberPart("Map/Desert")
            local cup = desert and desert:FindFirstChild("Cup", true)
            if cup then
                if moveToPart(cup, 8) then
                    local called, result = callProgress("GetCup")
                    runtime.state.saberCupRequestAt = now
                    if called and result ~= false then
                        runtime.state.status = "Saber: GetCup was accepted, waiting for the cup"
                    elseif called then
                        runtime.state.status = "Saber: the server refused GetCup"
                    else
                        runtime.state.status = "Saber: GetCup did not reach the server"
                    end
                end
            else
                runtime.state.status = "Saber: the cup is not loaded"
            end
        end
        return false
    end

    -- The Sick Man gives the next instruction. The game's own dialogue uses
    -- zero for the successful answer; an attempt is never counted as a step.
    if not runtime.state.saberSickDone then
        local npc = findTeacher("Sick Man")
        runtime.state.saberAt = "the Sick Man of the Frozen Village"
        if npc then
            if moveToPart(npc, 8) then
                local called, result = callProgress("SickMan")
                if called and result == 0 then
                    runtime.state.saberSickDone = true
                    runtime.state.saberProgressAt = now
                    runtime.state.status = "Saber: the Sick Man confirmed the cup"
                else
                    runtime.state.status = "Saber: the Sick Man did not confirm the cup yet"
                end
            end
        else
            runtime.state.status = "Saber: the Sick Man was not found"
        end
        return false
    end

    -- The Mob Leader has to be really killed. The server flag is the
    -- completion test; the health watch below only refreshes the timeout.
    if not progress.KilledMob then
        useBoss("Mob Leader", "the Mob Leader on Jean-Luc Island")
        local mob = findMob("Mob Leader")
        if mob then
            watchBoss(mob)
            runtime.state.status = "Saber: fighting the Mob Leader"
        else
            local spawn = findSpawn("Mob Leader")
            local anchor = spawn and anchorOf(spawn)
            if anchor and (root.Position - anchor.Position).Magnitude > 700 then
                runtime.state.status = "Saber: flying to the Mob Leader"
                flyTo(anchor.Position)
                if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                    or LocalPlayer.Character ~= char then return false end
            else
                runtime.state.status = "Saber: waiting for the Mob Leader"
            end
        end
        return false
    end
    runtime.state.saberTarget = nil

    -- The Rich Man's son hands over the relic only after the Mob Leader is
    -- dead. TalkedSon can already be true from an earlier conversation, so it
    -- must not skip the second RichSon request: answer one is the server
    -- response that grants the relic, and the Relic in the inventory is the
    -- second confirmation.
    local relic = ownedTool("Relic")
    if not relic then
        local npc = findTeacher("Rich Man")
        runtime.state.saberAt = "the Rich Man of the Pirate Village"
        if npc then
            if moveToPart(npc, 8) then
                local canRetry = not runtime.state.saberSonDone
                    or now - (runtime.state.saberRelicRequestAt or 0) >= 3
                if canRetry then
                    local called, result = callProgress("RichSon")
                    runtime.state.saberRelicRequestAt = now
                    if called and result == 1 then
                        runtime.state.saberSonDone = true
                        runtime.state.saberRelicGranted = true
                        runtime.state.saberProgressAt = now
                        runtime.state.status = "Saber: the Rich Man granted the relic"
                    elseif called and result == 0 then
                        runtime.state.status = "Saber: the Rich Man still wants the Mob Leader"
                    else
                        runtime.state.status = "Saber: the Rich Man did not answer yet"
                    end
                else
                    runtime.state.status = "Saber: waiting for the granted relic"
                end
            end
        else
            runtime.state.status = "Saber: the Rich Man was not found"
        end
        return false
    end
    runtime.state.saberSonDone = true
    runtime.state.saberRelicGranted = true

    -- PlaceRelic is the official server action for the door. A truthy reply
    -- is only the acceptance; UsedRelic in the next progress query is the
    -- confirmed completion.
    if not progress.UsedRelic then
        local jungle = saberPart("Map/Jungle")
        local door = nil
        if jungle then
            for _, child in ipairs(jungle:GetChildren()) do
                if child.Name == "Final" and not child:FindFirstChild("Invis") then
                    door = child
                    break
                end
            end
        end
        runtime.state.saberAt = "the relic in the Jungle door"
        if relic and door then
            local doorPart = anchorOf(door)
            if doorPart and moveToPart(doorPart, 9) then
                local called, result = callProgress("PlaceRelic")
                runtime.state.saberPlaceRequestAt = now
                if called and result then
                    runtime.state.saberPlaceAccepted = true
                    runtime.state.status = "Saber: PlaceRelic was accepted, waiting for the server"
                elseif called then
                    runtime.state.saberPlaceAccepted = false
                    runtime.state.status = "Saber: the server refused PlaceRelic"
                else
                    runtime.state.status = "Saber: PlaceRelic did not reach the server"
                end
            end
        elseif not relic then
            runtime.state.status = "Saber: waiting for the relic"
        else
            runtime.state.status = "Saber: the Jungle door is not loaded"
        end
        return false
    end

    -- The Saber Expert is behind the opened door. KilledShanks is the server
    -- proof that this boss died; merely disappearing is not enough.
    if not progress.KilledShanks then
        useBoss("Saber Expert", "the Saber Expert behind the Jungle door")
        local mob = findMob("Saber Expert")
        if mob then
            watchBoss(mob)
            runtime.state.status = "Saber: fighting the Saber Expert"
        else
            local spawn = findSpawn("Saber Expert")
            local anchor = spawn and anchorOf(spawn)
            if anchor and (root.Position - anchor.Position).Magnitude > 700 then
                runtime.state.status = "Saber: flying to the Saber Expert"
                flyTo(anchor.Position)
                if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
                    or LocalPlayer.Character ~= char then return false end
            else
                runtime.state.status = "Saber: waiting for the Saber Expert"
            end
        end
        return false
    end
    runtime.state.saberTarget = nil
    runtime.state.saberAt = "the Saber reward"
    runtime.state.status = "Saber: waiting for the Saber"
    return false
end

table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(1)
        if not runtime.isCurrent() then return end
        if runtime.config.AutoSaber and runtime.state.enabled then
            if not runtime.state.saberActive then
                runtime.state.saberActive = true
                runtime.state.saberLockAt = tick()
                runtime.state.saberProgressAt = tick()
            end

            -- The quest is over when the Saber itself is in hand: the steps can
            -- say one thing or another, the tool is the proof.
            local hasSaber = false
            local char = LocalPlayer.Character
            local backpack = LocalPlayer:FindFirstChild("Backpack")
            for _, folder in ipairs({char, backpack}) do
                if folder then
                    for _, tool in ipairs(folder:GetChildren()) do
                        if tool:IsA("Tool") and tool.Name:lower():find("saber", 1, true)
                            and not tool.Name:lower():find("expert", 1, true) then
                            hasSaber = true
                        end
                    end
                end
            end
            if hasSaber then
                dbg("Saber obtained, the quest is over")
                runtime.config.AutoSaber = false
                runtime.resetSaberState()
            else
                local root = getRoot()
                if root and runtime.config.AutoSaber then
                    local ok, err = pcall(saberStep, root)
                    if not runtime.isCurrent() then return end
                    if not ok then
                        dbg("Saber step failed: " .. tostring(err))
                        runtime.state.saberTarget = nil
                    end
                end
            end
        else
            runtime.resetSaberState()
        end
    end
end))

-- ================= AUTO BUY STYLES =================
-- Every style has its own teacher and its own requirements, so the list is
-- walked in order: the first form before its second form, and the ones with
-- no requirements first. A style the game refuses is simply tried again on
-- the next round.
local styleBuyIndex = 0
table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(5)
        if not runtime.isCurrent() then return end
        if runtime.config.AutoBuyStyles and runtime.state.enabled and not runtime.state.shopping
            and not runtime.state.shopInFlight and not runtime.state.flying then
            runtime.state.blockAt = tick()
            styleBuyIndex = styleBuyIndex % #STYLE_SHOP + 1
            local style = STYLE_SHOP[styleBuyIndex]
            dbg("Auto buy style: " .. style.name)
            local ok, err = pcall(buyStyle, style)
            if not runtime.isCurrent() then return end
            if not ok then dbg("Auto buy failed: " .. tostring(err)) end
            task.wait(20)
            if not runtime.isCurrent() then return end
        end
    end
end))

table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(1)
        if not runtime.isCurrent() then return end
        if runtime.config.AutoBuso and runtime.state.enabled then
            local ok, err = pcall(function()
                local char = LocalPlayer.Character
                local hasBuso = false
                if char then
                    for _, d in ipairs(char:GetDescendants()) do
                        local n = d.Name
                        if n == "HasBuso" or n:find("_BusoLayer", 1, true) then
                            hasBuso = true
                            break
                        end
                    end
                end
                if not hasBuso then
                    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                    local commF = remotes and remotes:FindFirstChild("CommF_")
                    if commF then
                        pcall(function() commF:InvokeServer("Buso") end)
                        task.wait(2)
                    end
                end
            end)
            if not runtime.isCurrent() then return end
            if not ok then dbg("The haki check failed: " .. tostring(err)) end
        end
    end
end))

table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(1)
        if not runtime.isCurrent() then return end
        raiseSimulationRadius()
        if runtime.config.AntiAfk then
            runtime.state.afkTimer = runtime.state.afkTimer + 1
            if runtime.state.afkTimer >= (runtime.config.AntiAfkInterval or 120) then
                runtime.state.afkTimer = 0
                local cam = Workspace.CurrentCamera
                if cam then
                    runtime.state.afkSign = -runtime.state.afkSign
                    pcall(function()
                        cam.CFrame = cam.CFrame * CFrame.Angles(0, 0.01 * runtime.state.afkSign, 0)
                    end)
                end
            end
        else
            runtime.state.afkTimer = 0
        end
    end
end))

-- ================= GUI HELPERS =================
-- The panel is built inside its own function on purpose: the top level of a
-- Lua chunk can only hold 200 locals, and some executors add their own to the
-- chunk that runs this file. In a function the panel gets a fresh frame.
local function buildPanel()
local function corner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p; return c end
local function stroke(p) local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(50,50,65); s.Thickness=1; s.Parent=p; return s end

local gui = Instance.new("ScreenGui")
gui.Name = "CustomFarmGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
runtime.gui = gui

local function spawnTracked(fn)
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    table.insert(runtime.tasks, task.spawn(function()
        if not runtime.running or FarmRuntime.current ~= runtime then return end
        local ok, err = pcall(fn)
        if not runtime.isCurrent() then return end
        if not ok and runtime.running and FarmRuntime.current == runtime then
            dbg("Background task failed: " .. tostring(err))
        end
    end))
end
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end
if not runtime.isCurrent() then
    gui:Destroy()
    return
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 320, 0, 540)
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
local fix = Instance.new("Frame")
fix.Size = UDim2.new(1, 0, 0, 12)
fix.Position = UDim2.new(0, 0, 1, -12)
fix.BackgroundColor3 = THEME.panel
fix.BorderSizePixel = 0
fix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Blox Fruits • Farm"
title.TextColor3 = THEME.text
title.Font = THEME.fontBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0.5, -12)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 35, 45)
closeBtn.Text = "✕"; closeBtn.TextColor3 = THEME.danger
closeBtn.Font = THEME.fontBold; closeBtn.TextSize = 12
closeBtn.AutoButtonColor = false; closeBtn.Parent = titleBar; corner(closeBtn, 6)
local setBotEnabled
closeBtn.MouseButton1Click:Connect(function()
    if not runtime.isCurrent() then return end
    if setBotEnabled then setBotEnabled(false) end
    gui.Enabled = false
end)

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Position = UDim2.new(1, -58, 0.5, -12)
minBtn.BackgroundColor3 = THEME.off
minBtn.Text = "—"; minBtn.TextColor3 = THEME.text
minBtn.Font = THEME.fontBold; minBtn.TextSize = 12
minBtn.AutoButtonColor = false; minBtn.Parent = titleBar; corner(minBtn, 6)

local TABS = {"HOME", "MOVE", "FIGHT", "STATS"}

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -152)
content.Position = UDim2.new(0, 8, 0, 74)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Parent = main

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 34)
tabBar.Position = UDim2.new(0, 8, 0, 40)
tabBar.BackgroundTransparency = 1
tabBar.BorderSizePixel = 0
tabBar.Parent = main

local pages = {}
local page
local tabButtons = {}

local function newPage(name)
    local p = Instance.new("ScrollingFrame")
    p.Name = "Page_" .. name
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 4
    p.ScrollBarImageColor3 = THEME.accent
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.Visible = false
    p.Parent = content
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = p
    pages[name] = p
    return p
end

local rebuildIslands = nil

local function showTab(index)
    for i, name in ipairs(TABS) do
        pages[name].Visible = (i == index)
        local b = tabButtons[i]
        if b then
            b.BackgroundColor3 = (i == index) and THEME.accent or THEME.panel
            b.TextColor3 = (i == index) and THEME.bg or THEME.subtext
        end
    end
    page = pages[TABS[index]]
    if TABS[index] == "MOVE" and rebuildIslands then rebuildIslands() end
end

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Name = "Tab_" .. name
    b.Size = UDim2.new(1/#TABS, -4, 1, 0)
    b.Position = UDim2.new((i-1)/#TABS, 0, 0, 0)
    b.BackgroundColor3 = THEME.panel
    b.Text = name; b.TextColor3 = THEME.subtext
    b.Font = THEME.fontBold; b.TextSize = 12
    b.AutoButtonColor = true; b.Parent = tabBar
    corner(b, 6); stroke(b)
    b.MouseButton1Click:Connect(function()
        if not runtime.isCurrent() then return end
        showTab(i)
    end)
    tabButtons[i] = b
    newPage(name)
end
showTab(1)

local expandedH, collapsedH = 540, 34
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    if not runtime.isCurrent() then return end
    minimized = not minimized
    TweenService:Create(main, TweenInfo.new(0.18), {
        Size = minimized and UDim2.new(0,320,0,collapsedH) or UDim2.new(0,320,0,expandedH)
    }):Play()
    content.Visible = not minimized
    tabBar.Visible = not minimized
end)

-- ===== BUILDERS =====
local function makeHeader(text)
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1,0,0,20)
    h.BackgroundTransparency = 1
    h.Text = text; h.TextColor3 = THEME.subtext
    h.Font = THEME.fontBold; h.TextSize = 10
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.LayoutOrder = #page:GetChildren()
    h.Parent = page
end

local function makeHint(text)
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1,0,0,16)
    h.BackgroundTransparency = 1
    h.Text = text; h.TextColor3 = THEME.subtext
    h.Font = THEME.font; h.TextSize = 10
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.LayoutOrder = #page:GetChildren()
    h.Parent = page
end

local function makeToggle(text, default, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,32); row.BackgroundTransparency = 1
    row.LayoutOrder = #page:GetChildren(); row.Parent = page

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
    btn.Text = ""; btn.Name = "Toggle_" .. text; btn.Parent = row

    local v = default
    local function set(newV)
        if not runtime.isCurrent() then return end
        if newV == v then return end
        v = newV
        TweenService:Create(switch, TweenInfo.new(0.15), {
            BackgroundColor3 = v and THEME.accent or THEME.off}):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = v and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)}):Play()
        cb(v)
    end

    btn.MouseButton1Click:Connect(function() set(not v) end)
    return set
end

local function makeSlider(text, mn, mx, def, fmt, cb)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1,0,0,46); container.BackgroundTransparency = 1
    container.LayoutOrder = #page:GetChildren(); container.Parent = page

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,-60,0,16); label.BackgroundTransparency = 1
    label.Text = text; label.TextColor3 = THEME.text
    label.Font = THEME.font; label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = container

    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0,60,0,16); val.Position = UDim2.new(1,-60,0,0)
    val.BackgroundTransparency = 1
    val.Text = fmt(def); val.TextColor3 = THEME.accent
    val.Font = THEME.fontBold; val.TextSize = 12
    val.TextXAlignment = Enum.TextXAlignment.Right; val.Parent = container

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1,0,0,6); bar.Position = UDim2.new(0,0,0,28)
    bar.BackgroundColor3 = THEME.off; bar.Parent = container; corner(bar, 3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((def-mn)/(mx-mn),0,1,0)
    fill.BackgroundColor3 = THEME.accent; fill.BorderSizePixel = 0
    fill.Parent = bar; corner(fill, 3)

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1,0,0,16); hit.Position = UDim2.new(0,0,0,20)
    hit.BackgroundTransparency = 1; hit.Text = ""; hit.Parent = container

    local v = def
    local function setFromInput(i)
        if not runtime.isCurrent() then return end
        local width = bar.AbsoluteSize.X
        if width <= 0 then return end
        local rel = math.clamp((i.Position.X - bar.AbsolutePosition.X) / width, 0, 1)
        v = math.floor(mn + (mx-mn)*rel + 0.5)
        fill.Size = UDim2.new((v-mn)/(mx-mn),0,1,0)
        val.Text = fmt(v); cb(v)
    end

    hit.InputBegan:Connect(function(i)
        if not runtime.isCurrent() then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            setFromInput(i)
            local m, e, f
            local function cleanup()
                if m then m:Disconnect() end
                if e then e:Disconnect() end
                if f then f:Disconnect() end
                m, e, f = nil, nil, nil
            end
            m = UserInputService.InputChanged:Connect(function(x)
                if not runtime.running or FarmRuntime.current ~= runtime then return end
                if x.UserInputType == Enum.UserInputType.MouseMovement or x.UserInputType == Enum.UserInputType.Touch then
                    setFromInput(x)
                end
            end)
            e = UserInputService.InputEnded:Connect(function(x)
                if x.UserInputType == Enum.UserInputType.MouseButton1 or x.UserInputType == Enum.UserInputType.Touch then
                    cleanup()
                end
            end)
            f = UserInputService.WindowFocusReleased:Connect(cleanup)
            table.insert(runtime.inputConnections, m)
            table.insert(runtime.inputConnections, e)
            table.insert(runtime.inputConnections, f)
        end
    end)
end

local function makeSegment(text, options, default, cb)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(1,0,0,58); c.BackgroundTransparency = 1
    c.LayoutOrder = #page:GetChildren(); c.Parent = page

    local label = Instance.new("TextButton")
    label.Size = UDim2.new(1,0,0,16); label.BackgroundTransparency = 1
    label.Text = text .. ": " .. tostring(default); label.TextColor3 = THEME.text
    label.Font = THEME.font; label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.AutoButtonColor = false; label.Parent = c

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1,0,0,34); bar.Position = UDim2.new(0,0,0,20)
    bar.BackgroundColor3 = THEME.panel; bar.Parent = c
    corner(bar, 6); stroke(bar)
    local L = Instance.new("UIListLayout")
    L.FillDirection = Enum.FillDirection.Horizontal
    L.Padding = UDim.new(0,2); L.Parent = bar

    local buttons = {}
    local choosers = {}
    local index = 1
    for i, opt in ipairs(options) do
        if opt == default then index = i end
    end
    for _, opt in ipairs(options) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1/#options, -2, 1, -4)
        b.Position = UDim2.new(0,0,0,2)
        b.BackgroundColor3 = opt == default and THEME.accent or THEME.panel
        b.Text = opt; b.TextColor3 = THEME.text
        b.Font = THEME.fontBold; b.TextSize = 11
        b.AutoButtonColor = false; b.Parent = bar
        corner(b, 4)
        local lastPick = 0
        local function choose()
            if not runtime.isCurrent() then return end
            local now = tick()
            if now - lastPick < 0.15 then return end
            lastPick = now
            cb(opt)
            for n, bb in pairs(buttons) do
                bb.BackgroundColor3 = n == opt and THEME.accent or THEME.panel
                pcall(function()
                    TweenService:Create(bb, TweenInfo.new(0.12), {
                        BackgroundColor3 = n == opt and THEME.accent or THEME.panel}):Play()
                end)
            end
            label.Text = text .. ": " .. tostring(opt)
            for i, o in ipairs(options) do
                if o == opt then index = i break end
            end
        end
        b.MouseButton1Click:Connect(choose)
        b.MouseButton1Down:Connect(choose)
        b.InputBegan:Connect(function(input)
            if input and (input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1) then
                choose()
            end
        end)
        buttons[opt] = b
        choosers[opt] = choose
    end

    label.MouseButton1Click:Connect(function()
        index = index % #options + 1
        local pick = choosers[options[index]]
        if pick then pick() end
    end)
    label.InputBegan:Connect(function(input)
        if input and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1) then
            index = index % #options + 1
            local pick = choosers[options[index]]
            if pick then pick() end
        end
    end)
end

local function makeButton(text, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,32); row.BackgroundTransparency = 1
    row.LayoutOrder = #page:GetChildren(); row.Parent = page

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,26); btn.Position = UDim2.new(0,0,0,3)
    -- the row is handed back so a list of buttons can be rebuilt later
    btn.BackgroundColor3 = THEME.panel; btn.Text = text; btn.TextColor3 = THEME.text
    btn.Font = THEME.fontBold; btn.TextSize = 12
    btn.AutoButtonColor = false; btn.Parent = row
    corner(btn, 6); stroke(btn)

    btn.MouseButton1Click:Connect(function()
        if not runtime.isCurrent() then return end
        cb()
        pcall(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = THEME.accent}):Play()
        end)
        spawnTracked(function()
            task.wait(0.15)
            if not runtime.isCurrent() then return end
            pcall(function()
                TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = THEME.panel}):Play()
            end)
        end)
    end)
    return row
end

-- ===== BUILD =====
showTab(1) -- HOME
makeHeader("MODULES")
setBotEnabled = makeToggle("Bot Enabled", runtime.state.enabled, function(v)
    runtime.state.enabled = v
    runtime.resetTransient(v and "bot enabled" or "bot disabled")
    if not v then
        runtime.state.farming = false
        runtime.state.fruit = nil
        runtime.state.fruitStart = 0
        runtime.state.fruitTries = 0
        runtime.stopTween()
        if runtime.releaseBringMobs then runtime.releaseBringMobs() end
        restoreHitbox()
    elseif runtime.config.AutoSaber then
        runtime.state.saberActive = true
        runtime.state.saberLockAt = tick()
        runtime.state.saberProgressAt = tick()
    end
end)
makeToggle("Auto Quest",    runtime.config.AutoQuest,    function(v) runtime.config.AutoQuest    = v end)
makeToggle("Auto Farm",     runtime.config.AutoFarm,     function(v) runtime.config.AutoFarm     = v end)
makeToggle("Fruit Sniper",  runtime.config.FruitSniper,  function(v) runtime.config.FruitSniper  = v end)
makeToggle("Eat Fruit",     runtime.config.EatFruit,     function(v) runtime.config.EatFruit     = v end)
makeToggle("Turn In Quest", runtime.config.QuestTurnIn,  function(v) runtime.config.QuestTurnIn  = v end)
makeToggle("Anti-AFK",      runtime.config.AntiAfk,      function(v) runtime.config.AntiAfk      = v end)
local setDebug = makeToggle("Debug Output (F9)", runtime.config.Debug, function(v) runtime.config.Debug = v end)
makeHint("✕ stops the bot  •  RightShift shows/hides this panel")

makeHeader("FRUIT")
makeToggle("Auto Store", runtime.config.AutoStore, function(v) runtime.config.AutoStore = v end)
makeSlider("Store From", 1, 10, runtime.config.StoreFruitMin,
    function(v) return v.." fruits" end, function(v) runtime.config.StoreFruitMin = v end)
makeSlider("Scan Radius", 500, 10000, runtime.config.FruitScanRadius,
    function(v) return tostring(v) end, function(v) runtime.config.FruitScanRadius = v end)

showTab(2) -- MOVE
makeHeader("MOVEMENT")
makeSegment("Mode", {"Walk","Tween","Teleport"}, runtime.config.MovementMode,
    function(v) runtime.config.MovementMode = v end)
makeSlider("Move Speed", 50, 500, runtime.config.MoveSpeed,
    function(v) return v.." st/s" end, function(v) runtime.config.MoveSpeed = v end)
makeSlider("Hover Height", 0, 60, runtime.config.HoverHeight,
    function(v) return v.." studs" end, function(v) runtime.config.HoverHeight = v end)
makeToggle("Short Warp", runtime.config.WarpClose, function(v) runtime.config.WarpClose = v end)
makeSlider("Warp Distance", 20, 200, runtime.config.WarpDistance,
    function(v) return v.." studs" end, function(v) runtime.config.WarpDistance = v end)
makeSlider("Void Guard Y", -1000, -50, runtime.config.SafeY,
    function(v) return tostring(v).." studs" end, function(v) runtime.config.SafeY = v end)

makeHeader("WORLD (SEA)")
makeButton("Go to Sea 1", function() spawnTracked(function() travelToWorld(1) end) end)
makeButton("Go to Sea 2", function() spawnTracked(function() travelToWorld(2) end) end)
makeButton("Go to Sea 3", function() spawnTracked(function() travelToWorld(3) end) end)
makeHint("The seas are separate places: this uses the travel of the game")

makeHeader("FLY TO ISLAND (tween)")
local islandButtons = {}
local islandHint = nil
rebuildIslands = function()
    local ok, err = pcall(function()
    for _, row in ipairs(islandButtons) do
        if row then pcall(function() row:Destroy() end) end
    end
    islandButtons = {}
    if islandHint then pcall(function() islandHint:Destroy() end); islandHint = nil end
    local list = islandPositions()
    for _, island in ipairs(list) do
        local target = island.pos
        local islandName = island.name
        table.insert(islandButtons, makeButton("Go: " .. islandName, function()
            runtime.state.status = "Flying to " .. islandName
            spawnTracked(function()
                if not specialTravel(islandName) then flyTo(target) end
            end)
        end))
    end
    if #list == 0 then
        islandHint = makeHint("The game has not told the islands yet")
    end
    end)
    if not ok then dbg("The island list failed: " .. tostring(err)) end
end
rebuildIslands()

makeHeader("BRING MOB")
makeToggle("Bring Mob", runtime.config.BringMob, function(v) runtime.config.BringMob = v end)
makeSlider("Bring Mob Count", 0, 10, runtime.config.BringMobCount,
    function(v) return v == 0 and "All mobs of the kind" or (v.." mobs") end,
    function(v) runtime.config.BringMobCount = v end)
makeSlider("Bring Mob Range", 20, 300, runtime.config.BringMobRange,
    function(v) return v.." studs" end,
    function(v) runtime.config.BringMobRange = v end)

showTab(3) -- FIGHT
makeHeader("COMBAT")
makeSegment("Weapon", {"Melee", "Sword", "Fruit", "Gun"}, runtime.config.WeaponMode,
    function(v) runtime.config.WeaponMode = v end)
makeToggle("Auto Attack", runtime.config.AutoAttack, function(v) runtime.config.AutoAttack = v end)
makeToggle("Fast Attack", runtime.config.FastAttack, function(v) runtime.config.FastAttack = v end)
makeToggle("Remote Attack", runtime.config.RemoteAttack, function(v) runtime.config.RemoteAttack = v end)
makeToggle("AOE (all mobs in reach)", runtime.config.Aoe, function(v) runtime.config.Aoe = v end)
makeSlider("AOE Range", 40, 200, runtime.config.AoeRange,
    function(v) return v.." studs" end, function(v) runtime.config.AoeRange = v end)
makeToggle("Auto Buso (Haki)", runtime.config.AutoBuso, function(v) runtime.config.AutoBuso = v end)
makeToggle("Big Hitbox", runtime.config.BigHitbox, function(v) runtime.config.BigHitbox = v end)
makeSlider("Hitbox Size", 4, 40, runtime.config.HitboxSize,
    function(v) return tostring(v) end, function(v) runtime.config.HitboxSize = v end)
makeSlider("Swing Reach", 0, 200, runtime.config.HitboxMagnitude,
    function(v) return v.." studs" end, function(v) runtime.config.HitboxMagnitude = v end)
makeSlider("Head Hover", 0, 8, runtime.config.HeadHover,
    function(v) return v.." studs" end, function(v) runtime.config.HeadHover = v end)
makeHint("Melee keeps its real, short reach - guns and fruits reach 70 studs")
makeHint("Swing cadence comes from the weapon animation; this adds extra delay")
makeSlider("Extra Cooldown", 0, 100, math.floor((runtime.config.AttackCooldown or 0)*100),
    function(v) return string.format("%.2fs", v/100) end,
    function(v) runtime.config.AttackCooldown = v/100 end)

makeHeader("AUTO QUESTS")
makeToggle("Auto Saber (First Sea puzzle)", runtime.config.AutoSaber,
    function(v)
        runtime.config.AutoSaber = v
        runtime.resetSaberState()
        if v then
            runtime.state.saberActive = true
            runtime.state.saberLockAt = tick()
            runtime.state.saberProgressAt = tick()
        end
    end)
makeHint("Does the Saber puzzle step by step: buttons, torch, cup, NPCs, bosses")

makeHeader("BOSS FARM")
makeToggle("Farm Bosses", runtime.config.BossFarm, function(v) runtime.config.BossFarm = v end)
makeSlider("Boss Range", 500, 8000, runtime.config.BossRange,
    function(v) return v.." studs" end, function(v) runtime.config.BossRange = v end)
makeHint("Bosses are only chased when the current quest actually wants a boss")

makeHeader("MELEE SHOP (buy)")
makeToggle("Auto Buy Styles (in order)", runtime.config.AutoBuyStyles,
    function(v) runtime.config.AutoBuyStyles = v end)
makeHint("Walks to the teacher of each style in turn and buys it")
-- The buy is asked for right away: no walk to the teacher of the style.
for _, style in ipairs(STYLE_SHOP) do
    makeButton("Buy " .. style.name, function()
        runtime.state.status = "Buying " .. style.name
        spawnTracked(function() buyStyle(style) end)
    end)
end
makeHeader("ABILITIES (buy)")
makeButton("Buy Buso Haki", function()
    spawnTracked(function() buyAbility("BuyHaki", "Buso") end)
end)
makeButton("Buy Geppo (Skyjump)", function()
    spawnTracked(function() buyAbility("BuyHaki", "Geppo") end)
end)
makeButton("Buy Soru", function()
    spawnTracked(function() buyAbility("BuyHaki", "Soru") end)
end)
makeButton("Buy Observation Haki", function()
    spawnTracked(function() buyAbility("KenTalk", "Buy") end)
end)

showTab(4) -- STATS
makeHeader("STATS")
makeToggle("Auto Stats", runtime.config.AutoStats, function(v) runtime.config.AutoStats = v end)
makeSegment("Stat", {"Melee","Sword","Gun","Fruit","Defense","All"}, runtime.config.AutoStatTarget,
    function(v) runtime.config.AutoStatTarget = v end)
makeSlider("Stat Wait", 1, 15, runtime.config.AutoStatWait,
    function(v) return v.."s" end, function(v) runtime.config.AutoStatWait = v end)

showTab(1)

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, -16, 0, 72)
footer.Position = UDim2.new(0, 8, 1, -80)
footer.BackgroundColor3 = THEME.panel
footer.BorderSizePixel = 0
footer.Parent = main; corner(footer, 6)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 18)
statusLabel.Position = UDim2.new(0, 8, 0, 4)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Idle"; statusLabel.TextColor3 = THEME.text
statusLabel.Font = THEME.fontBold; statusLabel.TextSize = 11
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = footer

local debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.new(1, -16, 0, 18)
debugLabel.Position = UDim2.new(0, 8, 0, 24)
debugLabel.BackgroundTransparency = 1
debugLabel.Text = "Ready"; debugLabel.TextColor3 = THEME.subtext
debugLabel.Font = THEME.font; debugLabel.TextSize = 10
debugLabel.TextXAlignment = Enum.TextXAlignment.Left
debugLabel.TextWrapped = true
debugLabel.Parent = footer

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -16, 0, 18)
infoLabel.Position = UDim2.new(0, 8, 0, 46)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Lv -"; infoLabel.TextColor3 = THEME.ok
infoLabel.Font = THEME.fontBold; infoLabel.TextSize = 11
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Parent = footer

table.insert(runtime.tasks, task.spawn(function()
    while gui.Parent and runtime.running and FarmRuntime.current == runtime do
        statusLabel.Text = runtime.state.enabled and runtime.state.status or "Stopped"
        debugLabel.Text = runtime.state.debugLine == "" and "Ready" or runtime.state.debugLine
        infoLabel.Text = string.format("Lv %d • Fruits: %d • Quest: %s • Spd %s",
            getMyLevel(), runtime.state.fruitsFound, questProgressText(),
            tostring(runtime.state.attackSpeed))
        task.wait(0.4)
        if not runtime.isCurrent() then return end
    end
end))

local dragging, dragInput, dragStart, startPos
titleBar.InputBegan:Connect(function(i)
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = i.Position; startPos = main.Position
        local changed = i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
        table.insert(runtime.inputConnections, changed)
    end
end)
titleBar.InputChanged:Connect(function(i)
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
        dragInput = i
    end
end)
table.insert(runtime.inputConnections, UserInputService.InputChanged:Connect(function(i)
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    if dragging and i == dragInput then
        local d = i.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                  startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end))

table.insert(runtime.inputConnections, UserInputService.InputBegan:Connect(function(i, gpe)
    if not runtime.running or FarmRuntime.current ~= runtime then return end
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then gui.Enabled = not gui.Enabled end
    if i.KeyCode == Enum.KeyCode.F9 and setDebug then setDebug(not runtime.config.Debug) end
end))

end

buildPanel()

print("[Farm] Fixed build loaded.")
