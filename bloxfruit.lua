-- // Blox Fruits Auto-Farm — Fixed Build
-- The services are put in the global table on purpose: the script has a hard
-- limit of 200 locals in one chunk, and it is already close to it.
Players           = game:GetService("Players")
RunService        = game:GetService("RunService")
Workspace         = game:GetService("Workspace")
ReplicatedStorage = game:GetService("ReplicatedStorage")
UserInputService  = game:GetService("UserInputService")
TweenService      = game:GetService("TweenService")
LocalPlayer       = Players.LocalPlayer

pcall(function() Workspace.StreamingEnabled = false end)
pcall(function() Workspace.StreamingMinRadius = 1e8 end)
pcall(function() Workspace.StreamingTargetRadius = 1e8 end)

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
    GunRange        = 70,
    FruitRange      = 70,
    AutoBuyStyles   = false,
    AutoSaber       = false,
    MeleeHover      = 4,
    BringMob        = true,
    BringMobRange   = 35,
    BringMobCount   = 0,
    BringMobSearch  = 200,
    AutoStats       = false,
    AutoStatTarget  = "Melee",
    AutoStatWait    = 3,
    BigHitbox       = true,
    HitboxSize      = 16,
    HeadHover       = 2,
    AutoAttack      = true,
    AutoStore       = true,
    StoreFruitMin   = 3,
    AutoBuso        = true,
    Aoe             = true,
    AoeRange        = 80,
    BossFarm        = false,
    BossRange       = 3000,
    WarpClose       = true,
    WarpDistance    = 60,
    HoverHeight     = 14,
    FruitScanRadius = 5000,
    MovementMode    = "Tween",
    MoveSpeed       = 250,
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
    flying        = false,
    whirlpooling  = false,
    questing      = false,
    bringMoved    = setmetatable({}, {__mode = "k"}),
    bringIgnored  = setmetatable({}, {__mode = "k"}),
    bringHealth   = setmetatable({}, {__mode = "k"}),
    bringPoint    = nil,
    bringTarget   = nil,
    questVerified = false,
    questGaveUp   = false,
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

local function isFruit(t)
    return t.Name:lower():find("fruit", 1, true) ~= nil
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

local function toolKind(tool)
    local tip = tool.ToolTip
    if type(tip) == "string" and tip ~= "" then return tip:lower() end
    return nil
end

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
    local group = WEAPON_GROUPS[CONFIG.WeaponMode] or WEAPON_GROUPS.Melee
    for i, w in ipairs(group) do
        if n:find(w, 1, true) then return i end
    end
    return nil
end

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
    if not tool then return CONFIG.MeleeRange end
    if isGun(tool) then return CONFIG.GunRange end
    if isFruit(tool) then return CONFIG.FruitRange or CONFIG.GunRange end
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
        
        if item.Parent ~= char then
            state.equipRetryAt = tick() + 2
            dbg("Could not equip " .. item.Name)
            return nil
        end
        return item
    end

    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and matchesMode(equipped) then return equipped end

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

    for _, entry in ipairs(weapons) do
        if entry.tool == equipped then return equipped end
        local weapon = equip(entry.tool)
        if weapon then return weapon end
    end

    if equipped and not isFruit(equipped) then return equipped end

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

local function enlargeHitbox(target)
    local anchor = anchorOf(target)
    if not anchor or not anchor.Size then return end
    local size = CONFIG.HitboxSize or 16
    if anchor.Size.X >= size then return end
    local now = tick()
    if now < (state.hitboxAt or 0) then return end
    state.hitboxAt = now + 2
    pcall(function() anchor.Size = Vector3.new(size, size, size) end)
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

task.spawn(function()
    local data = loadGameQuests()
    if data then
        gameQuests = data.quests
        gameGuideQuests = data.guide
        gameLevelQuests = data.levels
        gameGuideNames = data.guideNames
        gameQuestIndexes = data.indexes
        gameQuestCache, gameQuestCacheAt = nil, nil
        state.questTried = {}
        state.questTryKey = nil
        state.questIndexTry = nil
        refreshKnownMobs()
        dbg("Game quest data: " .. #gameQuests .. " quests")
    end
end)

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
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local q = remotes and remotes:FindFirstChild("QuestUpdate")
    if not q then return nil end
    questRemote = q
    if questRemoteHooked or not q.OnClientEvent then return q end
    questRemoteHooked = true
    pcall(function()
        q.OnClientEvent:Connect(function(data, update)
            if data == nil then
                questRemoteState = nil
                state.questDone = false
                state.questDoneMob = nil
                state.currentQuest = nil
                state.questSentAt = 0
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
            state.questVerified = true
            state.questGaveUp = false
            if state.questAsked and data.InternalQuestName ~= state.questAsked then
                dbg("The game gave us " .. tostring(data.InternalQuestName)
                    .. " instead of " .. tostring(state.questAsked))
            else
                state.questTried = {}
                state.questIndexTry = nil
            end
        end)
    end)
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

    if info and info.confirmed then
        state.questSeenUntil = now + 1
        return
    end
    if now < (state.questSeenUntil or 0) then return end
    if now - state.lastQuestTry < 2 then return end
    if state.questDone then return end

    local q = questFor(getMyLevel())
    if not q then
        dbg("No quest bracket for this level")
        return
    end

    local key = questKey(q) .. "@" .. tostring(getMyLevel())
    if state.questTryKey ~= key then
        state.questTryKey = key
        state.questTried = {}
        state.questIndexTry = nil
        state.questGaveUp = false
    end

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

    local index = state.questIndexTry or q.index

    pcall(function() commF:InvokeServer("SetLastSpawnPoint", "Town") end)

    if questRemoteState then
        pcall(function() commF:InvokeServer("AbandonQuest") end)
    end
    local ok, err = pcall(function() commF:InvokeServer("StartQuest", q.name, index) end)
    state.currentQuest = q.name .. "#" .. tostring(index)
    state.questSentAt = tick()
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
    ["cake prince"] = true, ["rip_indra true form"] = true,
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

local function pickBoss(root, range)
    if not root then return nil end
    local level = getMyLevel()
    local best, bestD, fallback, fallbackD = nil, nil, nil, nil
    for _, mob in ipairs(collectEnemies(tick())) do
        local key = bossKeyOf(mob)
        if key then
            local anchor = anchorOf(mob)
            if anchor then
                local d = (anchor.Position - root.Position).Magnitude
                if d <= range then
                    -- A boss whose level is unknown, or far above the level of
                    -- the player, is only taken when nothing better is around.
                    local bossLevel = BOSS_LEVELS[key]
                    if bossLevel == nil or bossLevel > level + 25 then
                        if fallbackD == nil or d < fallbackD then fallback, fallbackD = mob, d end
                    elseif bestD == nil or d < bestD then
                        best, bestD = mob, d
                    end
                end
            end
        end
    end
    return best or fallback
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
    for _, c in ipairs(chars:GetChildren()) do
        if c ~= LocalPlayer.Character then
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - part.Position).Magnitude <= 300 then return true end
        end
    end
    return false
