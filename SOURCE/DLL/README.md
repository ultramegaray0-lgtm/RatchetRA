# rando_give.dll source (v7)

This is the complete source of the released `rando_give.dll`. It's included so anyone can check what
the DLL does, and rebuild it.

- `rando_give.c`: the Windows layer. It allocates the mailbox, runs the byte checks, installs the
  hook, and handles armor interception. The comment at the top explains each step.
- `rando_give_core.h`: the portable part. It holds every byte check, address and request handler.
- `kernel32.def`, `ntdll.def`: the only imported functions.
- `build.sh`: builds the DLL with LLVM (`clang`, `lld-link`, `llvm-dlltool`), with no Windows SDK
  and no C runtime.

## Rebuild and compare

On Linux (or WSL) with LLVM installed:

```
sh build.sh
sha256sum out/rando_give.dll
```

The build is reproducible: the link timestamp is pinned. The result must be byte-identical to the
shipped file, SHA-256
`8055703e7dd7f48e16aa5a081d6795c15d515a52802bd0d70aafe88b54640744`. This was checked for this
release with clang/lld 18.

## v7 (v0.60)

v7 adds one read-only lookup over v6: it finds the game's SceneManager by a code signature and
publishes its address in the shared page, so the Enemy Randomizer's scripts can read the spawners'
script variables. Its import list is the same as v6's. v7 ran in the developer's game from round 32
on.
