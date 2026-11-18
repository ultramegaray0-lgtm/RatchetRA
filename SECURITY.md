# Security and privacy: v0.60

This page says what each part of the mod does, based on a review of the v0.60 source and player
ZIP. It is not a certification by a third party: please check the source yourself if in doubt.

## Summary

- No network access, no telemetry, no downloads, no auto-updates.
- No personal data is collected or sent anywhere.
- The game's own files and your game saves are never modified. Installing only adds files
  (and replaces `rivet.toml`, as the install guide says).
- No administrator rights are needed.

## What each part does

| Part | Reads | Writes | Network |
|---|---|---|---|
| Lua scripts (`scripts\*.lua`, run by rivet_hook) | game memory through rivet_hook's API | game memory through rivet_hook's API (inventory, mission state, travel flags, the shop's slots, enemy spawners' template variables); log lines in `rivet.log` | none. The only standard-library call they use is `os.clock` |
| `rando_give.dll` (loaded by rivet_hook) | `RiftApart.exe`'s code in memory, to check the exact game version | game memory only: one hook on the game's script update, one replaced armor-reward handler (only if its bytes match exactly), one 4 KiB memory page shared with the scripts. Nothing on disk | none |
| Companion (`rando_companion\RandoCompanion.ps1`) | `rivet.toml`, the `mods` folder and the game's `toc` file (read-only, to detect ARSENAL_RESTORED); the local pipe `\\.\pipe\rivet_hook` | only `rando_companion\randomizer_saves\` (progress, `.bak` copies, `random_seed.txt`, spoiler logs). It deletes only `random_seed.txt`, and only when asked for a new seed | none: the pipe is local to your PC |
| `Start-Companion.bat` | — | — | runs `RandoCompanion.ps1` with `-ExecutionPolicy Bypass` for that one script; no system setting is changed |
| `Install-ArsenalRestored.bat` / `.ps1` (optional, only when you run it) | the ARSENAL_RESTORED zip, folder or `.stage` you give it; `rivet.toml` | `mods\ARSENAL_RESTORED` (or `.stage`), the mod's own `.lua` files in `scripts` (never over a randomizer file), `rivet.toml` (+ `rivet.toml.bak`); a temporary folder for the unzip, deleted afterwards | none |

### rando_give.dll

- Full source in [`SOURCE/DLL`](SOURCE/DLL). It builds reproducibly: a clean build of this
  repository with clang/lld 18.1.3 is byte-identical to the released DLL (v7, SHA-256
  `8055703e7dd7f48e16aa5a081d6795c15d515a52802bd0d70aafe88b54640744`).
- v7 also reads one game structure (the SceneManager, found by a code signature) and publishes its
  address to the scripts; it writes nothing more than v6.
- Its complete import list: from `kernel32.dll` `CloseHandle`, `CreateToolhelp32Snapshot`,
  `FlushInstructionCache`, `GetCurrentProcess`, `GetCurrentProcessId`, `GetCurrentThreadId`,
  `GetModuleHandleA`, `GetModuleHandleExA`, `GetThreadContext`, `OpenThread`, `ResumeThread`,
  `SetThreadContext`, `SuspendThread`, `Thread32First`, `Thread32Next`, `VirtualAlloc`,
  `VirtualProtect`; from `ntdll.dll` `__C_specific_handler`. There are no file, registry, network
  or process-launch functions.
- If the game's code does not match the expected version byte for byte, it changes nothing.
- Some antivirus programs flag DLLs that hook a running game. Check the source and checksum if you
  are unsure.

## Things to know

- **rivet_hook's pipe bridge** (`[bridge] enabled = true`) lets programs on your own PC that run
  as your Windows user send Lua code to the game. The companion uses it to save and restore your
  progress. It is not reachable from other computers.
- **Randomizer progress files** (`randomizer_saves\*.lua`) are Lua code that the companion sends
  back to the game. Only use progress files you made yourself.
- **Logs:** `rivet.log` can contain the path of your game folder, which may include your Windows
  user name. Remove it before posting the log publicly.

## Review of the release

For v0.60 the player ZIP and this repository were checked for: personal names, user folders and
absolute paths; keys, tokens and passwords; network, download and process-launch code; registry
access; files written outside the game folder; developer tools and debug keys; the developer-only
randomizers (they stay in the private development repository). None were found in the files
players get. Developer-only tools (test helpers, debug keys, research scripts) are
not in the player ZIP or in this repository.

## Reporting a security issue

Please contact the repository owner through GitHub. Do not post personal data or exploit details
in a public issue.