end

-- The pack stands on one point. Like the hub, that point is the spawn point
-- of that mob in the world; the place the mob was first seen is the fallback.
local function mobSpawnPoint(target, fallback)
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    if not spawns then return fallback end
    local key = mobKey(target.Name)
    local best, bestD = nil, nil
    for _, part in ipairs(spawns:GetChildren()) do
        if part:IsA("BasePart") then
            local display = nil
            pcall(function() display = part:GetAttribute("DisplayName") end)
            local clean = tostring(display or part.Name)
            clean = clean:gsub("%s*%(Lv%.?%s*%d+%)", "")
            if mobKey(clean) == key then
                local d = (part.Position - fallback).Magnitude
                if bestD == nil or d < bestD then
                    best, bestD = part.Position, d
                end
            end
        end
    end
    return best or fallback
end

local function bringMob(target, root)
    local anchor = anchorOf(target)
    if not anchor then return end
    local now = tick()

    for _, mob in ipairs(collectEnemies(now)) do
        local marker = mob:FindFirstChild("Ignored")
        if marker and not state.bringIgnored[mob] then
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
        if now - at > 2.2 then
            state.bringMoved[mob] = nil
            local hum = mob:FindFirstChildOfClass("Humanoid")
            local hp = hum and hum.Health
            if hp and state.bringHealth[mob] == hp and not mob:FindFirstChild("Ignored") then
                -- It is not being hurt: it is put back and left alone.
                local part = anchorOf(mob)
                if part then
                    local home = mobSpawnPoint(mob, part.Position)
                    if home then pcall(function() part.CFrame = CFrame.new(home) end) end
                end
                state.bringIgnored[mob] = now
                Instance.new("IntValue", mob).Name = "Ignored"
            end
            state.bringHealth[mob] = hp
        end
    end

    local dx = root.Position.X - anchor.Position.X
    local dz = root.Position.Z - anchor.Position.Z
    if math.sqrt(dx * dx + dz * dz) > CONFIG.BringMobRange then return end
    if now < (state.bringAt or 0) then return end
    state.bringAt = now + 0.1

    if target:FindFirstChild("Ignored") then return end

    if ownedByOther(anchor) then
        dbg("The mob belongs to another player")
        return
    end

    -- The pack has one fixed point to stand on and the player comes to it.
    -- Pulling to the player instead drags the whole pack around every time
    -- the player turns or walks to the next fruit.
    if state.bringTarget ~= target or not state.bringPoint then
        state.bringTarget = target
        state.bringPoint = mobSpawnPoint(target, anchor.Position)
    end
    local point = state.bringPoint

    local list = {target}
    local count = CONFIG.BringMobCount or 0
    if count <= 0 then
        -- zero means every mob of the kind: the whole pack stands on one point
        count = math.huge
    end
    local key = mobKey(target.Name)
    if count > 1 then
        local near = {}
        for _, mob in ipairs(collectEnemies(now)) do
            if mob ~= target and not mob:FindFirstChild("Ignored")
                and mobKey(mob.Name) == key then
                local part = anchorOf(mob)
                local hum = mob:FindFirstChildOfClass("Humanoid")
                if part and hum and hum.Health > 0 and not ownedByOther(part)
                    and (part.Position - anchor.Position).Magnitude <= CONFIG.BringMobSearch then
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

    -- The pack is put down as one group: each mob gets its own small step of
    -- the same point, so five of them stand next to each other and one swing
    -- takes them all.
    for i, mob in ipairs(list) do
        local part = anchorOf(mob)
        if part then
            local shift = ((i - 1) % 3 - 1) * 2
            local goal = Vector3.new(point.X + shift, part.Position.Y, point.Z)
            local off = (part.Position - goal).Magnitude
            local vel = part.AssemblyLinearVelocity
            local speed = vel and vel.Magnitude or 0
            -- A mob that already stands still on its step is left alone: it is
            -- only handled when it drifted away or something is moving it.
            if off > 3 or speed > 2 then
                local hum = mob:FindFirstChildOfClass("Humanoid")
                if hum then
                    pcall(function() hum.PlatformStand = true end)
                    pcall(function() hum.Sit = true end)
                    pcall(function() hum.WalkSpeed = 0 end)
                    pcall(function() hum.JumpPower = 0 end)
                end
                pcall(function() part.CanCollide = false end)
                if speed > 2 then
                    pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
                    pcall(function() part.AssemblyAngularVelocity = Vector3.zero end)
                end
                if off > 3 then
                    pcall(function() part.CFrame = CFrame.new(goal) end)
                end
                pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
            end
            state.bringMoved[mob] = now
        end
    end
