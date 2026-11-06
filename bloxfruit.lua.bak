-- // Blox Fruits Auto-Farm — Fixed Build
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer

-- Roblox streams far away content out of the client. A mob that is not
-- loaded does not exist for us at all, so the bot walks around an empty
-- world and never finds anything to attack. The game hubs switch streaming
-- off for exactly this reason.
pcall(function() Workspace.StreamingEnabled = false end)
pcall(function() Workspace.StreamingMinRadius = 1e8 end)
pcall(function() Workspace.StreamingTargetRadius = 1e8 end)

-- ================= CONFIG =================
local CONFIG = {
    AutoQuest       = true,
    AutoFarm        = true,
    FruitSniper     = true,
    Debug           = true,
    EatFruit        = true,    -- eat the fruit right after picking it up
    QuestTurnIn     = true,    -- hand completed quests back to the quest giver
    AntiAfk         = true,    -- keep the session alive while the bot runs
    AntiAfkInterval = 120,     -- seconds between two anti-AFK nudges
    AttackCooldown  = 0.08,  -- ให้ตีไวขึ้น
    FastAttack      = true,     -- remove the game's attack cooldown
    RemoteAttack    = true,     -- send the swing through the game's own remotes
    HitboxMagnitude = 120,      -- how far the melee swing reaches
    WeaponMode      = "Melee", -- Melee | Sword | Fruit | Gun
    MeleeRange      = 10,      -- melee needs to be close to connect
    GunRange        = 60,      -- guns reach much further
    MeleeHover      = 4,       -- stay low so the swing hits
    BringMob        = true,   -- เปิดใช้งาน Bring Mob ได้ปกติแล้ว
    BringMobRange   = 35,     -- รัศมีดึงกำลังพอดี ไม่ดึงมอนไกลเกินไปจนกระตุก
    BringMobCount   = 2,       -- how many mobs of the same kind are brought over
    BringMobSearch  = 200,     -- how far around the target the other mobs are looked for
    AutoStats       = false,   -- spend the stat points of the game right away
    AutoStatTarget  = "Melee", -- Melee | Sword | Gun | Fruit | Defense | All
    AutoStatWait    = 3,       -- seconds between two stat upgrades
    SpawnBypass     = false,   -- respawn on the island of the quest giver
    BypassDistance  = 2500,    -- how far the quest giver has to be for a jump
    FastPortal      = true,    -- try the door of the game before the spawn reset
    TravelWorld     = 1,       -- world for the travel button
    BigHitbox       = true,    -- make the mob hitbox bigger
    HitboxSize      = 16,
    HeadHover       = 2,       -- studs above the mob head
    AutoAttack      = true,    -- swing at any mob that is in reach
    AutoStore       = false,   -- store the fruits we carry
    StoreFruitMin   = 3,       -- store from this many fruits on
    HoverHeight     = 8,       -- studs above the mob (lower = more reliable hits, higher = safer)
    FruitScanRadius = 5000,
    MovementMode    = "Tween", -- Walk | Tween | Teleport
    MoveSpeed       = 250,     -- studs/second for Tween mode
    QuestRetry      = 20,      -- seconds before the same quest is sent again
    TurnInTimeout   = 20,      -- seconds before a stuck quest turn-in is given up on
    QuestSeekTimeout = 30,     -- seconds spent asking a giver for a quest we don't know
    FruitPickupTries = 4,     -- touch attempts before a fruit is written off
    FruitTouchInterval = 0.35, -- seconds between two touch attempts on a fruit
    SafeY           = -300,    -- below this Y the character is pulled back up
    StuckTimeout    = 5,       -- seconds a mob may keep the same health before it is ignored
    StuckIgnore     = 10,      -- seconds a stuck mob is ignored

    -- {minLevel, maxLevel, questName, questIndex, mobName}
    -- NOTE: written from memory, verify against the game if a quest fails.
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
    enabled       = true,     -- master switch, driven by the GUI
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
    -- A quest that is finished but not handed in yet. The panel of the game
    -- can disappear, and a new quest would wipe the finished one.
    questDone     = false,
    questDoneMob  = nil,
    -- The quest we asked the game for and whether it was confirmed.
    questAsked    = nil,
    questAskedAt  = 0,
    questIndexTry = nil,
    questTried    = {},
    questTryKey   = nil,
    questNpc      = nil,
    questPos      = nil,
    statAt        = 0,
    bypassAt      = nil,
    bringMoved    = setmetatable({}, {__mode = "k"}),
    bringIgnored  = setmetatable({}, {__mode = "k"}),
    questVerified = false,
    questGaveUp   = false,
    -- Hits the game confirmed on the target we are fighting.
    hitsConfirmed = 0,
    hitRemoteHooked = false,
    statsHooked   = false,
    attackSpeed   = 1,
    turnInFailed  = false,
    turnInFailedAt = 0,
    seekSince     = nil,
    seekGaveUp    = false,
    seekGaveUpAt  = 0,
    afkTimer      = 0,
    afkSign       = 1,
    fruitTools    = nil,
}

