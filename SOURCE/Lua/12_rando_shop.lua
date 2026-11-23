-- Randomizer 7.0: the weapon vendor's 15 slots sell the seed's weapons at the seed's prices
-- (rivet_hook, Lua 5.4).
--
-- The vendor's stock is VendorConfig.ItemDatas, an array of VendorItemData { Item, Price,
-- MissionShow/Unlock, ... } (neptuwunium/rivet Types/VendorConfig.cs, VendorItemData.cs). Each
-- slot keeps its price and the point in the story it unlocks; only its Item changes, to the
-- weapon the seed puts there (seed.shop.slots: the slot named by the weapon it sells in the normal
-- game -> the weapon it sells now). Slots not in that map (Shatterbomb, RYNO 8, the Challenge Mode
-- Pixelizer/Bouncer slots, ammo) keep their item, unless the seed gives that weapon at the start or
-- at a location: then the slot is closed (below). 10.1: Shatterbomb and RYNO 8 are always rewards,
-- so their own slots are always closed (unless excluded or weapons = false). Nothing is saved: configs reload with their level, so
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
-- v0.71-DEV1 ITEM = A POINTER. Rounds 17-45 found an array at +0x48 of the vendor config in every round, but never a
-- weapon's 64-bit id in it or in the objects it points to (8.4). rivet.config() could not show the array either: rivet_hook's
-- values_of() skips arrays of structs (ddl_visit.cpp), which is what ItemDatas is - so the DEV5 probe saw only the plain
-- numbers. In this engine a field that names another config usually holds a POINTER to that loaded config. So the vendor's
-- weapons are now also looked for as pointers: rando_give.dll (kind 7, the same lookup that finds the vendor) gives the
-- address of every registry weapon's *_item.config, once per load, and an 8-byte field equal to one of those addresses
-- counts as that weapon. The layout (inline elements or slot objects, element size, Item offset) is found exactly as for
-- ids; a write then puts the new weapon's config address there, read back as before. If neither form is found,
-- rivet.log shows the config's first bytes, the first element and some of the looked-up addresses once per session
-- (RANDO-SHOP EVIDENCE) - the next round's data. Nothing is read or written during a load (10_rando_runtime.lua).
-- v0.71-DEV3 WHY THE SLOTS WERE NEVER FOUND (round 55 log, EVIDENCE lines): the vendor config's ItemDatas is an inline array
-- (pointer at config +0x48, 33 entries) of objects that each start with the SAME vtable pointer (the first 8 bytes of the
-- array are 7FF7..., an exe address). In the first element the volcanic eruptor's item id (8D6ED40E943F3883, ARSENAL_RESTORED's
-- vendor config) sits at element +20 - a 4-byte aligned offset, NOT 8-byte aligned - and its price 9000 (0x2328) at +32. Every
-- search since round 17 stepped through the array in 8-byte steps starting at the array's start, so with a stride that is a
-- multiple of 8 an id at +20 (= 4 mod 8) was never looked at: "only 0 vendor weapon(s)" in every round. Now: the scan steps by
-- 4 bytes, and the element size is first taken from the repeats of that vtable pointer (the id matches only vote for the
-- Item offset). The vendor config's ids are still the only thing written; whether the vendor screen reads them live is
-- what the next round shows (RANDO-SHOP VERIFY / TABLE lines).
-- v0.71-DEV3 SHOP BONUS (seed.shop.bonus: vendor slot -> location shop:omega_1 ... shop:armor_2): buying the weapon in such a
-- slot also pays that location's item (an Omega version, a gadget or an armor piece), see H.on_purchase.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["12_rando_shop"] = "10.0.39"   -- the kit check (10_rando_runtime.lua)

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

-- v0.71-DEV5: WHICH WEAPON A PURCHASE EVENT NAMES. Round 57's log: PurchaseWeaponEvent said WEAPON_MRFUNGI, but the config is
-- wpn_mrfunguy_item.config, so the old lookup ("wpn_" .. name .. "_item.config") found nothing and no shop bonus was ever paid
-- ("BUY WEAPON_MRFUNGI - not a weapon of this kit's registry"). The event's own names are matched here by what they have in
-- common with the registry once everything but letters and digits is dropped: the config's name (mrfunguy), the key
-- (mr_fungi -> mrfungi), the display name. The event's WeaponConfig is the *_item.config id as a DOUBLE (the low 11 bits are
-- rounded off: 12916239727364833280 for B33FB3994F5E7EC3), so it matches an id within 4096.
local function norm_name(n)
  n = tostring(n or ""):lower():gsub("^weapon_", ""):gsub("^wpn_", "")
  return (n:gsub("[^%a%d]", ""))
end
H.norm_name = norm_name
local function id_number(hex)
  hex = tostring(hex or ""):upper()
  if not hex:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") then return nil end
  return tonumber(hex:sub(1, 8), 16) * 4294967296.0 + tonumber(hex:sub(9, 16), 16)
end
H.id_number = id_number
H.NAMES = {}
for _, key in ipairs(GEN.sorted_keys(DB.items)) do
  local it = DB.items[key]
  if it.category == "weapon" then
    local function add(n) n = norm_name(n); if n ~= "" and not H.NAMES[n] then H.NAMES[n] = key end end
    add(it.config and it.config:match("wpn_(.-)_item%.config$"))
    add((key:gsub("^weapon:", "")))
    add(it.name)
  end
end
-- name and/or config number of a purchase -> registry weapon key, and how it was found
function H.weapon_of_purchase(name, config_number)
  local num = tonumber(config_number)
  if num then
    local best, bestd, second
    for _, key in ipairs(GEN.sorted_keys(DB.items)) do
      local it = DB.items[key]
      if it.category == "weapon" and it.id then
        local n = id_number(it.id)
        local d = n and math.abs(n - num)
        if d and d <= 4096 then
          if not bestd or d < bestd then second, best, bestd = best, key, d elseif not second then second = key end
        end
      end
    end
    if best and not second then return best, "config" end
  end
  local k = H.NAMES[norm_name(name)]
  if k then return k, "name" end
  if RANDO_REAL and RANDO_REAL.weapon_item then
    k = RANDO_REAL.weapon_item(name)
    if k then return k, "name (registry)" end
  end
  return nil
end

