# Companion: v0.60

Goes into `<game folder>\rando_companion`. Start `Start-Companion.bat` before the game and keep
its window open. It talks to the game through rivet_hook's local pipe, saves randomizer progress
to `randomizer_saves\`, picks and remembers random seeds, and writes the spoiler log. See
[SECURITY.md](../../SECURITY.md) for exactly what it reads and writes.

## Install-ArsenalRestored.bat (optional)

Installs the rivet_hook version of ARSENAL_RESTORED (not included; get it from its author): drag
its zip, folder or `.stage` onto the `.bat`. `Install-ArsenalRestored.ps1` copies the mod to
`mods\ARSENAL_RESTORED` (or `mods\ARSENAL_RESTORED.stage`), copies the mod's own `.lua` files
into `scripts` (never over a randomizer script), and adds the path to `rivet.toml` if it is missing
(keeping `rivet.toml.bak`). It prints every step and changes nothing else.
