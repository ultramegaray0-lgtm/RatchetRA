-- Randomizer 3.0 campaign layer: the mission registry, campaign sequence generation for every
-- mode, and the campaign constraints the progression solver (02_rando_generator.lua) uses.
--
-- 10.0: THE HUB AND PLANET SHUFFLE (hub = true, the default). v0.51 (10.0.2): the hub is Nefarious
-- City. A new game is taken there once the parade has handed Ratchet back after his wrench
-- (15_rando_hub.lua), and the city's story starts on arrival; the Battle Arena (Zurkie's first
-- visit) is open from the start as well. Every other visit opens when you hold its
-- planet's Coordinates (items of the seed, found anywhere) and the visits it depends on are done.
-- So the order planets open in is decided by where the seed put their Coordinates. The hub's
-- functions are at the end of this file (C.hub_*): which visits exist, which are playable, and the
-- reach the solver uses (a fixpoint: finishing a visit never closes another, so there is no dead
-- end to look for once every visit is reachable).
--
-- Each visit names where its story really begins (start_cp), where that is known from your logs:
--   * nefcity_1 = CHK_NEFCITY_START. In rounds 16 and 23 the game, with MIS_NEFCITY_01 active,
--     loaded Nefarious City and triggered checkpoint hash 2052464476, which is the engine's
--     CRC-32 (rivet.hash) of "CHK_NEFCITY_START". 8.x warped to CHK_NEFCITY_SHIP instead, and the
--     story never left OBJ_NEFCITY_GO_TO_NEFCITY there (rounds 17 and 22).
--   * scarstu_1 = CHK_ZURK_00_DEFAULT: the planet menu's own landing for MIS_ZURK_01_VISIT_01
--     (round 23 line 1096) and where round 17's forced start played the whole visit.
--   * the prologue resumes at the checkpoint the parade reached before the hub (learned at run time).
--   Others are learned at run time: the first checkpoint the game triggers with a visit's mission
--   active is kept as that visit's start (15_rando_hub.lua, 14_rando_travel.lua's hash names).
--
-- 9.0 (hub = false): THE STORY STARTS AS IN THE GAME. A new game plays the prologue (the parade on
-- Corson V), then Nefarious City, then Sargasso: the visits the game itself takes you to (arrival =
-- "story", C.STORY_START). Every campaign order of every mode begins with them, in that order;
-- only the visits after them are reordered.
--
-- 7.0: the same registry drives the LEVEL-LOCKED campaign (levels = true). The story keeps the
-- game's own mission order, but each planet's travel is locked behind its Coordinates, which are
-- items of the seed. A visit marked arrival = "story" is one the game itself takes you to (no
-- planet menu): those planets are open from the start, because the randomizer never blocks the
-- story's own travel.
--
-- A campaign is an ordered list of SEGMENTS. A segment is one visit to a planet: the game's
-- missions for that visit, in their own order (a mission's scripts expect the missions before it
-- on the same visit, so a visit is never split). Modes reorder the segments; the solver proves
-- the order can be played with the items the seed hands out.
--
-- Provenance of every entry (field `src`):
--   game   mission name seen in your rivet.log (MissionStateChangedEvent)
--   dag    name found in your game's dag (Phase 1 research: story-mission overlay regions)
--   guide  public walkthrough (gamepressure mission list, vulkk gear guide); NOT verified in the
--          game files. The research kit (companion/research/Research-Campaign.bat) replaces these
--          with the real names; tools/build_campaign_registry.py merges them.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["03_rando_campaign"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)
RANDO_CAMPAIGN = {}
local C = RANDO_CAMPAIGN
C.VERSION = "10.0.5"

-- story abilities: no item config exists, so only the story itself hands them out
C.STORY_ABILITIES = { phantom_dash = true, hurlshot = true, speetle = true, dragon_mount = true, wallrun = true }

