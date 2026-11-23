# Troubleshooting: Rift Apart Randomizer v0.75

Most answers are in `rivet.log` in the game folder. Open it with Notepad and search for `RANDO-`.
`RANDO-ERROR` lines say what went wrong.

## Nothing happens (no seed, no starting items)

1. Does `rivet.log` exist and change each time you start the game? If not, rivet_hook is not
   installed: `hid.dll` and `rivet_hook.dll` must be next to `RiftApart.exe`.
2. Is the randomizer's `rivet.toml` in the game folder? It turns on scripts (`[scripts]
   enabled = true`, `path = "scripts"`), which rivet_hook has off by default.
3. Are the scripts in `<game folder>\scripts\`, not in a `GAME_FOLDER` subfolder?
4. Is the companion running? With `seed = "random"`, no seed is made until it connects. The screen
   says "start the companion".

## `RANDO-KIT` says a file is missing or from another version

Your `scripts` folder mixes versions. Delete every `*_rando_*.lua` file and `enemy.lua` there and
copy the 16 files from `GAME_FOLDER\scripts` again. Also delete any file named `16_rando_testtravel.lua` or
`dev(...).lua` left from an older version.

## "rando_give.dll ... refused this exe" or "rando_give.dll is not loaded"

- **refused this exe:** your game version is not Steam v3.630.1.0. The helper then does nothing,
  on purpose, and most rewards can't arrive. Update the game in Steam. Other stores' versions are
  not supported.
- **not loaded:** `rando_give.dll` must be next to `RiftApart.exe`, and `rivet.toml` needs
  `[renderdoc] enabled = true` and `dll_path = "rando_give.dll"` (rivet_hook's setting for loading
  an extra DLL).

## Antivirus warns about `rando_give.dll`

The helper changes one function of the running game, as most game mod loaders do, and some
antivirus programs flag that. Its full source and build steps are in the project's GitHub
repository (`SOURCE/DLL`), and the build is reproducible: compare the SHA-256 in `SHA256SUMS.txt`.
It contains no network, file or registry code.

## The companion window closes at once or says scripts are disabled

- Right-click `RandoCompanion.ps1` → **Properties**, tick **Unblock** if it is there, click OK,
  then start `Start-Companion.bat` again. (The .bat runs only this script with PowerShell's
  `-ExecutionPolicy Bypass`; it changes no system setting. A policy set by a company
  administrator can still block it.)
- "Access to the path ... is denied": the companion saves into `rando_companion\randomizer_saves`,
  so your Windows user must be able to write in the game folder.
- Do not run the game or the companion as administrator: they must run as the same Windows user
  to talk to each other.

## A reward said it was given but is not in my inventory

Wait a few seconds or change planet; the randomizer tries again. If items are still missing,
press **Ctrl+0 twice** to send all your randomizer items again.

## The Enemy Randomizer: an enemy cannot be killed, or a fight does not end

The randomizer watches every replaced enemy and puts a replacement back when the fight goes on
without it dying. If a fight still will not end, press **-** to turn the Enemy Randomizer off (this
puts every change back), then reload the checkpoint. Please send `rivet.log` (search
`RANDO-ENEMIES`). Press **-** again to turn it back on.

## Enemies look the same as before

The game can only spawn enemies that are loaded where you are. Many fights load one faction only, so
a pirate becomes another pirate. Press **Ctrl+-** to see what was changed here.

## I was taken back to Nefarious City and want to stay

That is the trip back after a finished planet. Fly on with the ship's planet menu. To switch it off,
set `hub_auto_return = false` in `scripts\04_rando_settings.lua` (remove the `--` in front of it).

## ARSENAL_RESTORED's weapons are not in the seed

- `rivet.log` must show `[loader] mod path mods/ARSENAL_RESTORED is overstrike format.` If it says
  `does not exist! skipping.`, run `rando_companion\Install-ArsenalRestored.bat` with the mod's zip.
- The companion must be running when you choose New Game (it tells the game the mod is installed).
- Installing the mod gives a new seed: start it with New Game.

## Planet shuffle: a planet's story will not start, or a level misbehaves

Press **0** to turn planet shuffle off. The game then handles travel and stories its own way;
your items stay randomized. Press 0 again later to turn it back on.

## I loaded an older save and items are missing

Randomizer progress is saved separately and does not go back with an older game save. Press
**Ctrl+0 twice** to get your items again. Play forward from your latest save when you can.

## The shop shows its normal weapons

Another mod may have changed Ms. Zurkon's shop. The seed's shop weapons are then given to you
directly instead.

## Starting over

- Same seed: choose New Game.
- New random seed: close the game, delete `rando_companion\randomizer_saves\random_seed.txt`,
  start the companion and the game, then choose New Game.

## Reporting a problem

Include the mod version (v0.75), your game version, what you did, and `rivet.log`. Replace your
Windows user name in any paths in the log before you post it.
