[CmdletBinding()]
param(
    [string]$VcVars = $env:SOLOCOLLECTIONS_VCVARS
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildRoot = Join-Path $ProjectRoot 'build'
$ReleaseRoot = Join-Path $BuildRoot 'Release'
$TestRoot = Join-Path $BuildRoot 'Tests'
$ObjectRoot = Join-Path $BuildRoot 'obj'
$TempRoot = Join-Path $BuildRoot 'temp'

if ([string]::IsNullOrWhiteSpace($VcVars)) {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $VsWhere -PathType Leaf) {
        $InstallRoot = & $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($InstallRoot) {
            $VcVars = Join-Path ($InstallRoot | Select-Object -First 1) 'VC\Auxiliary\Build\vcvarsall.bat'
        }
    }
}

if ([string]::IsNullOrWhiteSpace($VcVars) -or -not (Test-Path -LiteralPath $VcVars -PathType Leaf)) {
    throw "Visual C++ environment not found: $VcVars"
}

New-Item -ItemType Directory -Force -Path $ReleaseRoot, $TestRoot, $ObjectRoot, $TempRoot | Out-Null
$env:TEMP = $TempRoot
$env:TMP = $TempRoot

$CameraProfileTest = Join-Path $TestRoot 'CameraProfileTests.exe'
$DisplayInfoBridgeTest = Join-Path $TestRoot 'DisplayInfoBridgeTests.exe'
$ItemCameraBridgeTest = Join-Path $TestRoot 'ItemCameraBridgeTests.exe'
$BodyCameraBridgeTest = Join-Path $TestRoot 'BodyCameraBridgeTests.exe'
$LoadLibraryProbe = Join-Path $TestRoot 'LoadLibraryProbe.exe'
$ProcessProbe = Join-Path $TestRoot 'ProcessProbe.exe'
$SoloCamDll = Join-Path $ReleaseRoot 'SoloCam.dll'
$SoloCamPdb = Join-Path $ReleaseRoot 'SoloCam.pdb'

$TestCommand = @(
    "call `"$VcVars`" x86 >nul",
    "cd /d `"$ObjectRoot`"",
    "cl.exe /nologo /std:c++17 /EHsc /MT /W4 /WX `"$ProjectRoot\tests\CameraProfileTests.cpp`" `"$ProjectRoot\src\CameraProfile.cpp`" /I`"$ProjectRoot\src`" /Fe:`"$CameraProfileTest`""
) -join ' && '

& cmd.exe /d /s /c $TestCommand
if ($LASTEXITCODE -ne 0) {
    throw "Camera profile test build failed with exit code $LASTEXITCODE"
}

& $CameraProfileTest
if ($LASTEXITCODE -ne 0) {
    throw "Camera profile tests failed with exit code $LASTEXITCODE"
}

$DisplayInfoTestCommand = @(
    "call `"$VcVars`" x86 >nul",
    "cd /d `"$ObjectRoot`"",
    "cl.exe /nologo /std:c++17 /EHsc /MT /W4 /WX `"$ProjectRoot\tests\DisplayInfoBridgeTests.cpp`" `"$ProjectRoot\src\DisplayInfoBridge.cpp`" /I`"$ProjectRoot\src`" /Fe:`"$DisplayInfoBridgeTest`""
) -join ' && '

& cmd.exe /d /s /c $DisplayInfoTestCommand
if ($LASTEXITCODE -ne 0) {
    throw "Display-info bridge test build failed with exit code $LASTEXITCODE"
}

& $DisplayInfoBridgeTest
if ($LASTEXITCODE -ne 0) {
    throw "Display-info bridge tests failed with exit code $LASTEXITCODE"
}

