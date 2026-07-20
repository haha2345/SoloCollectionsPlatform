# Packaging

Release packaging is intentionally gated until the code license and public
placeholder media set are approved.

Planned artifacts:

- `SoloCollections-<version>-addon.zip`: directly installable AddOn;
- `SoloCollections-<version>-source.zip`: GitHub-generated source archive;
- `SoloCam-<version>-win32.zip`: project DLL, patch tool, requirements, and
  instructions, never `Wow.exe`;
- external `SoloCollections-Media-<pack-version>.zip`: optional same-path media
  overlay with manifest and SHA-256 list.

Do not package directly from a game installation. Build from a clean tagged Git
checkout and audit the archive file list before release.

`build-release.ps1` creates AddOn/server archives and checksums. It refuses a
normal public build while `Media/assets.json` reports an unapproved asset set.
`-AllowUnauditedLocalMedia` exists only for a visibly named private preview and
must not be used for a GitHub release.

`assemble-local-release.ps1` creates the complete ignored local layout requested
for manual distribution: AddOn zip, ALE Lua, SoloCam DLL/patcher, the two MPQs,
two release READMEs, and `SHA256SUMS.txt`. It refuses to overwrite an existing
version directory. Binary distribution rights still require a separate audit.

## Unified C++ backend release

`tools/release/build_unified_release.py` is the release path for the unified
backend. It packages the AddOn and `mod-solo-collections` from committed Git
objects, records the three repository commits and compatibility versions, and
creates `release-manifest.json` plus `SHA256SUMS.txt`. It rejects client
EXE/DLL/MPQ files, database credentials, and Windows-local absolute paths.

The older PowerShell packagers remain historical/local-media tooling and must
not be used to publish the unified backend because they include the retired ALE
bridge and optional client media.
