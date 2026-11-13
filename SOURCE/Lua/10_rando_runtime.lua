-- Rift Apart Randomizer 10.0 runtime for rivet_hook (Lua 5.4).
--
-- Files (rivet_hook loads scripts/*.lua in name order into one VM):
--   01_rando_data.lua       game database (items, locations, planets) built from your game files
--   02_rando_generator.lua  seed generator, progression solver, spoiler log
--   03_rando_campaign.lua   3.0 campaign registry, campaign orders, campaign constraints
--   04_rando_settings.lua   your seed and options (RANDO_SETTINGS)
--   05_rando_bindings.lua   event-name bindings (planets, missions, collectibles)
--   06_rando_capabilities.lua  what mission control may do in your game (verified paths only)
--   09_rando_real.lua       puts rewards into the game's real inventory (rando_give.dll)
--   10_rando_runtime.lua    this file
--   11_rando_campaign.lua   3.0 campaign director, mission control, campaign research
--   12_rando_shop.lua       5.0 the weapon vendor's own weapons, shuffled over its slots
--   13_rando_armor.lua      5.0 armor sources: the game's armor rewards become locations
--   14_rando_travel.lua     7.0 locked levels: a planet's travel needs its Coordinates
--   15_rando_hub.lua        10.0 hub (v0.51: Nefarious City): mission selection and planet shuffle
--   16_rando_testtravel.lua 8.2 test travel (off unless test_travel = true)
--
-- What happens in the game:
--   1. The seed is generated from your settings over the first frames (a few milliseconds of
--      work, sliced so no frame is held up). Events that arrive meanwhile are kept and replayed.
--   2. The companion restores this seed's progress (or starts it fresh). The starting inventory
--      (always Hoverboots and the Map-O-Matic, plus the seed's random weapons and gadget) is
--      handed out once per playthrough.
--   3. NEW GAME: when the game's prologue starts (MIS_INTRO objective OBJ_INTRO_PARADE_START_CINE,
--      seen only on a new game in rounds 14 and 15), the seed's progress starts over and the
--      starting inventory is handed out again. The companion keeps the previous run's file.
--   4. Game events complete locations: each Gold Bolt you pick up gives exactly ONE item, at
--      once. Story missions, side activities and armor sources (pocket dimensions, Zurkie's
--      challenges, the Lorb monk) give theirs; a location without an item gives Bolts or
--      Raritanium (filler). Optional: collectibles.
--   5. Levels (7.0, travel_lock): flying to a planet without its Coordinates sends you back
--      (14_rando_travel.lua). With planet_locks alone (or if a warp is impossible) a planet's mission
--      rewards wait for its Coordinates instead (Gold Bolts never wait).
--   6. The weapon vendor sells its own weapons shuffled over its slots (12_rando_shop.lua).
--      Ammo and upgrades are not touched; 4.0's vendor lock is gone.
--   7. 10.0 (hub = true): NEW GAME goes to the hub after the parade's wrench (v0.51: Nefarious
--      City, once the parade has handed Ratchet back; the city's story starts there). The Battle
--      Arena is open from the start too, and every other destination opens with its planet's
--      Coordinates (15_rando_hub.lua). hub = false: the 9.0 story start.
-- Engine calls are wrapped in pcall; errors are logged as RANDO-ERROR and never switch the
-- randomizer off.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["10_rando_runtime"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)

RANDO = RANDO or {}
local R = RANDO
R.KIT_VERSION = "10.0.5"
R.RELEASE = "v0.54"                 -- the public release this kit belongs to (the start banner)
local DB = RANDO_DATA
local GEN = RANDO_GEN
local BIND = RANDO_BINDINGS or {}
BIND.missions = BIND.missions or {}; BIND.bolts = BIND.bolts or {}; BIND.planets = BIND.planets or {}
BIND.mission_prefixes = BIND.mission_prefixes or {}; BIND.collectible_events = BIND.collectible_events or {}

local function log(...) pcall(rivet.log, "[rando]", ...) end
R.log = log

-- ---------------------------------------------------------------------------------------
-- 8.3 keys: ordinary keyboard keys, not only F1-F12. A key setting is a name: one character
-- ("]", "/", "K", "7"), NUMPAD0-NUMPAD9, INSERT / DELETE / HOME / END / PAGEUP / PAGEDOWN, or F1-F24.
-- The names map to Windows virtual-key codes, the numbers rivet.key() itself returns (it gives
-- 0x75 for "F6"; checked at load, below). rivet_hook's own key names are tried last.
-- ---------------------------------------------------------------------------------------
R.VK = { CONTROL = 0x11, SHIFT = 0x10, ALT = 0x12, PAUSE = 0x13, SPACE = 0x20, PAGEUP = 0x21, PAGEDOWN = 0x22,
         ["END"] = 0x23, HOME = 0x24, INSERT = 0x2D, DELETE = 0x2E, BACKSPACE = 0x08, TAB = 0x09, ENTER = 0x0D }
for i = 1, 24 do R.VK["F" .. i] = 0x6F + i end
for i = 0, 9 do R.VK["NUMPAD" .. i] = 0x60 + i; R.VK[tostring(i)] = 0x30 + i end
for c = string.byte("A"), string.byte("Z") do R.VK[string.char(c)] = c end
R.VK_PUNCT = { [";"] = 0xBA, ["="] = 0xBB, [","] = 0xBC, ["-"] = 0xBD, ["."] = 0xBE, ["/"] = 0xBF, ["`"] = 0xC0,
               ["["] = 0xDB, ["\\"] = 0xDC, ["]"] = 0xDD, ["'"] = 0xDE }
-- does rivet.key() use these numbers? (it must, for our numbers to mean the same keys)
do
  local ok, f6 = pcall(rivet.key, "F6")
  R.keys_numeric = ok and f6 == 0x75
end
function R.vk(name)
  if type(name) ~= "string" or name == "" then return nil, "no key name" end
  if R.keys_numeric then
    local v = R.VK_PUNCT[name] or R.VK[name:upper()]
    if v then return v end
  end
  local ok, k = pcall(rivet.key, name)
  if ok and k ~= nil then return k end
  return nil, (R.keys_numeric and "unknown key " or "this rivet_hook knows only its own key names, not ") .. name
end
function R.key_down(name)
  local vk = R.vk(name)
  local down = false
  if vk then pcall(function() down = rivet.is_key_down(vk) == true end) end
  return down
end
function R.ctrl_down() return R.key_down("CONTROL") end
-- the key a setting names, for on-screen text ("]", "Ctrl+]")
function R.key(setting, ctrl)
  local name = (R.config and R.config[setting]) or setting
  return (ctrl and "Ctrl+" or "") .. tostring(name)
end

if not (DB and GEN) then
  log("RANDO-ERROR 01_rando_data.lua or 02_rando_generator.lua is missing from the scripts folder")
  return
end

-- ---------------------------------------------------------------------------------------
-- player settings (04_rando_settings.lua): runtime options here, randomization options go
-- to the generator (which validates them)
-- ---------------------------------------------------------------------------------------
R.config = {
  discovery = true, discovery_cap = 60, log_notifications = true,
  key_status = ";", key_campaign = "'",       -- 8.3: keyboard keys (were F9 / F12)
  real_items = true, real_weapons = true, auto_equip_armor = false,
  new_game_reset = true,             -- a new game starts the seed's progress over
  armor_intercept = true,            -- armor sources give the seed's item instead of their own piece
  shop_runtime = true,               -- apply the seed's shop shuffle to the vendor in memory
  levels_runtime = true,             -- 7.0: send you back from a locked planet (false: its rewards wait)
  -- 8.2 test travel (16_rando_testtravel.lua): go to any planet, whatever Coordinates you hold
  test_travel = false,               -- true: F7 / F8 / Ctrl+F7 / Ctrl+F8 work and nothing sends you back
  key_test_travel = ".",            -- . next planet, Ctrl+. warp there (8.3; was F7)
  key_test_point = ",",              -- , next landing point on that planet, Ctrl+, fly there with the ship (was F8)
  legacy_f_keys = true,              -- the old F5-F9 / F12 keys keep working as well
  -- 10.0 hub (15_rando_hub.lua; only for a hub seed). v0.51: the hub is Nefarious City
  hub_runtime = true,                -- false: no hub actions at all (no warps, no mission calls)
  hub_trigger = "parade",            -- New Game: go to the hub once the parade hands Ratchet back after his
                                     -- wrench (v0.51) | "wrench": at the wrench (10.0-v0.5) | "cinematic"
  hub_prologue = "end",              -- v0.51: "end" writes the prologue complete once you are at the hub (as
                                     -- the game has it before Nefarious City) | "keep": leave it to choose
  hub_start_story = true,            -- v0.51: the hub's first warp starts Nefarious City's story there
  hub_prologue_timing = "before",    -- v0.52: "before" writes the prologue complete before the city's story
                                     -- starts (the game's order, round 23) | "after": once on the city (v0.51)
  hub_opening = true,                -- v0.52: load a story at its opening scene (C.OPENINGS) while it waits at
                                     -- its first step | false: at its start checkpoint (v0.51)
  hub_force_missions = true,         -- a destination's inactive story mission is made available, then started
  hub_replay = true,                 -- if starting fails, try the game's replay call
  hub_levels = "all",                -- "all": set every level bit UnlockLevelAction can set | "off"
  hub_travel_flag = true,            -- turn planetary travel on (the ship's planet menu)
  hub_fly = true,                    -- to a landing (not a mission's start), fly when a ship answers
  hub_auto_return = true,            -- a finished destination takes you back to the hub
  hub_return_delay = 12,             -- seconds before that ([ cancels)
  restore_inventory = true,          -- v0.54: after the hub's own trips, give your items back when the load
                                     -- reports fewer than half of your weapons (Ctrl+0 twice does it by hand)
  hub_hero_swap = true,              -- a destination's hero is set before its story starts
  hub_follow_story = false,          -- true: when the game's own story takes you to an open destination, play it
  key_hub = "]",                     -- ] next destination, Ctrl+] go
  key_hub_return = "[",              -- v0.54: [ cancels the automatic return (it no longer goes back to the
                                     -- hub), Ctrl+[ twice finish a destination by hand
  key_story = "/",                   -- / start the story of the planet you are on
  key_shuffle = "0",                 -- v0.54: 0 planet shuffle off / on (remembered), Ctrl+0 twice give your
                                     -- items back
  shop_close_slots = true,           -- 10.0: closed vendor slots show the Burst Pistol (false: their own weapon)
}
R.CHOICES = { hub_trigger = { parade = true, wrench = true, cinematic = true }, hub_levels = { all = true, off = true },
              hub_prologue = { ["end"] = true, keep = true }, hub_prologue_timing = { before = true, after = true } }
-- options that no longer exist
local RETIRED_RUNTIME = { key_shop_next = "is not used since 4.0", key_shop_buy = "is not used since 4.0",
                          lock_vendor_weapons = "is not used since 5.0 (the vendor sells its own weapons, shuffled; ammo works)" }
-- 10.0: options of the 8.x hub that the 10.0 hub does not have
RETIRED_RUNTIME.hub_intro = "is not used since 10.0: v0.51's hub_prologue (\"end\" or \"keep\") decides what happens to the prologue"
RETIRED_RUNTIME.story_on_arrival = "is not used in 10.0: a planet-menu landing on an open planet starts its next destination"
RETIRED_RUNTIME.story_prime_before_travel = "is not used in 10.0: a destination's mission is always made active before the trip"
RETIRED_RUNTIME.story_reload_stuck = "is not used in 10.0: a story waiting at its first step is loaded once more on the same planet"
RETIRED_RUNTIME.story_restart_stuck = RETIRED_RUNTIME.story_reload_stuck
local SETTINGS = RANDO_SETTINGS or {}
local KEY_SETTINGS = { key_status = true, key_campaign = true, key_test_travel = true, key_test_point = true,
                       key_hub = true, key_hub_return = true, key_story = true, key_shuffle = true }
local GEN_OPTIONS = {}
for k, v in pairs(SETTINGS) do
  if R.config[k] ~= nil then
    if type(v) ~= type(R.config[k]) then
      log("RANDO-SETTINGS", k, "must be a " .. type(R.config[k]) .. " - keeping", tostring(R.config[k]))
    elseif KEY_SETTINGS[k] and not R.vk(v) then
      log("RANDO-SETTINGS", k, "= " .. tostring(v) .. " is not a key name rivet_hook knows - keeping", R.config[k])
    elseif R.CHOICES[k] and not R.CHOICES[k][v] then
      log("RANDO-SETTINGS", k, "= " .. tostring(v) .. " is not a choice - keeping", tostring(R.config[k]))
    else
      R.config[k] = v
    end
  elseif RETIRED_RUNTIME[k] then
    log("RANDO-SETTINGS", k, RETIRED_RUNTIME[k])
  elseif k ~= "seed" and k ~= "preset" then
    GEN_OPTIONS[k] = v
  end
end

-- 8.3: if rivet.key() does not use Windows key codes, keyboard key names cannot be bound: keys
-- that do not resolve go back to their old F keys
R.LEGACY_KEYS = { key_status = "F9", key_campaign = "F12", key_test_travel = "F7", key_test_point = "F8",
                  key_hub = "F6", key_hub_return = "F5", key_story = "F4" }
for setting, legacy in pairs(R.LEGACY_KEYS) do
  if not R.vk(R.config[setting]) then
    log("RANDO-SETTINGS", setting, "=", tostring(R.config[setting]), "cannot be bound here - using", legacy)
    R.config[setting] = legacy
  end
end

-- 7.0 restored_weapons = "auto": ARSENAL_RESTORED's weapons join the pool only if the mod is
-- installed. Lua cannot see the game's files, so the companion checks the game's toc for the
-- mod's added asset (Mr. Zurkon's item config) and calls rando_set_arsenal(true|false). The seed
-- is generated after that answer (or, with no companion, after R.WAIT_COMPANION_START frames, as
-- "not installed": a restored weapon is never handed out without the mod).
do
  local a = GEN_OPTIONS.restored_weapons
  if a == nil then a = GEN_OPTIONS.include_arsenal_restored end
  if a == "auto" then
    R.arsenal_pending = true
    GEN_OPTIONS.restored_weapons, GEN_OPTIONS.include_arsenal_restored = nil, nil
  end
end

-- ---------------------------------------------------------------------------------------
-- HUD messages: queued while the HUD is not loaded, so nothing is announced silently
-- ---------------------------------------------------------------------------------------
local queued = {}
local function show(text, opts)
  local ok, err = pcall(rivet.notify, text, opts)
  if ok and R.config.log_notifications then log("RANDO-NOTIFY", text) end
  return ok, err
end
local function say(text, opts)
  opts = opts or { type = "pickup", duration = 4 }
  local ok, err = show(text, opts)
  if not ok then
    log("notify failed:", err)
    if #queued < 30 then queued[#queued + 1] = { text = text, opts = opts } end
  end
end
local function flush_queue()
  while #queued > 0 do
    local m = queued[1]
    if not show(m.text, m.opts) then return end
    table.remove(queued, 1)
  end
end
R.say = say

-- ---------------------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------------------
local SEED                        -- set once generated
local S                           -- the state of this seed
R.version = 0
R.restored = false
R.boot = string.format("%x", math.floor(((rivet.time and rivet.time()) or 0) * 1000))
local function changed() R.version = R.version + 1 end
R.mark_changed = changed

local STATE_TABLES = { "collected", "paid", "banked", "access", "inventory", "story_missions", "planets_detected",
                       "bolts_seen", "armor_found", "armor_sets_done", "collectibles", "visited",
                       "history", "real", "real_nodes", "tracked", "gadgets_seen", "weapons", "gadgets",
                       "armor_sources", "currency_queue", "shop_given" }
local function fill_defaults(s)
  for _, k in ipairs(STATE_TABLES) do s[k] = s[k] or {} end
  s.planets_done = s.planets_done or 0
  s.run = s.run or 1                 -- playthrough number of this seed (a new game adds one)
  return s
end
local function fresh_state(run)
  return fill_defaults({ fingerprint = SEED.fingerprint, seed = SEED.seed, format = 8, started = false, run = run or 1 })
end

R.HISTORY_KEEP = 400            -- 8.5: entries kept in memory (the save keeps the last 60; rivet.log has all)
local function history(msg)
  if S then
    local h = S.history
    h[#h + 1] = string.format("[%d] %s", math.floor((rivet.time and rivet.time()) or 0), msg)
    if #h > R.HISTORY_KEEP + 100 then table.move(h, #h - R.HISTORY_KEEP + 1, #h, 1); for i = #h, R.HISTORY_KEEP + 1, -1 do h[i] = nil end end
    changed()
  end
  log(msg)
end
R.history = history
local function item_name(key) return GEN.item_name(key) end
local function planet_name(pid)
  for _, p in ipairs(DB.planets) do if p.id == pid then return p.name end end
  return tostring(pid)
end
R.item_name, R.planet_name = item_name, planet_name

-- ---------------------------------------------------------------------------------------
-- items
-- ---------------------------------------------------------------------------------------
local pay_banked
local function grant(key, quiet, prefix)
  prefix = prefix or "Randomizer: "
  if not key then return end
  local it = DB.items[key]
  if not it then log("RANDO-ERROR unknown item", key); return end
  history("received " .. it.name)
  if it.category == "coordinates" then
    S.access[it.planet] = true
    changed()
    if SEED.travel_lock then
      say(prefix .. it.name .. " - you can fly to " .. planet_name(it.planet) .. " now", { type = "center", duration = 6 })
    else
      say(prefix .. it.name .. " - mission rewards on " .. planet_name(it.planet) .. " are yours now")
    end
    pay_banked(it.planet)
    return
  end
  if it.category == "weapon" or it.category == "gadget" or it.category == "pickup" then
    S.inventory[key] = true
    if it.category == "weapon" then S.weapons[key:sub(8)] = true end
    changed()
    local real = RANDO_REAL and RANDO_REAL.request(key)
    if real == "queued" then
      if not quiet then say(prefix .. it.name .. " - adding it to your inventory") end
    elseif real == "done" then
      say(prefix .. it.name .. " (already in your inventory)")
    elseif real == "failed" then
      say(prefix .. it.name .. " (the game did not add it - you probably have it already)")
    else
      say(prefix .. it.name .. " (real items are off - tracked only)")
    end
    return
  end
  if it.category == "armor" then
    -- 5.0: through the game's own armor code (rando_give.dll v5, 09_rando_real.lua)
    S.inventory[key] = true
    changed()
    local real = RANDO_REAL and RANDO_REAL.request(key)
    if real == "queued" then
      if not quiet then say(prefix .. it.name .. " - adding it to your armor") end
    elseif real == "done" then
      say(prefix .. it.name .. " (you have it)")
    elseif real == "failed" then
      say(prefix .. it.name .. " (the game did not add it)")
    else
      say(prefix .. it.name .. " (real items are off - tracked only)")
    end
    return
  end
  S.tracked[key] = true
  changed()
  say(prefix .. it.name)
end
R.grant = grant

-- ---------------------------------------------------------------------------------------
-- locations
-- ---------------------------------------------------------------------------------------
local function loc_item(lid) return SEED.locations[lid] and SEED.locations[lid].item end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
function R.bolts_collected()
  local n = 0
  for lid in pairs(S.collected) do if DB.locations[lid] and DB.locations[lid].kind == "goldbolt" then n = n + 1 end end
  return n
end
local function pay(lid)
  if S.paid[lid] then return false end
  S.paid[lid] = true
  S.banked[lid] = nil
  local loc = DB.locations[lid]
  local item = loc_item(lid)
  local prefix
  if loc.kind == "goldbolt" then prefix = string.format("Gold Bolt %d/%d: ", R.bolts_collected(), #(SEED.gold_bolts or {})) end
  if loc.kind == "armor_source" then
    local piece = loc.armor and DB.items[loc.armor]
    prefix = "Armor pod" .. (piece and (" (" .. piece.name .. ")") or "") .. ": "
  end
  local fk, amount = GEN.parse_filler(item)
  if item and DB.items[item] then grant(item, false, prefix)
  elseif fk then
    -- 5.0 filler: Bolts or Raritanium, given as currency items with a count
    local cur = DB.filler and DB.filler[fk] and DB.filler[fk].item
    history(string.format("received %d %s (%s)", amount, fk, lid))
    if cur and RANDO_REAL and RANDO_REAL.give_currency and RANDO_REAL.give_currency(cur, amount, lid) then
      say((prefix or "Randomizer: ") .. string.format("%d %s", amount, DB.items[cur].name), { type = "corner", duration = 3 })
    else
      say((prefix or "Randomizer: ") .. string.format("%d %s (real items are off - tracked only)", amount, fk), { type = "corner", duration = 3 })
    end
    changed()
  else
    if item then log("RANDO-ERROR", lid, "holds an item this kit does not know:", tostring(item)) end
    say((prefix or "Randomizer: ") .. "no item at " .. (loc.name or lid), { type = "corner", duration = 3 })
    changed()
  end
  return true
end
function pay_banked(pid)
  local list = {}
  for lid in pairs(S.banked) do if DB.locations[lid] and DB.locations[lid].planet == pid then list[#list + 1] = lid end end
  table.sort(list)
  if #list > 0 then history(#list .. " banked reward(s) of " .. pid .. " paid") end
  for _, lid in ipairs(list) do pay(lid) end
end

-- collect a location once; pays now or banks it until the planet's Coordinates arrive
function R.collect(lid, why)
  if not SEED.locations[lid] or S.collected[lid] then return false end
  local loc = DB.locations[lid]
  S.collected[lid] = true
  changed()
  history("location " .. lid .. " (" .. (why or loc.trigger) .. ")")
  -- with levels (travel_lock) you only reach a locked planet when the game takes you there, so
  -- its rewards pay; they wait only when the warp back was impossible or levels_runtime is off
  local waits = SEED.planet_locks and loc.planet and loc.kind ~= "goldbolt" and not S.access[loc.planet]
  if waits and SEED.travel_lock then waits = RANDO_TRAVEL ~= nil and RANDO_TRAVEL.banks(loc.planet) end
  if waits then
    S.banked[lid] = true
    local item = loc_item(lid)
    say(string.format("Banked: %s - find the Coordinates for %s to receive it",
                      item and item_name(item) or "a reward", planet_name(loc.planet)), { type = "pickup", duration = 5 })
    return true
  end
  pay(lid)
  return true
end

-- locations of one kind on one planet, in order
local function planet_locations(pid, trigger)
  local out = {}
  for lid in pairs(SEED.locations) do
    local loc = DB.locations[lid]
    if loc.planet == pid and (not trigger or loc.trigger == trigger) then out[#out + 1] = lid end
  end
  table.sort(out)
  return out
end

local function story_index(pid)
  for _, p in ipairs(DB.planets) do if p.id == pid then return p.story_index end end
  return nil
end

-- bound mission names (05_rando_bindings.lua): a side location with a binding waits for it
local function bound_set()
  local b = {}
  for _, lid in pairs(BIND.missions) do b[lid] = true end
  return b
end

-- a planet's story progressed: count its distinct story missions, then the fallbacks
function R.on_story_mission(pid, mission)
  S.story_missions[pid] = S.story_missions[pid] or {}
  local done = S.story_missions[pid]
  if done[mission] then return end
  done[mission] = true
  local n = 0
  for _ in pairs(done) do n = n + 1 end
  changed()
  if not S.planets_detected[pid] then
    S.planets_detected[pid] = true
    S.planets_done = S.planets_done + 1
  end
  for _, lid in ipairs(planet_locations(pid, "story_mission")) do
    if (DB.locations[lid].count or 1) <= n then R.collect(lid, "story mission " .. mission) end
  end
  -- side activities without a bound mission name are paid with their planet
  local bound = bound_set()
  for _, lid in ipairs(planet_locations(pid)) do
    if DB.locations[lid].fallback == "with_planet" and not bound[lid] then R.collect(lid, "paid with the planet") end
  end
  -- second story missions of earlier planets: paid once the story has moved on (not in a hub
  -- seed: there the order is yours, and a destination pays its own when it is finished)
  local idx = story_index(pid) or 0
  if SEED.hub then idx = 0 end
  for _, lid in ipairs(GEN.sorted_keys(SEED.locations)) do
    local loc = DB.locations[lid]
    if loc.fallback == "next_planet" and loc.planet and (story_index(loc.planet) or 99) < idx then
      R.collect(lid, "the story moved on to " .. pid)
    end
  end
end

-- missions: MissionStateChangedEvent (3 CompleteCleaning, 4 CompleteFinished). The planet is
-- found from the mission name's prefix (05_rando_bindings.lua).
local NOT_PROGRESS = { "_DEFAULT", "RYNO_PLANS", "ARENA_CHALLENGE", "MIS_HAX", "MIS_POCKET", "MIS_CLANK" }
function R.mission_planet(name)
  if type(name) ~= "string" then return nil end
  local up = name:upper()
  for _, bad in ipairs(NOT_PROGRESS) do if up:find(bad, 1, true) then return nil end end
  local best, best_len = nil, 0
  for prefix, pid in pairs(BIND.mission_prefixes) do
    local p = prefix:upper()
    if up:sub(1, #p) == p and #p > best_len then best, best_len = pid, #p end
  end
  return best
end
-- the last story mission of the game (registry: MIS_MEGA_FINALE, a name from your dag; not yet
-- seen in a rivet.log, so any Megalopolis mission whose name has FINAL in it counts too)
R.FINALE_MISSIONS = { MIS_MEGA_FINALE = true }
function R.is_finale(name)
  if R.FINALE_MISSIONS[name] then return true end
  local up = name:upper()
  return up:sub(1, 8) == "MIS_MEGA" and up:find("FINAL", 1, true) ~= nil
end
function R.on_finale(name)
  if S.campaign_complete then return end
  S.campaign_complete = true
  changed()
  history("campaign complete (" .. tostring(name) .. ")")
  local missing = 0
  for lid in pairs(SEED.locations) do if not S.collected[lid] then missing = missing + 1 end end
  say(string.format("Randomizer: campaign complete! Gold Bolts %d/%d - seed %s", R.bolts_collected(), #(SEED.gold_bolts or {}), SEED.seed),
      { type = "planet", sub = string.format("%d reward location(s) left to find", missing), duration = 10 })
end
function R.on_mission_state(name, state)
  if type(name) ~= "string" then return false end
  if state ~= 3 and state ~= 4 then return false end
  if R.is_finale(name) then R.on_finale(name) end
  local lid = BIND.missions[name]
  if lid then return R.collect(lid, "mission " .. name) end
  if RANDO_HUB and RANDO_HUB.on_mission_state then
    local okh, eh = pcall(RANDO_HUB.on_mission_state, name, state)
    if not okh then log("RANDO-ERROR hub mission", tostring(eh)) end
  end
  local pid = R.mission_planet(name)
  if not pid then return false end
  R.on_story_mission(pid, name)
  return true
end

-- Gold Bolts: GainGoldBoltEvent.BoltName "<Planet> <n>" (observed: "Sargasso 2"). Matched to
-- one of that planet's Gold Bolt locations, preferring one whose requirements are met.
local function holds(req)
  if req:match("^ability:") then return false end
  if S.inventory[req] then return true end
  local gid = req
  return S.gadgets_seen[gid] == true
end
function R.bolt_planet(name)
  local base = name:gsub("%s*%d+%s*$", ""):lower()
  if DB.bolt_prefixes[base] then return DB.bolt_prefixes[base] end
  for prefix, pid in pairs(DB.bolt_prefixes) do
    if base:sub(1, #prefix) == prefix then return pid end
  end
  return nil
end
function R.pick_bolt_location(pid)
  local fallback
  local list = {}
  if pid then list = planet_locations(pid, "gold_bolt")
  else
    for _, lid in ipairs(SEED.gold_bolts or {}) do list[#list + 1] = lid end
  end
  for _, lid in ipairs(list) do
    if not S.collected[lid] then
      fallback = fallback or lid
      local ok = true
      for _, r in ipairs(DB.locations[lid].requires or {}) do if not holds(r) then ok = false; break end end
      if ok then return lid, "requirements met" end
    end
  end
  if fallback then return fallback, "first remaining" end
  return nil
end
function R.on_gold_bolt(name)
  if type(name) ~= "string" or name == "" then return nil end
  if S.bolts_seen[name] then log("RANDO-BOLT", name, "already counted"); return nil end
  local lid, how = BIND.bolts[name], "binding"
  if not lid then
    local pid = R.bolt_planet(name)
    if pid then lid, how = R.pick_bolt_location(pid) end
    -- a name the data does not know: the planet you are on
    if not lid and S.current_planet and S.current_planet ~= pid then
      lid, how = R.pick_bolt_location(S.current_planet)
      if lid then how = "current planet " .. S.current_planet .. ", " .. how end
    end
    -- the game has 25 Gold Bolts and so does the seed: if the data's split per planet is off,
    -- any Gold Bolt still unclaimed pays, so every Gold Bolt you find gives one item
    if not lid then
      lid, how = R.pick_bolt_location(nil)
      if lid then how = "any remaining Gold Bolt, " .. how end
    end
  end
  S.bolts_seen[name] = lid or "none"
  changed()
  if lid then
    log("RANDO-BOLT", name, "->", lid, "(" .. tostring(how) .. ")")
    R.collect(lid, "Gold Bolt " .. name)
  else
    -- more Gold Bolts on this planet than the game data lists (or an unknown planet name):
    -- reported, never paid twice
    log("RANDO-BOLT", name, "-> all", #(SEED.gold_bolts or {}), "Gold Bolt rewards are already given")
    say("Gold Bolt " .. name .. ": all 25 Gold Bolt rewards are already yours", { type = "corner", duration = 5 })
  end
  return lid
end

-- armor: 13_rando_armor.lua (armor sources, and the vanity_owns polling fallback)

-- collectibles bound in 05_rando_bindings.lua: { spybot = { class = "<event class>" }, ... }
function R.on_collectible(kind)
  S.collectibles[kind] = (S.collectibles[kind] or 0) + 1
  changed()
  local n = S.collectibles[kind]
  history(kind .. " #" .. n)
  R.collect(kind .. ":" .. n, kind .. " found")
end

-- ---------------------------------------------------------------------------------------
-- new game: the prologue's first cinematic objective starts. In rounds 14 and 15 the
-- ObjectiveStateChangedEvent MIS_INTRO / OBJ_INTRO_PARADE_START_CINE / state 1 came only when a
-- new game was started (loading a save only ever reported OBJ_INTRO_PROLOGUE state 1, the boot
-- default). The seed's progress starts over: the new save has none of the old run's items.
-- ---------------------------------------------------------------------------------------
R.NEW_GAME_MISSION, R.NEW_GAME_OBJECTIVE = "MIS_INTRO", "OBJ_INTRO_PARADE_START_CINE"
R.NEW_GAME_DEBOUNCE = 30
local last_new_game = -1000
function R.reset_for_new_game(why)
  local old = S
  -- 10.0: the hub's learned mission starts describe the game, not the run: they are kept
  -- v0.54: and planet shuffle on/off is your choice, not the run's
  local keep = { real_mode = old.real_mode, weapon_types = old.weapon_types, hub_learned = old.hub_learned,
                 planet_shuffle_off = old.planet_shuffle_off }
  S = fresh_state((old.run or 1) + 1); R.state = S
  for k, v in pairs(keep) do S[k] = v end
  S.previous_run = { run = old.run or 1, collected = count(old.collected), bolts = 0, complete = old.campaign_complete or nil }
  for lid in pairs(old.collected) do if DB.locations[lid] and DB.locations[lid].kind == "goldbolt" then S.previous_run.bolts = S.previous_run.bolts + 1 end end
  if RANDO_REAL and RANDO_REAL.new_game then RANDO_REAL.new_game() end
  if RANDO_ARMOR and RANDO_ARMOR.new_game then pcall(RANDO_ARMOR.new_game) end
  if RANDO_CAMPAIGN_RT and RANDO_CAMPAIGN_RT.new_game then pcall(RANDO_CAMPAIGN_RT.new_game) end
  if RANDO_TRAVEL and RANDO_TRAVEL.new_game then pcall(RANDO_TRAVEL.new_game) end
  if RANDO_HUB and RANDO_HUB.new_game then pcall(RANDO_HUB.new_game) end
  history("NEW GAME: run " .. S.run .. " of seed " .. SEED.seed .. " (" .. why .. "); run " .. S.previous_run.run ..
          " had " .. S.previous_run.collected .. " location(s)")
  R.begin()
  changed()
  say("Randomizer: new game - seed " .. SEED.seed .. " starts over (run " .. S.run .. ")", { type = "planet", sub = R.start_text(), duration = 8 })
end
function R.on_objective(mission, objective, state)
  if RANDO_HUB and RANDO_HUB.on_objective then pcall(RANDO_HUB.on_objective, mission, objective, state) end
  if not R.config.new_game_reset then return false end
  -- 10.0: a prologue the hub itself restarts begins with the same objective; it is no New Game
  if RANDO_HUB and RANDO_HUB.intro_restarting and RANDO_HUB.intro_restarting() then return false end
  if mission ~= R.NEW_GAME_MISSION or objective ~= R.NEW_GAME_OBJECTIVE or state ~= 1 then return false end
  local now = (rivet.time and rivet.time()) or 0
  if now - last_new_game < R.NEW_GAME_DEBOUNCE then return false end
  last_new_game = now
  if not (R.restored or R.unsaved) then
    -- the companion has not answered yet: whatever it restores belongs to an older run
    R.new_game_pending = true
    log("RANDO-NEWGAME new game seen before the companion's restore - the restored run will start over")
    return true
  end
  R.reset_for_new_game("the prologue started")
  return true
end

-- planets: PlanetChangedEvent.NewPlanetName (observed: Malinon, NefCity, Zurkon, Sargasso, ...)
local PLANET_BY_EVENT = {}
for _, p in ipairs(DB.planets) do for _, n in ipairs(p.event_names) do PLANET_BY_EVENT[n] = p.id end end
for n, pid in pairs(BIND.planets) do PLANET_BY_EVENT[n] = pid end
function R.process_planet(name, old)
  local pid = PLANET_BY_EVENT[name]
  if not pid then log("RANDO-PLANET", name, "(not in the model)"); return nil end
  if not S.visited[pid] then S.visited[pid] = true; changed() end
  local from = S.current_planet or (old and PLANET_BY_EVENT[old])
  S.current_planet = pid
  local banked = 0
  for lid in pairs(S.banked) do if DB.locations[lid].planet == pid then banked = banked + 1 end end
  log("RANDO-PLANET", name, pid, S.access[pid] and "rewards unlocked" or "rewards locked")
  -- 8.2 test travel: a test trip's landing is only reported (nothing sends you back)
  if RANDO_TEST_TRAVEL and RANDO_TEST_TRAVEL.on_arrival then
    local okt, claimed = pcall(RANDO_TEST_TRAVEL.on_arrival, pid, from)
    if not okt then log("RANDO-ERROR test travel arrival", tostring(claimed)) end
    if okt and claimed then return pid end
  end
  -- 10.0 hub seeds: the hub, destinations, the menu and the game's own travel (15_rando_hub.lua)
  if SEED.hub and RANDO_HUB and RANDO_HUB.on_arrival then
    local okh, handled = pcall(RANDO_HUB.on_arrival, pid, from)
    if not okh then log("RANDO-ERROR hub arrival", tostring(handled)) end
    if okh and handled then return pid end
  end
  -- 7.0 levels: a locked planet chosen in the planet menu sends you back (14_rando_travel.lua)
  if SEED.travel_lock and RANDO_TRAVEL and RANDO_TRAVEL.active() then
    RANDO_TRAVEL.on_arrival(pid, from)
    return pid
  end
  if SEED.planet_locks and not S.access[pid] then
    say(string.format("%s: mission rewards here wait for its Coordinates (Gold Bolts pay at once)%s", planet_name(pid),
                      banked > 0 and string.format(" (%d waiting)", banked) or ""), { type = "corner", duration = 5 })
  end
  return pid
end

function R.status_text()
  if not SEED then return "Randomizer: generating the seed..." end
  local done_loc, banked, total = count(S.paid), count(S.banked), count(SEED.locations)
  local real = RANDO_REAL and RANDO_REAL.status_text and RANDO_REAL.status_text()
  local camp = RANDO_CAMPAIGN_RT and RANDO_CAMPAIGN_RT.status_text and RANDO_CAMPAIGN_RT.status_text()
  if camp then real = real and (real .. " | " .. camp) or camp end
  local coords = SEED.planet_locks and string.format(" | Coordinates %d/%d", count(S.access), #DB.planets) or ""
  if SEED.travel_lock and RANDO_TRAVEL then coords = " | " .. RANDO_TRAVEL.status_text() end
  local hub = RANDO_HUB and RANDO_HUB.status_text and RANDO_HUB.status_text()
  if hub then coords = coords .. " | " .. hub end
  local armor = RANDO_ARMOR and RANDO_ARMOR.status_text and RANDO_ARMOR.status_text()
  if armor then real = real and (real .. " | " .. armor) or armor end
  local shop = RANDO_SHOP and RANDO_SHOP.status_text and RANDO_SHOP.status_text()
  if shop then real = real and (real .. " | " .. shop) or shop end
  local test = RANDO_TEST_TRAVEL and RANDO_TEST_TRAVEL.status_text and RANDO_TEST_TRAVEL.status_text()
  if test then real = real and (real .. " | " .. test) or test end
  return string.format("%sGold Bolts %d/%d | rewards %d/%d%s%s | planets %d%s%s%s",
                       S.test_used and "[TEST] " or "", R.bolts_collected(), #(SEED.gold_bolts or {}), done_loc, total,
                       banked > 0 and string.format(" (+%d waiting for Coordinates)", banked) or "", coords, S.planets_done,
                       S.campaign_complete and " | CAMPAIGN COMPLETE" or "",
                       real and (" | " .. real) or "", R.restored and "" or " | not saved yet")
end

-- ---------------------------------------------------------------------------------------
-- seed generation (sliced across frames) and the start of a seed
-- ---------------------------------------------------------------------------------------
R.GEN_BUDGET = 0.002                  -- seconds of generation work per frame
local gen_job
local event_buffer = {}               -- events that arrive before the seed is ready
local seed_source = { text = nil, why = nil }

local function random_seed_text()
  local words = { "lombax", "rivet", "clank", "kit", "zurkie", "nefarious", "ryno", "glitch", "rift", "bolt",
                  "savali", "blizar", "torren", "ardolis", "viceron", "sargasso", "trudi", "speetle", "qwark", "pocket" }
  local x = math.floor(((os and os.clock and os.clock()) or 0) * 1e6) ~ math.floor(((rivet.time and rivet.time()) or 0) * 1e6)
  local r = GEN.rng(GEN.fnv1a(tostring(x) .. R.boot))
  return r.pick(words) .. "-" .. r.pick(words) .. "-" .. r.pick(words) .. "-" .. r.int(100, 999)
end

function R.start_generation(text, why)
  if gen_job or SEED then return false end
  if R.arsenal_pending then
    R.deferred = R.deferred or { text = text, why = why }
    log("RANDO-SEED seed", text, "waits for the companion's ARSENAL_RESTORED check (restored_weapons = \"auto\")")
    return true
  end
  seed_source.text, seed_source.why = text, why
  local preset = SETTINGS.preset
  gen_job = coroutine.create(function()
    local last = os.clock()
    local function yield()
      if os.clock() - last >= R.GEN_BUDGET then coroutine.yield(); last = os.clock() end
    end
    return GEN.generate(text, GEN_OPTIONS, preset, yield)
  end)
  log("RANDO-SEED generating seed", text, "(" .. why .. ")")
  return true
end

local function seed_ready(seed)
  SEED = seed
  RANDO_SEED = seed
  S = fresh_state()
  R.state = S
  for _, w in ipairs(seed.warnings or {}) do log("RANDO-SETTINGS", w) end
  log("RANDO-SEED ready", seed.seed, seed.fingerprint, "preset " .. seed.preset, "attempt " .. seed.attempt)
  if seed.campaign and seed.campaign.order then
    log("RANDO-SEED campaign " .. seed.campaign.mode .. ": " .. table.concat(seed.campaign.order, " > "))
  end
  log("RANDO-SEED share code", seed.share_code)
  -- events that came in while generating
  local buf = event_buffer; event_buffer = nil
  R.replay_events = buf
end

-- the companion restored a save, or there is none: the starting inventory is handed out once
local function begin()
  if S.started then return end
  S.started = true
  for _, key in ipairs(SEED.start.items) do
    local it = DB.items[key]
    if it and it.category == "coordinates" then S.access[it.planet] = true
    else grant(key, true) end
  end
  -- 7.0 start currency
  for _, c in ipairs({ { "bolts", SEED.start.bolts }, { "raritanium", SEED.start.raritanium } }) do
    local amount = c[2] or 0
    local cur = DB.filler and DB.filler[c[1]] and DB.filler[c[1]].item
    if amount > 0 and cur then
      local ok = RANDO_REAL and RANDO_REAL.give_currency and RANDO_REAL.give_currency(cur, amount, "start")
      history(string.format("start: %d %s%s", amount, c[1], ok and "" or " (real items are off - tracked only)"))
    end
  end
  history("seed started: " .. SEED.seed .. " (" .. SEED.fingerprint .. "), run " .. S.run)
  say("Randomizer start: " .. R.start_text(), { type = "corner", duration = 8 })
end
R.begin = begin
function R.start_text()
  local names = {}
  for _, key in ipairs(SEED.start.items) do
    if not (SEED.travel_lock and key:match("^access:")) then names[#names + 1] = item_name(key) end
  end
  if (SEED.start.bolts or 0) > 0 then names[#names + 1] = SEED.start.bolts .. " Bolts" end
  if (SEED.start.raritanium or 0) > 0 then names[#names + 1] = SEED.start.raritanium .. " Raritanium" end
  return table.concat(names, ", ")
end

-- ---------------------------------------------------------------------------------------
-- saving through the companion (rivet_hook's bridge, script.exec answers <= 4095 characters)
-- ---------------------------------------------------------------------------------------
local ser = GEN.serialize
R.ser = ser
local function persisted()
  local copy = {}
  for k, v in pairs(S) do copy[k] = v end
  local h = S.history
  if #h > 60 then
    copy.history = {}
    for i = #h - 59, #h do copy.history[#copy.history + 1] = h[i] end
  end
  return copy
end
local CHUNK = 3000
local export_cache = { version = -1, text = "" }
local function export_text()
  if export_cache.version ~= R.version then
    export_cache.text = "return " .. ser(persisted())
    export_cache.version = R.version
  end
  return export_cache.text
end
-- fingerprint|boot|version|restored|length|chunks|ready|seed text
function rando_bridge_status()
  if not SEED then
    return table.concat({ "-", R.boot, "0", "0", "0", "1", gen_job and "generating" or "waiting", seed_source.text or "" }, "|")
  end
  local text = export_text()
  return table.concat({ SEED.fingerprint, R.boot, tostring(R.version), R.restored and "1" or "0",
                        tostring(#text), tostring(math.max(1, math.ceil(#text / CHUNK))), "ready", SEED.seed }, "|")
end
function rando_export_chunk(i)
  local text = export_text()
  return text:sub((i - 1) * CHUNK + 1, i * CHUNK)
end
-- 8.5: the merge of this session's state into the restored one (the companion can connect a
-- minute late: round 20). Sets are united; a delivery keeps its furthest status (an item this
-- session confirmed is never sent again because the save still had it queued); currency this
-- session paid but has not given yet is kept (8.4 lost it with the replaced queue); armor
-- sources and finds, gadgets and the shop's one-time gift are kept.
R.MERGE_SETS = { "collected", "paid", "banked", "bolts_seen", "story_missions", "planets_detected", "inventory",
                 "weapons", "access", "tracked", "armor_found", "armor_sources", "armor_sets_done", "gadgets_seen",
                 "visited", "shop_given", "gadgets" }
R.STATUS_RANK = { failed = 1, queued = 2, sent = 3, owned = 4, confirmed = 5 }
function R.merge_live(live, S)
  local restored_paid = {}
  for lid in pairs(S.paid or {}) do restored_paid[lid] = true end
  for _, k in ipairs(R.MERGE_SETS) do
    S[k] = S[k] or {}
    for key, v in pairs(live[k] or {}) do if S[k][key] == nil then S[k][key] = v end end
  end
  S.real = S.real or {}
  for item, r in pairs(live.real or {}) do
    local old = S.real[item]
    if old == nil or (R.STATUS_RANK[r.status] or 0) > (R.STATUS_RANK[old.status] or 0) then S.real[item] = r end
  end
  -- currency: an entry is the payment of one location (why = its id); entries of locations the
  -- restored save had not paid yet are this session's
  S.currency_queue = S.currency_queue or {}
  local queued = {}
  for _, c in ipairs(S.currency_queue) do queued[tostring(c.why)] = true end
  local added = 0
  for _, c in ipairs(live.currency_queue or {}) do
    local why = tostring(c.why)
    if not queued[why] and not restored_paid[why] and why ~= "start" then
      S.currency_queue[#S.currency_queue + 1] = c; added = added + 1
    end
  end
  if added > 0 then log("RANDO-SAVE kept", added, "currency payment(s) from before the restore") end
  -- the armor baseline is measured once: a save without one takes this session's
  if S.armor_baseline == nil and type(live.armor_baseline) == "table" then S.armor_baseline = live.armor_baseline end
  if type(live.weapon_types) == "table" then
    S.weapon_types = S.weapon_types or {}
    for t, it in pairs(live.weapon_types) do if S.weapon_types[t] == nil then S.weapon_types[t] = it end end
  end
  -- 10.0: the hub's objective record and learned starts of this session
  local lh, sh = live.hub, S.hub
  if type(lh) == "table" and type(sh) == "table" and type(lh.obj) == "table" then
    sh.obj = sh.obj or {}
    for m, o in pairs(lh.obj) do sh.obj[m] = o end
  end
  if RANDO_HUB and RANDO_HUB.on_restore then pcall(RANDO_HUB.on_restore, live) end
end

function rando_import_state(tbl)
  if not SEED then return false end
  if type(tbl) ~= "table" or tbl.fingerprint ~= SEED.fingerprint then
    log("RANDO-SAVE refusing state for another seed"); return false
  end
  local live = S
  S = fill_defaults(tbl); R.state = S
  -- 8.0: where you are is this session's knowledge, not the save's
  if live and live.current_planet then S.current_planet = live.current_planet end
  -- what happened in this session before the restore (Gold Bolts, missions, the items they
  -- gave) is kept, so nothing collected while the companion was still connecting is lost
  if live and live.started then R.merge_live(live, S) end
  -- v0.54: planet shuffle on/off (the 0 key) as this session or the save has it
  if RANDO_HUB and RANDO_HUB.after_restore then pcall(RANDO_HUB.after_restore) end
  R.restored = true
  if R.new_game_pending then
    R.new_game_pending = nil
    R.reset_for_new_game("the prologue started before the restore")
  else
    if RANDO_REAL then RANDO_REAL.sync() end
    begin()
  end
  changed()
  log("RANDO-SAVE restored:", R.status_text())
  say("Randomizer progress restored: " .. R.status_text(), { type = "corner", duration = 6 })
  return true
end
function rando_mark_restored()
  if not SEED then return "not ready" end
  R.restored = true
  R.new_game_pending = nil                -- nothing to start over: this is the first run
  begin()
  if RANDO_REAL then RANDO_REAL.sync() end
  log("RANDO-SAVE no saved progress for this seed, starting fresh")
  return "ok"
end
-- the companion's ARSENAL_RESTORED check (restored_weapons = "auto")
function R.resolve_arsenal(found, why)
  if not R.arsenal_pending then return false end
  R.arsenal_pending = false
  GEN_OPTIONS.include_arsenal_restored = found == true
  R.arsenal = { found = found == true, why = why }
  log("RANDO-SEED ARSENAL_RESTORED " .. (found and "is installed: its 9 weapons are in the pool" or "is not installed: its weapons stay out") ..
      " (" .. tostring(why) .. ")")
  local d = R.deferred; R.deferred = nil
  if d then R.start_generation(d.text, d.why) end
  return true
end
function rando_set_arsenal(found)
  if not R.arsenal_pending then return R.arsenal and tostring(R.arsenal.found) or "not asked" end
  R.resolve_arsenal(found == true, "the companion checked rivet.toml and the game's toc")
  return "ok"
end
function rando_arsenal_mode() return R.arsenal_pending and "auto" or "fixed" end
-- 8.4: the game itself answers when it can. ARSENAL_RESTORED adds Mr. Zurkon's item config
-- (DB.arsenal_marker, an asset the game does not have); once it is loaded, the mod is installed.
-- Round 20: rivet_hook loaded mods/ARSENAL_RESTORED.stage (wpn_mr_zurkon_item.config resolved),
-- but the companion answered after the 60 s wait, so the seed was made without the mod's weapons.
-- Only "installed" is concluded here; "not installed" still needs the companion (or, for a fixed
-- seed, the wait). With seed = "random" there is no wait at all: the seed comes from the
-- companion, which answers the check first.
R.ARSENAL_EVERY = 60
function R.arsenal_in_game()
  if type(rivet.config) ~= "function" or not DB.arsenal_marker then return false end
  local ok, c = pcall(rivet.config, DB.arsenal_marker)
  return ok and type(c) == "table"
end
-- the companion supplies the seed when 04_rando_settings.lua says seed = "random":
-- rando_use_seed("") asks for a new random seed, rando_use_seed(text) continues one
function rando_use_seed(text)
  if SEED or gen_job then return SEED and SEED.seed or "generating" end
  if R.deferred then return R.deferred.text end
  if type(text) ~= "string" or text == "" then text = random_seed_text() end
  R.start_generation(text, "random seed from the companion")
  return text
end
function rando_seed_mode()
  local s = SETTINGS.seed
  if s == nil or s == "" or s == "random" then return "random" end
  return "fixed"
end
-- spoiler log for the companion (written to its spoilers folder)
local spoiler_cache
function rando_spoiler_status()
  if not SEED then return "0|0" end
  spoiler_cache = spoiler_cache or GEN.spoiler(SEED)
  return tostring(#spoiler_cache) .. "|" .. tostring(math.ceil(#spoiler_cache / CHUNK))
end
function rando_spoiler_chunk(i)
  spoiler_cache = spoiler_cache or GEN.spoiler(SEED)
  return spoiler_cache:sub((i - 1) * CHUNK + 1, i * CHUNK)
end

-- ---------------------------------------------------------------------------------------
-- engine wiring
-- ---------------------------------------------------------------------------------------
local NOISE = { Frame = true, SenderHandle = true, EventLocatorHash = true, RequireActivated = true,
                SourceAnimDriverHandle = true, SourceAnimDriverNameHash = true, TrackedNameHash = true }
local seen_lines, class_lines = {}, {}
local function fmt(v)
  if math.type(v) == "float" and math.abs(v) >= 2^53 then return string.format("%.0f", v) end
  return tostring(v)
end
local function discover(class, ev)
  if not R.config.discovery then return end
  local parts = {}
  for k, v in pairs(ev.fields or {}) do
    if type(v) ~= "table" and not NOISE[k] then parts[#parts + 1] = k .. "=" .. fmt(v) end
  end
  table.sort(parts)
  local line = class .. " " .. table.concat(parts, " ")
  if seen_lines[line] then return end
  local n = (class_lines[class] or 0) + 1
  if n > R.config.discovery_cap then return end
  seen_lines[line] = true; class_lines[class] = n
  log("RANDO-DISCOVER", class, table.concat(parts, " "))
end

local pending = {}
local subscribed, total = 0, 0
local function try_subscribe(sub)
  local ok, err = pcall(rivet.on_event, sub.class, function(ev)
    local ok1, e1 = pcall(discover, sub.class, ev)
    if not ok1 then log("RANDO-ERROR discover", sub.class, tostring(e1)) end
    if not sub.fn then return end
    if not SEED or not S then
      -- keep it for after generation (bounded)
      if event_buffer and #event_buffer < 500 then event_buffer[#event_buffer + 1] = { fn = sub.fn, ev = ev, class = sub.class } end
      return
    end
    local ok2, e2 = pcall(sub.fn, ev)
    if not ok2 then log("RANDO-ERROR", sub.class, tostring(e2)) end
  end)
  if ok then
    subscribed = subscribed + 1
    if sub.failed then log("subscribed", sub.class, "after retrying") end
    return true
  end
  if not sub.failed then log("cannot subscribe yet", sub.class, err) end
  sub.failed = true
  if tostring(err):find("there is no event class", 1, true) then sub.dead = true end
  return false
end
local function on(class, fn)
  total = total + 1
  local sub = { class = class, fn = fn }
  if not try_subscribe(sub) and not sub.dead then pending[#pending + 1] = sub end
end
function R.retry_subscriptions()
  if #pending == 0 then return 0 end
  local still = {}
  for _, sub in ipairs(pending) do
    if not try_subscribe(sub) and not sub.dead then still[#still + 1] = sub end
  end
  pending = still
  if #pending == 0 then log(string.format("RANDO-STATUS events subscribed %d/%d", subscribed, total)) end
  return #pending
end

on("MissionStateChangedEvent", function(ev)
  local f = ev.fields or {}
  R.on_mission_state(f.MissionName, tonumber(f.MissionState))
end)
on("MissionCompleteEvent", function(ev) R.on_mission_state(ev.fields and ev.fields.MissionName, 4) end)
on("GadgetItemAddedEvent", function(ev)
  local h = ev.fields and ev.fields.ConfigTypeHash
  h = h and (math.tointeger(h) or h)
  for key, it in pairs(DB.items) do
    if it.type_id and it.type_id == h and not S.gadgets_seen[key] then
      S.gadgets_seen[key] = true; changed(); log("RANDO-GADGET", key)
    end
  end
end)
on("GainGoldBoltEvent", function(ev) R.on_gold_bolt(ev.fields and ev.fields.BoltName) end)
on("ObjectiveStateChangedEvent", function(ev)
  local f = ev.fields or {}
  R.on_objective(f.MissionName, f.ObjectiveName, tonumber(f.ObjectiveState))
end)
local pending_planet, pending_old
on("PlanetChangedEvent", function(ev)
  local name = ev.fields and ev.fields.NewPlanetName
  if name and name ~= "" then pending_planet = name; pending_old = ev.fields.OldPlanetName end
end)
-- collectibles bound by event class (05_rando_bindings.lua)
for _, kind in ipairs(GEN.sorted_keys(BIND.collectible_events)) do
  local b = BIND.collectible_events[kind]
  if type(b) == "table" and type(b.class) == "string" then
    on(b.class, function(ev)
      if b.field and b.value ~= nil and (ev.fields or {})[b.field] ~= b.value then return end
      R.on_collectible(kind)
    end)
  end
end
-- 10.0: checkpoints are named (14_rando_travel.lua: the engine's CRC-32 of every listed name)
on("CheckpointTriggeredEvent", function(ev)
  local f = ev.fields or {}
  if RANDO_TRAVEL and RANDO_TRAVEL.on_checkpoint then
    RANDO_TRAVEL.on_checkpoint(math.tointeger(tonumber(f.CheckpointHash)) or tonumber(f.CheckpointHash), f.Loaded)
  end
end)
-- discovery only
for _, c in ipairs({ "MissionStartedEvent", "MissionObjectiveCompleteEvent",
                     "MissionDeactivatedEvent", "StartMissionDevstatsEvent", "EndMissionDevstatsEvent",
                     "PurchaseWeaponEvent", "VendorPurchaseEvent", "WeaponAddedEvent",
                     "LevelLoadedEvent", "SaveDataAppliedEvent", "PlanetMenuAcceptEvent",
                     "GainBoltEvent", "GainRaritaniumEvent" }) do on(c) end

-- bind a key by name; every press is logged (RANDO-KEY), so a key the game never passes on shows
-- up as missing in rivet.log. Returns true when bound.
R.bound = R.bound or {}
function R.bind_key(name, fn, what)
  local vk, why = R.vk(name)
  if not vk then log("RANDO-ERROR key", tostring(name), tostring(why)); return false end
  if R.bound[vk] then log("RANDO-SETTINGS key", tostring(name), "is used twice:", R.bound[vk], "and", tostring(what)) end
  R.bound[vk] = what or name
  local okb, err = pcall(rivet.on_key, vk, function()
    log("RANDO-KEY", tostring(name), R.ctrl_down() and "with Ctrl" or "", tostring(what or ""))
    local ok, e = pcall(fn)
    if not ok then log("RANDO-ERROR key " .. tostring(name) .. ":", tostring(e)) end
  end)
  if not okb then log("RANDO-ERROR key", tostring(name), tostring(err)); return false end
  return true
end
-- a setting's key, and (legacy_f_keys) its old F key too
function R.bind_setting(setting, legacy, fn)
  R.bind_key(R.config[setting], fn, setting)
  if legacy and R.config.legacy_f_keys and R.config[setting] ~= legacy then R.bind_key(legacy, fn, setting .. " (old key)") end
end
local function on_key(name, fn)
  R.bind_key(name, function()
    if not (SEED and S) then say("Randomizer: the seed is still being prepared"); return end
    fn()
  end, name)
end
R.on_key = on_key
R.bind_setting("key_status", "F9", function()
  if not (SEED and S) then say("Randomizer: the seed is still being prepared"); return end
  if R.ctrl_down() and RANDO_TRAVEL and SEED.travel_lock then RANDO_TRAVEL.hatch(); return end
  say(R.status_text(), { type = "corner", duration = 6 })
end)
log("RANDO-KEYS", R.keys_numeric and "keyboard keys on" or "rivet.key() does not use Windows key codes: only its own key names work",
    string.format("status %s | hub %s | stay %s | story %s | planet shuffle %s | test travel %s %s%s", R.key("key_status"), R.key("key_hub"),
                  R.key("key_hub_return"), R.key("key_story"), R.key("key_shuffle"), R.key("key_test_travel"), R.key("key_test_point"),
                  R.config.legacy_f_keys and " | old F keys too" or ""))

-- start: a pre-generated seed (tools/rando.py writes 00_rando_seed.lua), the settings' seed, or
-- (seed = "random") one from the companion
R.WAIT_FOR_COMPANION = 600
R.WAIT_COMPANION_START = 3600
if type(RANDO_SEED) == "table" and RANDO_SEED.format == 10 then
  local pre = RANDO_SEED
  seed_ready(pre)
  log("RANDO-SEED using the pre-generated seed in 00_rando_seed.lua")
elseif rando_seed_mode() == "fixed" then
  R.start_generation(tostring(SETTINGS.seed), "04_rando_settings.lua")
end

-- 8.4 THE KIT CHECK: every script of this kit says its version (RANDO_FILES). On the first frame
-- (all scripts loaded) a missing script or one from another kit is reported in rivet.log and on
-- screen, so a scripts folder that mixes kits never plays silently half-updated.
R.KIT_FILES = { "01_rando_data", "02_rando_generator", "03_rando_campaign", "04_rando_settings", "05_rando_bindings",
                "06_rando_capabilities", "09_rando_real", "10_rando_runtime", "11_rando_campaign", "12_rando_shop",
                "13_rando_armor", "14_rando_travel", "15_rando_hub", "16_rando_testtravel" }
-- scripts of older kits that must not be in the folder any more (10.0: none; 15_rando_hub.lua is
-- part of the kit again, and an 8.x copy shows up as "other versions")
R.GONE_FILES = {}
function R.kit_check()
  local files = RANDO_FILES or {}
  local missing, other = {}, {}
  local gone = {}
  for f, why in pairs(R.GONE_FILES) do
    if files[f] ~= nil then gone[#gone + 1] = f .. ".lua (" .. why .. ")" end
  end
  table.sort(gone)
  if #gone > 0 then
    log("RANDO-ERROR RANDO-KIT delete from the scripts folder: " .. table.concat(gone, ", ") ..
        " - it was left by an older kit")
    say("Randomizer: delete " .. table.concat(gone, ", ") .. " from the scripts folder (left by an older kit) - see rivet.log",
        { type = "center", duration = 10 })
  end
  for _, f in ipairs(R.KIT_FILES) do
    local v = files[f]
    if f == "04_rando_settings" then
      if v ~= R.KIT_VERSION then
        log("RANDO-KIT 04_rando_settings.lua is from an older kit (" .. tostring(v or "before 8.4") ..
            "): options it does not list use their defaults (docs\\PLAYER_GUIDE.md)")
      end
    elseif v == nil then missing[#missing + 1] = f
    elseif v ~= R.KIT_VERSION then other[#other + 1] = f .. " " .. tostring(v) end
  end
  if #missing == 0 and #other == 0 then
    log("RANDO-KIT all " .. #R.KIT_FILES .. " scripts are " .. R.KIT_VERSION)
    return #gone == 0
  end
  log("RANDO-ERROR RANDO-KIT the scripts folder does not hold one kit:" ..
      (#missing > 0 and (" missing " .. table.concat(missing, ", ")) or "") ..
      (#other > 0 and (" | other versions: " .. table.concat(other, ", ")) or "") ..
      " - copy every file of the kit's scripts folder (INSTALL.txt)")
  say("Randomizer: the scripts folder mixes kits or misses files - see rivet.log (RANDO-KIT)", { type = "center", duration = 10 })
  return false
end

local announced = false
local frames = 0
local function frame(dt)
  frames = frames + 1
  if frames == 1 then pcall(R.kit_check) end
  if #pending > 0 and frames % 30 == 0 then R.retry_subscriptions() end
  if R.arsenal_pending and frames % R.ARSENAL_EVERY == 0 and R.arsenal_in_game() then
    R.resolve_arsenal(true, "the game has ARSENAL_RESTORED's Mr. Zurkon item config loaded")
  end
  if R.arsenal_pending and frames >= R.WAIT_COMPANION_START and rando_seed_mode() == "fixed" then
    R.resolve_arsenal(false, "the companion did not answer: treated as not installed")
  end
  -- generation
  if gen_job then
    local ok, seed, err = coroutine.resume(gen_job)
    if not ok then
      log("RANDO-ERROR generator:", tostring(seed)); gen_job = nil
      -- e.g. rivet_hook's frame budget hit inside a slice: start over (the result is the same)
      -- with smaller slices
      R.gen_restarts = (R.gen_restarts or 0) + 1
      if R.gen_restarts <= 3 then
        R.GEN_BUDGET = R.GEN_BUDGET / 2
        R.start_generation(seed_source.text, seed_source.why .. ", restarted")
      else
        say("Randomizer: the seed could not be generated - see rivet.log")
      end
    elseif coroutine.status(gen_job) == "dead" then
      gen_job = nil
      if seed then seed_ready(seed) else
        log("RANDO-ERROR seed generation failed:", tostring(err))
        say("Randomizer: these settings give no valid seed (" .. tostring(err) .. ")", { type = "center", duration = 8 })
      end
    end
  elseif not SEED and rando_seed_mode() == "random" and frames >= R.WAIT_FOR_COMPANION and not R.random_warned then
    R.random_warned = true
    log("RANDO-SEED seed = \"random\" needs the companion to remember the seed - start the companion")
    say("Randomizer: start the companion (seed = random)", { type = "center", duration = 8 })
  end
  if not (SEED and S) then return end
  -- no companion: play anyway (progress is not saved), so the start items still arrive
  if not R.restored and not R.unsaved and frames >= R.WAIT_COMPANION_START and rando_seed_mode() == "fixed" then
    R.unsaved = true
    log("RANDO-SAVE the companion did not connect - playing WITHOUT saving randomizer progress")
    say("Randomizer: the companion is not running - progress will NOT be saved", { type = "center", duration = 8 })
    if R.new_game_pending then R.new_game_pending = nil; R.reset_for_new_game("the prologue started")
    else begin() end
  end
  if R.replay_events then
    local buf = R.replay_events; R.replay_events = nil
    if #buf > 0 then log("RANDO-SEED replaying " .. #buf .. " event(s) that came in while generating") end
    for _, e in ipairs(buf) do
      local ok, err = pcall(e.fn, e.ev)
      if not ok then log("RANDO-ERROR", e.class, tostring(err)) end
    end
  end
  local ready = rivet.scene_ready() and rivet.hero()
  if ready and #queued > 0 and frames % 30 == 0 then flush_queue() end
  if pending_planet and ready then
    local name, old = pending_planet, pending_old; pending_planet, pending_old = nil, nil
    R.process_planet(name, old)
  end
  if RANDO_TRAVEL then
    local okt, et = pcall(RANDO_TRAVEL.tick, frames, ready)
    if not okt then log("RANDO-ERROR travel:", tostring(et)) end
  end
  if RANDO_HUB and SEED.hub then
    local okh, eh = pcall(RANDO_HUB.tick, frames, ready)
    if not okh then log("RANDO-ERROR hub:", tostring(eh)) end
  end
  if ready and RANDO_ARMOR then
    local oka, ea = pcall(RANDO_ARMOR.tick, frames)
    if not oka then log("RANDO-ERROR armor:", tostring(ea)) end
  end
  if ready and RANDO_SHOP then
    local okv, ev = pcall(RANDO_SHOP.tick, frames)
    if not okv then log("RANDO-ERROR shop:", tostring(ev)) end
  end
  if not announced and ready then
    announced = true
    -- (v0.54: round 26 showed "Randomizer 10. - seed ...": the kit's first 3 characters)
    say("Randomizer " .. R.RELEASE .. " (kit " .. R.KIT_VERSION .. ") - seed " .. SEED.seed .. " (" .. SEED.fingerprint .. ")",
        { type = "planet", sub = R.status_text(), duration = 6 })
  end
  if frames % 120 == 0 then
    pcall(rivet.ui_publish, 0, string.format('{"gold_bolts":%d,"planets":%d}', R.bolts_collected(), S.planets_done))
  end
end
local frame_errors = 0
pcall(rivet.on_frame, function(dt)
  local ok, err = pcall(frame, dt)
  if not ok then
    frame_errors = frame_errors + 1
    if frame_errors <= 5 then log("RANDO-ERROR frame:", tostring(err)) end
  end
end)

-- ---------------------------------------------------------------------------------------
-- TEST MODE (extras/test_mode/07_rando_testmode.lua sets RANDO_TEST_MODE = true)
--   F10  finish a story mission on the current planet (or the first one not done)
--   F11  pick up a Gold Bolt on the current planet
--   Ctrl+F10 twice  reset this seed's randomizer progress
-- ---------------------------------------------------------------------------------------
function R.test_planet()
  local cur = S.current_planet
  if cur then return cur end
  for _, p in ipairs(DB.planets) do if not S.planets_detected[p.id] then return p.id end end
  return DB.planets[#DB.planets].id
end
function R.test_story()
  local pid = R.test_planet()
  S.test_used = true
  local n = 0
  for _ in pairs(S.story_missions[pid] or {}) do n = n + 1 end
  history("[TEST] story mission " .. (n + 1) .. " on " .. pid)
  R.on_story_mission(pid, "TEST_" .. pid .. "_" .. (n + 1))
  return pid
end
function R.test_gold_bolt()
  local pid = R.test_planet()
  S.test_used = true
  local n = 1
  while S.bolts_seen["TEST " .. pid .. " " .. n] do n = n + 1 end
  local lid = R.pick_bolt_location(pid)
  S.bolts_seen["TEST " .. pid .. " " .. n] = lid or "none"
  history("[TEST] Gold Bolt on " .. pid)
  if lid then R.collect(lid, "[TEST] Gold Bolt") else say("[TEST] no Gold Bolt left on " .. planet_name(pid)) end
  return lid
end
local reset_armed_at = -100
function R.test_reset()
  local now = (rivet.time and rivet.time()) or 0
  if now - reset_armed_at > 5 then
    reset_armed_at = now
    say("[TEST] Press Ctrl+F10 again within 5 seconds to RESET this seed's progress", { type = "center", duration = 5 })
    return false
  end
  reset_armed_at = -100
  local keep = { real = S.real, real_nodes = S.real_nodes, real_mode = S.real_mode, weapon_types = S.weapon_types,
                 armor_baseline = S.armor_baseline, planet_shuffle_off = S.planet_shuffle_off }
  S = fresh_state(); R.state = S
  for k, v in pairs(keep) do S[k] = v end
  S.test_used = true
  begin()
  history("[TEST] progress reset")
  say("[TEST] Randomizer progress reset: " .. R.status_text(), { type = "center", duration = 5 })
  return true
end
if RANDO_TEST_MODE then
  on_key("F10", function()
    local ctrl = false
    pcall(function() ctrl = rivet.is_key_down(rivet.key("CONTROL")) end)
    if ctrl then R.test_reset() else R.test_story() end
  end)
  on_key("F11", function()
    local ctrl = false
    pcall(function() ctrl = rivet.is_key_down(rivet.key("CONTROL")) end)
    if not ctrl then R.test_gold_bolt() end        -- Ctrl+F11 is the campaign lab experiment
  end)
  log("RANDO-STATUS TEST MODE on: F10 story mission, F11 Gold Bolt, Ctrl+F10 twice resets")
end

log("Randomizer " .. R.KIT_VERSION .. " loaded (data " .. DB.version .. ", generator " .. GEN.VERSION .. ")")
log(string.format("RANDO-STATUS events subscribed %d/%d%s", subscribed, total,
                  #pending > 0 and (" (" .. #pending .. " will be retried)") or ""))
