[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleId,
    [Parameter(Mandatory)][string]$AddonRoot,
    [Parameter(Mandatory)][string]$ModuleRoot,
    [Parameter(Mandatory)][string]$CoreRoot,
    [Parameter(Mandatory)][string]$CoreBuildRoot,
    [Parameter(Mandatory)][string]$WorldserverPath,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$SoloCamPath = '',
    [string[]]$AssetPatchPaths = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'RoundTwoRelease.Common.ps1')

if ($BundleId -notmatch '^round2-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{7}-[0-9a-f]{7}-[0-9a-f]{7}$') { throw "Invalid bundle ID: $BundleId" }
$addon = Resolve-RoundTwoPath $AddonRoot
$module = Resolve-RoundTwoPath $ModuleRoot
$core = Resolve-RoundTwoPath $CoreRoot
$build = Resolve-RoundTwoPath $CoreBuildRoot
$worldserver = Resolve-RoundTwoPath $WorldserverPath
$evidence = Resolve-RoundTwoPath $EvidenceRoot
$output = Resolve-RoundTwoPath $OutputRoot -AllowMissing
Assert-RoundTwoWithin -Path $worldserver -Root $build
Assert-RoundTwoCleanTracked $addon
Assert-RoundTwoCleanTracked $module
Assert-RoundTwoBaseMedia -AddonRoot (Join-Path $addon 'addon\SoloCollections')
$pe = Get-RoundTwoPeInfo $worldserver
if (-not $pe.IsX64) { throw "worldserver.exe is not x64" }
$metadataPath = Join-Path $build 'module-build-metadata.json'
$contextPath = Join-Path $build 'round-two-build-context.json'
$metadata = Read-RoundTwoJson $metadataPath
$context = Read-RoundTwoJson $contextPath
if ((Get-Item -LiteralPath $worldserver).LastWriteTimeUtc -lt [DateTime]::Parse([string]$context.buildStartedAtUtc).ToUniversalTime()) {
    throw "worldserver.exe predates this build start"
}
if ((Get-RoundTwoSha256 $worldserver) -ne [string]$metadata.worldserverSha256) { throw "worldserver hash differs from module build metadata" }
if (Test-Path -LiteralPath $output) {
    if (@(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) { throw "Bundle output must be absent or empty: $output" }
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
foreach ($relative in @('addon\SoloCollections','server\runtime-dependencies','server\config','server\symbols','client\assets','evidence','backup','reports')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $output $relative) | Out-Null
}

$addonPrefix = 'addon/SoloCollections/'
$tracked = @(& git -C $addon ls-files -- 'addon/SoloCollections')
if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) { throw "Cannot enumerate release AddOn files" }
foreach ($relative in $tracked) {
    $source = Join-Path $addon ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Tracked AddOn file is missing: $relative" }
    $destination = Join-Path $output ('addon\SoloCollections\' + $relative.Substring($addonPrefix.Length).Replace('/', '\'))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}
Assert-RoundTwoBaseMedia -AddonRoot (Join-Path $output 'addon\SoloCollections')
Copy-Item -LiteralPath $worldserver -Destination (Join-Path $output 'server\worldserver.exe')
$configSource = Join-Path $module 'conf\transmog.conf.dist'
if (-not (Test-Path -LiteralPath $configSource -PathType Leaf)) { throw "Missing module config template" }
Copy-Item -LiteralPath $configSource -Destination (Join-Path $output 'server\config\transmog.conf.dist')
Copy-Item -LiteralPath $metadataPath -Destination (Join-Path $output 'server\module-build-metadata.json')
$pdbRecord = [ordered]@{ status='UNAVAILABLE'; fileName='worldserver.pdb'; sha256='' }
if ($metadata.pdb.status -eq 'LOCAL_ONLY') { $pdbRecord.status='LOCAL_ONLY'; $pdbRecord.sha256=[string]$metadata.pdb.sha256 }
Write-RoundTwoJson $pdbRecord (Join-Path $output 'server\symbols\worldserver.pdb.sha256')
$evidenceManifest = Join-Path $evidence 'evidence-manifest.json'
if (-not (Test-Path -LiteralPath $evidenceManifest -PathType Leaf)) { throw "Evidence manifest is missing" }
Copy-Item -LiteralPath $evidenceManifest -Destination (Join-Path $output 'evidence\evidence-manifest.json')
foreach ($report in Get-ChildItem -LiteralPath (Join-Path $addon 'docs\reports') -File -Filter '*.md') {
    Copy-Item -LiteralPath $report.FullName -Destination (Join-Path $output ('reports\' + $report.Name))
}

$systemImports = @(
    'advapi32.dll','bcrypt.dll','crypt32.dll','dbghelp.dll','gdi32.dll','iphlpapi.dll','kernel32.dll',
    'msvcp_win.dll','netapi32.dll','ntdll.dll','ole32.dll','oleaut32.dll','rpcrt4.dll','secur32.dll',
    'shell32.dll','shlwapi.dll','ucrtbase.dll','user32.dll','userenv.dll','version.dll','winhttp.dll',
    'winmm.dll','ws2_32.dll'
)
$dependencyRecords = @()
$worldDir = Split-Path -Parent $worldserver
foreach ($name in $pe.Imports) {
    $systemPath = Join-Path $env:WINDIR ('System32\' + $name)
    if ($name -in $systemImports -or $name -like 'api-ms-win-*' -or (Test-Path -LiteralPath $systemPath -PathType Leaf)) {
        $dependencyRecords += [ordered]@{ fileName=$name; classification='WINDOWS_SYSTEM'; sha256='' }
        continue
    }
    $candidate = Join-Path $worldDir $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        Copy-Item -LiteralPath $candidate -Destination (Join-Path $output ('server\runtime-dependencies\' + $name))
        $dependencyRecords += [ordered]@{ fileName=$name; classification='BUNDLED_NON_SYSTEM'; sha256=Get-RoundTwoSha256 $candidate }
    }
    else {
        $dependencyRecords += [ordered]@{ fileName=$name; classification='DEPLOYMENT_ENVIRONMENT_FIXED'; sha256='UNAVAILABLE' }
    }
}

$capabilities = [ordered]@{
    soloCam = [ordered]@{ status='UNAVAILABLE'; sha256=''; fileName='SoloCam.dll' }
    assetPatches = @()
}
if ($SoloCamPath) {
    $soloCam = Resolve-RoundTwoPath $SoloCamPath
    Copy-Item -LiteralPath $soloCam -Destination (Join-Path $output 'client\SoloCam.dll')
    $capabilities.soloCam = [ordered]@{ status='VERIFIED'; sha256=Get-RoundTwoSha256 $soloCam; fileName='SoloCam.dll' }
}
foreach ($assetPath in $AssetPatchPaths) {
    $asset = Resolve-RoundTwoPath $assetPath
    $name = Split-Path -Leaf $asset
    if ($name -notmatch '(?i)\.mpq$') { throw "Only explicit MPQ patch files are accepted: $asset" }
    Copy-Item -LiteralPath $asset -Destination (Join-Path $output ('client\assets\' + $name))
    $capabilities.assetPatches += [ordered]@{ status='VERIFIED'; fileName=$name; sha256=Get-RoundTwoSha256 $asset }
}
if ($capabilities.assetPatches.Count -eq 0) { $capabilities.assetPatches = @([ordered]@{ status='UNAVAILABLE'; fileName=''; sha256='' }) }

$values = $metadata.values
foreach ($pair in @(@('addonCommit',$addon),@('moduleCommit',$module),@('coreCommit',$core))) {
    if ([string]$values.($pair[0]) -ne (Get-RoundTwoCommit $pair[1])) { throw "$($pair[0]) differs from build metadata" }
}
$manifest = [ordered]@{
    schemaVersion = 1; bundleId = $BundleId; createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    build = $values; configuration = [string]$metadata.configuration
    worldserver = [ordered]@{ sha256=Get-RoundTwoSha256 $worldserver; machine=$pe.Machine; modules='static' }
    dependencies = $dependencyRecords; capabilities = $capabilities
    evidence = [ordered]@{ manifestSha256=Get-RoundTwoSha256 $evidenceManifest; sourcePackHash=[string](Read-RoundTwoJson $evidenceManifest).packHash }
    files = @()
}
foreach ($file in Get-ChildItem -LiteralPath $output -Recurse -File | Where-Object { $_.Name -ne 'release-manifest.json' } | Sort-Object FullName) {
    $relative = $file.FullName.Substring($output.Length + 1).Replace('\','/')
    $manifest.files += [ordered]@{ relativePath=$relative; size=$file.Length; sha256=Get-RoundTwoSha256 $file.FullName }
}
Write-RoundTwoJson $manifest (Join-Path $output 'release-manifest.json')
Write-Host "bundle_root=$output"
Write-Host "bundle_id=$BundleId"
Write-Host "worldserver_sha256=$($manifest.worldserver.sha256)"
Write-Host "file_count=$($manifest.files.Count)"