end

-- ================= MOVEMENT =================
local activeTween, tweenGoal

local function setFlying()
    -- While a tween moves the character, its own body (gravity, walking,
    -- getting up) fights the CFrame and the flight looks jerky. The body is
    -- put in the physics state and left alone until the move is over.
    local hum = getHumanoid()
    if not hum then return end
    pcall(function() hum.PlatformStand = true end)
    pcall(function() hum.AutoRotate = false end)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
end

local function setWalking()
    local hum = getHumanoid()
    if not hum then return end
    pcall(function() hum.PlatformStand = false end)
    pcall(function() hum.AutoRotate = true end)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
end

local function stopTween()
    if activeTween then activeTween:Cancel(); activeTween = nil end
    tweenGoal = nil
    setWalking()
end

local function moveTo(cf, noWarp)
    local root = getRoot()
    if not root then return end
    local mode = CONFIG.MovementMode
    local hop = (root.Position - cf.Position).Magnitude

    -- A short hop inside the same island is accepted by the game, so it is
    -- taken at once instead of being walked. The shop turns that off: the
    -- teacher of a style has to see the player walk up to it.
    if CONFIG.WarpClose and not noWarp and hop <= (CONFIG.WarpDistance or 60) then
        stopTween()
        root.CFrame = cf
        return
    end

    if mode == "Teleport" then
        stopTween()
        root.CFrame = cf
    elseif mode == "Tween" then
        local dist = (root.Position - cf.Position).Magnitude
        if dist < 6 and not noWarp then
            stopTween()
            setWalking()
            root.CFrame = cf
            return
        end
        -- A running tween is left alone while its goal only shifts a little:
        -- cancelling and building a new one every tick is what made the
        -- flight jump. It is only replaced when the goal really moved.
        if activeTween and tweenGoal
            and activeTween.PlaybackState == Enum.PlaybackState.Playing then
            local moved = (tweenGoal.Position - cf.Position).Magnitude
            local left = (root.Position - tweenGoal.Position).Magnitude
            if moved < math.max(8, left * 0.5) then return end
        end
        if activeTween then activeTween:Cancel() end
        setFlying()
        tweenGoal = cf
        activeTween = TweenService:Create(root,
            TweenInfo.new(math.max(dist / CONFIG.MoveSpeed, 0.1), Enum.EasingStyle.Sine,
                Enum.EasingDirection.Out),
            {CFrame = cf})
        activeTween:Play()
    else
        setWalking()
        local hum = getHumanoid()
        if hum then hum:MoveTo(cf.Position) end
    end
