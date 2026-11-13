-- Randomizer 10.0 seed generator, progression solver and spoiler log (Lua 5.4).
--
-- The same code runs inside the game (10_rando_runtime.lua generates the seed from your
-- settings in small slices across frames) and offline (tools/rando.py, tests). It is fully
-- deterministic: same seed text + same settings + same data version = same placements,
-- on any machine. Nothing here depends on table iteration order: every key list is sorted.
--
-- 10.0 (the hub and planet shuffle; the user's 8.5.2 defaults stay the baseline):
--   * HUB (hub = true, the default): a new game goes to the hub after the parade's wrench
--     (v0.51: Nefarious City, whose story starts there; 10.0-v0.5: Zurkie's Battleplex). The
--     prologue, the Battle Arena and Nefarious City are open from the start; every other visit
--     opens when you hold its planet's Coordinates (items of this seed) and the visits it depends
--     on are done (03_rando_campaign.lua C.hub_*). The solver's campaign reach is a fixpoint over
--     the visits, so the order planets open in is decided by where the Coordinates are. A hub seed
--     always has Coordinates as items and locked travel (planet_locks, travel_lock).
--   * REWARDS SPREAD (distribution = "spread", the default): items are no longer poured into the
--     25 Gold Bolts first. Progression (Coordinates, gadgets a location needs) goes anywhere in
--     logic; early_weapons weapons go to locations open from the start; every other item is shared
--     out over Gold Bolts, story missions, side activities and armor pods in proportion to how many
--     of each there are. Locations left over give Bolts or Raritanium (a Gold Bolt too: the game's
--     own Gold Bolt still counts as one, the randomizer adds the currency). "goldbolts_first" is
--     the 4.0-9.0 fill.
--   * SHOP vs REWARDS (shop_weapons, default 8): Ms. Zurkon's 15 normal slots sell shop_weapons
--     different weapons; her other slots are CLOSED (the runtime makes them sell the Burst Pistol,
--     which every save owns, so nothing can be bought there). Every weapon has exactly one route:
--     a weapon given at the start or at a location is never sold. ARSENAL_RESTORED's weapons are
--     never shop weapons: they are rewards (their slots in that mod's vendor are closed too).
--   * Seeds are format 10 (share code RA10).
-- 9.0 (hub = false: no hub; the story starts as in the game):
--   * The Zurkie's Battleplex hub of 8.0-8.5 is removed: its presets (hub, hub_chaos) and settings
--     (hub, hub_start_coordinates, hub_unlocks, hub_finale, hub_revisits) are retired and say so.
--   * A new game plays the prologue, then Nefarious City, then Sargasso, as in the game. Every
--     campaign order starts that way (03_rando_campaign.lua C.STORY_START); random_start is retired.
--   * The default preset is "balanced", which uses G.DEFAULTS as they stand (your 8.5.1 values:
--     Coordinates as items, planet_shuffle, weapon prices, Raritanium 120-1000).
--   * Seeds are format 9 (share code RA9). The generator version is in the fingerprint, so a 9.0
--     seed is a new seed: start it with NEW GAME.
-- 7.0 (one randomizer for everything):
--   * LEVELS (levels = true): every planet's travel is locked behind its Coordinates, which are
--     items of the seed. The planets the game itself takes you to (the prologue, Nefarious
--     City, Sargasso) are open from the start; every other planet opens when you find its
--     Coordinates (a Gold Bolt, a mission, an armor pod...). The story keeps the game's own
--     mission order (your game cannot open a mission out of order: docs/CAMPAIGN.md), so the
--     solver proves that the Coordinates the story needs next are always findable on the planets
--     already open. Locations on a locked planet (Gold Bolts included) are out of reach until
--     its Coordinates arrive.
--   * CURRENCY: every location without an item gives Bolts or Raritanium in a random amount
--     from your ranges, growing with the planet's place in the story, capped by a budget per
--     currency (bolts_min/max/budget, raritanium_min/max/budget). Optional start currency.
--   * SHOP PRICES: shop_prices = vanilla | weapon (a slot costs what its new weapon costs in the
--     normal game) | percent | random.
--   * START: start_items names items you always start with; the rest is random as before.
--   * RESTORED WEAPONS: ARSENAL_RESTORED's 9 weapons join the pool with include_arsenal_restored
--     (7.0 name restored_weapons; "auto" is resolved by the game from the companion's check).
--   * A reordered mission order (mission_order, experimental) must ALSO be finishable in the
--     game's own order, because that is what runs until mission control is verified.
-- 4.0-6.0 rules, kept:
--   * ONE GOLD BOLT = ONE ITEM. Every one of the game's 25 Gold Bolts holds exactly one real,
--     grantable item (a weapon, a gadget, an armor piece, or Coordinates).
--   * Hoverboots and the Map-O-Matic are ALWAYS in the starting inventory.
--   * Every item is placed at most once (start, a vendor slot, or one location).
--   * THE WEAPON REGISTRY (DB.items[...].acquisition, data/weapon_registry.json): every weapon
--     has exactly one route. The pool weapons are split by the seed over the vendor's 15 normal
--     slots (each keeps the point in the story it unlocks), the start and reward locations.
--     Shatterbomb and RYNO 8 stay in their own slots, the Burst Pistol is the starting weapon,
--     cut weapons are never placed.
--   * ARMOR: the 27 armor pieces you can find are items, and every armor source (a pocket
--     dimension, a Zurkie's challenge, the Lorb monk) is a location.
--
-- Logic model (honest version of what the game allows, see docs/DESIGN.md):
--   * Without levels the story is never blocked: every planet is reached in the game's order.
--   * planet_locks without travel_lock (6.0 behaviour): rewards of a planet whose Coordinates
--     you do not hold are banked and paid when they arrive. Gold Bolts are never banked.
--   * Gadget requirements of a location count only randomizer-given gadgets (the game's own
--     copy is ignored), so an ability is never placed behind itself.
--   * Abilities the story gives (Speetle, Trudi, ...) cannot be granted: locations needing
--     them, and locations whose trigger is not proven (armor finds, collectibles), only ever
--     hold non-progression rewards.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["02_rando_generator"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)
RANDO_GEN = {}
local G = RANDO_GEN
G.VERSION = "10.0.2"
local DB = RANDO_DATA

-- ------------------------------------------------------------------------------------------
-- hashing and random numbers (64-bit integer arithmetic wraps in Lua 5.4)
-- ------------------------------------------------------------------------------------------
function G.fnv1a(s)
  local h = -3750763034362895579            -- 0xcbf29ce484222325
  for i = 1, #s do h = (h ~ s:byte(i)) * 1099511628211 end
  return h
end
function G.hex(h) return string.format("%016x", h) end

local function rotl(x, k) return (x << k) | (x >> (64 - k)) end
function G.rng(seed_int)
  local sm = seed_int
  local function splitmix()
    sm = sm + -7046029254386353131            -- 0x9E3779B97F4A7C15
    local z = sm
    z = (z ~ (z >> 30)) * -4658895280553007687 -- 0xBF58476D1CE4E5B9
    z = (z ~ (z >> 27)) * -7723592293110705685 -- 0x94D049BB133111EB
    return z ~ (z >> 31)
  end
  local s1, s2, s3, s4 = splitmix(), splitmix(), splitmix(), splitmix()
  local r = {}
  function r.next()
    local result = rotl(s2 * 5, 7) * 9
    local t = s2 << 17
    s3 = s3 ~ s1; s4 = s4 ~ s2; s2 = s2 ~ s3; s1 = s1 ~ s4
    s3 = s3 ~ t; s4 = rotl(s4, 45)
    return result
  end
  function r.below(n)                          -- uniform integer in [0, n)
    assert(n >= 1)
    local span = 1 << 53
    local limit = span - (span % n)
    while true do
      local v = r.next() >> 11
      if v < limit then return v % n end
    end
  end
  function r.int(a, b) return a + r.below(b - a + 1) end
  function r.chance(p) return r.below(1000000) < math.floor(p * 1000000) end
  function r.shuffle(t)
    for i = #t, 2, -1 do local j = r.below(i) + 1; t[i], t[j] = t[j], t[i] end
    return t
  end
  function r.pick(t) return t[r.below(#t) + 1] end
  return r
end

-- ------------------------------------------------------------------------------------------
-- settings
-- ------------------------------------------------------------------------------------------
G.DEFAULTS = {
  -- what is randomized
  weapons = true,                 -- the weapon pool is shuffled over the shop, the start and the rewards
  include_arsenal_restored = false, -- ARSENAL_RESTORED's 9 weapons join the pool (7.0 name: restored_weapons;
                                  -- "auto" in 04_rando_settings.lua = on when the companion finds the mod)
  gadgets = true,                 -- Box Breaker, Omniglove, Glitch (Hoverboots, Map-O-Matic: always at the start)
  armor = true,                   -- armor pieces are rewards and armor sources are locations
  planet_locks = true,           -- Coordinates exist as items (7.0: levels = true sets this and travel_lock)
  travel_lock = false,            -- 7.0 levels: flying to a planet without its Coordinates sends you back;
                                  -- false with planet_locks: its mission rewards wait instead (6.0)
  shop = "shuffle",               -- shuffle: the vendor's 15 slots sell the seed's weapons | vanilla: her own
  shop_prices = "weapon",         -- vanilla | weapon | percent | random (7.0)
  shop_price_percent = 100,       -- percent: every slot costs this % of its price; random: the lowest %
  shop_price_max_percent = 150,   -- random: the highest %
  -- currency at every location without an item (7.0)
  bolts = true,                   -- Bolts rewards
  raritanium = true,              -- Raritanium rewards
  bolts_min = 1000, bolts_max = 10000,         -- Bolts per reward (grows with the story when currency_scaling)
  raritanium_min = 120, raritanium_max = 1000,   -- Raritanium per reward
  bolts_budget = 150000,          -- most Bolts all rewards give together (0 = no limit); the 15 shop
                                  -- weapons cost 255,250 Bolts in the normal game
  raritanium_budget = 2000,       -- most Raritanium all rewards give together (0 = no limit)
  bolts_percent = 60,             -- with both currencies: % of currency rewards that are Bolts
  currency_scaling = true,        -- later planets give more (false: any amount in the range anywhere)
  -- where rewards are (the 25 Gold Bolts always are)
  story_milestones = true,        -- second story mission of each planet
  side_locations = true,          -- Zurkie's cups, Trudi, Blizar chef, Ardolis
  -- start (Hoverboots and Map-O-Matic are always added)
  start_weapons = 2,
  start_gadgets = 1,              -- extra randomizer gadgets at the start
  start_items = "",               -- 7.0: comma-separated items you always start with, e.g. "weapon:enforcer,glitch"
  start_bolts = 0,                -- 7.0: Bolts handed out with the start
  start_raritanium = 0,           -- 7.0: Raritanium handed out with the start
  start_coordinates = "first_two",-- start_only | first_two | random_extra (planet_locks only)
  -- logic
  weapon_logic = "none",          -- none | light | standard: start/reward weapons needed before later
                                  -- planets' rewards (the shop's slots unlock as in the normal game,
                                  -- so you can always buy as many weapons as without the randomizer)
  accessibility = "full",         -- full: every location in logic | beatable: progression items only
  -- mission order (3.0, experimental: needs verified mission control, docs/CAMPAIGN.md; 7.0 name mission_order)
  campaign_mode = "planet_shuffle",      -- vanilla | planet_shuffle | mission_shuffle | full | chaos
                                  -- 9.0: every order starts with the prologue, Nefarious City, Sargasso
                                  -- 10.0: a hub seed is always planet_shuffle (Coordinates decide the order)
  exclude = "",                   -- comma-separated item keys never randomized, e.g. "weapon:ryno_8"
  -- 10.0
  hub = true,                     -- a new game goes to the hub (v0.51: Nefarious City, its story starts);
                                  -- the Battle Arena is open too; Coordinates open every other destination
  distribution = "spread",        -- spread: items over every kind of location | goldbolts_first (4.0-9.0)
  shop_weapons = 8,               -- different weapons Ms. Zurkon sells (0-15); her other slots are closed
                                  -- and those weapons become rewards
  early_weapons = 2,              -- weapons placed at locations open from the start (0-6)
}
-- items every seed starts with, whatever the settings say
G.ALWAYS_START = { "hoverboots", "map_o_matic" }
-- weapons the game itself hands out in the prologue whatever happens (Burst Pistol and
-- Shatterbomb: round 14's rivet.log shows the Burst Pistol already owned on a fresh save). A
-- Gold Bolt holding one would give nothing, so they are not rewards.
G.GAME_GIVEN = { "weapon:burst_pistol" }
-- settings that no longer exist, and why
G.RETIRED = {
  shop_slots = "3.x", shop_progression_max = "3.x", luxury_slots = "3.x", economy = "3.x",
  completion_gold_min = "3.x", completion_gold_max = "3.x", start_gold = "3.x", gold_bolt_locations = "3.x",
  armor_rewards = "armor", armor_finds = "armor", armor_mode = "armor", shop_weapons = "shop",
  filler_amount = "filler",
  include_hidden_weapons = "phantom", experimental_pickups = "phantom", experimental_collectibles = "phantom",
  hub_start_coordinates = "hub", hub_unlocks = "hub", hub_finale = "hub", hub_revisits = "hub",
  random_start = "start",
}
G.RETIRED_WHY = {
  ["3.x"] = "is not used since 4.0 (no Gold Bolt prices: every Gold Bolt gives one item)",
  armor = "is replaced by armor = true/false in 5.0 (armor pieces are rewards, armor sources are locations)",
  shop = "is replaced by shop = \"shuffle\" or \"vanilla\" in 5.0 (the vendor sells its own weapons, shuffled)",
  filler = "is replaced by bolts_min/bolts_max and raritanium_min/raritanium_max in 7.0",
  phantom = "is gone in 6.0: every reward must be obtainable (cut weapons, untested pickups and unbound collectibles are never placed)",
  hub = "is not used in 10.0: the hub's destinations open with Coordinates found in the seed (the start offers the prologue, the Battle Arena and Nefarious City)",
  start = "is gone in 9.0: every seed starts with the prologue, then Nefarious City",
}
-- 9.0: presets that no longer exist, and the one used instead (10.0: the hub is on in every preset)
G.RETIRED_PRESETS = { hub = "balanced", hub_chaos = "chaos" }
-- 7.0 names for existing settings (both are accepted)
G.ALIASES = { restored_weapons = "include_arsenal_restored", mission_order = "campaign_mode" }
G.CHOICES = {
  start_coordinates = { start_only = true, first_two = true, random_extra = true },
  shop = { shuffle = true, vanilla = true },
  shop_prices = { vanilla = true, weapon = true, percent = true, random = true },
  weapon_logic = { none = true, light = true, standard = true },
  accessibility = { full = true, beatable = true },
  campaign_mode = { vanilla = true, planet_shuffle = true, mission_shuffle = true, full = true, chaos = true },
  distribution = { spread = true, goldbolts_first = true },
}
-- the most rando_give.dll hands over in one request is 100,000 (RG_MAX_COUNT)
G.RANGES = { start_weapons = { 0, 4 }, start_gadgets = { 0, 2 },
             shop_price_percent = { 0, 500 }, shop_price_max_percent = { 0, 500 },
             bolts_min = { 100, 100000 }, bolts_max = { 100, 100000 },
             raritanium_min = { 1, 5000 }, raritanium_max = { 1, 5000 },
             bolts_budget = { 0, 5000000 }, raritanium_budget = { 0, 500000 }, bolts_percent = { 0, 100 },
             start_bolts = { 0, 100000 }, start_raritanium = { 0, 5000 },
             shop_weapons = { 0, 15 }, early_weapons = { 0, 6 } }
G.PRESETS = {
  -- 7.0 presets (9.0: the 8.0 hub presets are gone, G.RETIRED_PRESETS)
  -- balanced: every item system, the game's own level order, moderate currency, weapon prices
  balanced = {},
  -- chaos: wide currency swings, random prices, locked levels with the fewest open planets
  chaos = { start_weapons = 1, start_gadgets = 0, planet_locks = true, travel_lock = true, start_coordinates = "start_only",
            shop_prices = "random", shop_price_percent = 25, shop_price_max_percent = 300,
            bolts_min = 500, bolts_max = 40000, raritanium_min = 10, raritanium_max = 2000,
            bolts_budget = 350000, raritanium_budget = 10000, bolts_percent = 50, currency_scaling = false },
  -- full: every item system plus Coordinates as items (rewards of a planet wait for them; travel free)
  full = { planet_locks = true, bolts_max = 15000, raritanium_max = 250, bolts_budget = 180000, raritanium_budget = 3000 },
  -- campaign: locked levels (travel needs Coordinates), everything else balanced
  campaign = { planet_locks = true, travel_lock = true, start_coordinates = "first_two" },
  -- everything: locked levels, random prices, start currency, wider currency
  everything = { planet_locks = true, travel_lock = true, start_coordinates = "start_only",
                 shop_prices = "random", shop_price_percent = 50, shop_price_max_percent = 200,
                 start_bolts = 2500, start_raritanium = 25, bolts_max = 20000, raritanium_max = 400,
                 bolts_budget = 250000, raritanium_budget = 5000 },
  -- older names
  standard = {}, extended = {}, armor = {}, classic = {},
  coordinates = { planet_locks = true, story_milestones = true },
  -- 3.0 mission-order presets (experimental: need the runtime's mission control, docs/CAMPAIGN.md;
  -- until then they play the game's own order, which every seed is also checked against)
  planet_shuffle = { campaign_mode = "planet_shuffle" },
  mission_shuffle = { campaign_mode = "mission_shuffle" },
  full_campaign = { campaign_mode = "full", start_coordinates = "start_only" },
  campaign_chaos = { campaign_mode = "chaos", start_coordinates = "start_only" },
}
G.PRESET_NAMES = { balanced = "Balanced", chaos = "Chaos", full = "Full Randomizer", campaign = "Campaign Randomizer",
                   everything = "Everything Randomized" }

local function sorted_keys(t)
  local k = {}
  for key in pairs(t) do k[#k + 1] = key end
  table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
  return k
end
G.sorted_keys = sorted_keys
-- insertion sort: stable, and the same on every machine (Lua 5.4's table.sort picks a random
-- pivot for arrays over 100 elements, so it is not used where ties matter)
function G.stable_sort(t, less)
  for i = 2, #t do
    local v, j = t[i], i - 1
    while j >= 1 and less(v, t[j]) do t[j + 1] = t[j]; j = j - 1 end
    t[j + 1] = v
  end
  return t
end

-- 7.0: user settings in the 7.0 names, and 6.0's filler settings, turned into the generator's keys
function G.translate(user, warn)
  local u = {}
  for k, v in pairs(user or {}) do u[k] = v end
  for alias, key in pairs(G.ALIASES) do
    if u[alias] ~= nil then
      if u[key] == nil then u[key] = u[alias] end
      u[alias] = nil
    end
  end
  -- restored_weapons = "auto" is decided by the game (the companion checks whether ARSENAL_RESTORED
  -- is installed); anywhere else it means "not installed"
  if u.include_arsenal_restored == "auto" then
    u.include_arsenal_restored = false
    warn[#warn + 1] = "restored_weapons = \"auto\" is decided in the game by the companion's check; here it means false"
  end
  -- levels = true: Coordinates lock each planet's travel
  if u.levels ~= nil then
    if type(u.levels) ~= "boolean" then warn[#warn + 1] = "levels must be a boolean"
    else
      if u.planet_locks == nil then u.planet_locks = u.levels end
      if u.travel_lock == nil then u.travel_lock = u.levels end
    end
    u.levels = nil
  end
  -- 6.0 filler settings
  if u.filler ~= nil then
    local f = u.filler
    if f == "none" then u.bolts, u.raritanium = false, false
    elseif f == "bolts" then u.raritanium = false; if u.bolts == nil then u.bolts = true end
    elseif f == "raritanium" then u.bolts = false; if u.raritanium == nil then u.raritanium = true end
    elseif f == "mixed" then if u.bolts == nil then u.bolts = true end; if u.raritanium == nil then u.raritanium = true end
    else warn[#warn + 1] = "filler: unknown choice " .. tostring(f) end
    warn[#warn + 1] = "filler " .. G.RETIRED_WHY.filler .. " (converted)"
    u.filler = nil
  end
  for old, new in pairs({ filler_bolts = "bolts", filler_raritanium = "raritanium" }) do
    if u[old] ~= nil then
      if math.type(u[old]) == "integer" then
        if u[new .. "_min"] == nil then u[new .. "_min"] = u[old] end
        if u[new .. "_max"] == nil then u[new .. "_max"] = u[old] end
      end
      warn[#warn + 1] = old .. " " .. G.RETIRED_WHY.filler .. " (converted to " .. new .. "_min/" .. new .. "_max)"
      u[old] = nil
    end
  end
  return u
end

-- returns normalized settings (every key, right types, in range) and a list of warnings
function G.normalize(user, preset)
  local s, warn = {}, {}
  for k, v in pairs(G.DEFAULTS) do s[k] = v end
  local p = G.PRESETS[preset or "balanced"]
  if not p and G.RETIRED_PRESETS[preset] then
    local use = G.RETIRED_PRESETS[preset]
    warn[#warn + 1] = "preset " .. tostring(preset) .. " is gone (10.0: every preset has the hub, hub = true) - using " .. use
    p = G.PRESETS[use]
  end
  if not p then warn[#warn + 1] = "unknown preset " .. tostring(preset) .. " - using balanced"; p = {} end
  for k, v in pairs(p) do s[k] = v end
  user = G.translate(user, warn)
  for _, k in ipairs(sorted_keys(user or {})) do
    local v = user[k]
    if k == "seed" or k == "preset" or G.DEFAULTS[k] == nil then
      if G.RETIRED[k] then
        warn[#warn + 1] = k .. " " .. G.RETIRED_WHY[G.RETIRED[k]]
      elseif k ~= "seed" and k ~= "preset" then warn[#warn + 1] = "unknown setting " .. k end
    elseif type(v) ~= type(G.DEFAULTS[k]) then
      warn[#warn + 1] = k .. " must be a " .. type(G.DEFAULTS[k])
    elseif G.CHOICES[k] and not G.CHOICES[k][v] then
      warn[#warn + 1] = k .. ": unknown choice " .. tostring(v)
    elseif G.RANGES[k] and (v < G.RANGES[k][1] or v > G.RANGES[k][2] or math.type(v) ~= "integer") then
      warn[#warn + 1] = k .. " must be a whole number from " .. G.RANGES[k][1] .. " to " .. G.RANGES[k][2]
    else
      s[k] = v
    end
  end
  -- ranges given the wrong way round
  for _, pair in ipairs({ { "bolts_min", "bolts_max" }, { "raritanium_min", "raritanium_max" },
                          { "shop_price_percent", "shop_price_max_percent" } }) do
    local lo, hi = pair[1], pair[2]
    if s[lo] > s[hi] then
      if pair[1] == "shop_price_percent" and s.shop_prices ~= "random" then
        -- only random uses the upper bound
      else
        warn[#warn + 1] = lo .. " (" .. s[lo] .. ") is above " .. hi .. " (" .. s[hi] .. ") - swapped"
        s[lo], s[hi] = s[hi], s[lo]
      end
    end
  end
  -- 10.0 hub: Coordinates are items and travel is locked; the order is planet_shuffle (the hub's
  -- own: Coordinates decide it); start_coordinates does not apply (the start is the hub's three)
  if s.hub then
    local u = user or {}
    for k, want in pairs({ planet_locks = true, travel_lock = true, campaign_mode = "planet_shuffle" }) do
      if s[k] ~= want then
        if u[k] ~= nil then warn[#warn + 1] = k .. " = " .. tostring(s[k]) .. " does not apply to a hub seed (hub = true) - " .. tostring(want) .. " used" end
        s[k] = want
      end
    end
    if u.start_coordinates ~= nil then warn[#warn + 1] = "start_coordinates does not apply to a hub seed: the prologue's, Zurkie's and Nefarious City's planets are open" end
  end
  -- travel locks need Coordinates
  if s.travel_lock and not s.planet_locks then
    s.planet_locks = true
    warn[#warn + 1] = "planet_locks turned on: travel_lock (levels) needs Coordinates"
  end
  return s, warn
end

function G.canonical(s)
  local parts = {}
  for _, k in ipairs(sorted_keys(G.DEFAULTS)) do parts[#parts + 1] = k .. "=" .. tostring(s[k]) end
  return table.concat(parts, ";")
end
-- settings that differ from the defaults, as a short shareable text
function G.share_code(seed_text, s, preset)
  local parts = {}
  local base = {}
  for k, v in pairs(G.DEFAULTS) do base[k] = v end
  for k, v in pairs(G.PRESETS[preset or "balanced"] or {}) do base[k] = v end
  for _, k in ipairs(sorted_keys(G.DEFAULTS)) do
    if s[k] ~= base[k] then parts[#parts + 1] = k .. "=" .. tostring(s[k]) end
  end
  return string.format("RA10|%s|%s|%s", seed_text, preset or "balanced", table.concat(parts, ","))
end
function G.parse_share_code(code)
  if code:match("^RA[456789]|") then return nil, "a 4.0-9.0 share code: 10.0 seeds differ (the hub, planet shuffle, rewards spread, generator 10.0) - generate a new seed" end
  local seed, preset, rest = code:match("^RA10|([^|]*)|([^|]*)|(.*)$")
  if not seed then return nil, "not a Randomizer 10.0 share code" end
  local user = {}
  for kv in rest:gmatch("[^,]+") do
    local k, v = kv:match("^([%w_]+)=(.*)$")
    if k then
      local d = G.DEFAULTS[k]
      if type(d) == "boolean" then user[k] = (v == "true")
      elseif type(d) == "number" then user[k] = math.tointeger(tonumber(v)) or tonumber(v)
      else user[k] = v end
    end
  end
  return seed, preset, user
end

function G.fingerprint(seed_text, s)
  return G.hex(G.fnv1a(table.concat({ "RA10", G.VERSION, DB.version, seed_text, G.canonical(s) }, "\n"))):sub(1, 12)
end

-- ------------------------------------------------------------------------------------------
-- pools
-- ------------------------------------------------------------------------------------------
local function planet_index(pid)
  for _, p in ipairs(DB.planets) do if p.id == pid then return p.story_index end end
  return nil
end
G.planet_index = planet_index

local function excluded_set(s)
  local ex = {}
  for k in s.exclude:gmatch("[^,%s]+") do ex[k] = true end
  return ex
end

-- every location in this seed, with its logic requirements
function G.location_pool(s)
  local out = {}
  local ex = excluded_set(s)
  local always = {}
  for _, g in ipairs(G.ALWAYS_START) do always[g] = true end
  for _, lid in ipairs(sorted_keys(DB.locations)) do
    local loc = DB.locations[lid]
    local use = (loc.kind == "planet")
      or (loc.kind == "goldbolt")
      or (loc.kind == "story" and s.story_milestones)
      or (loc.kind == "side" and s.side_locations)
      or (loc.kind == "armor_source" and s.armor)
    if use then
      local reqs, in_logic = {}, loc.progression
      for _, r in ipairs(loc.requires or {}) do
        if r:match("^ability:") then in_logic = false end
        -- a gadget the randomizer does not hand out (gadgets off, or excluded): the game's own
        -- copy comes at an unknown time, so the location is out of logic. Hoverboots and the
        -- Map-O-Matic are always owned from the start, so they never take a location out.
        if not always[r] and (not s.gadgets or ex[r]) and not r:match("^ability:") then in_logic = false end
        if not always[r] then reqs[#reqs + 1] = r end
      end
      out[#out + 1] = { id = lid, kind = loc.kind, planet = loc.planet, requires = reqs, in_logic = in_logic,
                        filler_only = loc.holds == "filler" }
    end
  end
  return out
end

-- item pool: list of { key, class = "progression" | "useful" }
function G.item_pool(s, gating)
  local ex = excluded_set(s)
  local items = {}
  local function add(key, class) if not ex[key] then items[#items + 1] = { key = key, class = class } end end
  local skip = {}
  for _, g in ipairs(DB.start_kit) do skip[g] = true end
  for _, g in ipairs(G.ALWAYS_START) do skip[g] = true end
  for _, g in ipairs(G.GAME_GIVEN) do skip[g] = true end
  for _, key in ipairs(sorted_keys(DB.items)) do
    local it = DB.items[key]
    if it.category == "weapon" and s.weapons and not skip[key] then
      -- 6.0: the weapon pool (start, shop slots, rewards)
      if G.in_weapon_pool(key, s) then add(key, s.weapon_logic ~= "none" and "progression" or "useful") end
    elseif it.category == "gadget" and s.gadgets and not skip[key] then
      add(key, gating[key] and "progression" or "useful")
    elseif it.category == "coordinates" and s.planet_locks then
      add(key, "progression")
    elseif it.category == "armor" and s.armor and it.randomizable and not it.owned_from_start then
      add(key, "useful")
    end
  end
  return items, ex
end

-- an item a Gold Bolt may hold: one the randomizer can really hand over (or Coordinates).
-- Armor pieces are handed over through the game's own armor-give code (rando_give.dll v5).
function G.bolt_worthy(key)
  local it = DB.items[key]
  if not it then return false end
  if it.category == "coordinates" then return true end
  if it.category == "armor" then return it.grant == "vanity" and it.randomizable == true end
  return (it.category == "weapon" or it.category == "gadget") and it.grant == "inventory" and not it.experimental
end

-- filler: "filler:bolts:5000" = 5000 Bolts. Any number of locations may hold Bolts or Raritanium;
-- 7.0 gives each its own amount (G.currency_amounts)
function G.filler_key(kind, amount)
  return "filler:" .. kind .. ":" .. tostring(math.tointeger(amount) or amount)
end
function G.parse_filler(key)
  if type(key) ~= "string" then return nil end
  local kind, n = key:match("^filler:([%w_]+):(%d+)$")
  if not kind then return nil end
  return kind, tonumber(n)
end
-- the currencies a seed may give
function G.filler_kinds(s)
  local k = {}
  if s.bolts then k[#k + 1] = "bolts" end
  if s.raritanium then k[#k + 1] = "raritanium" end
  return k
end

-- 7.0 currency amounts. Each location's amount is drawn from the currency's range; with
-- currency_scaling it centres on the location's place in the story (first planet low, last
-- planet high; armor sources, which can be found anywhere, in the middle). Bolts round to 250
-- (50 under 1000), Raritanium to 5 (1 under 50). If the total is above the budget, every amount
-- is scaled down (never below the minimum) and the spoiler says so.
local function round_to(v, step) return math.floor(v / step + 0.5) * step end
function G.currency_step(kind, hi)
  if kind == "bolts" then return hi >= 1000 and 250 or 50 end
  return hi >= 50 and 5 or 1
end
local function clamp_round(v, lo, hi, step)
  local r = round_to(v, step)
  while r > hi do r = r - step end
  while r < lo do r = r + step end
  if r > hi then r = hi end                -- a range narrower than one step
  return math.tointeger(r) or math.floor(r)
end
function G.location_progress(lid)
  local loc = DB.locations[lid]
  local idx = loc and loc.planet and G.planet_index(loc.planet)
  if not idx then return 0.5 end
  local p = (idx - 1) / math.max(1, #DB.planets - 1)
  if loc.kind == "story" or loc.kind == "side" then p = math.min(1, p + 0.05) end
  return p
end
-- lids: the locations that get currency, in a fixed order; returns lid -> key, totals, notes
function G.currency_amounts(s, lids, rng)
  local kinds = G.filler_kinds(s)
  local out, totals, notes = {}, { bolts = 0, raritanium = 0 }, {}
  if #kinds == 0 then return out, totals, notes end
  local chosen = { bolts = {}, raritanium = {} }
  for _, lid in ipairs(lids) do
    local kind = kinds[1]
    if #kinds == 2 then kind = (rng.below(100) < s.bolts_percent) and "bolts" or "raritanium" end
    local lo, hi = s[kind .. "_min"], s[kind .. "_max"]
    local step = G.currency_step(kind, hi)
    local v
    if s.currency_scaling then
      local centre = lo + (hi - lo) * G.location_progress(lid)
      local spread = (hi - lo) * 0.25
      local a, b = math.max(lo, centre - spread), math.min(hi, centre + spread)
      v = a + (b - a) * (rng.below(1000001) / 1000000)
    else
      v = lo + (hi - lo) * (rng.below(1000001) / 1000000)
    end
    v = clamp_round(v, lo, hi, step)
    chosen[kind][#chosen[kind] + 1] = { lid = lid, v = v }
  end
  for _, kind in ipairs({ "bolts", "raritanium" }) do
    local list = chosen[kind]
    local lo, hi = s[kind .. "_min"], s[kind .. "_max"]
    local step = G.currency_step(kind, hi)
    local budget = s[kind .. "_budget"]
    local sum = 0
    for _, e in ipairs(list) do sum = sum + e.v end
    if budget > 0 and sum > budget and #list > 0 then
      local floor_sum = lo * #list
      if floor_sum >= budget then
        for _, e in ipairs(list) do e.v = lo end
        notes[#notes + 1] = string.format("%s_budget %d is below %d rewards x %s_min %d: every %s reward gives %d",
                                          kind, budget, #list, kind, lo, kind, lo)
      else
        -- scale the part above the minimum so the total lands within the budget
        local above = sum - floor_sum
        local f = (budget - floor_sum) / above
        local total = 0
        for _, e in ipairs(list) do
          e.v = lo + math.floor((e.v - lo) * f / step) * step
          if e.v > hi then e.v = hi end
          total = total + e.v
        end
        notes[#notes + 1] = string.format("%s rewards scaled down to the %s_budget of %d (they would have given %d)",
                                          kind, kind, budget, sum)
      end
    end
    for _, e in ipairs(list) do
      out[e.lid] = G.filler_key(kind, e.v)
      totals[kind] = totals[kind] + e.v
    end
  end
  return out, totals, notes
end

-- 6.0 the weapon pool: weapons that may be sold in a vendor slot, start, or be a reward
function G.in_weapon_pool(key, s)
  local it = DB.items[key]
  if not (it and it.category == "weapon") then return false end
  return it.acquisition == "pool" or (it.acquisition == "arsenal_restored" and s.include_arsenal_restored == true)
end
-- 10.0: a weapon Ms. Zurkon may sell in one of her 15 normal slots. ARSENAL_RESTORED's weapons are
-- never shop weapons (that mod's vendor sells them in slots of its own, which the runtime closes
-- when the seed gives them elsewhere), so they are always rewards.
function G.shop_eligible(key, s)
  local it = DB.items[key]
  return G.in_weapon_pool(key, s) and it.acquisition == "pool"
end
-- the vendor's 15 normal slots, named by the weapon each sells in the normal game (sorted)
function G.vendor_weapons()
  local out = {}
  for _, key in ipairs(sorted_keys(DB.items)) do
    if DB.items[key].category == "weapon" and DB.items[key].vendor then out[#out + 1] = key end
  end
  return out
end

-- ------------------------------------------------------------------------------------------
-- logic
-- ------------------------------------------------------------------------------------------
-- weapons needed before rewards of the planet at story index i count
function G.weapons_needed(s, i)
  if not i or s.weapon_logic == "none" or not s.weapons then return 0 end
  if s.weapon_logic == "light" then return math.max(0, (i - 2) // 2) end
  return math.max(0, i - 2)
end

local function weapon_count(owned)
  local n = 0
  for k, c in pairs(owned) do if c > 0 and k:sub(1, 7) == "weapon:" then n = n + 1 end end
  return n
end

-- can this location be collected with what is owned? (story progress is free)
local function can_collect(s, loc, owned, wcount, reach, reach_alt, hreach)
  if not loc.in_logic then return false end
  local camp = s._campaign
  if camp and camp.hub then
    -- 10.0 hub: a location counts once the visit holding it can be played
    local sid = camp.loc_seg[loc.id]
    if sid and not (hreach and hreach[sid]) then return false end
    if s.planet_locks and loc.planet and (owned["access:" .. loc.planet] or 0) == 0 then return false end
    for _, r in ipairs(loc.requires) do
      if (owned[r] or 0) == 0 then return false end
    end
    if loc.planet and wcount < G.weapons_needed(s, planet_index(loc.planet)) then return false end
    return true
  end
  if camp then
    local idx = camp.loc_segment[loc.id]
    if idx and idx > (reach or 0) then return false end
  end
  -- 7.0: a reordered campaign must also hold in the game's own order (what runs until mission
  -- control is verified), so a location counts only when both orders have reached it
  local alt = s._campaign_alt
  if alt then
    local idx = alt.loc_segment[loc.id]
    if idx and idx > (reach_alt or 0) then return false end
  end
  -- Coordinates: with travel_lock (levels) a locked planet cannot be reached at all; without it
  -- they gate its mission rewards only (a Gold Bolt always pays at once)
  if s.planet_locks and loc.planet and (owned["access:" .. loc.planet] or 0) == 0 then
    if s.travel_lock or loc.kind ~= "goldbolt" then return false end
  end
  for _, r in ipairs(loc.requires) do
    if (owned[r] or 0) == 0 then return false end
  end
  if loc.planet then
    local tier = planet_index(loc.planet)
    if camp and camp.loc_segment[loc.id] then tier = G.campaign_tier(camp, camp.loc_segment[loc.id]) end
    if wcount < G.weapons_needed(s, tier) then return false end
    if alt and alt.loc_segment[loc.id] and wcount < G.weapons_needed(s, G.campaign_tier(alt, alt.loc_segment[loc.id])) then return false end
  end
  return true
end
-- in a reordered campaign the combat tier follows the position in the campaign, not the planet
-- (7.0: in the game's own order, e.g. with levels, the tier is the planet's own story index, as
-- without a campaign)
function G.campaign_tier(camp, pos)
  if camp.vanilla then
    local seg = camp.segments[pos]
    if seg and seg.id == "finale" then return #DB.planets end
    return (seg and planet_index(seg.planet)) or math.max(1, math.ceil(pos * #DB.planets / #camp.segments))
  end
  return math.max(1, math.ceil(pos * #DB.planets / #camp.segments))
end
G.can_collect = can_collect

local function add_item(owned, key)
  owned[key] = (owned[key] or 0) + 1
end

-- Sphere-by-sphere playthrough. placement: lid -> item key. extra: items owned besides the
-- start (assumed fill). Returns { reachable = {lid=true}, spheres = { {lid...}... }, owned }
function G.solve(s, pool, placement, start_items, extra, opts)
  opts = opts or {}
  local owned = {}
  for _, k in ipairs(start_items) do add_item(owned, k) end
  for _, k in ipairs(extra or {}) do add_item(owned, k) end
  local reach, spheres = {}, {}
  local camp = s._campaign
  local kit = {}
  for _, g in ipairs(DB.start_kit) do kit[g] = true end
  local creach, cwhy = 0, nil
  local alt, areach, awhy = s._campaign_alt, 0, nil
  local hreach, horder
  local hub_first, hub_seq = {}, {}
  while true do
    local wcount = weapon_count(owned)
    if camp and camp.hub then
      hreach, horder = RANDO_CAMPAIGN.hub_reach(camp.dests, owned, kit)
      creach = #horder
      if creach < #camp.dests then
        for _, d in ipairs(camp.dests) do
          if not hreach[d.id] then cwhy = d.id; break end
        end
      else cwhy = nil end
      for _, id in ipairs(horder) do
        if not hub_first[id] then hub_first[id] = #spheres + 1; hub_seq[#hub_seq + 1] = id end
      end
    elseif camp then
      creach, cwhy = RANDO_CAMPAIGN.reach(camp, owned, kit, wcount, function(i) return G.weapons_needed(s, G.campaign_tier(camp, i)) end)
    end
    if alt then
      areach, awhy = RANDO_CAMPAIGN.reach(alt, owned, kit, wcount, function(i) return G.weapons_needed(s, G.campaign_tier(alt, i)) end)
    end
    local sphere = {}
    for _, loc in ipairs(pool) do
      if not reach[loc.id] and can_collect(s, loc, owned, wcount, creach, areach, hreach) then
        sphere[#sphere + 1] = loc.id
      end
    end
    for _, lid in ipairs(sphere) do
      reach[lid] = true
      local it = placement[lid]
      if it then add_item(owned, it) end
    end
    if #sphere == 0 then break end
    spheres[#spheres + 1] = sphere
    if opts.yield then opts.yield() end
  end
  return { reachable = reach, spheres = spheres, owned = owned, campaign_reach = creach, campaign_block = cwhy,
           alt_reach = areach, alt_block = awhy, hub_route = (camp and camp.hub) and hub_seq or nil, hub_first = hub_first }
end

-- ------------------------------------------------------------------------------------------
-- generation
-- ------------------------------------------------------------------------------------------
local function category(key) return DB.items[key] and DB.items[key].category or "?" end

-- gadgets that some location in this seed needs
local function gating_gadgets(s)
  local g = {}
  local always = {}
  for _, k in ipairs(G.ALWAYS_START) do always[k] = true end
  for _, loc in pairs(DB.locations) do
    for _, r in ipairs(loc.requires or {}) do
      if DB.items[r] and DB.items[r].category == "gadget" and not always[r] then g[r] = true end
    end
  end
  return g
end

-- reward order of the leftover (non-Gold-Bolt) locations: story missions first
local KIND_RANK = { goldbolt = 0, planet = 1, story = 2, side = 2, armor_source = 2, collectible = 3 }

local function attempt(seed_text, s, fp, n, yield)
  local rng = G.rng(G.fnv1a(fp .. "#" .. n))
  -- 3.0: the campaign order first (its own random stream), then everything else around it
  local copy = {}
  for k, v in pairs(s) do copy[k] = v end
  s = copy
  s._campaign = nil
  local corder, vanilla_camp
  s._campaign_alt = nil
  if s.hub then
    -- 10.0: the hub's destinations; a location belongs to the visit that holds it
    if not (RANDO_CAMPAIGN and RANDO_CAMPAIGN.hub_destinations) then return nil, "03_rando_campaign.lua (10.0) is missing" end
    local dests = RANDO_CAMPAIGN.hub_destinations()
    local loc_seg = {}
    for _, lid in ipairs(sorted_keys(DB.locations)) do
      local sid = RANDO_CAMPAIGN.location_segment(lid, DB.locations[lid].planet)
      if sid then loc_seg[lid] = sid end
    end
    s._campaign = { hub = true, dests = dests, segments = dests, loc_seg = loc_seg }
  elseif s.campaign_mode ~= "vanilla" or s.travel_lock then
    if not RANDO_CAMPAIGN then return nil, "03_rando_campaign.lua is missing" end
    -- the game's own order: what runs while mission control is not verified (7.0: every
    -- reordered seed must be finishable in it too), and the order a level-locked seed follows
    local ids = {}
    for _, seg in ipairs(RANDO_CAMPAIGN.SEGMENTS) do ids[#ids + 1] = seg.id end
    vanilla_camp = RANDO_CAMPAIGN.build(ids, s, DB.locations)
    -- in the game's own order the story waits for Coordinates only with travel_lock; without it
    -- they hold back a planet's rewards, never its story
    vanilla_camp.planet_locks = s.travel_lock == true
  end
  if s.hub then
    -- (no linear order: the player chooses among the open destinations)
  elseif s.campaign_mode ~= "vanilla" then
    local crng = G.rng(G.fnv1a(fp .. "#campaign#" .. n))
    local why
    corder, why = RANDO_CAMPAIGN.sequence(s.campaign_mode, crng)
    if not corder then return nil, "campaign: " .. tostring(why) end
    s._campaign = RANDO_CAMPAIGN.build(corder, s, DB.locations)
    s._campaign_alt = vanilla_camp
  elseif s.travel_lock then
    s._campaign = vanilla_camp
  end
  local pool = G.location_pool(s)
  local gating = gating_gadgets(s)
  local items, ex = G.item_pool(s, gating)
  local registry = {}                  -- item -> route
  local placement = {}                 -- lid -> item
  local start = {}

  -- start: the two items every seed has
  for _, g in ipairs(G.ALWAYS_START) do start[#start + 1] = g; registry[g] = "start (always)" end
  -- start: Coordinates
  local order = {}
  for _, p in ipairs(DB.planets) do order[#order + 1] = p.id end
  local start_coords = { order[1] }
  if s.start_coordinates == "first_two" then start_coords[2] = order[2]
  elseif s.start_coordinates == "random_extra" then start_coords[2] = order[rng.int(2, #order)] end
  if s._campaign then
    -- the campaign's first visits decide which planets are open at the start
    local seen, list = {}, {}
    for _, seg in ipairs(s._campaign.segments) do
      if not seen[seg.planet] then seen[seg.planet] = true; list[#list + 1] = seg.planet end
    end
    start_coords = { list[1] }
    if s.start_coordinates == "first_two" then start_coords[2] = list[2]
    elseif s.start_coordinates == "random_extra" then start_coords[2] = list[rng.int(2, #list)] end
  end
  if s.travel_lock then
    -- 7.0 levels: the planets the game itself takes you to are open (the randomizer never blocks
    -- the story's own travel), plus the next planet (first_two) or a random later one (random_extra)
    start_coords = RANDO_CAMPAIGN.story_arrival_planets()
    local open = {}
    for _, pid in ipairs(start_coords) do open[pid] = true end
    local later, seen = {}, {}
    for _, seg in ipairs(s._campaign.segments) do
      if not open[seg.planet] and not seen[seg.planet] then seen[seg.planet] = true; later[#later + 1] = seg.planet end
    end
    if s.start_coordinates == "first_two" and later[1] then start_coords[#start_coords + 1] = later[1]
    elseif s.start_coordinates == "random_extra" and #later > 0 then start_coords[#start_coords + 1] = later[rng.int(1, #later)] end
  end
  if s._campaign and not s.travel_lock then
    -- a reordered mission order is played in the game's own order until mission control is
    -- verified: the planets that order begins on (the story's own arrivals) are open too
    local have = {}
    for _, pid in ipairs(start_coords) do have[pid] = true end
    for _, pid in ipairs(RANDO_CAMPAIGN.story_arrival_planets()) do
      if not have[pid] then start_coords[#start_coords + 1] = pid; have[pid] = true end
    end
  end
  if s.hub then start_coords = RANDO_CAMPAIGN.hub_start_planets() end
  if not s.planet_locks then start_coords = {} end
  for _, pid in ipairs(start_coords) do start[#start + 1] = "access:" .. pid; registry["access:" .. pid] = "start" end
  -- a gadget a campaign visit needs that the randomizer will not hand out (gadgets off, or the
  -- gadget excluded): given at the start, so the campaign can always go on
  if s._campaign then
    local in_pool = {}
    for _, it in ipairs(items) do in_pool[it.key] = true end
    local kit = {}
    for _, g in ipairs(DB.start_kit) do kit[g] = true end
    for _, seg in ipairs(s._campaign.segments) do
      for _, r in ipairs(seg.requires) do
        if not r:match("^ability:") and not kit[r] and not in_pool[r] and not registry[r] and DB.items[r] then
          start[#start + 1] = r; registry[r] = "start (the campaign needs it)"
        end
      end
    end
  end
  -- Coordinates excluded from randomization are simply owned from the start
  if s.planet_locks then
    for _, pid in ipairs(order) do
      local key = "access:" .. pid
      if ex[key] and not registry[key] then start[#start + 1] = key; registry[key] = "start (excluded from randomization)" end
    end
  end

  -- start: random weapons and extra gadgets from the pool
  local function take(filter, count)
    local cands = {}
    for i, it in ipairs(items) do if not registry[it.key] and filter(it) then cands[#cands + 1] = i end end
    rng.shuffle(cands)
    for j = 1, math.min(count, #cands) do
      local it = items[cands[j]]
      registry[it.key] = "start"; start[#start + 1] = it.key
    end
  end
  -- 10.0 the weapons are split three ways: the start, the shop and the reward locations. Ms. Zurkon
  -- sells shop_weapons different weapons in her free slots (shuffle); her other free slots are
  -- closed. A slot of an excluded weapon, or every slot of an unshuffled shop, sells its own.
  local slots = G.vendor_weapons()
  local shuffle = s.weapons and s.shop == "shuffle"
  local fixed = {}                     -- slots selling their own weapon (vanilla shop, or excluded)
  for _, k in ipairs(slots) do if not shuffle or ex[k] then fixed[k] = true end end
  local free = {}
  for _, k in ipairs(slots) do if not fixed[k] then free[#free + 1] = k end end
  local function eligible_count()
    local n = 0
    for _, it in ipairs(items) do
      if category(it.key) == "weapon" and not registry[it.key] and not fixed[it.key] and G.shop_eligible(it.key, s) then n = n + 1 end
    end
    return n
  end
  -- 7.0 start_items: items you always start with (from this seed's pool)
  local notes = {}
  for key in s.start_items:gmatch("[^,%s]+") do
    local found
    for _, it in ipairs(items) do if it.key == key then found = it end end
    if registry[key] and registry[key]:sub(1, 5) == "start" then
      -- already there (Hoverboots, Map-O-Matic)
    elseif not found then
      notes[#notes + 1] = "start_items: " .. key .. " is not an item this seed randomizes - ignored"
    elseif category(key) == "weapon" and fixed[key] then
      notes[#notes + 1] = "start_items: " .. key .. " - its shop slot sells it (shop = vanilla or excluded) - ignored"
    else
      registry[key] = "start (chosen)"; start[#start + 1] = key
    end
  end
  -- the shop's sellers: open_n of the free slots, chosen at random; the rest are closed
  local open_n = math.min(#free, s.shop_weapons)
  local elig = eligible_count()
  if open_n > elig then
    notes[#notes + 1] = string.format("shop_weapons lowered to %d: only %d weapons can be sold in this seed", elig, elig)
    open_n = elig
  end
  local shop_slots, closed = {}, {}
  for _, k in ipairs(slots) do if fixed[k] then shop_slots[k] = k; registry[k] = registry[k] or "shop" end end
  if open_n > 0 then
    local cands = {}
    for _, it in ipairs(items) do
      if category(it.key) == "weapon" and not registry[it.key] and G.shop_eligible(it.key, s) then cands[#cands + 1] = it.key end
    end
    rng.shuffle(cands)
    local sellers = {}
    for j = 1, open_n do sellers[j] = cands[j] end
    local open = {}
    for _, k in ipairs(free) do open[#open + 1] = k end
    rng.shuffle(open)
    for j = #open, open_n + 1, -1 do closed[#closed + 1] = open[j]; open[j] = nil end
    table.sort(open)
    -- a derangement when one exists (a slot selling its own weapon is avoided)
    for _ = 1, 50 do
      rng.shuffle(sellers)
      local own = false
      for i, k in ipairs(open) do if sellers[i] == k then own = true; break end end
      if not own then break end
    end
    for i, k in ipairs(open) do shop_slots[k] = sellers[i]; registry[sellers[i]] = "shop" end
  else
    for _, k in ipairs(free) do closed[#closed + 1] = k end
  end
  table.sort(closed)
  s._shop_closed = closed
  -- start weapons: any weapon the shop does not sell
  local wleft = 0
  for _, it in ipairs(items) do if category(it.key) == "weapon" and not registry[it.key] then wleft = wleft + 1 end end
  local start_w = math.max(0, math.min(s.start_weapons, wleft))
  if start_w < s.start_weapons then s._start_short = start_w end
  take(function(it) return category(it.key) == "weapon" and not fixed[it.key] end, start_w)
  take(function(it) return category(it.key) == "gadget" end, s.start_gadgets)
  s._shop_slots = shop_slots
  -- 7.0 prices: what each of the 15 slots costs (nil: every slot keeps the game's own price).
  -- Rounded to 50 Bolts. Their own random stream, so prices never move the placements.
  local prices
  if s.shop_prices ~= "vanilla" then
    prices = {}
    local prng = G.rng(G.fnv1a(fp .. "#prices#" .. n))
    for _, k in ipairs(slots) do
      local base = DB.items[k].price or 0
      local sold = shop_slots[k]
      local v
      if s.shop_prices == "weapon" then v = (DB.items[sold] and DB.items[sold].price) or base
      elseif s.shop_prices == "percent" then v = base * s.shop_price_percent / 100
      else v = base * prng.int(s.shop_price_percent, s.shop_price_max_percent) / 100 end
      v = round_to(v, 50)
      prices[k] = math.tointeger(v) or math.floor(v)
    end
  end
  s._shop_prices = prices
  -- the shop's weapons are not rewards
  local kept = {}
  for _, it in ipairs(items) do if registry[it.key] ~= "shop" then kept[#kept + 1] = it end end
  items = kept
  -- weapon logic needs a number of weapons, not particular ones: only that many (beyond the
  -- starting weapons) are progression items, the rest are ordinary rewards
  if s.weapon_logic ~= "none" then
    local need = G.weapons_needed(s, #DB.planets)
    for _, k in ipairs(start) do if k:sub(1, 7) == "weapon:" then need = need - 1 end end
    local ws = {}
    for _, it in ipairs(items) do if not registry[it.key] and category(it.key) == "weapon" then ws[#ws + 1] = it end end
    rng.shuffle(ws)
    for j, it in ipairs(ws) do it.class = (j <= need) and "progression" or "useful" end
  end
  for _, g in ipairs(DB.start_kit) do if DB.items[g] then registry[g] = "start (game kit)" end end
  for _, g in ipairs(G.GAME_GIVEN) do if DB.items[g] then registry[g] = "start (game kit)" end end

  local bolts = {}
  for _, loc in ipairs(pool) do if loc.kind == "goldbolt" then bolts[#bolts + 1] = loc.id end end
  local function free_locations(reach, logic_only)
    local out = {}
    for _, loc in ipairs(pool) do
      if not placement[loc.id] and (not logic_only or (loc.in_logic and reach[loc.id])) then
        out[#out + 1] = loc.id
      end
    end
    return out
  end
  if s.distribution == "spread" then
    -- 1) early weapons first: locations you can reach with the start alone get early_weapons weapons
    --    (weapons that are not progression; the progression fill below works around them)
    local first = G.solve(s, pool, {}, start, nil).spheres[1] or {}
    local early = {}
    for _, lid in ipairs(first) do
      if not placement[lid] and DB.locations[lid].holds ~= "filler" then early[#early + 1] = lid end
    end
    rng.shuffle(early)
    local ws = {}
    for _, it in ipairs(items) do
      if not registry[it.key] and category(it.key) == "weapon" and it.class ~= "progression" then ws[#ws + 1] = it.key end
    end
    rng.shuffle(ws)
    local used = 0
    for j = 1, math.min(s.early_weapons, #ws, #early) do
      placement[early[j]] = ws[j]; registry[ws[j]] = "location"; used = j
    end
    -- and one Coordinates there, so the first planet beyond the start comes early (any Coordinates
    -- may go to a location the start reaches: it needs nothing)
    if s.planet_locks and early[used + 1] then
      local cs = {}
      for _, it in ipairs(items) do if not registry[it.key] and category(it.key) == "coordinates" then cs[#cs + 1] = it.key end end
      if #cs > 0 then
        local key = cs[rng.below(#cs) + 1]
        placement[early[used + 1]] = key; registry[key] = "location"
      end
    end
    -- 10.0 SPREAD. 2) progression (Coordinates, gadgets a location needs; weapons with weapon_logic)
    -- by assumed fill: each goes to a location reachable with everything not yet placed assumed
    -- owned, any kind of location, no preference for late ones (an early find may open a planet)
    local prog = {}
    for _, it in ipairs(items) do if not registry[it.key] and it.class == "progression" then prog[#prog + 1] = it.key end end
    rng.shuffle(prog)
    table.sort(prog, function(a, b)
      local ca, cb = category(a) == "coordinates", category(b) == "coordinates"
      if ca ~= cb then return ca end
      return false
    end)
    while #prog > 0 do
      local key = table.remove(prog)
      local res = G.solve(s, pool, placement, start, prog)
      local spots = {}
      for _, lid in ipairs(free_locations(res.reachable, true)) do
        if DB.locations[lid].holds ~= "filler" then spots[#spots + 1] = lid end
      end
      if #spots == 0 then return nil, "no reachable location left for " .. key end
      local lid = rng.pick(spots)
      placement[lid] = key; registry[key] = "location"
      if yield then yield() end
    end
    -- 3) everything else, shared out over the kinds of location in proportion to their number
    --    (largest remainder), then at random within each kind. Armor pods (anywhere) take part.
    local left = {}
    for _, it in ipairs(items) do if not registry[it.key] then left[#left + 1] = it.key end end
    rng.shuffle(left)
    local by_kind, kinds, nfree = {}, {}, 0
    for _, lid in ipairs(free_locations(nil, false)) do
      if DB.locations[lid].holds ~= "filler" then
        local k = DB.locations[lid].kind
        if not by_kind[k] then by_kind[k] = {}; kinds[#kinds + 1] = k end
        table.insert(by_kind[k], lid)
        nfree = nfree + 1
      end
    end
    table.sort(kinds)
    local take_n = math.min(#left, nfree)
    local quota, given, rems = {}, 0, {}
    for _, k in ipairs(kinds) do
      local exact = take_n * #by_kind[k] / math.max(1, nfree)
      quota[k] = math.floor(exact)
      given = given + quota[k]
      rems[#rems + 1] = { k = k, r = exact - quota[k] }
    end
    G.stable_sort(rems, function(x, y) return x.r > y.r end)
    for i = 1, take_n - given do quota[rems[i].k] = quota[rems[i].k] + 1 end
    local spots = {}
    for _, k in ipairs(kinds) do
      rng.shuffle(by_kind[k])
      for j = 1, quota[k] do spots[#spots + 1] = by_kind[k][j] end
    end
    rng.shuffle(spots)
    for i, key in ipairs(left) do
      if spots[i] then placement[spots[i]] = key; registry[key] = "location"
      elseif category(key) == "weapon" then
        -- more items than locations (few location kinds switched on): a weapon still needs its
        -- one route, so it starts with you
        start[#start + 1] = key; registry[key] = "start (no location left)"
        notes[#notes + 1] = "too few locations: " .. key .. " is given at the start"
      else registry[key] = "excluded (no location left)" end
    end
  else
    local worthy = 0
    for _, it in ipairs(items) do if not registry[it.key] and G.bolt_worthy(it.key) then worthy = worthy + 1 end end
    if worthy < #bolts then
      return nil, string.format("too few items for one per Gold Bolt: %d items for %d Gold Bolts", worthy, #bolts)
    end

    -- progression fill (assumed fill): each item goes to a location reachable with everything
    -- not yet placed assumed owned
    local prog = {}
    for _, it in ipairs(items) do if not registry[it.key] and it.class == "progression" then prog[#prog + 1] = it.key end end
    rng.shuffle(prog)
    -- coordinates first: they open the most
    table.sort(prog, function(a, b)
      local ca, cb = category(a) == "coordinates", category(b) == "coordinates"
      if ca ~= cb then return ca end
      return false
    end)
    local function free_locations(reach, logic_only)
      local out = {}
      for _, loc in ipairs(pool) do
        if not placement[loc.id] and (not logic_only or (loc.in_logic and reach[loc.id])) then
          out[#out + 1] = loc.id
        end
      end
      return out
    end
    -- Gold Bolts can only take grantable items; count how many Gold Bolts are still free, so the
    -- progression fill never uses up the items they need
    local function bolts_free()
      local c = 0
      for _, lid in ipairs(bolts) do if not placement[lid] then c = c + 1 end end
      return c
    end
    -- v0.5: hub seeds keep 10.0's early_weapons and early Coordinates with goldbolts_first too.
    -- Gold Bolts the start reaches are used first (they need an item anyway); another location the
    -- start reaches is used only while a spare grantable item is left, so every Gold Bolt still gets
    -- an item. Non-hub seeds are unchanged.
    local early_placed = 0
    if s.hub then
      local first = G.solve(s, pool, {}, start, nil).spheres[1] or {}
      local gb_first, other_first = {}, {}
      for _, lid in ipairs(first) do
        if not placement[lid] and DB.locations[lid].holds ~= "filler" then
          if DB.locations[lid].kind == "goldbolt" then gb_first[#gb_first + 1] = lid
          else other_first[#other_first + 1] = lid end
        end
      end
      rng.shuffle(gb_first); rng.shuffle(other_first)
      local spare = worthy - #bolts
      local function early_spot()
        if #gb_first > 0 then return table.remove(gb_first) end
        if spare > 0 and #other_first > 0 then spare = spare - 1; return table.remove(other_first) end
        return nil
      end
      local ws = {}
      for _, it in ipairs(items) do
        if not registry[it.key] and category(it.key) == "weapon" and it.class ~= "progression" and G.bolt_worthy(it.key) then
          ws[#ws + 1] = it.key
        end
      end
      rng.shuffle(ws)
      for j = 1, math.min(s.early_weapons, #ws) do
        local lid = early_spot()
        if not lid then break end
        placement[lid] = ws[j]; registry[ws[j]] = "location"; early_placed = early_placed + 1
      end
      if s.planet_locks and s.early_weapons > 0 then
        local cs = {}
        for _, it in ipairs(items) do if not registry[it.key] and category(it.key) == "coordinates" then cs[#cs + 1] = it.key end end
        if #cs > 0 then
          local lid = early_spot()
          if lid then
            local key = cs[rng.below(#cs) + 1]
            placement[lid] = key; registry[key] = "location"; early_placed = early_placed + 1
            for j = #prog, 1, -1 do if prog[j] == key then table.remove(prog, j) end end
          end
        end
      end
    end

    local base = G.solve(s, pool, placement, start, nil).reachable
    local worthy_left = worthy - early_placed
    while #prog > 0 do
      local key = table.remove(prog)
      local assumed = {}
      for _, k in ipairs(prog) do assumed[#assumed + 1] = k end
      local res = G.solve(s, pool, placement, start, assumed)
      local spots = free_locations(res.reachable, true)
      -- a non-grantable progression item (none today) never goes on a Gold Bolt
      if not G.bolt_worthy(key) then
        local keep = {}
        for _, lid in ipairs(spots) do if DB.locations[lid].kind ~= "goldbolt" then keep[#keep + 1] = lid end end
        spots = keep
      elseif worthy_left - 1 < bolts_free() then
        -- every remaining grantable item is needed by a Gold Bolt: this one must take one
        local keep = {}
        for _, lid in ipairs(spots) do if DB.locations[lid].kind == "goldbolt" then keep[#keep + 1] = lid end end
        spots = keep
      end
      if #spots == 0 then return nil, "no reachable location left for " .. key end
      local deep = {}
      for _, lid in ipairs(spots) do if not base[lid] then deep[#deep + 1] = lid end end
      if #deep > 0 and #spots - #deep <= #prog then spots = deep end
      local lid = rng.pick(spots)
      placement[lid] = key; registry[key] = "location"
      if G.bolt_worthy(key) then worthy_left = worthy_left - 1 end
      if yield then yield() end
    end

    -- every Gold Bolt still empty gets one grantable item (weapons and gadgets first, armor last)
    local rest = {}
    for _, it in ipairs(items) do if not registry[it.key] then rest[#rest + 1] = it.key end end
    rng.shuffle(rest)
    local ordered = {}
    for _, key in ipairs(rest) do if category(key) ~= "armor" then ordered[#ordered + 1] = key end end
    for _, key in ipairs(rest) do if category(key) == "armor" then ordered[#ordered + 1] = key end end
    local free_bolts = {}
    for _, lid in ipairs(bolts) do if not placement[lid] then free_bolts[#free_bolts + 1] = lid end end
    rng.shuffle(free_bolts)
    local left = {}
    for _, key in ipairs(ordered) do
      if #free_bolts > 0 and G.bolt_worthy(key) then
        local lid = table.remove(free_bolts)
        placement[lid] = key; registry[key] = "location"
      else
        left[#left + 1] = key
      end
    end
    if #free_bolts > 0 then return nil, "Gold Bolt left without an item: " .. free_bolts[1] end
    rng.shuffle(left)

    -- the rest: the first story mission of each planet first, then every other mission, side
    -- activity and armor source at random (in-logic first). Filler-only armor sources (the two
    -- of three folders that are Robot Disguise and Wasteland Gear) never take an item.
    local free = {}
    for _, lid in ipairs(free_locations(nil, false)) do
      if DB.locations[lid].holds ~= "filler" then free[#free + 1] = lid end
    end
    rng.shuffle(free)
    G.stable_sort(free, function(a, b)
      local ka, kb = KIND_RANK[DB.locations[a].kind] or 9, KIND_RANK[DB.locations[b].kind] or 9
      return ka < kb
    end)
    local fi = 1
    for _, key in ipairs(left) do
      if fi > #free and category(key) == "weapon" then
        -- 10.0: a weapon keeps its one route even when the locations run out
        start[#start + 1] = key; registry[key] = "start (no location left)"
        notes[#notes + 1] = "too few locations: " .. key .. " is given at the start"
      elseif fi > #free then registry[key] = "excluded (no location left)" else
        placement[free[fi]] = key; registry[key] = "location"; fi = fi + 1
      end
    end
  end
  -- 7.0 currency: every other location gives Bolts or Raritanium, each its own amount (none
  -- with bolts = false and raritanium = false). Its own random stream: currency never moves items.
  local cur_lids = {}
  for _, loc in ipairs(pool) do
    if not placement[loc.id] and (loc.kind ~= "goldbolt" or s.distribution == "spread") then cur_lids[#cur_lids + 1] = loc.id end
  end
  local amounts, totals, cnotes = G.currency_amounts(s, cur_lids, G.rng(G.fnv1a(fp .. "#currency#" .. n)))
  for lid, key in pairs(amounts) do placement[lid] = key end
  for _, m in ipairs(cnotes) do notes[#notes + 1] = m end
  for key in pairs(ex) do if DB.items[key] and not registry[key] then registry[key] = "excluded (setting)" end end
  for _, g in ipairs(G.ALWAYS_START) do registry[g] = "start (always)" end

  -- verification: the whole playthrough
  local res = G.solve(s, pool, placement, start, nil)
  if s._campaign and res.campaign_reach < #s._campaign.segments then
    return nil, "campaign cannot be finished: stops after visit " .. res.campaign_reach .. " (" .. tostring(res.campaign_block) .. ")"
  end
  -- 7.0: a reordered mission order is played in the game's own order until mission control is
  -- verified, so the seed must be finishable that way too (every location, every visit)
  if s._campaign and vanilla_camp and s._campaign ~= vanilla_camp then
    local keep, keep_alt = s._campaign, s._campaign_alt
    s._campaign, s._campaign_alt = vanilla_camp, nil
    local fres = G.solve(s, pool, placement, start, nil)
    s._campaign, s._campaign_alt = keep, keep_alt
    if fres.campaign_reach < #vanilla_camp.segments then
      return nil, "not finishable in the game's own order: stops after visit " .. fres.campaign_reach .. " (" .. tostring(fres.campaign_block) .. ")"
    end
    for _, loc in ipairs(pool) do
      if loc.in_logic and not fres.reachable[loc.id] and (s.accessibility == "full" or loc.kind == "planet") then
        return nil, "location not reachable in the game's own order: " .. loc.id
      end
    end
  end
  for _, it in ipairs(items) do
    if registry[it.key] == "location" and it.class == "progression" and (res.owned[it.key] or 0) == 0 then
      return nil, "progression item not reachable: " .. it.key
    end
  end
  for _, loc in ipairs(pool) do
    if loc.in_logic and not res.reachable[loc.id] then
      if s.accessibility == "full" or loc.kind == "planet" then return nil, "location not reachable: " .. loc.id end
    end
  end
  if s.distribution ~= "spread" then
    for _, lid in ipairs(bolts) do
      if not (placement[lid] and G.bolt_worthy(placement[lid])) then return nil, "Gold Bolt without a grantable item: " .. lid end
    end
  end
  return {
    pool = pool, placement = placement, registry = registry, start = start,
    solve = res, attempt = n, campaign = corder, shop_slots = s._shop_slots, start_short = s._start_short,
    shop_prices = s._shop_prices, currency_totals = totals, notes = notes,
    start_coords = start_coords, shop_closed = s._shop_closed,
    hub_route = res.hub_route, hub_first = res.hub_first,
  }
end

-- Generates a seed. settings: the user's table (seed, preset and options). Returns the seed
-- table, or nil and the reasons. yield (optional) is called now and then (in-game slicing).
function G.generate(seed_text, user, preset, yield)
  seed_text = tostring(seed_text or "")
  if seed_text == "" then return nil, "empty seed" end
  local s, warnings = G.normalize(user, preset)
  local fp = G.fingerprint(seed_text, s)
  local errors = {}
  -- settings that leave too few locations: the logic is relaxed (said in the warnings and the
  -- spoiler log) rather than the seed failing
  local eff = {}
  for k, v in pairs(s) do eff[k] = v end
  local n = 0
  while true do
    for _ = 1, 30 do
      n = n + 1
      local r, err = attempt(seed_text, eff, fp, n, yield)
      if r then
        if r.start_short then
          warnings[#warnings + 1] = string.format("start_weapons lowered to %d: no other weapon is left once the shop has its shop_weapons", r.start_short)
        end
        for _, m in ipairs(r.notes or {}) do warnings[#warnings + 1] = m end
        return G.package(seed_text, eff, preset, fp, r, warnings, s)
      end
      errors[#errors + 1] = err
      if tostring(err):match("^too few items for one per Gold Bolt") then
        if not eff.armor then
          -- 5.0: armor pieces are items too (the vendor's weapons never are)
          eff.armor = true
          warnings[#warnings + 1] = "armor turned on: without armor pieces these settings have " .. err:match(": (.*)$")
          break
        elseif eff.start_gadgets > 0 or eff.start_weapons > 0 then
          -- 8.5.2: fewer items at the start leaves more for the Gold Bolts (this comes before
          -- Coordinates as items)
          local k = eff.start_gadgets > 0 and "start_gadgets" or "start_weapons"
          eff[k] = eff[k] - 1
          warnings[#warnings + 1] = k .. " lowered to " .. eff[k] .. ": these settings have " .. err:match(": (.*)$")
          break
        elseif not eff.planet_locks then
          -- Coordinates are items too: with them the pool covers every Gold Bolt
          eff.planet_locks = true
          warnings[#warnings + 1] = "planet_locks turned on: without Coordinates these settings have " .. err:match(": (.*)$")
          break
        end
        return nil, err .. " - turn weapons/gadgets on, include ARSENAL_RESTORED's weapons, or start with fewer items", errors
      end
      if yield then yield() end
    end
    local room = 0
    if tostring(errors[#errors]):match("^too few items for one per Gold Bolt") then goto continue end
    for i = math.max(1, #errors - 29), #errors do
      if tostring(errors[i]):match("^no reachable location left") or tostring(errors[i]):match("not reachable")
         or tostring(errors[i]):match("needs weapons") or tostring(errors[i]):match("not finishable")
         or tostring(errors[i]):match("cannot be finished") then room = room + 1 end
    end
    if room > 0 and eff.hub and eff.distribution ~= "spread" and eff.early_weapons > 0 then
      -- v0.5: the Gold Bolts the start reaches cannot hold the early items and still leave room for
      -- the progression (few items, e.g. armor off): fewer early weapons (at 0, no early Coordinates)
      local was = eff.early_weapons
      eff.early_weapons = was - 1
      warnings[#warnings + 1] = "early_weapons lowered from " .. was .. " to " .. eff.early_weapons .. ": every Gold Bolt needs an item and too few are left with these settings"
    elseif room > 0 and eff.weapon_logic ~= "none" then
      -- too few locations for the weapons the logic asks for: ask for fewer
      local was = eff.weapon_logic
      eff.weapon_logic = (was == "standard") and "light" or "none"
      warnings[#warnings + 1] = "weapon_logic lowered from " .. was .. " to " .. eff.weapon_logic .. ": too few locations with these settings"
    elseif room > 0 and eff.planet_locks and not eff.hub and eff.start_coordinates ~= "random_extra" then
      -- too few locations to chain every planet's Coordinates: start with one more planet open
      local was = eff.start_coordinates
      eff.start_coordinates = (was == "start_only") and "first_two" or "random_extra"
      warnings[#warnings + 1] = "start_coordinates raised from " .. was .. " to " .. eff.start_coordinates .. ": too few locations with these settings"
    elseif room > 0 and eff.planet_locks and not eff.hub then
      -- last resort: too few reward locations to chain every planet's Coordinates
      eff.planet_locks = false
      eff.travel_lock = false
      warnings[#warnings + 1] = "planet_locks (levels) turned off: too few reward locations to chain every planet's Coordinates with these settings"
    else
      break
    end
    ::continue::
  end
  return nil, "no valid placement after " .. n .. " attempts: " .. tostring(errors[#errors]), errors
end

local function names(key)
  if key == "-" then return "(nothing)" end
  local fk, n = G.parse_filler(key)
  if fk then
    local f = DB.filler and DB.filler[fk]
    return string.format("%d %s", n, f and f.name or fk)
  end
  return DB.items[key] and DB.items[key].name or key
end
G.item_name = names

function G.package(seed_text, s, preset, fp, r, warnings, requested)
  local locs = {}
  for _, loc in ipairs(r.pool) do
    locs[loc.id] = { item = r.placement[loc.id], in_logic = loc.in_logic }
  end
  local sphere_of = {}
  for i, sp in ipairs(r.solve.spheres) do for _, lid in ipairs(sp) do sphere_of[lid] = i end end
  -- the Gold Bolts in order, for the spoiler and the runtime ("Gold Bolt 1 -> ...")
  local bolts = {}
  for _, lid in ipairs(sorted_keys(locs)) do
    if DB.locations[lid].kind == "goldbolt" then bolts[#bolts + 1] = lid end
  end
  -- 7.0 levels: when each planet opens (its Coordinates' sphere; 0 = open from the start)
  local levels
  if s.planet_locks then
    levels = { travel_lock = s.travel_lock == true, open_at_start = {}, unlock = {} }
    for _, k in ipairs(r.start) do
      local it = DB.items[k]
      if it and it.category == "coordinates" then levels.open_at_start[#levels.open_at_start + 1] = it.planet end
    end
    for _, lid in ipairs(sorted_keys(locs)) do
      local it = locs[lid].item and DB.items[locs[lid].item]
      if it and it.category == "coordinates" then
        levels.unlock[#levels.unlock + 1] = { planet = it.planet, at = lid, sphere = sphere_of[lid] or 0 }
      end
    end
    G.stable_sort(levels.unlock, function(a, b) return a.sphere < b.sphere end)
  end
  -- 10.0: the hub's plan (destinations, the start choices, one route the solver found)
  local hub
  if s.hub then
    local route = {}
    for _, id in ipairs(r.hub_route or {}) do route[#route + 1] = id end
    hub = { planet = RANDO_CAMPAIGN.HUB_PLANET, checkpoints = RANDO_CAMPAIGN.HUB_CHECKPOINTS,
            start = RANDO_CAMPAIGN.HUB_START, destinations = RANDO_CAMPAIGN.hub_destinations(),
            route = route, finale_planet = RANDO_CAMPAIGN.BY_ID.finale.planet }
  end
  return {
    format = 10, generator = G.VERSION, data = DB.version, hub = hub,
    seed = seed_text, preset = preset or "balanced", fingerprint = fp, settings = s,
    share_code = G.share_code(seed_text, requested or s, preset), warnings = warnings,
    start = { items = r.start, always = G.ALWAYS_START, bolts = s.start_bolts, raritanium = s.start_raritanium },
    locations = locs, registry = r.registry, gold_bolts = bolts,
    spheres = r.solve.spheres, sphere_of = sphere_of, attempt = r.attempt,
    planet_locks = s.planet_locks, travel_lock = s.travel_lock == true, levels = levels,
    -- 6.0: vendor slot -> weapon it sells; 7.0: vendor slot -> price (nil: the game's prices)
    shop = { mode = (s.weapons and s.shop) or "vanilla", slots = r.shop_slots, prices = r.shop_prices,
             price_mode = s.shop_prices, closed = r.shop_closed or {} },
    armor = s.armor,
    filler = { kinds = G.filler_kinds(s), bolts = { s.bolts_min, s.bolts_max }, raritanium = { s.raritanium_min, s.raritanium_max },
               totals = r.currency_totals },
    campaign = (r.campaign and { mode = s.campaign_mode, order = r.campaign, start = r.campaign[1],
                                 needs = RANDO_CAMPAIGN.NEEDS[s.campaign_mode] })
               or (s.hub and { mode = "hub" }) or { mode = "vanilla" },
    restored_weapons = s.include_arsenal_restored == true,
  }
end

-- ------------------------------------------------------------------------------------------
-- checks used by the tests and the batch validator (independent of the generator's own path)
-- ------------------------------------------------------------------------------------------
function G.audit(seed)
  local problems = {}
  local function bad(msg) problems[#problems + 1] = msg end
  local s = seed.settings
  -- one route per item
  local seen = {}
  local function note(key, where)
    if seen[key] then bad(key .. " placed twice: " .. seen[key] .. " and " .. where) end
    seen[key] = where
  end
  for _, k in ipairs(seed.start.items) do note(k, "start") end
  local fkinds = {}
  for _, k in ipairs(G.filler_kinds(s)) do fkinds[k] = true end
  local ctotal = { bolts = 0, raritanium = 0 }
  local ccount = { bolts = 0, raritanium = 0 }
  for _, lid in ipairs(sorted_keys(seed.locations)) do
    local it = seed.locations[lid].item
    local loc = DB.locations[lid]
    local kind = loc and loc.kind
    local fk, amount = G.parse_filler(it)
    if fk then
      -- currency repeats; only the currencies switched on, inside the range (10.0: a Gold Bolt may
      -- give currency with distribution = "spread")
      if kind == "goldbolt" and s.distribution ~= "spread" then bad(lid .. " holds currency") end
      if not fkinds[fk] then bad(lid .. " holds " .. it .. " but " .. fk .. " = false")
      else
        if amount < s[fk .. "_min"] or amount > s[fk .. "_max"] then
          bad(string.format("%s gives %d %s, outside %d-%d", lid, amount, fk, s[fk .. "_min"], s[fk .. "_max"]))
        end
        ctotal[fk] = ctotal[fk] + amount; ccount[fk] = ccount[fk] + 1
      end
    elseif it then
      note(it, lid)
      local item = DB.items[it]
      if not item then bad(lid .. " holds an unknown item " .. tostring(it))
      else
          if item.category == "armor" and not s.armor then bad(lid .. " holds armor with armor = false") end
        if item.category == "currency" then bad(lid .. " holds currency as an item") end
      end
      if loc and loc.holds == "filler" then bad(lid .. " is a filler-only armor source but holds " .. it) end
    elseif (kind ~= "goldbolt" or s.distribution == "spread") and #G.filler_kinds(s) > 0 then
      bad(lid .. " holds nothing although currency rewards are on")
    end
    if kind == "armor_source" and not s.armor then bad(lid .. " is an armor source with armor = false") end
  end
  -- 7.0 the currency budget: the total stays within it, unless the minimum alone is above it
  for _, fk in ipairs({ "bolts", "raritanium" }) do
    local budget = s[fk .. "_budget"]
    if budget > 0 and ctotal[fk] > math.max(budget, ccount[fk] * s[fk .. "_min"]) then
      bad(string.format("%s rewards total %d, above the budget %d", fk, ctotal[fk], budget))
    end
    local reported = seed.filler and seed.filler.totals and seed.filler.totals[fk]
    if reported ~= ctotal[fk] then bad(fk .. " total reported " .. tostring(reported) .. ", counted " .. ctotal[fk]) end
  end
  if seed.start.bolts ~= s.start_bolts or seed.start.raritanium ~= s.start_raritanium then bad("start currency differs from the settings") end
  -- 7.0 prices: every slot priced (whole Bolts, 0 or more) unless prices are the game's own
  if s.shop_prices == "vanilla" then
    if seed.shop.prices then bad("shop_prices = vanilla but the seed sets prices") end
  else
    for _, k in ipairs(G.vendor_weapons()) do
      local p = seed.shop.prices and seed.shop.prices[k]
      if math.type(p) ~= "integer" or p < 0 then bad("the vendor slot of " .. k .. " has no valid price (" .. tostring(p) .. ")") end
    end
  end
  -- 7.0 levels: travel locks need Coordinates; the story's own arrivals are open from the start
  -- (10.0 hub: exactly the planets of the three starting missions)
  local open = {}
  for _, k in ipairs(seed.start.items) do if k:match("^access:") then open[k:sub(8)] = true end end
  if s.travel_lock then
    if not s.planet_locks then bad("travel_lock without planet_locks") end
    local want = s.hub and RANDO_CAMPAIGN.hub_start_planets() or RANDO_CAMPAIGN.story_arrival_planets()
    for _, pid in ipairs(want) do
      if not open[pid] then bad("levels: " .. pid .. " is not open from the start") end
    end
  end
  -- 10.0 the hub: planet locks and travel locks on, the three starting planets and no other open,
  -- every destination in the solver's route, the finale last
  if s.hub then
    if not (s.planet_locks and s.travel_lock) then bad("hub seed without Coordinates and locked travel") end
    local starts = {}
    for _, pid in ipairs(RANDO_CAMPAIGN.hub_start_planets()) do starts[pid] = true end
    local exs = excluded_set(s)
    for pid in pairs(open) do
      if not starts[pid] and not exs["access:" .. pid] and seed.registry["access:" .. pid] ~= "start (chosen)" then
        bad("hub: " .. pid .. " is open from the start")
      end
    end
    local h = seed.hub
    if not h then bad("hub = true but the seed has no hub plan")
    else
      local ids, seen_r = {}, {}
      for _, d in ipairs(h.destinations or {}) do ids[d.id] = true end
      for _, id in ipairs(h.route or {}) do
        if seen_r[id] then bad("hub route: " .. id .. " twice") end
        seen_r[id] = true
      end
      for id in pairs(ids) do if not seen_r[id] then bad("hub: destination " .. id .. " is never reachable") end end
      if (h.route or {})[#(h.route or {})] ~= "finale" then bad("hub: the finale is not the last destination of the route") end
      for i, id in ipairs(RANDO_CAMPAIGN.HUB_START) do
        if h.start[i] ~= id then bad("hub: the starting missions are not " .. table.concat(RANDO_CAMPAIGN.HUB_START, ", ")) end
      end
      local reach = RANDO_CAMPAIGN.hub_reach(h.destinations, (function()
        local o = {}
        for _, k in ipairs(seed.start.items) do o[k] = 1 end
        return o
      end)(), (function()
        local k = {}
        for _, g in ipairs(DB.start_kit) do k[g] = true end
        return k
      end)())
      for _, id in ipairs(RANDO_CAMPAIGN.HUB_START) do
        if not reach[id] then bad("hub: the starting mission " .. id .. " cannot be played with the start") end
      end
    end
  elseif seed.hub then
    bad("a hub plan in a seed without hub = true")
  end
  if seed.campaign and seed.campaign.order then
    for i, id in ipairs(RANDO_CAMPAIGN.STORY_START) do
      if seed.campaign.order[i] ~= id then bad("the campaign order does not start with " .. table.concat(RANDO_CAMPAIGN.STORY_START, " > ")) end
    end
  end
  -- 6.0 the shop: every vendor slot sells one weapon, no weapon twice, none also elsewhere
  -- (10.0: or is closed; at most shop_weapons sell a weapon other than their own; no
  -- ARSENAL_RESTORED weapon is sold)
  local sold = {}
  local closed = {}
  for _, k in ipairs((seed.shop and seed.shop.closed) or {}) do
    if closed[k] then bad("the vendor slot of " .. k .. " is closed twice") end
    closed[k] = true
    if seed.shop.slots and seed.shop.slots[k] then bad("the vendor slot of " .. k .. " is closed and sells " .. seed.shop.slots[k]) end
    if seed.shop.mode ~= "shuffle" then bad("an unshuffled shop closes " .. k) end
  end
  local moved = 0
  for _, k in ipairs(G.vendor_weapons()) do
    local w = seed.shop and seed.shop.slots and seed.shop.slots[k]
    if closed[k] then
      -- closed: sells nothing the seed routes
    elseif not w then bad("the vendor slot of " .. k .. " sells nothing")
    else
      if not (seed.shop.mode ~= "shuffle" or excluded_set(s)[k]) then moved = moved + 1 end
      if DB.items[w] and DB.items[w].acquisition == "arsenal_restored" then bad(w .. " (ARSENAL_RESTORED) is sold in the shop") end
      if sold[w] then bad(w .. " is sold in two vendor slots") end
      sold[w] = k
      if not (G.in_weapon_pool(w, s) or w == k) then bad(w .. " is sold but is not in the weapon pool") end
      if seen[w] then bad(w .. " is sold in the shop and also at " .. seen[w]) end
      if seed.shop.mode ~= "shuffle" and w ~= k then bad("an unshuffled shop moves " .. k) end
    end
  end
  -- every weapon of the pool has exactly one route (start, a vendor slot, a location), unless excluded
  local exs = excluded_set(s)
  for _, key in ipairs(sorted_keys(DB.items)) do
    local it = DB.items[key]
    if it.category == "weapon" then
      local routes = (sold[key] and 1 or 0) + (seen[key] and 1 or 0)
      if G.in_weapon_pool(key, s) and s.weapons and not exs[key] and routes ~= 1 then
        bad(key .. " has " .. routes .. " routes (start, shop, location)")
      end
      if not G.in_weapon_pool(key, s) and seen[key] then bad(key .. " (" .. tostring(it.acquisition) .. ") is placed") end
      if not G.in_weapon_pool(key, s) and sold[key] and sold[key] ~= key then bad(key .. " is sold in another slot") end
    end
  end
  if seed.shop.mode == "shuffle" and moved > s.shop_weapons then bad(moved .. " vendor slots sell a seed weapon, above shop_weapons " .. s.shop_weapons) end
  for _, key in ipairs(sorted_keys(seed.registry)) do
    local route = seed.registry[key]
    if route == "location" and not (seen[key] and seen[key] ~= "start") then bad(key .. " registered at a location but not placed") end
  end
  -- every item placed must be registered with that route
  for key, where in pairs(seen) do
    local route = seed.registry[key]
    local want = where == "start" and "start" or "location"
    if not route or route:sub(1, #want) ~= want then bad(key .. " is at " .. where .. " but registered as " .. tostring(route)) end
  end
  -- 4.0: Hoverboots and the Map-O-Matic always start; every Gold Bolt holds one grantable item
  -- (10.0 spread: a grantable item or currency)
  for _, g in ipairs(G.ALWAYS_START) do
    if seen[g] ~= "start" then bad(g .. " is not in the starting inventory (" .. tostring(seen[g]) .. ")") end
  end
  local nbolts = 0
  for _, lid in ipairs(sorted_keys(DB.locations)) do
    if DB.locations[lid].kind == "goldbolt" then
      nbolts = nbolts + 1
      local l = seed.locations[lid]
      if not l then bad(lid .. " is not a reward location")
      elseif not l.item then
        if s.distribution ~= "spread" or #G.filler_kinds(s) > 0 then bad(lid .. " holds nothing") end
      elseif not G.bolt_worthy(l.item) and not (s.distribution == "spread" and G.parse_filler(l.item)) then
        bad(lid .. " holds " .. l.item .. ", which cannot be handed over")
      end
    end
  end
  if nbolts ~= 25 then bad("the game has 25 Gold Bolts, the data has " .. nbolts) end
  -- 10.0 spread: the start's own reach holds early_weapons weapons (as many as the seed has left)
  -- (with weapon_logic the weapons the logic counts are progression and go where the fill puts them)
  if s.distribution == "spread" and s.weapon_logic == "none" and seed.spheres and seed.spheres[1] then
    local early_w, reward_w = 0, 0
    for _, lid in ipairs(seed.spheres[1]) do
      local it = seed.locations[lid] and seed.locations[lid].item
      if it and DB.items[it] and DB.items[it].category == "weapon" then early_w = early_w + 1 end
    end
    for _, l in pairs(seed.locations) do
      if l.item and DB.items[l.item] and DB.items[l.item].category == "weapon" then reward_w = reward_w + 1 end
    end
    local spots = 0
    for _, lid in ipairs(seed.spheres[1]) do if DB.locations[lid].holds ~= "filler" then spots = spots + 1 end end
    if early_w < math.min(s.early_weapons, reward_w, spots) then
      bad(string.format("only %d weapon(s) where the start can reach, early_weapons is %d", early_w, s.early_weapons))
    end
  end

  -- self-locking: a gadget or Coordinates behind its own requirement
  for _, lid in ipairs(sorted_keys(seed.locations)) do
    local it = seed.locations[lid].item
    local loc = DB.locations[lid]
    if it and loc then
      for _, r in ipairs(loc.requires or {}) do if r == it then bad(it .. " placed behind itself at " .. lid) end end
      if s.planet_locks and loc.planet and (loc.kind ~= "goldbolt" or s.travel_lock) and it == "access:" .. loc.planet then bad(it .. " placed on its own planet " .. lid) end
    end
  end
  return problems
end

-- deterministic Lua text for any table (sorted keys): saves and pre-generated seed files
function G.serialize(v)
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local parts = {}
    for _, k in ipairs(keys) do
      local key = type(k) == "number" and ("[" .. k .. "]") or string.format("[%q]", k)
      parts[#parts + 1] = key .. "=" .. G.serialize(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return (string.format("%q", v):gsub("\\\n", "\\n"))
  else return tostring(v) end
end

-- ------------------------------------------------------------------------------------------
-- spoiler log
-- ------------------------------------------------------------------------------------------
function G.spoiler(seed)
  local L = {}
  local function w(...) L[#L + 1] = table.concat({ ... }) end
  w("Ratchet & Clank: Rift Apart Randomizer ", G.VERSION, " - spoiler log")
  w("Seed: ", seed.seed, "    Preset: ", seed.preset, "    Fingerprint: ", seed.fingerprint)
  w("Share code: ", seed.share_code)
  w("Data ", seed.data, ", generated in attempt ", seed.attempt)
  w("")
  w("SETTINGS")
  for _, k in ipairs(sorted_keys(seed.settings)) do w("  ", k, " = ", tostring(seed.settings[k])) end
  w("")
  if seed.warnings and #seed.warnings > 0 then
    w("NOTES (settings adjusted or capped for this seed)")
    for _, m in ipairs(seed.warnings) do w("  ", m) end
    w("")
  end
  if seed.campaign and seed.campaign.order then
    w("MISSION ORDER (" .. seed.campaign.mode .. ", experimental): the order of the game's planet visits")
    w(RANDO_CAMPAIGN.describe(seed.campaign.order))
    w("")
  end
  if seed.hub then
    local coords_at = {}
    for _, lid in ipairs(sorted_keys(seed.locations)) do
      local it = seed.locations[lid].item and DB.items[seed.locations[lid].item]
      if it and it.category == "coordinates" then coords_at[it.planet] = DB.locations[lid].name end
    end
    w("HUB AND PLANET SHUFFLE (" .. (RANDO_CAMPAIGN.HUB_NAME or "the hub") .. ")")
    w(RANDO_CAMPAIGN.hub_describe(seed.hub, function(pid) return DB.planets[planet_index(pid)].name end, coords_at))
    w("  Without a planet's Coordinates the ship's planet menu sends you back to the hub. Finishing a")
    w("  destination brings you back to the hub; the game's own next mission does not take over.")
  else
    w("STORY START: a new game plays the prologue (Corson V), then Nefarious City, then Sargasso, as in")
    w("  the game. The randomizer moves you nowhere; travel is the ship's planet menu.")
  end
  w("")
  if seed.levels then
    local lv = seed.levels
    w(lv.travel_lock and "LEVELS (locked: flying to a planet needs its Coordinates; the game's own story travel is never blocked)"
      or "LEVELS (Coordinates: a planet's mission rewards wait for them; travel is free)")
    local open = {}
    for _, pid in ipairs(lv.open_at_start) do open[#open + 1] = DB.planets[planet_index(pid)].name end
    w("  Open from the start: ", table.concat(open, ", "))
    w("  Planets open in this order (playthrough sphere of their Coordinates):")
    for _, u in ipairs(lv.unlock) do
      w(string.format("    sphere %2d  %-36s Coordinates at %s", u.sphere, DB.planets[planet_index(u.planet)].name, DB.locations[u.at].name))
    end
    if seed.hub then
      w("  Each planet's destinations open with its Coordinates (the hub above). Without them, the ship's")
      w("  planet menu sends you back to the hub; a mission's own rifts and cutscene travel are never blocked.")
    elseif lv.travel_lock then
      w("  The story keeps the game's mission order; the solver proves each planet the story needs next is")
      w("  open by then. Without its Coordinates, the randomizer flies you back to the planet you came from.")
    end
    w("")
  end
  w("START (Hoverboots and Map-O-Matic are in every seed)")
  for _, k in ipairs(seed.start.items) do w("  ", names(k)) end
  if (seed.start.bolts or 0) > 0 then w("  ", seed.start.bolts, " Bolts") end
  if (seed.start.raritanium or 0) > 0 then w("  ", seed.start.raritanium, " Raritanium") end
  w("  The game's own starting gadgets: ", table.concat(DB.start_kit, ", "))
  w("")
  if seed.settings.distribution == "spread" then
    w("GOLD BOLTS (each one you pick up is a real Gold Bolt in the game; the randomizer adds the reward")
    w("            below. A planet's Gold Bolts are matched in the order you pick them up)")
  else
    w("GOLD BOLTS (one item each; a planet's Gold Bolts are matched in the order you pick them up,")
    w("            preferring one whose requirements you meet)")
  end
  for i, lid in ipairs(seed.gold_bolts or {}) do
    local l = seed.locations[lid]
    w(string.format("  %2d  %-44s %s%s", i, DB.locations[lid].name, names(l.item or "-"), l.in_logic and "" or "  [needs a story ability]"))
  end
  w("")
  if seed.shop and seed.shop.slots then
    local pm = seed.shop.price_mode or "vanilla"
    w(seed.shop.mode == "shuffle" and "SHOP (Ms. Zurkon's 15 weapon slots; each keeps the point in the story it unlocks)"
      or "SHOP (Ms. Zurkon sells her own weapons)")
    w("  prices: " .. ({ vanilla = "the game's own", weapon = "what the weapon sold costs in the normal game",
                         percent = "a percentage of each slot's price", random = "random per slot" })[pm])
    local closed = {}
    for _, k in ipairs(seed.shop.closed or {}) do closed[k] = true end
    for _, k in ipairs(G.vendor_weapons()) do
      local p = seed.shop.prices and seed.shop.prices[k]
      if closed[k] then
        w(string.format("  the slot of %-22s CLOSED (shows the Burst Pistol you own; its weapon is a reward)", names(k)))
      else
        w(string.format("  the slot of %-22s sells %-26s %s", names(k), names(seed.shop.slots[k]),
                        p and string.format("%d Bolts", p) or string.format("(%s Bolts)", tostring(DB.items[k].price or "?"))))
      end
    end
    w("  Shatterbomb and RYNO 8 (after all 10 Spybots) stay in their own slots; ammo and upgrades as usual")
    w("  No weapon is both sold and given: a weapon at the start or at a location is never in a shop slot,")
    w("  and a slot of another vendor (ARSENAL_RESTORED's) selling such a weapon is closed by the runtime")
    if seed.shop.prices then w("  New prices apply only once the runtime finds the game's own prices in memory (TROUBLESHOOTING.md)") end
  end
  w("")
  w("ARMOR: " .. (seed.armor and "the armor pieces you can find are rewards above and below; each armor source (pocket dimension, Zurkie's challenge, the Lorb monk) gives the item listed for it instead of its own piece"
                  or "not randomized (armor = false)"))
  if seed.filler and #seed.filler.kinds > 0 then
    local f = seed.filler
    w("CURRENCY: a location without an item gives " .. table.concat(f.kinds, " or ") .. " (amounts listed below)")
    for _, k in ipairs(f.kinds) do
      w(string.format("  %-10s %d-%d per reward, %d in all", k, f[k][1], f[k][2], (f.totals or {})[k] or 0))
    end
  end
  w("")
  w("LOCATIONS")
  local by_planet = {}
  for _, lid in ipairs(sorted_keys(seed.locations)) do
    local loc = DB.locations[lid]
    local key = loc.planet or "~anywhere"
    by_planet[key] = by_planet[key] or {}
    table.insert(by_planet[key], lid)
  end
  local plist = {}
  for _, p in ipairs(DB.planets) do plist[#plist + 1] = p.id end
  plist[#plist + 1] = "~anywhere"
  for _, pid in ipairs(plist) do
    if by_planet[pid] then
      local pname = pid == "~anywhere" and "Anywhere (armor sources and collectibles)" or DB.locations["planet:" .. pid] and (DB.planets[planet_index(pid)].name)
      w("  ", pname)
      for _, lid in ipairs(by_planet[pid]) do
        local l = seed.locations[lid]
        w(string.format("    %-22s %-44s %s%s", lid, DB.locations[lid].name, names(l.item or "-"),
                        (l.in_logic or DB.locations[lid].kind == "armor_source") and "" or "  [out of logic]"))
      end
    end
  end
  w("")
  w("ITEM ROUTES")
  local routes = {}
  for _, k in ipairs(sorted_keys(seed.registry)) do
    local r = seed.registry[k]
    routes[r] = (routes[r] or 0) + 1
  end
  for _, r in ipairs(sorted_keys(routes)) do w(string.format("  %-28s %d", r, routes[r])) end
  w("")
  w("PLAYTHROUGH (spheres: what can be collected with what the previous spheres gave)")
  for i, sp in ipairs(seed.spheres) do
    local parts = {}
    for _, lid in ipairs(sp) do
      local it = (seed.locations[lid] and seed.locations[lid].item)
      if it then parts[#parts + 1] = lid .. " -> " .. names(it) end
    end
    w("  Sphere ", i, ": ", #sp, " locations")
    for _, p in ipairs(parts) do w("      ", p) end
  end
  return table.concat(L, "\n") .. "\n"
end
