-- Randomizer 3.2 campaign director, mission control and campaign research (rivet_hook, Lua 5.4).
--
-- WHAT IS PROVEN AND WHAT IS NOT (see docs/CAMPAIGN.md):
--   * Every mission action of the game reads its mission as a NAME and has two branches. Your
--     game runs the second ("system 2", round 15: the system 1 manager is NULL there): missions
--     are components on level actors, found through a manager at RVA 0x68EA390.
--   * In system 2 the game's own actions can: read a mission's state, START a mission whose state
--     is 1 (available) and that agrees to start, COMPLETE a mission whose state is 3, REPLAY a
--     mission. MakeMissionAvailableAction does NOTHING in system 2: what is available is the
--     game's own business. So the director can only start visits the game has made available.
--   * Every call goes through rando_give.dll v4, which makes exactly those calls on the game
--     thread, only when every byte of them matches your exe (bytes taken from your own code
--     dumps). Reading states changes nothing; changing anything is used by the director only
--     after the lab saw it work in your game (06_rando_capabilities.lua).
--   * The game does not report mission states when a save loads (round 14), so the director
--     asks the game (query) instead of waiting for events.
--   * Travel (rivet.fly / rivet.warp) has not been used by the randomizer in your game yet.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["11_rando_campaign"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)
RANDO_CAMPAIGN_RT = RANDO_CAMPAIGN_RT or {}
local D = RANDO_CAMPAIGN_RT
local C = RANDO_CAMPAIGN
local CAPS = RANDO_CAPABILITIES or {}
local R = RANDO

local function log(...) pcall(rivet.log, "[rando]", ...) end
local function say(text, opts) if R and R.say then R.say(text, opts) else pcall(rivet.notify, text, opts) end end

-- ---------------------------------------------------------------------------------------------
-- research: everything the mission system shows us this session
-- ---------------------------------------------------------------------------------------------
D.missions = D.missions or {}          -- name -> { state, previous, seen = n, first_frame } (events)
D.objectives = D.objectives or {}      -- "mission/objective" -> state
D.checkpoints_hit = D.checkpoints_hit or {}
D.known = D.known or {}                -- name -> { state, frame, system, object, missing } (asked the game)
local frame = 0

local function note_mission(f)
  local name = f.MissionName
  if type(name) ~= "string" then return end
  local m = D.missions[name] or { seen = 0, first_frame = frame, hash = nil }
  m.seen = m.seen + 1
  m.previous, m.state = tonumber(f.PreviousState), tonumber(f.MissionState)
  m.last_frame = frame
  if not m.hash then pcall(function() m.hash = rivet.hash(name) end) end
  D.missions[name] = m
  if D.on_mission then D.on_mission(name, m.state, m.previous) end
end

