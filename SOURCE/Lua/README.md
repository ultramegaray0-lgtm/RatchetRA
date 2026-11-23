# Lua scripts: v0.75

These 16 files go into `<game folder>\scripts`. rivet_hook loads them in name order.

| File | Role |
|---|---|
| `01_rando_data.lua` | game database: items, locations, planets |
| `02_rando_generator.lua` | seed generator, progression solver, spoiler log |
| `03_rando_campaign.lua` | mission registry and planet-shuffle destinations |
| `04_rando_settings.lua` | **the player's settings** |
| `05_rando_bindings.lua` | game event names |
| `06_rando_capabilities.lua` | game features verified in testing |
| `09_rando_real.lua` | delivers rewards into the real inventory (with `rando_give.dll`) |
| `10_rando_runtime.lua` | state, rewards, saving, the 0 key, the version check |
| `11_rando_campaign.lua` | mission state reads and calls |
| `12_rando_shop.lua` | Ms. Zurkon's shop |
| `13_rando_armor.lua` | armor sources as reward locations |
| `14_rando_travel.lua` | locked travel and checkpoint names |
| `15_rando_hub.lua` | **optional**: planet shuffle (the Nefarious City hub) and the trip back after each planet |
| `16_rando_spawners.lua` | **optional**: the spawner layer of the Enemy Randomizer |
| `enemy.lua` | **optional**: the Enemy Randomizer (the - key) |
| `17_rando_omega.lua` | **optional**: Omega weapons in the game (`omega_weapons`, on by default since v0.75) |

Files 07 and 08 do not exist in a release: those numbers belonged to developer tools.

The Lite package (no DLL, no companion) uses 13 of these: every file except `16_rando_spawners.lua`, `enemy.lua` and
`17_rando_omega.lua`, with its own `04_rando_settings.lua` from [`SOURCE/Lite`](../Lite).
