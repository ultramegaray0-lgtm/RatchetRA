# Ratchet & Clank: Rift Apart Randomizer v0.70 (beta)

**Download:** `Ratchet_Rift_Apart_Randomizer_v0.70_Player_Release.zip` (below, under Assets).
This ZIP is everything a player needs. "Source code" archives GitHub adds automatically are the
repository source, not the mod download. Older releases stay on the releases page.

SHA-256 of the ZIP:
`d3f76981fde3328e6a996d84eda115a9a73aeee90f16ca5c58b2fa45ad22f4f4`

## Requirements

- Ratchet & Clank: Rift Apart, Steam v3.630.1.0, Windows 10/11 64-bit
- **rivet_hook 2.0.1** (required, not included; 2.0.0 also works): https://github.com/neptuwunium/rivet_hook/releases

## Install

1. Back up `Documents\Ratchet & Clank - Rift Apart`.
2. Install rivet_hook into the game folder.
3. Copy everything inside the ZIP's `GAME_FOLDER` into the game folder (replace every file of
   `scripts` when you update from v0.60).
4. Run `rando_companion\Start-Companion.bat`, start the game, choose New Game.

Full guide: `INSTALLATION.md` in the ZIP.

## What's new in v0.70

- **No more crash when you die, retry a checkpoint or load a save.** During a load, rivet_hook
  runs the scripts while the game is freeing the level; the Omega search could read memory the
  game had just freed. The randomizer now notices every load the moment it starts and reads or
  writes nothing until it is over (`RANDO-LOAD` lines in `rivet.log`). Found in rivet_hook's
  source and tested in a simulator; **not yet played in the game**, so please send `rivet.log` if
  the game still closes when you die.
- **Omega weapons work in the game.** With `omega_weapons = true` an Omega reward now turns your
  weapon into its Omega version (seen in the developer's game: Omega Ricochet set and read back).
  A few seconds after each load the screen says **Randomizer: Omega ready**. Still **off by
  default**; turning it on makes a different seed.
- Omega purchases at Ms. Zurkon are recognized, and the Omegas of one save are no longer copied into
  another save you load.
- Enemy Randomizer: more of Ardolis' enemies are recognized; pool sharks are never used as
  replacements.
- The scripts check that every file is from the same version and name a mixed install.

## Seeds

With the default settings v0.70 makes **the same seeds as v0.60** (checked on 216 seeds), so a
run in progress carries over: replace the scripts and keep playing.

## Known issues

- Spybots and Lorbs hold no rewards (their pickups are not recognized yet).
- Only enemies already loaded on a level can be used by the Enemy Randomizer.
- Full list: `KNOWN_ISSUES.md` in the ZIP.
