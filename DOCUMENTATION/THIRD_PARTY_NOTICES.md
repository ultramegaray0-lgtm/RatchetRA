# Third-party notices and credits: v0.55

## This mod

Author: **MegaRay**. The randomizer's own files (Lua scripts, companion scripts, `rivet.toml`,
`rando_give.dll` and its source, documentation) are released under the **MIT License**
(`LICENSE.txt` in the repository root).

**AI disclosure:** most of the code and documentation was written with Anthropic's Claude under
MegaRay's direction. Research, design decisions and in-game testing were done by MegaRay. No
AI-generated game assets, images, voices or audio are included.

## Required, not included

- **rivet_hook** by neptuwunium, EUPL-1.2 — https://codeberg.org/neptuwunium/rivet_hook
  (releases: https://github.com/neptuwunium/rivet_hook/releases). The mod loader the randomizer
  runs on. No rivet_hook code is included. `rando_give.dll` finds the game's config asset manager
  with the same byte pattern rivet_hook uses and reads its layout as rivet_hook's source documents
  it; credit for that finding goes to neptuwunium.

## Optional, not included

- **ARSENAL_RESTORED**, a separate mod by its own author. The randomizer only detects it and adds
  its weapons to the item pool. None of its files are included.

## Research references (no code or files included)

- rivet (neptuwunium, EUPL-1.2), Overstrike (Tkachov) and Ripped Apart (chaoticgd): engine and
  file-format documentation.
- Weapon prices and mission order: public guides (gamepressure.com, thegamer, vulkk), used as
  facts only.
- Item, mission and checkpoint names and asset ids come from the game's own asset list.
  `rando_give.dll` contains short byte sequences of `RiftApart.exe`'s code, only to confirm the
  exact game version. No game files, models, textures, audio or text are included.

## The game

Ratchet & Clank: Rift Apart © Sony Interactive Entertainment LLC, developed by Insomniac Games,
PC version by Nixxes Software. This is an unofficial fan modification, not affiliated with or
endorsed by them. You need your own copy of the game.
