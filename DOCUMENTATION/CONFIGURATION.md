# Configuration: v0.55

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
| `restored_weapons` | `"auto"` | ARSENAL_RESTORED's weapons: `"auto"` (only if installed), `false` |
| `gadgets` | `true` | Box Breaker, Omniglove and Glitch are rewards |
| `armor` | `true` | armor pieces are rewards |
| `shop` | `"shuffle"` | `"shuffle"` or `"vanilla"` (her usual weapons) |
| `exclude` | `""` | items never randomized, e.g. `"weapon:ryno_8,armor:pirate_head"` |
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

The Hoverboots and the Map-O-Matic are always part of your start.

## In-game keys

| Key | What it does |
|---|---|
| `0` | Planet shuffle on / off (off by default; remembered, also over a New Game) |
| `Ctrl+0` twice | Send every randomizer item you own again (lost ones come back) |

No other key does anything.

## Planet shuffle

- **Off (default):** the game's normal story order with randomized items. Rewards on a planet
  wait until you hold its Coordinates.
- **On:** after the opening parade of a New Game, you go to Nefarious City, the hub. Planets open
  as you find their Coordinates; fly to them with the ship's planet menu. A finished planet takes
  you back to the hub. Turned on after the parade, it starts with your next New Game.
- Needs `scripts\15_rando_hub.lua`. Without that file, `0` does nothing.

## Seeds and spoilers

- Random seed: `rando_companion\randomizer_saves\random_seed.txt` (delete it for a new seed).
- Progress: `rando_companion\randomizer_saves\`.
- Spoiler log: `rando_companion\randomizer_saves\spoilers\`.
