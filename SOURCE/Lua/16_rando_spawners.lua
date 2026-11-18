-- Rift Apart Randomizer dev 10.12: the spawner layer shared by enemy.lua and boss.lua (rivet_hook, Lua 5.4).
--
-- dev 10.27: THE ENEMY RANDOMIZER NOW USES "THE VARIABLE ROUTE" (section SP.V below): it writes another enemy's
-- template into a spawner's script variable before that spawner runs - the method your game proved in round37
-- (dev 10.26 spawnproof). The census / Prius route described next is what the Boss and Chaos Randomizers still use;
-- it never found a Templates list in your game (every log since 10.12), so those two still change nothing.
--
-- OPTIONAL. This file does nothing by itself: it only works for the two features that register with
-- it (enemy.lua: regular enemies, boss.lua: boss-tier enemies). Without it, both say so in rivet.log
-- and stay off; without them, it never reads or writes anything. Removing any of the three files
-- never touches the rest of the randomizer (10_rando_runtime.lua lists them as optional).
--
-- HOW AN ENEMY IS CHANGED (and why progression keeps working)
--   The game's combat encounters spawn their enemies with SpawnerScriptAction nodes in the level's
--   scripts (neptuwunium/rivet DDL, SpawnerScriptActionPrius: Templates, SpawnLocations, NumSpawns,
--   MaxSimultaneousSpawns, OnNumDeadTrigger, ...). The node keeps its own count of what it spawned and
--   what died, puts its spawns into its actor group and fires its outputs ("all dead", "num dead")
--   that open doors, finish objectives and start the next wave. The randomizer changes ONLY the
--   actor template ids in the node's Templates list, in memory, before the node runs. It never
--   deletes an enemy, never spawns one itself, never fires a node output and never writes a mission or
--   objective. The encounter's own node spawns the new enemy at the original spawn points, counts its
--   death like the original's and completes the encounter itself: one completion, at the right time,
--   from the game's own logic. A multi-enemy encounter completes when the node's own count says so.
--
-- WHAT IS NOT KNOWN UNTIL IT IS SEEN IN YOUR GAME (so nothing is guessed)
--   * Where Templates sits in a live node: found per node by a signature of the DDL layout (three
--     dynamic arrays 24 bytes apart, the eight flag bytes after them, sane counts), never assumed.
--     dev 10.17: it is in the node's Prius (rivet.component(...).prius), read at FactoryGroup +8 and
--     checked with that signature; the instance (too small in your game) is only a fallback.
--     A node that does not match is left alone (RANDO-SPAWNERS says why).
--   * What an actor template is: learned when the game itself spawns it. The spawned actor is asked
--     for the bot components of the DDL (SP.FAMILY_CLASSES): a turret, a flyer, a swarmer, a ground
--     bot, a large bot, a story boss, a friendly or a mount. Only templates learned this way are ever
--     used or replaced, and only by one of the same family (a flyer for a flyer, a turret for a
--     turret). Learned templates are kept in the save (state.spawn_learned), so the pool grows as you play.
--   * Story bosses (BossBot* components, the Seekerpede) and friendly bots are never touched.
--
-- SAFETY NETS (each one only ever puts an encounter BACK to its original enemies)
--   * a changed spawner that starts and spawns nothing within SP.SPAWN_TIMEOUT seconds;
--   * a changed spawner whose enemies stay alive SP.STUCK_SECONDS seconds without a death;
--   * a checkpoint loaded SP.DEATH_LIMIT times while a changed encounter was running (deaths, reloads);
--   * a replacement that turns out to be another family than expected;
--   * story boss areas (checkpoints named in SP.BOSS_ZONES): every change is put back while you are there.
--   Such a spawner is put back at once and kept original for this seed (state.spawn_blocked).
--   Spawners already running are never changed; switching a feature off puts its spawners back at once.
--
-- dev 10.13 CHAOS (chaos.lua) is a PRIORITY client without guards: while it is ON it owns every slot
-- (the Enemy and Boss Randomizers keep their own ON/OFF but change nothing), it chooses its own
-- replacements (client.assign), and none of the safety nets above apply to the slots it changed:
-- no story boss area put-back, no timeouts, no retries limit, no family check, no "not started yet"
-- rule. What stays for every client is code integrity: the node must still be the same live instance,
-- the slot must hold what was written, a write is read back, refused writes are not repeated, and a
-- Templates list two nodes share is not written. When Chaos is switched OFF its slots go back to their
-- originals and the Enemy / Boss Randomizers plan again from their own settings.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["16_rando_spawners"] = "10.0.23"   -- the kit check (10_rando_runtime.lua)

RANDO_SPAWNERS = RANDO_SPAWNERS or {}
local SP = RANDO_SPAWNERS
local R = RANDO

local function log(...) pcall(rivet.log, "[rando]", "RANDO-SPAWNERS", ...) end
local function S() return RANDO and RANDO.state end
local function SEED() return RANDO_SEED end
local function say(text, opts) if RANDO and RANDO.say then RANDO.say(text, opts) end end
local function changed() if RANDO and RANDO.mark_changed then RANDO.mark_changed() end end
local function hexaddr(n) return string.format("%X", n) end
local function history(line) if RANDO and RANDO.history then pcall(RANDO.history, line) end end
local function clock() return (os and os.clock and os.clock()) or 0 end
SP.log = log

