-- Ratchet & Clank: Rift Apart Randomizer LITE - your settings.
--
-- The Lite package is the try-it-first version: Lua scripts only. No companion app, no DLL, nothing to
-- run but the game. Edit with Notepad, save, then restart the game. Changing the seed or any option
-- below makes a NEW seed: start it with New Game. Lines starting with -- are notes. A wrong value is
-- reported in rivet.log (search RANDO-SETTINGS) and the default is used instead.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["04_rando_settings"] = "10.0.39"   -- version check (do not edit)
RANDO_SETTINGS = {
  -- THE SEED: any text. The same text gives the same randomization on every PC, so you can share it.
  -- Lite cannot pick a random seed for you (that needs the companion of the full release): change
  -- this text to get a different game, e.g. "lombax-ryno-2026".
  seed = "rift-lite-test",

  -- PRESET: balanced (default) | full | chaos (1 starting weapon, no gadget) | everything
  preset = "balanced",

  -- THE LITE PACKAGE (do not change: these keep Lite working without the companion and the DLL)
  lite = true,                         -- starts at once, fixed seed, no planet shuffle (it needs the DLL)
  bank_rewards = false,                -- every reward pays at once (nothing waits for Coordinates)
  spoiler_log = true,                  -- the seed's spoiler is written into rivet.log (search RANDO-SPOILER);
                                       -- set false if you do not want it there
  shop_runtime = false,                -- Ms. Zurkon's screen cannot be changed without the DLL: she sells her own
                                       -- weapons as usual
  restored_weapons = false,            -- ARSENAL_RESTORED's weapons need the companion's check (full release)

  -- WHERE ITEMS GO
  distribution = "goldbolts_first",    -- "goldbolts_first": every Gold Bolt gives one item
                                       -- "spread": items spread over Gold Bolts, missions, side activities
  -- early_weapons = 2,                -- 0-6: weapons placed where you can reach them right at the start
  -- story_milestones = true,          -- each planet's second story mission gives a reward
  -- side_locations = true,            -- Zurkie's cups, Trudi, the Blizar chef and Ardolis give rewards
  -- collectibles = true,              -- the 10 Spybots and 12 Lorbs give rewards when you pick them up

  -- WHAT IS RANDOMIZED
  -- weapons = true,                   -- weapons are rewards (Ms. Zurkon still sells hers: buy one early and
                                       -- its reward later says you already have it)
  shop = "shuffle", shop_weapons = 0,  -- (Lite) every one of Ms. Zurkon's weapons is ALSO a reward somewhere
  shop_bonus = false,                  -- (Lite) her bonus items need the DLL
  -- gadgets = true,                   -- Box Breaker, Omniglove and Glitch are rewards
  armor = false,                       -- (Lite) armor pieces need the DLL: armor pods keep their own pieces
  omega_weapons = false,               -- (Lite) Omega weapons need the DLL
  weapon_xp = false,                   -- (Lite) weapon XP needs the DLL
  -- exclude = "",                     -- items never randomized, e.g. "weapon:ryno_8"

  -- YOUR START (Hoverboots and Map-O-Matic are always included)
  -- start_weapons = 2,                -- 0-4 random weapons
  -- start_gadgets = 1,                -- 0-2 random gadgets
  -- start_items = "",                 -- items you always start with, e.g. "weapon:enforcer,glitch"
  -- start_bolts = 0,                  -- 0-100000 (Lite: given again in every game session - keep 0)
  -- start_raritanium = 0,             -- 0-5000 (Lite: given again in every game session - keep 0)

  -- BOLTS AND RARITANIUM (a reward location without an item gives one of these)
  -- bolts = true,
  -- raritanium = true,
  -- bolts_min = 1000, bolts_max = 10000,         -- per reward (100-100000)
  -- raritanium_min = 120, raritanium_max = 1000,  -- per reward (1-5000)
  -- bolts_budget = 150000,            -- the most all Bolts rewards give together (0 = no limit)
  -- raritanium_budget = 2000,         -- the most all Raritanium rewards give together (0 = no limit)

  -- LOGIC
  -- weapon_logic = "none",            -- "none" | "light" | "standard": weapons expected before later planets
  -- accessibility = "full",           -- "full": every location reachable | "beatable": only what finishing needs

  -- BACK TO THE HUB: after you finish a planet's story you are taken back to Nefarious City (that is
  -- also where Lite hands your rewards over). Flying on with the planet menu before the countdown
  -- ends cancels it.
  -- hub_auto_return = true,           -- false: never taken back
  -- hub_return_delay = 12,            -- seconds before the trip back
}
-- In the game: Ctrl+0 pressed twice sends your randomizer items again if some went missing.
