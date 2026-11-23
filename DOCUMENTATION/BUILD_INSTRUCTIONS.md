# Build instructions: v0.75

Only one part of the mod is compiled: `rando_give.dll`. Everything else (Lua scripts, companion,
`rivet.toml`) is used as it is in this repository.

## rando_give.dll

Source: [`SOURCE/DLL`](../SOURCE/DLL). It is built without the Windows SDK and without a C
runtime, on Linux (or WSL) with LLVM.

1. Install LLVM: `clang`, `lld-link` and `llvm-dlltool` (tested with clang/lld 18.1.3 on Ubuntu).
2. Build:
   ```
   sh SOURCE/DLL/build.sh
   ```
   Output: `SOURCE/DLL/out/rando_give.dll`.
3. Compare with the released file:
   ```
   sha256sum SOURCE/DLL/out/rando_give.dll
   ```
   Expected: `8055703e7dd7f48e16aa5a081d6795c15d515a52802bd0d70aafe88b54640744` (v7).

The build is reproducible: the link timestamp is fixed in `build.sh`. A clean build from this
repository with clang/lld 18.1.3 was compared with the v0.75 player ZIP's DLL (unchanged since v0.60) and is
byte-identical.

## The player ZIP

The ZIP's `GAME_FOLDER` is assembled from this repository:

| In the ZIP | From |
|---|---|
| `GAME_FOLDER/scripts/*.lua` (16 files) | `SOURCE/Lua/*.lua` |
| `GAME_FOLDER/rando_give.dll` | the build above |
| `GAME_FOLDER/rando_companion/Start-Companion.bat`, `RandoCompanion.ps1`, `Install-ArsenalRestored.bat`, `Install-ArsenalRestored.ps1` | `SOURCE/Companion/` |
| `GAME_FOLDER/rivet.toml` | `SOURCE/Config/rivet.toml` |

Every file in the ZIP is listed with its SHA-256 in the ZIP's `SHA256SUMS.txt`, so you can check
that the released files match this repository.

## The Lite ZIP

Nothing is compiled. Its files come from `SOURCE/Lua` (13 scripts) and `SOURCE/Lite` (`04_rando_settings.lua`,
`rivet.toml`): see [SOURCE/Lite](../SOURCE/Lite/README.md). Its `SHA256SUMS.txt` lists every file.
