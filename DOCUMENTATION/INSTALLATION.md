# Installation: Rift Apart Randomizer v0.75

> Download the player ZIP from the [v0.75 release](https://github.com/ultramegaray0-lgtm/RatchetRA/releases/tag/v0.75). These steps refer to its `GAME_FOLDER` folder.
> For the Lite download (no DLL, no companion) see [LITE](LITE.md).

About 10 minutes. No programming tools needed.

## 1. Back up your saves

1. Close the game.
2. Press `Win+R`, paste `%USERPROFILE%\Documents\Ratchet & Clank - Rift Apart` and press Enter.
3. Copy that whole folder somewhere safe.

The randomizer never changes your save files, but the game saves normally while you play. Use a
save slot you don't need.

## 2. Find the game folder

In Steam, right-click **Ratchet & Clank: Rift Apart** → **Manage** → **Browse local files**. The
folder that opens contains `RiftApart.exe`. These steps call it **the game folder**.

## 3. Install rivet_hook (required)

rivet_hook is the mod loader the randomizer runs on. It is made by another author and is not
included. Follow its own instructions. In short:

1. Download rivet_hook 2.0.1 from https://github.com/neptuwunium/rivet_hook/releases and extract it.
2. Copy `hid.dll` and `rivet_hook.dll` into the game folder. If the game crashes at start, use
   `hid_win10.dll` instead, renamed to `hid.dll`.
3. Create a folder named `mods` in the game folder.
4. Start the game once, reach the main menu, then quit.

## 4. Install the randomizer

1. Open this download's `GAME_FOLDER` folder.
2. Copy **everything inside it** (`scripts`, `rando_companion`, `rando_give.dll`, `rivet.toml`)
   into the game folder.
3. When Windows asks about replacing `rivet.toml`:
   - **No other rivet_hook mods:** choose **Replace**.
   - **Other rivet_hook mods:** back up your `rivet.toml` first, replace it, then copy your own
     entries back into `paths` under `[assets]`.

The game folder then contains:

```
<game folder>\
    RiftApart.exe
    hid.dll, rivet_hook.dll, mods\      (rivet_hook)
    rivet.toml                          (randomizer)
    rando_give.dll                      (randomizer)
    scripts\                            (randomizer: 16 files, 01_rando_data.lua ... 17_rando_omega.lua, enemy.lua)
    rando_companion\                    (randomizer: Start-Companion.bat, RandoCompanion.ps1,
                                         Install-ArsenalRestored.bat, Install-ArsenalRestored.ps1)
```

`rando_give.dll` is required: it puts rewards into your inventory.
Optional scripts (delete one to switch its feature off completely):

- `15_rando_hub.lua`: planet shuffle and the trip back to Nefarious City after each planet. Without
  it the game's normal story plays and you are never taken back.
- `16_rando_spawners.lua` and `enemy.lua`: the Enemy Randomizer (delete both).
- `17_rando_omega.lua`: Omega weapons in the game (only used with `omega_weapons = true`).

## Optional: ARSENAL_RESTORED (rivet_hook version)

The randomizer does not include ARSENAL_RESTORED; get it from its author. To install its rivet_hook
version next to the randomizer:

1. Install the randomizer first (step 4).
2. Drag the ARSENAL_RESTORED zip (or its extracted folder, or its `.stage` file) onto
   `rando_companion\Install-ArsenalRestored.bat`, or double-click the `.bat` and paste the path.
3. The window shows each step: the mod goes to `mods\ARSENAL_RESTORED` (or
   `mods\ARSENAL_RESTORED.stage`), its own `.lua` files go into `scripts` (never over a randomizer
   file), and `rivet.toml` lists it (the randomizer's `rivet.toml` already does).
4. Restart the game. `rivet.log` shows `[loader] mod path mods/ARSENAL_RESTORED is overstrike format.`
   With `restored_weapons = "auto"` (the default) its 9 weapons join your next New Game's seed.

The Overstrike version of ARSENAL_RESTORED needs no installer: install it with Overstrike.

## 5. Play

1. Double-click `rando_companion\Start-Companion.bat` and keep the window open.
2. Start the game and choose **New Game** on a spare slot.

To check the install, open `rivet.log` in the game folder and search for `RANDO-KIT`. It should
say `all 12 required scripts`. If it says `RANDO-ERROR`, see TROUBLESHOOTING.md.

## Updating

1. Close the game and the companion window.
2. If you changed `scripts\04_rando_settings.lua`, copy your values somewhere first.
3. In the game folder's `scripts` folder, delete every `*_rando_*.lua` file and `enemy.lua`
   (leave other mods' scripts alone).
4. Copy the new `GAME_FOLDER` contents into the game folder, then put your settings back into the
   new `04_rando_settings.lua`.
5. Keep `rando_companion\randomizer_saves` (your progress and spoilers).

## Uninstalling

The randomizer only adds files. Close the game and the companion, then delete from the game folder:

- the `*_rando_*.lua` files and `enemy.lua` in `scripts` (the whole `scripts` folder only if no other
  mod uses it);
- `rando_give.dll`;
- `rando_companion\` (this also deletes your randomizer progress and spoilers);
- `rivet.toml` (put your backup back if you made one).

To remove rivet_hook too, delete `hid.dll`, `rivet_hook.dll`, `rivet.toml`, `rivet.log` and the
`mods` folder. The game's own files are never changed. Saves made during a randomized run keep
the items you received; restore your backup to go back.
