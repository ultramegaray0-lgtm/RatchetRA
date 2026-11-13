-- Randomizer 7.0: locked levels (rivet_hook, Lua 5.4). Loaded after 10_rando_runtime.lua.
--
-- With levels = true (seed.travel_lock) each planet's travel is locked behind its Coordinates.
-- What your game allows, and what this script does with it:
--   * Your game's mission system cannot open a mission out of order (rounds 14-15, CAMPAIGN.md),
--     so the STORY keeps the game's own mission order. The seed's solver proves that whenever the
--     story needs a planet, its Coordinates were findable on planets already open.
--   * The game cannot be stopped from flying (events cannot be vetoed), so a locked planet is
--     enforced AFTER the landing: if you chose it in the ship's planet menu (PlanetMenuAcceptEvent,
--     seen in rounds 14 and 16) and hold no Coordinates for it, rivet_hook's warp takes you back
--     to the planet you came from, to the checkpoint you last landed on there.
--   * Planet changes the game makes by itself are NEVER blocked: the parade's rifts, the rift
--     jumps inside missions (round 16: Nefarious City -> Savali -> Nefarious City), the story's own
--     travel (Nefarious City -> Sargasso) and loading a save all come without a planet-menu event.
--   * If no checkpoint to go back to is known, or the warp fails, the planet stays playable and
--     its rewards wait for its Coordinates instead (the 6.0 "banked" rule) - said on screen.
--   * Escape hatch: Ctrl+F9 twice opens the planet you were last sent back from (its Coordinates
--     are given, marked [OPENED BY HAND] in the history). The solver makes it unnecessary; it is
--     there in case the game's story differs from the model somewhere.
--   * levels_runtime = false in 04_rando_settings.lua turns the warp off (rewards wait instead).
-- Nothing here changes the game's files, missions or saves; a warp moves the save's checkpoint to
-- the planet you came from, which is where you were anyway.
--
-- 10.0 CHECKPOINT NAMES. CheckpointTriggeredEvent carries only CheckpointHash. That number is the
-- engine's 32-bit string hash of the checkpoint's name (the CRC-32 table with start value
-- 0xEDB88320 and no final xor, the one rivet.hash uses: MIS_INTRO = 1000115474): 29 names your
-- game listed match hashes in your rounds 13-23 logs, e.g. CHK_NEFCITY_START = 2052464476 and
-- CHK_ZURK_00_DEFAULT = 2229284024. Every name the catalog lists is hashed, so each triggered
-- checkpoint is logged by name (RANDO-CHECKPOINT) and the hub knows where a mission really starts.
-- In a hub seed (15_rando_hub.lua) the hub handles every arrival itself; this file's send-back is
-- used by 7.0-9.0 style seeds.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["14_rando_travel"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)

RANDO_TRAVEL = RANDO_TRAVEL or {}
local T = RANDO_TRAVEL
local DB = RANDO_DATA
local function log(...) pcall(rivet.log, "[rando]", "RANDO-TRAVEL", ...) end
local function R() return RANDO end
local function S() return RANDO and RANDO.state end
local function SEED() return RANDO_SEED end
local function say(text, opts) if RANDO and RANDO.say then RANDO.say(text, opts) end end
local function now() return (rivet.time and rivet.time()) or 0 end

T.MENU_WINDOW = 180          -- seconds a planet-menu choice waits for its landing (rift transitions are long)
T.SETTLE_FRAMES = 180        -- frames after the landing (scene and hero ready) before the warp
T.HATCH_WINDOW = 4           -- seconds between the two Ctrl+F9 presses
T.pending = nil              -- the last planet-menu choice not landed yet
T.hash_names = T.hash_names or {}   -- 10.0: engine hash -> checkpoint name (every name the catalog saw)
T.last_checkpoint = nil      -- 10.0: { hash, name, planet, frame, loaded } of the last CheckpointTriggeredEvent
T.cp_seen = T.cp_seen or {}  -- hashes already logged this session
T.warp = nil                 -- { to, planet, from, at_frame }
T.frame = 0