-- fruit -> time of the last failed grab, so it is retried instead of lost
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
    -- Print each distinct line once; the counter in the GUI shows the repeats.
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
local function startsWith(s, p) return s:sub(1, #p) == p end
local function sameName(a, b) return a:lower() == b:lower() end

-- The part of an object that carries it, used for positions.
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

local function isFruit(t)
    return t.Name:lower():find("fruit", 1, true) ~= nil
end
-- Weapons we prefer to swing, grouped by kind. The weapon mode picks the group.
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


-- The game says what a weapon is: the ToolTip holds "Melee", "Sword", "Gun"
-- or "Fruit". That is more reliable than the name of the tool.
local function toolKind(tool)
    local tip = tool.ToolTip
    if type(tip) == "string" and tip ~= "" then return tip:lower() end
    return nil
end

-- A ranged weapon reaches much further than a melee one.
local function isGun(tool)
    if toolKind(tool) == "gun" then return true end
    local n = tool.Name:lower()
    for _, w in ipairs(WEAPON_GROUPS.Gun) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

-- Lower is better: the list is ordered by preference.
local function weaponRank(tool)
    local n = tool.Name:lower()
    local group = WEAPON_GROUPS[CONFIG.WeaponMode] or WEAPON_GROUPS.Melee
    for i, w in ipairs(group) do
        if n:find(w, 1, true) then return i end
    end
    return nil
end

-- Does this tool belong to the weapon mode the user picked?
local function matchesMode(tool)
    local mode = CONFIG.WeaponMode
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

-- How good a fallback weapon is: a sword is closer to a melee fight than a
-- gun is, so it is used first when the mode has nothing to offer.
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

-- How far the swing reaches. Melee needs to be close, a gun does not.
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

    local function equip(item)
        if tick() < state.equipRetryAt then return nil end
        
        -- ลองใช้ EquipTool ปกติก่อน
        pcall(function() hum:EquipTool(item) end)
        
        -- ถ้าเกมไม่ยอมสลับ (ไอเทมยังไม่ยอมเข้า Character) ให้ลองใช้ EquipEvent ของเกม
        if item.Parent ~= char then
            pcall(function()
                -- the game keeps the equip remote in Backpack.Combat
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
        
        if item.Parent ~= char then
            state.equipRetryAt = tick() + 2
            dbg("Could not equip " .. item.Name)
            return nil
        end
        return item
    end

    -- 1. ถ้าถืออาวุธที่ตรงโหมดในมืออยู่แล้ว ให้ใช้อันนั้นเลย
    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and matchesMode(equipped) then return equipped end

    -- 2. ค้นหาในตัวละคร และ ใน Backpack
    local carriers = {char}
    if backpack then table.insert(carriers, backpack) end

    local weapons, fallbacks, order = {}, {}, 0
    for _, container in ipairs(carriers) do
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                order = order + 1
                if CONFIG.WeaponMode == "Fruit" then
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

    -- ถืออาวุธที่จัดอันดับไว้ตามโหมด
    for _, entry in ipairs(weapons) do
        -- the weapon in hand is already the right one: do not swap it every tick
        if entry.tool == equipped then return equipped end
        local weapon = equip(entry.tool)
        if weapon then return weapon end
    end

    -- ไม่มีอาวุธของโหมดนี้ ให้ถืออาวุธที่มีอยู่แล้ว อย่าเพิ่งสลับไปมา
    if equipped and not isFruit(equipped) then return equipped end

    -- ถ้ายังไม่มีอะไรในมือ ให้ใช้อาวุธที่ใกล้เคียงที่สุดที่พกไว้
    table.sort(fallbacks, function(a, b)
        local ra, rb = fallbackRank(a), fallbackRank(b)
        if ra ~= rb then return ra < rb end
        return a.Name < b.Name
    end)
    local best = fallbacks[1]
    if best then
        local tool = equip(best)
        if tool then return tool end
    end

    return equipped
end


-- Drag the mob to the player so a melee swing actually connects. Only the
-- A bigger hitbox makes the swing land more often. It only sticks when the
-- client owns that part, so it is a bonus, not a promise.
local function enlargeHitbox(target)
    local anchor = anchorOf(target)
    if not anchor or not anchor.Size then return end
    local size = CONFIG.HitboxSize or 16
    if anchor.Size.X >= size then return end
    -- The server puts the size back, so do not write it every frame.
    local now = tick()
    if now < (state.hitboxAt or 0) then return end
    state.hitboxAt = now + 2
    pcall(function() anchor.Size = Vector3.new(size, size, size) end)
end

-- ================= GAME QUEST DATA =================
-- The game ships its own quest list: ReplicatedStorage.Quests holds the
-- tasks (which mob, how many) and ReplicatedStorage.GuideModule holds the
-- givers with the level and the place each quest is given. Reading that is
-- far better than a table written from memory: the list of the game has
-- every level, the table in the config only the first ones.
local gameQuests
local gameGuideQuests
local gameLevelQuests
local gameGuideNames
local gameQuestIndexes
local gameQuestCache, gameQuestCacheAt

-- Quests of the game that are no normal quest to farm.
local QUEST_SKIP = {
    BartiloQuest = true,
    Trainees = true,
    MarineQuest = true,
    CitizenQuest = true,
}

-- The mob of a task: the one the quest asks for the most.
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

-- Read the quest data of the game. The quest list of the game has the task
-- and the level of every quest; the guide of the game adds the giver, the
-- place of a quest and the level it is given at.
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

    -- The quest list of the game: name -> id -> {LevelReq, Task}.
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
                        -- Only a quest with a level can be picked by it.
                        if type(req) == "number" then
                            table.insert(data.levels, entry)
                        end
                        -- Every id of the quest, also the ones without a
                        -- level: the game can refuse one id and take another.
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

    -- The guide says which giver gives which quest and at which level.
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
                            -- The quest is only good when the level of the
                            -- quest and the level of the giver both allow it.
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
                            -- The quest of the level list gets the giver too,
                            -- so the bot knows where to go for it.
                            local base = data.byKey[npc.InternalQuestName .. "#" .. tostring(index)]
                            if base then
                                base.npc = npc.NPCName or npcKey
                                base.pos = npc.Position
                            end
                            known = true
                        end
                    end
                end
                -- Only a quest the guide really gives is a known quest.
                if known then data.guideNames[npc.InternalQuestName] = true end
            end
        end
    end
    for _, ids in pairs(data.indexes) do
        table.sort(ids, function(a, b) return a.index < b.index end)
    end
    -- The same level must always give the same quest.
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
-- The quest of the game that fits the level best: the highest one the
-- player may take. A quest with more than one kill is preferred, those are
-- the normal quests, even when a quest with one kill is of a higher level.
local function pickQuest(list, level, only)
    local best, fallback, bestLevel, fallbackLevel
    for _, q in ipairs(list) do
        if type(q.level) == "number" and q.level <= level and (not only or only[q.name]) then
            if (q.count or 0) > 1 then
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
    return best or fallback
end

-- The quest of the game for this level. The guide comes first: it knows
-- which quest is really given at this level. The quest list of the game is
-- the backup, and then only for quests the guide knows.
local function gameQuestFor(level)
    if gameQuestCacheAt == level then return gameQuestCache end
    local best = nil
    if gameGuideQuests and #gameGuideQuests > 0 then
        best = pickQuest(gameGuideQuests, level, nil)
        if not best and gameLevelQuests and #gameLevelQuests > 0 then
            best = pickQuest(gameLevelQuests, level, gameGuideNames)
        end
    elseif gameLevelQuests and #gameLevelQuests > 0 then
        best = pickQuest(gameLevelQuests, level, nil)
    end
    gameQuestCache, gameQuestCacheAt = best, level
    return best
end

local function questFor(level)
    -- The game's own data wins over the table in the config.
    local best = gameQuestFor(level)
    if best then
        return {name = best.name, index = best.index, mob = best.mob,
                pos = best.pos, npc = best.npc}
    end
    for _, q in ipairs(CONFIG.QuestList) do
        if level >= q[1] and level <= q[2] then
            return {name = q[3], index = q[4], mob = q[5]}
        end
    end
    return nil
end

local function questKey(q) return q.name .. "#" .. q.index end

-- The other id of the same quest: the game gives a quest under more than
-- one id and only one of them fits this level.
local function nextQuestIndex(q, level, tried)
    local ids = gameQuestIndexes and gameQuestIndexes[q.name]
    if not ids or #ids == 0 then
        -- A quest of the config has the two slots 1 and 2.
        ids = {{index = 1, level = 0}, {index = 2, level = 0}}
    end
    local best, bestLevel = nil, nil
    for _, id in ipairs(ids) do
        if not tried[id.index] then
            local lv = id.level or 0
            -- An id the player is too low for is of no use.
            if lv <= level then
                if bestLevel == nil or lv > bestLevel then
                    best, bestLevel = id.index, lv
                end
            end
        end
    end
    return best
end

-- Mobs whose name contains another mob's name, used to tell "Bandit" and
-- "Bandit Captain" apart when reading the quest panel.
local OTHER_MOBS = {"Bandit Captain", "Desert Bandit Captain"}

-- Every mob name the script knows, longest first so "Bandit Captain" is
-- always preferred over "Bandit". The list grows when the quest data of
-- the game is there.
local KNOWN_MOBS = {}
-- The plural forms of every known mob, made once so that reading the text
-- of the quest panel does not build them again and again.
local KNOWN_MOB_FORMS = {}
-- The same forms, ready for a pattern search.
local KNOWN_MOB_PATTERNS = {}
-- The lower case names of the known mobs, longest first.
local KNOWN_MOB_LOWER = {}

-- The plural forms a mob name can have ("Bandits", "Snowmen").
local function pluralForms(name)
    local base = name:lower()
    local forms = {base, base .. "s"}
    if base:sub(-3) == "man" then
        -- snowman -> snowmen, fishman -> fishmen
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
    for _, q in ipairs(CONFIG.QuestList) do add(q[5]) end
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

-- Whole word search that also accepts the plural form ("Bandits").
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
        -- A plain search first: it is much cheaper than the pattern.
        if t:find(variant, 1, true) then
            if t:find("%f[%w]" .. patterns[i] .. "%f[^%w]") then return true end
        end
    end
    return false
end

-- Known mob names that are longer versions of another mob's name. A loose
-- match on one of them is the wrong mob ("Bandit" quest, "Bandit Captain" mob).
local function isCompoundMob(name, wanted)
    local key = name:lower()
    local want = wanted:lower()
    for _, mob in ipairs(KNOWN_MOB_LOWER) do
        if #mob > #want and key:find(mob, 1, true) then return true end
    end
    return false
end

-- The mob a piece of panel text talks about; the longest match wins so
-- "Bandit Captain" is never read as "Bandit".
local function mobInText(text)
    local best
    for _, name in ipairs(KNOWN_MOBS) do
        if containsWord(text, name) and (not best or #name > #best) then best = name end
    end
    return best
end

-- The mob name a text starts with, if any ("... 3/5 Bandits and ...").
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

-- The mob name a text ends with, if any ("Defeat Bandits 3/5").
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

-- Read the quest data of the game in the background; the bot keeps working
-- with the table in the config until it is there.
task.spawn(function()
    local data = loadGameQuests()
    if data then
        gameQuests = data.quests
        gameGuideQuests = data.guide
        gameLevelQuests = data.levels
        gameGuideNames = data.guideNames
        gameQuestIndexes = data.indexes
        gameQuestCache, gameQuestCacheAt = nil, nil
        -- The ids of the quests come from the game now, the old tries are
        -- of no use.
        state.questTried = {}
        state.questTryKey = nil
        state.questIndexTry = nil
        refreshKnownMobs()
        dbg("Game quest data: " .. #gameQuests .. " quests")
    end
end)

-- Words that join two mob names; the name after them belongs to the next
-- fraction, not to this one.
local CONNECTORS = {["and"] = true, ["then"] = true, ["plus"] = true}

-- "Defeat 3/5 Bandits and 1/2 Pirates" and "Bandits 1/5, Pirates 4/5" both
-- give the progress of every mob in the text.
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

-- "Defeat 7 Bandits" -> seven mobs left to kill, no fraction in the text.
local function parseRequired(text)
    local out = {}
    for num, rest in text:gmatch("(%d+)%s+([%a%s']+)") do
        local mob = mobAtStart(rest)
        if mob then out[mob] = {count = 0, total = tonumber(num), remaining = true} end
    end
    if next(out) == nil then
        -- "Bandits: 7": the count comes after the name. A separator is
        -- required so a level number ("Snowman level 110") is never read
        -- as a kill counter.
        for name, num in text:gmatch("([%a%s']+)%s*:%s*(%d+)") do
            local mob = mobInText(name)
            if mob then out[mob] = {count = 0, total = tonumber(num), remaining = true} end
        end
    end
    return out
end

-- The game tells us the quest itself through Remotes.QuestUpdate: the task
-- (how many of each mob) and the progress (how many we already killed).
-- That is the real state, the panel is only a picture of it.
local questRemote, questRemoteState, questRemoteHooked = nil, nil, false

local function hookQuestRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local q = remotes and remotes:FindFirstChild("QuestUpdate")
    if not q then return nil end
    questRemote = q
    if questRemoteHooked or not q.OnClientEvent then return q end
    questRemoteHooked = true
    pcall(function()
        q.OnClientEvent:Connect(function(data, update)
            if data == nil then
                -- the game cleared the quest: the turn-in worked
                questRemoteState = nil
                state.questDone = false
                state.questDoneMob = nil
                state.currentQuest = nil
                state.questSentAt = 0
                -- A quest we had is gone: the ids we tried are of no use.
                -- A clear that comes right after a request is the game
                -- dropping the old quest: that one keeps its ids.
                local hadQuest = state.questVerified
                state.questAsked = nil
                state.questVerified = false
                state.questGaveUp = false
                state.questTryKey = nil
                state.questNpc = nil
                if hadQuest then
                    state.questTried = {}
                    state.questIndexTry = nil
                end
                dbg("Quest cleared by the game")
                return
            end
            questRemoteState = data
            if type(update) == "table" and update.Context == "Complete" then
                dbg("Quest progress complete: " .. tostring(update.Name))
            end
            -- The game answered: this is the quest we really have.
            state.questVerified = true
            state.questGaveUp = false
            if state.questAsked and data.InternalQuestName ~= state.questAsked then
                dbg("The game gave us " .. tostring(data.InternalQuestName)
                    .. " instead of " .. tostring(state.questAsked))
            else
                -- The quest we asked for is taken: the ids we tried are of
                -- no use now.
                state.questTried = {}
                state.questIndexTry = nil
            end
        end)
    end)
    return q
end

-- The quest of the game in the same shape the panel gives us.
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
    -- Hunt the mob the quest still needs the most of.
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
        -- The game sent the quest, so it is running: never ask for it again.
        confirmed = true,
        questName = s.InternalQuestName,
    }
end

-- The game tells us when a hit really landed: RE/ReceivedHit comes back from
-- the server for every confirmed hit. That is the truth about the fight.
local function hookHitRemote()
    if state.hitRemoteHooked then return end
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    local hit = net and net:FindFirstChild("RE/ReceivedHit")
    if not hit or not hit.OnClientEvent then return end
    state.hitRemoteHooked = true
    pcall(function()
        hit.OnClientEvent:Connect(function(player, mob, kind, weapon, part)
            state.hitsConfirmed = state.hitsConfirmed + 1
            state.lastHitAt = tick()
            if mob then state.lastHitMob = mob.Name end
        end)
    end)
end

-- The game sends the attack speed of the player: with a buff the swings come
-- faster, and the bot should not swing slower than the game allows.
local function hookStatsRemote()
    if state.statsHooked then return end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local stats = remotes and remotes:FindFirstChild("Stats")
    if not stats or not stats.OnClientEvent then return end
    state.statsHooked = true
    pcall(function()
        stats.OnClientEvent:Connect(function(player, key, value)
            if key == "AttackSpeedMultiplier" and type(value) == "number" and value > 0 then
                state.attackSpeed = value
            end
        end)
    end)
end

-- The quest as the game counts it: "Bandit 3/8".
local function questProgressText()
    local s = questRemoteState
    if not s or not s.Info then return tostring(state.currentQuest) end
    local task = s.Info.Task or {}
    local progress = s.Progress or {}
    local parts = {}
    for mob, need in pairs(task) do
        table.insert(parts, mob .. " " .. tostring(progress[mob] or 0) .. "/" .. tostring(need))
    end
    if #parts == 0 then return tostring(s.InternalQuestName or state.currentQuest) end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function questPanelGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local mainFrame = pg:FindFirstChild("Main")
    local panel = mainFrame and mainFrame:FindFirstChild("Quest")
    if panel and panel.Visible then return panel end
    -- Newer builds show the tracked quest in their own frame.
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

-- A gui is shown when it is visible; screen frames use "Enabled" instead.
local function guiShown(gui)
    if gui == nil then return false end
    local ok, v = pcall(function() return gui.Visible end)
    if ok and v ~= nil then return v end
    local ok2, e = pcall(function() return gui.Enabled end)
    if ok2 and e ~= nil then return e end
    return true
end

-- Everything the panel tells us about the current quest: which mob to hunt,
-- how far along we are and whether it is done.
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
        -- Plain counters can sit next to a fraction in the same line
        -- ("Defeat 3/5 Bandits and 7 Pirates"): track what is missing.
        for mob, prog in pairs(parseRequired(t)) do
            if not found[mob] and not mobs[mob] then mobs[mob] = prog end
        end
        local m = mobInText(t)
        local lower = t:lower()
        local giverText = lower:find("quest giver", 1, true) ~= nil
        -- A text about a giver does not tell us which mob to hunt.
        if m and not giverText and (not mentioned or #m > #mentioned) then mentioned = m end
        if lower:find("complete", 1, true) then saysComplete = true end
        if lower:find("return to", 1, true) then saysReturn = true end
    end
    if not mentioned and not saysComplete and not saysReturn and next(mobs) == nil then return nil end

    -- Hunt the mob the quest still needs the most of.
    local target, worst = nil, 2
    local allDone = next(mobs) ~= nil
    -- Sorted names keep the choice stable when two mobs are equally far from done.
    local names = {}
    for mob in pairs(mobs) do table.insert(names, mob) end
    table.sort(names)
    for _, mob in ipairs(names) do
        local prog = mobs[mob]
        local ratio
        if prog.remaining then
            -- the number is what is left, so zero left means the quest is done
            ratio = prog.total > 0 and 0 or 1
        else
            ratio = prog.total > 0 and (prog.count / prog.total) or 0
        end
        if ratio < 1 then allDone = false end
        if ratio < worst then worst, target = ratio, mob end
    end
    if next(mobs) == nil then target = mentioned end

    -- With progress on screen the counters decide, not the word "complete".
    local complete = saysComplete
    if next(mobs) ~= nil then complete = allDone end
    -- "Return to the giver" only ends a quest that shows no counters left.
    if saysReturn and next(mobs) == nil then complete = true end

    -- The giver we need is the one for the mob we are actually hunting.
    if target and mobs[target] then mentioned = target end

    return {
        mobs = mobs,
        mentioned = mentioned,
        target = target,
        complete = complete,
        -- Any sign that a quest is running means: do not ask for it again.
        -- Asking again can wipe the progress we already made.
        confirmed = next(mobs) ~= nil or mentioned ~= nil or saysReturn or saysComplete,
    }
end

local function tryAcceptQuest(info)
    local now = tick()

    -- A running quest is confirmed by the panel; leave it alone. The panel
    -- of the game blinks while it updates, so the confirmation is kept a
    -- moment longer: asking again in the middle of that would throw the
    -- quest we just got away.
    if info and info.confirmed then
        state.questSeenUntil = now + 1
        return
    end
    if now < (state.questSeenUntil or 0) then return end

    if now - state.lastQuestTry < 2 then return end

    -- A quest that is finished but not handed in must not be replaced: the
    -- game would drop the progress we just made.
    if state.questDone then return end

    local q = questFor(getMyLevel())
    if not q then
        dbg("No quest bracket for this level")
        return
    end

    -- A new quest needs a fresh set of ids to try. The level is part of the
    -- key: a new level means a new quest.
    local key = questKey(q) .. "@" .. tostring(getMyLevel())
    if state.questTryKey ~= key then
        state.questTryKey = key
        state.questTried = {}
        state.questIndexTry = nil
        state.questGaveUp = false
    end

    -- We asked for a quest and the game never answered: it did not take it.
    -- Try another id of the same quest before walking to a giver.
    if state.questAsked and not state.questVerified then
        if now - state.questAskedAt < 6 then return end
        local nextIndex = nextQuestIndex(q, getMyLevel(), state.questTried)
        if nextIndex then
            dbg("The game did not take " .. state.questAsked .. " #" .. tostring(state.questIndexTry))
            state.questIndexTry = nextIndex
            state.currentQuest = nil
            state.questAskedAt = now
        else
            dbg("The game took no quest of this level, asking a giver")
            state.questGaveUp = true
            state.currentQuest = nil
            return
        end
    end
    if state.questGaveUp then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then dbg("CommF_ remote missing"); return end

    -- The quest is asked for right here: walking to the giver first only
    -- wastes time, the game takes the quest from anywhere.
    -- The index is the id the game gave to this quest at this level.
    local index = state.questIndexTry or q.index

    -- The game wants to know where we respawn before it gives the quest.
    -- While the bypass is running, the game has to keep the island it got.
    if not state.bypassBusy then
        pcall(function() commF:InvokeServer("SetLastSpawnPoint", "Town") end)
    end
    -- An old quest has to go first, the game does the same when the player
    -- takes a new quest from the giver.
    if questRemoteState then
        pcall(function() commF:InvokeServer("AbandonQuest") end)
    end
    local ok, err = pcall(function() commF:InvokeServer("StartQuest", q.name, index) end)
    state.currentQuest = q.name .. "#" .. tostring(index)
    state.questSentAt = tick() -- measured after the call, not before
    state.lastQuestTry = now
    state.questAsked = q.name
    state.questNpc = q.npc
    state.questPos = q.pos
    state.questAskedAt = tick()
    state.questVerified = false
    state.questIndexTry = index
    state.questTried[index] = true
    if ok then
        dbg("Quest sent: " .. q.name .. " #" .. index)
    else
        dbg("Quest FAIL: " .. tostring(err))
    end
end

-- Quest givers are models named like "Bandit Quest Giver".
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

-- The giver for this mob; "Bandit" must not pick the "Bandit Captain" giver.
-- With a mob name only a giver for that mob is used, never a random one.
-- The name of the giver from the guide of the game is used first.
local function pickQuestGiver(mobName, npcName)
    local root = getRoot()
    if not root then return nil end
    local best, bestD, exact, exactD, named, namedD = nil, math.huge, nil, math.huge, nil, math.huge
    for _, npc in ipairs(questGivers()) do
        local anchor = anchorOf(npc)
        if anchor then
            local d = (root.Position - anchor.Position).Magnitude
            local n = npc.Name:lower()
            -- The guide of the game names the giver ("Pirate Giver"); the
            -- model of the game has the name in it ("Pirate Quest Giver").
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

-- The npc that keeps the fruit storage. Used when the fruit menu of the
-- game has no store button.
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

-- Talk to a quest giver; the executor global fires the prompt instantly.
local function interactWith(obj, prompt)
    prompt = prompt or promptOf(obj)
    if not prompt then return false end
    local now = tick()
    if state.lastPrompt == prompt and now - state.promptAt < 3 then return true end
    state.lastPrompt, state.promptAt = prompt, now
    if fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function()
            prompt:InputHoldBegin()
            if task.delay then
                task.delay(prompt.HoldDuration or 1, function() prompt:InputHoldEnd() end)
            end
        end)
    end
    return true
end

-- ================= ENEMIES =================
-- Enemy names can carry a suffix ("Bandit [lvl 8]"), so match on the base name.
local function mobKey(name)
    local base = name
    -- the game labels its mobs "Lv. 30 Bandit" or "Bandit (Lv. 30)"
    base = base:gsub("^Lv%.%s*%d+%s*", "")
    local cut = base:find("%s*%[")
    if cut then base = base:sub(1, cut - 1) end
    cut = base:find("%s*%(")
    if cut then base = base:sub(1, cut - 1) end
    base = base:gsub("^%s+", ""):gsub("%s+$", "")
    return base
end

local function startsWithCI(a, b) return a:lower():sub(1, #b) == b:lower() end

-- An exact mob-name match always wins over a looser one, so the "Bandit"
-- quest never locks onto a "Bandit Captain".
local function pickBest(candidates, mobName, origin)
    local exact, exactD = nil, math.huge
    local loose, looseD = nil, math.huge
    for _, obj in ipairs(candidates) do
        local anchor = anchorOf(obj)
        if anchor then
            local d = (origin.Position - anchor.Position).Magnitude
            -- the display name of the game carries the level of the mob
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

-- Mobs that stop taking damage are ignored for a while.
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
            if hum and hum.Health > 0 and (not stuck or stuck < now) then
                table.insert(list, e)
            end
        end
    else
        -- Fallback for builds that drop enemies straight into the world.
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model") and not child.Name:lower():find("quest", 1, true) then
                local hum = child:FindFirstChildOfClass("Humanoid")
                local stuck = stuckTargets[child]
                if hum and hum.Health > 0 and (not stuck or stuck < now) then
                    table.insert(list, child)
                end
            end
        end
    end
    enemyCache, enemyCacheAt = list, now
    return list
end

-- No radius limit: the old version only found mobs already in attack range,
-- so the player never travelled to them.
local function getTarget(mobName)
    local root = getRoot()
    if not root then return nil end
    return pickBest(collectEnemies(tick()), mobName, root)
end

-- Mobs far away aren't loaded, so head to their spawn point first.
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

-- Mobs of another player must not be moved: the game owns them.
local function ownedByOther(part)
    local chars = Workspace:FindFirstChild("Characters")
    if not chars then return false end
    for _, c in ipairs(chars:GetChildren()) do
        if c ~= LocalPlayer.Character then
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - part.Position).Magnitude <= 300 then return true end
        end
    end
    return false
end

-- Bring the mobs of one kind to the player. The game puts a mob back when
-- it does not belong to us, so that one is left alone from then on.
local function bringMob(target, root)
    local anchor = anchorOf(target)
    if not anchor then return end
    local now = tick()

    -- A mob the server put back is not ours to move. The mark is taken away
    -- after a while, so the mob is tried once more.
    for _, mob in ipairs(collectEnemies(now)) do
        local marker = mob:FindFirstChild("Ignored")
        if marker and not state.bringIgnored[mob] then
            -- the game marked the mob on its own
            state.bringIgnored[mob] = now
        end
    end
    for mob, at in pairs(state.bringIgnored) do
        if now - at > 60 then
            local marker = mob:FindFirstChild("Ignored")
            if marker then pcall(function() marker:Destroy() end) end
            state.bringIgnored[mob] = nil
        end
    end
    for mob, at in pairs(state.bringMoved) do
        if now - at > 2.5 then
            state.bringMoved[mob] = nil
            local part = anchorOf(mob)
            if part and (part.Position - root.Position).Magnitude > CONFIG.BringMobRange * 2 then
                -- the game sent the mob back: it does not belong to us
                state.bringIgnored[mob] = now
                if not mob:FindFirstChild("Ignored") then
                    Instance.new("IntValue", mob).Name = "Ignored"
                end
            end
        end
    end

    local dx = root.Position.X - anchor.Position.X
    local dz = root.Position.Z - anchor.Position.Z
    -- Only a mob that is already close is dragged over. A mob far away has
    -- to be walked to first.
    if math.sqrt(dx * dx + dz * dz) > CONFIG.BringMobRange then return end
    if now < (state.bringAt or 0) then return end -- do not spam the write
    state.bringAt = now + 0.2

    -- A mob the server refused before is left alone.
    if target:FindFirstChild("Ignored") then return end

    -- A mob of another player belongs to that player.
    if ownedByOther(anchor) then
        dbg("The mob belongs to another player")
        return
    end

    -- The target mob first, then the ones of the same kind close by.
    local list = {target}
    local count = CONFIG.BringMobCount or 1
    local key = mobKey(target.Name)
    if count > 1 then
        local near = {}
        for _, mob in ipairs(collectEnemies(now)) do
            if mob ~= target and not mob:FindFirstChild("Ignored")
                and mobKey(mob.Name) == key then
                local part = anchorOf(mob)
                local hum = mob:FindFirstChildOfClass("Humanoid")
                -- The hub looks for the mobs around the target, not around
                -- the player, so a group of mobs is brought over whole.
                if part and hum and hum.Health > 0 and not ownedByOther(part)
                    and (part.Position - anchor.Position).Magnitude <= CONFIG.BringMobSearch then
                    table.insert(near, {mob = mob, dist = (part.Position - anchor.Position).Magnitude})
                end
            end
        end
        -- The mobs closest to the target come first.
        table.sort(near, function(a, b) return a.dist < b.dist end)
        for _, entry in ipairs(near) do
            if #list >= count then break end
            table.insert(list, entry.mob)
        end
    end

    for _, mob in ipairs(list) do
        local part = anchorOf(mob)
        if part then
            -- Freeze the mob, so it cannot fight back while it is dragged over.
            local hum = mob:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function() hum.PlatformStand = true end)
                pcall(function() hum.Sit = true end)
            end
            pcall(function() part.CanCollide = false end)
            -- Keep the mob's own height so it stays on the ground it spawned on.
            local goal = Vector3.new(root.Position.X, part.Position.Y, root.Position.Z)
            pcall(function() part.CFrame = CFrame.new(goal) end)
            state.bringMoved[mob] = now
        end
    end
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
        if dist < 6 then -- close enough: snap so we stick to moving mobs
            stopTween()
            root.CFrame = cf
            return
        end
        -- Don't rebuild the tween every frame if the goal barely moved
        if activeTween and tweenGoal and (tweenGoal.Position - cf.Position).Magnitude < 3
            and activeTween.PlaybackState == Enum.PlaybackState.Playing then
            return
        end
        if activeTween then activeTween:Cancel() end
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
-- Noclip while farming so we don't get snagged or fall through the tween.
-- Collision is restored as soon as farming stops, otherwise the character
-- sinks through the map.
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
            -- Tools and accessories added later must not snag the character.
            noclipConn = char.DescendantAdded:Connect(function(obj)
                if obj:IsA("BasePart") then
                    table.insert(noclipParts, {part = obj, original = obj.CanCollide})
                    if state.farming then obj.CanCollide = false end
                end
            end)
        end
    end
    for _, entry in ipairs(noclipParts) do
        local p = entry.part
        if p.Parent and p.CanCollide then p.CanCollide = false end
    end
end

RunService.Stepped:Connect(function()
    -- An error here would disconnect the handler for the rest of the session.
    pcall(function()
        local root = getRoot()
        -- Noclip only matters while farming; fruit sniping alone must not leave
        -- the player gliding through the map.
        if not CONFIG.AutoFarm or not state.farming or not state.enabled or not root then
            if #noclipParts > 0 then restoreNoclip() end
            return
        end
        applyNoclip()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end)

-- The camera shake makes the position tracking noisy.
local function stopCameraShaker()
    local util = ReplicatedStorage:FindFirstChild("Util")
    local shaker = util and util:FindFirstChild("CameraShaker")
    if not shaker then return false end
    local ok = pcall(function() require(shaker):Stop() end)
    return ok
end

-- ================= ATTACK =================
-- Blox Fruits runs the swing through Roblox's combat framework. That
-- framework has its own cooldown and a small hitbox, so a fast attack is
-- simply ignored and the swing misses. Opening it up is what makes the
-- weapon land.
local combatController

local function getCombatController()
    if combatController then return combatController end
    local ps = LocalPlayer and LocalPlayer.PlayerScripts
    if not ps then return nil end
    local mod = ps:FindFirstChild("CombatFramework")
    if not mod then return nil end
    local ok, cf = pcall(require, mod)
    if not ok or not cf then return nil end
    local ctrl = nil
    pcall(function() ctrl = cf:GetActiveController() end)
    if not ctrl then pcall(function() ctrl = cf.activeController end) end
    combatController = ctrl
    return combatController
end

-- Remove the cooldown and enlarge the melee hitbox.
local function fastAttack()
    local ctrl = getCombatController()
    if not ctrl then return false end
    local ok = pcall(function()
        ctrl.attacking = false
        ctrl.blocking = false
        ctrl.timeToNextAttack = tick() - 1
        ctrl.timeToNextBlock = 0
        ctrl.increment = 3
        ctrl.hitboxMagnitude = CONFIG.HitboxMagnitude or 120
    end)
    -- A stun stops the character from swinging at all.
    local char = LocalPlayer.Character
    local stun = char and char:FindFirstChild("Stun")
    if stun then pcall(function() stun.Value = 0 end) end
    return ok
end

-- The game keeps track of the weapon state itself: whether the weapon can
-- swing right now and how long the swing takes.
local function combatUtilModule()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local util = modules and modules:FindFirstChild("CombatUtil")
    if not util then return nil end
    local ok, combatUtil = pcall(require, util)
    if not ok or not combatUtil then return nil end
    return combatUtil
end

-- The game tells us how long the swing animation lasts. The server uses
-- that number to time the hit, so a fixed number is only right at normal
-- attack speed.
local function attackAnimLength(tool)
    local combatUtil = combatUtilModule()
    if not combatUtil or not tool then return 0.5 end
    local length = 0.5
    pcall(function()
        local weaponName = combatUtil:GetWeaponName(tool)
        local cache = combatUtil:GetMovesetAnimCache(weaponName)
        local pure = combatUtil:GetPureWeaponName(weaponName)
        local track = cache and cache[pure .. "-basic1"]
        if track then
            local speed = track:GetAttribute("SpeedMult") or 1
            if track.Length and speed > 0 then length = track.Length / speed end
        end
    end)
    return length
end

-- The game says when the weapon may not swing yet. Swinging anyway only
-- wastes the attack, the server throws it away.
local function canAttack(tool)
    local combatUtil = combatUtilModule()
    if not combatUtil or not tool then return true end
    local allowed = true
    pcall(function()
        local weaponName = combatUtil:GetWeaponName(tool)
        local data = combatUtil:GetWeaponData(weaponName)
        local weaponType = (data and data.WeaponType) or "Melee"
        allowed = combatUtil:CanAttack(LocalPlayer.Character, weaponType)
    end)
    return allowed ~= false
end

-- The game sends the swing itself through two remotes. Firing them is what
-- really hits: on a phone there is no mouse click to do it for us.
local function remoteAttack(target, tool)
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    if not net then return false end
    local regAttack = net:FindFirstChild("RE/RegisterAttack")
    local regHit = net:FindFirstChild("RE/RegisterHit")
    if not regAttack or not regHit then return false end
    local part = nil
    if target then
        part = target:FindFirstChild("RightHand")
            or target:FindFirstChild("Head")
            or anchorOf(target)
    end
    if not part then return false end
    local id = nil
    pcall(function() id = regAttack:FireServer(attackAnimLength(tool), 1) end)
    if type(id) ~= "string" then
        state.attackId = (state.attackId or 0) + 1
        id = string.format("%08x", state.attackId)
    end
    pcall(function() regHit:FireServer(part, {}, nil, id) end)
    return true
end

local function doAttack(tool, target)
    if CONFIG.FastAttack then fastAttack() end
    -- A stunned character cannot swing at all.
    local char = LocalPlayer.Character
    local stun = char and char:FindFirstChild("Stun")
    local stunned = false
    pcall(function() stunned = (stun and stun.Value and stun.Value ~= 0) end)
    if stunned then return false end
    -- The game may forbid the swing right now.
    if not canAttack(tool) then return false end
    -- The remote is the real swing; the tool is only the fallback.
    if CONFIG.RemoteAttack and remoteAttack(target, tool) then return true end
    local ok = pcall(function() tool:Activate() end)
    return ok
end

-- The mob closest to us that our weapon can reach. The flat distance
-- counts: the bot hovers above the mob on purpose.
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

-- Swing at whatever mob is closest, even when the quest points somewhere
-- else. This is the plain auto attack: keep the weapon moving.
local function autoAttackSwing(current)
    local now = tick()
    if now - state.lastAttack < CONFIG.AttackCooldown then return false end
    local tool = equipWeapon()
    -- A fruit is food, not a weapon: swinging with it would eat it.
    if not tool or isFruit(tool) then return false end
    local root = getRoot()
    if not root then return false end
    local reach = attackRange(tool)
    local best = mobInReach(root, reach)
    if not best then return false end
    if doAttack(tool, best) then
        state.lastAttack = now
        if best ~= current then state.status = "Attacking " .. best.Name end
        return true
    end
    return false
end

-- ================= FRUIT =================
-- Folders worth looking inside for dropped fruit.
local FRUIT_FOLDERS = {"fruit", "item", "drop", "loot", "spawn", "pickup"}

local function inContainerName(name)
    local n = name:lower()
    for _, f in ipairs(FRUIT_FOLDERS) do
        if n:find(f, 1, true) then return true end
    end
    return false
end

-- The part of a tool that carries it; the handle is not always named "Handle".
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

-- A fruit we failed to grab is retried after a while instead of lost forever.
local function recentlyFailed(obj, now)
    local t = grabbedFruits[obj]
    return t ~= nil and (now - t) < 90
end

local function scanFruits(root, now)
    local best, bestD = nil, CONFIG.FruitScanRadius
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    local function consider(obj)
        if not obj or recentlyFailed(obj, now) then return end
        if not isFruitTool(obj) then return end
        if char and obj:IsDescendantOf(char) then return end
        if backpack and obj:IsDescendantOf(backpack) then return end
        local parent = obj.Parent
        if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
            return -- a fruit that belongs to a mob or player model
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

-- How many tools we carry; a pickup adds one, a fruit that merely despawned
-- does not.
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

-- Every tool we own right now, as a set of instances.
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

-- The tool that showed up since the snapshot was taken. Only fruits count:
-- a quest reward or a weapon drop must not be eaten.
local function newTool(before)
    if not before then return nil end
    for t in pairs(ownedTools()) do
        if not before[t] and isFruit(t) then return t end
    end
    return nil
end

-- A fruit tool by name, in the character or in the backpack.
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

-- Click a button in the game's own user interface. The fruit menu of the
-- game is what really eats and stores a fruit, the tool alone does not.
local function useFruitMenu(fruitName, actions)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local function press(d)
        pcall(function() d.MouseButton1Click:Fire() end)
        -- Some menus listen to Activated instead of the click.
        pcall(function() d.Activated:Fire() end)
    end
    -- A hidden button belongs to a closed window: clicking it does nothing.
    local function shown(d) return d.Visible ~= false end
    -- First open the slot of the fruit, then the action button.
    if fruitName then
        local want = fruitName:lower()
        local compact = want:gsub("%s", "")
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and shown(d) then
                local text = (d.Text or ""):lower()
                local nm = (d.Name or ""):lower()
                if text == want or nm:find(compact, 1, true) then
                    press(d)
                    break
                end
            end
        end
        task.wait(0.2)
    end
    for _, action in ipairs(actions) do
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and shown(d) then
                local text = ((d.Text or "") .. " " .. (d.Name or "")):lower()
                -- Whole word only: "eat" must not match "heat" or "use".
                if text:find("%f[%w]" .. action .. "%f[^%w]") then
                    press(d)
                    return true
                end
            end
        end
    end
    -- No action button: the slot alone is not eating or storing.
    return false
end

-- The fruit tools we carry around.
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


-- Eat the fruit we just picked up: equip it and activate it for the buff.
-- The game menu is tried as well, because the tool alone often does nothing.
local function eatFruit(tool)
    local char = LocalPlayer.Character
    local hum = getHumanoid()
    if not tool or not char or not hum then return false end
    local name = tool.Name
    if tool.Parent ~= char then
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.1)
    end
    if tool.Parent ~= char then
        dbg("Could not equip " .. tool.Name)
        return false
    end
    pcall(function() tool:Activate() end)
    -- The real way: the eat button of the fruit menu.
    if useFruitMenu(name, {"eat"}) then
        dbg("Ate " .. name .. " from the menu")
        return true
    end
    -- The tool alone does not eat the fruit, so say so instead of pretending.
    dbg("No eat button for " .. name)
    return false
end

-- Put a fruit into the game storage. Uses the fruit menu, and falls back to
-- the storage npc when the menu has no store button.
local function storeFruit(tool)
    if not tool then return false end
    if useFruitMenu(tool.Name, {"store", "deposit", "stash"}) then
        -- The caller counts the fruits that really left the backpack.
        dbg("Asked the game to store " .. tool.Name)
        return true
    end
    return false
end

local function fruitWasTaken(fruit)
    local p = fruit.Parent
    if p == nil then
        -- The world fruit is gone: only a pickup when we gained a tool.
        return toolCount() > state.fruitToolCount
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack and fruit:IsDescendantOf(backpack) then return true end
    local char = LocalPlayer.Character
    if char and fruit:IsDescendantOf(char) then return true end
    return false
end

-- The fruit was really picked up: count it and eat it when asked to.
local function confirmFruitPickup(fruit)
    state.fruitsFound += 1
    local name = fruit.Name
    local tool = newTool(state.fruitTools) or findFruitTool(name)
    state.fruit = nil
    state.fruitTries = 0
    state.fruitTools = nil
    dbg("Picked up " .. name)
    if CONFIG.EatFruit and tool then
        -- The fruit may stay uneaten, but the hand must hold a weapon again.
        eatFruit(tool)
        equipWeapon()
    end
    return true
end

-- Returns true while it's busy handling a fruit (so farming pauses).
local function handleFruit(root)
    local now = tick()

    if now - state.lastFruitScan >= 1.5 and not state.fruit then
        state.lastFruitScan = now
        local best = scanFruits(root, now)
        if best then
            state.fruit, state.fruitStart, state.fruitTries = best, now, 0
            state.fruitLastTry = 0
            state.fruitToolCount = toolCount()
            state.fruitTools = ownedTools()
            dbg("Fruit spotted: " .. best.Name)
        end
    end

    local fruit = state.fruit
    if not fruit then return false end

    local handle = fruit.Parent and toolPart(fruit)
    if not handle then
        -- The fruit left the world: it was picked up when we gained a tool.
        if fruitWasTaken(fruit) then confirmFruitPickup(fruit) end
        state.fruit = nil
        state.fruitTools = nil
        return false
    end

    state.status = "Fruit: " .. fruit.Name
    moveTo(handle.CFrame)

    if (root.Position - handle.Position).Magnitude < 8 then
        -- Space the attempts out so the server has time to register a pickup.
        if now - state.fruitLastTry >= CONFIG.FruitTouchInterval then
            state.fruitLastTry = now
            pcall(function()
                if firetouchinterest then
                    firetouchinterest(root, handle, 0)
                    firetouchinterest(root, handle, 1)
                end
            end)
            state.fruitTries = state.fruitTries + 1
            if fruitWasTaken(fruit) then
                confirmFruitPickup(fruit)
            elseif state.fruitTries >= CONFIG.FruitPickupTries then
                grabbedFruits[fruit] = now -- retry later instead of losing it
                state.fruit = nil
                state.fruitTries = 0
                state.fruitTools = nil
                dbg("Could not pick up " .. fruit.Name)
            end
        end
    elseif now - state.fruitStart > 20 then
        grabbedFruits[fruit] = now
        state.fruit = nil
        state.fruitTries = 0
        state.fruitTools = nil
        dbg("Gave up on " .. fruit.Name)
    end
    return true
end

-- ================= STATS =================
-- The game gives stat points for quests and dailies. The points are spent
-- on melee, sword, gun, defense and the energy of the fruit.
local STAT_LIST = {"Melee", "Defense", "Sword", "Gun", "Demon Fruit"}
local STAT_MAX = 2800
-- The panel says "Fruit", the game calls the stat "Demon Fruit".
local STAT_TARGETS = {
    Melee = "Melee",
    Sword = "Sword",
    Gun = "Gun",
    Fruit = "Demon Fruit",
    Defense = "Defense",
    All = "All",
}

-- The data of the player. The game keeps it in a table, the test harness
-- uses an instance; both have to work.
-- Every place the game could keep the data of the player in: an instance
-- inside the player or a table on the player.
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

-- A value of the data of the player, no matter how it is stored.
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

-- The value of a value object of the game.
local function valueOf(obj)
    if type(obj) == "string" then return obj end
    if type(obj) == "number" then return obj end
    if obj then
        local ok, value = pcall(function() return obj.Value end)
        if ok then return value end
    end
    return nil
end

-- The level of a stat of the character, nil when the game does not say it.
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

-- The stat points the player has.
local function statPoints()
    return tonumber(valueOf(dataValue("Points"))) or 0
end

-- Spend the stat points of the game on the stats we want.
local function tryUpgradeStats()
    if not CONFIG.AutoStats then return end
    local now = tick()
    if now - (state.statAt or 0) < (CONFIG.AutoStatWait or 3) then return end
    local wanted = STAT_TARGETS[CONFIG.AutoStatTarget] or CONFIG.AutoStatTarget
    local targets = {}
    if wanted == "All" then
        for _, stat in ipairs(STAT_LIST) do targets[stat] = true end
    else
        targets[wanted] = true
    end
    -- The points are needed for every stat.
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
                if ok then
                    state.statAt = now
                    dbg("Stat up: " .. stat)
                    return
                end
            end
        end
    end
end

-- ================= TRAVEL =================
-- The three worlds of the game. The game moves the player to them.
local WORLD_TRAVEL = {"TravelMain", "TravelDressrosa", "TravelZou"}

local function travelToWorld(world)
    local what = WORLD_TRAVEL[world]
    if not what then return false end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then return false end
    local ok = pcall(function() commF:InvokeServer(what) end)
    if ok then
        dbg("Travelling to world " .. tostring(world))
        return true
    end
    dbg("The game did not take the travel to world " .. tostring(world))
    return false
end

-- The place of a model in the world.
local function modelCFrame(model)
    local ok, cf = pcall(function() return model:GetModelCFrame() end)
    if ok and cf then return cf end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.CFrame end
    return model.CFrame
end

-- The spawn points of the game and the island they belong to. The game
-- keeps the spawn point of the player, so the player can be sent to an
-- island by saving that point and letting the character die.
local islandSpawns, islandSpawnsAt = {}, -999

local function loadIslandSpawns()
    islandSpawns = {}
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    local spawns = origin and origin:FindFirstChild("PlayerSpawns")
    if not locations or not spawns then return end
    local points = {}
    for _, folder in ipairs(spawns:GetChildren()) do
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                table.insert(points, {name = model.Name, cf = modelCFrame(model)})
            end
        end
    end
    if #points == 0 then return end
    for _, island in ipairs(locations:GetChildren()) do
        if island:IsA("BasePart") then
            local mesh = island:FindFirstChildWhichIsA("SpecialMesh")
            local scale = mesh and mesh.Scale.X or 1
            local radius = island.Size.X * scale / 2
            local list = {}
            for _, p in ipairs(points) do
                if (p.cf.Position - island.Position).Magnitude <= radius then
                    table.insert(list, p)
                end
            end
            if #list > 0 then islandSpawns[island.Name] = list end
        end
    end
    islandSpawnsAt = tick()
end

-- The spawn point that is closest to a place on the map.
local function spawnNear(position)
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    if not locations then return nil end
    local best, bestD = nil, nil
    for _, island in ipairs(locations:GetChildren()) do
        local list = islandSpawns[island.Name]
        if list and island:IsA("BasePart") then
            local mesh = island:FindFirstChildWhichIsA("SpecialMesh")
            local scale = mesh and mesh.Scale.X or 1
            local radius = island.Size.X * scale / 2
            if radius >= (position - island.Position).Magnitude then
                for _, p in ipairs(list) do
                    local d = (p.cf.Position - position).Magnitude
                    if bestD == nil or d < bestD then best, bestD = p.name, d end
                end
            end
        end
    end
    return best
end
-- ================= FAST ISLAND BYPASS (FIXED) =================
local function fastBypassToIsland(spawnName, targetPos)
    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum then return false end
    
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then return false end
    
    -- 1. วาร์ปตัวละครไปยืนใกล้จุดเกิดเป้าหมายจริงๆ ก่อน (แก้ปัญหาเกมเช็คระยะทาง)
    if targetPos then
        root.CFrame = CFrame.new(targetPos + Vector3.new(0, 5, 0))
        task.wait(0.3) -- รอให้เกมโหลดและซิงค์ตำแหน่งกับเซิร์ฟเวอร์
    end
    
    local char = LocalPlayer.Character
    local marker = char and char:FindFirstChild("LastSpawnPoint")
    if marker then pcall(function() marker.Disabled = true end) end
    
    -- 2. ส่งรีโมทเซ็ตจุดเกิด (ตอนนี้อยู่ใกล้แล้ว เซิร์ฟเวอร์จะยอมรับ 100%)
    local ok = pcall(function() commF:InvokeServer("SetLastSpawnPoint", spawnName) end)
    if not ok then
        if marker then pcall(function() marker.Disabled = false end) end
        return false
    end
    dbg("Set spawn point success: " .. tostring(spawnName))
    
    -- 3. เช็คยืนยันค่าจากดาต้าตัวละคร
    local deadline = tick() + 2
    local taken = false
    while tick() < deadline do
        local current = valueOf(dataValue("LastSpawnPoint"))
        if current == nil or current == spawnName then
            taken = true
            break
        end
        task.wait(0.05)
    end
    
    -- 4. สั่งฆ่าตัวตายเพื่อให้เกิดใหม่ที่เกาะเป้าหมาย
    hum.Health = 0
    
    deadline = tick() + 15
    while tick() < deadline do
        local alive = getHumanoid()
        if alive and alive.Health > 0 then break end
        task.wait(0.2)
    end
    
    if marker then pcall(function() marker.Disabled = false end) end
    dbg("Successfully bypassed to: " .. tostring(spawnName))
    -return true
end

-- Send the player to an island. The flag has to go away even when the game
-- throws, so the work is wrapped and the flag is cleared after it.
local function spawnBypassTo(position)
    if not (position and position.X and position.Y and position.Z) then return false end
    if state.bypassBusy then return false end
    state.bypassBusy = true
    local ok, result = pcall(function()
        if tick() - islandSpawnsAt > 30 then loadIslandSpawns() end
        local name = spawnNear(position)
        if not name then
            -- ถ้าหาชื่อจุดเกิดไม่เจอ ให้ใช้พิกัดตรงนั้นเป็นจุดเซ็ตสปอว์นสำรอง
            name = "Cafe" -- หรือใช้ชื่อเกาะใกล้เคียง
        end
        -- ส่งพิกัดเป้าหมายเข้าไปวาร์ปยืนยันตัวตนก่อนเซ็ตจุดเกิด
        return fastBypassToIsland(name, position)
    end)
    state.bypassBusy = false
    if not ok then
        dbg("The jump to the island failed: " .. tostring(result))
        return false
    end
    return result
end


-- The islands of the game. The game keeps them in the map of the world and
-- in the places of the world itself.
local function islandPositions()
    local list = {}
    local known = {}
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
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Cross a door with the remote of the game. The player has to stand at the
-- door, then the game sends it to the other side. This is the second way
-- the big scripts cross the sea.
local function portalBypass(targetPos)
    local root = getRoot()
    if not root then return false end
    -- the doors of the game: models with a prompt that says so
    local door, bestD = nil, 800
    local function scan(container, depth)
        if depth > 2 then return end
        for _, obj in ipairs(container:GetChildren()) do
            local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
            local text = ""
            if prompt then
                text = ((prompt.ActionText or "") .. " " .. (prompt.ObjectText or "") .. " " .. obj.Name):lower()
            end
            if prompt and (text:find("door", 1, true) or text:find("gate", 1, true)
                or text:find("entrance", 1, true) or text:find("portal", 1, true)
                or text:find("teleport", 1, true)) then
                local anchor = anchorOf(obj)
                if anchor then
                    local d = (root.Position - anchor.Position).Magnitude
                    if d < bestD then door, bestD = anchor, d end
                end
            elseif obj:IsA("Model") or obj:IsA("Folder") then
                scan(obj, depth + 1)
            end
        end
    end
    scan(Workspace, 0)
    local npcs = Workspace:FindFirstChild("NPCs")
    if npcs then scan(npcs, 0) end
    if not door then return false end

    -- stand at the door
    local before = (root.Position - targetPos).Magnitude
    if (root.Position - door.Position).Magnitude > 12 then
        moveTo(CFrame.new(door.Position + Vector3.new(0, 3, 0)))
        local deadline = tick() + 10
        while tick() < deadline do
            local now = getRoot()
            if not now then break end
            if (now.Position - door.Position).Magnitude <= 12 then break end
            task.wait(0.2)
        end
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then return false end
    local ok = pcall(function() commF:InvokeServer("requestEntrance", door.Position) end)
    if not ok then return false end
    -- the game moves the player: give it a moment
    local deadline = tick() + 2
    while tick() < deadline do
        local now = getRoot()
        if now and (now.Position - targetPos).Magnitude < before - 50 then return true end
        task.wait(0.2)
    end
    return false
end

-- Travel to a place. A long way is too slow with a tween, so the game is
-- asked to put the player on that island instead.
local function travelTo(cf)
    local root = getRoot()
    if not root then return false end
    local dist = (root.Position - cf.Position).Magnitude
    if CONFIG.SpawnBypass and dist > (CONFIG.BypassDistance or 2500) then
        if tick() - islandSpawnsAt > 30 then loadIslandSpawns() end
        local name = spawnNear(cf.Position)
        if name then
            dbg("Far away (" .. tostring(math.floor(dist)) .. " studs): fast bypass")
            -- The bypass runs in the background: the main loop keeps going.
            if not state.bypassBusy then
                state.bypassBusy = true
                task.spawn(function()
                    local ok, err = pcall(fastBypassToIsland, name)
                    state.bypassBusy = false
                    if not ok then dbg("The bypass failed: " .. tostring(err)) end
                end)
            end
            return true
        end
    end
    moveTo(cf)
    return false
end

-- ================= MAIN LOOP =================
local function step()
    local root, hum = getRoot(), getHumanoid()
    local now = tick()
    if not root or not hum or hum.Health <= 0 then
        state.farming = false
        state.status = "Respawning..."
        state.lastSafe = nil
        state.lastPos = nil
        state.movedAt = 0
        return
    end

    -- The game puts the camera shake back every now and then.
    if state.shakerAt == nil or now - state.shakerAt > 30 then
        state.shakerAt = now
        stopCameraShaker()
    end

    -- Recover if noclip or a bad tween dropped us under the map.
    if root.Position.Y < CONFIG.SafeY and now >= state.recoverUntil then
        local y = root.Position.Y
        stopTween()
        restoreNoclip()
        state.recoverUntil = now + 2
        state.status = "Recovering..."
        if state.lastSafe then
            root.CFrame = CFrame.new(state.lastSafe)
            dbg(string.format("Recovered from out-of-bounds (Y=%.0f)", y))
        else
            dbg(string.format("Out of bounds (Y=%.0f), no safe spot yet", y))
        end
        return
    end

    -- A safe spot is only a place the bot actually worked at, so falling into
    -- the void can never turn into the position we recover to.
    if not state.lastPos or (root.Position - state.lastPos).Magnitude > 1 then
        state.lastPos = root.Position
        state.movedAt = now
    end
    if now - state.movedAt > 0.4 and root.Position.Y > CONFIG.SafeY then
        state.lastSafe = root.Position
    end

    if CONFIG.FruitSniper then
        state.farming = true
        if handleFruit(root) then return end
    end

    -- The panel knows the real quest, its progress and whether it is done.
    local info = CONFIG.AutoQuest and questPanelInfo() or nil

    -- The remote of the game is the better source: it counts the kills even
    -- when the panel is hidden or shows something else.
    if CONFIG.AutoQuest then
        hookQuestRemote()
        local remoteInfo = remoteQuestInfo()
        if remoteInfo then info = remoteInfo end
    end
    hookHitRemote()
    hookStatsRemote()

    -- Remember a finished quest. The panel of the game hides itself once the
    -- quest is done, and without this the bot would ask for a new quest and
    -- throw the finished one away.
    if info then
        if info.complete then
            state.questDone = true
            state.questDoneMob = info.mentioned or info.target
        elseif info.confirmed then
            state.questDone = false
            state.questDoneMob = nil
        end
    end

    -- Put the fruits we carry into the game storage. The menu of the game
    -- does the real work, the storage npc is the fallback.
    if CONFIG.AutoStore and now - (state.storeAt or 0) > 5 then
        local fruits = carriedFruits()
        if #fruits >= (CONFIG.StoreFruitMin or 3) then
            state.storeAt = now
            local before = #fruits
            local stored = 0
            -- A few fruits per pass, so the bot is not busy storing all the
            -- time.
            for _, f in ipairs(fruits) do
                if stored >= 4 then break end
                if storeFruit(f) then stored += 1 end
            end
            -- Only the fruits that really left the backpack count.
            stored = before - #carriedFruits()
            if stored > 0 then
                state.status = "Stored " .. stored .. " fruit(s)"
                dbg("Stored " .. stored .. " fruit(s)")
            else
                local npc = storageNpc()
                local prompt = npc and promptOf(npc)
                local anchor = (prompt and anchorOf(prompt.Parent)) or (npc and anchorOf(npc))
                if anchor and prompt then
                    state.status = "Storing fruit"
                    travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
                    interactWith(npc, prompt)
                    task.wait(0.5)
                    -- The npc opens the storage window: put the fruits in it.
                    for _, f in ipairs(fruits) do
                        if stored >= 4 then break end
                        if useFruitMenu(f.Name, {"deposit", "store"}) then stored += 1 end
                    end
                    stored = before - #carriedFruits()
                    if stored > 0 then
                        state.status = "Stored " .. stored .. " fruit(s)"
                        dbg("Stored " .. stored .. " fruit(s) at the npc")
                    else
                        state.status = "Could not store fruit"
                    end
                else
                    state.status = "No way to store fruit"
                    dbg("No store button and no storage npc")
                end
            end
            return
        end
    end

    local pendingTurnIn = (info and info.complete) or state.questDone
    if pendingTurnIn and CONFIG.QuestTurnIn then
        -- Try again later, but never sit at the giver forever.
        if state.turnInFailed and now - state.turnInFailedAt > CONFIG.TurnInTimeout then
            state.turnInFailed, state.turnInSince = false, now
            -- the giver never answered: do not stay stuck on the old quest
            state.questDone = false
            state.questDoneMob = nil
        end
        if not state.turnInFailed then
            local giver = pickQuestGiver((info and info.mentioned) or state.questDoneMob, state.questNpc)
            local prompt = giver and promptOf(giver)
            local anchor = (prompt and anchorOf(prompt.Parent)) or (giver and anchorOf(giver))
            if anchor and prompt then
                if state.turnInSince == nil then state.turnInSince = now end
                if now - state.turnInSince <= CONFIG.TurnInTimeout then
                    state.status = "Turning in quest"
                    travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
                    interactWith(giver, prompt)
                    return
                end
                dbg("Turn-in timed out, farming instead")
                state.turnInFailed, state.turnInFailedAt = true, now
            else
                dbg("No usable quest giver found")
                state.turnInFailed, state.turnInFailedAt = true, now
                state.status = "Quest complete, no giver found"
            end
        end
    else
        state.turnInSince, state.turnInFailed, state.turnInFailedAt = nil, false, 0
    end

    if CONFIG.AutoQuest then tryAcceptQuest(info) end

    -- Spend the stat points of the game while the bot runs.
    if CONFIG.AutoStats then tryUpgradeStats() end

    -- No quest known for this level (past the table above), or the game did
    -- not take the quest we asked for: go to a giver and let the game give
    -- us the quest it wants.
    local needGiver = not questFor(getMyLevel()) or state.questGaveUp
    if CONFIG.AutoQuest and needGiver and not (info and info.confirmed) then
        if state.seekSince == nil then state.seekSince = now end
        if state.seekGaveUp then
            -- We asked and nobody answered: farm for a while, then ask again.
            if now - state.seekGaveUpAt >= CONFIG.QuestSeekTimeout then
                state.seekGaveUp = false
                state.seekSince = now
            end
        elseif now - state.seekSince > CONFIG.QuestSeekTimeout then
            dbg("No quest giver answered, farming instead")
            state.seekGaveUp, state.seekGaveUpAt = true, now
        else
            -- The guide of the game knows the giver of the quest the game
            -- did not take.
            local giver = pickQuestGiver(nil, state.questGaveUp and state.questNpc or nil)
            local prompt = giver and promptOf(giver)
            local anchor = (prompt and anchorOf(prompt.Parent)) or (giver and anchorOf(giver))
            if anchor then
                -- The giver is on another island: the game can send us there
                -- by saving that island as the spawn point.
                if CONFIG.SpawnBypass and (not state.bypassAt or now - state.bypassAt > 60) then
                    local root = getRoot()
                    if root and (root.Position - anchor.Position).Magnitude
                        > (CONFIG.BypassDistance or 2000) then
                        state.bypassAt = now
                        dbg("Going to the island of the quest giver")
                        task.spawn(function() spawnBypassTo(anchor.Position) end)
                        return
                    end
                end
                state.status = "Looking for a quest"
                travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
                interactWith(giver, prompt)
                return
            end
        end
    else
        state.seekSince = nil
        state.seekGaveUp = false
    end

    if not CONFIG.AutoFarm then
        state.farming = false
        state.status = "Idle"
        -- Even without farming the weapon keeps swinging at close mobs.
        if CONFIG.AutoAttack then autoAttackSwing(nil) end
        return
    end
    state.farming = true

    local quest = CONFIG.AutoQuest and questFor(getMyLevel()) or nil
    local mob = quest and quest.mob or nil
    if info and info.target then mob = info.target end -- the panel wins

    local target = getTarget(mob)
    if not target then
        local sp = findSpawn(mob)
        local anchor = sp and anchorOf(sp)
        if anchor then
            state.status = "Travelling to " .. (mob or "mobs")
            travelTo(anchor.CFrame + Vector3.new(0, CONFIG.HoverHeight, 0))
        else
            state.status = "No targets"
        end
        return
    end

    local er = anchorOf(target)
    if not er then return end

    -- A mob that never loses health is ignored for a while.
    local th = target:FindFirstChildOfClass("Humanoid")
    local dist = (root.Position - er.Position).Magnitude
    -- "In range" depends on the weapon we hold: a gun reaches further.
    local reach = attackRange(LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool"))
    local inRange = dist <= reach + 6
    if th then
        if target ~= state.lastTarget then
            state.lastTarget, state.targetHealth, state.targetAt = target, th.Health, now
            -- A new target starts the hit count over.
            state.hitsConfirmed = 0
            state.targetDist, state.travelAt = dist, now
        elseif th.Health < (state.targetHealth or th.Health) then
            state.targetHealth, state.targetAt = th.Health, now
            state.targetDist, state.travelAt = dist, now
        elseif inRange then
            if now - state.targetAt > CONFIG.StuckTimeout then
                stuckTargets[target] = now + CONFIG.StuckIgnore
                state.lastTarget, state.targetHealth, state.targetAt = nil, nil, 0
                enemyCache, enemyCacheAt = {}, 0 -- drop it from the cache right away
                dbg("Ignoring stuck target " .. target.Name)
                return
            end
        elseif dist < (state.targetDist or dist) - 0.5 then
            -- Still closing in: the mob gets a fair chance.
            state.targetDist, state.travelAt = dist, now
        elseif now - (state.travelAt or now) > CONFIG.StuckTimeout * 3 then
            -- We cannot reach it at all.
            stuckTargets[target] = now + CONFIG.StuckIgnore
            state.lastTarget, state.targetHealth, state.targetAt = nil, nil, 0
            enemyCache, enemyCacheAt = {}, 0
            dbg("Cannot reach target " .. target.Name)
            return
        end
    end

    -- Hover above the mob, facing down. A melee swing only connects from
    -- close by, so stay low and inside the weapon's reach.
    local tool = equipWeapon()
    local reach = attackRange(tool)
    local hover = CONFIG.HoverHeight
    if reach <= CONFIG.MeleeRange then hover = math.min(hover, CONFIG.MeleeHover) end

    -- Bring the mob to us so the swing actually lands.
    if CONFIG.BringMob then bringMob(target, root) end

    -- The distance that counts is the flat one: the bot hovers above the
    -- mob on purpose.
    local dx = root.Position.X - er.Position.X
    local dz = root.Position.Z - er.Position.Z
    local flat = math.sqrt(dx * dx + dz * dz)

    -- The quest mob is far away but another one stands next to us: hit that
    -- one for a moment instead of walking away from it.
    local swingTarget, swingAnchor = target, er
    if CONFIG.AutoAttack then
        local close = mobInReach(root, reach)
        if close and close ~= target and flat > reach then
            if (state.autoBurst or 0) <= now then state.autoBurst = now + 2 end
            if state.autoBurst > now then
                swingTarget = close
                swingAnchor = anchorOf(close) or er
            end
        end
    end

    -- A bigger hitbox makes the swing land more often.
    if CONFIG.BigHitbox then enlargeHitbox(swingTarget) end

    -- Stand right above the head, then the swing comes down on the mob.
    local head = swingTarget:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        head = nil
        for _, d in ipairs(swingTarget:GetDescendants()) do
            if d:IsA("BasePart") and d.Name:lower():find("head", 1, true) then
                head = d
                break
            end
        end
    end
    local hoverPos
    if head then
        hoverPos = head.Position + Vector3.new(0, CONFIG.HeadHover, 0)
    else
        hoverPos = swingAnchor.Position + Vector3.new(0, hover, 0)
    end
    -- The feet must touch the top of the hitbox we enlarged, or the swing
    -- passes over it.
    local top = swingAnchor.Position.Y + (swingAnchor.Size and swingAnchor.Size.Y or 0) / 2
    hoverPos = Vector3.new(hoverPos.X, math.max(hoverPos.Y, top - 1), hoverPos.Z)
    -- A mob far away is crossed with the bypass of the game, not with a
    -- slow tween over the sea.
    if travelTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0)) then return end

    local sx = root.Position.X - swingAnchor.Position.X
    local sz = root.Position.Z - swingAnchor.Position.Z
    local swingFlat = math.sqrt(sx * sx + sz * sz)
    if now - state.lastAttack >= CONFIG.AttackCooldown
        and swingFlat <= reach then
        if not tool then dbg("No weapon in backpack!"); return end
        if doAttack(tool, swingTarget) then
            state.lastAttack = now
            if swingTarget == target then
                state.status = "Hitting " .. target.Name .. " (" .. state.hitsConfirmed .. " hits)"
            else
                state.status = "Attacking " .. swingTarget.Name
            end
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

-- Keep the session alive: a tiny camera turn resets the idle timer. It runs
-- even while the bot is stopped, because idling is when the kick comes.
task.spawn(function()
    while true do
        task.wait(1)
        if CONFIG.AntiAfk then
            state.afkTimer += 1
            if state.afkTimer >= (CONFIG.AntiAfkInterval or 120) then
                state.afkTimer = 0
                local cam = Workspace.CurrentCamera
                if cam then
                    -- Turn one way, then the other, so the view does not drift.
                    state.afkSign = -state.afkSign
                    pcall(function()
                        cam.CFrame = cam.CFrame * CFrame.Angles(0, 0.01 * state.afkSign, 0)
                    end)
                end
            end
        else
            state.afkTimer = 0
        end
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
local setBotEnabled -- assigned in the BUILD section below
closeBtn.MouseButton1Click:Connect(function()
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

-- The tabs of the panel. Every tab has its own page, so the rows stay big
-- and easy to tap instead of one long list.
local TABS = {"HOME", "MOVE", "FIGHT", "STATS", "TRAVEL"}

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -152)
content.Position = UDim2.new(0, 8, 0, 72)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Parent = main

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 28)
tabBar.Position = UDim2.new(0, 8, 0, 40)
tabBar.BackgroundTransparency = 1
tabBar.BorderSizePixel = 0
tabBar.Parent = main

local pages = {}
local page -- the page the new rows go into
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

-- Show one tab and hide the others.
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
end

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Name = "Tab_" .. name
    b.Size = UDim2.new(1/#TABS, -4, 1, 0)
    b.Position = UDim2.new((i-1)/#TABS, 0, 0, 0)
    b.BackgroundColor3 = THEME.panel
    b.Text = name; b.TextColor3 = THEME.subtext
    b.Font = THEME.fontBold; b.TextSize = 11
    b.AutoButtonColor = false; b.Parent = tabBar
    corner(b, 6); stroke(b)
    b.MouseButton1Click:Connect(function() showTab(i) end)
    tabButtons[i] = b
    newPage(name)
end
showTab(1)

local expandedH, collapsedH = 540, 34
local minimized = false
minBtn.MouseButton1Click:Connect(function()
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
        local width = bar.AbsoluteSize.X
        if width <= 0 then return end
        local rel = math.clamp((i.Position.X - bar.AbsolutePosition.X) / width, 0, 1)
        v = math.floor(mn + (mx-mn)*rel + 0.5)
        fill.Size = UDim2.new((v-mn)/(mx-mn),0,1,0)
        val.Text = fmt(v); cb(v)
    end

    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            setFromInput(i)
            local m, e, f
            local function cleanup()
                m:Disconnect(); e:Disconnect(); f:Disconnect()
            end
            m = UserInputService.InputChanged:Connect(function(x)
                if x.UserInputType == Enum.UserInputType.MouseMovement or x.UserInputType == Enum.UserInputType.Touch then
                    setFromInput(x)
                end
            end)
            e = UserInputService.InputEnded:Connect(function(x)
                if x.UserInputType == Enum.UserInputType.MouseButton1 or x.UserInputType == Enum.UserInputType.Touch then
                    cleanup()
                end
            end)
            -- Losing focus must not leave a live drag behind.
            f = UserInputService.WindowFocusReleased:Connect(cleanup)
        end
    end)
end

local function makeSegment(text, options, default, cb)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(1,0,0,58); c.BackgroundTransparency = 1
    c.LayoutOrder = #page:GetChildren(); c.Parent = page

    local label = Instance.new("TextButton")
    label.Size = UDim2.new(1,0,0,16); label.BackgroundTransparency = 1
    -- The label shows the current value, so a tap always shows up somewhere.
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
            -- The press and the click both arrive: one press, one change.
            local now = tick()
            if now - lastPick < 0.15 then return end
            lastPick = now
            -- The setting first, the colours after: a tween that fails must
            -- never swallow the click.
            cb(opt)
            for n, bb in pairs(buttons) do
                -- The colour goes on right away: a tap must be visible even
                -- when the tween does not run.
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
        -- Every way a phone can send a tap.
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

    -- Tapping the label cycles through the options. The label is a much
    -- bigger target than the buttons, so it works even when a small button
    -- does not get the tap.
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

-- A row with a button that does something once.
local function makeButton(text, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,32); row.BackgroundTransparency = 1
    row.LayoutOrder = #page:GetChildren(); row.Parent = page

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,26); btn.Position = UDim2.new(0,0,0,3)
    btn.BackgroundColor3 = THEME.panel; btn.Text = text; btn.TextColor3 = THEME.text
    btn.Font = THEME.fontBold; btn.TextSize = 12
    btn.AutoButtonColor = false; btn.Parent = row
    corner(btn, 6); stroke(btn)

    btn.MouseButton1Click:Connect(function()
        cb()
        -- The button lights up for a moment, so the tap is visible.
        pcall(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = THEME.accent}):Play()
        end)
        task.delay(0.15, function()
            pcall(function()
                TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = THEME.panel}):Play()
            end)
        end)
    end)
    return btn
