-- Randomizer 3.2: what the runtime may CHANGE in your game. Every "true" here must come from a
-- real game session: tools/build_capabilities.py writes this file from the lab's rivet.log
-- (docs/CAMPAIGN.md, "The in-game tests"). Nothing is verified yet, so campaign modes fall back
-- to the game's own order. (Reading mission states needs no entry: it only reads, and checks
-- itself at run time.)
--
-- After the lab, this file looks like:
--   mission_read = { verified = true },
--   mission_control = { verified = true, backend = "native" },   -- rando_give.dll v4
--   travel = { verified = true },
--   new_game_init = { verified = true },
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["06_rando_capabilities"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)
RANDO_CAPABILITIES = {
  source = nil,
  mission_read = { verified = false },
  mission_control = { verified = false, backend = "native" },
  travel = { verified = false },
  new_game_init = { verified = false },
}