function T.active()
  local seed, s = SEED(), S()
  if not (seed and s and seed.travel_lock) then return false end
  if RANDO and RANDO.config and RANDO.config.levels_runtime == false then return false end
  -- v0.54: planet shuffle switched off with the 0 key: no planet is locked either
  if RANDO_HUB and RANDO_HUB.shuffle_off and RANDO_HUB.shuffle_off() then return false end
  return true
end

-- 8.4: `landed` holds only real landings (the ship's planet menu). Before 8.4 test trips and hub
-- warps were remembered there too (round 20: a mid-mission checkpoint a test trip had left,
-- CHK_MOL_SALVAGE_PIRATES_COMMAND_SHIP). Older entries move to `test_landed`, which only test
-- travel offers.
local function state()
  local s = S()
  s.travel = s.travel or { landed = {}, sent_back = 0, banked_planets = {}, landed_v = 2 }
  local tr = s.travel
  tr.landed = tr.landed or {}
  tr.banked_planets = tr.banked_planets or {}
  tr.test_landed = tr.test_landed or {}
  if tr.landed_v ~= 2 then
    for pid, cp in pairs(tr.landed) do tr.test_landed[pid] = tr.test_landed[pid] or cp end
    tr.landed = {}
    tr.landed_v = 2
  end
  return tr
end
T.state = state

-- 8.2: lookups built once. Round 18's catalog ran past rivet_hook's 8 ms frame budget in T.place,
-- T.catalog_add and T.ranked (14_rando_travel.lua:115/140/141/197) and never finished: every
-- checkpoint name was compared with every planet's every code, and every sort comparison scored
-- both names again. Now a code is one table lookup per name token, an area is looked up once, and
-- a name is scored once.
local CODES, CODE_LENS = nil, nil         -- code -> { pid, order }, code lengths longest first
local function code_index()
  if CODES then return CODES, CODE_LENS end
  CODES, CODE_LENS = {}, {}
  local lens = {}
  for order, p in ipairs(DB.planets) do
    for _, code in ipairs((p.checkpoints and p.checkpoints.codes) or {}) do
      if not CODES[code] then CODES[code] = { p.id, order } end
      lens[#code] = true
    end
  end
  for l in pairs(lens) do CODE_LENS[#CODE_LENS + 1] = l end
  table.sort(CODE_LENS, function(a, b) return a > b end)
  return CODES, CODE_LENS
end

-- which planet a checkpoint name belongs to: a name token starting with one of the planet's codes
-- (CHK_ZURK_00_DEFAULT -> scarstu, CHK_TRANSITION_TO_ZURKIES -> scarstu); the longest code wins,
-- and between codes of the same length the planet earlier in the story (as 8.1 decided)
function T.planet_of_checkpoint(name)
  if type(name) ~= "string" then return nil end
  local codes, lens = code_index()
  local best, blen, border = nil, 0, math.huge
  for tok in name:upper():gmatch("[^_]+") do
    for _, l in ipairs(lens) do
      if l < blen then break end
      if #tok >= l then
        local hit = codes[tok:sub(1, l)]
        if hit and (l > blen or hit[2] < border) then best, blen, border = hit[1], l, hit[2]; break end
      end
    end
  end
  return best
end

-- 8.1: the checkpoint catalog. rivet.checkpoints(filter) lists the level's checkpoints whose name
-- contains filter, each with the top-level area it is in (round 17: "Zurkons", "Sargasso (open
-- world)", "Blizar_Destroyed", "interplanetary_space" for the planet tunnels). Torren IV and
-- Cordelion have no LANDING / SHIP / DEFAULT checkpoint, so 8.0 found nothing there: the catalog
-- now places every listed checkpoint on its planet by its area (the planet's "areas" fragments)
-- or else by its name (the planet's codes), and scores them, landing pads first, cinematics,
-- bosses and planet tunnels last. It is filled one filter per frame (T.catalog_step) so no
-- single callback lists the whole level.
T.PREFER = { "LANDINGPAD", "LANDING", "SHIP", "00_DEFAULT", "DEFAULT" }
T.SCORE = {
  { "LANDINGPAD", 100 }, { "LANDING", 90 }, { "_SHIP", 80 }, { "00_DEFAULT", 75 }, { "DEFAULT", 70 },
  { "ARRIVAL", 45 }, { "ARRIVE", 45 }, { "ENTRANCE", 40 }, { "_START", 35 }, { "_00_", 25 }, { "_01_", 20 },
}
T.AVOID = { "TRANSITION_TO", "CINE", "BOSS", "FINALE", "DEBUG", "TEST", "ARENA", "CHALLENGE", "_END",
            "DEATH", "RETURN", "ESCAPE", "PSHIFT", "REVISIT", "POSTMISSION", "WARPBACK", "TELEPORTER" }
T.CATALOG_SLICE = 128        -- most entries placed in one frame
T.SLICE_SECONDS = 0.0015     -- 8.2: and at most this long (the whole randomizer shares rivet_hook's 8 ms)
T.catalog = nil              -- { planets = { [pid] = { [name] = area } }, filters = {...}, next = i, done = bool }
T.scores = {}                -- name -> score (8.2: each name is scored once)

local function clock() return (os and os.clock and os.clock()) or 0 end

function T.score_checkpoint(name)
  local cached = T.scores[name]
  if cached then return cached end
  local up = tostring(name):upper()
  local score = 0
  local toks = {}
  for t in up:gmatch("[^_]+") do toks[#toks + 1] = t end
  for _, s in ipairs(T.SCORE) do
    if up:find(s[1], 1, true) then
      local v = s[2]
      -- 8.4: "_SHIP" is a landing only as a short name (CHK_NEFCITY_SHIP, CHK_ZURK_LANDING_SHIP,
      -- CHK_CORD_A_TELE_SHIP), not CHK_MOL_SALVAGE_PIRATES_COMMAND_SHIP, a mid-mission point
      if s[1] == "_SHIP" and #toks > 5 then v = 30 end
      score = math.max(score, v)
    end
  end
  -- 8.4: a planet's story start: CHK_<code>_START, CHK_<code>_A_START or CHK_<code>_01_START
  -- (round 20: the story of Ardolis ran from CHK_ARD_START)
  if toks[1] == "CHK" and #toks >= 3 and #toks <= 4 and toks[#toks] == "START" then
    if #toks == 3 or toks[3] == "A" or toks[3]:match("^0%d$") then score = math.max(score, 95) end
  end
  for _, a in ipairs(T.AVOID) do if up:find(a, 1, true) then score = score - 60 end end
  if type(name) == "string" then T.scores[name] = score end
  return score
end

-- which planet an area name belongs to (nil for interplanetary_space and unknown areas)
local AREAS = {}             -- area -> pid or false (a level has a handful of areas)
function T.planet_of_area(area)
  if type(area) ~= "string" or area == "" then return nil end
  local known = AREAS[area]
  if known ~= nil then return known or nil end
  local low = area:lower()
  local found = false
  if not low:find("interplanetary", 1, true) then
    for _, p in ipairs(DB.planets) do
      for _, frag in ipairs((p.checkpoints and p.checkpoints.areas) or {}) do
        if not found and low:find(frag, 1, true) then found = p.id end
      end
    end
  end
  AREAS[area] = found
  return found or nil
end

-- the planet a listed checkpoint is on: its area first, its name second
function T.place(name, area)
  if type(name) ~= "string" then return nil end
  if name:upper():find("TRANSITION_TO", 1, true) then return nil end
  return T.planet_of_area(area) or T.planet_of_checkpoint(name)
end

local function entry_of(c)
  if type(c) == "table" then return c.name or c[1], c.area or c[4] or "" end
  return c, ""
end

function T.catalog_filters()
  local out, seen = {}, {}
  local function add(f) if f and not seen[f] then seen[f] = true; out[#out + 1] = f end end
  for _, f in ipairs({ "LANDING", "SHIP", "DEFAULT", "START" }) do add(f) end
  for _, p in ipairs(DB.planets) do
    for _, code in ipairs((p.checkpoints and p.checkpoints.codes) or {}) do add(code) end
  end
  add("CHK_")                                -- last: everything the level lists (2048 at most)
  return out
end

-- add one rivet.checkpoints() answer to the catalog (entries first..last). With `budget` (seconds)
-- it stops early once that much time has gone. Returns how many it placed and the next entry.
-- 10.0 the engine's string hash (identical to rivet.hash; in Lua so it never depends on the
-- hook's version)
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do c = (c & 1 == 1) and ((c >> 1) ~ 0xEDB88320) or (c >> 1) end
  CRC[i] = c
end
function T.hash(text)
  local c = 0xEDB88320
  for i = 1, #text do c = (c >> 8) ~ CRC[(c ~ text:byte(i)) & 0xFF] end
  return c
end
function T.name_of_hash(h)
  h = math.tointeger(tonumber(h)) or h
  return T.hash_names[h]
end
-- v0.52: the name of a checkpoint hash, asked of the game now: the names are known already, else
-- each filter's list is hashed (stopping after `budget` seconds, 0.004 by default). Returns the
-- name and the filter it was found under, or nil.
function T.find_hash(h, filters, budget)
  h = math.tointeger(tonumber(h)) or h
  if T.hash_names[h] then return T.hash_names[h], "known" end
  if type(rivet.checkpoints) ~= "function" then return nil end
  local t0, limit = clock(), budget or 0.004
  for _, f in ipairs(filters or {}) do
    local ok, list = pcall(rivet.checkpoints, f)
    if ok and type(list) == "table" then
      for _, c in ipairs(list) do
        local name = entry_of(c)
        if type(name) == "string" then
          local x = T.hash(name)
          T.hash_names[x] = name
          if x == h then return name, f end
        end
      end
    end
    if clock() - t0 >= limit then break end
  end
  return nil
end
-- every name we know already (the registry's starts, entries, the hub's checkpoints, the logs)
do
  local function add(n) if type(n) == "string" and n ~= "" then T.hash_names[T.hash(n)] = n end end
  for _, seg in ipairs((RANDO_CAMPAIGN and RANDO_CAMPAIGN.SEGMENTS) or {}) do add(seg.entry); add(seg.start_cp) end
  for _, n in ipairs((RANDO_CAMPAIGN and RANDO_CAMPAIGN.HUB_CHECKPOINTS) or {}) do add(n) end
  for _, p in ipairs(DB.planets or {}) do
    for _, n in ipairs((p.checkpoints and p.checkpoints.known) or {}) do add(n) end
  end
end

-- CheckpointTriggeredEvent (10_rando_runtime.lua)
function T.on_checkpoint(hash, loaded)
  if hash == nil then return end
  local s = S()
  local name = T.name_of_hash(hash)
  local pid = (name and T.planet_of_checkpoint(name)) or (s and s.current_planet)
  T.last_checkpoint = { hash = hash, name = name, planet = pid, frame = T.frame, loaded = loaded }
  if not T.cp_seen[hash] then
    T.cp_seen[hash] = true
    log("RANDO-CHECKPOINT", name or "(not listed yet)", string.format("hash %s", tostring(hash)), "on", tostring(s and s.current_planet))
  end
  if RANDO_HUB and RANDO_HUB.on_checkpoint then
    local ok, err = pcall(RANDO_HUB.on_checkpoint, T.last_checkpoint)
    if not ok then log("RANDO-ERROR hub checkpoint", tostring(err)) end
  end
end

function T.catalog_add(list, first, last, budget)
  local cat = T.catalog
  local n = 0
  list = list or {}
  local t0 = budget and clock()
  local stop = math.min(last or #list, #list)
  local i = first or 1
  while i <= stop do
    local name, area = entry_of(list[i])
    if type(name) == "string" then T.hash_names[T.hash(name)] = name end
    local pid = T.place(name, area)
    if pid then
      cat.planets[pid] = cat.planets[pid] or {}
      if cat.planets[pid][name] == nil then n = n + 1; T.score_checkpoint(name) end
      cat.planets[pid][name] = area or ""
    end
    i = i + 1
    if budget and clock() - t0 >= budget then break end
  end
  return n, i
end

function T.catalog_reset()
  T.catalog = { planets = {}, filters = T.catalog_filters(), next = 1, done = false, errors = 0 }
end

-- one filter per call (call it once a frame). Returns true when the catalog is complete.
function T.catalog_step()
  if not T.catalog then T.catalog_reset() end
  local cat = T.catalog
  if cat.done then return true end
  local f = cat.filters[cat.next]
  if not f and not cat.pending then
    cat.done = true
    local parts = {}
    for _, p in ipairs(DB.planets) do
      local best = T.best_in_catalog(p.id)
      local count = 0
      for _ in pairs(cat.planets[p.id] or {}) do count = count + 1 end
      parts[#parts + 1] = string.format("%s %d%s", p.id, count, best and ("=" .. best) or "")
    end
    log("checkpoint catalog:", table.concat(parts, ", "))
    return true
  end
  if cat.pending then                        -- an answer is placed a slice a frame (8.2: also by time)
    local pd = cat.pending
    local _, nxt = T.catalog_add(pd.list, pd.at, pd.at + T.CATALOG_SLICE - 1, T.SLICE_SECONDS)
    pd.at = nxt
    if pd.at > #pd.list then cat.pending = nil end
    return false
  end
  cat.next = cat.next + 1
  local ok, list = pcall(rivet.checkpoints, f)
  if ok and type(list) == "table" then
    if #list > 0 then cat.pending = { list = list, at = 1 } end   -- placed from the next frame on
  else
    cat.errors = cat.errors + 1
    if cat.errors <= 3 then log("checkpoints", f, "not listed:", tostring(list)) end
  end
  return false
end

-- the catalog's order: higher score, then the shorter name, then by name
local function better(a, b)
  local sa, sb = T.score_checkpoint(a), T.score_checkpoint(b)
  if sa ~= sb then return sa > sb end
  if #a ~= #b then return #a < #b end
  return a < b
end
T.better = better

-- every checkpoint of a planet the catalog holds, best first (limit: only the best `limit`)
function T.ranked(pid, limit)
  local cat = T.catalog
  local names = {}
  for name in pairs((cat and cat.planets[pid]) or {}) do names[#names + 1] = name end
  if limit and #names > limit * 4 then
    -- a long list: keep the best `limit` without sorting all of it
    local top = {}
    for _, n in ipairs(names) do
      if #top < limit then top[#top + 1] = n; table.sort(top, better)
      elseif better(n, top[#top]) then top[#top] = n; table.sort(top, better) end
    end
    return top
  end
  table.sort(names, better)
  if limit then for i = #names, limit + 1, -1 do names[i] = nil end end
  return names
end
function T.best_in_catalog(pid)
  local cat = T.catalog
  local best = nil
  for name in pairs((cat and cat.planets[pid]) or {}) do
    if best == nil or better(name, best) then best = name end
  end
  return best
end

-- the whole catalog of one planet, for rivet.log (what the next round should name)
function T.describe_planet(pid, limit)
  local total = 0
  for _ in pairs((T.catalog and T.catalog.planets[pid]) or {}) do total = total + 1 end
  local names = T.ranked(pid, limit or 24)
  local out = {}
  for i = 1, #names do
    out[#out + 1] = string.format("%s(%d)", names[i], T.score_checkpoint(names[i]))
  end
  return string.format("%d: %s", total, table.concat(out, " "))
end

-- a checkpoint on planet pid to warp to: where you last landed there, then the ones seen in your
-- logs, then the catalog, then rivet.checkpoints() searched by the planet's codes right now
function T.checkpoint_for(pid)
  local tr = state()
  if tr.landed[pid] then return tr.landed[pid], "where you last landed" end
  local p
  for _, x in ipairs(DB.planets) do if x.id == pid then p = x end end
  if not p then return nil end
  local known = p.checkpoints and p.checkpoints.known
  if known and known[1] then return known[1], "seen in your logs" end
  local best = T.best_in_catalog(pid)
  if best then return best, "checkpoint catalog" end
  if not T.catalog then T.catalog_reset() end
  for _, code in ipairs((p.checkpoints and p.checkpoints.codes) or {}) do
    local ok, list = pcall(rivet.checkpoints, code)
    if ok and type(list) == "table" then T.catalog_add(list) end
  end
  best = T.best_in_catalog(pid)
  if best then return best, "rivet.checkpoints" end
  return nil
end

-- PlanetMenuAcceptEvent { DestinationCheckpointName, InterplanetaryCheckpointName }
function T.on_menu_accept(f)
  if not (SEED() and S()) then return end
  local dest = f.DestinationCheckpointName
  local cur = RANDO and RANDO.state and RANDO.state.current_planet
  T.pending = { dest = dest, planet = T.planet_of_checkpoint(dest) or T.planet_of_checkpoint(f.InterplanetaryCheckpointName),
                from = cur, at = now() }
  log("planet menu:", tostring(dest), "->", tostring(T.pending.planet), "from", tostring(cur))
end

-- a planet arrival the runtime has processed (scene ready). Returns true when the arrival is
-- locked and handled here (sent back, or its rewards banked).
function T.on_arrival(pid, from)
  if not T.active() then T.pending = nil; return false end
  local s, tr = S(), state()
  local p = T.pending
  if p and now() - p.at > T.MENU_WINDOW then p = nil; T.pending = nil end
  if p and p.planet and p.planet ~= pid then
    return false                       -- a planet passed on the way (keep waiting for the landing)
  end
  T.pending = nil
  if not p then
    log("arrived on", pid, "without the planet menu (the story, a rift or a load): never blocked")
    return false
  end
  if s.access[pid] then
    -- 8.5: through T.remember (8.4 wrote it here directly: a TRANSITION_TO name was kept, and
    -- the landing was not saved until something else changed)
    if p.dest then T.remember(pid, p.dest) end
    log("arrived on", pid, "(open) at", tostring(p.dest))
    return false
  end
  -- 8.2 test travel (16_rando_testtravel.lua): nothing is sent back while it is on
  local TT = RANDO_TEST_TRAVEL
  if TT and TT.on and TT.on() then
    if p.dest then T.remember(pid, p.dest) end
    TT.stayed(pid, "planet menu")
    return false
  end
  local back_to = p.from or from
  if not back_to or back_to == pid or not s.access[back_to] then
    -- where you came from is unknown or locked too: the nearest open planet in story order
    back_to = nil
    for _, x in ipairs(DB.planets) do if s.access[x.id] and x.id ~= pid then back_to = back_to or x.id end end
  end
  local cp, how = nil, nil
  if back_to then cp, how = T.checkpoint_for(back_to) end
  local name = RANDO.planet_name(pid)
  tr.last_locked = pid
  if not cp then
    T.bank(pid, "no checkpoint known to send you back to " .. tostring(back_to))
    return true
  end
  T.warp = { to = cp, planet = pid, from = back_to, at_frame = T.frame + T.SETTLE_FRAMES, how = how }
  log("locked:", pid, "- warping back to", back_to, "at", cp, "(" .. tostring(how) .. ") in", T.SETTLE_FRAMES, "frames")
  say(string.format("Randomizer: no Coordinates for %s yet - back to %s", name, RANDO.planet_name(back_to)),
      { type = "center", duration = 6 })
  return true
end

-- the planet stays playable; its rewards wait for its Coordinates (the 6.0 rule)
function T.bank(pid, why)
  local tr = state()
  tr.banked_planets[pid] = true
  if RANDO.mark_changed then RANDO.mark_changed() end
  log("locked:", pid, "- not sent back (" .. why .. "): its rewards wait for its Coordinates")
  say(string.format("Randomizer: no Coordinates for %s yet - rewards here wait for them", RANDO.planet_name(pid)),
      { type = "center", duration = 6 })
end
-- does a location on this planet wait for Coordinates? (10_rando_runtime.lua asks)
function T.banks(pid)
  local s = S()
  if not (s and pid) or s.access[pid] then return false end
  if not T.active() then return true end           -- levels off at runtime: rewards wait instead
  return state().banked_planets[pid] == true
end

-- where a planet was landed on (the planet menu's destination): the first choice next time
function T.remember(pid, cp)
  if not (pid and type(cp) == "string" and cp ~= "") then return end
  if cp:upper():find("TRANSITION_TO", 1, true) then return end
  local s = S()
  if not s then return end
  local tr = state()
  if tr.landed[pid] ~= cp then
    tr.landed[pid] = cp
    log("landing on", pid, "remembered:", cp)
    if RANDO and RANDO.mark_changed then RANDO.mark_changed() end
  end
end

-- 8.4: a test trip's landing: offered again by test travel, never used by the lock
function T.remember_test(pid, cp)
  if not (pid and type(cp) == "string" and cp ~= "") then return end
  local s = S()
  if not s then return end
  local tr = state()
  if tr.test_landed[pid] ~= cp then
    tr.test_landed[pid] = cp
    if RANDO and RANDO.mark_changed then RANDO.mark_changed() end
  end
end

function T.catalog_wanted()
  if T.catalog and T.catalog.done then return false end
  if type(rivet.checkpoints) ~= "function" then return false end
  local TT = RANDO_TEST_TRAVEL
  -- v0.52: a hub seed needs the names too (a visit's opening scene is found by its hash)
  local HB = RANDO_HUB
  if HB and HB.plan and HB.plan() ~= nil then return true end
  return T.active() or (TT ~= nil and TT.on ~= nil and TT.on())
end

function T.tick(frame, ready)
  T.frame = frame
  -- the catalog: one filter every 4 frames, every frame while test travel waits for it
  local every = (RANDO_TEST_TRAVEL and RANDO_TEST_TRAVEL.want_catalog) and 1 or 4
  if ready and frame % every == 0 and T.catalog_wanted() and frame >= (T.catalog_from or 600) then T.catalog_step() end
  local w = T.warp
  if not (w and ready) or frame < w.at_frame then return end
  T.warp = nil
  local s, tr = S(), state()
  if s.access[w.planet] then log("Coordinates for", w.planet, "arrived meanwhile: staying"); return end
  local ok, res = pcall(rivet.warp, w.to)
  if ok and res ~= false then
    tr.sent_back = (tr.sent_back or 0) + 1
    if RANDO.mark_changed then RANDO.mark_changed() end
    log("warped back to", w.from, "at", w.to, "(" .. tostring(res) .. ")")
  else
    log("warp to", w.to, "failed:", tostring(res))
    T.bank(w.planet, "the warp failed")
  end
end

-- Ctrl+F9 twice: open the planet you were last sent back from
local hatch_at = -100
function T.hatch()
  local tr = state()
  local pid = tr.last_locked
  if not pid or S().access[pid] then say("Randomizer: no locked planet to open", { type = "corner", duration = 4 }); return false end
  local t = now()
  if t - hatch_at > T.HATCH_WINDOW then
    hatch_at = t
    say(string.format("Randomizer: press %s again to open %s by hand (it is recorded in the history)", RANDO.key("key_status", true), RANDO.planet_name(pid)),
        { type = "center", duration = 5 })
    return false
  end
  hatch_at = -100
  tr.opened_by_hand = (tr.opened_by_hand or 0) + 1
  log("[OPENED BY HAND]", pid)
  if RANDO.history then RANDO.history("[OPENED BY HAND] Coordinates for " .. pid .. " (" .. RANDO.key("key_status", true) .. ")") end
  RANDO.grant("access:" .. pid, false, "[OPENED BY HAND] ")
  return true
end

function T.status_text()
  local seed, s = SEED(), S()
  if not (seed and s and seed.travel_lock) then return nil end
  local n = 0
  for _ in pairs(s.access) do n = n + 1 end
  return string.format("planets open %d/%d%s", n, #DB.planets, T.active() and "" or " (warp off)")
end

function T.new_game() T.pending, T.warp = nil, nil end

pcall(rivet.on_event, "PlanetMenuAcceptEvent", function(ev)
  local ok, err = pcall(T.on_menu_accept, ev.fields or {})
  if not ok then log("RANDO-ERROR menu", tostring(err)) end
end)
log("loaded")
