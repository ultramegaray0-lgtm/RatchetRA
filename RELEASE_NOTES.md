# Ratchet & Clank: Rift Apart Randomizer v0.55 (beta)

**Download:** `Ratchet_Rift_Apart_Randomizer_v0.55_Player_Release.zip` (below, under Assets).
This ZIP is everything a player needs. "Source code" archives GitHub adds automatically are the
repository source, not the mod download.

SHA-256 of the ZIP:
`0f262a9e2a5227732d03764c54ca21c2e62d2b00949f2557ebd6eab955418e1c`

## Requirements

- Ratchet & Clank: Rift Apart, Steam v3.630.1.0, Windows 10/11 64-bit
- **rivet_hook 2.0.1** (required, not included): https://github.com/neptuwunium/rivet_hook/releases

## Install

1. Back up `Documents\Ratchet & Clank - Rift Apart`.
2. Install rivet_hook into the game folder.
3. Copy everything inside the ZIP's `GAME_FOLDER` into the game folder.
4. Run `rando_companion\Start-Companion.bat`, start the game, choose New Game.

Full guide: `INSTALLATION.md` in the ZIP.

## What's new in v0.55

- Planet shuffle is now **off by default**. Press **0** in game to turn it on (during the opening
  parade of a New Game, or it starts with your next New Game).
- The only keys are **0** (planet shuffle) and **Ctrl+0 twice** (send your items again). With
  planet shuffle on, travel with the ship's planet menu.
- `15_rando_hub.lua` is optional: without it the game's normal story plays with randomized items.
- Simpler settings file and shorter documentation.
- Developer and test tools are no longer part of the download. The ARSENAL_RESTORED installer was
  removed: install that mod with its own instructions.
- Same seeds as v0.54 for the same settings; v0.54 progress files still load.

**Updating from v0.54:** delete every `*_rando_*.lua` file in `scripts` first (including
`16_rando_testtravel.lua`), then copy the new files.

## Known issues

- v0.55 has been checked with automated tests (a game simulator), **not yet in the real game**.
- The exact Steam build used in development is not confirmed (see KNOWN_ISSUES). If `rivet.log`
  says `refused this exe`, your game build differs; please report your `RiftApart.exe` version.
  A rivet_hook message `game version mismatch, invalidating pointers` alone was harmless on the
  development install.
- Some starting items may arrive only after the parade, once you reach Nefarious City.
- Ms. Zurkon's shop may stay unchanged; the seed's shop weapons are then given to you directly.

More: `DOCUMENTATION/KNOWN_ISSUES.md` in the repository.