end

-- ===== BUILD =====
-- The tabs are built one after the other: the rows of a tab go into the
-- page of that tab.
showTab(1) -- HOME
makeHeader("MODULES")
setBotEnabled = makeToggle("Bot Enabled", state.enabled, function(v)
    state.enabled = v
    if not v then
        state.farming = false
        state.fruit = nil
        state.fruitStart = 0
        state.fruitTries = 0
        stopTween()
    end
end)
makeToggle("Auto Quest",    CONFIG.AutoQuest,    function(v) CONFIG.AutoQuest    = v end)
makeToggle("Auto Farm",     CONFIG.AutoFarm,     function(v) CONFIG.AutoFarm     = v end)
makeToggle("Fruit Sniper",  CONFIG.FruitSniper,  function(v) CONFIG.FruitSniper  = v end)
makeToggle("Eat Fruit",     CONFIG.EatFruit,     function(v) CONFIG.EatFruit     = v end)
makeToggle("Turn In Quest", CONFIG.QuestTurnIn,  function(v) CONFIG.QuestTurnIn  = v end)
makeToggle("Anti-AFK",      CONFIG.AntiAfk,      function(v) CONFIG.AntiAfk      = v end)
local setDebug = makeToggle("Debug Output (F9)", CONFIG.Debug, function(v) CONFIG.Debug = v end)
makeHint("✕ stops the bot  •  RightShift shows/hides this panel")

