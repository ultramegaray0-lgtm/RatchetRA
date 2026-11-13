-- Randomizer 7.0: the weapon vendor's 15 slots sell the seed's weapons at the seed's prices
-- (rivet_hook, Lua 5.4).
--
-- The vendor's stock is VendorConfig.ItemDatas, an array of VendorItemData { Item, Price,
-- MissionShow/Unlock, ... } (neptuwunium/rivet Types/VendorConfig.cs, VendorItemData.cs). Each
-- slot keeps its price and the point in the story it unlocks; only its Item changes, to the
-- weapon the seed puts there (seed.shop.slots: the slot named by the weapon it sells in the normal
-- game -> the weapon it sells now). Slots not in that map (Shatterbomb, RYNO 8, the Challenge Mode
-- Pixelizer/Bouncer slots, ammo) are never touched. Nothing is saved: configs reload with their level, so
-- this runs again after every load. Ammo, upgrades and prices are never touched.
--
-- How the array is found, without trusting any offset that was not seen in your game:
--   1. rivet.configs("VendorConfig") lists the loaded vendor configs (as for 4.0's lock),
--   2. rando_give.dll v5 says where a config lives (the same walk rivet_hook makes, read only),
--   3. the config's first bytes are searched for dynamic arrays { pointer, count, capacity },
--   4. each array's elements are searched for the item ids of the vendor's weapons (64-bit ids
--      from your game's dag: they do not appear by chance). The spacing of the matches gives
--      the element size, their common position the Item field.
-- Only those exact 8-byte fields are rewritten, and only with ids of weapons of the registry.
-- If the shop cannot be changed (no v5 helper, no array, shop_runtime off), every weapon the seed
-- put in the shop that the normal vendor does not sell (Pixelizer, Bouncer) is given to you
-- directly instead, so no weapon is ever without a route. A done vendor is
-- marked by setting UpgradeCellYOffset's fraction to 1/16 (a layout offset of the upgrade grid:
-- 31 px -> 31.0625 px), which the config loses on its next reload, exactly when the shuffle has to
-- be applied again. The array must start in the config's first 0x100 bytes, and the first array
-- that holds the vendor's weapons is used, so a neighbouring object is never taken for it.
-- If anything does not match, the vendor is left as it is and rivet.log says why (RANDO-SHOP).
--
-- 8.4 (rounds 18-20): the search never found the slots: "only 0 vendor weapon(s) in the array at
-- +0x48", every try, every round. ItemDatas is List<VendorItemData?> (rivet's DDL,
-- VendorConfig.cs: GetObjects), an array of POINTERS to the slot objects, not the slots
-- themselves. The ids were found past the end of the pointer array (in the slot objects the
-- heap put after it), so no match fell inside it. Now an array whose elements are pointers is
-- also tried: each slot object's first H.OBJ bytes are searched for a vendor weapon's id, and
-- the Item field is the offset most slots agree on. The inline layout is still tried first.
--
-- 7.0 PRICES (seed.shop.prices: slot -> Bolts). The Price field's position is not known from your
-- game, so it is found the same way as the Item field: every slot's element is searched for that
-- slot's own vanilla price (Enforcer 1,250 ... Headhunter 40,000, data/weapon_registry.json), as a
-- 32-bit integer or a 32-bit float. Only an offset where at least 3 slots hold their own price,
-- and no slot holds a different one there, is taken; then each slot's price is written there in
-- the same encoding and read back. Otherwise prices stay the game's own (RANDO-SHOP says so).
-- 10.0 CLOSED SLOTS AND NO DUPLICATES. A seed's shop sells shop_weapons different weapons; its
-- other normal slots are listed in seed.shop.closed. A closed slot is made to sell the Burst Pistol
-- (every save owns it from the start, so the slot shows an owned weapon and nothing can be bought
-- there). Any other slot this vendor has (ARSENAL_RESTORED's own slots, Challenge Mode's Pixelizer /
-- Bouncer slots) is closed the same way when it sells a weapon the seed gives at the start or at a
-- location, so no weapon is both a reward and for sale. shop_close_slots = false leaves those
-- slots selling their own weapon (said in rivet.log). Whether the vendor screen accepts the Burst
-- Pistol in a slot has NOT been seen in your game yet.
-- 10.0 FRAME BUDGET. Rounds 17-23 logged "ran past the 8 ms frame budget" in this file at every
-- try, always while bytes were being parsed (8.x lines 88/110/113, 9.0 lines 98/182). The hex text
-- rivet.read returns is now turned into bytes by one gsub with a lookup table and string.byte (no
-- Lua loop per byte), reads are smaller, a slice also yields after H.SLICE_SECONDS, and a budget
-- error makes the next try use half the read size instead of counting against the vendor.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["12_rando_shop"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)

