# rando_give.dll source (v6)

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
`efb927232f67b7740aec473afa3866dd50636e1c29d0b2822717116a40092c12`. This was checked for this
release with clang/lld 18.
