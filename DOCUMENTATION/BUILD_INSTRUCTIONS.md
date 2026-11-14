# Build instructions: v0.55

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
   Expected: `efb927232f67b7740aec473afa3866dd50636e1c29d0b2822717116a40092c12`.

The build is reproducible: the link timestamp is fixed in `build.sh`. A clean build from this
repository with clang/lld 18.1.3 was compared with the v0.55 player ZIP's DLL and is
byte-identical.

## The player ZIP

The ZIP's `GAME_FOLDER` is assembled from this repository:

| In the ZIP | From |
|---|---|
| `GAME_FOLDER/scripts/*.lua` (13 files) | `SOURCE/Lua/*.lua` |
| `GAME_FOLDER/rando_give.dll` | the build above |
| `GAME_FOLDER/rando_companion/Start-Companion.bat`, `RandoCompanion.ps1` | `SOURCE/Companion/` |
| `GAME_FOLDER/rivet.toml` | `SOURCE/Config/rivet.toml` |

Every file in the ZIP is listed with its SHA-256 in the ZIP's `SHA256SUMS.txt`, so you can check
that the released files match this repository.