makeHeader("FRUIT")
makeToggle("Auto Store", CONFIG.AutoStore, function(v) CONFIG.AutoStore = v end)
makeSlider("Store From", 1, 10, CONFIG.StoreFruitMin,
    function(v) return v.." fruits" end, function(v) CONFIG.StoreFruitMin = v end)
makeSlider("Scan Radius", 500, 10000, CONFIG.FruitScanRadius,
    function(v) return tostring(v) end, function(v) CONFIG.FruitScanRadius = v end)

showTab(2) -- MOVE
makeHeader("MOVEMENT")
makeSegment("Mode", {"Walk","Tween","Teleport"}, CONFIG.MovementMode,
    function(v) CONFIG.MovementMode = v end)
makeSlider("Move Speed", 50, 500, CONFIG.MoveSpeed,
    function(v) return v.." st/s" end, function(v) CONFIG.MoveSpeed = v end)
makeSlider("Hover Height", 0, 30, CONFIG.HoverHeight,
    function(v) return v.." studs" end, function(v) CONFIG.HoverHeight = v end)
makeSlider("Void Guard Y", -1000, -50, CONFIG.SafeY,
    function(v) return tostring(v).." studs" end, function(v) CONFIG.SafeY = v end)

makeHeader("BRING MOB")
makeToggle("Bring Mob", CONFIG.BringMob, function(v) CONFIG.BringMob = v end)
makeSlider("Bring Mob Count", 1, 6, CONFIG.BringMobCount,
    function(v) return v.." mobs" end, function(v) CONFIG.BringMobCount = v end)