SP.NODE_CLASS = "SpawnerScriptAction"
SP.HEADER = 0x100                 -- node bytes searched for the layout
SP.PREFERRED_X = 0x50             -- AddToInventoryAction's first field is at +0x50 in your game (round 13 probe: ItemConfig +0x58)
SP.MAX_TEMPLATES = 16
SP.SCAN_LIMIT = 512               -- spawner nodes listed per level
SP.CHECK_PER_FRAME = 2            -- nodes read per frame (rivet_hook's frame budget is shared)
SP.SLICE_SECONDS = 0.002
SP.RESCAN_DELAY = 90              -- frames after a load before the level's spawners are read
SP.SPAWN_TIMEOUT = 20             -- seconds
SP.STUCK_SECONDS = 180
SP.DEATH_LIMIT = 3
SP.LEARN_CAP = 600
SP.BLOCK_CAP = 300
SP.BOSS_ZONES = { "BOSS", "FINALE", "HEAVY_FIGHT", "CHASE" }
SP.BUDGET_SECONDS = 0.003         -- writes per frame stop after this long; the rest follows next frame
SP.CENSUS_RETRIES = 8
SP.SCAN_SPAWNER_COMPONENTS = false -- dev 10.18 listed every Spawner component of the level; your log: "the component
                                   -- scan ran past the frame budget". 10.19 asks each node's own actor instead             -- dev 10.17: a census stopped by the frame budget is started again this often

-- the bot components of the DDL, most specific first: class, family, role. role: "enemy" (enemy.lua),
-- "boss" (boss.lua), "story_boss" / "friendly" / "never" (nobody touches them). Classes whose purpose is
-- not clear from the DDL are "never".
SP.FAMILY_CLASSES = {
  { "BossBotCordelionNefarious", "story_boss", "story_boss" }, { "BossBotNefariousBlimp", "story_boss", "story_boss" },
  { "BossBotNefariousFinale", "story_boss", "story_boss" }, { "BossBotUnderwaterBaseJuice", "story_boss", "story_boss" },
  { "BossBotZordoomMonster", "story_boss", "story_boss" }, { "GameBotSargassoCentipedeBoss", "story_boss", "story_boss" },
  { "BossBase", "story_boss", "story_boss" },
  { "GameBotClankLemming", "friendly", "friendly" }, { "GameBotShooterSheep", "friendly", "friendly" },
  { "GameBotShooterTestDummy", "friendly", "friendly" }, { "NPCInfobot", "friendly", "friendly" },
  -- dev 10.31: round41 - these are the Nefarious troopers (enm_neo_nefarious_shooter on Cordelion, _sniper in Zurkon
  -- C5), spawned by combat factories. 10.12-10.30 called them "friendly", so no Nefarious trooper was ever changed or
  -- used. The jetpack one first (it also has the plain class).
  { "GameBotShooterJetPackNoFiring", "flyer", "enemy" }, { "GameBotShooterNoFiring", "ground", "enemy" },
  { "GameBotMountBeast", "mount", "never" }, { "GameBotMountBeetle", "mount", "never" },
  { "GameBotMountFlyer", "mount", "never" }, { "GameBotMountKit", "mount", "never" },
  { "NPCBot", "friendly", "friendly" }, { "BotHexapod", "unclear", "never" },
  { "GameBotPufferFish", "hazard", "never" }, { "GameBotPoolShark", "unclear", "never" },
  { "GameBotMrFunGuy", "unclear", "never" }, { "GameBotTelepathipus", "unclear", "never" },
  { "GameBotGrunthor", "large", "boss" }, { "GameBotMeleeLarge", "large", "boss" }, { "GameBotTankBase", "large", "boss" },
  { "GameBotDoom", "large", "boss" }, { "GameBotMangler", "large", "boss" },
  { "GameBotShooterArmoredTransport", "large", "boss" },
  { "GameBotShooterTurret", "turret", "enemy" },
  { "GameBotMeleeSwarmerGroundFlyer", "flyer", "enemy" }, { "GameBotMeleeFlier", "flyer", "enemy" },
  { "GameBotShooterNymphFlyer", "flyer", "enemy" }, { "GameBotShooterHeli", "flyer", "enemy" },
  { "GameBotShooterJetPack", "flyer", "enemy" }, { "GameBotDarterBat", "flyer", "enemy" },
  { "GameBotShooterBlargSaucer", "flyer", "enemy" }, { "GameBotShooterBlargBomber", "flyer", "enemy" },
  { "GameBotMeleeSwarmerBurrower", "swarmer", "enemy" }, { "GameBotMeleeSwarmerJumper", "swarmer", "enemy" },
  { "GameBotMeleeSwarmer", "swarmer", "enemy" }, { "GameBotAmoeboid", "swarmer", "enemy" },
  { "GameBotShooterExtermibot", "ground", "enemy" }, { "GameBotShooterConstructorBot", "ground", "enemy" },
  { "GameBotShooterMrsZurkonMinion", "ground", "enemy" }, { "GameBotMeleeBase", "ground", "enemy" },
  { "GameBotShooterBase", "ground", "enemy" }, { "GameBotShooter", "ground", "enemy" },
}
SP.ROLE_OF_FAMILY = {}
for _, e in ipairs(SP.FAMILY_CLASSES) do SP.ROLE_OF_FAMILY[e[2]] = SP.ROLE_OF_FAMILY[e[2]] or e[3] end
-- dev 10.31: class -> family today (a save's registry keeps the family of the kit that learned it: its entries are
-- read through this, so a reclassified class takes effect on old saves too)
SP.FAMILY_BY_CLASS = {}
for _, e in ipairs(SP.FAMILY_CLASSES) do SP.FAMILY_BY_CLASS[e[1]] = SP.FAMILY_BY_CLASS[e[1]] or e[2] end

-- session state (a new Lua VM starts empty; what must outlive it is in RANDO.state)
SP.clients = SP.clients or {}
SP.client_order = SP.client_order or {}
SP.frame = SP.frame or 0
SP.level = nil                    -- the census of the loaded level
SP.spawned_by = {}                -- spawned actor handle -> { uid, tid }
SP.session = SP.session or { choice = {} }
SP.retries = {}                   -- uid -> checkpoint loads while its changed encounter ran
SP.zone = nil                     -- the story boss zone you are in (a checkpoint name), or nil
SP.stats = { applied = 0, reverted = 0, blocked = 0 }
SP.written = {}                   -- slot address -> { uid, orig, cur, owner, expect }: what this session wrote
SP.started_handles = {}           -- spawner handle -> frame it started (also before the census has read it)
SP.started_locs = {}              -- dev 10.18: spawn point uid -> { frame }: spawns seen before the census read the level
SP.tpl_seen = SP.tpl_seen or {}   -- dev 10.18: template ids whose template actor was asked (this session)
SP.tpl_class = SP.tpl_class or {} -- dev 10.18: template id -> its bot class (from its template actor or a spawn)
SP.revert_pending = {}            -- client name -> why: its slots are being put back (over a few frames if many)

-- ---------------------------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------------------------
local HEXB = {}
for i = 0, 255 do
  local hi, lo = string.format("%02X", i), string.format("%02x", i)
  local ch = string.char(i)
  HEXB[hi] = ch; HEXB[lo] = ch; HEXB[hi:sub(1, 1) .. lo:sub(2, 2)] = ch; HEXB[lo:sub(1, 1) .. hi:sub(2, 2)] = ch
end
local function bytes_of(text)
  local hex = (text or ""):gsub("[^%x]", "")
  if #hex % 2 == 1 then hex = hex:sub(1, #hex - 1) end
  if #hex == 0 then return {} end
  return { (hex:gsub("%x%x", HEXB)):byte(1, -1) }
end
local function u32(b, i)
  if not b[i + 3] then return nil end
  return b[i] + b[i + 1] * 0x100 + b[i + 2] * 0x10000 + b[i + 3] * 0x1000000
end
local function s32(b, i) local v = u32(b, i); if v and v >= 0x80000000 then v = v - 0x100000000 end; return v end
local function hex64(b, i)
  if not b[i + 7] then return nil end
  return string.format("%02X%02X%02X%02X%02X%02X%02X%02X", b[i + 7], b[i + 6], b[i + 5], b[i + 4], b[i + 3], b[i + 2], b[i + 1], b[i])
end
local function ptr64(b, i)
  local h = hex64(b, i)
  if not h or h:sub(1, 1):match("[89A-F]") then return nil end    -- above 2^63: not a user-space pointer
  return tonumber(h, 16)
end
local function le_hex(hex)
  local t = {}
  for k = 15, 1, -2 do t[#t + 1] = hex:sub(k, k + 1) end
  return table.concat(t, " ")
end
local function valid_ptr(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF and p % 8 == 0 end
local function read_bytes(addr, len)
  local ok, text = pcall(rivet.read, hexaddr(addr), len)
  if not ok or not text then return nil end
  return bytes_of(text)
end
local function read_id(addr)
  local b = read_bytes(addr, 8)
  return b and hex64(b, 1)
end
SP.bytes_of, SP.hex64, SP.le_hex = bytes_of, hex64, le_hex

-- FNV-1a, 32 bit: the same text gives the same number in every game and in the tests
function SP.hash(text)
  local h = 0x811C9DC5
  for i = 1, #text do h = ((h ~ text:byte(i)) * 0x01000193) & 0xFFFFFFFF end
  return h
end
-- rendezvous ranking: adding a candidate changes a pick only if the new one wins, so a pool that
-- grows while you play keeps most encounters as they were
function SP.rank(key, candidates)
  local scored = {}
  for _, c in ipairs(candidates) do scored[#scored + 1] = { c = c, h = SP.hash(key .. "|" .. c) } end
  table.sort(scored, function(a, b) if a.h ~= b.h then return a.h > b.h end return a.c < b.c end)
  local out = {}
  for i, e in ipairs(scored) do out[i] = e.c end
  return out
end
local function seed_key() local s = SEED(); return (s and (tostring(s.seed) .. "/" .. tostring(s.fingerprint))) or "no-seed" end
local function sorted_keys(t)
  local k = {}
  for key in pairs(t) do k[#k + 1] = key end
  table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
  return k
end
local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

-- ---------------------------------------------------------------------------------------------
-- clients (enemy.lua, boss.lua) and their switches
-- ---------------------------------------------------------------------------------------------
-- client = { name = "enemy", role = "enemy", label = "Enemy Randomizer", state_key = "enemy_rando",
--            config_key = "enemy_randomizer", unique = false }
function SP.register(client)
  if SP.clients[client.name] then return SP.clients[client.name] end
  SP.clients[client.name] = client
  SP.client_order[#SP.client_order + 1] = client.name
  table.sort(SP.client_order)
  local what = (client.role == "boss") and "boss-tier enemies" or (client.role == "any") and
               "every enemy and boss, priority, no guards" or "regular enemies"
  log(client.label, "is installed (", what, ")")
  return client
end
-- dev 10.13: the priority client (Chaos) when it is ON, else nil
function SP.priority_client()
  for _, name in ipairs(SP.client_order) do
    local c = SP.clients[name]
    if c.priority and SP.enabled(c) then return c end
  end
  return nil
end
-- does this client's work get the safety nets? (Chaos: guards = false)
local function guarded_name(name)
  local c = name and SP.clients[name]
  return c == nil or c.guards ~= false
end
SP.guarded_name = guarded_name
function SP.client_for_role(role)
  for _, name in ipairs(SP.client_order) do
    local c = SP.clients[name]
    if c.role == role then return c end
  end
  return nil
end
-- ON / OFF: the save's choice, else the setting (enemy_randomizer / boss_randomizer, false by default)
function SP.enabled(client)
  if type(client) == "string" then client = SP.clients[client] end
  if not client then return false end
  local cfg = R and R.config or {}
  if cfg.spawner_runtime == false then return false end
  local s = S()
  local v = s and s[client.state_key]
  if v == nil then v = cfg[client.config_key] == true end
  return v == true
end
function SP.any_enabled()
  for _, name in ipairs(SP.client_order) do if SP.enabled(SP.clients[name]) then return true end end
  return false
end
-- dev 10.27: the clients of the old census / Prius route (boss.lua, chaos.lua); enemy.lua uses the variable route
function SP.legacy(client) return client ~= nil and client.route ~= "vars" end
function SP.any_legacy_enabled()
  for _, name in ipairs(SP.client_order) do
    local c = SP.clients[name]
    if SP.legacy(c) and SP.enabled(c) then return true end
  end
  return false
end

function SP.set(client, on, why)
  if type(client) == "string" then client = SP.clients[client] end
  local s = S()
  if not (client and s) then return false end
  on = on == true
  if SP.enabled(client) == on then return false end
  s[client.state_key] = on
  SP.session.choice[client.state_key] = on        -- this session's choice outlives a later restore
  changed()
  history(string.format("[%s %s] (%s)", client.label:upper(), on and "ON" or "OFF", tostring(why)))
  if not SP.legacy(client) then
    log(client.label, (on and "ON" or "OFF") .. " (" .. tostring(why) .. ")")
    if SP.V and SP.V.on_switch then SP.V.on_switch(on, client) end
    return true
  end
  if on then
    log(client.label, "ON (" .. tostring(why) .. ")")
    if SP.level and SP.level.done then SP.plan("switched on") else SP.schedule_scan("switched on", 1) end
  else
    SP.revert_pending[client.name] = "switched off"
    local n = SP.continue_reverts()
    log(client.label, "OFF (" .. tostring(why) .. "):", n, "spawner slot(s) put back to their original enemies" ..
        (next(SP.revert_pending) and " (the rest over the next frames)" or ""))
    if not SP.any_legacy_enabled() then SP.job = nil else SP.replan = true end   -- the others plan again (dev 10.13)
  end
  return true
end
function SP.toggle(client, why)
  if type(client) == "string" then client = SP.clients[client] end
  if not client then return false end
  local on = not SP.enabled(client)
  SP.set(client, on, why)
  local sub = on and "takes effect for spawners that have not spawned yet" or "every spawner has its original enemies again"
  say(client.label .. ": " .. (on and "ON" or "OFF"), { type = "center", sub = sub, duration = 5 })
  return on
end

-- after the companion's restore: a choice made this session wins; what this session learned is kept
function SP.after_restore(live)
  local s = S()
  if not s then return end
  for k, v in pairs(SP.session.choice) do s[k] = v end
  if type(live) == "table" and live ~= s then
    for _, k in ipairs({ "spawn_learned", "spawn_blocked", "enemy_reg", "enemy_groups" }) do
      if type(live[k]) == "table" and next(live[k]) ~= nil then
        s[k] = s[k] or {}
        for key, v in pairs(live[k]) do if s[k][key] == nil then s[k][key] = v end end
      end
    end
  end
  for _, name in ipairs(SP.client_order) do
    local c = SP.clients[name]
    if c.after_restore then pcall(c.after_restore, live) end
  end
  -- a feature the restored save has off: whatever this session changed for it goes back
  for _, name in ipairs(SP.client_order) do
    if not SP.enabled(SP.clients[name]) then SP.revert_pending[name] = "off in the restored save" end
  end
  if next(SP.revert_pending) then SP.continue_reverts() end
  if not SP.any_legacy_enabled() then SP.job = nil else SP.replan = true end
end
-- kept over a New Game: the switches and what was learned about the game (not about the run)
SP.KEEP_OVER_NEW_GAME = { "enemy_rando", "boss_rando", "spawn_learned", "spawn_blocked", "enemy_reg", "enemy_groups",
                          "enemy_combat" }   -- dev 10.30: combat evidence (verified / rejected replacement pairs)

-- ---------------------------------------------------------------------------------------------
-- learning: what an actor template is
-- ---------------------------------------------------------------------------------------------
-- read: the save's table or an empty one (reading never adds anything to the save); write: created then
local EMPTY = setmetatable({}, { __newindex = function() error("read-only") end })
local function learned_t(write)
  local s = S(); if not s then return EMPTY end
  if write then s.spawn_learned = s.spawn_learned or {} end
  return s.spawn_learned or EMPTY
end
local function blocked_t(write)
  local s = S(); if not s then return EMPTY end
  if write then s.spawn_blocked = s.spawn_blocked or {} end
  return s.spawn_blocked or EMPTY
end
-- "family" or "family|hb" (a health bar was shown for it: boss tier)
function SP.family_of(tid)
  local v = learned_t()[tid]
  if type(v) ~= "string" then return nil, false end
  local fam, hb = v:match("^([%w_]+)(|?h?b?)$")
  return fam, hb == "|hb"
end
function SP.role_of(tid)
  local fam, hb = SP.family_of(tid)
  if not fam then return nil end
  local role = SP.ROLE_OF_FAMILY[fam] or "never"
  if role == "enemy" and hb then role = "boss" end     -- a regular bot with its own health bar is boss tier
  return role, fam, hb
end
-- the pool key: a replacement must share it (same tier, same movement family)
function SP.pool_key(tid)
  local role, fam = SP.role_of(tid)
  if role ~= "enemy" and role ~= "boss" then return nil end
  return role .. ":" .. fam, role
end

-- the bot components of a spawned actor (its first class of SP.FAMILY_CLASSES)
SP.CLASS_SUFFIXES = { "", "Prius" }
SP.unclassified_logged = SP.unclassified_logged or {}
function SP.classify_actor(handle, fast)
  if handle == nil then return nil end
  SP.last_classes = nil
  -- dev 10.17: one rivet.components call lists the actor's classes (instead of ~90 failing lookups)
  local okl, names = pcall(rivet.components, handle)
  if okl and type(names) == "table" and #names > 0 then
    local have = {}
    for _, n in ipairs(names) do
      have[tostring(n)] = true
      if tostring(n):sub(-5) == "Prius" then have[tostring(n):sub(1, -6)] = true end
    end
    SP.last_classes = names                                              -- dev 10.30: SP.V's initialization check
    for _, e in ipairs(SP.FAMILY_CLASSES) do if have[e[1]] then return e[2], e[1] end end
    -- not one class of the table: said once per class list, so the next log shows what bots really are
    local bots = {}
    for _, n in ipairs(names) do
      local t = tostring(n)
      if t:find("Bot", 1, true) or t:find("Boss", 1, true) or t:find("NPC", 1, true) then bots[#bots + 1] = t end
    end
    local key = table.concat(bots, ",")
    if #bots > 0 and not SP.unclassified_logged[key] and count(SP.unclassified_logged) < 20 then
      SP.unclassified_logged[key] = true
      log("spawned actor not classified (left alone):", key)
    end
    if #bots > 0 then return nil end
  end
  if fast then return nil end           -- dev 10.18: a template actor with no bot class is not asked ~90 times
  for _, e in ipairs(SP.FAMILY_CLASSES) do
    for _, suffix in ipairs(SP.CLASS_SUFFIXES) do
      local ok, c = pcall(rivet.component, handle, e[1] .. suffix)
      if ok and type(c) == "table" and c.address then return e[2], e[1] end
    end
  end
  return nil
end
-- dev 10.18: a template id is the uid of a template actor loaded with the level: its components say what
-- it spawns, before any fight (rivet.find_uid + rivet.components). Asked once per template per session.
function SP.learn_template(tid)
  if not tid then return end
  local fam = SP.tpl_seen[tid]                    -- the answer is kept for the session; the save may be
  if fam == nil then                              -- replaced (restore, New Game), so it is learned again there
    SP.pause()
    local loaded, h = SP.uid_loaded(tid)
    if not loaded then return end                 -- not loaded (yet): asked again at the next census
    local cls
    fam, cls = SP.classify_actor(h, true)
    SP.tpl_seen[tid] = fam or false
    if fam then SP.tpl_class[tid] = cls end
  end
  if fam and not SP.family_of(tid) then SP.learn(tid, fam, "template actor " .. tostring(SP.tpl_class[tid])) end
end
function SP.learn(tid, family, why)
  local L = learned_t(true)
  local old = L[tid]
  local hb = type(old) == "string" and old:find("|hb", 1, true) ~= nil
  local v = family .. (hb and "|hb" or "")
  if old == v then return false end
  if old == nil and count(L) >= SP.LEARN_CAP then return false end
  L[tid] = v
  changed()
  SP.replan = true                  -- idle spawners of the loaded level may use it now
  log("learned", tid, "=", family, "(" .. tostring(why) .. ")")
  return true
end
function SP.learn_health_bar(tid)
  local L = learned_t(true)
  local old = L[tid]
  if type(old) ~= "string" or old:find("|hb", 1, true) then return false end
  L[tid] = old .. "|hb"
  changed()
  SP.replan = true
  log("learned", tid, "shows a health bar: boss tier from now on")
  return true
end

-- ---------------------------------------------------------------------------------------------
-- the census: the level's spawner nodes, their Templates found by the layout's signature
-- ---------------------------------------------------------------------------------------------
-- dynamic array header { pointer, count, capacity } at byte i (1-based)
local function array_at(b, i)
  local p, n, cap = ptr64(b, i), u32(b, i + 8), u32(b, i + 12)
  if n == nil or cap == nil then return nil end
  -- dev 10.18: { T *data; int32 count; int32 capacity } (rivet_hook src/ddl_visit.cpp, checked on live
  -- instances). Only the count is trusted: a Prius loaded from an asset need not keep a tidy capacity
  if n > 64 then return nil end
  if n > 0 and not valid_ptr(p) then return nil end
  return { ptr = p, count = n }
end
-- SpawnerScriptActionPrius (rivet DDL; it extends SpawnerPrius, the same fields through +116):
-- FactoryGroup +8, FactorySelectionMethod +24, Templates +32, TemplateSelectionMethod +48,
-- SpawnLocations +56, LocationSelectionMethod +72, 8 bools +76..83, NumSpawns +108,
-- MaxSimultaneousSpawns +112, then (script action only) ActionType +120 (60), MaxActivations +128.
-- x = where FactoryGroup is (offset). short = a SpawnerPrius (120 bytes): no ActionType / MaxActivations.
-- Returns the layout, or nil and why.
function SP.layout_at(b, x, short)
  local i = x + 1
  if not b[i + (short and 107 or 127)] then return nil, "too few bytes" end
  local fac, tpl, loc = array_at(b, i), array_at(b, i + 24), array_at(b, i + 48)
  if not (fac and tpl and loc) then return nil, "no three lists" end
  if b[i + 16] > 15 or b[i + 40] > 15 then return nil, "selection enums out of range" end
  for k = 68, 75 do if b[i + k] > 1 then return nil, "flag bytes out of range" end end
  local num, maxsim = s32(b, i + 100), s32(b, i + 104)
  if not (num and maxsim) then return nil, "no counts" end
  if num < -1 or num > 10000 or maxsim < -1 or maxsim > 10000 then return nil, "counts out of range" end
  local action, maxact
  if not short then
    action, maxact = s32(b, i + 112), s32(b, i + 120)
    if not maxact or maxact < -1 or maxact > 10000 then return nil, "MaxActivations out of range" end
  end
  -- dev 10.20: three empty lists are what zero-filled memory looks like (your dev 10.19 log: the unused
  -- tail of a Spawner component read as "factory-only spawner"). A real spawner without Templates has
  -- factories or spawn points; only then is it called factory-only.
  if tpl.count < 1 and fac.count < 1 and loc.count < 1 then return nil, "all three lists empty (zeroed memory, not a Prius)" end
  if tpl.count < 1 then return nil, "no Templates (" .. fac.count .. " factories)", "empty" end
  if tpl.count > SP.MAX_TEMPLATES then return nil, tpl.count .. " Templates (more than " .. SP.MAX_TEMPLATES .. ")" end
  return { x = x, templates = tpl, locations = loc, factories = fac.count, num_spawns = num, max_alive = maxsim,
           action = action }
end
-- the one x that matches; nil and the reason otherwise. Mostly-zero bytes can make a place 24 bytes off
-- look like the list too, so when several match, the one with spawn locations and no factories (an
-- ordinary spawner) wins; if that does not decide it, SP.PREFERRED_X among them; else nothing is used.
function SP.find_layout(b)
  local cands = {}
  for x = 0x08, SP.HEADER - 0x88, 8 do
    local l = SP.layout_at(b, x)
    if l then cands[#cands + 1] = l end
  end
  if #cands == 0 then return nil, "no Templates list found" end
  if #cands == 1 then return cands[1] end
  local ordinary = {}
  for _, l in ipairs(cands) do if l.locations.count >= 1 and l.factories == 0 then ordinary[#ordinary + 1] = l end end
  if #ordinary == 1 then return ordinary[1] end
  for _, l in ipairs(#ordinary > 1 and ordinary or {}) do if l.x == SP.PREFERRED_X then return l end end
  return nil, #cands .. " places look like the spawner's fields"
end

function SP.still_valid(rec)
  local ok, c = pcall(rivet.component, rec.actor, rec.class or SP.NODE_CLASS)
  return ok and type(c) == "table" and c.handle == rec.component and tonumber(c.address, 16) == rec.addr
end

-- ---------------------------------------------------------------------------------------------
-- dev 10.18: FINDING A NODE'S PRIUS. Your two logs of 2026-11-17:
--   10.15: every node "cannot read the node"; 10.17: every node "no Prius and the instance is only
--   128 bytes". So rivet_hook's rivet.component gives no `prius` for SpawnerScriptAction (its
--   find_component only follows ComponentInfo.prius, which script actions evidently do not set), and
--   the 128-byte instance is ScriptAction's own header (Component 0x48, instance uid +0x48, graph uid
--   +0x50, plugs +0x58: rivet_hook src/game/script.hpp) plus 32 bytes: no room for the spawner's lists.
-- The Prius is therefore reached by hand, the way the engine reaches it, best route first:
--   1. rivet's `prius`, when it gives one;
--   2. Component.ddlPriusData (instance +0x08) -> holder { vtable, int32 count +8, data +16 } -> data
--      (rivet_hook src/ddl_visit.hpp: the same path rivet takes once it knows the type);
--   3. every pointer in the instance's own 32 bytes (+0x60..+0x78) and the rest of it, each read as the
--      Prius directly and as such a holder.
-- A candidate counts only if its bytes match SpawnerScriptActionPrius exactly at the DDL's offsets
-- (three { pointer, count, capacity } lists, the two enums, the eight flag bytes, sane counts) and, for
-- route 3, its ActionType is 60 or one of its spawn points / templates is a loaded actor's uid
-- (rivet.find_uid). The route that worked is tried first for the next nodes.
-- When no route works, the first nodes' bytes are written to rivet.log (RANDO-SPAWNERS dump), so the
-- next log shows where the fields are.
-- ---------------------------------------------------------------------------------------------
SP.PRIUS_X = 0x08                 -- FactoryGroup's offset in SpawnerScriptActionPrius (rivet DDL)
SP.PRIUS_READ = 0x90              -- bytes of the Prius read (its DDL size is 144)
SP.SPAWNER_PRIUS_READ = 0x78      -- SpawnerPrius (the Spawner component's) DDL size, 120
SP.ACTION_TYPE = 60               -- SpawnerScriptActionPrius.ActionType's value (DDL default)
SP.INSTANCE_READ = 0x80           -- the instance bytes read for routes 2 and 3 (its size in your game)
SP.DUMP_LIMIT = 6                 -- nodes per session whose bytes are logged when no route finds the Prius
SP.dumps = SP.dumps or 0
SP.route_hint = SP.route_hint or nil
SP.route_stats = {}

local function read_ids(ptr, n)
  if n < 1 then return {} end
  local b = read_bytes(ptr, n * 8)
  if not b or #b < n * 8 then return nil end
  local out = {}
  for k = 1, n do out[k] = hex64(b, (k - 1) * 8 + 1) end
  return out
end
SP.read_ids = read_ids

-- is this 64-bit id a loaded actor's uid? (nil when rivet cannot say)
local function uid_loaded(id)
  if not (rivet.find_uid and id) or id == "0000000000000000" then return nil end
  local ok, h = pcall(rivet.find_uid, id)
  if not ok then return nil end
  return h ~= nil and h ~= false, h
end
SP.uid_loaded = uid_loaded

local function hexdump(b, from, n)
  local t = {}
  for k = from, math.min(#b, from + n - 1) do t[#t + 1] = string.format("%02x", b[k]) end
  return table.concat(t, " ")
end
-- dev 10.20: rivet_hook's rivet.log keeps 1024 characters of a line (l_log, a 0x400 buffer): your dev 10.19
-- log lost the last 126 bytes of every 432-byte Spawner dump. Dumps are written SP.DUMP_CHUNK bytes a line.
SP.DUMP_CHUNK = 96
function SP.log_dump(head, b)
  if not b then return end
  if #b == 0 then log(head .. " (0 bytes)"); return end
  for from = 1, #b, SP.DUMP_CHUNK do
    log(string.format("%s +0x%03X: %s", head, from - 1, hexdump(b, from, SP.DUMP_CHUNK)))
  end
end

-- a Prius candidate at `p`: its layout and how sure we are, or nil and why
function SP.try_prius(p, size_hint, short, strict)
  if not valid_ptr(p) then return nil, "not a pointer" end
  local want = short and SP.SPAWNER_PRIUS_READ or SP.PRIUS_READ
  local len = want
  if size_hint and size_hint > 0 and size_hint < len then len = size_hint end
  local b = read_bytes(p, len)
  if not b or #b < (short and 0x74 or 0x88) then return nil, "unreadable" end
  local lay, why, kind = SP.layout_at(b, SP.PRIUS_X, short)
  if not lay then return nil, why, kind end
  lay.bytes = b
  local score = 0
  if lay.action == SP.ACTION_TYPE then score = score + 2 end
  -- the ids must look like the engine's: spawn points and templates are loaded actors
  local tids = read_ids(lay.templates.ptr, lay.templates.count)
  if not tids then return nil, "the Templates list is unreadable" end
  for _, id in ipairs(tids) do if id == "0000000000000000" then return nil, "an empty template" end end
  lay.tids = tids
  local l = lay.locations
  if l.count >= 1 and l.count <= 32 then lay.locs = read_ids(l.ptr, l.count) end
  local hit = uid_loaded(tids[1]) or (lay.locs and lay.locs[1] and uid_loaded(lay.locs[1]))
  if hit then score = score + 2 end
  lay.score = score
  if strict and score < 2 then return nil, "looks like the fields but neither ActionType 60 nor a loaded actor" end
  return lay
end

-- a long search yields to the next frame inside the census (rivet_hook stops a script after 8 ms a frame)
SP.slice_t0 = 0
function SP.pause()
  if coroutine.isyieldable() and clock() - SP.slice_t0 > SP.SLICE_SECONDS then
    coroutine.yield()
    SP.slice_t0 = clock()
  end
end

-- the pointers in a block, 8-aligned, in the order given; skips `skip` offsets
local function pointers_in(b, from, to, skip)
  local out = {}
  for off = from, math.min(to, #b - 8), 8 do
    if not (skip and skip[off]) then
      local p = ptr64(b, off + 1)
      if valid_ptr(p) then out[#out + 1] = { off = off, p = p } end
    end
  end
  return out
end

-- follow a path found before (the same class keeps its layout): { route, off, inner, x }
function SP.follow_path(path, c, addr, inst, short)
  if path.route == "rivet" then
    local pr = c.prius and tonumber(c.prius, 16)
    return pr and SP.try_prius(pr, c.prius_size, short, false)
  end
  if not inst then return nil end
  if path.route == "holder" then
    local holder = ptr64(inst, 9)
    local hb = valid_ptr(holder) and read_bytes(holder, 0x18)
    local data = hb and #hb >= 0x18 and ptr64(hb, 17)
    local lay = data and SP.try_prius(data, nil, short, false)
    if lay then lay.holder_count = s32(hb, 9); lay.prius_addr = data end
    return lay
  end
  if path.route == "inline" then
    local lay = SP.try_prius(addr + path.x - SP.PRIUS_X, nil, true, true)
    if lay then lay.prius_addr = addr + path.x - SP.PRIUS_X end
    return lay
  end
  local p = ptr64(inst, path.off + 1)
  if not valid_ptr(p) then return nil end
  local target = p
  if path.inner then
    local b = read_bytes(p, path.inner + 8)
    target = b and ptr64(b, path.inner + 1)
  elseif path.x then
    target = p + path.x - SP.PRIUS_X
  end
  if not valid_ptr(target) then return nil end
  local lay = SP.try_prius(target, nil, path.short or short, true)
  if lay then lay.prius_addr = target end
  return lay
end

-- routes for one node; returns layout, route name, instance bytes; or nil, every route's reason, inst, empty
SP.DEEP_NODES = 4                 -- nodes per session the deep search (route 4) may run on before a path is known
SP.deep_runs = SP.deep_runs or 0
function SP.find_prius(c, addr, short)
  local tried = {}
  -- dev 10.19: a Spawner component (short) may be bigger than a script node: up to 0x200 of it is read
  local inst_len = short and math.min(0x200, math.max(0x80, (c.size and c.size > 0) and c.size or 0x80))
                   or math.min(SP.INSTANCE_READ, math.max(0x10, (c.size and c.size > 0) and c.size or SP.INSTANCE_READ))
  local inst = read_bytes(addr, inst_len)
  local function done(lay, route, path)
    path.route = path.route or route
    SP.path_hint = path
    SP.route_stats[route] = (SP.route_stats[route] or 0) + 1
    return lay, route, inst
  end
  local function attempt(label, p, hint, strict, sh)
    if not p then return nil end
    SP.pause()
    local lay, why, kind = SP.try_prius(p, hint, (sh == nil) and short or sh, strict)
    if lay then lay.prius_addr = p; return lay end
    tried[#tried + 1] = label .. ": " .. tostring(why)
    if kind == "empty" then tried.empty = true end
    return nil
  end
  -- 0. the path that worked for the last node
  local hint = SP.path_hint
  if hint then
    local lay = SP.follow_path(hint, c, addr, inst, short)
    if lay then return done(lay, hint.route, hint) end
  end
  -- 1. rivet's own prius
  local pr = c.prius and tonumber(c.prius, 16)
  if pr then
    local lay = attempt("rivet", pr, c.prius_size, false)
    if lay then return done(lay, "rivet", { route = "rivet" }) end
  else tried[#tried + 1] = "rivet: no prius" end
  if tried.empty then return nil, table.concat(tried, "; "), inst, true end
  if not inst or #inst < 0x10 then tried[#tried + 1] = "instance unreadable"; return nil, table.concat(tried, "; "), inst end
  -- 2. Component.ddlPriusData -> holder -> data
  local holder = ptr64(inst, 9)
  if valid_ptr(holder) then
    local hb = read_bytes(holder, 0x18)
    local data = hb and #hb >= 0x18 and ptr64(hb, 17)
    if data then
      local lay = attempt("holder", data, nil, false)
      if lay then lay.holder_count = s32(hb, 9); return done(lay, "holder", { route = "holder" }) end
    else tried[#tried + 1] = "holder: no data pointer" end
  else tried[#tried + 1] = "holder: ddlPriusData is " .. tostring(hex64(inst, 9)) end
  if tried.empty then return nil, table.concat(tried, "; "), inst, true end
  -- 2b. dev 10.19: a Spawner component that copied its lists into its own instance (strict: a loaded uid)
  if short then
    for x = 0x48, #inst - 0x74, 8 do
      if SP.layout_at(inst, x, true) then
        local lay = attempt(string.format("inline +0x%X", x), addr + x - SP.PRIUS_X, nil, true, true)
        if lay then return done(lay, "inline", { route = "inline", x = x }) end
      end
    end
  end
  -- 3. a pointer in the instance: to the Prius itself, or to a holder of it
  local own = pointers_in(inst, short and 0x48 or 0x60, #inst - 8)
  local head = pointers_in(inst, 0x10, 0x58, { [0x18] = true })
  local cands = {}
  for _, e in ipairs(own) do cands[#cands + 1] = e end
  for _, e in ipairs(head) do cands[#cands + 1] = e end
  local seen = { [addr] = true }
  for _, e in ipairs(cands) do
    if not seen[e.p] then
      seen[e.p] = true
      local lay = attempt(string.format("+0x%X", e.off), e.p, nil, true)
      if lay then return done(lay, "scan", { route = "scan", off = e.off }) end
      local hb = read_bytes(e.p, 0x18)
      local data = hb and #hb >= 0x18 and ptr64(hb, 17)
      if data and not seen[data] then
        seen[data] = true
        lay = attempt(string.format("+0x%X->+16", e.off), data, nil, true)
        if lay then return done(lay, "scan", { route = "scan", off = e.off, inner = 16 }) end
      end
    end
  end
  -- 4. deep: a runtime object the node points to, holding the spawner's fields itself or a pointer to them
  --    (strict: only with a loaded actor's uid among its ids). A few nodes per session, until a path is known.
  if SP.deep_runs < SP.DEEP_NODES then
    SP.deep_runs = SP.deep_runs + 1
    for _, e in ipairs(cands) do
      SP.pause()
      local b = read_bytes(e.p, 0x100)
      if b and #b >= 0x80 then
        for x = 0x08, #b - 0x74, 8 do
          if SP.layout_at(b, x, true) then
            local lay = attempt(string.format("+0x%X fields at +0x%X", e.off, x), e.p + x - SP.PRIUS_X, nil, true, true)
            if lay then return done(lay, "deep", { route = "deep", off = e.off, x = x, short = true }) end
          end
        end
        for _, q in ipairs(pointers_in(b, 0, #b - 8)) do
          if not seen[q.p] then
            seen[q.p] = true
            local lay = attempt(string.format("+0x%X->+0x%X", e.off, q.off), q.p, nil, true)
            if lay then return done(lay, "deep", { route = "deep", off = e.off, inner = q.off }) end
          end
        end
      end
    end
  else
    tried[#tried + 1] = "deep search not run (" .. SP.DEEP_NODES .. " nodes tried this session)"
  end
  return nil, table.concat(tried, "; "), inst, tried.empty
end

-- ---------------------------------------------------------------------------------------------
-- dev 10.19: THE NODE'S SPAWNER COMPONENT. Your rivet.log with 10.18 dumped six nodes (all alike):
--   +0x08 ddlPriusData 0 | +0x1C own handle 0x406E8E | +0x48/+0x50 uid | +0x58 plugs |
--   +0x60 0x406E8F = the handle of the component made right after the node | +0x64 0x80B003E8 = an
--   actor group (bit 31, ScriptVar's group bit) | +0x68.. counters.
-- So a SpawnerScriptAction keeps no Prius itself: it makes a Spawner component (SpawnerPrius, which
-- SpawnerScriptActionPrius extends: the same Templates / SpawnLocations lists) and keeps its handle at
-- +0x60. That component is asked for on the node's own actor (rivet.component by class name) and used
-- only if its handle is exactly the one at +0x60; its Prius is then found the usual ways (short layout).
-- ---------------------------------------------------------------------------------------------
SP.SPAWNER_HANDLE_AT = 0x60
SP.spawner_diag = SP.spawner_diag or 0
function SP.spawner_of(node, addr)
  local hb = read_bytes(addr + SP.SPAWNER_HANDLE_AT, 4)
  local want = hb and #hb >= 4 and u32(hb, 1)
  if not want or want == 0 or want == 0xFFFFFFFF then return nil, "no component handle at +0x60" end
  local names, listed = { "Spawner" }, nil
  local okl, list = pcall(rivet.components, node.actor)
  if okl and type(list) == "table" then
    local t = {}
    for _, n in ipairs(list) do
      n = tostring(n); t[#t + 1] = n
      if n ~= "Spawner" and n:find("Spawner", 1, true) and not n:find("ScriptAction", 1, true) then names[#names + 1] = n end
    end
    listed = table.concat(t, ",")
  end
  local other = {}
  for _, name in ipairs(names) do
    local ok, c2 = pcall(rivet.component, node.actor, name)
    if ok and type(c2) == "table" and c2.address then
      if c2.handle == want then return c2, name, want end
      other[#other + 1] = name .. " " .. string.format("%X", tonumber(c2.handle) or 0)
    end
  end
  return nil, string.format("component %X of +0x60 is not on the node's actor (%s; its components: %s)", want,
      #other > 0 and table.concat(other, ", ") or "no Spawner", tostring(listed)), want
end

-- one node -> a record, or nil and why
function SP.read_node(node)
  local class = node.class or SP.NODE_CLASS
  local okc, c = pcall(rivet.component, node.actor, class)
  if not (okc and type(c) == "table" and c.handle == node.component and c.address) then return nil, "instance not reachable" end
  local addr = tonumber(c.address, 16)
  if not valid_ptr(addr) then return nil, "no address" end
  local short = node.kind == "spawner"
  local lay, route, inst, empty
  -- dev 10.19: a script node's Spawner component first
  local spawner_c, spawner_name, spawner_why
  if not short then
    local c2, name = SP.spawner_of(node, addr)
    if c2 then
      local addr2 = tonumber(c2.address, 16)
      if valid_ptr(addr2) then
        local l2, r2, i2, e2 = SP.find_prius(c2, addr2, true)
        if l2 then lay, route = l2, "spawner/" .. tostring(r2); spawner_c, spawner_name = c2, name
        else
          spawner_why = "Spawner component " .. tostring(name) .. ": " .. tostring(r2)
          if e2 then return nil, "factory-only spawner (no Templates)" end
          if SP.spawner_diag < SP.DUMP_LIMIT and i2 then
            SP.spawner_diag = SP.spawner_diag + 1
            SP.log_dump(string.format("dump %s Spawner component %s size %s at %X prius %s", tostring(node.uid), tostring(name),
                tostring(c2.size), addr2, tostring(c2.prius)), i2)
          end
        end
      end
    else
      spawner_why = name                     -- the reason
      if SP.spawner_diag < SP.DUMP_LIMIT then
        SP.spawner_diag = SP.spawner_diag + 1
        log("spawner component of", tostring(node.uid), "not found:", tostring(name))
      end
    end
  end
  if not lay then lay, route, inst, empty = SP.find_prius(c, addr, short) end
  if not lay and spawner_why then route = spawner_why .. "; node: " .. tostring(route) end
  if not lay and not short and (c.size or 0) >= 0x88 then
    -- an instance big enough to hold the fields itself (the simulator's 10.12 nodes)
    local b = read_bytes(addr, math.min(SP.HEADER, c.size))
    local l2, why2
    if b and #b >= 0x88 then l2, why2 = SP.find_layout(b) else why2 = "cannot read the node" end
    if not l2 then route = tostring(why2) .. " (" .. tostring(route) .. ")" end
    if l2 then
      lay, route = l2, "instance"
      lay.tids = read_ids(l2.templates.ptr, l2.templates.count)
      local l = l2.locations
      if l.count >= 1 and l.count <= 32 then lay.locs = read_ids(l.ptr, l.count) end
    end
  end
  if not lay then
    if empty then return nil, "factory-only spawner (no Templates)" end
    if inst and SP.dumps < SP.DUMP_LIMIT then
      SP.dumps = SP.dumps + 1
      SP.log_dump(string.format("dump %s %s size %s instance at %X", tostring(node.uid), class, tostring(c.size), addr), inst)
      local holder = ptr64(inst, 9)
      local hb = valid_ptr(holder) and read_bytes(holder, 0x18)
      if hb then
        SP.log_dump(string.format("dump %s holder at %X", tostring(node.uid), holder), hb)
        local data = ptr64(hb, 17)
        local db = valid_ptr(data) and read_bytes(data, SP.PRIUS_READ)
        if db then SP.log_dump(string.format("dump %s holder data at %X", tostring(node.uid), data), db) end
      end
      for off = 0x60, #inst - 8, 8 do
        local p = ptr64(inst, off + 1)
        local pb = valid_ptr(p) and read_bytes(p, SP.PRIUS_READ)
        if pb then SP.log_dump(string.format("dump %s +0x%X -> %X", tostring(node.uid), off, p), pb) end
      end
    end
    return nil, route
  end
  if not lay.tids then return nil, "cannot read the Templates list" end
  local t = lay.templates
  local rec = { uid = node.uid, component = node.component, actor = node.actor, class = class, addr = addr, x = lay.x,
                spawner_component = spawner_c and spawner_c.handle, spawner_class = spawner_name,
                where = route, prius_addr = lay.prius_addr, holder_count = lay.holder_count, action = lay.action,
                tptr = t.ptr, count = t.count, slots = {}, max_alive = lay.max_alive, num_spawns = lay.num_spawns,
                spawned = 0, alive = {}, alive_n = 0, locs = lay.locs, factories = lay.factories }
  for k = 1, t.count do
    local id = lay.tids[k]
    if not id or id == "0000000000000000" then return nil, "an empty template" end
    rec.slots[k] = { addr = t.ptr + (k - 1) * 8, orig = id, cur = id }
  end
  -- two nodes that reach the same Prius share its Templates list: the census marks both shared (never
  -- written). A holder count above 1 alone is only noted (rivet_hook does not say what it counts).
  return rec
end

function SP.schedule_scan(why, delay)
  if not SP.any_enabled() then return end
  SP.scan_at = SP.frame + (delay or SP.RESCAN_DELAY)
  SP.scan_why = why
end

-- the census runs as a job, a slice per frame
local function census(job)
  local okl, list = pcall(rivet.script_nodes, SP.NODE_CLASS, SP.SCAN_LIMIT)
  if not okl or type(list) ~= "table" then
    if tostring(list):find("budget", 1, true) then error(list, 0) end      -- dev 10.17: SP.tick starts it again
    log("the level's spawner nodes cannot be listed:", tostring(list))
    return
  end
  coroutine.yield()
  -- dev 10.18: placed actors with a Spawner component (SpawnerPrius: the same Templates list), if any
  local n_spawner_components = 0
  if SP.SCAN_SPAWNER_COMPONENTS and rivet.find_component then
    local okf, hs = pcall(rivet.find_component, "Spawner", SP.SCAN_LIMIT, true)
    if okf and type(hs) == "table" then
      for _, h in ipairs(hs) do
        local okc, c = pcall(rivet.component, h, "Spawner")
        if okc and type(c) == "table" and c.handle then
          local oku, uid = pcall(rivet.uid, h)
          list[#list + 1] = { component = c.handle, actor = h, uid = (oku and uid) or ("spawner:" .. tostring(h)),
                              class = "Spawner", kind = "spawner" }
          n_spawner_components = n_spawner_components + 1
        end
      end
    elseif not okf and not SP.spawner_scan_failed then
      -- a bad frame or no such class: the script nodes are still read; said once per session
      SP.spawner_scan_failed = true
      log("Spawner components not listed (the script nodes are read anyway):", tostring(hs))
    end
    coroutine.yield()
  end
  local lvl = { nodes = {}, order = {}, slots_by_addr = {}, skipped = {}, loc_index = {}, done = false, id = (SP.level_id or 0) + 1,
                reasons = {}, routes = {}, spawner_components = n_spawner_components }
  SP.level_id = lvl.id
  SP.route_stats = {}
  local n_in_slice, t0 = 0, clock()
  for _, node in ipairs(list) do
    if (node.class == SP.NODE_CLASS or node.kind == "spawner") and node.uid and not lvl.nodes[node.uid] then
      -- dev 10.19: a node interrupted by the frame budget is read again next frame (10.18 started the
      -- whole census over: your log shows up to 4 restarts on one level)
      local okr, rec, why
      for _ = 1, 3 do
        okr, rec, why = pcall(SP.read_node, node)
        if okr then break end
        if not tostring(rec):find("budget", 1, true) then error(rec, 0) end
        coroutine.yield(); t0 = clock(); SP.slice_t0 = clock()
      end
      if not okr then rec, why = nil, "read three times, each stopped by the frame budget" end
      if rec then
        lvl.routes[rec.where or "?"] = (lvl.routes[rec.where or "?"] or 0) + 1
        if rec.holder_count and rec.holder_count ~= 1 then lvl.holder_counts = (lvl.holder_counts or 0) + 1 end
        -- dev 10.18: what each template is, from its template actor (no need to wait for a fight)
        for _, sl in ipairs(rec.slots) do SP.learn_template(sl.orig) end
        -- a Templates list two nodes share is never changed (one write would change both encounters)
        for _, sl in ipairs(rec.slots) do
          local a = sl.addr
          if lvl.slots_by_addr[a] then
            sl.shared = true; rec.shared = true
            local other = lvl.nodes[lvl.slots_by_addr[a]]
            if other then other.shared = true; for _, o in ipairs(other.slots) do if o.addr == a then o.shared = true end end end
          else lvl.slots_by_addr[a] = rec.uid end
          -- a slot this session changed before a reload that kept the node: its original is remembered
          local w = SP.written[a]
          if w then
            if w.uid == rec.uid and w.cur == sl.cur then sl.orig, sl.owner, sl.expect = w.orig, w.owner, w.expect
            else SP.written[a] = nil end
          end
        end
        -- started before the census read it (an encounter at the load's checkpoint): never changed now
        local st = SP.started_handles[rec.component] or SP.started_handles[rec.actor]
        if not st then for _, id in ipairs(rec.locs or {}) do st = st or SP.started_locs[id] end end   -- dev 10.18
        if st then rec.started = st.frame; rec.stopped = st.stopped end
        lvl.nodes[rec.uid] = rec
        lvl.order[#lvl.order + 1] = rec.uid
        -- dev 10.17: spawn point id -> node uid (false when two nodes share the point: not a lead)
        for _, id in ipairs(rec.locs or {}) do
          if id ~= "0000000000000000" then
            local prev = lvl.loc_index[id]
            if prev == nil then lvl.loc_index[id] = rec.uid elseif prev ~= rec.uid then lvl.loc_index[id] = false end
          end
        end
      else
        lvl.skipped[#lvl.skipped + 1] = tostring(node.uid) .. ": " .. tostring(why)
        local key = tostring(why):gsub("%x%x%x%x%x%x%x%x+", "#")
        lvl.reasons[key] = (lvl.reasons[key] or 0) + 1
      end
      n_in_slice = n_in_slice + 1
      if n_in_slice >= SP.CHECK_PER_FRAME or clock() - t0 > SP.SLICE_SECONDS then
        coroutine.yield(); n_in_slice, t0 = 0, clock()
      end
    end
  end
  table.sort(lvl.order, function(a, b) return tostring(a) < tostring(b) end)
  lvl.done = true
  SP.level = lvl
  local tids = {}
  for _, uid in ipairs(lvl.order) do for _, sl in ipairs(lvl.nodes[uid].slots) do tids[sl.orig] = true end end
  lvl.templates = tids
  local layouts = {}
  for _, uid in ipairs(lvl.order) do
    local r = lvl.nodes[uid]
    local k = string.format("%s+0x%X", (r.where and r.where ~= "instance") and ("prius/" .. r.where .. " ") or "", r.x)
    layouts[k] = (layouts[k] or 0) + 1
  end
  local lay = {}
  for _, k in ipairs(sorted_keys(layouts)) do lay[#lay + 1] = string.format("%s x%d", k, layouts[k]) end
  log(string.format("census %d (%s): %d spawner node(s) read, %d template(s), %d skipped%s", lvl.id, tostring(job.why),
      #lvl.order, count(tids), #lvl.skipped, #lay > 0 and (" - layout " .. table.concat(lay, ", ")) or ""))
  local rt = {}
  for _, k in ipairs(sorted_keys(lvl.routes)) do rt[#rt + 1] = k .. " x" .. lvl.routes[k] end
  if #rt > 0 or lvl.spawner_components > 0 then
    log(string.format("Prius routes (census %d): %s; %d Spawner component(s)%s", lvl.id, #rt > 0 and table.concat(rt, ", ") or "nothing",
        lvl.spawner_components, lvl.holder_counts and (", " .. lvl.holder_counts .. " holder(s) with a count other than 1") or ""))
  end
  for _, k in ipairs(sorted_keys(lvl.reasons)) do log("  skipped", lvl.reasons[k] .. "x", k) end
  for i = 1, math.min(3, #lvl.skipped) do log("  skipped", lvl.skipped[i]) end
  for _, name in ipairs(SP.client_order) do
    local c = SP.clients[name]
    if c.on_census then
      local ok, err = pcall(c.on_census, lvl)
      if not ok then log("RANDO-ERROR", name, "census hook:", tostring(err)) end
    end
  end
  SP.plan("census " .. lvl.id)
  -- dev 10.13: forget writes in nodes that are gone (another planet's), so the record never grows
  local n_in, t1 = 0, clock()
  for _, a in ipairs(sorted_keys(SP.written)) do
    if not lvl.slots_by_addr[a] then
      local w = SP.written[a]
      if w and not SP.still_valid({ actor = w.actor, component = w.component, addr = w.node, class = w.class }) then SP.written[a] = nil end
      n_in = n_in + 1
      if n_in >= 8 or clock() - t1 > SP.SLICE_SECONDS then coroutine.yield(); n_in, t1 = 0, clock() end
    end
  end
end

function SP.start_scan(why)
  SP.scan_at = nil
  if not SP.any_legacy_enabled() then return end
  local job = { why = why }
  job.co = coroutine.create(function() census(job) end)
  SP.job = job
end

-- ---------------------------------------------------------------------------------------------
-- writing and putting back
-- ---------------------------------------------------------------------------------------------
-- one slot to `id`; checks the node is still the same live instance and the slot still holds what
-- we believe. Returns true, or false and why.
function SP.write_slot(rec, sl, id, why)
  if sl.cur == id then return true end
  if not SP.still_valid(rec) then return false, "the node is gone (the level reloaded)" end
  local now = read_id(sl.addr)
  if now ~= sl.cur then return false, "the slot holds " .. tostring(now) .. ", not " .. tostring(sl.cur) end
  local ok, err = pcall(rivet.write, hexaddr(sl.addr), le_hex(id))
  if not ok then return false, "write refused: " .. tostring(err) end
  local back = read_id(sl.addr)
  if back ~= id then
    pcall(rivet.write, hexaddr(sl.addr), le_hex(sl.cur))
    return false, "read back " .. tostring(back)
  end
  sl.cur = id
  if id == sl.orig then SP.written[sl.addr] = nil
  else SP.written[sl.addr] = { uid = rec.uid, orig = sl.orig, cur = id, actor = rec.actor, component = rec.component, class = rec.class,
                                node = rec.addr } end
  return true
end

function SP.revert_rec(rec, why, only_owner)
  local n = 0
  for _, sl in ipairs(rec.slots) do
    if sl.cur ~= sl.orig and (only_owner == nil or sl.owner == only_owner) then
      local ok, err = SP.write_slot(rec, sl, sl.orig, why)
      if ok then n = n + 1; sl.owner = nil
      else log("could not put back", rec.uid, "slot", tostring(sl.addr), "-", tostring(err)) end
    end
  end
  if n > 0 then SP.stats.reverted = SP.stats.reverted + n end
  return n
end
function SP.revert_client(client, why, deadline)
  if not client then return 0, true end
  local lvl = SP.level
  local n = 0
  if lvl then
    for _, uid in ipairs(lvl.order) do
      if n > 0 and deadline and clock() > deadline then return n, false end
      n = n + SP.revert_rec(lvl.nodes[uid], why, client.name)
    end
  end
  local m, done = SP.revert_written(client.name, why, deadline)
  return n + m, done
end
-- the pending put-backs, within the frame budget; returns the slots put back now
function SP.continue_reverts()
  local total = 0
  local deadline = clock() + SP.BUDGET_SECONDS
  for _, name in ipairs(sorted_keys(SP.revert_pending)) do
    local n, done = SP.revert_client(SP.clients[name], SP.revert_pending[name], deadline)
    total = total + n
    if done then SP.revert_pending[name] = nil else break end
  end
  return total
end
-- slots written in nodes the current census does not hold (it is being read again after a load):
-- put back from what this session wrote, if the node is still the same and still holds our write
function SP.revert_written(owner, why, deadline)
  local n = 0
  for _, a in ipairs(sorted_keys(SP.written)) do
    if n > 0 and deadline and clock() > deadline then return n, false end
    local w = SP.written[a]
    if owner == nil or w.owner == owner then
      if SP.still_valid({ actor = w.actor, component = w.component, addr = w.node, class = w.class }) and read_id(a) == w.cur then
        local ok = pcall(rivet.write, hexaddr(a), le_hex(w.orig))
        if ok and read_id(a) == w.orig then n = n + 1 end
      end
      SP.written[a] = nil
    end
  end
  if n > 0 then SP.stats.reverted = SP.stats.reverted + n; log(n, "slot(s) of an earlier census put back:", tostring(why)) end
  return n, true
end
-- the guarded clients' slots only (a story boss area does not touch Chaos)
function SP.revert_guarded(why)
  local n = 0
  for _, name in ipairs(SP.client_order) do
    if guarded_name(name) then n = n + (SP.revert_client(SP.clients[name], why)) end
  end
  if n > 0 then log(n, "slot(s) put back:", why) end
  return n
end
function SP.revert_all(why)
  local lvl = SP.level
  local n = 0
  if lvl then for _, uid in ipairs(lvl.order) do n = n + SP.revert_rec(lvl.nodes[uid], why) end end
  n = n + SP.revert_written(nil, why)
  if n > 0 then log(n, "slot(s) put back:", why) end
  return n
end
-- a spawner that must keep its original enemies for this seed
function SP.block(rec, why)
  local B = blocked_t(true)
  if B[rec.uid] == nil and count(B) < SP.BLOCK_CAP then B[rec.uid] = why; changed() end
  rec.blocked = why
  local n = SP.revert_rec(rec, why)
  SP.stats.blocked = SP.stats.blocked + 1
  log("encounter", rec.uid, "put back to its original enemies and kept so:", why, "(" .. n .. " slot(s))")
  history("[SPAWNER KEPT ORIGINAL] " .. tostring(rec.uid) .. ": " .. why)
  return n
end
function SP.is_blocked(rec) return rec.blocked ~= nil or blocked_t()[rec.uid] ~= nil end

-- ---------------------------------------------------------------------------------------------
-- the plan: which slot gets which template
-- ---------------------------------------------------------------------------------------------
-- may this spawner be changed now? (idle: not started since the level was read, not blocked)
function SP.idle(rec) return rec.started == nil and not SP.is_blocked(rec) end

-- the pools of the loaded level: pool key -> sorted template ids (learned, of a role a client owns)
function SP.pools(lvl)
  local pools = {}
  for tid in pairs(lvl.templates or {}) do
    local key = SP.pool_key(tid)
    if key then pools[key] = pools[key] or {}; table.insert(pools[key], tid) end
  end
  for _, p in pairs(pools) do table.sort(p) end
  return pools
end

-- unique clients (boss.lua): one permutation of each pool, so no boss tier enemy appears twice where it
-- appeared once; free clients (enemy.lua): each slot its own pick
function SP.permutation(key, pool)
  local order = SP.rank(seed_key() .. "|perm|" .. key, pool)
  local map = {}
  local n = #order
  for i, tid in ipairs(order) do map[tid] = order[(i % n) + 1] end
  return map
end

function SP.plan(why)
  local lvl = SP.level
  if not (lvl and lvl.done) then return 0 end
  local pools = SP.pools(lvl)
  local perms = {}
  local applied, kept, wrong, writes = 0, 0, 0, 0
  local deadline = clock() + SP.BUDGET_SECONDS
  -- dev 10.13: a priority client (Chaos) chooses every slot itself; the others wait
  local prio = SP.priority_client()
  local prio_picks
  if prio then
    local list = {}
    for _, uid in ipairs(lvl.order) do
      for i, sl in ipairs(lvl.nodes[uid].slots) do
        if not sl.shared and not sl.failed then list[#list + 1] = { uid = uid, i = i, orig = sl.orig } end
      end
    end
    local ok, picks = pcall(prio.assign, lvl, list)
    if not ok then log("RANDO-ERROR", prio.name, "assign:", tostring(picks)); picks = {} end
    prio_picks = picks or {}
  end
  for _, uid in ipairs(lvl.order) do
    -- after the first write, the budget decides; the rest next frame (the plan is the same, so a
    -- slot already done is passed over without a write)
    if writes > 0 and clock() > deadline then SP.replan = true; break end
    local rec = lvl.nodes[uid]
    for i, sl in ipairs(rec.slots) do
      local key, role, owner, pick
      if prio then
        pick = prio_picks[uid .. "#" .. i]
        if pick == sl.orig then pick = nil end
        owner = pick and prio or nil
        key = pick and "chaos" or nil
      else
        key, role = SP.pool_key(sl.orig)
        owner = role and SP.client_for_role(role)
        if owner and not SP.legacy(owner) then owner = nil end    -- dev 10.27: enemy.lua works on the variable route
      end
      -- a slot changed by a client that is off now, or that belongs to another client now: back
      if sl.cur ~= sl.orig and not sl.failed and (not owner or sl.owner ~= owner.name or not SP.enabled(owner)) then
        writes = writes + 1
        local ok, err = SP.write_slot(rec, sl, sl.orig, "owner changed")
        if ok then sl.owner = nil; wrong = wrong + 1
        else
          sl.failed = true
          log("slot of", uid, "could not be put back:", tostring(err), "- the level is read again")
          SP.schedule_scan("a node changed under the randomizer", 30)
        end
      end
      if not prio and owner and SP.enabled(owner) and not sl.shared and not sl.failed and SP.idle(rec) and not SP.zone then
        local pool = pools[key] or {}
        if #pool >= 2 then
          if owner.unique then
            perms[key] = perms[key] or SP.permutation(key, pool)
            pick = perms[key][sl.orig]
          else
            local others = {}
            for _, t in ipairs(pool) do if t ~= sl.orig then others[#others + 1] = t end end
            pick = SP.rank(seed_key() .. "|" .. tostring(uid) .. "|" .. i, others)[1]
          end
        end
      elseif not prio then
        owner = nil
      end
      if owner and not sl.failed then
        if pick and pick ~= sl.cur then
          writes = writes + 1
          local ok, err = SP.write_slot(rec, sl, pick, owner.name)
          if ok then
            sl.owner = (pick ~= sl.orig) and owner.name or nil
            sl.expect = (pick ~= sl.orig) and key or nil
            local w = SP.written[sl.addr]
            if w then w.owner, w.expect = sl.owner, sl.expect end
            applied = applied + 1
          else
            sl.failed = true          -- not tried again until the level is read again
            log("slot of", uid, "not changed:", tostring(err)); kept = kept + 1
          end
        elseif not pick then kept = kept + 1 end
      end
    end
  end
  SP.stats.applied = SP.stats.applied + applied
  if applied > 0 or wrong > 0 then
    local parts = {}
    if prio then parts[1] = prio.name .. " (priority, " .. tostring(prio.pool_size or "?") .. " template(s))"
    else for _, k in ipairs(sorted_keys(pools)) do parts[#parts + 1] = k .. "=" .. #pools[k] end end
    log(string.format("plan (%s): %d slot(s) changed, %d put back, %d left original | pools %s", tostring(why), applied,
        wrong, kept, #parts > 0 and table.concat(parts, " ") or "none learned yet"))
  end
  return applied
end
SP.seed_key = seed_key
SP.sorted_keys = sorted_keys

-- what a client changed in the loaded level (for its status line)
function SP.client_status(client)
  if not SP.legacy(client) and SP.V then
    local v = SP.V.status()
    return { slots = v.changed, encounters = v.changed, learned = v.known, blocked = 0, vars = v }
  end
  local lvl = SP.level
  local slots, nodes = 0, 0
  if lvl then
    for _, uid in ipairs(lvl.order) do
      local n = 0
      for _, sl in ipairs(lvl.nodes[uid].slots) do if sl.owner == client.name then n = n + 1 end end
      if n > 0 then slots = slots + n; nodes = nodes + 1 end
    end
  end
  local role_learned = 0
  for tid in pairs(learned_t()) do local r = SP.role_of(tid); if r == client.role then role_learned = role_learned + 1 end end
  return { slots = slots, encounters = nodes, learned = role_learned, blocked = count(blocked_t()) }
end

-- ---------------------------------------------------------------------------------------------
-- the game's events
-- ---------------------------------------------------------------------------------------------
local function rec_by_handle(h)
  local lvl = SP.level
  if not (lvl and h ~= nil) then return nil end
  h = math.tointeger(tonumber(h)) or h
  for _, uid in ipairs(lvl.order) do
    local rec = lvl.nodes[uid]
    if rec.component == h or rec.actor == h or (rec.spawner_component and rec.spawner_component == h) then return rec end
  end
  return nil
end
SP.rec_by_handle = rec_by_handle
local function changed_rec(rec)
  for _, sl in ipairs(rec.slots) do if sl.cur ~= sl.orig then return true end end
  return false
end
SP.changed_rec = changed_rec
-- every changed slot of this node belongs to a client with safety nets (not Chaos)
function SP.guarded_rec(rec)
  for _, sl in ipairs(rec.slots) do
    if sl.cur ~= sl.orig and not guarded_name(sl.owner) then return false end
  end
  return true
end
local function distinct_cur(rec)
  local one
  for _, sl in ipairs(rec.slots) do
    if one and sl.cur ~= one then return nil end
    one = sl.cur
  end
  return one
end

-- dev 10.17: the event's sender comes from ev.sender when its fields carry no SenderHandle
local function sender_of(f, ev) return f.SenderHandle or (type(ev) == "table" and ev.sender) or nil end
-- the node of a spawn: its sender, else its SpawnLocation's actor id in one node's SpawnLocations
local function rec_of_spawn(f, ev)
  local rec = rec_by_handle(sender_of(f, ev))
  if rec then return rec end
  local lvl = SP.level
  local loc = math.tointeger(tonumber(f.SpawnLocation))
  if not (lvl and loc and loc ~= 0 and rivet.uid) then return nil end
  local ok, id = pcall(rivet.uid, loc)
  if not ok or type(id) ~= "string" then return nil end
  local uid = lvl.loc_index[id:upper()]
  return uid and lvl.nodes[uid] or nil
end
SP.rec_of_spawn = rec_of_spawn

-- dev 10.19: the first start / stop events of a level, with their sender and node, go to rivet.log
local function event_diag(kind, f, ev, rec)
  local lvl = SP.level
  if not lvl or (lvl.event_logged or 0) >= 3 then return end
  lvl.event_logged = (lvl.event_logged or 0) + 1
  log(string.format("%s: SpawnerComponentHandle %s, sender %s -> %s", kind, tostring(f.SpawnerComponentHandle),
      tostring(type(ev) == "table" and ev.sender), rec and ("node " .. tostring(rec.uid)) or "no node of the census"))
end
function SP.on_started(f, ev)
  local h = f.SpawnerComponentHandle or sender_of(f, ev)
  h = math.tointeger(tonumber(h)) or h
  if h ~= nil then SP.started_handles[h] = { frame = SP.frame } end
  local rec = rec_by_handle(h)
  event_diag("started", f, ev, rec)
  if not rec then return end
  rec.started = rec.started or SP.frame
  rec.last_activity = SP.frame
  rec.stopped = nil
  rec.started_cp = SP.cp_hash
end
function SP.on_stopped(f, ev)
  local h = f.SpawnerComponentHandle or sender_of(f, ev)
  h = math.tointeger(tonumber(h)) or h
  if h ~= nil and SP.started_handles[h] then SP.started_handles[h].stopped = SP.frame end
  local rec = rec_by_handle(h)
  event_diag("stopped", f, ev, rec)
  if rec then rec.stopped = SP.frame; rec.last_activity = SP.frame end
end
SP.SPAWN_LOG = 5                  -- dev 10.18: spawns per level whose node match is written to rivet.log
function SP.on_spawn(f, ev)
  local rec = rec_of_spawn(f, ev)
  local lvl = SP.level
  if lvl and (lvl.spawn_logged or 0) < SP.SPAWN_LOG then
    lvl.spawn_logged = (lvl.spawn_logged or 0) + 1
    local loc = math.tointeger(tonumber(f.SpawnLocation))
    local okl, lid = false, nil
    if loc and loc ~= 0 and rivet.uid then okl, lid = pcall(rivet.uid, loc) end
    log(string.format("spawn: sender %s (field %s), location %s uid %s, spawned %s -> %s", tostring(type(ev) == "table" and ev.sender),
        tostring(f.SenderHandle), tostring(f.SpawnLocation), tostring(okl and lid), tostring(f.SpawnedHandle),
        rec and ("node " .. tostring(rec.uid)) or "no node of the census"))
  end
  if not rec then
    -- dev 10.18: a spawn before the census has read the level: that spawner has started (never changed now)
    local s = sender_of(f, ev)
    s = math.tointeger(tonumber(s)) or s
    if s ~= nil and s ~= 0 then SP.started_handles[s] = SP.started_handles[s] or { frame = SP.frame } end
    local loc = math.tointeger(tonumber(f.SpawnLocation))
    if loc and loc ~= 0 and rivet.uid then
      local ok, id = pcall(rivet.uid, loc)
      if ok and type(id) == "string" then SP.started_locs[id:upper()] = SP.started_locs[id:upper()] or { frame = SP.frame } end
    end
    return
  end
  local h = math.tointeger(tonumber(f.SpawnedHandle)) or f.SpawnedHandle
  rec.started = rec.started or SP.frame
  rec.spawned = rec.spawned + 1
  rec.last_activity = SP.frame
  if h ~= nil and not rec.alive[h] then rec.alive[h] = true; rec.alive_n = rec.alive_n + 1 end
  local tid = (not rec.shared) and distinct_cur(rec) or nil
  if h ~= nil then SP.spawned_by[h] = { uid = rec.uid, tid = tid } end
  if not tid then return end
  -- asking an actor for its components costs up to ~90 calls: once per template (unchanged spawner)
  -- and once per changed spawner (the check of its replacement)
  local is_changed = changed_rec(rec)
  if is_changed then
    if rec.verified then return end
    rec.verified = true
  elseif SP.family_of(tid) and SP.tpl_class[tid] then return end
  local fam, cls = SP.classify_actor(h)
  if not fam then return end
  if is_changed then
    -- dev 10.18: did the write take effect? The spawned bot's class against the written and the original template's
    local orig
    for _, sl in ipairs(rec.slots) do if sl.cur ~= sl.orig then orig = sl.orig end end
    local want, was = SP.tpl_class[tid], orig and SP.tpl_class[orig]
    local verdict = "class not known for both templates"
    if want and was and want ~= was then
      verdict = (cls == want) and "TOOK EFFECT" or ((cls == was) and "DID NOT take effect (the original spawned)" or "another class spawned")
    elseif want and was then verdict = "same class as the original (cannot tell)" end
    log(string.format("verify %s: spawned %s; written %s (%s), original %s (%s): %s", tostring(rec.uid), tostring(cls),
        tostring(tid), tostring(want), tostring(orig), tostring(was), verdict))
    SP.stats.verified = (SP.stats.verified or 0) + 1
  elseif not SP.tpl_class[tid] then
    SP.tpl_class[tid] = cls
  end
  local unguarded = false
  for _, sl in ipairs(rec.slots) do if sl.owner and not guarded_name(sl.owner) then unguarded = true end end
  if is_changed and unguarded then
    SP.learn(tid, fam, "spawned by " .. tostring(rec.uid) .. " (chaos)")     -- learned, never put back
  elseif is_changed then
    -- a replacement: it must be what the plan expected
    local expect
    for _, sl in ipairs(rec.slots) do if sl.expect then expect = sl.expect end end
    local known = SP.family_of(tid)
    if known and known ~= fam then
      SP.learn(tid, fam, "spawned by " .. tostring(rec.uid))
      SP.block(rec, "the replacement turned out to be a " .. fam .. ", not a " .. tostring(expect))
    end
  else
    SP.learn(tid, fam, "spawned by " .. tostring(rec.uid))
  end
end
function SP.on_death(f, ev)
  local s = sender_of(f, ev)
  local h = math.tointeger(tonumber(s)) or s
  local who = h ~= nil and SP.spawned_by[h]
  if not who then return end
  SP.spawned_by[h] = nil
  local lvl = SP.level
  local rec = lvl and lvl.nodes[who.uid]
  if rec and rec.alive[h] then rec.alive[h] = nil; rec.alive_n = rec.alive_n - 1; rec.last_activity = SP.frame end
end
function SP.on_health_bar(f, ev)
  if f.IsFriendly == true then return end
  local s = sender_of(f, ev)
  local h = math.tointeger(tonumber(s)) or s
  local who = h ~= nil and SP.spawned_by[h]
  if not (who and who.tid) then return end
  SP.learn_health_bar(who.tid)
end
function SP.on_boss_phase(f)
  log("boss phase change (", tostring(f.SenderHandle), ") - nothing of the randomizer reacts to it")
end

-- 14_rando_travel.lua calls this for every CheckpointTriggeredEvent
function SP.on_checkpoint(cp)
  if type(cp) ~= "table" then return end
  if SP.listeners.Checkpoint then SP.notify_listeners("Checkpoint", cp) end
  local name = cp.name and tostring(cp.name):upper() or nil
  local was = SP.zone
  SP.zone = nil
  if name then for _, z in ipairs(SP.BOSS_ZONES) do if name:find(z, 1, true) then SP.zone = cp.name end end end
  SP.cp_hash = cp.hash
  if SP.V then
    local okv, ev = pcall(SP.V.on_checkpoint, cp)
    if not okv then log("RANDO-ERROR enemies checkpoint:", tostring(ev)) end
  end
  if not SP.any_legacy_enabled() then return end
  if SP.zone and not was then
    local n = SP.revert_guarded("story boss area " .. tostring(SP.zone))
    log("story boss area", tostring(SP.zone), "- every change put back (" .. n .. " slot(s)) while you are there")
  end
  if cp.loaded then
    -- a load at a checkpoint: a death, a reload or a trip. A changed encounter that was running when
    -- it came counts one retry; too many and it keeps its original enemies.
    local lvl = SP.level
    if lvl then
      for _, uid in ipairs(lvl.order) do
        local rec = lvl.nodes[uid]
        if rec.started and not rec.stopped and changed_rec(rec) and SP.guarded_rec(rec) then
          SP.retries[uid] = (SP.retries[uid] or 0) + 1
          if SP.retries[uid] >= SP.DEATH_LIMIT then
            SP.block(rec, "the checkpoint was loaded " .. SP.retries[uid] .. " times while it ran")
            say("Randomizer: an encounter you retried " .. SP.retries[uid] .. " times has its original enemies now",
                { type = "corner", duration = 6 })
          end
        end
      end
    end
    SP.level = nil                    -- the load may have made the nodes anew
    SP.job = nil                      -- dev 10.18: and a census still reading the old ones is dropped
    SP.spawned_by, SP.started_handles, SP.started_locs = {}, {}, {}
    SP.schedule_scan("checkpoint loaded")
  elseif was and not SP.zone and SP.level then
    SP.plan("left the story boss area")
  end
end

-- =============================================================================================
-- dev 10.27: THE VARIABLE ROUTE - what the Enemy Randomizer (enemy.lua, the - key) uses
-- =============================================================================================
-- PROVEN IN YOUR GAME (tests/data/round37_rivet.log, dev 10.26 spawnproof v6, Zurkon challenge A1 twice): an arena
-- wave's enemies come from SunsetSpawnerFactory nodes; each one's "Templates" script variable (SceneManager script
-- variables, published by rando_give.dll v7) holds the enemy's template actor. Writing ANOTHER enemy's value (uid +
-- handle) into it BEFORE the factory spawns made it spawn the other enemy: 6/6 factories, 20/20 spawns, both runs
-- completed, every variable put back. This section turns that into the randomizer:
--
--   ADAPTERS (one registry, one set of rules, three kinds of spawner variable):
--     factory  - a SunsetSpawnerFactory node's "Templates" (one actor)          PROVEN (round37)
--     template - a SpawnerScriptAction node's "Template" (one actor)            same variable format, NOT yet seen
--                                                                                 replacing an enemy in the game
--     group    - a SpawnerScriptAction node's "Template" holding an actor GROUP NOT yet seen in the game: robomutts /
--                (round35-37: robomutts, thugs, robots, bladeballs from one     thugs waves. The group is replaced
--                 node, SpawnFactory 0)                                          by one enemy (re-chosen after each
--                                                                                 spawn so the wave stays mixed)
--   Every adapter VERIFIES its first spawn (the spawned actor's name against the replacement's). An adapter whose
--   writes the game ignores (V.FAIL_LIMIT "original spawned" with no "replacement spawned" in a session) is switched
--   off for the session and everything it wrote is put back - it never keeps writing blindly.
--
--   REGISTRY: what each template actor spawns (name, bot family, role), learned (a) when the game spawns it, (b) from
--   the template actor itself before any spawn (rivet.components / rivet.name of the handle in the variable; whether
--   your game answers this is logged), (c) from the save: state.enemy_reg keeps every learned enemy by its uid, so a
--   later visit is randomized from the first wave, and a known enemy whose template actor is loaded on another level
--   (rivet.find_uid) joins that level's pool.
--
--   RULES: only role "enemy" (SP.FAMILY_CLASSES: turret, flyer, swarmer, ground) is ever replaced or used. Boss-tier
--   (large bots, anything that showed a health bar), story bosses, friendly bots, mounts, NPCs, portals and props are
--   never touched. A replacement is of the same movement group (walkers - ground and swarmer - for walkers, flyers for
--   flyers, turrets for turrets), of another kind, and its template actor is loaded on this level (it could not
--   spawn otherwise). Picks are fixed by the seed and the spawner (the same encounter gets the same enemies on a
--   retry). Only spawners that have NOT spawned yet on this level are changed; a variable another spawner shares is
--   changed only if every user is fresh.
--
--   PUT BACK: every write is put back on a checkpoint load, a level / planet change, the - key (off), a story boss
--   area, a spawner the game ignored, an encounter stuck V.STUCK_SECONDS without a death, or one retried
--   V.RETRY_LIMIT (5) times (that one keeps its original enemies for the seed: state.spawn_blocked "v:<node>").
--   Only a variable that still holds exactly what was written (same generation) is ever written back.
SP.V = SP.V or {}
local V = SP.V
V.HELPER_MIN = 7
V.MB_SCENE = 0x128
V.SCENE_VARS = 0x75A0
V.VAR_SIZE = 0x40
V.VAR_TYPE_ACTORS = 5
V.GROUP_BIT = 0x80000000
V.ZERO_UID = "0000000000000000"
V.FIRST_SCAN = 6                  -- frames after a level reset before the first listing (dev 10.30: 20 -> 6; round40:
                                  -- 31 enemy spawns came "before the randomizer read its spawner", mostly in the first
                                  -- second after a checkpoint)
V.SCAN_EVERY = 120                -- frames between two listings (new factories of later waves)
V.NODE_LIMIT = 512
V.SLICE = 0.001                   -- seconds of work per frame (rivet_hook's 8 ms budget is shared; 10.28: 1.5 -> 1 ms)
V.QUEUE_CAP = 1024                -- dev 10.29: 256 -> 1024 (round39: a busy arena queued hundreds of ambient spawns)
V.SLOTS = 17                      -- dev 10.28: the Spawner's spawn list is a ring of 17 entries (0xDC..0x1B0), read whole
V.RESTART_CAP = 40                -- dev 10.28: budget restarts of one job without any progress before it is dropped
V.PROBE_GIVEUP = 40               -- dev 10.28: template actors asked with no answer before asking stops for the session
V.UNTIED_LOG = 6                  -- dev 10.28: enemy spawns tied to no spawner variable, logged per level
V.ALIVE_CHECKS = 24               -- dev 10.28: spawned actors checked for being gone per watchdog run
V.REG_CAP = 400
V.REG_RECHECK = 3                 -- dev 10.32: scans between two looks for the save's enemy kinds loaded on the level
V.GROUP_CAP = 300
V.MEMBER_CAP = 8
V.STUCK_SECONDS = 180
V.RETRY_LIMIT = 5                 -- deaths / reloads while a changed encounter ran before it keeps its originals
V.FAIL_LIMIT = 2
V.LATE_GRACE = 4                  -- dev 10.31 (unused since 10.33: a late change never gets an "original" verdict)
V.SPAWN_LOG = 12                  -- spawns of changed spawners logged per level
V.FACTORY_CLASS = "SunsetSpawnerFactoryScriptAction"
V.NODE_CLASS = "SpawnerScriptAction"
V.ADAPTER_LABEL = { factory = "factory Templates", template = "node Template", group = "node Template group" }
V.FAMILY_GROUP = { ground = "walker", swarmer = "walker", turret = "turret", flyer = "flyer" }
-- names that are never an enemy to change or to use, whatever their bot class says
V.NAME_EXCLUDE = { "npc_", "boss", "ally", "friend", "civ_", "vendor", "dummy", "test_", "infobot", "sheep", "lemming" }

local function u16(b, i) if not (b and b[i + 1]) then return nil end return b[i] + b[i + 1] * 0x100 end
local function le32(v) return string.format("%02X %02X %02X %02X", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF) end
local function vlog(...) pcall(rivet.log, "[rando]", "RANDO-ENEMIES", ...) end
V.log = vlog

-- the engine's string hash (rivet_hook script_signal.cpp: reflected CRC-32, start 0xEDB88320) for plug names
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do if c & 1 == 1 then c = (c >> 1) ~ 0xEDB88320 else c = c >> 1 end end
  CRC[i] = c
end
function V.crc(text)
  local c = 0xEDB88320
  for k = 1, #text do c = (c >> 8) ~ CRC[(text:byte(k) ~ c) & 0xFF] end
  return c
end
V.PLUG_TEMPLATE = V.crc("Template")       -- 1835115251
V.PLUG_TEMPLATES = V.crc("Templates")     -- 3990217346
V.PLUG_LASTSPAWN = V.crc("LastSpawn")     -- 406637480
V.PLUG_FACTORIES = V.crc("Factories")     -- 838143302
-- dev 10.28: a node variable whose name is unknown (no rivet.hash match) that holds the node's SPAWNED actors (round38:
-- portal nodes {LastSpawn's actor}, the vehicle group node a86fb955 a group of 3 spawned cars). Used to tie spawns.
V.PLUG_SPAWNED = 942662419
-- dev 10.29: the spawn point. Round39 (spawnprobe): every node's "Location" variable (2761897147 = rivet.hash
-- "Location") holds exactly the SpawnLocation its SpawnerSpawnEvents carry (8cfa5b53: Location {1103873}, spawn at
-- location 1103873; ede61f1b: {1103881} / 1103881; a33fd482: {1103468} / 1103468). A level's spawn points are indexed
-- once per listing, so a SpawnFactory-0 spawn is tied to its node by one table lookup - no search.
V.PLUG_LOCATION = V.crc("Location")       -- 2761897147
V.PLUG_LOCATIONS = V.crc("Locations")     -- 2501629366 (a factory's spawn points)
V.LEDGER_LOG = 300                        -- dev 10.29: per-spawn ledger lines logged per level (then counted only)
V.NOTE_GAP = 180                          -- dev 10.29: frames between two on-screen replacement notes
V.NOTE_QUEUE = 4                          -- dev 10.29: notes waiting at most (the rest are counted in the next one)
-- dev 10.30: combat compatibility (see "COMBAT COMPATIBILITY" below)
-- dev 10.31: "all" (the dev kit's default): EVERY regular enemy may replace every other of its movement group
-- (dev 10.32: enemy_mix_movement = true mixes walkers, flyers and turrets; off by default). Only a pair the game has
-- shown cannot be killed (built-in "bad", rejected in your save, or rejected this session by the combat watch) stays out.
V.COMPAT_MODES = { verified = true, trial = true, any = true, all = true }
V.COMBAT_DEATHS = 6                       -- other deaths on the level after a replaced bot spawned ...
V.COMBAT_SECONDS = 45                     -- ... and seconds it lived: alive past BOTH = it does not die in a fight
V.STALL_SECONDS = 40                      -- dev 10.32: a replaced bot of an unverified pair alive this long while NOTHING on
                                          -- the level died for this long = the fight is stuck on it (round42: Zurkon C5 and
                                          -- B3 - the replaced robot shooters were the whole wave, so no "other deaths" ever
                                          -- came and the check above never ran)
V.SUSPECT_LIMIT = 2                       -- a pair verified by the built-in table is rejected after this many failures
V.TRIAL_PER_LEVEL = 1                     -- enemy_compat = "trial": spawners with an unverified pair at a time
V.DEATH_LOG = 60                          -- DEATH lines (a replaced bot died) logged per level
V.COMPAT_CAP = 300                        -- pairs kept in the save
V.SIG_SAMPLES = 5                         -- original spawns of a kind whose components are compared (intersection)

-- the last path segment, without .actor / .a ("characters\enemy\x\actors\enm_pirate_robot_me" -> enm_pirate_robot_me)
function V.short(name)
  if name == nil then return nil end
  local n = tostring(name):match("([^\\/]+)$") or tostring(name)
  return (n:gsub("%.actor$", ""):gsub("%.a$", ""))
end
-- two names of one actor: rivet.name cuts names at 64 characters, so one may be a prefix of the other
function V.same_name(a, b)
  a, b = V.short(a), V.short(b)
  if not (a and b) then return false end
  if a == b then return true end
  local n = math.min(#a, #b)
  return n >= 8 and a:sub(1, n) == b:sub(1, n)
end
-- dev 10.28: the same KIND of enemy: the same (possibly cut) name AND, when both are known, the same bot family.
-- Round38: the ground and the jetpack shooter thug both read "enm_thugs4less_shoo" (cut at 64 characters); only their
-- family (ground / flyer) tells them apart.
function V.same_kind(a_name, a_fam, b_name, b_fam)
  if not V.same_name(a_name, b_name) then return false end
  return a_fam == nil or b_fam == nil or a_fam == b_fam
end

-- ---- dev 10.29: what an enemy IS, for the player ------------------------------------------------------------
-- The enemy's SPECIES: what it looks like. Round39's question was "the enemies were the same" - and they were close:
-- 10.28 swapped robot shooter / robot brawler / bladeball (all Zurkon pirates) and amoeboid small / large (one
-- creature in two sizes). A replacement now comes from ANOTHER species whenever the level has one (V.pick), and
-- size variants of one creature never replace each other (a large amoeboid splits into more enemies than a small one).
V.SIZE_TOKENS = { "_small", "_medium", "_large", "_xl", "_ps4", "_v2", "_rcf", "_rcn" }
function V.base_name(name)
  local n = (V.short(name) or ""):lower()
  for _, t in ipairs(V.SIZE_TOKENS) do n = n:gsub(t .. "$", ""):gsub(t .. "_", "_") end
  for _, t in ipairs(V.SIZE_TOKENS) do n = n:gsub(t .. "$", "") end
  return n
end
function V.species(name)
  local n = (V.short(name) or ""):lower()
  local a, b = n:match("^enm_([%a%d]+)_([%a%d]+)")
  if a == "indigenous" or a == "native" then return a .. "_" .. (b or ""):sub(1, 5) end   -- Sargasso: each creature its own
  if a then return a end
  return V.base_name(n)
end
-- names the game uses (round31-39 logs) -> what you see. Prefix match (names may be cut at 64 characters); the
-- jetpack thug shares the ground thug's cut name and is told apart by its bot family.
V.DISPLAY = {
  { "enm_pirate_robot_sh", "Pirate Robot Shooter" }, { "enm_pirate_robot_me", "Pirate Robot Brawler" },
  { "enm_pirate_bladeball", "Pirate Bladeball" },
  { "enm_thugs4less_shoo", "Goons-4-Less Shooter", flyer = "Goons-4-Less Jetpack" },
  { "enm_thugs4less_mele", "Goons-4-Less Brawler" }, { "enm_thugs4less_robomutt", "Goons-4-Less Robomutt" },
  { "enm_indigenous_wasp", "Sargasso Wasp" }, { "enm_indigenous_horne", "Sargasso Horned Toad" },
  { "enm_indigenous_grun", "Grunthor" }, { "enm_indigenous_poolsh", "Pool Shark" },
  { "enm_amoeboid_small", "Amoeboid (small)" }, { "enm_amoeboid_medium", "Amoeboid (medium)" },
  { "enm_amoeboid_large", "Amoeboid (large)" }, { "enm_seabase_boss", "Seabase boss (story)" },
  { "burrower_beetle", "Burrower Beetle (mount)" },
}
-- dev 10.32: a species as the player knows it (Ctrl+- and the first note of a level say which ones are loaded).
-- Sargasso's creatures are each their own species (V.species): they are named one by one.
V.SPECIES_DISPLAY = { pirate = "Pirates", thugs4less = "Goons-4-Less", neo = "Nefarious troopers", amoeboid = "Amoeboids" }
function V.species_display(sp, name, family)
  sp = tostring(sp or "?")
  if V.SPECIES_DISPLAY[sp] then return V.SPECIES_DISPLAY[sp] end
  if sp:find("_", 1, true) and name then return V.display(name, family) end
  return (sp:gsub("_", " "):gsub("^%l", string.upper))
end
-- the species of the regular enemies usable on this level (sorted display names, one per species)
function V.species_here()
  local seen, out = {}, {}
  for _, T in pairs(V.lvl and V.lvl.tpl or {}) do
    if V.usable(T) and T.name then
      local sp = V.species(T.name)
      if not seen[sp] then seen[sp] = true; out[#out + 1] = V.species_display(sp, T.name, T.family) end
    end
  end
  table.sort(out)
  return out
end
function V.display(name, family)
  local n = V.short(name)
  if not n then return "?" end
  for _, d in ipairs(V.DISPLAY) do
    if V.same_name(n, d[1]) then return (family and d[family]) or d[2] end
  end
  local t = n:gsub("^enm_", ""):gsub("_ps4$", ""):gsub("_", " ")
  t = t:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
  return family == "flyer" and (t .. " (flying)") or t
end

-- the spawned actor's FULL name from its actor asset (rivet_hook actor.hpp: Actor +0x30 asset; Asset +0x10 name,
-- +0x18 name offset) - what dev(spawnprobe) printed in round31-39 ("enm_thugs4less_shooter.actor" where rivet.name
-- gives the cut "...\\enm_thugs4less_shoo"). Reached through one of the actor's components (Component +0x10 actor).
local function cstr_at(p)
  if not p or p < 0x10000 then return nil end
  local b = read_bytes(p, 96)
  if not b then return nil end
  local t = {}
  for i = 1, #b do
    local c = b[i]
    if c == 0 then break end
    if c < 32 or c > 126 then return nil end
    t[#t + 1] = string.char(c)
  end
  return #t > 0 and table.concat(t) or nil
end
function V.asset_name(h, cls)
  if not (h and cls) then return nil end
  local ok, c = pcall(rivet.component, h, cls)
  local addr = ok and type(c) == "table" and c.address and tonumber(c.address, 16)
  local cb = addr and read_bytes(addr, 0x18)
  local actor = cb and #cb >= 0x18 and ptr64(cb, 0x11)
  if not valid_ptr(actor) then return nil end
  local ab = read_bytes(actor, 0x38)
  local asset = ab and #ab >= 0x38 and ptr64(ab, 0x31)
  if not valid_ptr(asset) then return nil end
  local nb = read_bytes(asset, 0x20)
  if not nb or #nb < 0x1A then return nil end
  local full = cstr_at(ptr64(nb, 0x11))
  if not full then return nil end
  local off = u16(nb, 0x19) or 0
  local n = (off > 1 and off < #full) and full:sub(off + 1) or full
  n = n:gsub("%.actor$", "")
  if not (n:match("^[%w_]+$") and #n >= 4) then return nil end
  return n, full                                                           -- dev 10.32: and the asset's whole path
end
-- dev 10.32: every enemy kind's actor asset path, once per kind and session ("ASSET" lines). The research for enemies
-- from OTHER planets (an asset-level swap: a template stays, the actor asset it loads becomes another enemy's) needs
-- these paths; they cost one log line per kind.
V.ASSET_LOG = 80
function V.note_asset(a)
  if not (a and a.path and a.name and a.family) then return end
  local ss = V.session
  ss.assets = ss.assets or {}
  local k = V.kind_key(a.name, a.family)
  if ss.assets[k] then return end
  ss.assets_n = (ss.assets_n or 0) + 1
  if ss.assets_n > V.ASSET_LOG then return end
  ss.assets[k] = a.path
  vlog(string.format("ASSET %s (%s, %s): %s", tostring(V.short(a.name)), tostring(a.family), tostring(a.class), a.path))
end

local function clock_() return (os and os.clock and os.clock()) or 0 end
-- one unit of work: a frame-budget error yields (the job goes on next frame) and retries, up to 3 times
local function vguard(fn, ...)
  for _ = 1, 3 do
    local res = table.pack(pcall(fn, ...))
    if res[1] then return table.unpack(res, 2, res.n) end
    local err = tostring(res[2])
    if not err:find("frame budget", 1, true) then error(err, 0) end
    V.budget_hits = (V.budget_hits or 0) + 1
    if coroutine.isyieldable() then coroutine.yield() else return nil end
  end
  return nil
end
V.guard = vguard
local function vpace(t0)
  V.progress = (V.progress or 0) + 1                                       -- dev 10.28: a unit done (V.tick's restarts)
  if clock_() - t0 > V.SLICE and coroutine.isyieldable() then coroutine.yield(); return clock_() end
  return t0
end

-- ---- the client and its switch ---------------------------------------------------------------------
function V.client(role)
  for _, name in ipairs(SP.client_order) do
    local c = SP.clients[name]
    if c.route == "vars" and (role == nil or c.role == role) then return c end
  end
  return nil
end
-- dev 10.29: the Enemy (role "enemy") and the Boss Randomizer (role "boss") both run on the variable route: one
-- engine, one registry; each changes only spawners whose original enemy is of its role.
function V.role_on(role)
  local c = V.client(role)
  return c ~= nil and SP.enabled(c)
end
function V.enabled()
  for _, name in ipairs(SP.client_order) do
    local c = SP.clients[name]
    if c.route == "vars" and SP.enabled(c) then return true end
  end
  return false
end

-- ---- the save: registry, groups, blocked spawners ----------------------------------------------------
local function vstate() return RANDO and RANDO.state end
local function reg_t(write)
  local s = vstate(); if not s then return {} end
  if write then s.enemy_reg = s.enemy_reg or {} end
  return s.enemy_reg or {}
end
local function groups_t(write)
  local s = vstate(); if not s then return {} end
  if write then s.enemy_groups = s.enemy_groups or {} end
  return s.enemy_groups or {}
end
local function vblocked(key) local s = vstate(); return s and s.spawn_blocked and s.spawn_blocked["v:" .. tostring(key)] or nil end

-- dev 10.33: THE BUILT-IN REGISTRY. A template actor's uid is level data: the same in every game (round42 and round43
-- read the same uids for the same enemies). Until 10.32 a save learned a kind only when one SPAWNED, so a new save - every
-- public player - changed nothing in a fight until its kinds had spawned once (round43 Cordelion: amoeboids and puffoids
-- were learned 2 minutes in, after the first fights; "kind not known yet" was the most common reason everywhere). These
-- are every enemy template uid the logs named; the save's own entries win.
V.REG_BUILTIN = {
  ["92B2CE851D2D2468"] = "enm_pirate_robot_melee|swarmer|GameBotMeleeSwarmer|enemy",          -- Zurkon arena
  ["E045F83C7223AF50"] = "enm_pirate_bladeball|swarmer|GameBotMeleeSwarmer|enemy",            -- Zurkon arena
  ["ECE0F432299E09D3"] = "enm_pirate_robot_shooter|ground|GameBotShooter|enemy",              -- Zurkon C5
  ["881AC9C3CBA94E0E"] = "enm_pirate_robot_shooter|ground|GameBotShooter|enemy",              -- Zurkon B3
  ["A1057DAD87C2604C"] = "enm_pirate_robot_shooter|ground|GameBotShooter|enemy",              -- Zurkon pub brawl
  ["94B0766A6CE1B456"] = "enm_thugs4less_robomutt|swarmer|GameBotMeleeSwarmer|enemy",         -- Zurkon B3
  ["F01DD224A2CE9D21"] = "enm_thugs4less_shooterjetpack|flyer|GameBotShooterJetPack|enemy",   -- Zurkon B3
  ["85D9909397F0E02B"] = "enm_thugs4less_biker|flyer|GameBotShooterJetPack|enemy",            -- Zurkon B3
  ["DC4C7E6CA0C585C8"] = "enm_neo_nefarious_sniper|flyer|GameBotShooterJetPackNoFiring|enemy",  -- Zurkon C5
  ["B6A048EF0922182D"] = "enm_neo_nefarious_hover|flyer|GameBotShooterJetPack|enemy",         -- Zurkon C5
  ["ED913ADEA9581235"] = "enm_neo_nefarious_shooter|ground|GameBotShooterNoFiring|enemy",     -- Cordelion
  ["CDCD55A20442F76D"] = "enm_neo_nefarious_shooter|ground|GameBotShooterNoFiring|enemy",     -- Cordelion
  ["8DBDBB2D4107EB6C"] = "enm_neo_nefarious_melee|swarmer|GameBotMeleeSwarmer|enemy",         -- Cordelion
  ["BC549A234BC37F2A"] = "enm_neo_nefarious_swarmer|swarmer|GameBotMeleeSwarmer|enemy",       -- Cordelion
  ["93F81D58CE0170AF"] = "enm_neo_nefarious_grenadier|flyer|GameBotShooterJetPackNoFiring|enemy", -- Cordelion
  ["D5C79D3A26DF1EB9"] = "enm_amoeboid_small_ps4|swarmer|GameBotAmoeboid|enemy",             -- Cordelion
  ["A49ABC9129557DC6"] = "enm_indigenous_puffoid|swarmer|GameBotMeleeSwarmer|enemy",          -- Cordelion
}
-- every uid the registry knows (the save's and the built-in ones)
function V.reg_uids()
  local seen, out = {}, {}
  for uid in pairs(reg_t()) do seen[uid] = true; out[#out + 1] = uid end
  for uid in pairs(V.REG_BUILTIN) do if not seen[uid] then out[#out + 1] = uid end end
  table.sort(out)
  return out
end
-- a registry entry: "short|family|class|role[|hb][|mixed]"
function V.reg_get(uid)
  local v = uid and (reg_t()[uid] or V.REG_BUILTIN[uid])
  if type(v) ~= "string" then return nil end
  local name, fam, cls, role, rest = v:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)(.*)$")
  if not name then return nil end
  local e = { name = name, family = fam ~= "" and fam or nil, class = cls ~= "" and cls or nil, role = role,
              hb = rest:find("|hb", 1, true) ~= nil, mixed = rest:find("|mixed", 1, true) ~= nil }
  -- dev 10.31: the family of its class today (round41's save holds enm_neo_nefarious_sniper as "friendly")
  local now = e.class and SP.FAMILY_BY_CLASS[e.class]
  if now and now ~= e.family then e.family = now; e.role = V.role_of(e) end
  return e
end
function V.reg_put(uid, T)
  if not uid or uid == V.ZERO_UID or not T.name then return end
  local R_ = reg_t(true)
  local v = string.format("%s|%s|%s|%s%s%s", V.short(T.name), T.family or "", T.class or "", T.role or "never",
                          T.hb and "|hb" or "", T.mixed and "|mixed" or "")
  if R_[uid] == v then return end
  if R_[uid] == nil then
    local n = 0
    for _ in pairs(R_) do n = n + 1 end
    if n >= V.REG_CAP then return end
  end
  R_[uid] = v
  if RANDO and RANDO.mark_changed then RANDO.mark_changed() end
end

-- the role a template plays for the randomizer
function V.role_of(T)
  if not (T and T.family) then return "never" end
  local role = SP.ROLE_OF_FAMILY[T.family] or "never"
  -- dev 10.31: enemy_compat = "all": the "unclear" bot classes (Hexapod, Pool Shark, Mr. Fungi, Telepathipus) are
  -- regular enemies too (walkers). Mounts, hazards, friendlies and story bosses stay out.
  if T.family == "unclear" and V.all_mode() then role = "enemy" end
  local n = (V.short(T.name) or ""):lower()
  for _, x in ipairs(V.NAME_EXCLUDE) do if n:find(x, 1, true) then return "never" end end
  if role == "enemy" and T.hb then role = "boss" end
  return role
end
-- dev 10.31: the movement group of a family ("unclear" walks, in "all" mode)
function V.family_group(fam)
  local g = V.FAMILY_GROUP[fam or ""]
  if not g and fam == "unclear" and V.all_mode() then g = "walker" end
  return g
end
function V.usable(T)
  return T and not T.mixed and not T.hb and V.role_of(T) == "enemy" and V.family_group(T.family) ~= nil
end
-- dev 10.29: the pool a template belongs to, and its role: regular enemies by movement (walker / flyer / turret);
-- boss tier (large bots, anything that showed a health bar) as "boss_walker" / "boss_flyer" / "boss_turret".
-- Story bosses, friendlies, mounts, hazards and anything unclassified: nil (never changed, never used).
function V.group_of(T)
  if not T or T.mixed or not T.family then return nil end
  local role = V.role_of(T)
  if role == "enemy" then return V.family_group(T.family), "enemy" end
  if role == "boss" then
    local g = T.family == "large" and "walker" or V.family_group(T.family)
    return g and ("boss_" .. g) or nil, "boss"
  end
  return nil, role
end

-- ---- dev 10.30: COMBAT COMPATIBILITY ------------------------------------------------------------------------
-- Round40 (dev 10.29; tests/data/round40_rivet.log): Zurkon arena A1 twice, 40 replaced spawns, every change "VERIFY
-- ... REPLACEMENT SPAWNED" - and the player could not kill the pirate robot SHOOTERS that a bladeball factory spawned
-- (DD6478DACCDD2129, bladeball -> robot shooter). The game's own deaths say the same: run 1 replaced 20 enemies (10
-- brawler, 2 bladeball, 8 shooter replacements) and BotDeathCompleteEvent named 12 of them - the number that were not
-- shooters (run 2: 13 of 20, 7 shooters short). A spawn proves which template the factory used; it does not prove the
-- enemy can take damage, die and be counted. WHY that shooter does not die is not known (the swarmer factory's spawn
-- point / entrance, or the template actor's own setup) - this layer does not guess it, it asks the game for proof:
--   * a replacement is a PAIR "spawner kind|original kind>replacement kind" (V.pair_key; kinds as cut names + family);
--   * a pair is VERIFIED (in-game evidence: V.COMPAT_BUILTIN from the round37-40 logs, or a replaced bot of the pair
--     that died in your game - kept in the save), REJECTED (in-game evidence it does not die, or it spawned without a
--     component the game's own enemies of that kind have - kept in the save) or UNVERIFIED;
--   * enemy_compat = "verified" (the default): only verified pairs are used - an unverified enemy never enters the
--     pool. "trial": unverified pairs of the SAME bot class too, one spawner per level at a time, watched (developer
--     test rounds; the first death verifies it). "any": the 10.29 rules (simulator tests of the scheduling only);
--   * every replaced bot is watched (V.combat_watch): a death naming it is the proof; alive V.COMBAT_SECONDS after it
--     spawned while V.COMBAT_DEATHS other bots died on the level = its pair is rejected and every spawner using it is
--     put back at once (the next spawns are the original enemies; one that already stands there stays until a reload).
V.COMPAT_BUILTIN = {
  ["factory|enm_pirate_robot_sh/ground>enm_pirate_robot_me/swarmer"] = { "ok",
    "round37: 20 of 20 spawns, A1 completed twice; round40: A1 completed twice, its replaced brawlers died" },
  ["factory|enm_pirate_robot_sh/ground>enm_pirate_bladebal/swarmer"] = { "ok",
    "round38-40: spawned in A1, A1 completed; round40: its bladeballs died" },
  ["factory|enm_pirate_bladebal/swarmer>enm_pirate_robot_me/swarmer"] = { "ok",
    "round38-40: spawned in A1, A1 completed; round40: its brawlers died" },
  ["factory|enm_pirate_bladebal/swarmer>enm_pirate_robot_sh/ground"] = { "bad",
    "round40: the player could not kill them; 16 spawned, 8 of 8 (run 1) and 7 of 8 (run 2) never died" },
  ["factory|enm_pirate_robot_me/swarmer>enm_pirate_robot_sh/ground"] = { "bad",
    "the same direction as round40's failure (a melee swarmer factory given the robot shooter); round40: the game ignored it once" },
}
local function compat_t(write)
  local s = vstate()
  if not s then V.session.compat_mem = V.session.compat_mem or {}; return V.session.compat_mem end
  if write then s.enemy_combat = s.enemy_combat or {} end
  return s.enemy_combat or {}
end
V.compat_t = compat_t
function V.kind_key(name, family)
  return (V.short(name) or "?"):lower():sub(1, 19) .. "/" .. tostring(family or "?")
end
function V.pair_key(adapter, o_name, o_fam, r_name, r_fam)
  return tostring(adapter) .. "|" .. V.kind_key(o_name, o_fam) .. ">" .. V.kind_key(r_name, r_fam)
end
-- the original kind(s) a spawner's replacement stands in for: its template, or every member of its group
function V.origs_of(r)
  local out = {}
  if r.kind == "group" then
    for m in (groups_t()[r.key] or ""):gmatch("[^,]+") do
      local fam, nm = m:match("^([^:]*):(.*)$")
      if nm then out[#out + 1] = { name = nm, family = fam ~= "-" and fam or nil } end
    end
  else
    local T = r.orig and r.orig.single and V.lvl and V.lvl.tpl[r.orig.actors]
    if T and T.name then out[1] = T end
  end
  return out
end
function V.pairs_of(r, rep)
  local out = {}
  for _, o in ipairs(V.origs_of(r)) do out[#out + 1] = V.pair_key(r.kind, o.name, o.family, rep.name, rep.family) end
  return out
end
function V.compat_mode()
  local m = RANDO and RANDO.config and RANDO.config.enemy_compat
  return V.COMPAT_MODES[m] and m or "verified"
end
-- dev 10.31
function V.all_mode() return V.compat_mode() == "all" end
-- walkers, flyers and turrets replace each other (boss tier: its own groups among themselves)
-- dev 10.32: only when enemy_mix_movement = true (now OFF by default). Round42: every replaced bot that could not be
-- killed was a walker (pirate robot shooter) at a flyer's spawn - a Nefarious sniper's in C5, a biker's in B3.
function V.mix_movement()
  return V.all_mode() and (RANDO and RANDO.config and RANDO.config.enemy_mix_movement == true) or false
end
-- the movement groups a spawner of group g may take its replacement from
function V.groups_for(g)
  if not g then return {} end
  if not V.mix_movement() then return { [g] = true } end
  if g:sub(1, 5) == "boss_" then return { boss_walker = true, boss_flyer = true, boss_turret = true } end
  return { walker = true, flyer = true, turret = true }
end
-- "verified" / "rejected" / "unverified", and the evidence
function V.compat_status(pair)
  local saved = compat_t()[pair]
  local b = V.COMPAT_BUILTIN[pair]
  if type(saved) == "string" and saved:sub(1, 4) == "bad:" then return "rejected", "your game: " .. saved:sub(5) end
  local sb = V.session and V.session.compat_bad and V.session.compat_bad[pair]
  if sb then return "rejected", "this session: " .. sb end
  if b and b[1] == "bad" then return "rejected", b[2] end
  if b and b[1] == "ok" then return "verified", b[2] end
  if type(saved) == "string" and saved:sub(1, 3) == "ok:" then return "verified", "your game: " .. saved:sub(4) .. " of them died" end
  return "unverified", nil
end
-- dev 10.33: REPLACEMENT KINDS that do not fight where another kind's spawner puts them. The pirate robot shooter has
-- never been killed as a replacement in five rounds: for a bladeball and a brawler (round40), a Nefarious sniper and a
-- biker (round42), a robomutt (round43, 10 of 10 alive 40 s, nothing died) and a pub-brawl group (round43). It stays
-- what it is in its own spawners and is never put into another's. A kind the game rejects as the replacement of two
-- different originals is banned the same way for your save (V.note_rep_failure).
V.BAD_REPLACEMENT = {
  ["enm_pirate_robot_sh/ground"] = "rounds 40-43: never killed as a replacement (bladeball, brawler, sniper, biker, robomutt spawners)",
}
V.REP_FAIL_LIMIT = 2
function V.rep_ban(rep)
  local k = V.kind_key(rep.name, rep.family)
  if V.BAD_REPLACEMENT[k] then return V.BAD_REPLACEMENT[k] end
  local saved = compat_t()["rep|" .. k]
  if type(saved) == "string" and saved:sub(1, 4) == "bad:" then return "your game: " .. saved:sub(5) end
  return nil
end
-- a rejected pair counts against its replacement kind (distinct originals; kept in the save)
function V.note_rep_failure(pair)
  local o, k = tostring(pair):match("|([^>]*)>(.*)$")
  if not (o and k) or o == k then return end
  local key = "rep|" .. k
  local t = compat_t(true)
  local saved = t[key]
  if type(saved) == "string" and saved:sub(1, 4) == "bad:" then return end
  local list = {}
  for x in (type(saved) == "string" and saved:match("^fails:(.*)$") or ""):gmatch("[^,]+") do list[x] = true end
  list[o] = true
  local names = {}
  for x in pairs(list) do names[#names + 1] = x end
  table.sort(names)
  if #names >= V.REP_FAIL_LIMIT then
    t[key] = "bad:could not be killed replacing " .. table.concat(names, ", ")
    vlog(string.format("REPLACEMENT BANNED %s: rejected as the replacement of %d different kinds (%s) - never used again in this save",
        k, #names, table.concat(names, ", ")))
  else
    t[key] = "fails:" .. table.concat(names, ",")
  end
  if RANDO and RANDO.mark_changed then RANDO.mark_changed() end
end
-- may rep stand in for every original kind of spawner r? -> ok, how ("verified" / "trial" / "any"), why not
function V.compat_allows(r, rep, origs)
  local mode = V.compat_mode()
  if mode == "any" then return true, "any" end
  origs = origs or V.origs_of(r)
  -- dev 10.33: a banned replacement kind only ever stands in for itself
  if V.rep_ban(rep) then
    local rk = V.kind_key(rep.name, rep.family)
    for _, o in ipairs(origs) do if V.kind_key(o.name, o.family) ~= rk then return false, nil, "rejected" end end
    if #origs == 0 then return false, nil, "rejected" end
  end
  -- dev 10.31: "all" - everything but a pair with in-game evidence that its replacement cannot be killed
  if mode == "all" then
    local how = (#origs > 0) and "verified" or "all"
    for _, o in ipairs(origs) do
      local st = V.compat_status(V.pair_key(r.kind, o.name, o.family, rep.name, rep.family))
      if st == "rejected" then return false, nil, "rejected" end
      if st ~= "verified" then how = "all" end
    end
    return true, how
  end
  if #origs == 0 then return false, nil, "unverified" end
  local how = "verified"
  for _, o in ipairs(origs) do
    local st = V.compat_status(V.pair_key(r.kind, o.name, o.family, rep.name, rep.family))
    if st == "rejected" then return false, nil, "rejected" end
    if st ~= "verified" then
      if mode ~= "trial" then return false, nil, "unverified" end
      local same
      if o.class and rep.class then same = o.class == rep.class else same = o.family ~= nil and o.family == rep.family end
      if not same then return false, nil, "unverified" end
      how = "trial"
    end
  end
  return true, how
end
function V.trials_running(r)
  local n = 0
  for _, A in ipairs(V.lvl and V.lvl.arms or {}) do if not A.restored and A.compat == "trial" and A.rec ~= r then n = n + 1 end end
  return n
end
function V.combat_c(pair)
  local lvl = V.lvl
  lvl.combat = lvl.combat or {}
  local c = lvl.combat[pair]
  if not c then c = { spawned = 0, died = 0, gone = 0 }; lvl.combat[pair] = c; lvl.combat_order = lvl.combat_order or {}; lvl.combat_order[#lvl.combat_order + 1] = pair end
  return c
end
local function compat_put(pair, value)
  local t = compat_t(true)
  if t[pair] == nil then
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n >= V.COMPAT_CAP then return end
  end
  t[pair] = value
  if RANDO and RANDO.mark_changed then RANDO.mark_changed() end
end
-- dev 10.33: a replaced bot that is GONE soon after its spawn was killed (round43 B3: 25 replaced jetpacks and bikers were
-- killed - the challenge was completed - and no BotDeathCompleteEvent named one; "deaths seen 0" on the whole level). That
-- is proof too, but only within V.GONE_PROOF_SECONDS: a bot gone much later may have been unloaded with its area.
V.GONE_PROOF_SECONDS = 60
function V.kills(lvl) return (lvl.deaths_seen or 0) + (lvl.gone_seen or 0) end
function V.combat_gone(h, x)
  if type(x) ~= "table" or x.dead or x.gone then return end
  x.gone = true
  local lvl = V.lvl
  local frame = SP.frame or 0
  lvl.last_death = frame                                                    -- the fight goes on (the stall watch)
  local secs = math.floor((frame - (x.frame or 0)) / 60 + 0.5)
  for _, p in ipairs(x.pairs or {}) do local c = V.combat_c(p); c.gone = c.gone + 1 end
  if secs <= V.GONE_PROOF_SECONDS and x.pairs and #x.pairs > 0 then
    x.dead = false                                                          -- (combat_died marks it)
    x.gone_proof = true
    V.combat_died(h, x, string.format("killed: gone %d s after its spawn", secs))
  end
end
-- a replaced bot died: the proof its pair works (an unverified pair is verified for your save from now on)
function V.combat_died(h, x, how)
  if x.dead then return end
  x.dead = true
  local lvl = V.lvl
  lvl.death_logged = (lvl.death_logged or 0) + 1
  if lvl.death_logged <= V.DEATH_LOG then
    vlog(string.format("DEATH %d | %s replacing %s | %d s after its spawn | %s%s", h, tostring(V.short(x.T and x.T.name)),
        tostring(x.orig or "?"), math.floor(((SP.frame or 0) - (x.frame or 0)) / 60 + 0.5), tostring(x.compat), how and (" | " .. how) or ""))
  end
  for _, p in ipairs(x.pairs or {}) do
    local c = V.combat_c(p)
    if not x.gone_proof then c.died = c.died + 1 end
    local st = V.compat_status(p)
    local saved = compat_t()[p]
    if st == "unverified" then
      compat_put(p, "ok:1")
      vlog("COMBAT VERIFIED " .. p .. ": a replaced bot of it died in your game (kept in the save)" .. (how and (" - " .. how) or ""))
    elseif type(saved) == "string" and saved:sub(1, 3) == "ok:" then
      compat_put(p, "ok:" .. math.min(999, (tonumber(saved:sub(4)) or 0) + 1))
    elseif type(saved) == "string" and saved:sub(1, 8) == "suspect:" then
      -- dev 10.31: a death clears a failure count (round41: robot shooter > bladeball got "suspect:1" from the
      -- initialization check, then its bot died)
      compat_put(p, "ok:1")
      vlog("COMBAT " .. p .. ": a replaced bot of it died - its earlier failure is cleared")
    end
  end
end
-- in-game evidence against pairs: rejected for this session at once and in the save (a built-in verified pair only
-- after V.SUSPECT_LIMIT failures), every change on this level that uses one is put back
-- dev 10.32: soft = the stall watch's evidence (nothing died while it lived: it may also be a player who walked away):
-- rejected for this session at once, for the save only after V.SUSPECT_LIMIT stalls (a death in between clears it)
function V.combat_reject(pairs, why, label, soft)
  local lvl = V.lvl
  V.session.compat_bad = V.session.compat_bad or {}
  local said = {}
  for _, p in ipairs(pairs or {}) do
    local c = V.combat_c(p)
    if not c.rejected then
      c.rejected = why
      V.session.compat_bad[p] = why
      local b = V.COMPAT_BUILTIN[p]
      local saved = compat_t()[p]
      local scope
      if (b and b[1] == "ok") or soft then
        local n = (tonumber(type(saved) == "string" and saved:match("^suspect:(%d+)") or 0) or 0) + 1
        if n >= V.SUSPECT_LIMIT then compat_put(p, "bad:" .. why); scope = "rejected for this save"
        else compat_put(p, "suspect:" .. n); scope = string.format("rejected for this session; failure %d of %d for this save", n, V.SUSPECT_LIMIT) end
      else
        compat_put(p, "bad:" .. why); scope = "rejected for this save"
      end
      vlog(string.format("COMBAT CHECK FAILED %s: %s - %s", p, why, scope))
      said[#said + 1] = p
      V.note_rep_failure(p)                                                 -- dev 10.33
    end
  end
  local n = 0
  for _, A in ipairs(lvl and lvl.arms or {}) do
    if not A.restored then
      for _, p in ipairs(A.pairs or {}) do
        if V.session.compat_bad[p] then V.put_back(A, "combat check: " .. why); n = n + 1; break end
      end
    end
  end
  if #said > 0 then
    vlog(string.format("combat check: %d changed spawner(s) put back", n))
    say("Enemy Randomizer: " .. tostring(label or "a replacement") .. " - its spawners use the original enemy again",
        { type = "corner", sub = "the one already here may still be out of reach: restart the challenge or load the last checkpoint",
          duration = 8 })
  end
end
-- a replaced bot that lives on while the fight goes on (V.tick, once a second)
-- dev 10.32: ... or while the whole level is stalled (V.STALL_SECONDS without any death), for pairs not verified yet
function V.pairs_verified(pairs)
  if not pairs or #pairs == 0 then return false end
  for _, p in ipairs(pairs) do if V.compat_status(p) ~= "verified" then return false end end
  return true
end
function V.combat_watch()
  local lvl = V.lvl
  if not (lvl and lvl.watch and #lvl.watch > 0) then return end
  local frame = SP.frame or 0
  local keep, asked = {}, 0
  for _, h in ipairs(lvl.watch) do
    local x = lvl.spawned[h]
    if type(x) == "table" and not x.dead and not x.gone and not x.failed then
      local others = V.kills(lvl) - (x.deaths0 or 0)                     -- dev 10.33: bots gone count as killed
      local age = frame - (x.frame or 0)
      local fight = others >= V.COMBAT_DEATHS and age >= V.COMBAT_SECONDS * 60
      local quiet = frame - math.max(lvl.last_death or 0, x.frame or 0)
      local stall = not fight and age >= V.STALL_SECONDS * 60 and quiet >= V.STALL_SECONDS * 60 and not V.pairs_verified(x.pairs)
      if (fight or stall) and asked < V.ALIVE_CHECKS then
        asked = asked + 1
        local state = V.presence(h)
        if state == "unknown" then
          -- a frame-budget error is no answer: asked again next second (never taken as "alive")
        elseif state == "gone" then
          V.combat_gone(h, x)
        else
          x.failed = true
          local secs = math.floor(age / 60 + 0.5)
          local label = string.format("%s replacing %s could not be killed", V.display(x.T and x.T.name, x.T and x.T.family),
              tostring(x.orig_display or x.orig or "?"))
          if fight then
            V.combat_reject(x.pairs, string.format("%s replacing %s (bot %d) was alive %d s after its spawn while %d other bots died",
                tostring(V.short(x.T and x.T.name)), tostring(x.orig or "?"), h, secs, others), label)
          else
            lvl.stalls = (lvl.stalls or 0) + 1
            V.combat_reject(x.pairs, string.format("%s replacing %s (bot %d) was alive %d s after its spawn and nothing on the level died for %d s",
                tostring(V.short(x.T and x.T.name)), tostring(x.orig or "?"), h, secs, math.floor(quiet / 60 + 0.5)), label, true)
          end
        end
      end
      if not x.gone and not x.failed then keep[#keep + 1] = h end
    end
  end
  lvl.watch = keep
end
-- dev 10.30: the INITIALIZATION check. The components of the game's own (unchanged) enemies of a kind are noted
-- (the intersection of up to V.SIG_SAMPLES spawns); a replacement of that kind that spawns without one of them did not
-- initialize as the game's own do - its pair is rejected. Uses the component list V.actor already asked for.
function V.sig_note(a)
  if not (a and a.classes and a.name and a.family) then return end
  V.session.sig = V.session.sig or {}
  local k = V.kind_key(a.name, a.family)
  local s = V.session.sig[k]
  if s and s.n >= V.SIG_SAMPLES then return end
  local have = {}
  for _, c in ipairs(a.classes) do have[tostring(c)] = true end
  if not s then V.session.sig[k] = { n = 1, set = have }; return end
  s.n = s.n + 1
  for c in pairs(s.set) do if not have[c] then s.set[c] = nil end end
end
function V.init_check(A, a, h)
  local s = V.session.sig and V.session.sig[V.kind_key(A.rep.name, A.rep.family)]
  if not (s and a and a.classes) then return "no original of it seen yet" end
  local have = {}
  for _, c in ipairs(a.classes) do have[tostring(c)] = true end
  local missing = {}
  for c in pairs(s.set) do if not have[c] then missing[#missing + 1] = c end end
  if #missing == 0 then return "OK (" .. s.n .. " original(s) compared)" end
  table.sort(missing)
  -- dev 10.31: NOTED, no longer rejected. Round41: bladeball bot 1115177 (replacing a robot shooter) was rejected for
  -- "spawned without WeakspotFiltered" - and died 9 s after its spawn. A missing component is not proof an enemy
  -- cannot be killed; only the combat watch (alive through a fight) rejects a pair now.
  return "MISSING " .. table.concat(missing, ", ") .. " (noted only; the combat watch decides)"
end

-- ---- the SceneManager and its script variables (rando_give.dll v7) ----------------------------------
function V.scene()
  local n = RANDO_REAL and RANDO_REAL.native
  if not (n and n.addr) then return nil, "rando_give.dll is not answering" end
  local hb = read_bytes(n.addr, 0x10)
  local ver = hb and u32(hb, 9)
  if not ver or ver < V.HELPER_MIN then
    return nil, "rando_give.dll is v" .. tostring(ver) .. ", v" .. V.HELPER_MIN .. " is needed (copy the kit's rando_give.dll into the game folder)"
  end
  local mb = read_bytes(n.addr + V.MB_SCENE, 0x0C)
  local scene, sigs = mb and ptr64(mb, 1), mb and u32(mb, 9)
  if not valid_ptr(scene) then return nil, "rando_give.dll found no SceneManager (signature matched " .. tostring(sigs) .. "x, exactly 1 needed)" end
  local sb = read_bytes(scene + V.SCENE_VARS, 0x20)
  local base, max = sb and ptr64(sb, 1), sb and u32(sb, 0x1D)
  if not (valid_ptr(base) and max and max > 0 and max < 0x100000) then
    return nil, string.format("SceneManager %X: no script variable array", scene)
  end
  return { scene = scene, base = base, max = max, sigs = sigs }
end

-- one variable, checked against the plug's generation: { addr, uid, actors, type, gen, single, group }
function V.var(sc, idx, gen)
  if not (sc and idx and gen) or gen == 0 or idx >= sc.max then return nil, "no such variable" end
  local addr = sc.base + idx * V.VAR_SIZE
  local b = read_bytes(addr, V.VAR_SIZE)
  if not b or #b < V.VAR_SIZE then return nil, "unreadable" end
  local v = { addr = addr, uid = hex64(b, 1), actors = u32(b, 0x11), type = u16(b, 0x35), gen = u16(b, 0x37) }
  if v.gen ~= gen then return nil, "generation " .. tostring(v.gen) .. ", the plug says " .. tostring(gen) end
  local is_actors = v.type == V.VAR_TYPE_ACTORS and v.actors ~= nil and v.actors ~= 0
  v.single = is_actors and (v.actors & V.GROUP_BIT) == 0
  v.group = is_actors and (v.actors & V.GROUP_BIT) ~= 0
  return v
end

-- a node's variable plugs (node +0x58 -> ScriptPlugs: entries { u32 plug, u16 idx, u16 gen } at +8, count at +0x1A)
function V.plugs_of(addr)
  local nb = read_bytes(addr, 0x80)
  if not nb or #nb < 0x80 then return nil end
  local plugs = ptr64(nb, 0x59)
  if not valid_ptr(plugs) then return nil end
  local hb = read_bytes(plugs, 0x28)
  if not hb or #hb < 0x28 then return nil end
  local var_ptr, n = ptr64(hb, 9), hb[0x1B]
  local out = { spawner = u32(nb, 0x61), key = hex64(nb, 0x49), vars = {} }
  if not n or n == 0 then return out end
  if not (var_ptr and var_ptr > 0x10000) or n > 32 then return nil end
  local vb = read_bytes(var_ptr, n * 8)
  if not vb or #vb < n * 8 then return nil end
  for k = 0, n - 1 do out.vars[u32(vb, k * 8 + 1)] = { idx = u16(vb, k * 8 + 5), gen = u16(vb, k * 8 + 7) } end
  return out
end

-- the Spawner component's spawn list (+0x9C count, +0xDC entries of 12 bytes { spawned, location, time }).
-- dev 10.28: round38's diffs show the list is a ring that runs to the end of the 432-byte component (17 entries; the
-- vehicle node a86fb955 counted 115 spawns with its newest entries past the 15th): every entry is read.
function V.spawner_slots(saddr)
  local b = saddr and read_bytes(saddr + 0x9C, 0x40 + V.SLOTS * 12)
  if not b or #b < 4 then return nil end
  local count_ = u32(b, 1) or 0
  local out = { count = count_ }
  if count_ == 0 then return out end
  for i = 0, V.SLOTS - 1 do
    local h = u32(b, 0xDC - 0x9C + i * 12 + 1)
    if h and h ~= 0 then out[#out + 1] = h end
  end
  return out
end

-- ---- what an actor is ---------------------------------------------------------------------------------
function V.actor(h)
  if not h or h == 0 then return nil end
  local a = { handle = h }
  if rivet.name then local ok, n = pcall(rivet.name, h); if ok and type(n) == "string" then a.name = n end end
  local okc, fam, cls = pcall(SP.classify_actor, h, true)
  if okc and fam then a.family, a.class = fam, cls end
  if okc then a.classes = SP.last_classes end                              -- dev 10.30: the initialization check
  -- dev 10.29: a bot's full name from its actor asset (a cut rivet.name is only a prefix of it)
  if a.class and V.ASSET_NAMES ~= false then
    local okn, full, path = pcall(V.asset_name, h, a.class)
    if okn and full and (not a.name or V.same_name(full, a.name)) then a.cut, a.name, a.path = a.name, full, path end
  end
  if a.path and V.eligible(a) then pcall(V.note_asset, a) end
  return a
end
-- dev 10.28: is a spawned actor gone (killed and removed)? Round38: no BotDeathCompleteEvent ever reached the randomizer
-- with its bot, so deaths are also found by asking for the actor: nothing answering for its handle = gone. (If the
-- game keeps answering for dead bots, nothing is ever "gone" this way - the stuck rule then waits for the whole
-- level to go quiet, see V.watchdog.) A frame-budget error is NOT taken as gone.
-- dev 10.30: "present" / "gone" / "unknown" (a frame-budget error: no answer either way) for the combat watch
function V.presence(h)
  local okc, c = pcall(rivet.components, h)
  if okc and type(c) == "table" and #c > 0 then return "present" end
  if not okc and tostring(c):find("budget", 1, true) then return "unknown" end
  if rivet.name then
    local okn, n = pcall(rivet.name, h)
    if okn and type(n) == "string" and n ~= "" then return "present" end
    if not okn and tostring(n):find("budget", 1, true) then return "unknown" end
  end
  return "gone"
end
function V.gone(h)
  local okc, c = pcall(rivet.components, h)
  if okc and type(c) == "table" and #c > 0 then return false end
  if not okc and tostring(c):find("budget", 1, true) then return false end
  if rivet.name then
    local okn, n = pcall(rivet.name, h)
    if okn and type(n) == "string" and n ~= "" then return false end
    if not okn and tostring(n):find("budget", 1, true) then return false end
  end
  return true
end

-- ---- the level ---------------------------------------------------------------------------------------
V.adapters = V.adapters or {}
for _, k in ipairs({ "factory", "template", "group" }) do
  V.adapters[k] = V.adapters[k] or { on = true, armed = 0, ok = 0, original = 0, other = 0, write_failed = 0 }
end
V.session = V.session or { said_blocked = false, said_ok = false, said_off = {}, retries = {}, probe_tried = 0, probe_ok = 0 }
V.pending = V.pending or {}       -- dev 10.28: put-backs a frame-budget error interrupted (done first, before any read)

function V.new_level(why)
  V.lvl = { why = why, scans = 0, fac = {}, nodes = {}, order = {}, users = {}, tpl = {}, tpl_uid = {}, fac_spawns = {},
            started = {}, arms = {}, queue = {}, spawned = {}, reg_checked = false, probe = { tried = 0, ok = 0 },
            logged = 0, next_scan = (SP.frame or 0) + V.FIRST_SCAN, frame0 = SP.frame or 0,
            -- dev 10.28
            loc = {}, untied = 0, untied_logged = 0, why_not = {}, activity = SP.frame or 0, dirty = true, arm_i = 1,
            gone_seen = 0, deaths_seen = 0, stuck_said = false, alive_i = 0, errors = {}, last_death = SP.frame or 0,
            -- dev 10.29: spawn point -> node (or list of nodes), spawns waiting for the next listing, the ledger
            loc_index = {}, loc_indexed = 0, deferred = {}, ledger = { eligible = 0, replaced = 0, original = 0, other = 0,
            unchanged = 0, reasons = {}, logged = 0, kinds = {} } }
  V.job = nil
end

-- a level / planet / checkpoint load: put back what is still ours, then start over (the nodes may be new)
function V.reset(why)
  local lvl = V.lvl
  local w = tostring(why)
  if lvl and #lvl.arms > 0 then
    local unloaded = w == "level loaded" or w:find("^planet ") ~= nil
    -- dev 10.28: whatever stops the put-backs here, every change still to put back waits in V.pending and the new
    -- level record is made all the same
    if not pcall(V.put_back_all, w, unloaded) then
      for _, A in ipairs(lvl.arms) do if not A.restored then A.unloaded = A.unloaded or unloaded; V.queue_put_back(A, w) end end
    end
  end
  if lvl and lvl.scans > 0 and V.enabled() then pcall(V.summary) end
  V.new_level(why)
end

-- a template value seen in a variable on this level (handle -> T); T from the registry when its uid is known
function V.tpl_of(handle, uid)
  local lvl = V.lvl
  local T = lvl.tpl[handle]
  if T then
    if uid and uid ~= V.ZERO_UID and not T.uid then T.uid = uid; lvl.tpl_uid[uid] = T end
    return T
  end
  T = { handle = handle, uid = (uid ~= V.ZERO_UID) and uid or nil }
  local e = T.uid and V.reg_get(T.uid)
  if e then
    T.name, T.family, T.class, T.hb, T.mixed, T.src = e.name, e.family, e.class, e.hb, e.mixed, "save"
  end
  lvl.tpl[handle] = T
  if T.uid then lvl.tpl_uid[T.uid] = T end
  if V.group_of(T) then lvl.kinds_n = (lvl.kinds_n or 0) + 1; lvl.dirty = true end   -- dev 10.29: the pool grew
  return T
end

-- learn what a template made (a spawn of an unchanged spawner, or its template actor)
function V.learn(T, a, src)
  if not (T and a and a.name) then return end
  local was_usable = V.usable(T)
  local was_group = V.group_of(T)
  if T.name and not V.same_kind(T.name, T.family, a.name, a.family) and T.src ~= "template actor" then
    if not T.mixed then T.mixed = true; vlog(string.format("template %s (%s) spawned %s and %s: MIXED, never used", tostring(T.handle),
        tostring(T.uid), tostring(V.short(T.name)), tostring(V.short(a.name)))) end
  else
    local new = T.name == nil or T.src == "template actor" and src ~= "template actor"
    T.name = a.name
    if a.family then T.family, T.class = a.family, a.class end
    T.src = (T.src == "save" and not new) and "save" or src
    if new and T.family then
      vlog(string.format("learned template %s (uid %s): %s = %s/%s, role %s (%s)", tostring(T.handle), tostring(T.uid), tostring(V.short(T.name)),
          tostring(T.family), tostring(T.class), V.role_of(T), src))
    end
  end
  T.role = V.role_of(T)
  if T.uid and T.family then V.reg_put(T.uid, T) end
  if V.lvl and V.usable(T) ~= was_usable then V.lvl.dirty = true end      -- dev 10.28: the pool changed: plan again
  if V.lvl and V.group_of(T) ~= was_group then V.lvl.dirty = true; V.lvl.kinds_n = (V.lvl.kinds_n or 0) + 1 end   -- dev 10.29
end

-- the factory record of a SunsetSpawnerFactory actor (nil if it has no Templates variable)
function V.factory_rec(fac, node)
  local lvl = V.lvl
  local r = lvl.fac[fac]
  if r ~= nil then return r or nil end
  local okc, c = pcall(rivet.component, fac, V.FACTORY_CLASS)
  local addr = okc and type(c) == "table" and c.address and tonumber(c.address, 16)
  local pl = addr and V.plugs_of(addr)
  local tv = pl and pl.vars[V.PLUG_TEMPLATES]
  if not tv then lvl.fac[fac] = false; return nil end
  r = { kind = "factory", actor = fac, component = c.handle, addr = addr, key = V.key_of(pl, fac), var = tv }
  lvl.fac[fac] = r
  V.add_rec(r)
  return r
end
-- a spawner's id for the seed's picks, its group members and "kept original": the node's own id (node +0x48, the same
-- on every load), or - if that reads as zero - its actor handle (this load only)
function V.key_of(pl, actor)
  if pl and pl.key and pl.key ~= V.ZERO_UID then return pl.key end
  return "a" .. tostring(actor)
end
function V.add_rec(r)
  local lvl = V.lvl
  lvl.order[#lvl.order + 1] = r
  lvl.dirty = true
  local u = lvl.users[r.var.idx] or {}
  u[#u + 1] = r
  lvl.users[r.var.idx] = u
end

-- a SpawnerScriptAction node with a Template variable (one actor or a group); Factories nodes are covered by
-- their factories, nodes without a Template variable are left alone
function V.node_rec(node)
  local okc, c = pcall(rivet.component, node.actor, V.NODE_CLASS)
  if not (okc and type(c) == "table" and (c.handle == nil or c.handle == node.component)) then return false end   -- another node of the actor
  local addr = c.address and tonumber(c.address, 16)
  local pl = addr and V.plugs_of(addr)
  local tv = pl and pl.vars[V.PLUG_TEMPLATE]
  if not tv then return false end
  local r = { kind = "template", actor = node.actor, component = node.component, addr = addr, key = V.key_of(pl, node.actor),
              var = tv, last = pl.vars[V.PLUG_LASTSPAWN], spawned_var = pl.vars[V.PLUG_SPAWNED], spawner = pl.spawner,
              loc = pl.vars[V.PLUG_LOCATION] }
  local oks, s = pcall(rivet.component, node.actor, "Spawner")
  if oks and type(s) == "table" and s.address and (pl.spawner == nil or s.handle == pl.spawner) then r.saddr = tonumber(s.address, 16) end
  return r
end

-- the template actor itself, before any spawn: its components (bot class) and name. Whether your game answers this
-- for a template actor is logged per level ("asked N template actor(s) before a spawn: M answered").
-- dev 10.28: round38 asked ~100 template actors on Zurkon, Sargasso and Nefarious City and the game answered NONE:
-- after V.PROBE_GIVEUP asks with no answer, asking stops for the session (each ask cost frame budget for nothing).
function V.probe(T)
  local lvl = V.lvl
  if T.family or T.probed then return end
  local ss = V.session
  if ss.probe_ok == 0 and ss.probe_tried >= V.PROBE_GIVEUP then
    if not ss.probe_said then
      ss.probe_said = true
      vlog(string.format("template actors never answered before a spawn (%d asked): asking stops for this session; a kind "
          .. "not in the save is learned from its first spawn", ss.probe_tried))
    end
    return
  end
  T.probed = true
  lvl.probe.tried = lvl.probe.tried + 1
  ss.probe_tried = ss.probe_tried + 1
  local a = V.actor(T.handle)
  if a and a.family and a.name then
    lvl.probe.ok = lvl.probe.ok + 1
    ss.probe_ok = ss.probe_ok + 1
    V.learn(T, a, "template actor")
  end
end

-- ---- the listing ---------------------------------------------------------------------------------------
local function list_nodes(class)
  return vguard(function()
    local ok, l = pcall(rivet.script_nodes, class, V.NODE_LIMIT)
    if ok and type(l) == "table" then return l end
    if not ok then error(l, 0) end
  end)
end

-- the original value of spawner records still without one (kind: only those of that kind)
local function read_origs(sc, kind, t0)
  local lvl = V.lvl
  for _, r in ipairs(lvl.order) do
    if (kind == nil or r.kind == kind) and not r.orig and (r.reads or 0) < 5 then
      r.reads = (r.reads or 0) + 1
      vguard(function()
        local v = V.var(sc, r.var.idx, r.var.gen)
        if v then
          r.orig = { uid = v.uid, actors = v.actors, single = v.single, group = v.group }
          lvl.dirty = true
          if r.kind == "template" and v.group then r.kind = "group" end
          if v.single then V.probe(V.tpl_of(v.actors, v.uid)) end
        end
      end)
      t0 = vpace(t0)
    end
  end
  return t0
end

function V.scan(sc)
  local lvl = V.lvl
  lvl.scans = lvl.scans + 1
  local t0 = clock_()
  local nf, nn = #lvl.order, 0
  for _, node in ipairs(list_nodes(V.FACTORY_CLASS) or {}) do
    if node.actor and lvl.fac[node.actor] == nil then vguard(V.factory_rec, node.actor, node) end
    t0 = vpace(t0)
  end
  -- dev 10.30: FACTORIES FIRST - read and planned before the level's node records are listed. Round40: 31 enemy
  -- spawns "before the randomizer read its spawner" and 34 "before it planned it", most of them arena factories that
  -- spawn in the first second after a checkpoint, while 10.29 was still listing 100-200 nodes (portals, cars, props).
  t0 = read_origs(sc, "factory", t0)
  for _, r in ipairs(lvl.order) do
    if r.kind == "factory" and not r.tried and not r.arm then vguard(V.plan_rec, sc, r); t0 = vpace(t0) end
  end
  -- dev 10.30: a node listing that fails (not the frame budget) no longer stops the scan: the factories above are
  -- planned and the spawn queue is followed; the nodes are listed again at the next scan
  local okl, nodes = pcall(list_nodes, V.NODE_CLASS)
  if not okl then
    if tostring(nodes):find("budget", 1, true) then error(nodes, 0) end
    lvl.errors = lvl.errors or {}
    if not lvl.errors["nodes:" .. tostring(nodes)] then lvl.errors["nodes:" .. tostring(nodes)] = true; vlog("RANDO-ERROR node listing: " .. tostring(nodes)) end
    nodes = nil
  end
  for _, node in ipairs(nodes or {}) do
    if node.component and lvl.nodes[node.component] == nil then
      local r = vguard(V.node_rec, node)
      lvl.nodes[node.component] = r or false
      if r then V.add_rec(r); nn = nn + 1 end
    end
    t0 = vpace(t0)
  end
  -- the original value of every spawner still without one: what it holds before anything of ours (a read lost
  -- to the frame budget - rivet.read answers nothing then - is tried again at the next listing, 5 times at most)
  local new = #lvl.order - nf
  t0 = read_origs(sc, nil, t0)
  for _, r in ipairs(lvl.order) do
    -- dev 10.29: its spawn point(s) -> this node (V.tie_one)
    if r.kind ~= "factory" and r.loc and not r.loc_done and (r.loc_reads or 0) < 5 then
      r.loc_reads = (r.loc_reads or 0) + 1
      vguard(V.index_loc, sc, r)
      t0 = vpace(t0)
    end
  end
  -- the registry's enemies whose template actor is loaded here
  -- dev 10.32: not only once a level - again whenever a listing found new spawner variables (a zone streamed in: the
  -- next Zurkon challenge, the next area of a planet) and at most every V.REG_RECHECK scans. Round42 checked once, in
  -- the first second of each level, and never found one: the zones holding the save's other kinds were not loaded yet.
  if new > 0 and lvl.reg_checked then lvl.reg_due = true end              -- (kept over a frame-budget restart of the scan)
  if rivet.find_uid and (not lvl.reg_checked or (lvl.reg_due and lvl.scans - (lvl.reg_scan or 0) >= V.REG_RECHECK)) then
    local first = not lvl.reg_checked
    lvl.reg_checked, lvl.reg_due = true, false
    lvl.reg_scan = lvl.scans
    local found, names = 0, {}
    for _, uid in ipairs(V.reg_uids()) do                                   -- dev 10.33: the built-in ones too
      if not lvl.tpl_uid[uid] then
        local e = V.reg_get(uid)
        if e and not e.mixed and not e.hb and e.role == "enemy" then
          local ok, h = pcall(rivet.find_uid, uid)
          h = ok and math.tointeger(tonumber(h)) or nil
          if h and h ~= 0 then
            local T = V.tpl_of(h, uid)
            T.src = "save, loaded here"
            found = found + 1
            if #names < 8 then names[#names + 1] = V.display(T.name, T.family) end
          end
        end
      end
      t0 = vpace(t0)
    end
    if found > 0 then
      vlog(string.format("%d enemy kind(s) of the save have their template actor loaded on this level%s: %s", found,
          first and "" or " (a zone streamed in)", table.concat(names, ", ")))
    end
  end
  if new > 0 then
    -- dev 10.29: spawn points that tied to nothing may belong to a node listed now (round39: Sargasso's nodes were
    -- listed ~40 s after the planet loaded, after their first spawns had been given up on)
    for k, v in pairs(lvl.loc) do if v == false then lvl.loc[k] = nil end end
    lvl.loc_miss = {}
  end
  if new > 0 then
    local kinds = { factory = 0, template = 0, group = 0 }
    for _, r in ipairs(lvl.order) do kinds[r.kind] = kinds[r.kind] + 1 end
    local known = 0
    for _, T in pairs(lvl.tpl) do if V.usable(T) then known = known + 1 end end
    vlog(string.format("scan %d on %s: %d spawner variable(s) (%d new): %d factory Templates, %d node Template, %d node Template group; %d enemy kind(s) known here; template actors asked before a spawn: %d, answered %d",
        lvl.scans, tostring(vstate() and vstate().current_planet), #lvl.order, new, kinds.factory, kinds.template, kinds.group, known,
        lvl.probe.tried, lvl.probe.ok))
  end
end

-- ---- choosing ------------------------------------------------------------------------------------------
-- the level's pool for a movement group: usable templates loaded here (a handle in a variable or found by uid)
-- (excl: names the pick must not have - the original, or a group's members; need_uid: the variable holds a uid, so
-- the replacement must have one too - round37's factories: whatever the original held, the write kept that form)
function V.pool(group, excl, need_uid)
  local out = {}
  local groups = V.groups_for(group)                                       -- dev 10.31: mixed movement in "all"
  for _, T in pairs(V.lvl.tpl) do
    local g = V.group_of(T)
    if g and groups[g] and (T.uid or not need_uid) then
      local ok = true
      for _, n in ipairs(excl or {}) do if V.same_name(T.name, n) then ok = false end end
      if ok then out[#out + 1] = T end
    end
  end
  return out
end
-- the seed's pick for this spawner (n: the n-th pick of a group node), by enemy NAME (the same on every load; handles
-- are not). A group whose members are the level's only enemies of their kind still gets one of them.
-- dev 10.29: never a size variant of the original (an amoeboid large for a small one: more enemies, same creature),
-- and ANOTHER SPECIES whenever the level has one loaded (round39: 10.28 swapped the Zurkon pirates among themselves
-- and the Cordelion amoeboids among their sizes - "the enemies were the same").
function V.pick(r, group, excl, n, need_uid)
  local pool = V.pool(group, excl, need_uid)
  if #pool == 0 and r.kind == "group" then pool = V.pool(group, nil, need_uid) end
  if #pool == 0 then
    return nil, V.mix_movement() and "no other enemy kind known on this level" or ("no other " .. group .. " kind known on this level")
  end
  -- dev 10.30: only what combat compatibility allows (V.compat_allows): in-game verified pairs by default
  if V.compat_mode() ~= "any" then
    local origs, allowed, rejected = V.origs_of(r), {}, false
    local trials = V.trials_running(r)
    for _, T in ipairs(pool) do
      local ok, how, why = V.compat_allows(r, T, origs)
      if ok and how == "trial" and trials >= V.TRIAL_PER_LEVEL then ok = false end
      if ok then allowed[#allowed + 1] = T elseif why == "rejected" then rejected = true end
    end
    if #allowed == 0 then
      if V.all_mode() then return nil, "every replacement here is rejected (could not be killed in your game)" end
      return nil, (rejected and V.compat_mode() == "verified") and "no combat-verified replacement here (some are rejected)"
                  or "no combat-verified replacement here"
    end
    pool = allowed
  end
  local bases, species = {}, {}
  for _, x in ipairs(excl or {}) do bases[V.base_name(x)] = true; species[V.species(x)] = true end
  local kept, other = {}, {}
  for _, T in ipairs(pool) do
    if r.kind == "group" or not bases[V.base_name(T.name)] then
      kept[#kept + 1] = T
      if not species[V.species(T.name)] then other[#other + 1] = T end
    end
  end
  if #kept == 0 then return nil, "only size variants of it are loaded on this level" end
  pool = (#other > 0) and other or kept
  local keys, by = {}, {}
  for _, T in ipairs(pool) do
    -- the kind's key: its name cut as rivet.name cuts the game's names (19 characters: "enm_pirate_robot_sh") and its
    -- family, so a pick is the same whether the name came from the save (cut) or from an actor asset (full)
    local k = V.short(T.name):lower():sub(1, 19) .. "/" .. tostring(T.family)
    local b = by[k]
    if not b then keys[#keys + 1] = k end
    -- one template per name: one with a uid first, then the lowest handle
    if not b or (T.uid and not b.uid) or ((T.uid ~= nil) == (b.uid ~= nil) and T.handle < b.handle) then by[k] = T end
  end
  table.sort(keys)
  local order = SP.rank(SP.seed_key() .. "|enemy|" .. tostring(r.key) .. "|" .. tostring(r.orig_name or "group") .. "|" .. tostring(n or 0), keys)
  -- dev 10.32: SPREAD. The seed's order alone can give one kind to most spawners of a level (round42's A1: 52 of its
  -- 64 replaced spawns were robot brawlers): the seed's order is kept, but a kind fewer spawners of this level use comes
  -- first, so every kind loaded here shows up. The same listing order gives the same picks on a retry.
  local used = {}
  for _, A in ipairs(V.lvl and V.lvl.arms or {}) do
    if not A.restored and A.rec ~= r and A.rep and A.rep.name then
      local k = V.short(A.rep.name):lower():sub(1, 19) .. "/" .. tostring(A.rep.family)
      used[k] = (used[k] or 0) + 1
    end
  end
  local best, bestn = order[1], math.huge
  for _, k in ipairs(order) do
    local u = used[k] or 0
    if u < bestn then best, bestn = k, u end
  end
  return by[best]
end

-- may this spawner be changed now?
function V.fresh(r)
  local lvl = V.lvl
  if r.kind == "factory" then return (lvl.fac_spawns[r.actor] or 0) == 0 and (r.spawned or 0) == 0 end
  if (r.spawned or 0) > 0 or (r.spawner and lvl.started[r.spawner]) then return false end
  if r.saddr then
    local sl = V.spawner_slots(r.saddr)
    if sl and sl.count > 0 then return false end
  end
  return true
end

-- dev 10.28: why a node / group spawner was not changed, counted once per spawner and level (the level summary prints
-- it: round38 changed 0 node and 0 group spawners and the log could not say why)
local function note_why(r, reason)
  if r.why_said == reason then return end                                -- dev 10.29: factories too (the ledger)
  local lvl = V.lvl
  if r.why_said then local t = lvl.why_not[r.kind]; if t and t[r.why_said] then t[r.why_said] = t[r.why_said] - 1 end end
  r.why_said = reason
  lvl.why_not[r.kind] = lvl.why_not[r.kind] or {}
  lvl.why_not[r.kind][reason] = (lvl.why_not[r.kind][reason] or 0) + 1
end
V.note_why = note_why

function V.plan_rec(sc, r)
  local lvl = V.lvl
  if r.arm then
    local A = r.arm
    -- dev 10.30: factories are planned before the nodes are listed; a node listed later that shares the variable and
    -- has already spawned makes the change unsafe (10.29's rule: shared variables only while every user is fresh)
    if not V.all_mode() then                                               -- dev 10.31: "all" changes spent spawners too
      for _, u in ipairs(lvl.users[r.var.idx] or {}) do
        if A.spawns == 0 and not A.restored and u ~= r and not u.arm and not V.fresh(u) then
          V.put_back(A, "shares its variable with a spent spawner"); return
        end
      end
    end
    if not A.restored and A.spawns == 0 and A.kinds_seen ~= (lvl.kinds_n or 0) and V.fresh(r) then V.repick(sc, A) end
    return
  end
  if r.tried then return end
  if r.not_enemy then return note_why(r, "spawns no enemy") end
  if not r.orig then return note_why(r, "value not read yet") end
  if not V.adapters[r.kind].on then return note_why(r, "adapter off") end
  if vblocked(r.key) then return note_why(r, "kept original for the seed") end
  if SP.zone then return note_why(r, "story boss area") end
  local orig_T, group, role
  local excl = {}
  if r.kind == "group" then
    local G = groups_t()[r.key]
    if type(G) ~= "string" or G == "" then return note_why(r, "members not learned yet (changes from its next run)") end
    for m in G:gmatch("[^,]+") do
      local fam, nm = m:match("^([^:]*):(.*)$")
      local g, rl = V.group_of({ family = fam ~= "-" and fam or nil, name = nm })
      if not g or rl ~= "enemy" then return note_why(r, "a member is no regular enemy") end
      if group and g ~= group and not V.mix_movement() then return note_why(r, "members of several movement groups (walkers and flyers)") end
      group, role = g, rl
      excl[#excl + 1] = nm
    end
  else
    if not r.orig.single then return note_why(r, "empty") end
    orig_T = lvl.tpl[r.orig.actors]
    if not (orig_T and orig_T.family) then return note_why(r, "kind not known yet (learned from its first spawn)") end
    group, role = V.group_of(orig_T)
    if not group then return note_why(r, "protected: " .. tostring(role)) end
    excl[1] = orig_T.name
  end
  if not group then return end
  if not V.role_on(role) then return note_why(r, (role == "boss" and "Boss" or "Enemy") .. " Randomizer off") end
  -- dev 10.31: round41 - Zurkon B3's robomutt / biker factories spawned their kind once ("kind not known yet"), and
  -- from then on every spawn was "already spawned on this level". In "all" mode a spawner that has spawned is changed
  -- for its NEXT spawns (the ones standing there stay what they are).
  local all = V.all_mode()
  for _, u in ipairs(lvl.users[r.var.idx] or {}) do
    if u.arm then return note_why(r, u == r and "already spawned on this level" or "shares its variable with a spent spawner") end
    if not all and not V.fresh(u) then return note_why(r, u == r and "already spawned on this level" or "shares its variable with a spent spawner") end
  end
  r.orig_name = orig_T and V.short(orig_T.name) or "group"
  local rep, why = V.pick(r, group, excl, 0, r.kind ~= "group" and r.orig.uid ~= V.ZERO_UID)
  if not rep then return note_why(r, why or ("no other " .. group .. " kind known on this level")) end
  r.tried = true
  r.plan_group, r.plan_excl = group, excl
  V.arm(sc, r, rep, orig_T, role)
  if r.arm then note_why(r, "CHANGED") end
end

function V.write_var(sc, r, uid, actors)
  local now = V.var(sc, r.var.idx, r.var.gen)
  if not now then return false, "the variable is gone" end
  local ok1, e1 = pcall(rivet.write, string.format("%X", now.addr), le_hex(uid))
  local ok2, e2 = pcall(rivet.write, string.format("%X", now.addr + 0x10), le32(actors))
  local back = V.var(sc, r.var.idx, r.var.gen)
  -- dev 10.28: the third answer says a write was lost to the frame budget (a put-back then tries again next frame)
  local budget = (not ok1 and tostring(e1):find("budget", 1, true) ~= nil) or (not ok2 and tostring(e2):find("budget", 1, true) ~= nil)
  return ok1 and ok2 and back and back.uid == uid and back.actors == actors, back, budget
end

function V.arm(sc, r, rep, orig_T, role)
  local now = V.var(sc, r.var.idx, r.var.gen)
  if not (now and now.uid == r.orig.uid and now.actors == r.orig.actors) then
    vlog(string.format("not changed (the variable changed while it was checked): %s %s", r.kind, tostring(r.key))); return
  end
  -- the proven format (round37, spawnproof v6): a value without uid keeps none; with one, the replacement's own.
  -- A group gets the replacement's own uid (none if it has none)
  local new_uid
  if r.kind == "group" then new_uid = rep.uid or V.ZERO_UID
  elseif now.uid == V.ZERO_UID then new_uid = V.ZERO_UID
  else new_uid = rep.uid end
  if not new_uid then vlog("not changed (the replacement has no uid): " .. tostring(r.key)); return end
  local ok = V.write_var(sc, r, new_uid, rep.handle)
  local ad = V.adapters[r.kind]
  if not ok then
    ad.write_failed = ad.write_failed + 1
    V.write_var(sc, r, r.orig.uid, r.orig.actors)
    vlog(string.format("write FAILED (%s %s): put back", r.kind, tostring(r.key)))
    return
  end
  local A = { rec = r, rep = rep, orig_T = orig_T, new_uid = new_uid, frame = SP.frame, spawns = 0, picks = 0, alive = {}, alive_n = 0,
              last_activity = SP.frame, role = role or "enemy", group = r.plan_group, excl = r.plan_excl,
              kinds_seen = V.lvl.kinds_n or 0 }
  A.late = not V.fresh(r)                                                  -- dev 10.31: changed after it spawned
  V.arm_compat(A)
  r.arm = A
  local lvl = V.lvl
  lvl.arms[#lvl.arms + 1] = A
  ad.armed = ad.armed + 1
  vlog(string.format("CHANGED%s %s %s (actor %s, variable %d): %s -> %s [template %s uid %s from %s; %s]",
      A.late and " (late: it had spawned, its next spawns)" or "", V.ADAPTER_LABEL[r.kind], tostring(r.key), tostring(r.actor), r.var.idx,
      r.kind == "group" and ("group " .. string.format("%08X", r.orig.actors) .. " (" .. tostring(groups_t()[r.key]) .. ")")
        or tostring(V.short(orig_T and orig_T.name)), tostring(V.short(rep.name)), tostring(rep.handle), tostring(rep.uid or "-"),
      tostring(rep.src or "?"), V.compat_label(A)))
end
-- dev 10.30: the pairs a change stands for and how combat compatibility allowed it
function V.arm_compat(A)
  local r = A.rec
  A.pairs = V.pairs_of(r, A.rep)
  local _, how = V.compat_allows(r, A.rep)
  A.compat = how or "unverified"
  local o = V.origs_of(r)
  A.orig_label = (#o == 1) and tostring(V.short(o[1].name)) or ("group (" .. tostring(groups_t()[r.key] or "?"):gsub("[%w_]*:", "") .. ")")
  A.orig_display = (#o == 1) and V.display(o[1].name, o[1].family) or A.orig_label
end
function V.compat_label(A)
  if A.compat == "verified" then
    local _, ev = V.compat_status(A.pairs[1] or "")
    return "combat-verified pair (" .. tostring(ev) .. ")"
  end
  if A.compat == "trial" then return "TRIAL: an unverified pair of the same bot class, watched" end
  if A.compat == "any" then return "enemy_compat = any: NOT combat-verified" end
  if A.compat == "all" then return "enemy_compat = all: not combat-verified yet, watched (a death verifies it)" end
  return "not combat-verified"
end

-- dev 10.29: a change that has not spawned yet is picked again when the level's pool grew (round39: Zurkon's A1
-- factories were changed while only the two pirate robots were known and kept pirate-for-pirate swaps after the thugs
-- were learned). Deterministic like every pick: the same pool gives the same answer on a reload.
function V.repick(sc, A)
  local r, lvl = A.rec, V.lvl
  A.kinds_seen = lvl.kinds_n or 0
  if not A.group then return end
  local rep = V.pick(r, A.group, A.excl, 0, r.kind ~= "group" and r.orig.uid ~= V.ZERO_UID)
  if not rep or rep == A.rep or V.same_kind(rep.name, rep.family, A.rep.name, A.rep.family) then return end
  local now = V.var(sc, r.var.idx, r.var.gen)
  if not (now and now.uid == A.new_uid and now.actors == A.rep.handle) then return end
  local new_uid
  if r.kind == "group" then new_uid = rep.uid or V.ZERO_UID
  elseif r.orig.uid == V.ZERO_UID then new_uid = V.ZERO_UID
  else new_uid = rep.uid end
  if not new_uid then return end
  if V.write_var(sc, r, new_uid, rep.handle) then
    vlog(string.format("CHANGED AGAIN %s %s (a kind learned since): %s -> %s", V.ADAPTER_LABEL[r.kind], tostring(r.key),
        tostring(V.short(A.rep.name)), tostring(V.short(rep.name))))
    A.rep, A.new_uid = rep, new_uid
    V.arm_compat(A)                                                         -- dev 10.30
  else
    V.write_var(sc, r, A.new_uid, A.rep.handle)                            -- the earlier pick stays
  end
end

-- a group node: the next spawn gets the next pick, so the wave stays mixed (only while the variable is ours)
function V.rotate(sc, A)
  local r = A.rec
  A.picks = A.picks + 1
  local G = groups_t()[r.key] or ""
  local fam = G:match("^([^:,]*):")
  local excl = {}
  for m in G:gmatch("[^,]+") do excl[#excl + 1] = m:match(":(.*)$") end
  local rep = fam and V.pick(r, V.group_of({ family = fam, name = excl[1] }), excl, A.picks)
  if not rep or rep.handle == A.rep.handle then return end
  local now = V.var(sc, r.var.idx, r.var.gen)
  if not (now and now.uid == A.new_uid and now.actors == A.rep.handle) then return end
  local uid = rep.uid or V.ZERO_UID
  if V.write_var(sc, r, uid, rep.handle) then A.rep, A.new_uid = rep, uid; V.arm_compat(A) end
end

function V.put_back_now(A, why)
  if not A or A.restored then return end
  local r = A.rec
  local sc = V.scene()
  local v, verr = nil, nil
  if sc then v, verr = V.var(sc, r.var.idx, r.var.gen) end
  -- a read lost to the frame budget (rivet.read answers nothing) is not "the variable changed": try again later
  if not v and verr == "unreadable" and not A.unloaded and (A.unreadable or 0) < 10 then
    A.unreadable = (A.unreadable or 0) + 1
    error("frame budget: the variable could not be read for its put-back", 0)
  end
  local res
  -- ours, or half ours (one of the two writes of an interrupted put-back went through)
  local ours = v and ((v.uid == A.new_uid and v.actors == A.rep.handle) or (v.uid == r.orig.uid and v.actors == A.rep.handle and A.new_uid ~= r.orig.uid)
                      or (v.uid == A.new_uid and v.actors == r.orig.actors and A.new_uid ~= r.orig.uid))
  if ours then
    local ok, back, budget = V.write_var(sc, r, r.orig.uid, r.orig.actors)
    if not ok and (back == nil or budget) and (A.unreadable or 0) < 10 then
      A.unreadable = (A.unreadable or 0) + 1
      error("frame budget: the put-back could not be read back", 0)
    end
    res = ok and "OK" or "FAILED"
  elseif v and v.uid == r.orig.uid and v.actors == r.orig.actors then
    res = "OK"                                                              -- written before an interrupted read-back
  elseif A.unloaded then
    res = "nothing to write (the level it was on is unloaded)"
  else
    res = "skipped (the variable no longer holds what was written)"
  end
  -- marked only once the write is done: a frame-budget error above leaves it for V.pending (dev 10.28)
  A.restored = true
  r.arm = nil
  r.restored_frame = SP.frame
  r.put_back_why = why
  local lvl = V.lvl
  local n = 1
  if lvl then lvl.put_back = (lvl.put_back or 0) + 1; n = lvl.put_back end
  if n <= 8 or res == "FAILED" then
    vlog(string.format("put back (%s): %s %s: %s", tostring(why), V.ADAPTER_LABEL[r.kind], tostring(r.key), res))
  end
end
function V.queue_put_back(A, why)
  if A.restored or A.queued then return end
  A.queued = true
  V.pending[#V.pending + 1] = { A = A, why = why }
end
-- the put-back every other part uses: one that cannot finish now (frame budget) waits in V.pending
function V.put_back(A, why)
  if not A or A.restored then return end
  local ok, err = pcall(V.put_back_now, A, why)
  if ok and A.restored then return end
  V.queue_put_back(A, why)
  if not ok and not tostring(err):find("budget", 1, true) then vlog("RANDO-ERROR put back: " .. tostring(err)) end
end
-- dev 10.28: every put-back runs on its own; one a frame-budget error interrupts waits in V.pending and is done at the
-- next frame BEFORE anything is read or written (round38: a checkpoint's put-backs were cut short by the budget once).
function V.put_back_all(why, unloaded)
  local lvl = V.lvl
  if not lvl then return 0 end
  local n = 0
  for _, A in ipairs(lvl.arms) do
    if not A.restored then
      n = n + 1
      if unloaded then A.unloaded = true end
      local ok, err = pcall(V.put_back_now, A, why)
      if not ok or not A.restored then
        V.queue_put_back(A, why)
        if not ok and not tostring(err):find("budget", 1, true) then vlog("RANDO-ERROR put back: " .. tostring(err)) end
      end
    end
  end
  if n > 0 then vlog(string.format("%d changed spawner(s) put back: %s%s", n, tostring(why),
      #V.pending > 0 and string.format(" (%d finish next frame)", #V.pending) or "")) end
  return n
end
function V.drain_pending()
  while #V.pending > 0 do
    local p = V.pending[1]
    if not p.A.restored then
      p.tries = (p.tries or 0) + 1
      local ok = pcall(V.put_back_now, p.A, p.why)
      if not ok and p.tries < 20 then return false end
    end
    table.remove(V.pending, 1)
  end
  return true
end

function V.block(A, why)
  local s = vstate()
  local key = "v:" .. tostring(A.rec.key)
  if s then
    s.spawn_blocked = s.spawn_blocked or {}
    if s.spawn_blocked[key] == nil then s.spawn_blocked[key] = why; if RANDO and RANDO.mark_changed then RANDO.mark_changed() end end
  end
  vlog(string.format("kept original for this seed: %s %s - %s", V.ADAPTER_LABEL[A.rec.kind], tostring(A.rec.key), tostring(why)))
  V.put_back(A, why)
end

-- ---- spawns ---------------------------------------------------------------------------------------------
-- every spawn is counted (also while the feature is off), so a spawner that already ran is never changed
function V.on_spawn_seen(f)
  local lvl = V.lvl
  if not lvl then return end
  local h = math.tointeger(tonumber(f.SpawnedHandle))
  local fac = math.tointeger(tonumber(f.SpawnFactory)) or 0
  if fac ~= 0 then lvl.fac_spawns[fac] = (lvl.fac_spawns[fac] or 0) + 1 end
  if not h or lvl.spawned[h] then return end
  lvl.spawned[h] = true
  if V.enabled() and #lvl.queue < V.QUEUE_CAP then
    lvl.queue[#lvl.queue + 1] = { h = h, fac = fac, loc = math.tointeger(tonumber(f.SpawnLocation)), idx = math.tointeger(tonumber(f.SpawnIndex)) }
  end
end
function V.on_started(f)
  local lvl = V.lvl
  local h = math.tointeger(tonumber(f.SpawnerComponentHandle))
  if lvl and h then lvl.started[h] = true end
end

-- does node record r name spawned actor h? (its LastSpawn, its spawned-actors variable, its Spawner's spawn list; for
-- a group node also the spawned-actors GROUP, expanded by rivet.script_node)
local function holds(sc, r, h, pass)
  if pass == 1 then
    if r.last then local lv = V.var(sc, r.last.idx, r.last.gen); if lv and lv.actors == h then return true end end
    if r.spawned_var then local sv = V.var(sc, r.spawned_var.idx, r.spawned_var.gen); if sv and sv.single and sv.actors == h then return true end end
  elseif pass == 2 then
    if r.saddr then for _, x in ipairs(V.spawner_slots(r.saddr) or {}) do if x == h then return true end end end
  elseif pass == 3 and r.kind == "group" and rivet.script_node and r.component then
    local ok, t = pcall(rivet.script_node, r.component, false)
    if ok and type(t) == "table" and type(t.vars) == "table" then
      for _, v in ipairs(t.vars) do
        if type(v) == "table" and type(v.value) == "table" and tonumber(v.plug) ~= V.PLUG_TEMPLATE then
          for _, x in ipairs(v.value) do if math.tointeger(tonumber(x)) == h then return true end end
        end
      end
    end
  end
  return false
end
V.holds = holds

-- dev 10.28: the node of a SpawnFactory-0 spawn, ONE spawn at a time. Round38: ambient portals and cars spawn all the
-- time with SpawnFactory 0 and 10.27 searched every node for each batch of them - the frame-budget storm. Now a spawn
-- location remembers its node (checked against that node's own spawn record, as two waves may share a spawn point);
-- a location that tied to nothing 3 times is not searched again on this level.
-- dev 10.29: the node's spawn point(s) into the level's index. A single Location is its handle; a group of them (a
-- group node spawning at several points) is expanded by rivet.script_node (rivet_hook lists an actors variable's
-- handles; round38-39's spawnprobe printed them). A spawn point two nodes share keeps both (V.tie_one decides).
local function index_add(lvl, h, r)
  if not h or h == 0 then return end
  local x = lvl.loc_index[h]
  if x == nil then lvl.loc_index[h] = r
  elseif x ~= r then
    if x.kind then lvl.loc_index[h] = { x, r }
    else
      for _, y in ipairs(x) do if y == r then return end end
      x[#x + 1] = r
    end
  end
  lvl.loc_indexed = lvl.loc_indexed + 1
end
function V.index_loc(sc, r)
  local lvl = V.lvl
  local v, err = V.var(sc, r.loc.idx, r.loc.gen)
  if not v then
    if err ~= "unreadable" then r.loc_done = true end                      -- regenerated: never indexed by location
    return
  end
  r.loc_done = true
  if v.single then index_add(lvl, v.actors, r); return end
  if v.group and rivet.script_node and r.component then
    local ok, t = pcall(rivet.script_node, r.component, false)
    if ok and type(t) == "table" and type(t.vars) == "table" then
      for _, x in ipairs(t.vars) do
        if type(x) == "table" and tonumber(x.plug) == V.PLUG_LOCATION and type(x.value) == "table" then
          for _, h in ipairs(x.value) do index_add(lvl, math.tointeger(tonumber(h)), r) end
        end
      end
    end
  end
end

-- the node of a SpawnFactory-0 spawn. dev 10.29: by its spawn point (one lookup in the level's index). Round39:
-- 10.28 searched node records for every untied spawn (513 in one Zurkon visit): the queue fell minutes behind, the
-- arena's factories spawned before they were planned and nothing of A1 changed. Only nodes whose Location could
-- not be read are still searched (one pass each over those few).
function V.tie_one(sc, e)
  local lvl = V.lvl
  if not e.loc or e.loc == 0 then return nil, "spawned at no spawn point (by another enemy or the level, not by a spawner)" end
  local x = lvl.loc_index[e.loc]
  if x then
    if x.kind then return x end
    for pass = 1, 3 do for _, r in ipairs(x) do if vguard(holds, sc, r, e.h, pass) then return r end end end
    return nil, "a spawn point several spawners share, and none names this spawn"
  end
  local c = lvl.loc[e.loc]
  if c then
    for pass = 1, 3 do if vguard(holds, sc, c, e.h, pass) then return c end end
  elseif c == false then
    return nil, "its spawn point belongs to no listed spawner"
  end
  local t0, found = clock_(), nil
  for pass = 1, 3 do
    for _, r in ipairs(lvl.order) do
      if r.kind ~= "factory" and r ~= c and not (r.loc and r.loc_done) then
        if vguard(holds, sc, r, e.h, pass) then found = r; break end
        t0 = vpace(t0)
      end
    end
    if found then break end
  end
  if found then lvl.loc[e.loc] = found; return found end
  lvl.loc_miss = lvl.loc_miss or {}
  lvl.loc_miss[e.loc] = (lvl.loc_miss[e.loc] or 0) + 1
  if lvl.loc_miss[e.loc] >= 3 then lvl.loc[e.loc] = false end
  return nil, "its spawn point belongs to no listed spawner"
end

function V.verify(A, a)
  local r, ad = A.rec, V.adapters[A.rec.kind]
  local verdict
  if a and a.name and V.same_kind(a.name, a.family, A.rep.name, A.rep.family) then verdict = "REPLACEMENT SPAWNED"; ad.ok = ad.ok + 1
  elseif a and a.name and A.orig_T and V.same_kind(a.name, a.family, A.orig_T.name, A.orig_T.family) then verdict = "ORIGINAL SPAWNED"; ad.original = ad.original + 1
  elseif a and a.name and r.kind == "group" then
    verdict = "ORIGINAL SPAWNED (a group member)"
    local G = groups_t()[r.key] or ""
    local member = false
    for m in G:gmatch("[^,]+") do
      local mf, mn = m:match("^([^:]*):(.*)$")
      if V.same_kind(mn, mf ~= "-" and mf or nil, a.name, a.family) then member = true end
    end
    if member then ad.original = ad.original + 1 else verdict = "SOMETHING ELSE SPAWNED"; ad.other = ad.other + 1 end
  elseif a and a.name then verdict = "SOMETHING ELSE SPAWNED"; ad.other = ad.other + 1
  else return end                                                           -- the actor is gone: the next spawn decides
  if verdict == "SOMETHING ELSE SPAWNED" and A.rep.src == "template actor" then
    V.learn(A.rep, a, "spawn")                                              -- its template actor misled: what it really makes
    if not V.group_of(A.rep) then A.verified = verdict; V.put_back(A, "the replacement is no regular enemy"); return end
  end
  -- dev 10.31: a LATE change (its spawner had spawned before it was changed, "all" mode) may still see originals the
  -- spawner had queued: up to V.LATE_GRACE of them are no verdict (not "the game ignored it", which puts the change
  -- back and can switch the adapter off for the session)
  -- dev 10.33: ... and never a verdict. Round43 Cordelion: C2E2DEEAE2E3C44B and C973D8BB298A4F20 were changed after
  -- their first spawn and made 5 / 3 more originals: a factory keeps the enemies it queued for this run. 10.32 then
  -- put the change back ("the game ignored the change") and showed FAILED. The change now stays for the factory's
  -- next run (the next wave); nothing is put back and nothing counts against the adapter.
  if A.late and verdict:find("ORIGINAL", 1, true) then
    A.late_orig = (A.late_orig or 0) + 1
    ad.original = ad.original - 1
    if A.late_orig == 1 then
      vlog(string.format("VERIFY %s %s: late change - the factory still makes the enemies it queued before; the change stays for its next run",
          V.ADAPTER_LABEL[r.kind], tostring(r.key)))
    end
    return
  end
  A.verified = verdict
  -- dev 10.30: a spawn is not proof it fights: its components against the game's own of that kind, its combat pair
  local init = verdict == "REPLACEMENT SPAWNED" and V.init_check(A, a, A.first_h or 0) or nil
  vlog(string.format("VERIFY %s %s: requested %s, spawned %s: %s%s", V.ADAPTER_LABEL[r.kind], tostring(r.key), tostring(V.short(A.rep.name)),
      tostring(V.short(a.name)), verdict, init and (" | initialization " .. init .. " | combat " .. V.compat_label(A) ..
      " - a death of it is the proof") or ""))
  if A.restored then return end                                            -- the initialization check put it back
  -- dev 10.29: on screen, for every changed spawner's first spawn (V.note: a queue, one note at a time)
  local orig_name = A.orig_T and V.display(A.orig_T.name, A.orig_T.family) or "group (" .. tostring(groups_t()[r.key] or "?"):gsub("[%w_]*:", "") .. ")"
  if verdict == "REPLACEMENT SPAWNED" then
    V.session.said_ok = true
    -- dev 10.32: round42 on Cordelion - "it said enemies randomized but I didn't notice": every kind loaded there was a
    -- Nefarious trooper. The level's first note says so (the game can only spawn enemies whose template is loaded here)
    local sp = V.species_here()
    local lvl = V.lvl
    if #sp == 1 and not lvl.one_species_said then
      lvl.one_species_said = true
      vlog(string.format("only %s are loaded on this level: replacements come from them (another planet's enemies are not loaded here)", sp[1]))
      V.note(orig_name, V.display(A.rep.name, A.rep.family), "SUCCESS - only " .. sp[1] .. " are loaded here")
    else
      V.note(orig_name, V.display(A.rep.name, A.rep.family), "SUCCESS")
    end
  end
  -- dev 10.33: a change the game ignored is put back and logged (VERIFY line above); no on-screen FAILED note
  if verdict:find("ORIGINAL", 1, true) then
    V.put_back(A, "the game ignored the change")
    if ad.ok == 0 and ad.original >= V.FAIL_LIMIT and ad.on then
      ad.on = false
      local n = 0
      for _, B in ipairs(V.lvl.arms) do if not B.restored and B.rec.kind == r.kind then V.put_back(B, "adapter off"); n = n + 1 end end
      vlog(string.format("ADAPTER OFF for this session: %s - the game ignored %d change(s) and made none (%d more put back)",
          V.ADAPTER_LABEL[r.kind], ad.original, n))
      if not V.session.said_off[r.kind] then
        V.session.said_off[r.kind] = true
        say("Enemy Randomizer: one kind of spawner cannot be changed", { type = "corner", sub = V.ADAPTER_LABEL[r.kind] .. " - kept original", duration = 5 })
      end
    end
  end
end

-- ---- dev 10.29: what you see on screen and what rivet.log keeps for every enemy spawn ---------------------------
-- V.note: one note per changed spawner's first spawn ([ENEMY RANDOMIZER] Original / Replacement / Result), queued and
-- shown one every V.NOTE_GAP frames; at most V.NOTE_QUEUE wait (the rest are counted into the next note). Setting
-- enemy_notify = false turns the notes off (the log keeps everything).
V.notes = V.notes or {}
function V.note(orig, rep, result)
  local cfg = RANDO and RANDO.config or {}
  if cfg.enemy_notify == false then return end
  if #V.notes >= V.NOTE_QUEUE then V.notes_dropped = (V.notes_dropped or 0) + 1; return end
  V.notes[#V.notes + 1] = { orig = orig, rep = rep, result = result }
end
function V.notes_tick(frame)
  if #V.notes == 0 or frame < (V.note_next or 0) then return end
  local n = table.remove(V.notes, 1)
  local more = V.notes_dropped or 0
  V.notes_dropped = 0
  V.note_next = frame + V.NOTE_GAP
  say("[ENEMY RANDOMIZER] " .. n.result, { type = "corner", duration = 3,
      sub = string.format("Original: %s  ->  Replacement: %s%s", n.orig, n.rep, more > 0 and string.format("  (+%d more)", more) or "") })
end

-- the ledger: every spawn of an enemy (regular or boss tier) - original, selected, spawned, planet, encounter,
-- spawner, result and, when it kept its enemy, why. Per level: counts by result and reason (V.summary), and the
-- first V.LEDGER_LOG lines in rivet.log ("SPAWN ...").
function V.encounter()
  local m = V.mission or "-"
  local cp = RANDO_TRAVEL and RANDO_TRAVEL.last_checkpoint
  local cpn = type(cp) == "table" and cp.name or nil
  return cpn and (m .. " @ " .. tostring(cpn)) or m
end
function V.ledger_add(e, r, a, A, result, why)
  local lvl = V.lvl
  local L = lvl.ledger
  L.eligible = L.eligible + 1
  if result == "SUCCESS" then L.replaced = L.replaced + 1
  elseif result == "ORIGINAL" then L.original = L.original + 1
  elseif result == "OTHER" then L.other = L.other + 1
  else
    L.unchanged = L.unchanged + 1
    local k = tostring(why or "?")
    L.reasons[k] = (L.reasons[k] or 0) + 1
  end
  local kind = V.short(a.name) .. "/" .. tostring(a.family)
  local kk = L.kinds[kind] or { n = 0, replaced = 0 }
  kk.n = kk.n + 1
  if result == "SUCCESS" then kk.replaced = kk.replaced + 1 end
  L.kinds[kind] = kk
  if L.logged < V.LEDGER_LOG then
    L.logged = L.logged + 1
    local orig = (A and A.orig_T and A.orig_T.name) or (r and r.orig and r.orig.single and lvl.tpl[r.orig.actors] and lvl.tpl[r.orig.actors].name) or a.name
    vlog(string.format("SPAWN %d | %s | %s | %s %s | original %s | selected %s | spawned %s (%s) | %s%s", e.h,
        tostring(vstate() and vstate().current_planet), V.encounter(), r and V.ADAPTER_LABEL[r.kind] or "no spawner",
        r and tostring(r.key) or "-", tostring(V.short(orig)), A and tostring(V.short(A.rep.name)) or "-", tostring(V.short(a.name)),
        tostring(a.family), result, why and (": " .. tostring(why)) or ""))
  end
end
function V.eligible(a)
  if not (a and a.family) then return false end
  local role = V.role_of(a)
  return role == "enemy" or role == "boss"
end

-- one spawn: learn, verify, keep group members, follow the changed ones (dev 10.28: one at a time, see V.pump)
-- dev 10.29: RE-ENTRANT. rivet_hook's budget error can stop it at any line; V.pump then runs it again for the same
-- spawn, and every step that counts or writes (the spawner's count, the ledger, the encounter's list, the verdict)
-- happens once per spawn (e.* marks). No spawn is dropped and none is counted twice.
function V.process_one(sc, e)
  if e.done then return end
  local lvl = V.lvl
  if not e.resolved then
    if e.fac ~= 0 then
      e.r = V.factory_rec(e.fac)
      if not e.r then e.tie_why = "its factory has no Templates variable" end
    else e.r, e.tie_why = V.tie_one(sc, e) end
    e.resolved = true
  end
  local r, tie_why = e.r, e.tie_why
  -- a spawner known to make no enemy (portals, cars, props): counted, nothing else asked (round39: most spawns)
  if r and r.not_enemy and not r.arm then
    if not e.counted then e.counted = true; r.spawned = (r.spawned or 0) + 1 end
    e.done = true
    return
  end
  if not r then
    -- dev 10.29: a spawn point no listed node has yet waits for the next listing once (round39: Zurkon's pub brawl
    -- nodes and Sargasso's nodes were listed after their first spawns); the listing is made at once
    if e.fac == 0 and e.loc and e.loc ~= 0 and not e.deferred and tie_why and tie_why:find("no listed spawner", 1, true) then
      e.deferred = true
      e.deferred_scan = lvl.scans
      lvl.deferred[#lvl.deferred + 1] = e
      lvl.next_scan = math.min(lvl.next_scan, (SP.frame or 0) + 1)
      e.done = true
      return
    end
    if e.a == nil then e.a = V.actor(e.h) or false end
    local a = e.a or nil
    if e.fac == 0 and not e.counted then e.counted = true; lvl.untied = lvl.untied + 1 end
    if V.eligible(a) and not e.ledgered then
      e.ledgered = true
      lvl.activity = SP.frame or 0
      V.sig_note(a)                                                         -- dev 10.30: the game's own enemy
      V.ledger_add(e, nil, a, nil, "NOT CHANGED", "not tied to a spawner: " .. tostring(tie_why))
      if e.fac == 0 and lvl.untied_logged < V.UNTIED_LOG then
        lvl.untied_logged = lvl.untied_logged + 1
        vlog(string.format("spawn %d of %s (%s) at location %s index %s: tied to no spawner variable (SpawnFactory 0): %s",
            e.h, tostring(V.short(a.name)), tostring(a.family), tostring(e.loc), tostring(e.idx), tostring(tie_why)))
      end
    end
    e.done = true
    return
  end
  if not e.counted then e.counted = true; r.spawned = (r.spawned or 0) + 1 end
  if e.a == nil then e.a = V.actor(e.h) or false end
  local a = e.a or nil
  if a and V.FAMILY_GROUP[a.family or ""] then lvl.activity = SP.frame or 0 end
  if e.A == nil then e.A = r.arm or false end                              -- the change in place when it spawned
  local A = e.A or nil
  -- dev 10.29: the ledger (before verify, which may put the spawner back)
  if V.eligible(a) and not e.ledgered then
    e.ledgered = true
    if A and not A.restored then
      local res = V.same_kind(a.name, a.family, A.rep.name, A.rep.family) and "SUCCESS"
                  or (A.orig_T and V.same_kind(a.name, a.family, A.orig_T.name, A.orig_T.family)) and "ORIGINAL" or "OTHER"
      if r.kind == "group" and res == "OTHER" then
        for m in (groups_t()[r.key] or ""):gmatch("[^,]+") do
          local mf, mn = m:match("^([^:]*):(.*)$")
          if V.same_kind(mn, mf ~= "-" and mf or nil, a.name, a.family) then res = "ORIGINAL" end
        end
      end
      V.ledger_add(e, r, a, A, res, res ~= "SUCCESS" and "the game spawned something else than the variable held" or nil)
    else
      local why = r.why_said
      if why == "CHANGED" or why == nil then
        why = r.restored_frame and ("put back: " .. tostring(r.put_back_why or "?"))
              or (r.orig == nil and "spawned before the randomizer read its spawner")
              or "spawned before the randomizer planned it"
      end
      V.ledger_add(e, r, a, nil, "NOT CHANGED", why)
    end
  end
  if A and not A.restored then
    if not e.armcounted then
      e.armcounted = true
      A.spawns = A.spawns + 1
      A.alive[e.h] = true; A.alive_n = A.alive_n + 1; A.last_activity = SP.frame
      -- dev 10.30: every replaced bot is watched until it dies (V.combat_watch / V.combat_died)
      local replaced = a and a.name and V.same_kind(a.name, a.family, A.rep.name, A.rep.family)
      lvl.spawned[e.h] = { A = A, T = A.rep, frame = SP.frame or 0, deaths0 = V.kills(lvl), pairs = replaced and A.pairs or {},
                           compat = A.compat, orig = A.orig_label, orig_display = A.orig_display }
      if replaced then
        A.first_h = A.first_h or e.h
        lvl.watch = lvl.watch or {}
        lvl.watch[#lvl.watch + 1] = e.h
        for _, p in ipairs(A.pairs or {}) do local c = V.combat_c(p); c.spawned = c.spawned + 1 end
      end
      if lvl.logged < V.SPAWN_LOG then
        lvl.logged = lvl.logged + 1
        vlog(string.format("spawn %d of changed %s %s: %s", e.h, V.ADAPTER_LABEL[r.kind], tostring(r.key), tostring(a and V.short(a.name))))
      end
    end
    if not A.verified and not e.verified then e.verified = true; V.verify(A, a) end
    if r.kind == "group" and not A.restored and A.verified == "REPLACEMENT SPAWNED" and not e.rotated then e.rotated = true; V.rotate(sc, A) end
    e.done = true
    return
  end
  if not (a and a.name) then e.done = true; return end
  -- a spawn of a spawner put back moments ago may still be the replacement: nothing is learned from it
  if r.restored_frame and (SP.frame or 0) - r.restored_frame < 120 then e.done = true; return end
  if V.eligible(a) and not e.sig then e.sig = true; V.sig_note(a) end      -- dev 10.30: what the game's own have
  if r.kind == "group" then
    if not a.family then r.not_enemy = true end                         -- a vehicle, a prop: never this group
    local fam = a.family or "-"
    local G = groups_t()[r.key]
    local has = false
    local n = 0
    for m in (G or ""):gmatch("[^,]+") do
      n = n + 1
      local mf, mn = m:match("^([^:]*):(.*)$")
      if V.same_kind(mn, mf ~= "-" and mf or nil, a.name, a.family) then has = true end
    end
    if not has and n < V.MEMBER_CAP then
      local Gt = groups_t(true)
      local ok = true
      if G == nil then
        local c = 0
        for _ in pairs(Gt) do c = c + 1 end
        if c >= V.GROUP_CAP then ok = false end
      end
      if ok then
        Gt[r.key] = (G and G ~= "" and (G .. ",") or "") .. fam .. ":" .. V.short(a.name)
        if RANDO and RANDO.mark_changed then RANDO.mark_changed() end
        vlog(string.format("group node %s: member %s (%s)", tostring(r.key), V.short(a.name), fam))
        lvl.dirty = true
      end
    end
  else
    local v = V.var(sc, r.var.idx, r.var.gen)
    if v and v.single then
      local T = V.tpl_of(v.actors, v.uid)
      V.learn(T, a, "spawn")
      lvl.spawned[e.h] = { T = T }
      if r.kind == "template" and not V.group_of(T) and not T.mixed then r.not_enemy = true end   -- dev 10.29: boss tier stays
    end
  end
  e.done = true
end

-- ---- deaths, health bars, checkpoints, the watchdog --------------------------------------------------------
-- dev 10.28: ANY death keeps the level "active" for the stuck rule (round38: the event came, but never with a bot the
-- randomizer could match); a death that names one of our spawned bots also takes it off its encounter's list
function V.on_death(f, ev)
  local lvl = V.lvl
  if not lvl then return end
  lvl.activity = SP.frame or 0
  lvl.deaths_seen = lvl.deaths_seen + 1
  lvl.last_death = SP.frame or 0                                           -- dev 10.32: the stall watch
  local s = f.SenderHandle or (type(ev) == "table" and ev.sender)
  local h = math.tointeger(tonumber(s))
  local x = h and lvl.spawned[h]
  if type(x) ~= "table" or not x.A then return end
  local A = x.A
  if A.alive[h] then A.alive[h] = nil; A.alive_n = A.alive_n - 1; A.last_activity = SP.frame; lvl.deaths_tied = (lvl.deaths_tied or 0) + 1 end
  if x.pairs and #x.pairs > 0 then V.combat_died(h, x) end                -- dev 10.30: the proof the pair fights
end
function V.on_health_bar(f, ev)
  if f.IsFriendly == true then return end
  local lvl = V.lvl
  local s = f.SenderHandle or (type(ev) == "table" and ev.sender)
  local h = math.tointeger(tonumber(s))
  local x = lvl and h and lvl.spawned[h]
  local T = type(x) == "table" and x.T
  if not T or T.hb then return end
  T.hb = true
  T.role = V.role_of(T)
  if T.uid then V.reg_put(T.uid, T) end
  vlog(string.format("%s showed a health bar: boss tier, never used by the Enemy Randomizer", tostring(V.short(T.name))))
  for _, A in ipairs(lvl.arms) do
    -- dev 10.29: only the Enemy Randomizer's changes (a boss-tier change between boss-tier kinds stays)
    if not A.restored and (A.role or "enemy") == "enemy" and (A.rep == T or A.orig_T == T) then V.put_back(A, "boss tier (health bar)") end
  end
end
function V.on_checkpoint(cp)
  if not (type(cp) == "table" and cp.loaded) then
    local lvl = V.lvl
    if SP.zone and not V.in_zone and lvl and #lvl.arms > 0 then V.put_back_all("story boss area " .. tostring(SP.zone)) end
    if not SP.zone and V.in_zone and lvl then
      for _, r in ipairs(lvl.order) do if not r.arm then r.tried = nil end end      -- left it: fresh spawners may change again
    end
    V.in_zone = SP.zone ~= nil
    return
  end
  V.in_zone = SP.zone ~= nil
  -- a changed encounter that was running when the checkpoint was loaded counts one retry
  local lvl = V.lvl
  if lvl and V.enabled() then
    for _, A in ipairs(lvl.arms) do
      if not A.restored and A.spawns > 0 and A.alive_n > 0 then
        local k = A.rec.key
        V.session.retries[k] = (V.session.retries[k] or 0) + 1
        if V.session.retries[k] >= V.RETRY_LIMIT then
          V.block(A, "the checkpoint was loaded " .. V.session.retries[k] .. " times while it ran")
          say("Enemy Randomizer: an encounter you retried " .. V.session.retries[k] .. " times has its original enemies now",
              { type = "corner", duration = 6 })
        end
      end
    end
  end
  V.reset("checkpoint loaded")
end
-- dev 10.28: the stuck rule. 10.27 called an encounter stuck when no death NAMED one of its bots for 180 s - and in
-- round38 no death ever did: all 5 changed A1 factories were "stuck" while you fought, and saved "kept original" for
-- the seed. Now: (1) bots that no longer answer are taken off their encounter (V.gone, a few per second); (2) stuck =
-- some of its bots still answer AND the whole level was quiet for V.STUCK_SECONDS (no death of anything, no enemy
-- spawn, no bot gone); (3) stuck puts the spawner back for this level only and counts one retry - only V.RETRY_LIMIT
-- retries keep it original for the seed.
function V.watchdog()
  local lvl = V.lvl
  if not lvl then return end
  local checked = 0
  for _, A in ipairs(lvl.arms) do
    if not A.restored and A.alive_n > 0 then
      for h in pairs(A.alive) do
        if checked >= V.ALIVE_CHECKS then break end
        checked = checked + 1
        if V.gone(h) then
          A.alive[h] = nil; A.alive_n = A.alive_n - 1; A.last_activity = SP.frame
          lvl.gone_seen = lvl.gone_seen + 1
          lvl.activity = SP.frame
          local x = lvl.spawned[h]                                           -- dev 10.30: no longer watched
          lvl.last_death = SP.frame or 0                                     -- dev 10.33: a bot gone = the fight goes on
          if type(x) == "table" and not x.dead and not x.gone then V.combat_gone(h, x) end
        end
      end
    end
  end
  V.combat_watch()                                                          -- dev 10.30
  for _, A in ipairs(lvl.arms) do
    local quiet = SP.frame - math.max(A.last_activity or 0, lvl.activity or 0)
    if not A.restored and A.alive_n > 0 and quiet > V.STUCK_SECONDS * 60 then
      local k = A.rec.key
      V.session.retries[k] = (V.session.retries[k] or 0) + 1
      if V.session.retries[k] >= V.RETRY_LIMIT then
        V.block(A, "stuck or retried " .. V.session.retries[k] .. " times")
      else
        V.put_back(A, string.format("the level was quiet %d s with %d of its enemies alive (retry %d of %d)", V.STUCK_SECONDS,
            A.alive_n, V.session.retries[k], V.RETRY_LIMIT))
      end
      if not lvl.stuck_said then
        lvl.stuck_said = true
        say("Enemy Randomizer: an encounter looks stuck - its next enemies here are the original ones (load the last checkpoint if an enemy cannot be reached)",
            { type = "corner", duration = 8 })
      end
    end
  end
end

-- dev 10.28: 10.27's watchdog saved "kept original for the seed" for encounters that were not stuck (round38: 5 Zurkon
-- A1 factories). Those entries are dropped once per save (10.28 never writes that reason).
function V.migrate()
  local s = vstate()
  if not s or V.migrated_state == s then return end
  V.migrated_state = s
  local n = 0
  for k, why in pairs(s.spawn_blocked or {}) do
    if type(k) == "string" and k:sub(1, 2) == "v:" and tostring(why):find("without a death", 1, true) then
      s.spawn_blocked[k] = nil; n = n + 1
    end
  end
  if n > 0 then
    vlog(string.format("%d spawner(s) 10.27 wrongly kept original (\"stuck\" while you fought) are randomized again", n))
    if RANDO and RANDO.mark_changed then RANDO.mark_changed() end
  end
end

-- ---- the frame ---------------------------------------------------------------------------------------------
-- dev 10.28: ONE job, V.pump, whose progress lives in the level record (the put-back list, the spawn queue, the plan
-- cursor), so a frame-budget error that kills it loses nothing: the job is started again from where it was. Round38:
-- ~100 "ran past the 8 ms frame budget" RANDO-ERRORs, each one dropped a batch of spawns (never verified, never learned)
-- and the plan restarted from the first spawner. Budget errors are now counted (level summary), not logged one by one.
function V.start(fn)
  V.job_fn, V.job_restarts, V.job_progress = fn, 0, V.progress or 0
  V.job = coroutine.create(fn)
end

function V.pump(sc)
  if not V.drain_pending() then return end                                 -- put-backs first: nothing is read before
  local lvl = V.lvl
  local t0 = clock_()
  if lvl.scan_due then
    V.scan(sc)                                                              -- memoized: a restart continues it
    lvl.scan_due = false
    t0 = clock_()
  end
  -- dev 10.29: spawns waiting for a listing go again (once), first
  if #lvl.deferred > 0 then
    local keep, again = {}, {}
    for _, e in ipairs(lvl.deferred) do
      if (e.deferred_scan or 0) < lvl.scans then
        e.done, e.tries, e.resolved, e.r, e.tie_why = false, 0, nil, nil, nil
        again[#again + 1] = e
      else keep[#keep + 1] = e end
    end
    lvl.deferred = keep
    for i = #again, 1, -1 do table.insert(lvl.queue, 1, again[i]) end
  end
  -- dev 10.29: a budget error inside process_one waits for the next frame and the same spawn goes on (process_one
  -- is re-entrant); only a spawn that keeps failing for another reason (3 times) or ran 60 frames into the budget is
  -- given up - and counted ("spawns given up" in the level detail)
  while lvl.scans > 0 and #lvl.queue > 0 do
    local e = lvl.queue[1]
    local finished = true
    if not e.done then
      local ok, err = pcall(V.process_one, sc, e)
      if not ok then
        local budget = tostring(err):find("budget", 1, true) ~= nil
        if budget then
          V.budget_hits = (V.budget_hits or 0) + 1
          e.budget = (e.budget or 0) + 1
          finished = e.budget > 60
        else
          e.tries = (e.tries or 0) + 1
          finished = e.tries >= 3
          if not lvl.errors[tostring(err)] then lvl.errors[tostring(err)] = true; vlog("RANDO-ERROR spawn " .. tostring(e.h) .. ": " .. tostring(err)) end
        end
        if finished then lvl.given_up = (lvl.given_up or 0) + 1 end
        if not finished and coroutine.isyieldable() then coroutine.yield(); t0 = clock_() end
      end
    end
    if finished and lvl.queue[1] == e then table.remove(lvl.queue, 1) end
    if finished then t0 = vpace(t0) end
  end
  if lvl.scans > 0 and (lvl.dirty or lvl.arm_running) then
    if not lvl.arm_running then lvl.arm_running, lvl.dirty, lvl.arm_i = true, false, 1 end
    while lvl.arm_i <= #lvl.order do
      vguard(V.plan_rec, sc, lvl.order[lvl.arm_i])
      lvl.arm_i = lvl.arm_i + 1
      t0 = vpace(t0)
    end
    lvl.arm_running = false
  end
end
-- kept for the tests and developer files of 10.27
function V.arm_pass(sc)
  local t0 = clock_()
  for _, r in ipairs(V.lvl.order) do
    vguard(V.plan_rec, sc, r)
    t0 = vpace(t0)
  end
end

local function job_error(err)
  local lvl = V.lvl
  local msg = tostring(err)
  if lvl and lvl.errors[msg] then return end
  if lvl then lvl.errors[msg] = true end
  vlog("RANDO-ERROR " .. msg)
end

function V.tick(frame, ready)
  if not V.lvl then V.new_level("scripts loaded") end
  local lvl = V.lvl
  if not V.enabled() then
    V.job = nil
    if #lvl.arms > 0 then V.put_back_all("Enemy Randomizer off"); lvl.arms = {} ; for _, r in ipairs(lvl.order) do r.tried = nil end end
    if #V.pending > 0 and ready then pcall(V.drain_pending) end
    lvl.queue = {}
    return
  end
  if not ready then return end
  V.migrate()
  V.notes_tick(frame)
  -- dev 10.29: one of the two clients switched off: its changes go back (the other's stay)
  for _, A in ipairs(lvl.arms) do
    if not A.restored and not V.role_on(A.role or "enemy") then
      V.put_back(A, (A.role == "boss" and "Boss" or "Enemy") .. " Randomizer off")
      A.rec.tried = nil
    end
  end
  -- dev 10.30: the watchdog (gone bots, stuck encounters, the combat watch) also while a long job runs (a busy level
  -- kept 10.29's job running for many seconds and its watchdog waited)
  if frame % 60 == 0 then
    local okw, errw = pcall(V.watchdog)
    if not okw and not tostring(errw):find("budget", 1, true) then job_error(errw) end
  end
  if V.job then
    local ok, err = coroutine.resume(V.job)
    if not ok then
      if tostring(err):find("budget", 1, true) then
        V.budget_hits = (V.budget_hits or 0) + 1
        if (V.progress or 0) ~= V.job_progress then V.job_progress, V.job_restarts = V.progress or 0, 0 end
        V.job_restarts = (V.job_restarts or 0) + 1
        if V.job_restarts <= V.RESTART_CAP then
          V.job = coroutine.create(V.job_fn)
        else
          V.job = nil
          lvl.jobs_dropped = (lvl.jobs_dropped or 0) + 1
          lvl.queue = {}                                                    -- spawns of a level too busy to follow
        end
      else
        V.job = nil
        job_error(err)
      end
    elseif coroutine.status(V.job) == "dead" then V.job = nil end
    return
  end
  local due = frame >= lvl.next_scan
  local work = due or #V.pending > 0 or (lvl.scans > 0 and (#lvl.queue > 0 or lvl.dirty or lvl.arm_running))
               or (#lvl.deferred > 0 and frame >= lvl.next_scan)
  if not work then return end
  local sc, why = V.scene()
  if not sc then
    lvl.next_scan = frame + V.SCAN_EVERY
    lvl.queue = {}
    if not lvl.blocked_said then
      lvl.blocked_said = true
      vlog("BLOCKED: " .. tostring(why))
      if not V.session.said_blocked then
        V.session.said_blocked = true
        say("Enemy Randomizer cannot work", { type = "corner", sub = tostring(why), duration = 8 })
      end
    end
    return
  end
  if due then lvl.next_scan, lvl.scan_due = frame + V.SCAN_EVERY, true end
  V.start(function() V.pump(sc) end)
end

-- the switch: off puts everything back at once (V.tick); on changes only spawners that have not run yet
function V.on_switch(on, client)
  if on then
    if V.lvl then
      V.lvl.next_scan = SP.frame or 0; V.lvl.dirty = true
      for _, r in ipairs(V.lvl.order) do if not r.arm then r.tried = nil end end
    end
  elseif V.lvl then
    -- dev 10.29: only the changes of the client switched off
    local role = client and client.role or nil
    local label = client and client.label or "Enemy Randomizer"
    local n = 0
    for _, A in ipairs(V.lvl.arms) do
      if not A.restored and (role == nil or (A.role or "enemy") == role) then V.put_back(A, label .. " off"); A.rec.tried = nil; n = n + 1 end
    end
    if n > 0 then vlog(string.format("%d changed spawner(s) put back: %s off", n, label)) end
  end
end

function V.status()
  local lvl = V.lvl
  local out = { changed = 0, factory = 0, template = 0, group = 0, kinds = 0, known = 0, ok = 0, original = 0 }
  if lvl then
    for _, A in ipairs(lvl.arms) do if not A.restored then out.changed = out.changed + 1; out[A.rec.kind] = out[A.rec.kind] + 1 end end
    local names = {}
    for _, T in pairs(lvl.tpl) do
      local k = tostring(V.short(T.name)) .. "/" .. tostring(T.family)
      if V.usable(T) and not names[k] then names[k] = true; out.kinds = out.kinds + 1 end
    end
  end
  for _, uid in ipairs(V.reg_uids()) do local e = V.reg_get(uid); if e and e.role == "enemy" and not e.hb and not e.mixed then out.known = out.known + 1 end end
  for _, ad in pairs(V.adapters) do out.ok, out.original = out.ok + ad.ok, out.original + ad.original end
  -- dev 10.29: this level's enemy spawns (the ledger)
  local L = lvl and lvl.ledger
  out.spawns, out.replaced, out.unchanged = L and L.eligible or 0, L and L.replaced or 0, L and L.unchanged or 0
  local top, topn = nil, 0
  for reason, n in pairs(L and L.reasons or {}) do if n > topn then top, topn = reason, n end end
  out.top_reason = top
  out.species = lvl and V.species_here() or {}                             -- dev 10.32
  out.stalls = lvl and lvl.stalls or 0
  -- dev 10.30: combat compatibility
  out.compat = V.compat_mode()
  out.pairs_verified, out.pairs_rejected = 0, 0
  for p in pairs(V.COMPAT_BUILTIN) do
    local st = V.compat_status(p)
    if st == "verified" then out.pairs_verified = out.pairs_verified + 1 elseif st == "rejected" then out.pairs_rejected = out.pairs_rejected + 1 end
  end
  for p in pairs(compat_t()) do
    if not V.COMPAT_BUILTIN[p] then
      local st = V.compat_status(p)
      if st == "verified" then out.pairs_verified = out.pairs_verified + 1 elseif st == "rejected" then out.pairs_rejected = out.pairs_rejected + 1 end
    end
  end
  return out
end

function V.summary()
  local lvl = V.lvl
  local parts = {}
  for _, k in ipairs({ "factory", "template", "group" }) do
    local ad = V.adapters[k]
    parts[#parts + 1] = string.format("%s: %s, %d changed, %d replaced, %d original, %d other", k, ad.on and "on" or "OFF", ad.armed, ad.ok, ad.original, ad.other)
  end
  local active = 0
  for _, A in ipairs(lvl.arms) do if not A.restored then active = active + 1 end end
  vlog(string.format("level summary (%s): %d spawner variable(s), %d changed (%d still), budget retries %d | session %s",
      tostring(lvl.why), #lvl.order, #lvl.arms, active, V.budget_hits or 0, table.concat(parts, " | ")))
  -- dev 10.28: what the next test needs to know about the routes that changed nothing in round38
  local why = {}
  for _, k in ipairs({ "factory", "template", "group" }) do               -- dev 10.29: factories too
    local t = lvl.why_not[k]
    if t then
      local keys = {}
      for reason, n in pairs(t) do if n > 0 then keys[#keys + 1] = reason end end
      table.sort(keys)
      local p = {}
      for _, reason in ipairs(keys) do p[#p + 1] = string.format("%d %s", t[reason], reason) end
      if #p > 0 then why[#why + 1] = V.ADAPTER_LABEL[k] .. ": " .. table.concat(p, ", ") end
    end
  end
  vlog(string.format("level detail: %s | SpawnFactory-0 spawns tied to nothing %d | deaths seen %d (of our bots %d), bots gone %d | stalls %d | jobs dropped %d | spawns given up %d | spawn points indexed %d | species %s",
      #why > 0 and table.concat(why, " | ") or "no node spawner considered", lvl.untied, lvl.deaths_seen, lvl.deaths_tied or 0,
      lvl.gone_seen, lvl.stalls or 0, lvl.jobs_dropped or 0, lvl.given_up or 0, lvl.loc_indexed,
      (function() local sp = V.species_here(); return #sp > 0 and table.concat(sp, ", ") or "-" end)()))
  -- dev 10.29: the answer to "are enemies being replaced?" for this level, from every enemy spawn
  local L = lvl.ledger
  if L.eligible > 0 then
    local rk = {}
    for reason in pairs(L.reasons) do rk[#rk + 1] = reason end
    table.sort(rk, function(a, b) return L.reasons[a] > L.reasons[b] end)
    local rp = {}
    for i = 1, math.min(#rk, 6) do rp[#rp + 1] = string.format("%d %s", L.reasons[rk[i]], rk[i]) end
    local kp = {}
    local kk = {}
    for k in pairs(L.kinds) do kk[#kk + 1] = k end
    table.sort(kk)
    for _, k in ipairs(kk) do kp[#kp + 1] = string.format("%s %d/%d", k, L.kinds[k].replaced, L.kinds[k].n) end
    vlog(string.format("ENEMY SPAWNS on this level: %d, replaced %d (%d%%), original despite a change %d, something else %d, not changed %d%s | by kind (replaced/spawned): %s",
        L.eligible, L.replaced, math.floor(100 * L.replaced / L.eligible + 0.5), L.original, L.other, L.unchanged,
        #rp > 0 and (" - why: " .. table.concat(rp, "; ")) or "", table.concat(kp, ", ")))
  end
  -- dev 10.30: every replacement pair of this level against the game's deaths (a spawn is not the proof; a death is)
  for i, p in ipairs(lvl.combat_order or {}) do
    if i > 16 then vlog(string.format("COMBAT ... %d more pair(s)", #lvl.combat_order - 16)); break end
    local c = lvl.combat[p]
    local alive = 0
    for _, h in ipairs(lvl.watch or {}) do
      local x = lvl.spawned[h]
      if type(x) == "table" and not x.dead and not x.gone and not x.failed then
        for _, q in ipairs(x.pairs or {}) do if q == p then alive = alive + 1 end end
      end
    end
    local st, ev = V.compat_status(p)
    vlog(string.format("COMBAT %s: replaced bots spawned %d, died %d, gone %d, alive at the end %d%s | pair %s%s", p, c.spawned, c.died,
        c.gone, alive, c.rejected and " | REJECTED here" or "", st, ev and (" (" .. ev .. ")") or ""))
  end
end

-- dev 10.33: bolts picked up = something was killed (10_rando_runtime.lua calls this for every GainBoltEvent)
if R then
  R.on_gain_bolt = function()
    local lvl = SP.V and SP.V.lvl
    if lvl then lvl.last_death = SP.frame or 0; lvl.bolts_seen = (lvl.bolts_seen or 0) + 1 end
  end
end

-- dev 10.29: the encounter for the ledger: the last mission that became active (a challenge, a story segment),
-- taken from the runtime's own mission handler (no new rivet callback; rivet_hook allows 64)
if R and R.on_mission_state and not V.mission_hooked then
  V.mission_hooked = true
  local orig_on_mission = R.on_mission_state
  R.on_mission_state = function(name, st, ...)
    if st == 2 and type(name) == "string" and not name:find("_CUP$") and name ~= "MIS_RYNO_PLANS" and name ~= "MIS_INTRO" then
      V.mission = name
    end
    return orig_on_mission(name, st, ...)
  end
end

-- ---------------------------------------------------------------------------------------------
-- the frame (10_rando_runtime.lua calls it)
-- ---------------------------------------------------------------------------------------------
function SP.tick(frame, ready)
  SP.frame = frame
  if SP.V then
    local okv, ev = pcall(SP.V.tick, frame, ready)
    if not okv then SP.V.job = nil; log("RANDO-ERROR enemies:", tostring(ev)) end
  end
  if ready and next(SP.revert_pending) then SP.continue_reverts() end
  if not SP.any_legacy_enabled() then
    SP.job = nil
    if not next(SP.revert_pending) then SP.level = nil end
    return
  end
  if not ready then return end
  if SP.job then
    SP.slice_t0 = clock()
    local ok, err = coroutine.resume(SP.job.co)
    if not ok then
      SP.job = nil
      -- dev 10.17: a frame that ran past rivet_hook's budget is a bad frame, not a broken level: the
      -- census starts again shortly (10.16 dropped it until the next checkpoint or planet)
      SP.census_retries = (SP.census_retries or 0) + 1
      if tostring(err):find("budget", 1, true) and SP.census_retries <= SP.CENSUS_RETRIES then
        log("census interrupted by the frame budget - reading again (" .. SP.census_retries .. "/" .. SP.CENSUS_RETRIES .. ")")
        SP.schedule_scan(SP.scan_why or "after a frame budget overrun", 20)
      else
        log("RANDO-ERROR census:", tostring(err))
      end
    elseif coroutine.status(SP.job.co) == "dead" then SP.job = nil; SP.census_retries = 0 end
    return
  end
  if (SP.scan_at and frame >= SP.scan_at) or (SP.level == nil and SP.scan_at == nil) then
    SP.start_scan(SP.scan_why or "the level is loaded")
    return
  end
  if SP.replan and SP.level then SP.replan = nil; SP.plan("learned while playing") end
  if frame % 60 ~= 0 or not SP.level then return end
  -- watchdogs: they only ever put an encounter back
  local lvl = SP.level
  for _, uid in ipairs(lvl.order) do
    local rec = lvl.nodes[uid]
    if changed_rec(rec) and rec.started and not SP.is_blocked(rec) and SP.guarded_rec(rec) then
      if rec.spawned == 0 and not rec.stopped and frame - rec.started > SP.SPAWN_TIMEOUT * 60 then
        SP.block(rec, "it started and spawned nothing for " .. SP.SPAWN_TIMEOUT .. " s")
      elseif rec.alive_n > 0 and frame - (rec.last_activity or rec.started) > SP.STUCK_SECONDS * 60 then
        SP.block(rec, "its enemies stayed alive " .. SP.STUCK_SECONDS .. " s without a death")
        say("Randomizer: an encounter looked stuck - it has its original enemies now (load the last checkpoint if an enemy cannot be reached)",
            { type = "corner", duration = 8 })
      end
    end
  end
end

-- a planet change or a level load: read the spawners again
function SP.on_level(why)
  if SP.V then pcall(SP.V.reset, why) end
  SP.level = nil
  SP.job = nil                      -- dev 10.18: a census of the level before is dropped (its nodes are gone)
  SP.census_retries = 0
  SP.spawned_by, SP.started_handles, SP.started_locs = {}, {}, {}
  SP.schedule_scan(why)
end

-- ---------------------------------------------------------------------------------------------
-- dev 10.21: LISTENERS. rivet_hook allows 64 event callbacks in all (scripting.cpp MAX_CALLBACKS); your
-- dev 10.20 log: dev(spawnprobe) "cannot subscribe PlanetChangedEvent / CheckpointTriggeredEvent: too many
-- callbacks registered, the limit is 64". Developer files listen to the spawner layer's own callbacks
-- instead: SP.listen(class, fn) costs no rivet callback. fn(fields, ev) runs for every event of the class
-- (whatever the switches say), after the layer's own handler; checkpoints come as "Checkpoint" with the
-- travel layer's { hash, name, loaded } record.
-- ---------------------------------------------------------------------------------------------
SP.listeners = SP.listeners or {}
function SP.listen(class, fn)
  SP.listeners[class] = SP.listeners[class] or {}
  table.insert(SP.listeners[class], fn)
end
function SP.notify_listeners(class, f, ev)
  for _, fn in ipairs(SP.listeners[class] or {}) do
    local ok, err = pcall(fn, f, ev)
    if not ok then log("RANDO-ERROR", "listener of", class, tostring(err)) end
  end
end

-- ---------------------------------------------------------------------------------------------
-- subscriptions (once per VM; RANDO.subscribe retries a class the game does not know yet)
-- ---------------------------------------------------------------------------------------------
if not SP.subscribed then
  SP.subscribed = true
  local sub = (R and R.subscribe) or function(class, fn) pcall(rivet.on_event, class, function(ev) pcall(fn, ev) end) end
  -- `always`: a spawner's start and stop are noted even while both are off (no read, no write), so
  -- an encounter already running when a feature is switched on is never changed
  -- dev 10.27: `vfn`, the variable route's handler (enemy.lua), runs first; the old route's handler only while
  -- Boss or Chaos is on. `always`: also while everything is off (only counting, no read, no write)
  local function on(class, fn, always, vfn, vfn_always)
    sub(class, function(ev)
      if vfn and SP.V and (vfn_always or SP.V.enabled()) then
        local ok, err = pcall(vfn, ev.fields or {}, ev)
        if not ok then log("RANDO-ERROR enemies", class, tostring(err)) end
      end
      if always or SP.any_legacy_enabled() then
        local ok, err = pcall(fn, ev.fields or {}, ev)
        if not ok then log("RANDO-ERROR", class, tostring(err)) end
      end
      if SP.listeners[class] then SP.notify_listeners(class, ev.fields or {}, ev) end
    end)
  end
  local function vcall(name) return function(...) return SP.V[name](...) end end
  on("SpawnerStartedEvent", SP.on_started, true, vcall("on_started"), true)
  on("SpawnerStoppedEvent", SP.on_stopped, true)
  on("SpawnerSpawnEvent", SP.on_spawn, false, vcall("on_spawn_seen"), true)
  on("BotDeathCompleteEvent", SP.on_death, false, vcall("on_death"))
  on("HealthBarShowEvent", SP.on_health_bar, false, vcall("on_health_bar"))
  on("BossPhaseChangeEvent", SP.on_boss_phase)
  on("LevelLoadedEvent", function() SP.on_level("level loaded") end, true)
  on("PlanetChangedEvent", function(f)
    if f.NewPlanetName then SP.on_level("planet " .. tostring(f.NewPlanetName))
    elseif f.OldPlanetName and SP.V and SP.V.lvl then pcall(SP.V.put_back_all, "leaving " .. tostring(f.OldPlanetName)) end   -- dev 10.28
  end, true)
end

log("spawner layer loaded (" .. SP.NODE_CLASS .. " Templates; families " .. #SP.FAMILY_CLASSES .. " bot classes)")
SP.V.log(string.format("variable route loaded (%s, kit %s): factory Templates, node Template, node Template group; plugs Templates %d Template %d; combat compatibility %s%s",
    tostring(RANDO and RANDO.RELEASE or "?"), tostring(RANDO_FILES["16_rando_spawners"]), SP.V.PLUG_TEMPLATES, SP.V.PLUG_TEMPLATE, SP.V.compat_mode(),
    SP.V.all_mode() and ("; ALL enemies (movement " .. (SP.V.mix_movement() and "mixed" or "kept") .. ", spent spawners change too, Nefarious troopers included)") or ""))
