-- Rift Apart Randomizer dev 10.15: OMEGA VERSIONS in the game (OPTIONAL; developer kit only until it has
-- run in your game: tools/build_public_release.py HELD_BACK). Read docs/OMEGA.md first.
--
-- WHAT AN OMEGA WEAPON IS IN YOUR GAME (static research, neptuwunium/rivet's DDL dump):
--   * not an item: your dag has no Omega item config, and AddToInventoryAction only gives item configs;
--   * the bool WeaponItemPrius.Omega (hash 0x534A51FB) of the weapon you own. Its base ItemPrius holds
--     ItemConfigHash, the weapon's 64-bit item config id (the id the randomizer already knows);
--   * the game sets it only when you buy an Omega at Ms. Zurkon in Challenge Mode; no script action does.
-- So 10_rando_runtime.lua keeps the TIER (weapon / Omega) and this file sets the flag of the weapon you
-- own, the one byte the vendor's Omega purchase sets, and nothing else.
--
-- HOW, WITHOUT TRUSTING ANY OFFSET NOT SEEN IN YOUR GAME:
--   1. the hero's inventory component: rivet.component(hero, class) for O.CLASSES (the Prius type is
--      ItemInventoryPrius; which class name rivet_hook answers to has not been seen yet);
--   2. its records: an array { pointer, count, capacity } in the component's first O.HEADER bytes whose
--      elements (pointers to item objects, or inline) hold the 64-bit ids of the weapons (they do not
--      appear by chance) - the same search 12_rando_shop.lua makes for the vendor's slots;
--   3. the Omega byte: LEARNED from the game itself. When you enter a vendor, every weapon record is
--      read; when you then buy an Omega there (PurchaseWeaponEvent for a weapon you already owned), the
--      bytes of that record that went 0 -> 1 are the candidates. Only a byte that every other record
--      holds as 0 or 1 counts. The candidates of O.CONFIRMATIONS (2) Omega purchases of different weapons
--      are intersected; exactly one byte left is the offset (a Raritanium upgrade made in the same visit
--      can add a candidate, never take the real one away, so one purchase alone is not trusted). It is
--      saved (state.omega_cal, kept over a New Game). Or a developer sets omega_flag_offset in
--      04_rando_settings.lua.
--   4. setting it: the record's id is read again, the byte must read 0 or 1, 01 is written, read back.
--      Only for a weapon the game has confirmed in your inventory (09_rando_real.lua: confirmed / owned).
--   5. keeping it: after every load and every 10 s, each Omega the randomizer gave, and each one the
--      game showed as Omega, is read; a cleared flag is set again (the tier never goes down, also if a
--      weapon is sent again by the inventory restore).
-- Until 3. has happened nothing is ever written: an Omega reward stays "pending" (state.omega) and is
-- set the moment the offset is known. omega_runtime = false: never written at all.
-- NOTHING OF THIS HAS RUN IN THE GAME. Simulator only (tests/test_v1015.py).
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["17_rando_omega"] = "10.0.23"   -- the kit check (10_rando_runtime.lua)

RANDO_OMEGA = RANDO_OMEGA or {}
local O = RANDO_OMEGA
local DB = RANDO_DATA
local GEN = RANDO_GEN

local function log(...) pcall(rivet.log, "[rando]", "RANDO-OMEGA", ...) end
local function S() return RANDO and RANDO.state end
local function changed() if RANDO and RANDO.mark_changed then RANDO.mark_changed() end end
local function say(text, opts) if RANDO and RANDO.say then RANDO.say(text, opts) end end
local function cfg(k) return RANDO and RANDO.config and RANDO.config[k] end
local function hexaddr(n) return string.format("%X", n) end

