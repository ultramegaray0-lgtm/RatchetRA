-- Rift Apart Randomizer dev 10.27: ENEMY RANDOMIZER (regular enemies). OPTIONAL.
--
-- In the game: the - key turns it ON / OFF (key_enemies; remembered in the save, kept over a New Game).
-- Ctrl+- shows what it changed on this level. The setting enemy_randomizer in 04_rando_settings.lua only decides
-- the start for a save that never used the key.
--
-- What it does (dev 10.27, the method your game proved in round37): before a spawner runs, the enemy template in its
-- script variable is replaced by another regular enemy's template that is loaded on this level - a SunsetSpawnerFactory's
-- "Templates" (the arena waves: proven), a SpawnerScriptAction's "Template" (one actor) or its actor GROUP (robomutt /
-- thug waves: not yet seen working in the game - verified on the first spawn and switched off for the session if the
-- game ignores it). The encounter's own spawner spawns, counts and completes them, so doors, objectives, waves and the
-- story advance as before. Walkers become walkers, flyers flyers, turrets turrets. It never touches boss-tier enemies
-- (large bots, anything with a health bar), story bosses, friendly bots, NPCs, mounts or props, and never an enemy
-- that is not spawned by a spawner (enemies placed in the level). Every change is put back on a checkpoint load, a
-- level change, the - key, and when a changed encounter looks stuck or was retried 5 times (16_rando_spawners.lua,
-- section SP.V). Needs rando_give.dll v7 (the kit's) in the game folder; it says so on screen if it cannot work.
--
-- dev 10.30: COMBAT COMPATIBILITY. Round40 showed a replacement that spawned and could not be killed (pirate robot
-- shooters from a bladeball factory). A replacement is now used only when its PAIR (spawner kind, original enemy,
-- replacement) has in-game evidence that it dies (enemy_compat = "verified", the default); every replaced bot is
-- watched, and a pair whose bots stay alive through a fight is rejected and its spawners put back at once
-- (16_rando_spawners.lua, "COMBAT COMPATIBILITY"; docs/ENEMY_RANDOMIZER_COVERAGE.md has the table).
--
-- dev 10.31: EVERY ENEMY TYPE (enemy_compat = "all", the dev kit's default). Round41 changed only Zurkon A1: the other
-- challenges were kept by "no combat-verified replacement here", "no other flyer kind known on this level" and
-- "already spawned on this level", and every Nefarious trooper was "friendly" (bot class GameBotShooterNoFiring). Now
-- any regular enemy can replace any other (walkers, flyers and turrets mix), spawners change after their first spawn,
-- and the troopers are enemies. Only a pair the game showed cannot be killed stays out (16_rando_spawners.lua).
--
-- dev 10.32: round42 (10.31 in the game): A1 64 of 70 replaced and every one died; Zurkon C5 and B3 replaced bots could
-- not be killed - each a pirate robot shooter (a walker) at a flyer's spawn (Nefarious sniper, biker), and the wave
-- waited on them. Walkers, flyers and turrets stay apart again (enemy_mix_movement = false), and a replaced bot alive
-- 40 s while nothing on the level dies is put back (the combat watch's "6 other deaths" never came). Cordelion only had
-- Nefarious troopers loaded: Ctrl+- and the level's first note say so; zones that stream in later are searched for the
-- save's other enemy kinds, and picks are spread over every kind loaded.
--
-- dev 10.33: round43 (10.32 in the game): A1 61 of 70, C5 15 of 17 and B3 21 of 51 replaced, every replaced bot killed -
-- but pirates became pirates, Nefarious became Nefarious and goons became goons (only that was loaded there), so you
-- saw no change. Cordelion had amoeboids and puffoids loaded, but a new kind was only learned when one spawned: they
-- were planned 2 minutes in and no fight used them. Now: a built-in registry knows every enemy template the logs named
-- (a new save or a public player gets them from the first fight); the pirate robot shooter is never a replacement (never
-- killed as one in five rounds); bots gone soon after spawning and bolts picked up count as kills; a change made after a
-- factory started stays for its next wave instead of being put back as FAILED.
--
-- Needs 16_rando_spawners.lua. Removing this file only removes the enemy randomizer.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["enemy"] = "10.0.23"   -- the kit check (10_rando_runtime.lua)

RANDO_ENEMY = RANDO_ENEMY or {}
local E = RANDO_ENEMY
local R = RANDO
local SP = RANDO_SPAWNERS

local function log(...) pcall(rivet.log, "[rando]", "RANDO-ENEMY", ...) end

if not (R and R.config) then return end
if not SP then
  log("16_rando_spawners.lua is not installed: the enemy randomizer stays off")
  return
end

E.client = SP.register({ name = "enemy", role = "enemy", label = "Enemy Randomizer", state_key = "enemy_rando",
                         config_key = "enemy_randomizer", unique = false,
                         route = (R.config.enemy_route ~= "census") and "vars" or nil })

function E.enabled() return SP.enabled(E.client) end
function E.set(on, why) return SP.set(E.client, on, why) end
function E.toggle(why) return SP.toggle(E.client, why) end

function E.status_text()
  if not E.enabled() then return nil end
  if E.client.route ~= "vars" then
    local st = SP.client_status(E.client)
    return string.format("enemies ON (%d changed here, %d known)", st.slots, st.learned)
  end
  local st = SP.V.status()
  return string.format("enemies ON (%d spawner(s) changed here, %d enemy kind(s) known)", st.changed, st.known)
end

function E.key()
  if not (RANDO_SEED and R.state) then
    R.say("Randomizer: the seed is still being prepared", { type = "corner", duration = 3 }); return
  end
  if R.ctrl_down() and E.client.route ~= "vars" then
    local st = SP.client_status(E.client)
    R.say(string.format("Enemy Randomizer %s: %d enemy slot(s) changed in %d encounter(s) here", E.enabled() and "ON" or "OFF",
                        st.slots, st.encounters),
          { type = "corner", sub = string.format("%d regular enemy type(s) learned, %d encounter(s) kept original", st.learned, st.blocked),
            duration = 6 })
    return
  end
  if R.ctrl_down() then
    local st = SP.V.status()
    -- dev 10.32: which species the replacements can come from here (round42: Cordelion had Nefarious troopers only)
    local sp = st.species or {}
    local loaded = (#sp == 0) and "no enemy kind learned here yet"
                   or (#sp == 1) and ("only " .. sp[1] .. " are loaded here (another planet's enemies are not)")
                   or ("loaded here: " .. table.concat(sp, ", "))
    -- dev 10.29: what happened to this level's enemy spawns, first
    R.say(string.format("Enemy Randomizer %s: %d of %d enemy spawn(s) here were replaced", E.enabled() and "ON" or "OFF",
                        st.replaced, st.spawns),
          { type = "corner", sub = string.format("%s; %d spawner(s) changed now; %d kind(s) here%s; combat: %d pair(s) verified, %d rejected (%s)",
                                                 loaded, st.changed, st.kinds,
                                                 st.top_reason and ("; most kept: " .. st.top_reason) or "",
                                                 st.pairs_verified or 0, st.pairs_rejected or 0, tostring(st.compat)), duration = 8 })
    return
  end
  E.toggle(R.key("key_enemies"))
end
R.bind_key(R.config.key_enemies, E.key, "key_enemies")
log("installed (" .. (E.enabled() and "ON" or "OFF") .. " until the save says otherwise) - " .. R.key("key_enemies") ..
    " turns it on / off, " .. R.key("key_enemies", true) .. " shows what it changed")