end

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
    pcall(function()
        local root = getRoot()
        if not CONFIG.AutoFarm or not state.farming or not state.enabled or not root then
            if #noclipParts > 0 then restoreNoclip() end
            return
        end
        applyNoclip()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
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
    local char = LocalPlayer.Character
    local stun = char and char:FindFirstChild("Stun")
    if stun then pcall(function() stun.Value = 0 end) end
    return ok
end

local function combatUtilModule()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local util = modules and modules:FindFirstChild("CombatUtil")
    if not util then return nil end
    local ok, combatUtil = pcall(require, util)
    if not ok or not combatUtil then return nil end
    return combatUtil
end

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

local function hitPartOf(mob)
    if not mob then return nil end
    return mob:FindFirstChild("RightHand")
        or mob:FindFirstChild("Head")
        or anchorOf(mob)
end

-- Every mob close to the player goes into one swing. Like the hub, each mob
-- goes in as a pair of its rig and the part that was hit, and the target is
-- the first one: the game takes that part on its own and the whole list with
-- it, so a single swing lands on all of them.
local function aoePairs(root, target)
    local range = CONFIG.AoeRange or 80
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
    if CONFIG.Aoe then
        for _, mob in ipairs(collectEnemies(tick())) do add(mob) end
    end
    return out
end

-- The hub fires the hit remote through the Net wrapper of the game; the raw
-- remote is the fallback when that wrapper is not there.
local function hitRemote()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    if not net then return nil, false end
    local ok, wrapped = pcall(function() return net:RemoteEvent("RegisterHit", true) end)
    if ok and wrapped then return wrapped, true end
    return net:FindFirstChild("RE/RegisterHit"), false
end

local function remoteAttack(target, tool)
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    if not net then return false end
    local regAttack = net:FindFirstChild("RE/RegisterAttack")
    if not regAttack then return false end
    local root = getRoot()
    local pairs_ = aoePairs(root, target)
    if #pairs_ == 0 then return false end
    local id = nil
    pcall(function() id = regAttack:FireServer(attackAnimLength(tool), 1) end)
    if type(id) ~= "string" then
        state.attackId = (state.attackId or 0) + 1
        id = string.format("%08x", state.attackId)
    end
    state.aoeCount = #pairs_
    local hit, wrapped = hitRemote()
    if not hit then return false end
    local rest = {}
    for i = 2, #pairs_ do rest[i - 1] = pairs_[i] end
    if wrapped then
        pcall(function() hit:FireServer(pairs_[1][2], rest) end)
    else
        pcall(function() hit:FireServer(pairs_[1][2], rest, nil, id) end)
    end
    return true
end

local function doAttack(tool, target)
    if CONFIG.FastAttack then fastAttack() end
    local char = LocalPlayer.Character
    local stun = char and char:FindFirstChild("Stun")
    local stunned = false
    pcall(function() stunned = (stun and stun.Value and stun.Value ~= 0) end)
    if stunned then return false end
    if not canAttack(tool) then return false end
    if CONFIG.RemoteAttack and remoteAttack(target, tool) then return true end
    local ok = pcall(function() tool:Activate() end)
    return ok
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
    if now - state.lastAttack < CONFIG.AttackCooldown then return false end
    local tool = equipWeapon()
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
    local function press(d)
        pcall(function() d.MouseButton1Click:Fire() end)
        pcall(function() d.Activated:Fire() end)
    end
    local function shown(d) return d.Visible ~= false end
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
    if useFruitMenu(name, {"eat"}) then
        dbg("Ate " .. name .. " from the menu")
        return true
    end
    dbg("No eat button for " .. name)
    return false
end

local function storeFruit(tool)
    if not tool then return false end
    if useFruitMenu(tool.Name, {"store", "deposit", "stash"}) then
        dbg("Asked the game to store " .. tool.Name)
        return true
    end
    return false
end

local function fruitWasTaken(fruit)
    local p = fruit.Parent
    if p == nil then
        return toolCount() > state.fruitToolCount
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack and fruit:IsDescendantOf(backpack) then return true end
    local char = LocalPlayer.Character
    if char and fruit:IsDescendantOf(char) then return true end
    return false
end

local function confirmFruitPickup(fruit)
    state.fruitsFound += 1
    local name = fruit.Name
    local tool = newTool(state.fruitTools) or findFruitTool(name)
    state.fruit = nil
    state.fruitTries = 0
    state.fruitTools = nil
    dbg("Picked up " .. name)
    if CONFIG.EatFruit and tool then
        eatFruit(tool)
        equipWeapon()
    end
    return true
end

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
        if fruitWasTaken(fruit) then confirmFruitPickup(fruit) end
        state.fruit = nil
        state.fruitTools = nil
        return false
    end

    state.status = "Fruit: " .. fruit.Name
    moveTo(handle.CFrame)

    if (root.Position - handle.Position).Magnitude < 8 then
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
                grabbedFruits[fruit] = now
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

takeWhirlpool = nil

-- Is this destination a place under the sea, and is the player still up here?
-- Then walking or tweening there is hopeless: the whirlpool is the way in.
local function needsWhirlpool(pos)
    if not (pos and pos.X and pos.Y and pos.Z) then return false end
    local root = getRoot()
    if not root then return false end
    local ok, map = pcall(function() return Workspace:GetAttribute("MAP") end)
    if not (ok and type(map) == "table") then return false end
    for name, place in pairs(map) do
        local lower = tostring(name):lower()
        if lower:find("underwater", 1, true) or lower:find("submerged", 1, true) then
            if place and place.X and place.Y and place.Z then
                if (place - pos).Magnitude < 2000
                    and (root.Position - place).Magnitude > 2000 then
                    return true
                end
            end
        end
    end
    return false
end

local function travelTo(cf, noWarp)
    -- A farm under the sea goes through the whirlpool of the sea first.
    if not noWarp and not state.whirlpooling and takeWhirlpool and needsWhirlpool(cf.Position) then
        state.whirlpooling = true
        takeWhirlpool()
        state.whirlpooling = false
    end
    moveTo(cf, noWarp)
    return false
end

-- ================= WORLD (SEA) TRAVEL =================
local WORLD_TRAVEL = {"TravelMain", "TravelDressrosa", "TravelZou"}

-- The seas are separate places: the game moves the whole character between
-- them, and the remotes are the ones BananaHub uses.
local function travelToWorld(world)
    local what = WORLD_TRAVEL[world]
    if not what then return false end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    local ok = pcall(function() commF:InvokeServer(what) end)
    if ok then
        dbg("Travelling to world " .. tostring(world))
        return true
    end
    dbg("The game did not take the travel to world " .. tostring(world))
    return false
end

-- ================= FLY TO AN ISLAND =================
local function islandPositions()
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

-- Some islands cannot be tweened to at all (the sea floor, the islands the
-- game only opens through a door). For those the game itself is asked to move
-- the player. The remotes are the ones BananaHub uses.
-- Fly to a place with the tween of the script: no jump, no portal, just a
-- straight tween across the sea, like the player would glide over.
local function flyTo(position)
    local root = getRoot()
    if not root or not position then return false end
    if state.flying then
        dbg("Already flying to an island")
        return false
    end
    state.flying = true
    stopTween()
    local here = root.Position
    local distance = (here - position).Magnitude
    dbg("Flying to the island (" .. tostring(math.floor(distance)) .. " studs)")
    setFlying()
    local ok, err = pcall(function()
        local tween = TweenService:Create(root,
            TweenInfo.new(math.max(distance / CONFIG.MoveSpeed, 0.2), Enum.EasingStyle.Sine,
                Enum.EasingDirection.Out),
            {CFrame = CFrame.new(position + Vector3.new(0, 6, 0))})
        activeTween, tweenGoal = tween, CFrame.new(position)
        tween:Play()
        local deadline = tick() + math.max(distance / CONFIG.MoveSpeed, 0.1) + 5
        while tick() < deadline do
            local now = getRoot()
            if not now then break end
            if (now.Position - position).Magnitude <= 12 then break end
            task.wait(0.2)
        end
    end)
    state.flying = false
    setWalking()
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
        local sub = net:FindFirstChild("RF/SubmarineWorkerSpeak")
        if not sub then
            dbg("The submarine remote of the game was not found")
            return false
        end
        local ok = pcall(function() sub:InvokeServer("TravelToSubmergedIsland") end)
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
local STYLE_SHOP = {
    {name = "Dark Step",       remote = "BuyBlackLeg",       teacher = "Dark Step Teacher"},
    {name = "Electric",        remote = "BuyElectro",        teacher = "Mad Scientist"},
    {name = "Water Kung Fu",   remote = "BuyFishmanKarate",  teacher = "Water Kung Fu Teacher"},
    {name = "Dragon Breath",   remote = "BuyDragonBreath",   teacher = "Sabi"},
    {name = "Superhuman",      remote = "BuySuperhuman",     teacher = "Martial Arts Master"},
    {name = "Death Step",      remote = "BuyDeathStep",      teacher = "Phoeyu, the Reformed"},
    {name = "Electric Claw",   remote = "BuyElectricClaw",   teacher = "Previous Hero"},
    {name = "Sharkman Karate", remote = "BuySharkmanKarate", teacher = "Sharkman Teacher"},
    {name = "Dragon Talon",    remote = "BuyDragonTalon",    teacher = "Uzoth"},
    {name = "Godhuman",        remote = "BuyGodhuman",       teacher = "Ancient Monk"},
    {name = "Sanguine Art",    remote = "BuySanguineArt",    teacher = "Shafi"},
    {name = "Advanced Combat", remote = "BuyAdvancedCombat", teacher = "Secrets Master"},
}

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

local function findWhirlpool()
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name:lower():find("whirlpool", 1, true) then return obj end
    end
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    if locations then
        for _, island in ipairs(locations:GetChildren()) do
            if island.Name:lower():find("whirlpool", 1, true) then return island end
        end
    end
    return nil
end

-- Fly into the whirlpool of the sea and wait until the game drops the player
-- under it. That is the way to Underwater (the Water Kung-fu teacher lives
-- there too).
function takeWhirlpool()
    local pool = findWhirlpool()
    if not pool then
        dbg("The whirlpool of the sea was not found")
        return false
    end
    local part = anchorOf(pool)
    if not part then
        dbg("The whirlpool has no place to fly to")
        return false
    end
    dbg("Flying into the whirlpool of the sea")
    flyTo(part.Position)
    -- the place to compare against is where the flight left the player: the
    -- jump the game does from here is what puts us under the sea
    local root = getRoot()
    local before = root and root.Position
    local deadline = tick() + 20
    while tick() < deadline do
        local now = getRoot()
        if not now then break end
        if before and (now.Position - before).Magnitude > 500 then
            dbg("The whirlpool took us under the sea")
            return true
        end
        travelTo(CFrame.new(part.Position), true)
        task.wait(0.3)
    end
    dbg("The whirlpool did not take us this time")
    return false
end

-- The game only takes the buy when the player stands at the teacher of the
-- style, so the bot walks to it first and asks there.
local function buyStyle(style)
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    if state.shopping then
        dbg("A buy is already running")
        return false
    end
    state.shopping = true
    if WHIRLPOOL_STYLES[style.name] then
        takeWhirlpool()
    end
    local npc = findTeacher(style.teacher)
    local near = false
    if npc then
        local deadline = tick() + 25
        pcall(function()
            while tick() < deadline do
                local root, anchor = getRoot(), anchorOf(npc)
                if not root or not anchor then break end
                if (root.Position - anchor.Position).Magnitude <= 8 then
                    near = true
                    break
                end
                travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)), true)
                task.wait(0.2)
            end
        end)
    end
    local ok, reply = true, nil
    for _ = 1, 3 do
        ok, reply = pcall(function() return commF:InvokeServer(style.remote) end)
        if not ok or reply == false then
            dbg("The game did not take the buy of " .. style.name)
        end
        task.wait(0.4)
    end
    state.shopping = false
    dbg("Buy " .. style.name .. " from " .. (npc and "the teacher" or "far away")
        .. (npc and (near and " (stood at it)" or " (could not reach it)") or " (no teacher was seen)"))
    return true