-- the state numbers of system 2 as the game's actions use them: start needs 1, complete needs 3.
-- 8.0: the DDL's MissionStates enum (neptuwunium/rivet Enums/MissionStates.cs) names them, and
-- MissionStateChangedEvent reports the same numbers (MIS_INTRO 2 while the parade runs, the
-- Zurkie's cups 1 <-> 2): 0 Inactive, 1 Available, 2 Active, 3 Complete Cleaning, 4 Complete
-- Finished, 5 Failed. CompleteMissionAction's "complete" input finishes a mission that is
-- already cleaning up (3 -> 4); an active mission is completed by its own objectives.
D.STATE_NAMES = { [0] = "inactive", [1] = "available", [2] = "active", [3] = "completing", [4] = "complete", [5] = "failed" }
-- the 3.x director's constants (kept as they were: it acts only on verified capabilities, none yet)
D.AVAILABLE, D.ACTIVE, D.COMPLETE = 1, 3, 4
-- 8.0 (the DDL's names)
D.MS = { INACTIVE = 0, AVAILABLE = 1, ACTIVE = 2, CLEANING = 3, COMPLETE = 4, FAILED = 5 }

local function hexaddr(n) return string.format("%X", n) end
local function read_bytes(addr, len)
  local ok, hex = pcall(rivet.read, type(addr) == "string" and addr or hexaddr(addr), len)
  if not ok or not hex then return nil end
  local out = {}
  for x in hex:gmatch("%x%x") do out[#out + 1] = tonumber(x, 16) end
  if #out < len then return nil end
  return out
end
local function u32_of(b, off) return b[off + 1] | (b[off + 2] << 8) | (b[off + 3] << 16) | (b[off + 4] << 24) end
local function u64_of(b, off)
  local v = 0
  for i = 8, 1, -1 do v = (v << 8) | b[off + i] end
  return v
end
local function read_u64(addr) local b = read_bytes(addr, 8); return b and u64_of(b, 0) end
local function read_u32(addr) local b = read_bytes(addr, 4); return b and u32_of(b, 0) end
D.read_u64, D.read_u32 = read_u64, read_u32

-- the engine's string hash; rivet.hash is the same function (CRC-32 table, start 0xEDB88320)
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do c = (c & 1 == 1) and ((c >> 1) ~ 0xEDB88320) or (c >> 1) end
  CRC[i] = c
end
function D.engine_hash(name)
  local ok, h = pcall(rivet.hash, name)
  if ok and math.type(h) == "integer" then return h & 0xFFFFFFFF end
  local c = 0xEDB88320
  for i = 1, #name do c = (c >> 8) ~ CRC[(c ~ name:byte(i)) & 0xFF] end
  return c
end

-- the exe's load address: rando_give.dll writes it into its mailbox (+0x30)
function D.exe_base()
  local rr = RANDO_REAL
  local addr = rr and rr.native and rr.native.addr
  return addr and read_u64(addr + 0x30), addr
end

-- ---------------------------------------------------------------------------------------------
-- asking and changing: rando_give.dll v4 (one request per frame, the game's own calls)
-- ---------------------------------------------------------------------------------------------
D.KIND = { query = 1, make_available = 2, start = 3, complete = 4, replay = 5,
           -- v6 (8.0): set_state writes a state into the mission's saved record (flag = the state);
           -- probe finds that record; level_set / level_read / travel_set are UnlockLevelAction's
           -- and SetPlanetaryTravelAction's changes (no mission name)
           set_state = 8, level_set = 9, level_read = 10, travel_set = 11, probe = 12 }
D.NAMELESS = { level_set = true, level_read = true, travel_set = true }
D.V6_BIT = { set_state = 1, probe = 1, level_set = 2, level_read = 2, travel_set = 4 }
D.RESULT = { [0] = "nothing", [1] = "sent", [2] = "no target", [3] = "faulted (caught)", [4] = "bad request",
             [5] = "the mission code of this exe did not match", [6] = "no mission manager", [7] = "the mission manager is not ready",
             [8] = "the game uses its other mission path", [9] = "not a mission in your game",
             [10] = "the game's action does nothing in this state", [11] = "done",
             [12] = "the game has no such action in its mission system", [13] = "not found",
             [-1] = "timed out", [-2] = "helper not available" }
D.MB = { PUMPS = 0x28, KIND = 0x48, SLOT = 0x4C, FLAG = 0x50, BEFORE = 0x54, AFTER = 0x58, RET = 0x5C, MISSIONS = 0x60, INDEX = 0x64,
         OBJECT = 0x68, SYSTEM = 0x70, NAMES = 0x400, NAME_SIZE = 0x40, SLOTS = 48, REQ = 0x10, DONE = 0x14, RESULT = 0x24,
         STATUS = 0x0C, VERSION = 0x08, COUNT = 0x20, V6 = 0x78 }
D.HELPER_VERSION = 4
D.native = D.native or { queue = {}, cur = nil, slots = {}, next_slot = 0 }
D.NATIVE_TIMEOUT = 300
D.NATIVE_LOAD_WAIT = 3600       -- 8.5: the longest a request waits through a loading screen

function D.native_ok(kind)
  local rr = RANDO_REAL
  local n = rr and rr.native
  if not (n and n.addr) then return false, "rando_give.dll is not loaded" end
  local version = read_u32(n.addr + D.MB.VERSION) or 0
  if version < D.HELPER_VERSION then return false, "rando_give.dll is older than v4 (replace it with the kit's)" end
  if read_u32(n.addr + D.MB.STATUS) ~= 1 then return false, "rando_give.dll is not ready" end
  local bit = kind and D.V6_BIT[kind]
  if bit then
    if version < 6 then return false, "rando_give.dll is older than v6 (8.0 needs the kit's)" end
    if ((read_u32(n.addr + D.MB.V6) or 0) & bit) == 0 then return false, "rando_give.dll did not recognise this part of your exe (" .. kind .. ")" end
    if D.NAMELESS[kind] then return true end
  end
  if read_u32(n.addr + D.MB.MISSIONS) ~= 1 then return false, "rando_give.dll did not recognise the mission code of this exe" end
  return true
end
-- 8.0: what the v6 helper recognised in this exe (bits: 1 mission records, 2 level mask, 4 travel)
function D.v6_bits()
  local rr = RANDO_REAL
  local n = rr and rr.native
  if not (n and n.addr) or (read_u32(n.addr + D.MB.VERSION) or 0) < 6 then return 0 end
  return read_u32(n.addr + D.MB.V6) or 0
end

local function le32(v) return string.format("%02X %02X %02X %02X", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF) end
-- each name gets its own slot for good: the game may keep the pointer it was given
local function slot_for(addr, name)
  local nat = D.native
  if nat.slots[name] then return nat.slots[name] end
  if nat.next_slot >= D.MB.SLOTS or #name < 1 or #name >= D.MB.NAME_SIZE or name:find("[^%w_]") then return nil end
  local hex = {}
  for i = 1, #name do hex[#hex + 1] = string.format("%02X", name:byte(i)) end
  hex[#hex + 1] = "00"
  local at = addr + D.MB.NAMES + nat.next_slot * D.MB.NAME_SIZE
  if not pcall(rivet.write, hexaddr(at), table.concat(hex, " ")) then return nil end
  nat.slots[name] = nat.next_slot
  nat.next_slot = nat.next_slot + 1
  return nat.slots[name]
end

-- queue a mission call; cb(r) runs when the game has answered, r = { code, before, after, ret,
-- index, object, system, name, kind }
function D.mission_call(kind, name, cb, flag, value)
  D.native.queue[#D.native.queue + 1] = { kind = kind, name = name, cb = cb, flag = flag or 0, value = value or 0 }
end

local function remember(r)
  if D.NAMELESS[r.kind] then return end
  if r.kind ~= "query" and r.code ~= 11 then return end
  local k = D.known[r.name] or {}
  if r.code == 9 then
    k.missing, k.state = true, nil
  elseif r.code == 11 then
    k.missing, k.state, k.system, k.object = false, r.after, r.system, r.object
  end
  k.frame = frame
  D.known[r.name] = k
end

local function finish_call(c, r)
  D.native.cur = nil
  if RANDO_REAL then RANDO_REAL.mission_busy = nil end
  r.name, r.kind = c.name, c.kind
  remember(r)
  if c.cb then
    local ok, err = pcall(c.cb, r)
    if not ok then log("RANDO-ERROR campaign mission callback", tostring(err)) end
  end
end

function D.native_tick()
  local nat, rr = D.native, RANDO_REAL
  local c = nat.cur
  if c then
    local addr = rr.native.addr
    if read_u32(addr + D.MB.DONE) == c.req then
      local b = read_bytes(addr + D.MB.BEFORE, 0x20)
      local r = { code = read_u32(addr + D.MB.RESULT) }
      if b then
        r.before, r.after, r.ret, r.index = u32_of(b, 0), u32_of(b, 4), u32_of(b, 8), u32_of(b, 16)
        r.object, r.system = u64_of(b, 20), u32_of(b, 28)
      end
      finish_call(c, r)
    elseif frame - c.sent > D.NATIVE_TIMEOUT then
      -- 8.5: a loading screen is not a timeout: while the helper's pump has not run and the scene
      -- is not up, the request simply waits (as item and currency requests do, 09_rando_real.lua)
      local pumps = read_u32(addr + D.MB.PUMPS)
      local ready = false
      pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
      if pumps == c.pumps and not ready and frame - c.sent <= D.NATIVE_LOAD_WAIT then
        return
      end
      -- 8.5: take the request back before giving up, so the helper can never carry it out later
      -- behind the script's back (a late start or state write the ladder thinks failed)
      local done = read_u32(addr + D.MB.DONE)
      if done == c.req then return end                  -- answered just now: read next frame
      if done then
        pcall(rivet.write, hexaddr(addr + D.MB.REQ), le32(done))
        -- if the helper took it between the read and the write, its answer stands
        if read_u32(addr + D.MB.DONE) == c.req then
          pcall(rivet.write, hexaddr(addr + D.MB.REQ), le32(c.req)); return
        end
      end
      log("RANDO-CAMPAIGN mission call timed out and was taken back", c.kind, c.name)
      finish_call(c, { code = -1 })
    end
    return
  end
  if #nat.queue == 0 then return end
  local ok, why = D.native_ok(nat.queue[1].kind)
  if not ok then
    local q = table.remove(nat.queue, 1)
    if not D.warned_native then D.warned_native = true; log("RANDO-CAMPAIGN mission calls not possible:", why) end
    nat.cur = q
    finish_call(q, { code = -2, why = why })
    return
  end
  if rr.busy or rr.mission_busy or rr.aux_busy then return end   -- an item delivery is using the mailbox
  local q = table.remove(nat.queue, 1)
  local addr = rr.native.addr
  local slot = 0
  if not D.NAMELESS[q.kind] then slot = slot_for(addr, q.name) end
  if not slot then log("RANDO-CAMPAIGN no name slot for", q.name); nat.cur = q; finish_call(q, { code = 4 }); return end
  local req = ((read_u32(addr + D.MB.REQ) or 0) + 1) & 0xFFFFFFFF
  local okw = true
  if D.NAMELESS[q.kind] then okw = pcall(rivet.write, hexaddr(addr + D.MB.COUNT), le32(q.value or 0)) end
  okw = okw and pcall(rivet.write, hexaddr(addr + D.MB.KIND), le32(D.KIND[q.kind]) .. " " .. le32(slot) .. " " .. le32(q.flag))
  okw = okw and pcall(rivet.write, hexaddr(addr + D.MB.REQ), le32(req))           -- last
  if not okw then log("RANDO-CAMPAIGN cannot write the mailbox"); nat.cur = q; finish_call(q, { code = -1 }); return end
  q.req, q.sent = req, frame
  q.pumps = read_u32(addr + D.MB.PUMPS)
  nat.cur = q
  rr.mission_busy = true
end

local function state_name(st) return st and (D.STATE_NAMES[st] or ("state " .. tostring(st))) or "?" end
function D.describe(r)
  return string.format("%s %s: %s (%s -> %s)", tostring(r.kind), tostring(r.name), D.RESULT[r.code] or tostring(r.code),
                       state_name(r.before), state_name(r.after))
end

-- ask the game for several missions; cb(answers) with answers[name] = r
function D.refresh(names, cb)
  local answers, left = {}, #names
  if left == 0 then return cb(answers) end
  for _, name in ipairs(names) do
    D.mission_call("query", name, function(r)
      answers[name] = r
      left = left - 1
      if left == 0 and cb then cb(answers) end
    end)
  end
end
-- what the game said last time (nil when not asked yet or not a mission there)
function D.mission_state(name)
  local k = D.known[name]
  if not k then return nil, "not asked yet" end
  if k.missing then return nil, "not a mission in your game" end
  return k.state
end

-- ---------------------------------------------------------------------------------------------
-- capabilities (06_rando_capabilities.lua)
-- ---------------------------------------------------------------------------------------------
function D.capability(name)
  local c = CAPS[name]
  return type(c) == "table" and c.verified == true
end

-- what a campaign mode needs, and which of it is missing
function D.missing_for(mode)
  local missing = {}
  for _, need in ipairs((C and C.NEEDS[mode]) or {}) do
    if not D.capability(need) then missing[#missing + 1] = need end
  end
  return missing
end

-- travel: rivet_hook's own engine travel. fly needs a ship nearby; warp works anywhere.
function D.landing_for(planet_id)
  local seg
  for _, s in ipairs((C and C.SEGMENTS) or {}) do if s.planet == planet_id and s.entry then seg = s; break end end
  if seg then return seg.entry end
  local learned = (R and R.state and R.state.campaign and R.state.campaign.landings or {})[planet_id]
  return learned
end
function D.travel(checkpoint, how)
  if not checkpoint then return false, "no known checkpoint" end
  D.lab.travel = { to = checkpoint, at = frame, how = how or "fly" }
  local fn = (how == "warp") and rivet.warp or rivet.fly
  local ok, res = pcall(fn, checkpoint)
  log("RANDO-CAMPAIGN travel", how or "fly", checkpoint, ok and tostring(res) or ("failed: " .. tostring(res)))
  return ok, res
end

-- ---------------------------------------------------------------------------------------------
-- the director: follows the seed's campaign order
-- ---------------------------------------------------------------------------------------------
local function S() return R and R.state end
local function seed() return RANDO_SEED end

function D.campaign_state()
  local s = S()
  if not s then return nil end
  s.campaign = s.campaign or { pos = 1, done = {}, landings = {}, prepared = {} }
  return s.campaign
end

function D.active()
  local sd = seed()
  if not (sd and sd.campaign and sd.campaign.order) then return false, "vanilla" end
  local missing = D.missing_for(sd.campaign.mode)
  if #missing > 0 then return false, "missing " .. table.concat(missing, ", ") end
  return true
end

function D.current_segment()
  local sd, cs = seed(), D.campaign_state()
  if not (sd and cs and sd.campaign.order) then return nil end
  local id = sd.campaign.order[cs.pos]
  return id and C.BY_ID[id], cs.pos
end

-- the next visit can begin only when the randomizer items it needs are owned (the solver
-- proved they come from earlier visits, the shop or the start)
function D.blocked(seg)
  local s = S()
  local kit = {}
  for _, g in ipairs(RANDO_DATA.start_kit or {}) do kit[g] = true end
  for _, r in ipairs(seg.requires) do
    if not r:match("^ability:") and not kit[r] and not (s.inventory[r] or s.gadgets_seen[r]) then
      return "you need " .. ((RANDO_DATA.items[r] and RANDO_DATA.items[r].name) or r)
    end
  end
  if seed().planet_locks and not s.access[seg.planet] then
    return "you need the Coordinates for " .. ((R.planet_name and R.planet_name(seg.planet)) or seg.planet)
  end
  return nil
end

D.INTRO = "MIS_INTRO"
function D.skip_done()
  local sd, cs = seed(), D.campaign_state()
  local moved = false
  while cs.pos <= #sd.campaign.order and cs.done[sd.campaign.order[cs.pos]] do cs.pos = cs.pos + 1; moved = true end
  if moved and R.mark_changed then R.mark_changed() end
end

-- random start (modes full/chaos): a new save always begins with the intro. With the verified
-- new_game_init capability the director finishes MIS_INTRO the way CompleteMissionAction does
-- (only from state 3; its rewards are paid then, never later than the logic placed them) and
-- the intro's later slot is skipped. cb(ok, why)
function D.init_new_game(cb)
  local sd, cs = seed(), D.campaign_state()
  if cs.intro_skipped or sd.campaign.order[1] == "corson_intro" then return cb(true, "not needed") end
  D.refresh({ D.INTRO }, function(a)
    local st = a[D.INTRO].code == 11 and a[D.INTRO].after or nil
    if st == D.COMPLETE then
      cs.intro_skipped, cs.done.corson_intro = true, true
      return cb(true, "intro already finished")
    end
    if not D.capability("new_game_init") then return cb(false, "new_game_init is not verified") end
    if st ~= D.ACTIVE then return cb(false, "the intro is " .. state_name(st) .. " - it can be finished once it is active") end
    D.mission_call("complete", D.INTRO, function(r)
      log("RANDO-CAMPAIGN random start:", D.describe(r))
      if r.code == 11 and r.after == D.COMPLETE then
        cs.intro_skipped, cs.done.corson_intro = true, true
        if R.mark_changed then R.mark_changed() end
        return cb(true, "intro completed")
      end
      cb(false, "could not finish the intro: " .. (D.RESULT[r.code] or tostring(r.code)))
    end)
  end)
end

-- make the current visit playable: start its first mission. In system 2 the game alone decides
-- what is available, so a visit the game has not opened yet cannot be started. cb(ok, why)
function D.prepare(cb)
  local cs = D.campaign_state()
  local function after_init(okn, whyn)
    if not okn then return cb(false, whyn) end
    D.skip_done()
    local seg, pos = D.current_segment()
    if not seg then return cb(false, "campaign finished") end
    if cs.prepared[seg.id] then return cb(true, "already prepared") end
    local why = D.blocked(seg)
    if why then return cb(false, why) end
    D.refresh(seg.missions, function(a)
      -- the visit's first mission your game knows (registry names are partly guesses)
      local first, r
      for _, m in ipairs(seg.missions) do
        if a[m].code == 11 then first, r = m, a[m]; break end
      end
      if not first then
        local r1 = a[seg.missions[1]]
        return cb(false, seg.missions[1] .. ": " .. (D.RESULT[r1.code] or tostring(r1.code)))
      end
      local function done(okd, w)
        if okd then
          cs.prepared[seg.id] = true
          if R.mark_changed then R.mark_changed() end
          log("RANDO-CAMPAIGN prepared", pos, seg.id, first, w or "")
        end
        cb(okd, w)
      end
      local st = r.after
      if st and st >= 2 then return done(true, "already started (" .. state_name(st) .. ")") end
      local function start()
        D.mission_call("start", first, function(rs)
          log("RANDO-CAMPAIGN", D.describe(rs))
          if rs.code == 11 then done(true, "started") else done(false, "start " .. first .. ": " .. (D.RESULT[rs.code] or tostring(rs.code))) end
        end)
      end
      if st == D.AVAILABLE then return start() end
      if r.system == 1 then
        D.mission_call("make_available", first, function(rm)
          log("RANDO-CAMPAIGN", D.describe(rm))
          if rm.code == 11 or rm.code == 10 then start() else done(false, "make available " .. first .. ": " .. (D.RESULT[rm.code] or tostring(rm.code))) end
        end)
        return
      end
      done(false, (seg.title or seg.id) .. " is not open in your game yet (" .. first .. " is " .. state_name(st) .. ")")
    end)
  end
  if cs.pos == 1 then D.init_new_game(after_init) else after_init(true) end
end

-- a visit is finished when its last mission is complete (state 4)
function D.on_mission(name, state)
  if state ~= D.COMPLETE then return end
  if not D.active() then return end
  local seg, pos = D.current_segment()
  if not seg then return end
  local last = seg.missions[#seg.missions]
  local cs = D.campaign_state()
  if name == last or (name:upper():sub(1, #last) == last:upper()) then
    cs.done[seg.id] = true
    cs.pos = pos + 1
    D.skip_done()
    if R.mark_changed then R.mark_changed() end
    local nxt = D.current_segment()
    log("RANDO-CAMPAIGN visit done", seg.id, "->", nxt and nxt.id or "the end")
    if nxt then
      local why = D.blocked(nxt)
      say(string.format("Campaign %d/%d: next is %s%s", cs.pos, #seed().campaign.order, nxt.title or nxt.id,
                        why and (" - " .. why) or " - press " .. D.KEY .. " to travel"), { type = "center", duration = 8 })
    else
      say("Campaign complete!", { type = "planet", duration = 8 })
    end
  end
end

-- the game does not report mission states when a save is loaded (round 14): every 2 s the
-- director asks the game about the current visit's missions
D.POLL_FRAMES = 120
function D.poll()
  if not D.active() or D.polling then return end
  local seg = D.current_segment()
  if not seg then return end
  D.polling = true
  D.refresh(seg.missions, function(a)
    D.polling = nil
    for i = #seg.missions, 1, -1 do
      local r = a[seg.missions[i]]
      if r.code == 11 then
        if r.after == D.COMPLETE then D.on_mission(seg.missions[#seg.missions], D.COMPLETE) end
        return
      end
    end
  end)
end

-- F12: go to the current visit (start its first mission, then travel there)
function D.go()
  local active, why = D.active()
  -- 8.4: the key means nothing in the game's own order: logged, no message (round 20: the old
  -- F12, also Steam's screenshot key, put "Campaign order is not available" on screen)
  if why == "vanilla" then
    log("RANDO-CAMPAIGN key: no campaign order in this seed (the game's own order)")
    return false
  end
  if not active then
    say("Campaign order is not available yet (" .. why .. ") - play the game's own order; rewards are randomized as usual",
        { type = "center", duration = 8 })
    return false
  end
  local seg = D.current_segment()
  if not seg then say("Campaign complete"); return false end
  if D.going then return false end
  D.going = true
  say("Campaign: preparing " .. (seg.title or seg.id) .. "...", { type = "center", duration = 3 })
  D.prepare(function(okp, w)
    D.going = nil
    if not okp then say("Campaign: " .. tostring(w), { type = "center", duration = 6 }); return end
    local cp = D.landing_for(seg.planet)
    local okt = D.travel(cp, "fly")
    if not okt then D.travel(cp, "warp") end
  end)
  return true
end

function D.status_text()
  local sd = seed()
  if not (sd and sd.campaign and sd.campaign.order) then return nil end
  local active, why = D.active()
  local seg, pos = D.current_segment()
  if not active then return "campaign " .. sd.campaign.mode .. ": not available yet (" .. why .. ")" end
  return string.format("campaign %d/%d: %s", pos or 0, #sd.campaign.order, seg and seg.id or "done")
end

-- remember landing checkpoints the game itself uses (PlanetMenuAcceptEvent)
local function note_landing(f)
  local cp = f.DestinationCheckpointName
  if type(cp) ~= "string" then return end
  D.last_destination = cp
end

-- ---------------------------------------------------------------------------------------------
-- research
-- ---------------------------------------------------------------------------------------------
function D.known_names()
  local names, list = {}, {}
  for _, seg in ipairs((C and C.SEGMENTS) or {}) do for _, m in ipairs(seg.missions) do names[m] = true end end
  for name in pairs(D.missions) do names[name] = true end
  for _, extra in ipairs({ "MIS_INTRO", "MIS_SARG_01_POST_MISSION", "MIS_SAV_01_POST_MISSION", "MIS_NEFCITY_01_TRAINSTATION",
                           "MIS_ZURK_ARENA_BRONZE_CUP", "MIS_NEFCITY_PASSIVESHIFT_01", "MIS_RYNO_PLANS" }) do names[extra] = true end
  for name in pairs(names) do list[#list + 1] = name end
  table.sort(list)
  return list
end

local research_cache
function rando_research_status()
  local data = { missions = D.missions, objectives = D.objectives, checkpoints = D.checkpoints_hit,
                 known = D.known, vtable = D.lab and D.lab.vtable, last_destination = D.last_destination,
                 capabilities = CAPS, frame = frame, native = { D.native_ok() } }
  local okc, cps = pcall(rivet.checkpoints, "")
  if okc then data.checkpoint_count = cps and #cps or 0 end
  research_cache = "return " .. RANDO_GEN.serialize(data)
  return tostring(#research_cache) .. "|" .. tostring(math.ceil(#research_cache / 3000))
end
function rando_research_chunk(i)
  return (research_cache or ""):sub((i - 1) * 3000 + 1, i * 3000)
end

-- ---------------------------------------------------------------------------------------------
-- wiring
-- ---------------------------------------------------------------------------------------------
pcall(rivet.on_event, "MissionStateChangedEvent", function(ev)
  local ok, err = pcall(note_mission, ev.fields or {})
  if not ok then log("RANDO-ERROR campaign mission", tostring(err)) end
end)
pcall(rivet.on_event, "ObjectiveStateChangedEvent", function(ev)
  local f = ev.fields or {}
  if type(f.MissionName) == "string" then D.objectives[f.MissionName .. "/" .. tostring(f.ObjectiveName)] = tonumber(f.ObjectiveState) end
end)
pcall(rivet.on_event, "PlanetMenuAcceptEvent", function(ev) pcall(note_landing, ev.fields or {}) end)
pcall(rivet.on_event, "CheckpointTriggeredEvent", function(ev)
  local h = ev.fields and ev.fields.CheckpointHash
  if h then D.checkpoints_hit[#D.checkpoints_hit + 1] = h; if #D.checkpoints_hit > 200 then table.remove(D.checkpoints_hit, 1) end end
  local t = D.lab and D.lab.travel
  if t and h and frame - t.at < 3600 then
    local want = D.engine_hash(t.to)
    if math.tointeger(h) and (math.tointeger(h) & 0xFFFFFFFF) == want then
      log("RANDO-LAB VERIFIED travel " .. t.to .. " (" .. t.how .. ")")
      say("[LAB] travel works: arrived at " .. t.to, { type = "center", duration = 6 })
      D.lab.travel = nil
    end
  end
end)

D.lab = D.lab or {}
pcall(rivet.on_frame, function()
  frame = frame + 1
  local ok, err = pcall(D.native_tick)
  if not ok then log("RANDO-ERROR campaign native", tostring(err)); D.native.cur = nil; if RANDO_REAL then RANDO_REAL.mission_busy = nil end end
  -- once per session, read-only: what the game says about the intro, and the helper's state
  if not D.diag_done and frame % 600 == 0 then
    local ready = false
    pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
    if ready then
      D.diag_done = true
      local okn, nwhy = D.native_ok()
      log("RANDO-CAMPAIGN mission helper:", okn and "ready (rando_give.dll v4, mission code matches this exe)" or tostring(nwhy))
      if okn then
        D.refresh({ D.INTRO }, function(a)
          local r = a[D.INTRO]
          log(string.format("RANDO-CAMPAIGN mission system %s: MIS_INTRO is %s (%s)", tostring(r.system), state_name(r.after), D.RESULT[r.code] or tostring(r.code)))
        end)
      end
    end
  end
  if frame % D.POLL_FRAMES == 0 then
    local okp, errp = pcall(D.poll)
    if not okp then log("RANDO-ERROR campaign poll", tostring(errp)); D.polling = nil end
  end
  if D.lab.travel_at and frame >= D.lab.travel_at then
    D.lab.travel_at = nil
    local okl, errl = pcall(D.lab_travel)
    if not okl then log("RANDO-ERROR lab travel", tostring(errl)) end
  end
end)

D.KEY = (R and R.config and R.config.key_campaign) or "F12"
local function vk_of(name)          -- 8.3: keyboard keys through the runtime's resolver
  if R and R.vk then local v = R.vk(name); return v ~= nil, v end
  return pcall(rivet.key, name)
end
local function ctrl_down()
  local ctrl = false
  pcall(function() ctrl = rivet.is_key_down(rivet.key("CONTROL")) end)
  return ctrl
end
-- 8.3: the setting's key, and the old F12 too while legacy_f_keys is on
D.KEYS = { D.KEY }
if R and R.config and R.config.legacy_f_keys and D.KEY ~= "F12" then D.KEYS[2] = "F12" end
for _, name in ipairs(D.KEYS) do
  local okk, vk = vk_of(name)
  if okk then pcall(rivet.on_key, vk, function()
    if ctrl_down() then return end
    local ok, err = pcall(D.go)
    if not ok then log("RANDO-ERROR campaign key", tostring(err)) end
  end) end
end

-- ---------------------------------------------------------------------------------------------
-- the lab (test mode, a SPARE save). Ctrl+F12 only asks; Ctrl+F11 changes the spare save's story.
-- Lines tools/build_capabilities.py turns into 06_rando_capabilities.lua:
--   RANDO-LAB VERIFIED read (N missions answered, system S)
--   RANDO-LAB VERIFIED native start (mission X went 1 -> 2)
--   RANDO-LAB VERIFIED native complete (mission MIS_INTRO went 3 -> 4)
--   RANDO-LAB VERIFIED native replay (mission X went 0 -> 2)        (research only)
--   RANDO-LAB VERIFIED travel <checkpoint> (fly|warp)
-- and RANDO-LAB NO EFFECT ... when the game did not change.
-- ---------------------------------------------------------------------------------------------
D.VT_SLOTS = { 0x38, 0xD0, 0xD8, 0xE8, 0xF0, 0x108 }
-- research: where a mission component's functions are (their code goes into rivet.log)
function D.lab_vtable(object)
  local base = D.exe_base()
  if not base or not object or object == 0 then return end
  local vt = read_u64(object)
  if not vt then log("RANDO-LAB component not readable"); return end
  local out = { vtable_rva = vt - base, slots = {} }
  log(string.format("RANDO-LAB component vtable rva 0x%X", vt - base))
  for _, off in ipairs(D.VT_SLOTS) do
    local fn = read_u64(vt + off)
    if fn then
      out.slots[off] = fn - base
      local okr, hex = pcall(rivet.read, hexaddr(fn), 0x180)
      log(string.format("RANDO-LAB code slot 0x%X rva 0x%X %s", off, fn - base, (okr and hex or "?"):gsub("%s", "")))
    end
  end
  D.lab.vtable = out
end

function D.lab_read()
  local nok, nwhy = D.native_ok()
  if not nok then
    log("RANDO-LAB helper not available:", nwhy)
    say("[LAB] " .. nwhy, { type = "center", duration = 8 })
    return
  end
  local names = D.known_names()
  D.refresh(names, function(a)
    local answered, missing, system, object = 0, 0, nil, nil
    for _, name in ipairs(names) do
      local r = a[name]
      if r.code == 11 then
        answered = answered + 1
        system = system or r.system
        if name == D.INTRO then object = r.object end
        log(string.format("RANDO-LAB mission %s %s (system %s)", name, state_name(r.after), tostring(r.system)))
      else
        if r.code == 9 then missing = missing + 1 end
        log("RANDO-LAB mission " .. name .. ": " .. (D.RESULT[r.code] or tostring(r.code)))
      end
    end
    if answered > 0 then
      log(string.format("RANDO-LAB VERIFIED read (%d missions answered, system %s)", answered, tostring(system)))
    else
      log("RANDO-LAB NO EFFECT read (no mission answered)")
    end
    pcall(D.lab_vtable, object)
    say(string.format("[LAB] %d of %d mission names answered (%d not missions in your game), system %s", answered, #names, missing, tostring(system)),
        { type = "center", duration = 8 })
  end)
end

local function lab_line(r)
  if r.code == 11 and r.before ~= r.after then
    log(string.format("RANDO-LAB VERIFIED native %s (mission %s went %s -> %s)", r.kind, r.name, tostring(r.before), tostring(r.after)))
    return true
  end
  log(string.format("RANDO-LAB NO EFFECT native %s (mission %s: %s, %s -> %s, returned %s)", r.kind, r.name, D.RESULT[r.code] or tostring(r.code),
                    tostring(r.before), tostring(r.after), tostring(r.ret)))
  return false
end

-- visits in the order the lab tries them (the seed's campaign order, else the game's)
local function lab_order()
  local order = {}
  local sd = seed()
  if sd and sd.campaign and sd.campaign.order then
    for _, id in ipairs(sd.campaign.order) do order[#order + 1] = C.BY_ID[id] end
  else
    for _, seg in ipairs(C.SEGMENTS) do order[#order + 1] = seg end
  end
  return order
end

function D.lab_try()
  local nok, nwhy = D.native_ok()
  if not nok then return false, nwhy end
  local names = {}
  for _, seg in ipairs(C.SEGMENTS) do for _, m in ipairs(seg.missions) do names[#names + 1] = m end end
  D.refresh(names, function(a)
    local intro = a[D.INTRO]
    local ist = intro.code == 11 and intro.after or nil
    if ist == D.ACTIVE then
      D.mission_call("complete", D.INTRO, function(r)
        local ok = lab_line(r)
        say("[LAB] finish intro: " .. (ok and "works" or (D.RESULT[r.code] or tostring(r.code))), { type = "center", duration = 8 })
      end)
      return
    end
    if ist == 1 or ist == 2 then
      log(string.format("RANDO-LAB intro is %s: CompleteMissionAction only finishes an active (3) mission - try again later in the intro", state_name(ist)))
      say("[LAB] the intro is " .. state_name(ist) .. " - the game's complete action needs it active (3). Play on a little and retry",
          { type = "center", duration = 8 })
      return
    end
    -- 1) a visit the game has opened (available): start it the game's way
    -- 2) none: the next locked visit, to see what start and replay do to it
    local open_seg, open_m, locked_seg, locked_m
    for _, seg in ipairs(lab_order()) do
      for _, m in ipairs(seg.missions) do
        local r = a[m]
        if r.code == 11 then
          if r.after == D.AVAILABLE and not open_seg then open_seg, open_m = seg, m end
          if r.after == 0 and not locked_seg and seg.kind ~= "finale" then locked_seg, locked_m = seg, m end
          break
        end
      end
    end
    local seg, m = open_seg or locked_seg, open_m or locked_m
    if not seg then say("[LAB] no visit to try (nothing available or locked)", { type = "center", duration = 6 }); return end
    D.lab.target = seg
    log("RANDO-LAB target", seg.id, m, open_seg and "(available)" or "(locked)")
    D.mission_call("start", m, function(r)
      local ok1 = lab_line(r)
      local function finish(text)
        say(string.format("[LAB] %s: %s. Travelling there in 2 s...", m, text), { type = "center", duration = 8 })
        D.lab.travel_at = frame + 120
      end
      if ok1 or open_seg then return finish("start " .. (ok1 and "works" or (D.RESULT[r.code] or tostring(r.code)))) end
      -- a locked visit: what does the game's replay do with it?
      D.mission_call("replay", m, function(r2)
        local ok2 = lab_line(r2)
        finish("start " .. (D.RESULT[r.code] or tostring(r.code)) .. ", replay " .. (ok2 and "changed it" or (D.RESULT[r2.code] or tostring(r2.code))))
      end)
    end)
  end)
  return true, "asking the game..."
end

function D.lab_travel()
  local seg = D.lab.target
  if not seg then return end
  local cp = D.landing_for(seg.planet)
  if not cp then log("RANDO-LAB no landing checkpoint known for", seg.planet); return end
  local ok = D.travel(cp, "fly")
  if not ok then D.travel(cp, "warp") end
end

if RANDO_TEST_MODE then
  for _, name in ipairs(D.KEYS) do
    local okc, vc = vk_of(name)
    if okc then pcall(rivet.on_key, vc, function()
      if not ctrl_down() then return end
      local ok, err = pcall(D.lab_read)
      if not ok then log("RANDO-ERROR lab read", tostring(err)) end
    end) end
  end
  local okt, vt = pcall(rivet.key, "F11")
  if okt then pcall(rivet.on_key, vt, function()
    if not ctrl_down() then return end
    local ok, res, msg = pcall(D.lab_try)
    if not ok then log("RANDO-ERROR lab try", tostring(res)) end
    say("[LAB] mission experiment: " .. tostring(msg or res), { type = "center", duration = 6 })
  end) end
end

log("RANDO-CAMPAIGN director loaded", CAPS.source and ("capabilities: " .. CAPS.source) or "capabilities: none verified yet")