showTab(3) -- FIGHT
makeHeader("COMBAT")
makeSegment("Weapon", {"Melee", "Sword", "Fruit", "Gun"}, CONFIG.WeaponMode,
    function(v) CONFIG.WeaponMode = v end)
makeToggle("Auto Attack", CONFIG.AutoAttack, function(v) CONFIG.AutoAttack = v end)
makeToggle("Fast Attack", CONFIG.FastAttack, function(v) CONFIG.FastAttack = v end)
makeToggle("Remote Attack", CONFIG.RemoteAttack, function(v) CONFIG.RemoteAttack = v end)
makeToggle("Big Hitbox", CONFIG.BigHitbox, function(v) CONFIG.BigHitbox = v end)
makeSlider("Hitbox Size", 4, 40, CONFIG.HitboxSize,
    function(v) return tostring(v) end, function(v) CONFIG.HitboxSize = v end)
makeSlider("Swing Reach", 0, 200, CONFIG.HitboxMagnitude,
    function(v) return v.." studs" end, function(v) CONFIG.HitboxMagnitude = v end)
makeSlider("Head Hover", 0, 8, CONFIG.HeadHover,
    function(v) return v.." studs" end, function(v) CONFIG.HeadHover = v end)
makeSlider("Melee Range", 4, 30, CONFIG.MeleeRange,
    function(v) return v.." studs" end, function(v) CONFIG.MeleeRange = v end)
