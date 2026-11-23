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
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["05_rando_bindings"] = "10.0.39"   -- the kit check (10_rando_runtime.lua)
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
  -- v0.62-DEV5: from the game's own type data (neptuwunium/rivet Rivet.DDL.RCRA): a Spybot is a "RYNO plan"
  -- (UICollectibleTypeRynoPlan: "Dialogue line for this spybot"; enum 0x81D3E717 = the 10 plans NefCity_01 ...
  -- Zordoom_01) and its pickup sends RYNOPlayPickedUpEvent { RynoId } (RYNOScriptPickupEvent { RynoId } for a scripted
  -- one). A Lorb is a "Ruin token" (enum 0xECCC3486 = Lorb_01 ... Lorb_12): RuinPlayPickedUpEvent { RuinId }.
  -- The id makes one pickup pay once, whichever of the events comes. NOT seen in a rivet.log yet: the first pickup
  -- logs "RANDO-DISCOVER RYNOPlayPickedUpEvent ..." and "RANDO-COLLECTIBLE spybot <id>".
  -- round54: "events subscribed 23/23", so these three classes exist in your game (rivet_hook marks a missing class
  -- dead and the count would be short). v0.71-DEV1: a Lorb picked up by a script may send RuinScriptPickupEvent, as a
  -- scripted Spybot does; it is bound too (a class the game does not have is skipped and listed at the start).
  collectible_events = {
    spybot = { classes = { "RYNOPlayPickedUpEvent", "RYNOScriptPickupEvent" }, id_field = "RynoId" },
    lorb = { classes = { "RuinPlayPickedUpEvent", "RuinScriptPickupEvent" }, id_field = "RuinId" },
  },
  -- v0.71-DEV1: event classes WATCHED ONLY (logged, never paid): names a collectible pickup might send. At the start
  -- rivet.log lists which of them your game has ("RANDO-COLLECTIBLE event classes ..."), and the first of each that
  -- fires is logged with its fields - the evidence a binding above needs. Nothing here hands out a reward.
  collectible_watch = { "CraiggerbearPickedUpEvent", "CraiggerBearPickedUpEvent", "CollectiblePickedUpEvent",
                        "CollectibleCollectedEvent", "CollectibleFoundEvent", "GainCollectibleEvent",
                        "PickupCollectedEvent", "RYNOPlanCollectedEvent", "RuinTokenCollectedEvent" },
}
