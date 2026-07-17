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
