[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$Version,
    [Parameter(Mandatory = $true)][string]$ClientDirectory,
    [ValidatePattern('^[A-Za-z]{4}$')][string]$Locale = 'zhCN',
    [ValidateRange(2, 9)][int]$LocalePatchNumber = 6,
    [string]$OutputRoot = '',
    [switch]$IncludeExternalMedia
)

$ErrorActionPreference = 'Stop'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$LicenseSource = Join-Path $RepoRoot 'LICENSE'
$ClientDirectory = [System.IO.Path]::GetFullPath($ClientDirectory)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot ("release\v{0}" -f $Version)
}
else {
    $OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "Refusing to overwrite an existing release directory: $OutputRoot"
}

$AddonSource = Join-Path $RepoRoot 'addon\SoloCollections'
$ServerSource = Join-Path $RepoRoot 'server\ale\solo_collections.lua'
$SoloCamRoot = Join-Path $RepoRoot 'client-extension\SoloCam'
$SoloCamDll = Join-Path $SoloCamRoot 'build\Release\SoloCam.dll'
$AssetMpq = Join-Path $ClientDirectory 'Data\Patch-W.MPQ'
$LocalePatchName = "patch-$Locale-$LocalePatchNumber.MPQ"
$LocaleMpq = Join-Path $ClientDirectory ("Data\{0}\{1}" -f $Locale, $LocalePatchName)
$ReadmeZh = Join-Path $PSScriptRoot 'RELEASE_README.zh-CN.md'
$ReadmeEn = Join-Path $PSScriptRoot 'RELEASE_README.en.md'

foreach ($required in @($LicenseSource, $AddonSource, $ServerSource, $SoloCamDll, $AssetMpq, $LocaleMpq, $ReadmeZh, $ReadmeEn)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required release input is missing: $required"
    }
}

$AddonDir = Join-Path $OutputRoot 'addon'
$ServerDir = Join-Path $OutputRoot 'server'
$ClientExtensionDir = Join-Path $OutputRoot 'client-extension'
$PatchDataDir = Join-Path $OutputRoot 'client-patches\Data'
$PatchLocaleDir = Join-Path $PatchDataDir $Locale
New-Item -ItemType Directory -Force -Path $AddonDir, $ServerDir, $ClientExtensionDir, $PatchLocaleDir | Out-Null

$AddonZip = Join-Path $AddonDir ("SoloCollections-v{0}.zip" -f $Version)
$ExternalMediaRoot = [System.IO.Path]::GetFullPath((Join-Path $AddonSource 'Media\Retail'))
$StageBase = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot '_work\release-stage'))
$StageRoot = Join-Path $StageBase ([Guid]::NewGuid().ToString('N'))
$AddonStage = Join-Path $StageRoot 'SoloCollections'

function Copy-AddonTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $itemPath = [System.IO.Path]::GetFullPath($item.FullName)
        if (-not $IncludeExternalMedia -and $item.PSIsContainer -and $itemPath -eq $ExternalMediaRoot) {
            continue
        }

        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-AddonTree -Source $item.FullName -Destination $target
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $target
        }
    }
}

try {
    Copy-AddonTree -Source $AddonSource -Destination $AddonStage
    Copy-Item -LiteralPath $LicenseSource -Destination (Join-Path $AddonStage 'LICENSE')
    Compress-Archive -LiteralPath $AddonStage -DestinationPath $AddonZip -CompressionLevel Optimal
}
finally {
    $resolvedStageBase = [System.IO.Path]::GetFullPath($StageBase).TrimEnd('\') + '\'
    $resolvedStageRoot = [System.IO.Path]::GetFullPath($StageRoot).TrimEnd('\') + '\'
    if ($resolvedStageRoot.StartsWith($resolvedStageBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $StageRoot)) {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force
    }
}
Copy-Item -LiteralPath $ServerSource -Destination (Join-Path $ServerDir 'solo_collections.lua')
Copy-Item -LiteralPath $SoloCamDll -Destination (Join-Path $ClientExtensionDir 'SoloCam.dll')
Copy-Item -LiteralPath (Join-Path $SoloCamRoot 'poc_patch.py') -Destination (Join-Path $ClientExtensionDir 'poc_patch.py')
Copy-Item -LiteralPath (Join-Path $SoloCamRoot 'requirements-dev.txt') -Destination (Join-Path $ClientExtensionDir 'requirements-dev.txt')
Copy-Item -LiteralPath $AssetMpq -Destination (Join-Path $PatchDataDir 'Patch-W.MPQ')
Copy-Item -LiteralPath $LocaleMpq -Destination (Join-Path $PatchLocaleDir $LocalePatchName)
Copy-Item -LiteralPath $LicenseSource -Destination (Join-Path $OutputRoot 'LICENSE')
Copy-Item -LiteralPath $ReadmeZh -Destination (Join-Path $OutputRoot 'README.zh-CN.md')
Copy-Item -LiteralPath $ReadmeEn -Destination (Join-Path $OutputRoot 'README.en.md')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($releaseReadme in @((Join-Path $OutputRoot 'README.zh-CN.md'), (Join-Path $OutputRoot 'README.en.md'))) {
    $readmeText = [System.IO.File]::ReadAllText($releaseReadme)
    $readmeText = $readmeText.Replace('{{VERSION}}', $Version).Replace('{{LOCALE}}', $Locale).Replace('{{LOCALE_PATCH}}', $LocalePatchName)
    [System.IO.File]::WriteAllText($releaseReadme, $readmeText, $Utf8NoBom)
}

function Get-RelativePathCompat {
    param([Parameter(Mandatory = $true)][string]$BasePath, [Parameter(Mandatory = $true)][string]$ChildPath)
    $base = $BasePath.TrimEnd('\') + '\'
    $baseUri = [Uri]::new($base)
    $childUri = [Uri]::new($ChildPath)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
}

$ChecksumPath = Join-Path $OutputRoot 'SHA256SUMS.txt'
$Lines = foreach ($file in Get-ChildItem -LiteralPath $OutputRoot -Recurse -File | Sort-Object FullName) {
    if ($file.FullName -eq $ChecksumPath) { continue }
    $relative = Get-RelativePathCompat $OutputRoot $file.FullName
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
}
[System.IO.File]::WriteAllLines($ChecksumPath, $Lines, $Utf8NoBom)

Write-Output "Local release created: $OutputRoot"
Write-Output "Locale patch: $LocalePatchName"
Write-Output "Checksums: $ChecksumPath"
if ($IncludeExternalMedia) {
    Write-Warning 'The AddOn archive includes external Retail media. Do not upload it until provenance and redistribution rights are confirmed.'
}
else {
    Write-Output 'External Retail media was excluded from the AddOn archive. Install it separately from the maintainer media pack.'
}
Write-Warning 'The release directory is ignored by Git. Audit media and distribution rights before uploading any binary.'
