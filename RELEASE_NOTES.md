# Ratchet & Clank: Rift Apart Randomizer v0.75 (beta)

**Two downloads** (below, under Assets). "Source code" archives GitHub adds automatically are the repository source,
not the mod download. Older releases stay on the releases page.

| Download | What it is | SHA-256 |
|---|---|---|
| `Ratchet_Rift_Apart_Randomizer_v0.75_Player_Release.zip` | **The full randomizer.** Everything a player needs. | `973144c7027ba490e566e638d707d6e299cc37a52250e86e68920daf3cd7d557` |
| `Ratchet_Rift_Apart_Randomizer_v0.75_Lite_NexusMods.zip` | **Lite: try it first.** Lua scripts only, no DLL, no companion. Also published on NexusMods. | `34c43ed897a24382fad163bcdbe1f1b35b827ffb3b42737ea0c0c3d2c4e47e79` |

## Requirements

- Ratchet & Clank: Rift Apart, Steam v3.630.1.0, Windows 10/11 64-bit
- **rivet_hook 2.0.1** (required, not included; 2.0.0 also works): https://github.com/neptuwunium/rivet_hook/releases
  (both downloads need it: it is the mod loader that runs the scripts)

## Install (full)

1. Back up `Documents\Ratchet & Clank - Rift Apart`.
2. Install rivet_hook into the game folder.
3. Delete every `*_rando_*.lua` and `enemy.lua` in the game's `scripts` folder, then copy everything inside the ZIP's
   `GAME_FOLDER` into the game folder.
4. Run `rando_companion\Start-Companion.bat`, start the game, choose **New Game**.

Full guide: `INSTALLATION.md` in the ZIP. Lite: copy its `GAME_FOLDER` (`scripts`, `rivet.toml`) and start the game.

## What's new in v0.75

- **New defaults:** planet shuffle stays **off** (press 0), the **Enemy Randomizer is off** (press - to turn it on;
  your save remembers), and **Omega weapons are on**: the 20 Omega versions are rewards and are set in the game.
- **Spybots and Lorbs give rewards** when you pick them up (seen working in the developer's game).
- **Ms. Zurkon's shop sells the seed's weapons** (her earliest slots stay open), and six of her slots also give a
  **bonus item** (2 Omega versions, 2 gadgets, 2 armor pieces) with the weapon you buy. She announces them when you talk
  to her; if you already own the weapon in such a slot, the bonus is given to you directly.
- **Back to Nefarious City** after every planet, with planet shuffle on **and** off. Fixed: turning planet shuffle on
  in the middle of a run (it starts with the next New Game) made the next trip back start the hub mid-run.
- Armor: a cutscene that reports several armor pieces at once no longer pays every armor reward at once.
- Enemy Randomizer (when on): more of Savali's Nefarious troopers are recognized before their first fight.
- **New: the Lite download** for trying the randomizer before installing the full one. It randomizes weapons, gadgets,
  Bolts and Raritanium over Gold Bolts, story missions, side activities, Spybots and Lorbs, and takes you back to
  Nefarious City after each planet, where your rewards are handed over. It writes the spoiler into `rivet.log`.
  Armor, the shop, Omega weapons, the Enemy Randomizer, planet shuffle and saved progress need the full download.

## Seeds

v0.75 makes **different seeds** than v0.70 (Omega weapons on, Spybots and Lorbs, the shop's bonus slots): start a
**New Game**. The Lite download makes its own seeds (`seed = "rift-lite-test"`; change the text for another game).

## Test status

- Played in the developer's game (development build v0.71-DEV9, the same code): the shop's slots, an owned bonus paid
  directly, Spybots and Lorbs, Omega weapons, the Enemy Randomizer on a Savali fight (13 of 16 replaced, all died),
  loads and warps without a crash.
- Checked in a simulator only: the trip-back fix, the whole Lite download, and Lite's Bolts / Raritanium rewards (they
  go through the game's own level script with the amount as its count; please send `rivet.log` if an amount is wrong).
- Automated: 940 tests, 0 failures; 32 of 32 release checks on the full ZIP; 360 Lite seeds checked.

## Known issues

- Only enemies already loaded on a level can be used by the Enemy Randomizer.
- Ms. Zurkon's closed slots show the Burst Pistol you own.
- Full list: `KNOWN_ISSUES.md` in the ZIP; Lite: `README.md` in the Lite ZIP.
