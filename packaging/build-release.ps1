[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$Version,
    [switch]$AllowUnauditedLocalMedia,
    [switch]$IncludeSoloCam
)

$ErrorActionPreference = 'Stop'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$AddonSource = Join-Path $RepoRoot 'addon\SoloCollections'
$ServerSource = Join-Path $RepoRoot 'server\ale\solo_collections.lua'
$AssetManifest = Join-Path $AddonSource 'Media\assets.json'
$OutputRoot = Join-Path $PSScriptRoot 'out'
$RunId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$StageRoot = Join-Path $OutputRoot "stage-$Version-$RunId"

foreach ($required in @($AddonSource, $ServerSource, $AssetManifest)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required release input is missing: $required"
    }
}

$AssetState = Get-Content -LiteralPath $AssetManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$PublicStatus = $AssetState.distribution.publicStatus
if ($PublicStatus -ne 'approved' -and -not $AllowUnauditedLocalMedia) {
    throw "Public media gate is closed ($PublicStatus). Replace/audit assets or use -AllowUnauditedLocalMedia for a private preview only."
}

New-Item -ItemType Directory -Force -Path $OutputRoot, $StageRoot | Out-Null
$AddonStage = Join-Path $StageRoot 'SoloCollections'
$ServerStage = Join-Path $StageRoot 'server-ale'
New-Item -ItemType Directory -Force -Path $AddonStage, $ServerStage | Out-Null
Get-ChildItem -LiteralPath $AddonSource -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $AddonStage -Recurse -Force
}
Copy-Item -LiteralPath $ServerSource -Destination (Join-Path $ServerStage 'solo_collections.lua') -Force

$Suffix = if ($PublicStatus -eq 'approved') { '' } else { '-PRIVATE-UNAUDITED' }
$AddonZip = Join-Path $OutputRoot "SoloCollections-$Version-addon$Suffix.zip"
$ServerZip = Join-Path $OutputRoot "SoloCollections-$Version-server-ale.zip"
foreach ($target in @($AddonZip, $ServerZip)) {
    if (Test-Path -LiteralPath $target) {
        throw "Refusing to overwrite an existing release archive: $target"
    }
}

Compress-Archive -LiteralPath $AddonStage -DestinationPath $AddonZip -CompressionLevel Optimal
Compress-Archive -LiteralPath (Join-Path $ServerStage 'solo_collections.lua') -DestinationPath $ServerZip -CompressionLevel Optimal

$Artifacts = @($AddonZip, $ServerZip)
if ($IncludeSoloCam) {
    $SoloCamRoot = Join-Path $RepoRoot 'client-extension\SoloCam'
    $SoloCamDll = Join-Path $SoloCamRoot 'build\Release\SoloCam.dll'
    if (-not (Test-Path -LiteralPath $SoloCamDll -PathType Leaf)) {
        throw "Build SoloCam first; DLL is missing: $SoloCamDll"
    }
    $SoloCamStage = Join-Path $StageRoot 'SoloCam'
    New-Item -ItemType Directory -Force -Path $SoloCamStage | Out-Null
    foreach ($file in @('README.md', 'poc_patch.py', 'requirements-dev.txt')) {
        Copy-Item -LiteralPath (Join-Path $SoloCamRoot $file) -Destination (Join-Path $SoloCamStage $file) -Force
    }
    Copy-Item -LiteralPath $SoloCamDll -Destination (Join-Path $SoloCamStage 'SoloCam.dll') -Force
    $SoloCamZip = Join-Path $OutputRoot "SoloCam-$Version-win32.zip"
    if (Test-Path -LiteralPath $SoloCamZip) {
        throw "Refusing to overwrite an existing release archive: $SoloCamZip"
    }
    Compress-Archive -LiteralPath $SoloCamStage -DestinationPath $SoloCamZip -CompressionLevel Optimal
    $Artifacts += $SoloCamZip
}

$ChecksumPath = Join-Path $OutputRoot "SHA256SUMS-$Version$Suffix.txt"
if (Test-Path -LiteralPath $ChecksumPath) {
    throw "Refusing to overwrite an existing checksum file: $ChecksumPath"
}
$Lines = foreach ($artifact in $Artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([System.IO.Path]::GetFileName($artifact))"
}
[System.IO.File]::WriteAllLines($ChecksumPath, $Lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "Release staging: $StageRoot"
foreach ($artifact in $Artifacts) { Write-Output "Artifact: $artifact" }
Write-Output "Checksums: $ChecksumPath"
