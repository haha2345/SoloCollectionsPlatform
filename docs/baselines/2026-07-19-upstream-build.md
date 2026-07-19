# 2026-07-19 Fork Bootstrap Build Baseline

## Result

PASS. A clean `RelWithDebInfo` configure and build produced both `authserver`
and `worldserver`, with `mod-solo-collections` linked statically into the
worldserver target.

The build used the unmodified upstream source at `33ac64b` plus the single
fork-bootstrap commit `17568dc`, which changes only the generated-loader entry
point from `Addmod_transmogScripts` to `Addmod_solo_collectionsScripts`. This
identity change is required because AzerothCore derives the expected entry
point from the module directory name.

## Revisions

| Component | Revision |
|---|---|
| AzerothCore | `bdb39abddb319eac0cd0755eedb3bffdb6490930` |
| mod-transmog upstream base | `33ac64b2c305eb1b6fbc97310a7ecbc30c2ba4ef` |
| mod-solo-collections build revision | `17568dcd51e79cfa0eb4fd0897b4f04b9724f3ba` |

Both source worktrees were clean when the result was recorded. The Core and
module worktrees, build directory, install prefix, and temporary directory were
all located outside the two project repositories on drive F.

## Toolchain and dependencies

| Item | Version/configuration |
|---|---|
| CMake | 4.3.3 |
| Generator | Visual Studio 18 2026, x64 |
| MSVC | 19.51.36248.0; toolset 14.51.36231 |
| Windows SDK | 10.0.26100.0 |
| Boost | 1.82.0 |
| OpenSSL | 3.0.10 |
| MySQL client development files | 8.4.10, x64 |

The installed Boost package records transitive dependencies as `lzma.lib`,
`z.lib`, and `zstd.lib`. The linker search path therefore included the existing
local compatibility-library directory as well as the dependency library
directory. No dependency files were copied into either repository.

## Configure contract

The successful clean configure was equivalent to:

```powershell
cmake -S $CoreWorktree -B $BuildDir `
  -G "Visual Studio 18 2026" -A x64 `
  -DCMAKE_GENERATOR_INSTANCE=$VisualStudioInstance `
  -DCMAKE_INSTALL_PREFIX=$InstallPrefix `
  -DMODULES=static `
  -DAPPS_BUILD=all `
  -DTOOLS_BUILD=none `
  -DBUILD_TESTING=OFF `
  -DBOOST_ROOT=$BoostRoot `
  -DOPENSSL_ROOT_DIR=$OpenSslRoot `
  -DMYSQL_INCLUDE_DIR=$MySqlInclude `
  -DMYSQL_LIBRARY=$MySqlLibrary `
  "-DCMAKE_EXE_LINKER_FLAGS=/machine:x64 /LIBPATH:$CompatibilityLib /LIBPATH:$DependencyLib"
```

The build command was:

```powershell
cmake --build $BuildDir --config RelWithDebInfo `
  --target authserver worldserver --parallel 8
```

CMake reported:

```text
Build applications : Yes (all)
Build tools        : No
Build with modules : Yes (static)
Build unit tests   : No
Modules            : mod-solo-collections
```

## Loader verification

The generated static module loader declares and invokes:

```cpp
void Addmod_solo_collectionsScripts();
Addmod_solo_collectionsScripts();
```

The module exports the same function from `src/transmog_loader.cpp`. The final
worldserver link completed without unresolved module symbols.

## Output evidence

| Output | Size | SHA-256 |
|---|---:|---|
| `authserver.exe` | 2,853,376 bytes | `23A4D89CF6ABA8044C8F97E07E756693CF7D8257FA263C7FA51BA8895920A239` |
| `worldserver.exe` | 36,211,712 bytes | `B2CAF2BEE0009E68E5EE8125BDA7E3D1B4BA48813CD2C7169689BA129A368478` |

These hashes identify this local baseline only; compiler or dependency changes
can legitimately produce different binaries.

## Reproduced setup failures

Two setup failures were resolved before the clean passing build:

1. Configure could not locate Boost until the existing dependency root was
   supplied explicitly.
2. The upstream loader name did not match the renamed module directory. The
   isolated `17568dc` bootstrap commit resolves that fork identity mismatch.

No SQL was installed and no production database or server process was started
for this baseline.
