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
-- v0.62-DEV10: steps 1-3 are replaced by the game's own type data (see "THE WEAPON ITEMS BY THE GAME'S OWN TYPE DATA"
-- below): the weapon records are the WeaponItemPrius components of the scene, the Omega byte is the live
-- WeaponItemPrius.Omega offset. Learning from a purchase stays only as the fallback (and as a confirmation).
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["17_rando_omega"] = "10.0.39"   -- the kit check (10_rando_runtime.lua)

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
-- v0.62-DEV5: round45 (kit 10.0.24, the hero component enumeration): the live hero has NONE of the four names above;
-- its item / weapon components are GameInventoryManager (8552 bytes), HeroWeaponManagerLocal (2080),
-- GameEquipManager (872) and VanityInventoryManager (17640, armor). Rounds 27-45 all logged "inventory not found".
-- These are searched next, the whole component (O.MAX_HEADER at most), for the same proof as before: an array whose
-- elements hold the 64-bit item ids of the weapons. Nothing is written until the Omega byte is learned (step 3).
O.CLASSES_LIVE = { "GameInventoryManager", "HeroWeaponManagerLocal", "GameEquipManager" }
O.HEADER = 0x200                 -- component bytes searched for the record array
O.MAX_HEADER = 0x2200            -- v0.62-DEV5: at most this much of a live component (GameInventoryManager: 0x2168)
O.OBJ = 0x60                     -- bytes of one item object searched for its id (pointer layout)
O.SPAN = 0x180                   -- bytes of a record read from its id on (the Omega byte must be in them)
O.MAX_COUNT = 512
O.CHUNK = 0x100                  -- bytes per rivet.read
O.SLICE_SECONDS = 0.0015         -- the whole randomizer shares rivet_hook's 8 ms frame budget
-- v0.62-DEV8: round48 (DEV7 in the game): the search job was killed 19 times ("ran past the 8 ms frame budget" at the
-- walk's reads) and the walk never finished. rivet_hook (src/scripting.cpp) arms ONE 8 ms deadline per callback - the
-- randomizer's whole frame, Enemy Randomizer included - and checks it from a count hook every 10,000 instructions. A
-- job coroutine inherits that hook with its OWN counter, which carries over from frame to frame, so it is the code that
-- happens to be running when a busy frame is checked. Now: a job runs only when the frame so far has used less than
-- O.FRAME_ROOM (R.frame_t0, set by 10_rando_runtime.lua's frame callback), its slice is short, and a killed walk
-- continues where it stopped (O.wstate) instead of starting over.
O.FRAME_ROOM = 0.003
O.FRAME_HARD = 0.005             -- v0.62-DEV10: a starved job still runs while the frame has used less than this
O.STARVE_FRAMES = 4              -- v0.62-DEV10: skipped frames in a row before a starved job runs anyway
O.SLICE_SHORT = 0.00075          -- v0.62-DEV10: its slice then
O.SLICE_LONG = 0.003             -- v0.62-DEV11: the longest slice, in a quiet frame
O.FRAME_TARGET = 0.0045          -- v0.62-DEV11: frame time used + slice stays under this (of rivet_hook's 8 ms)
O.SETTLE = 150                   -- frames after a load before the inventory is searched
O.KEEP_EVERY = 600               -- frames between keep checks
O.REFRESH = 30                   -- frames after a weapon was added before its record is looked for
O.MAX_WRITE_FAILS = 3
O.CONFIRMATIONS = 2              -- Omega purchases of different weapons that must agree on one byte

-- the weapons that have an Omega item, by id
O.BY_ID, O.ID_OF, O.BY_KEY = {}, {}, {}
for _, key in ipairs(GEN.sorted_keys(DB.items)) do
  local it = DB.items[key]
  if it.category == "omega" then
    local w = it.weapon:sub(8)
    O.BY_ID[it.id:upper()] = w
    O.ID_OF[w] = it.id:upper()
    O.BY_KEY[key] = w
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
O.slice = 0.0015                 -- v0.62-DEV10: this resume's slice (shorter when the job runs in a busy frame)
function O.pause()
  if coroutine.isyieldable() and clock() - slice_t0 >= O.slice then coroutine.yield(); slice_t0 = clock() end
end
local function read(addr, len, chunk)
  local out, at = {}, 0
  chunk = chunk or O.CHUNK
  while at < len do
    local n = math.min(chunk, len - at)
    local ok, text = pcall(rivet.read, hexaddr(addr + at), n)
    if not ok or not text then break end
    local b = bytes_of(text)
    table.move(b, 1, #b, #out + 1, out)
    if #b < n then break end
    at = at + n
    O.pause()                                         -- v0.62-DEV8: time-sliced (was: one read per frame)
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
O.hex64, O.valid_ptr = hex64, valid_ptr
local function gcd(a, b) while b ~= 0 do a, b = b, a % b end; return a end

-- ---- 1 + 2: the inventory component and its weapon records ------------------------------------
-- If the known inventory names are absent, enumerate the live hero once. This is diagnostic
-- only: a similarly named component is never treated as the inventory until its layout is proven.
function O.component_diagnostic(hero)
  if O.component_diag_done then return end
  O.component_diag_done = true
  local ok, classes = pcall(rivet.components, hero)
  if not ok or type(classes) ~= "table" then
    log("hero component enumeration failed:", tostring(classes))
    return
  end
  table.sort(classes)
  log("hero component enumeration:", #classes, "component(s)")
  log("hero component classes:", table.concat(classes, ", "))
  local relevant = 0
  for _, class in ipairs(classes) do
    local name = tostring(class):lower()
    if name:find("item", 1, true) or name:find("invent", 1, true)
      or name:find("weapon", 1, true) or name:find("equip", 1, true)
      or name:find("loadout", 1, true) then
      relevant = relevant + 1
      local okc, c = pcall(rivet.component, hero, class)
      if okc and type(c) == "table" then
        log("hero component candidate", tostring(class), "address", tostring(c.address),
            "size", tostring(c.size), "prius", tostring(c.prius), "prius_size", tostring(c.prius_size),
            "prius_behavior", tostring(c.prius_behavior))
        local size = math.tointeger(tonumber(c.prius_size)) or 0
        if c.prius and size > 0 then
          local n = math.min(size, 0x80, 512)
          local okr, bytes = pcall(rivet.read, tostring(c.prius), n)
          if okr and bytes then log("hero component Prius bytes", tostring(class), tostring(bytes))
          else log("hero component Prius read unavailable", tostring(class), tostring(bytes)) end
        end
      else
        log("hero component candidate metadata unavailable", tostring(class), tostring(c))
      end
    end
  end
  log("hero component candidates:", relevant, "(read-only; no game writes)")
end

function O.component()
  local list = O.components()
  if list[1] then return list[1].addr, list[1].class, list[1].size end
  return nil, "the hero has no component " .. table.concat(O.CLASSES, " / ") .. " / " .. table.concat(O.CLASSES_LIVE, " / ")
end
-- v0.62-DEV6: round46 (tests/data/round46_rivet.log, DEV5 in the game): none of GameInventoryManager /
-- HeroWeaponManagerLocal / GameEquipManager holds the weapon records, and the hero's real inventories are components
-- the name list never reached: InventoryChangedEvent { Actor = hero, Component = 2129937 / 2129951 / 2129975 /
-- 2129997 } and GadgetItemAddedEvent { InventoryHandle = 2129937 } name them by HANDLE (the probe saw 47 of the
-- hero's 132 component names: rivet.log cut the line). So the hero's own component list is walked, the way
-- rivet_hook itself does it (src/game/actor.hpp, src/game/ddl.hpp, develop branch):
--   component instance +0x10 = its Actor*, +0x1C = its handle, +0x25 = flags (2 = destroyed);
--   Actor +0x68 = ComponentPointer* { ComponentInfo* type, Component* instance } (0x10 each), +0x70 = count (u16);
--   ComponentInfo +0x60 = char* name, +0x78 = int32 instance size.
-- It starts from a component rivet.component() answers (GameInventoryManager), reads only, and checks that the walk
-- finds that same component again. Its result: every component's class, handle, address and size.
O.WALK_ANCHORS = { "GameInventoryManager", "GameEquipManager", "HeroWeaponManagerLocal" }
O.COMP_HINT = { "Inventor", "Item", "Weapon", "Loadout", "Equip", "Ammo" }
O.COMP_SKIP = { "Vanity", "Anim", "StateMap", "Aim", "Damage", "Camera" }
O.inv_handles = O.inv_handles or {}   -- component handle -> why (an inventory event named it on the hero)
O.walked = nil                        -- the walk of this load: { [i] = { name, addr, size, handle } }
local function u16(b, i) return b[i] + b[i + 1] * 0x100 end
local function u32(b, i) return b[i] + b[i + 1] * 0x100 + b[i + 2] * 0x10000 + b[i + 3] * 0x1000000 end
local function cstr(b)
  local t = {}
  for i = 1, #b do
    if b[i] == 0 then break end
    if b[i] < 32 or b[i] > 126 then return nil end
    t[#t + 1] = string.char(b[i])
  end
  return #t > 0 and table.concat(t) or nil
end
function O.walk()
  if O.walked then return O.walked end
  local hero = rivet.hero and rivet.hero()
  if not hero then return nil, "no hero" end
  local anchor
  for _, cls in ipairs(O.WALK_ANCHORS) do
    local ok, c = pcall(rivet.component, hero, cls)
    if ok and type(c) == "table" and c.address then anchor = tonumber(tostring(c.address), 16); if anchor then break end end
  end
  if not anchor then return nil, "no anchor component" end
  local hexp = function(b, i) local h = O.hex64(b, i); return h and tonumber(h, 16) end
  local W = O.wstate
  if not (W and W.anchor == anchor) then
    local ab = read(anchor + 0x10, 8)
    local actor = #ab == 8 and hexp(ab, 1)
    if not O.valid_ptr(actor) then return nil, "the anchor's actor pointer is not readable" end
    local hb = read(actor + 0x68, 0x10)
    if #hb < 0x10 then return nil, "the actor's component list is not readable" end
    local list, count = hexp(hb, 1), u16(hb, 9)
    if not O.valid_ptr(list) or count < 1 or count > 1024 then return nil, string.format("component list %s, count %d", tostring(list), count) end
    local arr = read(list, count * 0x10)
    if #arr < count * 0x10 then return nil, "the actor's component list is not readable" end
    W = { anchor = anchor, actor = actor, count = count, arr = arr, k = 0, out = {}, seen_anchor = false }
    O.wstate = W
  end
  local actor, count, arr, out = W.actor, W.count, W.arr, W.out
  while W.k < count do
    local k = W.k
    local tp, inst = hexp(arr, k * 16 + 1), hexp(arr, k * 16 + 9)
    if O.valid_ptr(tp) and O.valid_ptr(inst) then
      local tb = read(tp + 0x60, 0x20)
      local np = #tb >= 0x1C and hexp(tb, 1)
      local name = nil
      if O.valid_ptr(np) then                        -- a short name at the end of readable memory: try shorter reads
        local nb = read(np, 0x50)
        if #nb == 0 then nb = read(np, 0x20) end
        if #nb == 0 then nb = read(np, 0x10) end
        name = cstr(nb)
      end
      local ib = read(inst + 0x18, 0x10)
      if name and #ib >= 0x0E then
        local destroyed = (ib[0x0E] or 0) & 2 ~= 0
        if not destroyed then
          out[#out + 1] = { name = name, addr = inst, size = s32(tb, 0x19), handle = u32(ib, 5) }
          if inst == anchor then W.seen_anchor = true end
        end
      end
    end
    W.k = k + 1                                       -- v0.62-DEV8: a killed job continues from here
    O.pause()
  end
  O.wstate = nil
  if not W.seen_anchor then return nil, "the walk did not find its own anchor again - layout differs; nothing used" end
  O.walked = out
  if not O.walk_logged then
    O.walk_logged = true
    log(string.format("hero component list walked: %d components (actor %X)", #out, actor))
    local line = {}
    for i, c in ipairs(out) do
      line[#line + 1] = c.name
      if #line == 12 or i == #out then log("hero components:", table.concat(line, ", ")); line = {} end
    end
  end
  return out
end

-- v0.62-DEV9: round49 (tests/data/round49_rivet.log, DEV8 in the game): the walk finished (141 components), but none
-- of the inventories the events name (InventoryChangedEvent { Actor = hero, Component = 2129937 / 2129951 / 2129975 /
-- 2129997 / 2129999 }) is in the hero's component list - their handles are below the hero's own (2130019 ...). So a
-- handle is resolved the way the game does it (rivet_hook src/game/scene_manager.hpp, ResolveComponent):
--   handle = { id : 20 bits, generation : 12 bits };
--   SceneManager +0x1398 SceneComponent* components { Component*, u32 generation, s32 lookupIndex } (0x10 each),
--   +0x13B8 componentMax, +0x13C8 ComponentLookup* { Component*, ComponentInfo* type } (0x10 each), +0x13EC count.
-- The SceneManager comes from rando_give.dll v7 through 16_rando_spawners.lua (RANDO_SPAWNERS.scene, the same one the
-- Enemy Randomizer reads its spawner variables through). Read only.
O.SCENE_COMPONENTS = 0x1398
function O.scene()
  local V = RANDO_SPAWNERS and RANDO_SPAWNERS.V
  if not (V and V.scene) then return nil, "16_rando_spawners.lua is not installed (it finds the SceneManager)" end
  local ok, sc, why = pcall(V.scene)
  if not ok then return nil, tostring(sc) end
  if type(sc) ~= "table" or not valid_ptr(sc.scene) then return nil, tostring(why or "no SceneManager") end
  return sc.scene
end
O.handle_cache = {}                     -- handle -> { addr, name, size, handle } of this load
function O.resolve(h)
  h = math.tointeger(tonumber(h))
  if not h or h <= 0 or h >= 0xFFFFFFFF then return nil, "not a handle" end
  if O.handle_cache[h] then return O.handle_cache[h] end
  local scene, why = O.scene()
  if not scene then return nil, why end
  local hb = read(scene + O.SCENE_COMPONENTS, 0x58)
  if #hb < 0x58 then return nil, "the SceneManager's component table is not readable" end
  local comps, max = tonumber(hex64(hb, 1), 16), s32(hb, 0x21)
  local lookups, lcount = tonumber(hex64(hb, 0x31), 16), s32(hb, 0x55)
  if not valid_ptr(comps) or max < 1 or max > 0x100000 then return nil, string.format("component table %s, max %d", tostring(comps), max) end
  local id, gen = h & 0xFFFFF, h >> 20
  if id >= max then return nil, string.format("handle %d: slot %d past the table (%d)", h, id, max) end
  local e = read(comps + id * 0x10, 0x10)
  if #e < 0x10 then return nil, "slot not readable" end
  local addr, egen, li = tonumber(hex64(e, 1), 16), u32(e, 9), s32(e, 13)
  if egen ~= gen then return nil, string.format("handle %d: slot generation %d, the handle's %d (gone)", h, egen, gen) end
  if not valid_ptr(addr) then return nil, string.format("handle %d: no component in its slot", h) end
  local ib = read(addr + 0x18, 0x08)
  if #ib < 8 or u32(ib, 5) ~= h then return nil, string.format("handle %d: the component at %X has handle %s", h, addr, tostring(#ib >= 8 and u32(ib, 5))) end
  local name, size = "?", 0
  if valid_ptr(lookups) and li >= 0 and li < lcount then
    local l = read(lookups + li * 0x10, 0x10)
    local lc, tp = #l == 0x10 and tonumber(hex64(l, 1), 16), #l == 0x10 and tonumber(hex64(l, 9), 16)
    if lc == addr and valid_ptr(tp) then
      local tb = read(tp + 0x60, 0x20)
      local np = #tb >= 0x1C and tonumber(hex64(tb, 1), 16)
      if valid_ptr(np) then
        local nb = read(np, 0x50)
        if #nb == 0 then nb = read(np, 0x20) end
        if #nb == 0 then nb = read(np, 0x10) end
        name = cstr(nb) or "?"
      end
      size = #tb >= 0x1C and s32(tb, 0x19) or 0
    end
  end
  local c = { addr = addr, name = name, size = size, handle = h }
  O.handle_cache[h] = c
  return c
end
-- v0.62-DEV9: an item the game named by handle (GadgetItemAddedEvent ItemHandle): its class and first bytes, and the
-- first bytes of its prius data (+0x08), once each for a few items - the layout of an item object, for the next round
O.ITEM_PROBES = 4
O.item_probe_queue, O.item_probed = {}, 0
function O.probe_item(h)
  local c, why = O.resolve(h)
  if not c then log("item", h, "not resolved:", why); return end
  local function hx(b) local t = {}; for i = 1, #b do t[#t + 1] = string.format("%02X", b[i]) end; return table.concat(t, " ") end
  local b = read(c.addr, 0x80)
  log(string.format("item handle %d: %s size=%d at %X; its first bytes:", h, c.name, c.size, c.addr), hx(b))
  local pp = #b >= 16 and tonumber(hex64(b, 9), 16)
  if valid_ptr(pp) then log(string.format("item handle %d: prius data at %X:", h, pp), hx(read(pp, 0x60))) end
end
-- ---- v0.62-DEV10: THE WEAPON ITEMS BY THE GAME'S OWN TYPE DATA ----------------------------------------
-- round50 (tests/data/round50_rivet.log, DEV9 in the game): the SceneManager handle lookup WORKS in the game (four stale
-- item handles were told apart by their slot generation, and inventory 2191609 resolved to "GameGeneralInventory",
-- 8480 bytes), but the search never got to read it: the walk had to finish first and every GadgetItemAddedEvent threw it
-- away, the Omega job runs last in the frame (after the Enemy Randomizer) and so rarely had its 3 ms, the level changed
-- while the first candidate was being read, and the four item probes were spent on handles of the previous load.
-- And even a found weapon record would only have waited for a Challenge Mode purchase to learn the Omega byte.
-- Both are replaced by what the game itself says about its types (rivet_hook src/game/ddl.hpp, src/ddl_visit.hpp,
-- src/scene_query.cpp; neptuwunium/rivet docs/ddl/rcra_ddl.json, the dump of the same live data):
--   * every live component is in SceneManager.componentLookups (+0x13C8) { Component*, ComponentInfo* } x
--     componentLookupCount (+0x13EC) - the index rivet.find_component walks;
--   * ComponentInfo +0xC8 = DDLTypeInfo* prius; DDLTypeInfo +0x08 type_id, +0x10 parent_id, +0x14 allocation_size,
--     +0x18 field_count (s16), +0x50 field_names (char**), +0x58 field_types (u8*), +0x78 field_offsets (u32*);
--   * Component +0x08 ddlPriusData -> holder { vtable, s32 count +0x08, data +0x10 } -> the prius instance;
--   * WeaponItemPrius (type 0xA89E9C3C, 192 bytes; MeleeWeaponItemPrius 0x2F1E071F extends it):
--     ItemConfigHash +48 (the weapon's item config id), Omega +184 (bool).
-- So the weapon items are the components whose class has a WeaponItemPrius, their ids are read at the live
-- ItemConfigHash offset, and the Omega byte is the live Omega offset - no learning, no Challenge Mode. The live field
-- table is read and must name both fields; the dump's numbers are only compared with it (and logged if they differ).
-- Writes need the live field table; without it the records are read and nothing is written. Read only otherwise.
O.T_WEAPON = { [0xA89E9C3C] = "WeaponItemPrius", [0x2F1E071F] = "MeleeWeaponItemPrius" }
O.T_ITEM = { [0xF4ADA6B7] = "ItemPrius", [0x4E5CE3CB] = "GameItemPrius", [0xA89E9C3C] = "WeaponItemPrius",
  [0x2F1E071F] = "MeleeWeaponItemPrius", [0x6AC1C47B] = "GridItemPrius", [0x98EC4F93] = "SkinItemPrius",
  [0xD05312D4] = "TradingCardItemPrius", [0xF6AD1389] = "VanityItemPrius", [0x38D2F620] = "PlayerXpItemPrius",
  [0x388B19BC] = "GadgetSwingshotItemPrius", [0x7B94FF83] = "BattleBrewItemPrius" }
O.DDL_DUMP = { size = 192, id = 48, omega = 184 }   -- rcra_ddl.json (compared with the live type, never trusted alone)
O.SCENE_LOOKUPS = 0x13C8
O.SCENE_LOOKUP_COUNT = 0x13EC
O.CI_NAME, O.CI_PRIUS = 0x60, 0xC8
O.READ_MAX = 0x200                                  -- rivet_hook's MAX_READ_BYTES (src/scripting.cpp)
O.FT_BOOL, O.FT_ASSET = 15, 20                      -- DDL field types of Omega and ItemConfigHash (rcra_ddl.json)
O.class_cache = O.class_cache or {}                 -- ComponentInfo* -> class verdict (the registry never moves)
O.ddl_layout = O.ddl_layout or nil                  -- { id, omega, size, live, why } of WeaponItemPrius
O.dstate = nil                                      -- the census of this search (continues after a budget kill)
O.stats = { frames = 0, ran = 0, skipped = 0, starved = 0 }

local read_name_rest
local function ptr_at(b, i) local h = hex64(b, i); return h and tonumber(h, 16) end
-- a short string: a name at the end of readable memory is read in shorter pieces
local function read_name(p)
  if not valid_ptr(p) then return nil end
  local out = {}
  for _, len in ipairs({ 0x40, 0x20, 0x10, 0x08 }) do
    local nb = read(p, len)
    if #nb == len then
      for i = 1, len do
        if nb[i] == 0 then return cstr(out) end
        out[#out + 1] = nb[i]
      end
      p = p + len
      if #out >= 0x80 then return nil end
      return read_name_rest(p, out)
    end
  end
  return read_name_rest(p, out)
end
-- the rest of a name, a byte at a time (the end of readable memory; or a name longer than one read)
read_name_rest = function(p, out)
  for i = 0, 0x7F - #out do
    local b = read(p + i, 1)
    if #b < 1 then return nil end
    if b[1] == 0 then return cstr(out) end
    out[#out + 1] = b[1]
  end
  return nil
end
-- a read that the frame budget cut short is tried again in the next slice (3 times), not taken as unreadable
local function read_full(addr, len, chunk)
  for _ = 1, 3 do
    local b = read(addr, len, chunk)
    if #b >= len then return b end
    if coroutine.isyieldable() then coroutine.yield(); slice_t0 = clock() end
  end
  return read(addr, len, chunk)
end
O.read_full = read_full

-- the live field table of a prius type: { [name] = { off, type } } (nil and why if not readable)
function O.ddl_fields(tp, count)
  if not (valid_ptr(tp) and count and count > 0 and count < 256) then return nil, "no field table" end
  local hb = read_full(tp + 0x50, 0x30)
  local names, types, offs = ptr_at(hb, 1), ptr_at(hb, 9), ptr_at(hb, 0x29)
  if not (valid_ptr(names) and valid_ptr(offs)) then return nil, "field names / offsets not readable" end
  local nb, ob = read_full(names, count * 8), read_full(offs, count * 4)
  local tb = valid_ptr(types) and read_full(types, count) or {}
  if #nb < count * 8 or #ob < count * 4 then return nil, "field arrays not readable" end
  local out = {}
  for i = 0, count - 1 do
    local nm = read_name(ptr_at(nb, i * 8 + 1))
    if nm then out[nm] = { off = u32(ob, i * 4 + 1), type = tb[i + 1] } end
  end
  return out
end
-- WeaponItemPrius's layout from the live type (once per session)
O.layout_tries = 0
function O.weapon_layout(tp, tid, size, count)
  if O.ddl_layout and (O.ddl_layout.live or O.layout_tries >= 3) then return O.ddl_layout end
  O.layout_tries = O.layout_tries + 1
  local f, why = O.ddl_fields(tp, count)
  local id, om = f and f.ItemConfigHash, f and f.Omega
  local L
  if id and om and om.off > id.off and om.off < size and (om.type == nil or om.type == O.FT_BOOL) then
    L = { id = id.off, omega = om.off, size = size, live = true, tid = tid,
          why = string.format("%s from the game's type data: ItemConfigHash +0x%X, Omega +0x%X (bool), %d bytes",
                              O.T_WEAPON[tid] or "?", id.off, om.off, size) }
    if id.off ~= O.DDL_DUMP.id or om.off ~= O.DDL_DUMP.omega or size ~= O.DDL_DUMP.size then
      L.why = L.why .. string.format(" - NOT the numbers of rivet's DDL dump (+0x%X, +0x%X, %d): the game's own are used",
                                     O.DDL_DUMP.id, O.DDL_DUMP.omega, O.DDL_DUMP.size)
    end
  else
    -- read only: the dump's numbers find the records, but nothing is written without the live table
    L = { id = O.DDL_DUMP.id, omega = O.DDL_DUMP.omega, size = O.DDL_DUMP.size, live = false, tid = tid,
          why = "the live field table did not name ItemConfigHash and Omega (" .. tostring(why or (f and "fields: " ..
                table.concat(GEN.sorted_keys(f), " ") or "?")) .. ") - rivet's DDL dump is used to READ only, nothing is written" }
  end
  O.ddl_layout = L
  log("WeaponItemPrius layout: " .. L.why)
  return L
end
-- what a component class is: false, or { item = type name, weapon = layout or nil, name = class name }
function O.ddl_class(info)
  local v = O.class_cache[info]
  if v ~= nil then return v end
  v = false
  local pb = read_full(info + O.CI_PRIUS, 8)
  if #pb < 8 then return false end                  -- not readable now (the budget): asked again, not cached
  local tp = ptr_at(pb, 1)
  if valid_ptr(tp) then
    local hb = read_full(tp + 0x08, 0x14)
    if #hb < 0x14 then return false end
    do
      local tid, parent, size, count = u32(hb, 1), u32(hb, 9), u32(hb, 0x0D), u16(hb, 0x11)
      if O.T_ITEM[tid] or O.T_ITEM[parent] then
        v = { item = O.T_ITEM[tid] or ("a child of " .. O.T_ITEM[parent]), tid = tid }
        local np = read_full(info + O.CI_NAME, 0x20)
        if #np < 0x1C then return false end
        v.name = read_name(ptr_at(np, 1))
        if not v.name then return false end            -- not readable now: asked again, never cached as "not a weapon"
        v.inst_size = s32(np, 0x19)                    -- ComponentInfo +0x78: the instance's size
        -- v0.62-DEV11: round51's weapons are class GameWeaponItem with a plain ItemPrius: the name decides too
        local by_type = O.T_WEAPON[tid] or O.T_WEAPON[parent]
        if by_type or v.name:find("WeaponItem", 1, true) then
          v.weapon, v.tp, v.size, v.count = true, tp, size, count
          if by_type then O.weapon_layout(tp, tid, size, count) end
        end
      end
    end
  end
  O.class_cache[info] = v
  return v
end
-- the hero's Actor* (the owner of its components), for telling the hero's weapons from any other copy
function O.hero_actor()
  local hero = rivet.hero and rivet.hero()
  if not hero then return nil end
  for _, cls in ipairs(O.WALK_ANCHORS) do
    local ok, c = pcall(rivet.component, hero, cls)
    local a = ok and type(c) == "table" and c.address and tonumber(tostring(c.address), 16)
    if a then
      local b = read_full(a + 0x10, 8)
      local p = #b == 8 and ptr_at(b, 1)
      if valid_ptr(p) then return p end
    end
  end
  return nil
end
-- v0.62-DEV11: round51 (DEV10 in the game): the census WORKED (52,872 components, 1145 frames) and found the weapons -
-- "GameWeaponItem (ItemPrius) x33, GameMeleeWeaponItem (ItemPrius) x4" - but their class's prius is plain ItemPrius, not
-- WeaponItemPrius, so DEV10 skipped them. And the item probes show an item keeps no prius holder (Component +0x08 = 0):
-- its fields live in the instance itself (GameGeneralItem 1104 bytes). So a weapon item is now a component whose class
-- name has "WeaponItem" (or whose prius is WeaponItemPrius); its whole instance (and a prius holder, if it has one) is
-- searched for the weapon's id; the offset most weapon items agree on is the id's place.
-- The Omega byte: WeaponItemPrius's own order (rcra_ddl.json) from the id on - ItemCount +8 (= 1), ItemId +12, XP +16,
-- LastCheckpointAmmo +20 / LoadedAmmo +24 (floats), Mods +40, ModGrid +48, ModCount +80, SelectedCell +112, Test +120
-- { pointer, count, capacity }, Omega +136. Those fields are CHECKED in every weapon record (ItemCount 1, sane ammo
-- floats, a sane Test list, Omega 0 or 1); only if (nearly) all pass is the layout trusted and anything written.
-- Each weapon's decoded fields are logged (ammo, XP, Omega) so the numbers can be compared with the game.
O.INST_MAX = 0x800
O.REL = { count = 8, itemid = 12, xp = 16, ammo_cp = 20, ammo = 24, cell = 112, test = 120, omega = 136 }
O.ANY_ID = {}
for key, it in pairs(DB.items) do
  if key:sub(1, 7) == "weapon:" and type(it.id) == "string" then O.ANY_ID[it.id:upper()] = key:sub(8) end
end
local function f32(b, i)
  local v = u32(b, i)
  local ok, f = pcall(function() return (string.unpack("<f", string.pack("<I4", v))) end)
  return ok and f or nil
end
-- v0.71-DEV2: an EMPTY SLOT is a weapon record the hero does not hold. The game numbers the weapons the hero owns
-- (+12: 1001, 1002 ... - the WeaponType of the WeaponAddedEvent) and leaves every other record at 5000 + n with no XP and no
-- ammo. round54 (v0.71-DEV1): Pixelizer, given in Zurkon, read slot 1005 / XP 317740 / ammo 16 (and its event said 1005);
-- Negatron Collider, given in the Nefarious City intro, read slot 5015 / XP 0 / ammo 0 for the whole session, although the
-- game had answered "added" (event 1002). Its Omega flag was written on that empty record: "applied", but not in the game.
-- Every other check (ItemCount 1, ammo floats, Test list) passes for an empty slot too, so this one is separate.
O.EMPTY_SLOT_FROM = 5000
function O.slot_of(b) return (b and #b >= O.REL.itemid + 4) and u32(b, O.REL.itemid + 1) or nil end
function O.empty_slot(b)
  if not b or #b < O.REL.ammo + 4 then return false end
  local slot = u32(b, O.REL.itemid + 1)
  if slot < O.EMPTY_SLOT_FROM or u32(b, O.REL.xp + 1) ~= 0 then return false end
  local a = f32(b, O.REL.ammo + 1)
  return a == nil or a == 0
end
O.empty_since, O.regives = {}, {}
O.REGIVE_AFTER = 900               -- frames a confirmed weapon may stay an empty slot before it is sent again
O.MAX_REGIVE = 2                   -- sends per weapon and load
-- a weapon the game answered "added" for, whose record is still an empty slot: log it once, then send it again
function O.note_empty(w, name, b)
  local now = O.frame
  if not O.empty_since[w] then
    O.empty_since[w] = now
    local hx = {}
    for i = 1, math.min(#b, 40) do hx[#hx + 1] = string.format("%02X", b[i]) end
    log(string.format("%s waits: the record of %s is an empty slot (slot %s, XP %s, ammo %s) - the game does not hold the weapon (yet)",
        name, w, tostring(O.slot_of(b)), tostring(u32(b, O.REL.xp + 1)), tostring(f32(b, O.REL.ammo + 1))))
    log("EVIDENCE empty slot " .. w .. " from its id:", table.concat(hx, " "))
    return
  end
  if now - O.empty_since[w] >= O.REGIVE_AFTER and (O.regives[w] or 0) < O.MAX_REGIVE and RANDO_REAL and RANDO_REAL.regive then
    O.regives[w] = (O.regives[w] or 0) + 1
    O.empty_since[w] = now
    local ok = RANDO_REAL.regive("weapon:" .. w, "its record is still an empty slot; " .. name .. " needs the weapon")
    log(string.format("%s: the weapon is still not in your inventory - sending %s again (try %d of %d)%s", name, w, O.regives[w], O.MAX_REGIVE, ok and "" or " (not possible now)"))
    if ok then say("Randomizer: " .. name .. " - your weapon is missing, sending it again") end
  end
end

-- one weapon item component: every place in it (and in its prius data) that holds a weapon id
local function ddl_item(D, comp, cls)
  local size = math.max(0x48, math.min(cls.inst_size and cls.inst_size > 0 and cls.inst_size or 0x400, O.INST_MAX))
  local ib = read_full(comp, size, O.READ_MAX)
  if #ib < 0x48 then D.no_prius = D.no_prius + 1; return end
  if (ib[0x26] & 2) ~= 0 then return end                            -- destroyed (+0x25)
  D.weapon_items = D.weapon_items + 1
  local item = { comp = comp, actor = ptr_at(ib, 0x11), handle = u32(ib, 0x1D), class = cls.name, hits = {} }
  local function scan(b, base, where, from)
    local steps = 0
    for i = from, #b - 7, 8 do
      steps = steps + 1
      if steps % 32 == 0 then O.pause() end   -- v0.62-DEV13: round53 was killed by the frame budget in this loop
      local id = hex64(b, i)
      local w = id and O.ANY_ID[id]
      if w then
        local key = where .. "+" .. (i - 1)
        item.hits[key] = { w = w, at = base + i - 1 }
        D.votes[key] = (D.votes[key] or 0) + 1
      end
    end
  end
  scan(ib, comp, "instance", 0x49)                                    -- (after the Component header)
  local holder = ptr_at(ib, 9)
  if valid_ptr(holder) then
    local hb = read_full(holder + 0x10, 8)
    local data = #hb == 8 and ptr_at(hb, 1)
    if valid_ptr(data) then scan(read_full(data, 0xC0), data, "prius", 1) end
  end
  D.items[#D.items + 1] = item
end
-- WeaponItemPrius's fields from the id on, checked: true if they look like a weapon record
function O.check_record(b)
  if #b < O.REL.omega + 1 then return false, "short" end
  local cnt, xp = u32(b, O.REL.count + 1), u32(b, O.REL.xp + 1)
  local a1, a2 = f32(b, O.REL.ammo_cp + 1), f32(b, O.REL.ammo + 1)
  local tp, tn = ptr_at(b, O.REL.test + 1), s32(b, O.REL.test + 9)
  local cell, om = b[O.REL.cell + 1], b[O.REL.omega + 1]
  local why = {}
  if cnt ~= 1 then why[#why + 1] = "ItemCount " .. cnt end
  for _, a in ipairs({ a1, a2 }) do if not a or a ~= a or a < 0 or a > 100000 then why[#why + 1] = "ammo " .. tostring(a) end end
  if not (tp == 0 or valid_ptr(tp)) or tn < 0 or tn > 256 then why[#why + 1] = "Test list" end
  -- v0.62-DEV13: SelectedCell is logged only. round53 (a Challenge Mode save with upgraded weapons) read 118-216 on
  -- 16-20 of 25 records whose ItemCount, XP and ammo all matched the HUD, so "< 64" rejected the real records and
  -- nothing was ever written ("NOT trusted"). round52's Pixelizer 117 was the same thing.
  if om ~= 0 and om ~= 1 then why[#why + 1] = "Omega byte " .. om end
  local info = string.format("XP %d, ammo %s/%s, cell %d, Omega %d", xp, a1 and string.format("%.0f", a1) or "?",
                             a2 and string.format("%.0f", a2) or "?", cell, om)
  return #why == 0, (#why == 0) and info or (info .. " - FAILS: " .. table.concat(why, ", "))
end
O.progress = nil                                    -- { i, count, t0 } while a census runs (dev(debug).lua shows it)
-- every weapon record of this load through the component index (a job; keeps its place in O.dstate)
function O.ddl_find()
  local scene, why = O.scene()
  if not scene then return nil, why end
  local D = O.dstate
  if not (D and D.scene == scene) then
    local hb = read_full(scene + O.SCENE_LOOKUPS, 0x28)
    local lookups, count = #hb >= 0x28 and ptr_at(hb, 1), #hb >= 0x28 and s32(hb, 0x25)
    if not valid_ptr(lookups) or not count or count < 1 or count > 0x200000 then
      return nil, string.format("the component index is not readable (%s, %s)", tostring(lookups), tostring(count))
    end
    D = { scene = scene, lookups = lookups, count = count, i = 0, t0 = O.frame, short = 0, weapon_items = 0, no_prius = 0,
          items = {}, votes = {}, classes = {}, class_n = {} }
    O.dstate = D
    log(string.format("weapon items: reading the scene's component index (%d components)", count))
  end
  local per = O.READ_MAX // 0x10
  while D.i < D.count do
    O.progress = { i = D.i, count = D.count, t0 = D.t0 }
    local n = math.min(per, D.count - D.i)
    local b = read(D.lookups + D.i * 0x10, n * 0x10, O.READ_MAX)
    if #b < n * 0x10 then
      D.short = D.short + 1
      if D.short > 3 then
        O.dstate, O.progress = nil, nil
        return nil, string.format("the component index stopped being readable at %d of %d", D.i, D.count)
      end
      if coroutine.isyieldable() then coroutine.yield(); slice_t0 = clock() end
    else
      D.short = 0
      for k = 0, n - 1 do
        local comp, info = ptr_at(b, k * 16 + 1), ptr_at(b, k * 16 + 9)
        if valid_ptr(comp) and valid_ptr(info) then
          local cls = O.ddl_class(info)
          if cls then
            D.classes[info] = cls
            D.class_n[info] = (D.class_n[info] or 0) + 1
            if cls.weapon then ddl_item(D, comp, cls) end
          end
        end
      end
      D.i = D.i + n
      O.pause()
    end
  end
  O.dstate, O.progress = nil, nil
  local parts = {}
  for info, cls in pairs(D.classes) do parts[#parts + 1] = string.format("%s (%s%s) x%d", cls.name, cls.item, cls.weapon and ", weapon" or "", D.class_n[info] or 0) end
  table.sort(parts)
  log(string.format("weapon items: index read in %d frames; item classes: %s", O.frame - D.t0, #parts > 0 and table.concat(parts, ", ") or "none"))
  if D.weapon_items == 0 then return nil, "no live weapon item component (class GameWeaponItem / WeaponItemPrius) in the scene" end
  -- the id's place: the one most weapon items agree on
  local best, bn = nil, 0
  for key, n in pairs(D.votes) do if n > bn or (n == bn and best and key < best) then best, bn = key, n end end
  if not best then
    local it = D.items[1]
    local b = read_full(it.comp, 0x200, O.READ_MAX)
    local hx = {}
    for i = 1, #b do hx[#hx + 1] = string.format("%02X", b[i]) end
    log(string.format("weapon items: %d, none holds a known weapon id; the first (%s, handle %d) at %X:", D.weapon_items, it.class, it.handle, it.comp), table.concat(hx, " "))
    return nil, "no weapon item holds a known weapon id"
  end
  -- the hero's actor and the actors of the inventories the game named on the hero: the hero's own weapons
  local mine = {}
  local ha = O.hero_actor()
  if ha then mine[ha] = "hero" end
  for h in pairs(O.inv_handles) do
    local c = O.resolve(h)
    if c then
      local ab = read_full(c.addr + 0x10, 8)
      local a = #ab == 8 and ptr_at(ab, 1)
      if valid_ptr(a) then mine[a] = mine[a] or ("inventory " .. c.name) end
    end
  end
  -- the records of one id place, by owner; the owner chosen; how many of its records pass the field check
  local function evaluate(place)
    local groups = {}
    for _, it in ipairs(D.items) do
      local h = it.hits[place]
      if h then
        local key = it.actor or 0
        groups[key] = groups[key] or { n = 0, recs = {}, dup = 0 }
        local g = groups[key]
        if g.recs[h.w] then g.dup = g.dup + 1 else g.recs[h.w] = { id_at = h.at, comp = it.comp, handle = it.handle, class = it.class }; g.n = g.n + 1 end
      end
    end
    -- v0.62-DEV13: round53's hero had TWO full sets: GameEquipInventory (the weapons you own) and
    -- GameOverrideInventory (copies; ItemCount 0 outside some arena challenges). DEV12 took the larger set, so a
    -- census that picked the override copies failed every record. Now each of the hero's sets is checked; the
    -- override copies are never written; GameEquipInventory wins a tie.
    local function rank(key)
      local m = mine[key]
      if not m or m:find("Override", 1, true) then return nil end
      if m:find("GameEquipInventory", 1, true) then return 3 end
      return m == "hero" and 2 or 1
    end
    local function check_group(g)
      local pass, total, lines = 0, 0, {}
      for _, w in ipairs(GEN.sorted_keys(g and g.recs or {})) do
        local ok, info = O.check_record(read_full(g.recs[w].id_at, O.REL.omega + 8))
        total = total + 1
        if ok then pass = pass + 1 end
        lines[#lines + 1] = w .. ": " .. info
      end
      return pass, total, lines
    end
    local pick, pkey, pass, total, lines, prank = nil, nil, 0, 0, {}, -1
    for key, g in pairs(groups) do
      local r = rank(key)
      if r then
        local p, t, l = check_group(g)
        if not pick or p > pass or (p == pass and (r > prank or (r == prank and g.n > pick.n))) then
          pick, pkey, pass, total, lines, prank = g, key, p, t, l, r
        end
      end
    end
    local owner_ok = pick ~= nil
    if not pick then
      local largest, lkey, big = nil, nil, 0
      for key, g in pairs(groups) do
        if not (mine[key] and mine[key]:find("Override", 1, true)) then
          if not largest or g.n > largest.n then largest, lkey = g, key end
          if g.n >= 8 then big = big + 1 end
        end
      end
      pick, pkey = largest, lkey
      owner_ok = (largest ~= nil and largest.n >= 8 and big == 1)
      pass, total, lines = check_group(pick)
    end
    return { place = place, groups = groups, pick = pick, pkey = pkey, owner_ok = owner_ok, pass = pass, total = total, lines = lines,
             verified = total >= 3 and pass >= math.max(3, math.ceil(total * 0.9)) }
  end
  local places = {}
  for key, n in pairs(D.votes) do places[#places + 1] = { key = key, n = n } end
  table.sort(places, function(x, y) return x.n > y.n or (x.n == y.n and x.key < y.key) end)
  local E
  for i = 1, math.min(4, #places) do
    local e = evaluate(places[i].key)
    if e.verified then E = e; break end
    E = E or e
  end
  local pick, pkey, writable_owner = E.pick, E.pkey, E.owner_ok
  best, bn = E.place, D.votes[E.place]
  local other_votes = {}
  for _, pl in ipairs(places) do if pl.key ~= best then other_votes[#other_votes + 1] = pl.key .. " x" .. pl.n end end
  local owners = {}
  for key, g in pairs(E.groups) do owners[#owners + 1] = string.format("%X%s: %d", key, mine[key] and (" (" .. mine[key] .. ")") or "", g.n) end
  table.sort(owners)
  log(string.format("weapon items: %d; the weapon id is at %s (%d of them agree%s); known weapons by owner [%s]",
      D.weapon_items, best, bn, #other_votes > 0 and ("; other places: " .. table.concat(other_votes, ", ")) or "", table.concat(owners, ", ")))
  -- the layout check, record by record, with each weapon's fields in the log
  local L = O.ddl_layout
  local rel = (L and L.live) and (L.omega - L.id) or O.REL.omega
  local pass, total, lines, verified = E.pass, E.total, E.lines, E.verified
  for i = 1, #lines, 4 do log("weapon record " .. table.concat(lines, " | ", i, math.min(i + 3, #lines))) end
  if not (L and L.live) then
    O.ddl_layout = { id = O.DDL_DUMP.id, omega = O.DDL_DUMP.id + rel, size = O.DDL_DUMP.size, live = false, verified = verified,
                     why = string.format("WeaponItemPrius order from the id on, checked in %d of %d records", pass, total) }
    L = O.ddl_layout
  else
    L.verified = verified
  end
  log(string.format("weapon records: %d of %d match WeaponItemPrius's fields (ItemCount 1, ammo, Test list, Omega 0/1) - %s",
      pass, total, verified and string.format("layout TRUSTED: the Omega flag is +0x%X from the id", rel)
                   or "NOT trusted: nothing is written (send rivet.log)"))
  if verified and not writable_owner then log("weapon records: their owner is neither the hero nor one of its inventories and not clearly the only full set - read only") end
  -- the first record's surroundings, once per session, for the next round
  if not O.records_bytes_logged then
    O.records_bytes_logged = true
    local w = GEN.sorted_keys(pick.recs)[1]
    local r = pick.recs[w]
    local b = read_full(r.id_at - 0x40, 0x100)
    local hx = {}
    for i = 1, #b do hx[#hx + 1] = string.format("%02X", b[i]) end
    log(string.format("weapon record %s (%s handle %d at %X), from id-0x40:", w, r.class, r.handle, r.comp), table.concat(hx, " "))
  end
  local recs, n = {}, 0
  for w, r in pairs(pick.recs) do if O.ID_OF[w] then recs[w] = r; n = n + 1 end end
  if n == 0 then return nil, "the weapon records hold no weapon that has an Omega version" end
  return { route = "type data", comp = nil, class = string.format("%s components (owner %X)", pick.recs[next(pick.recs)].class, pkey),
           array_at = 0, records = recs, count = n, span = rel + 1, layout = L, hero_owned = writable_owner and verified }
end

-- v0.62-DEV5: every inventory candidate of the live hero, in order: { addr, class, size }
-- v0.62-DEV6: first the components an inventory event named (by handle), then every walked component whose class
-- name looks like an inventory, then the DEV5 names
function O.components()
  local out = {}
  local hero = rivet.hero and rivet.hero()
  if not hero then return out end
  local have = {}
  local function take(c, tag)
    if have[c.addr] then return end
    have[c.addr] = true
    local size = math.max(O.HEADER, math.min(c.size or 0, O.MAX_HEADER))
    out[#out + 1] = { addr = c.addr, class = c.name .. "#" .. c.handle, size = size }
    if not (O.cand_logged or {})[c.addr] then
      O.cand_logged = O.cand_logged or {}
      O.cand_logged[c.addr] = true
      log(string.format("inventory candidate %s handle=%d size=%d at %X (%s)", c.name, c.handle, c.size or -1, c.addr, tag))
    end
  end
  -- v0.62-DEV9: the inventories the events named, resolved through the SceneManager (they are not in the list)
  -- v0.62-DEV10: without waiting for the walk (round50: the walk came last and every gadget restarted it)
  for _, h in ipairs(GEN.sorted_keys(O.inv_handles)) do
    local c, why = O.resolve(h)
    if c then take(c, O.inv_handles[h] .. ", by handle")
    else
      O.unresolved = O.unresolved or {}
      if O.unresolved[h] ~= why then O.unresolved[h] = why; log("inventory handle", h, "(" .. O.inv_handles[h] .. ") not resolved:", why) end
    end
  end
  if #out == 0 then
    local walked, why = O.walk()
    if walked then
      for _, c in ipairs(walked) do if O.inv_handles[c.handle] then take(c, O.inv_handles[c.handle]) end end
      for _, c in ipairs(walked) do
        local hit, skip = false, false
        for _, h in ipairs(O.COMP_HINT) do if c.name:find(h, 1, true) then hit = true end end
        for _, k in ipairs(O.COMP_SKIP) do if c.name:find(k, 1, true) then skip = true end end
        if hit and not skip then take(c, "its class name") end
      end
    elseif why and why ~= O.walk_why then
      O.walk_why = why
      log("hero component list not walked:", why)
    end
  end
  local function add(cls, header)
    local ok, c = pcall(rivet.component, hero, cls)
    if ok and type(c) == "table" and c.address then
      local a = tonumber(tostring(c.address), 16)
      local size = math.tointeger(tonumber(c.size or 0)) or 0
      if a then out[#out + 1] = { addr = a, class = cls, size = header or math.max(O.HEADER, math.min(size, O.MAX_HEADER)) } end
    end
  end
  if #out == 0 then
    for _, cls in ipairs(O.CLASSES) do add(cls, O.HEADER) end
    for _, cls in ipairs(O.CLASSES_LIVE) do add(cls) end
  end
  if #out == 0 then O.component_diagnostic(hero) end
  return out
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
      local found = false
      for i = 1, #b - 7, 8 do
        local w = O.BY_ID[hex64(b, i) or ""]
        if w then hits[#hits + 1] = { w = w, at = p + i - 1, off = i - 1 }; votes[i - 1] = (votes[i - 1] or 0) + 1; found = true end
      end
      -- v0.62-DEV6: an item object whose id is in the prius data it points to (+0x08, like every component)
      local q = (not found) and #b >= 16 and tonumber(hex64(b, 9) or "0", 16) or nil
      if q and valid_ptr(q) then
        local b2 = read(q, 0x40)
        for i = 1, #b2 - 7, 8 do
          local w = O.BY_ID[hex64(b2, i) or ""]
          if w then hits[#hits + 1] = { w = w, at = q + i - 1, off = 0x10000 + i - 1 }; votes[0x10000 + i - 1] = (votes[0x10000 + i - 1] or 0) + 1 end
        end
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
-- v0.62-DEV9: an array of u32 item handles: each one resolved through the SceneManager, the weapon id looked for in the
-- item object and in its prius data (+0x08); the id's offset is the one most items agree on
function O.records_handles(ptr, count)
  if not O.scene() then return nil end
  local raw = read(ptr, count * 4)
  if #raw < count * 4 then return nil end
  local hits, votes = {}, {}
  for e = 0, count - 1 do
    local h = u32(raw, e * 4 + 1)
    local c = (h ~= 0 and h ~= 0xFFFFFFFF) and O.resolve(h) or nil
    if c then
      local b = read(c.addr, O.OBJ)
      for i = 1, #b - 7, 8 do
        local w = O.BY_ID[hex64(b, i) or ""]
        if w then hits[#hits + 1] = { w = w, at = c.addr + i - 1, off = i - 1 }; votes[i - 1] = (votes[i - 1] or 0) + 1 end
      end
      local q = #b >= 16 and tonumber(hex64(b, 9) or "0", 16) or nil
      if q and valid_ptr(q) then
        local b2 = read(q, 0x80)
        for i = 1, #b2 - 7, 8 do
          local w = O.BY_ID[hex64(b2, i) or ""]
          if w then hits[#hits + 1] = { w = w, at = q + i - 1, off = 0x10000 + i - 1 }; votes[0x10000 + i - 1] = (votes[0x10000 + i - 1] or 0) + 1 end
        end
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
function O.find_records()
  local list = O.components()
  if #list == 0 then
    return nil, "the hero has no component " .. table.concat(O.CLASSES, " / ") .. " / " .. table.concat(O.CLASSES_LIVE, " / ")
  end
  local best, why = nil, nil
  for _, c in ipairs(list) do
    local r, w = O.find_records_in(c.addr, c.class, c.size)
    if r and (not best or r.count > best.count) then best = r end
    if not r then why = (why and (why .. "; ") or "") .. tostring(w) end
  end
  if best then return best end
  return nil, why
end
function O.find_records_in(comp, cls, header)
  header = header or O.HEADER
  local head = read(comp, header)
  if #head < 0x40 then return nil, "inventory component not readable (" .. cls .. ")" end
  local best, bn = nil, 0
  for o = 1, #head - 15, 8 do
    if o % 64 == 1 then O.pause() end                -- v0.62-DEV6: round46 overran the budget here 60+ times
    local ptr = tonumber(hex64(head, o) or "0", 16)
    local count, cap = s32(head, o + 8), s32(head, o + 12)
    if valid_ptr(ptr) and count >= 1 and count <= O.MAX_COUNT and cap >= count and cap <= 8192 then
      local recs, n = records_pointers(ptr, count)
      if not recs then recs, n = records_inline(ptr, count) end
      if not recs then recs, n = O.records_handles(ptr, count) end   -- v0.62-DEV9
      if recs and n > bn then best, bn = { comp = comp, class = cls, array_at = o - 1, records = recs, count = n }, n end
    end
  end
  if not best then
    O.dumped = O.dumped or {}
    if not O.dumped[cls] then
      O.dumped[cls] = true
      local hx = {}
      for i = 1, math.min(#head, 0x100) do hx[#hx + 1] = string.format("%02X", head[i]) end
      log(string.format("no weapon record in the first 0x%X bytes of %s at %X; its first bytes:", header, cls, comp), table.concat(hx, " "))
    end
    return nil, "no array of weapon records in " .. cls
  end
  return best
end

-- v0.62-DEV5: once per session, every weapon record's first O.SPAN bytes (from its id on) - the evidence a developer
-- needs to find the Omega byte from a save that already owns an Omega (compare its record with the others)
function O.dump_records(inv)
  if O.records_dumped then return end
  O.records_dumped = true
  for _, w in ipairs(GEN.sorted_keys(inv.records)) do
    local b = read(inv.records[w].id_at, inv.span or O.SPAN)
    local hx = {}
    for i = 1, #b do hx[#hx + 1] = string.format("%02X", b[i]) end
    log("record", w, table.concat(hx, " "))
  end
end

-- ---- 3: the Omega byte ------------------------------------------------------------------------
function O.offset()
  local manual = cfg("omega_flag_offset")
  if type(manual) == "number" and manual >= 8 and manual < O.SPAN and math.type(manual) == "integer" then return manual, "omega_flag_offset" end
  -- v0.62-DEV10: the game's own type data (WeaponItemPrius.Omega - ItemConfigHash), read live; no purchase needed
  local L = O.ddl_layout
  if L and L.live and L.verified ~= false then return L.omega - L.id, "the game's type data" end
  if L and L.verified then return L.omega - L.id, "WeaponItemPrius's fields, checked in every weapon record" end
  local s = S()
  local c = s and s.omega_cal
  if type(c) == "table" and type(c.off) == "number" then return c.off, "learned from " .. tostring(c.from) end
  return nil
end
-- the bytes of every record, from its id on (a job)
local function snapshot(inv)
  local snap = {}
  for _, w in ipairs(GEN.sorted_keys(inv.records)) do snap[w] = read_full(inv.records[w].id_at, inv.span or O.SPAN) end
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
function O.on_purchase(weapon_name, known_w)
  local item = (not known_w) and RANDO_REAL and RANDO_REAL.weapon_item and RANDO_REAL.weapon_item(weapon_name)
  local w = known_w or (item and item:sub(8))
  local snap = O.snap
  if not (w and snap and snap.bytes[w]) then return end
  O.start_job("learn", function()
    local before = snap.bytes[w]
    local after = read(snap.inv.records[w].id_at, snap.inv.span or O.SPAN)
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
    O.next_resnap = O.frame + O.OMEGA_WAIT
  end)
end
-- v0.62-DEV6: round46 (DEV5 in the game): an Omega purchase at Ms. Zurkon sends ONLY VendorPurchaseEvent
-- { WeaponName = "MagShield" } (and "Warmonger") - no PurchaseWeaponEvent, no WeaponAddedEvent - and
-- EnteredVendorEvent never came in 20 purchases. So: the records are read (O.snap) as soon as they are found and
-- again after every check and purchase, and a VendorPurchaseEvent for a weapon that is already in that read and
-- brings no PurchaseWeaponEvent within O.OMEGA_WAIT frames is an Omega purchase.
O.OMEGA_WAIT = 20
O.VENDOR_ALIAS = { GOONER = "sheepinator", MRZURKON = "zurkon" }  -- round46 pairs VendorPurchase -> PurchaseWeapon
O.vendor_pending = {}
local function norm(t) return (tostring(t or "")):upper():gsub("[^%w]", "") end
O.BY_VENDOR = {}
for w in pairs(O.ID_OF) do
  local it = DB.items["weapon:" .. w]
  local base = it and it.config and it.config:match("wpn_(.-)_item%.config")
  if base then O.BY_VENDOR[norm(base)] = w end
  O.BY_VENDOR[norm(w)] = O.BY_VENDOR[norm(w)] or w
end
function O.weapon_of_vendor_name(name)
  local n = norm(name)
  local alias = O.VENDOR_ALIAS[n]
  if alias and O.ID_OF[alias] then return alias end
  return O.BY_VENDOR[n]
end
function O.on_vendor_purchase(name)
  local w = O.weapon_of_vendor_name(name)
  if not w then return end
  O.vendor_pending[w] = { at = O.frame, name = name }
  -- v0.75: a snapshot still queued or running (behind DEV8's "xp" or DEV9's "held" job) would read the records AFTER
  -- this purchase and replace the read from before it: the purchase would then compare with itself. It is dropped.
  for i = #O.jobs, 1, -1 do if O.jobs[i].kind == "snapshot" then table.remove(O.jobs, i) end end
end
function O.on_weapon_purchase(weapon_name)
  -- a weapon bought (not an Omega): forget the pending vendor purchase of it, read the records again later
  local item = RANDO_REAL and RANDO_REAL.weapon_item and RANDO_REAL.weapon_item(weapon_name)
  local w = item and item:sub(8)
  if w then O.vendor_pending[w] = nil end
  for k, v in pairs(O.vendor_pending) do if O.frame - v.at <= O.OMEGA_WAIT then O.vendor_pending[k] = nil end end
end
function O.vendor_tick()
  for w, v in pairs(O.vendor_pending) do
    if O.frame - v.at >= O.OMEGA_WAIT then
      O.vendor_pending[w] = nil
      if O.snap and O.snap.bytes[w] then
        log("Omega purchase seen: " .. tostring(v.name) .. " (" .. w .. ") - its record is compared with the read before it")
        O.on_purchase(nil, w)
      else
        log("a purchase of " .. tostring(v.name) .. " without a weapon record read before it - nothing learned" ..
            (O.inv and "" or " (the weapon records are not found yet)"))
      end
    end
  end
end
function O.take_snapshot(why)
  if not O.inv then return end
  O.start_job("snapshot", function()
    if not O.inv then return end
    O.snap = { inv = O.inv, bytes = snapshot(O.inv), why = why }
  end)
end

function O.learn(w, cands)
  local s = S(); if not s then return end
  -- v0.62-DEV10: the offset is the game's own; an Omega purchase only shows that it is the right byte
  local L = O.ddl_layout
  if L and (L.live or L.verified) and O.offset() then
    local rel, hit = L.omega - L.id, false
    for _, c in ipairs(cands) do if c == rel then hit = true end end
    if hit then O.game_omega[w] = true; log(string.format("Omega purchase of %s: its Omega byte (+0x%X, the game's type data) went 0 -> 1 - CONFIRMED in the game", w, rel))
    else log(string.format("purchase of %s: its Omega byte (+0x%X) did not go 0 -> 1 (bytes that did: %d)", w, rel, #cands)) end
    return
  end
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
-- v0.62-DEV13: a weapon whose record in your inventory (GameEquipInventory, layout trusted) holds ItemCount 1 and XP
-- above 0 has been used, so you own it. round53 (Challenge Mode): Bouncer, Topiary Sprinkler, Cold Snap, ... were
-- carried over; the Omega rewards sent them again as prerequisites, the game never answered for a weapon you already
-- have, and direct delivery paused every other reward ("the game did not react to any target"); the Omega itself
-- waited until you happened to equip the weapon. Such a weapon now counts as delivered and the send is called off.
function O.owned_in_game(w)
  local rec = O.inv and O.inv.hero_owned and O.inv.records[w]
  if not rec then return false end
  local b = read(rec.id_at, O.REL.xp + 4)
  return hex64(b, 1) == O.ID_OF[w] and #b >= O.REL.xp + 4 and u32(b, O.REL.count + 1) == 1 and u32(b, O.REL.xp + 1) > 0
end
-- v0.71-DEV9: WHICH WEAPONS THE HERO HOLDS (12_rando_shop.lua: a bonus slot selling a weapon you already own cannot be bought,
-- so its bonus is given directly). A record of the hero's own set (hero_owned) holding the weapon's id, ItemCount 1 and not an
-- empty slot (slot 5000+ with no XP and no ammo). Read after every census and every O.HELD_EVERY frames; dropped by a load
-- (O.on_loading, O.on_checkpoint_load, O.forget), so a save loaded afterwards is read again before anything counts.
O.HELD_EVERY = 600
O.held = nil                                        -- { [w] = true } or nil while not read
function O.held_pass()
  local inv = O.inv
  if not (inv and inv.hero_owned) then return end
  local held, names = {}, {}
  for _, w in ipairs(GEN.sorted_keys(inv.records)) do
    local b = read(inv.records[w].id_at, O.REL.ammo + 4)
    if O.inv ~= inv then return end                 -- the records were dropped meanwhile
    if hex64(b, 1) == O.ID_OF[w] and #b >= O.REL.ammo + 4 and u32(b, O.REL.count + 1) == 1 and not O.empty_slot(b) then
      held[w] = true; names[#names + 1] = w
    end
  end
  local txt = table.concat(names, " ")
  O.held, O.held_frame = held, O.frame
  if txt ~= O.held_logged then
    O.held_logged = txt
    log(string.format("held: %d weapon(s) in your inventory: %s", #names, #names > 0 and txt or "none"))
  end
end
local function delivered(w)
  local s = S()
  local r = s and s.real and s.real["weapon:" .. w]
  if r and (r.status == "confirmed" or r.status == "owned" or r.status == "failed") then return true end
  if O.owned_in_game(w) then
    if r and r.status == "queued" and RANDO_REAL and RANDO_REAL.set_owned then
      pcall(RANDO_REAL.set_owned, "weapon:" .. w, "in your inventory with XP (Omega census)")
    end
    return true
  end
  return false
end
-- one weapon's flag (in a job). Returns "already", "set", or nil and why. only_read: never writes
function O.set_flag(w, off, only_read)
  local rec = O.inv and O.inv.records[w]
  if not rec then return nil, "no record" end
  local b = read(rec.id_at, off + 1)
  if hex64(b, 1) ~= O.ID_OF[w] then return nil, "the record moved" end
  -- v0.62-DEV13: and still an owned weapon (ItemCount 1): a reused or override copy is never written
  if b[O.REL.count + 4] == nil or u32(b, O.REL.count + 1) ~= 1 then return nil, "the record is not an owned weapon now" end
  -- v0.71-DEV2: a record the hero does not hold is never written (round54: Omega Negatron Collider "applied" to slot 5015)
  if O.empty_slot(b) then return nil, "empty slot", b end
  local v = b[off + 1]
  if v == 1 then return "already" end
  if v ~= 0 then return nil, string.format("byte +0x%X holds %s, not a flag", off, tostring(v)) end
  if only_read then return nil, "waits for the weapon" end
  -- v0.62-DEV10: a type-data record of another owner than the hero's actor is only read
  if O.inv.route == "type data" and not O.inv.hero_owned then return nil, "waits for the weapon" end
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
      local r, err, eb = O.set_flag(w, off, not delivered(w))
      local name = RANDO.item_name("omega:" .. w)
      if r == "set" and o.status == "applied" then
        log("kept " .. name .. " - its flag had been cleared (" .. why .. "), set again")
        say("Randomizer: " .. name .. " kept (the game had cleared it)")
      elseif r == "set" or r == "already" then
        if o.status ~= "applied" then
          RANDO.omega_applied(w, r == "set" and ("flag set, " .. how) or "the game already had it")
          say("Randomizer: " .. name .. " is yours", { type = "pickup", duration = 5 })
        end
      elseif r == nil and err == "empty slot" then
        O.note_empty(w, name, eb)
      elseif r == nil and err ~= "waits for the weapon" then
        O.fails[w] = (O.fails[w] or 0) + 1
        log("could not set " .. name .. " - " .. tostring(err) .. " (try " .. O.fails[w] .. ")")
      end
      if r then O.game_omega[w] = true; O.empty_since[w] = nil end
    end
  end
  -- Omegas the game itself showed (bought, or from a New Game+ save): never lost by a randomizer send
  for _, w in ipairs(GEN.sorted_keys(O.game_omega)) do
    if not (s.omega and s.omega[w]) and O.inv.records[w] and (O.fails[w] or 0) < O.MAX_WRITE_FAILS then
      local r, err = O.set_flag(w, off)
      if r == "set" then log("kept the game's Omega " .. w .. " - its flag had been cleared (" .. why .. "), set again")
      elseif r == nil and err ~= "empty slot" and err ~= "waits for the weapon" then O.fails[w] = (O.fails[w] or 0) + 1; log("could not keep " .. w .. " - " .. tostring(err)) end
    end
  end
end
-- which weapons the game holds as Omega right now (once per load, when the offset is known)
function O.read_game_omega()
  local off = O.offset()
  if not (off and O.inv) then return end
  for _, w in ipairs(GEN.sorted_keys(O.inv.records)) do
    local b = read(O.inv.records[w].id_at, off + 1)
    if hex64(b, 1) == O.ID_OF[w] and b[off + 1] == 1 and not O.game_omega[w] and not O.empty_slot(b) then
      O.game_omega[w] = true
      log("the game holds", w, "as Omega")
    end
  end
end


-- ---- v0.71-DEV8 WEAPON XP ---------------------------------------------------------------------
-- A weapon XP reward ("filler:xp:N", generator setting weapon_xp) is queued in state.xp_pending (location -> amount) by
-- 10_rando_runtime.lua and given here, once the weapon records are found and their layout is TRUSTED (the same check the
-- Omega flag needs): XP is WeaponItemPrius.XP, a u32 at +16 from the record's item id (O.REL.xp; round 60 read it on every
-- record: Enforcer 15807, RYNO 8 783588 ...). The game shows a weapon's level from its XP, so a write is read back and
-- logged with the before / after values. Which weapon (weapon_xp_target):
--   "smart" (default): an OMEGA weapon you hold first (it can level to 10), the one with the least XP; with none, the weapon
--                      you hold with the least XP (so the reward is never wasted on a weapon that is already high);
--   "lowest": the weapon you hold with the least XP, Omega or not.
-- A weapon you hold is a record with ItemCount 1 that is no empty slot (O.empty_slot). A checkpoint load that takes the XP
-- back (you died before the game saved) is noticed after the load (XP below what was written) and given again, twice at most.
-- NOT VERIFIED IN THE GAME: that the level shown follows the written XP at once (it may update at the next kill).
O.XP_EVERY = 60
O.XP_MAX = 0x7FFFFFFF
O.XP_REGIVE_MAX = 2
O.xp_recent = O.xp_recent or {}          -- this session's writes: { lid, w, after, amount, regives }
function O.xp_holder(w)
  local rec = O.inv and O.inv.records[w]
  if not rec then return nil end
  local b = read(rec.id_at, O.REL.omega + 1)
  if hex64(b, 1) ~= O.ID_OF[w] or #b < O.REL.xp + 4 then return nil end
  if u32(b, O.REL.count + 1) ~= 1 or O.empty_slot(b) then return nil end
  local slot = O.slot_of(b)
  if not slot or slot >= O.EMPTY_SLOT_FROM then return nil end
  local off = O.offset()
  local om = off and b[off + 1] == 1
  return { w = w, rec = rec, xp = u32(b, O.REL.xp + 1), omega = om or O.game_omega[w] == true }
end
function O.xp_target()
  local mode = tostring(cfg("weapon_xp_target") or "smart")
  local best, best_om
  for _, w in ipairs(GEN.sorted_keys(O.inv and O.inv.records or {})) do
    local h = O.xp_holder(w)
    if h then
      if not best or h.xp < best.xp then best = h end
      if h.omega and (not best_om or h.xp < best_om.xp) then best_om = h end
    end
  end
  if mode ~= "lowest" and best_om then return best_om, "Omega first" end
  return best, best_om and "the least XP" or "no Omega weapon held: the least XP"
end
function O.xp_write(h, amount)
  local new = math.min(O.XP_MAX, h.xp + amount)
  local le = string.format("%02X %02X %02X %02X", new & 0xFF, (new >> 8) & 0xFF, (new >> 16) & 0xFF, (new >> 24) & 0xFF)
  local ok, err = pcall(rivet.write, hexaddr(h.rec.id_at + O.REL.xp), le)
  if not ok then return nil, "write refused: " .. tostring(err) end
  local back = read(h.rec.id_at + O.REL.xp, 4)
  if #back < 4 or u32(back, 1) ~= new then return nil, "read back " .. tostring(#back == 4 and u32(back, 1)) end
  return new
end
function O.xp_pass()
  local s = S()
  if not (s and s.xp_pending and next(s.xp_pending) and O.inv and O.offset()) then return end
  if O.inv.route == "type data" and not O.inv.hero_owned then return end
  s.xp_done = s.xp_done or {}
  for _, lid in ipairs(GEN.sorted_keys(s.xp_pending)) do
    local amount = s.xp_pending[lid]
    if s.xp_done[lid] then
      s.xp_pending[lid] = nil; changed()
    elseif type(amount) == "number" and amount > 0 then
      local h, why = O.xp_target()
      if not h then
        if not O.xp_none_said then O.xp_none_said = true; log("WEAPON-XP waits: no weapon you hold was found in the records yet") end
        return
      end
      local after, err = O.xp_write(h, amount)
      local name = RANDO.item_name("weapon:" .. h.w)
      if after then
        s.xp_pending[lid] = nil
        s.xp_done[lid] = { w = h.w, amount = amount, before = h.xp, after = after }
        changed()
        O.xp_recent[#O.xp_recent + 1] = { lid = lid, w = h.w, after = after, amount = amount, regives = 0 }
        log(string.format("WEAPON-XP %s: +%d XP to %s%s (%s): %d -> %d", lid, amount, h.omega and "Omega " or "", name, why, h.xp, after))
        say(string.format("Randomizer: +%d weapon XP to %s%s", amount, h.omega and "Omega " or "", name), { type = "corner", duration = 4 })
      else
        O.fails["xp:" .. h.w] = (O.fails["xp:" .. h.w] or 0) + 1
        log("WEAPON-XP could not give", amount, "XP to", name, "-", tostring(err))
        return
      end
      O.pause()
    else
      s.xp_pending[lid] = nil; changed()
    end
  end
end
-- after a load: an XP write the checkpoint took back is given again
function O.xp_check_rollback()
  for _, e in ipairs(O.xp_recent) do
    if e.regives < O.XP_REGIVE_MAX then
      local h = O.xp_holder(e.w)
      if h and h.xp < e.after - e.amount // 2 then
        local after = O.xp_write(h, e.amount)
        if after then
          log(string.format("WEAPON-XP %s: the load took %s's XP back (%d, written %d) - given again: %d", e.lid, e.w, h.xp, e.after, after))
          e.regives, e.after = e.regives + 1, after
        end
      end
    end
  end
end
-- 10_rando_runtime.lua: a weapon XP reward was paid (queued in state.xp_pending). Returns how it will arrive
function O.xp_request(lid, amount)
  O.next_xp = 0
  if cfg("omega_runtime") == false then return "off" end
  if not O.offset() then return "waits" end
  return "queued"
end

-- ---- jobs -------------------------------------------------------------------------------------
function O.start_job(kind, fn)
  for _, j in ipairs(O.jobs) do if j.kind == kind and (kind == "search" or kind == "keep" or kind == "snapshot" or kind == "xp" or kind == "held") then return false end end
  O.jobs[#O.jobs + 1] = { kind = kind, co = coroutine.create(fn) }
  return true
end
-- v0.62-DEV11: a short job that runs before the others (dev(debug).lua NUMPAD1 waited ~1000 frames behind a census)
function O.start_job_front(kind, fn)
  table.insert(O.jobs, 1, { kind = kind, co = coroutine.create(fn) })
  return true
end
local function run_job()
  local j = O.jobs[1]
  if not j then return end
  slice_t0 = clock()
  local ok, err = coroutine.resume(j.co)
  if coroutine.status(j.co) == "dead" then
    if O.jobs[1] == j then table.remove(O.jobs, 1) end
    if not ok then
      log("RANDO-ERROR", j.kind .. ":", tostring(err))
      -- v0.62-DEV8: a search killed by the frame budget is taken up again soon (the walk continues from O.wstate)
      if j.kind == "search" then O.next_search = math.min(O.next_search, O.frame + 30) end
    end
  end
end
O.run_job = run_job

-- 10_rando_runtime.lua asks after an Omega reward. Returns "applied" | "pending" | "learning" | "off"
function O.request(w)
  if cfg("omega_runtime") == false then return "off" end
  if not O.offset() and O.ddl_why == nil and O.scene() then
    return "pending"                                -- v0.62-DEV10: the type data is still being read
  end
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
  O.walked, O.inv_handles, O.cand_logged, O.wstate = nil, {}, nil, nil   -- v0.62-DEV6: handles change with every load
  O.handle_cache, O.unresolved = {}, nil                                  -- v0.62-DEV9
  O.item_probe_queue, O.dstate = {}, nil       -- v0.62-DEV10: round50 probed 4 handles of the previous load (all "gone")
  -- v0.62-DEV12: round52 bought Omegas in one save, loaded ANOTHER save, and the randomizer set those weapons Omega
  -- there too ("kept the game's Omega bouncer ... set again"). Every load comes from a save, so the game's own
  -- Omegas are read again after it (O.read_game_omega); only the randomizer's own Omega rewards (state.omega) are kept.
  O.game_omega, O.fails = {}, {}
  O.empty_since, O.regives = {}, {}            -- v0.71-DEV2
  O.held = nil                                  -- v0.71-DEV9
  O.next_search = O.frame + O.SETTLE
  O.inv_why = why
end
-- v0.62-DEV13: a checkpoint load (death, restart, arena challenge) rebuilds item components. round53's first census
-- ran across three of them and read other objects' memory where the weapons had been. The census and the records are
-- dropped and read again after it; the game's Omegas of this save stay known.
function O.on_checkpoint_load()
  O.inv, O.snap, O.dstate, O.progress = nil, nil, nil, nil
  O.held = nil                                  -- v0.71-DEV9: read again after the load
  local keep = {}
  for _, j in ipairs(O.jobs) do if j.kind ~= "search" and j.kind ~= "keep" and j.kind ~= "snapshot" then keep[#keep + 1] = j end end
  O.jobs = keep
  O.empty_since = {}                            -- v0.71-DEV2: the records are read again after the load
  O.next_search = O.frame + O.SETTLE
end
-- v0.62-DEV14: called by 10_rando_runtime.lua on every frame of a load (death, retry, checkpoint, save load, travel:
-- the game thread is not pumping). The crash on death: DEV13's census and keep checks went on reading the records
-- and the component index while the game freed and rebuilt them on its own threads. Every address this script holds
-- is dropped - the census, the records, the snapshot, every job and the handle cache - and the search waits
-- O.SETTLE frames AFTER the load (this runs each loading frame, so the wait starts when the load ends). Nothing is
-- read or written here. What was found, learned and set stays: the layout (O.ddl_layout), the randomizer's Omega
-- rewards (state.omega) and the game's Omegas of this save (O.game_omega) - after the load they are read and kept
-- exactly as before.
function O.on_loading()
  if O.inv or O.snap or O.dstate or O.jobs[1] or next(O.handle_cache) then
    O.inv, O.snap, O.dstate, O.progress = nil, nil, nil, nil
    O.jobs, O.handle_cache, O.item_probe_queue = {}, {}, {}
    O.walked, O.wstate = nil, nil
    O.refresh = nil
    O.held = nil                                -- v0.71-DEV9: read again after the load
    O.dropped_for_load = (O.dropped_for_load or 0) + 1
    if O.dropped_for_load <= 20 then log("a load began: the census and the records are dropped, read again after it") end
  end
  O.next_search = math.max(O.next_search or 0, O.frame + O.SETTLE)
  O.next_keep = math.max(O.next_keep or 0, O.frame + O.SETTLE)
end
function O.new_game()
  O.forget("a new game")
  O.game_omega, O.fails = {}, {}
end
function O.after_restore() O.next_keep = 0 end

function O.tick(frames, ready)
  O.frame = O.frame + 1
  if not ready or cfg("omega_runtime") == false then return end    -- (nothing is read while loading)
  -- v0.62-DEV8: a busy frame is skipped. v0.62-DEV10: round50's Omega job runs last in the frame, after the Enemy
  -- Randomizer, and was starved for minutes; after O.STARVE_FRAMES skipped frames in a row it runs a short slice
  -- anyway, as long as the frame has used less than O.FRAME_HARD of rivet_hook's 8 ms.
  local used = (RANDO and RANDO.frame_t0) and (clock() - RANDO.frame_t0) or 0
  -- v0.62-DEV11: a quiet frame gives a longer slice (round51's census took ~1000 frames at 1.5 ms)
  O.slice = math.max(O.SLICE_SECONDS, math.min(O.SLICE_LONG, O.FRAME_TARGET - used))
  if O.jobs[1] then O.stats.frames = O.stats.frames + 1 end
  if used > O.FRAME_ROOM then
    O.starve = (O.starve or 0) + 1
    if not (O.starve >= O.STARVE_FRAMES and used < O.FRAME_HARD) then
      if O.jobs[1] then O.stats.skipped = O.stats.skipped + 1 end
      return
    end
    O.slice = O.SLICE_SHORT
    if O.jobs[1] then O.stats.starved = O.stats.starved + 1 end
  end
  O.starve = 0
  if O.jobs[1] then O.stats.ran = O.stats.ran + 1; run_job(); return end
  if O.item_probe_queue[1] then                                       -- v0.62-DEV9: one item probe per job
    local h = table.remove(O.item_probe_queue, 1)
    O.item_probed = O.item_probed + 1
    O.start_job("probe", function() O.probe_item(h) end)
    return
  end
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
      -- v0.62-DEV10: the game's type data first; the DEV5-DEV9 inventory search only if that finds nothing
      local inv, why = O.ddl_find()
      if not inv then
        if why ~= O.ddl_why then O.ddl_why = why; log("weapon items by the game's type data not found:", why) end
        local w2
        inv, w2 = O.find_records()
        if not inv then why = tostring(why) .. "; " .. tostring(w2) end
      else
        O.ddl_why = nil
      end
      if inv then
        O.inv = inv
        log(string.format("inventory: %d weapon record(s) in %s (%s; %d of %d frames ran, %d short slices in busy frames)",
            inv.count, inv.class, inv.route or string.format("array at +0x%X", inv.array_at), O.stats.ran, O.stats.frames, O.stats.starved))
        local off, how = O.offset()
        if off then log(string.format("the Omega flag: +0x%X from a record's item id (%s)", off, how))
        elseif inv.layout then log("the Omega flag: not written (the weapon records did not match WeaponItemPrius's fields) - records are read only") end
        local off2 = O.offset()
        say(off2 and string.format("Randomizer: Omega ready - %d weapons found", inv.count)
                 or string.format("Randomizer: %d weapons found, Omega not trusted yet (see rivet.log)", inv.count), { type = "center", duration = 5 })
        O.dump_records(inv)
        O.snap = { inv = inv, bytes = snapshot(inv), why = "found" }   -- v0.62-DEV6: the read an Omega purchase is compared with
        O.read_game_omega()
        O.pass("after a load")
        O.xp_check_rollback()                                -- v0.71-DEV8
        O.held_pass()                                        -- v0.71-DEV9
        O.next_held = O.frame + O.HELD_EVERY
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
  -- v0.71-DEV9: which weapons you hold (12_rando_shop.lua pays the bonus of a slot whose weapon you already own)
  if O.inv.hero_owned and O.frame >= (O.next_held or 0) then
    O.next_held = O.frame + O.HELD_EVERY
    O.start_job("held", O.held_pass)
  end
  -- v0.71-DEV8: weapon XP rewards waiting for a weapon record
  if s.xp_pending and next(s.xp_pending) and O.frame >= (O.next_xp or 0) and O.offset() then
    O.next_xp = O.frame + O.XP_EVERY
    O.start_job("xp", function() O.xp_pass() end)
  end
  -- v0.62-DEV6: Omega purchases (VendorPurchaseEvent alone) and a fresh read of the records for the next one
  if next(O.vendor_pending) then O.vendor_tick(); return end
  if not O.offset() and (O.frame >= (O.next_resnap or 0)) then
    O.next_resnap = O.frame + O.KEEP_EVERY // 2
    O.take_snapshot("periodic")
  end
end

function O.status_text()
  local s = S()
  if not s then return nil end
  local n, done = 0, 0
  for _, o in pairs(s.omega or {}) do n = n + 1; if type(o) == "table" and o.status == "applied" then done = done + 1 end end
  -- v0.62-DEV12: out of the seed's Omega rewards (round52's "Omega 0/1" read as "only one Omega in the seed")
  local total = 0
  local reg = RANDO_SEED and RANDO_SEED.registry
  if type(reg) == "table" then
    for key, where in pairs(reg) do
      if O.BY_KEY[key] and type(where) == "string" and (where == "location" or where:find("^start")) then total = total + 1 end
    end
  end
  if total == 0 and n == 0 then return nil end
  return string.format("Omega %d/%d%s", done, math.max(total, n), O.offset() and "" or " (flag not found yet)")
end

if RANDO and RANDO.subscribe then
  local function on(class, fn)
    RANDO.subscribe(class, function(ev)
      local ok, err = pcall(fn, ev.fields or {})
      if not ok then log("RANDO-ERROR", class, tostring(err)) end
    end)
  end
  on("EnteredVendorEvent", function() O.on_vendor_entered() end)
  -- v0.62-DEV6: leaving the vendor no longer drops the read (EnteredVendorEvent never came in round46)
  on("PurchaseWeaponEvent", function(f) O.on_weapon_purchase(f.WeaponName); O.on_purchase(f.WeaponName) end)
  on("VendorPurchaseEvent", function(f) O.on_vendor_purchase(f.WeaponName) end)
  -- v0.62-DEV6: the hero's inventories by handle (round46: Component 2129937 ... on the hero, never by name)
  on("GadgetItemAddedEvent", function(f)
    local h = math.tointeger(tonumber(f.InventoryHandle))
    if h and not O.inv_handles[h] then O.inv_handles[h] = "GadgetItemAddedEvent" end   -- v0.62-DEV10: the walk is kept
    local ih = math.tointeger(tonumber(f.ItemHandle))
    if ih and O.item_probed + #O.item_probe_queue < O.ITEM_PROBES then O.item_probe_queue[#O.item_probe_queue + 1] = ih end
  end)
  on("PlanetChangedEvent", function() O.forget("a planet load") end)
  on("LevelLoadedEvent", function() O.forget("a level load") end)
  -- a weapon added: its record is new, so the records are searched again (soon, not in the event)
  on("WeaponAddedEvent", function() O.refresh = true; O.next_search = math.min(O.next_search, O.frame + O.REFRESH) end)
  -- the inventory changed (a give of a weapon you own reports only this): look at the flags soon
  on("InventoryChangedEvent", function(f)
    O.next_keep = math.min(O.next_keep, O.frame + O.REFRESH)
    local hero = rivet.hero and rivet.hero()
    local h = math.tointeger(tonumber(f.Component))
    if h and hero and math.tointeger(tonumber(f.Actor)) == hero and not O.inv_handles[h] then
      O.inv_handles[h] = "InventoryChangedEvent"
      if not O.inv then O.next_search = math.min(O.next_search, O.frame + O.REFRESH) end
    end
  end)
  -- (through 14_rando_travel.lua's checkpoint hook: one more rivet.on_event could pass rivet_hook's subscription limit)
  if RANDO_TRAVEL and type(RANDO_TRAVEL.on_checkpoint) == "function" and RANDO_TRAVEL.on_checkpoint ~= RANDO_TRAVEL.omega_wrapper then
    local prev = RANDO_TRAVEL.on_checkpoint
    RANDO_TRAVEL.omega_wrapper = function(hash, loaded, ...)
      if loaded == true or loaded == "true" or loaded == 1 then
        local ok, err = pcall(RANDO_OMEGA.on_checkpoint_load)
        if not ok then log("RANDO-ERROR checkpoint", tostring(err)) end
      end
      return prev(hash, loaded, ...)
    end
    RANDO_TRAVEL.on_checkpoint = RANDO_TRAVEL.omega_wrapper
  end
  log("loaded (10.0.39: Omega from the game's type data; nothing is read while the game loads)")
else
  log("RANDO-ERROR 10_rando_runtime.lua is missing: Omega versions stay records only")
end
