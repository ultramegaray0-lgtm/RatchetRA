# Ratchet & Clank: Rift Apart Randomizer

A randomizer for the PC version of **Ratchet & Clank: Rift Apart**. Weapons, gadgets, armor and
planet Coordinates are shuffled across Gold Bolts, story missions, side activities, armor pods
and Ms. Zurkon's shop. A solver checks every seed before you play, so it can always be finished.

Unofficial fan mod. **Current version: v0.55 (beta).**

## Download (players)

**[Download Ratchet_Rift_Apart_Randomizer_v0.55_Player_Release.zip](https://github.com/ultramegaray0-lgtm/RatchetRA/releases/download/v0.55/Ratchet_Rift_Apart_Randomizer_v0.55_Player_Release.zip)**
(release page with notes and checksum: [v0.55](https://github.com/ultramegaray0-lgtm/RatchetRA/releases/tag/v0.55)).

The player ZIP is all you need. The files in this repository are the **source code**, for
anyone who wants to check or rebuild the mod. Do not install from the repository's folders.

## Requirements

| | Version | Included? |
|---|---|---|
| Ratchet & Clank: Rift Apart | Steam, v3.630.1.0 | No (your own copy) |
| Windows | 10 or 11, 64-bit | — |
| [rivet_hook](https://github.com/neptuwunium/rivet_hook/releases) | 2.0.1 (2.0.0 also works) | **No — required, install it separately** |
| Windows PowerShell | 5.1 (built into Windows) | Already installed |
| ARSENAL_RESTORED | any | Optional, not included |

Details: [REQUIREMENTS](DOCUMENTATION/REQUIREMENTS.md).

## Install in short

1. Back up `Documents\Ratchet & Clank - Rift Apart`.
2. Install rivet_hook into the game folder (the folder with `RiftApart.exe`).
3. Copy everything inside the ZIP's `GAME_FOLDER` into the game folder.
4. Run `rando_companion\Start-Companion.bat`, keep it open, start the game, choose **New Game**.

Full steps, updating and uninstalling: [INSTALLATION](DOCUMENTATION/INSTALLATION.md).

## Features

- Items: weapons, gadgets (Box Breaker, Omniglove, Glitch), 21 armor pieces and planet
  Coordinates. With ARSENAL_RESTORED installed, its 9 weapons join too.
- Reward locations: 25 Gold Bolts, story missions, side activities (Zurkie's cups, Trudi, the
  Blizar chef, Ardolis) and armor pods. By default every Gold Bolt gives an item.
- Ms. Zurkon sells 8 weapons from the pool; her other slots close.
- Coordinates are items: rewards on a planet wait until you find its Coordinates.
- **Planet shuffle** (off by default, press **0** in game): Nefarious City becomes a hub and you
  visit planets in any order as you find their Coordinates.
- Fixed or random seeds, presets, a spoiler log, and progress saved per seed by the companion.

## Configuration

Edit `scripts\04_rando_settings.lua` in the game folder with Notepad. In game, the only keys are
**0** (planet shuffle on/off) and **Ctrl+0 twice** (send your randomizer items again).
See [CONFIGURATION](DOCUMENTATION/CONFIGURATION.md).

## More

- [Troubleshooting](DOCUMENTATION/TROUBLESHOOTING.md)
- [Known issues and compatibility](DOCUMENTATION/KNOWN_ISSUES.md)
- [Security and privacy](SECURITY.md)
- [Building from source](DOCUMENTATION/BUILD_INSTRUCTIONS.md)
- [Third-party notices](DOCUMENTATION/THIRD_PARTY_NOTICES.md)
- [License (MIT)](LICENSE.txt)

## Repository layout

| Folder | Contents |
|---|---|
| `SOURCE/Lua/` | The 13 Lua scripts that go into `<game>\scripts` |
| `SOURCE/DLL/` | Full source of `rando_give.dll` and its reproducible build script |
| `SOURCE/Companion/` | The companion (`Start-Companion.bat`, `RandoCompanion.ps1`) |
| `SOURCE/Config/` | `rivet.toml` for rivet_hook |
| `DOCUMENTATION/` | Player and developer documentation |

Developer-only tools (test helpers, debug keys, research scripts) are kept out of this
repository and out of the player ZIP.

Ratchet & Clank: Rift Apart © Sony Interactive Entertainment LLC. This project is not affiliated
with or endorsed by Sony, Insomniac Games or Nixxes Software.
