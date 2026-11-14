# Known issues and compatibility: v0.55

## Test status

- v0.55's changes are **checked by automated tests only** (a game simulator; 419 tests, plus a
  package validator). v0.55 has **not yet been played in the real game.** The randomizer logic
  it is built on was played in the game as v0.54.
- Only one Windows PC and one game install have been used in development.
- **Exact game build not confirmed:** the docs name Steam v3.630.1.0, but the development logs
  do not record the `RiftApart.exe` file version, and on that install rivet_hook printed
  `game version mismatch, invalidating pointers` while the randomizer still worked.
  `rando_give.dll` checks the game's code itself: if `rivet.log` says `refused this exe`, your
  build differs. If you see that, please report your exe's file version (right-click
  `RiftApart.exe` → Properties → Details).

## Known issues

- **Starting items during the opening parade:** the game sometimes ignores deliveries during the
  parade. The randomizer retries on the next planet, so some starting items may arrive only
  after you reach Nefarious City.
- **Ms. Zurkon's shop can stay unchanged** if the game's vendor data is not found in time. The
  seed's shop weapons are then given to you directly, and the screen says so.
- **Loading an older game save** does not undo randomizer progress. Press Ctrl+0 twice to get your
  items again, and play forward from your latest save.
- **A crash within about 2 seconds of a reward** can repeat a Bolts/Raritanium payment or forget
  that location, because progress is saved every ~2 seconds.
- **Planet shuffle:** if a planet's story will not start or a level misbehaves, press 0 to turn
  planet shuffle off; the game then plays its own way and your items stay randomized.

## Compatibility

See [REQUIREMENTS](REQUIREMENTS.md). In short: Steam v3.630.1.0 only, Windows 10/11 64-bit,
rivet_hook 2.0.1. Other game versions make the helper DLL switch itself off. Other rivet_hook
mods should coexist (keep their `[assets] paths` entries in `rivet.toml`). Mods that change
weapons, the shop or missions may conflict.

## Updating from v0.54

v0.55 makes the same seeds as v0.54 for the same settings, and v0.54 progress files still load.
Differences you will notice:

- Planet shuffle is now **off by default**. If you used it in v0.54, press 0 to turn it back on.
- `0` and `Ctrl+0` are the only keys. The v0.54 keys `]`, `[`, `/`, `;` and the F keys are gone.
- Delete every old `*_rando_*.lua` file before copying the new ones. A leftover
  `16_rando_testtravel.lua` is reported in `rivet.log`.
