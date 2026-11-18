# Known issues and compatibility: v0.60 (beta)

## Test status: what was checked where

- **Played in the real game** (the developer's PC, development builds of the same code):
  - The Enemy Randomizer in Zurkon arena challenges A1, B3 and C5 (round 44, development build
    dev 10.33). 92 enemies were replaced: 64 died, 28 were killed in ways the game does not report
    as a death, and **none was left alive**. Every challenge completed.
  - `rando_give.dll` v7 (the version in this download) since round 32.
  - Items, shop, armor and planet travel as in earlier releases.
- **Checked by automated tests only** (a game simulator, not the real game):
  - The trip back to Nefarious City **with planet shuffle off** (new in v0.60).
  - Omega weapons' reward and ownership rules.
  - `Install-ArsenalRestored.bat` (its install steps were not run on Windows for this release).
- **Exact game build not confirmed:** the docs name Steam v3.630.1.0. `rando_give.dll` checks the
  game's code itself: if `rivet.log` says `refused this exe`, your build differs. Please report
  your exe's file version (right-click `RiftApart.exe` → Properties → Details).

## Enemy Randomizer

- **Only enemies loaded where you are** can be used. Many fights load one faction only, so a
  pirate becomes another pirate. Enemies of other planets are not possible yet.
- **Some story fights are not changed yet.** On Cordelion's first visit, the enemies spawned
  before the randomizer had read their spawners (round 44: 0 of 45 changed). Arena challenges
  change most enemies (A1: 61 of 71).
- The pirate robot shooter is never used as a replacement (it could not be killed as one).
- If a fight does not end, press **-** (Enemy Randomizer off; every change is put back) and reload
  the checkpoint. Please send `rivet.log`.

## Omega weapons (off by default)

- With `omega_weapons = true`, Omega rewards are placed and recorded correctly, but **the
  randomizer cannot yet set the Omega upgrade in the game**: it has not found the hero's
  inventory in any test so far (`RANDO-OMEGA inventory not found` in `rivet.log`). An Omega found
  before its weapon gives you the weapon; otherwise the reward waits.

## Back to the hub

- With planet shuffle off, the game's story sometimes carries you straight to the next planet.
  If that planet's first visit starts there, you stay; otherwise you are taken back to Nefarious
  City after 12 seconds and fly on with the ship's planet menu.
- Without `scripts\15_rando_hub.lua` you are never taken back.

## Other

- **Spybots and Lorbs** hold no rewards in this release (their pickups are not recognized yet).
- **Starting items during the opening parade:** the game sometimes ignores deliveries during the
  parade. The randomizer retries, so some starting items may arrive only in Nefarious City.
- **Ms. Zurkon's shop can stay unchanged** if the game's vendor data is not found in time. The
  seed's shop weapons are then given to you directly, and the screen says so.
- **Loading an older game save** does not undo randomizer progress. Press Ctrl+0 twice to get your
  items again, and play forward from your latest save.
- **A crash within about 2 seconds of a reward** can repeat a Bolts/Raritanium payment or forget
  that location, because progress is saved every ~2 seconds.
- **Planet shuffle:** if a planet's story will not start or a level misbehaves, press 0 to turn
  planet shuffle off; the game then plays its own way and your items stay randomized.

## Updating from v0.55

- v0.60 makes **different seeds** than v0.55: start a **New Game**.
- Delete every old `*_rando_*.lua` file in `scripts` before copying the new files.
- New in the download: `enemy.lua`, `16_rando_spawners.lua`, `17_rando_omega.lua`, and
  `rando_companion\Install-ArsenalRestored.bat` / `.ps1`. `rando_give.dll` is replaced (v7).

## Compatibility

See [REQUIREMENTS](REQUIREMENTS.md). In short: Steam v3.630.1.0 only, Windows 10/11 64-bit,
rivet_hook 2.0.1. Other game versions make the helper DLL switch itself off. Other rivet_hook
mods should coexist (keep their `[assets] paths` entries in `rivet.toml`). Mods that change
weapons, the shop, enemies or missions may conflict.
