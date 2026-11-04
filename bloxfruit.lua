-- // Blox Fruits Auto-Farm — Fixed Build
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
    EatFruit        = true,    -- eat the fruit right after picking it up
    QuestTurnIn     = true,    -- hand completed quests back to the quest giver
    AntiAfk         = true,    -- keep the session alive while the bot runs
    AntiAfkInterval = 120,     -- seconds between two anti-AFK nudges
    AttackCooldown  = 0.15,
    FastAttack      = true,     -- remove the game's attack cooldown
    RemoteAttack    = true,     -- send the swing through the game's own remotes
    HitboxMagnitude = 120,      -- how far the melee swing reaches
    WeaponMode      = "Melee", -- Melee | Sword | Fruit | Gun
    MeleeRange      = 10,      -- melee needs to be close to connect
    GunRange        = 60,      -- guns reach much further
    MeleeHover      = 4,       -- stay low so the swing hits
    BringMob        = false,   -- drag the mob to the player
    BringMobRange   = 8,
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
        local weapon = equip(entry.tool)
        if weapon then return weapon end
    end
    
    -- ถ้าหาไม่เจอจริงๆ ค่อยใช้ fallback
    for _, item in ipairs(fallbacks) do
        local tool = equip(item)
        if tool then return tool end
    end

    return nil
end


