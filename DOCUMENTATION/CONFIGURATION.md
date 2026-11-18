# Configuration: v0.60

## Settings file

Open `scripts\04_rando_settings.lua` in the game folder with Notepad. Lines that start with `--`
are notes or switched-off options: remove the `--` to use one, then edit the value. Save and
restart the game.

**Changing the seed or any option makes a new seed. Start it with New Game.** A wrong value is
written to `rivet.log` (search `RANDO-SETTINGS`) and the default is used.

| Setting | Default | Values |
|---|---|---|
| `seed` | `"random"` | `"random"` (the companion picks and remembers one) or any text for a fixed, shareable seed |
| `preset` | `"balanced"` | `balanced`, `full` (bigger Bolts rewards, smaller Raritanium), `chaos` (1 start weapon, no start gadget, shop prices 25-300%), `everything` (shop prices 50-200%, 2,500 Bolts and 25 Raritanium at the start) |
| `distribution` | `"goldbolts_first"` | `"goldbolts_first"`: every Gold Bolt gives an item. `"spread"`: items anywhere |
| `shop_weapons` | `8` | 0-15 weapons Ms. Zurkon sells; the rest become rewards |
| `early_weapons` | `2` | 0-6 weapons placed where you can reach them at the start |
| `story_milestones` | `true` | each planet's second story mission gives a reward |
| `side_locations` | `true` | Zurkie's cups, Trudi, the Blizar chef and Ardolis give rewards |
| `weapons` | `true` | shuffle weapons |
| `collectibles` | `false` | Spybots and Lorbs hold no rewards in v0.60 (their pickups are not recognized yet) |
| `restored_weapons` | `"auto"` | ARSENAL_RESTORED's weapons: `"auto"` (only if installed), `false` |
| `gadgets` | `true` | Box Breaker, Omniglove and Glitch are rewards |
| `armor` | `true` | armor pieces are rewards |
| `shop` | `"shuffle"` | `"shuffle"` or `"vanilla"` (her usual weapons) |
| `exclude` | `""` | items never randomized, e.g. `"weapon:ryno_8,armor:pirate_head"` |
| `omega_weapons` | `false` | `true`: the 20 Omega versions (Challenge Mode / New Game+) become rewards. **Beta**: the Omega upgrade itself is not applied in the game yet ([KNOWN_ISSUES](KNOWN_ISSUES.md)) |
| `start_weapons` | `2` | 0-4 random starting weapons |
| `start_gadgets` | `1` | 0-2 random starting gadgets |
| `start_items` | `""` | items you always start with, e.g. `"weapon:enforcer,glitch"` |
| `start_bolts`, `start_raritanium` | `0`, `0` | 0-100000, 0-5000 |
| `bolts`, `raritanium` | `true` | rewards without an item give Bolts / Raritanium |
| `bolts_min`, `bolts_max` | `1000`, `10000` | per reward |
| `raritanium_min`, `raritanium_max` | `120`, `1000` | per reward |
| `bolts_budget`, `raritanium_budget` | `150000`, `2000` | the most all rewards give together (0 = no limit) |
| `shop_prices` | `"weapon"` | `"vanilla"`, `"weapon"` (the new weapon's price), `"percent"`, `"random"` |
| `shop_price_percent`, `shop_price_max_percent` | `100`, `150` | used by `"percent"` and `"random"` |
| `weapon_logic` | `"none"` | `"none"`, `"light"`, `"standard"`: weapons expected before later planets |
| `accessibility` | `"full"` | `"full"`: every location reachable; `"beatable"`: only what finishing needs |
| `coords_first_visit` | `true` | planet shuffle: Coordinates always open a planet's first visit |
| `hub_auto_return` | `true` | after a planet's story you are taken back to Nefarious City (planet shuffle on **and** off) |
| `hub_return_delay` | `12` | seconds before that trip |
| `enemy_randomizer` | `true` | the Enemy Randomizer at the start of a save that never used the `-` key |
| `enemy_notify` | `false` | `true`: a corner note for every changed spawner's first enemy |
| `enemy_compat` | `"all"` | `"all"`: every regular enemy loaded on the level can become every other; `"verified"`: only replacements already seen dying in the game |
| `enemy_mix_movement` | `false` | keep walkers, flyers and turrets apart (mixing them made unkillable enemies) |

The Hoverboots and the Map-O-Matic are always part of your start.

## In-game keys

| Key | What it does |
|---|---|
| `0` | Planet shuffle on / off (off by default; remembered, also over a New Game) |
| `Ctrl+0` twice | Send every randomizer item you own again (lost ones come back) |
| `-` | Enemy Randomizer on / off (on by default; remembered) |
| `Ctrl+-` | What the Enemy Randomizer changed where you are |

No other key does anything.

## Planet shuffle

- **Off (default):** the game's normal story order with randomized items. Rewards on a planet
  wait until you hold its Coordinates.
- **On:** after the opening parade of a New Game, you go to Nefarious City, the hub. Planets open
  as you find their Coordinates; fly to them with the ship's planet menu. Turned on after the
  parade, it starts with your next New Game.
- Needs `scripts\15_rando_hub.lua`. Without that file, `0` does nothing.

## Back to the hub (v0.60)

A finished planet takes you back to Nefarious City after `hub_return_delay` seconds, **with planet
shuffle on and off**. With it off, the game's own order goes on from there: fly on with the ship's
planet menu. No trip is made when:

- the planet's story was on Nefarious City itself, or it was the opening parade or the finale;
- you fly on yourself with the planet menu before the countdown ends;
- the game's own story carries you straight into a new planet's first visit (it plays there).

With planet shuffle off, the randomizer switches planetary travel on at the hub only if the game
has it off (so the ship can leave), and gives it back when one of Nefarious City's own stories
starts. It never unlocks planets in the ship's menu: the game's order stays.

## Enemy Randomizer (v0.60)

Regular enemies spawned by the level's spawners become other regular enemies **loaded on the same
level** (walkers stay walkers, flyers flyers, turrets turrets). Bosses, story bosses, friendly bots,
NPCs and mounts are never changed. Every replaced enemy is watched: a replacement that the fight
shows cannot be killed is put back, and that pair is never used again in your save. Needs
`scripts\16_rando_spawners.lua`, `scripts\enemy.lua` and `rando_give.dll` v7.

## Seeds and spoilers

- Random seed: `rando_companion\randomizer_saves\random_seed.txt` (delete it for a new seed).
- Progress: `rando_companion\randomizer_saves\`.
- Spoiler log: `rando_companion\randomizer_saves\spoilers\`.
