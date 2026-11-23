# Requirements: v0.70

| Component | Version | Where | Bundled? |
|---|---|---|---|
| Ratchet & Clank: Rift Apart | Steam, v3.630.1.0 (`RiftApart.exe` file version 3.0630.1.0) | Steam | No |
| Windows | 10 or 11, 64-bit | — | — |
| rivet_hook (mod loader) | 2.0.1; 2.0.0 also works | https://github.com/neptuwunium/rivet_hook/releases (source: https://codeberg.org/neptuwunium/rivet_hook) | **No. Required.** Another author's project (EUPL-1.2); install it yourself |
| Windows PowerShell | 5.1 (part of Windows); PowerShell 7 also works | already installed | — |
| `rando_give.dll` | v7 (SHA-256 `8055703e…54640744`) | in the player ZIP | Yes. **Required**: it puts rewards into your inventory; the Enemy Randomizer needs v7 |
| The companion (`rando_companion`) | v0.70 | in the player ZIP | Yes. **Required** with the default random seed; it saves your progress |
| `15_rando_hub.lua` | v0.70 | in the player ZIP | Yes. Optional: planet shuffle and the trip back to the hub |
| `16_rando_spawners.lua` + `enemy.lua` | v0.70 | in the player ZIP | Yes. Optional: the Enemy Randomizer |
| `17_rando_omega.lua` | v0.70 | in the player ZIP | Yes. Optional: Omega weapons (`omega_weapons`, off by default) |
| `Install-ArsenalRestored.bat` | v0.70 | in the player ZIP | Yes. Optional: installs the rivet_hook version of ARSENAL_RESTORED |
| ARSENAL_RESTORED | any | its own mod page | No. Optional |

## Not supported or not tested

- **Other game versions:** not supported. `rando_give.dll` checks the game's code and does nothing
  if it differs, so most rewards cannot arrive. A game patch needs a randomizer update.
- **Epic Games Store version:** not tested.
- **Steam Deck / Linux (Proton):** not supported.
- **Mod managers (Vortex, Overstrike):** install by hand. Overstrike is still fine for other
  `.stage` mods.
- **Mods that change weapons, the shop, item configs or missions:** may conflict.
