# Known issues and compatibility: v0.75 (beta)

## Test status: what was checked where

- **Played in the real game** (the developer's PC, development builds of the same code; v0.75 is
  the v0.71-DEV9 build with new default settings):
  - Ms. Zurkon's shop sells the seed's weapons (round 62: 19 of 19 slots written and still held 3 s
    later), and a bonus slot whose weapon you already own paid its bonus directly ("you already
    have the Warmonger - Robot Pirate boots is yours").
  - Spybots and Lorbs paid their rewards (round 54).
  - Omega weapons: set in the game and read back (rounds 52-54).
  - The Enemy Randomizer (round 62: 13 of 16 enemies replaced on a Savali fight, all 13 died;
    round 44: Zurkon arena challenges A1, B3, C5).
  - Loads, checkpoint reloads and warps without a crash (rounds 54-62).
  - `rando_give.dll` v7 (the version in this download) since round 32.
- **Checked by automated tests only** (a game simulator, not the real game):
  - The trip back to Nefarious City with planet shuffle off, and the v0.75 fix for planet shuffle
    turned on in the middle of a run.
  - Weapon XP rewards (`weapon_xp = true`, off by default).
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

## Omega weapons (on by default)

- Omega rewards are placed, recorded **and set in the game**. After every load the randomizer
  reads your weapons again before it sets anything: wait a few seconds for **Randomizer: Omega
  ready**. Arena challenges that swap your weapons can delay it.
- `omega_weapons = false` makes a **different seed** from the same seed name.
- Omegas are never placed on Gold Bolts, Spybots or Lorbs.

## Ms. Zurkon's shop

- Her closed slots still show the Burst Pistol you own (that is how the game closes a slot). Buying
  it once hides all of them. `shop_weapons` (up to 15) opens more slots.
- A bonus item rides on the weapon you buy: the vendor screen can only list weapons, so the bonus
  is announced when you talk to her and when you buy.

## Back to the hub

- With planet shuffle off, the game's story sometimes carries you straight to the next planet.
  If that planet's first visit starts there, you stay; otherwise you are taken back to Nefarious
  City after 12 seconds and fly on with the ship's planet menu.
- Without `scripts\15_rando_hub.lua` you are never taken back.

## Other

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

## Updating from v0.75 or v0.60

- v0.75 makes **different seeds** (Omega weapons on, Spybots and Lorbs, the shop's bonus slots):
  start a **New Game**. Replace every file of the `scripts` folder with the new ones.
- Your v0.75 settings file is replaced by the new one: copy your own values over again.

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

## Lite package

See [LITE](LITE.md): what the Lite download (no DLL, no companion) does and does not do.
