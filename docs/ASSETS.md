# Asset and overlay policy

## Decision

Asset paths are part of the compatibility contract and will not be removed.
The AddOn can therefore use the same Lua paths with either the public
placeholder set or an optional full media overlay.

Project-authored placeholder media remains eligible for source control. Known
client-extracted files under `addon/SoloCollections/Media/Retail` are now
explicitly ignored by Git and retained only in the local working tree, local
release candidate, and the maintainer's separate media workflow.

## Public repository gate

Before the first public GitHub push:

1. Classify every media file as project-authored, permissively licensed,
   third-party redistributable, or client-extracted/non-redistributable.
2. Keep project-authored or properly licensed files with attribution.
3. Replace non-redistributable files with project-authored placeholders at the
   exact same relative path, dimensions, container type, and alpha behavior.
4. Update `addon/SoloCollections/Media/assets.json` with provenance and SHA-256.
5. Build the AddOn zip from a clean Git checkout and inspect its file list.

Known client-derived files are recorded as external files in
`addon/SoloCollections/Media/assets.json`. A clean Git clone may not contain
them. The full media pack restores the exact paths; project-owned placeholder
paths remain in Git.

## Optional netdisk media overlay

The external pack should mirror paths beginning at the game client root, for
example:

```text
Interface/AddOns/SoloCollections/Media/...
Data/<dedicated SoloCollections patch archive, if required>
Data/<locale>/<dedicated SoloCollections locale patch archive, if required>
```

Users extract the pack into the client root and choose overwrite. The pack must
contain:

- `media-pack.json` with project version, pack version, locale, and target paths;
- `SHA256SUMS.txt` covering every file;
- installation, backup, and removal instructions;
- a clear statement that the pack is separately licensed and which UI features
  need it.

`Patch-W.MPQ` and numeric locale patch names may collide with another mod.
Always detect, identify, and back up same-name files; integrated clients require
a merge workflow. The source repository never contains a game executable.
If the maintainer distributes one through a separate channel, its provenance,
build, hash, legal-use warning, and patch state must be explicit.

## Compatibility rule

Overlay files must preserve the paths expected by the AddOn. Missing external
media must not prevent Lua from loading; affected artwork may fall back or be
blank until the matching media pack is installed. Missing MPQs must degrade to
AddOn-only previews rather than modifying unrelated client archives.
