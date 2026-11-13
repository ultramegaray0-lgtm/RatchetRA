# Build Instructions

**Status:** Pending source upload and verification. These are not yet executable build instructions.

A complete build guide must be based on the actual project files and must allow another person to build the distributed component from a clean checkout.

## Information to provide

1. Supported operating system and architecture.
2. Required compiler, SDK, runtime, and exact versions.
3. Required third-party dependencies and how to obtain them.
4. Project/solution files and build configuration.
5. Exact commands or IDE steps for a clean build.
6. Expected output filenames and locations.
7. Any post-build steps.
8. How to compare the locally built output with the distributed release.

## Clean-build verification

Before publishing:
- Start from a fresh checkout.
- Follow only the documented steps.
- Confirm that all dependencies are identified.
- Build without relying on files from the developer's machine.
- Record warnings and known limitations.
- Verify the output and document whether the build is reproducible.

Do not publish secrets, machine-specific paths, private SDKs, or proprietary game files as part of the source repository.