-- src "game": a mission name of the visit was seen in your game (round 14: the level scripts'
-- mission variables, MissionStateChanged / devstats events). A visit may list more than one
-- name: the director uses the first and the last name the game's mission table holds, so a
-- guessed name that does not exist does no harm (lab Ctrl+F12 lists which exist).
C.SEGMENTS = {
  { id = "corson_intro", planet = "corson_v", visit = 1, hero = "ratchet", src = "game",
    missions = { "MIS_INTRO" }, entry = nil, kind = "intro", arrival = "story",
    title = "Parade, pursue Dr. Nefarious" },
  { id = "nefcity_1", planet = "nefarious_city", visit = 1, hero = "ratchet", src = "game",
    missions = { "MIS_NEFCITY_01" }, entry = "CHK_NEFCITY_SHIP", start_cp = "CHK_NEFCITY_START", arrival = "story",
    grants = { "phantom_dash" }, title = "Market, Club Nefarious, follow the Phantom, the statue" },
  { id = "sargasso_1", planet = "sargasso", visit = 1, hero = "rivet", src = "game",
    missions = { "MIS_SARG_01_FIRST_VISIT", "MIS_SARG_01_CLANKPUZZLE" }, boss = "Seekerpede", arrival = "story",
    title = "Reach the Morts, Rivet's hideout, Seekerpede" },
  { id = "scarstu_1", planet = "scarstu", visit = 1, hero = "ratchet", src = "game",
    missions = { "MIS_ZURK_01_VISIT_01" }, entry = "CHK_ZURK_LANDING_SHIP", start_cp = "CHK_ZURK_00_DEFAULT", boss = "Francois (arena)",
    title = "Zurkie's Gastropub, defeat Francois" },
  { id = "savali_1", planet = "savali", visit = 1, hero = "ratchet", src = "game",
    missions = { "MIS_SAV_01" }, entry = "CHK_SAV_01_LANDING",
    title = "Village attack, Lombax lore, three temples, the Archives" },
  { id = "blizar_1", planet = "blizar_prime", visit = 1, hero = "rivet", src = "game",
    missions = { "MIS_BLIZAR" }, entry = "CHK_BLIZAR_A_LANDINGPAD",
    title = "Blockade, the miners, the drill, Phase Quartz" },
  { id = "torren_1", planet = "torren_iv", visit = 1, hero = "rivet", src = "game",
    missions = { "MIS_MOL_01_FIRST_VISIT" }, requires = { "hoverboots" },
    grants = { "hurlshot" }, boss = "the Fixer (chase)", title = "Find the Fixer, the Hurlshot, escape" },
  { id = "cordelion_1", planet = "cordelion", visit = 1, hero = "ratchet", src = "game",
    missions = { "MIS_CORD_01_FIRST_VISIT" }, entry = "CHK_CORD_A_START", boss = "Cordelion boss",
    title = "Kedaro Station, the Rubion Forge, a new Dimensionator" },
  { id = "scarstu_2", planet = "scarstu", visit = 2, hero = "rivet", src = "game",
    missions = { "MIS_ZURK_02B_VISIT_02B" }, after = { "scarstu_1" }, title = "Meet Ratchet in the Gastropub" },
  { id = "ardolis_1", planet = "ardolis", visit = 1, hero = "ratchet", src = "game",
    missions = { "MIS_ARD_01_FIRST_VISIT" }, entry = "CHK_ARD_START", requires = { "hoverboots" },
    title = "Pierre Le Fer, treasure hunt, Pirate Trials, Captain Quantum" },
  { id = "sargasso_2", planet = "sargasso", visit = 2, hero = "rivet", src = "game",
    missions = { "MIS_SARG_02_REVISIT_SHIPS" }, entry = "CHK_SARG_02_MININGPLATFORM_LANDINGPAD", after = { "sargasso_1" },
    title = "Protect the Morts, free the Seekerpede, Nefarious' ships" },
  { id = "savali_2", planet = "savali", visit = 2, hero = "ratchet", src = "game",
    missions = { "MIS_SVALI_02_SECOND_VISIT" }, after = { "savali_1" }, title = "The Archives' machines, the catacombs" },
  { id = "viceron_1", planet = "viceron", visit = 1, hero = "rivet", src = "game",
    missions = { "MIS_ZORD_01" }, entry = "CHK_ZORDOOM_START", requires = { "ability:phantom_dash", "ability:hurlshot" },
    boss = "Zordoom Prison warden", title = "Find Ratchet and Kit, reactor shutdown, follow the cell" },
  { id = "finale", planet = "corson_v", visit = 2, hero = "ratchet", src = "game",
    missions = { "MIS_MEGA_FINALE" }, entry = "CHK_MEGA_FINALE_START", kind = "finale", boss = "Emperor Nefarious",
    title = "The final battle" },
}
-- 8.4 (round 20): the hero of each visit, checked against the walkthroughs (Ratchet & Clank wiki
-- plot; gamepressure; thegamer) and against round 17/20: a story's first "go to <planet>" step
-- finished only when the visit's own hero was there (Ardolis, Savali, Zurkie's 1 as Ratchet: at
-- once; Torren IV, Viceron as Ratchet and Nefarious City as Rivet: never). Four heroes were wrong
-- and are fixed: nefcity_1 Ratchet ("Ratchet awakens in Nefarious City"), sargasso_2 Rivet ("Rivet
-- and Kit fly to Sargasso"), ardolis_1 Ratchet ("Ratchet and Clank fly to Ardolis"), viceron_1
-- Rivet ("Rivet flies to Zordoom Prison"). Entries: CHK_ARD_START (round 20: the story ran from
-- it), CHK_CORD_A_START and CHK_ZORDOOM_START (listed by rivet.checkpoints() in round 19).
-- 8.1 (round 17 research, rando_give.dll v6 queries): MIS_BLIZAR_01, MIS_CORD_BOSS, MIS_ZURK_02,
-- MIS_SARG_02_REVISIT and MIS_MEGA_01_RIVET are "not a mission in your game"; the names above all
-- exist (MIS_BLIZAR from MissionStateChanged events). Entries CHK_SARG_02_MININGPLATFORM_LANDINGPAD
-- and CHK_MEGA_FINALE_START are listed by rivet.checkpoints() in your game (not warped to yet).
-- 7.0 arrival = "story" evidence (round 16 rivet.log): the parade's rifts end on Nefarious City
-- (lines 200-221, no PlanetMenuAcceptEvent), and when MIS_NEFCITY_01 completes the game starts
-- MIS_SARG_01_FIRST_VISIT and changes the planet to Sargasso by itself (lines 338-344). The first
-- planet-menu travel in every log is the one to Zurkie's (round 14 line 171, round 16 line 390).
function C.story_arrival_planets()
  local out, seen = {}, {}
  for _, seg in ipairs(C.SEGMENTS) do
    if seg.arrival == "story" and not seen[seg.planet] then seen[seg.planet] = true; out[#out + 1] = seg.planet end
  end
  return out
end
C.BY_ID = {}
for i, seg in ipairs(C.SEGMENTS) do seg.index = i; seg.requires = seg.requires or {}; seg.grants = seg.grants or {}; seg.after = seg.after or {}; C.BY_ID[seg.id] = seg end

-- 9.0: the start every campaign has, in this order: the prologue, then the visits the story itself
-- travels to next (the parade's rifts end on Nefarious City; finishing MIS_NEFCITY_01 takes you to
-- Sargasso, round 16 lines 338-344). Built from the registry: the leading run of arrival = "story".
C.STORY_START = {}
for _, seg in ipairs(C.SEGMENTS) do
  if seg.arrival ~= "story" then break end
  C.STORY_START[#C.STORY_START + 1] = seg.id
end
C.IN_STORY_START = {}
for i, id in ipairs(C.STORY_START) do C.IN_STORY_START[id] = i end

-- where each 2.0 location sits in the campaign (the visit whose content holds it)
C.LOCATION_SEGMENT = {
  ["planet:corson_v"] = "corson_intro", ["story2:corson_v"] = "finale",
  ["planet:nefarious_city"] = "nefcity_1", ["story2:nefarious_city"] = "nefcity_1",
  ["planet:sargasso"] = "sargasso_1", ["story2:sargasso"] = "sargasso_2",
  ["planet:scarstu"] = "scarstu_1", ["story2:scarstu"] = "scarstu_2",
  ["planet:savali"] = "savali_1", ["story2:savali"] = "savali_2",
  ["planet:blizar_prime"] = "blizar_1", ["story2:blizar_prime"] = "blizar_1",
  ["planet:torren_iv"] = "torren_1", ["story2:torren_iv"] = "torren_1",
  ["planet:cordelion"] = "cordelion_1", ["story2:cordelion"] = "cordelion_1",
  ["planet:ardolis"] = "ardolis_1", ["story2:ardolis"] = "ardolis_1",
  ["planet:viceron"] = "viceron_1",
  ["side:zurkies_bronze"] = "scarstu_1", ["side:zurkies_silver"] = "scarstu_1", ["side:zurkies_gold"] = "scarstu_2",
  ["side:sargasso_trudi"] = "sargasso_2", ["side:blizar_chef"] = "blizar_1", ["side:ardolis_mapomatic"] = "ardolis_1",
}
-- Gold Bolts: the first visit of their planet (open-world content of that planet)
function C.location_segment(lid, planet)
  local s = C.LOCATION_SEGMENT[lid]
  if s then return s end
  if planet then
    for _, seg in ipairs(C.SEGMENTS) do if seg.planet == planet and seg.visit == 1 then return seg.id end end
  end
  return nil
end

-- (the default mode is campaign_mode in 02_rando_generator.lua's G.DEFAULTS: planet_shuffle)
-- 9.0: every mode starts with the prologue, Nefarious City and Sargasso (C.STORY_START)
C.MODES = {
  vanilla = "the game's own order; rewards randomized (2.0 behaviour)",
  planet_shuffle = "after the story's start, planets in a random order; each planet's visits keep their order",
  mission_shuffle = "after the story's start, every visit (including revisits) placed anywhere the dependencies allow",
  full = "mission shuffle (9.0: the same start as every mode)",
  chaos = "mission shuffle with story-ability order checks only (9.0: the same start as every mode)",
}
-- what the runtime must be able to do in the game for a mode (see 11_rando_campaign.lua). 9.0: no
-- mode skips the prologue any more, so none needs new_game_init
C.NEEDS = {
  vanilla = {},
  planet_shuffle = { "mission_control", "travel" },
  mission_shuffle = { "mission_control", "travel" },
  full = { "mission_control", "travel" },
  chaos = { "mission_control", "travel" },
}

-- ---------------------------------------------------------------------------------------------
-- sequence generation
-- ---------------------------------------------------------------------------------------------
local function contains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end

-- hard rules every mode keeps:
--   * 9.0: the order begins with the story's start (prologue, Nefarious City, Sargasso)
--   * a revisit comes after the first visit of its planet (its scripts continue that story)
--   * the finale is last
--   * a visit needing a story ability comes after the visit that grants it
-- (the second argument of 3.0-8.5, start_fixed, is ignored: the start is always fixed)
function C.hard_ok(order)
  local pos = {}
  for i, id in ipairs(order) do pos[id] = i end
  for _, seg in ipairs(C.SEGMENTS) do
    local p = pos[seg.id]
    if not p then return false, "missing " .. seg.id end
    for _, a in ipairs(seg.after) do if pos[a] > p then return false, seg.id .. " before " .. a end end
    for _, r in ipairs(seg.requires) do
      local ab = r:match("^ability:(.+)$")
      if ab then
        local granted = false
        for _, other in ipairs(C.SEGMENTS) do
          if contains(other.grants, ab) and pos[other.id] < p then granted = true end
        end
        if not granted then return false, seg.id .. " needs " .. ab .. " before it" end
      end
    end
  end
  if order[#order] ~= "finale" then return false, "finale not last" end
  for i, id in ipairs(C.STORY_START) do
    if order[i] ~= id then return false, "the story's start is not " .. table.concat(C.STORY_START, " > ") end
  end
  if #order ~= #C.SEGMENTS then return false, "visits twice or missing" end
  return true
end

-- builds a valid order by random topological insertion. rng: RANDO_GEN.rng. 9.0: the order always
-- begins with C.STORY_START; the third argument of 3.0-8.5 (random_start) is ignored.
function C.sequence(mode, rng)
  local ids = {}
  for _, seg in ipairs(C.SEGMENTS) do ids[#ids + 1] = seg.id end
  if mode == "vanilla" then return ids, ids[1] end
  for _ = 1, 500 do
    local order
    if mode == "planet_shuffle" then
      -- shuffle planets by their first visit; revisits keep their vanilla slot relative to the
      -- shuffled first visits (inserted right after a random later point)
      local firsts, rest = {}, {}
      for _, seg in ipairs(C.SEGMENTS) do
        if seg.kind ~= "finale" and not C.IN_STORY_START[seg.id] then
          if seg.visit == 1 then firsts[#firsts + 1] = seg.id else rest[#rest + 1] = seg.id end
        end
      end
      rng.shuffle(firsts)
      order = {}
      for _, id in ipairs(C.STORY_START) do order[#order + 1] = id end
      for _, id in ipairs(firsts) do order[#order + 1] = id end
      for _, id in ipairs(rest) do
        local first = C.BY_ID[C.BY_ID[id].after[1]]
        local at
        for i, x in ipairs(order) do if x == first.id then at = i end end
        local slot = rng.int(at + 1, #order + 1)
        table.insert(order, slot, id)
      end
      order[#order + 1] = "finale"
    else
      local pool = {}
      for _, seg in ipairs(C.SEGMENTS) do
        if seg.kind ~= "finale" and not C.IN_STORY_START[seg.id] then pool[#pool + 1] = seg.id end
      end
      rng.shuffle(pool)
      order = {}
      for _, id in ipairs(C.STORY_START) do order[#order + 1] = id end
      for _, id in ipairs(pool) do order[#order + 1] = id end
      order[#order + 1] = "finale"
      -- repair: move each revisit after its first visit, and ability needs after their grant
      for _ = 1, 3 do
        for _, seg in ipairs(C.SEGMENTS) do
          local deps = {}
          for _, a in ipairs(seg.after) do deps[#deps + 1] = a end
          for _, r in ipairs(seg.requires) do
            local ab = r:match("^ability:(.+)$")
            if ab then for _, o in ipairs(C.SEGMENTS) do if contains(o.grants, ab) then deps[#deps + 1] = o.id end end end
          end
          local pos = {}
          for i, id in ipairs(order) do pos[id] = i end
          local need = 0
          for _, d in ipairs(deps) do if pos[d] and pos[d] > need then need = pos[d] end end
          if pos[seg.id] and pos[seg.id] < need and seg.kind ~= "finale" and not C.IN_STORY_START[seg.id] then
            table.remove(order, pos[seg.id])
            table.insert(order, math.min(need, #order), seg.id)   -- right after the last dependency
          end
        end
      end
    end
    local ok = C.hard_ok(order)
    if ok then return order, order[1] end
  end
  return nil, "no valid order"
end

-- the campaign constraint object the solver uses
-- returns { order = {...}, index = {seg_id = n}, loc_segment = {lid = n}, segments = {...} }
function C.build(order, s, db_locations)
  local camp = { order = order, index = {}, loc_segment = {}, segments = {}, vanilla = true }
  for i, id in ipairs(order) do if not C.SEGMENTS[i] or C.SEGMENTS[i].id ~= id then camp.vanilla = false end end
  for i, id in ipairs(order) do
    camp.index[id] = i
    local seg = C.BY_ID[id]
    camp.segments[i] = { id = id, planet = seg.planet, requires = seg.requires, grants = seg.grants, boss = seg.boss }
  end
  for lid, loc in pairs(db_locations) do
    local sid = C.location_segment(lid, loc.planet)
    if sid and camp.index[sid] then camp.loc_segment[lid] = camp.index[sid] end
  end
  camp.planet_locks = s.planet_locks
  return camp
end

-- how far the campaign gets with what is owned: the number of visits that can be played in
-- order. owned: item key -> count (randomizer items + start); weapons_needed(i) per visit index
function C.reach(camp, owned, start_kit, wcount, weapons_needed)
  local abilities = {}
  for k in pairs(start_kit or {}) do abilities[k] = true end
  for i, seg in ipairs(camp.segments) do
    for _, r in ipairs(seg.requires) do
      local ab = r:match("^ability:(.+)$")
      if ab then
        if not abilities[ab] then return i - 1, "needs " .. ab end
      elseif not start_kit[r] and (owned[r] or 0) == 0 then
        return i - 1, "needs " .. r
      end
    end
    -- (with levels = true the story-arrival planets are open from the start: 02's start rules)
    if camp.planet_locks and (owned["access:" .. seg.planet] or 0) == 0 then return i - 1, "needs Coordinates for " .. seg.planet end
    if seg.boss and weapons_needed and wcount < weapons_needed(i) then return i - 1, "needs weapons for " .. seg.boss end
    for _, g in ipairs(seg.grants) do abilities[g] = true end
  end
  return #camp.segments
end

-- spoiler text for the campaign
function C.describe(order)
  local L = {}
  for i, id in ipairs(order) do
    local seg = C.BY_ID[id]
    local need = (#seg.requires > 0) and ("  needs " .. table.concat(seg.requires, ", ")) or ""
    local gives = (#seg.grants > 0) and ("  story gives " .. table.concat(seg.grants, ", ")) or ""
    L[#L + 1] = string.format("  %2d. %-13s %-15s %-8s %s%s%s%s", i, id, seg.planet, seg.hero,
                              seg.title or "", seg.boss and ("  [boss: " .. seg.boss .. "]") or "", need, gives)
  end
  L[#L + 1] = "  A new game plays the prologue, then Nefarious City, then Sargasso, as in the game; only the"
  L[#L + 1] = "  visits after them are reordered."
  local vanilla = true
  for i, id in ipairs(order) do if C.SEGMENTS[i].id ~= id then vanilla = false end end
  if not vanilla then
    L[#L + 1] = "  The order is followed only when the runtime's mission control is verified in your game"
    L[#L + 1] = "  (experimental). Until then you play the game's own order with these rewards; the seed"
    L[#L + 1] = "  is checked to be finishable in that order too."
  end
  return table.concat(L, "\n")
end

-- ---------------------------------------------------------------------------------------------
-- 10.0 THE HUB (hub = true): three starting missions, Coordinates open the rest.
-- v0.51 (10.0.2): the hub is NEFARIOUS CITY (10.0-v0.5: Zurkie's Battleplex). The new game's warp
-- lands at CHK_NEFCITY_START with MIS_NEFCITY_01 already started - the state the game itself loads
-- the city in after the prologue (rounds 16 and 23) - so the city's story plays at once.
-- ---------------------------------------------------------------------------------------------
C.HUB_PLANET = "nefarious_city"
C.HUB_NAME = "Nefarious City"
-- where the hub warps to. CHK_NEFCITY_START: where the game loads the city's story (rounds 16
-- and 23, by its CRC-32); it is the way home while the city's story (nefcity_1) is not finished.
-- CHK_NEFCITY_SHIP: the ship's landing pad (rounds 17 and 22 landed there; with the story still at
-- its first step it never moved on there), the way home once the city's story is done.
C.HUB_CHECKPOINTS = { "CHK_NEFCITY_START", "CHK_NEFCITY_SHIP" }
C.HUB_STORY = "nefcity_1"            -- the hub planet's own story: started by the hub's first warp
-- the starting missions. This order feeds the generator (the starting Coordinates), so it is
-- 10.0's and placements stay the same; the menu shows them in C.HUB_MENU order.
C.HUB_START = { "corson_intro", "scarstu_1", "nefcity_1" }
C.HUB_MENU = { "nefcity_1", "scarstu_1", "corson_intro" }
C.HUB_LABEL = { corson_intro = "Prologue - the parade on Corson V",
                scarstu_1 = "Battle Arena - Zurkie's Battleplex",
                nefcity_1 = "Nefarious City - the hub's story" }
-- v0.52 (10.0.3): A VISIT'S OPENING SCENE. Round 24 (v0.51's first run): MIS_NEFCITY_01 was made
-- available and started, the warp landed at CHK_NEFCITY_START, the city was loaded there three more
-- times (the stuck-story reload and three presses of /), and the story never left
-- OBJ_NEFCITY_GO_TO_NEFCITY. In round 23 the game's own rift after the prologue loaded the city at
-- checkpoint hash 3046787773 FIRST (the city's arrival scene), and only then CHK_NEFCITY_START. So
-- CHK_NEFCITY_START is where gameplay picks up after that scene, not where the story begins.
--   hash   the checkpoint the game loads the visit at (its name is in no log yet: it is looked up at
--          run time among the names rivet.checkpoints() lists, by the engine's CRC-32)
--   codes  rivet.checkpoints() filters tried first for it (the whole list is the catalog's "CHK_")
--   with   missions the game made available together with the story (round 23 line 711:
--          MIS_NEFCITY_01_TRAINSTATION 0 -> 1 in the same frame as MIS_NEFCITY_01 0 -> 2)
-- Round 23 also had MIS_INTRO complete (line 703) before the city's story started: the hub now ends
-- the prologue before it starts the city's story (hub_prologue_timing = "before").
-- Not part of the seed's hub plan: seeds, fingerprints and placements stay 10.0.2's.
C.OPENINGS = {
  nefcity_1 = { hash = 3046787773, codes = { "NEFCITY", "NEF_" }, with = { "MIS_NEFCITY_01_TRAINSTATION" } },
}
C.IN_HUB_START = {}
for i, id in ipairs(C.HUB_START) do C.IN_HUB_START[id] = i end
C.IN_HUB_MENU = {}
for i, id in ipairs(C.HUB_MENU) do C.IN_HUB_MENU[id] = i end

function C.hub_kind(seg)
  if seg.kind == "finale" then return "finale" end
  if seg.kind == "intro" then return "intro" end
  if seg.planet == C.HUB_PLANET then return "hub" end
  return "planet"
end
-- the planets open from the start (their Coordinates are starting items of a hub seed)
function C.hub_start_planets()
  local out, seen = {}, {}
  for _, id in ipairs(C.HUB_START) do
    local p = C.BY_ID[id].planet
    if not seen[p] then seen[p] = true; out[#out + 1] = p end
  end
  return out
end
-- every visit as a hub destination (the plan a hub seed carries; registry order)
function C.hub_destinations()
  local out = {}
  for _, seg in ipairs(C.SEGMENTS) do
    local req = {}
    for _, r in ipairs(seg.requires) do req[#req + 1] = r end
    local after = {}
    for _, a in ipairs(seg.after) do after[#after + 1] = a end
    local grants = {}
    for _, g in ipairs(seg.grants) do grants[#grants + 1] = g end
    local missions = {}
    for _, m in ipairs(seg.missions or {}) do missions[#missions + 1] = m end
    out[#out + 1] = { id = seg.id, planet = seg.planet, visit = seg.visit, hero = seg.hero, kind = C.hub_kind(seg),
                      missions = missions, title = seg.title, entry = seg.entry, start_cp = seg.start_cp,
                      after = after, requires = req, grants = grants, boss = seg.boss,
                      start = C.IN_HUB_START[seg.id] ~= nil, label = C.HUB_LABEL[seg.id] }
  end
  return out
end

-- is destination d playable? done: id -> truthy; access: planet -> truthy (Coordinates held);
-- has(item) -> bool for item requirements; abilities: ability -> true
function C.hub_playable(d, done, access, has, abilities, all_ids)
  if done[d.id] then return false, "done" end
  if d.kind == "finale" then
    for _, id in ipairs(all_ids) do
      if id ~= d.id and not done[id] then return false, "needs every other destination (" .. id .. ")" end
    end
  end
  if not access[d.planet] then return false, "needs Coordinates for " .. d.planet end
  for _, a in ipairs(d.after or {}) do if not done[a] then return false, "after " .. a end end
  for _, r in ipairs(d.requires or {}) do
    local ab = r:match("^ability:(.+)$")
    if ab then
      if not abilities[ab] then return false, "needs " .. ab end
    elseif not has(r) then
      return false, "needs " .. r
    end
  end
  return true
end

-- the solver's reach in a hub seed: every destination that can be finished with what is owned,
-- in the order they become playable (a fixpoint). owned: item -> count; start_kit: name -> true.
-- Returns done (id -> position) and the list in that order.
function C.hub_reach(dests, owned, start_kit)
  local done, order, abilities = {}, {}, {}
  for k in pairs(start_kit or {}) do abilities[k] = true end
  local access = setmetatable({}, { __index = function(_, pid) return (owned["access:" .. pid] or 0) > 0 end })
  local function has(r) return (start_kit and start_kit[r]) or (owned[r] or 0) > 0 end
  local ids = {}
  for _, d in ipairs(dests) do ids[#ids + 1] = d.id end
  local changed = true
  while changed do
    changed = false
    for _, d in ipairs(dests) do
      if not done[d.id] and C.hub_playable(d, done, access, has, abilities, ids) then
        order[#order + 1] = d.id
        done[d.id] = #order
        for _, g in ipairs(d.grants or {}) do abilities[g] = true end
        changed = true
      end
    end
  end
  return done, order
end

-- the destinations playable now at run time (ids; the starting missions first, then registry
-- order). done: id -> truthy; access: planet -> true (the runtime's S.access); owned(item) -> bool
function C.hub_available(plan, done, access, owned)
  local abilities = {}
  for _, k in ipairs(RANDO_DATA and RANDO_DATA.start_kit or {}) do abilities[k] = true end
  for _, d in ipairs(plan.destinations) do
    if done[d.id] then for _, g in ipairs(d.grants or {}) do abilities[g] = true end end
  end
  local kit = {}
  for _, k in ipairs(RANDO_DATA and RANDO_DATA.start_kit or {}) do kit[k] = true end
  local function has(r) return kit[r] or (owned and owned(r)) or false end
  local ids = {}
  for _, d in ipairs(plan.destinations) do ids[#ids + 1] = d.id end
  local first, rest = {}, {}
  for _, d in ipairs(plan.destinations) do
    if C.hub_playable(d, done, access, has, abilities, ids) then
      if d.start then first[#first + 1] = d else rest[#rest + 1] = d end
    end
  end
  table.sort(first, function(a, b) return (C.IN_HUB_MENU[a.id] or 99) < (C.IN_HUB_MENU[b.id] or 99) end)
  local out = {}
  for _, d in ipairs(first) do out[#out + 1] = d.id end
  for _, d in ipairs(rest) do out[#out + 1] = d.id end
  return out
end

-- spoiler text: the start, then one possible route (the order destinations become playable when
-- every reachable location is collected), with where each planet's Coordinates are
function C.hub_describe(plan, planet_name, coords_at)
  local L = {}
  L[#L + 1] = "  A new game plays the parade until Ratchet has his wrench and the parade hands him back, then"
  L[#L + 1] = "  the randomizer takes him to " .. C.HUB_NAME .. " (the hub) and the city's story starts there."
  L[#L + 1] = "  The prologue counts as done (in-game option hub_prologue = \"keep\" leaves it to choose)."
  L[#L + 1] = "  Open from the start:"
  for i, id in ipairs(C.HUB_MENU) do L[#L + 1] = string.format("    %d. %s", i, C.HUB_LABEL[id]) end
  L[#L + 1] = "  Every other destination opens when you hold its planet's Coordinates and what it depends on"
  L[#L + 1] = "  is done. One possible route (the solver's order):"
  for i, id in ipairs(plan.route or {}) do
    local d
    for _, x in ipairs(plan.destinations) do if x.id == id then d = x end end
    local why = {}
    if d.start then why[#why + 1] = "start choice"
    elseif d.kind == "finale" then why[#why + 1] = "after every other destination"
    elseif coords_at and coords_at[d.planet] then why[#why + 1] = "Coordinates at " .. coords_at[d.planet] end
    for _, a in ipairs(d.after or {}) do why[#why + 1] = "after " .. a end
    for _, r in ipairs(d.requires or {}) do why[#why + 1] = "needs " .. r end
    L[#L + 1] = string.format("  %2d. %-13s %-30s %-7s %s", i, id, planet_name(d.planet), d.hero or "?", table.concat(why, ", "))
  end
  return table.concat(L, "\n")
end