makeSlider("Gun Range", 20, 120, CONFIG.GunRange,
    function(v) return v.." studs" end, function(v) CONFIG.GunRange = v end)
makeSlider("Attack Cooldown", 5, 100, math.floor(CONFIG.AttackCooldown*100),
    function(v) return string.format("%.2fs", v/100) end,
    function(v) CONFIG.AttackCooldown = v/100 end)

showTab(4) -- STATS
makeHeader("STATS")
makeToggle("Auto Stats", CONFIG.AutoStats, function(v) CONFIG.AutoStats = v end)
makeSegment("Stat", {"Melee","Sword","Gun","Fruit","Defense","All"}, CONFIG.AutoStatTarget,
    function(v) CONFIG.AutoStatTarget = v end)
makeSlider("Stat Wait", 1, 15, CONFIG.AutoStatWait,
    function(v) return v.."s" end, function(v) CONFIG.AutoStatWait = v end)

showTab(5) -- TRAVEL
makeHeader("WORLD")
makeSegment("World", {"1","2","3"}, tostring(CONFIG.TravelWorld),
    function(v) CONFIG.TravelWorld = tonumber(v) end)
makeButton("Travel To World", function() travelToWorld(CONFIG.TravelWorld) end)

makeHeader("FAST TRAVEL")
makeToggle("Spawn Bypass", CONFIG.SpawnBypass, function(v) CONFIG.SpawnBypass = v end)
makeToggle("Fast Portal", CONFIG.FastPortal, function(v) CONFIG.FastPortal = v end)
makeSlider("Bypass Distance", 500, 5000, CONFIG.BypassDistance,
    function(v) return v.." studs" end, function(v) CONFIG.BypassDistance = v end)