RANDO_SHOP = RANDO_SHOP or {}
local H = RANDO_SHOP
local DB = RANDO_DATA
local GEN = RANDO_GEN

local function log(...) pcall(rivet.log, "[rando]", "RANDO-SHOP", ...) end
local function S() return RANDO and RANDO.state end
local function SEED() return RANDO_SEED end
local function say(text, opts) if RANDO and RANDO.say then RANDO.say(text, opts) end end
local function hexaddr(n) return string.format("%X", n) end

H.EVERY = 120
H.MARK_FIELD = "UpgradeCellYOffset"
H.MARK_FRACTION = 0.0625
H.MAX_TRIES = 5
H.HEADER = 0x100                -- config bytes searched for arrays
H.CHUNK = 0x100                 -- bytes per rivet.read (its limit is 512; 10.0: 256, halved after a budget error)
H.MAX_DATA = 0x4000             -- bytes of one array searched for ids
H.vendors = H.vendors or {}     -- config id -> { status, tries, pending, ... }
H.NO_WEAPONS = "no array of the vendor's weapons in this config"
H.OBJ = 0x80                    -- 8.4: bytes of one slot object searched (pointer layout)

-- every weapon of the registry, by item id (a slot is recognised by the weapon it sells)
H.VENDOR = {}
for _, key in ipairs(GEN.sorted_keys(DB.items)) do
  if DB.items[key].category == "weapon" then H.VENDOR[DB.items[key].id:upper()] = key end
end
H.COMPENSATE_AFTER = 7200      -- frames without a usable helper before the shop's extra weapons are given

-- 10.0: hex text -> bytes without a Lua loop per byte (gsub with a table, then string.byte)
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
  local bin = hex:gsub("%x%x", HEXB)
  return { bin:byte(1, -1) }
end
H.bytes_of = bytes_of
local function hex64(b, i)
  if not b[i + 7] then return nil end
  return string.format("%02X%02X%02X%02X%02X%02X%02X%02X", b[i + 7], b[i + 6], b[i + 5], b[i + 4], b[i + 3], b[i + 2], b[i + 1], b[i])
