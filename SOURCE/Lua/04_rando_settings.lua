-- Ratchet & Clank: Rift Apart Randomizer - your settings.
--
-- Edit with Notepad, save, then restart the game. Changing the seed or any option below makes a
-- NEW seed with its own progress: start it with New Game. Lines starting with -- are notes; to
-- change an option, remove the -- in front of it and edit the value. A wrong value is reported in
-- rivet.log (search RANDO-SETTINGS) and the default is used instead.
RANDO_FILES = RANDO_FILES or {}; RANDO_FILES["04_rando_settings"] = "10.0.35"   -- version check (do not edit)
RANDO_SETTINGS = {
  -- THE SEED: "random" = the companion picks one and remembers it. Any other text is a fixed seed
  -- (the same text and settings give the same seed on every PC), e.g. "lombax-ryno-2026".
  seed = "random",

  -- PRESET: the starting point for every option below.
  --   balanced    the defaults shown below
  --   full        bigger Bolts rewards (up to 15,000), smaller Raritanium rewards (up to 250)
  --   chaos       1 starting weapon, no starting gadget, shop prices 25-300%, wide currency swings
  --   everything  shop prices 50-200%, start with 2,500 Bolts and 25 Raritanium, bigger rewards
  preset = "balanced",

  -- WHERE ITEMS GO
  distribution = "goldbolts_first",    -- "goldbolts_first": every Gold Bolt gives one item
                                       -- "spread": items spread over Gold Bolts, missions, side activities, armor pods
  -- shop_weapons = 8,                 -- 0-15: weapons Ms. Zurkon sells; her other slots close and those weapons become rewards
  -- early_weapons = 2,                -- 0-6: weapons placed where you can reach them right at the start
  -- story_milestones = true,          -- each planet's second story mission gives a reward
  -- side_locations = true,            -- Zurkie's cups, Trudi, the Blizar chef and Ardolis give rewards
  collectibles = false,                -- Spybots and Lorbs never hold rewards in this release (their pickups are
                                       -- not recognized yet: a reward placed there could never be collected)

  -- WHAT IS RANDOMIZED
  -- weapons = true,                   -- weapons are shuffled over the shop, your start and the rewards
  restored_weapons = "auto",           -- ARSENAL_RESTORED's 9 weapons: "auto" = only when that mod is installed,
                                       -- false = never (true = always: ONLY if you have that mod)
                                       -- (rando_companion\Install-ArsenalRestored.bat installs that mod)
  -- gadgets = true,                   -- Box Breaker, Omniglove and Glitch are rewards
  -- armor = true,                     -- armor pieces are rewards; armor pods give random items
  -- shop = "shuffle",                 -- "shuffle": Ms. Zurkon sells the seed's weapons | "vanilla": her usual ones
  -- exclude = "",                     -- items never randomized, e.g. "weapon:ryno_8,armor:pirate_head"
  omega_weapons = false,               -- OMEGA WEAPONS (for Challenge Mode / New Game+), OFF by default.
                                       -- true: the 20 Omega versions become rewards of their own. An Omega found
                                       -- first also gives its weapon; the weapon found later never undoes the Omega.
                                       -- v0.70: the Omega upgrade is set in the game itself (seen working in the
                                       -- developer's game). Turning this on makes a different seed (see KNOWN_ISSUES).

  -- YOUR START (Hoverboots and Map-O-Matic are always included)
  -- start_weapons = 2,                -- 0-4 random weapons
  -- start_gadgets = 1,                -- 0-2 random gadgets
  -- start_items = "",                 -- items you always start with, e.g. "weapon:enforcer,glitch"
  -- start_bolts = 0,                  -- 0-100000
  -- start_raritanium = 0,             -- 0-5000

  -- BOLTS AND RARITANIUM (a reward location without an item gives one of these)
  -- bolts = true,
  -- raritanium = true,
  -- bolts_min = 1000, bolts_max = 10000,         -- per reward (100-100000)
  -- raritanium_min = 120, raritanium_max = 1000,  -- per reward (1-5000)
  -- bolts_budget = 150000,            -- the most all Bolts rewards give together (0 = no limit)
  -- raritanium_budget = 2000,         -- the most all Raritanium rewards give together (0 = no limit)

  -- SHOP PRICES
  -- shop_prices = "weapon",           -- "vanilla" | "weapon": a slot costs its new weapon's price
                                       -- | "percent": shop_price_percent of it | "random": between the two percents
  -- shop_price_percent = 100,
  -- shop_price_max_percent = 150,

  -- LOGIC
  -- weapon_logic = "none",            -- "none" | "light" | "standard": weapons expected before later planets
  -- accessibility = "full",           -- "full": every location reachable | "beatable": only what finishing needs
  -- coords_first_visit = true,        -- planet shuffle: Coordinates always open a planet's first visit

  -- BACK TO THE HUB: after you finish a planet's story you are taken back to Nefarious City, with
  -- planet shuffle on AND off (with it off, the game's own order goes on from there: fly on with the
  -- ship's planet menu). Flying on yourself with the planet menu before the countdown ends cancels it.
  -- hub_auto_return = true,           -- false: never taken back
  -- hub_return_delay = 12,            -- seconds before the trip back

  -- ENEMY RANDOMIZER: regular enemies become other regular enemies loaded on the same level.
  -- Bosses, story bosses, friendly bots and NPCs are never touched. A replacement that the game shows
  -- cannot be killed is put back. The - key turns it on or off (remembered by your save); this setting
  -- only decides the start of a save that has never used the key.
  enemy_randomizer = true,
  enemy_notify = false,                -- true: a corner note for every changed spawner's first enemy
  -- enemy_compat = "all",             -- "all": every regular enemy loaded on the level can become every other
                                       -- "verified": only replacements already seen dying in the game (fewer changes)
  -- enemy_mix_movement = false,       -- keep walkers, flyers and turrets apart (mixing them made unkillable enemies)
  -- key_enemies = "-",                -- the Enemy Randomizer's key (Ctrl+key: what it changed here)
}
-- In the game: 0 turns PLANET SHUFFLE on or off (off by default; remembered).
-- The - key turns the ENEMY RANDOMIZER on or off (on by default; remembered). Ctrl+- shows what it changed here.
-- Ctrl+0 pressed twice sends your randomizer items again if some went missing.
