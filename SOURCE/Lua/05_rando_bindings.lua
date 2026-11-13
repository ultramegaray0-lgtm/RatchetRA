-- Trigger bindings: which in-game event completes which randomizer location.
--
-- Mission completions observed in the game live in the model (data/game_model.json,
-- "completion_missions") and are exported with the seed; e.g. MIS_INTRO -> planet:corson_v.
-- This file is for extra or corrected bindings only. Gold Bolt names are still unobserved. Play with discovery on, then copy names from the "RANDO-DISCOVER" lines in
-- rivet.log into these tables. Do not guess: a wrong binding hands out the wrong reward.
--
-- Example of the shape (names below are placeholders, not real game strings):
--   missions    = { ["<MissionName from MissionCompleteEvent>"] = "planet:savali" },
--   bolts       = { ["<BoltName from GainGoldBoltEvent>"]       = "goldbolt:10" },
--   checkpoints = { ["<DestinationCheckpointName>"]             = "savali" },
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["05_rando_bindings"] = "10.0.5"   -- the kit check (10_rando_runtime.lua)
RANDO_BINDINGS = {
  -- PlanetChangedEvent.NewPlanetName -> planet id, for names observed after the model was frozen
  -- (adding them to the model would change every seed's fingerprint)
  -- observed in PlanetChangedEvent.NewPlanetName (rounds 8-9, a save with every planet unlocked)
  planets = { Savali = "savali", Blizar = "blizar_prime", Cordelion = "cordelion",
              Viceron = "viceron", Zurkon = "scarstu" },   -- Zurkon: inferred (internal code "zurkons")
  -- mission name prefix -> planet (from the mission names in your dag). Any story mission of
  -- that planet finishing completes the planet for the randomizer.
  mission_prefixes = {
    MIS_INTRO = "corson_v", MIS_MEGA = "corson_v", MIS_MALINON = "corson_v",
    MIS_NEFCITY = "nefarious_city",
    MIS_SARG = "sargasso", MIS_SARGASSO = "sargasso",
    MIS_ZURK = "scarstu", MIS_ZURKON = "scarstu", MIS_ZURKONS = "scarstu",
    MIS_SAV = "savali", MIS_SAVALI = "savali", MIS_SVLI = "savali",
    MIS_BLIZAR = "blizar_prime",
    MIS_MOL = "torren_iv", MIS_MOLONOTH = "torren_iv",
    MIS_CORD = "cordelion", MIS_CORDELION = "cordelion",
    MIS_ARD = "ardolis",
    MIS_ZORD = "viceron", MIS_ZORDOOM = "viceron", MIS_ZRD = "viceron",
  },
  missions = {},
  bolts = {},
  checkpoints = {},
  -- collectibles: once rivet.log shows the event a pickup sends, bind it here, e.g.
  --   spybot = { class = "<EventClassName>" },  (optional: field = "Name", value = "...")
  -- Each event then completes the next "Spybot found #n" location (experimental_collectibles).
  collectible_events = {},
}
