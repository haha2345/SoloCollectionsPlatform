# SoloCollections build and development environment

## Toolchains

| Component | Environment | Build |
| --- | --- | --- |
| AddOn | WoW 3.3.5 Lua 5.1/FrameXML | No compile step |
| Catalog/protocol tooling | Python 3.10 | Generators and contracts |
| SoloCam | Windows 10/11, VS 2022, MSVC v143 x86, Windows SDK | Native build |
| C++ backend | Official AzerothCore dependencies, x64 Core build | Built with Core |
| Client resources | PowerShell, Python, x64 StormLib, user's clean client | Local only |

The current official Windows requirements include CMake 3.27+, Visual Studio
2022 Desktop C++, Boost 1.78+, MySQL 8.0+, and OpenSSL 3.x. Follow the
[AzerothCore requirements](https://www.azerothcore.org/wiki/windows-requirements)
when they change.

Clone both repositories as siblings and work on a feature branch:

```powershell
git clone https://github.com/haha2345/SoloCollections.git
git clone https://github.com/haha2345/mod-solo-collections.git
Set-Location .\SoloCollections
git switch -c feature/my-change
```

## Python and AddOn

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r .\client-extension\SoloCam\requirements-dev.txt

$tempRoot = Join-Path $PWD '_work\python-temp'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$env:TEMP = $tempRoot
$env:TMP = $tempRoot
$env:PYTHONDONTWRITEBYTECODE = '1'

python -m unittest discover -s .\tools\collections\tests -p "test_*.py" -v
```

The AddOn is copied from `addon/SoloCollections`; it is not compiled. An
installed Lua 5.1 `luac -p` is useful for syntax checks but does not replace a
real 3.3.5 client check.

## Catalog generation

Catalog outputs are derived from canonical source and reviewed decisions:

```powershell
python .\tools\catalog\generate_catalog.py `
  --module-root ..\mod-solo-collections `
  --evidence-root <legally-obtained-external-evidence> `
  --check
```

External evidence may describe local DBC, database, or client-model inputs and
must remain outside Git. A catalog change normally updates `catalog/source`,
`catalog/review`, `catalog/generated`, the AddOn generated projection, and the
module JSON/C++ projections. Do not hand-edit generated Lua as the only change.

## SoloCam

Install the VS 2022 Desktop C++ workload, MSVC v143 x86/x64 tools, and a Windows
SDK:

```powershell
$env:SOLOCOLLECTIONS_VCVARS = '<VS>\VC\Auxiliary\Build\vcvarsall.bat'
& .\client-extension\SoloCam\scripts\build.ps1

python -m unittest discover -s .\client-extension\SoloCam\tests -p "test_*.py" -v
```

Outputs stay in the ignored `client-extension/SoloCam/build` directory. Tests
that inspect a real executable only read
`SOLOCOLLECTIONS_WOW_EXE`; they must skip when the user has not supplied a
local file.

## Server module and pinned build metadata

Follow the
[`mod-solo-collections` README](https://github.com/haha2345/mod-solo-collections/blob/main/README.en.md)
to build the module with AzerothCore. A clean module clone has fallback build
metadata. A matched candidate should generate exact AddOn/module/Core metadata
before compiling:

```powershell
& .\tools\release\New-SoloCollectionsBuildInfo.ps1 `
  -AddonRoot $PWD `
  -ModuleRoot ..\mod-solo-collections `
  -CoreRoot <AzerothCore-source> `
  -CoreBuildRoot <AzerothCore-build> `
  -Configuration RelWithDebInfo
```

The generated module include is intentionally ignored.

## Unified source package

```powershell
python .\tools\release\build_unified_release.py `
  --version <version> `
  --addon-repo $PWD `
  --module-repo ..\mod-solo-collections `
  --core-repo <AzerothCore-source> `
  --output-dir (Join-Path $PWD '_work\release-candidate')
```

The packager admits project source, manifests, and license material. It rejects
executables, DLL/PDB/MPQ output, databases, credentials, and extracted client
assets. A public binary/client-resource release still requires a separate
provenance and licensing review.