end

local function buyAbility(remote, what)
    local commF = shopRemote()
    if not commF then
        dbg("CommF_ remote missing")
        return false
    end
    if state.shopping then
        dbg("A buy is already running")
        return false
    end
    state.shopping = true
    local ok, reply = pcall(function() return commF:InvokeServer(remote, what) end)
    state.shopping = false
    if not ok or reply == false then
        dbg("The game did not take the buy of " .. tostring(what))
        return false
    end
    dbg("Asked the game to buy " .. tostring(what))
    return true
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

    if state.shakerAt == nil or now - state.shakerAt > 30 then
        state.shakerAt = now
        stopCameraShaker()
    end

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

    -- A shop buy, a flight or a quest owns the movement while it runs.
    if state.shopping or state.flying or state.questing then return end

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

    local info = CONFIG.AutoQuest and questPanelInfo() or nil

    if CONFIG.AutoQuest then
        hookQuestRemote()
        local remoteInfo = remoteQuestInfo()
        if remoteInfo then info = remoteInfo end
    end
    hookHitRemote()
    hookStatsRemote()

    if info then
        if info.complete then
            state.questDone = true
            state.questDoneMob = info.mentioned or info.target
        elseif info.confirmed then
            state.questDone = false
            state.questDoneMob = nil
        end
    end

    if CONFIG.AutoStore and now - (state.storeAt or 0) > 5 then
        local fruits = carriedFruits()
        if #fruits >= (CONFIG.StoreFruitMin or 3) then
            state.storeAt = now
            local before = #fruits
            local stored = 0
            for _, f in ipairs(fruits) do
                if stored >= 4 then break end
                if storeFruit(f) then stored += 1 end
            end
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
        if state.turnInFailed and now - state.turnInFailedAt > CONFIG.TurnInTimeout then
            state.turnInFailed, state.turnInSince = false, now
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
    if CONFIG.AutoStats then tryUpgradeStats() end

    local needGiver = not questFor(getMyLevel()) or state.questGaveUp
    if CONFIG.AutoQuest and needGiver and not (info and info.confirmed) then
        if state.seekSince == nil then state.seekSince = now end
        if state.seekGaveUp then
            if now - state.seekGaveUpAt >= CONFIG.QuestSeekTimeout then
                state.seekGaveUp = false
                state.seekSince = now
            end
        elseif now - state.seekSince > CONFIG.QuestSeekTimeout then
            dbg("No quest giver answered, farming instead")
            state.seekGaveUp, state.seekGaveUpAt = true, now
        else
            local giver = pickQuestGiver(nil, state.questGaveUp and state.questNpc or nil)
            local prompt = giver and promptOf(giver)
            local anchor = (prompt and anchorOf(prompt.Parent)) or (giver and anchorOf(giver))
            if anchor then
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
        if CONFIG.AutoAttack then autoAttackSwing(nil) end
        return
    end
    state.farming = true

    local quest = CONFIG.AutoQuest and questFor(getMyLevel()) or nil
    local mob = quest and quest.mob or nil
    if info and info.target then mob = info.target end

    local target = getTarget(mob)
    if CONFIG.BossFarm then
        local boss = pickBoss(root, CONFIG.BossRange or 3000)
        if boss then target = boss end
    end
    if state.saberTarget then
        -- a running quest knows which mob it needs
        for _, m in ipairs(collectEnemies(tick())) do
            if m.Name:lower():find(state.saberTarget:lower(), 1, true) then
                target = m
                break
            end
        end
    end
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

    local th = target:FindFirstChildOfClass("Humanoid")
    local dist = (root.Position - er.Position).Magnitude
    local reach = attackRange(LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool"))
    local inRange = dist <= reach + 6
    if th then
        if target ~= state.lastTarget then
            state.lastTarget, state.targetHealth, state.targetAt = target, th.Health, now
            state.hitsConfirmed = 0
            state.targetDist, state.travelAt = dist, now
        elseif th.Health < (state.targetHealth or th.Health) then
            state.targetHealth, state.targetAt = th.Health, now
            state.targetDist, state.travelAt = dist, now
        elseif inRange then
            if now - state.targetAt > CONFIG.StuckTimeout then
                stuckTargets[target] = now + CONFIG.StuckIgnore
                state.lastTarget, state.targetHealth, state.targetAt = nil, nil, 0
                enemyCache, enemyCacheAt = {}, 0
                dbg("Ignoring stuck target " .. target.Name)
                return
            end
        elseif dist < (state.targetDist or dist) - 0.5 then
            state.targetDist, state.travelAt = dist, now
        elseif now - (state.travelAt or now) > CONFIG.StuckTimeout * 3 then
            stuckTargets[target] = now + CONFIG.StuckIgnore
            state.lastTarget, state.targetHealth, state.targetAt = nil, nil, 0
            enemyCache, enemyCacheAt = {}, 0
            dbg("Cannot reach target " .. target.Name)
            return
        end
    end

    local tool = equipWeapon()
    local reach = attackRange(tool)
    local hover = CONFIG.HoverHeight
    -- The hits go through the remote of the game, so the player can stay high
    -- above the mob where its swings cannot reach. Only the plain swing has to
    -- come down close.
    if reach <= CONFIG.MeleeRange and not CONFIG.RemoteAttack then
        hover = math.min(hover, CONFIG.MeleeHover)
    end

    if CONFIG.BringMob then bringMob(target, root) end

    local dx = root.Position.X - er.Position.X
    local dz = root.Position.Z - er.Position.Z
    local flat = math.sqrt(dx * dx + dz * dz)

    local swingTarget, swingAnchor = target, er
    if CONFIG.AutoAttack then
        local close = mobInReach(root, reach)
        -- A boss is not given up for a normal mob that happens to stand near:
        -- the boss is what the boss farm went there for.
        local onBoss = CONFIG.BossFarm and bossKeyOf(target)
        if close and close ~= target and flat > reach and not onBoss then
            if (state.autoBurst or 0) <= now then state.autoBurst = now + 2 end
            if state.autoBurst > now then
                swingTarget = close
                swingAnchor = anchorOf(close) or er
            end
        end
    end

    if CONFIG.BigHitbox then enlargeHitbox(swingTarget) end

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
        local above = CONFIG.RemoteAttack and math.max(hover, CONFIG.HeadHover) or CONFIG.HeadHover
        hoverPos = head.Position + Vector3.new(0, above, 0)
    else
        hoverPos = swingAnchor.Position + Vector3.new(0, hover, 0)
    end
    local top = swingAnchor.Position.Y + (swingAnchor.Size and swingAnchor.Size.Y or 0) / 2
    hoverPos = Vector3.new(hoverPos.X, math.max(hoverPos.Y, top - 1), hoverPos.Z)

    travelTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))

    local sx = root.Position.X - swingAnchor.Position.X
    local sz = root.Position.Z - swingAnchor.Position.Z
    local swingFlat = math.sqrt(sx * sx + sz * sz)
    if now - state.lastAttack >= CONFIG.AttackCooldown
        and swingFlat <= reach then
        if not tool then dbg("No weapon in backpack!"); return end
        if doAttack(tool, swingTarget) then
            state.lastAttack = now
            local many = (state.aoeCount or 1) > 1 and (" +" .. (state.aoeCount - 1) .. " close") or ""
            if swingTarget == target then
                state.status = "Hitting " .. target.Name .. many
                    .. " (" .. state.hitsConfirmed .. " hits)"
            else
                state.status = "Attacking " .. swingTarget.Name .. many
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

