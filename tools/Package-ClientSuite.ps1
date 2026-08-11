[CmdletBinding()]
param(
    [string] $Version = 'development',
    [string] $PackageRoot = (Join-Path $PSScriptRoot '..\build\packages'),
    [string] $SoloCollectionsSource = (Join-Path $PSScriptRoot '..\..\SoloCollections\addon\SoloCollections'),
    [string] $EzCollectionsSource = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $suiteRoot 'build\packages'))
$output = [IO.Path]::GetFullPath($PackageRoot)
if ($output -ne $allowedRoot) { throw "PackageRoot must be the suite's exact build/packages directory: $output" }
if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') { throw 'Version contains unsupported characters.' }

$buildParameters = @{ SoloCollectionsSource = $SoloCollectionsSource }
if (-not [string]::IsNullOrWhiteSpace($EzCollectionsSource)) {
    $buildParameters.EzCollectionsSource = $EzCollectionsSource
}
& (Join-Path $PSScriptRoot 'Build-ClientSuite.ps1') @buildParameters
$buildRoot = Join-Path $suiteRoot 'build'
$addonsRoot = Join-Path $buildRoot 'Interface\AddOns'
[IO.Directory]::CreateDirectory($output) | Out-Null
$archive = Join-Path $output "SoloClientSuite-$Version-integrated-ui.zip"
$manifestPath = Join-Path $output "SoloClientSuite-$Version-SHA256.json"
if ((Test-Path -LiteralPath $archive) -or (Test-Path -LiteralPath $manifestPath)) {
    throw "Refusing to overwrite an existing package for version $Version"
}

$files = Get-ChildItem -LiteralPath $addonsRoot -File -Recurse | Sort-Object FullName
$ezUiProvenancePath = Join-Path $addonsRoot 'SoloCollections_EzUI\EZUI-PROVENANCE.json'
$manifest = [ordered]@{
    schemaVersion = 2
    version = $Version
    installRoot = 'Interface/AddOns'
    suiteLock = (Get-Content -LiteralPath (Join-Path $suiteRoot 'upstream\suite-lock.json') -Raw | ConvertFrom-Json)
    localEzCollectionsUI = if (Test-Path -LiteralPath $ezUiProvenancePath -PathType Leaf) {
        Get-Content -LiteralPath $ezUiProvenancePath -Raw | ConvertFrom-Json
    } else { $null }
    files = @($files | ForEach-Object {
        [ordered]@{
            path = ('Interface/AddOns/' + [IO.Path]::GetRelativePath($addonsRoot, $_.FullName).Replace('\', '/'))
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

Add-Type -AssemblyName System.IO.Compression
$stream = [IO.File]::Open($archive, [IO.FileMode]::CreateNew)
try {
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($file in $files) {
            $relative = [IO.Path]::GetRelativePath($addonsRoot, $file.FullName).Replace('\', '/')
            $entry = $zip.CreateEntry("Interface/AddOns/$relative", [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $source = [IO.File]::OpenRead($file.FullName)
            $target = $entry.Open()
            try { $source.CopyTo($target) } finally { $target.Dispose(); $source.Dispose() }
        }
    } finally { $zip.Dispose() }
} finally { $stream.Dispose() }
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest.archive = [ordered]@{ file = [IO.Path]::GetFileName($archive); sha256 = $archiveHash }
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
Write-Output "Integrated package: $archive"
Write-Output "Package SHA-256: $archiveHash"
Write-Output "File manifest: $manifestPath"
