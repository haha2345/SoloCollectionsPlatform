# SoloCollections for WoW 3.3.5a

[中文](README.md) | [Downloads](docs/DOWNLOADS.md)

SoloCollections adds a Retail-inspired collection journal to a clean World of
Warcraft 3.3.5a build-12340 client. It groups mounts, non-battle pets, toys,
equipment appearances, and sets in one AddOn. The repository also contains an
AzerothCore ALE bridge, an optional x86 SoloCam camera extension, and tooling
that builds the two client patch MPQs used by standalone weapon previews.

This is a development preview. The UI and demo/action bridge work, but a full
persistent account collection backend and production unlock synchronization
are not complete.

## Screenshots

| Mounts | Non-battle pets |
| --- | --- |
| ![Mount collection and model preview](docs/images/mounts.png) | ![Non-battle pet collection and model preview](docs/images/pets.png) |

| Toy box | Item appearances |
| --- | --- |
| ![Toy box and item tooltip](docs/images/toys.png) | ![Item appearance and slot filters](docs/images/wardrobe-items.png) |

![Set collection and dressing-room preview](docs/images/wardrobe-sets.png)

## Components

| Component | Purpose | Install location |
| --- | --- | --- |
| AddOn zip | Collection UI and catalog | `Interface/AddOns/SoloCollections` |
| `solo_collections.lua` | ALE protocol/action bridge | server `lua_scripts` directory |
| `SoloCam.dll` + patcher | Optional local camera/display bridge | client root |
| `Patch-W.MPQ` | Custom weapon M2/SKIN/BLP | client `Data` |
| `patch-<locale>-6.MPQ` | Extended Creature DBC rows | `Data/<locale>` |
| External media pack | Full visual assets and optional client-side files | extract over the client root |

## Downloads

Source control excludes proprietary/extracted media, game executables, MPQs,
and compiled artifacts. Runtime packages are assembled separately under the
ignored local `release` directory and may be attached to a GitHub Release.
Full media is hosted separately.

**External download: [Baidu Netdisk](https://pan.baidu.com/s/1XyCl8PaimIVPPSTNUDaIOg?pwd=j8sk)**  
**Access code: `j8sk`**

See [DOWNLOADS.md](docs/DOWNLOADS.md) before using the external package.

## Installation summary

1. Back up and close a clean 3.3.5a client.
2. Extract the AddOn zip under `Interface/AddOns`.
3. copy `solo_collections.lua` to the ALE script directory and restart the
   world server.
4. Copy `Patch-W.MPQ` to `Data`.
5. Use only a locale patch matching the client. The bundled
   `patch-zhCN-6.MPQ` is for zhCN only. Build `patch-enUS-6.MPQ`,
   `patch-zhTW-6.MPQ`, and other variants from the user's clean client.
6. Optionally place `SoloCam.dll` and `poc_patch.py` beside the user's legally
   obtained `Wow.exe`, then create the copy-only PoC executable.
7. Verify and extract the external media pack over the client root.

The exact supported `Wow.exe` SHA-256 is:

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

The project does not authorize redistribution of the game executable. See the
[Chinese installation guide](docs/INSTALLATION.zh-CN.md) and
[locale-independent MPQ guide](docs/BUILD_MPQ.zh-CN.md).

## Building

- AddOn and ALE Lua: no compilation.
- Python tooling: Python 3.10; install
  `client-extension/SoloCam/requirements-dev.txt`.
- SoloCam: Windows 10/11, Visual Studio 2022 Build Tools with Desktop C++, a
  Windows SDK, and the x86 MSVC toolchain; run
  `client-extension/SoloCam/scripts/build.ps1`.
- MPQs: PowerShell, Python 3.10, x64 StormLib, and a clean 3.3.5a client; run
  `build-weapon-models.ps1` without `-Deploy` first.

## Contributing

Fork the repository, branch from `main`, make one focused change, update tests
and documentation, and open a pull request with client hash, server version,
reproduction/validation steps, and screenshots. Never commit game executables,
MPQs, extracted client media, secrets, databases, or build output. Read
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

Project-authored SoloCollections code is licensed under **GPL-3.0-or-later**;
see [LICENSE](LICENSE). Client media, MPQs, game binaries, and third-party
libraries remain separately licensed under their respective terms.

This is an unofficial community compatibility project and is not endorsed by
Blizzard Entertainment or the AzerothCore project.
