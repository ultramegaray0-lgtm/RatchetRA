-- Real grants: puts randomizer rewards (weapons, gadgets) into the game's actual inventory.
--
-- Route 0, every planet (kit 1.2): rando_give.dll, loaded by rivet_hook through rivet.toml
-- ([renderdoc] dll_path). It hooks the game's script signal pump and, when this script asks
-- through a shared "mailbox" page, sends the game's own AddToInventoryHandle message to the
-- player - the exact call AddToInventoryAction makes (native/rando_give). If the DLL is missing,
-- refuses the exe, or the game never reacts to it, route 1 is used as before.
--
-- Route 1, proven in game (rounds 7-8): the game's own level-script node AddToInventoryAction
-- gives item [node+0x60] x [node+0x68] to the player when its "In" plug fires. Nefarious City
-- keeps three loaded. The node is pointed at the reward's item config, fired, and put back.
-- Box Breaker, Hoverboots, Bombardier, Glove of Doom, Negatron Collider and more arrived this
-- way and stayed in the save.
--
-- Route 2 (OFF, did not work in game): borrow another harmless node that is loaded there
-- (preferably DebugMessageAction, which does nothing in the released game). The exe's signal
-- queue (0x12BE970) calls a node's handler through the node's own vtable, and
-- AddToInventoryAction's handler (0x86CB90) only uses [+0x58] script context, [+0x60] item and
-- [+0x68] count. So for 5 frames the borrowed node's vtable pointer and those 12 bytes are
-- swapped, "In" is fired, and all 20 bytes are put back. Every node is checked against your
-- exe first (its vtable must match the RTTI table, which also gives the exe's load address;
-- AddToInventoryAction's handler must read back at the right address).
--
-- Every grant is checked: an item counts as delivered only when the game itself reports it
-- (GadgetItemAddedEvent with that gadget's type id, WeaponAddedEvent for weapons). A weapon you
-- already own is not reported again; owned weapons are recognised when you equip or buy them.
-- The queue survives restarts (it is part of the randomizer save).
--
-- Kit 16 (after round 13, where one unanswered item switched direct delivery off for good):
--   * a target that has delivered before stays in use; an item the game does not answer for
--     waits (10 s, then the next planet) while the other rewards keep coming
--   * only two different unanswered items in a row make the target suspect; then the targets
--     are tried again, and if none answers, delivery pauses until the next planet load
--   * nothing is sent while the game is loading, paused (rivet.time_scale() < 0.5) or within
--     2 s of a planet load; the wait for an answer counts only frames the game actually ran
--   * InventoryChangedEvent in the same pump as the hand-over now counts (it was missed, so an
--     already-owned weapon looked like "no reaction")
--   * WeaponType numbers are learned per item and saved; a late report at the next planet load
--     is credited to the one weapon still waiting (see G.on_weapon_added)
-- Verified only against the simulator (tests/), not yet in the game.
--
-- 5.0 (rando_give.dll v5):
--   * armor pieces are given through the game's own armor code (mailbox kind 6, the calls
--     VanityGiveBundleAction makes); the helper answers at once whether the piece was added
--   * Bolts and Raritanium (filler) are currency items given with a count, one request each,
--     from their own queue (G.give_currency); nothing is retried once the game took the message
--   * G.lookup_config asks the helper where a loaded config lives (kind 7, read only), for the
--     shop (12_rando_shop.lua)
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["09_rando_real"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)

RANDO_REAL = RANDO_REAL or {}
local G = RANDO_REAL
local SET = RANDO_SETTINGS or {}
G.enabled = G.enabled ~= false and SET.real_items ~= false
G.weapons = G.weapons ~= false and SET.real_weapons ~= false
-- route 2 is OFF: in rounds 10-11 three items fired through a borrowed node produced no
-- InventoryChangedEvent at all (route 1 produces one even for items you already own), so the
-- swap does not reach the give-item code. Kept for experiments: RANDO_DONOR_ROUTE = true.
G.donor_route = (RANDO_DONOR_ROUTE == true) or (G.donor_route == true)
G.frame = 0
G.gframe = 0                             -- frames the game actually ran (not paused, not loading)
G.node = nil
G.busy = nil
G.next_scan = 0
G.visit = 0                              -- bumps on every planet change
G.hinted_visit = -1
G.RESTORE_FRAMES = 45
G.DONOR_RESTORE_FRAMES = 5
G.CONFIRM_FRAMES = 180
G.OWNED_FRAMES = 60                      -- inventory changed, no new item after this long: owned
G.SILENT_HOLD = 600                      -- an item the game did not answer for waits 10 s
G.SETTLE_FRAMES = 120                    -- after a planet load, 2 s before anything is sent
G.SCAN_EVERY = 600
G.MAX_TRIES = { gadget = 3, weapon = 2 }
G.WAIT_RESTORE = 3600                    -- frames to wait for the companion's restore before going ahead
G.NODE_CLASS = "AddToInventoryAction"
G.ITEM_OFFSET = 0x60
G.seen = G.seen or {}                    -- gadget type ids the game has reported this session

-- 2.0: the deliverable items come from the game database (01_rando_data.lua), not the seed
local DATA = RANDO_DATA or {}
local ITEMS = DATA.real_items or {}
local NODES = DATA.real_nodes or { layout_ids = {}, preferred_nodes = {} }
local VT = RANDO_VTABLES or {}
local EXE = RANDO_EXE or { add_to_inventory_vtable = 0x2FA4DE0, add_to_inventory_handler = 0x86CB90, handler_slot = 10 }
local TARGET_PLUG = 0x7817619b

local function log(...) pcall(rivet.log, "[rando]", "RANDO-REAL", ...) end
local function S() return RANDO and RANDO.state end
local function changed() if RANDO and RANDO.mark_changed then RANDO.mark_changed() end end
local function say(text) if RANDO and RANDO.say then RANDO.say(text) else pcall(rivet.notify, text, { type = "pickup", duration = 4 }) end end
local function name(item) return (DATA.items and DATA.items[item] and DATA.items[item].name) or item end
local function hexaddr(n) return string.format("%X", n) end

local function le_hex(hex)               -- "%016X" -> "AA BB ..." little-endian
  local t = {}
  for k = 15, 1, -2 do t[#t + 1] = hex:sub(k, k + 1) end
  return table.concat(t, " ")
end
local function qword_from_text(text)     -- rivet.read text -> "%016X"
  local b = {}
  for x in text:gmatch("%x%x") do b[#b + 1] = x:upper() end
  if #b < 8 then return nil end
  return b[8] .. b[7] .. b[6] .. b[5] .. b[4] .. b[3] .. b[2] .. b[1]
end
local function read_u64(addr)
  local ok, text = pcall(rivet.read, hexaddr(addr), 8)
  if not ok or not text then return nil end
  local h = qword_from_text(text)
  return h and tonumber(h, 16)
end
G.le_hex, G.qword_from_text, G.read_u64 = le_hex, qword_from_text, read_u64

local LAYOUT, KNOWN, PREF, BY_TYPE, BY_CONFIG = {}, {}, {}, {}, {}
for _, h in ipairs(NODES.layout_ids or {}) do LAYOUT[h] = true; KNOWN[h] = true end
for i, uid in ipairs(NODES.preferred_nodes or {}) do PREF[uid] = i end
for item, info in pairs(ITEMS) do
  KNOWN[info.id] = true
  if info.type_id then BY_TYPE[math.tointeger(info.type_id) or info.type_id] = item end
  BY_CONFIG[info.config] = item
end

-- "WEAPON_PROTOGRENADE" / "ProtoGrenade" -> "weapon:shatterbomb"
function G.weapon_item(weapon_name)
  if type(weapon_name) ~= "string" or weapon_name == "" then return nil end
  local base = weapon_name:lower():gsub("^weapon_", ""):gsub("^wpn_", "")
  return BY_CONFIG["configs/equipment/wpn_" .. base .. "_item.config"]
end

-- ---- queue -------------------------------------------------------------------------------
local function rec(item)
  local s = S(); if not s then return nil end
  s.real = s.real or {}
  return s.real[item]
end

local function set_owned(item, why)
  local s = S(); if not (s and item) then return end
  s.real = s.real or {}
  local r = s.real[item]
  if r and (r.status == "confirmed" or r.status == "owned" or r.status == "sent") then return end
  s.real[item] = { status = "owned", tries = r and r.tries or 0 }
  changed()
  log("already in the game:", item, "(" .. why .. ")")
end
G.set_owned = set_owned

-- ask for a real grant. returns "queued", "done" (already in the game), "failed" or "unsupported"
function G.request(item)
  local info = ITEMS[item]
  local s = S()
  if not (G.enabled and info and s) or (info.kind == "weapon" and not G.weapons) then return "unsupported" end
  s.real = s.real or {}
  local r = s.real[item]
  if r and (r.status == "confirmed" or r.status == "owned") then return "done" end
  if info.type_id and G.seen[math.tointeger(info.type_id) or info.type_id] then
    set_owned(item, "reported by the game"); return "done"
  end
  if r and r.status == "failed" then return "failed" end
  s.real[item] = { status = (r and r.status == "sent") and "sent" or "queued", tries = r and r.tries or 0 }
  changed()
  return "queued"
end

-- queue everything the randomizer has already given that the game has not confirmed yet.
-- Called after the companion's restore (or after waiting for it).
function G.sync()
  local s = S(); if not s then return 0 end
  G.sanitize_types()
  local n = 0
  for item, r in pairs(s.real or {}) do      -- a grant cut off by a restart is sent again
    if r.status == "sent" and not (G.busy and G.busy.item == item) then r.status = "queued" end
  end
  local keys = {}
  for k in pairs(s.inventory or {}) do keys[#keys + 1] = k end             -- 2.0 state
  for w in pairs(s.weapons or {}) do keys[#keys + 1] = "weapon:" .. w end  -- 1.x state
  for g in pairs(s.gadgets or {}) do keys[#keys + 1] = g end
  table.sort(keys)
  local seen = {}
  for _, k in ipairs(keys) do
    if not seen[k] then seen[k] = true; if G.request(k) == "queued" then n = n + 1 end end
  end
  if n > 0 then log("sync:", n, "item(s) waiting for the game") end
  return n
end

-- items waiting; through a borrowed node, skip the ones it already failed on during this visit.
-- An item the game did not answer for waits (r.hold frames, or until the next planet:
-- r.skip_visit) so the others are not held up behind it. `all` lists every queued item.
function G.pending(for_donor, all)
  local s = S(); local list = {}
  for item, r in pairs((s and s.real) or {}) do
    if r.status == "queued" and not (for_donor and r.donor_visit == G.visit)
       and (all or ((r.hold or 0) <= G.frame and r.skip_visit ~= G.visit)) then
      list[#list + 1] = item
    end
  end
  table.sort(list, function(a, b)
    local ra, rb = s.real[a].silent or 0, s.real[b].silent or 0
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return list
end

-- a new game: the new save owns none of the old run's items, and gadgets the game reported in
-- the old save this session say nothing about the new one
function G.new_game()
  G.seen = {}
  -- 8.5: the weapon types this session saw belong to the old save: a late answer in the new run
  -- needs a fresh replay first, and a purchase name or unknown type in flight is dropped
  G.wseen, G.baseline, G.last_unknown, G.last_bought = {}, false, nil, nil
  G.inv_watch = nil                                  -- v0.54
  if G.burst then G.burst.new = nil end
  if G.busy then
    local b = G.busy
    if b.restore and not b.restored then pcall(b.restore); b.restored = true end
    -- 8.5: an item of the old run still in the mailbox is taken back, not given to the new one
    if b.via == "native" and b.stage == "handover" then G.take_back(b.req) end
    G.busy = nil
  end
  -- 8.5: likewise a currency payment of the old run (a config lookup simply runs again)
  if G.aux_busy and G.aux_busy.kind == 0 then G.aux_withdraw("a new game") end
  G.visit = G.visit + 1
  log("new game: delivery state cleared")
end

function G.counts()
  local s = S(); local c = { queued = 0, sent = 0, confirmed = 0, owned = 0, failed = 0 }
  for _, r in pairs((s and s.real) or {}) do c[r.status] = (c[r.status] or 0) + 1 end
  return c
end

-- ---- v0.54 (kit 10.0.5): giving your items back ---------------------------------------------
-- Round 26: after trips with ] / Ctrl+] the inventory was empty, and the save kept it that way
-- (its next load on Viceron replayed no weapon at all, where the randomizer knew 15 items as
-- yours). What empties it is not known (a mission's start loadout is one candidate: every
-- mission and objective node carries a SpawnLoadout for "loading directly into it", RESEARCH_8.0).
-- Every weapon and gadget the randomizer knows you own (given and confirmed, or recognised as
-- owned) can be sent again: one the game still has is answered with nothing new and simply stays
-- owned, one it lost is added again ("Given back: ..."). Bolts, Raritanium and armor are not.
G.RESTORE_KINDS = { weapon = true, gadget = true }
G.LOSS_CHECK_FRAMES = 420          -- after a trip has landed: the load's weapon replay has come by then
G.visit_weapons = G.visit_weapons or 0   -- WeaponAddedEvents since the last planet load
-- the items the randomizer knows you own; `strict` leaves out the ones only "probably owned"
function G.owned_items(kinds, strict)
  local s, out = S(), {}
  for item, r in pairs((s and s.real) or {}) do
    local info = ITEMS[item]
    if info and (kinds or G.RESTORE_KINDS)[info.kind] and (r.status == "confirmed" or r.status == "owned"
       or (not strict and r.status == "failed")) then
      out[#out + 1] = item
    end
  end
  table.sort(out)
  return out
end
-- queue them all again (quietly: only what the game really adds back is announced). Returns n.
function G.restore_inventory(why)
  local s = S(); if not s then return 0 end
  local n = 0
  for _, item in ipairs(G.owned_items()) do
    local r = s.real[item]
    if not (G.busy and G.busy.item == item) then
      r.status, r.restoring, r.tries = "queued", true, 0
      r.hold, r.skip_visit, r.silent, r.donor_visit = nil, nil, nil, nil
      n = n + 1
    end
  end
  G.inv_watch = nil
  if n > 0 then changed() end
  log("RANDO-RESTORE", n, "item(s) sent again (" .. tostring(why) .. ")")
  if RANDO and RANDO.history then RANDO.history("[RESTORE] " .. n .. " item(s) sent again (" .. tostring(why) .. ")") end
  return n
end
-- the hub's own trip has landed: look at the load's weapon replay a moment later. `same_planet`:
-- a warp that loads a checkpoint without a planet change (no PlanetChangedEvent starts the count)
function G.watch_inventory(why, same_planet)
  if same_planet then G.visit_weapons = 0 end
  G.inv_watch = { why = why, at = G.gframe }
end
function G.check_inventory()
  local w = G.inv_watch
  G.inv_watch = nil
  if not (w and RANDO and RANDO.config and RANDO.config.restore_inventory ~= false) then return nil end
  local known = #G.owned_items({ weapon = true }, true)
  local seen = G.visit_weapons or 0
  if known < 2 or seen >= math.max(1, known // 2) then
    log("RANDO-RESTORE after", w.why .. ":", seen, "weapon(s) reported by the load,", known, "known as yours - nothing to do")
    return false
  end
  log("RANDO-RESTORE after", w.why .. ": the load reported", seen, "of the", known, "weapons you own - giving your items back")
  say(string.format("Randomizer: your inventory looks emptied (%d of %d weapons) - giving your items back", seen, known))
  G.restore_inventory("the load after " .. w.why .. " reported " .. seen .. " of " .. known .. " weapons")
  return true
end

-- ---- nodes -------------------------------------------------------------------------------
-- the node is still the same live instance (levels reload; round 9 showed a stale write)
function G.still_valid(node, addr)
  local ok, c = pcall(rivet.component, node.actor, node.class)
  return ok and c and c.handle == node.component and tonumber(c.address, 16) == addr
end

local function outputs_of(component)
  local ok, n = pcall(rivet.script_node, component, false)
  if not ok or type(n) ~= "table" then return nil end
  return #(n.outputs or {})
end

-- route 1: a real AddToInventoryAction node
function G.find_node()
  local ok, list = pcall(rivet.script_nodes, G.NODE_CLASS, 32)
  if not ok or type(list) ~= "table" then return nil end
  local s = S()
  s.real_nodes = s.real_nodes or {}
  local best, best_score = nil, nil
  for _, node in ipairs(list) do
    local okc, c = pcall(rivet.component, node.actor, node.class)
    if node.class == G.NODE_CLASS and okc and c and c.handle == node.component then
      local addr = tonumber(c.address, 16)
      local okr, text = pcall(rivet.read, hexaddr(addr + G.ITEM_OFFSET), 12)
      local cur = okr and text and qword_from_text(text)
      local original = s.real_nodes[node.uid]
      if cur and LAYOUT[cur] and not original then s.real_nodes[node.uid] = cur; original = cur; changed() end
      -- a node left pointing at a reward (game closed mid-grant) is put back first
      if cur and original and cur ~= original and KNOWN[cur] then
        pcall(rivet.write, hexaddr(addr + G.ITEM_OFFSET), le_hex(original))
        log("node", node.uid, "was left at", cur, "- restored to", original)
        cur = original
      end
      if cur and LAYOUT[cur] then
        local score = PREF[node.uid]
        if not score and outputs_of(node.component) == 0 then score = 100 end
        if score and (not best_score or score < best_score) then
          best, best_score = { kind = "node", component = node.component, actor = node.actor, uid = node.uid,
                               class = node.class, addr = addr, original = original }, score
        end
      end
    end
  end
  return best
end

-- route 2: borrowed node
G.DONOR_WHITELIST = { DebugMessageAction = 0 }     -- does nothing in the released game
G.DONOR_FILTERS = { "DebugMessageAction", "Get", "Is", "Was", "Has", "Check", "Compare" }
G.DONOR_PER_FRAME = 4
function G.donor_rank(class)
  if G.DONOR_WHITELIST[class] then return G.DONOR_WHITELIST[class] end
  for i, pre in ipairs({ "Get", "Is", "Was", "Has", "Check", "Compare" }) do
    if class:sub(1, #pre) == pre then return i end
  end
  return nil
end

-- checks one node; returns a donor record, or nil and the reason (and its output count)
function G.check_donor(node)
  local rva = VT[node.class]
  if not rva then return nil, "class not in the vtable table" end
  local okc, c = pcall(rivet.component, node.actor, node.class)
  if not (okc and c and c.handle == node.component) then return nil, "instance not reachable" end
  if (c.size or 0) < 0x70 then return nil, "instance too small (" .. tostring(c.size) .. ")" end
  local okn, n = pcall(rivet.script_node, node.component, false)
  if not okn or type(n) ~= "table" then return nil, "script_node failed" end
  local outs = #(n.outputs or {})
  for _, v in ipairs(n.vars or {}) do
    if v.plug == TARGET_PLUG then return nil, "has a Target variable", outs end
  end
  local inst = tonumber(c.address, 16)
  local vt = read_u64(inst)
  if not vt then return nil, "cannot read the vtable", outs end
  local base = vt - rva
  if base % 0x10000 ~= 0 then return nil, string.format("vtable %X does not match the RTTI table", vt), outs end
  local aia_vt = base + EXE.add_to_inventory_vtable
  if read_u64(aia_vt + 8 * EXE.handler_slot) ~= base + EXE.add_to_inventory_handler then
    return nil, "AddToInventoryAction vtable check failed", outs
  end
  if outs > 0 then return nil, outs .. " output(s) wired", outs end
  return { kind = "donor", component = node.component, actor = node.actor, uid = node.uid, class = node.class,
           inst = inst, vt = vt, base = base, aia_vt = aia_vt, size = c.size }, nil, outs
end

-- runs over frames: phase 1 lists nodes (one rivet.script_nodes call per frame, so the frame
-- budget is never exceeded), phase 2 checks candidates. census = true (probe NUMPAD9) lists
-- every class and logs each verdict; otherwise only safe classes, stopping at the first donor.
function G.start_donor_search(census)
  G.donor_job = { phase = 1, filters = census and { "Action" } or G.DONOR_FILTERS, fi = 1,
                  limit = census and 512 or 64, nodes = {}, seen = {}, census = census, bases = {} }
end

local function donor_prepare(job)
  local per_class, order = {}, {}
  for _, node in ipairs(job.nodes) do
    local cls = node.class
    if not per_class[cls] then per_class[cls] = {}; order[#order + 1] = cls end
    if #per_class[cls] < 3 then table.insert(per_class[cls], node) end
  end
  table.sort(order, function(a, b)
    local ra, rb = G.donor_rank(a) or 99, G.donor_rank(b) or 99
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  local queue = {}
  for _, cls in ipairs(order) do
    if job.census or G.donor_rank(cls) then
      for _, node in ipairs(per_class[cls]) do queue[#queue + 1] = node end
    end
  end
  job.queue, job.phase = queue, 2
  log("donor search:", #job.nodes, "nodes,", #order, "classes,", #queue, "to check", job.census and "(census)" or "")
end

function G.donor_step()
  local job = G.donor_job
  if job.phase == 1 then
    local filter = job.filters[job.fi]
    if not filter then donor_prepare(job); return end
    job.fi = job.fi + 1
    local ok, list = pcall(rivet.script_nodes, filter, job.limit)
    if ok and type(list) == "table" then
      for _, n in ipairs(list) do
        if not job.seen[n.component] then job.seen[n.component] = true; job.nodes[#job.nodes + 1] = n end
      end
    end
    return
  end
  for _ = 1, G.DONOR_PER_FRAME do
    local node = table.remove(job.queue, 1)
    if not node then break end
    local d, why, outs = G.check_donor(node)
    if d then job.bases[d.base] = (job.bases[d.base] or 0) + 1 end
    if job.census then
      log(string.format("census %s comp=%s rank=%s outputs=%s %s", node.class, tostring(node.component),
          tostring(G.donor_rank(node.class)), tostring(outs), d and string.format("DONOR base=%X", d.base) or ("no: " .. tostring(why))))
    end
    if d and G.donor_rank(d.class) and not job.found then
      job.found = d
      if not job.census then break end
    end
  end
  if #job.queue > 0 and not (job.found and not job.census) then return end
  G.donor_job = nil
  local d = job.found
  local nbases = 0
  for _ in pairs(job.bases) do nbases = nbases + 1 end
  if d and nbases > 1 then log("donor search: nodes disagree on the exe address - not using any"); d = nil end
  if d then
    G.node = d
    log(string.format("donor: %s comp=%s uid=%s exe base %X", d.class, tostring(d.component), tostring(d.uid), d.base))
  else
    log("donor search: no safe node on this planet")
    G.hint()
  end
  if job.census and RANDO_PROBE and RANDO_PROBE.say then
    RANDO_PROBE.say(d and ("donor found: " .. d.class .. " - NUMPAD8 gives the test item through it") or "no safe donor node here")
  end
end

-- once per planet visit: tell the player that rewards are waiting, and say honestly where and
-- when they can arrive (round 13: "it arrives on Nefarious City" was shown on Nefarious City)
local function on_nefarious_city()
  return RANDO and RANDO.state and RANDO.state.current_planet == "nefarious_city"
end
function G.hint()
  if G.hinted_visit == G.visit then return end
  local n = G.native
  local native_on = n.addr and not n.dead and n.status == 1 and (n.version or 0) >= 2
  if native_on and not n.soft_off then return end
  local count = #G.pending(false, true)
  if count == 0 then return end
  G.hinted_visit = G.visit
  local what = string.format("%d randomizer reward%s waiting", count, count == 1 and "" or "s")
  if native_on then
    say(what .. " - the game is not answering right now; trying again on the next planet")
  elseif on_nefarious_city() then
    say(what .. " - no delivery point is loaded in this part of Nefarious City; it is tried again after the next load")
  else
    say(what .. (count == 1 and " - it arrives" or " - they arrive") .. " on Nefarious City (rando_give.dll is not working)")
  end
end

-- ---- delivery ----------------------------------------------------------------------------
local function begin(item, info, via, restore, restore_after, probe)
  local r = not probe and rec(item) or nil
  if r then
    if via == "node" then r.tries = (r.tries or 0) + 1 end
    r.status = "sent"
    changed()
  end
  G.busy = { item = item, kind = info.kind, via = via, sent = G.frame, gsent = G.gframe, restored = false, probe = probe,
             restore_after = restore_after, restore = restore, visit = G.visit }
  return r
end

function G.send(item)
  if G.node.kind == "donor" then return G.send_donor(item) end
  local info, node = ITEMS[item], G.node
  if not G.still_valid(node, node.addr) then log("node is gone (level changed); looking again"); G.node = nil; return false end
  local at = hexaddr(node.addr + G.ITEM_OFFSET)
  local okr, before = pcall(rivet.read, at, 12)
  if not okr or not before or qword_from_text(before) ~= node.original then
    log("node changed under us; looking again"); G.node = nil; return false
  end
  local okw, err = pcall(rivet.write, at, le_hex(info.id) .. " 01 00 00 00")
  if not okw then log("write failed:", tostring(err)); G.node = nil; return false end
  local okv, after = pcall(rivet.read, at, 8)
  if not okv or qword_from_text(after or "") ~= info.id then
    pcall(rivet.write, at, before); log("write did not stick; node restored"); G.node = nil; return false
  end
  local oks, serr = pcall(rivet.signal, node.component, "In")
  local r = begin(item, info, "node", function()
    if not G.still_valid(node, node.addr) then return true, "node gone - nothing to put back" end
    return pcall(rivet.write, at, before)
  end, G.RESTORE_FRAMES)
  log("sent", item, info.config, info.id, "via node", node.uid, oks and "fired" or ("signal refused: " .. tostring(serr)), "try " .. r.tries)
  if not oks then G.busy.sent = G.frame - G.CONFIRM_FRAMES end
  return oks
end

function G.send_donor(item, probe)
  local info, d = ITEMS[item], G.node
  local fields = hexaddr(d.inst + G.ITEM_OFFSET)
  if not G.still_valid(d, d.inst) then log("donor is gone (level changed); looking again"); G.node = nil; return false end
  if read_u64(d.inst) ~= d.vt then log("donor changed under us; looking again"); G.node = nil; return false end
  local ok1, before = pcall(rivet.read, fields, 12)
  if not ok1 or not before then G.node = nil; return false end
  local vt_le = le_hex(string.format("%016X", d.vt))
  local function restore()
    if not G.still_valid(d, d.inst) then return true, "donor gone - nothing to put back" end
    local a = pcall(rivet.write, hexaddr(d.inst), vt_le)
    local b2 = pcall(rivet.write, fields, before)
    return a and b2, (a and b2) and nil or "restore write failed"
  end
  local okw = pcall(rivet.write, fields, le_hex(info.id) .. " 01 00 00 00")
  local okv = okw and pcall(rivet.write, hexaddr(d.inst), le_hex(string.format("%016X", d.aia_vt)))
  if not (okw and okv) or read_u64(d.inst) ~= d.aia_vt then
    restore(); log("donor write failed; restored"); G.node = nil; return false
  end
  local oks, serr = pcall(rivet.signal, d.component, "In")
  begin(item, info, "donor", restore, G.DONOR_RESTORE_FRAMES, probe)
  log("sent", item, info.config, info.id, "via donor", d.class, "comp=" .. tostring(d.component),
      oks and "fired" or ("signal refused: " .. tostring(serr)), probe and "(probe)" or "")
  if not oks then restore(); G.busy.restored = true; G.busy.sent = G.frame - G.CONFIRM_FRAMES end
  return oks
end

local function finish(confirmed, interrupted)
  local b = G.busy; G.busy = nil
  if not b.restored then b.restore(); b.restored = true end
  local r = not b.probe and rec(b.item) or nil
  if not r then
    log(confirmed and "probe grant confirmed" or "probe grant: no confirmation", b.item)
    if RANDO_PROBE and RANDO_PROBE.say then RANDO_PROBE.say(confirmed and "the game confirmed the item" or "no confirmation from the game") end
    return
  end
  if confirmed then
    if b.via == "native" then G.native_target_works(b.mode) end
    r.status = "confirmed"
    r.hold, r.skip_visit = nil, nil
    log("confirmed", b.item, "via", b.via, "after", G.frame - b.sent, "frames", r.restoring and "(given back)" or "")
    say((r.restoring and "Given back: " or "Added to your inventory: ") .. name(b.item))
    r.restoring = nil
  elseif r.status == "owned" or r.status == "confirmed" then
    -- recognised as owned while we waited (equipped/bought/reported late): nothing more to do
    r.restoring = nil
  elseif interrupted then
    r.status = "queued"
    if b.via == "node" then r.tries = math.max(0, (r.tries or 1) - 1) end
    log("interrupted by a level change:", b.item)
  elseif r.restoring and not (b.via == "native" and S() and S().real_mode ~= b.mode) then
    -- v0.54: an item given back that the game reported nothing new for is still yours: it stays
    -- owned, quietly (no tries counted, the delivery target is not questioned)
    r.status = "owned"
    r.restoring, r.hold, r.skip_visit = nil, nil, nil
    if b.via == "native" and (G.inv_changed_frame or -1) >= (b.asked or b.sent) then G.native_target_works(b.mode) end
    log("still in your inventory:", b.item, "(given back, nothing new reported)")
  elseif b.via == "native" then
    local s = S()
    -- b.asked: the frame the request was written. The game's answer can arrive in the same pump
    -- that takes the request, before the script sees the hand-over, so b.sent is too late here
    if (G.inv_changed_frame or -1) >= (b.asked or b.sent) then
      -- the game handled the message (inventory changed) but did not report a new item:
      -- most likely already owned. The target works.
      G.native_target_works(b.mode)
      r.tries = (r.tries or 0) + 1
      if r.tries >= (G.MAX_TRIES[b.kind] or 2) then
        r.status = "failed"
        log("not confirmed after", r.tries, "direct tries:", b.item)
        say(name(b.item) .. ": the game reported nothing new - you probably have it already")
      else
        r.status = "queued"
        log("no confirmation yet for", b.item, "(direct) - will retry")
      end
    elseif s and s.real_mode == b.mode then
      -- Round 13: the target had delivered four items, then the game did not answer for one
      -- (Executor). That says nothing against the target: the item waits and is tried again
      -- (in 10 s, then on the next planet); the other rewards keep coming. Only when two
      -- different items in a row get no answer is the target itself questioned.
      r.status = "queued"
      r.silent = (r.silent or 0) + 1
      local n = G.native
      n.silent_items = n.silent_items or {}
      n.silent_items[b.item] = true
      local distinct = 0
      for _ in pairs(n.silent_items) do distinct = distinct + 1 end
      if r.silent >= 2 then
        r.skip_visit = G.visit
        log("direct delivery: still no answer for", b.item, "- trying again on the next planet")
        say(name(b.item) .. ": the game has not answered yet - trying again on the next planet")
      else
        r.hold = G.frame + G.SILENT_HOLD
        log("direct delivery: no answer for", b.item, "with target " .. G.native_target_name(b.mode) .. " (it worked before) - trying again shortly")
      end
      if distinct >= 2 then
        log("direct delivery: " .. distinct .. " different items got no answer - checking the target again")
        n.silent_items = {}
        s.real_mode_hint = s.real_mode
        s.real_mode = nil
        n.bad = n.bad or {}
        n.bad[b.mode] = true
        changed()
        if G.native_mode() == nil then G.native_soft_off("the game is not answering") end
      end
    else
      -- calibrating: the game did not react at all. Not counted against the item; the
      -- next target is tried
      r.status = "queued"
      log("direct delivery: no reaction from the game for", b.item, "with target " .. G.native_target_name(b.mode))
      G.native_target_failed(b.mode)
    end
  elseif b.via == "donor" then
    -- through a borrowed node, no confirmation is not counted against the item: it may simply
    -- not have worked here. It is tried again on Nefarious City (route 1).
    r.status = "queued"
    r.donor_visit = G.visit
    log("no confirmation through the borrowed node for", b.item, "- waits for Nefarious City")
  elseif r.tries >= (G.MAX_TRIES[b.kind] or 2) then
    r.status = "failed"
    log("not confirmed after", r.tries, "tries:", b.item)
    say(name(b.item) .. " was not added - you probably have it already")
  else
    r.status = "queued"
    log("no confirmation yet for", b.item, "- will retry")
  end
  changed()
end

function G.confirm_event(kind, type_id)
  local b = G.busy
  if type_id then
    G.seen[math.tointeger(type_id) or type_id] = true
    local item = BY_TYPE[math.tointeger(type_id) or type_id]
    if b and item == b.item then finish(true); return end
    -- the game gave (or loaded) a gadget we were going to send: nothing to do any more
    local r = item and rec(item)
    if r and (r.status == "queued" or r.status == "failed" or r.status == "sent") then set_owned(item, "reported by the game") end
    return
  end
  if b and b.kind == kind then finish(true) end
end

-- ---- weapons: WeaponAddedEvent{WeaponType} -----------------------------------------------
-- The event names no item, only a WeaponType number (round 13: 1001-1015). Each type the
-- randomizer sees confirm one of its own deliveries is remembered in the save
-- (s.weapon_types), so later reports of that type are recognised. A planet load replays the
-- event for every weapon owned (round 13, lines 79-88).
-- A late answer: when the game took a give message but reported the weapon only at the next
-- planet load (round 13: Executor, WeaponType 1015 on Nefarious City), a type never seen
-- before is credited to the one weapon still waiting for an answer - only if exactly one is
-- waiting, and only after a whole load replay has been seen this session (so weapons from the
-- save are known and are never mistaken for it).
G.BURST_FRAMES = 600
G.wseen = G.wseen or {}                 -- weapon types seen this session
G.burst = nil                           -- the replay after the current planet load
G.baseline = G.baseline or false        -- a whole replay has been seen
local function weapon_types()
  local s = S(); if not s then return {} end
  s.weapon_types = s.weapon_types or {}
  return s.weapon_types
end
local function learn_type(t, item)
  local wt = weapon_types()
  if t and item and wt[t] ~= item then
    for other, it in pairs(wt) do if it == item and other ~= t then wt[other] = nil end end   -- one type per weapon
    wt[t] = item; changed()
    log("weapon type", t, "is", item)
  end
end
local function end_burst()
  local b = G.burst
  G.burst = nil
  if not b then return end
  local new = b.new or {}
  if G.baseline and #new == 1 then
    local ok, err = pcall(G.unknown_type_expired, new[1])
    if not ok then log("late answer:", tostring(err)) end
  elseif #new > 1 then
    log("weapon replay with", #new, "types new to this session - none taken as a late answer")
  end
  if b.n >= 2 then
    if not G.baseline then log("weapon replay seen (" .. b.n .. " weapons) - late answers can be recognised now") end
    G.baseline = true
  end
end
G.end_burst = end_burst
-- 8.4 (round 20): a load equips the current weapon (UserEquippedWeaponEvent) and then replays
-- WeaponAddedEvent for every weapon owned. 8.3 took every unknown type within 60 frames of a
-- weapon NAME as that weapon, so Cordelion's replay taught "1002 ... 1012 are the Burst Pistol".
-- Now a type is learned from a name only from a purchase (PurchaseWeaponEvent), never during a
-- load's replay, one type per purchase, in either order (round 20: WeaponAddedEvent 1013 came
-- just BEFORE PurchaseWeaponEvent WEAPON_SHEEPINATOR). An unknown type is held 90 frames before it
-- may count as a late answer, so a purchase is never credited to a waiting delivery.
G.NAME_FRAMES = 90
-- one weapon has one type: types the save maps to the same weapon are all dropped (8.3's bad lessons)
function G.sanitize_types()
  local s = S(); if not (s and s.weapon_types) then return 0 end
  local by_item = {}
  for t, item in pairs(s.weapon_types) do by_item[item] = (by_item[item] or 0) + 1 end
  local dropped = 0
  for t, item in pairs(s.weapon_types) do
    if by_item[item] > 1 then s.weapon_types[t] = nil; dropped = dropped + 1 end
  end
  if dropped > 0 then
    changed()
    log("weapon types: dropped", dropped, "wrong lesson(s) (several types for one weapon)")
  end
  return dropped
end
function G.on_weapon_added(raw)
  G.visit_weapons = (G.visit_weapons or 0) + 1      -- v0.54: the inventory check after a trip
  local t = math.tointeger(raw) or raw
  local b = G.busy
  local wt = weapon_types()
  local known = t and wt[t]
  local new = t and not G.wseen[t]
  if t then G.wseen[t] = true end
  if b and b.kind == "weapon" and (not known or known == b.item) then
    learn_type(t, b.item)
    finish(true)
    return
  end
  if G.burst then G.burst.n = G.burst.n + 1 end
  if known then
    local r = rec(known)
    if r and r.status ~= "confirmed" and r.status ~= "owned" then set_owned(known, "reported by the game (type " .. tostring(t) .. ")") end
    return
  end
  if not t then return end
  if G.burst then
    -- a load's replay: weapons from the save. A type new to this session in a replay is a late
    -- answer only when it is the replay's ONLY new type (round 13: Executor 1015 on Nefarious
    -- City); round 20's first full replay (1002-1012 on Cordelion) taught nothing
    if new then G.burst.new = G.burst.new or {}; G.burst.new[#G.burst.new + 1] = t end
    return
  end
  local bought = G.last_bought
  if bought and G.frame - bought.frame <= G.NAME_FRAMES then
    G.last_bought = nil
    learn_type(t, bought.item)                     -- bought just now (the name came first)
    return
  end
  if not new then return end
  G.last_unknown = { t = t, frame = G.frame }      -- a purchase may still name it
end
-- an unknown type no purchase claimed: a late answer for the one weapon still waiting, if exactly one
function G.unknown_type_expired(t)
  if not G.baseline then return end
  local s, waiting = S(), {}
  for item, r in pairs((s and s.real) or {}) do
    -- (8.4: also one given up on - "not confirmed" - since the answer can come after the tries)
    if ITEMS[item] and ITEMS[item].kind == "weapon" and (r.silent or 0) > 0
       and (r.status == "queued" or r.status == "sent" or r.status == "failed") then
      waiting[#waiting + 1] = item
    end
  end
  if #waiting == 1 then
    learn_type(t, waiting[1])
    set_owned(waiting[1], "the game answered late (type " .. tostring(t) .. ")")
    say("Added to your inventory: " .. name(waiting[1]))
  end
end

-- equipping or buying a weapon proves it is owned; only a purchase teaches a type
function G.on_weapon_name(weapon_name, why)
  local item = G.weapon_item(weapon_name)
  if not item then return end
  if why == "bought" then
    local u = G.last_unknown
    if u and G.frame - u.frame <= G.NAME_FRAMES then
      G.last_unknown = nil
      learn_type(u.t, item)
    else
      G.last_bought = { item = item, frame = G.frame }
    end
  end
  local r = rec(item)
  if r and (r.status == "confirmed" or r.status == "owned") then return end
  if G.busy and G.busy.item == item then return end
  set_owned(item, why)
end

function G.on_planet_change(new_name)
  G.node = nil; G.donor_job = nil
  G.next_scan = G.frame + 120
  G.settle_until = G.frame + G.SETTLE_FRAMES
  if new_name and new_name ~= "" then
    G.visit = G.visit + 1
    G.visit_weapons = 0
    end_burst()
    G.burst = { n = 0, ends = G.frame + G.BURST_FRAMES }
    local n = G.native
    n.bad = {}                              -- targets and the game get a fresh chance
    n.silent_items = {}
    if n.soft_off then n.soft_off = false; log("direct delivery: trying again on this planet") end
  end
  if G.aux_busy and G.native.addr and G.u32_at(G.native.addr + G.MB.DONE) ~= G.aux_busy.req then
    G.aux_withdraw("a level load")
  end
  local b = G.busy
  if b and b.via == "native" then
    -- a load replays WeaponAddedEvent for every owned weapon: none of those may be taken as the
    -- answer to a request still in flight. A request the helper has not taken yet is withdrawn.
    if b.stage == "handover" and G.native.addr and not G.take_back(b.req) then
      -- answered in the meantime: the answer is read now, before the load's replay
      G.native_handover(b)
      if G.busy == b and b.stage == "confirm" then finish(false, true) end
    else
      finish(false, true)
    end
  elseif b and not b.restored then
    finish(false, true)
  end
end

function G.forget_node() G.node = nil; G.donor_job = nil; G.next_scan = G.frame + 120 end

-- Is the game running normally right now? rivet.time_scale() raises while the pump is on the
-- render thread (loading screens) and reports the applied speed otherwise; a paused game or a
-- menu that stops time reads (close to) 0. Builds of rivet_hook without time_scale skip this.
G.ts_errors = 0
function G.game_running()
  if type(rivet.time_scale) ~= "function" then return true end
  local ok, v = pcall(rivet.time_scale)
  if not ok then
    G.ts_errors = G.ts_errors + 1
    if G.ts_errors > 3600 then                -- a minute of errors with a hero: ignore the check
      if not G.ts_warned then G.ts_warned = true; log("time scale keeps failing (" .. tostring(v) .. ") - not waiting for it") end
      return true
    end
    return false
  end
  G.ts_errors = 0
  return type(v) ~= "number" or v >= 0.5
end

function G.on_frame()
  G.frame = G.frame + 1
  local running = G.game_running()
  if running then G.gframe = G.gframe + 1 end
  if G.burst and G.frame >= G.burst.ends then end_burst() end
  local u = G.last_unknown
  if u and G.frame - u.frame > G.NAME_FRAMES then
    G.last_unknown = nil
    local oku, eu = pcall(G.unknown_type_expired, u.t)
    if not oku then log("late answer:", tostring(eu)) end
  end
  if G.donor_job then local ok, err = pcall(G.donor_step); if not ok then log("donor step:", tostring(err)); G.donor_job = nil end end
  if G.inv_watch and G.gframe >= G.inv_watch.at + G.LOSS_CHECK_FRAMES then
    local okc, ec = pcall(G.check_inventory)
    if not okc then log("inventory check:", tostring(ec)) end
  end
  local b = G.busy
  if b and b.via == "native" and b.stage == "handover" then G.native_handover(b); return end
  if b then
    if not b.restored and G.frame >= b.sent + b.restore_after then
      local ok, err = b.restore()
      b.restored = true
      log("node restored", ok and "ok" or tostring(err))
    end
    -- the answer is waited for in frames the game actually ran (a paused game answers later).
    -- The game handled the message but reported no new item for a second: it already had it.
    if b.via == "native" and b.stage == "confirm" and (G.inv_changed_frame or -1) >= (b.asked or b.sent)
       and G.gframe >= (b.gsent or G.gframe) + G.OWNED_FRAMES then
      finish(false)
    elseif G.gframe >= (b.gsent or G.gframe) + G.CONFIRM_FRAMES then
      finish(false)
    end
    return
  end
  if G.frame % 30 ~= 0 then return end
  if not G.enabled then
    if not G.warned_off then
      local ready = false
      pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
      if ready then
        G.warned_off = true
        say("Randomizer: real items are OFF (real_items = false in 04_rando_settings.lua)")
      end
    end
    return
  end
  -- the companion restores the saved state first, so nothing is sent twice after a restart
  if RANDO and not RANDO.restored then
    if G.frame < G.WAIT_RESTORE then return end
    if not G.synced_without_save then G.synced_without_save = true; log("no saved state restored - going ahead"); G.sync() end
  end
  if G.aux_tick() then return end
  if #G.pending(false) == 0 then
    if #G.pending(false, true) > 0 and not G.native_ready() then G.hint() end
    return
  end
  local ready = true
  pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
  if not ready or not running or G.frame < (G.settle_until or 0) then return end
  if G.mission_busy or G.aux_busy then return end   -- a mission or aux request is using the mailbox
  if G.native_ready() then
    G.send_native(G.pending(false)[1])
    return
  end
  if not G.node then
    if G.donor_job or G.frame < G.next_scan then return end
    G.next_scan = G.frame + G.SCAN_EVERY
    G.node = G.find_node()
    if G.node then
      log("using node", G.node.uid, "comp=" .. tostring(G.node.component))
    elseif G.donor_route then
      G.start_donor_search(false)
      return
    else
      G.hint()
      return
    end
  end
  local list = G.pending(G.node.kind == "donor")
  if #list == 0 then G.hint(); return end
  G.send(list[1])
end

-- ---- route 0: rando_give.dll mailbox ------------------------------------------------------
G.NATIVE_CANDIDATES = { 0x7FEF00000000, 0x7FEE00000000, 0x7FED00000000, 0xB00000000 }
G.MB = { MAGIC = 0x00, STATUS = 0x0C, REQ = 0x10, DONE = 0x14, ITEM = 0x18, COUNT = 0x20, RESULT = 0x24,
         PUMPS = 0x28, TARGETS = 0x2C, HERO = 0x38, PATH = 0x40, MODE = 0x44 }
G.NATIVE_MAGIC = "52 41 4E 44 47 49 56 31"         -- "RANDGIV1"
G.NATIVE_STATUS = { [0] = "starting", [1] = "ready", [2] = "refused this exe (nothing patched)", [3] = "could not install its hook" }
G.NATIVE_WAIT = 120                                -- frames to wait for the helper to pick up a request
G.native = G.native or { addr = nil, status = nil, dead = false, silent = 0, seq = 0, next_probe = 0, reported = false }

local function u32_at(addr)
  local ok, text = pcall(rivet.read, hexaddr(addr), 4)
  if not ok or not text then return nil end
  local b = {}
  for x in text:gmatch("%x%x") do b[#b + 1] = tonumber(x, 16) end
  if #b < 4 then return nil end
  return b[1] + b[2] * 0x100 + b[3] * 0x10000 + b[4] * 0x1000000
end
local function le32(v) return string.format("%02X %02X %02X %02X", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF) end
G.u32_at, G.le32 = u32_at, le32

-- for good: the helper cannot work in this session (wrong exe, no hook, faulted)
function G.native_disable(why)
  if G.native.dead then return end
  G.native.dead = true
  log("direct delivery off:", why, "- rewards arrive on Nefarious City instead")
  say("Randomizer: direct delivery is not working (" .. why .. ") - rewards arrive on Nefarious City")
end

-- until the next planet: the helper works but the game answered no target. Nothing is lost:
-- the rewards wait, and every planet load tries again (round 13 switched off for good here)
function G.native_soft_off(why)
  local n = G.native
  if n.soft_off or n.dead then return end
  n.soft_off = true
  log("direct delivery paused:", why, "- trying again on the next planet")
end

-- finds the mailbox and reads its status; cheap, so it can run often
function G.native_probe()
  local n = G.native
  if not n.addr then
    if G.frame < n.next_probe then return false end
    n.next_probe = G.frame + G.SCAN_EVERY
    for _, a in ipairs(G.NATIVE_CANDIDATES) do
      local ok, text = pcall(rivet.read, hexaddr(a), 8)
      if ok and text and text:upper():gsub("%s+$", "") == G.NATIVE_MAGIC then n.addr = a; break end
    end
    if not n.addr then
      if not n.reported then n.reported = true; log("direct delivery: rando_give.dll is not loaded (check rivet.toml [renderdoc])") end
      return false
    end
    n.seq = u32_at(n.addr + G.MB.REQ) or 0
  end
  n.status = u32_at(n.addr + G.MB.STATUS)
  n.version = u32_at(n.addr + 0x08)
  if (n.version or 0) < 2 then
    if not n.old_warned then
      n.old_warned = true
      log("direct delivery: rando_give.dll is an old version (" .. tostring(n.version) .. ") - replace it with the one from the kit")
      say("Randomizer: replace rando_give.dll with the new one from the kit (old version found)")
    end
    return false
  end
  if n.status ~= n.logged_status then
    n.logged_status = n.status
    log(string.format("direct delivery: helper at %X: %s", n.addr, G.NATIVE_STATUS[n.status] or tostring(n.status)))
  end
  return n.status == 1
end

function G.native_ready() return not G.native.dead and not G.native.soft_off and G.native_probe() end

-- Which actor the give message goes to. Round 12: the game's default group (0) was ignored.
-- Candidates, tried in this order until the game answers: the hero actor rivet_hook reports
-- (0), then actor groups 1, 0 and 3 (mode = group + 1). The one that works is kept in the save.
G.TARGET_MODES = { 0, 2, 1, 4 }
G.TARGET_NAMES = { [0] = "hero", [1] = "group 0", [2] = "group 1", [4] = "group 3" }
function G.native_target_name(mode) return G.TARGET_NAMES[mode] or ("mode " .. tostring(mode)) end
function G.native_mode()
  local s = S()
  if s and s.real_mode ~= nil then return s.real_mode end
  local n = G.native
  n.bad = n.bad or {}
  -- the target that worked last time is tried first again
  if s and s.real_mode_hint ~= nil and not n.bad[s.real_mode_hint] then return s.real_mode_hint end
  for _, m in ipairs(G.TARGET_MODES) do
    if not n.bad[m] then return m end
  end
  return nil
end
function G.native_target_works(mode)
  local s = S()
  if s and mode ~= nil and s.real_mode ~= mode then
    s.real_mode = mode
    changed()
    log("direct delivery: target " .. G.native_target_name(mode) .. " works - kept for next time")
  end
end
function G.native_target_failed(mode)
  local s, n = S(), G.native
  n.bad = n.bad or {}
  n.bad[mode] = true
  if s and s.real_mode == mode then s.real_mode = nil; changed() end
  if G.native_mode() == nil then G.native_soft_off("the game did not react to any target") end
end

function G.send_native(item, probe)
  local info, n = ITEMS[item], G.native
  if info.kind == "armor" then return G.send_armor(item) end
  local hero = 0
  pcall(function() hero = rivet.hero() or 0 end)
  local mode = G.native_mode()
  if mode == nil then G.native_soft_off("the game did not react to any target"); return false end
  n.seq = ((u32_at(n.addr + G.MB.REQ) or n.seq) + 1) & 0xFFFFFFFF
  -- v3 helpers also take mission requests (11_rando_campaign.lua): this one is a give
  if (n.version or 0) >= 3 and not pcall(rivet.write, hexaddr(n.addr + 0x48), le32(0)) then
    G.native_disable("cannot write its mailbox"); return false
  end
  local ok1 = pcall(rivet.write, hexaddr(n.addr + G.MB.ITEM), le_hex(info.id) .. " " .. le32(1))
  local ok2 = pcall(rivet.write, hexaddr(n.addr + G.MB.HERO), le32(hero & 0xFFFFFFFF))
        and pcall(rivet.write, hexaddr(n.addr + G.MB.MODE), le32(mode))
  local ok3 = ok1 and ok2 and pcall(rivet.write, hexaddr(n.addr + G.MB.REQ), le32(n.seq))   -- last
  if not ok3 then G.native_disable("cannot write its mailbox"); return false end
  local r = not probe and rec(item) or nil
  if r then r.status = "sent"; changed() end
  G.busy = { item = item, kind = info.kind, via = "native", sent = G.frame, restored = true, probe = probe,
             restore_after = 0, restore = function() return true end, visit = G.visit,
             stage = "handover", req = n.seq, asked = G.frame, pumps = u32_at(n.addr + G.MB.PUMPS) or 0, mode = mode }
  log("sent", item, info.config, info.id, "via rando_give.dll", "request " .. n.seq, "target " .. G.native_target_name(mode),
      probe and "(probe)" or "")
  return true
end

-- while the helper has not picked up the request yet
local function native_handover(b)
  local n = G.native
  if u32_at(n.addr + G.MB.DONE) == b.req then
    local result = u32_at(n.addr + G.MB.RESULT)
    if b.armor then G.armor_answer(b, result); return end
    local targets = u32_at(n.addr + G.MB.TARGETS)
    if result == 1 then
      b.stage = "confirm"
      b.sent = G.frame
      b.gsent = G.gframe
      log("direct delivery: message sent to", targets, "actor(s) for", b.item)
      return
    end
    G.busy = nil
    local r = not b.probe and rec(b.item) or nil
    if r then r.status = "queued"; changed() end
    if result == 2 then
      if b.mode == 0 then
        log("direct delivery: no hero yet; will retry", b.item)
      else
        log("direct delivery: target " .. G.native_target_name(b.mode) .. " is empty", b.item)
        G.native_target_failed(b.mode)
      end
    elseif result == 3 then
      G.native_disable("the game faulted in the helper")
    else
      log("direct delivery: request refused (" .. tostring(result) .. ")", b.item)
      if r then r.status = "failed"; changed() end
    end
    return
  end
  if G.frame >= b.sent + G.NATIVE_WAIT then
    local pumps = u32_at(n.addr + G.MB.PUMPS) or 0
    local ready = false
    pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
    if pumps == b.pumps and not ready then
      -- a load: the game's script pump (and so the helper) does not run during loading
      -- screens. The request stays in the mailbox and is handled when it runs again.
      b.sent = G.frame
      return
    end
    -- 8.5: taken back first: a helper that comes back later must not give it a second time
    if not G.take_back(b.req) then return end      -- answered after all: read next frame
    G.busy = nil
    local r = not b.probe and rec(b.item) or nil
    if r then r.status = "queued"; changed() end
    if pumps == b.pumps then
      G.native_disable("its hook is not running")
    else
      G.native_soft_off("it did not pick up the request")
    end
  end
end
G.native_handover = native_handover

-- ---- 5.0: armor, currency and config lookups through the helper -------------------------
G.MB.KIND, G.MB.RET, G.MB.OBJECT, G.MB.VANITY = 0x48, 0x5C, 0x68, 0x74
G.HELPER_V5 = 5
function G.native_v5()
  local n = G.native
  return G.native_ready() and (n.version or 0) >= G.HELPER_V5
end
-- can armor be handed over at all in this session? nil while unknown
function G.armor_ok()
  if not G.native_ready() then return nil end
  if (G.native.version or 0) < G.HELPER_V5 then return false, "rando_give.dll is older than v5 (replace it with the kit's)" end
  if u32_at(G.native.addr + G.MB.VANITY) ~= 1 then return false, "rando_give.dll did not recognise this exe's armor code" end
  return true
end

function G.send_armor(item)
  local info, n = ITEMS[item], G.native
  local r = rec(item)
  local ok, why = G.armor_ok()
  if ok == false then
    if r then r.status = "failed"; r.why = why; changed() end
    log("armor cannot be handed over:", why, item)
    say(name(item) .. ": armor cannot be added (" .. why .. ")")
    return false
  end
  n.seq = ((u32_at(n.addr + G.MB.REQ) or n.seq) + 1) & 0xFFFFFFFF
  local ok1 = pcall(rivet.write, hexaddr(n.addr + G.MB.KIND), le32(6))
  ok1 = ok1 and pcall(rivet.write, hexaddr(n.addr + G.MB.ITEM), le_hex(info.id))
  ok1 = ok1 and pcall(rivet.write, hexaddr(n.addr + G.MB.REQ), le32(n.seq))   -- last
  if not ok1 then G.native_disable("cannot write its mailbox"); return false end
  if r then r.status = "sent"; changed() end
  G.busy = { item = item, kind = "armor", via = "native", armor = true, sent = G.frame, restored = true,
             restore_after = 0, restore = function() return true end, visit = G.visit,
             stage = "handover", req = n.seq, asked = G.frame, pumps = u32_at(n.addr + G.MB.PUMPS) or 0 }
  log("sent", item, info.config, info.id, "via rando_give.dll (armor)", "request " .. n.seq)
  return true
end

-- the helper answered an armor request
function G.armor_answer(b, result)
  local n = G.native
  G.busy = nil
  local r = rec(b.item)
  local ret = u32_at(n.addr + G.MB.RET)
  if result == 11 and ret == 1 then
    if r then r.status = "confirmed"; r.hold = nil; changed() end
    log("confirmed", b.item, "(armor) after", G.frame - b.sent, "frames")
    say("Added to your armor: " .. name(b.item))
  elseif result == 11 then
    if r then r.status = "owned"; changed() end
    log("already in the game:", b.item, "(the game's armor code said no: owned)")
    say(name(b.item) .. ": you have this armor piece already")
  elseif result == 2 then
    if r then r.status = "queued"; r.hold = G.frame + G.SILENT_HOLD; changed() end
    log("armor: no hero right now, will retry", b.item)
  elseif result == 3 then
    if r then r.status = "queued"; changed() end
    G.native_disable("the game faulted in the helper")
  else
    if r then r.status = "failed"; changed() end
    log("armor request refused (" .. tostring(result) .. ")", b.item)
    say(name(b.item) .. ": armor cannot be added (helper result " .. tostring(result) .. ")")
  end
end

-- one auxiliary helper request at a time (currency, config lookups), only while nothing else
-- uses the mailbox
G.aux_queue = G.aux_queue or {}
G.AUX_WAIT = 120
function G.give_currency(item, count, why)
  local s = S(); if not (s and ITEMS[item] and count and count > 0) then return false end
  s.currency_queue = s.currency_queue or {}
  local q = s.currency_queue
  q[#q + 1] = { item = item, count = math.floor(count), why = why }
  changed()
  return true
end
function G.lookup_config(id_hex, cb)
  G.aux_queue[#G.aux_queue + 1] = { kind = 7, id = id_hex, cb = cb }
end
function G.aux_idle() return not (G.busy or G.mission_busy or G.aux_busy) end

local function aux_start()
  local n = G.native
  local s = S()
  local job = table.remove(G.aux_queue, 1)
  local cur
  if job then
    if (n.version or 0) < G.HELPER_V5 then job.cb(nil, "rando_give.dll is older than v5"); return end
    cur = job
  elseif s and s.currency_queue and #s.currency_queue > 0 and #G.pending(false) == 0 then
    local c = s.currency_queue[1]
    local mode = G.native_mode()
    if mode == nil then return end
    local hero = 0
    pcall(function() hero = rivet.hero() or 0 end)
    cur = { kind = 0, currency = c, mode = mode, hero = hero }
  else
    return
  end
  n.seq = ((u32_at(n.addr + G.MB.REQ) or n.seq) + 1) & 0xFFFFFFFF
  local ok
  if cur.kind == 7 then
    ok = pcall(rivet.write, hexaddr(n.addr + G.MB.KIND), le32(7)) and pcall(rivet.write, hexaddr(n.addr + G.MB.ITEM), le_hex(cur.id:upper()))
  else
    local info = ITEMS[cur.currency.item]
    ok = pcall(rivet.write, hexaddr(n.addr + G.MB.KIND), le32(0))
         and pcall(rivet.write, hexaddr(n.addr + G.MB.ITEM), le_hex(info.id) .. " " .. le32(cur.currency.count))
         and pcall(rivet.write, hexaddr(n.addr + G.MB.HERO), le32(cur.hero & 0xFFFFFFFF))
         and pcall(rivet.write, hexaddr(n.addr + G.MB.MODE), le32(cur.mode))
  end
  ok = ok and pcall(rivet.write, hexaddr(n.addr + G.MB.REQ), le32(n.seq))          -- last
  if not ok then
    if cur.cb then cur.cb(nil, "cannot write the mailbox") end
    G.native_disable("cannot write its mailbox"); return
  end
  cur.req, cur.asked, cur.pumps = n.seq, G.frame, u32_at(n.addr + G.MB.PUMPS) or 0
  G.aux_busy = cur
end

-- 8.5: takes a request the helper has not answered out of the mailbox (REQ back to DONE), so it
-- can never be carried out later behind the script's back. false when the helper answered it
-- after all (just now, or between the read and the write): that answer stands.
function G.take_back(req)
  local n = G.native
  if not n.addr then return true end
  local done = u32_at(n.addr + G.MB.DONE)
  if done == req then return false end
  if done then
    pcall(rivet.write, hexaddr(n.addr + G.MB.REQ), le32(done))
    if u32_at(n.addr + G.MB.DONE) == req then pcall(rivet.write, hexaddr(n.addr + G.MB.REQ), le32(req)); return false end
  end
  return true
end

-- an aux request the helper has not taken is taken back (a load, or a hook that stopped)
function G.aux_withdraw(why)
  local cur = G.aux_busy
  if not cur then return end
  if not G.take_back(cur.req) then return end     -- answered: aux_poll reads it
  G.aux_busy = nil
  if cur.cb then cur.cb(nil, why) end           -- currency stays first in its queue
  log("aux request withdrawn:", why)
  return true
end

local function aux_poll()
  local cur, n = G.aux_busy, G.native
  if u32_at(n.addr + G.MB.DONE) ~= cur.req then
    if G.frame >= cur.asked + G.AUX_WAIT then
      local pumps = u32_at(n.addr + G.MB.PUMPS) or 0
      local ready = false
      pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
      if pumps == cur.pumps and not ready then cur.asked = G.frame; return end      -- loading: wait
      if not G.aux_withdraw("the helper did not answer") then return end
      if pumps == cur.pumps then G.native_disable("its hook is not running") else G.native_soft_off("it did not pick up the request") end
    end
    return
  end
  G.aux_busy = nil
  local result = u32_at(n.addr + G.MB.RESULT)
  if cur.kind == 7 then
    local ok, text = pcall(rivet.read, hexaddr(n.addr + G.MB.OBJECT), 8)
    local obj = ok and text and qword_from_text(text)
    if result == 11 and obj and obj ~= "0000000000000000" then cur.cb(obj) else cur.cb(nil, "helper result " .. tostring(result)) end
    return
  end
  local s, c = S(), cur.currency
  if result == 1 then
    if s and s.currency_queue and s.currency_queue[1] == c then table.remove(s.currency_queue, 1) end
    s.currency_given = (s.currency_given or 0) + 1
    changed()
    log("currency sent:", c.count, c.item, "(" .. tostring(c.why) .. ")")
    say(string.format("+%d %s", c.count, name(c.item)))
  elseif result == 2 then
    log("currency: no target right now, will retry", c.item, c.count)
    G.currency_hold = G.frame + G.SILENT_HOLD
  else
    if s and s.currency_queue and s.currency_queue[1] == c then table.remove(s.currency_queue, 1) end
    changed()
    log("currency refused (" .. tostring(result) .. "):", c.item, c.count)
    say(string.format("%d %s could not be given (helper result %s) - see rivet.log", c.count, name(c.item), tostring(result)))
    if result == 3 then G.native_disable("the game faulted in the helper") end
  end
end

function G.aux_tick()
  if G.aux_busy then local ok, err = pcall(aux_poll); if not ok then log("aux:", tostring(err)); G.aux_busy = nil end; return true end
  if not (G.busy or G.mission_busy) and G.native_ready() then
    local s = S()
    -- config lookups first (rare); currency only when no item is waiting, so items never wait
    -- behind a row of Bolts and Raritanium gifts
    local want = #G.aux_queue > 0 or (s and s.currency_queue and #s.currency_queue > 0 and G.frame >= (G.currency_hold or 0)
                                      and #G.pending(false) == 0)
    if want then
      local ready = false
      pcall(function() ready = rivet.scene_ready() and rivet.hero() ~= nil end)
      if ready and G.game_running() and G.frame >= (G.settle_until or 0) then
        local ok, err = pcall(aux_start)
        if not ok then log("aux start:", tostring(err)); G.aux_busy = nil end
        return G.aux_busy ~= nil
      end
    end
  end
  return false
end

-- probe: give one item through the borrowed node found by the census (NUMPAD9, then NUMPAD8)
function G.probe_donor_grant(item)
  if G.busy then return false, "a grant is still in progress" end
  if not (G.node and G.node.kind == "donor") then return false, "no donor yet - NUMPAD9 first" end
  if not ITEMS[item] then return false, "unknown item " .. tostring(item) end
  return G.send_donor(item, true)
end

function G.status_text()
  local c = G.counts()
  if c.queued + c.sent + c.confirmed + c.failed + c.owned == 0 then return nil end
  local t = string.format("in inventory %d", c.confirmed + c.owned)
  local waiting = c.queued + c.sent
  if waiting > 0 then
    t = t .. string.format(", waiting %d", waiting)
    local names = {}
    for item, r in pairs((S() or {}).real or {}) do
      if r.status == "queued" or r.status == "sent" then names[#names + 1] = name(item) end
    end
    table.sort(names)
    if #names <= 3 then t = t .. " (" .. table.concat(names, ", ") .. ")" end
  end
  if c.failed > 0 then t = t .. string.format(", probably owned %d", c.failed) end
  local q = (S() or {}).currency_queue
  if q and #q > 0 then t = t .. string.format(", %d Bolts/Raritanium gift(s) waiting", #q) end
  return t
end

-- ---- wiring ------------------------------------------------------------------------------
local function on(class, fn)
  local ok, err = pcall(rivet.on_event, class, function(ev) local ok2, e2 = pcall(fn, ev.fields or {}); if not ok2 then log(class, tostring(e2)) end end)
  if not ok then log("cannot subscribe", class, tostring(err)) end
end
on("GadgetItemAddedEvent", function(f) if f.ConfigTypeHash then G.confirm_event("gadget", f.ConfigTypeHash) end end)
on("WeaponAddedEvent", function(f) G.on_weapon_added(f.WeaponType) end)
on("InventoryChangedEvent", function(f)
  G.inv_changed_frame = G.frame
  -- experimental pickups (Raritanium, weapon upgrades) report nothing else
  if G.busy and G.busy.kind == "pickup" then finish(true) end
end)
on("UserEquippedWeaponEvent", function(f) G.on_weapon_name(f.WeaponName, "equipped") end)
on("PurchaseWeaponEvent", function(f) G.on_weapon_name(f.WeaponName, "bought") end)
on("PlanetChangedEvent", function(f) G.on_planet_change(f.NewPlanetName) end)
on("LevelLoadedEvent", function() G.on_planet_change(nil) end)
pcall(rivet.on_frame, function() local ok, err = pcall(G.on_frame); if not ok then log("frame:", tostring(err)) end end)
log("loaded:", G.enabled and "on" or "off", G.weapons and "(weapons and gadgets)" or "(gadgets only)",
    G.donor_route and "+ borrowed-node route" or "")
pcall(G.native_probe)