makeButton("Go To Quest Island", function()
    -- The island of the quest we have, or the one the game would give us.
    local pos = state.questPos
    if not pos then
        local q = questFor(getMyLevel())
        pos = q and q.pos
    end
    if not pos then dbg("No island known for this quest"); return end
    task.spawn(function() spawnBypassTo(pos) end)
end)
makeHint("A long way is crossed with the spawn point of the island")

makeHeader("ISLANDS")
-- The islands the game knows: one button for every one of them.
for _, island in ipairs(islandPositions()) do
    local name = island.name
    makeButton("Go: " .. name, function()
        task.spawn(function()
            -- The door of the game first, the spawn point as the fallback.
            if not (CONFIG.FastPortal and portalBypass(island.pos)) then
                spawnBypassTo(island.pos)
            end
        end)
    end)
end
if #islandPositions() == 0 then
    makeHint("The game has not told the islands yet")
end

showTab(1) -- back to the first tab

-- Footer
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

task.spawn(function()
    while gui.Parent do
        statusLabel.Text = state.enabled and state.status or "Stopped"
        debugLabel.Text = state.debugLine == "" and "Ready" or state.debugLine
        infoLabel.Text = string.format("Lv %d • Fruits: %d • Quest: %s • Spd %s",
            getMyLevel(), state.fruitsFound, questProgressText(),
            tostring(state.attackSpeed))
        task.wait(0.4)
    end
end)

-- Drag
local dragging, dragInput, dragStart, startPos
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = i.Position; startPos = main.Position
        i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
titleBar.InputChanged:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
        dragInput = i
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and i == dragInput then
        local d = i.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                  startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then gui.Enabled = not gui.Enabled end
    if i.KeyCode == Enum.KeyCode.F9 and setDebug then setDebug(not CONFIG.Debug) end
end)

print("[Farm] Fixed build loaded.")