-- Drag the mob to the player so a melee swing actually connects. Only the
-- flat distance counts: the bot hovers above the mob on purpose, and the
-- look direction points down while farming, so a local offset would shove
-- the mob into the ground.
local function bringMob(target, root)
    local allEnemies = collectEnemies(tick())
    if not allEnemies or #allEnemies == 0 then return end
    
    local clusterPos = root.Position + Vector3.new(0, -2, 0) -- จุดสุมใต้ตัว/หน้าผู้เล่น
    local now = tick()
    if now < (state.bringAt or 0) then return end
    state.bringAt = now + 0.15 -- ความถี่ในการอัปเดตตำแหน่งไม่ให้กินเครื่อง

    for _, mob in ipairs(allEnemies) do
        local anchor = anchorOf(mob)
        if anchor then
            local dist = (anchor.Position - root.Position).Magnitude
            -- ดึงเฉพาะมอนสเตอร์ที่อยู่ในรัศมีรอบๆ ไม่ไกลเกินไปเพื่อกันเซิร์ฟเวอร์เตด (Anti-Cheat Kick)
            if dist <= 40 then
                local hum = mob:FindFirstChildOfClass("Humanoid")
                if hum then
                    pcall(function()
                        hum.PlatformStand = true -- ปิดการเคลื่อนไหวปกติของมอนสเตอร์
                        hum.Sit = true
                    end)
                end
                pcall(function()
                    anchor.CanCollide = false
                    -- ล็อกพิกัดให้ซ้อนทับกันเป๊ะๆ ที่จุดศูนย์กลางเดียว
                    anchor.CFrame = CFrame.new(clusterPos)
                    -- ล้างแรงเหวี่ยงและแรงกระเด็น (Knockback) ทั้งหมดทิ้งเป็นศูนย์
                    anchor.AssemblyLinearVelocity = Vector3.zero
                    anchor.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end
end



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

-- ================= QUEST =================
local function questFor(level)
    for _, q in ipairs(CONFIG.QuestList) do
        if level >= q[1] and level <= q[2] then
            return {name = q[3], index = q[4], mob = q[5]}
        end
    end
    return nil
end

local function questKey(q) return q.name .. "#" .. q.index end

-- Mobs whose name contains another mob's name, used to tell "Bandit" and
-- "Bandit Captain" apart when reading the quest panel.
local OTHER_MOBS = {"Bandit Captain", "Desert Bandit Captain"}

-- Every mob name the script knows, longest first so "Bandit Captain" is
-- always preferred over "Bandit".
local KNOWN_MOBS = (function()
    local list = {}
    for _, q in ipairs(CONFIG.QuestList) do table.insert(list, q[5]) end
    for _, m in ipairs(OTHER_MOBS) do table.insert(list, m) end
    table.sort(list, function(a, b) return #a > #b end)
    return list
end)()

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

-- Whole word search that also accepts the plural form ("Bandits").
local function containsWord(text, word)
    local t = text:lower()
    for _, variant in ipairs(pluralForms(word)) do
        local escaped = variant:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        if t:find("%f[%w]" .. escaped .. "%f[^%w]") then return true end
    end
    return false
end

-- Known mob names that are longer versions of another mob's name. A loose
-- match on one of them is the wrong mob ("Bandit" quest, "Bandit Captain" mob).
local function isCompoundMob(name, wanted)
    local key = name:lower()
    local want = wanted:lower()
    for _, m in ipairs(KNOWN_MOBS) do
        local mob = m:lower()
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
        for _, variant in ipairs(pluralForms(name)) do
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
        for _, variant in ipairs(pluralForms(name)) do
            if #t >= #variant and t:sub(-#variant) == variant then
                local before = t:sub(1, #t - #variant)
                if before == "" or before:match("[%s,%.%+]$") then return name end
            end
        end
    end
    return nil
end

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

local function questPanelGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local mainFrame = pg and pg:FindFirstChild("Main")
    return mainFrame and mainFrame:FindFirstChild("Quest")
end

-- ================= UPGRADED: DYNAMIC QUEST PANEL INFO =================
-- อ่านค่าเควสต์จากหน้าจอเกมแบบยืดหยุ่น รองรับการเปลี่ยนแปลงของแพตช์เกมอัตโนมัติ
local function questPanelInfo()
    local qg = questPanelGui()
    if not qg or not qg.Visible then return nil end

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
        
        if m and not giverText and (not mentioned or #m > #mentioned) then 
            mentioned = m 
        end
        if lower:find("complete", 1, true) then saysComplete = true end
        if lower:find("return to", 1, true) then saysReturn = true end
    end

    -- กรณีที่เกมเปลี่ยนฟอร์แมตข้อความเควสต์จน parser อ่านตัวเลขไม่ออก แต่ยังมีข้อความเป้าหมายอยู่
    -- ระบบจะใช้ชื่อมอนสเตอร์ตัวแรกที่สแกนเจอในหน้าต่างเควสต์เป็นเป้าหมายสำรองทันที (Dynamic Fallback)
    if not mentioned and #texts > 0 then
        for _, t in ipairs(texts) do
            local cleanText = t:gsub("%d", ""):gsub("[/%-%.:]", "")
            if #cleanText > 3 and not t:lower():find("level") and not t:lower():find("quest") then
                mentioned = texts[2] or texts[1] -- ดึงข้อความบรรทัดรองในกล่องเควสต์มาใช้ชั่วคราว
                break
            end
        end
    end

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
        mentioned = mentioned or "Bandit", -- ป้องกันค่าว่างด้วย Default เผื่อเกมเปลี่ยนชื่อหน้าต่าง UI
        target = target or mentioned,
        complete = complete,
        confirmed = next(mobs) ~= nil or mentioned ~= nil or saysReturn or saysComplete,
    }
end

local function tryAcceptQuest(info)
    local now = tick()
    if now - state.lastQuestTry < 2 then return end
    state.lastQuestTry = now

    -- A running quest is confirmed by the panel; leave it alone.
    if info and info.confirmed then return end

    local q = questFor(getMyLevel())
    if not q then dbg("No quest bracket for this level"); return end

    -- Same quest already sent and still not visible: back off instead of
    -- re-sending StartQuest every two seconds.
    if state.currentQuest == questKey(q) and now - state.questSentAt < CONFIG.QuestRetry then
        return
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then dbg("CommF_ remote missing"); return end

    -- Third arg is the quest INDEX (1 or 2), not a level.
    -- The game wants to know where we respawn before it gives the quest.
    pcall(function() commF:InvokeServer("SetSpawnPoint") end)
    local ok, err = pcall(function() commF:InvokeServer("StartQuest", q.name, q.index) end)
    state.currentQuest = questKey(q)
    state.questSentAt = tick() -- measured after the call, not before
    if ok then
        dbg("Quest sent: " .. q.name .. " #" .. q.index)
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
local function pickQuestGiver(mobName)
    local root = getRoot()
    if not root then return nil end
    local best, bestD, exact, exactD = nil, math.huge, nil, math.huge
    for _, npc in ipairs(questGivers()) do
        local anchor = anchorOf(npc)
        if anchor then
            local d = (root.Position - anchor.Position).Magnitude
            local n = npc.Name:lower()
            if mobName then
                if containsWord(n, mobName) and not isCompoundMob(n, mobName) then
                    if d < exactD then exact, exactD = npc, d end
                end
            elseif d < bestD then
                best, bestD = npc, d
            end
        end
    end
    return exact or best
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
            local key = mobKey(obj.Name)
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

-- The game sends the swing itself through two remotes. Firing them is what
-- really hits: on a phone there is no mouse click to do it for us.
local function remoteAttack(target)
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
    pcall(function() id = regAttack:FireServer(0.5, 1) end)
    if type(id) ~= "string" then
        state.attackId = (state.attackId or 0) + 1
        id = string.format("%08x", state.attackId)
    end
    pcall(function() regHit:FireServer(part, {}, nil, id) end)
    return true
end

local function doAttack(tool, target)
    if CONFIG.FastAttack then fastAttack() end
    -- The remote is the real swing; the tool is only the fallback.
    if CONFIG.RemoteAttack and remoteAttack(target) then return true end
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
                    moveTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
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

    if info and info.complete and CONFIG.QuestTurnIn then
        -- Try again later, but never sit at the giver forever.
        if state.turnInFailed and now - state.turnInFailedAt > CONFIG.TurnInTimeout then
            state.turnInFailed, state.turnInSince = false, now
        end
        if not state.turnInFailed then
            local giver = pickQuestGiver(info.mentioned)
            local prompt = giver and promptOf(giver)
            local anchor = (prompt and anchorOf(prompt.Parent)) or (giver and anchorOf(giver))
            if anchor and prompt then
                if state.turnInSince == nil then state.turnInSince = now end
                if now - state.turnInSince <= CONFIG.TurnInTimeout then
                    state.status = "Turning in quest"
                    moveTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
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

    -- No quest known for this level (past the table above): ask a giver.
    if CONFIG.AutoQuest and not questFor(getMyLevel()) and not (info and info.confirmed) then
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
            local giver = pickQuestGiver(nil)
            local prompt = giver and promptOf(giver)
            local anchor = (prompt and anchorOf(prompt.Parent)) or (giver and anchorOf(giver))
            if anchor then
                state.status = "Looking for a quest"
                moveTo(CFrame.new(anchor.Position + Vector3.new(0, 3, 0)))
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
            moveTo(anchor.CFrame + Vector3.new(0, CONFIG.HoverHeight, 0))
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
    moveTo(CFrame.new(hoverPos) * CFrame.Angles(math.rad(-90), 0, 0))

    local sx = root.Position.X - swingAnchor.Position.X
    local sz = root.Position.Z - swingAnchor.Position.Z
    local swingFlat = math.sqrt(sx * sx + sz * sz)
    if now - state.lastAttack >= CONFIG.AttackCooldown
        and swingFlat <= reach then
        if not tool then dbg("No weapon in backpack!"); return end
        if doAttack(tool, swingTarget) then
            state.lastAttack = now
            if swingTarget == target then
                state.status = "Hitting " .. target.Name
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

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -16, 1, -120)
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

local expandedH, collapsedH = 540, 34
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    TweenService:Create(main, TweenInfo.new(0.18), {
        Size = minimized and UDim2.new(0,320,0,collapsedH) or UDim2.new(0,320,0,expandedH)
    }):Play()
    content.Visible = not minimized
end)

-- ===== BUILDERS =====
local function makeHeader(text)
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1,0,0,20)
    h.BackgroundTransparency = 1
    h.Text = text; h.TextColor3 = THEME.subtext
    h.Font = THEME.fontBold; h.TextSize = 10
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.LayoutOrder = #content:GetChildren()
    h.Parent = content