end
local function u32(b, i) return b[i] + b[i + 1] * 0x100 + b[i + 2] * 0x10000 + b[i + 3] * 0x1000000 end
local function s32(b, i) local v = u32(b, i); if v >= 0x80000000 then v = v - 0x100000000 end; return v end
local function le64(hex)
  local t = {}
  for k = 15, 1, -2 do t[#t + 1] = hex:sub(k, k + 1) end
  return table.concat(t, " ")
end
-- len bytes from addr, in 512-byte reads; stops early (returning what it has) at unreadable memory
local function read_span(addr, len)
  local out = {}
  local at = 0
  while at < len do
    local n = math.min(H.CHUNK, len - at)
    local ok, text = pcall(rivet.read, hexaddr(addr + at), n)
    if not ok or not text then break end
    local b = bytes_of(text)
    table.move(b, 1, #b, #out + 1, out)
    if #b < n then break end
    at = at + n
    H.pause()
  end
  return out
end
H.read_span = read_span

-- 8.1: the search runs as a job (a coroutine), a slice per frame: in 8.0 it ran past rivet_hook's
-- 8 ms frame budget at every try (round 17: 440 "ran past the 8 ms frame budget" in 12_rando_shop
-- lines 88/110/113) and the vendor was never changed. H.pause() yields when called from a job
-- after H.SLICE_READS reads; outside a job (tests, tools) it does nothing.
H.SLICE_READS = 1
H.SLICE_SECONDS = 0.002         -- 10.0: a slice also ends after this long (the whole randomizer shares 8 ms)
H.jobs = H.jobs or {}
local reads_in_slice = 0
local slice_t0 = 0
local function clock() return (os and os.clock and os.clock()) or 0 end
function H.pause(force)
  if not coroutine.isyieldable() or reads_in_slice < 0 then return end
  reads_in_slice = reads_in_slice + 1
  if force or reads_in_slice >= H.SLICE_READS or clock() - slice_t0 >= H.SLICE_SECONDS then
    reads_in_slice = 0; coroutine.yield(); slice_t0 = clock()
  end
end

local function gcd(a, b) while b ~= 0 do a, b = b, a % b end; return a end

-- 8.4: an array of pointers to slot objects. Returns the layout, or nil and why.
local function valid_ptr(p) return p and p > 0x10000 and p < 0x7FFFFFFFFFFF and p % 8 == 0 end
function H.discover_pointers(ptr, count, header_at)
  local raw = read_span(ptr, count * 8)
  if #raw < count * 8 then return nil, "pointer array not readable" end
  local elems = {}
  for e = 0, count - 1 do
    local p = tonumber(hex64(raw, e * 8 + 1), 16)
    if p and p ~= 0 then
      if not valid_ptr(p) then return nil, "not an array of pointers" end
      elems[#elems + 1] = { index = e, base = p }
    end
  end
  if #elems < 3 then return nil, "too few slot objects" end
  local votes, hits = {}, {}
  for _, el in ipairs(elems) do
    local b = read_span(el.base, H.OBJ)
    el.bytes = b
    for i = 1, #b - 7, 8 do
      local id = hex64(b, i)
      if id and H.VENDOR[id] then
        hits[#hits + 1] = { el = el, off = i - 1, key = H.VENDOR[id] }
        votes[i - 1] = (votes[i - 1] or 0) + 1
      end
    end
  end
  local off, nv = nil, 0
  for o, v in pairs(votes) do if v > nv or (v == nv and off and o < off) then off, nv = o, v end end
  if not off then
    -- v0.54: the first slot object's bytes, once per session, so the next round shows its layout
    if not H.dumped_slot and elems[1] and elems[1].bytes and #elems[1].bytes > 0 then
      H.dumped_slot = true
      local hx = {}
      for i = 1, #elems[1].bytes do hx[#hx + 1] = string.format("%02X", elems[1].bytes[i]) end
      log(string.format("slot object 0 of the array at +0x%X (%d objects), first %d bytes:", header_at, #elems, #hx), table.concat(hx, " "))
    end
    return nil, string.format("no vendor weapon in the %d slot objects of the array at +0x%X", #elems, header_at)
  end
  local slots, used, seen_key = {}, {}, {}
  for _, m in ipairs(hits) do
    if m.off == off and not used[m.el.index] and not seen_key[m.key] then
      used[m.el.index] = true; seen_key[m.key] = true
      slots[#slots + 1] = { index = m.el.index, key = m.key, addr = m.el.base + off, base = m.el.base }
    end
  end
  if #slots < 3 then return nil, string.format("only %d vendor weapon(s) in the slot objects of the array at +0x%X", #slots, header_at) end
  return { data = ptr, stride = H.OBJ, offset = off, slots = slots, count = count, header_at = header_at, pointers = true }
end

-- 3 and 4 above. Returns { data = address, stride, offset, slots = { { index, key, addr, base } },
-- count, pointers } or nil and why.
function H.discover(obj)
  local head = read_span(obj, H.HEADER)
  if #head < 0x40 then return nil, "config not readable" end
  local best, why = nil, H.NO_WEAPONS
  local ptr_why = nil
  for o = 1, #head - 15, 8 do
    local p = hex64(head, o)
    local ptr = p and tonumber(p, 16)
    local count, cap = s32(head, o + 8), s32(head, o + 12)
    if ptr and ptr > 0x10000 and ptr < 0x7FFFFFFFFFFF and ptr % 8 == 0 and count >= 2 and count <= 256 and cap >= count and cap <= 4096 then
      -- 8.4: an array of pointers to slot objects (VendorConfig.ItemDatas) first
      if not best then
        local lp, whyp = H.discover_pointers(ptr, count, o - 1)
        if lp then best = lp elseif whyp ~= "not an array of pointers" and whyp ~= "too few slot objects" and whyp ~= "pointer array not readable" then
          why = whyp
          ptr_why = whyp                               -- v0.54: kept for the log (the inline try overwrote it)
        end
      end
      local data = (not best) and read_span(ptr, math.min(H.MAX_DATA, count * 0x400)) or {}
      local pos = {}
      for i = 1, #data - 7, 8 do
        local id = hex64(data, i)
        if id and H.VENDOR[id] then pos[#pos + 1] = { at = i - 1, key = H.VENDOR[id] } end
        -- v0.54: round 26 still ran past the 8 ms frame budget on this loop (a smaller READ size does
        -- not shorten it): it now yields every 256 bytes instead of every 512
        if i % 256 == 1 then H.pause(true) end
      end
      if #pos >= 2 then
        local g = 0
        for k = 2, #pos do g = gcd(g, pos[k].at - pos[1].at) end
        if g >= 0x10 and g <= 0x400 then
          local votes = {}
          for _, m in ipairs(pos) do local r = m.at % g; votes[r] = (votes[r] or 0) + 1 end
          local off, nv = nil, 0
          for r, v in pairs(votes) do if v > nv or (v == nv and off and r < off) then off, nv = r, v end end
          local slots, used, seen_key = {}, {}, {}
          for _, m in ipairs(pos) do
            local idx = (m.at - off) // g
            if m.at % g == off and idx < count and not used[idx] and not seen_key[m.key] then
              used[idx] = true; seen_key[m.key] = true
              slots[#slots + 1] = { index = idx, key = m.key, addr = ptr + m.at, base = ptr + idx * g }
            end
          end
          if #slots >= 3 and not best then
            best = { data = ptr, stride = g, offset = off, slots = slots, count = count, header_at = o - 1 }
          elseif #slots < 3 then
            why = string.format("only %d vendor weapon(s) in the array at +0x%X", #slots, o - 1)
          end
        else
          why = string.format("vendor weapons at +0x%X are %d bytes apart: not an array element size", o - 1, g)
        end
      end
    end
  end
  if not best then
    -- v0.54: both layouts' reasons reach rivet.log (rounds 18-26 only ever showed the inline one)
    if ptr_why and ptr_why ~= why then why = why .. "; as pointers: " .. ptr_why end
    return nil, why
  end
  table.sort(best.slots, function(a, b) return a.index < b.index end)
  return best
end

H.CLOSE_KEY = "weapon:burst_pistol"   -- 10.0: what a closed slot sells (owned on every save)

-- weapons of the seed's shop that the normal vendor does not sell (or `list`), given directly
-- once per run, so they always have a route
function H.compensate(list, why)
  local seed, s, rt = SEED(), S(), RANDO
  if not (seed and s and rt and seed.shop and seed.shop.slots) then return end
  if not list then
    list = {}
    for _, w in pairs(seed.shop.slots) do if not DB.items[w].vendor then list[#list + 1] = w end end
    table.sort(list)
  end
  s.shop_given = s.shop_given or {}
  for _, w in ipairs(list) do
    if not s.shop_given[w] then
      s.shop_given[w] = why
      rt.mark_changed()
      log("given directly (" .. why .. "):", w)
      rt.grant(w, false, "Shop: ")
    end
  end
end

local function is_marked(v)
  return type(v) == "number" and v - math.floor(v) == H.MARK_FRACTION
end

-- apply the seed's order to one vendor config whose address the helper found
function H.apply(id, obj_hex, v)
  local seed = SEED()
  local obj = tonumber(obj_hex, 16)
  local lay, why = H.discover(obj)
  if not lay then
    v.tries = (v.tries or 0) + 1
    v.status = "not shuffled: " .. why
    log("vendor", id, "at", obj_hex, "-", why, "(try " .. v.tries .. ")")
    if why == H.NO_WEAPONS and v.tries >= 2 then
      v.off, v.no_weapons = true, true              -- another kind of vendor: nothing to shuffle
    elseif v.tries >= H.MAX_TRIES then
      v.off = true
      H.compensate(nil, "the vendor could not be changed")
      if not H.failed_said then
        H.failed_said = true
        say("Randomizer: Ms. Zurkon could not be changed - she sells her usual weapons (some are also rewards in this seed); the seed's other shop weapons were given to you (see rivet.log)", { type = "corner", duration = 6 })
      end
    end
    return false
  end
  -- the search may have spanned frames: every slot must still sell what it sold when it was found
  -- (a level load frees the config), else nothing is written and the vendor is tried again.
  -- From here on nothing yields: the check, the writes and the prices happen in one frame.
  reads_in_slice = -1000000
  for _, sl in ipairs(lay.slots) do
    local now_b = read_span(sl.addr, 8)
    if hex64(now_b, 1) ~= DB.items[sl.key].id:upper() then
      v.status = "changed while searched: tried again"
      log("vendor", id, "changed while it was searched (a load?) - tried again")
      return false
    end
  end
  local map = seed.shop.slots
  local parts, wrote, mine = {}, 0, 0
  local found = {}
  -- 10.0: the slots to close: the seed's closed slots, and any other slot of this vendor selling a
  -- weapon the seed gives at the start or at a location
  local closing = {}
  local close_on = not (RANDO and RANDO.config and RANDO.config.shop_close_slots == false)
  for _, k in ipairs(seed.shop.closed or {}) do closing[k] = "closed by the seed" end
  local mapped = {}
  for k, w in pairs(map) do if k ~= w then mapped[w] = k end end
  for _, sl in ipairs(lay.slots) do
    if not map[sl.key] and not closing[sl.key] and sl.key ~= H.CLOSE_KEY then
      local route = seed.registry and seed.registry[sl.key]
      if route and (route:sub(1, 5) == "start" or route == "location") then closing[sl.key] = "the seed gives it (" .. route .. ")"
      elseif mapped[sl.key] then closing[sl.key] = "the slot of " .. mapped[sl.key] .. " sells it" end
    end
  end
  local nclose = 0
  for _, sl in ipairs(lay.slots) do
    if map[sl.key] then found[sl.key] = true; mine = mine + 1
    elseif closing[sl.key] and close_on then found[sl.key] = true; nclose = nclose + 1 end
  end
  if mine + nclose == 0 then
    v.off, v.no_weapons = true, true
    v.status = "no slot of the seed's shop in this config"
    log("vendor", id, "sells none of the 15 normal weapons: left alone")
    return false
  end
  local close_id = DB.items[H.CLOSE_KEY] and DB.items[H.CLOSE_KEY].id:upper()
  v.closed = 0
  for _, sl in ipairs(lay.slots) do
    local new = map[sl.key]
    if not new and closing[sl.key] then
      if close_on and close_id then new = H.CLOSE_KEY
      elseif not H.dup_said then
        H.dup_said = true
        log("vendor", id, "slot of", sl.key, "kept (shop_close_slots = false):", closing[sl.key], "- it may come twice")
      end
    end
    if new and new ~= sl.key then
      local ok, err = pcall(rivet.write, hexaddr(sl.addr), le64(DB.items[new].id:upper()))
      local back = ok and read_span(sl.addr, 8)
      if not (ok and back and hex64(back, 1) == DB.items[new].id:upper()) then
        log("vendor", id, "write failed at slot", sl.index, tostring(err))
        -- put back what was written so far: never leave a half shuffle
        for _, done in ipairs(lay.slots) do
          if done == sl then break end
          pcall(rivet.write, hexaddr(done.addr), le64(DB.items[done.key].id:upper()))
        end
        v.status = "not shuffled: a write failed"
        v.tries = (v.tries or 0) + 1
        return false
      end
      wrote = wrote + 1
    end
    if new == H.CLOSE_KEY then
      parts[#parts + 1] = (sl.key:gsub("^weapon:", "")) .. "->CLOSED"
      v.closed = (v.closed or 0) + 1
    else
      parts[#parts + 1] = (sl.key:gsub("^weapon:", "")) .. "->" .. ((new or sl.key):gsub("^weapon:", "")) .. (new and "" or " (kept)")
    end
  end
  -- a slot of the seed's shop this vendor does not have: its weapon is given directly
  local missing = {}
  for k, w in pairs(map) do if not found[k] then missing[#missing + 1] = w end end
  if #missing > 0 then
    table.sort(missing)
    log("vendor", id, "has no slot for", #missing, "of the seed's weapons - given directly")
    H.compensate(missing, "the vendor has no slot for it")
  end
  -- 7.0 prices
  if seed.shop.prices then
    local okp, perr = pcall(H.apply_prices, id, lay, seed.shop.prices, v)
    if not okp then log("prices:", tostring(perr)) end
  end
  -- the mark: the config forgets it on reload, exactly when the stock is authored again
  local okc, cfg = pcall(rivet.config, id)
  local idle = okc and type(cfg) == "table" and cfg[H.MARK_FIELD]
  if type(idle) == "number" then pcall(rivet.config_set, id, H.MARK_FIELD, math.floor(idle) + H.MARK_FRACTION) end
  v.status = string.format("%d of %d weapon slots changed", wrote, #lay.slots)
  v.applied = (v.applied or 0) + 1
  H.applied_total = (H.applied_total or 0) + 1
  log(string.format("vendor %s at %s: %d weapon slots, %d changed (%s, Item at +0x%X, array of %d at +0x%X) - %s",
                    id, obj_hex, #lay.slots, wrote, lay.pointers and "slot objects by pointer" or string.format("element 0x%X bytes", lay.stride),
                    lay.offset, lay.count, lay.header_at, table.concat(parts, " ")))
  if not H.said then
    H.said = true
    say(string.format("Randomizer: Ms. Zurkon's %d weapon slots sell this seed's weapons%s", mine,
                      nclose > 0 and string.format(" (%d slots closed: those weapons are rewards)", nclose) or ""), { type = "corner", duration = 5 })
  end
  return true
end

-- 7.0 the Price field: an offset inside the element where the slots hold their own vanilla price
local function f32_bits(x)
  return string.unpack("<I4", string.pack("<f", x))
end
H.MIN_PRICE_MATCHES = 3
function H.find_price(lay)
  local votes = {}                  -- "offset:enc" -> { n = matches, bad = slots with another value }
  local elems = {}
  for _, sl in ipairs(lay.slots) do
    local price = DB.items[sl.key] and DB.items[sl.key].price
    local base = sl.base or (lay.data + sl.index * lay.stride)
    local b = read_span(base, lay.stride)
    if #b >= lay.stride then
      elems[#elems + 1] = { sl = sl, b = b, base = base, price = price }
      if price and price > 0 then
        for o = 1, lay.stride - 3, 4 do
          local off = o - 1
          if off < lay.offset or off >= lay.offset + 8 then          -- never the Item field
            local u = u32(b, o)
            if u == price then local k = off .. ":u32"; votes[k] = (votes[k] or 0) + 1 end
            if u == f32_bits(price) then local k = off .. ":f32"; votes[k] = (votes[k] or 0) + 1 end
          end
        end
      end
    end
  end
  local best, bestn = nil, 0
  for k, n in pairs(votes) do
    if n > bestn or (n == bestn and best and k < best) then best, bestn = k, n end
  end
  if not best or bestn < H.MIN_PRICE_MATCHES then
    return nil, string.format("no field holds the slots' own prices (best: %d slot(s))", bestn)
  end
  local off, enc = best:match("^(%d+):(%a+%d+)$")
  off = tonumber(off)
  -- every slot with a known price must hold exactly it there
  for _, e in ipairs(elems) do
    if e.price and e.price > 0 then
      local u = u32(e.b, off + 1)
      local want = enc == "u32" and e.price or f32_bits(e.price)
      if u ~= want then return nil, string.format("+0x%X holds %d in the slot of %s, not its price %d", off, u, e.sl.key, e.price) end
    end
  end
  return { offset = off, enc = enc, matches = bestn }
end
local function le32(v)
  return string.format("%02X %02X %02X %02X", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF)
end
function H.apply_prices(id, lay, prices, v)
  local pf, why = H.find_price(lay)
  if not pf then
    v.price_status = "prices as usual: " .. why
    log("vendor", id, "prices left as they are -", why)
    if not H.price_said then
      H.price_said = true
      say("Randomizer: Ms. Zurkon's prices are her usual ones (see rivet.log)", { type = "corner", duration = 5 })
    end
    return false
  end
  local n, parts = 0, {}
  for _, sl in ipairs(lay.slots) do
    local p = prices[sl.key]
    if p then
      local addr = (sl.base or (lay.data + sl.index * lay.stride)) + pf.offset
      local raw = pf.enc == "u32" and math.floor(p) or f32_bits(p)
      local ok, err = pcall(rivet.write, hexaddr(addr), le32(raw))
      local back = ok and read_span(addr, 4)
      if not (ok and back and #back == 4 and u32(back, 1) == raw) then
        log("vendor", id, "price write failed at slot", sl.index, tostring(err))
        v.price_status = "prices: a write failed"
        return false
      end
      n = n + 1
      parts[#parts + 1] = (sl.key:gsub("^weapon:", "")) .. "=" .. p
    end
  end
  v.price_status = string.format("%d prices set", n)
  log(string.format("vendor %s: Price at +0x%X (%s, %d slots held their own price): %s", id, pf.offset, pf.enc, pf.matches,
                    table.concat(parts, " ")))
  return true
end

-- one slice of the first job; a job that fails is counted as a try, and MAX_TRIES failures turn
-- the vendor off (8.0 retried a failing vendor forever)
function H.run_job()
  local job = H.jobs[1]
  if not job then return end
  reads_in_slice = 0
  slice_t0 = clock()
  local first = job.args_given == nil
  job.args_given = true
  local ok, res
  if first then ok, res = coroutine.resume(job.co, job.id, job.obj, job.v)
  else ok, res = coroutine.resume(job.co) end
  if ok and coroutine.status(job.co) ~= "dead" then return end
  table.remove(H.jobs, 1)
  local v = job.v
  v.pending = nil
  if not ok and tostring(res):find("frame budget", 1, true) and (v.budget_hits or 0) < 4 then
    v.budget_hits = (v.budget_hits or 0) + 1
    H.CHUNK = math.max(0x40, H.CHUNK // 2)
    log("apply:", tostring(res), string.format("- reading 0x%X bytes at a time from now on (not counted as a try)", H.CHUNK))
    return
  end
  if not ok then
    v.tries = (v.tries or 0) + 1
    log("apply:", tostring(res), "(try " .. v.tries .. ")")
    if v.tries >= H.MAX_TRIES and not v.off then
      v.off = true
      v.status = "not shuffled: " .. tostring(res)
      H.compensate(nil, "the vendor could not be changed")
    end
  else
    log(string.format("vendor %s: search %s after %d frames", job.id, res and "done" or "ended", H.frame - job.started))
  end
end

-- why the vendor can never be changed in this session, or nil while it still might be
function H.helper_missing(n)
  n = n or {}
  if not n.addr then return "rando_give.dll is not loaded" end
  if n.dead then return "rando_give.dll stopped working" end
  if n.version and n.version < 5 then return "rando_give.dll is older than v5" end
  return nil
end

function H.tick(frame)
  H.frame = frame
  local seed, s = SEED(), S()
  if not (seed and s and s.started and seed.shop and seed.shop.mode == "shuffle" and seed.shop.slots) then return end
  if #H.jobs > 0 then
    local okj, ej = pcall(H.run_job)
    if not okj then log("job:", tostring(ej)); local j = table.remove(H.jobs, 1); if j then j.v.pending = nil end end
    return
  end
  if H.off or frame % H.EVERY ~= 0 then return end
  H.since = H.since or frame
  if RANDO and RANDO.config and RANDO.config.shop_runtime == false then
    H.off = true; log("shop_runtime is off: Ms. Zurkon sells her usual weapons")
    H.compensate(nil, "shop_runtime is off"); return
  end
  if not (rivet.configs and rivet.config and rivet.config_set) then
    H.off = true; log("rivet_hook has no config API - the vendor is not changed")
    H.compensate(nil, "rivet_hook has no config API"); return
  end
  local rr = RANDO_REAL
  if not (rr and rr.lookup_config and rr.native_v5) then return end
  local okv5, v5 = pcall(rr.native_v5)
  if not (okv5 and v5) then
    if not H.waiting_said and frame - H.since > 3600 then H.waiting_said = true; log("waiting for rando_give.dll (v5 or later, needed to find the vendor in memory)") end
    -- 8.5: also without the helper at all, or with one that stopped (the header always promised
    -- this; 8.4 only covered an old helper, so the shop's extra weapons had no route otherwise).
    -- A helper that is only paused until the next planet (soft_off) is waited for.
    if frame - H.since > H.COMPENSATE_AFTER and not H.comp_old then
      local why = H.helper_missing(rr.native)
      if why then H.comp_old = true; H.compensate(nil, why) end
    end
    return
  end
  if not H.helper_logged then
    H.helper_logged = true
    local n = rr.native
    local function q(off)
      local okr, text = pcall(rivet.read, hexaddr(n.addr + off), 8)
      return okr and text and rr.qword_from_text(text)
    end
    local mgr, base, sigs = q(0x118), q(0x30), rr.u32_at(n.addr + 0x120)
    local rva = (mgr and base and tonumber(mgr, 16) ~= 0) and string.format("+0x%X", tonumber(mgr, 16) - tonumber(base, 16)) or "-"
    log("helper: config manager at " .. tostring(mgr) .. " (exe " .. rva .. ", rivet_hook's signature matched " .. tostring(sigs) .. "x)")
  end
  local ok, list = pcall(rivet.configs, "VendorConfig", 50)
  if not ok or type(list) ~= "table" then
    H.errors = (H.errors or 0) + 1
    if H.errors == 1 then log("cannot list vendor configs:", tostring(list)) end
    return
  end
  for _, c in ipairs(list) do
    local id = tostring(c.id):upper()
    local v = H.vendors[id] or {}
    H.vendors[id] = v
    if not (v.off or v.pending) then
      local okc, cfg = pcall(rivet.config, id)
      local idle = okc and type(cfg) == "table" and cfg[H.MARK_FIELD]
      if not is_marked(idle) then
        v.pending = true
        rr.lookup_config(id, function(obj, err)
          v.pending = nil
          if not obj then
            v.tries = (v.tries or 0) + 1
            v.status = "not found: " .. tostring(err)
            log("vendor", id, "not found in memory:", tostring(err))
            if v.tries >= H.MAX_TRIES then
              -- 8.5: as for a vendor that could not be changed (8.4 turned it off without a route)
              v.off = true
              H.compensate(nil, "the vendor could not be found in memory")
            end
            return
          end
          v.pending = true
          H.jobs[#H.jobs + 1] = { id = id, obj = obj, v = v, co = coroutine.create(H.apply), started = H.frame }
        end)
      end
    end
  end
end

function H.status_text()
  local seed = SEED()
  if not (seed and seed.shop and seed.shop.mode == "shuffle") then return nil end
  if (H.applied_total or 0) > 0 then
    local closed = 0
    for _, v in pairs(H.vendors) do if (v.closed or 0) > closed then closed = v.closed end end
    return "shop randomized" .. (closed > 0 and string.format(" (%d slots closed)", closed) or "")
  end
  for _, v in pairs(H.vendors) do if v.off and not v.no_weapons then return "shop as usual" end end
  return nil
end

log("loaded (" .. #GEN.vendor_weapons() .. " vendor weapons)")