-- v0.71-DEV1: the loaded weapon configs' addresses (address -> weapon key, weapon key -> address), per load
H.PTR, H.PTR_OF = {}, {}
H.ptr_wait, H.ptr_round, H.ptr_ready_round = 0, -1, -2
H.PTR_WAIT_FRAMES = 1800       -- ~30 s for the lookups of one load
local function load_round() return (RANDO and RANDO.loads_seen) or 0 end
function H.request_pointers(rr)
  H.PTR, H.PTR_OF = {}, {}
  H.ptr_wait, H.ptr_failed, H.ptr_round = 0, 0, load_round()
  local round = H.ptr_round
  -- only weapons a vendor slot can hold or be given: the seed's weapons and the vendor's special slots (the Burst
  -- Pistol first: closing a slot needs it). Cut weapons of the registry are never asked for.
  local want, seen = { H.CLOSE_KEY, "weapon:shatterbomb", "weapon:ryno_8", "weapon:pixelizer", "weapon:bouncer" }, {}
  local seed = SEED()
  for _, k in ipairs(GEN.sorted_keys(DB.items)) do
    local it = DB.items[k]
    if it.category == "weapon" and (it.vendor or (seed and seed.registry and seed.registry[k])) then want[#want + 1] = k end
  end
  for _, key in ipairs(want) do
    local id = DB.items[key] and DB.items[key].id:upper()
    if id and not seen[key] then
    seen[key] = true
    H.ptr_wait = H.ptr_wait + 1
    rr.lookup_config(id, function(obj)
      if round ~= H.ptr_round then return end                -- an older load's answer
      H.ptr_wait = H.ptr_wait - 1
      if obj and obj ~= "0000000000000000" then
        obj = obj:upper()
        if not H.PTR[obj] then H.PTR[obj] = key; H.PTR_OF[key] = obj end
      else
        H.ptr_failed = H.ptr_failed + 1
      end
      if H.ptr_wait == 0 then
        H.ptr_ready_round = round
        local n = 0
        for _ in pairs(H.PTR_OF) do n = n + 1 end
        if not H.ptr_said or H.ptr_said ~= n then
          H.ptr_said = n
          log(string.format("weapon configs in memory: %d of %d weapons asked for (the rest are not loaded)",
                            n, n + H.ptr_failed))
        end
      end
    end)
    end
  end
end
-- what an 8-byte value names: a registry weapon by id, or by its loaded config's address
local function match8(v)
  if not v then return nil end
  local k = H.VENDOR[v]
  if k then return k, "id" end
  k = H.PTR[v]
  if k then return k, "ptr" end
  return nil
end
H.match8 = match8
-- v0.71-DEV8 WHAT A SLOT SOLD BEFORE THIS KIT WROTE IT. Round 60 (DEV7 in the game): the first try at the vendor wrote most
-- slots and was then killed by rivet_hook's 8 ms frame budget ("apply: 12_rando_shop.lua:573: ran past the 8 ms frame budget")
-- - before its mark, so the vendor was searched again. That search took the WRITTEN weapons for the slots' own weapons and
-- shuffled them a second time (four tries in a row): the Enforcer's slot, already selling the Ricochet, was taken for the
-- Ricochet's slot and given the Void Repulser; the slots closed by the first try all read "burst_pistol" and were counted
-- once, so the Mr. Fungi, Negatron, Lightning Rod and Drillhound slots were never found - their weapons were "given
-- directly" and three of the six bonuses rode on slots that now sold the (owned) Burst Pistol. 4 of 8 weapons were for sale.
-- Now every write is remembered (address -> the slot's own weapon and the value written) BEFORE it is made, for the whole
-- session; a search reads a slot that still holds what this kit wrote as the slot's own weapon. A reloaded config holds the
-- game's values again, which never equal a written value at the same address, so nothing stale is ever used.
H.orig = H.orig or {}           -- item field address -> { key = the slot's own weapon, wrote = 8-byte hex written, mode }
H.price_orig = H.price_orig or {} -- price field address -> { orig = raw u32 before, wrote = raw u32 written }
function H.match_at(addr, v)
  local o = H.orig[addr]
  if o and v and o.wrote == v then return o.key, o.mode end
  return match8(v)
end
function H.remember(addr, key, newv, mode)
  H.orig[addr] = { key = key, wrote = newv, mode = mode }
end
-- the 8-byte value that names weapon `key` in a layout of `mode` (nil: that weapon's config is not loaded)
function H.value_of(key, mode)
  if mode == "ptr" then return H.PTR_OF[key] end
  return DB.items[key] and DB.items[key].id:upper()
end

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
    for i = 1, #b - 7, 4 do                                        -- v0.71-DEV3: 4-byte steps (an id may sit at +20)
      local cur = hex64(b, i)
      local key, mode = H.match_at(el.base + i - 1, cur)            -- v0.71-DEV8: a slot this kit wrote counts as its own weapon
      if key then
        local vk = (i - 1) .. ":" .. mode                       -- v0.71-DEV1: an offset holds ids OR pointers
        hits[#hits + 1] = { el = el, off = i - 1, key = key, mode = mode, cur = cur }
        votes[vk] = (votes[vk] or 0) + 1
      end
    end
  end
  -- the most votes; a tie goes to the SMALLER offset (as numbers: as text "112:ptr" < "16:ptr"), then to ids. A slot
  -- object read with H.OBJ bytes can reach into the next one, whose Item has as many votes one object further on.
  local off, mode, nv = nil, nil, 0
  for vk, v in pairs(votes) do
    local o, m = tonumber(vk:match("^(%d+)")), vk:match(":(%a+)$")
    if v > nv or (v == nv and (o < off or (o == off and m == "id"))) then off, mode, nv = o, m, v end
  end
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
    if m.off == off and m.mode == mode and not used[m.el.index] and not seen_key[m.key] then
      used[m.el.index] = true; seen_key[m.key] = true
      slots[#slots + 1] = { index = m.el.index, key = m.key, addr = m.el.base + off, base = m.el.base, cur = m.cur }
    end
  end
  if #slots < 3 then return nil, string.format("only %d vendor weapon(s) in the slot objects of the array at +0x%X", #slots, header_at) end
  return { data = ptr, stride = H.OBJ, offset = off, slots = slots, count = count, header_at = header_at, pointers = true,
           mode = mode }
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
      local pos, nmode = {}, {}
      for i = 1, #data - 7, 4 do                                   -- v0.71-DEV3: 4-byte steps (round 55: the id sits at element +20)
        local cur = hex64(data, i)
        local key, mode = H.match_at(ptr + i - 1, cur)              -- v0.71-DEV8: a slot this kit wrote counts as its own weapon
        if key then pos[#pos + 1] = { at = i - 1, key = key, mode = mode, cur = cur }; nmode[mode] = (nmode[mode] or 0) + 1 end
        -- v0.54: round 26 still ran past the 8 ms frame budget on this loop (a smaller READ size does
        -- not shorten it): it now yields every 256 bytes instead of every 512
        if i % 256 == 1 then H.pause(true) end
      end
      -- v0.71-DEV1: one form per array - the one with more matches (ids win a tie, as before)
      local imode = ((nmode.ptr or 0) > (nmode.id or 0)) and "ptr" or "id"
      do
        local keep = {}
        for _, m in ipairs(pos) do if m.mode == imode then keep[#keep + 1] = m end end
        pos = keep
      end
      -- v0.71-DEV3: the element size from the repeats of the array's first 8 bytes (every element starts with the same vtable
      -- pointer: round 55's array begins 98 ED D7 AC F7 7F 00 00). It must repeat at 2x and 3x as well, and 'count' elements
      -- must fit in what was read. Without it the matches' spacing (their gcd) decides, as before.
      local vstride
      do
        local vt = hex64(data, 1)
        local vp = vt and tonumber(vt, 16)
        if vp and valid_ptr(vp) then
          for i = 9, math.min(#data - 7, 0x400 + 8), 8 do
            if hex64(data, i) == vt then
              local g1 = i - 1
              if g1 >= 0x10 and (count < 3 or (hex64(data, 2 * g1 + 1) == vt and (count < 4 or hex64(data, 3 * g1 + 1) == vt))) and count * g1 <= #data + g1 then
                vstride = g1
              end
              break
            end
          end
        end
      end
      if #pos >= 2 then
        local g = vstride or 0
        if g == 0 then for k = 2, #pos do g = gcd(g, pos[k].at - pos[1].at) end end
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
              slots[#slots + 1] = { index = idx, key = m.key, addr = ptr + m.at, base = ptr + idx * g, cur = m.cur }
            end
          end
          if #slots >= 3 and not best then
            best = { data = ptr, stride = g, offset = off, slots = slots, count = count, header_at = o - 1, mode = imode,
                     bytes = data, by_vtable = vstride ~= nil }
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
    H.evidence(obj, head)
    return nil, why
  end
  table.sort(best.slots, function(a, b) return a.index < b.index end)
  return best
end

-- v0.71-DEV1: once per session, what the next round needs to see when neither ids nor pointers matched
function H.evidence(obj, head)
  if H.evidence_done then return end
  H.evidence_done = true
  local hx = {}
  for i = 1, math.min(#head, 0x100) do hx[#hx + 1] = string.format("%02X", head[i]) end
  log(string.format("EVIDENCE vendor config at %X, first %d bytes:", obj, #hx), table.concat(hx, " "))
  for o = 1, #head - 15, 8 do
    local p = tonumber(hex64(head, o) or "", 16)
    local count = s32(head, o + 8)
    if p and valid_ptr(p) and count >= 2 and count <= 256 then
      local b = read_span(p, 0x40)
      local eh = {}
      for i = 1, #b do eh[#eh + 1] = string.format("%02X", b[i]) end
      log(string.format("EVIDENCE array at +0x%X (%d entries) at %X, first %d bytes:", o - 1, count, p, #eh), table.concat(eh, " "))
    end
  end
  local some = {}
  for _, key in ipairs(GEN.sorted_keys(H.PTR_OF)) do
    if #some < 6 then some[#some + 1] = (key:gsub("^weapon:", "")) .. "=" .. H.PTR_OF[key] end
  end
  log("EVIDENCE weapon configs looked up:", #some > 0 and table.concat(some, " ") or "none found (or the lookups had not answered yet)")
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
  -- v0.71-DEV8: the writes start in a FRESH frame (round 60: the search had used up the frame and the writes were killed
  -- half-way by the 8 ms budget). From the check on nothing yields: the check and the writes happen in one frame.
  reads_in_slice = 0
  H.pause(true)
  reads_in_slice = -1000000
  local mode = lay.mode or "id"
  for _, sl in ipairs(lay.slots) do
    local now_b = read_span(sl.addr, 8)
    if hex64(now_b, 1) ~= (sl.cur or H.value_of(sl.key, mode)) then
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
  -- v0.71-DEV8 REROUTE: a slot of the seed's shop this vendor does not have (or did not show) sells its weapon - and its bonus -
  -- in one of this vendor's closed slots instead of giving the weapon away. The earliest closed slots first.
  local reroute, rerouted = {}, {}
  H.price_key = H.price_key or {}
  do
    local missing0 = {}
    for k in pairs(map) do if not found[k] and map[k] ~= H.CLOSE_KEY then missing0[#missing0 + 1] = k end end
    table.sort(missing0)
    if #missing0 > 0 then
      local spare = {}
      for _, sl in ipairs(lay.slots) do
        if closing[sl.key] and not map[sl.key] and sl.key ~= H.CLOSE_KEY then spare[#spare + 1] = sl end
      end
      table.sort(spare, function(a, b) return a.index < b.index end)
      local mv = {}
      for i, k in ipairs(missing0) do
        local sl = spare[i]
        if not sl then break end
        local w = map[k]
        if H.value_of(w, mode) then
          reroute[sl.key] = w
          rerouted[k] = sl.key
          H.price_key[sl.key] = k
          found[k] = true
          mv[#mv + 1] = (k:gsub("^weapon:", "")) .. "->slot of " .. (sl.key:gsub("^weapon:", ""))
        end
      end
      if #mv > 0 then log("vendor", id, "REROUTE: the seed's slots this vendor lacks sell in its closed slots:", table.concat(mv, " ")) end
    end
  end
  local close_id = H.value_of(H.CLOSE_KEY, mode)
  if not close_id and close_on then log("vendor", id, "the Burst Pistol's config is not loaded: slots cannot be closed this time") end
  v.closed = 0
  local shown, expect = {}, {}                         -- v0.71-DEV3: slot -> what it sells now; what to read back later
  local written = {}                                   -- v0.71-DEV8: the slots written in this try (put back if one fails)
  for _, sl in ipairs(lay.slots) do
    local new = map[sl.key] or reroute[sl.key]
    if not new and closing[sl.key] then
      if close_on and close_id then new = H.CLOSE_KEY
      elseif not H.dup_said then
        H.dup_said = true
        log("vendor", id, "slot of", sl.key, close_on and "kept (the Burst Pistol's config is not loaded, nothing to close it with):"
            or "kept (shop_close_slots = false):", closing[sl.key], "- it may come twice")
      end
    end
    local newv = new and H.value_of(new, mode)
    if new and new ~= sl.key and not newv then
      -- v0.71-DEV1: the new weapon's config is not loaded, so it cannot be named by pointer: the slot keeps its own
      -- weapon and the seed's weapon is given directly (below)
      log("vendor", id, "slot of", sl.key, "kept:", new, "has no loaded config to point to")
      if map[sl.key] then found[sl.key] = nil; mine = mine - 1 end
      new = nil
    end
    -- the value this slot must hold: the new weapon, or its own (an earlier, interrupted try may have written it)
    local want = (new and new ~= sl.key) and newv or H.value_of(sl.key, mode)
    if want and sl.cur and sl.cur == want then
      if new and new ~= sl.key then wrote = wrote + 1; expect[#expect + 1] = { addr = sl.addr, value = newv } end   -- already written
    elseif want then
      if new and new ~= sl.key then H.remember(sl.addr, sl.key, newv, mode) end
      local ok, err = pcall(rivet.write, hexaddr(sl.addr), le64(want))
      local back = ok and read_span(sl.addr, 8)
      if not (ok and back and hex64(back, 1) == want) then
        log("vendor", id, "write failed at slot", sl.index, tostring(err))
        -- put back what was written so far: never leave a half shuffle
        for _, done in ipairs(written) do
          pcall(rivet.write, hexaddr(done.addr), le64(H.value_of(done.key, mode)))
          H.orig[done.addr] = nil
        end
        v.status = "not shuffled: a write failed"
        v.tries = (v.tries or 0) + 1
        return false
      end
      written[#written + 1] = sl
      if new and new ~= sl.key then
        wrote = wrote + 1
        expect[#expect + 1] = { addr = sl.addr, value = newv }
      else
        H.orig[sl.addr] = nil                          -- its own weapon again
      end
    end
    shown[sl.key] = new or sl.key
    if new == H.CLOSE_KEY then
      parts[#parts + 1] = (sl.key:gsub("^weapon:", "")) .. "->CLOSED"
      v.closed = (v.closed or 0) + 1
    else
      parts[#parts + 1] = (sl.key:gsub("^weapon:", "")) .. "->" .. ((new or sl.key):gsub("^weapon:", "")) .. (new and "" or " (kept)")
    end
  end
  -- a rerouted slot's weapon (and its bonus) is shown under the seed's slot name too: H.slot_of_weapon finds its bonus
  for k, slk in pairs(rerouted) do shown[k] = shown[slk] end
  -- a slot of the seed's shop this vendor does not have (and no closed slot took it): its weapon is given directly
  local missing = {}
  for k, w in pairs(map) do if not found[k] then missing[#missing + 1] = w end end
  if #missing > 0 then
    table.sort(missing)
    log("vendor", id, "has no slot for", #missing, "of the seed's weapons - given directly")
    H.compensate(missing, "the vendor has no slot for it")
  end
  -- the mark: the config forgets it on reload, exactly when the stock is authored again
  local okc, cfg = pcall(rivet.config, id)
  local idle = okc and type(cfg) == "table" and cfg[H.MARK_FIELD]
  if type(idle) == "number" then pcall(rivet.config_set, id, H.MARK_FIELD, math.floor(idle) + H.MARK_FRACTION) end
  v.status = string.format("%d of %d weapon slots changed", wrote, #lay.slots)
  H.shown = H.shown or {}
  for k, w in pairs(shown) do H.shown[k] = w end
  v.verify = { at = (H.frame or 0) + H.VERIFY_FRAMES, frames = H.VERIFY_FRAMES, expect = expect }
  pcall(H.log_table, lay, obj_hex)
  v.applied = (v.applied or 0) + 1
  H.applied_total = (H.applied_total or 0) + 1
  log(string.format("vendor %s at %s: %d weapon slots, %d changed (%s, Item at +0x%X as %s, array of %d at +0x%X) - %s",
                    id, obj_hex, #lay.slots, wrote, lay.pointers and "slot objects by pointer" or string.format("element 0x%X bytes", lay.stride),
                    lay.offset, mode == "ptr" and "a config pointer" or "an item id", lay.count, lay.header_at, table.concat(parts, " ")))
  if not H.said then
    H.said = true
    say(string.format("Randomizer: Ms. Zurkon's %d weapon slots sell this seed's weapons%s", mine,
                      nclose > 0 and string.format(" (%d slots closed: those weapons are rewards)", nclose) or ""), { type = "corner", duration = 5 })
    pcall(H.announce_bonuses)
  end
  -- v0.71-DEV5: EVERYTHING BELOW MAY TAKE SEVERAL FRAMES. The slots are written; what follows (what the vendor's other fields hold,
  -- the unknown slots, the items shown in closed slots, the prices) used to run in the same frame and was killed by rivet_hook's
  -- 8 ms budget (round 57: "prices: ... ran past the 8 ms frame budget", and the EVIDENCE lines never appeared - the budget error
  -- was caught by the pcall around them). Now the frame ends here and each step reads at most one chunk per frame. A load drops
  -- the job (H.on_loading), so nothing is written into a config the load freed.
  reads_in_slice = 0
  H.pause(true)
  local okd, derr = pcall(H.dump_fields, lay, map, closing, close_on)
  if not okd then log("EVIDENCE vendor fields failed:", tostring(derr)) end
  local oks, serr = pcall(H.show_items, id, lay, closing, close_on, shown, expect, mode)
  if not oks then log("ITEMS failed:", tostring(serr)) end
  H.pause(true)
  -- 7.0 prices
  if seed.shop.prices then
    local okp, perr = pcall(H.apply_prices, id, lay, seed.shop.prices, v, shown, mode)
    if not okp then log("prices:", tostring(perr)) end
  end
  return true
end

-- v0.71-DEV7: Ms. Zurkon's screen names the WEAPON of a slot (the game's own text), so a bonus slot looks like a plain weapon.
-- Round 59 (DEV6): the one long corner note showed 2-3 words and the rest was cut off, and it came ~20 s into a load, not when you
-- talk to her. Now: ONE SHORT message per bonus ("Topiary Sprinkler = Q-Force boots"), queued one after another, shown when the
-- vendor opens (shop_note_when), when the \ key asks, or after a purchase when no "vendor opened" signal has ever come.
H.NOTE_SECONDS = 4
H.NOTE_GAP = 290                -- frames between two messages (~4.8 s at 60 fps)
H.NOTE_REPEAT = 1800            -- a second "vendor opened" signal within ~30 s does not repeat the notes
H.msgq = H.msgq or {}
function H.bonus_pairs()
  local seed, s = SEED(), S()
  local out = {}
  local bonus = seed and seed.shop and seed.shop.bonus
  if not bonus or not next(bonus) then return out end
  for _, slot in ipairs(GEN.sorted_keys(bonus)) do
    local lid = bonus[slot]
    local ik = seed.locations[lid] and seed.locations[lid].item
    local sells = (H.shown and H.shown[slot]) or slot
    local wname = DB.items[sells] and DB.items[sells].name or (sells:gsub("^weapon:", ""))
    local iname = ik and DB.items[ik] and DB.items[ik].name or tostring(ik)
    out[#out + 1] = { weapon = wname, item = iname, sells = sells, item_key = ik, lid = lid,
                      paid = (s and s.collected and s.collected[lid]) and true or false }
  end
  return out
end
function H.note_texts()
  local open = {}
  for _, p in ipairs(H.bonus_pairs()) do if not p.paid then open[#open + 1] = p.weapon .. " = " .. p.item end end
  if #open == 0 then return {} end
  local out = { string.format("Ms. Zurkon: %d bonus weapon%s", #open, #open > 1 and "s" or "") }
  for _, t in ipairs(open) do out[#out + 1] = t end
  return out
end
-- queue the notes (replacing any still waiting); quiet = only the RANDO-SHOP BONUS log lines
function H.announce_bonuses(quiet)
  local lines = H.bonus_lines()
  if #lines == 0 then return end
  local round = load_round()
  if H.bonus_logged ~= round then H.bonus_logged = round; for _, l in ipairs(lines) do log("BONUS", l) end end
  if quiet then return end
  if RANDO and RANDO.config and RANDO.config.shop_show_items == "off" then return end
  local texts = H.note_texts()
  if #texts == 0 then return end
  H.msgq = texts
  H.msg_next = 0
  H.last_note = H.frame or 0
end
function H.pump_notes(frame)
  if #H.msgq == 0 or frame < (H.msg_next or 0) then return end
  local t = table.remove(H.msgq, 1)
  say(t, { type = "center", duration = H.NOTE_SECONDS })
  H.msg_next = frame + H.NOTE_GAP
end
local function note_when() return tostring(RANDO and RANDO.config and RANDO.config.shop_note_when or "vendor") end
-- the log lines (and, with shop_note_when = "load" or "both", the notes) a while into each of the first loads
H.ann_count = H.ann_count or 0
function H.maybe_announce(frame)
  local seed, s = SEED(), S()
  if not (seed and s and s.started and seed.shop and seed.shop.bonus and next(seed.shop.bonus)) then return end
  if H.ann_count >= 3 then return end
  local round = load_round()
  if H.ann_round ~= round then H.ann_round, H.ann_at = round, frame; return end
  if frame - (H.ann_at or frame) < 1200 then return end        -- ~20 s into the load: the HUD is up
  H.ann_count = H.ann_count + 1
  H.ann_at = math.huge
  local w = note_when()
  pcall(H.announce_bonuses, not (w == "load" or w == "both"))
end
-- WHEN YOU TALK TO HER. EnteredVendorEvent never came in earlier rounds, so several event names that could mean "vendor opened"
-- are watched (the ones this game does not have are skipped silently); the first hit shows the notes. Generic names (interaction,
-- dialog, menu) are only LOGGED (VENDOR-EVIDENCE, at most 40 lines) so the next log shows which event really comes.
H.VENDOR_SIGNALS = { "EnteredVendorEvent", "VendorEnteredEvent", "VendorOpenedEvent", "VendorOpenEvent", "OpenVendorEvent",
                     "VendorMenuOpenedEvent", "VendorScreenOpenedEvent", "VendorUIOpenedEvent", "ShopOpenedEvent", "EnterVendorEvent" }
H.EVIDENCE_SIGNALS = { "ExitedVendorEvent", "VendorExitedEvent", "InteractionStartedEvent", "InteractEvent", "HeroInteractEvent",
                       "DialogStartedEvent", "DialogueStartedEvent", "ConversationStartedEvent", "NPCInteractEvent",
                       "UIOpenedEvent", "MenuOpenedEvent", "ScreenOpenedEvent", "OpenedMenuEvent" }
H.evidence_n = H.evidence_n or 0
function H.on_vendor_signal(class, ev)
  H.signal_seen = true
  local f = (ev and ev.fields) or {}
  local parts = {}
  for k, v in pairs(f) do if type(v) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v):sub(1, 40) end end
  table.sort(parts)
  log("VENDOR-SIGNAL", class, table.concat(parts, " "), "- the vendor opened")
  local w = note_when()
  if w == "load" then return end
  local now = H.frame or 0
  if H.last_note and now - H.last_note < H.NOTE_REPEAT then return end
  pcall(H.announce_bonuses)
end
function H.watch_signals()
  if H.watching or not rivet.on_event then return end
  H.watching = true
  local have, missing, ev_have = {}, {}, {}
  for _, c in ipairs(H.VENDOR_SIGNALS) do
    local ok = pcall(rivet.on_event, c, function(ev)
      local ok2, e2 = pcall(H.on_vendor_signal, c, ev)
      if not ok2 then log("signal:", tostring(e2)) end
    end)
    if ok then have[#have + 1] = c else missing[#missing + 1] = c end
  end
  for _, c in ipairs(H.EVIDENCE_SIGNALS) do
    local ok = pcall(rivet.on_event, c, function(ev)
      if H.evidence_n >= 40 then return end
      local f = (ev and ev.fields) or {}
      local parts = {}
      for k, v in pairs(f) do if type(v) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v):sub(1, 40) end end
      table.sort(parts)
      local line = c .. " " .. table.concat(parts, " ")
      H.evidence_seen = H.evidence_seen or {}
      if H.evidence_seen[line] then return end
      H.evidence_seen[line] = true
      H.evidence_n = H.evidence_n + 1
      log("VENDOR-EVIDENCE", line)
    end)
    if ok then ev_have[#ev_have + 1] = c end
  end
  log("VENDOR-SIGNAL watching:", #have > 0 and table.concat(have, ", ") or "none", "| not in this game:", #missing > 0 and table.concat(missing, ", ") or "none",
      "| logged only:", #ev_have > 0 and table.concat(ev_have, ", ") or "none")
end

-- v0.71-DEV7 NAMES ON HER SCREEN (shop_rename). The vendor screen takes a weapon's name and description from the weapon's own
-- *_item.config. A bonus slot's weapon config is changed so its DESCRIPTION ("desc") or its NAME ("name") shows the bonus item's
-- text: the text field of the weapon config is set to the same field of the item's config. Only a name/description field of the
-- same type on both sides is touched; it is read back, and put back when the bonus is paid. "probe" only logs the fields.
-- Configs are freed by a load, so it is applied again once per load. NOT TESTED IN THE GAME: RANDO-SHOP RENAME lines say what happened.
H.renamed = H.renamed or {}      -- weapon config id -> { round, field, orig }
H.rename_probed = H.rename_probed or {}
local function pv(v) return tostring(v):gsub("[\r\n\t|]", " "):sub(1, 28) end
function H.read_cfg(id)
  if not (rivet.config and id) then return nil end
  local ok, cfg = pcall(rivet.config, id)
  if ok and type(cfg) == "table" then return cfg end
  return nil, tostring(cfg)
end
function H.probe_cfg(key, id, cfg)
  if H.rename_probed[id] then return end
  H.rename_probed[id] = true
  local parts = {}
  for k, v in pairs(cfg) do
    local t = type(v)
    parts[#parts + 1] = tostring(k) .. " " .. (t == "table" and "table" or (t .. "=" .. pv(v)))
  end
  table.sort(parts)
  if #parts > 90 then parts = table.move(parts, 1, 90, 1, {}) end
  log("RENAME-PROBE", key, id, "fields:", table.concat(parts, " | "))
end
function H.text_fields(cfg)
  local out = {}
  for k, v in pairs(cfg) do
    local ks, t = tostring(k), type(v)
    local l = ks:lower()
    if ks:sub(1, 1) ~= "_" and (t == "string" or t == "number") and (l:find("name", 1, true) or l:find("desc", 1, true) or l:find("title", 1, true)) then
      out[#out + 1] = { key = ks, kind = t, value = v, low = l }
    end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end
local function first_field(list, want, avoid)
  for _, f in ipairs(list) do
    if f.low:find(want, 1, true) and not (avoid and f.low:find(avoid, 1, true)) then return f end
  end
end
function H.rename_pair(p, mode)
  local wk = DB.items[p.sells]
  local ik = p.item_key and DB.items[p.item_key]
  if not (wk and wk.id) then return log("RENAME", p.sells, "- no config id for the weapon") end
  local wcfg, werr = H.read_cfg(wk.id)
  if not wcfg then return log("RENAME", p.sells, wk.id, "- the weapon config could not be read:", tostring(werr)) end
  H.probe_cfg(p.sells, wk.id, wcfg)
  local rec = H.renamed[wk.id]
  if p.paid then      -- the bonus is yours: her screen shows the weapon's own text again
    if rec and rec.round == load_round() then
      pcall(rivet.config_set, wk.id, rec.field, rec.orig)
      log("RENAME", p.sells, "- paid: field", rec.field, "put back")
      H.renamed[wk.id] = nil
    end
    return
  end
  if mode == "probe" then
    if ik and ik.id then
      local icfg = H.read_cfg(ik.id)
      if icfg then H.probe_cfg(p.item_key, ik.id, icfg) end
    end
    return
  end
  if rec and rec.round == load_round() then return end
  if not (ik and ik.id) then return log("RENAME", p.sells, "- the item", tostring(p.item_key), "has no config id") end
  local icfg, ierr = H.read_cfg(ik.id)
  if not icfg then return log("RENAME", p.sells, "- the item config of", tostring(p.item_key), "could not be read:", tostring(ierr)) end
  H.probe_cfg(p.item_key, ik.id, icfg)
  local wf, itf = H.text_fields(wcfg), H.text_fields(icfg)
  local w = (mode == "name") and first_field(wf, "name", "desc") or first_field(wf, "desc")
  local i = first_field(itf, "name", "desc")
  if not (w and i) then
    return log("RENAME", p.sells, "- no matching text fields (weapon:", w and w.key or "none", "| item:", i and i.key or "none", ") - see RENAME-PROBE")
  end
  if w.kind ~= i.kind then return log("RENAME", p.sells, "- field types differ:", w.key, w.kind, "vs", i.key, i.kind) end
  -- DEV8: rivet_hook refuses string writes ("number expected, got string" in the round-DEV7 log), and every name/description
  -- field is a string, so nothing is written. Her screen keeps the weapon's own text; the bonus is announced by the HUD note.
  if w.kind == "string" then
    if not H.rename_string_noted then
      H.rename_string_noted = true
      log("RENAME", "skipped: rivet.config_set writes numbers only, the text fields (", w.key, ") are strings - use the HUD note (shop_note_when)")
    end
    return
  end
  local ok, err = pcall(rivet.config_set, wk.id, w.key, i.value)
  local back = ok and H.read_cfg(wk.id)
  if back and back[w.key] == i.value then
    H.renamed[wk.id] = { round = load_round(), field = w.key, orig = w.value }
    log("RENAME", p.sells, "- its", w.key, "now shows", p.item_key, "(" .. i.key .. " =", pv(i.value) .. "); was", pv(w.value))
  else
    pcall(rivet.config_set, wk.id, w.key, w.value)
    log("RENAME", p.sells, "- write of", w.key, "failed or was not kept:", tostring(err))
  end
end
-- one bonus slot per call, from ~15 s into a load (not in the loading frames)
function H.rename_tick(frame)
  local mode = tostring(RANDO and RANDO.config and RANDO.config.shop_rename or "desc")
  if mode == "off" then return end
  local seed, s = SEED(), S()
  if not (seed and s and s.started and seed.shop and seed.shop.bonus and next(seed.shop.bonus)) then return end
  local round = load_round()
  if H.rn_round ~= round then H.rn_round, H.rn_at, H.rn = round, frame, nil; return end
  if frame - (H.rn_at or frame) < 900 then return end
  if not H.rn then H.rn = { todo = H.bonus_pairs(), idx = 1 } end
  local p = H.rn.todo[H.rn.idx]
  if not p then return end
  H.rn.idx = H.rn.idx + 1
  local ok, err = pcall(H.rename_pair, p, mode)
  if not ok then log("RENAME failed:", tostring(err)) end
end

-- v0.71-DEV5: the bytes of one element as they were BEFORE the seed was written (inline layouts keep the whole array), else read
function H.element_bytes(lay, sl)
  if lay.bytes and not lay.pointers and lay.stride then
    local from = sl.index * lay.stride
    if from + lay.stride <= #lay.bytes then return table.move(lay.bytes, from + 1, from + lay.stride, 1, {}) end
  end
  return read_span(sl.base or (lay.data + sl.index * lay.stride), lay.stride)
end

-- v0.71-DEV5 EVIDENCE for the next round: which 4-byte words of the vendor's elements differ from entry to entry (that is where
-- Price, MissionShow, MissionUnlock, OmegaPrice, OmegaOnly and IsAmmo live), from the array as read before the seed was written.
-- Also the entries that are none of the registry's weapons (ARSENAL_RESTORED's Dimensionator and others: round 57 bought one).
function H.dump_fields(lay, map, closing, close_on)
  if H.fields_dumped then return end
  if not (lay.bytes and not lay.pointers and lay.stride and lay.stride <= 0x400) then
    log("EVIDENCE vendor fields: this layout keeps no copy of the array (", lay.pointers and "slot objects" or "no bytes", ")")
    return
  end
  H.fields_dumped = true
  local n, stride, b = lay.count, lay.stride, lay.bytes
  local known = {}
  for _, sl in ipairs(lay.slots) do known[sl.index] = sl.key end
  local lines = 0
  for off = 0, stride - 4, 4 do
    if off < 8 or (off >= lay.offset and off < lay.offset + 8) then goto continue end     -- the vtable and the Item id
    do
      local words, freq, ok = {}, {}, true
      for idx = 0, n - 1 do
        local at = idx * stride + off + 1
        if not b[at + 3] then ok = false; break end
        local w = string.format("%08X", u32(b, at))
        words[idx] = w; freq[w] = (freq[w] or 0) + 1
      end
      if ok then
        local common, cn = nil, 0
        for w, c in pairs(freq) do if c > cn or (c == cn and common and w < common) then common, cn = w, c end end
        if cn < n then
          local parts = {}
          for idx = 0, n - 1 do
            if words[idx] ~= common then parts[#parts + 1] = idx .. ":" .. words[idx] end
          end
          lines = lines + 1
          if lines <= 40 then
            log(string.format("EVIDENCE field +0x%02X (u32; %d of %d entries hold %s; the others as index:value): %s", off, cn, n, common, table.concat(parts, " ")))
          end
        end
      end
    end
    ::continue::
  end
  -- the entries nothing in the registry names
  local unknown = {}
  for idx = 0, n - 1 do
    if not known[idx] then
      local hx = hex64(b, idx * stride + lay.offset + 1)
      unknown[#unknown + 1] = idx .. ":" .. (hx or "-")
    end
  end
  if #unknown > 0 then
    log(string.format("EVIDENCE %d entries sell something this kit's registry does not know (index:item id; left as they are): %s", #unknown, table.concat(unknown, " ")))
  end
  -- three whole elements: an open slot, the pistol's, a closed one
  local shown_tags, want = 0, {}
  for _, sl in ipairs(lay.slots) do
    local tag = (map[sl.key] and "open") or (sl.key == H.CLOSE_KEY and "pistol") or (closing[sl.key] and "closed") or nil
    if tag and not want[tag] then
      want[tag] = true
      local eb = H.element_bytes(lay, sl)
      local hx = {}
      for i = 1, #eb do hx[#hx + 1] = string.format("%02X", eb[i]) end
      log(string.format("EVIDENCE element of the %s slot %s (index %d, %d bytes from the element start):", tag, (sl.key:gsub("^weapon:", "")), sl.index, #eb), table.concat(hx, " "))
      shown_tags = shown_tags + 1
    end
  end
end

-- v0.71-DEV5 SHOP ITEMS (shop_show_items = "try"): the bonus items that are NOT weapons (gadgets, armor) are written into closed
-- slots by their own item id, so the vendor screen would list them. UNTESTED: the vendor screen may expect a weapon in every
-- slot. Off by default ("notify"). The closed slot that hosts an item is chosen in the vendor's own order.
H.hosted, H.hosted_lids = H.hosted or {}, H.hosted_lids or {}
function H.show_items(id, lay, closing, close_on, shown, expect, mode)
  local seed = SEED()
  local how = tostring(RANDO and RANDO.config and RANDO.config.shop_show_items or "notify")
  if how ~= "try" then return end
  local bonus = seed and seed.shop and seed.shop.bonus
  if not (bonus and next(bonus)) then log("ITEMS: this seed has no shop bonus"); return end
  if mode ~= "id" or lay.pointers then log("ITEMS: the vendor names its items by pointer here; an item id cannot be written (not tried)"); return end
  local want = {}
  for _, slot in ipairs(GEN.sorted_keys(bonus)) do
    local lid = bonus[slot]
    local key = seed.locations[lid] and seed.locations[lid].item
    local it = key and DB.items[key]
    if it and (it.category == "armor" or it.category == "gadget") and it.id then want[#want + 1] = { lid = lid, key = key, it = it } end
  end
  if #want == 0 then log("ITEMS: no gadget or armor bonus in this seed"); return end
  local hosts = {}
  for _, sl in ipairs(lay.slots) do
    if shown[sl.key] == H.CLOSE_KEY and sl.key ~= H.CLOSE_KEY and closing[sl.key] then hosts[#hosts + 1] = sl end
  end
  -- the closed slots nearest to the open ones (the open ones are the earliest of the vendor's order: the nearest closed ones
  -- are the next to unlock; round 57's evidence of the fields will say which slot shows when)
  local first_open
  for _, sl in ipairs(lay.slots) do
    if seed.shop.slots and seed.shop.slots[sl.key] and (not first_open or sl.index < first_open) then first_open = sl.index end
  end
  first_open = first_open or 0
  table.sort(hosts, function(a, b)
    local da, db = math.abs(a.index - first_open), math.abs(b.index - first_open)
    if da ~= db then return da < db end
    return a.index < b.index
  end)
  for i, w in ipairs(want) do
    local sl = hosts[i]
    if not sl then log("ITEMS: no closed slot left for", w.key); break end
    local newv = w.it.id:upper()
    log("ITEMS: writing", w.key, newv, "into the closed slot of", (sl.key:gsub("^weapon:", "")), "(index " .. sl.index .. "); if the game stops here, set shop_show_items = \"notify\"")
    H.remember(sl.addr, sl.key, newv, mode)                                  -- v0.71-DEV8
    local ok, err = pcall(rivet.write, hexaddr(sl.addr), le64(newv))
    local back = ok and read_span(sl.addr, 8)
    if ok and back and hex64(back, 1) == newv then
      H.hosted[newv] = { lid = w.lid, item = w.key, slot = sl.key }
      H.hosted_lids[w.lid] = true
      local replaced = false
      for _, e in ipairs(expect) do if e.addr == sl.addr then e.value = newv; replaced = true end end    -- the slot was written once already (closed)
      if not replaced then expect[#expect + 1] = { addr = sl.addr, value = newv } end
      log("ITEMS: the slot of", (sl.key:gsub("^weapon:", "")), "now offers", w.it.name or w.key, "- bought, it pays", w.lid)
    else
      log("ITEMS: write failed at slot", sl.index, tostring(err))
      pcall(rivet.write, hexaddr(sl.addr), le64(H.value_of(H.CLOSE_KEY, mode)))
      H.remember(sl.addr, sl.key, H.value_of(H.CLOSE_KEY, mode), mode)
    end
  end
end

-- v0.71-DEV3: what every entry of the array held before the seed was written (once per vendor and load), so a round's log
-- shows the whole stock: the vanilla weapons, ARSENAL_RESTORED's, and the entries that are none of them (ammo, Omega, ...)
H.VERIFY_FRAMES = 180
function H.log_table(lay, obj_hex)
  if not lay.bytes or lay.pointers then return end
  local parts = {}
  for idx = 0, lay.count - 1 do
    local hx = hex64(lay.bytes, idx * lay.stride + lay.offset + 1)
    local key = hx and H.match_at(lay.data + idx * lay.stride + lay.offset, hx)   -- v0.71-DEV8: as it was before this kit wrote it
    parts[#parts + 1] = idx .. ":" .. (key and (key:gsub("^weapon:", "")) or (hx and ("?" .. hx:sub(-6)) or "-"))
  end
  log(string.format("TABLE vendor at %s: %d entries before the seed was written (element 0x%X bytes%s, Item at +0x%X): %s",
                    tostring(obj_hex), lay.count, lay.stride, lay.by_vtable and ", size from the vtable repeats" or ", size from the id spacing",
                    lay.offset, table.concat(parts, " ")))
end
-- read the written ids back some frames later: does the game keep the seed's stock?
function H.verify(id, v)
  local ver = v.verify
  v.verify = nil
  if not ver then return end
  local same, total = 0, 0
  for _, e in ipairs(ver.expect) do
    total = total + 1
    local b = read_span(e.addr, 8)
    if #b == 8 and hex64(b, 1) == e.value then same = same + 1 end
  end
  log(string.format("VERIFY vendor %s, %d frames after the write: %d of %d slots still hold the seed's weapon%s", id, ver.frames, same, total,
                    same == total and "" or " - the game put its own stock back, or the config was freed (a load?)"))
  v.verified = (same == total)
end

-- v0.71-DEV3 SHOP BONUS. The slot (named by its normal weapon) whose bonus a bought weapon pays. H.shown (set when the
-- vendor was changed) says what each slot sells now; with a vendor that was never changed a slot sells its own weapon.
function H.slot_of_weapon(weapon_key)
  local seed = SEED()
  local bonus = seed and seed.shop and seed.shop.bonus
  if not bonus then return nil end
  for _, slot in ipairs(GEN.sorted_keys(bonus)) do
    local sells = (H.shown and H.shown[slot]) or slot
    if sells == weapon_key then return slot, bonus[slot] end
  end
  -- the vendor was changed but this slot was not found in it (it sells its own weapon): the slot's own weapon pays
  if bonus[weapon_key] and not (H.shown and H.shown[weapon_key]) then return weapon_key, bonus[weapon_key] end
  return nil
end
function H.on_purchase(weapon_name, config_number)
  local seed, rt = SEED(), RANDO
  if not (seed and seed.shop and seed.shop.bonus and next(seed.shop.bonus) and rt and rt.collect) then return end
  local item, how = H.weapon_of_purchase(weapon_name, config_number)
  local cfgtxt = tonumber(config_number) and string.format("%.0f", tonumber(config_number)) or tostring(config_number)
  if not item then
    -- v0.71-DEV5 (shop_show_items = "try"): an armor piece or gadget written into a vendor slot is named by ITS id
    local num = tonumber(config_number)
    for hex, h in pairs(H.hosted or {}) do
      local n = id_number(hex)
      if num and n and math.abs(n - num) <= 4096 then
        local s0 = S()
        if s0 and s0.collected and s0.collected[h.lid] then log("BUY", tostring(weapon_name), "- the item of this slot was paid before:", h.lid); return end
        log("BUY", tostring(weapon_name), "config", cfgtxt, "- the slot that shows", h.item, "- pays", h.lid)
        rt.collect(h.lid, "bought in the shop (" .. tostring(h.item) .. ")")
        return
      end
    end
    log("BUY", tostring(weapon_name), "config", cfgtxt, "- not a weapon of this kit's registry (a weapon of another mod's vendor slot?): no bonus checked")
    return
  end
  local slot, lid = H.slot_of_weapon(item)
  if not slot then log("BUY", tostring(weapon_name), "(" .. item .. ", by " .. tostring(how) .. ") - no bonus rides on it"); return end
  if H.hosted_lids and H.hosted_lids[lid] then log("BUY", item, "- its bonus", lid, "is sold in a slot of its own (shop_show_items = try)"); return end
  local s = S()
  if s and s.collected and s.collected[lid] then log("BUY", item, "- the bonus of this slot was paid before:", lid); return end
  log("BUY", item, "(by " .. tostring(how) .. ") in the slot of", slot, "- pays the bonus", lid, "=", tostring(seed.locations[lid] and seed.locations[lid].item))
  rt.collect(lid, "bought in the shop (" .. item .. ")")
  H.rn = nil
end
-- status lines for the shop key (dev(debug).lua) and the log
function H.bonus_lines()
  local seed, s = SEED(), S()
  local out = {}
  local bonus = seed and seed.shop and seed.shop.bonus
  if not bonus or not next(bonus) then return out end
  for _, slot in ipairs(GEN.sorted_keys(bonus)) do
    local lid = bonus[slot]
    local it = seed.locations[lid] and seed.locations[lid].item
    local sells = (H.shown and H.shown[slot]) or slot
    local paid = s and s.collected and s.collected[lid]
    out[#out + 1] = string.format("%s%s sells %s + %s",
      paid and "[paid] " or (H.owned_seen and H.owned_seen[lid] and "[you own it: given soon] " or ""),
      (slot:gsub("^weapon:", "")), (sells:gsub("^weapon:", "")),
      it and DB.items[it] and DB.items[it].name or tostring(it))
  end
  return out
end
-- developer/test: pay the next bonus that is not paid yet, without a purchase (to test the grant itself)
function H.claim_next()
  local seed, s, rt = SEED(), S(), RANDO
  local bonus = seed and seed.shop and seed.shop.bonus
  if not (bonus and s and rt and rt.collect) then return false, "this seed has no shop bonus (shop_bonus = false, or no open slot)" end
  for _, slot in ipairs(GEN.sorted_keys(bonus)) do
    local lid = bonus[slot]
    if not (s.collected and s.collected[lid]) then
      log("CLAIM by hand: the bonus", lid, "of the slot of", slot)
      rt.collect(lid, "claimed by hand (slot " .. slot .. ")")
      return true
    end
  end
  return false, "every shop bonus of this seed is paid"
end

-- v0.71-DEV9 A BONUS SLOT SELLING A WEAPON YOU ALREADY OWN. Round 61 (DEV8 in the game): the 28 slot writes held, but the save
-- already had the Enforcer, so the slot of Mr. Fungi (Enforcer + Box Breaker) showed an owned weapon and nothing could be bought
-- there - exactly how the closed slots are closed (H.CLOSE_KEY). Its bonus could never be paid; the same for every bonus slot
-- whose weapon you hold. In a new game this happens whenever the weapon reaches you another way first: an Omega reward sends its
-- weapon before the Omega, a weapon the game gives in a cutscene, a weapon the shop had to give directly. Now a bonus whose
-- slot's weapon reads as yours in two checks H.OWNED_CONFIRM frames apart (no purchase paid it in between) is given directly:
-- "Ms. Zurkon: you already have the Enforcer - Box Breaker is yours". What counts as yours: 09_rando_real.lua says confirmed or
-- owned (never "failed", which is only "probably"), the shop gave it directly, or the hero's weapon records hold it
-- (17_rando_omega.lua: RANDO_OMEGA.held, ItemCount 1 and not an empty slot). shop_pay_owned = false keeps DEV8's behaviour.
H.OWNED_EVERY = 300             -- frames between two looks (~5 s)
H.OWNED_CONFIRM = 300           -- the weapon must still be yours this long after it was first seen
H.owned_seen = H.owned_seen or {}   -- bonus location -> frame its weapon first read as owned
function H.owns(key)
  local s = S()
  if not (s and type(key) == "string") then return false end
  local r = s.real and s.real[key]
  if type(r) == "table" and (r.status == "confirmed" or r.status == "owned") then return true, "the game has it (" .. r.status .. ")" end
  if s.shop_given and s.shop_given[key] then return true, "the shop gave it directly" end
  local O = RANDO_OMEGA
  local w = key:gsub("^weapon:", "")
  if O and type(O.held) == "table" and O.held[w] then return true, "in your weapon records" end
  return false
end
-- what a bonus slot sells, or nil while that is not known yet (the vendor was neither changed nor given up this session)
function H.bonus_sells(slot)
  if H.shown then return H.shown[slot] or slot end
  if H.off then return slot end
  for _, v in pairs(H.vendors) do if v.off and not v.no_weapons then return slot end end
  return nil
end
function H.owned_tick(frame)
  if frame % H.OWNED_EVERY ~= 0 then return end
  if RANDO and RANDO.config and RANDO.config.shop_pay_owned == false then return end
  local seed, s, rt = SEED(), S(), RANDO
  local bonus = seed and seed.shop and seed.shop.bonus
  if not (bonus and next(bonus) and s and s.started and rt and rt.collect) then return end
  for _, slot in ipairs(GEN.sorted_keys(bonus)) do
    local lid = bonus[slot]
    local sells = H.bonus_sells(slot)
    local own, how = false, nil
    if sells and sells ~= H.CLOSE_KEY and not (s.collected and s.collected[lid]) and not (H.hosted_lids and H.hosted_lids[lid]) then
      own, how = H.owns(sells)
    end
    if not own then
      H.owned_seen[lid] = nil
    elseif not H.owned_seen[lid] then
      H.owned_seen[lid] = frame
      log("OWNED", sells, "(" .. tostring(how) .. ") - the slot of", slot, "shows it owned and cannot be bought; its bonus", lid,
          "is given directly if it is still yours in", H.OWNED_CONFIRM, "frames")
    elseif frame - H.owned_seen[lid] >= H.OWNED_CONFIRM then
      H.owned_seen[lid] = nil
      local ik = seed.locations[lid] and seed.locations[lid].item
      local wname = DB.items[sells] and DB.items[sells].name or (sells:gsub("^weapon:", ""))
      local iname = ik and DB.items[ik] and DB.items[ik].name or tostring(ik)
      log("OWNED", sells, "(" .. tostring(how) .. ") - pays the bonus", lid, "=", tostring(ik), "of the slot of", slot, "directly")
      say("Ms. Zurkon: you already have the " .. wname .. " - " .. iname .. " is yours", { type = "corner", duration = 6 })
      rt.collect(lid, "shop bonus: you already own " .. wname)
      H.rn = nil
      for i = #H.msgq, 1, -1 do if H.msgq[i] == wname .. " = " .. iname then table.remove(H.msgq, i) end end   -- not announced any more
    end
  end
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
    local b = H.element_bytes(lay, sl)               -- v0.71-DEV5: the copy read before the seed was written (no memory reads)
    if #b >= lay.stride then
      elems[#elems + 1] = { sl = sl, b = b, base = base, price = price }
      if price and price > 0 then
        for o = 1, lay.stride - 3, 4 do
          local off = o - 1
          if off < lay.offset or off >= lay.offset + 8 then          -- never the Item field
            local u = u32(b, o)
            local po = H.price_orig[base + off]                    -- v0.71-DEV8: a price an interrupted try wrote
            if po and po.wrote == u then u = po.orig end
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
      local po = H.price_orig[e.base + off]
      if po and po.wrote == u then u = po.orig end
      local want = enc == "u32" and e.price or f32_bits(e.price)
      if u ~= want then return nil, string.format("+0x%X holds %d in the slot of %s, not its price %d", off, u, e.sl.key, e.price) end
    end
  end
  return { offset = off, enc = enc, matches = bestn }
end
local function le32(v)
  return string.format("%02X %02X %02X %02X", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF)
end
function H.apply_prices(id, lay, prices, v, shown, mode)
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
    local p = prices[(H.price_key and H.price_key[sl.key]) or sl.key]      -- v0.71-DEV8: a rerouted slot costs its seed slot's price
    if p then
      local addr = (sl.base or (lay.data + sl.index * lay.stride)) + pf.offset
      local raw = pf.enc == "u32" and math.floor(p) or f32_bits(p)
      -- v0.71-DEV5: this runs frames after the slots were written: the slot must still sell what the seed put there
      if shown and mode then
        local want = H.value_of(shown[sl.key] or sl.key, mode)
        local nowb = read_span(sl.addr, 8)
        if want and hex64(nowb, 1) ~= want then
          log("vendor", id, "the slot of", sl.key, "no longer sells what was written (a load?) - prices not written")
          v.price_status = "prices: the vendor changed meanwhile"
          return false
        end
      end
      do
        local nb = read_span(addr, 4)
        local nowu = #nb == 4 and u32(nb, 1)
        local po = H.price_orig[addr]
        if nowu and nowu ~= raw and not (po and po.wrote == nowu) then H.price_orig[addr] = { orig = nowu, wrote = raw }
        elseif po then po.wrote = raw end
      end
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

-- v0.71-DEV1: called by 10_rando_runtime.lua on every frame of a load: a running search holds the vendor config's
-- address and the slots' addresses, which the load frees. It is dropped (not counted as a try) and starts again after.
function H.on_loading()
  if #H.jobs > 0 then
    for _, j in ipairs(H.jobs) do j.v.pending = nil end
    H.jobs = {}
    log("a load began: the vendor search is dropped and starts again after it")
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

-- v0.62-DEV5: READ-ONLY evidence for a shop route without memory offsets. Rounds 17-45 never found the vendor's slot
-- array in memory ("only 0 vendor weapon(s) in the array at +0x48"), so Ms. Zurkon always sold her usual weapons -
-- also the ones the seed placed on Gold Bolts (round45: "Ms. Zurkon could not be changed"). The dev settings now use
-- shop = "vanilla" (her weapons are bought, never rewards). This logs, once per vendor config and session, what
-- rivet.config() answers for it (field names, types, and the first entry of any list), so a later build can tell
-- whether rivet.config_set reaches VendorConfig.ItemDatas by a path. Nothing is written.
H.probed = H.probed or {}
function H.probe_configs()
  if H.probe_done or not (rivet.configs and rivet.config) then return end
  if RANDO and RANDO.config and RANDO.config.shop_probe == false then H.probe_done = true; return end
  local ok, list = pcall(rivet.configs, "VendorConfig", 20)
  if not ok or type(list) ~= "table" then return end
  if #list == 0 then return end
  H.probe_done = true
  for _, c in ipairs(list) do
    local id = tostring(c.id):upper()
    if not H.probed[id] then
      H.probed[id] = true
      local okc, cfg = pcall(rivet.config, id)
      if okc and type(cfg) == "table" then
        local parts = {}
        for k, v in pairs(cfg) do
          local d = type(v)
          if d == "table" then
            local n, first = 0, nil
            for _, e in pairs(v) do n = n + 1; first = first or e end
            d = "table[" .. n .. "]"
            if type(first) == "table" then
              local ks = {}
              for fk, fv in pairs(first) do ks[#ks + 1] = tostring(fk) .. ":" .. type(fv) .. "=" .. tostring(fv):sub(1, 24) end
              table.sort(ks)
              d = d .. "{" .. table.concat(ks, ",") .. "}"
            elseif first ~= nil then d = d .. "{" .. type(first) .. "=" .. tostring(first):sub(1, 24) .. "}" end
          elseif d ~= "function" then d = d .. "=" .. tostring(v):sub(1, 32) end
          parts[#parts + 1] = tostring(k) .. " " .. d
        end
        table.sort(parts)
        log("PROBE vendor config", id, tostring(c.type or ""), "fields:", table.concat(parts, " | "))
      else
        log("PROBE vendor config", id, "rivet.config answered:", tostring(cfg))
      end
    end
  end
end

-- v0.71-DEV6: why the vendor is (not) rewritten, once per load: the one line the DEV5 log lacked
function H.state_line(frame, why)
  local round = load_round()
  if H.state_round == round and H.state_why == why then return end
  H.state_round, H.state_why = round, why
  local seed = SEED()
  log("STATE frame " .. tostring(frame) .. " load " .. tostring(round) .. ": " .. why .. " | seed shop mode " .. tostring(seed and seed.shop and seed.shop.mode)
      .. ", slots " .. tostring(seed and seed.shop and seed.shop.slots and "yes" or "no") .. ", shop_runtime " .. tostring(RANDO and RANDO.config and RANDO.config.shop_runtime))
end
function H.tick(frame)
  H.frame = frame
  if frame % H.EVERY == 0 then pcall(H.probe_configs) end
  pcall(H.watch_signals)
  pcall(H.maybe_announce, frame)
  pcall(H.pump_notes, frame)
  pcall(H.rename_tick, frame)
  local oko, eo = pcall(H.owned_tick, frame)                 -- v0.71-DEV9: before the returns below (a running search returns)
  if not oko then log("owned:", tostring(eo)) end
  for id, v in pairs(H.vendors) do
    if v.verify and frame >= v.verify.at and #H.jobs == 0 then
      local okv, ev = pcall(H.verify, id, v)
      if not okv then v.verify = nil; log("verify:", tostring(ev)) end
    end
  end
  local seed, s = SEED(), S()
  if not (seed and s and s.started and seed.shop and seed.shop.mode == "shuffle" and seed.shop.slots) then
    if frame % H.EVERY == 0 and seed and seed.shop then pcall(H.state_line, frame, "vendor not rewritten - " .. (s and s.started and "the seed's shop mode is not shuffle (the vendor keeps her usual weapons)" or "the seed has not started")) end
    return
  end
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
  if not (rr and rr.lookup_config and rr.native_v5) then pcall(H.state_line, frame, "no rando_game helper functions"); return end
  local okv5, v5 = pcall(rr.native_v5)
  if not (okv5 and v5) then
    pcall(H.state_line, frame, "waiting for rando_give.dll v5")
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
  if not H.helper_logged and frame % (H.EVERY * 5) == 0 then
    H.helper_logged = true        -- v0.71-DEV6: set first and run under pcall: round 58's budget error at this block stopped the whole tick
    pcall(function()
      local n = rr.native
      local function q(off)
        local okr, text = pcall(rivet.read, hexaddr(n.addr + off), 8)
        return okr and text and rr.qword_from_text(text)
      end
      local mgr, base, sigs = q(0x118), q(0x30), rr.u32_at(n.addr + 0x120)
      local rva = (mgr and base and tonumber(mgr, 16) ~= 0) and string.format("+0x%X", tonumber(mgr, 16) - tonumber(base, 16)) or "-"
      log("helper: config manager at " .. tostring(mgr) .. " (exe " .. rva .. ", rivet_hook's signature matched " .. tostring(sigs) .. "x)")
    end)
    return
  end
  -- v0.71-DEV1: this load's weapon config addresses first (the vendor's Item may be a pointer); at most
  -- H.PTR_WAIT_FRAMES, then the search goes on with whatever answered (ids are always tried)
  local round = load_round()
  pcall(H.state_line, frame, "looking for the vendor (weapon config lookups " .. tostring(H.ptr_wait) .. " pending)")
  if H.ptr_round ~= round then H.request_pointers(rr); H.ptr_asked = frame; return end
  if H.ptr_ready_round ~= round then
    if frame - (H.ptr_asked or frame) < H.PTR_WAIT_FRAMES then return end
    H.ptr_ready_round = round
    log("weapon config lookups: " .. tostring(H.ptr_wait) .. " did not answer - searching with the ones that did")
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

-- v0.71-DEV3: a weapon bought at the vendor pays the bonus of its slot. PurchaseWeaponEvent is the event the game sent for
-- every weapon bought in the logs of rounds 17-55 ("PurchaseWeaponEvent WEAPON_SHEEPINATOR"); VendorPurchaseEvent is logged
-- too (evidence only: round 46 saw it alone for an Omega purchase).
if RANDO and RANDO.subscribe then
  RANDO.subscribe("PurchaseWeaponEvent", function(ev)
    local f = (ev and ev.fields) or {}
    local ok, err = pcall(H.on_purchase, f.WeaponName, f.WeaponConfig)
    if not ok then log("RANDO-ERROR purchase:", tostring(err)) end
    if not H.signal_seen and note_when() ~= "load" then pcall(H.announce_bonuses) end    -- no "vendor opened" event ever came: show what is left after a purchase
  end)
  RANDO.subscribe("VendorPurchaseEvent", function(ev)
    local f = (ev and ev.fields) or {}
    local k, how = H.weapon_of_purchase(f.WeaponName, nil)
    log("VendorPurchaseEvent", tostring(f.WeaponName), k and ("= " .. k .. " (by " .. how .. ")") or "(not a registry weapon)")
  end)
end

log("loaded (" .. #GEN.vendor_weapons() .. " vendor weapons)")