O.CLASSES = { "ItemInventory", "ItemInventoryPrius", "GridInventory", "GridInventoryPrius" }
O.HEADER = 0x200                 -- component bytes searched for the record array
O.OBJ = 0x60                     -- bytes of one item object searched for its id (pointer layout)
O.SPAN = 0x180                   -- bytes of a record read from its id on (the Omega byte must be in them)
O.MAX_COUNT = 512
O.CHUNK = 0x100                  -- bytes per rivet.read
O.SLICE_SECONDS = 0.002          -- the whole randomizer shares rivet_hook's 8 ms frame budget
O.SETTLE = 150                   -- frames after a load before the inventory is searched
O.KEEP_EVERY = 600               -- frames between keep checks
O.REFRESH = 30                   -- frames after a weapon was added before its record is looked for
O.MAX_WRITE_FAILS = 3
O.CONFIRMATIONS = 2              -- Omega purchases of different weapons that must agree on one byte

-- the weapons that have an Omega item, by id
O.BY_ID, O.ID_OF = {}, {}
for _, key in ipairs(GEN.sorted_keys(DB.items)) do
  local it = DB.items[key]
  if it.category == "omega" then
    local w = it.weapon:sub(8)
    O.BY_ID[it.id:upper()] = w
    O.ID_OF[w] = it.id:upper()
  end
end

O.frame = 0
O.inv = nil                      -- { comp, records = { [w] = { id_at } }, visit } of this load
O.inv_why = nil
O.jobs = {}                      -- { kind, co }, run one slice per frame, in order
O.next_search = 0
O.next_keep = 0
O.snap = nil                     -- { [w] = bytes } read when you entered a vendor
O.game_omega = {}                -- weapons the game showed as Omega (flag 1) in this session
O.fails = {}

