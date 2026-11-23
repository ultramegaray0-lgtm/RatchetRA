# Lite package: v0.75

The Lite download (`Ratchet_Rift_Apart_Randomizer_v0.75_Lite_NexusMods.zip`) is the try-it-first version: Lua scripts
only, **no `rando_give.dll` and no companion**. Its `GAME_FOLDER` is assembled from this repository:

| In the Lite ZIP | From |
|---|---|
| `GAME_FOLDER/scripts/` (13 files) | `SOURCE/Lua/*.lua` except `16_rando_spawners.lua`, `enemy.lua`, `17_rando_omega.lua` and `04_rando_settings.lua` |
| `GAME_FOLDER/scripts/04_rando_settings.lua` | `SOURCE/Lite/04_rando_settings.lua` (`lite = true`, a fixed seed) |
| `GAME_FOLDER/rivet.toml` | `SOURCE/Lite/rivet.toml` (loads no DLL, opens no bridge) |

The scripts are the same files as the full release; `lite = true` in the settings switches them to the Lite behaviour:
no waiting for the companion, every reward pays at once, the spoiler goes into `rivet.log`, no planet shuffle. Rewards
reach your inventory through the game's own `AddToInventoryAction` level-script nodes on Nefarious City. See
[DOCUMENTATION/LITE.md](../../DOCUMENTATION/LITE.md).
