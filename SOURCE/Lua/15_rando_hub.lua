-- Randomizer 10.0 hub, mission selection and planet shuffle (rivet_hook, Lua 5.4). v0.51
-- (10.0.2): the hub is NEFARIOUS CITY (10.0-v0.5: Zurkie's Battleplex). Loaded after
-- 10_rando_runtime.lua, 11_rando_campaign.lua and 14_rando_travel.lua. Active only for a seed made
-- with hub = true (the default).
--
-- NOTHING OF 10.0 OR v0.5x HAS RUN IN YOUR GAME YET. What each step rests on:
--
--  1. NEW GAME -> NEFARIOUS CITY. A new save always begins with the parade (the mission graph's
--     NewGameLoadInfo; a script cannot change it).
--     WHEN (v0.51, hub_trigger = "parade"): not at the wrench itself. Picking the wrench up
--     (OBJ_INTRO_PARADE_PICKUP_WRENCH done) starts OBJ_INTRO_GOING_DOWN at once, a scripted
--     sequence: in round 23 the game answered nothing sent to the hero during it ("no reaction from
--     the game", "the game is not answering right now") until GOING_DOWN finished and the parade
--     went on (OBJ_INTRO_PARADE_VELDIN_START). 10.0-v0.5 warped at the wrench, i.e. in the middle of
--     that sequence, with the prologue left active, and you report Ratchet could not walk after
--     the warp. So the warp now waits until GOING_DOWN is done and no parade sequence (an objective
--     named *GOING_DOWN*, *CINE* or *CUTSCENE*) has run for H.RELEASE_SETTLE frames (Ratchet walking
--     the Veldin float). If GOING_DOWN is never reported done, it goes H.RELEASE_TIMEOUT frames after
--     the wrench. hub_trigger = "wrench" keeps 10.0's timing.
--     HOW: like the game after the prologue (round 23: MIS_NEFCITY_01 becomes active, then the city
--     loads at CHK_NEFCITY_START), Ratchet is confirmed, MIS_NEFCITY_01 is made available and
--     started (round 17: these calls made it active), and the warp goes to CHK_NEFCITY_START, where
--     the game itself loads the city's story (rounds 16 and 23, by its CRC-32; the 8.x landing
--     CHK_NEFCITY_SHIP left it at "go to Nefarious City", rounds 17 and 22). The story is watched
--     (step 4d). Once you are there, the prologue is written complete (hub_prologue = "end"), as
--     kit 8.0 did after its warp in round 17 (the Battle Arena then played to its end), so no
--     parade state stays with Ratchet; its reward is paid. hub_prologue = "keep" leaves it active and
--     offers it as a destination, as 10.0 did.
--  2. THE START MENU. ] (next) and Ctrl+] (go) offer what is open:
--       Nefarious City - the hub's own story, MIS_NEFCITY_01 (Ratchet); already running after step 1
--       Battle Arena  - Zurkie's first visit, MIS_ZURK_01_VISIT_01 (Ratchet), loaded at
--                       CHK_ZURK_00_DEFAULT; round 17 played it to the end after the same steps
--       Prologue      - only with hub_prologue = "keep": back to the parade where you left it
--  3. PLANET SHUFFLE. Every other destination opens when you hold its planet's Coordinates (items
--     of the seed: Gold Bolts, missions, armor pods ... can hold them) and what it depends on is
--     done (03_rando_campaign.lua C.hub_available). ] lists what you can play, Ctrl+] goes.
--  4. LAUNCHING A DESTINATION (all steps logged as RANDO-HUB):
--       a. the visit's hero (rivet.hero_play_as; "already playing as that hero" is the
--          confirmation, 8.4);
--       b. its mission, asked from the game (rando_give.dll, the game's own State()):
--          active -> left as it is; available -> the game's start call; inactive -> "available"
--          written into its saved record (rando_give.dll v6), then the start call (round 17:
--          MIS_NEFCITY_01 and MIS_ZURK_01_VISIT_01 went active this way); complete -> finished;
--          start refused -> the replay call -> otherwise EXPLORE (Ctrl+[ twice finishes by hand);
--       c. the trip: a warp to the visit's own start checkpoint (start_cp, or one learned from an
--          earlier run), else the ship's flight / a warp to its landing. This mirrors what the game
--          does: its next mission becomes active first, then the planet loads at its start.
--       d. the story's first step ("go to <planet>") is watched; if it has not finished after
--          20 s, the start checkpoint (or the landing) is loaded once more.
--  5. FINISHING. A destination finishes when its last mission completes (MissionStateChangedEvent
--     3/4). Its story-mission and side locations pay, newly playable destinations are announced,
--     and after hub_return_delay seconds you are taken back to the hub. If the game's own story
--     takes you elsewhere first (Nefarious City -> Sargasso), you are brought back to the hub from
--     there: the game's linear order never takes over (hub_follow_story = true lets you carry on
--     when that destination is open anyway). The way home is CHK_NEFCITY_START while the city's
--     story is not finished (it resumes there), then the ship's pad CHK_NEFCITY_SHIP.
--  6. THE SHIP'S MENU. A landing on a planet without Coordinates sends you back to the hub; on an
--     open planet it starts that planet's next playable destination. Travel inside a destination
--     (a mission's own rifts) is never touched.
--  7. LEARNING. Every checkpoint the game triggers is named (14_rando_travel.lua: the engine's
--     CRC-32 of every name rivet.checkpoints() lists). The first one a destination's mission
--     triggers on its planet is kept as that destination's start for the next run.
--
-- v0.52 (10.0.3) THE CITY'S OPENING SCENE. Round 24 (v0.51's first run): the warp to
-- CHK_NEFCITY_START with MIS_NEFCITY_01 active landed, but the story never left
-- OBJ_NEFCITY_GO_TO_NEFCITY - not after the stuck-story reload, not after three presses of /. In
-- round 23 the game's own rift loaded the city at checkpoint hash 3046787773 first (the arrival
-- scene), then CHK_NEFCITY_START. So the hub start now copies the game's order more closely:
--   1. the prologue is written complete first (hub_prologue_timing = "before"; round 23: MIS_INTRO
--      turned 4 before the city's story started);
--   2. MIS_NEFCITY_01 is made available and started, and MIS_NEFCITY_01_TRAINSTATION made available
--      (round 23: the game opened it in the same frame);
--   3. the warp goes to the city's OPENING checkpoint (03_rando_campaign.lua C.OPENINGS), whose name
--      is found by its hash among the names your game lists. While that name is not found the hub
--      waits for the checkpoint catalog (H.OPENING_WAIT); if your game does not list it, the warp
--      goes to CHK_NEFCITY_START as before and rivet.log lists the city's checkpoints.
--   The story is given H.OPENING_STUCK_WAIT (the scene must not be cut short) before one reload
--   at the opening; / loads the opening again while the story waits at its first step.
-- None of this has run in your game yet.
--
-- v0.53 (10.0.4) THE BOSS FIGHT'S SHIFTS. Round 25 (v0.52's first run): the city's story ran, but
-- its boss fight (CHK_NEFCITY_HEAVY_FIGHT) shifts Ratchet to Savali or Sargasso, and with the
-- planetary travel byte on (set at the hub, set again on every return) the game played each shift
-- as a ship landing on ground that is not there: Ratchet fell and died, again after every reload.
-- The travel byte and the level bits are now left to the game while a destination runs (see
-- H.apply_world), taken back before the hub's own story is launched, and the hub stays quiet when
-- the story brings you back from a shift. They go on again once no destination is running.
--
-- v0.54 (10.0.5) ROUND 26. You report: [ (back to the hub) is useless; after trips with ] / Ctrl+]
-- the inventory was gone; some levels "don't work" when you warp to them. The log (a restored save
-- that continues on Viceron) shows the hub calling the save's own planet "the game's own story"
-- and sending you back to Nefarious City: h.finished_at, a frame number of an EARLIER session,
-- was saved with the hub's state, and frame numbers start at 0 again in every session, so the
-- 2-minute guard after a finished destination held for the whole first stretch of the next one.
--   * the guards after a finish and after the hub start are this session's only (H.session)
--   * [ no longer takes you back to the hub; it only cancels the automatic trip back after a
--     finished destination. Ctrl+[ twice still finishes a destination by hand
--   * 0 turns PLANET SHUFFLE off and on (H.set_shuffle): off, the hub and the levels lock leave
--     travel to the game (no trip undone, no warp, no story started, no send-back, the travel
--     byte and level bits this session turned on are taken back); items stay randomized. The
--     choice is part of the randomizer state the companion saves, and survives a New Game
--   * Ctrl+0 twice gives back everything the randomizer knows you own (09_rando_real.lua
--     G.restore_inventory); after the hub's own trips and after a load on another planet this
--     happens by itself when the load reports fewer than half of your weapons
--   * apply_world records the travel byte as its own only when it was off before, and the record
--     is dropped at every planet change (a load sets the save's own values): turning shuffle off
--     never turns off a travel the game itself has on
--
-- Keys (8.3 defaults; legacy_f_keys keeps F6/F5): ] next destination, Ctrl+] go, [ cancels an
-- automatic return, Ctrl+[ twice finish this destination by hand, / start the story of the planet
-- you are on, 0 planet shuffle off/on, Ctrl+0 twice give your items back.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["15_rando_hub"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)
RANDO_HUB = RANDO_HUB or {}
local H = RANDO_HUB
local C = RANDO_CAMPAIGN
local DB = RANDO_DATA
H.VERSION = "10.0.5"

local function log(...) pcall(rivet.log, "[rando]", "RANDO-HUB", ...) end
local function S() return RANDO and RANDO.state end
local function SEED() return RANDO_SEED end
local function D() return RANDO_CAMPAIGN_RT end
local function cfg(k, default)
  local c = RANDO and RANDO.config
  if c and c[k] ~= nil then return c[k] end
  return default
end
local function say(text, opts) if RANDO and RANDO.say then RANDO.say(text, opts) else pcall(rivet.notify, text, opts) end end
local function pname(pid) return (RANDO and RANDO.planet_name and RANDO.planet_name(pid)) or tostring(pid) end
local function changed() if RANDO and RANDO.mark_changed then RANDO.mark_changed() end end
local function K(setting, ctrl) return (RANDO and RANDO.key and RANDO.key(setting, ctrl)) or setting end
local function history(msg) if RANDO and RANDO.history then RANDO.history(msg) else log(msg) end end
local function now() return (rivet.time and rivet.time()) or 0 end
-- the hub's name in messages ("Nefarious City"; the seed's plan names the planet)
local function HUBN()
  local p = H.plan()
  if p and p.planet then return pname(p.planet) end
  return (C and C.HUB_NAME) or "the hub"
end
H.hub_name = HUBN

H.SETTLE = 180              -- after a landing, before acting (scene, hero, HUD)
H.ARRIVE_TIMEOUT = 3600     -- a trip that has not landed after this is tried another way
H.MENU_WINDOW = 180         -- seconds a planet-menu choice waits for its landing
H.NEXT_MISSION_WAIT = 600   -- after a visit's mission completes, before acting on the next one
H.ORDER_KEPT_WAIT = 900     -- an undone story trip waits this long for the new planet's first loaded checkpoint
H.STARTUP_GUARD = 7200      -- after the hub starts, the game's own travel is undone
H.TRIGGER_TIMEOUT = 5400    -- New Game seen but the wrench never came: go anyway
H.RELEASE_SETTLE = 120      -- v0.51: frames with no parade sequence running (Ratchet walking) before the warp
H.RELEASE_TIMEOUT = 1800    -- v0.51: frames after the wrench when the warp goes even without GOING_DOWN done
-- v0.51: MIS_INTRO objectives during which Ratchet is in a scripted sequence (no warp then)
H.BUSY_MARKS = { "GOING_DOWN", "CINE", "CUTSCENE" }
H.CONFIRM = 4               -- seconds for the second press
H.STUCK_WAIT = 1200         -- after a launch, frames before a story still at "go to" is loaded again
H.HERO_EVERY = 60
H.HERO_TRIES = 15
H.LEARN_WINDOW = 7200       -- frames after a launch in which a destination's start is learned
H.INTRO_FALLBACK = { "CHK_MALINON_INTRO_DEFAULT" }   -- listed by your game (rounds 19-20 catalog)
H.OPENING_WAIT = 900        -- v0.52: frames the hub waits for an opening checkpoint's name (the catalog)
H.OPENING_POLL = 30         -- v0.52: how often it looks while waiting
H.OPENING_STUCK_WAIT = 3600 -- v0.52: after a load at an opening, frames before a story still at "go to" is loaded again

H.frame = 0
H.session = H.session or { new_game = nil, wrench = nil, started = {}, reloaded = {} }
H.session.started = H.session.started or {}
H.session.reloaded = H.session.reloaded or {}
H.session.busy = H.session.busy or {}   -- v0.51: parade objectives running a scripted sequence
H.expect = nil              -- our own trip in flight: { planet, dest, at, how, cp, why }
H.menu = nil                -- the last planet-menu choice: { planet, dest, at }
H.pending = nil             -- deferred actions: { at, fn, why }
H.ladder = nil              -- the mission ladder running for a destination
H.sel = 0                   -- ] selection (not saved)
H.launch = nil              -- the destination being launched: { id, at }
H.intro_restart = nil       -- frame until which a restarted prologue is not a New Game

-- ---------------------------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------------------------
function H.plan() local sd = SEED(); return sd and sd.hub end
-- v0.54: planet shuffle switched off with the 0 key (saved in the randomizer state)
function H.shuffle_off() local s = S(); return s ~= nil and s.planet_shuffle_off == true end
function H.enabled() return H.plan() ~= nil and cfg("hub_runtime", true) ~= false and not H.shuffle_off() end
function H.state()
  local s = S()
  if not s then return nil end
  local h = s.hub
  if type(h) ~= "table" then h = {}; s.hub = h end
  h.done = h.done or {}
  h.n_done = h.n_done or 0
  h.attempts = h.attempts or {}
  h.by_hand = h.by_hand or {}
  h.phase = h.phase or "pre"
  h.obj = h.obj or {}               -- mission -> { o = last objective, s = its state }
  h.learned = h.learned or {}       -- destination id -> start checkpoint learned in this run
  return h
end
local function dest_by_id(id)
  local p = H.plan()
  for _, d in ipairs((p and p.destinations) or {}) do if d.id == id then return d end end
  return nil
end
H.dest = dest_by_id
-- v0.51: the hub planet's own story (nefcity_1): the plan's first "hub" destination
function H.hub_story()
  local p = H.plan()
  for _, d in ipairs((p and p.destinations) or {}) do
    if d.kind == "hub" and d.visit == 1 then return d end
  end
  return nil
end
-- v0.51: the hub's checkpoints in the order to try: while its story is not finished the first
-- (CHK_NEFCITY_START: the story resumes there), afterwards the plan's order reversed (the pad first)
function H.home_order()
  local p, h = H.plan(), H.state()
  local cps = {}
  for _, cp in ipairs((p and p.checkpoints) or {}) do cps[#cps + 1] = cp end
  local story = H.hub_story()
  if h and story and h.done[story.id] and #cps > 1 then
    local rev = {}
    for i = #cps, 1, -1 do rev[#rev + 1] = cps[i] end
    cps = rev
  end
  return cps
end
function H.home_checkpoint()
  return H.home_order()[1] or (H.state() and H.state().home_cp)
end
-- learned starts survive a New Game (they describe the game, not the run)
local function learned_store()
  local s = S()
  if not s then return {} end
  s.hub_learned = s.hub_learned or {}
  return s.hub_learned
end
function H.start_of(d)
  if d.start_cp then return d.start_cp, "registry" end
  local l = learned_store()[d.id]
  if l then return l, "learned" end
  return nil
end

-- what the player owns, for a destination's item requirements (the randomizer's own items)
local function owns(item)
  local s = S()
  return s and ((s.inventory and s.inventory[item]) or (s.gadgets_seen and s.gadgets_seen[item])) and true or false
end
-- destinations playable now (ids: the three starting missions first)
function H.available()
  local p, h, s = H.plan(), H.state(), S()
  if not (p and h and s) then return {} end
  return C.hub_available(p, h.done, s.access or {}, owns)
end
-- open planets whose destinations are all done or not open yet: offered to look around
function H.revisits()
  local p, h, s = H.plan(), H.state(), S()
  local out, seen = {}, {}
  if not (p and h and s) then return out end
  local playable = {}
  for _, id in ipairs(H.available()) do playable[dest_by_id(id).planet] = true end
  for _, pl in ipairs(DB.planets) do
    local pid = pl.id
    if s.access[pid] and not playable[pid] and pid ~= p.planet and not seen[pid] then
      seen[pid] = true
      out[#out + 1] = pid
    end
  end
  return out
end
-- the ] list: playable destinations, then "revisit" entries. v0.51: with hub_prologue = "end" the
-- prologue is not offered (it is written complete once you are at the hub; if that write is
-- refused, h.prologue_kept brings it back as a destination)
function H.menu_entries()
  local out = {}
  local h = H.state()
  local hide_intro = cfg("hub_prologue", "end") == "end" and not (h and h.prologue_kept)
  for _, id in ipairs(H.available()) do
    local d = dest_by_id(id)
    if not (hide_intro and d.kind == "intro") then out[#out + 1] = { dest = d } end
  end
  for _, pid in ipairs(H.revisits()) do out[#out + 1] = { revisit = pid } end
  return out
end

function H.status_text()
  if not H.plan() then return nil end
  local h = H.state()
  if not h then return nil end
  if not h.started then return "hub: not started (" .. K("key_hub", true) .. " goes to " .. HUBN() .. ")" end
  local total = #H.plan().destinations
  local cur = h.current and dest_by_id(h.current)
  local off = ""
  if H.shuffle_off() then off = " (planet shuffle OFF - " .. K("key_shuffle") .. " turns it on)"
  elseif not H.enabled() then off = " (hub_runtime off)" end
  return string.format("hub %d/%d done, %d open%s%s", h.n_done, total, #H.available(), cur and (" | at " .. cur.id) or "", off)
end

-- ---------------------------------------------------------------------------------------------
-- travel
-- ---------------------------------------------------------------------------------------------
-- a landing checkpoint for a planet: the hub's own, the registry entry, then 14's
function H.landing_for(d_or_pid)
  local pid, entry = d_or_pid, nil
  if type(d_or_pid) == "table" then pid, entry = d_or_pid.planet, d_or_pid.entry end
  local p = H.plan()
  if p and pid == p.planet then return H.home_checkpoint(), "the hub" end
  if entry then return entry, "registry" end
  if RANDO_TRAVEL and RANDO_TRAVEL.checkpoint_for then
    local ok, cp, how = pcall(RANDO_TRAVEL.checkpoint_for, pid)
    if ok and cp then return cp, how end
  end
  return nil, "no checkpoint known"
end

-- go to checkpoint cp on planet pid: fly when asked and a ship answers, else warp
function H.go(pid, cp, d, prefer_fly, why)
  local method, ok, res = nil, false, nil
  if prefer_fly and cfg("hub_fly", true) then
    ok, res = pcall(rivet.fly, cp)
    method = "fly"
    if not ok then log("fly to", cp, "refused:", tostring(res), "- warping instead") end
  end
  if not ok then
    ok, res = pcall(rivet.warp, cp)
    method = "warp"
  end
  if not ok or res == false then
    log("trip to", pid, "at", cp, "failed:", tostring(res))
    return false, tostring(res)
  end
  log("travel:", method, "to", cp, "for", pid, d and d.id or "", why or "", tostring(res))
  -- a warp on the planet you are on loads its checkpoint without a planet change: nothing to wait for
  if S() and S().current_planet == pid and method == "warp" then
    if d then H.state().phase = (pid == H.plan().planet) and H.state().phase or "away" end
    H.watch_inventory("the warp to " .. tostring(cp), true)
    return true
  end
  H.expect = { planet = pid, dest = d and d.id or nil, at = H.frame, how = method, cp = cp, why = why }
  return true
end

-- the warp to the hub (start, return): H.home_order(), then the checkpoint last landed on there,
-- then a checkpoint of the hub's code (NEFCITY) the game lists, as the last resort
function H.home_candidates()
  local p = H.plan()
  local out, seen = {}, {}
  local function add(cp) if cp and not seen[cp] then seen[cp] = true; out[#out + 1] = cp end end
  local h = H.state()
  for _, cp in ipairs(H.home_order()) do add(cp) end
  add(h and h.home_cp)
  local code = p and p.checkpoints and p.checkpoints[1] and p.checkpoints[1]:match("^CHK_([A-Z]+)_")
  local ok, list = false, nil
  if code then ok, list = pcall(rivet.checkpoints, code) end
  if ok and type(list) == "table" then
    local names = {}
    for _, c in ipairs(list) do
      local n = type(c) == "table" and (c.name or c[1]) or c
      if type(n) == "string" and not n:find("TRANSITION", 1, true) then names[#names + 1] = n end
    end
    table.sort(names)
    for _, want in ipairs({ "LANDING", "DEFAULT", "SHIP", "START" }) do
      for _, n in ipairs(names) do if n:find(want, 1, true) then add(n) end end
    end
  end
  return out
end
H.zurk_candidates = H.home_candidates     -- the 10.0 name
function H.go_home(why)
  local p, h = H.plan(), H.state()
  if not (p and h) then return false end
  local cands = H.home_candidates()
  local start = (H.expect and H.expect.planet == p.planet and H.expect.cand or 0) + 1
  for i = start, #cands do
    local ok, res = pcall(rivet.warp, cands[i])
    if ok and res ~= false then
      log("warp to the hub (" .. HUBN() .. ") at", cands[i], "(" .. tostring(why) .. ")", tostring(res))
      -- a warp on the hub planet itself reloads the checkpoint without a planet change: no arrival
      -- will come to wait for (10.0 waited ARRIVE_TIMEOUT and tried the next checkpoint)
      if h.started and S() and S().current_planet == p.planet then
        H.expect = nil
        h.phase = "hub"
        return true
      end
      H.expect = { planet = p.planet, at = H.frame, how = "warp", cp = cands[i], cand = i, why = why }
      return true
    end
    log("warp to", cands[i], "failed:", tostring(res))
  end
  H.expect = nil
  return false
end

-- ---------------------------------------------------------------------------------------------
-- New Game -> the hub
-- ---------------------------------------------------------------------------------------------
function H.new_game()
  H.expect, H.menu, H.pending, H.ladder, H.sel, H.launch = nil, nil, nil, nil, 0, nil
  H.return_at, H.hero_job, H.watching, H.intro_restart, H.order_kept = nil, nil, nil, nil, nil
  H.ending_prologue = nil
  H.session.started, H.session.reloaded, H.session.started_frame = {}, {}, nil
  H.session.finished_frame = nil                       -- v0.54: this session's last finish
  H.session.opening_loaded = {}
  H.session.world = { travel = false, levels = {} }   -- a new game clears both (v0.53)
  local h = H.state()
  if h then h.phase = "pre" end
  log("new game: the parade plays until Ratchet has his wrench and the parade hands him back, then " .. HUBN())
end

-- a prologue the hub restarts must not count as a New Game (10_rando_runtime.lua asks)
function H.intro_restarting() return H.intro_restart ~= nil and H.frame <= H.intro_restart end

local function busy_objective(objective)
  for _, mark in ipairs(H.BUSY_MARKS) do if objective:find(mark, 1, true) then return true end end
  return false
end

-- every ObjectiveStateChangedEvent (also before the seed is ready)
function H.on_objective(mission, objective, state)
  if type(mission) == "string" and type(objective) == "string" and H.plan() and S() then
    local h = H.state()
    if h then
      h.obj[mission] = { o = objective, s = state, f = H.frame }
      -- v0.52: the steps of the story being played always reach rivet.log (RANDO-DISCOVER stops
      -- after discovery_cap lines of a kind; round 23's city steps were cut off that way)
      local cur = h.current and dest_by_id(h.current)
      local o = cur and C.OPENINGS and C.OPENINGS[cur.id]
      local mine = false
      for _, m in ipairs((cur and cur.missions) or {}) do if m == mission then mine = true end end
      for _, m in ipairs((o and o.with) or {}) do if m == mission then mine = true end end
      if mine then log("objective", mission, objective, tostring(state)) end
    end
  end
  if mission ~= "MIS_INTRO" or type(objective) ~= "string" then return end
  local ss = H.session
  if objective == "OBJ_INTRO_PARADE_START_CINE" and state == 1 and not H.intro_restarting() then
    ss.new_game, ss.wrench, ss.released, ss.busy, ss.busy_changed = H.frame, nil, nil, {}, nil
  elseif objective == "OBJ_INTRO_PARADE_PICKUP_WRENCH" and state == 2 then
    ss.wrench = ss.wrench or H.frame
  end
  -- v0.51: the parade's scripted sequences and when it hands Ratchet back
  ss.busy = ss.busy or {}
  if busy_objective(objective) then
    ss.busy[objective] = (state == 1) or nil
    ss.busy_changed = H.frame
  end
  if objective == "OBJ_INTRO_GOING_DOWN" and state == 2 and ss.wrench then ss.released = ss.released or H.frame end
end

-- is a parade sequence running? (and which one, for the log)
local function parade_busy()
  local names = {}
  for o in pairs(H.session.busy or {}) do names[#names + 1] = o end
  table.sort(names)
  return #names > 0, table.concat(names, ", ")
end

local function trigger_met()
  local ss = H.session
  if not ss.new_game then return false end
  local mode = cfg("hub_trigger", "parade")
  if mode == "cinematic" then return true end
  if not ss.wrench then return H.frame - ss.new_game >= H.TRIGGER_TIMEOUT, "the wrench did not come" end
  if mode == "wrench" then return true end
  -- "parade" (v0.51): after GOING_DOWN, no scripted sequence running, none started or ended for a
  -- moment (the parade's ordinary steps, such as walking the Veldin float, do not hold it back)
  if ss.released and not parade_busy() and H.frame - math.max(ss.busy_changed or 0, ss.released) >= H.RELEASE_SETTLE then
    return true, "the parade handed Ratchet back after his wrench"
  end
  if H.frame - ss.wrench >= H.RELEASE_TIMEOUT then
    local _, which = parade_busy()
    return true, ss.released and ("the parade still runs " .. which .. " " .. H.RELEASE_TIMEOUT .. " frames after the wrench")
                 or ("OBJ_INTRO_GOING_DOWN was not reported done " .. H.RELEASE_TIMEOUT .. " frames after the wrench")
  end
  return false
end
H.trigger_met = trigger_met

-- the parade's checkpoint when we leave it: the prologue resumes there
local function remember_parade()
  local h = H.state()
  local T = RANDO_TRAVEL
  local last = T and T.last_checkpoint
  if last and last.planet == "corson_v" then
    h.parade_hash = last.hash
    h.parade_cp = last.name or (T.name_of_hash and T.name_of_hash(last.hash)) or h.parade_cp
    log("the parade is at checkpoint", tostring(h.parade_cp or "?"), string.format("(hash %s)", tostring(last.hash)),
        "- the prologue resumes there")
  else
    log("no parade checkpoint seen yet - the prologue will resume at", H.INTRO_FALLBACK[1])
  end
  changed()
end

function H.start_failed(why)
  local h = H.state()
  log("could not reach the hub (" .. HUBN() .. "):", why)
  say("Randomizer: could not reach " .. HUBN() .. " (" .. why .. ") - " .. K("key_hub") .. " / " .. K("key_hub", true) .. " work from anywhere",
      { type = "center", duration = 9 })
  H.hub_started("unreached")
  h.phase = "hub_unreached"
end

function H.menu_text()
  local lines = {}
  for i, e in ipairs(H.menu_entries()) do
    if i > 6 then lines[#lines + 1] = "..."; break end
    if e.dest then lines[#lines + 1] = string.format("%d. %s", i, e.dest.label or (pname(e.dest.planet) .. ": " .. (e.dest.title or e.dest.id)))
    else lines[#lines + 1] = string.format("%d. revisit %s", i, pname(e.revisit)) end
  end
  return table.concat(lines, "  |  ")
end

function H.hub_started(how)
  local h = H.state()
  if h.started then return end
  h.started, h.started_how = true, how
  h.phase = "hub"
  H.session.started_frame = H.frame
  history("HUB: the campaign starts at " .. HUBN() .. " (" .. tostring(how) .. ")")
  log("start menu:", H.menu_text())
  local story = H.hub_story()
  local running = story and h.current == story.id and not h.done[story.id]
  say(HUBN() .. " - the hub" .. (running and ": its story starts here. " or ". ") .. K("key_hub") .. " lists what is open, "
      .. K("key_hub", true) .. " goes", { type = "planet", sub = H.menu_text(), duration = 12 })
  changed()
  H.after(H.SETTLE, function() H.apply_world("hub start") end, "hub start")
  H.after(H.SETTLE, function() H.prologue_check() end, "prologue")
end

-- v0.51: end the prologue once you are on the hub planet (never while still in the parade)
function H.prologue_check()
  local h, p, s = H.state(), H.plan(), S()
  if not (h and p and s) or h.prologue_ended or s.current_planet ~= p.planet then return end
  H.end_prologue()
end

function H.at_hub(how)
  local h = H.state()
  if not h.started then return H.hub_started(how) end
  h.phase = "hub"
  local cur = h.current and dest_by_id(h.current)
  if cur and cur.kind ~= "hub" then h.current = nil; H.ladder = nil end
  if not (cur and cur.kind == "hub" and not h.done[cur.id]) then
    H.after(60, function()
      if H.expect or H.launch then return end
      H.ensure_hero("ratchet", nil, "back at the hub")
    end, "back to Ratchet")
  end
  local fresh = h.unannounced or {}
  h.unannounced = nil
  if #fresh > 0 then
    local names = {}
    for _, id in ipairs(fresh) do local d = dest_by_id(id); names[#names + 1] = d and (pname(d.planet) .. " (" .. (d.title or id) .. ")") or id end
    say("Now open: " .. table.concat(names, ", "), { type = "planet", sub = H.menu_text(), duration = 10 })
  else
    say(string.format("%s: %d destination(s) open - %s next, %s go", HUBN(), #H.available(), K("key_hub"), K("key_hub", true)),
        { type = "corner", duration = 6 })
  end
  changed()
  H.after(H.SETTLE, function() H.apply_world("at the hub") end, "at the hub")
  if not h.prologue_ended then H.after(H.SETTLE, function() H.prologue_check() end, "prologue") end
end

-- ---------------------------------------------------------------------------------------------
-- the game's state (rando_give.dll: mission calls, v6 travel flag and level bits)
-- ---------------------------------------------------------------------------------------------
local function call(kind, name, cb, flag, value)
  local d = D()
  if not d then if cb then cb({ code = -2, why = "11_rando_campaign.lua is missing" }) end; return end
  d.mission_call(kind, name, cb, flag, value)
end
local function describe(r)
  local d = D()
  local names = d and d.STATE_NAMES or {}
  if d and d.NAMELESS and d.NAMELESS[r.kind] then
    return string.format("%s (0x%X -> 0x%X)", d.RESULT[r.code] or tostring(r.code), r.before or 0, r.after or 0)
  end
  return string.format("%s (%s -> %s)", d and d.RESULT[r.code] or tostring(r.code),
                       r.before and (names[r.before] or tostring(r.before)) or "?", r.after and (names[r.after] or tostring(r.after)) or "?")
end
H.describe = describe

-- round 17: with the travel byte on and level bits 1-10 set, the planet menu offered Blizar and
-- Savali at Zurkie's. A save load clears the bits (8.1), so they are put back on every arrival.
--
-- v0.53 (10.0.4) NOT WHILE A STORY RUNS. Round 25: in Nefarious City's boss fight
-- (CHK_NEFCITY_HEAVY_FIGHT) the story's own rift shifts Ratchet to Savali or Sargasso
-- (CHK_NEFCITY_HEAVYSHIFT_SAVALI) and back. The travel byte had been turned on at the hub (and
-- again on every return from a shift, after the death reload cleared it), so the game played the
-- shift as a SHIP LANDING: Ratchet came down with the ship where the shift's ground is not solid,
-- fell and died, several times. In the game the city's story runs with both off (no ship yet). So
-- while a destination is being played, the world is left as the game has it: nothing is turned
-- on, and what this session turned on is taken back before the hub's own story is launched. The
-- byte and the bits go on again once no destination is running (at the hub, a finished story).
H.session.world = H.session.world or { travel = false, levels = {} }

-- the destination being played, if any (not finished)
function H.running()
  local h = H.state()
  local cur = h and h.current and dest_by_id(h.current)
  if cur and not h.done[cur.id] then return cur end
  return nil
end

function H.apply_world(why)
  local dd = D()
  if not (dd and dd.native_ok and dd.native_ok("level_read")) then return end
  local cur = H.running()
  if cur then
    log("planetary travel and level bits left to the game while", cur.id, "runs (its own rifts)", why and ("(" .. why .. ")") or "")
    return
  end
  local w = H.session.world
  if cfg("hub_travel_flag", true) then
    call("travel_set", nil, function(r)
      log("planetary travel:", describe(r))
      -- v0.54: ours to take back only when the game had it off (0x1 -> 0x1 is the game's own)
      if r.code == 11 and r.after == 1 and r.before ~= 1 then w.travel = true end
    end, 1)
  end
  if cfg("hub_levels", "all") ~= "all" then return end
  call("level_read", nil, function(r)
    if r.code ~= 11 then log("levels:", describe(r)); return end
    local want = 0x7FE
    if ((r.after or 0) & want) == want then return end
    log(string.format("level bits 0x%X - unlocking 1-10", r.after or 0))
    for level = 1, 10 do
      if ((r.after or 0) >> level) & 1 == 0 then
        call("level_set", nil, function(res) if res.code == 11 then w.levels[level] = true end end, 1, level)
      end
    end
  end)
end

-- v0.53: take back what apply_world turned on in this session (the travel byte, the level bits it
-- set), so a story starts with the game's own world. A load since then has cleared them already;
-- writing them off again changes nothing.
function H.take_back_world(why)
  local w = H.session.world
  local levels = {}
  for level in pairs(w.levels) do levels[#levels + 1] = level end
  table.sort(levels)
  if not w.travel and #levels == 0 then return false end
  local dd = D()
  if not (dd and dd.native_ok and dd.native_ok("level_read")) then return false end
  if w.travel then
    call("travel_set", nil, function(r) log("planetary travel off (" .. tostring(why) .. "):", describe(r)) end, 0)
  end
  for _, level in ipairs(levels) do call("level_set", nil, function(res) end, 0, level) end
  if #levels > 0 then log("level bits taken back (" .. tostring(why) .. "):", table.concat(levels, ",")) end
  H.session.world = { travel = false, levels = {} }
  return true
end

-- ---------------------------------------------------------------------------------------------
-- heroes (8.4: rivet.hero_play_as answers "already playing as that hero" exactly when it is)
-- ---------------------------------------------------------------------------------------------
function H.is_already(res) return tostring(res):find("already playing", 1, true) ~= nil end
function H.ensure_hero(hero, cb, why)
  cb = cb or function() end
  if not hero or not cfg("hub_hero_swap", true) then return cb(true, "no swap") end
  local tries, asked = 0, false
  local job = { hero = hero }
  H.hero_job = job
  local function try()
    if H.hero_job ~= job then return end
    tries = tries + 1
    local ok, res = pcall(rivet.hero_play_as, hero)
    if not ok and H.is_already(res) then
      log("hero:", hero, asked and ("confirmed after the swap (" .. tries .. " checks)") or "confirmed", why and ("(" .. why .. ")") or "")
      H.hero_job = nil
      return cb(true, asked and "swapped" or "already")
    end
    if ok then
      if not asked then log("hero: swapping to", hero, "-", tostring(res), why and ("(" .. why .. ")") or "") end
      asked = true
    else
      log("hero: swap to", hero, "refused:", tostring(res), "(check " .. tries .. ")")
    end
    if tries >= H.HERO_TRIES then
      log("hero:", hero, "NOT confirmed after", tries, "checks - going on anyway")
      H.hero_job = nil
      say(string.format("Randomizer: could not switch to %s (%s)", hero, tostring(res)), { type = "center", duration = 8 })
      return cb(false, tostring(res))
    end
    H.after(H.HERO_EVERY, try, "hero " .. hero)
  end
  try()
end

-- ---------------------------------------------------------------------------------------------
-- a destination's story
-- ---------------------------------------------------------------------------------------------
local function set_attempt(d, what, detail)
  local h = H.state()
  h.attempts[d.id] = { what = what, detail = detail, frame = H.frame }
  changed()
  log("destination", d.id .. ":", what, detail or "")
end
function H.explore(d, why)
  set_attempt(d, "explore", why)
  say(string.format("%s: the story could not be started (%s) - explore; %s twice finishes it by hand", pname(d.planet), tostring(why),
                    K("key_hub_return", true)), { type = "center", duration = 9 })
end

-- the visit's mission to act on: the first one the game knows that is not complete
local function next_mission(d, answers)
  local real = {}
  for _, m in ipairs(d.missions or {}) do
    local r = answers[m]
    if r and r.code == 11 then real[#real + 1] = { name = m, state = r.after } end
  end
  for _, x in ipairs(real) do
    if x.state ~= 3 and x.state ~= 4 then return x, real end
  end
  return nil, real
end
H.next_mission = next_mission

function H.goto_step(objective)
  return type(objective) == "string" and (objective:find("_GO_TO_", 1, true) ~= nil or objective:find("_GOTO_", 1, true) ~= nil)
end
function H.waiting_goto(name)
  local h = H.state()
  local last = h and h.obj[name]
  return last ~= nil and H.goto_step(last.o) and last.s ~= 2
end

-- the mission ladder (no travel): cb(result, how, mission) with result "running", "complete",
-- "explore". The hero is confirmed first.
function H.activate(d, cb)
  cb = cb or function() end
  local dd = D()
  if not dd then return cb("explore", "11_rando_campaign.lua is missing") end
  local ok, why = dd.native_ok("query")
  if not ok then return cb("explore", why) end
  local token = {}
  H.ladder = { d = d.id, token = token }
  local function live() return H.ladder and H.ladder.token == token end
  H.ensure_hero(d.hero, function(okh)
    if not live() then return end
    dd.refresh(d.missions or {}, function(answers)
      if not live() then return end
      local m, real = next_mission(d, answers)
      if #real == 0 then H.ladder = nil; return cb("explore", "none of " .. table.concat(d.missions or {}, ", ") .. " is a mission in your game") end
      if not m then H.ladder = nil; return cb("complete", "its missions are already complete") end
      local function running(how) H.ladder = nil; H.session.started[m.name] = H.frame; cb("running", how, m.name) end
      local function replay_then_explore(why2)
        call("replay", m.name, function(rr)
          if not live() then return end
          log("replay", m.name, describe(rr))
          if rr.code == 11 and rr.after == 2 then return running("replayed") end
          H.ladder = nil
          cb("explore", why2 .. "; replay: " .. describe(rr))
        end)
      end
      local function start(how)
        call("start", m.name, function(r)
          if not live() then return end
          log("start", m.name, describe(r))
          if r.code == 11 and r.after == 2 then return running(how or "started") end
          if r.code == 11 and (r.after == 3 or r.after == 4) then H.ladder = nil; return cb("complete", "completed on start") end
          if cfg("hub_replay", true) then return replay_then_explore("start: " .. describe(r)) end
          H.ladder = nil; cb("explore", "start: " .. describe(r))
        end)
      end
      log("destination", d.id, "mission", m.name, "is", dd.STATE_NAMES[m.state] or tostring(m.state),
          "(hero " .. tostring(d.hero) .. (okh and " confirmed)" or " NOT confirmed)"))
      if m.state == 2 then H.ladder = nil; return cb("running", "already active", m.name) end
      if m.state == 1 then return start() end
      if m.state == 0 and cfg("hub_force_missions", true) then
        local okv, whyv = dd.native_ok("set_state")
        if not okv then return replay_then_explore("inactive and " .. whyv) end
        if d.kind == "intro" then H.intro_restart = H.frame + 1800 end
        return call("set_state", m.name, function(w)
          if not live() then return end
          log("made available", m.name, describe(w))
          if w.code == 11 and w.after == 1 then return start("made available, then started") end
          replay_then_explore("making it available: " .. describe(w))
        end, 1)
      end
      replay_then_explore("it is " .. (dd.STATE_NAMES[m.state] or tostring(m.state)))
    end)
  end, d.id)
end

-- ---------------------------------------------------------------------------------------------
-- v0.52 a visit's opening scene (03_rando_campaign.lua C.OPENINGS)
-- ---------------------------------------------------------------------------------------------
function H.opening_of(d) return d and C.OPENINGS and C.OPENINGS[d.id] or nil end
-- is checkpoint name cp one of the openings? (by its hash)
function H.is_opening_cp(cp)
  local T = RANDO_TRAVEL
  if type(cp) ~= "string" or not (T and T.hash and C.OPENINGS) then return false end
  local x = T.hash(cp)
  for _, o in pairs(C.OPENINGS) do if o.hash == x then return true end end
  return false
end
-- the opening is where to load while the story has not left its first step ("go to <planet>")
function H.opening_wanted(d)
  local o = H.opening_of(d)
  if not (o and o.hash) or not cfg("hub_opening", true) then return false end
  local h = H.state()
  local m = (d.missions or {})[1]
  local last = h and m and h.obj[m]
  return last == nil or H.waiting_goto(m)
end
-- the opening checkpoint's name: known, or found under the visit's codes now. Returns name, how
function H.opening_cp(d)
  local o = H.opening_of(d)
  local T = RANDO_TRAVEL
  if not (o and o.hash and T and T.find_hash) then return nil end
  local okf, name, how = pcall(T.find_hash, o.hash, o.codes)
  if okf and name then return name, how end
  return nil
end
-- the city's checkpoints for rivet.log (the next round names the opening if it is listed elsewhere)
local function log_planet_checkpoints(pid)
  local T = RANDO_TRAVEL
  if not (T and T.describe_planet) then return end
  local ok, text = pcall(T.describe_planet, pid, 120)
  if ok then log("checkpoints listed for", pid .. ":", text) end
end
-- cb(cp, how, is_start): where to load d now. Waits up to H.OPENING_WAIT frames for an opening's
-- name while the checkpoint catalog fills; then the destination's ordinary load point.
function H.with_load_point(d, cb)
  if not H.opening_wanted(d) then return cb(H.load_point(d)) end
  local o = H.opening_of(d)
  local t0 = H.frame
  local function look()
    local name, how = H.opening_cp(d)
    if name then
      log(string.format("opening of %s: %s (hash %d, %s)", d.id, name, o.hash, tostring(how)))
      return cb(name, "its opening scene", true)
    end
    local T = RANDO_TRAVEL
    local catalog_done = T and T.catalog and T.catalog.done
    if not catalog_done and H.frame - t0 < H.OPENING_WAIT then
      return H.after(H.OPENING_POLL, look, "opening " .. d.id)
    end
    local cp, cphow, is_start = H.load_point(d)
    log(string.format("opening of %s: hash %d is not among the checkpoints your game lists%s - loading %s (%s) instead",
                      d.id, o.hash, catalog_done and "" or (" (the catalog was not complete after " .. H.OPENING_WAIT .. " frames)"),
                      tostring(cp), tostring(cphow)))
    log_planet_checkpoints(d.planet)
    cb(cp, cphow, is_start)
  end
  look()
end
-- the missions the game opens together with d's story (C.OPENINGS .with): inactive ones are made
-- available (rando_give.dll v6), as the game itself did in round 23. cb() when done.
function H.open_with(d, cb)
  cb = cb or function() end
  local o = H.opening_of(d)
  local list = (o and o.with) or {}
  local dd = D()
  if #list == 0 or not dd then return cb() end
  if not (dd.native_ok("query") and dd.native_ok("set_state")) then return cb() end
  dd.refresh(list, function(answers)
    local left = 0
    local todo = {}
    for _, m in ipairs(list) do
      local r = answers[m]
      if r and r.code == 11 and r.after == 0 then todo[#todo + 1] = m
      elseif r then log("with", d.id .. ":", m, r.code == 11 and (dd.STATE_NAMES[r.after] or tostring(r.after)) or (dd.RESULT[r.code] or tostring(r.code))) end
    end
    left = #todo
    if left == 0 then return cb() end
    for _, m in ipairs(todo) do
      call("set_state", m, function(w)
        log("with", d.id .. ": made available", m, describe(w))
        left = left - 1
        if left == 0 then cb() end
      end, 1)
    end
  end)
end

-- where to load a destination: its own start (registry or learned), the prologue's parade
-- checkpoint, else its landing. Returns cp, how, is_start
function H.load_point(d)
  local h = H.state()
  if d.kind == "intro" then
    local cp = h.parade_cp
    if not cp and h.parade_hash and RANDO_TRAVEL and RANDO_TRAVEL.name_of_hash then cp = RANDO_TRAVEL.name_of_hash(h.parade_hash); h.parade_cp = cp end
    if cp then return cp, "where the parade was left", true end
    return H.INTRO_FALLBACK[1], "the prologue's default (no parade checkpoint seen)", true
  end
  local cp, how = H.start_of(d)
  if cp then return cp, how, true end
  cp, how = H.landing_for(d)
  return cp, how, false
end

-- Ctrl+]: launch destination d (from anywhere)
function H.launch_dest(d, why)
  local h = H.state()
  if H.launch then return say("Randomizer: getting " .. tostring(H.launch.id) .. " ready...", { type = "corner", duration = 3 }) end
  H.return_at, H.order_kept = nil, nil
  H.launch = { id = d.id, at = H.frame }
  h.current = d.id
  changed()
  say(string.format("Randomizer: %s - getting the story ready", d.label or (pname(d.planet) .. ": " .. (d.title or d.id))), { type = "corner", duration = 5 })
  log("launch", d.id, "(" .. tostring(why) .. ")")
  -- v0.53: the hub's own story is played on the planet you are on (no load clears the world):
  -- its rifts must find the travel byte and the level bits as the game has them (round 25)
  if d.kind == "hub" then H.take_back_world("launch " .. d.id) end
  H.activate(d, function(result, how, mission)
    if result == "complete" then
      H.launch = nil
      H.finish(d, how)
      return
    end
    if result == "explore" then H.explore(d, how) else set_attempt(d, "story", tostring(mission) .. " " .. tostring(how)) end
    -- v0.52: the missions the game opens with the story, then where to load (an opening scene's
    -- name may take the catalog a moment); H.launch stays set until the trip leaves
    local function travel(cp, cphow, is_start)
      H.launch = nil
      if not cp then
        log("no checkpoint for", d.id, "-", tostring(cphow))
        say("Randomizer: no warp point known for " .. pname(d.planet) .. " yet - fly there from the ship's planet menu",
            { type = "center", duration = 8 })
        return
      end
      -- a start checkpoint is warped to (the game's own way of loading a mission's start); a mere
      -- landing is flown to when a ship answers
      local at_hub = S().current_planet == H.plan().planet
      local okg, err = H.go(d.planet, cp, d, (not is_start) and at_hub, "launch " .. d.id .. " (" .. tostring(cphow) .. ")")
      if not okg then
        say("Randomizer: the trip to " .. pname(d.planet) .. " failed (" .. tostring(err) .. ")", { type = "center", duration = 6 })
        return
      end
      if result == "running" and mission then H.watch_story(d, mission, cp) end
    end
    if result == "running" then
      H.open_with(d, function() H.with_load_point(d, travel) end)
    else
      travel(H.load_point(d))
    end
  end)
end

-- a story should leave its "go to <planet>" step soon after its planet loads with its hero. If
-- it has not after H.STUCK_WAIT frames, the load point is loaded once more (8.4 went out to
-- Zurkie's and back; round 22 crashed right after such a round trip, so 10.0 stays on the planet).
function H.watch_story(d, name, cp)
  local token = {}
  H.watching = H.watching or {}
  H.watching[d.id] = token
  -- v0.52: an opening scene is given longer (a reload must not cut it short), and its reload is
  -- the opening again
  local opening = H.opening_of(d)
  local at_opening = opening and opening.hash and type(cp) == "string" and RANDO_TRAVEL and RANDO_TRAVEL.hash
                     and RANDO_TRAVEL.hash(cp) == opening.hash
  H.after(at_opening and H.OPENING_STUCK_WAIT or H.STUCK_WAIT, function()
    if H.watching[d.id] ~= token then return end
    H.watching[d.id] = nil
    local h = H.state()
    if h.done[d.id] or h.current ~= d.id then return end
    local last = h.obj[name]
    if not H.waiting_goto(name) then
      log("story", name, last and ("is at " .. tostring(last.o)) or "reported no step yet")
      return
    end
    if S().current_planet ~= d.planet then log("story", name, "waits for", d.planet, "- you are on", tostring(S().current_planet)); return end
    if H.session.reloaded[d.id] then
      log("story", name, "still at", last.o, "after a reload")
      say(string.format("%s: the story still waits at its first step - press %s to load it again, or %s twice to finish by hand",
                        pname(d.planet), K("key_story"), K("key_hub_return", true)), { type = "center", duration = 9 })
      return
    end
    H.session.reloaded[d.id] = H.frame
    -- the other load point when there is one (start <-> landing); v0.52: an opening is loaded again
    local alt = cp
    local land = H.landing_for(d)
    local start = H.start_of(d)
    if at_opening then alt = cp
    elseif cp == start and land then alt = land elseif start and cp ~= start then alt = start end
    log("story", name, "still at", last.o, "- loading", alt, "once more")
    history(string.format("[STORY RELOAD] %s at %s", d.id, tostring(alt)))
    H.ensure_hero(d.hero, function() H.go(d.planet, alt, d, false, "reload " .. d.id) end, "reload " .. d.id)
  end, "watch " .. name)
end

-- ---------------------------------------------------------------------------------------------
-- v0.51 the hub start (after the story functions it uses)
-- ---------------------------------------------------------------------------------------------
-- v0.51: the hub's first warp. Like the game after the prologue (round 23), the city's story is
-- made active first (hero confirmed, available, start), then the city loads at the story's start.
-- Whatever the ladder answers, the warp goes: CHK_NEFCITY_START is also the hub's first checkpoint.
function H.begin_hub(why)
  local h = H.state()
  if not h or h.started then return end
  h.phase = "to_hub"
  remember_parade()
  changed()
  log("going to the hub (" .. HUBN() .. "):", why)
  local story = H.hub_story()
  if not (story and cfg("hub_start_story", true) and not h.done[story.id]) then
    say("Randomizer: to " .. HUBN() .. " - the hub", { type = "center", duration = 6 })
    if not H.go_home("hub start") then H.start_failed("no checkpoint of " .. HUBN() .. " could be warped to") end
    return
  end
  say("Randomizer: to " .. HUBN() .. " - the hub; its story starts there", { type = "center", duration = 6 })
  H.launch = { id = story.id, at = H.frame }
  h.current = story.id
  local function travel(result, mission, cp, cphow)
    H.launch = nil
    if cp and H.go(story.planet, cp, story, false, "hub start: " .. story.id .. " (" .. tostring(cphow) .. ")") then
      if result == "running" and mission then H.watch_story(story, mission, cp) end
      return
    end
    if not H.go_home("hub start") then H.start_failed("no checkpoint of " .. HUBN() .. " could be warped to") end
  end
  local function story_then_travel()
    H.activate(story, function(result, how, mission)
      log("hub start:", story.id, result, tostring(how), tostring(mission or ""))
      if result == "explore" then set_attempt(story, "explore", how)
      elseif result == "running" then set_attempt(story, "story", tostring(mission) .. " " .. tostring(how)) end
      if result == "complete" then h.current = nil; return travel(result, mission, nil) end
      if result ~= "running" then return travel(result, mission, H.start_of(story), "its start") end
      -- v0.52: the missions the game opens with it, then the opening scene (or the start)
      H.open_with(story, function()
        H.with_load_point(story, function(cp, cphow) travel(result, mission, cp, cphow) end)
      end)
    end)
  end
  -- v0.52 (hub_prologue_timing = "before"): the prologue complete before the city's story starts,
  -- as in the game (round 23); "after" is v0.51's order (written once on Nefarious City)
  if cfg("hub_prologue", "end") == "end" and cfg("hub_prologue_timing", "before") == "before" then
    H.end_prologue(story_then_travel)
  else
    story_then_travel()
  end
end

-- v0.51 (hub_prologue = "end"): once at the hub, the prologue is written "Complete Finished" (4)
-- into its saved record (rando_give.dll v6), as kit 8.0 did after its warp in round 17, and its
-- locations pay. The game itself has it complete before it loads Nefarious City (round 23).
-- v0.52: cb() runs once the write has been answered (or at once when there is nothing to write);
-- hub_prologue_timing = "before" calls this before the city's story is started
function H.end_prologue(cb)
  cb = cb or function() end
  local h = H.state()
  if not h or cfg("hub_prologue", "end") ~= "end" then return cb() end
  local d
  for _, x in ipairs(H.plan().destinations) do if x.kind == "intro" then d = x end end
  if not d or h.done[d.id] then return cb() end
  local name = (d.missions or {})[1]
  local dd = D()
  local ok, why = false, "11_rando_campaign.lua is missing"
  if dd then ok, why = dd.native_ok("set_state") end
  if not (name and ok) then
    log("prologue: left active (" .. tostring(why) .. ") - it stays a destination")
    h.prologue_kept = true
    return cb()
  end
  H.ending_prologue = true
  call("set_state", name, function(w)
    H.ending_prologue = nil
    log("prologue:", name, "written Complete Finished:", describe(w))
    if w.code == 11 and (w.after == 3 or w.after == 4) then
      h.prologue_ended = true
      H.finish(d, "ended at the hub start", true)
    else
      log("prologue: left active - it stays a destination")
      h.prologue_kept = true
    end
    cb()
  end, 4)
end

-- ---------------------------------------------------------------------------------------------
-- finishing a destination
-- ---------------------------------------------------------------------------------------------
function H.locations_of(d)
  local out = {}
  local sd = SEED()
  for _, lid in ipairs(RANDO_GEN.sorted_keys(sd.locations)) do
    local loc = DB.locations[lid]
    if loc and (loc.kind == "planet" or loc.kind == "story" or loc.kind == "side") then
      if C.location_segment(lid, loc.planet) == d.id then out[#out + 1] = lid end
    end
  end
  return out
end

-- quiet (v0.51): a destination the hub itself closes (the prologue at the hub start): it pays,
-- but there is no message and no trip back
function H.finish(d, how, quiet)
  local h, p = H.state(), H.plan()
  if not (h and d) or h.done[d.id] then return false end
  local before = {}
  for _, id in ipairs(H.available()) do before[id] = true end
  h.n_done = h.n_done + 1
  h.done[d.id] = h.n_done
  if how == "by hand" then h.by_hand[d.id] = true end
  if H.watching then H.watching[d.id] = nil end
  history(string.format("HUB: %s finished (%s) - %d/%d", d.id, how, h.n_done, #p.destinations))
  changed()
  for _, lid in ipairs(H.locations_of(d)) do
    if RANDO and RANDO.collect then RANDO.collect(lid, "destination " .. d.id .. " finished") end
  end
  local fresh = {}
  for _, id in ipairs(H.available()) do if not before[id] then fresh[#fresh + 1] = id end end
  h.unannounced = h.unannounced or {}
  for _, id in ipairs(fresh) do h.unannounced[#h.unannounced + 1] = id end
  if d.kind == "finale" then
    h.phase = "done"
    if RANDO and RANDO.on_finale then RANDO.on_finale("hub finale (" .. how .. ")") end
    return true
  end
  if h.current == d.id then h.current = nil end
  if quiet then
    log("destination", d.id, "closed by the hub:", how)
    return true
  end
  local msg = string.format("Destination complete (%d/%d)%s", h.n_done, #p.destinations,
                            #fresh > 0 and string.format(" - %d new destination(s) open", #fresh) or "")
  -- v0.54: a frame of THIS session (h.finished_at was saved, and a later session's frames start at
  -- 0 again: the guard below then held long into the next session - round 26)
  H.session.finished_frame = H.frame
  h.finished_at = nil
  if not H.enabled() then
    say(msg, { type = "planet", sub = "planet shuffle is off - " .. K("key_shuffle") .. " turns it on", duration = 8 })
    return true
  end
  if d.kind ~= "hub" and cfg("hub_auto_return", true) then
    local delay = cfg("hub_return_delay", 12)
    H.return_at = H.frame + math.max(1, delay) * 60
    say(msg, { type = "planet", sub = string.format("Back to %s in %d s (%s to stay)", HUBN(), delay, K("key_hub_return")), duration = 8 })
  else
    say(msg, { type = "planet", sub = K("key_hub") .. " to choose the next destination", duration = 8 })
    if d.kind == "hub" then
      h.unannounced = nil
      -- v0.53: the world was left to the game while the story ran; the hub's travel goes on now
      if S() and S().current_planet == p.planet then
        H.after(H.SETTLE, function() H.apply_world("the hub's story finished") end, "world after " .. d.id)
      end
      H.after(300, function()
        if H.expect or H.launch then return end
        local hh = H.state()
        local cur = hh and hh.current and dest_by_id(hh.current)
        if cur and not hh.done[cur.id] then return end
        H.ensure_hero("ratchet", nil, "the hub's visit finished")
      end, "back to Ratchet")
    end
  end
  return true
end

-- missions completing anywhere (10_rando_runtime.lua passes every MissionStateChanged/Complete)
function H.on_mission_state(name, state)
  if not (H.plan() and type(name) == "string") then return end
  local h = H.state()
  if not h then return end
  if state ~= 3 and state ~= 4 then return end
  local cur = h.current and dest_by_id(h.current)
  local order = {}
  if cur then order[1] = cur end
  for _, d in ipairs(H.plan().destinations) do if d ~= cur then order[#order + 1] = d end end
  for _, d in ipairs(order) do
    if not h.done[d.id] then
      for i, m in ipairs(d.missions or {}) do
        if m == name then
          if i == #d.missions then
            -- the hub writing the prologue complete may be reported as an event too (v0.51)
            H.finish(d, "story: " .. name, H.ending_prologue and d.kind == "intro")
          elseif d == cur and H.enabled() then
            log(name, "complete; the next mission of", d.id, "is looked at in", H.NEXT_MISSION_WAIT, "frames")
            H.after(H.NEXT_MISSION_WAIT, function()
              local hh = H.state()
              if hh and not hh.done[d.id] then H.activate(d, function(result, how) log("next mission of", d.id .. ":", result, tostring(how)) end) end
            end, "next mission " .. d.id)
          end
          return
        end
      end
    end
  end
end

-- the checkpoints the game triggers (14_rando_travel.lua names them). A destination's first
-- checkpoint on its own planet while its mission runs is kept as its start for the next run.
function H.on_checkpoint(cp)
  local h = H.state()
  if not (h and cp) then return end
  -- v0.52: an opening scene's checkpoint loaded (by the hub's warp or by the game itself)
  local cur = h.current and dest_by_id(h.current)
  local o = cur and H.opening_of(cur)
  if o and o.hash == cp.hash then
    H.session.opening_loaded = H.session.opening_loaded or {}
    H.session.opening_loaded[cur.id] = H.frame
    local m = (cur.missions or {})[1]
    local last = m and h.obj[m]
    log("opening of", cur.id, "loaded:", tostring(cp.name or cp.hash), "-", m and (m .. " at " .. tostring(last and last.o or "no step yet")) or "")
  end
  -- the game's own travel being undone: go home once the new planet has loaded (round 23: the
  -- prologue ends on Ardolis, then the game rifts to Nefarious City and plays its opening)
  local ok = H.order_kept
  if ok and cp.loaded ~= false and not ok.loaded then
    ok.loaded = true
    log("the new planet loaded (checkpoint", tostring(cp.name or cp.hash) .. ") - back to the hub in", H.SETTLE, "frames")
    H.after(H.SETTLE, function() H.order_kept_go(ok) end, "order kept")
  end
  if not cp.name then return end
  local d = h.current and dest_by_id(h.current)
  if not d or h.done[d.id] or d.start_cp or d.kind == "intro" then return end
  if cp.planet ~= d.planet or cp.name:find("TRANSITION_TO", 1, true) then return end
  local started = false
  for _, m in ipairs(d.missions or {}) do if H.session.started[m] and H.frame - H.session.started[m] < H.LEARN_WINDOW then started = true end end
  if not started then return end
  local L = learned_store()
  if L[d.id] then return end
  L[d.id] = cp.name
  changed()
  log("learned the start of", d.id .. ":", cp.name, "(the first checkpoint its story triggered there)")
end

-- ---------------------------------------------------------------------------------------------
-- arrivals (10_rando_runtime.lua calls this from process_planet). Returns true when handled.
-- ---------------------------------------------------------------------------------------------
local function test_travel_on()
  local TT = RANDO_TEST_TRAVEL
  return TT ~= nil and TT.on ~= nil and TT.on()
end
-- the next playable destination on a planet
function H.playable_on(pid)
  for _, id in ipairs(H.available()) do
    local d = dest_by_id(id)
    if d.planet == pid and d.kind ~= "hub" then return d end
  end
  return nil
end

-- v0.54: the inventory is looked at after every trip of the hub's own (09_rando_real.lua)
function H.watch_inventory(why, same_planet)
  local G = RANDO_REAL
  if G and G.watch_inventory then pcall(G.watch_inventory, why, same_planet) end
end

function H.on_arrival(pid, from)
  local p, h, s = H.plan(), H.state(), S()
  -- v0.54: a planet change may be a load, which sets the travel byte and the level bits to the
  -- save's own values (a later save can have travel ON): what apply_world recorded before it is
  -- not ours to take back any more (H.take_back_world, planet shuffle off)
  H.session.world = { travel = false, levels = {} }
  if not (p and h) or not H.enabled() then return false end
  local exp = H.expect
  H.expect = nil
  if exp and exp.planet == pid then H.watch_inventory("the trip to " .. tostring(pid)) end
  if not h.started then
    if pid == p.planet and (h.phase == "to_hub" or (exp and exp.planet == pid)) then
      -- (v0.52: never an opening scene: the way home must not play it again)
      if exp and exp.cp and not H.is_opening_cp(exp.cp) then h.home_cp = exp.cp end
      H.hub_started(exp and exp.cp or "arrived")
      return true
    end
    if exp then H.expect = exp end
    return false
  end
  if pid == p.planet then
    if exp and exp.cp and exp.planet == pid and not exp.dest then h.home_cp = exp.cp end
    -- a launch of one of the hub planet's own visits lands here too
    local d = exp and exp.dest and dest_by_id(exp.dest)
    if d and d.kind == "hub" then
      log("arrived at the hub (" .. HUBN() .. ") for", d.id)
      h.phase = "away"
      say(d.label or (d.title or d.id), { type = "planet", sub = "Randomized destination", duration = 6 })
      return true
    end
    -- v0.53: back from another planet in the middle of the hub's own story (round 25: the boss
    -- fight's shifts to Savali / Sargasso and back) - the story's own travel: no hub message, and
    -- the world stays the game's (H.apply_world)
    local cur = H.running()
    if not exp and cur and cur.kind == "hub" and from and from ~= pid then
      h.phase = "hub"
      log("back on", pid, "from", from, "during", cur.id, "- the story's own travel")
      if not h.prologue_ended then H.after(H.SETTLE, function() H.prologue_check() end, "prologue") end
      return true
    end
    H.at_hub(exp and exp.how or "arrived")
    return true
  end
  -- our own trip
  if exp and exp.planet == pid then
    local d = exp.dest and dest_by_id(exp.dest)
    h.phase = "away"
    if d then
      log("arrived for", d.id, "(" .. tostring(exp.how) .. " to " .. tostring(exp.cp) .. ")")
      say(string.format("%s: %s", pname(d.planet), d.label or d.title or d.id), { type = "planet", sub = "Randomized destination", duration = 6 })
    else
      h.current = nil
    end
    return true
  end
  -- the ship's planet menu
  local m = H.menu
  if m and now() - m.at <= H.MENU_WINDOW and m.planet == pid then
    H.menu = nil
    if s.access[pid] then
      if RANDO_TRAVEL and RANDO_TRAVEL.remember then RANDO_TRAVEL.remember(pid, m.dest) end
      local d = H.playable_on(pid)
      if d then
        log("planet menu: landed on", pid, "- launching", d.id)
        H.after(H.SETTLE, function() H.launch_dest(d, "planet menu") end, "menu launch " .. d.id)
      else
        h.phase, h.current = "away", nil
        say(pname(pid) .. ": nothing to play here yet - explore, or choose a destination with " .. K("key_hub") .. " / " .. K("key_hub", true),
            { type = "corner", duration = 6 })
      end
    elseif test_travel_on() then
      h.phase, h.current = "away", nil
      if RANDO_TEST_TRAVEL.stayed then RANDO_TEST_TRAVEL.stayed(pid, "planet menu") end
    else
      log("no Coordinates for", pid, "- back to the hub")
      say(string.format("Randomizer: no Coordinates for %s yet - back to %s", pname(pid), HUBN()), { type = "center", duration = 6 })
      h.sent_back = (h.sent_back or 0) + 1
      H.after(H.SETTLE, function() H.go_home("no Coordinates for " .. pid) end, "sent back")
    end
    return true
  end
  if test_travel_on() then log("arrived on", pid, "(test travel on: nothing is changed)"); return true end
  local cur = h.current and dest_by_id(h.current)
  -- travel inside the destination being played (a mission's own rifts) is never touched
  if cur and not h.done[cur.id] then
    log("arrived on", pid, "during", cur.id, "- the story's own travel")
    return true
  end
  -- the game's own travel right after the hub started, or after a destination finished: the
  -- game would carry on with its own (linear) order - back to the hub
  -- (v0.54: both frames are this session's; a save of an earlier session never holds the guard)
  local guard = H.session.started_frame and (H.frame - H.session.started_frame) < H.STARTUP_GUARD
  local after_finish = H.session.finished_frame and (H.frame - H.session.finished_frame) < H.STARTUP_GUARD
  if guard or after_finish or H.return_at then
    local d = H.playable_on(pid)
    if d and cfg("hub_follow_story", false) then
      log("the game's own story took you to", pid, "- carrying on with", d.id, "(hub_follow_story)")
      H.return_at = nil
      H.after(H.SETTLE, function() H.launch_dest(d, "the game's own travel") end, "follow " .. d.id)
      return true
    end
    log("the game's own story took you to", pid, "- back to the hub (the hub decides the order)")
    history("[ORDER KEPT] the game's own travel to " .. pid .. " undone")
    say(string.format("Randomizer: the game's story went on to %s - back to %s; choose your next mission there", pname(pid), HUBN()),
        { type = "center", duration = 7 })
    H.return_at = nil
    H.order_kept = { pid = pid, at = H.frame }
    return true
  end
  log("arrived on", pid, "(a load) - nothing changed")
  -- v0.54: a save that continues elsewhere is looked at too (round 26: Viceron loaded without a
  -- single weapon of the 15 items the randomizer had given)
  H.watch_inventory("the load on " .. tostring(pid))
  return true
end

-- the warp home for an undone story trip (once per trip; a launch or a new game cancels it)
function H.order_kept_go(ok)
  if H.order_kept ~= ok then return end
  H.order_kept = nil
  if H.launch or H.expect then return end
  H.go_home("the game's own travel to " .. tostring(ok.pid))
end

-- PlanetMenuAcceptEvent { DestinationCheckpointName, InterplanetaryCheckpointName }
function H.on_menu_accept(f)
  if not (H.plan() and H.state()) then return end
  local dest = f.DestinationCheckpointName
  local pid = RANDO_TRAVEL and RANDO_TRAVEL.planet_of_checkpoint and
              (RANDO_TRAVEL.planet_of_checkpoint(dest) or RANDO_TRAVEL.planet_of_checkpoint(f.InterplanetaryCheckpointName))
  H.menu = { planet = pid, dest = dest, at = now() }
  log("planet menu:", tostring(dest), "->", tostring(pid))
end

-- ---------------------------------------------------------------------------------------------
-- keys
-- ---------------------------------------------------------------------------------------------
local function ctrl_down()
  if RANDO and RANDO.ctrl_down then return RANDO.ctrl_down() end
  local ctrl = false
  pcall(function() ctrl = rivet.is_key_down(rivet.key("CONTROL")) end)
  return ctrl
end
local function describe_entry(e)
  if e.revisit then return "revisit " .. pname(e.revisit) .. " (no story; Gold Bolts, armor pods ...)" end
  local d = e.dest
  return string.format("%s (%s)", d.label or (pname(d.planet) .. ": " .. (d.title or d.id)), d.hero or "?")
end

function H.key_select()
  local h = H.state()
  if not h.started then
    say("Randomizer: " .. K("key_hub", true) .. " goes to " .. HUBN() .. " and starts the hub", { type = "center", duration = 6 })
    return
  end
  local list = H.menu_entries()
  if #list == 0 then say("Randomizer: nothing open", { type = "corner", duration = 4 }); return end
  H.sel = (H.sel % #list) + 1
  say(string.format("%d/%d - %s - %s to go", H.sel, #list, describe_entry(list[H.sel]), K("key_hub", true)), { type = "center", duration = 6 })
end

function H.key_go()
  local h = H.state()
  if not h.started then
    if h.phase == "to_hub" and H.expect then return end
    return H.begin_hub(K("key_hub", true))
  end
  local list = H.menu_entries()
  if #list == 0 then say("Randomizer: nothing open", { type = "corner", duration = 4 }); return end
  if H.sel < 1 or H.sel > #list then H.sel = 1 end
  local e = list[H.sel]
  if e.revisit then
    local cp, how = H.landing_for(e.revisit)
    if not cp then return say("Randomizer: no warp point known for " .. pname(e.revisit), { type = "center", duration = 6 }) end
    h.current = nil
    H.return_at = nil
    local at_hub = S().current_planet == H.plan().planet
    H.go(e.revisit, cp, nil, at_hub, "revisit (" .. tostring(how) .. ")")
    return
  end
  H.launch_dest(e.dest, K("key_hub", true))
end

local confirm = { finish = -100, restore = -100 }

-- the story key: start the story of the planet you are on (its next playable destination)
function H.key_story()
  local h = H.state()
  local pid = S().current_planet
  if not pid then return say("Randomizer: the planet is not known yet", { type = "corner", duration = 4 }) end
  local d = (h.current and dest_by_id(h.current))
  if not (d and d.planet == pid and not h.done[d.id]) then d = H.playable_on(pid) end
  if not d and pid == H.plan().planet then
    for _, id in ipairs(H.available()) do local x = dest_by_id(id); if x.kind == "hub" then d = x; break end end
  end
  if not d then return say(pname(pid) .. ": nothing to start here for the randomizer", { type = "corner", duration = 5 }) end
  H.session.reloaded[d.id] = nil
  log("story key:", pid, "->", d.id)
  H.launch_dest(d, K("key_story"))
end

-- v0.54: [ no longer warps back to the hub (round 26: "useless"). It only cancels the automatic
-- trip back after a finished destination; the ship, ] / Ctrl+] and the next finish take you on.
function H.key_return()
  if H.return_at then
    H.return_at = nil
    log("automatic return cancelled")
    say("Randomizer: staying here", { type = "corner", duration = 4 })
    return
  end
  say("Randomizer: " .. K("key_hub_return") .. " only cancels the trip back after a finished destination; "
      .. K("key_hub_return", true) .. " twice finishes this one by hand", { type = "corner", duration = 5 })
end

function H.key_finish()
  local h = H.state()
  local d = h.current and dest_by_id(h.current)
  if not d or h.done[d.id] then return say("Randomizer: no destination in progress", { type = "corner", duration = 4 }) end
  local t = now()
  if t - confirm.finish > H.CONFIRM then
    confirm.finish = t
    say(string.format("Randomizer: press %s again to finish %s by hand (it is recorded)", K("key_hub_return", true), d.id), { type = "center", duration = 5 })
    return
  end
  confirm.finish = -100
  log("[FINISHED BY HAND]", d.id)
  H.finish(d, "by hand")
end

-- ---------------------------------------------------------------------------------------------
-- v0.54 planet shuffle off / on (the 0 key), and giving your items back (Ctrl+0 twice)
-- ---------------------------------------------------------------------------------------------
-- everything the hub has scheduled or is waiting for is dropped (nothing fires later)
function H.quiet(why)
  H.expect, H.menu, H.pending, H.ladder, H.launch = nil, nil, nil, nil, nil
  H.return_at, H.order_kept, H.watching, H.hero_job = nil, nil, nil, nil
  if why then log("hub at rest:", why) end
end

-- off: the game travels and plays its levels its own way; the randomizer's items stay
function H.set_shuffle(on, why)
  local s = S()
  if not s then return false end
  local was_on = not H.shuffle_off()
  if on == was_on then return false end
  s.planet_shuffle_off = (not on) or nil
  H.session.shuffle_set = not on            -- this session's choice outlives a later restore
  changed()
  history(string.format("[PLANET SHUFFLE %s] (%s)", on and "ON" or "OFF", tostring(why)))
  if not on then
    H.quiet("planet shuffle off")
    -- the travel byte and level bits this session turned on go back to what the game had
    H.take_back_world("planet shuffle off")
    log("planet shuffle OFF (" .. tostring(why) .. "): the game's own travel, levels and stories are left alone")
    say("Randomizer: planet shuffle OFF - travel and levels are the game's own (items stay randomized)",
        { type = "center", sub = K("key_shuffle") .. " turns it back on", duration = 8 })
    return true
  end
  log("planet shuffle ON (" .. tostring(why) .. ")")
  local p, h = H.plan(), H.state()
  if p and h and h.started and s.current_planet == p.planet and not H.running() then
    H.after(H.SETTLE, function() H.apply_world("planet shuffle on") end, "planet shuffle on")
  end
  say("Randomizer: planet shuffle ON", { type = "center",
      sub = K("key_hub") .. " lists the destinations, " .. K("key_hub", true) .. " goes", duration = 6 })
  return true
end
function H.key_shuffle()
  H.set_shuffle(H.shuffle_off(), K("key_shuffle"))
end

function H.key_restore()
  local G = RANDO_REAL
  if not (G and G.restore_inventory and G.owned_items) then
    return say("Randomizer: 09_rando_real.lua is missing", { type = "corner", duration = 4 })
  end
  local n = #G.owned_items()
  if n == 0 then return say("Randomizer: no items of the randomizer to give back yet", { type = "corner", duration = 4 }) end
  local t = now()
  if t - confirm.restore > H.CONFIRM then
    confirm.restore = t
    say(string.format("Randomizer: press %s again to send your %d items again (lost ones come back, owned ones stay as they are)",
                      K("key_shuffle", true), n), { type = "center", duration = 5 })
    return
  end
  confirm.restore = -100
  local sent = G.restore_inventory("by hand (" .. K("key_shuffle", true) .. ")")
  say(string.format("Randomizer: sending %d item(s) again - lost ones come back over the next seconds", sent), { type = "corner", duration = 6 })
end

-- after the companion's restore (10_rando_runtime.lua): a choice made this session wins over the
-- save's; with planet shuffle off nothing the hub scheduled before the restore may fire
function H.after_restore()
  local s = S()
  if not s then return end
  if H.session.shuffle_set ~= nil then s.planet_shuffle_off = H.session.shuffle_set or nil end
  if s.hub then s.hub.finished_at = nil end   -- v0.54: an earlier session's frame (never used again)
  if H.shuffle_off() then
    H.quiet("planet shuffle is off (restored)")
    log("planet shuffle is OFF in this save -", K("key_shuffle"), "turns it on")
  end
end

-- ---------------------------------------------------------------------------------------------
-- the frame
-- ---------------------------------------------------------------------------------------------
function H.after(frames, fn, why)
  H.pending = H.pending or {}
  H.pending[#H.pending + 1] = { at = H.frame + frames, fn = fn, why = why }
end

function H.tick(frame, ready)
  H.frame = frame
  if not (H.plan() and S()) then return end
  local h = H.state()
  if not H.enabled() then return end
  if ready and H.pending and #H.pending > 0 then
    local due, keep = {}, {}
    for _, a in ipairs(H.pending) do if frame >= a.at then due[#due + 1] = a else keep[#keep + 1] = a end end
    H.pending = keep
    for _, a in ipairs(due) do
      local ok, err = pcall(a.fn)
      if not ok then log("RANDO-ERROR hub", tostring(a.why), tostring(err)) end
    end
  end
  -- New Game -> the hub
  if not h.started and h.phase == "pre" and S().started and ready then
    local ok, why = trigger_met()
    if ok then H.begin_hub(why or "the parade's wrench") end
  end
  -- a trip that has not landed
  local e = H.expect
  if e and ready and frame - e.at > H.ARRIVE_TIMEOUT then
    local p = H.plan()
    if e.planet == p.planet and (not e.dest or not h.started) then
      -- (v0.51: the hub start's trip carries the city's story; it is retried the same way)
      if not e.cand then for i, cp in ipairs(H.home_candidates()) do if cp == e.cp then e.cand = i end end end
      log("no arrival at the hub after", H.ARRIVE_TIMEOUT, "frames from", e.cp)
      if not H.go_home(e.why or "retry") then
        H.expect = nil
        if not h.started then H.start_failed("the warp did not land") end
      end
    elseif e.how == "fly" then
      log("the ship did not land on", e.planet, "- warping")
      H.expect = nil
      H.go(e.planet, e.cp, e.dest and dest_by_id(e.dest), false, "fly timed out")
    else
      log("no arrival on", e.planet, "after the warp to", e.cp)
      H.expect = nil
      say("Randomizer: the trip to " .. pname(e.planet) .. " did not land (see rivet.log)", { type = "center", duration = 6 })
    end
  end
  -- an undone story trip whose planet never reported a loaded checkpoint
  local ok = H.order_kept
  if ok and not ok.loaded and ready and frame - ok.at > H.ORDER_KEPT_WAIT then
    log("no loaded checkpoint on", ok.pid, "after", H.ORDER_KEPT_WAIT, "frames - back to the hub now")
    H.order_kept_go(ok)
  end
  -- automatic return after a finished destination (v0.51: not when the game's own travel has
  -- already brought you to the hub planet, e.g. the prologue's rift to Nefarious City)
  if H.return_at and ready and frame >= H.return_at then
    H.return_at = nil
    h.current = nil
    if S().current_planet == H.plan().planet then
      log("destination finished - already at the hub, no trip back")
    elseif not H.go_home("destination finished") then
      say("Randomizer: the warp to " .. HUBN() .. " failed - take the ship, or choose a destination with " .. K("key_hub", true),
          { type = "center", duration = 6 })
    end
  end
end

-- persistence: the companion's restore replaces the state; a hub started in this session before
-- the restore (a new game while the companion connected) is kept
function H.on_restore(live)
  local s = S()
  if not s then return end
  if live and live.hub and (not s.hub or not s.hub.started) and live.hub.started then
    s.hub = live.hub
    log("kept this session's hub start over the restored state")
  end
  if live and type(live.hub_learned) == "table" then
    s.hub_learned = s.hub_learned or {}
    for k, v in pairs(live.hub_learned) do if s.hub_learned[k] == nil then s.hub_learned[k] = v end end
  end
  local h = s.hub
  if not (H.plan() and h and h.started and H.enabled()) then return end
  if s.current_planet == H.plan().planet then H.after(H.SETTLE, function() H.apply_world("restored at the hub") end, "restored at the hub") end
end

-- ---------------------------------------------------------------------------------------------
-- wiring
-- ---------------------------------------------------------------------------------------------
pcall(rivet.on_event, "PlanetMenuAcceptEvent", function(ev)
  local ok, err = pcall(H.on_menu_accept, ev.fields or {})
  if not ok then log("RANDO-ERROR menu", tostring(err)) end
end)

local function bind(setting, legacy, fn)
  if not (RANDO and RANDO.bind_setting) then return end
  RANDO.bind_setting(setting, legacy, function()
    if not (H.plan() and S()) then return end
    if H.shuffle_off() then
      return say("Randomizer: planet shuffle is off - " .. K("key_shuffle") .. " turns it on", { type = "corner", duration = 4 })
    end
    if not H.enabled() then return say("Randomizer: hub_runtime is off", { type = "corner", duration = 3 }) end
    local ready = false
    pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
    if not ready then return say("Randomizer: wait until the game has loaded", { type = "corner", duration = 3 }) end
    fn(ctrl_down())
  end)
end
bind("key_hub", "F6", function(ctrl) if ctrl then H.key_go() else H.key_select() end end)
bind("key_hub_return", "F5", function(ctrl) if ctrl then H.key_finish() else H.key_return() end end)
bind("key_story", nil, function() H.key_story() end)
-- v0.54: 0 planet shuffle off / on, Ctrl+0 twice give your items back (both work with it off)
if RANDO and RANDO.bind_setting then
  RANDO.bind_setting("key_shuffle", nil, function()
    if not S() then return say("Randomizer: the seed is still being prepared", { type = "corner", duration = 3 }) end
    if ctrl_down() then return H.key_restore() end
    if not H.plan() then return say("Randomizer: planet shuffle is part of hub seeds (hub = true)", { type = "corner", duration = 4 }) end
    H.key_shuffle()
  end)
end
log("loaded (" .. H.VERSION .. ")" .. (H.shuffle_off() and " - planet shuffle OFF" or ""))
