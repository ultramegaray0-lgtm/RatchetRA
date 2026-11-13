# Security and Privacy

This document describes the intended security and privacy expectations for the Ratchet & Clank: Rift Apart Randomizer. It must be checked against the actual source and release package before being treated as a verified security audit.

## User data

The project should not request, collect, store, or transmit personal information. Do not include usernames, email addresses, access tokens, API keys, private save files, or machine-specific paths in source files, logs, examples, or release archives.

## Network activity

Any network access must be identified and explained here, including its purpose, destination, and the data sent or received. If the mod does not need network access, it should not make network requests.

## Files and permissions

The mod should only read or write files required for its documented functionality. It should not modify unrelated user files, install persistence mechanisms, launch unrelated programs, or silently download and execute additional code.

## Compiled components

If a compiled DLL is distributed:
- Publish the corresponding source code when legally and technically possible.
- Document the compiler/toolchain and exact build steps.
- Identify required dependencies and their versions.
- Explain the DLL's role and any files it reads or writes.
- Do not claim that a binary is reproducible until a clean build has been compared with the distributed binary.

## Reporting a security issue

Please report suspected security or privacy issues privately to the repository owner through GitHub. Do not post secrets, personal information, or exploit details in a public issue.

## Audit status

This file is a policy and documentation template, not a certification that the current release has passed a security audit. Review the actual source, binaries, and packaged files before release.