$ItemCameraTestCommand = @(
    "call `"$VcVars`" x86 >nul",
    "cd /d `"$ObjectRoot`"",
    "cl.exe /nologo /std:c++17 /EHsc /MT /W4 /WX `"$ProjectRoot\tests\ItemCameraBridgeTests.cpp`" `"$ProjectRoot\src\ItemCameraBridge.cpp`" /I`"$ProjectRoot\src`" /Fe:`"$ItemCameraBridgeTest`""
) -join ' && '

& cmd.exe /d /s /c $ItemCameraTestCommand
if ($LASTEXITCODE -ne 0) {
    throw "Item-camera bridge test build failed with exit code $LASTEXITCODE"
}

& $ItemCameraBridgeTest
if ($LASTEXITCODE -ne 0) {
    throw "Item-camera bridge tests failed with exit code $LASTEXITCODE"
}

$BodyCameraTestCommand = @(
    "call `"$VcVars`" x86 >nul",
    "cd /d `"$ObjectRoot`"",
    "cl.exe /nologo /std:c++17 /EHsc /MT /W4 /WX `"$ProjectRoot\tests\BodyCameraBridgeTests.cpp`" `"$ProjectRoot\src\CameraProfile.cpp`" `"$ProjectRoot\src\BodyCameraBridge.cpp`" `"$ProjectRoot\src\ItemCameraBridge.cpp`" `"$ProjectRoot\src\DisplayInfoBridge.cpp`" /I`"$ProjectRoot\src`" /Fe:`"$BodyCameraBridgeTest`""
) -join ' && '

& cmd.exe /d /s /c $BodyCameraTestCommand
if ($LASTEXITCODE -ne 0) {
    throw "Body-camera bridge test build failed with exit code $LASTEXITCODE"
}

& $BodyCameraBridgeTest
if ($LASTEXITCODE -ne 0) {
    throw "Body-camera bridge tests failed with exit code $LASTEXITCODE"
}

$ProbeCommand = @(
    "call `"$VcVars`" x86 >nul",
    "cd /d `"$ObjectRoot`"",
    "cl.exe /nologo /std:c++17 /EHsc /MT /W4 /WX `"$ProjectRoot\tests\LoadLibraryProbe.cpp`" /Fe:`"$LoadLibraryProbe`""
) -join ' && '

& cmd.exe /d /s /c $ProbeCommand
if ($LASTEXITCODE -ne 0) {
    throw "LoadLibrary probe build failed with exit code $LASTEXITCODE"
}

$ProcessProbeCommand = @(
    "call `"$VcVars`" x86 >nul",
    "cd /d `"$ObjectRoot`"",
    "cl.exe /nologo /std:c++17 /EHsc /MT /W4 /WX `"$ProjectRoot\tests\ProcessProbe.cpp`" /Fe:`"$ProcessProbe`""
) -join ' && '

& cmd.exe /d /s /c $ProcessProbeCommand
if ($LASTEXITCODE -ne 0) {
    throw "Process probe build failed with exit code $LASTEXITCODE"
}

$DllCommand = @(
    "call `"$VcVars`" x86 >nul",
    "cd /d `"$ObjectRoot`"",
    "cl.exe /nologo /std:c++17 /LD /O2 /EHsc /MT /W4 /WX /DWIN32 /D_WINDOWS `"$ProjectRoot\src\SoloCam.cpp`" `"$ProjectRoot\src\InlineHook.cpp`" `"$ProjectRoot\src\CameraProfile.cpp`" `"$ProjectRoot\src\BodyCameraBridge.cpp`" `"$ProjectRoot\src\DisplayInfoBridge.cpp`" `"$ProjectRoot\src\ItemCameraBridge.cpp`" `"$ProjectRoot\src\PreviewItemBridge.cpp`" /I`"$ProjectRoot\src`" /link user32.lib /OUT:`"$SoloCamDll`" /PDB:`"$SoloCamPdb`""
) -join ' && '

& cmd.exe /d /s /c $DllCommand
if ($LASTEXITCODE -ne 0) {
    throw "SoloCam.dll build failed with exit code $LASTEXITCODE"
}

Write-Host "Built x86 PoC DLL: $SoloCamDll"
Write-Host "Built x86 loader probe: $LoadLibraryProbe"
Write-Host "Built x86 process probe: $ProcessProbe"
