-- Randomizer 7.0 (unchanged since 5.0): armor sources (rivet_hook, Lua 5.4).
--
-- Every armor piece the game hands out in a story save comes from a level script running
-- VanityGiveBundleAction: the pocket dimensions, Zurkie's challenges, the Lorb monk on Savali.
-- rando_give.dll v5 replaces that action's handler with one that does the same calls, except
-- for the pieces listed in its mailbox (MB_ARMOR_TABLE): those are not given, the action still
-- reports success (so the level script goes on as usual), and the helper writes the event to a
-- ring. This script:
--   * keeps the table equal to the armor sources of this seed that are not collected yet
--     (only after the seed has started, so nothing is held back before the save is restored),
--   * reads the ring: an intercepted source collects its location, which pays that location's
--     item (any item, or Bolts / Raritanium),
--   * falls back to polling rivet.vanity_owns: a piece that appears without the randomizer
--     giving it (an older DLL, interception off, a source the table missed) still collects its
--     source, so nothing is ever lost - you then simply keep the game's own piece as well.
-- Pieces owned before the seed started (the 30 of the Deluxe Edition and free sets) never count.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["13_rando_armor"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)

RANDO_ARMOR = RANDO_ARMOR or {}
local A = RANDO_ARMOR
local DB = RANDO_DATA
local GEN = RANDO_GEN

local function log(...) pcall(rivet.log, "[rando]", "RANDO-ARMOR", ...) end
local function R() return RANDO end
local function S() return RANDO and RANDO.state end
local function SEED() return RANDO_SEED end
local function hexaddr(n) return string.format("%X", n) end

A.MB = { VERSION = 0x08, STATUS = 0x0C, VANITY = 0x74, ON = 0x100, HOOK = 0x104, SEQ = 0x10C, CALLS = 0x110,
         TABLE = 0x180, MAX = 48, RING = 0x300, RING_N = 16 }
A.HOOK_TEXT = { [0] = "not installed", [1] = "on", [2] = "this exe's armor code differs (nothing patched)",
                [3] = "a thread was inside the code at start (nothing patched)" }
A.WHAT = { [1] = "intercepted", [2] = "given by the game", [3] = "not given by the game" }
A.RING_EVERY = 10
A.SYNC_EVERY = 30
A.POLL_FRAMES = 300
A.POLL_PER_FRAME = 4

