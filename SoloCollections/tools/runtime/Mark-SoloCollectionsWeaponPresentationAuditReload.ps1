[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [string]$Method = 'computer-use'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not [IO.Path]::IsPathRooted($RunRoot) -or [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($RunRoot)) {
    throw "RunRoot must be an absolute non-wildcard path: $RunRoot"
}
$run = [IO.Path]::GetFullPath($RunRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
if (-not $run.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $run -PathType Container)) {
    throw "RunRoot must be an existing F: directory: $run"
}
$metadataPath = Join-Path $run 'run.json'
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw "Run metadata is missing: $metadataPath" }
$metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$metadata.cacheState -ne 'reload' -or [string]::IsNullOrWhiteSpace([string]$metadata.runId)) {
    throw 'Reload marker only applies to a reload-cache audit run.'
}
$markerPath = Join-Path $run 'reload-command.json'
if (Test-Path -LiteralPath $markerPath) { throw "Reload marker already exists: $markerPath" }
$marker = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsWeaponPresentationAuditReloadCommand'; runId=[string]$metadata.runId
    cacheState='reload'; method=$Method; sentUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($markerPath, (($marker | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$marker | ConvertTo-Json -Depth 6
