# Ratchet & Clank: Rift Apart Randomizer v0.60 (beta)

**Download:** `Ratchet_Rift_Apart_Randomizer_v0.60_Player_Release.zip` (below, under Assets).
This ZIP is everything a player needs. "Source code" archives GitHub adds automatically are the
repository source, not the mod download. Older releases stay on the releases page.

SHA-256 of the ZIP:
`584aab41785646165440b90a5e0429411b00f680c2830a5ae9fd97ccbe55554d`

## Requirements

- Ratchet & Clank: Rift Apart, Steam v3.630.1.0, Windows 10/11 64-bit
- **rivet_hook 2.0.1** (required, not included): https://github.com/neptuwunium/rivet_hook/releases

## Install

1. Back up `Documents\Ratchet & Clank - Rift Apart`.
2. Install rivet_hook into the game folder.
3. Copy everything inside the ZIP's `GAME_FOLDER` into the game folder.
4. Run `rando_companion\Start-Companion.bat`, start the game, choose New Game.

Full guide: `INSTALLATION.md` in the ZIP.

## What's new in v0.60

- **Enemy Randomizer** (on by default). Regular enemies become other regular enemies loaded on the
  same level. Bosses, story bosses, friendly bots and NPCs are never changed. Every replaced enemy
  is watched; a replacement that cannot be killed is put back. **-** turns it on/off, **Ctrl+-**
  shows what it changed.
- **Back to the hub with planet shuffle on AND off.** After a planet's story you are taken back to
  Nefarious City after 12 seconds. With planet shuffle off the game's own order goes on from there
  (fly on with the ship's planet menu). Flying on yourself first cancels it; a new planet's first
  visit that the story starts directly plays where it starts. `hub_auto_return = false` turns it off.
- **Omega weapons** (`omega_weapons`, **off by default, beta**). The 20 Omega versions become
  rewards; an Omega found first also gives its weapon, the weapon found later never takes the Omega
  away, and nothing is given twice. The Omega upgrade itself cannot be applied in the game yet.
- **`Install-ArsenalRestored.bat` is back** in `rando_companion`: drag the ARSENAL_RESTORED (rivet_hook
  version) zip onto it.
- `rando_give.dll` **v7** (needed by the Enemy Randomizer; source in `SOURCE/DLL`, reproducible).
- Spybots and Lorbs hold no rewards (their pickups are not recognized yet).

**Updating from v0.55:** v0.60 makes different seeds - start a **New Game**. Delete every
`*_rando_*.lua` file in `scripts` first, then copy the new files (`enemy.lua`, `16_rando_spawners.lua`
and `17_rando_omega.lua` are new; `rando_give.dll` is replaced).

## Test status

- **Real game** (development builds of this code, the developer's PC): the Enemy Randomizer in Zurkon
  arena challenges A1, B3 and C5 - 92 enemies replaced, none left alive, every challenge completed;
  `rando_give.dll` v7 since round 32.
- **Automated tests only** (a game simulator; 842 tests, 0 failures, plus a 32-check package
  validator): the trip back with planet shuffle off, Omega rules, the ARSENAL_RESTORED launcher's
  file handling. Not yet played in the real game.

## Known issues

- The Enemy Randomizer can only use enemies loaded where you are (often one faction), and some story
  fights are not changed yet (Cordelion's first visit: 0 of 45 in testing).
- Omega weapons: the randomizer cannot yet set the Omega upgrade in the game.
- The exact Steam build used in development is not confirmed. If `rivet.log` says `refused this
  exe`, your game build differs; please report your `RiftApart.exe` version.
- Some starting items may arrive only after the parade, once you reach Nefarious City.

More: `DOCUMENTATION/KNOWN_ISSUES.md` in the repository.