-- ================= AUTO QUESTS (Saber) =================
-- The Saber of the First Sea is a puzzle of five steps (the wiki): five green
-- buttons in the Jungle, a torch in the hidden room, a cup filled in the
-- Frozen cave, two NPCs, the Mob Leader and finally the Saber Expert. The
-- script looks the pieces up in the world by name and walks the list.
local SABER_STEPS = {
    {act = "press", name = "Button", note = "the green buttons of the Jungle"},
    {act = "pick",  name = "Torch",  note = "the torch in the hidden Jungle room"},
    {act = "talk",  name = "Sick Man", note = "the Sick Man of the Frozen Village"},
    {act = "talk",  name = "Rich Man", note = "the Rich Man of the Pirate Village"},
    {act = "kill",  name = "Mob Leader", note = "the Mob Leader on Jean-Luc Island"},
    {act = "talk",  name = "Rich Man", note = "the Rich Man again, for the relic"},
    {act = "kill",  name = "Saber Expert", note = "the Saber Expert behind the door"},
}

-- every object of the world whose name has the wanted text in it
local function findParts(text, limit)
    local out = {}
    local ok, list = pcall(function() return Workspace:GetDescendants() end)
    if not ok then return out end
    for _, obj in ipairs(list) do
        if (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Tool"))
            and obj.Name:lower():find(text:lower(), 1, true) then
            table.insert(out, obj)
            if limit and #out >= limit then break end
        end
    end
    return out
end

local function pressPart(part)
    -- a button of the game answers a click or a touch
    pcall(function()
        local cd = part:FindFirstChildWhichIsA("ClickDetector")
        if cd and fireclickdetector then fireclickdetector(cd) end
    end)
    pcall(function()
        local root = getRoot()
        if root and firetouchinterest then
            firetouchinterest(root, part, 0)
            firetouchinterest(root, part, 1)
        end
    end)
end

local function findMob(text)
    for _, mob in ipairs(collectEnemies(tick())) do
        if mob.Name:lower():find(text:lower(), 1, true) then return mob end
    end
    return nil
end

-- One pass at the current step of the quest.
local function saberStep(step, root)
    if not step then return true end
    if step.act == "press" then
        local best, bestD = nil, nil
        for _, part in ipairs(findParts(step.name, 12)) do
            local anchor = anchorOf(part)
            if anchor then
                local d = (anchor.Position - root.Position).Magnitude
                if bestD == nil or d < bestD then best, bestD = anchor, d end
            end
        end
        if not best then
            state.status = "Saber: no " .. step.name .. " seen"
            return false
        end
        if bestD and bestD > 30 then
            state.status = "Saber: walking to " .. step.name
            travelTo(CFrame.new(best.Position))
            return false
        end
        pressPart(best)
        state.status = "Saber: pressed a " .. step.name
        return true
    elseif step.act == "pick" then
        local best, bestD = nil, nil
        for _, obj in ipairs(findParts(step.name, 8)) do
            local anchor = anchorOf(obj)
            if anchor then
                local d = (anchor.Position - root.Position).Magnitude
                if bestD == nil or d < bestD then best, bestD = anchor, d end
            end
        end
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local have = false
        for _, folder in ipairs({char, backpack}) do
            if folder then
                for _, t in ipairs(folder:GetChildren()) do
                    if t:IsA("Tool") and t.Name:lower():find(step.name:lower(), 1, true) then
                        have = true
                    end
                end
            end
        end
        if have then return true end
        if not best then
            state.status = "Saber: no " .. step.name .. " seen"
            return false
        end
        if bestD and bestD > 12 then
            state.status = "Saber: walking to the " .. step.name
            travelTo(CFrame.new(best.Position))
            return false
        end
        if firetouchinterest then
            pcall(function()
                firetouchinterest(root, best, 0)
                firetouchinterest(root, best, 1)
            end)
        end
        state.status = "Saber: took the " .. step.name
        return true
    elseif step.act == "talk" then
        local npc = nil
        for _, obj in ipairs(findParts(step.name, 4)) do
            if anchorOf(obj) then npc = obj break end
        end
        if not npc then
            state.status = "Saber: " .. step.name .. " not found"
            return false
        end
        local prompt = promptOf(npc)
        local anchor = (prompt and anchorOf(prompt.Parent)) or anchorOf(npc)
        if not anchor then return false end
        if (root.Position - anchor.Position).Magnitude > 8 then
            state.status = "Saber: walking to " .. step.name
            travelTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
            return false
        end
        interactWith(npc, prompt)
        state.status = "Saber: talked to " .. step.name
        return true
    elseif step.act == "kill" then
        state.saberTarget = step.name
        local mob = findMob(step.name)
        if not mob then
            state.saberTarget = nil
            state.status = "Saber: " .. step.name .. " is down"
            return true
        end
        state.status = "Saber: fighting " .. step.name
        return false
    end
    return true
end

local saberIndex = 1
task.spawn(function()
    while true do
        task.wait(1)
        state.questing = CONFIG.AutoSaber and state.enabled
        if CONFIG.AutoSaber and state.enabled then
            local root = getRoot()
            if root then
                local step = SABER_STEPS[saberIndex]
                if step then
                    if not state.saberAt or state.saberAt ~= step.note then
                        state.saberAt = step.note
                        dbg("Saber quest step: " .. step.note)
                    end
                    if saberStep(step, root) then
                        dbg("Saber quest done: " .. step.note)
                        state.saberTarget = nil
                        state.saberAt = nil
                        saberIndex = saberIndex + 1
                        if saberIndex > #SABER_STEPS then
                            dbg("Saber quest finished")
                            CONFIG.AutoSaber = false
                        end
                    end
                end
            end
        end
    end
end)

-- ================= AUTO BUY STYLES =================
-- Every style has its own teacher and its own requirements, so the list is
-- walked in order: the first form before its second form, and the ones with
-- no requirements first. A style the game refuses is simply tried again on
-- the next round.
local styleBuyIndex = 0
task.spawn(function()
    while true do
        task.wait(5)
        if CONFIG.AutoBuyStyles and state.enabled and not state.shopping and not state.flying then
            styleBuyIndex = styleBuyIndex % #STYLE_SHOP + 1
            local style = STYLE_SHOP[styleBuyIndex]
            dbg("Auto buy style: " .. style.name)
            buyStyle(style)
            task.wait(20)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        if CONFIG.AutoBuso and state.enabled then
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
            if not ok then dbg("The haki check failed: " .. tostring(err)) end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        if CONFIG.AntiAfk then
            state.afkTimer += 1
            if state.afkTimer >= (CONFIG.AntiAfkInterval or 120) then
                state.afkTimer = 0
                local cam = Workspace.CurrentCamera
                if cam then
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
local setBotEnabled
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
        cb()
        pcall(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = THEME.accent}):Play()
        end)
        task.delay(0.15, function()
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
makeSlider("Hover Height", 0, 60, CONFIG.HoverHeight,
    function(v) return v.." studs" end, function(v) CONFIG.HoverHeight = v end)
makeToggle("Short Warp", CONFIG.WarpClose, function(v) CONFIG.WarpClose = v end)
makeSlider("Warp Distance", 20, 200, CONFIG.WarpDistance,
    function(v) return v.." studs" end, function(v) CONFIG.WarpDistance = v end)
makeSlider("Void Guard Y", -1000, -50, CONFIG.SafeY,
    function(v) return tostring(v).." studs" end, function(v) CONFIG.SafeY = v end)

makeHeader("WORLD (SEA)")
makeButton("Go to Sea 1", function() task.spawn(function() travelToWorld(1) end) end)
makeButton("Go to Sea 2", function() task.spawn(function() travelToWorld(2) end) end)
makeButton("Go to Sea 3", function() task.spawn(function() travelToWorld(3) end) end)
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
            state.status = "Flying to " .. islandName
            task.spawn(function()
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
makeToggle("Bring Mob", CONFIG.BringMob, function(v) CONFIG.BringMob = v end)
makeSlider("Bring Mob Count", 0, 10, CONFIG.BringMobCount,
    function(v) return v == 0 and "All mobs of the kind" or (v.." mobs") end,
    function(v) CONFIG.BringMobCount = v end)

showTab(3) -- FIGHT
makeHeader("COMBAT")
makeSegment("Weapon", {"Melee", "Sword", "Fruit", "Gun"}, CONFIG.WeaponMode,
    function(v) CONFIG.WeaponMode = v end)
makeToggle("Auto Attack", CONFIG.AutoAttack, function(v) CONFIG.AutoAttack = v end)
makeToggle("Fast Attack", CONFIG.FastAttack, function(v) CONFIG.FastAttack = v end)
makeToggle("Remote Attack", CONFIG.RemoteAttack, function(v) CONFIG.RemoteAttack = v end)
makeToggle("AOE (all mobs in reach)", CONFIG.Aoe, function(v) CONFIG.Aoe = v end)
makeSlider("AOE Range", 40, 200, CONFIG.AoeRange,
    function(v) return v.." studs" end, function(v) CONFIG.AoeRange = v end)
makeToggle("Auto Buso (Haki)", CONFIG.AutoBuso, function(v) CONFIG.AutoBuso = v end)
makeToggle("Big Hitbox", CONFIG.BigHitbox, function(v) CONFIG.BigHitbox = v end)
makeSlider("Hitbox Size", 4, 40, CONFIG.HitboxSize,
    function(v) return tostring(v) end, function(v) CONFIG.HitboxSize = v end)
makeSlider("Swing Reach", 0, 200, CONFIG.HitboxMagnitude,
    function(v) return v.." studs" end, function(v) CONFIG.HitboxMagnitude = v end)
makeSlider("Head Hover", 0, 8, CONFIG.HeadHover,
    function(v) return v.." studs" end, function(v) CONFIG.HeadHover = v end)
makeHint("Melee keeps its real, short reach - guns and fruits reach 70 studs")
makeSlider("Attack Cooldown", 5, 100, math.floor(CONFIG.AttackCooldown*100),
    function(v) return string.format("%.2fs", v/100) end,
    function(v) CONFIG.AttackCooldown = v/100 end)

makeHeader("AUTO QUESTS")
makeToggle("Auto Saber (First Sea puzzle)", CONFIG.AutoSaber,
    function(v) CONFIG.AutoSaber = v end)
makeHint("Does the Saber puzzle step by step: buttons, torch, cup, NPCs, bosses")

makeHeader("BOSS FARM")
makeToggle("Farm Bosses", CONFIG.BossFarm, function(v) CONFIG.BossFarm = v end)
makeSlider("Boss Range", 500, 8000, CONFIG.BossRange,
    function(v) return v.." studs" end, function(v) CONFIG.BossRange = v end)
makeHint("Takes the nearest boss of the player's level over the quest mob")

makeHeader("MELEE SHOP (buy)")
makeToggle("Auto Buy Styles (in order)", CONFIG.AutoBuyStyles,
    function(v) CONFIG.AutoBuyStyles = v end)
makeHint("Walks to the teacher of each style in turn and buys it")
-- The buy is asked for right away: no walk to the teacher of the style.
for _, style in ipairs(STYLE_SHOP) do
    makeButton("Buy " .. style.name, function()
        state.status = "Buying " .. style.name
        task.spawn(function() buyStyle(style) end)
    end)
end
makeHeader("ABILITIES (buy)")
makeButton("Buy Buso Haki", function()
    task.spawn(function() buyAbility("BuyHaki", "Buso") end)
end)
makeButton("Buy Geppo (Skyjump)", function()
    task.spawn(function() buyAbility("BuyHaki", "Geppo") end)
end)
makeButton("Buy Soru", function()
    task.spawn(function() buyAbility("BuyHaki", "Soru") end)
end)
makeButton("Buy Observation Haki", function()
    task.spawn(function() buyAbility("KenTalk", "Buy") end)
end)

showTab(4) -- STATS
makeHeader("STATS")
makeToggle("Auto Stats", CONFIG.AutoStats, function(v) CONFIG.AutoStats = v end)
makeSegment("Stat", {"Melee","Sword","Gun","Fruit","Defense","All"}, CONFIG.AutoStatTarget,
    function(v) CONFIG.AutoStatTarget = v end)
makeSlider("Stat Wait", 1, 15, CONFIG.AutoStatWait,
    function(v) return v.."s" end, function(v) CONFIG.AutoStatWait = v end)

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
