# Asset and overlay policy

## Base UI decision

The base AddOn is self-contained. Every production media role must resolve to
a tracked, redistributable file under `addon/SoloCollections/Media`; it must
not resolve only after a maintainer installs a local overlay. The authoritative
role-to-file, provenance, format, dimensions and SHA-256 contract is
`addon/SoloCollections/Media/assets.json`.

The default collection launcher, mount portrait, wardrobe slot atlas, selected
ring and hover ring are project-authored TGA assets. The deterministic source
for the generated slot and portrait assets is
`tools/media/generate_base_ui_media.py`. It reads no client-extracted artwork.
`Media/Retail` is not a supported base-UI path and is not part of the repository
or a clean release bundle.

## Public repository gate

Before the first public GitHub push:

1. Classify every media file as project-authored, permissively licensed,
   third-party redistributable, or client-extracted/non-redistributable.
2. Keep project-authored or properly licensed files with attribution.
3. Replace non-redistributable defaults with project-authored or properly
   licensed assets before they are referenced by production Lua.
4. Update `addon/SoloCollections/Media/assets.json` with provenance, licence,
   SHA-256, container, dimensions and alpha/origin metadata.
5. Run the media contract test and release verifier from a clean Git checkout.
   They verify both the declared roles and the files copied to the bundle.

`requiredForBaseUI` and `optionalExternalFiles` are deliberately separate: an
optional declaration can never satisfy a default production reference.

## Optional netdisk media overlay

An external pack is permitted only for an explicitly selected skin or
non-essential enhancement. It must use a distinct, documented skin namespace;
it must not replace the files that the base role contract requires. For
example:

```text
Interface/AddOns/SoloCollections/Media/...
Data/<dedicated SoloCollections patch archive, if required>
Data/<locale>/<dedicated SoloCollections locale patch archive, if required>
```

Users opt in to the pack and choose its skin through AddOn configuration. The
pack must contain:

- `media-pack.json` with project version, pack version, locale, and target paths;
- `SHA256SUMS.txt` covering every file;
- installation, backup, and removal instructions;
- a clear statement that the pack is separately licensed and which UI features
  it enhances.

`Patch-W.MPQ` and numeric locale patch names may collide with another mod.
Always detect, identify, and back up same-name files; integrated clients require
a merge workflow. The source repository never contains a game executable.
If the maintainer distributes one through a separate channel, its provenance,
build, hash, legal-use warning, and patch state must be explicit.

## Compatibility rule

Missing optional media must not change the base UI or leave a default control
blank. Missing MPQs must degrade to AddOn-only previews rather than modifying
unrelated client archives. A release is rejected when any default production
media reference lacks a tracked, hash-verified base file.