-- ---- reading (in a job: yields between reads) ------------------------------------------------
local HEXB = {}
for i = 0, 255 do
  local ch = string.char(i)
  HEXB[string.format("%02X", i)] = ch; HEXB[string.format("%02x", i)] = ch
  HEXB[string.format("%X", i // 16) .. string.format("%x", i % 16)] = ch
  HEXB[string.format("%x", i // 16) .. string.format("%X", i % 16)] = ch
end
local function bytes_of(text)
  local hex = (text or ""):gsub("[^%x]", "")
  if #hex % 2 == 1 then hex = hex:sub(1, #hex - 1) end
  if #hex == 0 then return {} end
  return { (hex:gsub("%x%x", HEXB)):byte(1, -1) }
end
local slice_t0 = 0
local function clock() return (os and os.clock and os.clock()) or 0 end
function O.pause()
  if coroutine.isyieldable() and clock() - slice_t0 >= O.SLICE_SECONDS then coroutine.yield(); slice_t0 = clock() end
end
local function read(addr, len)
  local out, at = {}, 0
  while at < len do
    local n = math.min(O.CHUNK, len - at)
    local ok, text = pcall(rivet.read, hexaddr(addr + at), n)
    if not ok or not text then break end
    local b = bytes_of(text)
    table.move(b, 1, #b, #out + 1, out)
    if #b < n then break end
    at = at + n
    if coroutine.isyieldable() then coroutine.yield(); slice_t0 = clock() end
  end
  return out
end
O.read = read
local function hex64(b, i)
  if not b[i + 7] then return nil end
  return string.format("%02X%02X%02X%02X%02X%02X%02X%02X", b[i + 7], b[i + 6], b[i + 5], b[i + 4], b[i + 3], b[i + 2], b[i + 1], b[i])
end
local function s32(b, i)
  local v = b[i] + b[i + 1] * 0x100 + b[i + 2] * 0x10000 + b[i + 3] * 0x1000000
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end
local function valid_ptr(p) return p and p > 0x10000 and p < 0x7FFFFFFFFFFF and p % 8 == 0 end
local function gcd(a, b) while b ~= 0 do a, b = b, a % b end; return a end

-- ---- 1 + 2: the inventory component and its weapon records ------------------------------------
function O.component()
  local hero = rivet.hero and rivet.hero()
  if not hero then return nil, "no hero" end
  for _, cls in ipairs(O.CLASSES) do
    local ok, c = pcall(rivet.component, hero, cls)
    if ok and type(c) == "table" and c.address then
      local a = tonumber(tostring(c.address), 16)
      if a then return a, cls end
    end
  end
  return nil, "the hero has no component " .. table.concat(O.CLASSES, " / ")
end
-- an array of pointers to item objects: the id's offset in the objects is the one most agree on
local function records_pointers(ptr, count)
  local raw = read(ptr, count * 8)
  if #raw < count * 8 then return nil end
  local hits, votes = {}, {}
  for e = 0, count - 1 do
    local p = tonumber(hex64(raw, e * 8 + 1), 16)
    if p and p ~= 0 then
      if not valid_ptr(p) then return nil end
      local b = read(p, O.OBJ)
      for i = 1, #b - 7, 8 do
        local w = O.BY_ID[hex64(b, i) or ""]
        if w then hits[#hits + 1] = { w = w, at = p + i - 1, off = i - 1 }; votes[i - 1] = (votes[i - 1] or 0) + 1 end
      end
    end
  end
  local off, nv = nil, 0
  for o, v in pairs(votes) do if v > nv or (v == nv and off and o < off) then off, nv = o, v end end
  if not off then return nil end
  local recs, n = {}, 0
  for _, h in ipairs(hits) do
    if h.off == off and not recs[h.w] then recs[h.w] = { id_at = h.at }; n = n + 1 end
  end
  return recs, n
end
-- inline elements: the ids' spacing is the element size
local function records_inline(ptr, count)
  local data = read(ptr, math.min(0x4000, count * 0x200))
  local pos = {}
  for i = 1, #data - 7, 8 do
    local w = O.BY_ID[hex64(data, i) or ""]
    if w then pos[#pos + 1] = { at = i - 1, w = w } end
    if i % 256 == 1 then O.pause() end
  end
  if #pos == 0 then return nil end
  local g = 0
  for k = 2, #pos do g = gcd(g, pos[k].at - pos[1].at) end
  if #pos >= 2 and (g < 0x20 or g > 0x400) then return nil end
  local recs, n = {}, 0
  for _, m in ipairs(pos) do
    if (#pos == 1 or m.at % g == pos[1].at % g) and not recs[m.w] then recs[m.w] = { id_at = ptr + m.at }; n = n + 1 end
  end
  return recs, n
end
function O.find_records()
  local comp, cls = O.component()
  if not comp then return nil, cls end
  local head = read(comp, O.HEADER)
  if #head < 0x40 then return nil, "inventory component not readable" end
  local best, bn = nil, 0
  for o = 1, #head - 15, 8 do
    local ptr = tonumber(hex64(head, o) or "0", 16)
    local count, cap = s32(head, o + 8), s32(head, o + 12)
    if valid_ptr(ptr) and count >= 1 and count <= O.MAX_COUNT and cap >= count and cap <= 8192 then
      local recs, n = records_pointers(ptr, count)
      if not recs then recs, n = records_inline(ptr, count) end
      if recs and n > bn then best, bn = { comp = comp, class = cls, array_at = o - 1, records = recs, count = n }, n end
    end
  end
  if not best then
    if not O.dumped then
      O.dumped = true
      local hx = {}
      for i = 1, math.min(#head, 0x100) do hx[#hx + 1] = string.format("%02X", head[i]) end
      log(string.format("no weapon record in the first 0x%X bytes of %s at %X; its first bytes:", O.HEADER, cls, comp), table.concat(hx, " "))
    end
    return nil, "no array of weapon records in " .. cls
  end
  return best
end

-- ---- 3: the Omega byte ------------------------------------------------------------------------
function O.offset()
  local manual = cfg("omega_flag_offset")
  if type(manual) == "number" and manual >= 8 and manual < O.SPAN and math.type(manual) == "integer" then return manual, "omega_flag_offset" end
  local s = S()
  local c = s and s.omega_cal
  if type(c) == "table" and type(c.off) == "number" then return c.off, "learned from " .. tostring(c.from) end
  return nil
end
-- the bytes of every record, from its id on (a job)
local function snapshot(inv)
  local snap = {}
  for _, w in ipairs(GEN.sorted_keys(inv.records)) do snap[w] = read(inv.records[w].id_at, O.SPAN) end
  return snap
end
function O.on_vendor_entered()
  O.snap = nil
  O.start_job("snapshot", function()
    local inv = O.inv
    if not inv then
      local why
      inv, why = O.find_records()
      if not inv then log("vendor: no weapon records -", why); return end
      O.inv = inv
    end
    local snap = snapshot(inv)
    O.snap = { inv = inv, bytes = snap }
    log("vendor: " .. #GEN.sorted_keys(snap) .. " weapon record(s) read")
  end)
end
-- a purchase of a weapon already owned when you entered: an Omega (learn the byte from it)
function O.on_purchase(weapon_name)
  local item = RANDO_REAL and RANDO_REAL.weapon_item and RANDO_REAL.weapon_item(weapon_name)
  local w = item and item:sub(8)
  local snap = O.snap
  if not (w and snap and snap.bytes[w]) then return end
  O.start_job("learn", function()
    local before = snap.bytes[w]
    local after = read(snap.inv.records[w].id_at, O.SPAN)
    if hex64(after, 1) ~= O.ID_OF[w] then log("learn: the record of", w, "moved - nothing learned"); return end
    local cands = {}
    for i = 9, math.min(#before, #after) do
      if before[i] == 0 and after[i] == 1 then
        -- a flag: 0 or 1 in every other record, and 0 in at least one (a byte every weapon holds as 1,
        -- like a count, is not a flag that a purchase turned on)
        local ok, zero, others = true, false, 0
        for other, b in pairs(snap.bytes) do
          if other ~= w and b[i] ~= nil then
            others = others + 1
            if b[i] ~= 0 and b[i] ~= 1 then ok = false; break end
            if b[i] == 0 then zero = true end
          end
        end
        if ok and (zero or others == 0) then cands[#cands + 1] = i - 1 end
      end
    end
    snap.bytes[w] = after                              -- a second purchase in the same visit compares to this
    O.learn(w, cands)
  end)
end
function O.learn(w, cands)
  local s = S(); if not s then return end
  local prev = type(s.omega_cal) == "table" and s.omega_cal or nil
  if prev and prev.off then return end
  if #cands == 0 then log("purchase of", w, "changed no byte from 0 to 1 - not an Omega purchase; nothing learned"); return end
  local keep, seen = cands, {}
  if prev and type(prev.cands) == "table" and type(prev.seen) == "table" then
    if prev.seen[w] then log("a second Omega purchase of", w, "- only other weapons confirm"); return end
    local was = {}
    for _, c in ipairs(prev.cands) do was[c] = true end
    keep = {}
    for _, c in ipairs(cands) do if was[c] then keep[#keep + 1] = c end end
    if #keep == 0 then
      log("Omega purchase of", w, ": no byte in common with the earlier purchase(s) - starting over from this one")
      keep = cands
    else
      for k in pairs(prev.seen) do seen[k] = true end
    end
  end
  seen[w] = true
  local n = #GEN.sorted_keys(seen)
  local hx = {}
  for _, c in ipairs(keep) do hx[#hx + 1] = string.format("+0x%X", c) end
  for k in pairs(seen) do O.game_omega[k] = true end
  if #keep == 1 and n >= O.CONFIRMATIONS then
    s.omega_cal = { off = keep[1], from = table.concat(GEN.sorted_keys(seen), "+"), at = math.floor((rivet.time and rivet.time()) or 0) }
    changed()
    log(string.format("LEARNED: the Omega flag is the byte at +0x%X from a weapon record's item id (Omega purchases of %s)", keep[1], s.omega_cal.from))
    say("Randomizer: Omega versions can be given now (learned from your Omega purchases)", { type = "corner", duration = 6 })
    O.next_keep = 0
  else
    s.omega_cal = { cands = keep, seen = seen }
    changed()
    log(string.format("Omega purchase %d of %d (%s): candidate byte(s) %s", n, O.CONFIRMATIONS, w, table.concat(hx, " ")) ..
        (#keep > 1 and " - another Omega purchase narrows it down" or " - another weapon's Omega purchase confirms it"))
  end
end

-- ---- 4 + 5: setting and keeping ---------------------------------------------------------------
-- the game has the weapon: confirmed or recognised as owned (09_rando_real.lua), or it refused a give of
-- it ("failed": you probably have it) while its record is in the inventory
local function delivered(w)
  local s = S()
  local r = s and s.real and s.real["weapon:" .. w]
  return r and (r.status == "confirmed" or r.status == "owned" or r.status == "failed")
end
-- one weapon's flag (in a job). Returns "already", "set", or nil and why. only_read: never writes
function O.set_flag(w, off, only_read)
  local rec = O.inv and O.inv.records[w]
  if not rec then return nil, "no record" end
  local b = read(rec.id_at, off + 1)
  if hex64(b, 1) ~= O.ID_OF[w] then return nil, "the record moved" end
  local v = b[off + 1]
  if v == 1 then return "already" end
  if v ~= 0 then return nil, string.format("byte +0x%X holds %s, not a flag", off, tostring(v)) end
  if only_read then return nil, "waits for the weapon" end
  local ok, err = pcall(rivet.write, hexaddr(rec.id_at + off), "01")
  if not ok then return nil, "write refused: " .. tostring(err) end
  local back = read(rec.id_at + off, 1)
  if back[1] ~= 1 then return nil, "read back " .. tostring(back[1]) end
  return "set"
end
function O.pass(why)
  local s = S()
  local off, how = O.offset()
  if not (s and off and O.inv and cfg("omega_runtime") ~= false) then return end
  -- the randomizer's Omegas: set the pending ones, keep the applied ones
  for _, w in ipairs(GEN.sorted_keys(s.omega or {})) do
    local o = s.omega[w]
    if type(o) == "table" and O.inv.records[w] and (O.fails[w] or 0) < O.MAX_WRITE_FAILS then
      local r, err = O.set_flag(w, off, not delivered(w))
      local name = RANDO.item_name("omega:" .. w)
      if r == "set" and o.status == "applied" then
        log("kept " .. name .. " - its flag had been cleared (" .. why .. "), set again")
        say("Randomizer: " .. name .. " kept (the game had cleared it)")
      elseif r == "set" or r == "already" then
        if o.status ~= "applied" then
          RANDO.omega_applied(w, r == "set" and ("flag set, " .. how) or "the game already had it")
          say("Randomizer: " .. name .. " is yours", { type = "pickup", duration = 5 })
        end
      elseif r == nil and err ~= "waits for the weapon" then
        O.fails[w] = (O.fails[w] or 0) + 1
        log("could not set " .. name .. " - " .. tostring(err) .. " (try " .. O.fails[w] .. ")")
      end
      if r then O.game_omega[w] = true end
    end
  end
  -- Omegas the game itself showed (bought, or from a New Game+ save): never lost by a randomizer send
  for _, w in ipairs(GEN.sorted_keys(O.game_omega)) do
    if not (s.omega and s.omega[w]) and O.inv.records[w] and (O.fails[w] or 0) < O.MAX_WRITE_FAILS then
      local r, err = O.set_flag(w, off)
      if r == "set" then log("kept the game's Omega " .. w .. " - its flag had been cleared (" .. why .. "), set again")
      elseif r == nil then O.fails[w] = (O.fails[w] or 0) + 1; log("could not keep " .. w .. " - " .. tostring(err)) end
    end
  end
end
-- which weapons the game holds as Omega right now (once per load, when the offset is known)
function O.read_game_omega()
  local off = O.offset()
  if not (off and O.inv) then return end
  for _, w in ipairs(GEN.sorted_keys(O.inv.records)) do
    local b = read(O.inv.records[w].id_at, off + 1)
    if hex64(b, 1) == O.ID_OF[w] and b[off + 1] == 1 and not O.game_omega[w] then
      O.game_omega[w] = true
      log("the game holds", w, "as Omega")
    end
  end
end

-- ---- jobs -------------------------------------------------------------------------------------
function O.start_job(kind, fn)
  for _, j in ipairs(O.jobs) do if j.kind == kind and (kind == "search" or kind == "keep" or kind == "snapshot") then return false end end
  O.jobs[#O.jobs + 1] = { kind = kind, co = coroutine.create(fn) }
  return true
end
local function run_job()
  local j = O.jobs[1]
  if not j then return end
  slice_t0 = clock()
  local ok, err = coroutine.resume(j.co)
  if coroutine.status(j.co) == "dead" then
    if O.jobs[1] == j then table.remove(O.jobs, 1) end
    if not ok then log("RANDO-ERROR", j.kind .. ":", tostring(err)) end
  end
end
O.run_job = run_job

-- 10_rando_runtime.lua asks after an Omega reward. Returns "applied" | "pending" | "learning" | "off"
function O.request(w)
  if cfg("omega_runtime") == false then return "off" end
  if not O.offset() then
    if not O.told then
      O.told = true
      log("an Omega reward waits: the Omega flag's place is not known yet - buy one Omega at Ms. Zurkon (Challenge Mode)" ..
          " and it is learned, or set omega_flag_offset (docs/OMEGA.md)")
    end
    return "learning"
  end
  O.next_keep = 0                                   -- the next frame looks
  return "pending"
end

function O.forget(why)
  O.inv, O.snap, O.jobs = nil, nil, {}
  O.next_search = O.frame + O.SETTLE
  O.inv_why = why
end
function O.new_game()
  O.forget("a new game")
  O.game_omega, O.fails = {}, {}
end
function O.after_restore() O.next_keep = 0 end

function O.tick(frames, ready)
  O.frame = O.frame + 1
  if not ready or cfg("omega_runtime") == false then return end    -- (nothing is read while loading)
  if O.jobs[1] then run_job(); return end
  local s = S()
  if not (s and RANDO_SEED) then return end
  if O.inv and O.refresh and O.frame >= O.next_search then
    O.refresh = nil
    O.inv = nil                                     -- searched again below (same load: the snapshot stays)
    O.next_search = O.frame
  end
  if not O.inv then
    if O.frame < O.next_search then return end
    O.next_search = O.frame + O.KEEP_EVERY
    O.start_job("search", function()
      local inv, why = O.find_records()
      if inv then
        O.inv = inv
        log(string.format("inventory: %d weapon record(s) in %s (array at +0x%X)", inv.count, inv.class, inv.array_at))
        O.read_game_omega()
        O.pass("after a load")
        O.next_keep = O.frame + O.KEEP_EVERY
      elseif why ~= O.inv_why then
        O.inv_why = why
        log("inventory not found:", why)
      end
    end)
    return
  end
  if O.frame >= O.next_keep and O.offset() then
    O.next_keep = O.frame + O.KEEP_EVERY
    O.start_job("keep", function() O.pass("check") end)
  end
end

function O.status_text()
  local s = S()
  if not s then return nil end
  local n, done = 0, 0
  for _, o in pairs(s.omega or {}) do n = n + 1; if type(o) == "table" and o.status == "applied" then done = done + 1 end end
  if n == 0 and not O.offset() then return nil end
  return string.format("Omega %d/%d%s", done, n, O.offset() and "" or " (flag not learned)")
end

if RANDO and RANDO.subscribe then
  local function on(class, fn)
    RANDO.subscribe(class, function(ev)
      local ok, err = pcall(fn, ev.fields or {})
      if not ok then log("RANDO-ERROR", class, tostring(err)) end
    end)
  end
  on("EnteredVendorEvent", function() O.on_vendor_entered() end)
  on("ExitedVendorEvent", function() O.snap = nil end)
  on("PurchaseWeaponEvent", function(f) O.on_purchase(f.WeaponName) end)
  on("PlanetChangedEvent", function() O.forget("a planet load") end)
  on("LevelLoadedEvent", function() O.forget("a level load") end)
  -- a weapon added: its record is new, so the records are searched again (soon, not in the event)
  on("WeaponAddedEvent", function() O.refresh = true; O.next_search = math.min(O.next_search, O.frame + O.REFRESH) end)
  -- the inventory changed (a give of a weapon you own reports only this): look at the flags soon
  on("InventoryChangedEvent", function() O.next_keep = math.min(O.next_keep, O.frame + O.REFRESH) end)
  log("loaded (Omega flag " .. (O.offset() and "known" or "not learned yet") .. ")")
else
  log("RANDO-ERROR 10_rando_runtime.lua is missing: Omega versions stay records only")
end
