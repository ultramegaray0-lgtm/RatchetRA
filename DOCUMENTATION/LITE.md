# Lite package: v0.75 (beta)

Download: `Ratchet_Rift_Apart_Randomizer_v0.75_Lite_NexusMods.zip` from the [v0.75 release](https://github.com/ultramegaray0-lgtm/RatchetRA/releases/tag/v0.75) (also on NexusMods).

The try-it-first version of the Rift Apart Randomizer. **Lua scripts only**: this download has no
DLL, no companion app and nothing else to run. If you like it, get the full release for everything
listed under "Full release only" below.

This is an unofficial fan mod and a beta: please report problems.

## What Lite randomizes

- **Weapons and gadgets.** Every weapon Ms. Zurkon sells, plus the reward-only weapons, Box
  Breaker, Omniglove and Glitch, is placed on a reward somewhere in the game.
- **Where rewards come from:** all 25 Gold Bolts (each gives an item), story missions, side
  activities (Zurkie's cups, Trudi, the Blizar chef, Ardolis), and the 10 Spybots and 12 Lorbs.
- **Bolts and Raritanium** fill the remaining reward spots.
- **Your start:** Hoverboots, Map-O-Matic, 2 random weapons and 1 random gadget.
- **Back to the hub:** when a planet's story is done, the screen says **Back to Nefarious City in
  12 s** and you are taken back to Nefarious City. Fly on from there with the ship's planet menu.
  If you fly on yourself before the countdown ends, you stay where you flew.
- Every seed is checked by a solver before you play, so it can always be finished.

## How Lite hands rewards over

Without the DLL, the randomizer can only put items into your inventory through a piece of the
game's own level scripting that is loaded on **Nefarious City**. So:

- You find a reward anywhere: the screen tells you what it is.
- It arrives in your inventory the next time you are on Nefarious City (the trip back after each
  planet takes you there).
- The game's own story starts and ends on Nefarious City often, so this happens naturally.

## Full release only

These need the full release's `rando_give.dll` or its companion app:

| Feature | Why Lite can't |
|---|---|
| Rewards arriving on every planet at once | the DLL sends the game's own "add item" message anywhere |
| Ms. Zurkon's shop selling the seed's weapons, her bonus items, shuffled prices | her stock is found in memory by the DLL |
| Armor pieces as rewards (armor pods give random items) | the game's armor code is reached through the DLL |
| Omega weapons and weapon XP rewards | the weapon records are found through the DLL |
| Enemy Randomizer | the level's spawner data is found through the DLL |
| Planet shuffle (Nefarious City as a hub, planets in any order) | missions and travel are switched through the DLL |
| Saved randomizer progress, random seeds, a spoiler file | that is the companion app's job |
| ARSENAL_RESTORED's weapons | the companion checks whether that mod is installed |

## What you need

- Ratchet & Clank: Rift Apart on Steam (version 3.630.1.0), Windows 10 or 11.
- **rivet_hook 2.0.1** (2.0.0 also works). It is the mod loader that runs the scripts. It is
  **required** and **not included**: https://github.com/neptuwunium/rivet_hook/releases

Install steps: `INSTALLATION.md` in the Lite ZIP (about 5 minutes): install rivet_hook, then copy the ZIP's
`GAME_FOLDER` (`scripts` and `rivet.toml`) into the game folder.

## Playing

1. Start the game and choose **New Game** on a spare save slot.
2. The screen shows `Randomizer Lite: seed rift-lite-test`, then your starting items arrive.
3. Play normally. Gold Bolts, story missions, side activities, Spybots and Lorbs now give the
   seed's items.

### Your seed

Lite always uses the seed written in `scripts\04_rando_settings.lua` (`seed = "rift-lite-test"`).
Change that text to any other text for a different game, then start a **New Game**. The same text
gives the same game on every PC, so you can share it.

### Progress

Lite has no companion, so the randomizer's own progress lives only while the game runs:

- Items you received stay in your game save as usual.
- Rewards you already collected never pay twice: the game does not report them again.
- **A reward that has not reached Nefarious City yet when you quit is lost.** Before you quit,
  visit Nefarious City (or wait for the trip back) so everything waiting is handed over.
- Your starting items are sent again when you start the game: items you already have stay as
  they are.

### Spoilers

The full list of what is where goes into `rivet.log` in the game folder (lines starting with
`RANDO-SPOILER`). Don't open it if you don't want spoilers. `spoiler_log = false` in the settings
turns it off.

### Keys

| Key | What it does |
|---|---|
| **Ctrl+0** twice | Send your randomizer items again if some went missing |

Planet shuffle (the **0** key in the full release) is not in Lite.

## Settings

Open `scripts\04_rando_settings.lua` with Notepad. Each option has a short note. Changing the seed
or an option makes a new game: start it with **New Game**.

| Setting | What it does |
|---|---|
| `seed` | any text; the same text gives the same game |
| `preset` | `balanced` (default), `full`, `chaos` (1 starting weapon) or `everything` |
| `distribution` | `"goldbolts_first"`: every Gold Bolt gives an item. `"spread"`: items go anywhere |
| `start_weapons`, `start_gadgets` | what you start with |
| `exclude` | items to leave out |
| `hub_auto_return` | `true` (default): taken back to Nefarious City after each planet |

## Known issues (Lite)

- **Bolts and Raritanium rewards** go through the same piece of level scripting as items. This is
  new in v0.75 and has not been checked in the game yet: if a Bolts reward arrives with the wrong
  amount (or not at all), please send `rivet.log`.
- Ms. Zurkon sells her own weapons as usual. If you buy a weapon that is also a reward, that
  reward later says you already have it.
- Armor pods give their own armor pieces, as in the normal game.
- If the ship can't leave Nefarious City after the trip back, it is the game's own story holding
  travel: play the city's story on, or set `hub_auto_return = false`.
- Coordinates are items in every seed (they open planets in the full release's planet shuffle).
  In Lite they do nothing else.

## Moving to the full release

Delete every file in the game folder's `scripts` folder and `rivet.toml`, then install the full
release as its own guide says. Start a **New Game**: the full release makes different seeds.

## Help

When you report a problem, include the mod version (v0.75 Lite), your game version and
`rivet.log` from the game folder. Remove your Windows user name from any path in it first.

Credits and licenses: [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
