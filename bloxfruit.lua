-- // Blox Fruits Auto-Farm — Fixed Build
print("[Farm] build start")
-- One live copy of the bot is allowed. A second execution first tears the old
-- copy down; the generation check makes every old task leave instead of
-- running a second farm beside the new one.
-- Apex executes injected chunks in an isolated script VM. Keep the registry in
-- the executor's shared environment as well as in this chunk, so a later
-- execution can stop the previous copy and live diagnostics can inspect the
-- same runtime that the farm is actually using.
FarmRuntime = (getgenv and getgenv().FarmRuntime) or (_G and _G.FarmRuntime) or {}
if getgenv then getgenv().FarmRuntime = FarmRuntime end
if _G then _G.FarmRuntime = FarmRuntime end
-- Pending Bring Mob restorations outlive one execution. A server-owned rig can
-- keep the snapshot in this shared registry until this client gets ownership
-- back and restores it.
FarmRuntime.bringRestore = FarmRuntime.bringRestore or {}
-- A queued bootstrap carries the hop attempt and its start time into the new
-- server. It is deliberately separate from FarmRuntime, whose live instances
-- must never be reused across servers.
FarmHopBootstrap = (getgenv and getgenv().FarmHopBootstrap)
    or (_G and _G.FarmHopBootstrap) or {}
if getgenv then getgenv().FarmHopBootstrap = FarmHopBootstrap end
if _G then _G.FarmHopBootstrap = FarmHopBootstrap end

-- Some executors cannot read a host filesystem path from inside Roblox. Try
-- to capture the current chunk, but only keep source that really compiles: MK's
-- decompiler can emit invalid control flow for a large injected chunk. The
-- embedded fallback below is the same build without its embedded copy, and the
-- persisted hop metadata keeps that valid source available for later hops.
local function compileSource(source)
    if type(source) ~= "string" or source == "" then return nil end
    local loader = type(loadstring) == "function" and loadstring or load
    if type(loader) ~= "function" then return source end
    local compiled, result = pcall(loader, source)
    if not compiled or type(result) ~= "function" then return nil end
    return source
end

local function captureExecutorSource()
    if type(debug) ~= "table" or type(debug.info) ~= "function" then return nil end
    local env = type(getgenv) == "function" and getgenv() or _G
    local decompiler = type(env) == "table" and env.__mk_decompile or nil
    if type(decompiler) ~= "function" then return nil end
    local chunk = debug.info(2, "f")
    if type(chunk) ~= "function" then return nil end
    local ok, source = pcall(decompiler, chunk)
    if not ok then return nil end
    return compileSource(source)
end

local function persistedRejoinSource()
    local meta = FarmHopBootstrap
    if type(meta) ~= "table" or meta.cancelled == true then return nil end
    return compileSource(meta.source)
end

local EMBEDDED_REJOIN_SOURCE = -- The embedded copy is generated from this same template with the
-- payload set to nil. It is the validated fallback when the host path
-- and the executor decompiler are unavailable (core SHA-256 70b98a61aae3461e60305e7c414121c2608f9ba9e08ccdea8c6b88b916638547).
[===[
-- // Blox Fruits Auto-Farm — Fixed Build
print("[Farm] build start")
-- One live copy of the bot is allowed. A second execution first tears the old
-- copy down; the generation check makes every old task leave instead of
-- running a second farm beside the new one.
-- Apex executes injected chunks in an isolated script VM. Keep the registry in
-- the executor's shared environment as well as in this chunk, so a later
-- execution can stop the previous copy and live diagnostics can inspect the
-- same runtime that the farm is actually using.
FarmRuntime = (getgenv and getgenv().FarmRuntime) or (_G and _G.FarmRuntime) or {}
if getgenv then getgenv().FarmRuntime = FarmRuntime end
if _G then _G.FarmRuntime = FarmRuntime end
-- Pending Bring Mob restorations outlive one execution. A server-owned rig can
-- keep the snapshot in this shared registry until this client gets ownership
-- back and restores it.
FarmRuntime.bringRestore = FarmRuntime.bringRestore or {}
-- A queued bootstrap carries the hop attempt and its start time into the new
-- server. It is deliberately separate from FarmRuntime, whose live instances
-- must never be reused across servers.
FarmHopBootstrap = (getgenv and getgenv().FarmHopBootstrap)
    or (_G and _G.FarmHopBootstrap) or {}
if getgenv then getgenv().FarmHopBootstrap = FarmHopBootstrap end
if _G then _G.FarmHopBootstrap = FarmHopBootstrap end

-- Some executors cannot read a host filesystem path from inside Roblox. Try
-- to capture the current chunk, but only keep source that really compiles: MK's
-- decompiler can emit invalid control flow for a large injected chunk. The
-- embedded fallback below is the same build without its embedded copy, and the
-- persisted hop metadata keeps that valid source available for later hops.
local function compileSource(source)
    if type(source) ~= "string" or source == "" then return nil end
    local loader = type(loadstring) == "function" and loadstring or load
    if type(loader) ~= "function" then return source end
    local compiled, result = pcall(loader, source)
    if not compiled or type(result) ~= "function" then return nil end
    return source
end

local function captureExecutorSource()
    if type(debug) ~= "table" or type(debug.info) ~= "function" then return nil end
    local env = type(getgenv) == "function" and getgenv() or _G
    local decompiler = type(env) == "table" and env.__mk_decompile or nil
    if type(decompiler) ~= "function" then return nil end
    local chunk = debug.info(2, "f")
    if type(chunk) ~= "function" then return nil end
    local ok, source = pcall(decompiler, chunk)
    if not ok then return nil end
    return compileSource(source)
end

local function persistedRejoinSource()
    local meta = FarmHopBootstrap
    if type(meta) ~= "table" or meta.cancelled == true then return nil end
    return compileSource(meta.source)
end

local EMBEDDED_REJOIN_SOURCE = nil
FarmRuntime.rejoinSource = EMBEDDED_REJOIN_SOURCE
    or persistedRejoinSource()
    or captureExecutorSource()
if getgenv then pcall(function() getgenv().FarmRuntime = FarmRuntime end) end
if _G then pcall(function() _G.FarmRuntime = FarmRuntime end) end

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
    operationEpoch = 0,
    state = nil,
    config = nil,
}
runtime.isCurrent = function()
    return runtime.running and FarmRuntime.current == runtime
end
-- A reset starts a new operation generation. Long operations capture the old
-- value before they yield and must not write state or keep moving after a
-- disable, re-enable, respawn or teardown.
runtime.operationValid = function(operationEpoch, characterEpoch, char)
    return runtime.isCurrent()
        and runtime.operationEpoch == operationEpoch
        and runtime.characterEpoch == characterEpoch
        and runtime.state ~= nil
        and runtime.state.enabled == true
        and (char == nil or LocalPlayer.Character == char)
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
TeleportService   = game:GetService("TeleportService")
HttpService       = game:GetService("HttpService")
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
    -- Fast Attack sends the normal RegisterAttack/RegisterHit flow at this
    -- cadence. Health feedback backs it off automatically when the server
    -- refuses a hit, so a quick cadence never turns into false confirmations.
    FastAttackInterval = 0.4,
    FastAttackFeedback = 0.55,
    RemoteAttack    = true,
    HitboxMagnitude = 120,
    WeaponMode      = "Melee",
    MeleeRange      = 50,
    GunRange        = 70,
    FruitRange      = 70,
    AutoBuyStyles   = false,
    AutoSaber       = false,
    -- The puzzle includes long walks and two boss fights. Ninety seconds
    -- stopped a healthy run halfway through; five minutes still catches a
    -- genuinely stuck step without breaking the step-by-step flow.
    AutoSaberTimeout = 300,
    MeleeHover      = 4,
    BringMob        = true,
    BringMobRange   = 60,
    -- Do not grab a mob while the player is still high above it. A purely
    -- horizontal check caught mobs across cliffs and under the ocean plane.
    BringMobVerticalRange = 18,
    BringMobCount   = 5,
    -- The proven Bring Mobs source searches the same-name pack far away.
    -- The bounded radius keeps a coast or another island out of the pack;
    -- ownership, path checks and the BringMobMax cap bound it further.
    BringMobSearch  = 300,
    -- A direct CFrame snap can jump over a narrow coast. Keep it off by
    -- default; the body mover still closes a path that was proved dry.
    BringMobSnap    = false,
    BringMobSnapDistance = 4,
    -- Carry the target under the player when this client owns it. A
    -- server-owned target keeps the source's reliable layout instead: the
    -- extras are packed around it and the player walks to the target.
    BringMobCarryTarget = true,
    -- Every carried mob gets a private, runtime-owned root BodyVelocity.
    -- The game's BodyMover intentionally refuses enemy characters, so it is
    -- never used to move a mob.
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
    -- The farm moves between safe slots around the target instead of
    -- spinning the character in place. Twenty-eight studs is outside the
    -- normal enemy melee threat and still inside the real melee/gun range.
    DodgeRadius     = 28,
    DodgeSpeed      = 90,
    DodgeStepTime   = 0.4,
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

    -- New collection and target features default off. Automatic quest and
    -- boss behaviour therefore stays exactly as it was until the user picks
    -- an explicit target or enables the extra utility.
    AutoChest       = false,
    ChestRange      = 5000,
    ChestTimeout    = 30,
    PoleMastery     = false,
    PoleTarget      = "Bandit",
    SelectedMob     = "Auto",
    ManualQuest     = "Auto",
    BossTarget      = "Auto",
    FruitESP        = false,
    FruitNotifier   = false,
    FruitWebhook    = "",
    AntiFall        = true,
    AutoHop         = false,
    HopCooldown     = 120,
    HopMaxAttempts  = 3,
    HopFailureQuarantine = 10,
    RejoinScriptPath = "/home/x86thegod/Downloads/bloxfruit.lua",
    KickRecovery    = true,
    TeamSelection   = "None",

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
    dodgeSlotAt   = 0,
    dodgeSlotIndex = 0,
    dodgeSlotTarget = nil,
    dodgeSlotAngle = 0,
    dodgePatrolCentre = nil,
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
    promptHolds   = setmetatable({}, {__mode = "k"}),
    promptHoldSeq = 0,
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
    shopMovementToken = nil,
    saberMovementToken = nil,
    styleTrialAt  = {},
    flying        = false,
    flightToken   = 0,
    flightOwner   = nil,
    flightMovementToken = nil,
    movementOwner = nil,
    movementToken = 0,
    movementOwnerToken = 0,
    whirlpooling  = false,
    questing      = false,
    bringHeld     = setmetatable({}, {__mode = "k"}),
    bringSaved    = setmetatable({}, {__mode = "k"}),
    bringSnapped  = setmetatable({}, {__mode = "k"}),
    bringCarryingTarget = setmetatable({}, {__mode = "k"}),
    bringSlot     = setmetatable({}, {__mode = "k"}),
    bringSlotCount = 0,
    bringPoint    = nil,
    bringTarget   = nil,
    bringCentre   = nil,
    bringCarryOffsetY = nil,
    bringPathBlocked = false,
    bringPathCheck = nil,
    bringPathCache = setmetatable({}, {__mode = "k"}),
    bringMover    = setmetatable({}, {__mode = "k"}),
    bringMoverSeq = 0,
    questVerified = false,
    questGaveUp   = false,
    questRemoteState = nil,
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
    attackReportedLength = 0.5,
    attackDispatched = false,
    attackRegistered = false,
    attackHitDispatched = false,
    attackConfirmed = false,
    attackPrimaryConfirmed = false,
    attackFallback = false,
    attackComboSent = false,
    attackConfirmSeq = 0,
    attackPending = {},
    attackHealthSeen = setmetatable({}, {__mode = "k"}),
    attackCadence = 0.4,
    attackMisses = 0,
    attackLastConfirmedAt = 0,
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
    saberSonReady = false,
    saberPlates = {},
    saberUsedTorch = false,
    saberUsedCup = false,
    saberKilledMob = false,
    saberUsedRelic = false,
    saberKilledShanks = false,
    saberRelicGrantAccepted = false,
    saberRelicConfirmed = false,
    saberMobLeaderRequired = false,
    saberAttemptKey = nil,
    saberAttemptAt = 0,
    saberAttempts = {},
    saberCupRequestAt = 0,
    saberCupGranted = false,
    saberCupTouched = false,
    saberCupTouchAt = 0,
    saberCupTouchTool = nil,
    saberCupTouchWater = nil,
    saberCupTouchHandle = nil,
    saberCupTouchConnection = nil,
    saberFillRequestAt = 0,
    saberFillPending = false,
    saberFillSickAt = 0,
    saberFillSickResult = nil,
    saberRelicRequestAt = 0,
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
    -- Feature state is transient unless it lives in CONFIG. Weak tables are
    -- used for instances so a removed fruit, chest or mob cannot leave stale
    -- objects behind.
    fruitEspVisuals = setmetatable({}, {__mode = "k"}),
    notifiedFruits  = setmetatable({}, {__mode = "k"}),
    -- Notification success belongs to one destination. Changing the webhook
    -- must allow the same fruit to be delivered to the new URL.
    notifiedFruitUrls = setmetatable({}, {__mode = "k"}),
    -- A notification is marked only after the webhook accepted it. Failed
    -- requests stay here and are retried with a small backoff.
    fruitNotificationPending = setmetatable({}, {__mode = "k"}),
    chestSeen       = setmetatable({}, {__mode = "k"}),
    chestTarget     = nil,
    chestTargetPart = nil,
    chestTargetIdentityPart = nil,
    chestStartedAt  = 0,
    chestSelectedAt = 0,
    chestTravelDeadline = 0,
    chestLastTry    = 0,
    chestLastScanAt = 0,
    chestToken      = 0,
    chestMovementToken = nil,
    chestTouchAt    = 0,
    chestTouchPart  = nil,
    chestTouchRoot  = nil,
    chestSequence   = 0,
    chestTouchSequence = 0,
    chestTouchRewardBaselineAt = 0,
    chestTouchBeliBefore = nil,
    chestTouchFruitBefore = nil,
    chestTouchFragmentsBefore = nil,
    chestServerAt   = 0,
    chestServerState = nil,
    chestOpenedAt   = 0,
    chestCollectedAt = 0,
    chestDisabledAt = 0,
    chestOpenedSequence = 0,
    chestCollectedSequence = 0,
    chestDisabledSequence = 0,
    chestBeliBefore = nil,
    chestFruitBefore = nil,
    chestFragmentsBefore = nil,
    chestRewardBaselineAt = 0,
    chestConnections = {},
    poleToken       = 0,
    poleLevel       = 0,
    poleExp         = 0,
    poleHits        = 0,
    poleEquipped    = false,
    poleWeapon      = nil,
    poleMovementToken = nil,
    codeToken       = 0,
    codeInFlight    = false,
    teamToken       = 0,
    teamInFlight    = false,
    currentTeam     = "None",
    travelToken     = 0,
    travelMovementToken = nil,
    travelActive    = false,
    currentSea      = nil,
    currentSeaAt    = 0,
    seaDetectionToken = 0,
    questRevision   = 0,
    questCatalogToken = 0,
    questCatalogLoading = false,
    questRequestToken = 0,
    questRequestInFlight = false,
    selectedMob     = nil,
    selectedBoss    = nil,
    hopToken        = 0,
    hopAttempt      = 0,
    hopStartedAt    = 0,
    hopLastAt       = 0,
    hopInFlight     = false,
    hopQueued       = false,
    hopFailureAt    = 0,
    hopFailureSource = nil,
    hopFailureQuarantineUntil = 0,
    hopMovementToken = nil,
    hopQueuedAt     = 0,
    hopExhaustedNotified = false,
    hopJobId        = "",
    manualQuestKey  = nil,
    manualQuestRequestAt = 0,
    manualQuestRevision = 0,
    manualQuestSentKey = nil,
    manualQuestAttempts = 0,
    manualQuestRequestRevision = 0,
    manualQuestRequestId = 0,
    questRefreshAt  = 0,
    islandRevision  = 0,
}

runtime.config = CONFIG
runtime.state = state
state.hopAttempt = tonumber(FarmHopBootstrap.attempt) or 0
state.hopStartedAt = tonumber(FarmHopBootstrap.startedAt) or os.time()
state.hopLastAt = tonumber(FarmHopBootstrap.lastAt) or state.hopStartedAt
state.hopJobId = tostring(FarmHopBootstrap.jobId or "")
if type(FarmHopBootstrap.path) == "string" and FarmHopBootstrap.path ~= "" then
    CONFIG.RejoinScriptPath = FarmHopBootstrap.path
end

-- Shop, flight and Saber are exclusive movement owners. Ordinary farming can
-- still move the character while Saber is fighting a boss, but two long
-- operations must never cancel or retarget each other's tween.
runtime.acquireMovement = function(owner)
    if not owner then return false end
    local current = runtime.state.movementOwner
    if current then
        if current ~= owner then return false end
        -- Re-entering the same owner keeps its token. A nested shop flight or
        -- Saber step must not invalidate the outer operation that owns it.
        return true, runtime.state.movementOwnerToken
    end
    runtime.state.movementToken = (runtime.state.movementToken or 0) + 1
    runtime.state.movementOwnerToken = runtime.state.movementToken
    runtime.state.movementOwner = owner
    return true, runtime.state.movementOwnerToken
end
runtime.releaseMovement = function(owner, ownerToken)
    if runtime.state.movementOwner == owner
        and (ownerToken == nil or runtime.state.movementOwnerToken == ownerToken) then
        runtime.state.movementOwner = nil
        runtime.state.movementOwnerToken = 0
    end
end

-- Transient state is reset as one unit. A disabled bot, a character change, a
-- Saber timeout and a fresh enable must never inherit an old attack combo,
-- prompt throttle, burst window or half-finished puzzle action.
runtime.resetSaberState = function()
    local s = runtime.state
    s.saberActive = false
    if runtime.releaseTweenHold then runtime.releaseTweenHold() end
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
    s.saberSonReady = false
    s.saberPlates = {}
    s.saberUsedTorch = false
    s.saberUsedCup = false
    s.saberKilledMob = false
    s.saberUsedRelic = false
    s.saberKilledShanks = false
    s.saberRelicGrantAccepted = false
    s.saberRelicConfirmed = false
    s.saberMobLeaderRequired = false
    local saberMovementToken = s.saberMovementToken
    s.saberMovementToken = nil
    if runtime.releaseMovement then runtime.releaseMovement("saber", saberMovementToken) end
    s.saberAttemptKey = nil
    s.saberAttemptAt = 0
    s.saberAttempts = {}
    s.saberCupRequestAt = 0
    s.saberCupGranted = false
    if s.saberDesertCupConnection then
        pcall(function() s.saberDesertCupConnection:Disconnect() end)
    end
    s.saberDesertCupConnection = nil
    s.saberDesertCupTouched = false
    s.saberDesertCupTouchPart = nil
    s.saberDesertCupTouchAt = 0
    if s.saberCupTouchConnection then
        pcall(function() s.saberCupTouchConnection:Disconnect() end)
    end
    s.saberCupTouchConnection = nil
    s.saberCupTouched = false
    s.saberCupTouchAt = 0
    s.saberCupTouchTool = nil
    s.saberCupTouchWater = nil
    s.saberCupTouchHandle = nil
    s.saberFillRequestAt = 0
    s.saberFillPending = false
    s.saberFillSickAt = 0
    s.saberFillSickResult = nil
    s.saberRelicRequestAt = 0
    s.saberPlaceRequestAt = 0
    s.saberPlaceAccepted = false
end

-- A fallback prompt hold belongs to the bot until the hold has ended. A
-- character change, a reset or teardown must not leave a hidden hold on the
-- new character, so every bot-started hold is ended explicitly.
runtime.endPromptHolds = function()
    local holds = runtime.state and runtime.state.promptHolds
    if not holds then return end
    for prompt in pairs(holds) do
        -- Remove the marker before ending the hold. A completion task from the
        -- old hold then cannot end a newer hold on the same prompt.
        holds[prompt] = nil
        pcall(function() prompt:InputHoldEnd() end)
    end
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
    s.attackReportedLength = 0.5
    s.attackDispatched, s.attackRegistered, s.attackHitDispatched = false, false, false
    s.attackConfirmed, s.attackPrimaryConfirmed = false, false
    s.attackFallback, s.attackComboSent = false, false
    -- Confirmation sequence numbers are never reused. An old watcher that is
    -- still finishing must not mistake a reset run for its own sequence.
    s.attackConfirmSeq = (s.attackConfirmSeq or 0) + 1
    s.attackPending = {}
    s.attackHealthSeen = setmetatable({}, {__mode = "k"})
    s.attackCadence = tonumber(runtime.config.FastAttackInterval) or 0.4
    s.attackMisses = 0
    s.attackLastConfirmedAt = 0
    s.aoeCount, s.aoeRequested, s.aoeConfirmed = 0, 0, 0
    s.hitsConfirmed = 0
    s.lastHitAt, s.lastHitMob = nil, nil
    s.lastTarget, s.targetHealth, s.targetAt, s.targetDist = nil, nil, 0, nil
    s.travelAt = 0
    s.lastRemoteAttackAt = nil
    s.combatUtil, s.combatUtilMod = nil, nil
    s.netModule, s.netModuleInstance = nil, nil
    s.hitRemoteCache, s.attackRemoteCache = nil, nil
    s.hitUseFallback = false
end

-- A purchase owns the main loop while it walks to a teacher or waits for a
-- server reply. Invalidate it as one unit so an old RPC can never leave the
-- new run permanently stuck behind stale shopping flags.
runtime.resetShopState = function()
    local s = runtime.state
    s.shopping = false
    s.shopInFlight = false
    s.shopToken = (s.shopToken or 0) + 1
    s.blockAt = nil
    local shopMovementToken = s.shopMovementToken
    s.shopMovementToken = nil
    if runtime.releaseMovement then runtime.releaseMovement("shop", shopMovementToken) end
end

-- Pole progress is tied to one real Pole tool. A tool replacement, a mode
-- change, a respawn or a teardown starts a fresh passive-mastery session.
runtime.resetPoleState = function()
    local s = runtime.state
    s.poleToken = (s.poleToken or 0) + 1
    s.poleLevel = 0
    s.poleExp = 0
    s.poleHits = 0
    s.poleEquipped = false
    s.poleProgressAt = 0
    s.poleWeapon = nil
    if runtime.releaseMovement and s.poleMovementToken then
        runtime.releaseMovement("pole", s.poleMovementToken)
    end
    s.poleMovementToken = nil
end

runtime.resetTransient = function()
    -- Invalidate every operation that can yield. The old attack, quest, flight
    -- or prompt task may wake up after this point; it must leave without
    -- touching the new state.
    runtime.operationEpoch = (runtime.operationEpoch or 0) + 1
    runtime.resetSaberState()
    runtime.resetCombatState()
    runtime.resetShopState()
    runtime.resetFeatureState()
    -- Invalidate an old flight before a new one can start. The old coroutine
    -- must never clear the new flight's flag when it wakes up later.
    local flightOwner = runtime.state.flightOwner
    local flightOwnerToken = runtime.state.flightMovementToken
    runtime.state.flightToken = (runtime.state.flightToken or 0) + 1
    runtime.state.flightOwner = nil
    runtime.state.flightMovementToken = nil
    runtime.state.flying = false
    if flightOwner and runtime.releaseMovement then
        runtime.releaseMovement(flightOwner, flightOwnerToken)
    end
    if runtime.endPromptHolds then runtime.endPromptHolds() end
    local s = runtime.state
    s.lastPrompt, s.promptAt = nil, 0
    s.autoBurst, s.autoBurstCd = 0, 0
    s.questing = false
    -- Turn-in and quest-seek deadlines belong to the old attempt. Keeping
    -- them across a disable, respawn or re-enable can make the next run give
    -- up before its first request or wait on a target that no longer exists.
    s.turnInSince, s.turnInFailed, s.turnInFailedAt = nil, false, 0
    s.seekSince, s.seekGaveUp, s.seekGaveUpAt = nil, false, 0
    s.dodgeSlotAt, s.dodgeSlotIndex = 0, 0
    s.dodgeSlotTarget, s.dodgeSlotAngle, s.dodgePatrolCentre = nil, 0, nil
    s.farming = false
end

local grabbedFruits = setmetatable({}, {__mode = "k"})

-- The feature requests that can yield have their own tokens. A reset, a
-- respawn or a second execution must not let an old chest, code, team, travel
-- or Pole reply write into the new state.
runtime.resetFeatureState = function()
    local s = runtime.state
    local chestMovementToken = s.chestMovementToken
    if chestMovementToken == nil and s.movementOwner == "chest" then
        chestMovementToken = s.movementOwnerToken
    end
    local chestOwnsMovement = s.movementOwner == "chest"
        and s.movementOwnerToken == chestMovementToken
    local travelMovementToken = s.travelMovementToken
    local hopMovementToken = s.hopMovementToken
    s.chestToken = (s.chestToken or 0) + 1
    if runtime.clearChestConnections then runtime.clearChestConnections() end
    s.codeToken = (s.codeToken or 0) + 1
    s.teamToken = (s.teamToken or 0) + 1
    s.travelToken = (s.travelToken or 0) + 1
    if runtime.cancelHopMetadata then runtime.cancelHopMetadata(s.hopToken) end
    s.hopToken = (s.hopToken or 0) + 1
    -- A cancelled teleport can still emit one late TeleportInitFailed event.
    -- Keep a short quarantine in which no new request may start, so that late
    -- event cannot be attributed to the newer request.
    local hopQuarantine = math.max(0, tonumber(runtime.config.HopFailureQuarantine) or 10)
    s.hopFailureQuarantineUntil = os.time() + hopQuarantine
    s.hopFailureSource = "cancelled"
    s.codeInFlight = false
    s.teamInFlight = false
    s.travelActive = false
    s.hopInFlight = false
    s.hopQueued = false
    s.hopMovementToken = nil
    s.hopQueuedAt = 0
    s.chestTarget, s.chestTargetPart = nil, nil
    s.chestTargetIdentityPart = nil
    s.chestStartedAt, s.chestSelectedAt, s.chestLastTry = 0, 0, 0
    s.chestTravelDeadline, s.chestLastScanAt = 0, 0
    s.chestTouchAt, s.chestTouchPart, s.chestTouchRoot = 0, nil, nil
    s.chestSequence, s.chestTouchSequence = 0, 0
    s.chestTouchRewardBaselineAt = 0
    s.chestTouchBeliBefore = nil
    s.chestTouchFruitBefore = nil
    s.chestTouchFragmentsBefore = nil
    s.chestServerAt, s.chestServerState = 0, nil
    s.chestOpenedAt, s.chestCollectedAt, s.chestDisabledAt = 0, 0, 0
    s.chestOpenedSequence, s.chestCollectedSequence = 0, 0
    s.chestDisabledSequence = 0
    s.chestBeliBefore = nil
    s.chestFruitBefore = nil
    s.chestFragmentsBefore = nil
    s.chestRewardBaselineAt = 0
    s.chestMovementToken = nil
    s.travelMovementToken = nil
    -- Force a fresh Realm check after a reset instead of trusting a sea
    -- value that belonged to the previous character or server. Invalidate an
    -- older Realm lookup as well as the operation epoch.
    s.currentSea = nil
    s.currentSeaAt = 0
    s.seaDetectionToken = (s.seaDetectionToken or 0) + 1
    -- A catalog load that is still yielding belongs to the old runtime. It
    -- must not install its result or leave new requests blocked.
    s.questCatalogToken = (s.questCatalogToken or 0) + 1
    s.questCatalogLoading = false
    s.selectedMob, s.selectedBoss = nil, nil
    -- A reset invalidates an in-flight manual request. The selected quest stays
    -- in the configuration, but its request counters and reply revision start
    -- from a clean state on the next run.
    s.manualQuestRevision = (s.manualQuestRevision or 0) + 1
    s.questRequestToken = (s.questRequestToken or 0) + 1
    s.questRequestInFlight = false
    s.manualQuestRequestAt = 0
    s.manualQuestSentKey = nil
    s.manualQuestAttempts = 0
    s.manualQuestRequestRevision = 0
    -- Keep request ids monotonic across a reset. An old response must not
    -- be able to clear the marker of a new request that happens to reuse the
    -- same numeric id after the state was recreated.
    s.manualQuestRequestId = (s.manualQuestRequestId or 0) + 1
    s.lastManualQuest = nil
    if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
    -- Hop attempt metadata is deliberately not reset here. A disable/re-enable
    -- must not turn an automatic hop loop back into attempt zero.
    if runtime.destroyFruitEsp then runtime.destroyFruitEsp() end
    if runtime.resetPoleState then runtime.resetPoleState() end
    if chestOwnsMovement and runtime.stopTween then runtime.stopTween() end
    if runtime.releaseMovement then
        runtime.releaseMovement("chest", chestMovementToken)
        runtime.releaseMovement("travel", travelMovementToken)
        runtime.releaseMovement("hop", hopMovementToken)
    end
end

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

-- ================= SERVER HOP / REJOIN =================
-- A hop is two coordinated actions. The exact source is queued for the new
-- server and TeleportService starts the same-place teleport. The queued
-- bootstrap carries the attempt number as literals, so the chain cannot be
-- restarted from zero if the executor clears its global environment while the
-- client is changing servers.
runtime.hopBootstrapSource = function(path, attempt, startedAt, lastAt, reason,
    requestToken, rejoinSource)
    return string.format([=[
local REJOIN_PATH = %q
local HOP_ATTEMPT = %d
local HOP_STARTED_AT = %d
local HOP_LAST_AT = %d
local HOP_REASON = %q
local HOP_REQUEST_TOKEN = %d
local REJOIN_SOURCE = %q

local function executorEnvironment()
    local env
    if type(getgenv) == "function" then
        pcall(function() env = getgenv() end)
    end
    if type(env) ~= "table" then env = _G end
    if type(env) ~= "table" then env = {} end
    return env
end

local env = executorEnvironment()
local meta = env.FarmHopBootstrap
-- The executor global is the cancellation authority. A queued bootstrap from
-- an older request must not overwrite or start a newer hop chain.
local stale = type(meta) ~= "table"
    or tonumber(meta.requestToken) ~= HOP_REQUEST_TOKEN
    or meta.cancelled == true
if not stale then
meta.attempt = HOP_ATTEMPT
meta.startedAt = HOP_STARTED_AT
meta.lastAt = HOP_LAST_AT
meta.path = REJOIN_PATH
meta.reason = HOP_REASON
meta.requestToken = HOP_REQUEST_TOKEN
meta.cancelled = false
if type(REJOIN_SOURCE) == "string" and REJOIN_SOURCE ~= "" then
    meta.source = REJOIN_SOURCE
end
env.FarmHopBootstrap = meta
if type(getgenv) == "function" then
    pcall(function() getgenv().FarmHopBootstrap = meta end)
end
if type(_G) == "table" then _G.FarmHopBootstrap = meta end

local function compileAndRun(source)
    local loader = type(loadstring) == "function" and loadstring or load
    if type(loader) ~= "function" then return false, "no source loader" end
    local chunk, err = loader(source)
    if type(chunk) ~= "function" then return false, tostring(err) end
    chunk()
    return true
end

local function runRejoin()
    -- An embedding executor may provide the exact source directly. The file
    -- path is the normal route and is checked first so a stale embedded copy
    -- can never replace the file the user selected. A path read failure is
    -- not terminal: the executor may deliberately reject host paths while
    -- still supporting the source embedded in this bootstrap.
    local pathError = nil
    if type(readfile) == "function" then
        local ok, source = pcall(readfile, REJOIN_PATH)
        if ok and type(source) == "string" and source ~= "" then
            local ran, err = compileAndRun(source)
            if ran then return end
            error(err)
        end
        pathError = type(source) == "string" and source or "readfile failed"
    end
    if type(loadfile) == "function" then
        local ok, chunk, err = pcall(loadfile, REJOIN_PATH)
        if ok and type(chunk) == "function" then
            chunk()
            return
        end
        pathError = type(err) == "string" and err or pathError
    end
    if type(dofile) == "function" then
        local ok, err = pcall(dofile, REJOIN_PATH)
        if ok then return end
        pathError = type(err) == "string" and err or pathError
    end
    if type(meta.source) == "string" and meta.source ~= "" then
        local ran, err = compileAndRun(meta.source)
        if ran then return end
        error(err)
    end
    error("the executor cannot read the rejoin script"
        .. (type(pathError) == "string" and (": " .. pathError) or ""))
end

runRejoin()
end
]=], tostring(path or ""), tonumber(attempt) or 1,
        tonumber(startedAt) or os.time(), tonumber(lastAt) or os.time(),
        tostring(reason or "hop"), tonumber(requestToken) or 0,
        tostring(rejoinSource or ""))
end

runtime.writeHopMetadata = function(attempt, startedAt, lastAt, path, reason,
    requestToken, rejoinSource)
    local meta = FarmHopBootstrap
    if type(meta) ~= "table" then meta = {} end
    meta.attempt = tonumber(attempt) or 0
    meta.startedAt = tonumber(startedAt) or os.time()
    meta.lastAt = tonumber(lastAt) or os.time()
    meta.path = tostring(path or runtime.config.RejoinScriptPath or "")
    meta.reason = tostring(reason or "hop")
    meta.jobId = tostring(game.JobId or "")
    meta.requestToken = tonumber(requestToken) or 0
    meta.cancelled = false
    if type(rejoinSource) == "string" and rejoinSource ~= "" then
        meta.source = rejoinSource
    end
    FarmHopBootstrap = meta
    if getgenv then pcall(function() getgenv().FarmHopBootstrap = meta end) end
    if _G then pcall(function() _G.FarmHopBootstrap = meta end) end
    return meta
end

runtime.cancelHopMetadata = function(requestToken)
    local meta = FarmHopBootstrap
    if type(meta) ~= "table" then return false end
    local owner = tonumber(meta.requestToken)
    if requestToken ~= nil and owner ~= tonumber(requestToken) then return false end
    meta.cancelled = true
    return true
end

runtime.failHop = function(requestToken, movementToken, reason, failureSource)
    local s = runtime.state
    if requestToken == nil or s.hopToken ~= requestToken then return false end
    -- The queued source cannot be removed from the executor. Mark this exact
    -- request cancelled so a late teleport cannot revive it.
    if runtime.cancelHopMetadata then runtime.cancelHopMetadata(requestToken) end
    s.hopInFlight = false
    s.hopQueued = false
    s.hopQueuedAt = 0
    s.hopFailureAt = os.time()
    s.hopFailureSource = tostring(failureSource or "request")
    -- A timeout or cancellation may still have one late failure event in
    -- flight. Quarantine a new request briefly so that event cannot clear the
    -- newer request's movement owner. A failure event already consumed by
    -- this handler needs no such quarantine.
    if s.hopFailureSource ~= "event" then
        local quarantine = math.max(0, tonumber(runtime.config.HopFailureQuarantine) or 10)
        s.hopFailureQuarantineUntil = os.time() + quarantine
    end
    local ownedToken = movementToken or s.hopMovementToken
    s.hopMovementToken = nil
    runtime.releaseMovement("hop", ownedToken)
    dbg("Server hop failed: " .. tostring(reason or "unknown reason"))
    return true
end

runtime.hopServer = function(reason, manual)
    local s = runtime.state
    reason = tostring(reason or "manual")
    manual = manual == true
    if s.hopInFlight then
        dbg("A server hop is already running")
        return false
    end
    local quarantineUntil = tonumber(s.hopFailureQuarantineUntil) or 0
    if os.time() < quarantineUntil then
        dbg("Server hop is waiting for the previous teleport failure to settle")
        return false
    end
    local maxAttempts = math.max(1, math.floor(tonumber(runtime.config.HopMaxAttempts) or 3))
    local attempt = math.max(0, math.floor(tonumber(s.hopAttempt) or 0))
    local startedAt = tonumber(s.hopStartedAt) or os.time()
    if manual then
        -- A button press starts a new chain. Automatic hops keep counting the
        -- old chain and cannot use a manual reset to bypass the limit.
        attempt = 0
        startedAt = os.time()
        s.hopExhaustedNotified = false
    elseif attempt >= maxAttempts then
        if not s.hopExhaustedNotified then
            s.hopExhaustedNotified = true
            dbg("Server hop stopped: the attempt limit was reached")
        end
        return false
    end
    local path = tostring(runtime.config.RejoinScriptPath or ""):match("^%s*(.-)%s*$") or ""
    if path == "" then
        dbg("Server hop failed: the rejoin script path is empty")
        return false
    end
    if type(queue_on_teleport) ~= "function" then
        dbg("Server hop failed: queue_on_teleport is not available")
        return false
    end

    local acquired, movementToken = runtime.acquireMovement("hop")
    if not acquired and reason == "kick" then
        -- A kick is the one case where the old movement owner must not keep
        -- the client in the server it is being removed from.
        local oldOwner = s.movementOwner
        local oldToken = s.movementOwnerToken
        runtime.operationEpoch = (runtime.operationEpoch or 0) + 1
        if oldOwner then runtime.releaseMovement(oldOwner, oldToken) end
        acquired, movementToken = runtime.acquireMovement("hop")
    end
    if not acquired then
        dbg("Server hop failed: another movement operation is running")
        return false
    end

    local requestToken = (s.hopToken or 0) + 1
    s.hopToken = requestToken
    s.hopInFlight = true
    s.hopMovementToken = movementToken
    runtime.stopTween()

    local now = os.time()
    local nextAttempt = attempt + 1
    local rejoinSource = type(FarmRuntime.rejoinSource) == "string"
        and FarmRuntime.rejoinSource or ""
    -- Publish the request token before queueing. The bootstrap checks this
    -- exact token after the teleport and refuses to run if a newer request or
    -- a cancellation replaced it.
    runtime.writeHopMetadata(nextAttempt, startedAt, now, path, reason,
        requestToken, rejoinSource)
    local source = runtime.hopBootstrapSource(path, nextAttempt, startedAt, now,
        reason, requestToken, rejoinSource)
    local queued, queueError = pcall(queue_on_teleport, source)
    if not queued then
        runtime.failHop(requestToken, movementToken, queueError)
        return false
    end

    s.hopAttempt = nextAttempt
    s.hopStartedAt = startedAt
    s.hopLastAt = now
    s.hopQueued = true
    s.hopQueuedAt = now
    s.hopFailureAt = 0
    s.hopFailureSource = nil
    s.hopExhaustedNotified = false

    local placeId = game.PlaceId
    local teleported, teleportError = pcall(function()
        -- Teleport is the last client-side teleport API. TeleportAsync is now
        -- server-only; this experience still accepts the client request.
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
    if not teleported then
        runtime.failHop(requestToken, movementToken, teleportError)
        return false
    end
    runtime.state.status = "Changing server..."
    dbg("Server hop " .. tostring(nextAttempt) .. " was queued")
    return true
end

runtime.resetHopAttempts = function()
    local s = runtime.state
    if s.hopInFlight or s.hopQueued then
        dbg("The hop attempt list cannot be reset while a hop is running")
        return false
    end
    local now = os.time()
    -- Even though the live flags are already clear, a queued source may still
    -- exist in the executor. Replace its request token so it cannot revive an
    -- old attempt after the user resets the chain.
    if runtime.cancelHopMetadata then runtime.cancelHopMetadata(s.hopToken) end
    local quarantine = math.max(0, tonumber(runtime.config.HopFailureQuarantine) or 10)
    s.hopFailureQuarantineUntil = now + quarantine
    s.hopFailureSource = "cancelled"
    s.hopAttempt = 0
    s.hopStartedAt = now
    s.hopLastAt = now
    s.hopExhaustedNotified = false
    s.hopFailureAt = 0
    runtime.writeHopMetadata(0, now, now, runtime.config.RejoinScriptPath, "reset", 0)
    dbg("Server hop attempts were reset")
    return true
end

runtime.updateHopScheduler = function()
    local s = runtime.state
    if s.hopQueued then
        -- A client can accept the queue and still lose the teleport before it
        -- starts. This check must run before the in-flight guard: a queued hop
        -- keeps both flags set while the teleport request is pending.
        local queuedAt = tonumber(s.hopQueuedAt) or 0
        if queuedAt > 0 and os.time() - queuedAt >= 30 then
            runtime.failHop(s.hopToken, s.hopMovementToken, "teleport timed out", "timeout")
        end
        return false
    end
    if s.hopInFlight then return false end
    if not runtime.config.AutoHop or not s.enabled then return false end
    local maxAttempts = math.max(1, math.floor(tonumber(runtime.config.HopMaxAttempts) or 3))
    local attempt = math.max(0, math.floor(tonumber(s.hopAttempt) or 0))
    if attempt >= maxAttempts then
        if not s.hopExhaustedNotified then
            s.hopExhaustedNotified = true
            dbg("Automatic server hop stopped: the attempt limit was reached")
        end
        return false
    end
    local cooldown = math.max(0, tonumber(runtime.config.HopCooldown) or 120)
    local lastAt = tonumber(s.hopLastAt) or tonumber(s.hopStartedAt) or os.time()
    if os.time() - lastAt < cooldown then return false end
    return runtime.hopServer("auto", false)
end

runtime.armHopRecovery = function()
    local playerConnection = Players.PlayerRemoving:Connect(function(player)
        if player ~= LocalPlayer or not runtime.config.KickRecovery then return end
        if not runtime.isCurrent() then return end
        runtime.hopServer("kick", false)
    end)
    table.insert(runtime.hookConnections, playerConnection)

    local teleportFailure = TeleportService.TeleportInitFailed:Connect(function(player, result, message)
        if player ~= LocalPlayer then return end
        local s = runtime.state
        if not s.hopInFlight then return end
        -- TeleportInitFailed has no request id. Cancelled and timed-out
        -- requests quarantine the next request, so an old late event is
        -- consumed while no new hop owns the movement. A genuine failure of
        -- the current request is then handled normally; no sticky
        -- "prior failure" flag may hide later failures.
        if os.time() < (tonumber(s.hopFailureQuarantineUntil) or 0) then return end
        local detail = tostring(result or "")
        if message and message ~= "" then detail = detail .. ": " .. tostring(message) end
        runtime.failHop(s.hopToken, s.hopMovementToken, detail, "event")
    end)
    table.insert(runtime.hookConnections, teleportFailure)
end

runtime.armHopRecovery()
table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(1)
        if not runtime.isCurrent() then return end
        runtime.updateHopScheduler()
    end
end))

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
    if type(value) == "number" then return math.floor(tonumber(value) or 0) end
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local alt = stats and stats:FindFirstChild("Level")
    value = readNumber(alt)
    if type(value) == "number" then return math.floor(tonumber(value) or 0) end
    return 1
end

local function toolKind(tool)
    local tip = tool.ToolTip
    if type(tip) == "string" and tip ~= "" then return tip:lower() end
    return nil
end

local function isFruit(t)
    if t.Name:lower():find("fruit", 1, true) then return true end
    -- Current official fruit tools can be named "Light-Light" or "Ice-Ice"
    -- and identify themselves with the exact tooltip "Blox Fruit". Do not use
    -- an ItemId alone: weapon-only ItemIds are not fruits.
    local kind = toolKind(t)
    return kind == "fruit" or kind == "blox fruit"
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
    if runtime.config.PoleMastery then
        -- Pole Mastery is a dedicated mode. Falling back to another weapon
        -- would give hits to the wrong mastery and reset the attack combo.
        return runtime.equipPole and runtime.equipPole() or nil
    end
    if runtime.state.poleWeapon and runtime.resetPoleState then runtime.resetPoleState() end
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
    -- Bring Mob owns the collision state of a held rig. Restoring the hitbox
    -- while that rig is still held must not turn its collision back on. Once
    -- the Bring Mob snapshot is gone, the original hitbox value is safe to
    -- restore again.
    local managedByBring = false
    for _, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.parts and saved.parts[part] then
            managedByBring = true
            break
        end
    end
    if not managedByBring then
        pcall(function() part.CanCollide = runtime.state.hitboxOrigCollide end)
    end
end

local function enlargeHitbox(target)
    local anchor = anchorOf(target)
    if not anchor or not anchor.Size then return end
    if runtime.state.hitboxPart and runtime.state.hitboxPart ~= anchor then restoreHitbox() end
    local size = runtime.config.HitboxSize or 16
    if anchor.Size.X >= size then return end
    runtime.state.hitboxAt = tick()
    runtime.state.hitboxOrigSize = anchor.Size
    -- If Bring Mob has already changed this rig, the hitbox snapshot must
    -- remember the game's original collision value, not the temporary false
    -- value used by the hold.
    local originalCollide = anchor.CanCollide
    for _, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.parts and saved.parts[anchor] then
            originalCollide = saved.parts[anchor].collide
            break
        end
    end
    runtime.state.hitboxOrigCollide = originalCollide
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

-- QuestUpdate does not carry the quest index in the current game.  The
-- official quest table does, and the task table is the only stable identity
-- that can be compared with the update.  Build a canonical signature so the
-- comparison is independent of table iteration order.  A signature is also
-- used to reject an ambiguous index instead of accepting the wrong quest.
local function questTaskSignature(task)
    if type(task) ~= "table" then return nil end
    local keys = {}
    for key, value in pairs(task) do
        if type(key) ~= "string" or type(value) ~= "number" then return nil end
        keys[#keys + 1] = key
    end
    if #keys == 0 then return nil end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = tonumber(task[key])
        parts[#parts + 1] = string.format("%d:%s=%s", #key, key, tostring(value))
    end
    return table.concat(parts, "|")
end
runtime.questTaskSignature = questTaskSignature

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
                            task = quest.Task,
                            taskKey = questTaskSignature(quest.Task),
                            -- The quest module itself has no sea field. The
                            -- official records put Area1Quest (level 700) in
                            -- the Second Sea and CakeQuest2 (level 2250) in
                            -- the Third Sea, so those two boundaries are
                            -- exclusive on the lower world.
                            sea = level < 700 and 1 or (level < 2250 and 2 or 3),
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
                                task = quest.Task,
                                taskKey = questTaskSignature(quest.Task),
                                sea = need < 700 and 1 or (need < 2250 and 2 or 3),
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
                                base.sea = need < 700 and 1 or (need < 2250 and 2 or 3)
                            end
                            known = true
                        end
                    end
                end
                if known then data.guideNames[npc.InternalQuestName] = true end
            end
        end
    end
    -- A task signature is normally unique within a quest line.  Keep the
    -- ambiguity flag, though: if a future quest table has two indexes with
    -- the same task, an update without an index cannot safely identify one
    -- of them and the manual selector must refuse it.
    local taskIndexes = {}
    for _, entry in ipairs(data.quests) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = taskIndexes[key]
            if not indexes then
                indexes = {}
                taskIndexes[key] = indexes
            end
            indexes[tostring(entry.index)] = true
        end
    end
    for _, entry in ipairs(data.quests) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = taskIndexes[key] or {}
            local count = 0
            for _ in pairs(indexes) do count = count + 1 end
            entry.taskAmbiguous = count > 1
        end
    end
    local guideTaskIndexes = {}
    for _, entry in ipairs(data.guide) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = guideTaskIndexes[key]
            if not indexes then
                indexes = {}
                guideTaskIndexes[key] = indexes
            end
            indexes[tostring(entry.index)] = true
        end
    end
    for _, entry in ipairs(data.guide) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = guideTaskIndexes[key] or {}
            local count = 0
            for _ in pairs(indexes) do count = count + 1 end
            entry.taskAmbiguous = count > 1
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
    -- A manual quest is identified by the exact quest key (Name#index), or by
    -- Name when the player wants the newest available index. Automatic quest
    -- selection is untouched while ManualQuest is "Auto".
    local wanted = runtime.config.ManualQuest
    if wanted and wanted ~= "Auto" and wanted ~= "" then
        local selected, selectedIndex
        local exactName, exactIndex = wanted:match("^(.-)#(%d+)$")
        local exactNumber = tonumber(exactIndex)
        for _, q in ipairs(gameQuests or {}) do
            local exact = exactName and q.name == exactName
                and tonumber(q.index) == exactNumber
            if exact then
                selected, selectedIndex = q, q.index
                break
            elseif not exactName and q.name == wanted
                and (q.level or 0) <= (level or 0) then
                -- A bare name means the highest eligible index, not merely
                -- the quest with the highest level requirement.
                local candidateIndex = tonumber(q.index) or 0
                local currentIndex = tonumber(selectedIndex) or 0
                if not selected or candidateIndex > currentIndex then
                    selected, selectedIndex = q, q.index
                end
            end
        end
        if selected then
            return {name = selected.name, index = selected.index, mob = selected.mob,
                count = selected.count, level = selected.level, sea = selected.sea,
                pos = selected.pos, npc = selected.npc, task = selected.task,
                taskKey = selected.taskKey, taskAmbiguous = selected.taskAmbiguous}
        end
        if runtime.state.lastManualQuest ~= wanted then
            runtime.state.lastManualQuest = wanted
            dbg("Manual quest not found: " .. tostring(wanted))
        end
        -- An explicit selection is never replaced by an automatic quest. A
        -- missing or not-yet-available index must wait for the catalog or the
        -- player level instead of silently farming a different quest.
        return nil
    end
    local best = gameQuestFor(level)
    if best then
        return {name = best.name, index = best.index, mob = best.mob,
                count = best.count, level = best.level, sea = best.sea,
                pos = best.pos, npc = best.npc, task = best.task,
                taskKey = best.taskKey, taskAmbiguous = best.taskAmbiguous}
    end
    for _, q in ipairs(runtime.config.QuestList) do
        if level >= q[1] and level <= q[2] then
            return {name = q[3], index = q[4], mob = q[5], sea = 1}
        end
    end
    return nil
end

local function questKey(q) return q.name .. "#" .. q.index end

-- Find the exact quest record that a StartQuest request selected. The
-- official QuestUpdate has no index, so automatic verification needs the
-- catalog entry (and its task signature) for this exact name/index pair.
questByKey = function(name, index)
    local wantedIndex = tonumber(index)
    for _, list in ipairs({gameQuests or {}, gameGuideQuests or {}}) do
        for _, q in ipairs(list) do
            if q.name == name and tonumber(q.index) == wantedIndex then
                return {
                    name = q.name, index = q.index, mob = q.mob,
                    count = q.count, level = q.level, sea = q.sea,
                    pos = q.pos, npc = q.npc, task = q.task,
                    taskKey = q.taskKey, taskAmbiguous = q.taskAmbiguous,
                }
            end
        end
    end
    return nil
end
runtime.questByKey = questByKey

-- A manual bare name is resolved to one concrete index when it is requested.
-- Keep verifying later progress against that exact catalog record even if the
-- player's level changes and a higher index becomes eligible in the meantime.
local function manualQuestExpected()
    local requestedName = runtime.state.questAsked
    local requestedIndex = runtime.state.questIndexTry
    if requestedName and requestedIndex then
        -- A requested record that disappeared from the catalog is unknown, not
        -- permission to verify a different index of the same quest line.
        return questByKey(requestedName, requestedIndex)
    end
    return questFor(getMyLevel())
end
runtime.manualQuestExpected = manualQuestExpected

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

-- Every automatic and manual request owns one generation. Invalidating that
-- generation is the only safe way to stop an old StartQuest reply or travel
-- request from writing into a newer selection.
runtime.invalidateQuestRequest = function()
    local s = runtime.state
    s.questRequestToken = (s.questRequestToken or 0) + 1
    s.questRequestInFlight = false
    -- Keep request ids monotonic across invalidations. An old response must
    -- not be able to clear the marker of a later request.
    s.manualQuestRequestId = (s.manualQuestRequestId or 0) + 1
    s.manualQuestRequestRevision = 0
    return s.questRequestToken
end

runtime.invalidateAutomaticQuestSelection = function(reason)
    local wanted = runtime.config.ManualQuest
    if wanted and wanted ~= "Auto" and wanted ~= "" then return false end
    local s = runtime.state
    runtime.invalidateQuestRequest()
    s.currentQuest = nil
    s.questVerified = false
    s.questAsked = nil
    s.questAskedAt = 0
    s.questIndexTry = nil
    s.questTried = {}
    s.questTryKey = nil
    s.questGaveUp = false
    s.questSeenUntil = 0
    s.lastQuestTry = 0
    s.questDone = false
    s.questDoneMob = nil
    s.turnInSince = nil
    s.turnInFailed = false
    s.turnInFailedAt = 0
    s.bossQuestName = nil
    s.bossQuestUntil = 0
    if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
    dbg("Automatic quest selection changed: " .. tostring(reason or "policy"))
    return true
end

-- Reloading the quest catalog is safe to expose as a button. The operation
-- epoch is captured because the module load can yield for several seconds.
-- A refresh owns the catalog while it loads: old requests are invalidated
-- before the yield, new requests wait, and a selection made during the load
-- keeps its own state when the new catalog is installed.
runtime.refreshQuestData = function()
    local epoch = runtime.operationEpoch
    local char = LocalPlayer.Character
    local s = runtime.state
    local catalogToken = (s.questCatalogToken or 0) + 1
    s.questCatalogToken = catalogToken
    s.questCatalogLoading = true
    runtime.invalidateQuestRequest()
    local manualRevision = s.manualQuestRevision
    local requestToken = s.questRequestToken

    local data = loadGameQuests()
    if not runtime.operationValid(epoch, runtime.characterEpoch, char) then return false end
    if s.questCatalogToken ~= catalogToken then return false end
    s.questCatalogLoading = false
    if not data then return false end
    gameQuests = data.quests
    gameGuideQuests = data.guide
    gameLevelQuests = data.levels
    gameGuideNames = data.guideNames
    gameQuestIndexes = data.indexes
    runtime.questCatalog = gameQuests
    gameQuestCache, gameQuestCacheAt = nil, nil
    -- A selection or request made while the module load was yielding owns the
    -- newer state. Installing the catalog must not erase that verification.
    local requestChanged = s.manualQuestRevision ~= manualRevision
        or s.questRequestToken ~= requestToken
        or s.questRequestInFlight == true
    if not requestChanged then
        if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
        s.questVerified = false
        s.questTried = {}
        s.questTryKey = nil
        if not s.questAsked then s.questIndexTry = nil end
    end
    s.questRevision = (s.questRevision or 0) + 1
    refreshKnownMobs()
    dbg("Game quest data: " .. #gameQuests .. " quests")
    return true
end

-- Selecting a quest is an explicit replacement. The old quest is abandoned
-- once, the selected quest is sent once, and the normal verification path
-- takes over after the server has shown it.
runtime.setManualQuest = function(value)
    value = tostring(value or "Auto"):match("^%s*(.-)%s*$") or "Auto"
    if value == "" then value = "Auto" end
    local changed = runtime.config.ManualQuest ~= value
    runtime.config.ManualQuest = value
    local s = runtime.state
    if not changed and s.manualQuestKey == value then return true end
    s.manualQuestKey = value
    s.manualQuestRequestAt = 0
    s.manualQuestRevision = (s.manualQuestRevision or 0) + 1
    runtime.invalidateQuestRequest()
    s.manualQuestSentKey = nil
    s.manualQuestAttempts = 0
    s.manualQuestRequestRevision = 0
    -- The shared invalidation helper also advanced the request id, so an old
    -- reply cannot clear the marker of this new selection.
    s.lastManualQuest = nil
    s.currentQuest = nil
    s.questVerified = false
    s.questAsked = nil
    s.questAskedAt = 0
    s.questTryKey = nil
    s.questTried = {}
    s.questIndexTry = nil
    s.questGaveUp = false
    s.questSeenUntil = 0
    s.lastQuestTry = 0
    s.questDone = false
    s.questDoneMob = nil
    s.turnInSince = nil
    s.turnInFailed = false
    s.turnInFailedAt = 0
    s.bossQuestName = nil
    s.bossQuestUntil = 0
    if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
    dbg(value == "Auto" and "Manual quest selection cleared"
        or ("Manual quest selected: " .. value))
    return true
end

table.insert(runtime.tasks, task.spawn(function()
    runtime.refreshQuestData()
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

local function normalizeQuestRemoteData(data)
    if type(data) ~= "table" then return nil, "not a table" end
    local name = data.InternalQuestName
    if type(name) ~= "string" or name == "" then return nil, "missing quest name" end
    local info = data.Info
    if type(info) ~= "table" then return nil, "missing quest info" end
    local task = info.Task
    if type(task) ~= "table" or next(task) == nil then return nil, "missing quest tasks" end
    local progress = data.Progress
    if type(progress) ~= "table" then return nil, "missing quest progress" end
    local rawIndex
    if data.Index ~= nil then
        rawIndex = data.Index
    elseif data.QuestIndex ~= nil then
        rawIndex = data.QuestIndex
    end
    local index
    if rawIndex ~= nil then
        index = tonumber(rawIndex)
        if not index or index < 1 or index % 1 ~= 0 then
            return nil, "invalid quest index"
        end
    end

    local cleanProgress = {}
    for key, need in pairs(task) do
        if type(key) ~= "string" or type(need) ~= "number" then
            return nil, "invalid quest task"
        end
        local value = progress[key]
        if type(value) == "boolean" then
            value = value and need or 0
        elseif type(value) == "number" then
            if value < 0 then value = 0 end
            if value > need then value = need end
        else
            value = 0
        end
        cleanProgress[key] = value
    end
    return {
        InternalQuestName = name,
        Index = index,
        Info = {Name = info.Name, Task = task, LevelReq = info.LevelReq},
        Progress = cleanProgress,
        TaskKey = questTaskSignature(task),
    }
end

local function clearQuestRemoteState()
    questRemoteState = nil
    runtime.state.questRemoteState = nil
end
runtime.clearQuestRemoteState = clearQuestRemoteState

local function questPayloadMatchesExpected(payload, expected)
    if not payload or not expected then return false end
    if payload.InternalQuestName ~= expected.name then return false end

    local expectedIndex = tonumber(expected.index)
    local payloadIndex = tonumber(payload.Index)
    if payloadIndex ~= nil and expectedIndex ~= nil
        and payloadIndex ~= expectedIndex then
        return false
    end

    local task = payload.Info and payload.Info.Task or {}
    local expectedTaskKey = expected.taskKey
    if expectedTaskKey then
        -- If the task is unique within the quest line, it identifies the
        -- selected index even though the official update omits Index.  An
        -- ambiguous signature is not safe to guess.
        if payloadIndex == nil and expected.taskAmbiguous then return false end
        local payloadTaskKey = payload.TaskKey or questTaskSignature(task)
        if payloadTaskKey ~= expectedTaskKey then return false end
    elseif payloadIndex == nil then
        -- A fallback quest without a task signature cannot prove its index.
        return false
    elseif expectedIndex ~= nil and payloadIndex ~= expectedIndex then
        return false
    end

    local need = task[expected.mob]
    if type(need) ~= "number" then return false end
    if expected.count and tonumber(need) ~= tonumber(expected.count) then return false end
    return true
end
runtime.normalizeQuestRemoteData = normalizeQuestRemoteData
runtime.questPayloadMatchesExpected = questPayloadMatchesExpected

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
            local manualWanted = runtime.config.ManualQuest
            local manual = manualWanted and manualWanted ~= "Auto" and manualWanted ~= ""
            if data == nil then
                -- A nil event has no quest or request id. While a newer manual
                -- request is in flight it may be the old quest being cleared;
                -- do not erase the new request's state.
                if runtime.state.questRequestInFlight then
                    dbg("Ignored a quest-clear event while a request was in flight")
                    return
                end
                clearQuestRemoteState()
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
            local payload, reason = normalizeQuestRemoteData(data)
            if not payload then
                if runtime.state.questRequestInFlight then
                    dbg("Ignored an incomplete quest update while a request was in flight")
                    return
                end
                clearQuestRemoteState()
                runtime.state.questDone = false
                runtime.state.questDoneMob = nil
                runtime.state.currentQuest = nil
                runtime.state.questVerified = false
                runtime.state.questAsked = nil
                runtime.state.questIndexTry = nil
                dbg("Ignored an incomplete quest update: " .. tostring(reason))
                return
            end
            if type(update) == "table" and update.Context == "Complete" then
                dbg("Quest progress complete: " .. tostring(update.Name))
            end
            if manual then
                local expected = manualQuestExpected()
                if not questPayloadMatchesExpected(payload, expected) then
                    -- The event does not carry a request id. A mismatching
                    -- payload can therefore be a delayed update from the
                    -- previous selection. Ignore it without erasing the
                    -- newer request; the request reply decides its outcome.
                    dbg("Ignored the wrong manual quest update: "
                        .. tostring(payload.InternalQuestName))
                    return
                end
                questRemoteState = payload
                runtime.state.questRemoteState = payload
                runtime.state.currentQuest = expected.name .. "#" .. tostring(expected.index)
                runtime.state.questVerified = true
                runtime.state.questGaveUp = false
                runtime.state.questTried = {}
                -- Keep questIndexTry: it is the exact manual index that was
                -- requested and must remain the verification target when the
                -- player's level changes later.
                return
            end
            if runtime.state.questAsked then
                local requestedName = runtime.state.questAsked
                if payload.InternalQuestName ~= requestedName then
                    if runtime.state.questRequestInFlight then
                        dbg("Ignored the wrong automatic quest update while a request was in flight")
                        return
                    end
                    clearQuestRemoteState()
                    runtime.state.questDone = false
                    runtime.state.questDoneMob = nil
                    runtime.state.currentQuest = nil
                    runtime.state.questVerified = false
                    runtime.state.questAsked = nil
                    runtime.state.questIndexTry = nil
                    dbg("The game gave us " .. tostring(payload.InternalQuestName)
                        .. " instead of " .. tostring(requestedName))
                    return
                end

                -- The update does not carry an index. Verify the exact quest
                -- record that StartQuest requested by its complete task
                -- signature. A same-name update from another index, or an
                -- ambiguous signature shared by two indexes, is not accepted.
                local expected = questByKey(requestedName,
                    runtime.state.questIndexTry)
                if not expected or not questPayloadMatchesExpected(payload, expected) then
                    if runtime.state.questRequestInFlight then
                        dbg("Ignored the wrong automatic quest data while a request was in flight")
                        return
                    end
                    clearQuestRemoteState()
                    runtime.state.questDone = false
                    runtime.state.questDoneMob = nil
                    runtime.state.currentQuest = nil
                    runtime.state.questVerified = false
                    runtime.state.questAsked = nil
                    runtime.state.questIndexTry = nil
                    runtime.state.questTried = {}
                    runtime.state.questTryKey = nil
                    dbg("The game gave the wrong quest data for "
                        .. tostring(requestedName))
                    return
                end
            end
            questRemoteState = payload
            runtime.state.questRemoteState = payload
            runtime.state.questVerified = true
            runtime.state.questGaveUp = false
            runtime.state.questTried = {}
            -- Keep the requested index for the lifetime of the quest. Later
            -- progress updates also omit Index and must be checked against
            -- the same selected catalog record.
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
    local operationEpoch = runtime.operationEpoch

    local manualWanted = runtime.config.ManualQuest
    local manual = manualWanted and manualWanted ~= "Auto" and manualWanted ~= ""
    if manual then runtime.setManualQuest(manualWanted) end
    local manualRevision = runtime.state.manualQuestRevision
    local manualRequestId
    if info and info.confirmed then
        -- Automatic quests keep the old fast path. A manual quest is the
        -- exception: when the live panel still shows a different quest, the
        -- old one has to be abandoned before the selected one is accepted.
        local exactName = manualWanted and manualWanted:find("#", 1, true)
        local currentMatches = false
        if manualWanted and runtime.state.currentQuest then
            if exactName then
                currentMatches = runtime.state.currentQuest == manualWanted
            else
                currentMatches = runtime.state.currentQuest:sub(1, #manualWanted + 1)
                    == manualWanted .. "#"
            end
        end
        if not manual or currentMatches then
            runtime.state.questSeenUntil = now + 1
            return
        end
    end
    if now < (runtime.state.questSeenUntil or 0) then return end
    if now - runtime.state.lastQuestTry < 2 then return end
    if runtime.state.questDone then return end
    if runtime.state.questCatalogLoading then return end
    if runtime.state.questRequestInFlight then return end

    local q = questFor(getMyLevel())
    if not q then
        dbg("No quest bracket for this level")
        return
    end

    -- Reserve one request generation before any Realm lookup can yield. A
    -- selection change during that lookup must invalidate this request too;
    -- otherwise an old automatic or manual selection could still start a
    -- quest after the user chose a different one.
    local requestToken = (runtime.state.questRequestToken or 0) + 1
    local questRevision = runtime.state.questRevision
    runtime.state.questRequestToken = requestToken
    runtime.state.questRequestInFlight = true
    local function expireOwnRequest()
        if runtime.state.questRequestToken == requestToken then
            runtime.state.questRequestInFlight = false
        end
    end
    local function requestIsCurrent()
        if runtime.state.questRequestToken ~= requestToken then return false end
        if runtime.state.questRevision ~= questRevision then
            expireOwnRequest()
            return false
        end
        if manual and runtime.state.manualQuestRevision ~= manualRevision then
            expireOwnRequest()
            return false
        end
        if not manual then
            -- Automatic selection also depends on level, boss policy and the
            -- quest catalog. If it now resolves to another exact quest, the
            -- old request must not start it.
            local selected = questFor(getMyLevel())
            if not selected or questKey(selected) ~= questKey(q) then
                expireOwnRequest()
                return false
            end
        end
        if not runtime.operationValid(operationEpoch, epoch, char) then
            expireOwnRequest()
            return false
        end
        return true
    end
    local function clearQuestRequest()
        expireOwnRequest()
    end

    -- A selected Second or Third Sea quest is routed to its world before it
    -- is accepted. The current sea must be known first: accepting a quest in
    -- the wrong world is worse than waiting for one fresh Realm result.
    if q.sea then
        -- A cached sea can belong to the previous world. A sea quest always
        -- asks Realm for a fresh result before it routes or accepts.
        local currentSea = nil
        if runtime.detectCurrentSea then
            currentSea = runtime.detectCurrentSea()
        end
        if not requestIsCurrent() then
            clearQuestRequest()
            return
        end
        if manual and runtime.state.manualQuestRevision ~= manualRevision then
            clearQuestRequest()
            return
        end
        if not currentSea then
            clearQuestRequest()
            dbg("The current sea is not known; the quest was not accepted")
            return
        end
        if currentSea ~= q.sea then
            -- The guard belongs to the selection that created this request,
            -- not to the revision that happens to be current after the yield.
            local travelRevision = manual and manualRevision or nil
            local travelGuard = manual and function()
                return runtime.state.manualQuestRevision == travelRevision
                    and runtime.state.questRequestToken == requestToken
                    and runtime.state.questRevision == questRevision
            end or nil
            if runtime.travelToWorld then
                runtime.state.status = "Travelling to Sea " .. tostring(q.sea)
                runtime.travelToWorld(q.sea, travelGuard)
            end
            -- The world request can yield for several seconds. A manual
            -- selection changed during that wait must not be cleared by this
            -- stale route.
            if not requestIsCurrent() then
                clearQuestRequest()
                return
            end
            if manual and runtime.state.manualQuestRevision ~= travelRevision then
                clearQuestRequest()
                return
            end
            runtime.state.currentQuest = nil
            runtime.state.questVerified = false
            runtime.state.questAsked = nil
            runtime.state.questIndexTry = nil
            runtime.state.questTried = {}
            runtime.state.questTryKey = nil
            clearQuestRequest()
            return
        end
    end

    local key = questKey(q) .. "@" .. tostring(getMyLevel())
    if runtime.state.questTryKey ~= key then
        runtime.state.questTryKey = key
        runtime.state.questTried = {}
        -- Keep the index of an active quest when a level change changes the
        -- automatic bracket. The next progress update still omits Index and
        -- must be checked against the quest that is actually running.
        if not runtime.state.questAsked then
            runtime.state.questIndexTry = nil
        end
        runtime.state.questGaveUp = false
    end

    if runtime.state.questAsked and not runtime.state.questVerified then
        if now - runtime.state.questAskedAt < 6 then
            clearQuestRequest()
            return
        end
        if manual then
            -- A manual selection is exact. Never walk it to another index and
            -- never turn a slow server update into a request loop.
            if (runtime.state.manualQuestAttempts or 0) >= 3 then
                runtime.state.questGaveUp = true
                runtime.state.currentQuest = nil
                dbg("The manual quest was not confirmed after three requests")
                clearQuestRequest()
                return
            end
            runtime.state.questAsked = nil
            runtime.state.questVerified = false
            runtime.state.questAskedAt = 0
            runtime.state.currentQuest = nil
            clearQuestRequest()
            return
        end
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
            clearQuestRequest()
            return
        end
    end
    if runtime.state.questGaveUp then
        clearQuestRequest()
        return
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        clearQuestRequest()
        dbg("CommF_ remote missing")
        return
    end

    local index = runtime.state.questIndexTry or q.index

    if manual then
        if (runtime.state.manualQuestAttempts or 0) >= 3 then
            runtime.state.questGaveUp = true
            runtime.state.currentQuest = nil
            dbg("The manual quest was refused three times; no more requests were sent")
            clearQuestRequest()
            return
        end
        local requestKey = questKey(q)
        if runtime.state.manualQuestSentKey == requestKey
            and now - (runtime.state.manualQuestRequestAt or 0) < 12 then
            clearQuestRequest()
            return
        end
        manualRequestId = (runtime.state.manualQuestRequestId or 0) + 1
        runtime.state.manualQuestRequestId = manualRequestId
        runtime.state.manualQuestRequestRevision = manualRevision
    end

    -- Every automatic and manual StartQuest request owns one generation. A
    -- selection change or a newer request invalidates the older coroutine
    -- before it can write quest state.
    local function clearManualRequest()
        if manualRequestId and runtime.state.manualQuestRequestId == manualRequestId then
            runtime.state.manualQuestRequestId = 0
            runtime.state.manualQuestRequestRevision = 0
        end
        clearQuestRequest()
    end

    -- The request id is part of the ownership check as well as the selection
    -- revision. Two requests for the same quest can otherwise overlap: the
    -- older coroutine must not continue to AbandonQuest or StartQuest after a
    -- newer request has taken ownership.
    local function manualRequestIsCurrent()
        return requestIsCurrent() and (not manual or (
            runtime.state.manualQuestRevision == manualRevision
            and runtime.state.manualQuestRequestRevision == manualRevision
            and runtime.state.manualQuestRequestId == manualRequestId))
    end

    local spawnOk = pcall(function() commF:InvokeServer("SetLastSpawnPoint", "Town") end)
    if not spawnOk or not requestIsCurrent() then
        clearManualRequest()
        return
    end
    if manual and not manualRequestIsCurrent() then
        clearManualRequest()
        return
    end

    if manual or questRemoteState then
        local abandonOk = pcall(function() commF:InvokeServer("AbandonQuest") end)
        if not abandonOk or not requestIsCurrent() then
            clearManualRequest()
            return
        end
    end
    if manual and not manualRequestIsCurrent() then
        clearManualRequest()
        return
    end
    if manual then
        runtime.state.manualQuestSentKey = questKey(q)
        runtime.state.manualQuestRequestAt = now
        runtime.state.manualQuestAttempts = (runtime.state.manualQuestAttempts or 0) + 1
    end
    local ok, reply = pcall(function()
        return commF:InvokeServer("StartQuest", q.name, index)
    end)
    if not requestIsCurrent() then
        clearManualRequest()
        return
    end
    if manual and not manualRequestIsCurrent() then
        clearManualRequest()
        dbg("A stale manual quest reply was ignored")
        return
    end
    clearManualRequest()
    if not ok then
        dbg("Quest FAIL: " .. tostring(reply))
        return
    end
    -- The official reply is 0 for accepted, 1 for an error, 2 for a quest
    -- already completed, and a level requirement otherwise. Treating every
    -- non-error reply as success was how the bot kept farming a quest that
    -- the server had actually refused.
    if reply ~= 0 then
        local reason = reply == 1 and "the game refused it"
            or (reply == 2 and "it was already completed"
            or ("level requirement " .. tostring(reply)))
        dbg("Quest " .. q.name .. " was not accepted: " .. reason)
        runtime.state.questAsked = nil
        runtime.state.questVerified = false
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
    runtime.state.lastPrompt, runtime.state.promptAt = prompt, now
    if fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function()
            prompt:InputHoldBegin()
            runtime.state.promptHoldSeq = (runtime.state.promptHoldSeq or 0) + 1
            local holdToken = runtime.state.promptHoldSeq
            runtime.state.promptHolds[prompt] = holdToken
            table.insert(runtime.tasks, task.spawn(function()
                task.wait(prompt.HoldDuration or 1)
                -- Only the task that owns this exact hold may end it. A reset
                -- can remove the marker and a later run can start a new hold
                -- on the same prompt; the old task must not end that new hold.
                if runtime.state.promptHolds[prompt] == holdToken then
                    runtime.state.promptHolds[prompt] = nil
                    pcall(function() prompt:InputHoldEnd() end)
                end
            end))
        end)
    end
    return true
end

-- ================= CHESTS =================
-- Ordinary chests are the server instances tagged by the game itself. Their
-- live names are Chest1, Chest2 and Chest3, so a name table misses them. The
-- official tag is the discovery proof; collection still requires the current
-- character to physically touch the exact tagged server part.
runtime.chestTag = "_ChestTagged"

runtime.chestStateOf = function(instance)
    if not instance then return nil end
    if instance:GetAttribute("Opened") == true then return "Opened" end
    if instance:GetAttribute("Collected") == true then return "Collected" end
    if instance:GetAttribute("IsDisabled") == true then return "IsDisabled" end
    return nil
end

runtime.chestServerState = function(chest)
    if not chest then return nil end
    local state = runtime.chestStateOf(chest)
    if state then return state end
    local part = runtime.chestPart(chest)
    if part and part ~= chest then
        state = runtime.chestStateOf(part)
        if state then return state end
    end
    part = runtime.chestIdentityPart(chest)
    if part and part ~= chest then
        state = runtime.chestStateOf(part)
        if state then return state end
    end
    for _, descendant in ipairs(chest:GetDescendants()) do
        if descendant:IsA("BasePart") then
            state = runtime.chestStateOf(descendant)
            if state then return state end
        end
    end
    return nil
end

runtime.chestTargets = function()
    local ok, collection = pcall(function()
        return game:GetService("CollectionService")
    end)
    if not ok or not collection then return {} end
    local taggedOk, tagged = pcall(function()
        return collection:GetTagged(runtime.chestTag)
    end)
    if not taggedOk or type(tagged) ~= "table" then return {} end
    return tagged
end

runtime.chestPart = function(chest, requireTouchable)
    if requireTouchable == nil then requireTouchable = true end
    if not chest then return nil end
    if chest:IsA("BasePart") then
        if requireTouchable and chest.CanTouch == false then return nil end
        return chest
    end
    local primary
    if chest:IsA("Model") then
        pcall(function() primary = chest.PrimaryPart end)
    end
    if not primary then primary = chest:FindFirstChild("PrimaryPart") end
    if primary and primary:IsA("BasePart")
        and (not requireTouchable or primary.CanTouch ~= false) then
        return primary
    end
    for _, part in ipairs(chest:GetDescendants()) do
        if part:IsA("BasePart")
            and (not requireTouchable or part.CanTouch ~= false) then return part end
    end
    return nil
end

runtime.chestIdentityPart = function(chest, fallback)
    if not chest then return nil end
    if chest:IsA("BasePart") then return chest end
    local primary
    if chest:IsA("Model") then
        pcall(function() primary = chest.PrimaryPart end)
    end
    if not primary then primary = chest:FindFirstChild("PrimaryPart") end
    if primary and primary:IsA("BasePart") then return primary end
    if fallback and fallback.Parent then return fallback end
    for _, part in ipairs(chest:GetDescendants()) do
        if part:IsA("BasePart") then return part end
    end
    return nil
end

runtime.chestHasTag = function(chest)
    if not chest then return false end
    local ok, collection = pcall(function()
        return game:GetService("CollectionService")
    end)
    if not ok or not collection then return false end
    local hasOk, hasTag = pcall(function()
        return collection:HasTag(chest, runtime.chestTag)
    end)
    if hasOk then return hasTag == true end
    local taggedOk, tagged = pcall(function()
        return collection:GetTagged(runtime.chestTag)
    end)
    if not taggedOk or type(tagged) ~= "table" then return false end
    for _, taggedChest in ipairs(tagged) do
        if taggedChest == chest then return true end
    end
    return false
end

runtime.chestFruitCount = function()
    local count = 0
    local containers = {}
    local char = LocalPlayer.Character
    if char then table.insert(containers, char) end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then table.insert(containers, backpack) end
    for _, container in ipairs(containers) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and isFruit(tool) then count += 1 end
        end
    end
    return count
end

runtime.chestFragmentCount = function()
    local data = LocalPlayer:FindFirstChild("Data")
    local fragments = data and data:FindFirstChild("Fragments")
    local value = readNumber(fragments)
    if type(value) == "number" then return value end
    value = tonumber(LocalPlayer:GetAttribute("Fragments"))
    if type(value) == "number" then return value end
    return nil
end

runtime.clearChestConnections = function(operationToken)
    local s = runtime.state
    if operationToken ~= nil and s.chestToken ~= operationToken then return false end
    for _, connection in ipairs(s.chestConnections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    s.chestConnections = {}
    return true
end

runtime.watchChestTouch = function(target, part, root, operationToken)
    runtime.clearChestConnections(operationToken)
    local s = runtime.state
    local function recordTouch(hit)
        if s.chestToken ~= operationToken or s.chestTarget ~= target
            or s.chestTargetPart ~= part then return end
        local char = LocalPlayer.Character
        if not char or root.Parent ~= char then return end
        local belongs = hit == root
        if not belongs then
            pcall(function() belongs = hit:IsDescendantOf(char) end)
        end
        if not belongs then return end
        -- Keep the first valid contact. A later repeated Touched event must not
        -- move the server transition behind the touch and hide valid proof.
        if s.chestTouchAt == 0 then
            local at = tick()
            s.chestSequence = (s.chestSequence or 0) + 1
            s.chestTouchSequence = s.chestSequence
            s.chestTouchAt = at
            s.chestTouchPart = part
            s.chestTouchRoot = root
            -- Reward proof is measured from the exact touch instant. A reward
            -- increase seen before contact cannot later be inherited by this
            -- operation after an unrelated touch.
            s.chestTouchRewardBaselineAt = at
            s.chestTouchBeliBefore = myBeli and myBeli()
            s.chestTouchFruitBefore = runtime.chestFruitCount()
            s.chestTouchFragmentsBefore = runtime.chestFragmentCount()
        end
    end

    local connections = {}
    local partTouch = part.Touched:Connect(function(hit) recordTouch(hit) end)
    local rootTouch = root.Touched:Connect(function(hit)
        if hit == part then recordTouch(hit) end
    end)
    table.insert(connections, partTouch)
    table.insert(connections, rootTouch)

    local function watchServerState(instance)
        for _, attribute in ipairs({"IsDisabled", "Opened", "Collected"}) do
            local serverChange = instance:GetAttributeChangedSignal(attribute):Connect(function()
                if s.chestToken ~= operationToken or s.chestTarget ~= target then return end
                if instance:GetAttribute(attribute) ~= true then return end
                local at = tick()
                s.chestSequence = (s.chestSequence or 0) + 1
                local sequence = s.chestSequence
                s.chestServerAt = at
                s.chestServerState = attribute
                if attribute == "Opened" then
                    s.chestOpenedAt = at
                    s.chestOpenedSequence = sequence
                elseif attribute == "Collected" then
                    s.chestCollectedAt = at
                    s.chestCollectedSequence = sequence
                else
                    s.chestDisabledAt = at
                    s.chestDisabledSequence = sequence
                end
            end)
            table.insert(connections, serverChange)
        end
    end
    local watchedServerState = {}
    local function watchServerStateOnce(instance)
        if not instance or watchedServerState[instance] then return end
        watchedServerState[instance] = true
        watchServerState(instance)
    end
    watchServerStateOnce(target)
    watchServerStateOnce(part)
    -- A Model may select a touchable fallback while its identity remains the
    -- PrimaryPart. Watch that exact identity part too, so a post-touch server
    -- transition on it receives the same strict sequence proof.
    watchServerStateOnce(runtime.chestIdentityPart(target, part))
    s.chestConnections = connections
end

runtime.scanChestTargets = function(root, now)
    local best, bestD = nil, (tonumber(runtime.config.ChestRange) or 5000)
    for _, d in ipairs(runtime.chestTargets()) do
        if (d:IsA("Model") or d:IsA("BasePart")) and d:IsDescendantOf(Workspace) then
            local part = runtime.chestPart(d)
            local disabled = runtime.chestServerState(d) ~= nil
            local seenAt = runtime.state.chestSeen[d]
            if part and part.Parent and not disabled
                and (not seenAt or now - seenAt >= 60) then
                local distance = (root.Position - part.Position).Magnitude
                if distance < bestD then best, bestD = d, distance end
            end
        end
    end
    return best
end

runtime.cancelChest = function()
    local s = runtime.state
    local hadOwner = s.chestMovementToken ~= nil
        or s.chestTarget ~= nil
        or s.chestTargetPart ~= nil
        or #(s.chestConnections or {}) > 0
        or s.movementOwner == "chest"
    if not hadOwner then return false end
    s.chestToken = (s.chestToken or 0) + 1
    -- Use the exact token that owns the chest lock. Releasing with nil would
    -- also release a newer chest owner that happened to replace this state.
    local movementToken = s.chestMovementToken
    if movementToken == nil and s.movementOwner == "chest" then
        movementToken = s.movementOwnerToken
    end
    local ownsMovement = s.movementOwner == "chest"
        and s.movementOwnerToken == movementToken
    if runtime.clearChestConnections then runtime.clearChestConnections() end
    s.chestMovementToken = nil
    s.chestTarget = nil
    s.chestTargetPart = nil
    s.chestTargetIdentityPart = nil
    s.chestStartedAt = 0
    s.chestSelectedAt = 0
    s.chestTravelDeadline = 0
    s.chestLastTry = 0
    s.chestTouchAt = 0
    s.chestTouchPart = nil
    s.chestTouchRoot = nil
    s.chestSequence = 0
    s.chestTouchSequence = 0
    s.chestTouchRewardBaselineAt = 0
    s.chestTouchBeliBefore = nil
    s.chestTouchFruitBefore = nil
    s.chestTouchFragmentsBefore = nil
    s.chestServerAt = 0
    s.chestServerState = nil
    s.chestOpenedAt = 0
    s.chestCollectedAt = 0
    s.chestDisabledAt = 0
    s.chestOpenedSequence = 0
    s.chestCollectedSequence = 0
    s.chestDisabledSequence = 0
    s.chestBeliBefore = nil
    s.chestFruitBefore = nil
    s.chestFragmentsBefore = nil
    s.chestRewardBaselineAt = 0
    if ownsMovement and runtime.stopTween then runtime.stopTween() end
    runtime.releaseMovement("chest", movementToken)
    return true
end

runtime.handleChest = function(root)
    if not runtime.config.AutoChest then
        runtime.cancelChest()
        return false
    end
    if not root then return false end
    local now = tick()
    local s = runtime.state
    local target = s.chestTarget
    local operationToken = s.chestToken
    local movementToken = s.chestMovementToken

    if not target then
        if s.chestMovementToken or s.chestTargetPart
            or #(s.chestConnections or {}) > 0 then
            runtime.cancelChest()
        end
        if now - (s.chestLastScanAt or 0) >= 1.5 then
            s.chestLastScanAt = now
            target = runtime.scanChestTargets(root, now)
        end
        if not target then return false end

        -- Do not commit a chest target while another feature owns movement.
        -- The scan may find a chest, but the ordinary farm keeps its own
        -- operation until the exclusive chest lock can be acquired cleanly.
        local acquired
        acquired, movementToken = runtime.acquireMovement("chest")
        if not acquired then return false end
        local selectedPart = runtime.chestPart(target)
        if not selectedPart then
            s.chestSeen[target] = now
            runtime.releaseMovement("chest", movementToken)
            return true
        end
        -- The chest now owns movement. Cancel a farm tween left over from the
        -- preceding frame so the proxy cannot keep moving toward a mob while
        -- the chest route is being committed.
        if runtime.stopTween then runtime.stopTween() end
        s.chestMovementToken = movementToken
        s.chestToken = (s.chestToken or 0) + 1
        operationToken = s.chestToken
        s.chestTarget = target
        s.chestTargetPart = selectedPart
        s.chestTargetIdentityPart = runtime.chestIdentityPart(target, selectedPart)
        s.chestSelectedAt = now
        s.chestStartedAt = 0
        s.chestTravelDeadline = 0
        s.chestLastTry = 0
        s.chestTouchAt = 0
        s.chestTouchPart = nil
        s.chestTouchRoot = nil
        s.chestSequence = 0
        s.chestTouchSequence = 0
        s.chestTouchRewardBaselineAt = 0
        s.chestTouchBeliBefore = nil
        s.chestTouchFruitBefore = nil
        s.chestTouchFragmentsBefore = nil
        s.chestServerAt = 0
        s.chestServerState = nil
        s.chestOpenedAt = 0
        s.chestCollectedAt = 0
        s.chestDisabledAt = 0
        s.chestOpenedSequence = 0
        s.chestCollectedSequence = 0
        s.chestDisabledSequence = 0
        s.chestBeliBefore = nil
        s.chestFruitBefore = nil
        s.chestFragmentsBefore = nil
        s.chestRewardBaselineAt = 0
        -- Install the exact-part and server-state watchers before the first
        -- approach frame so a fast contact cannot outrun the proof.
        runtime.watchChestTouch(target, selectedPart, root, operationToken)
        local travelDistance = (root.Position - selectedPart.Position).Magnitude
        local travelSeconds = travelDistance / math.max(1, tonumber(runtime.config.MoveSpeed) or 200)
        s.chestTravelDeadline = now + math.max(
            tonumber(runtime.config.ChestTimeout) or 30, travelSeconds * 2 + 10)
    elseif not movementToken or s.movementOwner ~= "chest"
        or s.movementOwnerToken ~= movementToken then
        -- A target is valid only with its exact movement owner. If another
        -- operation replaced the owner, cancel the stale chest as a unit.
        runtime.cancelChest()
        return false
    end

    if s.chestToken ~= operationToken or s.chestMovementToken ~= movementToken
        or s.movementOwner ~= "chest" or s.movementOwnerToken ~= movementToken then
        return false
    end

    local function finishChest()
        local ownsMovement = s.movementOwner == "chest"
            and s.movementOwnerToken == movementToken
        if s.chestToken == operationToken then
            s.chestTarget = nil
            s.chestTargetPart = nil
            s.chestTargetIdentityPart = nil
            s.chestStartedAt = 0
            s.chestSelectedAt = 0
            s.chestTravelDeadline = 0
            s.chestLastTry = 0
            s.chestTouchAt = 0
            s.chestTouchPart = nil
            s.chestTouchRoot = nil
            s.chestSequence = 0
            s.chestTouchSequence = 0
            s.chestTouchRewardBaselineAt = 0
            s.chestTouchBeliBefore = nil
            s.chestTouchFruitBefore = nil
            s.chestTouchFragmentsBefore = nil
            s.chestServerAt = 0
            s.chestServerState = nil
            s.chestOpenedAt = 0
            s.chestCollectedAt = 0
            s.chestDisabledAt = 0
            s.chestOpenedSequence = 0
            s.chestCollectedSequence = 0
            s.chestDisabledSequence = 0
            s.chestBeliBefore = nil
            s.chestFruitBefore = nil
            s.chestFragmentsBefore = nil
            s.chestRewardBaselineAt = 0
            s.chestMovementToken = nil
            if runtime.clearChestConnections then
                runtime.clearChestConnections(operationToken)
            end
        end
        if ownsMovement and runtime.stopTween then runtime.stopTween() end
        runtime.releaseMovement("chest", movementToken)
    end

    local targetPart = s.chestTargetPart
    local exactTouch = targetPart ~= nil and s.chestTouchAt > 0
        and s.chestTouchPart == targetPart and s.chestTouchRoot == root
    local serverState = runtime.chestServerState(target)
    if serverState then s.chestServerState = serverState end
    local identityPart = s.chestTargetIdentityPart
    local currentIdentityPart = runtime.chestIdentityPart(target, targetPart)
    local exactPartStillOwned = false
    pcall(function()
        exactPartStillOwned = targetPart ~= nil and targetPart.Parent ~= nil
            and (targetPart == target or targetPart:IsDescendantOf(target))
    end)
    local stillInWorkspace = false
    pcall(function() stillInWorkspace = target:IsDescendantOf(Workspace) end)
    local stillTagged = runtime.chestHasTag(target)
    local partChanged = stillInWorkspace and (not targetPart or not identityPart
        or not currentIdentityPart or currentIdentityPart ~= identityPart
        or not exactPartStillOwned)
    local tagChanged = stillInWorkspace and not stillTagged
    if partChanged or tagChanged then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest changed"
        dbg("Chest changed before collection: " .. target.Name)
        return true
    end
    local beli = myBeli and myBeli()
    local fruitCount = runtime.chestFruitCount()
    local fragments = runtime.chestFragmentCount()
    -- The completion baseline is captured inside the exact Touched callback.
    -- A reward increase seen during the approach but before contact is not
    -- inherited by a later, unrelated touch.
    local beliPaid = exactTouch and type(s.chestTouchBeliBefore) == "number"
        and type(beli) == "number" and beli > s.chestTouchBeliBefore
    local fruitPaid = exactTouch and type(s.chestTouchFruitBefore) == "number"
        and fruitCount > s.chestTouchFruitBefore
    local fragmentsPaid = exactTouch and type(s.chestTouchFragmentsBefore) == "number"
        and type(fragments) == "number" and fragments > s.chestTouchFragmentsBefore
    local rewardObserved = beliPaid or fruitPaid or fragmentsPaid
    -- Opened, Collected, and IsDisabled are independent server transitions.
    -- Sequence numbers prove callback order even when two callbacks receive
    -- the same tick() value. Only a transition after the exact touch counts.
    local openedAfterTouch = exactTouch
        and s.chestOpenedSequence > s.chestTouchSequence
    local collectedAfterTouch = exactTouch
        and s.chestCollectedSequence > s.chestTouchSequence
    local disabledAfterTouch = exactTouch
        and s.chestDisabledSequence > s.chestTouchSequence
    local explicitCollected = openedAfterTouch or collectedAfterTouch
    local serverAfterTouch = openedAfterTouch or collectedAfterTouch
        or disabledAfterTouch
    if exactTouch and (rewardObserved or explicitCollected or disabledAfterTouch) then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = (rewardObserved or explicitCollected)
            and "Chest collected" or "Chest confirmed"
        dbg("Collected " .. target.Name)
        return true
    end

    if not target.Parent or not stillInWorkspace then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest became unavailable"
        dbg("Chest became unavailable: " .. target.Name)
        return true
    end
    if s.chestServerAt > 0 and (not exactTouch or not serverAfterTouch)
        and now - s.chestServerAt >= 0.5 then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest became unavailable"
        dbg("Chest became unavailable: " .. target.Name)
        return true
    end

    if #(s.chestConnections or {}) == 0 then
        runtime.watchChestTouch(target, targetPart, root, operationToken)
    end

    -- Once contact has begun, the confirmation deadline owns the operation
    -- even if the character drifts away again. The travel deadline is no
    -- longer allowed to terminate this later phase.
    if s.chestStartedAt > 0
        and now - s.chestStartedAt > (tonumber(runtime.config.ChestTimeout) or 30) then
        -- A failed chest is skipped for one minute, not forever. The server can
        -- disable it later or the player can come back after its reset.
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest was not confirmed"
        dbg("Could not collect " .. target.Name)
        return true
    end

    local distance = (root.Position - targetPart.Position).Magnitude
    if distance > 8 then
        if s.chestStartedAt == 0 and s.chestTravelDeadline > 0
            and now > s.chestTravelDeadline then
            s.chestSeen[target] = now
            finishChest()
            runtime.state.status = "Chest route timed out"
            dbg("Chest route timed out: " .. target.Name)
            return true
        end
        runtime.state.status = "Collecting chest"
        runtime.tweenTo(CFrame.new(targetPart.Position + Vector3.new(0, 2, 0)))
        return true
    end

    -- The timeout starts at contact, not when a distant chest was selected.
    -- A long smooth trip must not consume the whole server-confirmation window.
    if s.chestStartedAt == 0 then
        s.chestStartedAt = now
        -- Travel and contact are separate phases. Once contact begins, the
        -- route deadline must not terminate a still-live confirmation.
        s.chestTravelDeadline = 0
    end
    if s.chestRewardBaselineAt == 0 then
        s.chestRewardBaselineAt = now
        s.chestBeliBefore = beli
        s.chestFruitBefore = fruitCount
        s.chestFragmentsBefore = fragments
    end
    if now - (s.chestLastTry or 0) >= 0.45 then
        s.chestLastTry = now
        -- Retry the final approach only when the proxy did not reach the exact
        -- server part. No forced touch is sent: the Touched event is proof.
        if distance > 3.25 then
            runtime.tweenTo(CFrame.new(targetPart.Position + Vector3.new(0, 2, 0)))
        end
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

local function pickBest(candidates, mobName, origin, exactOnly)
    local exact, exactD = nil, math.huge
    local loose, looseD = nil, math.huge
    local wanted = mobName and mobKey(tostring(mobName)) or nil
    if wanted == "" then wanted = nil end
    for _, obj in ipairs(candidates) do
        local anchor = anchorOf(obj)
        if anchor then
            local d = (origin.Position - anchor.Position).Magnitude
            local display = nil
            pcall(function() display = obj:GetAttribute("DisplayName") end)
            local key = mobKey(display or obj.Name)
            if not wanted then
                if d < exactD then exact, exactD = obj, d end
            elseif sameName(key, wanted) then
                if d < exactD then exact, exactD = obj, d end
            elseif not exactOnly and startsWithCI(key, wanted)
                and not isCompoundMob(key, wanted) then
                if d < looseD then loose, looseD = obj, d end
            end
        end
    end
    return exact or loose
end

-- "Nearest" is a mode, not the literal name of a mob. Keep that distinction in
-- one helper so the target resolver can never search for a mob named Nearest.
runtime.resolveSelectedMob = function(value)
    value = tostring(value or "")
    if value == "" or value == "Auto" then
        return false, nil, false
    end
    if value:lower() == "nearest" then
        return true, nil, true
    end
    return true, value, false
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
    ["greybeard"] = true,
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
    ["diamond"] = 750, ["greybeard"] = 750, ["jeremy"] = 850, ["orbitus"] = 925, ["smoke admiral"] = 1150,
    ["awakened ice admiral"] = 1400, ["tide keeper"] = 1475, ["stone"] = 1550,
    ["hydra leader"] = 1675, ["kilo admiral"] = 1750, ["captain elephant"] = 1875,
    ["beautiful pirate"] = 1950, ["cake queen"] = 2175,
}

-- The key of the boss tables for a mob, from its name or its display name.
-- nil when the mob is no boss at all.
local function bossKeyOf(mob)
    if not mob then return nil end
    local function known(key)
        if not key then return nil end
        if BOSS_NAMES[key] then return key end
        if key:sub(1, 4) == "the " and BOSS_NAMES[key:sub(5)] then return key:sub(5) end
        if BOSS_NAMES["the " .. key] then return "the " .. key end
        return nil
    end
    local key = known(mobKey(mob.Name):lower())
    if key then return key end
    local display = nil
    pcall(function() display = mob:GetAttribute("DisplayName") end)
    if display then return known(mobKey(display):lower()) end
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

local function pickBoss(root, range, mobName, ignoreWindow)
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
                    local bossLevel = bossLevelOf and bossLevelOf(key) or BOSS_LEVELS[key]

                    -- Bosses are only taken when their level is close to the
                    -- player, so a level 700 player is not thrown at a level
                    -- 600 boss. The quest boss itself is always allowed if its
                    -- level table is missing.
                    local levelOk = ignoreWindow or bossLevel == nil
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

local function getTarget(mobName, exactOnly)
    local root = getRoot()
    if not root then return nil end
    return pickBest(collectEnemies(tick()), mobName, root, exactOnly)
end

local function findSpawn(mobName, exactOnly)
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    local root = getRoot()
    if not spawns or not root then return nil end

    local candidates = {}
    for _, p in ipairs(spawns:GetChildren()) do
        if p:IsA("BasePart") or p:IsA("Model") then table.insert(candidates, p) end
    end
    return pickBest(candidates, mobName, root, exactOnly)
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

-- Bring Mob has its own water rules. The exact Cup Water is deliberately not
-- part of them: it is a tiny, invisible trigger part and not an ocean. Every
-- other water part below the map is treated as a hazard for a carried rig.
runtime.bringWaterPart = function(part)
    if not part or type(part.IsA) ~= "function" or not part:IsA("BasePart") then return false end
    local fullName = ""
    pcall(function() fullName = part:GetFullName() end)
    if fullName == "Workspace.Map.Ice.ParticleDrop.Water" then return false end
    local map = nil
    pcall(function() map = part:FindFirstAncestor("Map") end)
    if not map then return false end
    local name = ""
    pcall(function() name = part.Name end)
    return name:lower():find("water", 1, true) ~= nil
end

-- Check the ground below one point. Enemy rigs and the local character are
-- excluded so their bodies cannot hide the terrain. The first ray starts at
-- the point itself: starting it 80 studs higher let overhead map geometry
-- hide the real water below and made a wet Prison ledge look dry. A raised
-- ray is only the fallback for a point that starts inside solid geometry.
-- The check fails closed if the real Workspace raycast itself errors: a Bring
-- carry is stopped instead of guessing that an unknown path is dry.
runtime.bringPointOverWater = function(point, exclude)
    if not point then return true end
    local excluded = {}
    local character = LocalPlayer and LocalPlayer.Character
    if character then excluded[#excluded + 1] = character end
    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then excluded[#excluded + 1] = enemies end
    if exclude then excluded[#excluded + 1] = exclude end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excluded
    local ok, hit = pcall(function()
        return Workspace:Raycast(point, Vector3.new(0, -500, 0), params)
    end)
    if not ok then return true end
    if hit then return runtime.bringWaterPart(hit.Instance) == true end
    local raisedOk, raisedHit = pcall(function()
        return Workspace:Raycast(point + Vector3.new(0, 80, 0),
            Vector3.new(0, -500, 0), params)
    end)
    if not raisedOk then return true end
    return raisedHit ~= nil and runtime.bringWaterPart(raisedHit.Instance) == true
end

-- A straight carry path is safe only when the ground below every sample is
-- dry. This catches a same-height island or coast across a bay even though
-- the player's and the mob's vertical difference is small.
runtime.bringPathOverWater = function(from, to)
    if not from or not to then return true end
    local dx = to.X - from.X
    local dz = to.Z - from.Z
    local distance = math.sqrt(dx * dx + dz * dz)
    local steps = math.max(1, math.ceil(distance / 6))
    if steps > 48 then steps = 48 end
    for index = 0, steps do
        local amount = index / steps
        local point = Vector3.new(
            from.X + dx * amount,
            from.Y + (to.Y - from.Y) * amount,
            from.Z + dz * amount)
        if runtime.bringPointOverWater(point) then return true end
    end
    return false
end

-- A saved mover is usable only when it is still the exact runtime-owned
-- BodyVelocity on the current root. A reparented or replaced mover is never
-- driven by this run.
runtime.validBringMover = function(mover, part)
    if not mover or not part then return false end
    if not mover:IsA("BodyVelocity") or mover.Parent ~= part then return false end
    local owned = false
    pcall(function() owned = mover:GetAttribute("FarmOwned") == true end)
    return owned
end

runtime.bringSnap = function(mob, part, goal)
    if not runtime.config.BringMobSnap or runtime.state.bringSnapped[mob] then
        return false
    end
    if not runtime.bringLocallyOwned(part) then return false end
    -- Never teleport a rig over a detected water gap. The normal mover may
    -- still close a dry path, but a straight CFrame snap is only allowed when
    -- the ground under that exact path is dry.
    if runtime.bringPathOverWater(part.Position, goal) then return false end

    local gap = (part.Position - goal).Magnitude
    if gap < (runtime.config.BringMobSnapDistance or 4) then
        -- It is already close enough. Do not keep testing ownership for this
        -- hold; the mover is responsible from here on.
        runtime.state.bringSnapped[mob] = true
        return false
    end

    local moved = false
    if runtime.bringLocallyOwned(part) then
        moved = pcall(function()
            -- Keep the facing of the rig, but put its root at the ring slot. The
            -- source uses the same one-step position move for the pack.
            part.CFrame = CFrame.new(goal) * part.CFrame.Rotation
        end)
    end
    if runtime.bringLocallyOwned(part) then
        pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
    end
    if runtime.bringLocallyOwned(part) then
        pcall(function() part.AssemblyAngularVelocity = Vector3.zero end)
    end
    if moved and runtime.bringLocallyOwned(part) then
        runtime.state.bringSnapped[mob] = true
    end
    return moved
end

-- A mob is let go: the drag goes away and every value this run changed is put
-- back exactly as the game had it, so the mob can stand and walk on its own
-- again. Only the private mover recorded for this mob is destroyed; a
-- pre-existing mover belongs to somebody else and is never touched.
runtime.letGoMob = function(mob, part)
    part = part or anchorOf(mob)
    local mover = runtime.state.bringMover[mob]
    if mover then
        pcall(function() mover:Destroy() end)
        runtime.state.bringMover[mob] = nil
    end

    local saved = runtime.state.bringSaved[mob]
    if saved then
        -- A client must not write to a rig that the server has taken back.
        -- Keep the snapshot while that rig is alive but server-owned: if this
        -- client gets ownership back, the original values can still be put
        -- back instead of capturing the frozen values as a new "original".
        local restorePart = saved.part or part
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        local rigDead = hum ~= nil and hum.Health <= 0
        local partAlive = restorePart and restorePart.Parent ~= nil
        local canRestore = partAlive and runtime.bringLocallyOwned(restorePart)
        local restoreComplete = false
        if canRestore then
            -- Only CanCollide was changed by this run. CanTouch and Massless
            -- are deliberately not written, so the real touch behaviour and
            -- assembly mass are never replaced by an old snapshot.
            --
            -- Ownership can change while the values are being restored. Check
            -- it before every group of writes and once more at the end. If it
            -- was lost in the middle, keep the snapshot: a partial restore
            -- must be retried instead of silently freezing a part of the rig.
            local stillOwned = true
            local restoreSucceeded = true
            for d, orig in pairs(saved.parts) do
                if d.Parent then
                    if not runtime.bringLocallyOwned(restorePart) then
                        stillOwned = false
                        break
                    end
                    local ok = pcall(function() d.CanCollide = orig.collide end)
                    if not ok then restoreSucceeded = false end
                end
            end
            if stillOwned and runtime.bringLocallyOwned(restorePart) then
                local ok = pcall(function()
                    restorePart.AssemblyLinearVelocity = saved.linear or Vector3.zero
                    restorePart.AssemblyAngularVelocity = saved.angular or Vector3.zero
                    if saved.hadBeingBrought then
                        restorePart:SetAttribute("BeingBrought", saved.beingBrought)
                    else
                        restorePart:SetAttribute("BeingBrought", nil)
                    end
                end)
                if not ok then restoreSucceeded = false end
            else
                stillOwned = false
            end
            if stillOwned and hum then
                if runtime.bringLocallyOwned(restorePart) then
                    local ok = pcall(function()
                        if saved.platformStand ~= nil then hum.PlatformStand = saved.platformStand end
                        if saved.autoRotate ~= nil then hum.AutoRotate = saved.autoRotate end
                        if saved.walk ~= nil then hum.WalkSpeed = saved.walk end
                        if saved.jump ~= nil then hum.JumpPower = saved.jump end
                        -- Restore the state that was captured before the hold. A
                        -- blanket Running change used to overwrite a mob that was
                        -- already jumping or lying down before it was picked up.
                        if saved.state then
                            local changed = hum:ChangeState(saved.state)
                            if changed == false then error("state restore was refused") end
                        end
                    end)
                    if not ok then restoreSucceeded = false end
                else
                    stillOwned = false
                end
                -- A corpse cannot really be revived by ChangeState. The saved
                -- state was still attempted above, but a mob that died during
                -- the hold must remain a corpse afterwards.
                if hum.Health <= 0 then
                    local currentState = nil
                    pcall(function() currentState = hum:GetState() end)
                    if currentState ~= Enum.HumanoidStateType.Dead then
                        local ok, changed = pcall(function()
                            return hum:ChangeState(Enum.HumanoidStateType.Dead)
                        end)
                        if not ok or changed == false then restoreSucceeded = false end
                    end
                end
            end
            if stillOwned and not runtime.bringLocallyOwned(restorePart) then
                stillOwned = false
            end
            restoreComplete = stillOwned and restoreSucceeded
        end
        local keepPending = partAlive and not restoreComplete and not rigDead
        if keepPending then
            -- This snapshot is waiting for ownership to return. It is not an
            -- active hold snapshot and must be restored before the same mob is
            -- selected and held again.
            saved.pending = true
        end
        if not keepPending then
            runtime.state.bringSaved[mob] = nil
            if FarmRuntime.bringRestore then FarmRuntime.bringRestore[mob] = nil end
        end
    end
    runtime.state.bringHeld[mob] = nil
    runtime.state.bringSnapped[mob] = nil
    runtime.state.bringCarryingTarget[mob] = nil
    -- the slot is only given back; the counter never walks back, or a new mob
    -- would take a step a mob that is still held already stands on
    runtime.state.bringSlot[mob] = nil
end
letGoMob = runtime.letGoMob

-- Keep restoration snapshots in the shared runtime registry when an
-- execution is torn down. The next execution can adopt them and finish the
-- restoration after ownership returns.
runtime.exportPendingBringSnapshots = function()
    for mob, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.pending then
            FarmRuntime.bringRestore[mob] = saved
        end
    end
end
runtime.importBringRestoreSnapshots = function()
    for mob, saved in pairs(FarmRuntime.bringRestore) do
        local part = saved and saved.part
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        if not part or not part.Parent or (hum and hum.Health <= 0) then
            FarmRuntime.bringRestore[mob] = nil
            -- Sweep the identical stale copy from the live state as well.
            -- Do not touch a newer active snapshot for the same mob.
            if runtime.state.bringSaved[mob] == saved then
                runtime.state.bringSaved[mob] = nil
            end
        elseif not runtime.state.bringSaved[mob] then
            runtime.state.bringSaved[mob] = saved
        end
    end
end
runtime.restorePendingBringMobs = function()
    local pending = {}
    for mob, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.pending then
            pending[#pending + 1] = {mob = mob, saved = saved}
        end
    end
    for _, entry in ipairs(pending) do
        local mob, saved = entry.mob, entry.saved
        local part = saved and saved.part
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        if not part or not part.Parent or (hum and hum.Health <= 0) then
            runtime.state.bringSaved[mob] = nil
            FarmRuntime.bringRestore[mob] = nil
        elseif runtime.bringLocallyOwned(part) then
            runtime.letGoMob(mob, part)
        end
    end
end
runtime.importBringRestoreSnapshots()

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
        if runtime.state.bringHeld[target] or runtime.state.bringSaved[target] then
            runtime.letGoMob(target, anchor)
        end
        return
    end

    local now = tick()

    -- Check the straight route before the range and height gates. Otherwise an
    -- out-of-range target can pull the player across water before Bring Mob
    -- ever learns that the route is wet. The result is cached briefly and
    -- repeated when the player moves.
    local pathCheck = runtime.state.bringPathCheck
    if pathCheck and pathCheck.target ~= target then pathCheck = nil end
    local pathRootMoved = pathCheck and pathCheck.root
        and (pathCheck.root - root.Position).Magnitude > 3
    if not pathCheck or now - (pathCheck.at or 0) > 0.5 or pathRootMoved then
        pathCheck = {
            target = target,
            at = now,
            root = root.Position,
            blocked = runtime.bringPathOverWater(anchor.Position, root.Position),
        }
        runtime.state.bringPathCheck = pathCheck
    end
    runtime.state.bringPathBlocked = pathCheck.blocked == true
    if runtime.state.bringPathBlocked then
        -- A wet path is never used for a mob or for the player's approach. The
        -- pack is released and the stable hold position is kept instead.
        for mob, part in pairs(runtime.state.bringHeld) do
            runtime.letGoMob(mob, part)
        end
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint = nil
        runtime.state.bringCentre = nil
        runtime.state.bringCarryOffsetY = nil
        return
    end

    local bringRange = tonumber(runtime.config.BringMobRange) or 60
    -- BringMobRange is a horizontal range. The main loop uses the same
    -- X/Z geometry, so a configured limit means exactly the same thing in
    -- both places. An out-of-range target releases the whole pack at once.
    local rangeDx = anchor.Position.X - root.Position.X
    local rangeDy = anchor.Position.Y - root.Position.Y
    local rangeDz = anchor.Position.Z - root.Position.Z
    local rangeFlat = math.sqrt(rangeDx * rangeDx + rangeDz * rangeDz)
    if bringRange <= 0 or rangeFlat > bringRange then
        for mob, part in pairs(runtime.state.bringHeld) do
            runtime.letGoMob(mob, part)
        end
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathBlocked = false
        runtime.state.bringPathCheck = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
        return
    end

    -- The player must also be near the mob's height before the carry starts.
    -- Otherwise the bot grabs a camp from high in the air and carries it at
    -- that impossible vertical offset, which is how a pack ended up below the
    -- walkable ground and in the water.
    local verticalRange = tonumber(runtime.config.BringMobVerticalRange) or 18
    if verticalRange > 0 and math.abs(rangeDy) > verticalRange then
        for mob, part in pairs(runtime.state.bringHeld) do
            runtime.letGoMob(mob, part)
        end
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathBlocked = false
        runtime.state.bringPathCheck = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
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
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathBlocked = false
        runtime.state.bringPathCheck = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
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
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
    end

    -- Keep the carried rig at a fixed vertical distance from the player. The
    -- old goal was rebuilt from the rig's current Y every update, so gravity
    -- could lower both the goal and the rig without limit. The live trace
    -- showed that drift ending on the ocean plane and pulling the player down
    -- with it. Capture the original offset once per target and keep it stable.
    local carryOffsetY
    if carryTarget then
        carryOffsetY = runtime.state.bringCarryOffsetY
        if carryOffsetY == nil then
            local rawOffsetY = anchor.Position.Y - root.Position.Y
            local maxDrop = math.max((runtime.config.HoverHeight or 7) + 8, 12)
            local maxRise = 8
            carryOffsetY = math.max(-maxDrop, math.min(maxRise, rawOffsetY))
            runtime.state.bringCarryOffsetY = carryOffsetY
        end
    else
        runtime.state.bringCarryOffsetY = nil
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
    local pathGoal = carryTarget and root.Position or anchor.Position
    if count > 1 then
        local near = {}
        for _, mob in ipairs(collectEnemies(now)) do
            if mob ~= target and not mob:FindFirstChild("Ignored") then
                local part = anchorOf(mob)
                local hum = mob:FindFirstChildOfClass("Humanoid")
                if part and hum and hum.Health > 0 and not ownedByOther(part)
                    and runtime.bringLocallyOwned(part)
                    and mobKey(mob.Name) == key
                    and (part.Position - anchor.Position).Magnitude <= (runtime.config.BringMobSearch or 200)
                    and (verticalRange <= 0
                        or math.abs(part.Position.Y - anchor.Position.Y) <= verticalRange) then
                    table.insert(near, {mob = mob, dist = (part.Position - anchor.Position).Magnitude})
                end
            end
        end
        table.sort(near, function(a, b) return a.dist < b.dist end)
        for _, entry in ipairs(near) do
            if #list >= count then break end
            local mob, part = entry.mob, anchorOf(entry.mob)
            local cached = runtime.state.bringPathCache[mob]
            local goalMoved = cached and cached.goal
                and (cached.goal - pathGoal).Magnitude > 3
            if not cached or now - (cached.at or 0) > 1 or goalMoved then
                cached = {
                    at = now,
                    goal = pathGoal,
                    blocked = runtime.bringPathOverWater(part.Position, pathGoal),
                }
                runtime.state.bringPathCache[mob] = cached
            end
            if not cached.blocked then
                table.insert(list, entry.mob)
            end
        end
    end

    local stillHeld = {}
    for index, mob in ipairs(list) do
        local part = anchorOf(mob)
        if part then
            local isTarget = mob == target
            -- A server-owned target is the centre of the ring but is never
            -- held or changed. Only locally owned extras are packed around
            -- it, and the player walks to the target itself. Ownership is
            -- checked again here: it can change between selecting the mob
            -- and changing its rig.
            local shouldHold = (not isTarget) or carryTarget
            if shouldHold and not runtime.bringLocallyOwned(part) then
                runtime.letGoMob(mob, part)
                shouldHold = false
            end
            if not shouldHold then
                if runtime.state.bringHeld[mob] or runtime.state.bringSaved[mob] then
                    runtime.letGoMob(mob, part)
                end
            else
                -- A snapshot left by a temporary ownership loss must be
                -- restored before this mob becomes an active hold again. Only
                -- then is a fresh snapshot of the current game state captured.
                local pendingSaved = runtime.state.bringSaved[mob]
                if pendingSaved and pendingSaved.pending then
                    runtime.letGoMob(mob, part)
                end
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
                -- pulled over a slope otherwise floats or sinks into it. A
                -- carried target uses the stable player-relative height above;
                -- using its current Y here made the goal fall with the rig.
                local packY = anchor.Position.Y
                if carryTarget then
                    packY = root.Position.Y + carryOffsetY
                end
                local goal = Vector3.new(goalX,
                    packY + (part.Size.Y - anchor.Size.Y) * 0.5, goalZ)
                local hum = mob:FindFirstChildOfClass("Humanoid")

                -- The pack keeps the real assembly mass and the real touch
                -- behaviour. Only collision and the walking state are changed,
                -- and every original value is written down before the first
                -- change so release can restore the rig exactly.
                if not runtime.state.bringSaved[mob] then
                    local saved = { parts = {}, part = part, pending = false }
                    for _, d in ipairs(mob:GetDescendants()) do
                        if d:IsA("BasePart") then
                            saved.parts[d] = {
                                collide = d.CanCollide,
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

                    -- Ownership is checked immediately before each change.
                    -- If it was lost during the capture, release restores the
                    -- untouched rig and the mob is no longer part of the pack.
                    for d in pairs(saved.parts) do
                        if d.Parent and runtime.bringLocallyOwned(part) then
                            pcall(function() d.CanCollide = false end)
                        end
                    end
                    if runtime.bringLocallyOwned(part) then
                        pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
                    end
                    if runtime.bringLocallyOwned(part) then
                        pcall(function() part.AssemblyAngularVelocity = Vector3.zero end)
                    end
                    if runtime.bringLocallyOwned(part) then
                        pcall(function() part:SetAttribute("BeingBrought", true) end)
                    end
                end

                if hum and stillHeld[mob] then
                    if runtime.bringLocallyOwned(part) then
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.PlatformStand = true end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.AutoRotate = false end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.WalkSpeed = 0 end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.JumpPower = 0 end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function()
                                hum:ChangeState(Enum.HumanoidStateType.Physics)
                            end)
                        end
                        -- This is the fast first step from the working source.
                        -- It checks ownership again before moving the root.
                        if runtime.bringLocallyOwned(part) then
                            runtime.bringSnap(mob, part, goal)
                        end
                    else
                        runtime.letGoMob(mob, part)
                        stillHeld[mob] = nil
                    end
                end

                if stillHeld[mob] then
                    -- The game deliberately refuses to run its BodyMover on enemy
                    -- characters. Each carried mob therefore gets one private root
                    -- BodyVelocity with a unique runtime name. Only that exact mover
                    -- is stored and later destroyed; unrelated movers are untouched.
                    local mover = runtime.state.bringMover[mob]
                    if mover and not runtime.validBringMover(mover, part) then
                        pcall(function() mover:Destroy() end)
                        runtime.state.bringMover[mob] = nil
                        mover = nil
                    end
                    if not mover and runtime.bringLocallyOwned(part) then
                        runtime.state.bringMoverSeq = (runtime.state.bringMoverSeq or 0) + 1
                        mover = Instance.new("BodyVelocity")
                        mover.Name = "FarmBringMover_" .. tostring(runtime.generation)
                            .. "_" .. tostring(runtime.state.bringMoverSeq)
                        -- The working source uses 1e9. A finite force is enough for
                        -- every enemy rig and avoids an unbounded force on an assembly
                        -- that is changing ownership.
                        mover.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                        mover.P = 12500
                        mover.Velocity = Vector3.zero
                        pcall(function() mover:SetAttribute("FarmOwned", true) end)
                        if runtime.bringLocallyOwned(part) then
                            mover.Parent = part
                            runtime.state.bringMover[mob] = mover
                        else
                            mover:Destroy()
                            mover = nil
                            runtime.letGoMob(mob, part)
                            stillHeld[mob] = nil
                        end
                    elseif not mover then
                        runtime.letGoMob(mob, part)
                        stillHeld[mob] = nil
                    end

                    -- The hold drags the mob over with the same body velocity the hubs
                    -- use. The owned target is carried too, so the bot fights where it
                    -- stands instead of walking after a mob that was never brought.
                    if stillHeld[mob] and mover and runtime.bringLocallyOwned(part) then
                        local toGo = goal - part.Position
                        local gap = toGo.Magnitude
                        if gap > 0.6 then
                            -- A speed that closes a fixed fraction of the gap per update
                            -- (the hold is refreshed twenty times a second). The old
                            -- distance times eight with a six-stud floor overshot every
                            -- step, and the mob visibly bounced.
                            mover.Velocity = toGo.Unit * math.min(gap * 4, 120)
                        else
                            mover.Velocity = Vector3.zero
                        end
                        runtime.state.bringHeld[mob] = part
                    elseif stillHeld[mob] then
                        runtime.letGoMob(mob, part)
                        stillHeld[mob] = nil
                    end
                end
            end
        end
    end

    -- A rig whose ownership was taken away keeps its original snapshot until
    -- it can be restored. If ownership has returned but the mob is no longer
    -- part of this pack, restore it now instead of freezing it for ever.
    local restorePending = {}
    for mob, saved in pairs(runtime.state.bringSaved) do
        if not stillHeld[mob] then
            restorePending[#restorePending + 1] = {
                mob = mob,
                part = saved and saved.part,
            }
        end
    end
    for _, entry in ipairs(restorePending) do
        local part = entry.part
        if part and part.Parent and runtime.bringLocallyOwned(part) then
            runtime.letGoMob(entry.mob, part)
        elseif not part or not part.Parent then
            runtime.state.bringSaved[entry.mob] = nil
        end
    end

    runtime.state.bringCarryingTarget[target] = stillHeld[target] == true
    if not stillHeld[target] then
        runtime.state.bringCarryOffsetY = nil
    end

    -- the mobs of the last pack that are not in this one any more go free
    local releaseHeld = {}
    for mob, part in pairs(runtime.state.bringHeld) do
        if not stillHeld[mob] then
            releaseHeld[#releaseHeld + 1] = {mob = mob, part = part}
        end
    end
    for _, entry in ipairs(releaseHeld) do
        runtime.letGoMob(entry.mob, entry.part)
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
local tweenProxy
local tweenFollower
local tweenHold
local tweenHoldRoot

-- Banana Hub does not tween HumanoidRootPart directly. It tweens a small
-- transparent proxy and makes the character follow that proxy every frame.
-- The character therefore keeps the proxy's exact interpolated position while
-- its Humanoid is in the physics state. A zero-velocity body hold keeps
-- gravity from pulling it away before an official touch can be observed.
-- The main script keeps its own movement-owner lock around this transport.
local function destroyTweenHold()
    local oldRoot = tweenHoldRoot
    if tweenHold and tweenHold.Parent then
        pcall(function() tweenHold:Destroy() end)
    end
    tweenHold = nil
    tweenHoldRoot = nil
    if oldRoot and oldRoot.Parent then
        pcall(function() oldRoot.AssemblyLinearVelocity = Vector3.zero end)
    end
end

local function hasActiveBringHold()
    for _, carried in pairs(runtime.state.bringCarryingTarget or {}) do
        if carried == true then return true end
    end
    return false
end

local function shouldKeepTweenHold()
    return runtime.state.saberActive == true or runtime.state.flying == true
        or hasActiveBringHold()
end

local function ensureTweenHold(root)
    if not root then return end
    if tweenHold and tweenHold.Parent and tweenHoldRoot == root then return end
    destroyTweenHold()
    local hold = Instance.new("BodyVelocity")
    hold.Name = "FarmRuntimeTweenHold"
    hold.MaxForce = Vector3.new(100000, 100000, 100000)
    hold.Velocity = Vector3.zero
    hold.Parent = root
    tweenHold = hold
    tweenHoldRoot = root
end

runtime.releaseTweenHold = function()
    if not shouldKeepTweenHold() then destroyTweenHold() end
end

local function getTweenProxy(root)
    if tweenProxy and tweenProxy.Parent then
        local ownerGeneration = tweenProxy:GetAttribute("FarmRuntimeGeneration")
        if ownerGeneration == runtime.generation then
            tweenProxy.CFrame = root.CFrame
            return tweenProxy
        end
        -- A proxy from an older runtime must never become the transport of a
        -- newer runtime. The old owner has already been stopped by the time
        -- this code runs, so the stale part can be removed safely.
        pcall(function() tweenProxy:Destroy() end)
        tweenProxy = nil
    end
    local proxy = Instance.new("Part")
    proxy.Name = "FarmRuntimeTweenProxy"
    proxy:SetAttribute("FarmRuntimeGeneration", runtime.generation)
    proxy.Size = Vector3.new(1, 1, 1)
    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CanTouch = false
    proxy.Massless = true
    proxy.Transparency = 1
    proxy.CFrame = root.CFrame
    proxy.Parent = Workspace
    tweenProxy = proxy
    return proxy
end

-- A crashed or older runtime can leave its invisible proxy behind. The
-- current runtime owns the character and must not inherit that stale part.
for _, object in ipairs(Workspace:GetChildren()) do
    if object:IsA("BasePart") and object.Name == "FarmRuntimeTweenProxy"
        and object:GetAttribute("FarmRuntimeGeneration") ~= runtime.generation then
        pcall(function() object:Destroy() end)
    end
end

local function startTweenFollower(tween, proxy)
    local follower = {cancelled = false}
    tweenFollower = follower
    task.spawn(function()
        while not follower.cancelled and activeTween == tween do
            local root = getRoot()
            if root then
                ensureTweenHold(root)
                -- This is Banana Hub's proxy rule: a large divergence means
                -- the character was replaced or corrected, so the proxy takes
                -- the character's current pose; otherwise the character takes
                -- the proxy's interpolated pose.
                local gap = (root.Position - proxy.Position).Magnitude
                if gap > 200 then
                    proxy.CFrame = root.CFrame
                else
                    root.CFrame = proxy.CFrame
                end
            end
            if tween.PlaybackState ~= Enum.PlaybackState.Playing then break end
            task.wait()
        end
        if not follower.cancelled and activeTween == tween then
            local root = getRoot()
            if root then root.CFrame = proxy.CFrame end
            -- Saber and flight keep the hold through the final official touch.
            -- Ordinary farming releases it as soon as the tween is complete.
            if not shouldKeepTweenHold() then
                destroyTweenHold()
            end
        end
        if tweenFollower == follower then tweenFollower = nil end
    end)
end

-- The one tween of the script. Every trip of the character goes through here,
-- so the walk to a mob, the flight to an island and the way into the whirlpool
-- all move at exactly runtime.config.MoveSpeed. There is no cap: a longer way simply
-- takes longer, it is never rushed (a rushed flight is what the game undoes).
runtime.tweenTo = function(cf)
    local root = getRoot()
    if not root or not cf then return false end
    if runtime.state.travelActive then return false end
    local dist = (root.Position - cf.Position).Magnitude
    if activeTween and tweenGoal
        and activeTween.PlaybackState == Enum.PlaybackState.Playing then
        local moved = (tweenGoal.Position - cf.Position).Magnitude
        local left = (root.Position - tweenGoal.Position).Magnitude
        if moved < math.max(12, left * 0.4) then return false end
    end
    if activeTween then activeTween:Cancel() end
    if tweenFollower then tweenFollower.cancelled = true end
    runtime.setFlying()
    ensureTweenHold(root)
    local proxy = getTweenProxy(root)
    tweenGoal = cf
    activeTween = TweenService:Create(proxy,
        TweenInfo.new(math.max(dist / runtime.config.MoveSpeed, 0.12), Enum.EasingStyle.Linear),
        {CFrame = cf})
    activeTween:Play()
    startTweenFollower(activeTween, proxy)
    return true
end

-- Safe tween farming moves the character between real travel slots. The old
-- dodge loop changed the CFrame every frame around a tiny circle, which looked
-- like spinning in place and kept the player inside the enemy's threat range.
-- Each slot is far enough away to be safe and still inside the attack range.
runtime.tweenFarmSlot = function(targetObject, centre, root, heldTarget, height)
    if not targetObject or not centre or not root then return end
    local s = runtime.state
    local now = tick()
    local radius = tonumber(runtime.config.DodgeRadius) or 28
    if radius < 14 then radius = 14 end
    if radius > 45 then radius = 45 end

    if s.dodgeSlotTarget ~= targetObject then
        s.dodgeSlotTarget = targetObject
        s.dodgeSlotIndex = 0
        s.dodgeSlotAt = 0
        s.dodgePatrolCentre = nil
        local dx = root.Position.X - centre.X
        local dz = root.Position.Z - centre.Z
        s.dodgeSlotAngle = math.atan2(dz, dx)
    end

    local requestedStepTime = tonumber(runtime.config.DodgeStepTime) or 0.4
    if requestedStepTime < 0.2 then requestedStepTime = 0.2 end
    if requestedStepTime > 1.5 then requestedStepTime = 1.5 end
    if now < (s.dodgeSlotAt or 0) then return end

    local goal
    local candidateAngle
    local candidateIndex
    local polygonChord = 0
    if heldTarget then
        -- A carried target follows the player. Patrol around a stable centre
        -- instead of chasing the moving target, which would make the pack and
        -- the player pull against each other.
        local patrol = s.dodgePatrolCentre
        if not patrol or (root.Position - patrol).Magnitude > radius * 1.5 then
            patrol = root.Position
            s.dodgePatrolCentre = patrol
            s.dodgeSlotIndex = 0
        end
        candidateIndex = (s.dodgeSlotIndex or 0) + 1
        candidateAngle = ((candidateIndex - 1) % 4) * math.pi * 0.5
        goal = Vector3.new(patrol.X + math.cos(candidateAngle) * radius,
            height or (patrol.Y + (runtime.config.HoverHeight or 7)),
            patrol.Z + math.sin(candidateAngle) * radius)
    else
        -- Around a normal target, move through wide polygon legs. The first
        -- leg starts on the side where the player already is, so the approach
        -- never crosses through the mob.
        local speed = tonumber(runtime.config.DodgeSpeed) or 90
        local stepAngle = math.rad(speed * requestedStepTime)
        if stepAngle < math.pi / 3 then stepAngle = math.pi / 3 end
        -- The horizontal distance of this polygon leg is the chord between the
        -- old and new slot, not the radius of the ring.
        polygonChord = 2 * radius * math.sin(stepAngle * 0.5)
        candidateAngle = (s.dodgeSlotAngle or 0) + stepAngle
        goal = Vector3.new(centre.X + math.cos(candidateAngle) * radius,
            height or (centre.Y + (runtime.config.HoverHeight or 7)),
            centre.Z + math.sin(candidateAngle) * radius)
    end

    -- The next slot starts only after this exact leg has had time to finish.
    -- Otherwise a slow MoveSpeed can cancel the tween halfway and make the
    -- character jitter around the mob instead of travelling between slots.
    local legDistance = math.max((root.Position - goal).Magnitude, polygonChord)
    local travelTime = legDistance / math.max(1, tonumber(runtime.config.MoveSpeed) or 200)
    local slotDuration = math.max(requestedStepTime, travelTime + 0.1)
    local accepted = runtime.tweenTo(CFrame.new(goal) * CFrame.Angles(math.rad(-90), 0, 0))
    -- The polygon advances only when a tween was really accepted. A skipped
    -- or canceled leg must not count as a completed side of the safe ring.
    if accepted then
        if heldTarget then
            s.dodgeSlotIndex = candidateIndex
        else
            s.dodgeSlotAngle = candidateAngle
        end
        s.dodgeSlotAt = now + slotDuration
    end
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
    if tweenFollower then tweenFollower.cancelled = true; tweenFollower = nil end
    tweenGoal = nil
    runtime.releaseTweenHold()
    -- Another movement operation now owns the character. The polygon must
    -- start from a fresh side instead of continuing from a canceled leg.
    local s = runtime.state
    s.dodgeSlotTarget = nil
    s.dodgeSlotAngle = 0
    s.dodgeSlotIndex = 0
    s.dodgeSlotAt = 0
    s.dodgePatrolCentre = nil
    runtime.setWalking()
end

-- Anti-fall keeps a real ground point, not the last point of a tween in the
-- air. A raycast finds the floor below the character; the old point is only
-- replaced when the player is not already falling.
runtime.updateSafePoint = function(root, now)
    if not root then return end
    if root.Position.Y <= (runtime.config.SafeY or -300) + 10 then return end
    local velocity = root.AssemblyLinearVelocity
    if velocity.Y < -35 then return end
    if runtime.state.flying or runtime.state.travelActive then return end
    if activeTween and activeTween.PlaybackState == Enum.PlaybackState.Playing then return end
    local char = LocalPlayer.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = char and {char} or {}
    local ok, hit = pcall(function()
        return Workspace:Raycast(root.Position, Vector3.new(0, -900, 0), params)
    end)
    if ok and hit and not runtime.bringWaterPart(hit.Instance)
        and hit.Position.Y > (runtime.config.SafeY or -300) + 5 then
        runtime.state.lastSafe = hit.Position + Vector3.new(0, 4, 0)
        runtime.state.lastSafeAt = now
    end
end

runtime.fallbackSafePoint = function(root)
    local best, bestD = nil, math.huge
    local function consider(obj)
        local anchor = anchorOf(obj)
        if anchor and not runtime.bringPointOverWater(anchor.Position) then
            local d = root and (root.Position - anchor.Position).Magnitude or 0
            if d < bestD then best, bestD = anchor, d end
        end
    end
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("SpawnLocation") then consider(d) end
    end
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("PlayerSpawns")
    if spawns then
        for _, d in ipairs(spawns:GetChildren()) do consider(d) end
    end
    local map = Workspace:FindFirstChild("Map")
    if map then
        local teleport = map:FindFirstChild("TeleportSpawn")
        if teleport then consider(teleport) end
    end
    return best and best.Position or nil
end

runtime.recoverFall = function(root, now)
    if not runtime.config.AntiFall or not root then return false end
    -- A tween or a world/flight operation is a deliberate route. Recovering
    -- from a fall in the middle of one cancels the route and can move the
    -- character into a different island or sea.
    if runtime.state.travelActive or runtime.state.flying then return false end
    if activeTween and activeTween.PlaybackState == Enum.PlaybackState.Playing then return false end
    local limit = tonumber(runtime.config.SafeY) or -300
    local velocity = root.AssemblyLinearVelocity
    local falling = velocity.Y < -70
    if root.Position.Y >= limit and not (falling and root.Position.Y < limit + 140) then
        return false
    end
    if now < (runtime.state.recoverUntil or 0) then return true end

    local flightOwner = runtime.state.flightOwner
    local flightOwnerToken = runtime.state.flightMovementToken
    runtime.state.flightToken = (runtime.state.flightToken or 0) + 1
    runtime.state.flying = false
    runtime.state.flightOwner = nil
    runtime.state.flightMovementToken = nil
    if flightOwner and runtime.releaseMovement then
        runtime.releaseMovement(flightOwner, flightOwnerToken)
    end
    if flightOwner == "shop" and runtime.resetShopState then runtime.resetShopState() end
    runtime.stopTween()
    -- A falling player must not keep dragging a pack downward. Release the
    -- Bring Mob hold before the recovery teleport so the mobs cannot pull the
    -- character back into the sea.
    if runtime.releaseBringMobs then runtime.releaseBringMobs() end
    if runtime.restoreHitbox then runtime.restoreHitbox() end
    if runtime.restoreNoclip then runtime.restoreNoclip() end
    local safe = runtime.state.lastSafe or runtime.fallbackSafePoint(root)
    runtime.state.recoverUntil = now + 2
    runtime.state.status = "Recovering..."
    -- Stop the downward velocity even when no safe point exists. Otherwise
    -- the character can keep accelerating while the next recovery attempt is
    -- waiting for the cooldown.
    local velocity = root.AssemblyLinearVelocity
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(
            velocity.X, math.max(0, velocity.Y), velocity.Z)
    end)
    if safe then
        root.CFrame = CFrame.new(safe)
        local velocity = root.AssemblyLinearVelocity
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(
                velocity.X, math.max(0, velocity.Y), velocity.Z)
        end)
        runtime.setWalking()
        dbg(string.format("Recovered from a fall (Y=%.0f)", root.Position.Y))
    else
        dbg(string.format("Fall detected (Y=%.0f), but no safe point was found", root.Position.Y))
    end
    return true
end

runtime.moveTo = function(cf, noWarp)
    local root = getRoot()
    if not root then return end
    if runtime.state.travelActive then return end
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
    -- bypasses it; here we only clear the client stun/busy flags that can
    -- block a swing.
    local char = LocalPlayer.Character
    for _, name in ipairs({"Stun", "Busy"}) do
        local marker = char and char:FindFirstChild(name)
        if marker then
            pcall(function()
                if marker:IsA("BoolValue") then
                    marker.Value = false
                else
                    marker.Value = 0
                end
            end)
        end
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
    runtime.state.attackRegistered = false
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
            -- End the synthetic touch even for a normal gun. Destroying only
            -- the event left some controller paths with a Begin input that
            -- never received its matching End.
            pcall(function() input.UserInputState = Enum.UserInputState.End end)
            pcall(function() changed:Fire() end)
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
        runtime.state.attackRegistered = true
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

-- Health confirmation runs beside the attack loop. Waiting for the mob to lose
-- health used to block the next swing for the whole animation (often about two
-- seconds). The watcher records real health decreases without delaying the
-- next attack and backs the fast cadence off when the server refuses a hit.
--
-- Fast attacks can overlap, so every pending swing is kept in dispatch order.
-- A health decrease is claimed by the oldest swing that has not claimed that
-- mob yet. This prevents a late hit from the previous packet from falsely
-- confirming the newer packet, while a later decrease can still confirm the
-- newer swing.
runtime.publishAttackConfirmation = function(record)
    local s = runtime.state
    if not record or record.id ~= s.attackConfirmSeq then return end
    s.attackConfirmed = record.fullConfirmed
    s.attackPrimaryConfirmed = record.primaryConfirmed
    s.aoeCount = record.count
    s.aoeConfirmed = record.fullConfirmed and record.count or 0
    if record.primaryConfirmed then
        local extra = record.count > 1 and (" +" .. tostring(record.count - 1) .. " damaged") or ""
        s.status = "Hitting " .. record.targetName .. extra
            .. (record.fullConfirmed and " (confirmed)" or " (primary confirmed)")
    end
end

runtime.pollAttackDamage = function()
    local s = runtime.state
    local pending = s.attackPending or {}
    local observed = {}

    -- Read every watched mob once. The global seen value is the health after
    -- the last decrease that was already assigned to an earlier swing.
    for _, record in ipairs(pending) do
        for mob in pairs(record.watched) do
            if observed[mob] == nil then
                local hum = mob and mob:FindFirstChildOfClass("Humanoid")
                if hum then observed[mob] = hum.Health end
            end
        end
    end

    for mob, currentHealth in pairs(observed) do
        local seen = s.attackHealthSeen[mob]
        if seen == nil then
            seen = currentHealth
        elseif currentHealth < seen then
            -- Assign this decrease to the oldest pending swing that has not
            -- already claimed a decrease from this mob.
            for _, record in ipairs(pending) do
                if record.watched[mob] and not record.claimed[mob] then
                    record.claimed[mob] = true
                    record.count = record.count + 1
                    if mob == record.target then
                        record.primaryConfirmed = true
                        -- Count the Pole hit when this record actually claims
                        -- the decrease. Publication may happen after a newer
                        -- swing became current, but the older confirmed hit
                        -- must still count exactly once.
                        if record.pole and not record.poleCounted
                            and s.poleToken == record.poleToken
                            and s.poleWeapon == record.poleWeapon then
                            record.poleCounted = true
                            s.poleHits = (s.poleHits or 0) + 1
                            s.poleProgressAt = tick()
                        end
                    end
                    -- Full AOE confirmation still means that every watched mob
                    -- lost health. A primary hit by itself is not full AOE.
                    if record.primaryConfirmed and record.count >= record.watchedCount then
                        record.fullConfirmed = true
                    end
                    if record.primaryConfirmed and record.id == s.attackConfirmSeq then
                        s.attackLastConfirmedAt = tick()
                        s.attackMisses = 0
                        s.attackCadence = record.fastTarget
                    end
                    break
                end
            end
        end
        -- Health regeneration and a decrease that no pending swing claimed are
        -- both folded into the next baseline.
        s.attackHealthSeen[mob] = currentHealth
    end

    local latest = nil
    for _, record in ipairs(pending) do
        if record.id == s.attackConfirmSeq then latest = record end
        if not record.feedbackChecked and tick() >= record.feedbackDeadline then
            record.feedbackChecked = true
            -- Only the newest swing owns the shared cadence. An older missed
            -- packet must not mask a miss from the current target.
            if record.id == s.attackConfirmSeq and not record.primaryConfirmed then
                s.attackMisses = (s.attackMisses or 0) + 1
                local current = s.attackCadence or record.fastTarget
                local safe = math.max(record.fastTarget, record.officialDelay)
                s.attackCadence = math.min(safe,
                    math.max(record.fastTarget, current * 1.5))
            end
        end
    end

    if latest then runtime.publishAttackConfirmation(latest) end

    -- A fully confirmed swing no longer needs to stay in the claim queue.
    -- Remove from the back so an earlier record is never skipped.
    for index = #pending, 1, -1 do
        local record = pending[index]
        if record.fullConfirmed then
            if record.id == s.attackConfirmSeq then
                runtime.publishAttackConfirmation(record)
            end
            table.remove(pending, index)
        end
    end
end

runtime.removeAttackRecord = function(record)
    local pending = runtime.state.attackPending or {}
    for index, item in ipairs(pending) do
        if item == record then
            table.remove(pending, index)
            return true
        end
    end
    return false
end

runtime.startAttackConfirmation = function(watched, target, deadline, startedAt,
    epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
    local s = runtime.state
    -- Account for damage that landed just before this swing was registered.
    -- Existing older records get the first claim through the normal queue.
    runtime.pollAttackDamage()

    local watchedCount = 0
    for _ in pairs(watched) do watchedCount = watchedCount + 1 end
    local sequence = (s.attackConfirmSeq or 0) + 1
    local feedbackWindow = tonumber(runtime.config.FastAttackFeedback) or 0.55
    local record = {
        id = sequence,
        watched = watched,
        target = target,
        targetName = target and target.Name or "the target",
        watchedCount = watchedCount,
        claimed = {},
        count = 0,
        primaryConfirmed = false,
        fullConfirmed = false,
        feedbackChecked = false,
        feedbackDeadline = math.min(deadline, startedAt + feedbackWindow),
        officialDelay = officialDelay,
        fastTarget = fastTarget,
        gun = gun,
        pole = tool ~= nil and tool == s.poleWeapon and s.poleEquipped == true,
        poleToken = s.poleToken,
        poleWeapon = tool,
        poleCounted = false,
    }

    -- A mob that is not watched by an older pending swing starts at the health
    -- it has now. A decrease from before this dispatch is not its damage.
    local pending = s.attackPending or {}
    for mob, health in pairs(watched) do
        local watchedByOlder = false
        for _, older in ipairs(pending) do
            if older.watched[mob] then
                watchedByOlder = true
                break
            end
        end
        if not watchedByOlder then s.attackHealthSeen[mob] = health end
    end

    table.insert(pending, record)
    s.attackPending = pending
    s.attackConfirmSeq = sequence
    s.attackConfirmed = false
    s.attackPrimaryConfirmed = false
    s.aoeCount = 0
    s.aoeConfirmed = 0

    task.spawn(function()
        while tick() < deadline do
            runtime.pollAttackDamage()
            if record.fullConfirmed then break end
            task.wait(0.02)
            if not runtime.operationValid(operationEpoch, epoch, char) then return end
        end

        runtime.pollAttackDamage()
        runtime.removeAttackRecord(record)
        if record.id == s.attackConfirmSeq then
            runtime.publishAttackConfirmation(record)
        end
    end)
end

local function doAttack(tool, target)
    if not tool then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char or not runtime.operationValid(operationEpoch, epoch, char) then return false end
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

    local speed = tonumber(runtime.state.attackSpeed) or 1
    local charSpeed = char and tonumber(char:GetAttribute("AttackSpeedMultiplier")) or 1
    if charSpeed > speed then speed = charSpeed end
    if speed < 0.1 then speed = 0.1 end

    local extraDelay = tonumber(runtime.config.AttackCooldown) or 0
    local officialDelay
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
        officialDelay = interval / speed
    else
        -- The live controller can cancel a basic attack at 80% of its
        -- animation. This is the safe cadence used when Fast Attack is off or
        -- when health feedback has to back the quick cadence off.
        officialDelay = animLength * 0.8 / speed
    end
    if officialDelay < 0.05 then officialDelay = 0.05 end

    local fastTarget = tonumber(runtime.config.FastAttackInterval) or 0.4
    if fastTarget < 0.15 then fastTarget = 0.15 end
    if fastTarget > 1.5 then fastTarget = 1.5 end
    local delay = officialDelay + extraDelay
    local reportedLength = animLength
    if not gun and runtime.config.FastAttack and runtime.config.RemoteAttack then
        local cadence = tonumber(runtime.state.attackCadence) or fastTarget
        if cadence < fastTarget then cadence = fastTarget end
        if cadence > officialDelay then cadence = officialDelay end
        delay = cadence + extraDelay
        -- RegisterAttack still uses the official length/combo protocol. In Fast
        -- Attack mode the length describes the shortened effective animation,
        -- just like the game does when an animation speed multiplier is used.
        local officialBase = animLength * 0.8 / speed
        if officialBase > 0 then
            reportedLength = math.max(0.15,
                math.min(animLength, animLength * (cadence / officialBase)))
        end
    end
    if delay < 0.05 then delay = 0.05 end
    runtime.state.attackReportedLength = reportedLength

    local dispatched = false
    if runtime.config.RemoteAttack then
        dispatched = remoteAttack(target, tool, reportedLength, combo, attackPairs)
    else
        runtime.state.attackRegistered = false
        runtime.state.attackHitDispatched = false
        runtime.state.attackComboSent = false
        runtime.state.aoeCount = 0
    end
    if not runtime.operationValid(operationEpoch, epoch, char) then return false end

    if dispatched then
        runtime.state.attackNextAt = now + delay
        runtime.state.lastAttack = now
        runtime.state.attackFallback = false
        local deadline = now + (gun and 0.6
            or math.min(2.5, math.max(0.7, animLength * 0.8 + 0.2)))
        runtime.startAttackConfirmation(watched, target, deadline, now,
            epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
        return true
    elseif gun and runtime.config.RemoteAttack then
        -- The controller refused this attempt (usually a reload or cooldown).
        -- It must not be bypassed with a raw tool activation.
        runtime.state.attackNextAt = now + math.max(delay, 0.1)
        return false
    elseif runtime.state.attackRegistered then
        -- RegisterAttack succeeded even when the hit transmission failed or
        -- only partly succeeded. The swing is already registered with the
        -- server, so tool:Activate would register a second attack in the
        -- same window. Wait for the next cadence instead.
        runtime.state.attackNextAt = now + delay
        runtime.state.lastAttack = now
        runtime.state.attackFallback = false
        local deadline = now + math.min(2.5, math.max(0.7, animLength * 0.8 + 0.2))
        runtime.startAttackConfirmation(watched, target, deadline, now,
            epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
        return true
    end

    if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
    local deadline = now + math.max(0.35, math.min(1, delay + 0.2))
    runtime.startAttackConfirmation(watched, target, deadline, now,
        epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
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

-- Auto Saber can be enabled while ordinary farming is off. In that mode the
-- normal farm path must not be used as a fallback: it would select and attack
-- an unrelated mob. This path owns only the exact Saber boss named by the
-- current puzzle stage, while reusing the same weapon, movement and official
-- attack confirmation systems as the normal farm.
runtime.runSaberCombat = function(root)
    if not root or not runtime.state.saberActive then return false end
    local wanted = runtime.state.saberTarget
    if type(wanted) ~= "string" or wanted == "" then return false end

    local target = nil
    local wantedLower = wanted:lower()
    for _, candidate in ipairs(collectEnemies(tick())) do
        if candidate.Name:lower() == wantedLower then
            target = candidate
            break
        end
    end
    if not target then
        runtime.state.status = "Saber: waiting for " .. wanted
        return false
    end

    local targetHum = target:FindFirstChildOfClass("Humanoid")
    local er = anchorOf(target)
    if not targetHum or targetHum.Health <= 0 or not er then return true end

    local tool = equipWeapon()
    if not tool or isFruit(tool) then
        runtime.state.status = "Saber: no usable weapon"
        return true
    end

    local reach = attackRange(tool)
    local hover = runtime.config.HoverHeight
    if reach <= runtime.config.MeleeRange and not runtime.config.RemoteAttack then
        hover = math.min(hover, runtime.config.MeleeHover)
    end

    local head = target:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        head = nil
        for _, descendant in ipairs(target:GetDescendants()) do
            if descendant:IsA("BasePart")
                and descendant.Name:lower():find("head", 1, true) then
                head = descendant
                break
            end
        end
    end

    local hoverPos
    if head then
        local above = runtime.config.RemoteAttack
            and math.max(hover, runtime.config.HeadHover) or runtime.config.HeadHover
        hoverPos = head.Position + Vector3.new(0, above, 0)
    else
        hoverPos = er.Position + Vector3.new(0, hover, 0)
    end
    local top = er.Position.Y + (er.Size and er.Size.Y or 0) / 2
    hoverPos = Vector3.new(hoverPos.X, math.max(hoverPos.Y, top - 1), hoverPos.Z)

    -- The Saber target is never carried with an ordinary mob pack. The safe
    -- tween ring is still used when it is enabled, so the boss fight uses the
    -- same movement speed and ownership rules as the rest of the script.
    if runtime.config.Dodge and runtime.config.RemoteAttack then
        runtime.tweenFarmSlot(target, er.Position, root, false, hoverPos.Y)
    else
        runtime.travelTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))
    end

    local dx = root.Position.X - er.Position.X
    local dz = root.Position.Z - er.Position.Z
    local swingFlat = math.sqrt(dx * dx + dz * dz)
    if runtime.config.BigHitbox and swingFlat <= reach then
        enlargeHitbox(target)
    elseif runtime.state.hitboxPart then
        restoreHitbox()
    end

    local now = tick()
    if runtime.config.AutoAttack
        and (not runtime.state.attackNextAt or now >= runtime.state.attackNextAt)
        and swingFlat <= reach then
        if doAttack(tool, target) then
            runtime.state.lastAttack = now
            runtime.state.status = "Hitting " .. target.Name
        end
    elseif swingFlat > reach then
        runtime.state.status = "Saber: approaching " .. target.Name
    end
    return true
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

-- Pole mastery is passive in the game: the server awards mastery from real
-- Pole hits. The mode therefore keeps one Pole equipped and reports the
-- tool's own mastery level instead of inventing a direct upgrade RPC.
runtime.findPole = function()
    local containers = {}
    local char = LocalPlayer.Character
    if char then table.insert(containers, char) end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then table.insert(containers, backpack) end
    for _, container in ipairs(containers) do
        for _, tool in ipairs(container:GetChildren()) do
            -- Name-only matching accepts any client-created Tool containing
            -- "pole". Use the official physical ItemIds for both mastery forms;
            -- their active movesets are 1132 and 1193 respectively.
            local itemId = tool:GetAttribute("ItemId")
            if tool:IsA("Tool") and (itemId == 51 or itemId == 121) then
                return tool
            end
        end
    end
    return nil
end

runtime.readToolMastery = function(tool)
    if not tool then return nil, nil end
    -- The current client exposes the mastery level as the tool's Level value.
    -- Other attributes such as Mastery or Data.Stars may describe a different
    -- value and must not be used as the current level.
    local level = tool:GetAttribute("Level")
    local exp = tool:GetAttribute("Exp") or tool:GetAttribute("Experience")
    if level == nil then
        local value = tool:FindFirstChild("Level")
        if value and type(value.Value) == "number" then level = value.Value end
    end
    if exp == nil then
        local value = tool:FindFirstChild("Exp")
        if value and type(value.Value) == "number" then exp = value.Value end
    end
    return tonumber(level), tonumber(exp)
end

runtime.equipPole = function()
    local char = LocalPlayer.Character
    local hum = getHumanoid()
    local pole = runtime.findPole()
    if runtime.state.poleWeapon and runtime.state.poleWeapon ~= pole then
        runtime.resetPoleState()
    end
    runtime.state.poleEquipped = false
    if not char or not hum or not pole then return nil end
    if pole.Parent ~= char then
        pcall(function() hum:EquipTool(pole) end)
        if pole.Parent ~= char then
            pcall(function() pole.Parent = char end)
        end
    end
    if pole.Parent ~= char then return nil end
    runtime.state.poleWeapon = pole
    if runtime.state.attackWeapon ~= pole then
        runtime.state.attackWeapon = pole
        runtime.state.attackCombo = 0
        runtime.state.attackComboAt = 0
        runtime.state.attackNextAt = 0
    end
    local level, exp = runtime.readToolMastery(pole)
    level, exp = level or 0, exp or 0
    if level > (runtime.state.poleLevel or 0) then
        runtime.state.poleLevel = level
        runtime.state.poleExp = exp
        runtime.state.poleProgressAt = tick()
    elseif exp > (runtime.state.poleExp or 0) then
        runtime.state.poleExp = exp
        runtime.state.poleProgressAt = tick()
    end
    runtime.state.poleEquipped = true
    return pole
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

-- The fruit ESP uses separate visual objects and leaves the proven pickup
-- scanner above untouched. Highlights and billboards are destroyed as soon as
-- the fruit disappears or the bot is reset.
runtime.worldFruits = function()
    local list = {}
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local function consider(obj)
        if isFruitTool(obj) then
            if not (char and obj:IsDescendantOf(char))
                and not (backpack and obj:IsDescendantOf(backpack)) then
                table.insert(list, obj)
            end
        end
    end
    local function walk(container, depth)
        for _, obj in ipairs(container:GetChildren()) do
            consider(obj)
            if depth > 0 and (obj:IsA("Folder") or obj:IsA("Model"))
                and inContainerName(obj.Name) then
                walk(obj, depth - 1)
            end
        end
    end
    walk(Workspace, 3)
    return list
end

runtime.fruitRarity = function(fruit)
    local attr = fruit:GetAttribute("Rarity") or fruit:GetAttribute("Quality")
        or fruit:GetAttribute("FruitRarity")
    if attr ~= nil then return tostring(attr) end
    if fruit:GetAttribute("IsGodly") == true then return "Godly" end
    if fruit:GetAttribute("IsMystery") == true then return "Mystery" end
    local name = fruit.Name:lower()
    if name:find("mystery", 1, true) then return "Mystery" end
    if name:find("legendary", 1, true) then return "Legendary" end
    if name:find("rare", 1, true) then return "Rare" end
    return "Devil Fruit"
end

runtime.fruitEspColor = function(rarity)
    local r = tostring(rarity):lower()
    if r:find("godly", 1, true) or r:find("legendary", 1, true) then
        return Color3.fromRGB(255, 205, 70)
    elseif r:find("mystery", 1, true) or r:find("epic", 1, true) then
        return Color3.fromRGB(190, 100, 255)
    elseif r:find("rare", 1, true) then
        return Color3.fromRGB(85, 170, 255)
    end
    return Color3.fromRGB(105, 220, 135)
end

runtime.destroyFruitEsp = function()
    local visuals = runtime.state and runtime.state.fruitEspVisuals
    if not visuals then return end
    for fruit, visual in pairs(visuals) do
        visuals[fruit] = nil
        if visual then
            pcall(function() visual.highlight:Destroy() end)
            pcall(function() visual.billboard:Destroy() end)
        end
    end
end

runtime.notifyFruit = function(fruit)
    local s = runtime.state
    if not runtime.config.FruitNotifier then return end
    local url = tostring(runtime.config.FruitWebhook or "")
    if url == "" then return end
    if s.notifiedFruitUrls[fruit] == url then return end
    local now = tick()
    local pending = s.fruitNotificationPending[fruit]
    if pending and pending.inFlight then return end
    if pending and pending.url == url and now < (pending.nextAt or 0) then return end

    local rarity = runtime.fruitRarity(fruit)
    if not pending then
        dbg("Devil fruit spotted: " .. fruit.Name .. " (" .. rarity .. ")")
    end
    local body = HttpService:JSONEncode({
        content = "Blox Fruits: " .. fruit.Name .. " (" .. rarity .. ") spotted",
        username = "Blox Fruits Fruit Notifier",
    })
    pending = {
        url = url,
        body = body,
        attempts = pending and pending.attempts or 0,
        nextAt = 0,
        inFlight = true,
    }
    s.fruitNotificationPending[fruit] = pending

    task.spawn(function()
        local ok, first, second = pcall(function()
            if request then
                return request({
                    Url = url,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = body,
                })
            elseif http_request then
                return http_request(url, "POST", body, {["Content-Type"] = "application/json"})
            end
            return false
        end)
        local success = false
        if ok then
            if type(first) == "boolean" then
                success = first and (type(second) ~= "number"
                    or (second >= 200 and second < 300))
            elseif type(first) == "number" then
                success = first >= 200 and first < 300
            end
        end
        local current = s.fruitNotificationPending[fruit]
        if current ~= pending then return end
        -- The destination may have changed while the request was in flight.
        -- A late success for the old URL must not mark the fruit as already
        -- notified for the new destination.
        if pending.url ~= tostring(runtime.config.FruitWebhook or "") then
            pending.inFlight = false
            pending.nextAt = 0
            return
        end
        if not runtime.config.FruitNotifier then
            pending.inFlight = false
            pending.nextAt = 0
            return
        end
        if success then
            s.fruitNotificationPending[fruit] = nil
            s.notifiedFruits[fruit] = true
            s.notifiedFruitUrls[fruit] = url
            dbg("Fruit notification sent for " .. fruit.Name)
            return
        end
        pending.inFlight = false
        pending.attempts = (pending.attempts or 0) + 1
        local backoff = math.min(60, 5 * (2 ^ math.min(pending.attempts - 1, 4)))
        pending.nextAt = tick() + backoff
        dbg("Fruit notification failed for " .. fruit.Name
            .. "; retrying in " .. tostring(math.floor(backoff)) .. "s")
    end)
end

runtime.updateFruitEsp = function()
    local s = runtime.state
    if not runtime.config.FruitESP and not runtime.config.FruitNotifier then
        if next(s.fruitEspVisuals) ~= nil then runtime.destroyFruitEsp() end
        return
    end
    if not runtime.config.FruitESP and next(s.fruitEspVisuals) ~= nil then
        runtime.destroyFruitEsp()
    end

    local fruits = runtime.worldFruits()
    local live = {}
    for _, fruit in ipairs(fruits) do
        live[fruit] = true
        if runtime.config.FruitESP then
            local rarity = runtime.fruitRarity(fruit)
            local visual = s.fruitEspVisuals[fruit]
            local handle = toolPart(fruit)
            if not handle then
                if visual then
                    pcall(function() visual.highlight:Destroy() end)
                    pcall(function() visual.billboard:Destroy() end)
                    s.fruitEspVisuals[fruit] = nil
                end
            elseif not visual then
                local highlight = Instance.new("Highlight")
                highlight.Adornee = handle
                highlight.FillTransparency = 0.25
                highlight.OutlineTransparency = 0.05
                highlight.DepthMode = Enum.HighlightDepthMode.Occluded
                highlight.Parent = handle
                local billboard = Instance.new("BillboardGui")
                billboard.Size = UDim2.fromOffset(170, 34)
                billboard.StudsOffset = Vector3.new(0, 3.2, 0)
                billboard.AlwaysOnTop = true
                billboard.MaxDistance = tonumber(runtime.config.FruitScanRadius) or 5000
                billboard.Parent = handle
                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.Text = fruit.Name .. "\n" .. rarity .. " • Devil Fruit"
                label.TextColor3 = runtime.fruitEspColor(rarity)
                label.TextStrokeTransparency = 0.35
                label.Font = Enum.Font.GothamBold
                label.TextSize = 12
                label.TextWrapped = true
                label.Parent = billboard
                visual = {highlight = highlight, billboard = billboard}
                s.fruitEspVisuals[fruit] = visual
            end
        end
        if runtime.config.FruitNotifier then runtime.notifyFruit(fruit) end
    end
    for fruit, visual in pairs(s.fruitEspVisuals) do
        if not live[fruit] then
            s.fruitEspVisuals[fruit] = nil
            pcall(function() visual.highlight:Destroy() end)
            pcall(function() visual.billboard:Destroy() end)
        end
    end
end

table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(0.5)
        if not runtime.isCurrent() then return end
        local ok, err = pcall(runtime.updateFruitEsp)
        if not runtime.isCurrent() then return end
        if not ok then dbg("Fruit ESP error: " .. tostring(err)) end
    end
end))

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
            -- An equipped current-fruit moveset can also have the official
            -- "Blox Fruit" tooltip. It is not a newly carried physical fruit
            -- and must never be sent to the storage dialogue/remote.
            local originalName = t:GetAttribute("OriginalName")
            if t:IsA("Tool") and isFruit(t)
                and type(originalName) == "string" and originalName ~= "" then
                table.insert(list, t)
            end
        end
    end
    return list
end

-- ItemReplication is the official server-published inventory state. A store
-- request is not successful merely because its remote returned without an
-- error: the same physical ItemId must newly appear in that inventory.
local function fruitInventorySnapshot(tool)
    local itemId = tonumber(tool and tool:GetAttribute("ItemId"))
    if not itemId then return nil end
    local util = ReplicatedStorage:FindFirstChild("Util")
    local module = util and util:FindFirstChild("ItemReplication")
    if not module then return nil end
    local ok, replication = pcall(function() return require(module) end)
    if not ok or type(replication) ~= "table" then return nil end
    local function read(field)
        local reader = replication[field]
        if type(reader) ~= "table" or type(reader.readClient) ~= "function" then
            return nil
        end
        local success, value = pcall(function() return reader.readClient(itemId) end)
        if not success then return nil end
        return value
    end
    return {
        itemId = itemId,
        owned = read("IsOwned"),
        equipped = read("IsEquipped"),
        quantity = read("Quantity"),
    }
end

local function fruitInventoryShowsStore(before, after)
    if not before or not after then return false end
    if after.owned ~= true then return false end
    if type(after.quantity) ~= "number" or after.quantity < 1 then return false end
    if before.owned ~= true then return true end
    return type(before.quantity) == "number"
        and type(after.quantity) == "number"
        and after.quantity > before.quantity
end

local function toolIsInside(tool, container)
    if not tool or not container then return false end
    local ok, inside = pcall(function() return tool:IsDescendantOf(container) end)
    return ok and inside or false
end

local function confirmFruitStored(tool, char, backpack, inventoryBefore)
    local epoch = runtime.characterEpoch
    for _ = 1, 30 do
        local inCharacter = toolIsInside(tool, char)
        local inBackpack = toolIsInside(tool, backpack)
        local inventoryAfter = fruitInventorySnapshot(tool)
        if not inCharacter and not inBackpack
            and fruitInventoryShowsStore(inventoryBefore, inventoryAfter) then
            return true
        end
        task.wait(0.1)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    return false
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
    local hum = getHumanoid()
    local epoch = runtime.characterEpoch
    if not char or not hum then return false end

    -- The official fruit dialogue stores the equipped tool. Equip it first so
    -- the server sees the same tool object that it expects in the request.
    if tool.Parent ~= char then
        local equipped = pcall(function() hum:EquipTool(tool) end)
        if not equipped then return false end
        task.wait(0.1)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    if tool.Parent ~= char then
        dbg("Could not equip " .. tool.Name .. " for storage")
        return false
    end

    -- The game stores a fruit itself when the remote gets the tool: the server
    -- moves it into the bank at once. This is the path the hubs use; the GUI
    -- of the storage npc is only the fallback for builds without the remote.
    -- Capture the official server-published inventory before the request. A
    -- successful request must produce a new inventory entry for this exact
    -- physical ItemId in addition to moving the exact tool out of both carry
    -- containers.
    local inventoryBefore = fruitInventorySnapshot(tool)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if commF then
        -- The official signature is StoreFruit(OriginalName, Tool). Sending
        -- only the tool, or only the display name, is silently refused and is
        -- the reason the old automatic store never removed a fruit.
        local originalName = tool:GetAttribute("OriginalName") or tool.Name
        local called, reply = pcall(function()
            return commF:InvokeServer("StoreFruit", originalName, tool)
        end)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
        if not called then
            dbg("The store remote failed for " .. tool.Name)
            return false
        end
        if reply == false then
            dbg("The game refused to store " .. tool.Name)
            return false
        end
        if type(reply) == "number" then
            dbg("Fruit storage is full (capacity " .. tostring(reply) .. ")")
            return false
        end
        if confirmFruitStored(tool, char, backpack, inventoryBefore) then
            dbg("Stored " .. tool.Name)
            return true
        end
        dbg("The store remote did not take " .. tool.Name)
        return false
    end
    local used = useFruitMenu(tool.Name, {"store", "deposit", "stash"})
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if used and confirmFruitStored(tool, char, backpack, inventoryBefore) then
        dbg("Stored " .. tool.Name)
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
    if runtime.state.travelActive then return false end
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

-- The current world is read from the game's own Realm service. The guide
-- contains quest lines from every sea, so aggregating it can report the
-- highest sea even while the character is still in the First Sea.
runtime.detectCurrentSea = function()
    local operationEpoch = runtime.operationEpoch
    local characterEpoch = runtime.characterEpoch
    runtime.state.seaDetectionToken = (runtime.state.seaDetectionToken or 0) + 1
    local detectionToken = runtime.state.seaDetectionToken
    local detected = nil
    local util = ReplicatedStorage:FindFirstChild("Util")
    local realm = util and util:FindFirstChild("Realm")
    if not realm then realm = ReplicatedStorage:FindFirstChild("Realm") end
    if realm then
        pcall(function()
            local realmModule = require(realm)
            local getter = realmModule and realmModule.getCurrentSeaAsync
            if type(getter) == "function" then
                local ok, sea = pcall(getter, realmModule)
                if ok then
                    if sea == "Sea1" then detected = 1
                    elseif sea == "Sea2" then detected = 2
                    elseif sea == "Sea3" then detected = 3
                    end
                end
            end
        end)
    end
    -- A fresh Realm result is authoritative. In particular, nil means that
    -- the official lookup cannot identify the current realm; a stale Map model
    -- must not turn that unknown state into a confirmed sea.
    -- The Realm lookup can yield. Do not let a stale lookup write the sea of
    -- a reset or a new character into the current runtime. A stale or unknown
    -- lookup returns nil; the cached sea is not proof that this lookup saw the
    -- current world.
    if runtime.operationEpoch == operationEpoch
        and runtime.characterEpoch == characterEpoch
        and runtime.state.seaDetectionToken == detectionToken
        and runtime.isCurrent() then
        runtime.state.currentSea = detected
        runtime.state.currentSeaAt = detected and tick() or 0
        return detected
    end
    return nil
end

-- The seas are separate places: the game moves the whole character between
-- them, and the remotes are the ones BananaHub uses. The request is owned by
-- the movement lock, uses the operation epoch, and is only successful after
-- the destination world is visible.
runtime.travelToWorld = function(world, selectionGuard)
    local what = WORLD_TRAVEL[world]
    if not what then return false end
    local function guardValid()
        return type(selectionGuard) ~= "function" or selectionGuard() == true
    end
    if not guardValid() then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    if runtime.state.travelActive then
        dbg("A world travel is already running")
        return false
    end
    local acquired, movementToken = runtime.acquireMovement("travel")
    if not acquired then
        dbg("Another movement operation is already running")
        return false
    end
    local token = (runtime.state.travelToken or 0) + 1
    runtime.state.travelToken = token
    runtime.state.travelActive = true
    runtime.state.travelMovementToken = movementToken
    runtime.state.blockAt = tick()
    runtime.stopTween()
    local function finishTravel()
        if runtime.state.travelToken == token then
            runtime.state.travelActive = false
            runtime.state.travelMovementToken = nil
        end
        runtime.releaseMovement("travel", movementToken)
    end
    local currentSea = runtime.detectCurrentSea()
    if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
        finishTravel()
        return false
    end
    if not currentSea then
        local detected = nil
        for _ = 1, 3 do
            if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
                finishTravel()
                return false
            end
            detected = runtime.detectCurrentSea()
            if detected then break end
            task.wait(0.05)
        end
        currentSea = detected
        if not currentSea then
            finishTravel()
            dbg("The current sea could not be confirmed")
            return false
        end
    end
    if currentSea == world then
        finishTravel()
        dbg("Already in world " .. tostring(world))
        return true
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        finishTravel()
        dbg("CommF_ remote missing")
        return false
    end

    -- The Second and Third Sea captains first verify their own quest line.
    -- Calling the travel remote without that step is refused by the server.
    if world == 2 or world == 3 then
        local progressRemote = world == 2 and "DressrosaQuestProgress" or "ZQuestProgress"
        local progressWorld = world == 2 and "Dressrosa" or "Zou"
        local progressOk, progress = pcall(function()
            return commF:InvokeServer(progressRemote, progressWorld)
        end)
        if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
            finishTravel()
            return false
        end
        if not progressOk or progress ~= 0 then
            finishTravel()
            dbg("The game did not unlock travel to world " .. tostring(world))
            return false
        end
    end

    if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
        finishTravel()
        return false
    end
    local ok, reply = pcall(function() return commF:InvokeServer(what) end)
    -- A world change may replace the character and reset the operation epoch.
    -- The travel token is the ownership of this request; resetFeatureState
    -- invalidates it on disable, respawn or teardown.
    if not runtime.isCurrent() or runtime.state.travelToken ~= token
        or not runtime.state.enabled or not guardValid() then
        finishTravel()
        return false
    end
    if not ok then
        finishTravel()
        dbg("The game did not take the travel to world " .. tostring(world))
        return false
    end
    local message = ""
    if type(reply) == "table" then
        for _, part in ipairs(reply) do message = message .. tostring(part) end
    elseif type(reply) == "string" then
        message = reply
    end
    local lower = message:lower()
    if lower:find("cannot", 1, true) or lower:find("not allowed", 1, true)
        or lower:find("failed", 1, true) or lower:find("error", 1, true) then
        finishTravel()
        dbg("Travel to world " .. tostring(world) .. " was refused: " .. message)
        return false
    end

    dbg("Travelling to world " .. tostring(world))
    local deadline = tick() + 20
    while tick() < deadline do
        runtime.state.blockAt = tick()
        if runtime.state.travelToken ~= token then break end
        if not runtime.isCurrent() or not runtime.state.enabled or not guardValid() then break end
        local sea = runtime.detectCurrentSea()
        if not runtime.operationValid(operationEpoch, epoch, char)
            or runtime.state.travelToken ~= token or not guardValid() then
            break
        end
        if sea == world then
            if not guardValid() then break end
            runtime.refreshQuestData()
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.travelToken ~= token or not guardValid() then
                break
            end
            runtime.state.currentSea = world
            runtime.state.questTryKey = nil
            runtime.state.questTried = {}
            runtime.state.questIndexTry = nil
            runtime.state.currentQuest = nil
            runtime.state.questVerified = false
            runtime.state.questAsked = nil
            if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
            finishTravel()
            dbg("Arrived in world " .. tostring(world))
            return true
        end
        task.wait(0.25)
    end
    finishTravel()
    dbg("Travel to world " .. tostring(world) .. " was not confirmed")
    return false
end

-- ================= FLY TO AN ISLAND =================

-- Some islands cannot be tweened to at all (the sea floor, the islands the
-- game only opens through a door). For those the game itself is asked to move
-- the player. The remotes are the ones BananaHub uses.
-- Fly to a place with the tween of the script: no jump, no portal, just a
-- straight tween across the sea, like the player would glide over.
local function flyTo(position, owner)
    owner = owner or "flight"
    local root = getRoot()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not root or not position or not char then return false end
    if runtime.state.flying then
        dbg("Already flying to an island")
        return false
    end
    -- Shop and Saber own long movements exclusively. A shop-owned whirlpool
    -- flight is the only flight allowed while a purchase is walking, and a
    -- Saber flight is the only one allowed while the puzzle is active.
    if (runtime.state.shopping or runtime.state.shopInFlight) and owner ~= "shop" then
        dbg("A shopping request owns the movement")
        return false
    end
    if runtime.state.saberActive and owner ~= "saber" then
        dbg("Saber owns the movement")
        return false
    end
    local alreadyOwned = runtime.state.movementOwner == owner
    local acquired, movementToken = runtime.acquireMovement(owner)
    if not acquired then
        dbg("Another movement operation is already running")
        return false
    end

    local flightToken = (runtime.state.flightToken or 0) + 1
    runtime.state.flightToken = flightToken
    runtime.state.flightOwner = owner
    runtime.state.flightMovementToken = movementToken
    runtime.state.flying = true
    runtime.state.blockAt = tick()
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
                if runtime.state.flightToken ~= flightToken then
                    stale = true
                    break
                end
                if not runtime.operationValid(operationEpoch, epoch, char) then
                    stale = true
                    break
                end
            end
            if stale then break end
        end
    end)
    -- Only the flight that still owns the token may clear the shared flag. An
    -- old, timed-out coroutine must never clear a newer flight's state.
    local ownsFlight = runtime.state.flightToken == flightToken
    if ownsFlight then
        runtime.state.flying = false
        runtime.state.flightOwner = nil
        runtime.state.flightMovementToken = nil
        -- A shop or Saber flight is nested inside an operation that already
        -- owns the lock. Only a standalone flight releases that owner here.
        if not alreadyOwned then runtime.releaseMovement(owner, movementToken) end
        if runtime.operationValid(operationEpoch, epoch, char) then
            runtime.setWalking()
        end
        runtime.releaseTweenHold()
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
    {name = "Dark Step",       remote = "BuyBlackLeg",       teacher = "Dark Step Teacher",
        toolNames = {"Black Leg", "BlackLeg"},
        checkOwnedReply = 1,
        level = 100, cost = 150000},
    {name = "Electric",        remote = "BuyElectro",        teacher = "Mad Scientist",
        toolNames = {"Electro"},
        checkOwnedReply = 1, checkRefusalReplies = {3, 4},
        level = 150, item = "Lightning Bolt", cost = 500000},
    {name = "Water Kung Fu",   remote = "BuyFishmanKarate",  teacher = "Water Kung Fu Teacher",
        toolNames = {"Fishman Karate", "Water Kung Fu", "WaterKungFu"},
        checkOwnedReply = 1,
        readinessRemote = "CheckFishmanKarate", readinessArgs = {},
        level = 450, cost = 750000},
    {name = "Dragon Breath",   remote = "BlackbeardReward",  teacher = "Sabi",
        -- Sabi uses a two-argument BlackbeardReward protocol.  The check
        -- reply 1 means that the style is known; 0 is the ordinary
        -- not-owned answer and is still a valid request to buy.
        checkArgs = {"DragonClaw", "1"}, buyArgs = {"DragonClaw", "2"},
        checkOwnedReply = 1,
        toolNames = {"Dragon Breath", "Dragon Claw", "DragonBreath", "DragonClaw"},
        level = 450, fragments = 1500},
    {name = "Superhuman",      remote = "BuySuperhuman",     teacher = "Martial Arts Master",
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 300, cost = 3000000,
        masteries = {
            {style = "Dark Step", level = 300},
            {style = "Electric", level = 300},
            {style = "Water Kung Fu", level = 300},
            {style = "Dragon Breath", level = 300},
        }},
    {name = "Death Step",      remote = "BuyDeathStep",      teacher = "Phoeyu, the Reformed",
        toolNames = {"DeathStep"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 450, fragments = 5000,
        items = {{name = "Library Key", count = 1}},
        needs = "Dark Step", mastery = 400, cost = 2500000},
    {name = "Electric Claw",   remote = "BuyElectricClaw",   teacher = "Previous Hero",
        toolNames = {"ElectricClaw"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        -- The official Previous Hero dialogue sends reply 4 to a short
        -- mansion trial and then calls BuyElectricClaw("Start").
        trialReply = 4, trialArgs = {"Start"},
        level = 1000, fragments = 5000,
        needs = "Electric", mastery = 400, cost = 3000000},
    {name = "Sharkman Karate", remote = "BuySharkmanKarate", teacher = "Sharkman Teacher",
        toolNames = {"SharkmanKarate"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 1000, fragments = 5000,
        items = {{name = "Water Key", count = 1}},
        needs = "Water Kung Fu", mastery = 400, cost = 2500000},
    {name = "Dragon Talon",    remote = "BuyDragonTalon",    teacher = "Uzoth",
        toolNames = {"DragonTalon"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        -- The loaded current place normally refuses this check with reply 3
        -- and does not start a trial. Some servers use the reply-4 handshake
        -- found on the Electric Claw teacher, so trial support is activated
        -- only when that exact reply is received.
        trialReply = 4, trialArgs = {"Start"},
        level = 1500, fragments = 5000,
        items = {{name = "Fire Essence", count = 1}},
        needs = "Dragon Breath", mastery = 400, cost = 3000000},
    {name = "Godhuman",        remote = "BuyGodhuman",       teacher = "Ancient Monk",
        toolNames = {"Godhuman"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 3000, fragments = 5000,
        items = {
            {name = "Dragon Scale", count = 10},
            {name = "Fish Tail", count = 20},
            {name = "Mystic Droplet", count = 10},
            {name = "Magma Ore", count = 20},
        },
        masteries = {
            {style = "Superhuman", level = 400},
            {style = "Death Step", level = 400},
            {style = "Sharkman Karate", level = 400},
            {style = "Electric Claw", level = 400},
            {style = "Dragon Talon", level = 400},
        }, cost = 5000000},
    {name = "Sanguine Art",    remote = "BuySanguineArt",    teacher = "Shafi",
        toolNames = {"SanguineArt"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 3000, fragments = 5000,
        items = {
            {name = "Leviathan Heart", count = 1},
            {name = "Demonic Wisp", count = 20},
            {name = "Vampire Fang", count = 20},
            {name = "Dark Fragment", count = 2},
        }, cost = 5000000},
    {name = "Advanced Combat", remote = "SetSecretStyle",    teacher = "Secrets Master",
        checkArgs = false, buyArgs = {"Advanced Combat"},
        level = 1100},
}

-- The item a teacher asks for is carried as a tool or kept as a value of the
-- player data: the backpack, the hand and the values are all looked at.
-- The money of the player, wherever this build keeps it: the folder of the
-- player data, a leaderstat or a plain value on the player are all looked at.
-- When none of them is there the number is nil; a paid purchase refuses to
-- start until the real balance can be read.
myBeli = function()
    local player = LocalPlayer
    if not player then return nil end
    local v = nil
    local function read(obj)
        if type(obj) == "number" then return obj end
        return readNumber(obj)
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

-- Fragments are a currency in Data.Fragments. They are not ordinary carried
-- items, so a name search would incorrectly count Fragment Elixir, a Fragment
-- Chest or a Dark Fragment as spendable currency.
runtime.fragmentCount = function()
    local data = LocalPlayer:FindFirstChild("Data")
    local fragments = data and data:FindFirstChild("Fragments")
    local value = readNumber(fragments)
    if type(value) == "number" then return value end
    local attribute = LocalPlayer:GetAttribute("Fragments")
    value = tonumber(attribute)
    if type(value) == "number" then return value end
    return nil
end

runtime.itemCount = function(name)
    local wanted = tostring(name or ""):lower()
    if wanted == "" then return 0 end
    local count = 0
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, folder in ipairs({char, backpack}) do
        if folder then
            for _, item in ipairs(folder:GetChildren()) do
                if item.Name:lower() == wanted then count = count + 1 end
            end
        end
    end
    pcall(function()
        for _, d in ipairs(LocalPlayer:GetDescendants()) do
            local matches = d.Name:lower() == wanted
            if matches then
                if d:IsA("NumberValue") or d:IsA("IntValue") then
                    count = math.max(count, tonumber(d.Value) or 0)
                elseif d:IsA("StringValue") and d.Value ~= nil
                    and d.Value ~= "" and d.Value ~= false then
                    count = math.max(count, 1)
                end
            end
        end
    end)
    return count
end

hasItem = function(name)
    return runtime.itemCount(name) > 0
end

runtime.styleDefinition = function(name)
    local wanted = tostring(name or ""):lower()
    for _, style in ipairs(STYLE_SHOP) do
        if style.name:lower() == wanted then return style end
    end
    return nil
end

runtime.styleNames = function(style)
    local names = {style.name}
    for _, name in ipairs(style.toolNames or {}) do table.insert(names, name) end
    return names
end

runtime.styleTool = function(style)
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, container in ipairs({char, backpack}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    for _, name in ipairs(runtime.styleNames(style)) do
                        if tool.Name:lower() == name:lower() then return tool end
                    end
                end
            end
        end
    end
    return nil
end

runtime.styleModuleOwned = function(style)
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local modules = gui and gui:FindFirstChild("MovesetModules")
    if not modules then return false end
    for _, name in ipairs(runtime.styleNames(style)) do
        if modules:FindFirstChild(name) then return true end
    end
    return false
end

runtime.styleMastery = function(style)
    local tool = runtime.styleTool(style)
    local level = runtime.readToolMastery(tool)
    if type(level) == "number" then return level end
    -- Data.Stars stores unused mastery points, not the current mastery level.
    -- Returning it here could make an unmastered prerequisite look ready.
    return nil
end

runtime.styleItemRequirements = function(style)
    local requirements = {}
    if style.item then
        table.insert(requirements, {
            name = style.item,
            required = tonumber(style.itemCount) or 1,
        })
    end
    for _, item in ipairs(style.items or {}) do
        table.insert(requirements, {
            name = item.name,
            required = tonumber(item.count) or 1,
        })
    end
    return requirements
end

runtime.styleMasteryRequirements = function(style)
    local requirements = {}
    if style.needs then
        table.insert(requirements, {
            style = style.needs,
            required = tonumber(style.mastery) or 0,
        })
    end
    for _, mastery in ipairs(style.masteries or {}) do
        table.insert(requirements, {
            style = mastery.style,
            required = tonumber(mastery.level) or 0,
        })
    end
    return requirements
end

runtime.styleCheck = function(commF, style)
    if not commF or not style or style.checkArgs == false then return nil, false end
    local args = style.checkArgs or {true}
    local ok, reply = pcall(function()
        return commF:InvokeServer(style.remote, table.unpack(args))
    end)
    if not ok then return nil, false end
    return reply, true
end

runtime.styleCheckReply = function(commF, style)
    local reply = runtime.styleCheck(commF, style)
    return reply
end

local function styleReplyIsRefusal(style, reply)
    if type(reply) == "string" or reply == false then return true end
    for _, refusal in ipairs(style and style.checkRefusalReplies or {}) do
        if reply == refusal then return true end
    end
    return false
end

-- A style check has more than two answers. Reply 1 is ownership, a listed
-- numeric reply is a hard refusal, a string is the teacher's refusal text,
-- and a style-specific trial reply means that the normal buy must not be
-- sent until the trial handshake has been handled.
runtime.styleOwnershipState = function(commF, style)
    if not style then return "unknown" end
    if runtime.styleModuleOwned(style) or runtime.styleTool(style) then return "owned" end
    if style.checkArgs == false then return "not-owned" end
    local reply, ok = runtime.styleCheck(commF, style)
    if not ok or reply == nil then return "unknown" end
    local ownedReply = style.checkOwnedReply
    if ownedReply == nil then ownedReply = 1 end
    if reply == ownedReply then return "owned" end
    if style.trialReply ~= nil and reply == style.trialReply then return "trial" end
    if styleReplyIsRefusal(style, reply) then return "refused" end
    return "not-owned"
end

runtime.styleOwned = function(commF, style)
    return runtime.styleOwnershipState(commF, style) == "owned"
end

-- Some teachers expose a separate server-side readiness check. The game
-- treats a false answer as a hard refusal, so the bot must not walk to that
-- teacher or send its buy after a failed check.
runtime.styleReady = function(commF, style)
    if not style or not style.readinessRemote then return true end
    local ok, reply = pcall(function()
        return commF:InvokeServer(style.readinessRemote, table.unpack(style.readinessArgs or {}))
    end)
    if not ok then
        dbg("Auto buy: the readiness check for " .. style.name .. " failed")
        return false
    end
    if reply == true or reply == 1 then return true end
    dbg("Auto buy: " .. style.name .. " is not ready (reply " .. tostring(reply) .. ")")
    return false
end

runtime.styleBuyArgs = function(style)
    if not style then return {} end
    return style.buyArgs or {}
end

local function shopRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_")
end

-- Team selection uses the official SetTeam2 request. Reply 0 is the only
-- success; a non-zero reply means that the server refused the change.
runtime.setTeam = function(team)
    team = tostring(team or "None")
    if team ~= "Pirates" and team ~= "Marines" and team ~= "None" then
        dbg("Unknown team: " .. team)
        return false
    end
    if team == "None" then
        -- Clearing the selection invalidates a SetTeam2 request that is still
        -- in flight. Its late reply must not put the old team back into the
        -- local state.
        runtime.state.teamToken = (runtime.state.teamToken or 0) + 1
        runtime.state.teamInFlight = false
        runtime.state.currentTeam = "None"
        runtime.config.TeamSelection = "None"
        dbg("Team selection cleared")
        return true
    end
    if runtime.state.teamInFlight then
        dbg("A team request is already running")
        return false
    end
    if runtime.state.codeInFlight then
        dbg("A code request is already running")
        return false
    end
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    local token = (runtime.state.teamToken or 0) + 1
    runtime.state.teamToken = token
    runtime.state.teamInFlight = true
    local function finishTeam()
        if runtime.state.teamToken == token then runtime.state.teamInFlight = false end
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    local ok, reply = pcall(function() return commF:InvokeServer("SetTeam2", team) end)
    if not runtime.operationValid(operationEpoch, epoch, char) then
        finishTeam()
        return false
    end
    if runtime.state.teamToken ~= token then return false end
    if not ok then
        finishTeam()
        dbg("The team request failed")
        return false
    end
    -- The official team UI does not use the remote reply as its result. It
    -- waits until the player is actually placed on the requested team, so the
    -- replicated Team/TeamColor is the proof used here as well.
    local deadline = tick() + 6
    while tick() < deadline do
        if not runtime.operationValid(operationEpoch, epoch, char) then
            finishTeam()
            return false
        end
        if runtime.state.teamToken ~= token then return false end
        local actual = LocalPlayer.Team
        local actualName = actual and actual.Name or ""
        local matches = actualName:lower() == team:lower()
            or (team == "Pirates" and LocalPlayer.TeamColor == Enum.TeamColor.Pirate)
            or (team == "Marines" and LocalPlayer.TeamColor == Enum.TeamColor.Marine)
        if matches then
            runtime.state.currentTeam = team
            runtime.config.TeamSelection = team
            finishTeam()
            dbg("Team changed to " .. team)
            return true
        end
        task.wait(0.1)
    end
    local message = ""
    if type(reply) == "table" then
        for _, part in ipairs(reply) do message = message .. tostring(part) end
    elseif reply ~= nil then
        message = tostring(reply)
    end
    finishTeam()
    dbg("The game did not change the team to " .. team
        .. (message ~= "" and (" (" .. message .. ")") or ""))
    return false
end

-- Code redemption uses the official Redeem remote. The game answers with the
-- exact string "SUCCESS!" or a human-readable error.
runtime.redeemCode = function(code)
    code = tostring(code or ""):match("^%s*(.-)%s*$") or ""
    if code == "" then
        dbg("No redemption code was entered")
        return false
    end
    if #code > 100 then
        dbg("The redemption code is too long")
        return false
    end
    if runtime.state.codeInFlight then
        dbg("A code request is already running")
        return false
    end
    if runtime.state.teamInFlight then
        dbg("A team request is already running")
        return false
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local redeem = remotes and remotes:FindFirstChild("Redeem")
    if not redeem then
        dbg("Redeem remote missing")
        return false
    end
    local token = (runtime.state.codeToken or 0) + 1
    runtime.state.codeToken = token
    runtime.state.codeInFlight = true
    local function finishCode()
        if runtime.state.codeToken == token then runtime.state.codeInFlight = false end
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    local ok, reply = pcall(function() return redeem:InvokeServer(code) end)
    if not runtime.operationValid(operationEpoch, epoch, char) then
        finishCode()
        return false
    end
    if runtime.state.codeToken ~= token then return false end
    finishCode()
    if not ok then
        dbg("The redemption request failed")
        return false
    end
    if reply == "SUCCESS!" then
        dbg("Code redeemed")
        return true
    end
    dbg("Code was not redeemed: " .. tostring(reply or "unknown reply"))
    return false
end

-- Reserve a purchase before its first yielding server check. Without this
-- reservation two requests can both pass the idle guard, yield in preflight,
-- and then send their purchases in the opposite order.
runtime.beginShopRequest = function()
    local s = runtime.state
    if s.shopping or s.shopInFlight then return nil end
    local requestToken = (s.shopToken or 0) + 1
    s.shopToken = requestToken
    s.shopping = true
    s.shopInFlight = false
    return requestToken
end

-- Clear only the purchase that owns this token. An invalidated old request
-- must not clear a newer purchase that has already replaced it.
runtime.finishShopState = function(requestToken)
    if requestToken == nil or runtime.state.shopToken == requestToken then
        runtime.state.shopping = false
        runtime.state.shopInFlight = false
        local movementToken = runtime.state.shopMovementToken
        runtime.state.shopMovementToken = nil
        runtime.releaseMovement("shop", movementToken)
    end
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
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    local pos = runtime.whirlpoolPos()
    if not pos then
        dbg("The whirlpool of the sea was not found")
        return false
    end
    dbg("Flying into the whirlpool of the sea")
    flyTo(pos, "shop")
    if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
            if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            return true
        end
        runtime.travelTo(CFrame.new(pos), true)
        task.wait(0.3)
        if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
    if runtime.state.saberActive or runtime.state.movementOwner == "saber" then
        dbg("Saber owns the movement; the style buy was not started")
        return false
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    local requestToken = runtime.beginShopRequest()
    if not requestToken then
        dbg("A buy is already running")
        return false
    end
    local function requestCurrent()
        return runtime.state.shopToken == requestToken
            and runtime.operationValid(operationEpoch, epoch, char)
    end

    -- Ownership is checked first. A style that is already known must not be
    -- refused because the fragments, items or money used to buy it are gone.
    local ownership = runtime.styleOwnershipState(commF, style)
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end
    if ownership == "owned" then
        runtime.state.shopUnknown[style.remote] = nil
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " is already owned")
        return true
    end
    if ownership == "unknown" then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " could not confirm ownership; no buy was sent")
        return nil
    end
    if ownership == "refused" then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " was refused by the ownership check")
        return false
    end
    local ready = runtime.styleReady(commF, style)
    -- The readiness request can yield.  A reset or respawn during it must
    -- stop this purchase before it acquires a new movement owner.
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end
    if not ready then
        runtime.finishShopState(requestToken)
        return false
    end

    -- What the style needs is checked before the walk: a teacher that will
    -- refuse is a wasted trip, and the player has to see why nothing happened.
    if style.level and getMyLevel() < style.level then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " needs level " .. style.level
            .. ", we are " .. getMyLevel())
        return false
    end
    for _, requirement in ipairs(runtime.styleItemRequirements(style)) do
        local needed = requirement.required
        local have = runtime.itemCount(requirement.name)
        if have < needed then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. needed .. " "
                .. requirement.name .. ", we have " .. have)
            return false
        end
    end
    if style.fragments then
        local needed = tonumber(style.fragments) or 0
        local available = tonumber(runtime.fragmentCount())
        if not available then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. needed
                .. " fragments, but the fragment balance is not available")
            return false
        end
        if available < needed then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. needed
                .. " fragments, we have " .. math.floor(available))
            return false
        end
    end
    for _, requirement in ipairs(runtime.styleMasteryRequirements(style)) do
        local needStyle = runtime.styleDefinition(requirement.style)
        if not needStyle then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " has an unknown prerequisite")
            return false
        end
        local ownership = runtime.styleOwnershipState(commF, needStyle)
        if not requestCurrent() then
            runtime.finishShopState(requestToken)
            return false
        end
        if ownership ~= "owned" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. requirement.style .. " first")
            return false
        end
        local mastery = runtime.styleMastery(needStyle)
        local neededMastery = requirement.required
        if type(mastery) ~= "number" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. requirement.style
                .. " mastery " .. tostring(neededMastery) .. ", but its level is not available")
            return false
        end
        if mastery < neededMastery then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. requirement.style
                .. " mastery " .. tostring(neededMastery) .. ", we have " .. mastery)
            return false
        end
    end
    -- Money first: the walk to the teacher is only worth it when the real
    -- balance can be read and is enough to pay.
    local beli = myBeli()
    if style.cost then
        if type(beli) ~= "number" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " costs " .. style.cost
                .. " Beli, but the Beli balance is not available")
            return false
        end
        if beli < style.cost then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " costs " .. style.cost
                .. " Beli, we have " .. math.floor(tonumber(beli) or 0))
            return false
        end
    end
    -- An unknown reply is not a refusal, but it is also not permission to send
    -- the same purchase over and over. It gets a short cooldown.
    local unknownAt = runtime.state.shopUnknown[style.remote]
    if unknownAt and tick() - unknownAt < 60 then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " has an unknown result; waiting before retrying")
        return nil
    end
    if ownership == "trial" then
        local trialAt = runtime.state.styleTrialAt[style.remote]
        if trialAt and tick() - trialAt < 45 then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " trial is already active; waiting before retrying")
            return nil
        end
    end
    local acquired, shopMovementToken = runtime.acquireMovement("shop")
    if not acquired then
        runtime.finishShopState(requestToken)
        dbg("Another movement operation is already running")
        return false
    end
    runtime.state.shopMovementToken = shopMovementToken
    runtime.state.shopping = true
    if WHIRLPOOL_STYLES[style.name] then
        runtime.takeWhirlpool()
        if not requestCurrent() then
            runtime.finishShopState(requestToken)
            return false
        end
    end
    local npc = findTeacher(style.teacher)
    local near = false
    if npc then
        local deadline = tick() + 25
        pcall(function()
            while tick() < deadline do
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
            return true
        end)
    end
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end

    -- A reply-4 check is a trial invitation, not permission for the ordinary
    -- buy. Start only the style-specific trial and wait for the normal
    -- ownership check to confirm that the server actually granted the style.
    if ownership == "trial" then
        runtime.state.shopInFlight = true
        runtime.state.styleTrialAt[style.remote] = tick()
        local trialOk, trialReply = pcall(function()
            return commF:InvokeServer(style.remote, table.unpack(style.trialArgs or {"Start"}))
        end)
        if not runtime.operationValid(operationEpoch, epoch, char)
            or runtime.state.shopToken ~= requestToken then
            runtime.finishShopState(requestToken)
            return false
        end
        local trialBought = nil
        if trialOk then
            local confirmDeadline = tick() + 2
            repeat
                if not runtime.operationValid(operationEpoch, epoch, char)
                    or runtime.state.shopToken ~= requestToken then
                    runtime.finishShopState(requestToken)
                    return false
                end
                local trialOwnership = runtime.styleOwnershipState(commF, style)
                if not runtime.operationValid(operationEpoch, epoch, char)
                    or runtime.state.shopToken ~= requestToken then
                    runtime.finishShopState(requestToken)
                    return false
                end
                if trialOwnership == "owned" then
                    trialBought = true
                    break
                end
                task.wait(0.1)
            until tick() >= confirmDeadline
        else
            dbg("The trial request for " .. style.name .. " failed")
        end
        runtime.finishShopState(requestToken)
        dbg("Trial for " .. style.name .. " was started"
            .. (trialReply ~= nil and (" (reply " .. tostring(trialReply) .. ")") or ""))
        return trialBought
    end

    -- Send the request once. Repeating it can buy the same style more than
    -- once when the server has no reply yet. The live buy RPCs answer 1 for a
    -- successful purchase and 2 when the style is already known.
    runtime.state.shopInFlight = true
    local buyArgs = runtime.styleBuyArgs(style)
    local ok, reply = pcall(function()
        return commF:InvokeServer(style.remote, table.unpack(buyArgs))
    end)
    if not runtime.operationValid(operationEpoch, epoch, char) then
        runtime.finishShopState(requestToken)
        return false
    end
    if runtime.state.shopToken ~= requestToken then
        runtime.finishShopState(requestToken)
        return false
    end

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

    -- A success reply is followed by the official ownership check when the
    -- style has one. A delayed or misleading reply therefore cannot leave the
    -- bot convinced that it owns a style that the server still rejects.
    if bought == true and style.checkArgs ~= false then
        local confirmDeadline = tick() + 2
        repeat
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            local confirmedOwnership = runtime.styleOwnershipState(commF, style)
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            if confirmedOwnership == "owned" then
                bought = true
                break
            end
            task.wait(0.1)
        until tick() >= confirmDeadline
        if bought ~= true then
            local finalOwnership = runtime.styleOwnershipState(commF, style)
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            if finalOwnership ~= "owned" then
                bought = nil
                runtime.state.shopUnknown[style.remote] = tick()
                dbg("The buy reply for " .. style.name .. " was not confirmed as owned")
            end
        end
    end
    runtime.finishShopState(requestToken)
    dbg("Buy " .. style.name .. " from " .. (npc and "the teacher" or "far away")
        .. (npc and (near and " (stood at it)" or " (could not reach it)") or " (no teacher was seen)")
        .. (bought == true and " (the game took it)"
            or (bought == false and " (the game refused it)" or " (result unknown)")))
    return bought
end

runtime.abilityShop = {
    Buso = {remote = "BuyHaki", argument = "Buso", label = "Buso Haki",
        official = "Buso", identity = {kind = "marker", name = "HasBuso"},
        cost = 25000, level = 50, teacher = "Ability Teacher"},
    Geppo = {remote = "BuyHaki", argument = "Geppo", label = "Geppo",
        official = "Geppo", identity = {kind = "tag", name = "Geppo"},
        tags = {"Geppo"},
        cost = 10000, level = 50, teacher = "Ability Teacher"},
    Soru = {remote = "BuyHaki", argument = "Soru", label = "Soru",
        official = "Soru", identity = {kind = "tag", name = "Soru"},
        tags = {"Soru"},
        cost = 100000, level = 300, teacher = "Ability Teacher"},
    Observation = {remote = "KenTalk", argument = "Buy", label = "Observation Haki",
        official = "Instinct", identity = {kind = "tag", name = "Ken"},
        tags = {"Ken", "KenUpgrade"},
        checkRemote = "KenTalk", checkArgument = "Start", ownedReply = 0, readyReply = 1,
        cost = 750000, level = 300, teacher = "Instinct Teacher", success = 0},
}

runtime.abilityDefinition = function(name)
    local wanted = tostring(name or ""):lower()
    if wanted == "" then return nil end
    local ability = runtime.abilityShop[name]
    if ability then return ability end
    for key, entry in pairs(runtime.abilityShop) do
        if key:lower() == wanted then return entry end
        if entry.official and entry.official:lower() == wanted then return entry end
        for _, tag in ipairs(entry.tags or {}) do
            if tag:lower() == wanted then return entry end
        end
    end
    return nil
end

runtime.hasAbility = function(name)
    local ability = runtime.abilityDefinition(name)
    if not ability then return false end
    local char = LocalPlayer.Character
    if not char then return false end

    -- These are the ownership signals used by the current character scripts.
    -- HasBuso is a marker whose mere existence is the proof; the other
    -- abilities are exact CollectionService tags on the character.
    local identity = ability.identity
    if identity and identity.kind == "marker" then
        if char:FindFirstChild(identity.name) ~= nil then return true end
    elseif identity and identity.kind == "tag" then
        local collection = game:GetService("CollectionService")
        local ok, tagged = pcall(function()
            return collection:HasTag(char, identity.name)
        end)
        if ok and tagged == true then return true end
    end

    for _, tag in ipairs(ability.tags or {}) do
        local collection = game:GetService("CollectionService")
        local ok, tagged = pcall(function()
            return collection:HasTag(char, tag)
        end)
        if ok and tagged == true then return true end
    end
    return false
end

runtime.buyAbility = function(name)
    local ability = runtime.abilityDefinition(name)
    if not ability then
        dbg("Unknown ability: " .. tostring(name))
        return false
    end
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    if runtime.state.saberActive or runtime.state.movementOwner == "saber" then
        dbg("Saber owns the quest; the ability buy was not started")
        return false
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    if ability.level and getMyLevel() < ability.level then
        dbg("Auto buy: " .. ability.label .. " needs level " .. ability.level
            .. ", we are " .. getMyLevel())
        return false
    end
    if runtime.hasAbility(ability.official or name) then
        dbg(ability.label .. " is already owned")
        return true
    end
    local requestToken = runtime.beginShopRequest()
    if not requestToken then
        dbg("A buy is already running")
        return false
    end
    local function requestCurrent()
        return runtime.state.shopToken == requestToken
            and runtime.operationValid(operationEpoch, epoch, char)
    end

    -- KenTalk("Start") is the official Instinct eligibility check. Reply 0
    -- means the ability is already known, reply 1 means the server accepts the
    -- purchase, and every other reply is a level or prerequisite refusal.
    if ability.checkRemote then
        local checkOk, checkReply = pcall(function()
            return commF:InvokeServer(ability.checkRemote, ability.checkArgument)
        end)
        if not requestCurrent() then
            runtime.finishShopState(requestToken)
            return false
        end
        if not checkOk then
            runtime.finishShopState(requestToken)
            dbg("The " .. ability.label .. " eligibility check failed")
            return false
        end
        if checkReply == ability.ownedReply then
            runtime.finishShopState(requestToken)
            dbg(ability.label .. " is already owned")
            return true
        end
        if checkReply ~= ability.readyReply then
            runtime.finishShopState(requestToken)
            dbg("The game did not unlock " .. ability.label
                .. " (reply " .. tostring(checkReply) .. ")")
            return false
        end
    end

    local beli = myBeli()
    if ability.cost then
        if type(beli) ~= "number" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. ability.label .. " costs " .. ability.cost
                .. " Beli, but the Beli balance is not available")
            return false
        end
        if beli < ability.cost then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. ability.label .. " costs " .. ability.cost
                .. " Beli, we have " .. math.floor(tonumber(beli) or 0))
            return false
        end
    end
    local acquired, movementToken = runtime.acquireMovement("shop")
    if not acquired then
        runtime.finishShopState(requestToken)
        dbg("Another movement operation is already running")
        return false
    end
    -- Keep the exact owner token with the request.  Without it a reset cannot
    -- release an ability purchase that is walking to its teacher, and a late
    -- reply could otherwise release a newer shop owner.
    runtime.state.shopMovementToken = movementToken
    runtime.state.shopping = true
    runtime.state.shopInFlight = false

    -- The teacher must see the player. A missing teacher is reported, but the
    -- official request is still attempted once so the server remains the final
    -- authority when its NPC list is streamed later.
    local teacher = findTeacher(ability.teacher)
    if teacher then
        local deadline = tick() + 20
        while tick() < deadline do
            if not requestCurrent() then
                runtime.finishShopState(requestToken)
                return false
            end
            local root, anchor = getRoot(), anchorOf(teacher)
            if not root or not anchor then break end
            runtime.state.blockAt = tick()
            if (root.Position - anchor.Position).Magnitude <= 8 then break end
            runtime.travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)), true)
            task.wait(0.2)
        end
    else
        dbg("The teacher of " .. ability.label .. " was not found")
    end
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end

    runtime.state.shopInFlight = true
    local ok, reply = pcall(function()
        return commF:InvokeServer(ability.remote, ability.argument)
    end)
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end
    if not ok then
        runtime.finishShopState(requestToken)
        dbg("The buy request for " .. ability.label .. " failed")
        return false
    end
    local success = ability.success
    if success == nil then success = 1 end
    local bought = false
    if reply == success or (success ~= 0 and (reply == true)) then
        bought = true
        dbg("The game took the buy of " .. ability.label)
    elseif success == 1 and reply == 2 then
        bought = true
        dbg(ability.label .. " was already owned")
    elseif reply == nil then
        bought = nil
        dbg("The game did not answer the buy of " .. ability.label)
    else
        dbg("The game refused the buy of " .. ability.label
            .. " (reply " .. tostring(reply) .. ")")
    end

    if bought == true then
        local confirmDeadline = tick() + 3
        repeat
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            if runtime.hasAbility(ability.official or name) then
                bought = true
                break
            end
            task.wait(0.1)
        until tick() >= confirmDeadline
        if not runtime.hasAbility(ability.official or name) then
            bought = nil
            dbg("The buy of " .. ability.label .. " was not confirmed in the client")
        end
    end
    runtime.finishShopState(requestToken)
    return bought
end

-- ================= MAIN LOOP =================
-- The mobs that were frozen for the farm are let go again with this.

local function releaseBringMobs()
    -- letGoMob removes entries while it works. Take a stable list first so no
    -- saved rig can be skipped by changing the weak tables during pairs().
    local pending, seen = {}, {}
    for mob, part in pairs(runtime.state.bringHeld) do
        pending[#pending + 1] = {mob = mob, part = part}
        seen[mob] = true
    end
    -- A mob can have saved state before it ever enters bringHeld (for example
    -- when ownership changes during the first mutation). Restore those saved
    -- rigs as well instead of dropping the table and losing their state.
    for mob, saved in pairs(runtime.state.bringSaved) do
        if not seen[mob] then
            pending[#pending + 1] = {mob = mob, part = saved and saved.part}
            seen[mob] = true
        end
    end
    for _, entry in ipairs(pending) do
        runtime.letGoMob(entry.mob, entry.part)
    end
    runtime.state.bringHeld = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlot = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlotCount = 0
    -- the point of the last pack dies with it, so the next fight is gathered
    -- where the fight actually is
    runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
    runtime.state.bringCarryOffsetY = nil
    runtime.state.bringPathBlocked = false
    runtime.state.bringPathCheck = nil
    runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
    -- A server-owned rig can keep its restoration snapshot until ownership
    -- returns. Dropping that snapshot would capture the frozen values as the
    -- new originals on a later hold.
    runtime.state.bringSnapped = setmetatable({}, {__mode = "k"})
    runtime.state.bringCarryingTarget = setmetatable({}, {__mode = "k"})
    runtime.state.bringMover = setmetatable({}, {__mode = "k"})
    runtime.state.bringAt = 0
    -- Releasing the pack also ends the player's stationary hold. This keeps a
    -- disabled bot, a respawn, or an inactivity timeout from leaving a
    -- zero-velocity BodyVelocity attached to the character.
    if runtime.releaseTweenHold then runtime.releaseTweenHold() end
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
    runtime.state.bringCarryOffsetY = nil
    runtime.state.bringPathBlocked = false
    runtime.state.bringPathCheck = nil
    runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
    runtime.state.bringHeld = setmetatable({}, {__mode = "k"})
    -- Keep pending restoration snapshots for rigs that the server currently
    -- owns; letGoMob removes each snapshot once it has safely restored it.
    runtime.state.bringSnapped = setmetatable({}, {__mode = "k"})
    runtime.state.bringCarryingTarget = setmetatable({}, {__mode = "k"})
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
    table.insert(runtime.cleanupFns, function()
    runtime.stopTween()
    if tweenProxy and tweenProxy.Parent then
        pcall(function() tweenProxy:Destroy() end)
    end
    tweenProxy = nil
end)
    table.insert(runtime.cleanupFns, function() runtime.restoreNoclip() end)
    table.insert(runtime.cleanupFns, function() runtime.releaseBringMobs() end)
    table.insert(runtime.cleanupFns, function() runtime.exportPendingBringSnapshots() end)
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

    if not runtime.state.travelActive
        and (not runtime.state.currentSeaAt or now - runtime.state.currentSeaAt > 2) then
        runtime.detectCurrentSea()
    end

    -- A world change owns the character until the Realm service confirms the
    -- destination. Ordinary farming must not start another tween in parallel.
    if runtime.state.travelActive then
        if not runtime.state.blockAt then runtime.state.blockAt = now end
        if now - runtime.state.blockAt > 25 then
            local travelMovementToken = runtime.state.travelMovementToken
            runtime.state.travelToken = (runtime.state.travelToken or 0) + 1
            runtime.state.travelActive = false
            runtime.state.travelMovementToken = nil
            runtime.releaseMovement("travel", travelMovementToken)
            runtime.state.blockAt = nil
            runtime.stopTween()
            dbg("A stuck world travel got cleared")
        else
            runtime.state.status = "Travelling between seas..."
            return
        end
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

    runtime.updateSafePoint(root, now)
    if runtime.recoverFall(root, now) then return end

    -- A shop buy or a flight owns the movement while it runs. This watchdog is
    -- before every Saber early return: a stale purchase must not be able to
    -- hide behind a puzzle step until the much longer Saber timeout.
    if runtime.state.shopping or runtime.state.shopInFlight or runtime.state.flying then
        if not runtime.state.blockAt then runtime.state.blockAt = now end
        local timedOut = now - runtime.state.blockAt > 25
        if timedOut and (runtime.state.shopping or runtime.state.shopInFlight
            or runtime.state.flying) then
            local flightOwner = runtime.state.flightOwner
            local flightOwnerToken = runtime.state.flightMovementToken
            if runtime.state.shopping or runtime.state.shopInFlight then
                runtime.resetShopState()
            end
            if runtime.state.flying then
                -- Invalidate the old flight coroutine before another one can
                -- start. The old task then cannot clear the new flight's flag.
                runtime.state.flightToken = (runtime.state.flightToken or 0) + 1
                runtime.state.flightOwner = nil
                runtime.state.flightMovementToken = nil
                runtime.state.flying = false
                if flightOwner and runtime.releaseMovement then
                    runtime.releaseMovement(flightOwner, flightOwnerToken)
                end
                if flightOwner == "shop" then runtime.resetShopState() end
            end
            runtime.state.blockAt = nil
            runtime.stopTween()
            dbg("A stuck movement operation got cleared, farming again")
        end
        if runtime.state.shopping or runtime.state.shopInFlight or runtime.state.flying then return end
    else
        runtime.state.blockAt = nil
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
                if candidate.Name:lower() == runtime.state.saberTarget:lower() then
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

    if not runtime.state.lastPos or (root.Position - runtime.state.lastPos).Magnitude > 1 then
        runtime.state.lastPos = root.Position
        runtime.state.movedAt = now
    end
    -- The safe point is maintained by the raycast above. Replacing it with a
    -- stationary position would remember a point in mid-air after a tween.

    if runtime.handleChest(root) then
        return
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
        if runtime.state.saberActive and runtime.state.saberTarget then
            -- Auto Saber owns one exact boss in this mode. Ordinary farming
            -- stays off, but the current Saber target is still fought with
            -- the normal movement and attack systems.
            if next(runtime.state.bringHeld) ~= nil
                or next(runtime.state.bringSaved) ~= nil then
                releaseBringMobs()
            end
            restoreHitbox()
            runtime.state.farming = runtime.runSaberCombat(root)
            return
        end
        runtime.state.farming = false
        runtime.state.status = "Idle"
        -- nothing is being farmed: the pack of the last mob is let go and the
        -- hitbox that was made big for the swing is put back
        restoreHitbox()
        if next(runtime.state.bringHeld) ~= nil
            or next(runtime.state.bringSaved) ~= nil then
            releaseBringMobs()
        end
        runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
        return
    end
    runtime.state.farming = true

    local quest = runtime.config.AutoQuest and questFor(getMyLevel()) or nil
    local mob = quest and quest.mob or nil
    local bossWindow = runtime.config.BossLevelWindow or 25
    local explicitBoss = runtime.config.BossTarget and runtime.config.BossTarget ~= "Auto"
    local explicitMobChoice, explicitMobName, nearestMob =
        runtime.resolveSelectedMob(runtime.config.SelectedMob)
    -- "Nearest" is a mode, not an exact mob selection. It must not make an
    -- automatic boss quest bypass the boss level window.
    local explicitMob = explicitMobChoice and not nearestMob
    local explicitPole = runtime.config.PoleMastery and runtime.config.PoleTarget
        and runtime.config.PoleTarget ~= "Auto"
    local exactSelection = explicitBoss or explicitMob or explicitPole
    local function bossAllowedFor(name)
        if not bossNameIs(name) then return false end
        -- An explicit boss or selected mob is the user's decision. Automatic
        -- boss farming still keeps its level window.
        if exactSelection then return true end
        if not runtime.config.BossFarm then return false end
        local level = bossLevelOf and bossLevelOf(name)
        return level == nil or math.abs(level - getMyLevel()) <= bossWindow
    end
    if explicitBoss then
        mob = runtime.config.BossTarget
    elseif explicitMobChoice then
        mob = explicitMobName
    elseif explicitPole then
        mob = runtime.config.PoleTarget
    elseif info and info.target then
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
            target = pickBoss(root, runtime.config.BossRange or 3000, mob,
                exactSelection)
            -- The boss is dead or out of range: automatic quests may farm
            -- normal mobs around the spawn. An explicit target stays exact.
            if not target and not exactSelection then
                target = pickNormal(root)
            end
        else
            -- Boss farm off, or the boss is too far from the player's level.
            -- Do not let the normal quest picker walk into it anyway.
            mob = nil
            target = pickNormal(root)
        end
    else
        target = nearestMob and pickNormal(root) or getTarget(mob, exactSelection)
    end
    if runtime.state.saberTarget then
        -- a running quest knows which mob it needs
        for _, m in ipairs(collectEnemies(tick())) do
            if m.Name:lower() == runtime.state.saberTarget:lower() then
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
        if next(runtime.state.bringHeld) ~= nil
            or next(runtime.state.bringSaved) ~= nil then
            releaseBringMobs()
        end
        runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
        local sp = findSpawn(mob, exactSelection)
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
            if runtime.state.saberTarget and target.Name:lower() == runtime.state.saberTarget:lower() then
                runtime.state.saberKillHealth = th.Health
            end
        elseif th.Health < (runtime.state.targetHealth or th.Health) then
            runtime.state.targetHealth, runtime.state.targetAt = th.Health, now
            runtime.state.targetDist, runtime.state.travelAt = dist, now
            if runtime.state.saberTarget and target.Name:lower() == runtime.state.saberTarget:lower() then
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
    local isSaberTarget = runtime.state.saberTarget
        and target.Name:lower() == runtime.state.saberTarget:lower()
    if runtime.config.BringMob and not isSaberTarget then
        -- Bring Mob checks the straight route before its own range gate. Call
        -- it for an out-of-range target as well, so a wet route is known
        -- before the player is asked to approach it.
        local hadPack = next(runtime.state.bringHeld) ~= nil
            or next(runtime.state.bringSaved) ~= nil
        bringMob(target, root)
        if hadPack and next(runtime.state.bringHeld) == nil
            and next(runtime.state.bringSaved) == nil then
            restoreHitbox()
        end
    elseif next(runtime.state.bringHeld) ~= nil
        or next(runtime.state.bringSaved) ~= nil then
        -- The exact Saber boss owns the ordinary farm during its kill step.
        -- It is never frozen or dragged by Bring Mob.
        releaseBringMobs()
        restoreHitbox()
    end

    local swingTarget = target
    if runtime.config.AutoAttack then
        local close = mobInReach(root, reach)
        -- A boss is not given up for a normal mob that happens to stand near:
        -- the boss is what the boss farm went there for.
        local onBoss = bossKeyOf(target)
        local onSelected = explicitBoss or explicitMob or explicitPole
        local onSaber = runtime.state.saberTarget
            and target.Name:lower() == runtime.state.saberTarget:lower()
        -- A swipe at a mob that stands in the way is fine, but the window has
        -- to close and then stay closed for a while. If it is armed again on
        -- the next tick the bot farms the mob beside it for ever and never
        -- walks to the mob of the quest at all.
        if close and close ~= target and flat > reach and not onBoss and not onSaber
            and not onSelected and (runtime.state.autoBurstCd or 0) <= now then
            runtime.state.autoBurst = now + 2
            runtime.state.autoBurstCd = now + 8
        end
        if (runtime.state.autoBurst or 0) > now and close and not onSaber
            and not onSelected then
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
    -- ground while the mob comes over; it never follows the mob's height.
    local heldTarget = runtime.state.bringCarryingTarget[target] == true
    if heldTarget then
        -- A carried target is already moving under the player. Following its
        -- current vertical position made the player follow a falling rig into
        -- the water, while the old held-target patrol made the character jump
        -- around in four slots. Hold the current ground position instead.
        hoverPos = root.Position
    end

    -- Safe tween farming travels between wide slots around the target. It no
    -- longer writes the root CFrame every frame, which made the character
    -- spin in place. A carried target is different: the pack is already moving
    -- under the player, so any slot or target-height follow makes the two
    -- systems pull against each other. Cancel the approach once and hold.
    if heldTarget then
        -- A completed Tween is no longer Playing, but its Humanoid can still
        -- be left in Physics/PlatformStand. Cancel any remaining Tween object
        -- and restore walking in both the active and completed cases.
        -- Keep the zero-velocity body hold while the target is actually held.
        -- Releasing it here lets gravity pull the player down from an
        -- elevated approach, which can end in the water even though the bot
        -- issued no further movement command.
        ensureTweenHold(root)
        if activeTween then
            runtime.stopTween()
        else
            runtime.setWalking()
        end
    elseif runtime.config.BringMob then
        -- Bring Mob owns the player's position while the pack is being
        -- gathered. The old safe-slot orbit kept dashing the character around
        -- the target whenever network ownership briefly changed. Approach the
        -- stable hover point once, then stand still while the pack arrives.
        local bringRange = tonumber(runtime.config.BringMobRange) or 60
        if runtime.state.bringPathBlocked then
            -- The straight path to this mob crosses water. Keep the player on
            -- its current dry ground instead of sending it over the same gap.
            if activeTween then
                runtime.stopTween()
            else
                runtime.setWalking()
            end
        elseif bringRange > 0 and flat <= bringRange then
            local verticalGap = math.abs(root.Position.Y - hoverPos.Y)
            if flat > reach + 4 or verticalGap > 12 then
                runtime.tweenTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))
            else
                if activeTween then
                    runtime.stopTween()
                else
                    runtime.setWalking()
                end
            end
        elseif runtime.config.Dodge and runtime.config.RemoteAttack then
            local centre = er.Position
            runtime.tweenFarmSlot(target, centre, root, false, hoverPos.Y)
        else
            runtime.travelTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))
        end
    elseif runtime.config.Dodge and runtime.config.RemoteAttack then
        local centre = er.Position
        runtime.tweenFarmSlot(target, centre, root, false, hoverPos.Y)
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
        -- This sweep also runs while the bot is stopped. A rig that was
        -- server-owned can get ownership back after the stop and must still
        -- receive the restoration that was saved before it was released.
        runtime.restorePendingBringMobs()
        if runtime.state.enabled then
            runtime.state.wasStopped = false
            local ok, err = pcall(step)
            if not runtime.isCurrent() then return end
            if not ok then dbg("Loop error: " .. tostring(err)) end
            -- The Bring hold keeps the player at the position where the pack
            -- was caught. Once the actual hold is gone, release the body hold
            -- so ordinary walking and the next operation are not affected.
            if runtime.releaseTweenHold then runtime.releaseTweenHold() end
            -- A pause of the farm (a turn-in, a fruit, a shop) must not leave
            -- the last pack frozen: if the farm has not carried it for a few
            -- seconds, the mobs are let go and the enlarged hitbox is put back.
            if (next(runtime.state.bringHeld) ~= nil
                or next(runtime.state.bringSaved) ~= nil)
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
                if next(runtime.state.bringHeld) ~= nil
                    or next(runtime.state.bringSaved) ~= nil then
                    releaseBringMobs()
                end
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

-- Quest objects can be nested below a streamed map folder. The official
-- QuestPro script uses FindFirstChild(name, true) for the Cup, so the source
-- uses the same lookup instead of guessing a fixed parent path.
local function saberDescendant(root, name)
    if not root then return nil end
    local found = root:FindFirstChild(name, true)
    return found
end

-- The Frozen Village and Desert markers are kept by the world even while
-- their decorative map objects are streamed. They are the route anchors for
-- the Saber Cup; hard-coded coordinates of an old map revision are not used.
local function saberLocations(name)
    local wanted = name:lower()
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    local list = {}
    if not locations then return list end
    for _, part in ipairs(locations:GetChildren()) do
        if part:IsA("BasePart") and part.Name:lower() == wanted then
            list[#list + 1] = part
        end
    end
    -- Some locations have more than one marker. The lower-X Desert marker is
    -- the one that streams Workspace.Map.Desert on the current map.
    table.sort(list, function(left, right)
        if left.Position.X ~= right.Position.X then
            return left.Position.X < right.Position.X
        end
        return left.Position.Z < right.Position.Z
    end)
    return list
end

local function saberLocation(name)
    return saberLocations(name)[1]
end

local function findMob(text)
    local wanted = text:lower()
    for _, mob in ipairs(collectEnemies(tick())) do
        if mob.Name:lower() == wanted then return mob end
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
    local operationEpoch = runtime.operationEpoch
    local commF = shopRemote()
    if not commF then
        runtime.state.status = "Saber: CommF_ is missing"
        return false
    end

    local ok, progress = pcall(function()
        return commF:InvokeServer("ProQuestProgress")
    end)
    if not runtime.operationValid(operationEpoch, epoch, char) then return false end
    if not ok or type(progress) ~= "table" then
        runtime.state.status = "Saber: could not read the quest state"
        return false
    end
    runtime.state.saberProgress = progress
    runtime.state.saberStateAt = now

    local plates = progress.Plates or {}
    local function plateDone(index)
        return runtime.state.saberPlates[index] == true
            or plates[index] == true or plates[tostring(index)] == true
    end

    -- Every confirmed server stage is latched. A later query that briefly
    -- omits an old flag must not move the puzzle backwards or make the
    -- timeout look fresh. Only the first false-to-true transition is new
    -- progress.
    local function latchProgress(authoritative)
        local changed = false
        local sourcePlates = authoritative.Plates or {}
        for index = 1, 5 do
            local done = sourcePlates[index] == true or sourcePlates[tostring(index)] == true
            if done and not runtime.state.saberPlates[index] then
                runtime.state.saberPlates[index] = true
                changed = true
            end
        end
        local function latch(name, value)
            if value and not runtime.state[name] then
                runtime.state[name] = true
                return true
            end
            return false
        end
        if latch("saberUsedTorch", authoritative.UsedTorch) then changed = true end
        if latch("saberUsedCup", authoritative.UsedCup) then changed = true end
        if latch("saberKilledMob", authoritative.KilledMob) then changed = true end
        if latch("saberUsedRelic", authoritative.UsedRelic) then changed = true end
        if latch("saberKilledShanks", authoritative.KilledShanks) then changed = true end
        if latch("saberSonReady", authoritative.TalkedSon) then changed = true end
        if changed then runtime.state.saberProgressAt = now end
        return changed
    end
    latchProgress(progress)

    local plateCount = 0
    for index = 1, 5 do
        if plateDone(index) then plateCount = plateCount + 1 end
    end

    -- The fingerprint describes the monotonic state for diagnostics and
    -- change detection. It is deliberately not a timeout source: an
    -- alternating RichSon reply or the first observation of an unchanged
    -- state must never keep a stuck puzzle alive.
    local fingerprint = table.concat({
        tostring(plateCount),
        runtime.state.saberUsedTorch and "1" or "0",
        runtime.state.saberUsedCup and "1" or "0",
        runtime.state.saberCupGranted and "1" or "0",
        runtime.state.saberCupTouched and "1" or "0",
        runtime.state.saberFillPending and "1" or "0",
        runtime.state.saberSickDone and "1" or "0",
        runtime.state.saberKilledMob and "1" or "0",
        runtime.state.saberSonReady and "1" or "0",
        runtime.state.saberRelicGrantAccepted and "1" or "0",
        runtime.state.saberRelicConfirmed and "1" or "0",
        runtime.state.saberUsedRelic and "1" or "0",
        runtime.state.saberKilledShanks and "1" or "0",
    }, ":")
    runtime.state.saberFingerprint = fingerprint

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
        if not runtime.operationValid(operationEpoch, epoch, char) then return nil, nil end
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

    local function ownedTool(name, exact)
        local wanted = name:lower()
        for tool in pairs(ownedTools()) do
            local toolName = tool.Name:lower()
            if (exact and toolName == wanted)
                or (not exact and toolName:find(wanted, 1, true)) then
                return tool
            end
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

    local function findSaberSpawn(name)
        local spawn = findSpawn(name, true)
        if spawn then return spawn end
        local origin = Workspace:FindFirstChild("_WorldOrigin")
        local spawns = origin and origin:FindFirstChild("EnemySpawns")
        if not spawns then return nil end
        for _, part in ipairs(spawns:GetChildren()) do
            -- Spawn names include level and role suffixes. Normalize the
            -- display label before applying the exact Mob Leader alias.
            local label = mobKey(part.Name):lower()
            -- The current map labels the Mob Leader spawn "Mob Boss" with a
            -- level/role suffix. The enemy that spawns there is still the
            -- exact Mob Leader.
            if name == "Mob Leader" and label == "mob boss" then
                return part
            end
            if name == "Saber Expert" and label == "saber expert" then
                return part
            end
        end
        return nil
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
    if not runtime.state.saberUsedTorch then
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

    -- GetCup only gives the empty cup. The official QuestPro client waits
    -- for the equipped Cup.Handle to touch the exact Ice water part before it
    -- sends FillCup. A request based only on the character's distance is not
    -- accepted by the current server, so the physical touch is a separate gate.
    if not runtime.state.saberUsedCup then
        local cupTool = ownedTool("Cup", true)
        local water = saberPart("Map/Ice/ParticleDrop/Water")
        local frozenMarker = saberLocation("Frozen Village")
        local desertCup = saberDescendant(saberPart("Map/Desert"), "Cup")
        local currentDesertCupPart = desertCup
            and (desertCup:IsA("BasePart") and desertCup or anchorOf(desertCup))
        local desertCupPart = currentDesertCupPart
            or runtime.state.saberDesertCupTouchPart
        runtime.state.saberAt = "the cup in the Frozen cave"

        -- The official QuestPro flow starts with the character touching the
        -- Desert Cup. GetCup must not be sent from a distance: the current
        -- server can grant the inventory tool, but later refuses FillCup when
        -- that earlier physical Cup step never happened.
        if currentDesertCupPart
            and runtime.state.saberDesertCupTouchPart ~= currentDesertCupPart then
            if runtime.state.saberDesertCupConnection then
                pcall(function()
                    runtime.state.saberDesertCupConnection:Disconnect()
                end)
            end
            runtime.state.saberDesertCupConnection = nil
            runtime.state.saberDesertCupTouched = false
            runtime.state.saberDesertCupTouchPart = currentDesertCupPart
            runtime.state.saberDesertCupTouchAt = 0
            desertCupPart = currentDesertCupPart
        end
        if not currentDesertCupPart
            and not runtime.state.saberDesertCupTouched then
            local desertMarker = saberLocation("Desert")
            if desertMarker then
                runtime.state.status = "Saber: flying to Desert for the Cup"
                flyTo(desertMarker.Position + Vector3.new(0, 30), "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            else
                runtime.state.status = "Saber: the Desert Cup is not loaded"
            end
            return false
        end
        if not desertCupPart then
            runtime.state.status = "Saber: the Desert Cup is not loaded"
            return false
        end
        if not runtime.state.saberDesertCupConnection and desertCupPart.Parent then
            runtime.state.saberDesertCupConnection = desertCupPart.Touched:Connect(function(hit)
                if not char or not hit or not hit:IsDescendantOf(char) then return end
                if not runtime.operationValid(operationEpoch, epoch, char) then return end
                if runtime.state.saberDesertCupTouchPart ~= desertCupPart then return end
                runtime.state.saberDesertCupTouched = true
                runtime.state.saberDesertCupTouchAt = tick()
                runtime.state.status = "Saber: the character touched the Desert Cup"
            end)
        end

        -- This is a real tween, not a warp. MoveSpeed is 200 studs per second
        -- by default (the accepted range is 180-200), and the character is
        -- placed against the Cup before the exact touch is requested.
        if not runtime.state.saberDesertCupTouched then
            local rootHeight = root.Size and root.Size.Y or 2
            local cupHeight = desertCupPart.Size and desertCupPart.Size.Y or 0
            local cupGoal = desertCupPart.Position
                + Vector3.new(0, math.max(0, (cupHeight - rootHeight) / 2), 0)
            if (root.Position - cupGoal).Magnitude > 2 then
                runtime.state.status = "Saber: tweening to the Desert Cup"
                runtime.tweenTo(CFrame.new(cupGoal))
                return false
            end
            -- The client is already physically against the exact Cup part.
            -- This only completes the local Touched callback; FillCup still
            -- requires a separate real touch of the exact Water part later.
            touch(root, desertCupPart)
            return false
        end

        if not cupTool then
            -- GetCup is now sent only after the official Desert Cup touch
            -- sequence. The actual tool is still required before FillCup.
            local called, result = callProgress("GetCup")
            runtime.state.saberCupRequestAt = now
            if called and result ~= false then
                runtime.state.status = "Saber: GetCup was accepted, waiting for the cup"
            elseif called then
                runtime.state.status = "Saber: the server refused GetCup"
            else
                runtime.state.status = "Saber: GetCup did not reach the server"
            end
            return false
        end

        -- The actual inventory tool is the only proof that GetCup was granted.
        -- The server flag alone is not used to skip the item.
        runtime.state.saberCupGranted = true
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        -- The live Blox Fruits Humanoid does not expose GetEquippedTool.
        -- EquipTool moves the exact tool into the Character, so its parent
        -- is the authoritative equipped-state check.
        if hum and cupTool.Parent ~= char then
            pcall(function() hum:EquipTool(cupTool) end)
        end
        if cupTool.Parent ~= char then
            runtime.state.status = "Saber: waiting for the Cup to be equipped"
            return false
        end

        -- The official proof is the exact Cup.Handle part. A generic tool
        -- part fallback is not enough for FillCup.
        local handle = cupTool:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then
            runtime.state.status = "Saber: the Cup handle is not loaded"
            return false
        end

        -- Frozen Village is a real route anchor. The first flight loads the
        -- Ice model and its ParticleDrop/Water part without relying on an old
        -- hard-coded position or on the decorative map GUI.
        if not water then
            if frozenMarker then
                runtime.state.status = "Saber: flying to Frozen Village"
                flyTo(frozenMarker.Position + Vector3.new(0, 30), "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            else
                runtime.state.status = "Saber: the Frozen Village marker is not loaded"
            end
            return false
        end

        -- FillCup and SickMan are two halves of one official exchange. The
        -- server accepts the filled Cup first, but it publishes UsedCup only
        -- after SickMan confirms that exchange. Waiting for UsedCup before
        -- sending SickMan deadlocks the stage. A retry still needs a new
        -- physical touch of the exact Water part.
        if runtime.state.saberFillPending then
            local fillAge = now - (runtime.state.saberFillRequestAt or 0)
            local sickStatus
            if fillAge >= 0.35
                and runtime.state.saberFillSickResult ~= 0
                and now - (runtime.state.saberFillSickAt or 0) >= 2
                and now - (runtime.state.saberAttempts["SickMan"] or 0) >= 2 then
                local sickCalled, sickResult = callProgress("SickMan")
                if sickCalled then
                    runtime.state.saberFillSickAt = now
                    runtime.state.saberFillSickResult = sickResult
                    if sickResult == 0 then
                        runtime.state.saberSickDone = true
                        sickStatus = "Saber: FillCup was sent; waiting for the Sick Man confirmation"
                    else
                        sickStatus = "Saber: the Sick Man has not confirmed the filled Cup yet"
                    end
                    runtime.state.status = sickStatus
                end
            end
            if fillAge < 8 then
                runtime.state.status = sickStatus
                    or runtime.state.status
                    or "Saber: FillCup was accepted, waiting for the server"
                return false
            end
            runtime.state.saberFillPending = false
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: FillCup was not confirmed, touching the water again"
            return false
        end
        if now - (runtime.state.saberFillRequestAt or 0) < 2 then
            runtime.state.status = "Saber: waiting before the next FillCup request"
            return false
        end

        -- Move to the loaded water before installing the touch listener. The
        -- flight stays under the Saber movement token and cannot race a shop
        -- or an ordinary farm trip.
        if (root.Position - water.Position).Magnitude > 18 then
            runtime.state.status = "Saber: flying to the Cup water"
            flyTo(water.Position, "saber")
            if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            return false
        end

        local function disconnectTouch()
            if runtime.state.saberCupTouchConnection then
                pcall(function() runtime.state.saberCupTouchConnection:Disconnect() end)
            end
            runtime.state.saberCupTouchConnection = nil
        end

        -- A touch belongs to one exact tool, Handle and Water instance. A
        -- replacement Cup, Handle or newly streamed Water part starts a new
        -- touch attempt instead of inheriting an old proof.
        if runtime.state.saberCupTouchConnection
            and (runtime.state.saberCupTouchTool ~= cupTool
                or runtime.state.saberCupTouchWater ~= water
                or runtime.state.saberCupTouchHandle ~= handle) then
            disconnectTouch()
        end
        if runtime.state.saberCupTouchTool ~= cupTool
            or runtime.state.saberCupTouchWater ~= water
            or runtime.state.saberCupTouchHandle ~= handle then
            runtime.state.saberCupTouched = false
            runtime.state.saberCupTouchTool = cupTool
            runtime.state.saberCupTouchWater = water
            runtime.state.saberCupTouchHandle = handle
        end

        -- Move the handle above the water first, then install the listener and
        -- enter the water. This creates a real Touched event for the exact
        -- ParticleDrop/Water part instead of accepting a nearby part.
        local function moveHandleToHeight(handleY, timeout, waitForTouch)
            local deadline = tick() + timeout
            while tick() < deadline do
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
                local offset = handle.Position - root.Position
                local target = Vector3.new(
                    water.Position.X - offset.X,
                    handleY - offset.Y,
                    water.Position.Z - offset.Z)
                runtime.setFlying()
                runtime.tweenTo(CFrame.new(target) * root.CFrame.Rotation)
                if (root.Position - target).Magnitude <= 3 and not waitForTouch then return true end
                task.wait(0.05)
            end
            return false
        end

        if not runtime.state.saberCupTouched then
            local waterHeight = water.Size and water.Size.Y / 2 or 14
            local aboveY = water.Position.Y + waterHeight + 5
            moveHandleToHeight(aboveY, 3)

            if not runtime.state.saberCupTouchConnection then
                runtime.state.saberCupTouchConnection = handle.Touched:Connect(function(part)
                    if part ~= water then return end
                    if not runtime.operationValid(operationEpoch, epoch, char) then return end
                    if cupTool.Parent ~= char
                        or cupTool:FindFirstChild("Handle") ~= handle then return end
                    runtime.state.saberCupTouched = true
                    runtime.state.saberCupTouchHandle = handle
                    runtime.state.saberCupTouchAt = tick()
                    runtime.state.status = "Saber: the Cup handle touched the water"
                end)
            end

            moveHandleToHeight(water.Position.Y, 4, true)
            if not runtime.state.saberCupTouched then
                runtime.state.status = "Saber: waiting for the Cup handle to touch the water"
                return false
            end
        end

        -- Let the exact touch reach the server before asking it to fill the
        -- Cup. The request is never sent from a distance-only check.
        task.wait(0.25)
        if not runtime.operationValid(operationEpoch, epoch, char) then return false end
        if cupTool.Parent ~= char then
            disconnectTouch()
            runtime.state.saberCupTouched = false
            runtime.state.status = "Saber: the Cup is no longer equipped"
            return false
        end
        -- Re-resolve both physical participants immediately before the
        -- request. If the Handle or streamed Water was replaced during the
        -- settling delay, the old touch cannot authorize the new instances.
        if cupTool:FindFirstChild("Handle") ~= handle
            or saberPart("Map/Ice/ParticleDrop/Water") ~= water then
            disconnectTouch()
            runtime.state.saberCupTouched = false
            runtime.state.status = "Saber: waiting for a fresh Cup water touch"
            return false
        end
        if not runtime.state.saberCupTouched
            or runtime.state.saberCupTouchTool ~= cupTool
            or runtime.state.saberCupTouchWater ~= water
            or runtime.state.saberCupTouchHandle ~= handle then
            runtime.state.status = "Saber: waiting for a fresh Cup water touch"
            return false
        end

        local called, result = callProgress("FillCup", cupTool)
        disconnectTouch()
        runtime.state.saberCupTouched = false
        if called and result ~= false then
            -- The delay starts when the server accepts FillCup, not when this
            -- pass began. Positioning the handle can take several seconds.
            runtime.state.saberFillRequestAt = tick()
            runtime.state.saberFillPending = true
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: FillCup was accepted, waiting for the server"
        elseif called then
            runtime.state.saberFillRequestAt = 0
            runtime.state.saberFillPending = false
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: the server refused FillCup"
        else
            runtime.state.saberFillRequestAt = 0
            runtime.state.saberFillPending = false
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: FillCup did not reach the server"
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

    -- The first Rich Son conversation is its own server-backed stage. The
    -- reply 0 tells the player that the Mob Leader must be killed, and it is
    -- made before the boss hunt so the later reply 1 is not skipped.
    if not runtime.state.saberSonReady then
        local npc = findTeacher("Rich Man")
        runtime.state.saberAt = "the Rich Man of the Pirate Village"
        if npc then
            if moveToPart(npc, 8) then
                local called, result = callProgress("RichSon")
                if called and result == 0 then
                    runtime.state.saberSonReady = true
                    runtime.state.saberProgressAt = now
                    runtime.state.status = "Saber: the Rich Man confirmed the Mob Leader task"
                elseif called and result == 1 then
                    -- The server already knows about the kill. Keep both
                    -- stages separate: the grant still has to be followed by
                    -- the actual relic in the inventory.
                    runtime.state.saberSonReady = true
                    runtime.state.saberRelicGrantAccepted = true
                    runtime.state.saberProgressAt = now
                    runtime.state.status = "Saber: the Rich Man already granted the relic"
                else
                    runtime.state.status = "Saber: the Rich Man did not confirm the Mob Leader task"
                end
            end
        else
            runtime.state.status = "Saber: the Rich Man was not found"
        end
        return false
    end

    -- The Mob Leader has to be really killed. The server flag is the
    -- completion test; the health watch below only refreshes the timeout.
    if not runtime.state.saberKilledMob then
        useBoss("Mob Leader", "the Mob Leader on Jean-Luc Island")
        local mob = findMob("Mob Leader")
        if mob then
            watchBoss(mob)
            runtime.state.status = "Saber: fighting the Mob Leader"
        else
            local spawn = findSaberSpawn("Mob Leader")
            local anchor = spawn and anchorOf(spawn)
            if anchor and (root.Position - anchor.Position).Magnitude > 700 then
                runtime.state.status = "Saber: flying to the Mob Leader"
                flyTo(anchor.Position, "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            else
                runtime.state.status = "Saber: waiting for the Mob Leader"
            end
        end
        return false
    end
    runtime.state.saberTarget = nil

    -- The Rich Man's son hands over the relic only after the Mob Leader is
    -- dead. The stages are deliberately separate: the pre-kill reply 0, the
    -- post-kill grant reply 1, the actual Relic in the inventory, and finally
    -- the UsedRelic server flag after the door accepted it.
    local relic = ownedTool("Relic")
    if not runtime.state.saberUsedRelic then
        if relic then
            -- The inventory tool is the proof that the grant happened, even
            -- when this run did not make the reply-1 request itself.
            local firstRelic = not runtime.state.saberRelicConfirmed
            runtime.state.saberRelicGrantAccepted = true
            runtime.state.saberRelicConfirmed = true
            if firstRelic then runtime.state.saberProgressAt = now end
        else
            -- Reply 1 means that the grant was accepted, but the actual Relic
            -- can still arrive late. Keep asking on a cooldown until the tool
            -- is really in the inventory. Latching reply 1 without the item
            -- used to leave Auto Saber waiting until its timeout.
            local npc = findTeacher("Rich Man")
            runtime.state.saberAt = "the Rich Man of the Pirate Village"
            if npc then
                if moveToPart(npc, 8) then
                    if now - (runtime.state.saberRelicRequestAt or 0) >= 3 then
                        local called, result = callProgress("RichSon")
                        runtime.state.saberRelicRequestAt = now
                        if called and result == 1 then
                            local firstGrant = not runtime.state.saberRelicGrantAccepted
                            runtime.state.saberRelicGrantAccepted = true
                            -- Only the first accepted grant is real progress.
                            -- Repeating reply 1 every three seconds must not
                            -- refresh the timeout forever while the item is
                            -- still missing.
                            if firstGrant then runtime.state.saberProgressAt = now end
                            runtime.state.status = "Saber: the Rich Man granted the relic, waiting for the item"
                        elseif called and result == 0 then
                            -- Reply 0 is an ephemeral dialogue result. It must not
                            -- clear an earlier accepted grant, because doing so
                            -- would make alternating replies refresh the Saber
                            -- timeout forever. Requery the authoritative state;
                            -- if the server says the Mob Leader is still needed,
                            -- the next pass returns to that boss stage.
                            runtime.state.saberSonReady = true
                            runtime.state.saberMobLeaderRequired = true
                            local freshOk, freshProgress = pcall(function()
                                return commF:InvokeServer("ProQuestProgress")
                            end)
                            if not runtime.operationValid(operationEpoch, epoch, char) then return false end
                            if freshOk and type(freshProgress) == "table" then
                                progress = freshProgress
                                runtime.state.saberProgress = progress
                                latchProgress(progress)
                            end
                            runtime.state.saberMobLeaderRequired = not runtime.state.saberKilledMob
                            if not runtime.state.saberKilledMob then
                                useBoss("Mob Leader", "the Mob Leader on Jean-Luc Island")
                                runtime.state.status = "Saber: the Rich Man still wants the Mob Leader"
                            else
                                runtime.state.status = "Saber: waiting for the granted relic"
                            end
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

        -- PlaceRelic is the official server action for the door. A truthy reply
        -- is only the acceptance; UsedRelic in the next progress query is the
        -- confirmed completion.
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
    runtime.state.saberRelicGrantAccepted = true
    runtime.state.saberRelicConfirmed = true

    -- The Saber Expert is behind the opened door. KilledShanks is the server
    -- proof that this boss died; merely disappearing is not enough.
    if not runtime.state.saberKilledShanks then
        useBoss("Saber Expert", "the Saber Expert behind the Jungle door")
        local mob = findMob("Saber Expert")
        if mob then
            watchBoss(mob)
            runtime.state.status = "Saber: fighting the Saber Expert"
        else
            local spawn = findSaberSpawn("Saber Expert")
            local anchor = spawn and anchorOf(spawn)
            if anchor and (root.Position - anchor.Position).Magnitude > 700 then
                runtime.state.status = "Saber: flying to the Saber Expert"
                flyTo(anchor.Position, "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
            local canRunSaber = false
            if not runtime.state.saberActive then
                local acquired, saberMovementToken = runtime.acquireMovement("saber")
                if acquired then
                    runtime.state.saberMovementToken = saberMovementToken
                    runtime.state.saberActive = true
                    runtime.state.saberLockAt = tick()
                    runtime.state.saberProgressAt = tick()
                    canRunSaber = true
                else
                    runtime.state.status = "Saber is waiting for the movement"
                end
            elseif runtime.state.movementOwner == "saber" then
                canRunSaber = true
            else
                local acquired, saberMovementToken = runtime.acquireMovement("saber")
                if acquired then
                    runtime.state.saberMovementToken = saberMovementToken
                    canRunSaber = true
                else
                    runtime.state.status = "Saber is waiting for the movement"
                end
            end

            if canRunSaber and not runtime.state.shopping
                and not runtime.state.shopInFlight then
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
            and not runtime.state.shopInFlight and not runtime.state.flying
            and not runtime.state.saberActive and runtime.state.movementOwner ~= "saber" then
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
        if runtime.config.AutoBuso and runtime.state.enabled
            and not runtime.state.shopping and not runtime.state.shopInFlight
            and not runtime.state.saberActive then
            local now = tick()
            if not runtime.hasAbility("Buso")
                and now - (runtime.state.busoAttemptAt or 0) >= 300 then
                runtime.state.busoAttemptAt = now
                local ok, err = pcall(function() runtime.buyAbility("Buso") end)
                if not runtime.isCurrent() then return end
                if not ok then dbg("The Buso buy failed: " .. tostring(err)) end
            end
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

local TABS = {"HOME", "MOVE", "FIGHT", "TOOLS", "STATS"}

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

local function makeTextInput(text, value, placeholder, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundTransparency = 1
    row.LayoutOrder = #page:GetChildren()
    row.Parent = page

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -48, 0, 15)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = THEME.text
    label.Font = THEME.font
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -50, 0, 27)
    box.Position = UDim2.new(0, 0, 0, 17)
    box.BackgroundColor3 = THEME.bg
    box.BorderSizePixel = 0
    box.Text = tostring(value or "")
    box.PlaceholderText = tostring(placeholder or "")
    box.PlaceholderColor3 = THEME.subtext
    box.TextColor3 = THEME.text
    box.Font = THEME.font
    box.TextSize = 11
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.Parent = row
    corner(box, 5)
    stroke(box)

    local apply = Instance.new("TextButton")
    apply.Size = UDim2.new(0, 46, 0, 27)
    apply.Position = UDim2.new(1, -46, 0, 17)
    apply.BackgroundColor3 = THEME.panel
    apply.Text = "Set"
    apply.TextColor3 = THEME.text
    apply.Font = THEME.fontBold
    apply.TextSize = 10
    apply.AutoButtonColor = false
    apply.Parent = row
    corner(apply, 5)
    stroke(apply)

    local committed = tostring(value or "")
    local function commit()
        if not runtime.isCurrent() then return end
        local nextValue = box.Text
        if nextValue == committed then return end
        committed = nextValue
        cb(nextValue)
    end
    local function setValue(nextValue)
        committed = tostring(nextValue or "")
        box.Text = committed
    end
    apply.MouseButton1Click:Connect(commit)
    box.FocusLost:Connect(commit)
    return box, commit, setValue
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
makeToggle("Safe Tween Farm", runtime.config.Dodge, function(v) runtime.config.Dodge = v end)
makeSlider("Safe Distance", 14, 45, runtime.config.DodgeRadius,
    function(v) return v.." studs" end, function(v) runtime.config.DodgeRadius = v end)
makeSlider("Move Slot Time", 200, 1000, math.floor((runtime.config.DodgeStepTime or 0.4) * 1000),
    function(v) return string.format("%.2fs", v/1000) end,
    function(v) runtime.config.DodgeStepTime = v/1000 end)
makeToggle("Short Warp", runtime.config.WarpClose, function(v) runtime.config.WarpClose = v end)
makeSlider("Warp Distance", 20, 200, runtime.config.WarpDistance,
    function(v) return v.." studs" end, function(v) runtime.config.WarpDistance = v end)
makeSlider("Void Guard Y", -1000, -50, runtime.config.SafeY,
    function(v) return tostring(v).." studs" end, function(v) runtime.config.SafeY = v end)

makeHeader("WORLD (SEA)")
makeButton("Go to Sea 1", function() spawnTracked(function() runtime.travelToWorld(1) end) end)
makeButton("Go to Sea 2", function() spawnTracked(function() runtime.travelToWorld(2) end) end)
makeButton("Go to Sea 3", function() spawnTracked(function() runtime.travelToWorld(3) end) end)
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
makeToggle("Fast Attack", runtime.config.FastAttack, function(v)
    runtime.config.FastAttack = v
    if v then runtime.state.attackCadence = runtime.config.FastAttackInterval end
end)
makeSlider("Fast Swing", 200, 1000, math.floor((runtime.config.FastAttackInterval or 0.4) * 1000),
    function(v) return string.format("%.2fs", v/1000) end,
    function(v)
        runtime.config.FastAttackInterval = v/1000
        runtime.state.attackCadence = v/1000
    end)
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
makeButton("Reset Attack State", function()
    runtime.resetCombatState()
    runtime.state.attackNextAt = 0
    dbg("Attack state reset")
end)
makeButton("Release Held Mobs", function()
    if runtime.releaseBringMobs then runtime.releaseBringMobs() end
    if runtime.restoreHitbox then runtime.restoreHitbox() end
    dbg("Held mobs released")
end)

makeHeader("AUTO QUESTS")
makeToggle("Auto Saber (First Sea puzzle)", runtime.config.AutoSaber,
    function(v)
        if v and (runtime.state.shopping or runtime.state.shopInFlight
            or runtime.state.flying or runtime.state.movementOwner == "shop"
            or runtime.state.movementOwner == "flight") then
            runtime.config.AutoSaber = false
            runtime.state.status = "Saber could not start: another movement is running"
            return
        end
        runtime.config.AutoSaber = v
        runtime.operationEpoch = (runtime.operationEpoch or 0) + 1
        runtime.stopTween()
        runtime.resetSaberState()
        if v then
            local acquired, saberMovementToken = runtime.acquireMovement("saber")
            if not acquired then
                runtime.config.AutoSaber = false
                runtime.state.status = "Saber could not start: another movement is running"
                return
            end
            runtime.state.saberMovementToken = saberMovementToken
            runtime.state.saberActive = true
            runtime.state.saberLockAt = tick()
            runtime.state.saberProgressAt = tick()
        end
    end)
makeSlider("Saber Timeout", 60, 600, runtime.config.AutoSaberTimeout,
    function(v) return v.."s" end, function(v) runtime.config.AutoSaberTimeout = v end)
makeHint("Does the Saber puzzle step by step: buttons, torch, cup, NPCs, bosses")

makeHeader("BOSS FARM")
makeToggle("Farm Bosses", runtime.config.BossFarm, function(v)
    runtime.config.BossFarm = v
    runtime.invalidateAutomaticQuestSelection("boss farming was " .. (v and "enabled" or "disabled"))
end)
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
    spawnTracked(function() runtime.buyAbility("Buso") end)
end)
makeButton("Buy Geppo (Skyjump)", function()
    spawnTracked(function() runtime.buyAbility("Geppo") end)
end)
makeButton("Buy Soru", function()
    spawnTracked(function() runtime.buyAbility("Soru") end)
end)
makeButton("Buy Observation Haki", function()
    spawnTracked(function() runtime.buyAbility("Observation") end)
end)

showTab(4) -- TOOLS
makeHeader("QUEST AND TARGET SELECTION")
local selectedMobBox, selectedMobCommit, setSelectedMobValue = makeTextInput("Selected mob", runtime.config.SelectedMob, "Auto, Nearest, or mob name", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.config.SelectedMob = value ~= "" and value or "Auto"
    runtime.state.selectedMob = runtime.config.SelectedMob
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    dbg("Selected mob: " .. runtime.config.SelectedMob)
end)
makeButton("Use Nearest Mob", function()
    runtime.config.SelectedMob = "Nearest"
    runtime.state.selectedMob = "Nearest"
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    if setSelectedMobValue then setSelectedMobValue("Nearest") end
    dbg("Selected mob: Nearest")
end)
makeTextInput("Manual quest", runtime.config.ManualQuest, "QuestName or questName#index", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.setManualQuest(value ~= "" and value or "Auto")
end)
local bossTargetBox, bossTargetCommit, setBossTargetValue = makeTextInput("Boss target", runtime.config.BossTarget, "Auto or exact boss name", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.config.BossTarget = value ~= "" and value or "Auto"
    runtime.state.selectedBoss = runtime.config.BossTarget
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    dbg("Boss target: " .. runtime.config.BossTarget)
end)
makeButton("Target Greybeard", function()
    runtime.config.BossTarget = "Greybeard"
    runtime.state.selectedBoss = "Greybeard"
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    if setBossTargetValue then setBossTargetValue("Greybeard") end
    dbg("Boss target: Greybeard")
end)
makeButton("Refresh Quest Data", function()
    spawnTracked(function() runtime.refreshQuestData() end)
end)
makeButton("Refresh Island List", function()
    if rebuildIslands then rebuildIslands() end
end)
makeSegment("Team", {"None", "Pirates", "Marines"}, runtime.config.TeamSelection, function(value)
    spawnTracked(function() runtime.setTeam(value) end)
end)

makeHeader("CODES")
local codeBox = makeTextInput("Redemption code", "", "Enter a code", function() end)
makeButton("Redeem Code", function()
    spawnTracked(function() runtime.redeemCode(codeBox.Text) end)
end)

makeHeader("CHESTS AND POLE")
makeToggle("Auto Chest", runtime.config.AutoChest, function(v)
    runtime.config.AutoChest = v
    if not v then runtime.cancelChest() end
end)
makeSlider("Chest Range", 100, 10000, runtime.config.ChestRange,
    function(v) return v .. " studs" end, function(v)
        runtime.config.ChestRange = v
        if runtime.state.chestTarget then runtime.cancelChest() end
    end)
makeSlider("Chest Timeout", 5, 120, runtime.config.ChestTimeout,
    function(v) return v .. "s" end, function(v) runtime.config.ChestTimeout = v end)
makeToggle("Pole Mastery", runtime.config.PoleMastery, function(v)
    runtime.config.PoleMastery = v
    if not v then runtime.resetPoleState() end
end)
makeTextInput("Pole target", runtime.config.PoleTarget, "Mob to hit with the pole", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.config.PoleTarget = value ~= "" and value or "Bandit"
    dbg("Pole target: " .. runtime.config.PoleTarget)
end)

makeHeader("FRUIT ESP AND NOTIFIER")
makeToggle("Fruit ESP", runtime.config.FruitESP, function(v) runtime.config.FruitESP = v end)
makeToggle("Fruit Notifier", runtime.config.FruitNotifier, function(v) runtime.config.FruitNotifier = v end)
makeTextInput("Webhook URL", runtime.config.FruitWebhook, "Optional Discord webhook", function(value)
    runtime.config.FruitWebhook = tostring(value or ""):match("^%s*(.-)%s*$") or ""
end)
makeToggle("Anti-Fall", runtime.config.AntiFall, function(v) runtime.config.AntiFall = v end)

makeHeader("SERVER HOP AND REJOIN")
makeToggle("Auto Hop", runtime.config.AutoHop, function(v)
    runtime.config.AutoHop = v
    if v then runtime.state.hopLastAt = os.time() end
end)
makeSlider("Hop Cooldown", 10, 600, runtime.config.HopCooldown,
    function(v) return v .. "s" end, function(v) runtime.config.HopCooldown = v end)
makeSlider("Max Hop Attempts", 1, 10, runtime.config.HopMaxAttempts,
    function(v) return tostring(v) end, function(v) runtime.config.HopMaxAttempts = v end)
makeToggle("Kick Recovery", runtime.config.KickRecovery, function(v) runtime.config.KickRecovery = v end)
makeTextInput("Rejoin script path", runtime.config.RejoinScriptPath, "/path/to/bloxfruit.lua", function(value)
    runtime.config.RejoinScriptPath = tostring(value or ""):match("^%s*(.-)%s*$") or ""
end)
makeButton("Hop Server Now", function()
    spawnTracked(function() runtime.hopServer("manual", true) end)
end)
makeButton("Reset Hop Attempts", function()
    runtime.resetHopAttempts()
end)
makeHint("Auto Hop waits for the cooldown; the attempt limit stops a loop")

showTab(5) -- STATS
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
        infoLabel.Text = string.format("Lv %d • Fruits: %d • Quest: %s • Spd %s • Swing %.2fs",
            getMyLevel(), runtime.state.fruitsFound, questProgressText(),
            tostring(runtime.state.attackSpeed),
            tonumber(runtime.state.attackCadence) or 0)
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












]===]

FarmRuntime.rejoinSource = EMBEDDED_REJOIN_SOURCE
    or persistedRejoinSource()
    or captureExecutorSource()
if getgenv then pcall(function() getgenv().FarmRuntime = FarmRuntime end) end
if _G then pcall(function() _G.FarmRuntime = FarmRuntime end) end

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
    operationEpoch = 0,
    state = nil,
    config = nil,
}
runtime.isCurrent = function()
    return runtime.running and FarmRuntime.current == runtime
end
-- A reset starts a new operation generation. Long operations capture the old
-- value before they yield and must not write state or keep moving after a
-- disable, re-enable, respawn or teardown.
runtime.operationValid = function(operationEpoch, characterEpoch, char)
    return runtime.isCurrent()
        and runtime.operationEpoch == operationEpoch
        and runtime.characterEpoch == characterEpoch
        and runtime.state ~= nil
        and runtime.state.enabled == true
        and (char == nil or LocalPlayer.Character == char)
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
TeleportService   = game:GetService("TeleportService")
HttpService       = game:GetService("HttpService")
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
    -- Fast Attack sends the normal RegisterAttack/RegisterHit flow at this
    -- cadence. Health feedback backs it off automatically when the server
    -- refuses a hit, so a quick cadence never turns into false confirmations.
    FastAttackInterval = 0.4,
    FastAttackFeedback = 0.55,
    RemoteAttack    = true,
    HitboxMagnitude = 120,
    WeaponMode      = "Melee",
    MeleeRange      = 50,
    GunRange        = 70,
    FruitRange      = 70,
    AutoBuyStyles   = false,
    AutoSaber       = false,
    -- The puzzle includes long walks and two boss fights. Ninety seconds
    -- stopped a healthy run halfway through; five minutes still catches a
    -- genuinely stuck step without breaking the step-by-step flow.
    AutoSaberTimeout = 300,
    MeleeHover      = 4,
    BringMob        = true,
    BringMobRange   = 60,
    -- Do not grab a mob while the player is still high above it. A purely
    -- horizontal check caught mobs across cliffs and under the ocean plane.
    BringMobVerticalRange = 18,
    BringMobCount   = 5,
    -- The proven Bring Mobs source searches the same-name pack far away.
    -- The bounded radius keeps a coast or another island out of the pack;
    -- ownership, path checks and the BringMobMax cap bound it further.
    BringMobSearch  = 300,
    -- A direct CFrame snap can jump over a narrow coast. Keep it off by
    -- default; the body mover still closes a path that was proved dry.
    BringMobSnap    = false,
    BringMobSnapDistance = 4,
    -- Carry the target under the player when this client owns it. A
    -- server-owned target keeps the source's reliable layout instead: the
    -- extras are packed around it and the player walks to the target.
    BringMobCarryTarget = true,
    -- Every carried mob gets a private, runtime-owned root BodyVelocity.
    -- The game's BodyMover intentionally refuses enemy characters, so it is
    -- never used to move a mob.
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
    -- The farm moves between safe slots around the target instead of
    -- spinning the character in place. Twenty-eight studs is outside the
    -- normal enemy melee threat and still inside the real melee/gun range.
    DodgeRadius     = 28,
    DodgeSpeed      = 90,
    DodgeStepTime   = 0.4,
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

    -- New collection and target features default off. Automatic quest and
    -- boss behaviour therefore stays exactly as it was until the user picks
    -- an explicit target or enables the extra utility.
    AutoChest       = false,
    ChestRange      = 5000,
    ChestTimeout    = 30,
    PoleMastery     = false,
    PoleTarget      = "Bandit",
    SelectedMob     = "Auto",
    ManualQuest     = "Auto",
    BossTarget      = "Auto",
    FruitESP        = false,
    FruitNotifier   = false,
    FruitWebhook    = "",
    AntiFall        = true,
    AutoHop         = false,
    HopCooldown     = 120,
    HopMaxAttempts  = 3,
    HopFailureQuarantine = 10,
    RejoinScriptPath = "/home/x86thegod/Downloads/bloxfruit.lua",
    KickRecovery    = true,
    TeamSelection   = "None",

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
    dodgeSlotAt   = 0,
    dodgeSlotIndex = 0,
    dodgeSlotTarget = nil,
    dodgeSlotAngle = 0,
    dodgePatrolCentre = nil,
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
    promptHolds   = setmetatable({}, {__mode = "k"}),
    promptHoldSeq = 0,
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
    shopMovementToken = nil,
    saberMovementToken = nil,
    styleTrialAt  = {},
    flying        = false,
    flightToken   = 0,
    flightOwner   = nil,
    flightMovementToken = nil,
    movementOwner = nil,
    movementToken = 0,
    movementOwnerToken = 0,
    whirlpooling  = false,
    questing      = false,
    bringHeld     = setmetatable({}, {__mode = "k"}),
    bringSaved    = setmetatable({}, {__mode = "k"}),
    bringSnapped  = setmetatable({}, {__mode = "k"}),
    bringCarryingTarget = setmetatable({}, {__mode = "k"}),
    bringSlot     = setmetatable({}, {__mode = "k"}),
    bringSlotCount = 0,
    bringPoint    = nil,
    bringTarget   = nil,
    bringCentre   = nil,
    bringCarryOffsetY = nil,
    bringPathBlocked = false,
    bringPathCheck = nil,
    bringPathCache = setmetatable({}, {__mode = "k"}),
    bringMover    = setmetatable({}, {__mode = "k"}),
    bringMoverSeq = 0,
    questVerified = false,
    questGaveUp   = false,
    questRemoteState = nil,
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
    attackReportedLength = 0.5,
    attackDispatched = false,
    attackRegistered = false,
    attackHitDispatched = false,
    attackConfirmed = false,
    attackPrimaryConfirmed = false,
    attackFallback = false,
    attackComboSent = false,
    attackConfirmSeq = 0,
    attackPending = {},
    attackHealthSeen = setmetatable({}, {__mode = "k"}),
    attackCadence = 0.4,
    attackMisses = 0,
    attackLastConfirmedAt = 0,
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
    saberSonReady = false,
    saberPlates = {},
    saberUsedTorch = false,
    saberUsedCup = false,
    saberKilledMob = false,
    saberUsedRelic = false,
    saberKilledShanks = false,
    saberRelicGrantAccepted = false,
    saberRelicConfirmed = false,
    saberMobLeaderRequired = false,
    saberAttemptKey = nil,
    saberAttemptAt = 0,
    saberAttempts = {},
    saberCupRequestAt = 0,
    saberCupGranted = false,
    saberCupTouched = false,
    saberCupTouchAt = 0,
    saberCupTouchTool = nil,
    saberCupTouchWater = nil,
    saberCupTouchHandle = nil,
    saberCupTouchConnection = nil,
    saberFillRequestAt = 0,
    saberFillPending = false,
    saberFillSickAt = 0,
    saberFillSickResult = nil,
    saberRelicRequestAt = 0,
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
    -- Feature state is transient unless it lives in CONFIG. Weak tables are
    -- used for instances so a removed fruit, chest or mob cannot leave stale
    -- objects behind.
    fruitEspVisuals = setmetatable({}, {__mode = "k"}),
    notifiedFruits  = setmetatable({}, {__mode = "k"}),
    -- Notification success belongs to one destination. Changing the webhook
    -- must allow the same fruit to be delivered to the new URL.
    notifiedFruitUrls = setmetatable({}, {__mode = "k"}),
    -- A notification is marked only after the webhook accepted it. Failed
    -- requests stay here and are retried with a small backoff.
    fruitNotificationPending = setmetatable({}, {__mode = "k"}),
    chestSeen       = setmetatable({}, {__mode = "k"}),
    chestTarget     = nil,
    chestTargetPart = nil,
    chestTargetIdentityPart = nil,
    chestStartedAt  = 0,
    chestSelectedAt = 0,
    chestTravelDeadline = 0,
    chestLastTry    = 0,
    chestLastScanAt = 0,
    chestToken      = 0,
    chestMovementToken = nil,
    chestTouchAt    = 0,
    chestTouchPart  = nil,
    chestTouchRoot  = nil,
    chestSequence   = 0,
    chestTouchSequence = 0,
    chestTouchRewardBaselineAt = 0,
    chestTouchBeliBefore = nil,
    chestTouchFruitBefore = nil,
    chestTouchFragmentsBefore = nil,
    chestServerAt   = 0,
    chestServerState = nil,
    chestOpenedAt   = 0,
    chestCollectedAt = 0,
    chestDisabledAt = 0,
    chestOpenedSequence = 0,
    chestCollectedSequence = 0,
    chestDisabledSequence = 0,
    chestBeliBefore = nil,
    chestFruitBefore = nil,
    chestFragmentsBefore = nil,
    chestRewardBaselineAt = 0,
    chestConnections = {},
    poleToken       = 0,
    poleLevel       = 0,
    poleExp         = 0,
    poleHits        = 0,
    poleEquipped    = false,
    poleWeapon      = nil,
    poleMovementToken = nil,
    codeToken       = 0,
    codeInFlight    = false,
    teamToken       = 0,
    teamInFlight    = false,
    currentTeam     = "None",
    travelToken     = 0,
    travelMovementToken = nil,
    travelActive    = false,
    currentSea      = nil,
    currentSeaAt    = 0,
    seaDetectionToken = 0,
    questRevision   = 0,
    questCatalogToken = 0,
    questCatalogLoading = false,
    questRequestToken = 0,
    questRequestInFlight = false,
    selectedMob     = nil,
    selectedBoss    = nil,
    hopToken        = 0,
    hopAttempt      = 0,
    hopStartedAt    = 0,
    hopLastAt       = 0,
    hopInFlight     = false,
    hopQueued       = false,
    hopFailureAt    = 0,
    hopFailureSource = nil,
    hopFailureQuarantineUntil = 0,
    hopMovementToken = nil,
    hopQueuedAt     = 0,
    hopExhaustedNotified = false,
    hopJobId        = "",
    manualQuestKey  = nil,
    manualQuestRequestAt = 0,
    manualQuestRevision = 0,
    manualQuestSentKey = nil,
    manualQuestAttempts = 0,
    manualQuestRequestRevision = 0,
    manualQuestRequestId = 0,
    questRefreshAt  = 0,
    islandRevision  = 0,
}

runtime.config = CONFIG
runtime.state = state
state.hopAttempt = tonumber(FarmHopBootstrap.attempt) or 0
state.hopStartedAt = tonumber(FarmHopBootstrap.startedAt) or os.time()
state.hopLastAt = tonumber(FarmHopBootstrap.lastAt) or state.hopStartedAt
state.hopJobId = tostring(FarmHopBootstrap.jobId or "")
if type(FarmHopBootstrap.path) == "string" and FarmHopBootstrap.path ~= "" then
    CONFIG.RejoinScriptPath = FarmHopBootstrap.path
end

-- Shop, flight and Saber are exclusive movement owners. Ordinary farming can
-- still move the character while Saber is fighting a boss, but two long
-- operations must never cancel or retarget each other's tween.
runtime.acquireMovement = function(owner)
    if not owner then return false end
    local current = runtime.state.movementOwner
    if current then
        if current ~= owner then return false end
        -- Re-entering the same owner keeps its token. A nested shop flight or
        -- Saber step must not invalidate the outer operation that owns it.
        return true, runtime.state.movementOwnerToken
    end
    runtime.state.movementToken = (runtime.state.movementToken or 0) + 1
    runtime.state.movementOwnerToken = runtime.state.movementToken
    runtime.state.movementOwner = owner
    return true, runtime.state.movementOwnerToken
end
runtime.releaseMovement = function(owner, ownerToken)
    if runtime.state.movementOwner == owner
        and (ownerToken == nil or runtime.state.movementOwnerToken == ownerToken) then
        runtime.state.movementOwner = nil
        runtime.state.movementOwnerToken = 0
    end
end

-- Transient state is reset as one unit. A disabled bot, a character change, a
-- Saber timeout and a fresh enable must never inherit an old attack combo,
-- prompt throttle, burst window or half-finished puzzle action.
runtime.resetSaberState = function()
    local s = runtime.state
    s.saberActive = false
    if runtime.releaseTweenHold then runtime.releaseTweenHold() end
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
    s.saberSonReady = false
    s.saberPlates = {}
    s.saberUsedTorch = false
    s.saberUsedCup = false
    s.saberKilledMob = false
    s.saberUsedRelic = false
    s.saberKilledShanks = false
    s.saberRelicGrantAccepted = false
    s.saberRelicConfirmed = false
    s.saberMobLeaderRequired = false
    local saberMovementToken = s.saberMovementToken
    s.saberMovementToken = nil
    if runtime.releaseMovement then runtime.releaseMovement("saber", saberMovementToken) end
    s.saberAttemptKey = nil
    s.saberAttemptAt = 0
    s.saberAttempts = {}
    s.saberCupRequestAt = 0
    s.saberCupGranted = false
    if s.saberDesertCupConnection then
        pcall(function() s.saberDesertCupConnection:Disconnect() end)
    end
    s.saberDesertCupConnection = nil
    s.saberDesertCupTouched = false
    s.saberDesertCupTouchPart = nil
    s.saberDesertCupTouchAt = 0
    if s.saberCupTouchConnection then
        pcall(function() s.saberCupTouchConnection:Disconnect() end)
    end
    s.saberCupTouchConnection = nil
    s.saberCupTouched = false
    s.saberCupTouchAt = 0
    s.saberCupTouchTool = nil
    s.saberCupTouchWater = nil
    s.saberCupTouchHandle = nil
    s.saberFillRequestAt = 0
    s.saberFillPending = false
    s.saberFillSickAt = 0
    s.saberFillSickResult = nil
    s.saberRelicRequestAt = 0
    s.saberPlaceRequestAt = 0
    s.saberPlaceAccepted = false
end

-- A fallback prompt hold belongs to the bot until the hold has ended. A
-- character change, a reset or teardown must not leave a hidden hold on the
-- new character, so every bot-started hold is ended explicitly.
runtime.endPromptHolds = function()
    local holds = runtime.state and runtime.state.promptHolds
    if not holds then return end
    for prompt in pairs(holds) do
        -- Remove the marker before ending the hold. A completion task from the
        -- old hold then cannot end a newer hold on the same prompt.
        holds[prompt] = nil
        pcall(function() prompt:InputHoldEnd() end)
    end
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
    s.attackReportedLength = 0.5
    s.attackDispatched, s.attackRegistered, s.attackHitDispatched = false, false, false
    s.attackConfirmed, s.attackPrimaryConfirmed = false, false
    s.attackFallback, s.attackComboSent = false, false
    -- Confirmation sequence numbers are never reused. An old watcher that is
    -- still finishing must not mistake a reset run for its own sequence.
    s.attackConfirmSeq = (s.attackConfirmSeq or 0) + 1
    s.attackPending = {}
    s.attackHealthSeen = setmetatable({}, {__mode = "k"})
    s.attackCadence = tonumber(runtime.config.FastAttackInterval) or 0.4
    s.attackMisses = 0
    s.attackLastConfirmedAt = 0
    s.aoeCount, s.aoeRequested, s.aoeConfirmed = 0, 0, 0
    s.hitsConfirmed = 0
    s.lastHitAt, s.lastHitMob = nil, nil
    s.lastTarget, s.targetHealth, s.targetAt, s.targetDist = nil, nil, 0, nil
    s.travelAt = 0
    s.lastRemoteAttackAt = nil
    s.combatUtil, s.combatUtilMod = nil, nil
    s.netModule, s.netModuleInstance = nil, nil
    s.hitRemoteCache, s.attackRemoteCache = nil, nil
    s.hitUseFallback = false
end

-- A purchase owns the main loop while it walks to a teacher or waits for a
-- server reply. Invalidate it as one unit so an old RPC can never leave the
-- new run permanently stuck behind stale shopping flags.
runtime.resetShopState = function()
    local s = runtime.state
    s.shopping = false
    s.shopInFlight = false
    s.shopToken = (s.shopToken or 0) + 1
    s.blockAt = nil
    local shopMovementToken = s.shopMovementToken
    s.shopMovementToken = nil
    if runtime.releaseMovement then runtime.releaseMovement("shop", shopMovementToken) end
end

-- Pole progress is tied to one real Pole tool. A tool replacement, a mode
-- change, a respawn or a teardown starts a fresh passive-mastery session.
runtime.resetPoleState = function()
    local s = runtime.state
    s.poleToken = (s.poleToken or 0) + 1
    s.poleLevel = 0
    s.poleExp = 0
    s.poleHits = 0
    s.poleEquipped = false
    s.poleProgressAt = 0
    s.poleWeapon = nil
    if runtime.releaseMovement and s.poleMovementToken then
        runtime.releaseMovement("pole", s.poleMovementToken)
    end
    s.poleMovementToken = nil
end

runtime.resetTransient = function()
    -- Invalidate every operation that can yield. The old attack, quest, flight
    -- or prompt task may wake up after this point; it must leave without
    -- touching the new state.
    runtime.operationEpoch = (runtime.operationEpoch or 0) + 1
    runtime.resetSaberState()
    runtime.resetCombatState()
    runtime.resetShopState()
    runtime.resetFeatureState()
    -- Invalidate an old flight before a new one can start. The old coroutine
    -- must never clear the new flight's flag when it wakes up later.
    local flightOwner = runtime.state.flightOwner
    local flightOwnerToken = runtime.state.flightMovementToken
    runtime.state.flightToken = (runtime.state.flightToken or 0) + 1
    runtime.state.flightOwner = nil
    runtime.state.flightMovementToken = nil
    runtime.state.flying = false
    if flightOwner and runtime.releaseMovement then
        runtime.releaseMovement(flightOwner, flightOwnerToken)
    end
    if runtime.endPromptHolds then runtime.endPromptHolds() end
    local s = runtime.state
    s.lastPrompt, s.promptAt = nil, 0
    s.autoBurst, s.autoBurstCd = 0, 0
    s.questing = false
    -- Turn-in and quest-seek deadlines belong to the old attempt. Keeping
    -- them across a disable, respawn or re-enable can make the next run give
    -- up before its first request or wait on a target that no longer exists.
    s.turnInSince, s.turnInFailed, s.turnInFailedAt = nil, false, 0
    s.seekSince, s.seekGaveUp, s.seekGaveUpAt = nil, false, 0
    s.dodgeSlotAt, s.dodgeSlotIndex = 0, 0
    s.dodgeSlotTarget, s.dodgeSlotAngle, s.dodgePatrolCentre = nil, 0, nil
    s.farming = false
end

local grabbedFruits = setmetatable({}, {__mode = "k"})

-- The feature requests that can yield have their own tokens. A reset, a
-- respawn or a second execution must not let an old chest, code, team, travel
-- or Pole reply write into the new state.
runtime.resetFeatureState = function()
    local s = runtime.state
    local chestMovementToken = s.chestMovementToken
    if chestMovementToken == nil and s.movementOwner == "chest" then
        chestMovementToken = s.movementOwnerToken
    end
    local chestOwnsMovement = s.movementOwner == "chest"
        and s.movementOwnerToken == chestMovementToken
    local travelMovementToken = s.travelMovementToken
    local hopMovementToken = s.hopMovementToken
    s.chestToken = (s.chestToken or 0) + 1
    if runtime.clearChestConnections then runtime.clearChestConnections() end
    s.codeToken = (s.codeToken or 0) + 1
    s.teamToken = (s.teamToken or 0) + 1
    s.travelToken = (s.travelToken or 0) + 1
    if runtime.cancelHopMetadata then runtime.cancelHopMetadata(s.hopToken) end
    s.hopToken = (s.hopToken or 0) + 1
    -- A cancelled teleport can still emit one late TeleportInitFailed event.
    -- Keep a short quarantine in which no new request may start, so that late
    -- event cannot be attributed to the newer request.
    local hopQuarantine = math.max(0, tonumber(runtime.config.HopFailureQuarantine) or 10)
    s.hopFailureQuarantineUntil = os.time() + hopQuarantine
    s.hopFailureSource = "cancelled"
    s.codeInFlight = false
    s.teamInFlight = false
    s.travelActive = false
    s.hopInFlight = false
    s.hopQueued = false
    s.hopMovementToken = nil
    s.hopQueuedAt = 0
    s.chestTarget, s.chestTargetPart = nil, nil
    s.chestTargetIdentityPart = nil
    s.chestStartedAt, s.chestSelectedAt, s.chestLastTry = 0, 0, 0
    s.chestTravelDeadline, s.chestLastScanAt = 0, 0
    s.chestTouchAt, s.chestTouchPart, s.chestTouchRoot = 0, nil, nil
    s.chestSequence, s.chestTouchSequence = 0, 0
    s.chestTouchRewardBaselineAt = 0
    s.chestTouchBeliBefore = nil
    s.chestTouchFruitBefore = nil
    s.chestTouchFragmentsBefore = nil
    s.chestServerAt, s.chestServerState = 0, nil
    s.chestOpenedAt, s.chestCollectedAt, s.chestDisabledAt = 0, 0, 0
    s.chestOpenedSequence, s.chestCollectedSequence = 0, 0
    s.chestDisabledSequence = 0
    s.chestBeliBefore = nil
    s.chestFruitBefore = nil
    s.chestFragmentsBefore = nil
    s.chestRewardBaselineAt = 0
    s.chestMovementToken = nil
    s.travelMovementToken = nil
    -- Force a fresh Realm check after a reset instead of trusting a sea
    -- value that belonged to the previous character or server. Invalidate an
    -- older Realm lookup as well as the operation epoch.
    s.currentSea = nil
    s.currentSeaAt = 0
    s.seaDetectionToken = (s.seaDetectionToken or 0) + 1
    -- A catalog load that is still yielding belongs to the old runtime. It
    -- must not install its result or leave new requests blocked.
    s.questCatalogToken = (s.questCatalogToken or 0) + 1
    s.questCatalogLoading = false
    s.selectedMob, s.selectedBoss = nil, nil
    -- A reset invalidates an in-flight manual request. The selected quest stays
    -- in the configuration, but its request counters and reply revision start
    -- from a clean state on the next run.
    s.manualQuestRevision = (s.manualQuestRevision or 0) + 1
    s.questRequestToken = (s.questRequestToken or 0) + 1
    s.questRequestInFlight = false
    s.manualQuestRequestAt = 0
    s.manualQuestSentKey = nil
    s.manualQuestAttempts = 0
    s.manualQuestRequestRevision = 0
    -- Keep request ids monotonic across a reset. An old response must not
    -- be able to clear the marker of a new request that happens to reuse the
    -- same numeric id after the state was recreated.
    s.manualQuestRequestId = (s.manualQuestRequestId or 0) + 1
    s.lastManualQuest = nil
    if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
    -- Hop attempt metadata is deliberately not reset here. A disable/re-enable
    -- must not turn an automatic hop loop back into attempt zero.
    if runtime.destroyFruitEsp then runtime.destroyFruitEsp() end
    if runtime.resetPoleState then runtime.resetPoleState() end
    if chestOwnsMovement and runtime.stopTween then runtime.stopTween() end
    if runtime.releaseMovement then
        runtime.releaseMovement("chest", chestMovementToken)
        runtime.releaseMovement("travel", travelMovementToken)
        runtime.releaseMovement("hop", hopMovementToken)
    end
end

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

-- ================= SERVER HOP / REJOIN =================
-- A hop is two coordinated actions. The exact source is queued for the new
-- server and TeleportService starts the same-place teleport. The queued
-- bootstrap carries the attempt number as literals, so the chain cannot be
-- restarted from zero if the executor clears its global environment while the
-- client is changing servers.
runtime.hopBootstrapSource = function(path, attempt, startedAt, lastAt, reason,
    requestToken, rejoinSource)
    return string.format([=[
local REJOIN_PATH = %q
local HOP_ATTEMPT = %d
local HOP_STARTED_AT = %d
local HOP_LAST_AT = %d
local HOP_REASON = %q
local HOP_REQUEST_TOKEN = %d
local REJOIN_SOURCE = %q

local function executorEnvironment()
    local env
    if type(getgenv) == "function" then
        pcall(function() env = getgenv() end)
    end
    if type(env) ~= "table" then env = _G end
    if type(env) ~= "table" then env = {} end
    return env
end

local env = executorEnvironment()
local meta = env.FarmHopBootstrap
-- The executor global is the cancellation authority. A queued bootstrap from
-- an older request must not overwrite or start a newer hop chain.
local stale = type(meta) ~= "table"
    or tonumber(meta.requestToken) ~= HOP_REQUEST_TOKEN
    or meta.cancelled == true
if not stale then
meta.attempt = HOP_ATTEMPT
meta.startedAt = HOP_STARTED_AT
meta.lastAt = HOP_LAST_AT
meta.path = REJOIN_PATH
meta.reason = HOP_REASON
meta.requestToken = HOP_REQUEST_TOKEN
meta.cancelled = false
if type(REJOIN_SOURCE) == "string" and REJOIN_SOURCE ~= "" then
    meta.source = REJOIN_SOURCE
end
env.FarmHopBootstrap = meta
if type(getgenv) == "function" then
    pcall(function() getgenv().FarmHopBootstrap = meta end)
end
if type(_G) == "table" then _G.FarmHopBootstrap = meta end

local function compileAndRun(source)
    local loader = type(loadstring) == "function" and loadstring or load
    if type(loader) ~= "function" then return false, "no source loader" end
    local chunk, err = loader(source)
    if type(chunk) ~= "function" then return false, tostring(err) end
    chunk()
    return true
end

local function runRejoin()
    -- An embedding executor may provide the exact source directly. The file
    -- path is the normal route and is checked first so a stale embedded copy
    -- can never replace the file the user selected. A path read failure is
    -- not terminal: the executor may deliberately reject host paths while
    -- still supporting the source embedded in this bootstrap.
    local pathError = nil
    if type(readfile) == "function" then
        local ok, source = pcall(readfile, REJOIN_PATH)
        if ok and type(source) == "string" and source ~= "" then
            local ran, err = compileAndRun(source)
            if ran then return end
            error(err)
        end
        pathError = type(source) == "string" and source or "readfile failed"
    end
    if type(loadfile) == "function" then
        local ok, chunk, err = pcall(loadfile, REJOIN_PATH)
        if ok and type(chunk) == "function" then
            chunk()
            return
        end
        pathError = type(err) == "string" and err or pathError
    end
    if type(dofile) == "function" then
        local ok, err = pcall(dofile, REJOIN_PATH)
        if ok then return end
        pathError = type(err) == "string" and err or pathError
    end
    if type(meta.source) == "string" and meta.source ~= "" then
        local ran, err = compileAndRun(meta.source)
        if ran then return end
        error(err)
    end
    error("the executor cannot read the rejoin script"
        .. (type(pathError) == "string" and (": " .. pathError) or ""))
end

runRejoin()
end
]=], tostring(path or ""), tonumber(attempt) or 1,
        tonumber(startedAt) or os.time(), tonumber(lastAt) or os.time(),
        tostring(reason or "hop"), tonumber(requestToken) or 0,
        tostring(rejoinSource or ""))
end

runtime.writeHopMetadata = function(attempt, startedAt, lastAt, path, reason,
    requestToken, rejoinSource)
    local meta = FarmHopBootstrap
    if type(meta) ~= "table" then meta = {} end
    meta.attempt = tonumber(attempt) or 0
    meta.startedAt = tonumber(startedAt) or os.time()
    meta.lastAt = tonumber(lastAt) or os.time()
    meta.path = tostring(path or runtime.config.RejoinScriptPath or "")
    meta.reason = tostring(reason or "hop")
    meta.jobId = tostring(game.JobId or "")
    meta.requestToken = tonumber(requestToken) or 0
    meta.cancelled = false
    if type(rejoinSource) == "string" and rejoinSource ~= "" then
        meta.source = rejoinSource
    end
    FarmHopBootstrap = meta
    if getgenv then pcall(function() getgenv().FarmHopBootstrap = meta end) end
    if _G then pcall(function() _G.FarmHopBootstrap = meta end) end
    return meta
end

runtime.cancelHopMetadata = function(requestToken)
    local meta = FarmHopBootstrap
    if type(meta) ~= "table" then return false end
    local owner = tonumber(meta.requestToken)
    if requestToken ~= nil and owner ~= tonumber(requestToken) then return false end
    meta.cancelled = true
    return true
end

runtime.failHop = function(requestToken, movementToken, reason, failureSource)
    local s = runtime.state
    if requestToken == nil or s.hopToken ~= requestToken then return false end
    -- The queued source cannot be removed from the executor. Mark this exact
    -- request cancelled so a late teleport cannot revive it.
    if runtime.cancelHopMetadata then runtime.cancelHopMetadata(requestToken) end
    s.hopInFlight = false
    s.hopQueued = false
    s.hopQueuedAt = 0
    s.hopFailureAt = os.time()
    s.hopFailureSource = tostring(failureSource or "request")
    -- A timeout or cancellation may still have one late failure event in
    -- flight. Quarantine a new request briefly so that event cannot clear the
    -- newer request's movement owner. A failure event already consumed by
    -- this handler needs no such quarantine.
    if s.hopFailureSource ~= "event" then
        local quarantine = math.max(0, tonumber(runtime.config.HopFailureQuarantine) or 10)
        s.hopFailureQuarantineUntil = os.time() + quarantine
    end
    local ownedToken = movementToken or s.hopMovementToken
    s.hopMovementToken = nil
    runtime.releaseMovement("hop", ownedToken)
    dbg("Server hop failed: " .. tostring(reason or "unknown reason"))
    return true
end

runtime.hopServer = function(reason, manual)
    local s = runtime.state
    reason = tostring(reason or "manual")
    manual = manual == true
    if s.hopInFlight then
        dbg("A server hop is already running")
        return false
    end
    local quarantineUntil = tonumber(s.hopFailureQuarantineUntil) or 0
    if os.time() < quarantineUntil then
        dbg("Server hop is waiting for the previous teleport failure to settle")
        return false
    end
    local maxAttempts = math.max(1, math.floor(tonumber(runtime.config.HopMaxAttempts) or 3))
    local attempt = math.max(0, math.floor(tonumber(s.hopAttempt) or 0))
    local startedAt = tonumber(s.hopStartedAt) or os.time()
    if manual then
        -- A button press starts a new chain. Automatic hops keep counting the
        -- old chain and cannot use a manual reset to bypass the limit.
        attempt = 0
        startedAt = os.time()
        s.hopExhaustedNotified = false
    elseif attempt >= maxAttempts then
        if not s.hopExhaustedNotified then
            s.hopExhaustedNotified = true
            dbg("Server hop stopped: the attempt limit was reached")
        end
        return false
    end
    local path = tostring(runtime.config.RejoinScriptPath or ""):match("^%s*(.-)%s*$") or ""
    if path == "" then
        dbg("Server hop failed: the rejoin script path is empty")
        return false
    end
    if type(queue_on_teleport) ~= "function" then
        dbg("Server hop failed: queue_on_teleport is not available")
        return false
    end

    local acquired, movementToken = runtime.acquireMovement("hop")
    if not acquired and reason == "kick" then
        -- A kick is the one case where the old movement owner must not keep
        -- the client in the server it is being removed from.
        local oldOwner = s.movementOwner
        local oldToken = s.movementOwnerToken
        runtime.operationEpoch = (runtime.operationEpoch or 0) + 1
        if oldOwner then runtime.releaseMovement(oldOwner, oldToken) end
        acquired, movementToken = runtime.acquireMovement("hop")
    end
    if not acquired then
        dbg("Server hop failed: another movement operation is running")
        return false
    end

    local requestToken = (s.hopToken or 0) + 1
    s.hopToken = requestToken
    s.hopInFlight = true
    s.hopMovementToken = movementToken
    runtime.stopTween()

    local now = os.time()
    local nextAttempt = attempt + 1
    local rejoinSource = type(FarmRuntime.rejoinSource) == "string"
        and FarmRuntime.rejoinSource or ""
    -- Publish the request token before queueing. The bootstrap checks this
    -- exact token after the teleport and refuses to run if a newer request or
    -- a cancellation replaced it.
    runtime.writeHopMetadata(nextAttempt, startedAt, now, path, reason,
        requestToken, rejoinSource)
    local source = runtime.hopBootstrapSource(path, nextAttempt, startedAt, now,
        reason, requestToken, rejoinSource)
    local queued, queueError = pcall(queue_on_teleport, source)
    if not queued then
        runtime.failHop(requestToken, movementToken, queueError)
        return false
    end

    s.hopAttempt = nextAttempt
    s.hopStartedAt = startedAt
    s.hopLastAt = now
    s.hopQueued = true
    s.hopQueuedAt = now
    s.hopFailureAt = 0
    s.hopFailureSource = nil
    s.hopExhaustedNotified = false

    local placeId = game.PlaceId
    local teleported, teleportError = pcall(function()
        -- Teleport is the last client-side teleport API. TeleportAsync is now
        -- server-only; this experience still accepts the client request.
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
    if not teleported then
        runtime.failHop(requestToken, movementToken, teleportError)
        return false
    end
    runtime.state.status = "Changing server..."
    dbg("Server hop " .. tostring(nextAttempt) .. " was queued")
    return true
end

runtime.resetHopAttempts = function()
    local s = runtime.state
    if s.hopInFlight or s.hopQueued then
        dbg("The hop attempt list cannot be reset while a hop is running")
        return false
    end
    local now = os.time()
    -- Even though the live flags are already clear, a queued source may still
    -- exist in the executor. Replace its request token so it cannot revive an
    -- old attempt after the user resets the chain.
    if runtime.cancelHopMetadata then runtime.cancelHopMetadata(s.hopToken) end
    local quarantine = math.max(0, tonumber(runtime.config.HopFailureQuarantine) or 10)
    s.hopFailureQuarantineUntil = now + quarantine
    s.hopFailureSource = "cancelled"
    s.hopAttempt = 0
    s.hopStartedAt = now
    s.hopLastAt = now
    s.hopExhaustedNotified = false
    s.hopFailureAt = 0
    runtime.writeHopMetadata(0, now, now, runtime.config.RejoinScriptPath, "reset", 0)
    dbg("Server hop attempts were reset")
    return true
end

runtime.updateHopScheduler = function()
    local s = runtime.state
    if s.hopQueued then
        -- A client can accept the queue and still lose the teleport before it
        -- starts. This check must run before the in-flight guard: a queued hop
        -- keeps both flags set while the teleport request is pending.
        local queuedAt = tonumber(s.hopQueuedAt) or 0
        if queuedAt > 0 and os.time() - queuedAt >= 30 then
            runtime.failHop(s.hopToken, s.hopMovementToken, "teleport timed out", "timeout")
        end
        return false
    end
    if s.hopInFlight then return false end
    if not runtime.config.AutoHop or not s.enabled then return false end
    local maxAttempts = math.max(1, math.floor(tonumber(runtime.config.HopMaxAttempts) or 3))
    local attempt = math.max(0, math.floor(tonumber(s.hopAttempt) or 0))
    if attempt >= maxAttempts then
        if not s.hopExhaustedNotified then
            s.hopExhaustedNotified = true
            dbg("Automatic server hop stopped: the attempt limit was reached")
        end
        return false
    end
    local cooldown = math.max(0, tonumber(runtime.config.HopCooldown) or 120)
    local lastAt = tonumber(s.hopLastAt) or tonumber(s.hopStartedAt) or os.time()
    if os.time() - lastAt < cooldown then return false end
    return runtime.hopServer("auto", false)
end

runtime.armHopRecovery = function()
    local playerConnection = Players.PlayerRemoving:Connect(function(player)
        if player ~= LocalPlayer or not runtime.config.KickRecovery then return end
        if not runtime.isCurrent() then return end
        runtime.hopServer("kick", false)
    end)
    table.insert(runtime.hookConnections, playerConnection)

    local teleportFailure = TeleportService.TeleportInitFailed:Connect(function(player, result, message)
        if player ~= LocalPlayer then return end
        local s = runtime.state
        if not s.hopInFlight then return end
        -- TeleportInitFailed has no request id. Cancelled and timed-out
        -- requests quarantine the next request, so an old late event is
        -- consumed while no new hop owns the movement. A genuine failure of
        -- the current request is then handled normally; no sticky
        -- "prior failure" flag may hide later failures.
        if os.time() < (tonumber(s.hopFailureQuarantineUntil) or 0) then return end
        local detail = tostring(result or "")
        if message and message ~= "" then detail = detail .. ": " .. tostring(message) end
        runtime.failHop(s.hopToken, s.hopMovementToken, detail, "event")
    end)
    table.insert(runtime.hookConnections, teleportFailure)
end

runtime.armHopRecovery()
table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(1)
        if not runtime.isCurrent() then return end
        runtime.updateHopScheduler()
    end
end))

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
    if type(value) == "number" then return math.floor(tonumber(value) or 0) end
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local alt = stats and stats:FindFirstChild("Level")
    value = readNumber(alt)
    if type(value) == "number" then return math.floor(tonumber(value) or 0) end
    return 1
end

local function toolKind(tool)
    local tip = tool.ToolTip
    if type(tip) == "string" and tip ~= "" then return tip:lower() end
    return nil
end

local function isFruit(t)
    if t.Name:lower():find("fruit", 1, true) then return true end
    -- Current official fruit tools can be named "Light-Light" or "Ice-Ice"
    -- and identify themselves with the exact tooltip "Blox Fruit". Do not use
    -- an ItemId alone: weapon-only ItemIds are not fruits.
    local kind = toolKind(t)
    return kind == "fruit" or kind == "blox fruit"
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
    if runtime.config.PoleMastery then
        -- Pole Mastery is a dedicated mode. Falling back to another weapon
        -- would give hits to the wrong mastery and reset the attack combo.
        return runtime.equipPole and runtime.equipPole() or nil
    end
    if runtime.state.poleWeapon and runtime.resetPoleState then runtime.resetPoleState() end
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
    -- Bring Mob owns the collision state of a held rig. Restoring the hitbox
    -- while that rig is still held must not turn its collision back on. Once
    -- the Bring Mob snapshot is gone, the original hitbox value is safe to
    -- restore again.
    local managedByBring = false
    for _, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.parts and saved.parts[part] then
            managedByBring = true
            break
        end
    end
    if not managedByBring then
        pcall(function() part.CanCollide = runtime.state.hitboxOrigCollide end)
    end
end

local function enlargeHitbox(target)
    local anchor = anchorOf(target)
    if not anchor or not anchor.Size then return end
    if runtime.state.hitboxPart and runtime.state.hitboxPart ~= anchor then restoreHitbox() end
    local size = runtime.config.HitboxSize or 16
    if anchor.Size.X >= size then return end
    runtime.state.hitboxAt = tick()
    runtime.state.hitboxOrigSize = anchor.Size
    -- If Bring Mob has already changed this rig, the hitbox snapshot must
    -- remember the game's original collision value, not the temporary false
    -- value used by the hold.
    local originalCollide = anchor.CanCollide
    for _, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.parts and saved.parts[anchor] then
            originalCollide = saved.parts[anchor].collide
            break
        end
    end
    runtime.state.hitboxOrigCollide = originalCollide
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

-- QuestUpdate does not carry the quest index in the current game.  The
-- official quest table does, and the task table is the only stable identity
-- that can be compared with the update.  Build a canonical signature so the
-- comparison is independent of table iteration order.  A signature is also
-- used to reject an ambiguous index instead of accepting the wrong quest.
local function questTaskSignature(task)
    if type(task) ~= "table" then return nil end
    local keys = {}
    for key, value in pairs(task) do
        if type(key) ~= "string" or type(value) ~= "number" then return nil end
        keys[#keys + 1] = key
    end
    if #keys == 0 then return nil end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = tonumber(task[key])
        parts[#parts + 1] = string.format("%d:%s=%s", #key, key, tostring(value))
    end
    return table.concat(parts, "|")
end
runtime.questTaskSignature = questTaskSignature

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
                            task = quest.Task,
                            taskKey = questTaskSignature(quest.Task),
                            -- The quest module itself has no sea field. The
                            -- official records put Area1Quest (level 700) in
                            -- the Second Sea and CakeQuest2 (level 2250) in
                            -- the Third Sea, so those two boundaries are
                            -- exclusive on the lower world.
                            sea = level < 700 and 1 or (level < 2250 and 2 or 3),
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
                                task = quest.Task,
                                taskKey = questTaskSignature(quest.Task),
                                sea = need < 700 and 1 or (need < 2250 and 2 or 3),
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
                                base.sea = need < 700 and 1 or (need < 2250 and 2 or 3)
                            end
                            known = true
                        end
                    end
                end
                if known then data.guideNames[npc.InternalQuestName] = true end
            end
        end
    end
    -- A task signature is normally unique within a quest line.  Keep the
    -- ambiguity flag, though: if a future quest table has two indexes with
    -- the same task, an update without an index cannot safely identify one
    -- of them and the manual selector must refuse it.
    local taskIndexes = {}
    for _, entry in ipairs(data.quests) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = taskIndexes[key]
            if not indexes then
                indexes = {}
                taskIndexes[key] = indexes
            end
            indexes[tostring(entry.index)] = true
        end
    end
    for _, entry in ipairs(data.quests) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = taskIndexes[key] or {}
            local count = 0
            for _ in pairs(indexes) do count = count + 1 end
            entry.taskAmbiguous = count > 1
        end
    end
    local guideTaskIndexes = {}
    for _, entry in ipairs(data.guide) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = guideTaskIndexes[key]
            if not indexes then
                indexes = {}
                guideTaskIndexes[key] = indexes
            end
            indexes[tostring(entry.index)] = true
        end
    end
    for _, entry in ipairs(data.guide) do
        if entry.taskKey then
            local key = entry.name .. "\0" .. entry.taskKey
            local indexes = guideTaskIndexes[key] or {}
            local count = 0
            for _ in pairs(indexes) do count = count + 1 end
            entry.taskAmbiguous = count > 1
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
    -- A manual quest is identified by the exact quest key (Name#index), or by
    -- Name when the player wants the newest available index. Automatic quest
    -- selection is untouched while ManualQuest is "Auto".
    local wanted = runtime.config.ManualQuest
    if wanted and wanted ~= "Auto" and wanted ~= "" then
        local selected, selectedIndex
        local exactName, exactIndex = wanted:match("^(.-)#(%d+)$")
        local exactNumber = tonumber(exactIndex)
        for _, q in ipairs(gameQuests or {}) do
            local exact = exactName and q.name == exactName
                and tonumber(q.index) == exactNumber
            if exact then
                selected, selectedIndex = q, q.index
                break
            elseif not exactName and q.name == wanted
                and (q.level or 0) <= (level or 0) then
                -- A bare name means the highest eligible index, not merely
                -- the quest with the highest level requirement.
                local candidateIndex = tonumber(q.index) or 0
                local currentIndex = tonumber(selectedIndex) or 0
                if not selected or candidateIndex > currentIndex then
                    selected, selectedIndex = q, q.index
                end
            end
        end
        if selected then
            return {name = selected.name, index = selected.index, mob = selected.mob,
                count = selected.count, level = selected.level, sea = selected.sea,
                pos = selected.pos, npc = selected.npc, task = selected.task,
                taskKey = selected.taskKey, taskAmbiguous = selected.taskAmbiguous}
        end
        if runtime.state.lastManualQuest ~= wanted then
            runtime.state.lastManualQuest = wanted
            dbg("Manual quest not found: " .. tostring(wanted))
        end
        -- An explicit selection is never replaced by an automatic quest. A
        -- missing or not-yet-available index must wait for the catalog or the
        -- player level instead of silently farming a different quest.
        return nil
    end
    local best = gameQuestFor(level)
    if best then
        return {name = best.name, index = best.index, mob = best.mob,
                count = best.count, level = best.level, sea = best.sea,
                pos = best.pos, npc = best.npc, task = best.task,
                taskKey = best.taskKey, taskAmbiguous = best.taskAmbiguous}
    end
    for _, q in ipairs(runtime.config.QuestList) do
        if level >= q[1] and level <= q[2] then
            return {name = q[3], index = q[4], mob = q[5], sea = 1}
        end
    end
    return nil
end

local function questKey(q) return q.name .. "#" .. q.index end

-- Find the exact quest record that a StartQuest request selected. The
-- official QuestUpdate has no index, so automatic verification needs the
-- catalog entry (and its task signature) for this exact name/index pair.
questByKey = function(name, index)
    local wantedIndex = tonumber(index)
    for _, list in ipairs({gameQuests or {}, gameGuideQuests or {}}) do
        for _, q in ipairs(list) do
            if q.name == name and tonumber(q.index) == wantedIndex then
                return {
                    name = q.name, index = q.index, mob = q.mob,
                    count = q.count, level = q.level, sea = q.sea,
                    pos = q.pos, npc = q.npc, task = q.task,
                    taskKey = q.taskKey, taskAmbiguous = q.taskAmbiguous,
                }
            end
        end
    end
    return nil
end
runtime.questByKey = questByKey

-- A manual bare name is resolved to one concrete index when it is requested.
-- Keep verifying later progress against that exact catalog record even if the
-- player's level changes and a higher index becomes eligible in the meantime.
local function manualQuestExpected()
    local requestedName = runtime.state.questAsked
    local requestedIndex = runtime.state.questIndexTry
    if requestedName and requestedIndex then
        -- A requested record that disappeared from the catalog is unknown, not
        -- permission to verify a different index of the same quest line.
        return questByKey(requestedName, requestedIndex)
    end
    return questFor(getMyLevel())
end
runtime.manualQuestExpected = manualQuestExpected

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

-- Every automatic and manual request owns one generation. Invalidating that
-- generation is the only safe way to stop an old StartQuest reply or travel
-- request from writing into a newer selection.
runtime.invalidateQuestRequest = function()
    local s = runtime.state
    s.questRequestToken = (s.questRequestToken or 0) + 1
    s.questRequestInFlight = false
    -- Keep request ids monotonic across invalidations. An old response must
    -- not be able to clear the marker of a later request.
    s.manualQuestRequestId = (s.manualQuestRequestId or 0) + 1
    s.manualQuestRequestRevision = 0
    return s.questRequestToken
end

runtime.invalidateAutomaticQuestSelection = function(reason)
    local wanted = runtime.config.ManualQuest
    if wanted and wanted ~= "Auto" and wanted ~= "" then return false end
    local s = runtime.state
    runtime.invalidateQuestRequest()
    s.currentQuest = nil
    s.questVerified = false
    s.questAsked = nil
    s.questAskedAt = 0
    s.questIndexTry = nil
    s.questTried = {}
    s.questTryKey = nil
    s.questGaveUp = false
    s.questSeenUntil = 0
    s.lastQuestTry = 0
    s.questDone = false
    s.questDoneMob = nil
    s.turnInSince = nil
    s.turnInFailed = false
    s.turnInFailedAt = 0
    s.bossQuestName = nil
    s.bossQuestUntil = 0
    if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
    dbg("Automatic quest selection changed: " .. tostring(reason or "policy"))
    return true
end

-- Reloading the quest catalog is safe to expose as a button. The operation
-- epoch is captured because the module load can yield for several seconds.
-- A refresh owns the catalog while it loads: old requests are invalidated
-- before the yield, new requests wait, and a selection made during the load
-- keeps its own state when the new catalog is installed.
runtime.refreshQuestData = function()
    local epoch = runtime.operationEpoch
    local char = LocalPlayer.Character
    local s = runtime.state
    local catalogToken = (s.questCatalogToken or 0) + 1
    s.questCatalogToken = catalogToken
    s.questCatalogLoading = true
    runtime.invalidateQuestRequest()
    local manualRevision = s.manualQuestRevision
    local requestToken = s.questRequestToken

    local data = loadGameQuests()
    if not runtime.operationValid(epoch, runtime.characterEpoch, char) then return false end
    if s.questCatalogToken ~= catalogToken then return false end
    s.questCatalogLoading = false
    if not data then return false end
    gameQuests = data.quests
    gameGuideQuests = data.guide
    gameLevelQuests = data.levels
    gameGuideNames = data.guideNames
    gameQuestIndexes = data.indexes
    runtime.questCatalog = gameQuests
    gameQuestCache, gameQuestCacheAt = nil, nil
    -- A selection or request made while the module load was yielding owns the
    -- newer state. Installing the catalog must not erase that verification.
    local requestChanged = s.manualQuestRevision ~= manualRevision
        or s.questRequestToken ~= requestToken
        or s.questRequestInFlight == true
    if not requestChanged then
        if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
        s.questVerified = false
        s.questTried = {}
        s.questTryKey = nil
        if not s.questAsked then s.questIndexTry = nil end
    end
    s.questRevision = (s.questRevision or 0) + 1
    refreshKnownMobs()
    dbg("Game quest data: " .. #gameQuests .. " quests")
    return true
end

-- Selecting a quest is an explicit replacement. The old quest is abandoned
-- once, the selected quest is sent once, and the normal verification path
-- takes over after the server has shown it.
runtime.setManualQuest = function(value)
    value = tostring(value or "Auto"):match("^%s*(.-)%s*$") or "Auto"
    if value == "" then value = "Auto" end
    local changed = runtime.config.ManualQuest ~= value
    runtime.config.ManualQuest = value
    local s = runtime.state
    if not changed and s.manualQuestKey == value then return true end
    s.manualQuestKey = value
    s.manualQuestRequestAt = 0
    s.manualQuestRevision = (s.manualQuestRevision or 0) + 1
    runtime.invalidateQuestRequest()
    s.manualQuestSentKey = nil
    s.manualQuestAttempts = 0
    s.manualQuestRequestRevision = 0
    -- The shared invalidation helper also advanced the request id, so an old
    -- reply cannot clear the marker of this new selection.
    s.lastManualQuest = nil
    s.currentQuest = nil
    s.questVerified = false
    s.questAsked = nil
    s.questAskedAt = 0
    s.questTryKey = nil
    s.questTried = {}
    s.questIndexTry = nil
    s.questGaveUp = false
    s.questSeenUntil = 0
    s.lastQuestTry = 0
    s.questDone = false
    s.questDoneMob = nil
    s.turnInSince = nil
    s.turnInFailed = false
    s.turnInFailedAt = 0
    s.bossQuestName = nil
    s.bossQuestUntil = 0
    if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
    dbg(value == "Auto" and "Manual quest selection cleared"
        or ("Manual quest selected: " .. value))
    return true
end

table.insert(runtime.tasks, task.spawn(function()
    runtime.refreshQuestData()
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

local function normalizeQuestRemoteData(data)
    if type(data) ~= "table" then return nil, "not a table" end
    local name = data.InternalQuestName
    if type(name) ~= "string" or name == "" then return nil, "missing quest name" end
    local info = data.Info
    if type(info) ~= "table" then return nil, "missing quest info" end
    local task = info.Task
    if type(task) ~= "table" or next(task) == nil then return nil, "missing quest tasks" end
    local progress = data.Progress
    if type(progress) ~= "table" then return nil, "missing quest progress" end
    local rawIndex
    if data.Index ~= nil then
        rawIndex = data.Index
    elseif data.QuestIndex ~= nil then
        rawIndex = data.QuestIndex
    end
    local index
    if rawIndex ~= nil then
        index = tonumber(rawIndex)
        if not index or index < 1 or index % 1 ~= 0 then
            return nil, "invalid quest index"
        end
    end

    local cleanProgress = {}
    for key, need in pairs(task) do
        if type(key) ~= "string" or type(need) ~= "number" then
            return nil, "invalid quest task"
        end
        local value = progress[key]
        if type(value) == "boolean" then
            value = value and need or 0
        elseif type(value) == "number" then
            if value < 0 then value = 0 end
            if value > need then value = need end
        else
            value = 0
        end
        cleanProgress[key] = value
    end
    return {
        InternalQuestName = name,
        Index = index,
        Info = {Name = info.Name, Task = task, LevelReq = info.LevelReq},
        Progress = cleanProgress,
        TaskKey = questTaskSignature(task),
    }
end

local function clearQuestRemoteState()
    questRemoteState = nil
    runtime.state.questRemoteState = nil
end
runtime.clearQuestRemoteState = clearQuestRemoteState

local function questPayloadMatchesExpected(payload, expected)
    if not payload or not expected then return false end
    if payload.InternalQuestName ~= expected.name then return false end

    local expectedIndex = tonumber(expected.index)
    local payloadIndex = tonumber(payload.Index)
    if payloadIndex ~= nil and expectedIndex ~= nil
        and payloadIndex ~= expectedIndex then
        return false
    end

    local task = payload.Info and payload.Info.Task or {}
    local expectedTaskKey = expected.taskKey
    if expectedTaskKey then
        -- If the task is unique within the quest line, it identifies the
        -- selected index even though the official update omits Index.  An
        -- ambiguous signature is not safe to guess.
        if payloadIndex == nil and expected.taskAmbiguous then return false end
        local payloadTaskKey = payload.TaskKey or questTaskSignature(task)
        if payloadTaskKey ~= expectedTaskKey then return false end
    elseif payloadIndex == nil then
        -- A fallback quest without a task signature cannot prove its index.
        return false
    elseif expectedIndex ~= nil and payloadIndex ~= expectedIndex then
        return false
    end

    local need = task[expected.mob]
    if type(need) ~= "number" then return false end
    if expected.count and tonumber(need) ~= tonumber(expected.count) then return false end
    return true
end
runtime.normalizeQuestRemoteData = normalizeQuestRemoteData
runtime.questPayloadMatchesExpected = questPayloadMatchesExpected

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
            local manualWanted = runtime.config.ManualQuest
            local manual = manualWanted and manualWanted ~= "Auto" and manualWanted ~= ""
            if data == nil then
                -- A nil event has no quest or request id. While a newer manual
                -- request is in flight it may be the old quest being cleared;
                -- do not erase the new request's state.
                if runtime.state.questRequestInFlight then
                    dbg("Ignored a quest-clear event while a request was in flight")
                    return
                end
                clearQuestRemoteState()
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
            local payload, reason = normalizeQuestRemoteData(data)
            if not payload then
                if runtime.state.questRequestInFlight then
                    dbg("Ignored an incomplete quest update while a request was in flight")
                    return
                end
                clearQuestRemoteState()
                runtime.state.questDone = false
                runtime.state.questDoneMob = nil
                runtime.state.currentQuest = nil
                runtime.state.questVerified = false
                runtime.state.questAsked = nil
                runtime.state.questIndexTry = nil
                dbg("Ignored an incomplete quest update: " .. tostring(reason))
                return
            end
            if type(update) == "table" and update.Context == "Complete" then
                dbg("Quest progress complete: " .. tostring(update.Name))
            end
            if manual then
                local expected = manualQuestExpected()
                if not questPayloadMatchesExpected(payload, expected) then
                    -- The event does not carry a request id. A mismatching
                    -- payload can therefore be a delayed update from the
                    -- previous selection. Ignore it without erasing the
                    -- newer request; the request reply decides its outcome.
                    dbg("Ignored the wrong manual quest update: "
                        .. tostring(payload.InternalQuestName))
                    return
                end
                questRemoteState = payload
                runtime.state.questRemoteState = payload
                runtime.state.currentQuest = expected.name .. "#" .. tostring(expected.index)
                runtime.state.questVerified = true
                runtime.state.questGaveUp = false
                runtime.state.questTried = {}
                -- Keep questIndexTry: it is the exact manual index that was
                -- requested and must remain the verification target when the
                -- player's level changes later.
                return
            end
            if runtime.state.questAsked then
                local requestedName = runtime.state.questAsked
                if payload.InternalQuestName ~= requestedName then
                    if runtime.state.questRequestInFlight then
                        dbg("Ignored the wrong automatic quest update while a request was in flight")
                        return
                    end
                    clearQuestRemoteState()
                    runtime.state.questDone = false
                    runtime.state.questDoneMob = nil
                    runtime.state.currentQuest = nil
                    runtime.state.questVerified = false
                    runtime.state.questAsked = nil
                    runtime.state.questIndexTry = nil
                    dbg("The game gave us " .. tostring(payload.InternalQuestName)
                        .. " instead of " .. tostring(requestedName))
                    return
                end

                -- The update does not carry an index. Verify the exact quest
                -- record that StartQuest requested by its complete task
                -- signature. A same-name update from another index, or an
                -- ambiguous signature shared by two indexes, is not accepted.
                local expected = questByKey(requestedName,
                    runtime.state.questIndexTry)
                if not expected or not questPayloadMatchesExpected(payload, expected) then
                    if runtime.state.questRequestInFlight then
                        dbg("Ignored the wrong automatic quest data while a request was in flight")
                        return
                    end
                    clearQuestRemoteState()
                    runtime.state.questDone = false
                    runtime.state.questDoneMob = nil
                    runtime.state.currentQuest = nil
                    runtime.state.questVerified = false
                    runtime.state.questAsked = nil
                    runtime.state.questIndexTry = nil
                    runtime.state.questTried = {}
                    runtime.state.questTryKey = nil
                    dbg("The game gave the wrong quest data for "
                        .. tostring(requestedName))
                    return
                end
            end
            questRemoteState = payload
            runtime.state.questRemoteState = payload
            runtime.state.questVerified = true
            runtime.state.questGaveUp = false
            runtime.state.questTried = {}
            -- Keep the requested index for the lifetime of the quest. Later
            -- progress updates also omit Index and must be checked against
            -- the same selected catalog record.
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
    local operationEpoch = runtime.operationEpoch

    local manualWanted = runtime.config.ManualQuest
    local manual = manualWanted and manualWanted ~= "Auto" and manualWanted ~= ""
    if manual then runtime.setManualQuest(manualWanted) end
    local manualRevision = runtime.state.manualQuestRevision
    local manualRequestId
    if info and info.confirmed then
        -- Automatic quests keep the old fast path. A manual quest is the
        -- exception: when the live panel still shows a different quest, the
        -- old one has to be abandoned before the selected one is accepted.
        local exactName = manualWanted and manualWanted:find("#", 1, true)
        local currentMatches = false
        if manualWanted and runtime.state.currentQuest then
            if exactName then
                currentMatches = runtime.state.currentQuest == manualWanted
            else
                currentMatches = runtime.state.currentQuest:sub(1, #manualWanted + 1)
                    == manualWanted .. "#"
            end
        end
        if not manual or currentMatches then
            runtime.state.questSeenUntil = now + 1
            return
        end
    end
    if now < (runtime.state.questSeenUntil or 0) then return end
    if now - runtime.state.lastQuestTry < 2 then return end
    if runtime.state.questDone then return end
    if runtime.state.questCatalogLoading then return end
    if runtime.state.questRequestInFlight then return end

    local q = questFor(getMyLevel())
    if not q then
        dbg("No quest bracket for this level")
        return
    end

    -- Reserve one request generation before any Realm lookup can yield. A
    -- selection change during that lookup must invalidate this request too;
    -- otherwise an old automatic or manual selection could still start a
    -- quest after the user chose a different one.
    local requestToken = (runtime.state.questRequestToken or 0) + 1
    local questRevision = runtime.state.questRevision
    runtime.state.questRequestToken = requestToken
    runtime.state.questRequestInFlight = true
    local function expireOwnRequest()
        if runtime.state.questRequestToken == requestToken then
            runtime.state.questRequestInFlight = false
        end
    end
    local function requestIsCurrent()
        if runtime.state.questRequestToken ~= requestToken then return false end
        if runtime.state.questRevision ~= questRevision then
            expireOwnRequest()
            return false
        end
        if manual and runtime.state.manualQuestRevision ~= manualRevision then
            expireOwnRequest()
            return false
        end
        if not manual then
            -- Automatic selection also depends on level, boss policy and the
            -- quest catalog. If it now resolves to another exact quest, the
            -- old request must not start it.
            local selected = questFor(getMyLevel())
            if not selected or questKey(selected) ~= questKey(q) then
                expireOwnRequest()
                return false
            end
        end
        if not runtime.operationValid(operationEpoch, epoch, char) then
            expireOwnRequest()
            return false
        end
        return true
    end
    local function clearQuestRequest()
        expireOwnRequest()
    end

    -- A selected Second or Third Sea quest is routed to its world before it
    -- is accepted. The current sea must be known first: accepting a quest in
    -- the wrong world is worse than waiting for one fresh Realm result.
    if q.sea then
        -- A cached sea can belong to the previous world. A sea quest always
        -- asks Realm for a fresh result before it routes or accepts.
        local currentSea = nil
        if runtime.detectCurrentSea then
            currentSea = runtime.detectCurrentSea()
        end
        if not requestIsCurrent() then
            clearQuestRequest()
            return
        end
        if manual and runtime.state.manualQuestRevision ~= manualRevision then
            clearQuestRequest()
            return
        end
        if not currentSea then
            clearQuestRequest()
            dbg("The current sea is not known; the quest was not accepted")
            return
        end
        if currentSea ~= q.sea then
            -- The guard belongs to the selection that created this request,
            -- not to the revision that happens to be current after the yield.
            local travelRevision = manual and manualRevision or nil
            local travelGuard = manual and function()
                return runtime.state.manualQuestRevision == travelRevision
                    and runtime.state.questRequestToken == requestToken
                    and runtime.state.questRevision == questRevision
            end or nil
            if runtime.travelToWorld then
                runtime.state.status = "Travelling to Sea " .. tostring(q.sea)
                runtime.travelToWorld(q.sea, travelGuard)
            end
            -- The world request can yield for several seconds. A manual
            -- selection changed during that wait must not be cleared by this
            -- stale route.
            if not requestIsCurrent() then
                clearQuestRequest()
                return
            end
            if manual and runtime.state.manualQuestRevision ~= travelRevision then
                clearQuestRequest()
                return
            end
            runtime.state.currentQuest = nil
            runtime.state.questVerified = false
            runtime.state.questAsked = nil
            runtime.state.questIndexTry = nil
            runtime.state.questTried = {}
            runtime.state.questTryKey = nil
            clearQuestRequest()
            return
        end
    end

    local key = questKey(q) .. "@" .. tostring(getMyLevel())
    if runtime.state.questTryKey ~= key then
        runtime.state.questTryKey = key
        runtime.state.questTried = {}
        -- Keep the index of an active quest when a level change changes the
        -- automatic bracket. The next progress update still omits Index and
        -- must be checked against the quest that is actually running.
        if not runtime.state.questAsked then
            runtime.state.questIndexTry = nil
        end
        runtime.state.questGaveUp = false
    end

    if runtime.state.questAsked and not runtime.state.questVerified then
        if now - runtime.state.questAskedAt < 6 then
            clearQuestRequest()
            return
        end
        if manual then
            -- A manual selection is exact. Never walk it to another index and
            -- never turn a slow server update into a request loop.
            if (runtime.state.manualQuestAttempts or 0) >= 3 then
                runtime.state.questGaveUp = true
                runtime.state.currentQuest = nil
                dbg("The manual quest was not confirmed after three requests")
                clearQuestRequest()
                return
            end
            runtime.state.questAsked = nil
            runtime.state.questVerified = false
            runtime.state.questAskedAt = 0
            runtime.state.currentQuest = nil
            clearQuestRequest()
            return
        end
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
            clearQuestRequest()
            return
        end
    end
    if runtime.state.questGaveUp then
        clearQuestRequest()
        return
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        clearQuestRequest()
        dbg("CommF_ remote missing")
        return
    end

    local index = runtime.state.questIndexTry or q.index

    if manual then
        if (runtime.state.manualQuestAttempts or 0) >= 3 then
            runtime.state.questGaveUp = true
            runtime.state.currentQuest = nil
            dbg("The manual quest was refused three times; no more requests were sent")
            clearQuestRequest()
            return
        end
        local requestKey = questKey(q)
        if runtime.state.manualQuestSentKey == requestKey
            and now - (runtime.state.manualQuestRequestAt or 0) < 12 then
            clearQuestRequest()
            return
        end
        manualRequestId = (runtime.state.manualQuestRequestId or 0) + 1
        runtime.state.manualQuestRequestId = manualRequestId
        runtime.state.manualQuestRequestRevision = manualRevision
    end

    -- Every automatic and manual StartQuest request owns one generation. A
    -- selection change or a newer request invalidates the older coroutine
    -- before it can write quest state.
    local function clearManualRequest()
        if manualRequestId and runtime.state.manualQuestRequestId == manualRequestId then
            runtime.state.manualQuestRequestId = 0
            runtime.state.manualQuestRequestRevision = 0
        end
        clearQuestRequest()
    end

    -- The request id is part of the ownership check as well as the selection
    -- revision. Two requests for the same quest can otherwise overlap: the
    -- older coroutine must not continue to AbandonQuest or StartQuest after a
    -- newer request has taken ownership.
    local function manualRequestIsCurrent()
        return requestIsCurrent() and (not manual or (
            runtime.state.manualQuestRevision == manualRevision
            and runtime.state.manualQuestRequestRevision == manualRevision
            and runtime.state.manualQuestRequestId == manualRequestId))
    end

    local spawnOk = pcall(function() commF:InvokeServer("SetLastSpawnPoint", "Town") end)
    if not spawnOk or not requestIsCurrent() then
        clearManualRequest()
        return
    end
    if manual and not manualRequestIsCurrent() then
        clearManualRequest()
        return
    end

    if manual or questRemoteState then
        local abandonOk = pcall(function() commF:InvokeServer("AbandonQuest") end)
        if not abandonOk or not requestIsCurrent() then
            clearManualRequest()
            return
        end
    end
    if manual and not manualRequestIsCurrent() then
        clearManualRequest()
        return
    end
    if manual then
        runtime.state.manualQuestSentKey = questKey(q)
        runtime.state.manualQuestRequestAt = now
        runtime.state.manualQuestAttempts = (runtime.state.manualQuestAttempts or 0) + 1
    end
    local ok, reply = pcall(function()
        return commF:InvokeServer("StartQuest", q.name, index)
    end)
    if not requestIsCurrent() then
        clearManualRequest()
        return
    end
    if manual and not manualRequestIsCurrent() then
        clearManualRequest()
        dbg("A stale manual quest reply was ignored")
        return
    end
    clearManualRequest()
    if not ok then
        dbg("Quest FAIL: " .. tostring(reply))
        return
    end
    -- The official reply is 0 for accepted, 1 for an error, 2 for a quest
    -- already completed, and a level requirement otherwise. Treating every
    -- non-error reply as success was how the bot kept farming a quest that
    -- the server had actually refused.
    if reply ~= 0 then
        local reason = reply == 1 and "the game refused it"
            or (reply == 2 and "it was already completed"
            or ("level requirement " .. tostring(reply)))
        dbg("Quest " .. q.name .. " was not accepted: " .. reason)
        runtime.state.questAsked = nil
        runtime.state.questVerified = false
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
    runtime.state.lastPrompt, runtime.state.promptAt = prompt, now
    if fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function()
            prompt:InputHoldBegin()
            runtime.state.promptHoldSeq = (runtime.state.promptHoldSeq or 0) + 1
            local holdToken = runtime.state.promptHoldSeq
            runtime.state.promptHolds[prompt] = holdToken
            table.insert(runtime.tasks, task.spawn(function()
                task.wait(prompt.HoldDuration or 1)
                -- Only the task that owns this exact hold may end it. A reset
                -- can remove the marker and a later run can start a new hold
                -- on the same prompt; the old task must not end that new hold.
                if runtime.state.promptHolds[prompt] == holdToken then
                    runtime.state.promptHolds[prompt] = nil
                    pcall(function() prompt:InputHoldEnd() end)
                end
            end))
        end)
    end
    return true
end

-- ================= CHESTS =================
-- Ordinary chests are the server instances tagged by the game itself. Their
-- live names are Chest1, Chest2 and Chest3, so a name table misses them. The
-- official tag is the discovery proof; collection still requires the current
-- character to physically touch the exact tagged server part.
runtime.chestTag = "_ChestTagged"

runtime.chestStateOf = function(instance)
    if not instance then return nil end
    if instance:GetAttribute("Opened") == true then return "Opened" end
    if instance:GetAttribute("Collected") == true then return "Collected" end
    if instance:GetAttribute("IsDisabled") == true then return "IsDisabled" end
    return nil
end

runtime.chestServerState = function(chest)
    if not chest then return nil end
    local state = runtime.chestStateOf(chest)
    if state then return state end
    local part = runtime.chestPart(chest)
    if part and part ~= chest then
        state = runtime.chestStateOf(part)
        if state then return state end
    end
    part = runtime.chestIdentityPart(chest)
    if part and part ~= chest then
        state = runtime.chestStateOf(part)
        if state then return state end
    end
    for _, descendant in ipairs(chest:GetDescendants()) do
        if descendant:IsA("BasePart") then
            state = runtime.chestStateOf(descendant)
            if state then return state end
        end
    end
    return nil
end

runtime.chestTargets = function()
    local ok, collection = pcall(function()
        return game:GetService("CollectionService")
    end)
    if not ok or not collection then return {} end
    local taggedOk, tagged = pcall(function()
        return collection:GetTagged(runtime.chestTag)
    end)
    if not taggedOk or type(tagged) ~= "table" then return {} end
    return tagged
end

runtime.chestPart = function(chest, requireTouchable)
    if requireTouchable == nil then requireTouchable = true end
    if not chest then return nil end
    if chest:IsA("BasePart") then
        if requireTouchable and chest.CanTouch == false then return nil end
        return chest
    end
    local primary
    if chest:IsA("Model") then
        pcall(function() primary = chest.PrimaryPart end)
    end
    if not primary then primary = chest:FindFirstChild("PrimaryPart") end
    if primary and primary:IsA("BasePart")
        and (not requireTouchable or primary.CanTouch ~= false) then
        return primary
    end
    for _, part in ipairs(chest:GetDescendants()) do
        if part:IsA("BasePart")
            and (not requireTouchable or part.CanTouch ~= false) then return part end
    end
    return nil
end

runtime.chestIdentityPart = function(chest, fallback)
    if not chest then return nil end
    if chest:IsA("BasePart") then return chest end
    local primary
    if chest:IsA("Model") then
        pcall(function() primary = chest.PrimaryPart end)
    end
    if not primary then primary = chest:FindFirstChild("PrimaryPart") end
    if primary and primary:IsA("BasePart") then return primary end
    if fallback and fallback.Parent then return fallback end
    for _, part in ipairs(chest:GetDescendants()) do
        if part:IsA("BasePart") then return part end
    end
    return nil
end

runtime.chestHasTag = function(chest)
    if not chest then return false end
    local ok, collection = pcall(function()
        return game:GetService("CollectionService")
    end)
    if not ok or not collection then return false end
    local hasOk, hasTag = pcall(function()
        return collection:HasTag(chest, runtime.chestTag)
    end)
    if hasOk then return hasTag == true end
    local taggedOk, tagged = pcall(function()
        return collection:GetTagged(runtime.chestTag)
    end)
    if not taggedOk or type(tagged) ~= "table" then return false end
    for _, taggedChest in ipairs(tagged) do
        if taggedChest == chest then return true end
    end
    return false
end

runtime.chestFruitCount = function()
    local count = 0
    local containers = {}
    local char = LocalPlayer.Character
    if char then table.insert(containers, char) end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then table.insert(containers, backpack) end
    for _, container in ipairs(containers) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and isFruit(tool) then count += 1 end
        end
    end
    return count
end

runtime.chestFragmentCount = function()
    local data = LocalPlayer:FindFirstChild("Data")
    local fragments = data and data:FindFirstChild("Fragments")
    local value = readNumber(fragments)
    if type(value) == "number" then return value end
    value = tonumber(LocalPlayer:GetAttribute("Fragments"))
    if type(value) == "number" then return value end
    return nil
end

runtime.clearChestConnections = function(operationToken)
    local s = runtime.state
    if operationToken ~= nil and s.chestToken ~= operationToken then return false end
    for _, connection in ipairs(s.chestConnections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    s.chestConnections = {}
    return true
end

runtime.watchChestTouch = function(target, part, root, operationToken)
    runtime.clearChestConnections(operationToken)
    local s = runtime.state
    local function recordTouch(hit)
        if s.chestToken ~= operationToken or s.chestTarget ~= target
            or s.chestTargetPart ~= part then return end
        local char = LocalPlayer.Character
        if not char or root.Parent ~= char then return end
        local belongs = hit == root
        if not belongs then
            pcall(function() belongs = hit:IsDescendantOf(char) end)
        end
        if not belongs then return end
        -- Keep the first valid contact. A later repeated Touched event must not
        -- move the server transition behind the touch and hide valid proof.
        if s.chestTouchAt == 0 then
            local at = tick()
            s.chestSequence = (s.chestSequence or 0) + 1
            s.chestTouchSequence = s.chestSequence
            s.chestTouchAt = at
            s.chestTouchPart = part
            s.chestTouchRoot = root
            -- Reward proof is measured from the exact touch instant. A reward
            -- increase seen before contact cannot later be inherited by this
            -- operation after an unrelated touch.
            s.chestTouchRewardBaselineAt = at
            s.chestTouchBeliBefore = myBeli and myBeli()
            s.chestTouchFruitBefore = runtime.chestFruitCount()
            s.chestTouchFragmentsBefore = runtime.chestFragmentCount()
        end
    end

    local connections = {}
    local partTouch = part.Touched:Connect(function(hit) recordTouch(hit) end)
    local rootTouch = root.Touched:Connect(function(hit)
        if hit == part then recordTouch(hit) end
    end)
    table.insert(connections, partTouch)
    table.insert(connections, rootTouch)

    local function watchServerState(instance)
        for _, attribute in ipairs({"IsDisabled", "Opened", "Collected"}) do
            local serverChange = instance:GetAttributeChangedSignal(attribute):Connect(function()
                if s.chestToken ~= operationToken or s.chestTarget ~= target then return end
                if instance:GetAttribute(attribute) ~= true then return end
                local at = tick()
                s.chestSequence = (s.chestSequence or 0) + 1
                local sequence = s.chestSequence
                s.chestServerAt = at
                s.chestServerState = attribute
                if attribute == "Opened" then
                    s.chestOpenedAt = at
                    s.chestOpenedSequence = sequence
                elseif attribute == "Collected" then
                    s.chestCollectedAt = at
                    s.chestCollectedSequence = sequence
                else
                    s.chestDisabledAt = at
                    s.chestDisabledSequence = sequence
                end
            end)
            table.insert(connections, serverChange)
        end
    end
    local watchedServerState = {}
    local function watchServerStateOnce(instance)
        if not instance or watchedServerState[instance] then return end
        watchedServerState[instance] = true
        watchServerState(instance)
    end
    watchServerStateOnce(target)
    watchServerStateOnce(part)
    -- A Model may select a touchable fallback while its identity remains the
    -- PrimaryPart. Watch that exact identity part too, so a post-touch server
    -- transition on it receives the same strict sequence proof.
    watchServerStateOnce(runtime.chestIdentityPart(target, part))
    s.chestConnections = connections
end

runtime.scanChestTargets = function(root, now)
    local best, bestD = nil, (tonumber(runtime.config.ChestRange) or 5000)
    for _, d in ipairs(runtime.chestTargets()) do
        if (d:IsA("Model") or d:IsA("BasePart")) and d:IsDescendantOf(Workspace) then
            local part = runtime.chestPart(d)
            local disabled = runtime.chestServerState(d) ~= nil
            local seenAt = runtime.state.chestSeen[d]
            if part and part.Parent and not disabled
                and (not seenAt or now - seenAt >= 60) then
                local distance = (root.Position - part.Position).Magnitude
                if distance < bestD then best, bestD = d, distance end
            end
        end
    end
    return best
end

runtime.cancelChest = function()
    local s = runtime.state
    local hadOwner = s.chestMovementToken ~= nil
        or s.chestTarget ~= nil
        or s.chestTargetPart ~= nil
        or #(s.chestConnections or {}) > 0
        or s.movementOwner == "chest"
    if not hadOwner then return false end
    s.chestToken = (s.chestToken or 0) + 1
    -- Use the exact token that owns the chest lock. Releasing with nil would
    -- also release a newer chest owner that happened to replace this state.
    local movementToken = s.chestMovementToken
    if movementToken == nil and s.movementOwner == "chest" then
        movementToken = s.movementOwnerToken
    end
    local ownsMovement = s.movementOwner == "chest"
        and s.movementOwnerToken == movementToken
    if runtime.clearChestConnections then runtime.clearChestConnections() end
    s.chestMovementToken = nil
    s.chestTarget = nil
    s.chestTargetPart = nil
    s.chestTargetIdentityPart = nil
    s.chestStartedAt = 0
    s.chestSelectedAt = 0
    s.chestTravelDeadline = 0
    s.chestLastTry = 0
    s.chestTouchAt = 0
    s.chestTouchPart = nil
    s.chestTouchRoot = nil
    s.chestSequence = 0
    s.chestTouchSequence = 0
    s.chestTouchRewardBaselineAt = 0
    s.chestTouchBeliBefore = nil
    s.chestTouchFruitBefore = nil
    s.chestTouchFragmentsBefore = nil
    s.chestServerAt = 0
    s.chestServerState = nil
    s.chestOpenedAt = 0
    s.chestCollectedAt = 0
    s.chestDisabledAt = 0
    s.chestOpenedSequence = 0
    s.chestCollectedSequence = 0
    s.chestDisabledSequence = 0
    s.chestBeliBefore = nil
    s.chestFruitBefore = nil
    s.chestFragmentsBefore = nil
    s.chestRewardBaselineAt = 0
    if ownsMovement and runtime.stopTween then runtime.stopTween() end
    runtime.releaseMovement("chest", movementToken)
    return true
end

runtime.handleChest = function(root)
    if not runtime.config.AutoChest then
        runtime.cancelChest()
        return false
    end
    if not root then return false end
    local now = tick()
    local s = runtime.state
    local target = s.chestTarget
    local operationToken = s.chestToken
    local movementToken = s.chestMovementToken

    if not target then
        if s.chestMovementToken or s.chestTargetPart
            or #(s.chestConnections or {}) > 0 then
            runtime.cancelChest()
        end
        if now - (s.chestLastScanAt or 0) >= 1.5 then
            s.chestLastScanAt = now
            target = runtime.scanChestTargets(root, now)
        end
        if not target then return false end

        -- Do not commit a chest target while another feature owns movement.
        -- The scan may find a chest, but the ordinary farm keeps its own
        -- operation until the exclusive chest lock can be acquired cleanly.
        local acquired
        acquired, movementToken = runtime.acquireMovement("chest")
        if not acquired then return false end
        local selectedPart = runtime.chestPart(target)
        if not selectedPart then
            s.chestSeen[target] = now
            runtime.releaseMovement("chest", movementToken)
            return true
        end
        -- The chest now owns movement. Cancel a farm tween left over from the
        -- preceding frame so the proxy cannot keep moving toward a mob while
        -- the chest route is being committed.
        if runtime.stopTween then runtime.stopTween() end
        s.chestMovementToken = movementToken
        s.chestToken = (s.chestToken or 0) + 1
        operationToken = s.chestToken
        s.chestTarget = target
        s.chestTargetPart = selectedPart
        s.chestTargetIdentityPart = runtime.chestIdentityPart(target, selectedPart)
        s.chestSelectedAt = now
        s.chestStartedAt = 0
        s.chestTravelDeadline = 0
        s.chestLastTry = 0
        s.chestTouchAt = 0
        s.chestTouchPart = nil
        s.chestTouchRoot = nil
        s.chestSequence = 0
        s.chestTouchSequence = 0
        s.chestTouchRewardBaselineAt = 0
        s.chestTouchBeliBefore = nil
        s.chestTouchFruitBefore = nil
        s.chestTouchFragmentsBefore = nil
        s.chestServerAt = 0
        s.chestServerState = nil
        s.chestOpenedAt = 0
        s.chestCollectedAt = 0
        s.chestDisabledAt = 0
        s.chestOpenedSequence = 0
        s.chestCollectedSequence = 0
        s.chestDisabledSequence = 0
        s.chestBeliBefore = nil
        s.chestFruitBefore = nil
        s.chestFragmentsBefore = nil
        s.chestRewardBaselineAt = 0
        -- Install the exact-part and server-state watchers before the first
        -- approach frame so a fast contact cannot outrun the proof.
        runtime.watchChestTouch(target, selectedPart, root, operationToken)
        local travelDistance = (root.Position - selectedPart.Position).Magnitude
        local travelSeconds = travelDistance / math.max(1, tonumber(runtime.config.MoveSpeed) or 200)
        s.chestTravelDeadline = now + math.max(
            tonumber(runtime.config.ChestTimeout) or 30, travelSeconds * 2 + 10)
    elseif not movementToken or s.movementOwner ~= "chest"
        or s.movementOwnerToken ~= movementToken then
        -- A target is valid only with its exact movement owner. If another
        -- operation replaced the owner, cancel the stale chest as a unit.
        runtime.cancelChest()
        return false
    end

    if s.chestToken ~= operationToken or s.chestMovementToken ~= movementToken
        or s.movementOwner ~= "chest" or s.movementOwnerToken ~= movementToken then
        return false
    end

    local function finishChest()
        local ownsMovement = s.movementOwner == "chest"
            and s.movementOwnerToken == movementToken
        if s.chestToken == operationToken then
            s.chestTarget = nil
            s.chestTargetPart = nil
            s.chestTargetIdentityPart = nil
            s.chestStartedAt = 0
            s.chestSelectedAt = 0
            s.chestTravelDeadline = 0
            s.chestLastTry = 0
            s.chestTouchAt = 0
            s.chestTouchPart = nil
            s.chestTouchRoot = nil
            s.chestSequence = 0
            s.chestTouchSequence = 0
            s.chestTouchRewardBaselineAt = 0
            s.chestTouchBeliBefore = nil
            s.chestTouchFruitBefore = nil
            s.chestTouchFragmentsBefore = nil
            s.chestServerAt = 0
            s.chestServerState = nil
            s.chestOpenedAt = 0
            s.chestCollectedAt = 0
            s.chestDisabledAt = 0
            s.chestOpenedSequence = 0
            s.chestCollectedSequence = 0
            s.chestDisabledSequence = 0
            s.chestBeliBefore = nil
            s.chestFruitBefore = nil
            s.chestFragmentsBefore = nil
            s.chestRewardBaselineAt = 0
            s.chestMovementToken = nil
            if runtime.clearChestConnections then
                runtime.clearChestConnections(operationToken)
            end
        end
        if ownsMovement and runtime.stopTween then runtime.stopTween() end
        runtime.releaseMovement("chest", movementToken)
    end

    local targetPart = s.chestTargetPart
    local exactTouch = targetPart ~= nil and s.chestTouchAt > 0
        and s.chestTouchPart == targetPart and s.chestTouchRoot == root
    local serverState = runtime.chestServerState(target)
    if serverState then s.chestServerState = serverState end
    local identityPart = s.chestTargetIdentityPart
    local currentIdentityPart = runtime.chestIdentityPart(target, targetPart)
    local exactPartStillOwned = false
    pcall(function()
        exactPartStillOwned = targetPart ~= nil and targetPart.Parent ~= nil
            and (targetPart == target or targetPart:IsDescendantOf(target))
    end)
    local stillInWorkspace = false
    pcall(function() stillInWorkspace = target:IsDescendantOf(Workspace) end)
    local stillTagged = runtime.chestHasTag(target)
    local partChanged = stillInWorkspace and (not targetPart or not identityPart
        or not currentIdentityPart or currentIdentityPart ~= identityPart
        or not exactPartStillOwned)
    local tagChanged = stillInWorkspace and not stillTagged
    if partChanged or tagChanged then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest changed"
        dbg("Chest changed before collection: " .. target.Name)
        return true
    end
    local beli = myBeli and myBeli()
    local fruitCount = runtime.chestFruitCount()
    local fragments = runtime.chestFragmentCount()
    -- The completion baseline is captured inside the exact Touched callback.
    -- A reward increase seen during the approach but before contact is not
    -- inherited by a later, unrelated touch.
    local beliPaid = exactTouch and type(s.chestTouchBeliBefore) == "number"
        and type(beli) == "number" and beli > s.chestTouchBeliBefore
    local fruitPaid = exactTouch and type(s.chestTouchFruitBefore) == "number"
        and fruitCount > s.chestTouchFruitBefore
    local fragmentsPaid = exactTouch and type(s.chestTouchFragmentsBefore) == "number"
        and type(fragments) == "number" and fragments > s.chestTouchFragmentsBefore
    local rewardObserved = beliPaid or fruitPaid or fragmentsPaid
    -- Opened, Collected, and IsDisabled are independent server transitions.
    -- Sequence numbers prove callback order even when two callbacks receive
    -- the same tick() value. Only a transition after the exact touch counts.
    local openedAfterTouch = exactTouch
        and s.chestOpenedSequence > s.chestTouchSequence
    local collectedAfterTouch = exactTouch
        and s.chestCollectedSequence > s.chestTouchSequence
    local disabledAfterTouch = exactTouch
        and s.chestDisabledSequence > s.chestTouchSequence
    local explicitCollected = openedAfterTouch or collectedAfterTouch
    local serverAfterTouch = openedAfterTouch or collectedAfterTouch
        or disabledAfterTouch
    if exactTouch and (rewardObserved or explicitCollected or disabledAfterTouch) then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = (rewardObserved or explicitCollected)
            and "Chest collected" or "Chest confirmed"
        dbg("Collected " .. target.Name)
        return true
    end

    if not target.Parent or not stillInWorkspace then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest became unavailable"
        dbg("Chest became unavailable: " .. target.Name)
        return true
    end
    if s.chestServerAt > 0 and (not exactTouch or not serverAfterTouch)
        and now - s.chestServerAt >= 0.5 then
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest became unavailable"
        dbg("Chest became unavailable: " .. target.Name)
        return true
    end

    if #(s.chestConnections or {}) == 0 then
        runtime.watchChestTouch(target, targetPart, root, operationToken)
    end

    -- Once contact has begun, the confirmation deadline owns the operation
    -- even if the character drifts away again. The travel deadline is no
    -- longer allowed to terminate this later phase.
    if s.chestStartedAt > 0
        and now - s.chestStartedAt > (tonumber(runtime.config.ChestTimeout) or 30) then
        -- A failed chest is skipped for one minute, not forever. The server can
        -- disable it later or the player can come back after its reset.
        s.chestSeen[target] = now
        finishChest()
        runtime.state.status = "Chest was not confirmed"
        dbg("Could not collect " .. target.Name)
        return true
    end

    local distance = (root.Position - targetPart.Position).Magnitude
    if distance > 8 then
        if s.chestStartedAt == 0 and s.chestTravelDeadline > 0
            and now > s.chestTravelDeadline then
            s.chestSeen[target] = now
            finishChest()
            runtime.state.status = "Chest route timed out"
            dbg("Chest route timed out: " .. target.Name)
            return true
        end
        runtime.state.status = "Collecting chest"
        runtime.tweenTo(CFrame.new(targetPart.Position + Vector3.new(0, 2, 0)))
        return true
    end

    -- The timeout starts at contact, not when a distant chest was selected.
    -- A long smooth trip must not consume the whole server-confirmation window.
    if s.chestStartedAt == 0 then
        s.chestStartedAt = now
        -- Travel and contact are separate phases. Once contact begins, the
        -- route deadline must not terminate a still-live confirmation.
        s.chestTravelDeadline = 0
    end
    if s.chestRewardBaselineAt == 0 then
        s.chestRewardBaselineAt = now
        s.chestBeliBefore = beli
        s.chestFruitBefore = fruitCount
        s.chestFragmentsBefore = fragments
    end
    if now - (s.chestLastTry or 0) >= 0.45 then
        s.chestLastTry = now
        -- Retry the final approach only when the proxy did not reach the exact
        -- server part. No forced touch is sent: the Touched event is proof.
        if distance > 3.25 then
            runtime.tweenTo(CFrame.new(targetPart.Position + Vector3.new(0, 2, 0)))
        end
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

local function pickBest(candidates, mobName, origin, exactOnly)
    local exact, exactD = nil, math.huge
    local loose, looseD = nil, math.huge
    local wanted = mobName and mobKey(tostring(mobName)) or nil
    if wanted == "" then wanted = nil end
    for _, obj in ipairs(candidates) do
        local anchor = anchorOf(obj)
        if anchor then
            local d = (origin.Position - anchor.Position).Magnitude
            local display = nil
            pcall(function() display = obj:GetAttribute("DisplayName") end)
            local key = mobKey(display or obj.Name)
            if not wanted then
                if d < exactD then exact, exactD = obj, d end
            elseif sameName(key, wanted) then
                if d < exactD then exact, exactD = obj, d end
            elseif not exactOnly and startsWithCI(key, wanted)
                and not isCompoundMob(key, wanted) then
                if d < looseD then loose, looseD = obj, d end
            end
        end
    end
    return exact or loose
end

-- "Nearest" is a mode, not the literal name of a mob. Keep that distinction in
-- one helper so the target resolver can never search for a mob named Nearest.
runtime.resolveSelectedMob = function(value)
    value = tostring(value or "")
    if value == "" or value == "Auto" then
        return false, nil, false
    end
    if value:lower() == "nearest" then
        return true, nil, true
    end
    return true, value, false
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
    ["greybeard"] = true,
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
    ["diamond"] = 750, ["greybeard"] = 750, ["jeremy"] = 850, ["orbitus"] = 925, ["smoke admiral"] = 1150,
    ["awakened ice admiral"] = 1400, ["tide keeper"] = 1475, ["stone"] = 1550,
    ["hydra leader"] = 1675, ["kilo admiral"] = 1750, ["captain elephant"] = 1875,
    ["beautiful pirate"] = 1950, ["cake queen"] = 2175,
}

-- The key of the boss tables for a mob, from its name or its display name.
-- nil when the mob is no boss at all.
local function bossKeyOf(mob)
    if not mob then return nil end
    local function known(key)
        if not key then return nil end
        if BOSS_NAMES[key] then return key end
        if key:sub(1, 4) == "the " and BOSS_NAMES[key:sub(5)] then return key:sub(5) end
        if BOSS_NAMES["the " .. key] then return "the " .. key end
        return nil
    end
    local key = known(mobKey(mob.Name):lower())
    if key then return key end
    local display = nil
    pcall(function() display = mob:GetAttribute("DisplayName") end)
    if display then return known(mobKey(display):lower()) end
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

local function pickBoss(root, range, mobName, ignoreWindow)
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
                    local bossLevel = bossLevelOf and bossLevelOf(key) or BOSS_LEVELS[key]

                    -- Bosses are only taken when their level is close to the
                    -- player, so a level 700 player is not thrown at a level
                    -- 600 boss. The quest boss itself is always allowed if its
                    -- level table is missing.
                    local levelOk = ignoreWindow or bossLevel == nil
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

local function getTarget(mobName, exactOnly)
    local root = getRoot()
    if not root then return nil end
    return pickBest(collectEnemies(tick()), mobName, root, exactOnly)
end

local function findSpawn(mobName, exactOnly)
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    local root = getRoot()
    if not spawns or not root then return nil end

    local candidates = {}
    for _, p in ipairs(spawns:GetChildren()) do
        if p:IsA("BasePart") or p:IsA("Model") then table.insert(candidates, p) end
    end
    return pickBest(candidates, mobName, root, exactOnly)
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

-- Bring Mob has its own water rules. The exact Cup Water is deliberately not
-- part of them: it is a tiny, invisible trigger part and not an ocean. Every
-- other water part below the map is treated as a hazard for a carried rig.
runtime.bringWaterPart = function(part)
    if not part or type(part.IsA) ~= "function" or not part:IsA("BasePart") then return false end
    local fullName = ""
    pcall(function() fullName = part:GetFullName() end)
    if fullName == "Workspace.Map.Ice.ParticleDrop.Water" then return false end
    local map = nil
    pcall(function() map = part:FindFirstAncestor("Map") end)
    if not map then return false end
    local name = ""
    pcall(function() name = part.Name end)
    return name:lower():find("water", 1, true) ~= nil
end

-- Check the ground below one point. Enemy rigs and the local character are
-- excluded so their bodies cannot hide the terrain. The first ray starts at
-- the point itself: starting it 80 studs higher let overhead map geometry
-- hide the real water below and made a wet Prison ledge look dry. A raised
-- ray is only the fallback for a point that starts inside solid geometry.
-- The check fails closed if the real Workspace raycast itself errors: a Bring
-- carry is stopped instead of guessing that an unknown path is dry.
runtime.bringPointOverWater = function(point, exclude)
    if not point then return true end
    local excluded = {}
    local character = LocalPlayer and LocalPlayer.Character
    if character then excluded[#excluded + 1] = character end
    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then excluded[#excluded + 1] = enemies end
    if exclude then excluded[#excluded + 1] = exclude end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excluded
    local ok, hit = pcall(function()
        return Workspace:Raycast(point, Vector3.new(0, -500, 0), params)
    end)
    if not ok then return true end
    if hit then return runtime.bringWaterPart(hit.Instance) == true end
    local raisedOk, raisedHit = pcall(function()
        return Workspace:Raycast(point + Vector3.new(0, 80, 0),
            Vector3.new(0, -500, 0), params)
    end)
    if not raisedOk then return true end
    return raisedHit ~= nil and runtime.bringWaterPart(raisedHit.Instance) == true
end

-- A straight carry path is safe only when the ground below every sample is
-- dry. This catches a same-height island or coast across a bay even though
-- the player's and the mob's vertical difference is small.
runtime.bringPathOverWater = function(from, to)
    if not from or not to then return true end
    local dx = to.X - from.X
    local dz = to.Z - from.Z
    local distance = math.sqrt(dx * dx + dz * dz)
    local steps = math.max(1, math.ceil(distance / 6))
    if steps > 48 then steps = 48 end
    for index = 0, steps do
        local amount = index / steps
        local point = Vector3.new(
            from.X + dx * amount,
            from.Y + (to.Y - from.Y) * amount,
            from.Z + dz * amount)
        if runtime.bringPointOverWater(point) then return true end
    end
    return false
end

-- A saved mover is usable only when it is still the exact runtime-owned
-- BodyVelocity on the current root. A reparented or replaced mover is never
-- driven by this run.
runtime.validBringMover = function(mover, part)
    if not mover or not part then return false end
    if not mover:IsA("BodyVelocity") or mover.Parent ~= part then return false end
    local owned = false
    pcall(function() owned = mover:GetAttribute("FarmOwned") == true end)
    return owned
end

runtime.bringSnap = function(mob, part, goal)
    if not runtime.config.BringMobSnap or runtime.state.bringSnapped[mob] then
        return false
    end
    if not runtime.bringLocallyOwned(part) then return false end
    -- Never teleport a rig over a detected water gap. The normal mover may
    -- still close a dry path, but a straight CFrame snap is only allowed when
    -- the ground under that exact path is dry.
    if runtime.bringPathOverWater(part.Position, goal) then return false end

    local gap = (part.Position - goal).Magnitude
    if gap < (runtime.config.BringMobSnapDistance or 4) then
        -- It is already close enough. Do not keep testing ownership for this
        -- hold; the mover is responsible from here on.
        runtime.state.bringSnapped[mob] = true
        return false
    end

    local moved = false
    if runtime.bringLocallyOwned(part) then
        moved = pcall(function()
            -- Keep the facing of the rig, but put its root at the ring slot. The
            -- source uses the same one-step position move for the pack.
            part.CFrame = CFrame.new(goal) * part.CFrame.Rotation
        end)
    end
    if runtime.bringLocallyOwned(part) then
        pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
    end
    if runtime.bringLocallyOwned(part) then
        pcall(function() part.AssemblyAngularVelocity = Vector3.zero end)
    end
    if moved and runtime.bringLocallyOwned(part) then
        runtime.state.bringSnapped[mob] = true
    end
    return moved
end

-- A mob is let go: the drag goes away and every value this run changed is put
-- back exactly as the game had it, so the mob can stand and walk on its own
-- again. Only the private mover recorded for this mob is destroyed; a
-- pre-existing mover belongs to somebody else and is never touched.
runtime.letGoMob = function(mob, part)
    part = part or anchorOf(mob)
    local mover = runtime.state.bringMover[mob]
    if mover then
        pcall(function() mover:Destroy() end)
        runtime.state.bringMover[mob] = nil
    end

    local saved = runtime.state.bringSaved[mob]
    if saved then
        -- A client must not write to a rig that the server has taken back.
        -- Keep the snapshot while that rig is alive but server-owned: if this
        -- client gets ownership back, the original values can still be put
        -- back instead of capturing the frozen values as a new "original".
        local restorePart = saved.part or part
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        local rigDead = hum ~= nil and hum.Health <= 0
        local partAlive = restorePart and restorePart.Parent ~= nil
        local canRestore = partAlive and runtime.bringLocallyOwned(restorePart)
        local restoreComplete = false
        if canRestore then
            -- Only CanCollide was changed by this run. CanTouch and Massless
            -- are deliberately not written, so the real touch behaviour and
            -- assembly mass are never replaced by an old snapshot.
            --
            -- Ownership can change while the values are being restored. Check
            -- it before every group of writes and once more at the end. If it
            -- was lost in the middle, keep the snapshot: a partial restore
            -- must be retried instead of silently freezing a part of the rig.
            local stillOwned = true
            local restoreSucceeded = true
            for d, orig in pairs(saved.parts) do
                if d.Parent then
                    if not runtime.bringLocallyOwned(restorePart) then
                        stillOwned = false
                        break
                    end
                    local ok = pcall(function() d.CanCollide = orig.collide end)
                    if not ok then restoreSucceeded = false end
                end
            end
            if stillOwned and runtime.bringLocallyOwned(restorePart) then
                local ok = pcall(function()
                    restorePart.AssemblyLinearVelocity = saved.linear or Vector3.zero
                    restorePart.AssemblyAngularVelocity = saved.angular or Vector3.zero
                    if saved.hadBeingBrought then
                        restorePart:SetAttribute("BeingBrought", saved.beingBrought)
                    else
                        restorePart:SetAttribute("BeingBrought", nil)
                    end
                end)
                if not ok then restoreSucceeded = false end
            else
                stillOwned = false
            end
            if stillOwned and hum then
                if runtime.bringLocallyOwned(restorePart) then
                    local ok = pcall(function()
                        if saved.platformStand ~= nil then hum.PlatformStand = saved.platformStand end
                        if saved.autoRotate ~= nil then hum.AutoRotate = saved.autoRotate end
                        if saved.walk ~= nil then hum.WalkSpeed = saved.walk end
                        if saved.jump ~= nil then hum.JumpPower = saved.jump end
                        -- Restore the state that was captured before the hold. A
                        -- blanket Running change used to overwrite a mob that was
                        -- already jumping or lying down before it was picked up.
                        if saved.state then
                            local changed = hum:ChangeState(saved.state)
                            if changed == false then error("state restore was refused") end
                        end
                    end)
                    if not ok then restoreSucceeded = false end
                else
                    stillOwned = false
                end
                -- A corpse cannot really be revived by ChangeState. The saved
                -- state was still attempted above, but a mob that died during
                -- the hold must remain a corpse afterwards.
                if hum.Health <= 0 then
                    local currentState = nil
                    pcall(function() currentState = hum:GetState() end)
                    if currentState ~= Enum.HumanoidStateType.Dead then
                        local ok, changed = pcall(function()
                            return hum:ChangeState(Enum.HumanoidStateType.Dead)
                        end)
                        if not ok or changed == false then restoreSucceeded = false end
                    end
                end
            end
            if stillOwned and not runtime.bringLocallyOwned(restorePart) then
                stillOwned = false
            end
            restoreComplete = stillOwned and restoreSucceeded
        end
        local keepPending = partAlive and not restoreComplete and not rigDead
        if keepPending then
            -- This snapshot is waiting for ownership to return. It is not an
            -- active hold snapshot and must be restored before the same mob is
            -- selected and held again.
            saved.pending = true
        end
        if not keepPending then
            runtime.state.bringSaved[mob] = nil
            if FarmRuntime.bringRestore then FarmRuntime.bringRestore[mob] = nil end
        end
    end
    runtime.state.bringHeld[mob] = nil
    runtime.state.bringSnapped[mob] = nil
    runtime.state.bringCarryingTarget[mob] = nil
    -- the slot is only given back; the counter never walks back, or a new mob
    -- would take a step a mob that is still held already stands on
    runtime.state.bringSlot[mob] = nil
end
letGoMob = runtime.letGoMob

-- Keep restoration snapshots in the shared runtime registry when an
-- execution is torn down. The next execution can adopt them and finish the
-- restoration after ownership returns.
runtime.exportPendingBringSnapshots = function()
    for mob, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.pending then
            FarmRuntime.bringRestore[mob] = saved
        end
    end
end
runtime.importBringRestoreSnapshots = function()
    for mob, saved in pairs(FarmRuntime.bringRestore) do
        local part = saved and saved.part
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        if not part or not part.Parent or (hum and hum.Health <= 0) then
            FarmRuntime.bringRestore[mob] = nil
            -- Sweep the identical stale copy from the live state as well.
            -- Do not touch a newer active snapshot for the same mob.
            if runtime.state.bringSaved[mob] == saved then
                runtime.state.bringSaved[mob] = nil
            end
        elseif not runtime.state.bringSaved[mob] then
            runtime.state.bringSaved[mob] = saved
        end
    end
end
runtime.restorePendingBringMobs = function()
    local pending = {}
    for mob, saved in pairs(runtime.state.bringSaved) do
        if saved and saved.pending then
            pending[#pending + 1] = {mob = mob, saved = saved}
        end
    end
    for _, entry in ipairs(pending) do
        local mob, saved = entry.mob, entry.saved
        local part = saved and saved.part
        local hum = mob and mob:FindFirstChildOfClass("Humanoid")
        if not part or not part.Parent or (hum and hum.Health <= 0) then
            runtime.state.bringSaved[mob] = nil
            FarmRuntime.bringRestore[mob] = nil
        elseif runtime.bringLocallyOwned(part) then
            runtime.letGoMob(mob, part)
        end
    end
end
runtime.importBringRestoreSnapshots()

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
        if runtime.state.bringHeld[target] or runtime.state.bringSaved[target] then
            runtime.letGoMob(target, anchor)
        end
        return
    end

    local now = tick()

    -- Check the straight route before the range and height gates. Otherwise an
    -- out-of-range target can pull the player across water before Bring Mob
    -- ever learns that the route is wet. The result is cached briefly and
    -- repeated when the player moves.
    local pathCheck = runtime.state.bringPathCheck
    if pathCheck and pathCheck.target ~= target then pathCheck = nil end
    local pathRootMoved = pathCheck and pathCheck.root
        and (pathCheck.root - root.Position).Magnitude > 3
    if not pathCheck or now - (pathCheck.at or 0) > 0.5 or pathRootMoved then
        pathCheck = {
            target = target,
            at = now,
            root = root.Position,
            blocked = runtime.bringPathOverWater(anchor.Position, root.Position),
        }
        runtime.state.bringPathCheck = pathCheck
    end
    runtime.state.bringPathBlocked = pathCheck.blocked == true
    if runtime.state.bringPathBlocked then
        -- A wet path is never used for a mob or for the player's approach. The
        -- pack is released and the stable hold position is kept instead.
        for mob, part in pairs(runtime.state.bringHeld) do
            runtime.letGoMob(mob, part)
        end
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint = nil
        runtime.state.bringCentre = nil
        runtime.state.bringCarryOffsetY = nil
        return
    end

    local bringRange = tonumber(runtime.config.BringMobRange) or 60
    -- BringMobRange is a horizontal range. The main loop uses the same
    -- X/Z geometry, so a configured limit means exactly the same thing in
    -- both places. An out-of-range target releases the whole pack at once.
    local rangeDx = anchor.Position.X - root.Position.X
    local rangeDy = anchor.Position.Y - root.Position.Y
    local rangeDz = anchor.Position.Z - root.Position.Z
    local rangeFlat = math.sqrt(rangeDx * rangeDx + rangeDz * rangeDz)
    if bringRange <= 0 or rangeFlat > bringRange then
        for mob, part in pairs(runtime.state.bringHeld) do
            runtime.letGoMob(mob, part)
        end
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathBlocked = false
        runtime.state.bringPathCheck = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
        return
    end

    -- The player must also be near the mob's height before the carry starts.
    -- Otherwise the bot grabs a camp from high in the air and carries it at
    -- that impossible vertical offset, which is how a pack ended up below the
    -- walkable ground and in the water.
    local verticalRange = tonumber(runtime.config.BringMobVerticalRange) or 18
    if verticalRange > 0 and math.abs(rangeDy) > verticalRange then
        for mob, part in pairs(runtime.state.bringHeld) do
            runtime.letGoMob(mob, part)
        end
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathBlocked = false
        runtime.state.bringPathCheck = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
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
        for mob, saved in pairs(runtime.state.bringSaved) do
            if saved and saved.part then runtime.letGoMob(mob, saved.part) end
        end
        runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathBlocked = false
        runtime.state.bringPathCheck = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
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
        runtime.state.bringCarryOffsetY = nil
        runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
    end

    -- Keep the carried rig at a fixed vertical distance from the player. The
    -- old goal was rebuilt from the rig's current Y every update, so gravity
    -- could lower both the goal and the rig without limit. The live trace
    -- showed that drift ending on the ocean plane and pulling the player down
    -- with it. Capture the original offset once per target and keep it stable.
    local carryOffsetY
    if carryTarget then
        carryOffsetY = runtime.state.bringCarryOffsetY
        if carryOffsetY == nil then
            local rawOffsetY = anchor.Position.Y - root.Position.Y
            local maxDrop = math.max((runtime.config.HoverHeight or 7) + 8, 12)
            local maxRise = 8
            carryOffsetY = math.max(-maxDrop, math.min(maxRise, rawOffsetY))
            runtime.state.bringCarryOffsetY = carryOffsetY
        end
    else
        runtime.state.bringCarryOffsetY = nil
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
    local pathGoal = carryTarget and root.Position or anchor.Position
    if count > 1 then
        local near = {}
        for _, mob in ipairs(collectEnemies(now)) do
            if mob ~= target and not mob:FindFirstChild("Ignored") then
                local part = anchorOf(mob)
                local hum = mob:FindFirstChildOfClass("Humanoid")
                if part and hum and hum.Health > 0 and not ownedByOther(part)
                    and runtime.bringLocallyOwned(part)
                    and mobKey(mob.Name) == key
                    and (part.Position - anchor.Position).Magnitude <= (runtime.config.BringMobSearch or 200)
                    and (verticalRange <= 0
                        or math.abs(part.Position.Y - anchor.Position.Y) <= verticalRange) then
                    table.insert(near, {mob = mob, dist = (part.Position - anchor.Position).Magnitude})
                end
            end
        end
        table.sort(near, function(a, b) return a.dist < b.dist end)
        for _, entry in ipairs(near) do
            if #list >= count then break end
            local mob, part = entry.mob, anchorOf(entry.mob)
            local cached = runtime.state.bringPathCache[mob]
            local goalMoved = cached and cached.goal
                and (cached.goal - pathGoal).Magnitude > 3
            if not cached or now - (cached.at or 0) > 1 or goalMoved then
                cached = {
                    at = now,
                    goal = pathGoal,
                    blocked = runtime.bringPathOverWater(part.Position, pathGoal),
                }
                runtime.state.bringPathCache[mob] = cached
            end
            if not cached.blocked then
                table.insert(list, entry.mob)
            end
        end
    end

    local stillHeld = {}
    for index, mob in ipairs(list) do
        local part = anchorOf(mob)
        if part then
            local isTarget = mob == target
            -- A server-owned target is the centre of the ring but is never
            -- held or changed. Only locally owned extras are packed around
            -- it, and the player walks to the target itself. Ownership is
            -- checked again here: it can change between selecting the mob
            -- and changing its rig.
            local shouldHold = (not isTarget) or carryTarget
            if shouldHold and not runtime.bringLocallyOwned(part) then
                runtime.letGoMob(mob, part)
                shouldHold = false
            end
            if not shouldHold then
                if runtime.state.bringHeld[mob] or runtime.state.bringSaved[mob] then
                    runtime.letGoMob(mob, part)
                end
            else
                -- A snapshot left by a temporary ownership loss must be
                -- restored before this mob becomes an active hold again. Only
                -- then is a fresh snapshot of the current game state captured.
                local pendingSaved = runtime.state.bringSaved[mob]
                if pendingSaved and pendingSaved.pending then
                    runtime.letGoMob(mob, part)
                end
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
                -- pulled over a slope otherwise floats or sinks into it. A
                -- carried target uses the stable player-relative height above;
                -- using its current Y here made the goal fall with the rig.
                local packY = anchor.Position.Y
                if carryTarget then
                    packY = root.Position.Y + carryOffsetY
                end
                local goal = Vector3.new(goalX,
                    packY + (part.Size.Y - anchor.Size.Y) * 0.5, goalZ)
                local hum = mob:FindFirstChildOfClass("Humanoid")

                -- The pack keeps the real assembly mass and the real touch
                -- behaviour. Only collision and the walking state are changed,
                -- and every original value is written down before the first
                -- change so release can restore the rig exactly.
                if not runtime.state.bringSaved[mob] then
                    local saved = { parts = {}, part = part, pending = false }
                    for _, d in ipairs(mob:GetDescendants()) do
                        if d:IsA("BasePart") then
                            saved.parts[d] = {
                                collide = d.CanCollide,
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

                    -- Ownership is checked immediately before each change.
                    -- If it was lost during the capture, release restores the
                    -- untouched rig and the mob is no longer part of the pack.
                    for d in pairs(saved.parts) do
                        if d.Parent and runtime.bringLocallyOwned(part) then
                            pcall(function() d.CanCollide = false end)
                        end
                    end
                    if runtime.bringLocallyOwned(part) then
                        pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
                    end
                    if runtime.bringLocallyOwned(part) then
                        pcall(function() part.AssemblyAngularVelocity = Vector3.zero end)
                    end
                    if runtime.bringLocallyOwned(part) then
                        pcall(function() part:SetAttribute("BeingBrought", true) end)
                    end
                end

                if hum and stillHeld[mob] then
                    if runtime.bringLocallyOwned(part) then
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.PlatformStand = true end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.AutoRotate = false end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.WalkSpeed = 0 end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function() hum.JumpPower = 0 end)
                        end
                        if runtime.bringLocallyOwned(part) then
                            pcall(function()
                                hum:ChangeState(Enum.HumanoidStateType.Physics)
                            end)
                        end
                        -- This is the fast first step from the working source.
                        -- It checks ownership again before moving the root.
                        if runtime.bringLocallyOwned(part) then
                            runtime.bringSnap(mob, part, goal)
                        end
                    else
                        runtime.letGoMob(mob, part)
                        stillHeld[mob] = nil
                    end
                end

                if stillHeld[mob] then
                    -- The game deliberately refuses to run its BodyMover on enemy
                    -- characters. Each carried mob therefore gets one private root
                    -- BodyVelocity with a unique runtime name. Only that exact mover
                    -- is stored and later destroyed; unrelated movers are untouched.
                    local mover = runtime.state.bringMover[mob]
                    if mover and not runtime.validBringMover(mover, part) then
                        pcall(function() mover:Destroy() end)
                        runtime.state.bringMover[mob] = nil
                        mover = nil
                    end
                    if not mover and runtime.bringLocallyOwned(part) then
                        runtime.state.bringMoverSeq = (runtime.state.bringMoverSeq or 0) + 1
                        mover = Instance.new("BodyVelocity")
                        mover.Name = "FarmBringMover_" .. tostring(runtime.generation)
                            .. "_" .. tostring(runtime.state.bringMoverSeq)
                        -- The working source uses 1e9. A finite force is enough for
                        -- every enemy rig and avoids an unbounded force on an assembly
                        -- that is changing ownership.
                        mover.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                        mover.P = 12500
                        mover.Velocity = Vector3.zero
                        pcall(function() mover:SetAttribute("FarmOwned", true) end)
                        if runtime.bringLocallyOwned(part) then
                            mover.Parent = part
                            runtime.state.bringMover[mob] = mover
                        else
                            mover:Destroy()
                            mover = nil
                            runtime.letGoMob(mob, part)
                            stillHeld[mob] = nil
                        end
                    elseif not mover then
                        runtime.letGoMob(mob, part)
                        stillHeld[mob] = nil
                    end

                    -- The hold drags the mob over with the same body velocity the hubs
                    -- use. The owned target is carried too, so the bot fights where it
                    -- stands instead of walking after a mob that was never brought.
                    if stillHeld[mob] and mover and runtime.bringLocallyOwned(part) then
                        local toGo = goal - part.Position
                        local gap = toGo.Magnitude
                        if gap > 0.6 then
                            -- A speed that closes a fixed fraction of the gap per update
                            -- (the hold is refreshed twenty times a second). The old
                            -- distance times eight with a six-stud floor overshot every
                            -- step, and the mob visibly bounced.
                            mover.Velocity = toGo.Unit * math.min(gap * 4, 120)
                        else
                            mover.Velocity = Vector3.zero
                        end
                        runtime.state.bringHeld[mob] = part
                    elseif stillHeld[mob] then
                        runtime.letGoMob(mob, part)
                        stillHeld[mob] = nil
                    end
                end
            end
        end
    end

    -- A rig whose ownership was taken away keeps its original snapshot until
    -- it can be restored. If ownership has returned but the mob is no longer
    -- part of this pack, restore it now instead of freezing it for ever.
    local restorePending = {}
    for mob, saved in pairs(runtime.state.bringSaved) do
        if not stillHeld[mob] then
            restorePending[#restorePending + 1] = {
                mob = mob,
                part = saved and saved.part,
            }
        end
    end
    for _, entry in ipairs(restorePending) do
        local part = entry.part
        if part and part.Parent and runtime.bringLocallyOwned(part) then
            runtime.letGoMob(entry.mob, part)
        elseif not part or not part.Parent then
            runtime.state.bringSaved[entry.mob] = nil
        end
    end

    runtime.state.bringCarryingTarget[target] = stillHeld[target] == true
    if not stillHeld[target] then
        runtime.state.bringCarryOffsetY = nil
    end

    -- the mobs of the last pack that are not in this one any more go free
    local releaseHeld = {}
    for mob, part in pairs(runtime.state.bringHeld) do
        if not stillHeld[mob] then
            releaseHeld[#releaseHeld + 1] = {mob = mob, part = part}
        end
    end
    for _, entry in ipairs(releaseHeld) do
        runtime.letGoMob(entry.mob, entry.part)
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
local tweenProxy
local tweenFollower
local tweenHold
local tweenHoldRoot

-- Banana Hub does not tween HumanoidRootPart directly. It tweens a small
-- transparent proxy and makes the character follow that proxy every frame.
-- The character therefore keeps the proxy's exact interpolated position while
-- its Humanoid is in the physics state. A zero-velocity body hold keeps
-- gravity from pulling it away before an official touch can be observed.
-- The main script keeps its own movement-owner lock around this transport.
local function destroyTweenHold()
    local oldRoot = tweenHoldRoot
    if tweenHold and tweenHold.Parent then
        pcall(function() tweenHold:Destroy() end)
    end
    tweenHold = nil
    tweenHoldRoot = nil
    if oldRoot and oldRoot.Parent then
        pcall(function() oldRoot.AssemblyLinearVelocity = Vector3.zero end)
    end
end

local function hasActiveBringHold()
    for _, carried in pairs(runtime.state.bringCarryingTarget or {}) do
        if carried == true then return true end
    end
    return false
end

local function shouldKeepTweenHold()
    return runtime.state.saberActive == true or runtime.state.flying == true
        or hasActiveBringHold()
end

local function ensureTweenHold(root)
    if not root then return end
    if tweenHold and tweenHold.Parent and tweenHoldRoot == root then return end
    destroyTweenHold()
    local hold = Instance.new("BodyVelocity")
    hold.Name = "FarmRuntimeTweenHold"
    hold.MaxForce = Vector3.new(100000, 100000, 100000)
    hold.Velocity = Vector3.zero
    hold.Parent = root
    tweenHold = hold
    tweenHoldRoot = root
end

runtime.releaseTweenHold = function()
    if not shouldKeepTweenHold() then destroyTweenHold() end
end

local function getTweenProxy(root)
    if tweenProxy and tweenProxy.Parent then
        local ownerGeneration = tweenProxy:GetAttribute("FarmRuntimeGeneration")
        if ownerGeneration == runtime.generation then
            tweenProxy.CFrame = root.CFrame
            return tweenProxy
        end
        -- A proxy from an older runtime must never become the transport of a
        -- newer runtime. The old owner has already been stopped by the time
        -- this code runs, so the stale part can be removed safely.
        pcall(function() tweenProxy:Destroy() end)
        tweenProxy = nil
    end
    local proxy = Instance.new("Part")
    proxy.Name = "FarmRuntimeTweenProxy"
    proxy:SetAttribute("FarmRuntimeGeneration", runtime.generation)
    proxy.Size = Vector3.new(1, 1, 1)
    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CanTouch = false
    proxy.Massless = true
    proxy.Transparency = 1
    proxy.CFrame = root.CFrame
    proxy.Parent = Workspace
    tweenProxy = proxy
    return proxy
end

-- A crashed or older runtime can leave its invisible proxy behind. The
-- current runtime owns the character and must not inherit that stale part.
for _, object in ipairs(Workspace:GetChildren()) do
    if object:IsA("BasePart") and object.Name == "FarmRuntimeTweenProxy"
        and object:GetAttribute("FarmRuntimeGeneration") ~= runtime.generation then
        pcall(function() object:Destroy() end)
    end
end

local function startTweenFollower(tween, proxy)
    local follower = {cancelled = false}
    tweenFollower = follower
    task.spawn(function()
        while not follower.cancelled and activeTween == tween do
            local root = getRoot()
            if root then
                ensureTweenHold(root)
                -- This is Banana Hub's proxy rule: a large divergence means
                -- the character was replaced or corrected, so the proxy takes
                -- the character's current pose; otherwise the character takes
                -- the proxy's interpolated pose.
                local gap = (root.Position - proxy.Position).Magnitude
                if gap > 200 then
                    proxy.CFrame = root.CFrame
                else
                    root.CFrame = proxy.CFrame
                end
            end
            if tween.PlaybackState ~= Enum.PlaybackState.Playing then break end
            task.wait()
        end
        if not follower.cancelled and activeTween == tween then
            local root = getRoot()
            if root then root.CFrame = proxy.CFrame end
            -- Saber and flight keep the hold through the final official touch.
            -- Ordinary farming releases it as soon as the tween is complete.
            if not shouldKeepTweenHold() then
                destroyTweenHold()
            end
        end
        if tweenFollower == follower then tweenFollower = nil end
    end)
end

-- The one tween of the script. Every trip of the character goes through here,
-- so the walk to a mob, the flight to an island and the way into the whirlpool
-- all move at exactly runtime.config.MoveSpeed. There is no cap: a longer way simply
-- takes longer, it is never rushed (a rushed flight is what the game undoes).
runtime.tweenTo = function(cf)
    local root = getRoot()
    if not root or not cf then return false end
    if runtime.state.travelActive then return false end
    local dist = (root.Position - cf.Position).Magnitude
    if activeTween and tweenGoal
        and activeTween.PlaybackState == Enum.PlaybackState.Playing then
        local moved = (tweenGoal.Position - cf.Position).Magnitude
        local left = (root.Position - tweenGoal.Position).Magnitude
        if moved < math.max(12, left * 0.4) then return false end
    end
    if activeTween then activeTween:Cancel() end
    if tweenFollower then tweenFollower.cancelled = true end
    runtime.setFlying()
    ensureTweenHold(root)
    local proxy = getTweenProxy(root)
    tweenGoal = cf
    activeTween = TweenService:Create(proxy,
        TweenInfo.new(math.max(dist / runtime.config.MoveSpeed, 0.12), Enum.EasingStyle.Linear),
        {CFrame = cf})
    activeTween:Play()
    startTweenFollower(activeTween, proxy)
    return true
end

-- Safe tween farming moves the character between real travel slots. The old
-- dodge loop changed the CFrame every frame around a tiny circle, which looked
-- like spinning in place and kept the player inside the enemy's threat range.
-- Each slot is far enough away to be safe and still inside the attack range.
runtime.tweenFarmSlot = function(targetObject, centre, root, heldTarget, height)
    if not targetObject or not centre or not root then return end
    local s = runtime.state
    local now = tick()
    local radius = tonumber(runtime.config.DodgeRadius) or 28
    if radius < 14 then radius = 14 end
    if radius > 45 then radius = 45 end

    if s.dodgeSlotTarget ~= targetObject then
        s.dodgeSlotTarget = targetObject
        s.dodgeSlotIndex = 0
        s.dodgeSlotAt = 0
        s.dodgePatrolCentre = nil
        local dx = root.Position.X - centre.X
        local dz = root.Position.Z - centre.Z
        s.dodgeSlotAngle = math.atan2(dz, dx)
    end

    local requestedStepTime = tonumber(runtime.config.DodgeStepTime) or 0.4
    if requestedStepTime < 0.2 then requestedStepTime = 0.2 end
    if requestedStepTime > 1.5 then requestedStepTime = 1.5 end
    if now < (s.dodgeSlotAt or 0) then return end

    local goal
    local candidateAngle
    local candidateIndex
    local polygonChord = 0
    if heldTarget then
        -- A carried target follows the player. Patrol around a stable centre
        -- instead of chasing the moving target, which would make the pack and
        -- the player pull against each other.
        local patrol = s.dodgePatrolCentre
        if not patrol or (root.Position - patrol).Magnitude > radius * 1.5 then
            patrol = root.Position
            s.dodgePatrolCentre = patrol
            s.dodgeSlotIndex = 0
        end
        candidateIndex = (s.dodgeSlotIndex or 0) + 1
        candidateAngle = ((candidateIndex - 1) % 4) * math.pi * 0.5
        goal = Vector3.new(patrol.X + math.cos(candidateAngle) * radius,
            height or (patrol.Y + (runtime.config.HoverHeight or 7)),
            patrol.Z + math.sin(candidateAngle) * radius)
    else
        -- Around a normal target, move through wide polygon legs. The first
        -- leg starts on the side where the player already is, so the approach
        -- never crosses through the mob.
        local speed = tonumber(runtime.config.DodgeSpeed) or 90
        local stepAngle = math.rad(speed * requestedStepTime)
        if stepAngle < math.pi / 3 then stepAngle = math.pi / 3 end
        -- The horizontal distance of this polygon leg is the chord between the
        -- old and new slot, not the radius of the ring.
        polygonChord = 2 * radius * math.sin(stepAngle * 0.5)
        candidateAngle = (s.dodgeSlotAngle or 0) + stepAngle
        goal = Vector3.new(centre.X + math.cos(candidateAngle) * radius,
            height or (centre.Y + (runtime.config.HoverHeight or 7)),
            centre.Z + math.sin(candidateAngle) * radius)
    end

    -- The next slot starts only after this exact leg has had time to finish.
    -- Otherwise a slow MoveSpeed can cancel the tween halfway and make the
    -- character jitter around the mob instead of travelling between slots.
    local legDistance = math.max((root.Position - goal).Magnitude, polygonChord)
    local travelTime = legDistance / math.max(1, tonumber(runtime.config.MoveSpeed) or 200)
    local slotDuration = math.max(requestedStepTime, travelTime + 0.1)
    local accepted = runtime.tweenTo(CFrame.new(goal) * CFrame.Angles(math.rad(-90), 0, 0))
    -- The polygon advances only when a tween was really accepted. A skipped
    -- or canceled leg must not count as a completed side of the safe ring.
    if accepted then
        if heldTarget then
            s.dodgeSlotIndex = candidateIndex
        else
            s.dodgeSlotAngle = candidateAngle
        end
        s.dodgeSlotAt = now + slotDuration
    end
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
    if tweenFollower then tweenFollower.cancelled = true; tweenFollower = nil end
    tweenGoal = nil
    runtime.releaseTweenHold()
    -- Another movement operation now owns the character. The polygon must
    -- start from a fresh side instead of continuing from a canceled leg.
    local s = runtime.state
    s.dodgeSlotTarget = nil
    s.dodgeSlotAngle = 0
    s.dodgeSlotIndex = 0
    s.dodgeSlotAt = 0
    s.dodgePatrolCentre = nil
    runtime.setWalking()
end

-- Anti-fall keeps a real ground point, not the last point of a tween in the
-- air. A raycast finds the floor below the character; the old point is only
-- replaced when the player is not already falling.
runtime.updateSafePoint = function(root, now)
    if not root then return end
    if root.Position.Y <= (runtime.config.SafeY or -300) + 10 then return end
    local velocity = root.AssemblyLinearVelocity
    if velocity.Y < -35 then return end
    if runtime.state.flying or runtime.state.travelActive then return end
    if activeTween and activeTween.PlaybackState == Enum.PlaybackState.Playing then return end
    local char = LocalPlayer.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = char and {char} or {}
    local ok, hit = pcall(function()
        return Workspace:Raycast(root.Position, Vector3.new(0, -900, 0), params)
    end)
    if ok and hit and not runtime.bringWaterPart(hit.Instance)
        and hit.Position.Y > (runtime.config.SafeY or -300) + 5 then
        runtime.state.lastSafe = hit.Position + Vector3.new(0, 4, 0)
        runtime.state.lastSafeAt = now
    end
end

runtime.fallbackSafePoint = function(root)
    local best, bestD = nil, math.huge
    local function consider(obj)
        local anchor = anchorOf(obj)
        if anchor and not runtime.bringPointOverWater(anchor.Position) then
            local d = root and (root.Position - anchor.Position).Magnitude or 0
            if d < bestD then best, bestD = anchor, d end
        end
    end
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("SpawnLocation") then consider(d) end
    end
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("PlayerSpawns")
    if spawns then
        for _, d in ipairs(spawns:GetChildren()) do consider(d) end
    end
    local map = Workspace:FindFirstChild("Map")
    if map then
        local teleport = map:FindFirstChild("TeleportSpawn")
        if teleport then consider(teleport) end
    end
    return best and best.Position or nil
end

runtime.recoverFall = function(root, now)
    if not runtime.config.AntiFall or not root then return false end
    -- A tween or a world/flight operation is a deliberate route. Recovering
    -- from a fall in the middle of one cancels the route and can move the
    -- character into a different island or sea.
    if runtime.state.travelActive or runtime.state.flying then return false end
    if activeTween and activeTween.PlaybackState == Enum.PlaybackState.Playing then return false end
    local limit = tonumber(runtime.config.SafeY) or -300
    local velocity = root.AssemblyLinearVelocity
    local falling = velocity.Y < -70
    if root.Position.Y >= limit and not (falling and root.Position.Y < limit + 140) then
        return false
    end
    if now < (runtime.state.recoverUntil or 0) then return true end

    local flightOwner = runtime.state.flightOwner
    local flightOwnerToken = runtime.state.flightMovementToken
    runtime.state.flightToken = (runtime.state.flightToken or 0) + 1
    runtime.state.flying = false
    runtime.state.flightOwner = nil
    runtime.state.flightMovementToken = nil
    if flightOwner and runtime.releaseMovement then
        runtime.releaseMovement(flightOwner, flightOwnerToken)
    end
    if flightOwner == "shop" and runtime.resetShopState then runtime.resetShopState() end
    runtime.stopTween()
    -- A falling player must not keep dragging a pack downward. Release the
    -- Bring Mob hold before the recovery teleport so the mobs cannot pull the
    -- character back into the sea.
    if runtime.releaseBringMobs then runtime.releaseBringMobs() end
    if runtime.restoreHitbox then runtime.restoreHitbox() end
    if runtime.restoreNoclip then runtime.restoreNoclip() end
    local safe = runtime.state.lastSafe or runtime.fallbackSafePoint(root)
    runtime.state.recoverUntil = now + 2
    runtime.state.status = "Recovering..."
    -- Stop the downward velocity even when no safe point exists. Otherwise
    -- the character can keep accelerating while the next recovery attempt is
    -- waiting for the cooldown.
    local velocity = root.AssemblyLinearVelocity
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(
            velocity.X, math.max(0, velocity.Y), velocity.Z)
    end)
    if safe then
        root.CFrame = CFrame.new(safe)
        local velocity = root.AssemblyLinearVelocity
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(
                velocity.X, math.max(0, velocity.Y), velocity.Z)
        end)
        runtime.setWalking()
        dbg(string.format("Recovered from a fall (Y=%.0f)", root.Position.Y))
    else
        dbg(string.format("Fall detected (Y=%.0f), but no safe point was found", root.Position.Y))
    end
    return true
end

runtime.moveTo = function(cf, noWarp)
    local root = getRoot()
    if not root then return end
    if runtime.state.travelActive then return end
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
    -- bypasses it; here we only clear the client stun/busy flags that can
    -- block a swing.
    local char = LocalPlayer.Character
    for _, name in ipairs({"Stun", "Busy"}) do
        local marker = char and char:FindFirstChild(name)
        if marker then
            pcall(function()
                if marker:IsA("BoolValue") then
                    marker.Value = false
                else
                    marker.Value = 0
                end
            end)
        end
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
    runtime.state.attackRegistered = false
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
            -- End the synthetic touch even for a normal gun. Destroying only
            -- the event left some controller paths with a Begin input that
            -- never received its matching End.
            pcall(function() input.UserInputState = Enum.UserInputState.End end)
            pcall(function() changed:Fire() end)
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
        runtime.state.attackRegistered = true
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

-- Health confirmation runs beside the attack loop. Waiting for the mob to lose
-- health used to block the next swing for the whole animation (often about two
-- seconds). The watcher records real health decreases without delaying the
-- next attack and backs the fast cadence off when the server refuses a hit.
--
-- Fast attacks can overlap, so every pending swing is kept in dispatch order.
-- A health decrease is claimed by the oldest swing that has not claimed that
-- mob yet. This prevents a late hit from the previous packet from falsely
-- confirming the newer packet, while a later decrease can still confirm the
-- newer swing.
runtime.publishAttackConfirmation = function(record)
    local s = runtime.state
    if not record or record.id ~= s.attackConfirmSeq then return end
    s.attackConfirmed = record.fullConfirmed
    s.attackPrimaryConfirmed = record.primaryConfirmed
    s.aoeCount = record.count
    s.aoeConfirmed = record.fullConfirmed and record.count or 0
    if record.primaryConfirmed then
        local extra = record.count > 1 and (" +" .. tostring(record.count - 1) .. " damaged") or ""
        s.status = "Hitting " .. record.targetName .. extra
            .. (record.fullConfirmed and " (confirmed)" or " (primary confirmed)")
    end
end

runtime.pollAttackDamage = function()
    local s = runtime.state
    local pending = s.attackPending or {}
    local observed = {}

    -- Read every watched mob once. The global seen value is the health after
    -- the last decrease that was already assigned to an earlier swing.
    for _, record in ipairs(pending) do
        for mob in pairs(record.watched) do
            if observed[mob] == nil then
                local hum = mob and mob:FindFirstChildOfClass("Humanoid")
                if hum then observed[mob] = hum.Health end
            end
        end
    end

    for mob, currentHealth in pairs(observed) do
        local seen = s.attackHealthSeen[mob]
        if seen == nil then
            seen = currentHealth
        elseif currentHealth < seen then
            -- Assign this decrease to the oldest pending swing that has not
            -- already claimed a decrease from this mob.
            for _, record in ipairs(pending) do
                if record.watched[mob] and not record.claimed[mob] then
                    record.claimed[mob] = true
                    record.count = record.count + 1
                    if mob == record.target then
                        record.primaryConfirmed = true
                        -- Count the Pole hit when this record actually claims
                        -- the decrease. Publication may happen after a newer
                        -- swing became current, but the older confirmed hit
                        -- must still count exactly once.
                        if record.pole and not record.poleCounted
                            and s.poleToken == record.poleToken
                            and s.poleWeapon == record.poleWeapon then
                            record.poleCounted = true
                            s.poleHits = (s.poleHits or 0) + 1
                            s.poleProgressAt = tick()
                        end
                    end
                    -- Full AOE confirmation still means that every watched mob
                    -- lost health. A primary hit by itself is not full AOE.
                    if record.primaryConfirmed and record.count >= record.watchedCount then
                        record.fullConfirmed = true
                    end
                    if record.primaryConfirmed and record.id == s.attackConfirmSeq then
                        s.attackLastConfirmedAt = tick()
                        s.attackMisses = 0
                        s.attackCadence = record.fastTarget
                    end
                    break
                end
            end
        end
        -- Health regeneration and a decrease that no pending swing claimed are
        -- both folded into the next baseline.
        s.attackHealthSeen[mob] = currentHealth
    end

    local latest = nil
    for _, record in ipairs(pending) do
        if record.id == s.attackConfirmSeq then latest = record end
        if not record.feedbackChecked and tick() >= record.feedbackDeadline then
            record.feedbackChecked = true
            -- Only the newest swing owns the shared cadence. An older missed
            -- packet must not mask a miss from the current target.
            if record.id == s.attackConfirmSeq and not record.primaryConfirmed then
                s.attackMisses = (s.attackMisses or 0) + 1
                local current = s.attackCadence or record.fastTarget
                local safe = math.max(record.fastTarget, record.officialDelay)
                s.attackCadence = math.min(safe,
                    math.max(record.fastTarget, current * 1.5))
            end
        end
    end

    if latest then runtime.publishAttackConfirmation(latest) end

    -- A fully confirmed swing no longer needs to stay in the claim queue.
    -- Remove from the back so an earlier record is never skipped.
    for index = #pending, 1, -1 do
        local record = pending[index]
        if record.fullConfirmed then
            if record.id == s.attackConfirmSeq then
                runtime.publishAttackConfirmation(record)
            end
            table.remove(pending, index)
        end
    end
end

runtime.removeAttackRecord = function(record)
    local pending = runtime.state.attackPending or {}
    for index, item in ipairs(pending) do
        if item == record then
            table.remove(pending, index)
            return true
        end
    end
    return false
end

runtime.startAttackConfirmation = function(watched, target, deadline, startedAt,
    epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
    local s = runtime.state
    -- Account for damage that landed just before this swing was registered.
    -- Existing older records get the first claim through the normal queue.
    runtime.pollAttackDamage()

    local watchedCount = 0
    for _ in pairs(watched) do watchedCount = watchedCount + 1 end
    local sequence = (s.attackConfirmSeq or 0) + 1
    local feedbackWindow = tonumber(runtime.config.FastAttackFeedback) or 0.55
    local record = {
        id = sequence,
        watched = watched,
        target = target,
        targetName = target and target.Name or "the target",
        watchedCount = watchedCount,
        claimed = {},
        count = 0,
        primaryConfirmed = false,
        fullConfirmed = false,
        feedbackChecked = false,
        feedbackDeadline = math.min(deadline, startedAt + feedbackWindow),
        officialDelay = officialDelay,
        fastTarget = fastTarget,
        gun = gun,
        pole = tool ~= nil and tool == s.poleWeapon and s.poleEquipped == true,
        poleToken = s.poleToken,
        poleWeapon = tool,
        poleCounted = false,
    }

    -- A mob that is not watched by an older pending swing starts at the health
    -- it has now. A decrease from before this dispatch is not its damage.
    local pending = s.attackPending or {}
    for mob, health in pairs(watched) do
        local watchedByOlder = false
        for _, older in ipairs(pending) do
            if older.watched[mob] then
                watchedByOlder = true
                break
            end
        end
        if not watchedByOlder then s.attackHealthSeen[mob] = health end
    end

    table.insert(pending, record)
    s.attackPending = pending
    s.attackConfirmSeq = sequence
    s.attackConfirmed = false
    s.attackPrimaryConfirmed = false
    s.aoeCount = 0
    s.aoeConfirmed = 0

    task.spawn(function()
        while tick() < deadline do
            runtime.pollAttackDamage()
            if record.fullConfirmed then break end
            task.wait(0.02)
            if not runtime.operationValid(operationEpoch, epoch, char) then return end
        end

        runtime.pollAttackDamage()
        runtime.removeAttackRecord(record)
        if record.id == s.attackConfirmSeq then
            runtime.publishAttackConfirmation(record)
        end
    end)
end

local function doAttack(tool, target)
    if not tool then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char or not runtime.operationValid(operationEpoch, epoch, char) then return false end
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

    local speed = tonumber(runtime.state.attackSpeed) or 1
    local charSpeed = char and tonumber(char:GetAttribute("AttackSpeedMultiplier")) or 1
    if charSpeed > speed then speed = charSpeed end
    if speed < 0.1 then speed = 0.1 end

    local extraDelay = tonumber(runtime.config.AttackCooldown) or 0
    local officialDelay
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
        officialDelay = interval / speed
    else
        -- The live controller can cancel a basic attack at 80% of its
        -- animation. This is the safe cadence used when Fast Attack is off or
        -- when health feedback has to back the quick cadence off.
        officialDelay = animLength * 0.8 / speed
    end
    if officialDelay < 0.05 then officialDelay = 0.05 end

    local fastTarget = tonumber(runtime.config.FastAttackInterval) or 0.4
    if fastTarget < 0.15 then fastTarget = 0.15 end
    if fastTarget > 1.5 then fastTarget = 1.5 end
    local delay = officialDelay + extraDelay
    local reportedLength = animLength
    if not gun and runtime.config.FastAttack and runtime.config.RemoteAttack then
        local cadence = tonumber(runtime.state.attackCadence) or fastTarget
        if cadence < fastTarget then cadence = fastTarget end
        if cadence > officialDelay then cadence = officialDelay end
        delay = cadence + extraDelay
        -- RegisterAttack still uses the official length/combo protocol. In Fast
        -- Attack mode the length describes the shortened effective animation,
        -- just like the game does when an animation speed multiplier is used.
        local officialBase = animLength * 0.8 / speed
        if officialBase > 0 then
            reportedLength = math.max(0.15,
                math.min(animLength, animLength * (cadence / officialBase)))
        end
    end
    if delay < 0.05 then delay = 0.05 end
    runtime.state.attackReportedLength = reportedLength

    local dispatched = false
    if runtime.config.RemoteAttack then
        dispatched = remoteAttack(target, tool, reportedLength, combo, attackPairs)
    else
        runtime.state.attackRegistered = false
        runtime.state.attackHitDispatched = false
        runtime.state.attackComboSent = false
        runtime.state.aoeCount = 0
    end
    if not runtime.operationValid(operationEpoch, epoch, char) then return false end

    if dispatched then
        runtime.state.attackNextAt = now + delay
        runtime.state.lastAttack = now
        runtime.state.attackFallback = false
        local deadline = now + (gun and 0.6
            or math.min(2.5, math.max(0.7, animLength * 0.8 + 0.2)))
        runtime.startAttackConfirmation(watched, target, deadline, now,
            epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
        return true
    elseif gun and runtime.config.RemoteAttack then
        -- The controller refused this attempt (usually a reload or cooldown).
        -- It must not be bypassed with a raw tool activation.
        runtime.state.attackNextAt = now + math.max(delay, 0.1)
        return false
    elseif runtime.state.attackRegistered then
        -- RegisterAttack succeeded even when the hit transmission failed or
        -- only partly succeeded. The swing is already registered with the
        -- server, so tool:Activate would register a second attack in the
        -- same window. Wait for the next cadence instead.
        runtime.state.attackNextAt = now + delay
        runtime.state.lastAttack = now
        runtime.state.attackFallback = false
        local deadline = now + math.min(2.5, math.max(0.7, animLength * 0.8 + 0.2))
        runtime.startAttackConfirmation(watched, target, deadline, now,
            epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
        return true
    end

    if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
    local deadline = now + math.max(0.35, math.min(1, delay + 0.2))
    runtime.startAttackConfirmation(watched, target, deadline, now,
        epoch, operationEpoch, char, officialDelay, fastTarget, gun, tool)
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

-- Auto Saber can be enabled while ordinary farming is off. In that mode the
-- normal farm path must not be used as a fallback: it would select and attack
-- an unrelated mob. This path owns only the exact Saber boss named by the
-- current puzzle stage, while reusing the same weapon, movement and official
-- attack confirmation systems as the normal farm.
runtime.runSaberCombat = function(root)
    if not root or not runtime.state.saberActive then return false end
    local wanted = runtime.state.saberTarget
    if type(wanted) ~= "string" or wanted == "" then return false end

    local target = nil
    local wantedLower = wanted:lower()
    for _, candidate in ipairs(collectEnemies(tick())) do
        if candidate.Name:lower() == wantedLower then
            target = candidate
            break
        end
    end
    if not target then
        runtime.state.status = "Saber: waiting for " .. wanted
        return false
    end

    local targetHum = target:FindFirstChildOfClass("Humanoid")
    local er = anchorOf(target)
    if not targetHum or targetHum.Health <= 0 or not er then return true end

    local tool = equipWeapon()
    if not tool or isFruit(tool) then
        runtime.state.status = "Saber: no usable weapon"
        return true
    end

    local reach = attackRange(tool)
    local hover = runtime.config.HoverHeight
    if reach <= runtime.config.MeleeRange and not runtime.config.RemoteAttack then
        hover = math.min(hover, runtime.config.MeleeHover)
    end

    local head = target:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        head = nil
        for _, descendant in ipairs(target:GetDescendants()) do
            if descendant:IsA("BasePart")
                and descendant.Name:lower():find("head", 1, true) then
                head = descendant
                break
            end
        end
    end

    local hoverPos
    if head then
        local above = runtime.config.RemoteAttack
            and math.max(hover, runtime.config.HeadHover) or runtime.config.HeadHover
        hoverPos = head.Position + Vector3.new(0, above, 0)
    else
        hoverPos = er.Position + Vector3.new(0, hover, 0)
    end
    local top = er.Position.Y + (er.Size and er.Size.Y or 0) / 2
    hoverPos = Vector3.new(hoverPos.X, math.max(hoverPos.Y, top - 1), hoverPos.Z)

    -- The Saber target is never carried with an ordinary mob pack. The safe
    -- tween ring is still used when it is enabled, so the boss fight uses the
    -- same movement speed and ownership rules as the rest of the script.
    if runtime.config.Dodge and runtime.config.RemoteAttack then
        runtime.tweenFarmSlot(target, er.Position, root, false, hoverPos.Y)
    else
        runtime.travelTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))
    end

    local dx = root.Position.X - er.Position.X
    local dz = root.Position.Z - er.Position.Z
    local swingFlat = math.sqrt(dx * dx + dz * dz)
    if runtime.config.BigHitbox and swingFlat <= reach then
        enlargeHitbox(target)
    elseif runtime.state.hitboxPart then
        restoreHitbox()
    end

    local now = tick()
    if runtime.config.AutoAttack
        and (not runtime.state.attackNextAt or now >= runtime.state.attackNextAt)
        and swingFlat <= reach then
        if doAttack(tool, target) then
            runtime.state.lastAttack = now
            runtime.state.status = "Hitting " .. target.Name
        end
    elseif swingFlat > reach then
        runtime.state.status = "Saber: approaching " .. target.Name
    end
    return true
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

-- Pole mastery is passive in the game: the server awards mastery from real
-- Pole hits. The mode therefore keeps one Pole equipped and reports the
-- tool's own mastery level instead of inventing a direct upgrade RPC.
runtime.findPole = function()
    local containers = {}
    local char = LocalPlayer.Character
    if char then table.insert(containers, char) end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then table.insert(containers, backpack) end
    for _, container in ipairs(containers) do
        for _, tool in ipairs(container:GetChildren()) do
            -- Name-only matching accepts any client-created Tool containing
            -- "pole". Use the official physical ItemIds for both mastery forms;
            -- their active movesets are 1132 and 1193 respectively.
            local itemId = tool:GetAttribute("ItemId")
            if tool:IsA("Tool") and (itemId == 51 or itemId == 121) then
                return tool
            end
        end
    end
    return nil
end

runtime.readToolMastery = function(tool)
    if not tool then return nil, nil end
    -- The current client exposes the mastery level as the tool's Level value.
    -- Other attributes such as Mastery or Data.Stars may describe a different
    -- value and must not be used as the current level.
    local level = tool:GetAttribute("Level")
    local exp = tool:GetAttribute("Exp") or tool:GetAttribute("Experience")
    if level == nil then
        local value = tool:FindFirstChild("Level")
        if value and type(value.Value) == "number" then level = value.Value end
    end
    if exp == nil then
        local value = tool:FindFirstChild("Exp")
        if value and type(value.Value) == "number" then exp = value.Value end
    end
    return tonumber(level), tonumber(exp)
end

runtime.equipPole = function()
    local char = LocalPlayer.Character
    local hum = getHumanoid()
    local pole = runtime.findPole()
    if runtime.state.poleWeapon and runtime.state.poleWeapon ~= pole then
        runtime.resetPoleState()
    end
    runtime.state.poleEquipped = false
    if not char or not hum or not pole then return nil end
    if pole.Parent ~= char then
        pcall(function() hum:EquipTool(pole) end)
        if pole.Parent ~= char then
            pcall(function() pole.Parent = char end)
        end
    end
    if pole.Parent ~= char then return nil end
    runtime.state.poleWeapon = pole
    if runtime.state.attackWeapon ~= pole then
        runtime.state.attackWeapon = pole
        runtime.state.attackCombo = 0
        runtime.state.attackComboAt = 0
        runtime.state.attackNextAt = 0
    end
    local level, exp = runtime.readToolMastery(pole)
    level, exp = level or 0, exp or 0
    if level > (runtime.state.poleLevel or 0) then
        runtime.state.poleLevel = level
        runtime.state.poleExp = exp
        runtime.state.poleProgressAt = tick()
    elseif exp > (runtime.state.poleExp or 0) then
        runtime.state.poleExp = exp
        runtime.state.poleProgressAt = tick()
    end
    runtime.state.poleEquipped = true
    return pole
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

-- The fruit ESP uses separate visual objects and leaves the proven pickup
-- scanner above untouched. Highlights and billboards are destroyed as soon as
-- the fruit disappears or the bot is reset.
runtime.worldFruits = function()
    local list = {}
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local function consider(obj)
        if isFruitTool(obj) then
            if not (char and obj:IsDescendantOf(char))
                and not (backpack and obj:IsDescendantOf(backpack)) then
                table.insert(list, obj)
            end
        end
    end
    local function walk(container, depth)
        for _, obj in ipairs(container:GetChildren()) do
            consider(obj)
            if depth > 0 and (obj:IsA("Folder") or obj:IsA("Model"))
                and inContainerName(obj.Name) then
                walk(obj, depth - 1)
            end
        end
    end
    walk(Workspace, 3)
    return list
end

runtime.fruitRarity = function(fruit)
    local attr = fruit:GetAttribute("Rarity") or fruit:GetAttribute("Quality")
        or fruit:GetAttribute("FruitRarity")
    if attr ~= nil then return tostring(attr) end
    if fruit:GetAttribute("IsGodly") == true then return "Godly" end
    if fruit:GetAttribute("IsMystery") == true then return "Mystery" end
    local name = fruit.Name:lower()
    if name:find("mystery", 1, true) then return "Mystery" end
    if name:find("legendary", 1, true) then return "Legendary" end
    if name:find("rare", 1, true) then return "Rare" end
    return "Devil Fruit"
end

runtime.fruitEspColor = function(rarity)
    local r = tostring(rarity):lower()
    if r:find("godly", 1, true) or r:find("legendary", 1, true) then
        return Color3.fromRGB(255, 205, 70)
    elseif r:find("mystery", 1, true) or r:find("epic", 1, true) then
        return Color3.fromRGB(190, 100, 255)
    elseif r:find("rare", 1, true) then
        return Color3.fromRGB(85, 170, 255)
    end
    return Color3.fromRGB(105, 220, 135)
end

runtime.destroyFruitEsp = function()
    local visuals = runtime.state and runtime.state.fruitEspVisuals
    if not visuals then return end
    for fruit, visual in pairs(visuals) do
        visuals[fruit] = nil
        if visual then
            pcall(function() visual.highlight:Destroy() end)
            pcall(function() visual.billboard:Destroy() end)
        end
    end
end

runtime.notifyFruit = function(fruit)
    local s = runtime.state
    if not runtime.config.FruitNotifier then return end
    local url = tostring(runtime.config.FruitWebhook or "")
    if url == "" then return end
    if s.notifiedFruitUrls[fruit] == url then return end
    local now = tick()
    local pending = s.fruitNotificationPending[fruit]
    if pending and pending.inFlight then return end
    if pending and pending.url == url and now < (pending.nextAt or 0) then return end

    local rarity = runtime.fruitRarity(fruit)
    if not pending then
        dbg("Devil fruit spotted: " .. fruit.Name .. " (" .. rarity .. ")")
    end
    local body = HttpService:JSONEncode({
        content = "Blox Fruits: " .. fruit.Name .. " (" .. rarity .. ") spotted",
        username = "Blox Fruits Fruit Notifier",
    })
    pending = {
        url = url,
        body = body,
        attempts = pending and pending.attempts or 0,
        nextAt = 0,
        inFlight = true,
    }
    s.fruitNotificationPending[fruit] = pending

    task.spawn(function()
        local ok, first, second = pcall(function()
            if request then
                return request({
                    Url = url,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = body,
                })
            elseif http_request then
                return http_request(url, "POST", body, {["Content-Type"] = "application/json"})
            end
            return false
        end)
        local success = false
        if ok then
            if type(first) == "boolean" then
                success = first and (type(second) ~= "number"
                    or (second >= 200 and second < 300))
            elseif type(first) == "number" then
                success = first >= 200 and first < 300
            end
        end
        local current = s.fruitNotificationPending[fruit]
        if current ~= pending then return end
        -- The destination may have changed while the request was in flight.
        -- A late success for the old URL must not mark the fruit as already
        -- notified for the new destination.
        if pending.url ~= tostring(runtime.config.FruitWebhook or "") then
            pending.inFlight = false
            pending.nextAt = 0
            return
        end
        if not runtime.config.FruitNotifier then
            pending.inFlight = false
            pending.nextAt = 0
            return
        end
        if success then
            s.fruitNotificationPending[fruit] = nil
            s.notifiedFruits[fruit] = true
            s.notifiedFruitUrls[fruit] = url
            dbg("Fruit notification sent for " .. fruit.Name)
            return
        end
        pending.inFlight = false
        pending.attempts = (pending.attempts or 0) + 1
        local backoff = math.min(60, 5 * (2 ^ math.min(pending.attempts - 1, 4)))
        pending.nextAt = tick() + backoff
        dbg("Fruit notification failed for " .. fruit.Name
            .. "; retrying in " .. tostring(math.floor(backoff)) .. "s")
    end)
end

runtime.updateFruitEsp = function()
    local s = runtime.state
    if not runtime.config.FruitESP and not runtime.config.FruitNotifier then
        if next(s.fruitEspVisuals) ~= nil then runtime.destroyFruitEsp() end
        return
    end
    if not runtime.config.FruitESP and next(s.fruitEspVisuals) ~= nil then
        runtime.destroyFruitEsp()
    end

    local fruits = runtime.worldFruits()
    local live = {}
    for _, fruit in ipairs(fruits) do
        live[fruit] = true
        if runtime.config.FruitESP then
            local rarity = runtime.fruitRarity(fruit)
            local visual = s.fruitEspVisuals[fruit]
            local handle = toolPart(fruit)
            if not handle then
                if visual then
                    pcall(function() visual.highlight:Destroy() end)
                    pcall(function() visual.billboard:Destroy() end)
                    s.fruitEspVisuals[fruit] = nil
                end
            elseif not visual then
                local highlight = Instance.new("Highlight")
                highlight.Adornee = handle
                highlight.FillTransparency = 0.25
                highlight.OutlineTransparency = 0.05
                highlight.DepthMode = Enum.HighlightDepthMode.Occluded
                highlight.Parent = handle
                local billboard = Instance.new("BillboardGui")
                billboard.Size = UDim2.fromOffset(170, 34)
                billboard.StudsOffset = Vector3.new(0, 3.2, 0)
                billboard.AlwaysOnTop = true
                billboard.MaxDistance = tonumber(runtime.config.FruitScanRadius) or 5000
                billboard.Parent = handle
                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.Text = fruit.Name .. "\n" .. rarity .. " • Devil Fruit"
                label.TextColor3 = runtime.fruitEspColor(rarity)
                label.TextStrokeTransparency = 0.35
                label.Font = Enum.Font.GothamBold
                label.TextSize = 12
                label.TextWrapped = true
                label.Parent = billboard
                visual = {highlight = highlight, billboard = billboard}
                s.fruitEspVisuals[fruit] = visual
            end
        end
        if runtime.config.FruitNotifier then runtime.notifyFruit(fruit) end
    end
    for fruit, visual in pairs(s.fruitEspVisuals) do
        if not live[fruit] then
            s.fruitEspVisuals[fruit] = nil
            pcall(function() visual.highlight:Destroy() end)
            pcall(function() visual.billboard:Destroy() end)
        end
    end
end

table.insert(runtime.tasks, task.spawn(function()
    while runtime.running and FarmRuntime.current == runtime do
        task.wait(0.5)
        if not runtime.isCurrent() then return end
        local ok, err = pcall(runtime.updateFruitEsp)
        if not runtime.isCurrent() then return end
        if not ok then dbg("Fruit ESP error: " .. tostring(err)) end
    end
end))

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
            -- An equipped current-fruit moveset can also have the official
            -- "Blox Fruit" tooltip. It is not a newly carried physical fruit
            -- and must never be sent to the storage dialogue/remote.
            local originalName = t:GetAttribute("OriginalName")
            if t:IsA("Tool") and isFruit(t)
                and type(originalName) == "string" and originalName ~= "" then
                table.insert(list, t)
            end
        end
    end
    return list
end

-- ItemReplication is the official server-published inventory state. A store
-- request is not successful merely because its remote returned without an
-- error: the same physical ItemId must newly appear in that inventory.
local function fruitInventorySnapshot(tool)
    local itemId = tonumber(tool and tool:GetAttribute("ItemId"))
    if not itemId then return nil end
    local util = ReplicatedStorage:FindFirstChild("Util")
    local module = util and util:FindFirstChild("ItemReplication")
    if not module then return nil end
    local ok, replication = pcall(function() return require(module) end)
    if not ok or type(replication) ~= "table" then return nil end
    local function read(field)
        local reader = replication[field]
        if type(reader) ~= "table" or type(reader.readClient) ~= "function" then
            return nil
        end
        local success, value = pcall(function() return reader.readClient(itemId) end)
        if not success then return nil end
        return value
    end
    return {
        itemId = itemId,
        owned = read("IsOwned"),
        equipped = read("IsEquipped"),
        quantity = read("Quantity"),
    }
end

local function fruitInventoryShowsStore(before, after)
    if not before or not after then return false end
    if after.owned ~= true then return false end
    if type(after.quantity) ~= "number" or after.quantity < 1 then return false end
    if before.owned ~= true then return true end
    return type(before.quantity) == "number"
        and type(after.quantity) == "number"
        and after.quantity > before.quantity
end

local function toolIsInside(tool, container)
    if not tool or not container then return false end
    local ok, inside = pcall(function() return tool:IsDescendantOf(container) end)
    return ok and inside or false
end

local function confirmFruitStored(tool, char, backpack, inventoryBefore)
    local epoch = runtime.characterEpoch
    for _ = 1, 30 do
        local inCharacter = toolIsInside(tool, char)
        local inBackpack = toolIsInside(tool, backpack)
        local inventoryAfter = fruitInventorySnapshot(tool)
        if not inCharacter and not inBackpack
            and fruitInventoryShowsStore(inventoryBefore, inventoryAfter) then
            return true
        end
        task.wait(0.1)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    return false
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
    local hum = getHumanoid()
    local epoch = runtime.characterEpoch
    if not char or not hum then return false end

    -- The official fruit dialogue stores the equipped tool. Equip it first so
    -- the server sees the same tool object that it expects in the request.
    if tool.Parent ~= char then
        local equipped = pcall(function() hum:EquipTool(tool) end)
        if not equipped then return false end
        task.wait(0.1)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
    end
    if tool.Parent ~= char then
        dbg("Could not equip " .. tool.Name .. " for storage")
        return false
    end

    -- The game stores a fruit itself when the remote gets the tool: the server
    -- moves it into the bank at once. This is the path the hubs use; the GUI
    -- of the storage npc is only the fallback for builds without the remote.
    -- Capture the official server-published inventory before the request. A
    -- successful request must produce a new inventory entry for this exact
    -- physical ItemId in addition to moving the exact tool out of both carry
    -- containers.
    local inventoryBefore = fruitInventorySnapshot(tool)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if commF then
        -- The official signature is StoreFruit(OriginalName, Tool). Sending
        -- only the tool, or only the display name, is silently refused and is
        -- the reason the old automatic store never removed a fruit.
        local originalName = tool:GetAttribute("OriginalName") or tool.Name
        local called, reply = pcall(function()
            return commF:InvokeServer("StoreFruit", originalName, tool)
        end)
        if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
            or LocalPlayer.Character ~= char then return false end
        if not called then
            dbg("The store remote failed for " .. tool.Name)
            return false
        end
        if reply == false then
            dbg("The game refused to store " .. tool.Name)
            return false
        end
        if type(reply) == "number" then
            dbg("Fruit storage is full (capacity " .. tostring(reply) .. ")")
            return false
        end
        if confirmFruitStored(tool, char, backpack, inventoryBefore) then
            dbg("Stored " .. tool.Name)
            return true
        end
        dbg("The store remote did not take " .. tool.Name)
        return false
    end
    local used = useFruitMenu(tool.Name, {"store", "deposit", "stash"})
    if not runtime.isCurrent() or runtime.characterEpoch ~= epoch
        or LocalPlayer.Character ~= char then return false end
    if used and confirmFruitStored(tool, char, backpack, inventoryBefore) then
        dbg("Stored " .. tool.Name)
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
    if runtime.state.travelActive then return false end
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

-- The current world is read from the game's own Realm service. The guide
-- contains quest lines from every sea, so aggregating it can report the
-- highest sea even while the character is still in the First Sea.
runtime.detectCurrentSea = function()
    local operationEpoch = runtime.operationEpoch
    local characterEpoch = runtime.characterEpoch
    runtime.state.seaDetectionToken = (runtime.state.seaDetectionToken or 0) + 1
    local detectionToken = runtime.state.seaDetectionToken
    local detected = nil
    local util = ReplicatedStorage:FindFirstChild("Util")
    local realm = util and util:FindFirstChild("Realm")
    if not realm then realm = ReplicatedStorage:FindFirstChild("Realm") end
    if realm then
        pcall(function()
            local realmModule = require(realm)
            local getter = realmModule and realmModule.getCurrentSeaAsync
            if type(getter) == "function" then
                local ok, sea = pcall(getter, realmModule)
                if ok then
                    if sea == "Sea1" then detected = 1
                    elseif sea == "Sea2" then detected = 2
                    elseif sea == "Sea3" then detected = 3
                    end
                end
            end
        end)
    end
    -- A fresh Realm result is authoritative. In particular, nil means that
    -- the official lookup cannot identify the current realm; a stale Map model
    -- must not turn that unknown state into a confirmed sea.
    -- The Realm lookup can yield. Do not let a stale lookup write the sea of
    -- a reset or a new character into the current runtime. A stale or unknown
    -- lookup returns nil; the cached sea is not proof that this lookup saw the
    -- current world.
    if runtime.operationEpoch == operationEpoch
        and runtime.characterEpoch == characterEpoch
        and runtime.state.seaDetectionToken == detectionToken
        and runtime.isCurrent() then
        runtime.state.currentSea = detected
        runtime.state.currentSeaAt = detected and tick() or 0
        return detected
    end
    return nil
end

-- The seas are separate places: the game moves the whole character between
-- them, and the remotes are the ones BananaHub uses. The request is owned by
-- the movement lock, uses the operation epoch, and is only successful after
-- the destination world is visible.
runtime.travelToWorld = function(world, selectionGuard)
    local what = WORLD_TRAVEL[world]
    if not what then return false end
    local function guardValid()
        return type(selectionGuard) ~= "function" or selectionGuard() == true
    end
    if not guardValid() then return false end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    if runtime.state.travelActive then
        dbg("A world travel is already running")
        return false
    end
    local acquired, movementToken = runtime.acquireMovement("travel")
    if not acquired then
        dbg("Another movement operation is already running")
        return false
    end
    local token = (runtime.state.travelToken or 0) + 1
    runtime.state.travelToken = token
    runtime.state.travelActive = true
    runtime.state.travelMovementToken = movementToken
    runtime.state.blockAt = tick()
    runtime.stopTween()
    local function finishTravel()
        if runtime.state.travelToken == token then
            runtime.state.travelActive = false
            runtime.state.travelMovementToken = nil
        end
        runtime.releaseMovement("travel", movementToken)
    end
    local currentSea = runtime.detectCurrentSea()
    if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
        finishTravel()
        return false
    end
    if not currentSea then
        local detected = nil
        for _ = 1, 3 do
            if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
                finishTravel()
                return false
            end
            detected = runtime.detectCurrentSea()
            if detected then break end
            task.wait(0.05)
        end
        currentSea = detected
        if not currentSea then
            finishTravel()
            dbg("The current sea could not be confirmed")
            return false
        end
    end
    if currentSea == world then
        finishTravel()
        dbg("Already in world " .. tostring(world))
        return true
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        finishTravel()
        dbg("CommF_ remote missing")
        return false
    end

    -- The Second and Third Sea captains first verify their own quest line.
    -- Calling the travel remote without that step is refused by the server.
    if world == 2 or world == 3 then
        local progressRemote = world == 2 and "DressrosaQuestProgress" or "ZQuestProgress"
        local progressWorld = world == 2 and "Dressrosa" or "Zou"
        local progressOk, progress = pcall(function()
            return commF:InvokeServer(progressRemote, progressWorld)
        end)
        if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
            finishTravel()
            return false
        end
        if not progressOk or progress ~= 0 then
            finishTravel()
            dbg("The game did not unlock travel to world " .. tostring(world))
            return false
        end
    end

    if not runtime.operationValid(operationEpoch, epoch, char) or not guardValid() then
        finishTravel()
        return false
    end
    local ok, reply = pcall(function() return commF:InvokeServer(what) end)
    -- A world change may replace the character and reset the operation epoch.
    -- The travel token is the ownership of this request; resetFeatureState
    -- invalidates it on disable, respawn or teardown.
    if not runtime.isCurrent() or runtime.state.travelToken ~= token
        or not runtime.state.enabled or not guardValid() then
        finishTravel()
        return false
    end
    if not ok then
        finishTravel()
        dbg("The game did not take the travel to world " .. tostring(world))
        return false
    end
    local message = ""
    if type(reply) == "table" then
        for _, part in ipairs(reply) do message = message .. tostring(part) end
    elseif type(reply) == "string" then
        message = reply
    end
    local lower = message:lower()
    if lower:find("cannot", 1, true) or lower:find("not allowed", 1, true)
        or lower:find("failed", 1, true) or lower:find("error", 1, true) then
        finishTravel()
        dbg("Travel to world " .. tostring(world) .. " was refused: " .. message)
        return false
    end

    dbg("Travelling to world " .. tostring(world))
    local deadline = tick() + 20
    while tick() < deadline do
        runtime.state.blockAt = tick()
        if runtime.state.travelToken ~= token then break end
        if not runtime.isCurrent() or not runtime.state.enabled or not guardValid() then break end
        local sea = runtime.detectCurrentSea()
        if not runtime.operationValid(operationEpoch, epoch, char)
            or runtime.state.travelToken ~= token or not guardValid() then
            break
        end
        if sea == world then
            if not guardValid() then break end
            runtime.refreshQuestData()
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.travelToken ~= token or not guardValid() then
                break
            end
            runtime.state.currentSea = world
            runtime.state.questTryKey = nil
            runtime.state.questTried = {}
            runtime.state.questIndexTry = nil
            runtime.state.currentQuest = nil
            runtime.state.questVerified = false
            runtime.state.questAsked = nil
            if runtime.clearQuestRemoteState then runtime.clearQuestRemoteState() end
            finishTravel()
            dbg("Arrived in world " .. tostring(world))
            return true
        end
        task.wait(0.25)
    end
    finishTravel()
    dbg("Travel to world " .. tostring(world) .. " was not confirmed")
    return false
end

-- ================= FLY TO AN ISLAND =================

-- Some islands cannot be tweened to at all (the sea floor, the islands the
-- game only opens through a door). For those the game itself is asked to move
-- the player. The remotes are the ones BananaHub uses.
-- Fly to a place with the tween of the script: no jump, no portal, just a
-- straight tween across the sea, like the player would glide over.
local function flyTo(position, owner)
    owner = owner or "flight"
    local root = getRoot()
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not root or not position or not char then return false end
    if runtime.state.flying then
        dbg("Already flying to an island")
        return false
    end
    -- Shop and Saber own long movements exclusively. A shop-owned whirlpool
    -- flight is the only flight allowed while a purchase is walking, and a
    -- Saber flight is the only one allowed while the puzzle is active.
    if (runtime.state.shopping or runtime.state.shopInFlight) and owner ~= "shop" then
        dbg("A shopping request owns the movement")
        return false
    end
    if runtime.state.saberActive and owner ~= "saber" then
        dbg("Saber owns the movement")
        return false
    end
    local alreadyOwned = runtime.state.movementOwner == owner
    local acquired, movementToken = runtime.acquireMovement(owner)
    if not acquired then
        dbg("Another movement operation is already running")
        return false
    end

    local flightToken = (runtime.state.flightToken or 0) + 1
    runtime.state.flightToken = flightToken
    runtime.state.flightOwner = owner
    runtime.state.flightMovementToken = movementToken
    runtime.state.flying = true
    runtime.state.blockAt = tick()
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
                if runtime.state.flightToken ~= flightToken then
                    stale = true
                    break
                end
                if not runtime.operationValid(operationEpoch, epoch, char) then
                    stale = true
                    break
                end
            end
            if stale then break end
        end
    end)
    -- Only the flight that still owns the token may clear the shared flag. An
    -- old, timed-out coroutine must never clear a newer flight's state.
    local ownsFlight = runtime.state.flightToken == flightToken
    if ownsFlight then
        runtime.state.flying = false
        runtime.state.flightOwner = nil
        runtime.state.flightMovementToken = nil
        -- A shop or Saber flight is nested inside an operation that already
        -- owns the lock. Only a standalone flight releases that owner here.
        if not alreadyOwned then runtime.releaseMovement(owner, movementToken) end
        if runtime.operationValid(operationEpoch, epoch, char) then
            runtime.setWalking()
        end
        runtime.releaseTweenHold()
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
    {name = "Dark Step",       remote = "BuyBlackLeg",       teacher = "Dark Step Teacher",
        toolNames = {"Black Leg", "BlackLeg"},
        checkOwnedReply = 1,
        level = 100, cost = 150000},
    {name = "Electric",        remote = "BuyElectro",        teacher = "Mad Scientist",
        toolNames = {"Electro"},
        checkOwnedReply = 1, checkRefusalReplies = {3, 4},
        level = 150, item = "Lightning Bolt", cost = 500000},
    {name = "Water Kung Fu",   remote = "BuyFishmanKarate",  teacher = "Water Kung Fu Teacher",
        toolNames = {"Fishman Karate", "Water Kung Fu", "WaterKungFu"},
        checkOwnedReply = 1,
        readinessRemote = "CheckFishmanKarate", readinessArgs = {},
        level = 450, cost = 750000},
    {name = "Dragon Breath",   remote = "BlackbeardReward",  teacher = "Sabi",
        -- Sabi uses a two-argument BlackbeardReward protocol.  The check
        -- reply 1 means that the style is known; 0 is the ordinary
        -- not-owned answer and is still a valid request to buy.
        checkArgs = {"DragonClaw", "1"}, buyArgs = {"DragonClaw", "2"},
        checkOwnedReply = 1,
        toolNames = {"Dragon Breath", "Dragon Claw", "DragonBreath", "DragonClaw"},
        level = 450, fragments = 1500},
    {name = "Superhuman",      remote = "BuySuperhuman",     teacher = "Martial Arts Master",
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 300, cost = 3000000,
        masteries = {
            {style = "Dark Step", level = 300},
            {style = "Electric", level = 300},
            {style = "Water Kung Fu", level = 300},
            {style = "Dragon Breath", level = 300},
        }},
    {name = "Death Step",      remote = "BuyDeathStep",      teacher = "Phoeyu, the Reformed",
        toolNames = {"DeathStep"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 450, fragments = 5000,
        items = {{name = "Library Key", count = 1}},
        needs = "Dark Step", mastery = 400, cost = 2500000},
    {name = "Electric Claw",   remote = "BuyElectricClaw",   teacher = "Previous Hero",
        toolNames = {"ElectricClaw"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        -- The official Previous Hero dialogue sends reply 4 to a short
        -- mansion trial and then calls BuyElectricClaw("Start").
        trialReply = 4, trialArgs = {"Start"},
        level = 1000, fragments = 5000,
        needs = "Electric", mastery = 400, cost = 3000000},
    {name = "Sharkman Karate", remote = "BuySharkmanKarate", teacher = "Sharkman Teacher",
        toolNames = {"SharkmanKarate"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 1000, fragments = 5000,
        items = {{name = "Water Key", count = 1}},
        needs = "Water Kung Fu", mastery = 400, cost = 2500000},
    {name = "Dragon Talon",    remote = "BuyDragonTalon",    teacher = "Uzoth",
        toolNames = {"DragonTalon"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        -- The loaded current place normally refuses this check with reply 3
        -- and does not start a trial. Some servers use the reply-4 handshake
        -- found on the Electric Claw teacher, so trial support is activated
        -- only when that exact reply is received.
        trialReply = 4, trialArgs = {"Start"},
        level = 1500, fragments = 5000,
        items = {{name = "Fire Essence", count = 1}},
        needs = "Dragon Breath", mastery = 400, cost = 3000000},
    {name = "Godhuman",        remote = "BuyGodhuman",       teacher = "Ancient Monk",
        toolNames = {"Godhuman"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 3000, fragments = 5000,
        items = {
            {name = "Dragon Scale", count = 10},
            {name = "Fish Tail", count = 20},
            {name = "Mystic Droplet", count = 10},
            {name = "Magma Ore", count = 20},
        },
        masteries = {
            {style = "Superhuman", level = 400},
            {style = "Death Step", level = 400},
            {style = "Sharkman Karate", level = 400},
            {style = "Electric Claw", level = 400},
            {style = "Dragon Talon", level = 400},
        }, cost = 5000000},
    {name = "Sanguine Art",    remote = "BuySanguineArt",    teacher = "Shafi",
        toolNames = {"SanguineArt"},
        checkOwnedReply = 1, checkRefusalReplies = {3},
        level = 3000, fragments = 5000,
        items = {
            {name = "Leviathan Heart", count = 1},
            {name = "Demonic Wisp", count = 20},
            {name = "Vampire Fang", count = 20},
            {name = "Dark Fragment", count = 2},
        }, cost = 5000000},
    {name = "Advanced Combat", remote = "SetSecretStyle",    teacher = "Secrets Master",
        checkArgs = false, buyArgs = {"Advanced Combat"},
        level = 1100},
}

-- The item a teacher asks for is carried as a tool or kept as a value of the
-- player data: the backpack, the hand and the values are all looked at.
-- The money of the player, wherever this build keeps it: the folder of the
-- player data, a leaderstat or a plain value on the player are all looked at.
-- When none of them is there the number is nil; a paid purchase refuses to
-- start until the real balance can be read.
myBeli = function()
    local player = LocalPlayer
    if not player then return nil end
    local v = nil
    local function read(obj)
        if type(obj) == "number" then return obj end
        return readNumber(obj)
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

-- Fragments are a currency in Data.Fragments. They are not ordinary carried
-- items, so a name search would incorrectly count Fragment Elixir, a Fragment
-- Chest or a Dark Fragment as spendable currency.
runtime.fragmentCount = function()
    local data = LocalPlayer:FindFirstChild("Data")
    local fragments = data and data:FindFirstChild("Fragments")
    local value = readNumber(fragments)
    if type(value) == "number" then return value end
    local attribute = LocalPlayer:GetAttribute("Fragments")
    value = tonumber(attribute)
    if type(value) == "number" then return value end
    return nil
end

runtime.itemCount = function(name)
    local wanted = tostring(name or ""):lower()
    if wanted == "" then return 0 end
    local count = 0
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, folder in ipairs({char, backpack}) do
        if folder then
            for _, item in ipairs(folder:GetChildren()) do
                if item.Name:lower() == wanted then count = count + 1 end
            end
        end
    end
    pcall(function()
        for _, d in ipairs(LocalPlayer:GetDescendants()) do
            local matches = d.Name:lower() == wanted
            if matches then
                if d:IsA("NumberValue") or d:IsA("IntValue") then
                    count = math.max(count, tonumber(d.Value) or 0)
                elseif d:IsA("StringValue") and d.Value ~= nil
                    and d.Value ~= "" and d.Value ~= false then
                    count = math.max(count, 1)
                end
            end
        end
    end)
    return count
end

hasItem = function(name)
    return runtime.itemCount(name) > 0
end

runtime.styleDefinition = function(name)
    local wanted = tostring(name or ""):lower()
    for _, style in ipairs(STYLE_SHOP) do
        if style.name:lower() == wanted then return style end
    end
    return nil
end

runtime.styleNames = function(style)
    local names = {style.name}
    for _, name in ipairs(style.toolNames or {}) do table.insert(names, name) end
    return names
end

runtime.styleTool = function(style)
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, container in ipairs({char, backpack}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    for _, name in ipairs(runtime.styleNames(style)) do
                        if tool.Name:lower() == name:lower() then return tool end
                    end
                end
            end
        end
    end
    return nil
end

runtime.styleModuleOwned = function(style)
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local modules = gui and gui:FindFirstChild("MovesetModules")
    if not modules then return false end
    for _, name in ipairs(runtime.styleNames(style)) do
        if modules:FindFirstChild(name) then return true end
    end
    return false
end

runtime.styleMastery = function(style)
    local tool = runtime.styleTool(style)
    local level = runtime.readToolMastery(tool)
    if type(level) == "number" then return level end
    -- Data.Stars stores unused mastery points, not the current mastery level.
    -- Returning it here could make an unmastered prerequisite look ready.
    return nil
end

runtime.styleItemRequirements = function(style)
    local requirements = {}
    if style.item then
        table.insert(requirements, {
            name = style.item,
            required = tonumber(style.itemCount) or 1,
        })
    end
    for _, item in ipairs(style.items or {}) do
        table.insert(requirements, {
            name = item.name,
            required = tonumber(item.count) or 1,
        })
    end
    return requirements
end

runtime.styleMasteryRequirements = function(style)
    local requirements = {}
    if style.needs then
        table.insert(requirements, {
            style = style.needs,
            required = tonumber(style.mastery) or 0,
        })
    end
    for _, mastery in ipairs(style.masteries or {}) do
        table.insert(requirements, {
            style = mastery.style,
            required = tonumber(mastery.level) or 0,
        })
    end
    return requirements
end

runtime.styleCheck = function(commF, style)
    if not commF or not style or style.checkArgs == false then return nil, false end
    local args = style.checkArgs or {true}
    local ok, reply = pcall(function()
        return commF:InvokeServer(style.remote, table.unpack(args))
    end)
    if not ok then return nil, false end
    return reply, true
end

runtime.styleCheckReply = function(commF, style)
    local reply = runtime.styleCheck(commF, style)
    return reply
end

local function styleReplyIsRefusal(style, reply)
    if type(reply) == "string" or reply == false then return true end
    for _, refusal in ipairs(style and style.checkRefusalReplies or {}) do
        if reply == refusal then return true end
    end
    return false
end

-- A style check has more than two answers. Reply 1 is ownership, a listed
-- numeric reply is a hard refusal, a string is the teacher's refusal text,
-- and a style-specific trial reply means that the normal buy must not be
-- sent until the trial handshake has been handled.
runtime.styleOwnershipState = function(commF, style)
    if not style then return "unknown" end
    if runtime.styleModuleOwned(style) or runtime.styleTool(style) then return "owned" end
    if style.checkArgs == false then return "not-owned" end
    local reply, ok = runtime.styleCheck(commF, style)
    if not ok or reply == nil then return "unknown" end
    local ownedReply = style.checkOwnedReply
    if ownedReply == nil then ownedReply = 1 end
    if reply == ownedReply then return "owned" end
    if style.trialReply ~= nil and reply == style.trialReply then return "trial" end
    if styleReplyIsRefusal(style, reply) then return "refused" end
    return "not-owned"
end

runtime.styleOwned = function(commF, style)
    return runtime.styleOwnershipState(commF, style) == "owned"
end

-- Some teachers expose a separate server-side readiness check. The game
-- treats a false answer as a hard refusal, so the bot must not walk to that
-- teacher or send its buy after a failed check.
runtime.styleReady = function(commF, style)
    if not style or not style.readinessRemote then return true end
    local ok, reply = pcall(function()
        return commF:InvokeServer(style.readinessRemote, table.unpack(style.readinessArgs or {}))
    end)
    if not ok then
        dbg("Auto buy: the readiness check for " .. style.name .. " failed")
        return false
    end
    if reply == true or reply == 1 then return true end
    dbg("Auto buy: " .. style.name .. " is not ready (reply " .. tostring(reply) .. ")")
    return false
end

runtime.styleBuyArgs = function(style)
    if not style then return {} end
    return style.buyArgs or {}
end

local function shopRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_")
end

-- Team selection uses the official SetTeam2 request. Reply 0 is the only
-- success; a non-zero reply means that the server refused the change.
runtime.setTeam = function(team)
    team = tostring(team or "None")
    if team ~= "Pirates" and team ~= "Marines" and team ~= "None" then
        dbg("Unknown team: " .. team)
        return false
    end
    if team == "None" then
        -- Clearing the selection invalidates a SetTeam2 request that is still
        -- in flight. Its late reply must not put the old team back into the
        -- local state.
        runtime.state.teamToken = (runtime.state.teamToken or 0) + 1
        runtime.state.teamInFlight = false
        runtime.state.currentTeam = "None"
        runtime.config.TeamSelection = "None"
        dbg("Team selection cleared")
        return true
    end
    if runtime.state.teamInFlight then
        dbg("A team request is already running")
        return false
    end
    if runtime.state.codeInFlight then
        dbg("A code request is already running")
        return false
    end
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    local token = (runtime.state.teamToken or 0) + 1
    runtime.state.teamToken = token
    runtime.state.teamInFlight = true
    local function finishTeam()
        if runtime.state.teamToken == token then runtime.state.teamInFlight = false end
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    local ok, reply = pcall(function() return commF:InvokeServer("SetTeam2", team) end)
    if not runtime.operationValid(operationEpoch, epoch, char) then
        finishTeam()
        return false
    end
    if runtime.state.teamToken ~= token then return false end
    if not ok then
        finishTeam()
        dbg("The team request failed")
        return false
    end
    -- The official team UI does not use the remote reply as its result. It
    -- waits until the player is actually placed on the requested team, so the
    -- replicated Team/TeamColor is the proof used here as well.
    local deadline = tick() + 6
    while tick() < deadline do
        if not runtime.operationValid(operationEpoch, epoch, char) then
            finishTeam()
            return false
        end
        if runtime.state.teamToken ~= token then return false end
        local actual = LocalPlayer.Team
        local actualName = actual and actual.Name or ""
        local matches = actualName:lower() == team:lower()
            or (team == "Pirates" and LocalPlayer.TeamColor == Enum.TeamColor.Pirate)
            or (team == "Marines" and LocalPlayer.TeamColor == Enum.TeamColor.Marine)
        if matches then
            runtime.state.currentTeam = team
            runtime.config.TeamSelection = team
            finishTeam()
            dbg("Team changed to " .. team)
            return true
        end
        task.wait(0.1)
    end
    local message = ""
    if type(reply) == "table" then
        for _, part in ipairs(reply) do message = message .. tostring(part) end
    elseif reply ~= nil then
        message = tostring(reply)
    end
    finishTeam()
    dbg("The game did not change the team to " .. team
        .. (message ~= "" and (" (" .. message .. ")") or ""))
    return false
end

-- Code redemption uses the official Redeem remote. The game answers with the
-- exact string "SUCCESS!" or a human-readable error.
runtime.redeemCode = function(code)
    code = tostring(code or ""):match("^%s*(.-)%s*$") or ""
    if code == "" then
        dbg("No redemption code was entered")
        return false
    end
    if #code > 100 then
        dbg("The redemption code is too long")
        return false
    end
    if runtime.state.codeInFlight then
        dbg("A code request is already running")
        return false
    end
    if runtime.state.teamInFlight then
        dbg("A team request is already running")
        return false
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local redeem = remotes and remotes:FindFirstChild("Redeem")
    if not redeem then
        dbg("Redeem remote missing")
        return false
    end
    local token = (runtime.state.codeToken or 0) + 1
    runtime.state.codeToken = token
    runtime.state.codeInFlight = true
    local function finishCode()
        if runtime.state.codeToken == token then runtime.state.codeInFlight = false end
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    local ok, reply = pcall(function() return redeem:InvokeServer(code) end)
    if not runtime.operationValid(operationEpoch, epoch, char) then
        finishCode()
        return false
    end
    if runtime.state.codeToken ~= token then return false end
    finishCode()
    if not ok then
        dbg("The redemption request failed")
        return false
    end
    if reply == "SUCCESS!" then
        dbg("Code redeemed")
        return true
    end
    dbg("Code was not redeemed: " .. tostring(reply or "unknown reply"))
    return false
end

-- Reserve a purchase before its first yielding server check. Without this
-- reservation two requests can both pass the idle guard, yield in preflight,
-- and then send their purchases in the opposite order.
runtime.beginShopRequest = function()
    local s = runtime.state
    if s.shopping or s.shopInFlight then return nil end
    local requestToken = (s.shopToken or 0) + 1
    s.shopToken = requestToken
    s.shopping = true
    s.shopInFlight = false
    return requestToken
end

-- Clear only the purchase that owns this token. An invalidated old request
-- must not clear a newer purchase that has already replaced it.
runtime.finishShopState = function(requestToken)
    if requestToken == nil or runtime.state.shopToken == requestToken then
        runtime.state.shopping = false
        runtime.state.shopInFlight = false
        local movementToken = runtime.state.shopMovementToken
        runtime.state.shopMovementToken = nil
        runtime.releaseMovement("shop", movementToken)
    end
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
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    local pos = runtime.whirlpoolPos()
    if not pos then
        dbg("The whirlpool of the sea was not found")
        return false
    end
    dbg("Flying into the whirlpool of the sea")
    flyTo(pos, "shop")
    if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
            if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            return true
        end
        runtime.travelTo(CFrame.new(pos), true)
        task.wait(0.3)
        if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
    if runtime.state.saberActive or runtime.state.movementOwner == "saber" then
        dbg("Saber owns the movement; the style buy was not started")
        return false
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    local requestToken = runtime.beginShopRequest()
    if not requestToken then
        dbg("A buy is already running")
        return false
    end
    local function requestCurrent()
        return runtime.state.shopToken == requestToken
            and runtime.operationValid(operationEpoch, epoch, char)
    end

    -- Ownership is checked first. A style that is already known must not be
    -- refused because the fragments, items or money used to buy it are gone.
    local ownership = runtime.styleOwnershipState(commF, style)
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end
    if ownership == "owned" then
        runtime.state.shopUnknown[style.remote] = nil
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " is already owned")
        return true
    end
    if ownership == "unknown" then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " could not confirm ownership; no buy was sent")
        return nil
    end
    if ownership == "refused" then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " was refused by the ownership check")
        return false
    end
    local ready = runtime.styleReady(commF, style)
    -- The readiness request can yield.  A reset or respawn during it must
    -- stop this purchase before it acquires a new movement owner.
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end
    if not ready then
        runtime.finishShopState(requestToken)
        return false
    end

    -- What the style needs is checked before the walk: a teacher that will
    -- refuse is a wasted trip, and the player has to see why nothing happened.
    if style.level and getMyLevel() < style.level then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " needs level " .. style.level
            .. ", we are " .. getMyLevel())
        return false
    end
    for _, requirement in ipairs(runtime.styleItemRequirements(style)) do
        local needed = requirement.required
        local have = runtime.itemCount(requirement.name)
        if have < needed then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. needed .. " "
                .. requirement.name .. ", we have " .. have)
            return false
        end
    end
    if style.fragments then
        local needed = tonumber(style.fragments) or 0
        local available = tonumber(runtime.fragmentCount())
        if not available then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. needed
                .. " fragments, but the fragment balance is not available")
            return false
        end
        if available < needed then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. needed
                .. " fragments, we have " .. math.floor(available))
            return false
        end
    end
    for _, requirement in ipairs(runtime.styleMasteryRequirements(style)) do
        local needStyle = runtime.styleDefinition(requirement.style)
        if not needStyle then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " has an unknown prerequisite")
            return false
        end
        local ownership = runtime.styleOwnershipState(commF, needStyle)
        if not requestCurrent() then
            runtime.finishShopState(requestToken)
            return false
        end
        if ownership ~= "owned" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. requirement.style .. " first")
            return false
        end
        local mastery = runtime.styleMastery(needStyle)
        local neededMastery = requirement.required
        if type(mastery) ~= "number" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. requirement.style
                .. " mastery " .. tostring(neededMastery) .. ", but its level is not available")
            return false
        end
        if mastery < neededMastery then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " needs " .. requirement.style
                .. " mastery " .. tostring(neededMastery) .. ", we have " .. mastery)
            return false
        end
    end
    -- Money first: the walk to the teacher is only worth it when the real
    -- balance can be read and is enough to pay.
    local beli = myBeli()
    if style.cost then
        if type(beli) ~= "number" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " costs " .. style.cost
                .. " Beli, but the Beli balance is not available")
            return false
        end
        if beli < style.cost then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " costs " .. style.cost
                .. " Beli, we have " .. math.floor(tonumber(beli) or 0))
            return false
        end
    end
    -- An unknown reply is not a refusal, but it is also not permission to send
    -- the same purchase over and over. It gets a short cooldown.
    local unknownAt = runtime.state.shopUnknown[style.remote]
    if unknownAt and tick() - unknownAt < 60 then
        runtime.finishShopState(requestToken)
        dbg("Auto buy: " .. style.name .. " has an unknown result; waiting before retrying")
        return nil
    end
    if ownership == "trial" then
        local trialAt = runtime.state.styleTrialAt[style.remote]
        if trialAt and tick() - trialAt < 45 then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. style.name .. " trial is already active; waiting before retrying")
            return nil
        end
    end
    local acquired, shopMovementToken = runtime.acquireMovement("shop")
    if not acquired then
        runtime.finishShopState(requestToken)
        dbg("Another movement operation is already running")
        return false
    end
    runtime.state.shopMovementToken = shopMovementToken
    runtime.state.shopping = true
    if WHIRLPOOL_STYLES[style.name] then
        runtime.takeWhirlpool()
        if not requestCurrent() then
            runtime.finishShopState(requestToken)
            return false
        end
    end
    local npc = findTeacher(style.teacher)
    local near = false
    if npc then
        local deadline = tick() + 25
        pcall(function()
            while tick() < deadline do
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
            return true
        end)
    end
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end

    -- A reply-4 check is a trial invitation, not permission for the ordinary
    -- buy. Start only the style-specific trial and wait for the normal
    -- ownership check to confirm that the server actually granted the style.
    if ownership == "trial" then
        runtime.state.shopInFlight = true
        runtime.state.styleTrialAt[style.remote] = tick()
        local trialOk, trialReply = pcall(function()
            return commF:InvokeServer(style.remote, table.unpack(style.trialArgs or {"Start"}))
        end)
        if not runtime.operationValid(operationEpoch, epoch, char)
            or runtime.state.shopToken ~= requestToken then
            runtime.finishShopState(requestToken)
            return false
        end
        local trialBought = nil
        if trialOk then
            local confirmDeadline = tick() + 2
            repeat
                if not runtime.operationValid(operationEpoch, epoch, char)
                    or runtime.state.shopToken ~= requestToken then
                    runtime.finishShopState(requestToken)
                    return false
                end
                local trialOwnership = runtime.styleOwnershipState(commF, style)
                if not runtime.operationValid(operationEpoch, epoch, char)
                    or runtime.state.shopToken ~= requestToken then
                    runtime.finishShopState(requestToken)
                    return false
                end
                if trialOwnership == "owned" then
                    trialBought = true
                    break
                end
                task.wait(0.1)
            until tick() >= confirmDeadline
        else
            dbg("The trial request for " .. style.name .. " failed")
        end
        runtime.finishShopState(requestToken)
        dbg("Trial for " .. style.name .. " was started"
            .. (trialReply ~= nil and (" (reply " .. tostring(trialReply) .. ")") or ""))
        return trialBought
    end

    -- Send the request once. Repeating it can buy the same style more than
    -- once when the server has no reply yet. The live buy RPCs answer 1 for a
    -- successful purchase and 2 when the style is already known.
    runtime.state.shopInFlight = true
    local buyArgs = runtime.styleBuyArgs(style)
    local ok, reply = pcall(function()
        return commF:InvokeServer(style.remote, table.unpack(buyArgs))
    end)
    if not runtime.operationValid(operationEpoch, epoch, char) then
        runtime.finishShopState(requestToken)
        return false
    end
    if runtime.state.shopToken ~= requestToken then
        runtime.finishShopState(requestToken)
        return false
    end

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

    -- A success reply is followed by the official ownership check when the
    -- style has one. A delayed or misleading reply therefore cannot leave the
    -- bot convinced that it owns a style that the server still rejects.
    if bought == true and style.checkArgs ~= false then
        local confirmDeadline = tick() + 2
        repeat
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            local confirmedOwnership = runtime.styleOwnershipState(commF, style)
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            if confirmedOwnership == "owned" then
                bought = true
                break
            end
            task.wait(0.1)
        until tick() >= confirmDeadline
        if bought ~= true then
            local finalOwnership = runtime.styleOwnershipState(commF, style)
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            if finalOwnership ~= "owned" then
                bought = nil
                runtime.state.shopUnknown[style.remote] = tick()
                dbg("The buy reply for " .. style.name .. " was not confirmed as owned")
            end
        end
    end
    runtime.finishShopState(requestToken)
    dbg("Buy " .. style.name .. " from " .. (npc and "the teacher" or "far away")
        .. (npc and (near and " (stood at it)" or " (could not reach it)") or " (no teacher was seen)")
        .. (bought == true and " (the game took it)"
            or (bought == false and " (the game refused it)" or " (result unknown)")))
    return bought
end

runtime.abilityShop = {
    Buso = {remote = "BuyHaki", argument = "Buso", label = "Buso Haki",
        official = "Buso", identity = {kind = "marker", name = "HasBuso"},
        cost = 25000, level = 50, teacher = "Ability Teacher"},
    Geppo = {remote = "BuyHaki", argument = "Geppo", label = "Geppo",
        official = "Geppo", identity = {kind = "tag", name = "Geppo"},
        tags = {"Geppo"},
        cost = 10000, level = 50, teacher = "Ability Teacher"},
    Soru = {remote = "BuyHaki", argument = "Soru", label = "Soru",
        official = "Soru", identity = {kind = "tag", name = "Soru"},
        tags = {"Soru"},
        cost = 100000, level = 300, teacher = "Ability Teacher"},
    Observation = {remote = "KenTalk", argument = "Buy", label = "Observation Haki",
        official = "Instinct", identity = {kind = "tag", name = "Ken"},
        tags = {"Ken", "KenUpgrade"},
        checkRemote = "KenTalk", checkArgument = "Start", ownedReply = 0, readyReply = 1,
        cost = 750000, level = 300, teacher = "Instinct Teacher", success = 0},
}

runtime.abilityDefinition = function(name)
    local wanted = tostring(name or ""):lower()
    if wanted == "" then return nil end
    local ability = runtime.abilityShop[name]
    if ability then return ability end
    for key, entry in pairs(runtime.abilityShop) do
        if key:lower() == wanted then return entry end
        if entry.official and entry.official:lower() == wanted then return entry end
        for _, tag in ipairs(entry.tags or {}) do
            if tag:lower() == wanted then return entry end
        end
    end
    return nil
end

runtime.hasAbility = function(name)
    local ability = runtime.abilityDefinition(name)
    if not ability then return false end
    local char = LocalPlayer.Character
    if not char then return false end

    -- These are the ownership signals used by the current character scripts.
    -- HasBuso is a marker whose mere existence is the proof; the other
    -- abilities are exact CollectionService tags on the character.
    local identity = ability.identity
    if identity and identity.kind == "marker" then
        if char:FindFirstChild(identity.name) ~= nil then return true end
    elseif identity and identity.kind == "tag" then
        local collection = game:GetService("CollectionService")
        local ok, tagged = pcall(function()
            return collection:HasTag(char, identity.name)
        end)
        if ok and tagged == true then return true end
    end

    for _, tag in ipairs(ability.tags or {}) do
        local collection = game:GetService("CollectionService")
        local ok, tagged = pcall(function()
            return collection:HasTag(char, tag)
        end)
        if ok and tagged == true then return true end
    end
    return false
end

runtime.buyAbility = function(name)
    local ability = runtime.abilityDefinition(name)
    if not ability then
        dbg("Unknown ability: " .. tostring(name))
        return false
    end
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    if runtime.state.saberActive or runtime.state.movementOwner == "saber" then
        dbg("Saber owns the quest; the ability buy was not started")
        return false
    end
    local char = LocalPlayer.Character
    local epoch = runtime.characterEpoch
    local operationEpoch = runtime.operationEpoch
    if not char then return false end
    if ability.level and getMyLevel() < ability.level then
        dbg("Auto buy: " .. ability.label .. " needs level " .. ability.level
            .. ", we are " .. getMyLevel())
        return false
    end
    if runtime.hasAbility(ability.official or name) then
        dbg(ability.label .. " is already owned")
        return true
    end
    local requestToken = runtime.beginShopRequest()
    if not requestToken then
        dbg("A buy is already running")
        return false
    end
    local function requestCurrent()
        return runtime.state.shopToken == requestToken
            and runtime.operationValid(operationEpoch, epoch, char)
    end

    -- KenTalk("Start") is the official Instinct eligibility check. Reply 0
    -- means the ability is already known, reply 1 means the server accepts the
    -- purchase, and every other reply is a level or prerequisite refusal.
    if ability.checkRemote then
        local checkOk, checkReply = pcall(function()
            return commF:InvokeServer(ability.checkRemote, ability.checkArgument)
        end)
        if not requestCurrent() then
            runtime.finishShopState(requestToken)
            return false
        end
        if not checkOk then
            runtime.finishShopState(requestToken)
            dbg("The " .. ability.label .. " eligibility check failed")
            return false
        end
        if checkReply == ability.ownedReply then
            runtime.finishShopState(requestToken)
            dbg(ability.label .. " is already owned")
            return true
        end
        if checkReply ~= ability.readyReply then
            runtime.finishShopState(requestToken)
            dbg("The game did not unlock " .. ability.label
                .. " (reply " .. tostring(checkReply) .. ")")
            return false
        end
    end

    local beli = myBeli()
    if ability.cost then
        if type(beli) ~= "number" then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. ability.label .. " costs " .. ability.cost
                .. " Beli, but the Beli balance is not available")
            return false
        end
        if beli < ability.cost then
            runtime.finishShopState(requestToken)
            dbg("Auto buy: " .. ability.label .. " costs " .. ability.cost
                .. " Beli, we have " .. math.floor(tonumber(beli) or 0))
            return false
        end
    end
    local acquired, movementToken = runtime.acquireMovement("shop")
    if not acquired then
        runtime.finishShopState(requestToken)
        dbg("Another movement operation is already running")
        return false
    end
    -- Keep the exact owner token with the request.  Without it a reset cannot
    -- release an ability purchase that is walking to its teacher, and a late
    -- reply could otherwise release a newer shop owner.
    runtime.state.shopMovementToken = movementToken
    runtime.state.shopping = true
    runtime.state.shopInFlight = false

    -- The teacher must see the player. A missing teacher is reported, but the
    -- official request is still attempted once so the server remains the final
    -- authority when its NPC list is streamed later.
    local teacher = findTeacher(ability.teacher)
    if teacher then
        local deadline = tick() + 20
        while tick() < deadline do
            if not requestCurrent() then
                runtime.finishShopState(requestToken)
                return false
            end
            local root, anchor = getRoot(), anchorOf(teacher)
            if not root or not anchor then break end
            runtime.state.blockAt = tick()
            if (root.Position - anchor.Position).Magnitude <= 8 then break end
            runtime.travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)), true)
            task.wait(0.2)
        end
    else
        dbg("The teacher of " .. ability.label .. " was not found")
    end
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end

    runtime.state.shopInFlight = true
    local ok, reply = pcall(function()
        return commF:InvokeServer(ability.remote, ability.argument)
    end)
    if not requestCurrent() then
        runtime.finishShopState(requestToken)
        return false
    end
    if not ok then
        runtime.finishShopState(requestToken)
        dbg("The buy request for " .. ability.label .. " failed")
        return false
    end
    local success = ability.success
    if success == nil then success = 1 end
    local bought = false
    if reply == success or (success ~= 0 and (reply == true)) then
        bought = true
        dbg("The game took the buy of " .. ability.label)
    elseif success == 1 and reply == 2 then
        bought = true
        dbg(ability.label .. " was already owned")
    elseif reply == nil then
        bought = nil
        dbg("The game did not answer the buy of " .. ability.label)
    else
        dbg("The game refused the buy of " .. ability.label
            .. " (reply " .. tostring(reply) .. ")")
    end

    if bought == true then
        local confirmDeadline = tick() + 3
        repeat
            if not runtime.operationValid(operationEpoch, epoch, char)
                or runtime.state.shopToken ~= requestToken then
                runtime.finishShopState(requestToken)
                return false
            end
            if runtime.hasAbility(ability.official or name) then
                bought = true
                break
            end
            task.wait(0.1)
        until tick() >= confirmDeadline
        if not runtime.hasAbility(ability.official or name) then
            bought = nil
            dbg("The buy of " .. ability.label .. " was not confirmed in the client")
        end
    end
    runtime.finishShopState(requestToken)
    return bought
end

-- ================= MAIN LOOP =================
-- The mobs that were frozen for the farm are let go again with this.

local function releaseBringMobs()
    -- letGoMob removes entries while it works. Take a stable list first so no
    -- saved rig can be skipped by changing the weak tables during pairs().
    local pending, seen = {}, {}
    for mob, part in pairs(runtime.state.bringHeld) do
        pending[#pending + 1] = {mob = mob, part = part}
        seen[mob] = true
    end
    -- A mob can have saved state before it ever enters bringHeld (for example
    -- when ownership changes during the first mutation). Restore those saved
    -- rigs as well instead of dropping the table and losing their state.
    for mob, saved in pairs(runtime.state.bringSaved) do
        if not seen[mob] then
            pending[#pending + 1] = {mob = mob, part = saved and saved.part}
            seen[mob] = true
        end
    end
    for _, entry in ipairs(pending) do
        runtime.letGoMob(entry.mob, entry.part)
    end
    runtime.state.bringHeld = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlot = setmetatable({}, {__mode = "k"})
    runtime.state.bringSlotCount = 0
    -- the point of the last pack dies with it, so the next fight is gathered
    -- where the fight actually is
    runtime.state.bringPoint, runtime.state.bringTarget, runtime.state.bringCentre = nil, nil, nil
    runtime.state.bringCarryOffsetY = nil
    runtime.state.bringPathBlocked = false
    runtime.state.bringPathCheck = nil
    runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
    -- A server-owned rig can keep its restoration snapshot until ownership
    -- returns. Dropping that snapshot would capture the frozen values as the
    -- new originals on a later hold.
    runtime.state.bringSnapped = setmetatable({}, {__mode = "k"})
    runtime.state.bringCarryingTarget = setmetatable({}, {__mode = "k"})
    runtime.state.bringMover = setmetatable({}, {__mode = "k"})
    runtime.state.bringAt = 0
    -- Releasing the pack also ends the player's stationary hold. This keeps a
    -- disabled bot, a respawn, or an inactivity timeout from leaving a
    -- zero-velocity BodyVelocity attached to the character.
    if runtime.releaseTweenHold then runtime.releaseTweenHold() end
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
    runtime.state.bringCarryOffsetY = nil
    runtime.state.bringPathBlocked = false
    runtime.state.bringPathCheck = nil
    runtime.state.bringPathCache = setmetatable({}, {__mode = "k"})
    runtime.state.bringHeld = setmetatable({}, {__mode = "k"})
    -- Keep pending restoration snapshots for rigs that the server currently
    -- owns; letGoMob removes each snapshot once it has safely restored it.
    runtime.state.bringSnapped = setmetatable({}, {__mode = "k"})
    runtime.state.bringCarryingTarget = setmetatable({}, {__mode = "k"})
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
    table.insert(runtime.cleanupFns, function()
    runtime.stopTween()
    if tweenProxy and tweenProxy.Parent then
        pcall(function() tweenProxy:Destroy() end)
    end
    tweenProxy = nil
end)
    table.insert(runtime.cleanupFns, function() runtime.restoreNoclip() end)
    table.insert(runtime.cleanupFns, function() runtime.releaseBringMobs() end)
    table.insert(runtime.cleanupFns, function() runtime.exportPendingBringSnapshots() end)
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

    if not runtime.state.travelActive
        and (not runtime.state.currentSeaAt or now - runtime.state.currentSeaAt > 2) then
        runtime.detectCurrentSea()
    end

    -- A world change owns the character until the Realm service confirms the
    -- destination. Ordinary farming must not start another tween in parallel.
    if runtime.state.travelActive then
        if not runtime.state.blockAt then runtime.state.blockAt = now end
        if now - runtime.state.blockAt > 25 then
            local travelMovementToken = runtime.state.travelMovementToken
            runtime.state.travelToken = (runtime.state.travelToken or 0) + 1
            runtime.state.travelActive = false
            runtime.state.travelMovementToken = nil
            runtime.releaseMovement("travel", travelMovementToken)
            runtime.state.blockAt = nil
            runtime.stopTween()
            dbg("A stuck world travel got cleared")
        else
            runtime.state.status = "Travelling between seas..."
            return
        end
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

    runtime.updateSafePoint(root, now)
    if runtime.recoverFall(root, now) then return end

    -- A shop buy or a flight owns the movement while it runs. This watchdog is
    -- before every Saber early return: a stale purchase must not be able to
    -- hide behind a puzzle step until the much longer Saber timeout.
    if runtime.state.shopping or runtime.state.shopInFlight or runtime.state.flying then
        if not runtime.state.blockAt then runtime.state.blockAt = now end
        local timedOut = now - runtime.state.blockAt > 25
        if timedOut and (runtime.state.shopping or runtime.state.shopInFlight
            or runtime.state.flying) then
            local flightOwner = runtime.state.flightOwner
            local flightOwnerToken = runtime.state.flightMovementToken
            if runtime.state.shopping or runtime.state.shopInFlight then
                runtime.resetShopState()
            end
            if runtime.state.flying then
                -- Invalidate the old flight coroutine before another one can
                -- start. The old task then cannot clear the new flight's flag.
                runtime.state.flightToken = (runtime.state.flightToken or 0) + 1
                runtime.state.flightOwner = nil
                runtime.state.flightMovementToken = nil
                runtime.state.flying = false
                if flightOwner and runtime.releaseMovement then
                    runtime.releaseMovement(flightOwner, flightOwnerToken)
                end
                if flightOwner == "shop" then runtime.resetShopState() end
            end
            runtime.state.blockAt = nil
            runtime.stopTween()
            dbg("A stuck movement operation got cleared, farming again")
        end
        if runtime.state.shopping or runtime.state.shopInFlight or runtime.state.flying then return end
    else
        runtime.state.blockAt = nil
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
                if candidate.Name:lower() == runtime.state.saberTarget:lower() then
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

    if not runtime.state.lastPos or (root.Position - runtime.state.lastPos).Magnitude > 1 then
        runtime.state.lastPos = root.Position
        runtime.state.movedAt = now
    end
    -- The safe point is maintained by the raycast above. Replacing it with a
    -- stationary position would remember a point in mid-air after a tween.

    if runtime.handleChest(root) then
        return
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
        if runtime.state.saberActive and runtime.state.saberTarget then
            -- Auto Saber owns one exact boss in this mode. Ordinary farming
            -- stays off, but the current Saber target is still fought with
            -- the normal movement and attack systems.
            if next(runtime.state.bringHeld) ~= nil
                or next(runtime.state.bringSaved) ~= nil then
                releaseBringMobs()
            end
            restoreHitbox()
            runtime.state.farming = runtime.runSaberCombat(root)
            return
        end
        runtime.state.farming = false
        runtime.state.status = "Idle"
        -- nothing is being farmed: the pack of the last mob is let go and the
        -- hitbox that was made big for the swing is put back
        restoreHitbox()
        if next(runtime.state.bringHeld) ~= nil
            or next(runtime.state.bringSaved) ~= nil then
            releaseBringMobs()
        end
        runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
        return
    end
    runtime.state.farming = true

    local quest = runtime.config.AutoQuest and questFor(getMyLevel()) or nil
    local mob = quest and quest.mob or nil
    local bossWindow = runtime.config.BossLevelWindow or 25
    local explicitBoss = runtime.config.BossTarget and runtime.config.BossTarget ~= "Auto"
    local explicitMobChoice, explicitMobName, nearestMob =
        runtime.resolveSelectedMob(runtime.config.SelectedMob)
    -- "Nearest" is a mode, not an exact mob selection. It must not make an
    -- automatic boss quest bypass the boss level window.
    local explicitMob = explicitMobChoice and not nearestMob
    local explicitPole = runtime.config.PoleMastery and runtime.config.PoleTarget
        and runtime.config.PoleTarget ~= "Auto"
    local exactSelection = explicitBoss or explicitMob or explicitPole
    local function bossAllowedFor(name)
        if not bossNameIs(name) then return false end
        -- An explicit boss or selected mob is the user's decision. Automatic
        -- boss farming still keeps its level window.
        if exactSelection then return true end
        if not runtime.config.BossFarm then return false end
        local level = bossLevelOf and bossLevelOf(name)
        return level == nil or math.abs(level - getMyLevel()) <= bossWindow
    end
    if explicitBoss then
        mob = runtime.config.BossTarget
    elseif explicitMobChoice then
        mob = explicitMobName
    elseif explicitPole then
        mob = runtime.config.PoleTarget
    elseif info and info.target then
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
            target = pickBoss(root, runtime.config.BossRange or 3000, mob,
                exactSelection)
            -- The boss is dead or out of range: automatic quests may farm
            -- normal mobs around the spawn. An explicit target stays exact.
            if not target and not exactSelection then
                target = pickNormal(root)
            end
        else
            -- Boss farm off, or the boss is too far from the player's level.
            -- Do not let the normal quest picker walk into it anyway.
            mob = nil
            target = pickNormal(root)
        end
    else
        target = nearestMob and pickNormal(root) or getTarget(mob, exactSelection)
    end
    if runtime.state.saberTarget then
        -- a running quest knows which mob it needs
        for _, m in ipairs(collectEnemies(tick())) do
            if m.Name:lower() == runtime.state.saberTarget:lower() then
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
        if next(runtime.state.bringHeld) ~= nil
            or next(runtime.state.bringSaved) ~= nil then
            releaseBringMobs()
        end
        runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
        local sp = findSpawn(mob, exactSelection)
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
            if runtime.state.saberTarget and target.Name:lower() == runtime.state.saberTarget:lower() then
                runtime.state.saberKillHealth = th.Health
            end
        elseif th.Health < (runtime.state.targetHealth or th.Health) then
            runtime.state.targetHealth, runtime.state.targetAt = th.Health, now
            runtime.state.targetDist, runtime.state.travelAt = dist, now
            if runtime.state.saberTarget and target.Name:lower() == runtime.state.saberTarget:lower() then
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
    local isSaberTarget = runtime.state.saberTarget
        and target.Name:lower() == runtime.state.saberTarget:lower()
    if runtime.config.BringMob and not isSaberTarget then
        -- Bring Mob checks the straight route before its own range gate. Call
        -- it for an out-of-range target as well, so a wet route is known
        -- before the player is asked to approach it.
        local hadPack = next(runtime.state.bringHeld) ~= nil
            or next(runtime.state.bringSaved) ~= nil
        bringMob(target, root)
        if hadPack and next(runtime.state.bringHeld) == nil
            and next(runtime.state.bringSaved) == nil then
            restoreHitbox()
        end
    elseif next(runtime.state.bringHeld) ~= nil
        or next(runtime.state.bringSaved) ~= nil then
        -- The exact Saber boss owns the ordinary farm during its kill step.
        -- It is never frozen or dragged by Bring Mob.
        releaseBringMobs()
        restoreHitbox()
    end

    local swingTarget = target
    if runtime.config.AutoAttack then
        local close = mobInReach(root, reach)
        -- A boss is not given up for a normal mob that happens to stand near:
        -- the boss is what the boss farm went there for.
        local onBoss = bossKeyOf(target)
        local onSelected = explicitBoss or explicitMob or explicitPole
        local onSaber = runtime.state.saberTarget
            and target.Name:lower() == runtime.state.saberTarget:lower()
        -- A swipe at a mob that stands in the way is fine, but the window has
        -- to close and then stay closed for a while. If it is armed again on
        -- the next tick the bot farms the mob beside it for ever and never
        -- walks to the mob of the quest at all.
        if close and close ~= target and flat > reach and not onBoss and not onSaber
            and not onSelected and (runtime.state.autoBurstCd or 0) <= now then
            runtime.state.autoBurst = now + 2
            runtime.state.autoBurstCd = now + 8
        end
        if (runtime.state.autoBurst or 0) > now and close and not onSaber
            and not onSelected then
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
    -- ground while the mob comes over; it never follows the mob's height.
    local heldTarget = runtime.state.bringCarryingTarget[target] == true
    if heldTarget then
        -- A carried target is already moving under the player. Following its
        -- current vertical position made the player follow a falling rig into
        -- the water, while the old held-target patrol made the character jump
        -- around in four slots. Hold the current ground position instead.
        hoverPos = root.Position
    end

    -- Safe tween farming travels between wide slots around the target. It no
    -- longer writes the root CFrame every frame, which made the character
    -- spin in place. A carried target is different: the pack is already moving
    -- under the player, so any slot or target-height follow makes the two
    -- systems pull against each other. Cancel the approach once and hold.
    if heldTarget then
        -- A completed Tween is no longer Playing, but its Humanoid can still
        -- be left in Physics/PlatformStand. Cancel any remaining Tween object
        -- and restore walking in both the active and completed cases.
        -- Keep the zero-velocity body hold while the target is actually held.
        -- Releasing it here lets gravity pull the player down from an
        -- elevated approach, which can end in the water even though the bot
        -- issued no further movement command.
        ensureTweenHold(root)
        if activeTween then
            runtime.stopTween()
        else
            runtime.setWalking()
        end
    elseif runtime.config.BringMob then
        -- Bring Mob owns the player's position while the pack is being
        -- gathered. The old safe-slot orbit kept dashing the character around
        -- the target whenever network ownership briefly changed. Approach the
        -- stable hover point once, then stand still while the pack arrives.
        local bringRange = tonumber(runtime.config.BringMobRange) or 60
        if runtime.state.bringPathBlocked then
            -- The straight path to this mob crosses water. Keep the player on
            -- its current dry ground instead of sending it over the same gap.
            if activeTween then
                runtime.stopTween()
            else
                runtime.setWalking()
            end
        elseif bringRange > 0 and flat <= bringRange then
            local verticalGap = math.abs(root.Position.Y - hoverPos.Y)
            if flat > reach + 4 or verticalGap > 12 then
                runtime.tweenTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))
            else
                if activeTween then
                    runtime.stopTween()
                else
                    runtime.setWalking()
                end
            end
        elseif runtime.config.Dodge and runtime.config.RemoteAttack then
            local centre = er.Position
            runtime.tweenFarmSlot(target, centre, root, false, hoverPos.Y)
        else
            runtime.travelTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))
        end
    elseif runtime.config.Dodge and runtime.config.RemoteAttack then
        local centre = er.Position
        runtime.tweenFarmSlot(target, centre, root, false, hoverPos.Y)
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
        -- This sweep also runs while the bot is stopped. A rig that was
        -- server-owned can get ownership back after the stop and must still
        -- receive the restoration that was saved before it was released.
        runtime.restorePendingBringMobs()
        if runtime.state.enabled then
            runtime.state.wasStopped = false
            local ok, err = pcall(step)
            if not runtime.isCurrent() then return end
            if not ok then dbg("Loop error: " .. tostring(err)) end
            -- The Bring hold keeps the player at the position where the pack
            -- was caught. Once the actual hold is gone, release the body hold
            -- so ordinary walking and the next operation are not affected.
            if runtime.releaseTweenHold then runtime.releaseTweenHold() end
            -- A pause of the farm (a turn-in, a fruit, a shop) must not leave
            -- the last pack frozen: if the farm has not carried it for a few
            -- seconds, the mobs are let go and the enlarged hitbox is put back.
            if (next(runtime.state.bringHeld) ~= nil
                or next(runtime.state.bringSaved) ~= nil)
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
                if next(runtime.state.bringHeld) ~= nil
                    or next(runtime.state.bringSaved) ~= nil then
                    releaseBringMobs()
                end
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

-- Quest objects can be nested below a streamed map folder. The official
-- QuestPro script uses FindFirstChild(name, true) for the Cup, so the source
-- uses the same lookup instead of guessing a fixed parent path.
local function saberDescendant(root, name)
    if not root then return nil end
    local found = root:FindFirstChild(name, true)
    return found
end

-- The Frozen Village and Desert markers are kept by the world even while
-- their decorative map objects are streamed. They are the route anchors for
-- the Saber Cup; hard-coded coordinates of an old map revision are not used.
local function saberLocations(name)
    local wanted = name:lower()
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    local list = {}
    if not locations then return list end
    for _, part in ipairs(locations:GetChildren()) do
        if part:IsA("BasePart") and part.Name:lower() == wanted then
            list[#list + 1] = part
        end
    end
    -- Some locations have more than one marker. The lower-X Desert marker is
    -- the one that streams Workspace.Map.Desert on the current map.
    table.sort(list, function(left, right)
        if left.Position.X ~= right.Position.X then
            return left.Position.X < right.Position.X
        end
        return left.Position.Z < right.Position.Z
    end)
    return list
end

local function saberLocation(name)
    return saberLocations(name)[1]
end

local function findMob(text)
    local wanted = text:lower()
    for _, mob in ipairs(collectEnemies(tick())) do
        if mob.Name:lower() == wanted then return mob end
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
    local operationEpoch = runtime.operationEpoch
    local commF = shopRemote()
    if not commF then
        runtime.state.status = "Saber: CommF_ is missing"
        return false
    end

    local ok, progress = pcall(function()
        return commF:InvokeServer("ProQuestProgress")
    end)
    if not runtime.operationValid(operationEpoch, epoch, char) then return false end
    if not ok or type(progress) ~= "table" then
        runtime.state.status = "Saber: could not read the quest state"
        return false
    end
    runtime.state.saberProgress = progress
    runtime.state.saberStateAt = now

    local plates = progress.Plates or {}
    local function plateDone(index)
        return runtime.state.saberPlates[index] == true
            or plates[index] == true or plates[tostring(index)] == true
    end

    -- Every confirmed server stage is latched. A later query that briefly
    -- omits an old flag must not move the puzzle backwards or make the
    -- timeout look fresh. Only the first false-to-true transition is new
    -- progress.
    local function latchProgress(authoritative)
        local changed = false
        local sourcePlates = authoritative.Plates or {}
        for index = 1, 5 do
            local done = sourcePlates[index] == true or sourcePlates[tostring(index)] == true
            if done and not runtime.state.saberPlates[index] then
                runtime.state.saberPlates[index] = true
                changed = true
            end
        end
        local function latch(name, value)
            if value and not runtime.state[name] then
                runtime.state[name] = true
                return true
            end
            return false
        end
        if latch("saberUsedTorch", authoritative.UsedTorch) then changed = true end
        if latch("saberUsedCup", authoritative.UsedCup) then changed = true end
        if latch("saberKilledMob", authoritative.KilledMob) then changed = true end
        if latch("saberUsedRelic", authoritative.UsedRelic) then changed = true end
        if latch("saberKilledShanks", authoritative.KilledShanks) then changed = true end
        if latch("saberSonReady", authoritative.TalkedSon) then changed = true end
        if changed then runtime.state.saberProgressAt = now end
        return changed
    end
    latchProgress(progress)

    local plateCount = 0
    for index = 1, 5 do
        if plateDone(index) then plateCount = plateCount + 1 end
    end

    -- The fingerprint describes the monotonic state for diagnostics and
    -- change detection. It is deliberately not a timeout source: an
    -- alternating RichSon reply or the first observation of an unchanged
    -- state must never keep a stuck puzzle alive.
    local fingerprint = table.concat({
        tostring(plateCount),
        runtime.state.saberUsedTorch and "1" or "0",
        runtime.state.saberUsedCup and "1" or "0",
        runtime.state.saberCupGranted and "1" or "0",
        runtime.state.saberCupTouched and "1" or "0",
        runtime.state.saberFillPending and "1" or "0",
        runtime.state.saberSickDone and "1" or "0",
        runtime.state.saberKilledMob and "1" or "0",
        runtime.state.saberSonReady and "1" or "0",
        runtime.state.saberRelicGrantAccepted and "1" or "0",
        runtime.state.saberRelicConfirmed and "1" or "0",
        runtime.state.saberUsedRelic and "1" or "0",
        runtime.state.saberKilledShanks and "1" or "0",
    }, ":")
    runtime.state.saberFingerprint = fingerprint

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
        if not runtime.operationValid(operationEpoch, epoch, char) then return nil, nil end
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

    local function ownedTool(name, exact)
        local wanted = name:lower()
        for tool in pairs(ownedTools()) do
            local toolName = tool.Name:lower()
            if (exact and toolName == wanted)
                or (not exact and toolName:find(wanted, 1, true)) then
                return tool
            end
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

    local function findSaberSpawn(name)
        local spawn = findSpawn(name, true)
        if spawn then return spawn end
        local origin = Workspace:FindFirstChild("_WorldOrigin")
        local spawns = origin and origin:FindFirstChild("EnemySpawns")
        if not spawns then return nil end
        for _, part in ipairs(spawns:GetChildren()) do
            -- Spawn names include level and role suffixes. Normalize the
            -- display label before applying the exact Mob Leader alias.
            local label = mobKey(part.Name):lower()
            -- The current map labels the Mob Leader spawn "Mob Boss" with a
            -- level/role suffix. The enemy that spawns there is still the
            -- exact Mob Leader.
            if name == "Mob Leader" and label == "mob boss" then
                return part
            end
            if name == "Saber Expert" and label == "saber expert" then
                return part
            end
        end
        return nil
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
    if not runtime.state.saberUsedTorch then
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

    -- GetCup only gives the empty cup. The official QuestPro client waits
    -- for the equipped Cup.Handle to touch the exact Ice water part before it
    -- sends FillCup. A request based only on the character's distance is not
    -- accepted by the current server, so the physical touch is a separate gate.
    if not runtime.state.saberUsedCup then
        local cupTool = ownedTool("Cup", true)
        local water = saberPart("Map/Ice/ParticleDrop/Water")
        local frozenMarker = saberLocation("Frozen Village")
        local desertCup = saberDescendant(saberPart("Map/Desert"), "Cup")
        local currentDesertCupPart = desertCup
            and (desertCup:IsA("BasePart") and desertCup or anchorOf(desertCup))
        local desertCupPart = currentDesertCupPart
            or runtime.state.saberDesertCupTouchPart
        runtime.state.saberAt = "the cup in the Frozen cave"

        -- The official QuestPro flow starts with the character touching the
        -- Desert Cup. GetCup must not be sent from a distance: the current
        -- server can grant the inventory tool, but later refuses FillCup when
        -- that earlier physical Cup step never happened.
        if currentDesertCupPart
            and runtime.state.saberDesertCupTouchPart ~= currentDesertCupPart then
            if runtime.state.saberDesertCupConnection then
                pcall(function()
                    runtime.state.saberDesertCupConnection:Disconnect()
                end)
            end
            runtime.state.saberDesertCupConnection = nil
            runtime.state.saberDesertCupTouched = false
            runtime.state.saberDesertCupTouchPart = currentDesertCupPart
            runtime.state.saberDesertCupTouchAt = 0
            desertCupPart = currentDesertCupPart
        end
        if not currentDesertCupPart
            and not runtime.state.saberDesertCupTouched then
            local desertMarker = saberLocation("Desert")
            if desertMarker then
                runtime.state.status = "Saber: flying to Desert for the Cup"
                flyTo(desertMarker.Position + Vector3.new(0, 30), "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            else
                runtime.state.status = "Saber: the Desert Cup is not loaded"
            end
            return false
        end
        if not desertCupPart then
            runtime.state.status = "Saber: the Desert Cup is not loaded"
            return false
        end
        if not runtime.state.saberDesertCupConnection and desertCupPart.Parent then
            runtime.state.saberDesertCupConnection = desertCupPart.Touched:Connect(function(hit)
                if not char or not hit or not hit:IsDescendantOf(char) then return end
                if not runtime.operationValid(operationEpoch, epoch, char) then return end
                if runtime.state.saberDesertCupTouchPart ~= desertCupPart then return end
                runtime.state.saberDesertCupTouched = true
                runtime.state.saberDesertCupTouchAt = tick()
                runtime.state.status = "Saber: the character touched the Desert Cup"
            end)
        end

        -- This is a real tween, not a warp. MoveSpeed is 200 studs per second
        -- by default (the accepted range is 180-200), and the character is
        -- placed against the Cup before the exact touch is requested.
        if not runtime.state.saberDesertCupTouched then
            local rootHeight = root.Size and root.Size.Y or 2
            local cupHeight = desertCupPart.Size and desertCupPart.Size.Y or 0
            local cupGoal = desertCupPart.Position
                + Vector3.new(0, math.max(0, (cupHeight - rootHeight) / 2), 0)
            if (root.Position - cupGoal).Magnitude > 2 then
                runtime.state.status = "Saber: tweening to the Desert Cup"
                runtime.tweenTo(CFrame.new(cupGoal))
                return false
            end
            -- The client is already physically against the exact Cup part.
            -- This only completes the local Touched callback; FillCup still
            -- requires a separate real touch of the exact Water part later.
            touch(root, desertCupPart)
            return false
        end

        if not cupTool then
            -- GetCup is now sent only after the official Desert Cup touch
            -- sequence. The actual tool is still required before FillCup.
            local called, result = callProgress("GetCup")
            runtime.state.saberCupRequestAt = now
            if called and result ~= false then
                runtime.state.status = "Saber: GetCup was accepted, waiting for the cup"
            elseif called then
                runtime.state.status = "Saber: the server refused GetCup"
            else
                runtime.state.status = "Saber: GetCup did not reach the server"
            end
            return false
        end

        -- The actual inventory tool is the only proof that GetCup was granted.
        -- The server flag alone is not used to skip the item.
        runtime.state.saberCupGranted = true
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        -- The live Blox Fruits Humanoid does not expose GetEquippedTool.
        -- EquipTool moves the exact tool into the Character, so its parent
        -- is the authoritative equipped-state check.
        if hum and cupTool.Parent ~= char then
            pcall(function() hum:EquipTool(cupTool) end)
        end
        if cupTool.Parent ~= char then
            runtime.state.status = "Saber: waiting for the Cup to be equipped"
            return false
        end

        -- The official proof is the exact Cup.Handle part. A generic tool
        -- part fallback is not enough for FillCup.
        local handle = cupTool:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then
            runtime.state.status = "Saber: the Cup handle is not loaded"
            return false
        end

        -- Frozen Village is a real route anchor. The first flight loads the
        -- Ice model and its ParticleDrop/Water part without relying on an old
        -- hard-coded position or on the decorative map GUI.
        if not water then
            if frozenMarker then
                runtime.state.status = "Saber: flying to Frozen Village"
                flyTo(frozenMarker.Position + Vector3.new(0, 30), "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            else
                runtime.state.status = "Saber: the Frozen Village marker is not loaded"
            end
            return false
        end

        -- FillCup and SickMan are two halves of one official exchange. The
        -- server accepts the filled Cup first, but it publishes UsedCup only
        -- after SickMan confirms that exchange. Waiting for UsedCup before
        -- sending SickMan deadlocks the stage. A retry still needs a new
        -- physical touch of the exact Water part.
        if runtime.state.saberFillPending then
            local fillAge = now - (runtime.state.saberFillRequestAt or 0)
            local sickStatus
            if fillAge >= 0.35
                and runtime.state.saberFillSickResult ~= 0
                and now - (runtime.state.saberFillSickAt or 0) >= 2
                and now - (runtime.state.saberAttempts["SickMan"] or 0) >= 2 then
                local sickCalled, sickResult = callProgress("SickMan")
                if sickCalled then
                    runtime.state.saberFillSickAt = now
                    runtime.state.saberFillSickResult = sickResult
                    if sickResult == 0 then
                        runtime.state.saberSickDone = true
                        sickStatus = "Saber: FillCup was sent; waiting for the Sick Man confirmation"
                    else
                        sickStatus = "Saber: the Sick Man has not confirmed the filled Cup yet"
                    end
                    runtime.state.status = sickStatus
                end
            end
            if fillAge < 8 then
                runtime.state.status = sickStatus
                    or runtime.state.status
                    or "Saber: FillCup was accepted, waiting for the server"
                return false
            end
            runtime.state.saberFillPending = false
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: FillCup was not confirmed, touching the water again"
            return false
        end
        if now - (runtime.state.saberFillRequestAt or 0) < 2 then
            runtime.state.status = "Saber: waiting before the next FillCup request"
            return false
        end

        -- Move to the loaded water before installing the touch listener. The
        -- flight stays under the Saber movement token and cannot race a shop
        -- or an ordinary farm trip.
        if (root.Position - water.Position).Magnitude > 18 then
            runtime.state.status = "Saber: flying to the Cup water"
            flyTo(water.Position, "saber")
            if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            return false
        end

        local function disconnectTouch()
            if runtime.state.saberCupTouchConnection then
                pcall(function() runtime.state.saberCupTouchConnection:Disconnect() end)
            end
            runtime.state.saberCupTouchConnection = nil
        end

        -- A touch belongs to one exact tool, Handle and Water instance. A
        -- replacement Cup, Handle or newly streamed Water part starts a new
        -- touch attempt instead of inheriting an old proof.
        if runtime.state.saberCupTouchConnection
            and (runtime.state.saberCupTouchTool ~= cupTool
                or runtime.state.saberCupTouchWater ~= water
                or runtime.state.saberCupTouchHandle ~= handle) then
            disconnectTouch()
        end
        if runtime.state.saberCupTouchTool ~= cupTool
            or runtime.state.saberCupTouchWater ~= water
            or runtime.state.saberCupTouchHandle ~= handle then
            runtime.state.saberCupTouched = false
            runtime.state.saberCupTouchTool = cupTool
            runtime.state.saberCupTouchWater = water
            runtime.state.saberCupTouchHandle = handle
        end

        -- Move the handle above the water first, then install the listener and
        -- enter the water. This creates a real Touched event for the exact
        -- ParticleDrop/Water part instead of accepting a nearby part.
        local function moveHandleToHeight(handleY, timeout, waitForTouch)
            local deadline = tick() + timeout
            while tick() < deadline do
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
                local offset = handle.Position - root.Position
                local target = Vector3.new(
                    water.Position.X - offset.X,
                    handleY - offset.Y,
                    water.Position.Z - offset.Z)
                runtime.setFlying()
                runtime.tweenTo(CFrame.new(target) * root.CFrame.Rotation)
                if (root.Position - target).Magnitude <= 3 and not waitForTouch then return true end
                task.wait(0.05)
            end
            return false
        end

        if not runtime.state.saberCupTouched then
            local waterHeight = water.Size and water.Size.Y / 2 or 14
            local aboveY = water.Position.Y + waterHeight + 5
            moveHandleToHeight(aboveY, 3)

            if not runtime.state.saberCupTouchConnection then
                runtime.state.saberCupTouchConnection = handle.Touched:Connect(function(part)
                    if part ~= water then return end
                    if not runtime.operationValid(operationEpoch, epoch, char) then return end
                    if cupTool.Parent ~= char
                        or cupTool:FindFirstChild("Handle") ~= handle then return end
                    runtime.state.saberCupTouched = true
                    runtime.state.saberCupTouchHandle = handle
                    runtime.state.saberCupTouchAt = tick()
                    runtime.state.status = "Saber: the Cup handle touched the water"
                end)
            end

            moveHandleToHeight(water.Position.Y, 4, true)
            if not runtime.state.saberCupTouched then
                runtime.state.status = "Saber: waiting for the Cup handle to touch the water"
                return false
            end
        end

        -- Let the exact touch reach the server before asking it to fill the
        -- Cup. The request is never sent from a distance-only check.
        task.wait(0.25)
        if not runtime.operationValid(operationEpoch, epoch, char) then return false end
        if cupTool.Parent ~= char then
            disconnectTouch()
            runtime.state.saberCupTouched = false
            runtime.state.status = "Saber: the Cup is no longer equipped"
            return false
        end
        -- Re-resolve both physical participants immediately before the
        -- request. If the Handle or streamed Water was replaced during the
        -- settling delay, the old touch cannot authorize the new instances.
        if cupTool:FindFirstChild("Handle") ~= handle
            or saberPart("Map/Ice/ParticleDrop/Water") ~= water then
            disconnectTouch()
            runtime.state.saberCupTouched = false
            runtime.state.status = "Saber: waiting for a fresh Cup water touch"
            return false
        end
        if not runtime.state.saberCupTouched
            or runtime.state.saberCupTouchTool ~= cupTool
            or runtime.state.saberCupTouchWater ~= water
            or runtime.state.saberCupTouchHandle ~= handle then
            runtime.state.status = "Saber: waiting for a fresh Cup water touch"
            return false
        end

        local called, result = callProgress("FillCup", cupTool)
        disconnectTouch()
        runtime.state.saberCupTouched = false
        if called and result ~= false then
            -- The delay starts when the server accepts FillCup, not when this
            -- pass began. Positioning the handle can take several seconds.
            runtime.state.saberFillRequestAt = tick()
            runtime.state.saberFillPending = true
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: FillCup was accepted, waiting for the server"
        elseif called then
            runtime.state.saberFillRequestAt = 0
            runtime.state.saberFillPending = false
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: the server refused FillCup"
        else
            runtime.state.saberFillRequestAt = 0
            runtime.state.saberFillPending = false
            runtime.state.saberFillSickAt = 0
            runtime.state.saberFillSickResult = nil
            runtime.state.status = "Saber: FillCup did not reach the server"
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

    -- The first Rich Son conversation is its own server-backed stage. The
    -- reply 0 tells the player that the Mob Leader must be killed, and it is
    -- made before the boss hunt so the later reply 1 is not skipped.
    if not runtime.state.saberSonReady then
        local npc = findTeacher("Rich Man")
        runtime.state.saberAt = "the Rich Man of the Pirate Village"
        if npc then
            if moveToPart(npc, 8) then
                local called, result = callProgress("RichSon")
                if called and result == 0 then
                    runtime.state.saberSonReady = true
                    runtime.state.saberProgressAt = now
                    runtime.state.status = "Saber: the Rich Man confirmed the Mob Leader task"
                elseif called and result == 1 then
                    -- The server already knows about the kill. Keep both
                    -- stages separate: the grant still has to be followed by
                    -- the actual relic in the inventory.
                    runtime.state.saberSonReady = true
                    runtime.state.saberRelicGrantAccepted = true
                    runtime.state.saberProgressAt = now
                    runtime.state.status = "Saber: the Rich Man already granted the relic"
                else
                    runtime.state.status = "Saber: the Rich Man did not confirm the Mob Leader task"
                end
            end
        else
            runtime.state.status = "Saber: the Rich Man was not found"
        end
        return false
    end

    -- The Mob Leader has to be really killed. The server flag is the
    -- completion test; the health watch below only refreshes the timeout.
    if not runtime.state.saberKilledMob then
        useBoss("Mob Leader", "the Mob Leader on Jean-Luc Island")
        local mob = findMob("Mob Leader")
        if mob then
            watchBoss(mob)
            runtime.state.status = "Saber: fighting the Mob Leader"
        else
            local spawn = findSaberSpawn("Mob Leader")
            local anchor = spawn and anchorOf(spawn)
            if anchor and (root.Position - anchor.Position).Magnitude > 700 then
                runtime.state.status = "Saber: flying to the Mob Leader"
                flyTo(anchor.Position, "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
            else
                runtime.state.status = "Saber: waiting for the Mob Leader"
            end
        end
        return false
    end
    runtime.state.saberTarget = nil

    -- The Rich Man's son hands over the relic only after the Mob Leader is
    -- dead. The stages are deliberately separate: the pre-kill reply 0, the
    -- post-kill grant reply 1, the actual Relic in the inventory, and finally
    -- the UsedRelic server flag after the door accepted it.
    local relic = ownedTool("Relic")
    if not runtime.state.saberUsedRelic then
        if relic then
            -- The inventory tool is the proof that the grant happened, even
            -- when this run did not make the reply-1 request itself.
            local firstRelic = not runtime.state.saberRelicConfirmed
            runtime.state.saberRelicGrantAccepted = true
            runtime.state.saberRelicConfirmed = true
            if firstRelic then runtime.state.saberProgressAt = now end
        else
            -- Reply 1 means that the grant was accepted, but the actual Relic
            -- can still arrive late. Keep asking on a cooldown until the tool
            -- is really in the inventory. Latching reply 1 without the item
            -- used to leave Auto Saber waiting until its timeout.
            local npc = findTeacher("Rich Man")
            runtime.state.saberAt = "the Rich Man of the Pirate Village"
            if npc then
                if moveToPart(npc, 8) then
                    if now - (runtime.state.saberRelicRequestAt or 0) >= 3 then
                        local called, result = callProgress("RichSon")
                        runtime.state.saberRelicRequestAt = now
                        if called and result == 1 then
                            local firstGrant = not runtime.state.saberRelicGrantAccepted
                            runtime.state.saberRelicGrantAccepted = true
                            -- Only the first accepted grant is real progress.
                            -- Repeating reply 1 every three seconds must not
                            -- refresh the timeout forever while the item is
                            -- still missing.
                            if firstGrant then runtime.state.saberProgressAt = now end
                            runtime.state.status = "Saber: the Rich Man granted the relic, waiting for the item"
                        elseif called and result == 0 then
                            -- Reply 0 is an ephemeral dialogue result. It must not
                            -- clear an earlier accepted grant, because doing so
                            -- would make alternating replies refresh the Saber
                            -- timeout forever. Requery the authoritative state;
                            -- if the server says the Mob Leader is still needed,
                            -- the next pass returns to that boss stage.
                            runtime.state.saberSonReady = true
                            runtime.state.saberMobLeaderRequired = true
                            local freshOk, freshProgress = pcall(function()
                                return commF:InvokeServer("ProQuestProgress")
                            end)
                            if not runtime.operationValid(operationEpoch, epoch, char) then return false end
                            if freshOk and type(freshProgress) == "table" then
                                progress = freshProgress
                                runtime.state.saberProgress = progress
                                latchProgress(progress)
                            end
                            runtime.state.saberMobLeaderRequired = not runtime.state.saberKilledMob
                            if not runtime.state.saberKilledMob then
                                useBoss("Mob Leader", "the Mob Leader on Jean-Luc Island")
                                runtime.state.status = "Saber: the Rich Man still wants the Mob Leader"
                            else
                                runtime.state.status = "Saber: waiting for the granted relic"
                            end
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

        -- PlaceRelic is the official server action for the door. A truthy reply
        -- is only the acceptance; UsedRelic in the next progress query is the
        -- confirmed completion.
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
    runtime.state.saberRelicGrantAccepted = true
    runtime.state.saberRelicConfirmed = true

    -- The Saber Expert is behind the opened door. KilledShanks is the server
    -- proof that this boss died; merely disappearing is not enough.
    if not runtime.state.saberKilledShanks then
        useBoss("Saber Expert", "the Saber Expert behind the Jungle door")
        local mob = findMob("Saber Expert")
        if mob then
            watchBoss(mob)
            runtime.state.status = "Saber: fighting the Saber Expert"
        else
            local spawn = findSaberSpawn("Saber Expert")
            local anchor = spawn and anchorOf(spawn)
            if anchor and (root.Position - anchor.Position).Magnitude > 700 then
                runtime.state.status = "Saber: flying to the Saber Expert"
                flyTo(anchor.Position, "saber")
                if not runtime.operationValid(operationEpoch, epoch, char) then return false end
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
            local canRunSaber = false
            if not runtime.state.saberActive then
                local acquired, saberMovementToken = runtime.acquireMovement("saber")
                if acquired then
                    runtime.state.saberMovementToken = saberMovementToken
                    runtime.state.saberActive = true
                    runtime.state.saberLockAt = tick()
                    runtime.state.saberProgressAt = tick()
                    canRunSaber = true
                else
                    runtime.state.status = "Saber is waiting for the movement"
                end
            elseif runtime.state.movementOwner == "saber" then
                canRunSaber = true
            else
                local acquired, saberMovementToken = runtime.acquireMovement("saber")
                if acquired then
                    runtime.state.saberMovementToken = saberMovementToken
                    canRunSaber = true
                else
                    runtime.state.status = "Saber is waiting for the movement"
                end
            end

            if canRunSaber and not runtime.state.shopping
                and not runtime.state.shopInFlight then
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
            and not runtime.state.shopInFlight and not runtime.state.flying
            and not runtime.state.saberActive and runtime.state.movementOwner ~= "saber" then
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
        if runtime.config.AutoBuso and runtime.state.enabled
            and not runtime.state.shopping and not runtime.state.shopInFlight
            and not runtime.state.saberActive then
            local now = tick()
            if not runtime.hasAbility("Buso")
                and now - (runtime.state.busoAttemptAt or 0) >= 300 then
                runtime.state.busoAttemptAt = now
                local ok, err = pcall(function() runtime.buyAbility("Buso") end)
                if not runtime.isCurrent() then return end
                if not ok then dbg("The Buso buy failed: " .. tostring(err)) end
            end
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

local TABS = {"HOME", "MOVE", "FIGHT", "TOOLS", "STATS"}

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

local function makeTextInput(text, value, placeholder, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundTransparency = 1
    row.LayoutOrder = #page:GetChildren()
    row.Parent = page

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -48, 0, 15)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = THEME.text
    label.Font = THEME.font
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -50, 0, 27)
    box.Position = UDim2.new(0, 0, 0, 17)
    box.BackgroundColor3 = THEME.bg
    box.BorderSizePixel = 0
    box.Text = tostring(value or "")
    box.PlaceholderText = tostring(placeholder or "")
    box.PlaceholderColor3 = THEME.subtext
    box.TextColor3 = THEME.text
    box.Font = THEME.font
    box.TextSize = 11
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.Parent = row
    corner(box, 5)
    stroke(box)

    local apply = Instance.new("TextButton")
    apply.Size = UDim2.new(0, 46, 0, 27)
    apply.Position = UDim2.new(1, -46, 0, 17)
    apply.BackgroundColor3 = THEME.panel
    apply.Text = "Set"
    apply.TextColor3 = THEME.text
    apply.Font = THEME.fontBold
    apply.TextSize = 10
    apply.AutoButtonColor = false
    apply.Parent = row
    corner(apply, 5)
    stroke(apply)

    local committed = tostring(value or "")
    local function commit()
        if not runtime.isCurrent() then return end
        local nextValue = box.Text
        if nextValue == committed then return end
        committed = nextValue
        cb(nextValue)
    end
    local function setValue(nextValue)
        committed = tostring(nextValue or "")
        box.Text = committed
    end
    apply.MouseButton1Click:Connect(commit)
    box.FocusLost:Connect(commit)
    return box, commit, setValue
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
makeToggle("Safe Tween Farm", runtime.config.Dodge, function(v) runtime.config.Dodge = v end)
makeSlider("Safe Distance", 14, 45, runtime.config.DodgeRadius,
    function(v) return v.." studs" end, function(v) runtime.config.DodgeRadius = v end)
makeSlider("Move Slot Time", 200, 1000, math.floor((runtime.config.DodgeStepTime or 0.4) * 1000),
    function(v) return string.format("%.2fs", v/1000) end,
    function(v) runtime.config.DodgeStepTime = v/1000 end)
makeToggle("Short Warp", runtime.config.WarpClose, function(v) runtime.config.WarpClose = v end)
makeSlider("Warp Distance", 20, 200, runtime.config.WarpDistance,
    function(v) return v.." studs" end, function(v) runtime.config.WarpDistance = v end)
makeSlider("Void Guard Y", -1000, -50, runtime.config.SafeY,
    function(v) return tostring(v).." studs" end, function(v) runtime.config.SafeY = v end)

makeHeader("WORLD (SEA)")
makeButton("Go to Sea 1", function() spawnTracked(function() runtime.travelToWorld(1) end) end)
makeButton("Go to Sea 2", function() spawnTracked(function() runtime.travelToWorld(2) end) end)
makeButton("Go to Sea 3", function() spawnTracked(function() runtime.travelToWorld(3) end) end)
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
makeToggle("Fast Attack", runtime.config.FastAttack, function(v)
    runtime.config.FastAttack = v
    if v then runtime.state.attackCadence = runtime.config.FastAttackInterval end
end)
makeSlider("Fast Swing", 200, 1000, math.floor((runtime.config.FastAttackInterval or 0.4) * 1000),
    function(v) return string.format("%.2fs", v/1000) end,
    function(v)
        runtime.config.FastAttackInterval = v/1000
        runtime.state.attackCadence = v/1000
    end)
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
makeButton("Reset Attack State", function()
    runtime.resetCombatState()
    runtime.state.attackNextAt = 0
    dbg("Attack state reset")
end)
makeButton("Release Held Mobs", function()
    if runtime.releaseBringMobs then runtime.releaseBringMobs() end
    if runtime.restoreHitbox then runtime.restoreHitbox() end
    dbg("Held mobs released")
end)

makeHeader("AUTO QUESTS")
makeToggle("Auto Saber (First Sea puzzle)", runtime.config.AutoSaber,
    function(v)
        if v and (runtime.state.shopping or runtime.state.shopInFlight
            or runtime.state.flying or runtime.state.movementOwner == "shop"
            or runtime.state.movementOwner == "flight") then
            runtime.config.AutoSaber = false
            runtime.state.status = "Saber could not start: another movement is running"
            return
        end
        runtime.config.AutoSaber = v
        runtime.operationEpoch = (runtime.operationEpoch or 0) + 1
        runtime.stopTween()
        runtime.resetSaberState()
        if v then
            local acquired, saberMovementToken = runtime.acquireMovement("saber")
            if not acquired then
                runtime.config.AutoSaber = false
                runtime.state.status = "Saber could not start: another movement is running"
                return
            end
            runtime.state.saberMovementToken = saberMovementToken
            runtime.state.saberActive = true
            runtime.state.saberLockAt = tick()
            runtime.state.saberProgressAt = tick()
        end
    end)
makeSlider("Saber Timeout", 60, 600, runtime.config.AutoSaberTimeout,
    function(v) return v.."s" end, function(v) runtime.config.AutoSaberTimeout = v end)
makeHint("Does the Saber puzzle step by step: buttons, torch, cup, NPCs, bosses")

makeHeader("BOSS FARM")
makeToggle("Farm Bosses", runtime.config.BossFarm, function(v)
    runtime.config.BossFarm = v
    runtime.invalidateAutomaticQuestSelection("boss farming was " .. (v and "enabled" or "disabled"))
end)
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
    spawnTracked(function() runtime.buyAbility("Buso") end)
end)
makeButton("Buy Geppo (Skyjump)", function()
    spawnTracked(function() runtime.buyAbility("Geppo") end)
end)
makeButton("Buy Soru", function()
    spawnTracked(function() runtime.buyAbility("Soru") end)
end)
makeButton("Buy Observation Haki", function()
    spawnTracked(function() runtime.buyAbility("Observation") end)
end)

showTab(4) -- TOOLS
makeHeader("QUEST AND TARGET SELECTION")
local selectedMobBox, selectedMobCommit, setSelectedMobValue = makeTextInput("Selected mob", runtime.config.SelectedMob, "Auto, Nearest, or mob name", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.config.SelectedMob = value ~= "" and value or "Auto"
    runtime.state.selectedMob = runtime.config.SelectedMob
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    dbg("Selected mob: " .. runtime.config.SelectedMob)
end)
makeButton("Use Nearest Mob", function()
    runtime.config.SelectedMob = "Nearest"
    runtime.state.selectedMob = "Nearest"
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    if setSelectedMobValue then setSelectedMobValue("Nearest") end
    dbg("Selected mob: Nearest")
end)
makeTextInput("Manual quest", runtime.config.ManualQuest, "QuestName or questName#index", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.setManualQuest(value ~= "" and value or "Auto")
end)
local bossTargetBox, bossTargetCommit, setBossTargetValue = makeTextInput("Boss target", runtime.config.BossTarget, "Auto or exact boss name", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.config.BossTarget = value ~= "" and value or "Auto"
    runtime.state.selectedBoss = runtime.config.BossTarget
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    dbg("Boss target: " .. runtime.config.BossTarget)
end)
makeButton("Target Greybeard", function()
    runtime.config.BossTarget = "Greybeard"
    runtime.state.selectedBoss = "Greybeard"
    runtime.state.lastTarget, runtime.state.targetHealth, runtime.state.targetAt = nil, nil, 0
    if setBossTargetValue then setBossTargetValue("Greybeard") end
    dbg("Boss target: Greybeard")
end)
makeButton("Refresh Quest Data", function()
    spawnTracked(function() runtime.refreshQuestData() end)
end)
makeButton("Refresh Island List", function()
    if rebuildIslands then rebuildIslands() end
end)
makeSegment("Team", {"None", "Pirates", "Marines"}, runtime.config.TeamSelection, function(value)
    spawnTracked(function() runtime.setTeam(value) end)
end)

makeHeader("CODES")
local codeBox = makeTextInput("Redemption code", "", "Enter a code", function() end)
makeButton("Redeem Code", function()
    spawnTracked(function() runtime.redeemCode(codeBox.Text) end)
end)

makeHeader("CHESTS AND POLE")
makeToggle("Auto Chest", runtime.config.AutoChest, function(v)
    runtime.config.AutoChest = v
    if not v then runtime.cancelChest() end
end)
makeSlider("Chest Range", 100, 10000, runtime.config.ChestRange,
    function(v) return v .. " studs" end, function(v)
        runtime.config.ChestRange = v
        if runtime.state.chestTarget then runtime.cancelChest() end
    end)
makeSlider("Chest Timeout", 5, 120, runtime.config.ChestTimeout,
    function(v) return v .. "s" end, function(v) runtime.config.ChestTimeout = v end)
makeToggle("Pole Mastery", runtime.config.PoleMastery, function(v)
    runtime.config.PoleMastery = v
    if not v then runtime.resetPoleState() end
end)
makeTextInput("Pole target", runtime.config.PoleTarget, "Mob to hit with the pole", function(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    runtime.config.PoleTarget = value ~= "" and value or "Bandit"
    dbg("Pole target: " .. runtime.config.PoleTarget)
end)

makeHeader("FRUIT ESP AND NOTIFIER")
makeToggle("Fruit ESP", runtime.config.FruitESP, function(v) runtime.config.FruitESP = v end)
makeToggle("Fruit Notifier", runtime.config.FruitNotifier, function(v) runtime.config.FruitNotifier = v end)
makeTextInput("Webhook URL", runtime.config.FruitWebhook, "Optional Discord webhook", function(value)
    runtime.config.FruitWebhook = tostring(value or ""):match("^%s*(.-)%s*$") or ""
end)
makeToggle("Anti-Fall", runtime.config.AntiFall, function(v) runtime.config.AntiFall = v end)

makeHeader("SERVER HOP AND REJOIN")
makeToggle("Auto Hop", runtime.config.AutoHop, function(v)
    runtime.config.AutoHop = v
    if v then runtime.state.hopLastAt = os.time() end
end)
makeSlider("Hop Cooldown", 10, 600, runtime.config.HopCooldown,
    function(v) return v .. "s" end, function(v) runtime.config.HopCooldown = v end)
makeSlider("Max Hop Attempts", 1, 10, runtime.config.HopMaxAttempts,
    function(v) return tostring(v) end, function(v) runtime.config.HopMaxAttempts = v end)
makeToggle("Kick Recovery", runtime.config.KickRecovery, function(v) runtime.config.KickRecovery = v end)
makeTextInput("Rejoin script path", runtime.config.RejoinScriptPath, "/path/to/bloxfruit.lua", function(value)
    runtime.config.RejoinScriptPath = tostring(value or ""):match("^%s*(.-)%s*$") or ""
end)
makeButton("Hop Server Now", function()
    spawnTracked(function() runtime.hopServer("manual", true) end)
end)
makeButton("Reset Hop Attempts", function()
    runtime.resetHopAttempts()
end)
makeHint("Auto Hop waits for the cooldown; the attempt limit stops a loop")

showTab(5) -- STATS
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
        infoLabel.Text = string.format("Lv %d • Fruits: %d • Quest: %s • Spd %s • Swing %.2fs",
            getMyLevel(), runtime.state.fruitsFound, questProgressText(),
            tostring(runtime.state.attackSpeed),
            tonumber(runtime.state.attackCadence) or 0)
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