end

local function makeHint(text)
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1,0,0,16)
    h.BackgroundTransparency = 1
    h.Text = text; h.TextColor3 = THEME.subtext
    h.Font = THEME.font; h.TextSize = 10
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.LayoutOrder = #content:GetChildren()
    h.Parent = content
end

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
    container.LayoutOrder = #content:GetChildren(); container.Parent = content

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
    c.LayoutOrder = #content:GetChildren(); c.Parent = content

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

-- ===== BUILD =====
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

makeHeader("MOVEMENT")
makeSegment("Mode", {"Walk","Tween","Teleport"}, CONFIG.MovementMode,
    function(v) CONFIG.MovementMode = v end)
makeSlider("Move Speed", 50, 500, CONFIG.MoveSpeed,
    function(v) return v.." st/s" end, function(v) CONFIG.MoveSpeed = v end)
makeSlider("Hover Height", 0, 30, CONFIG.HoverHeight,
    function(v) return v.." studs" end, function(v) CONFIG.HoverHeight = v end)
makeSlider("Void Guard Y", -1000, -50, CONFIG.SafeY,
    function(v) return tostring(v).." studs" end, function(v) CONFIG.SafeY = v end)

makeHeader("COMBAT")
makeSegment("Weapon", {"Melee", "Sword", "Fruit", "Gun"}, CONFIG.WeaponMode,
    function(v) CONFIG.WeaponMode = v end)
makeToggle("Auto Attack", CONFIG.AutoAttack, function(v) CONFIG.AutoAttack = v end)
makeToggle("Fast Attack", CONFIG.FastAttack, function(v) CONFIG.FastAttack = v end)
makeToggle("Remote Attack", CONFIG.RemoteAttack, function(v) CONFIG.RemoteAttack = v end)
makeToggle("Big Hitbox", CONFIG.BigHitbox, function(v) CONFIG.BigHitbox = v end)
makeToggle("Bring Mob", CONFIG.BringMob, function(v) CONFIG.BringMob = v end)
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
makeSlider("Attack Cooldown", 0, 100, math.floor(CONFIG.AttackCooldown*100),
    function(v) return string.format("%.2fs", v/100) end,
    function(v) CONFIG.AttackCooldown = v/100 end)

makeHeader("FRUIT")
makeToggle("Auto Store", CONFIG.AutoStore, function(v) CONFIG.AutoStore = v end)
makeSlider("Store From", 1, 10, CONFIG.StoreFruitMin,
    function(v) return v.." fruits" end, function(v) CONFIG.StoreFruitMin = v end)
makeSlider("Scan Radius", 500, 10000, CONFIG.FruitScanRadius,
    function(v) return tostring(v) end, function(v) CONFIG.FruitScanRadius = v end)

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
        infoLabel.Text = string.format("Lv %d • Fruits: %d • Quest: %s",
            getMyLevel(), state.fruitsFound, tostring(state.currentQuest))
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