-- armor item key <-> bundle id, armor item key -> its source location
A.BY_ID, A.SOURCE_OF, A.PIECES = {}, {}, {}
for _, key in ipairs(GEN.sorted_keys(DB.items)) do
  local it = DB.items[key]
  if it.category == "armor" then
    A.BY_ID[it.id:upper()] = key
    if it.randomizable then A.PIECES[#A.PIECES + 1] = key end
  end
end
for _, lid in ipairs(GEN.sorted_keys(DB.locations)) do
  local loc = DB.locations[lid]
  if loc.kind == "armor_source" and loc.armor then A.SOURCE_OF[loc.armor] = lid end
end

-- ---- helper mailbox ------------------------------------------------------------------------
local function bytes_of(text)
  local b = {}
  for x in (text or ""):gmatch("%x%x") do b[#b + 1] = tonumber(x, 16) end
  return b
end
local function u32(b, i) return b[i] + b[i + 1] * 0x100 + b[i + 2] * 0x10000 + b[i + 3] * 0x1000000 end
local function hex64(b, i)
  return string.format("%02X%02X%02X%02X%02X%02X%02X%02X", b[i + 7], b[i + 6], b[i + 5], b[i + 4], b[i + 3], b[i + 2], b[i + 1], b[i])
end
local function read(addr, len)
  local ok, text = pcall(rivet.read, hexaddr(addr), len)
  if not ok or not text then return nil end
  local b = bytes_of(text)
  if #b < len then return nil end
  return b
end
local function le64(hex)
  hex = string.rep("0", 16 - #hex) .. hex
  local t = {}
  for k = 15, 1, -2 do t[#t + 1] = hex:sub(k, k + 1) end
  return table.concat(t, " ")
end
A.le64 = le64

-- the mailbox, when the helper is v5 and ready
function A.mailbox()
  local rr = RANDO_REAL
  if not (rr and rr.native and rr.native_ready) then return nil end
  local okr, ready = pcall(rr.native_ready)
  if not (okr and ready) then return nil end
  local n = rr.native
  if (n.version or 0) < 5 then
    if not A.old_warned then A.old_warned = true; log("rando_give.dll is older than v5: armor sources fall back to polling") end
    return nil
  end
  return n.addr
end

-- ---- the table -----------------------------------------------------------------------------
-- the bundle ids that should be intercepted now: every armor source of this seed not collected
function A.desired()
  local seed, s = SEED(), S()
  local out = {}
  if not (seed and s and s.started and seed.armor) then return out end
  if RANDO and RANDO.config and RANDO.config.armor_intercept == false then return out end
  for _, key in ipairs(A.PIECES) do
    local lid = A.SOURCE_OF[key]
    if lid and seed.locations[lid] and not s.collected[lid] then out[#out + 1] = DB.items[key].id:upper() end
  end
  if #out > A.MB.MAX then
    log("more armor sources than table entries:", #out, "- the rest fall back to polling")
    while #out > A.MB.MAX do table.remove(out) end
  end
  return out
end

function A.sync(addr)
  local want = A.desired()
  local cur = read(addr + A.MB.TABLE, 8 * A.MB.MAX)
  local on = read(addr + A.MB.ON, 4)
  if not (cur and on) then return false end
  local same = true
  for i = 1, A.MB.MAX do
    local have = hex64(cur, 8 * (i - 1) + 1)
    local w = want[i] or "0000000000000000"
    if have ~= w then same = false; break end
  end
  local want_on = (#want > 0) and 1 or 0
  if same and u32(on, 1) == want_on then return true end
  -- off while the table changes, then the new table, then on (one game thread: no race, but
  -- the order also keeps a half-written table from ever being used)
  pcall(rivet.write, hexaddr(addr + A.MB.ON), "00 00 00 00")
  for blk = 0, A.MB.MAX / 8 - 1 do
    local parts = {}
    for j = 1, 8 do parts[#parts + 1] = le64(want[blk * 8 + j] or "0000000000000000") end
    local ok, err = pcall(rivet.write, hexaddr(addr + A.MB.TABLE + 64 * blk), table.concat(parts, " "))
    if not ok then log("cannot write the armor table:", tostring(err)); return false end
  end
  if want_on == 1 then pcall(rivet.write, hexaddr(addr + A.MB.ON), "01 00 00 00") end
  if A.listed ~= #want then
    A.listed = #want
    log("intercepting " .. #want .. " armor source(s)")
  end
  return true
end

-- ---- the ring --------------------------------------------------------------------------------
function A.on_event(bundle, what)
  local s, seed, rt = S(), SEED(), R()
  local key = A.BY_ID[bundle]
  local name = key and DB.items[key].name or ("bundle " .. bundle)
  local lid = key and A.SOURCE_OF[key]
  log("source", name, A.WHAT[what] or tostring(what), lid or "(not a location)")
  if not (s and seed and rt) then return end
  s.armor_sources = s.armor_sources or {}
  if what == 1 then
    s.armor_sources[key or bundle] = "intercepted"
    rt.mark_changed()
    if lid and seed.locations[lid] then
      if not rt.collect(lid, "armor source of the " .. name) then
        -- intercepted but already collected (should not happen: the table only lists open
        -- sources): give the game's own piece back rather than lose it
        if key and RANDO_REAL then RANDO_REAL.request(key) end
      end
    elseif key and RANDO_REAL then
      RANDO_REAL.request(key)
    end
  elseif what == 2 or what == 3 then
    -- not listed (interception off, or the table was not up to date): the source still ran, so
    -- its location pays. 3: the game had nothing to add (the piece was already a reward)
    s.armor_sources[key or bundle] = s.armor_sources[key or bundle] or (what == 2 and "given" or "owned")
    rt.mark_changed()
    if lid and seed.locations[lid] and not s.collected[lid] then
      rt.collect(lid, "armor source of the " .. name .. (what == 2 and " (the game gave its own piece)" or " (already owned)"))
    end
  end
end

function A.read_ring(addr)
  local seqb = read(addr + A.MB.SEQ, 4)
  if not seqb then return end
  local seq = u32(seqb, 1)
  if A.last_seq == nil then A.last_seq = 0 end
  if seq == A.last_seq then return end
  local ring = read(addr + A.MB.RING, 16 * A.MB.RING_N)
  if not ring then return end
  local from = math.max(A.last_seq + 1, seq - A.MB.RING_N + 1)
  if from > A.last_seq + 1 then log("missed", from - A.last_seq - 1, "armor event(s) - polling covers them") end
  for q = from, seq do
    local i = 16 * (q % A.MB.RING_N) + 1
    if u32(ring, i + 8) == q then
      local ok, err = pcall(A.on_event, hex64(ring, i), u32(ring, i + 12))
      if not ok then log("event:", tostring(err)) end
    end
  end
  A.last_seq = seq
end

-- ---- polling fallback (and the baseline) ----------------------------------------------------
local job
function A.poll(frame)
  local s, seed, rt = S(), SEED(), R()
  if not job then
    if frame % A.POLL_FRAMES ~= 0 then return end
    job = { i = 1, owned = {}, ok = true }
  end
  for _ = 1, A.POLL_PER_FRAME do
    local key = A.PIECES[job.i]
    if not key then break end
    local okc, owned = pcall(rivet.vanity_owns, DB.items[key].id)
    if not okc then job.ok = false; job.err = owned; break end
    job.owned[key] = owned == true
    job.i = job.i + 1
  end
  if job.ok and job.i <= #A.PIECES then return end
  local done = job; job = nil
  if not done.ok then
    if not A.poll_warned then A.poll_warned = true; log("vanity_owns failed (" .. tostring(done.err) .. ") - will retry") end
    return
  end
  if not s.armor_baseline then
    s.armor_baseline = {}
    local n = 0
    for key, o in pairs(done.owned) do if o then s.armor_baseline[key] = true; n = n + 1 end end
    rt.mark_changed()
    log("baseline: " .. n .. " armor piece(s) owned before this seed - they do not count")
    return
  end
  for _, key in ipairs(A.PIECES) do
    if done.owned[key] and not s.armor_baseline[key] and not s.armor_found[key] then
      s.armor_found[key] = true
      rt.mark_changed()
      -- the randomizer gave it (a reward) or the ring already handled it: nothing to do
      local ours = s.inventory[key] or (s.armor_sources or {})[key]
      if not ours then
        local lid = A.SOURCE_OF[key]
        log("new piece without an intercepted source:", DB.items[key].name, lid or "")
        if lid and seed.locations[lid] and not s.collected[lid] then
          rt.collect(lid, "armor source of the " .. DB.items[key].name .. " (found by polling)")
        end
      end
    end
  end
end

-- ---- frame -------------------------------------------------------------------------------------
function A.tick(frame)
  local s, seed = S(), SEED()
  if not (seed and s and s.started) then return end
  local addr = A.mailbox()
  if addr then
    if not A.reported then
      A.reported = true
      local b = read(addr + A.MB.VANITY, 4)
      local h = read(addr + A.MB.HOOK, 4)
      A.hook = h and u32(h, 1)
      log("helper: armor give " .. ((b and u32(b, 1) == 1) and "verified" or "NOT verified") ..
          ", armor sources " .. (A.HOOK_TEXT[A.hook] or tostring(A.hook)))
    end
    if frame % A.RING_EVERY == 0 then A.read_ring(addr) end
    if seed.armor and A.hook == 1 and frame % A.SYNC_EVERY == 0 then A.sync(addr) end
  end
  if seed.armor then A.poll(frame) end
end

function A.new_game()
  A.listed = nil
  job = nil
end

function A.status_text()
  local s, seed = S(), SEED()
  if not (s and seed and seed.armor) then return nil end
  local n, got = 0, 0
  for lid in pairs(seed.locations) do
    if DB.locations[lid] and DB.locations[lid].kind == "armor_source" then
      n = n + 1
      if s.collected[lid] then got = got + 1 end
    end
  end
  return string.format("armor sources %d/%d", got, n)
end

log("loaded (" .. #A.PIECES .. " armor pieces, interception needs rando_give.dll v5)")
