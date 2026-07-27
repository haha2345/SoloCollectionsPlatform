[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallationManifest,
    [Parameter(Mandatory = $true)][string]$ClientRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-AbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) { throw "Wildcard paths are forbidden: $Path" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) { throw "Required path is missing: $full" }
    return $full
}

function Assert-UnderRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    $fullPath = Resolve-AbsolutePath $Path -AllowMissing
    $fullRoot = Resolve-AbsolutePath $Root -AllowMissing
    $prefix = $fullRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes approved root: $fullPath" }
    return $fullPath
}

function Get-Sha256 { param([Parameter(Mandatory = $true)][string]$Path) return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

$manifestPath = Resolve-AbsolutePath $InstallationManifest
$client = Resolve-AbsolutePath $ClientRoot
if ($manifestPath.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase) -or $client.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installation manifest and client root must not be on C:.'
}
if (Get-Process -Name 'Wow', 'Wow-SoloCam-PoC', 'Wow-CQM-SoloCam' -ErrorAction SilentlyContinue) {
    throw 'The client must be closed before restore.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.kind -ne 'SoloCollectionsWeaponShadowInstallation' -or $manifest.status -ne 'INSTALLED') {
    throw 'Unsupported installation manifest.'
}
if ([IO.Path]::GetFullPath([string]$manifest.clientRoot) -ne $client) {
    throw 'Client root differs from the installation manifest.'
}
$dataRoot = Assert-UnderRoot (Join-Path $client 'Data') $client
$runRoot = Split-Path -Parent $manifestPath
$recoveredRoot = Join-Path $runRoot 'recovered-new-files'
New-Item -ItemType Directory -Force -Path $recoveredRoot | Out-Null
$restored = New-Object System.Collections.Generic.List[object]
foreach ($record in @($manifest.records)) {
    $target = Assert-UnderRoot ([string]$record.target) $dataRoot
    if ($record.existedBefore) { throw 'This first-time-only recovery script refuses a replacement-style manifest.' }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Installed target is already absent: $target" }
    if ((Get-Sha256 $target) -ne [string]$record.installedSha256) { throw "Installed target changed after deployment: $target" }
    $destination = Join-Path $recoveredRoot ([IO.Path]::GetFileName($target))
    if (Test-Path -LiteralPath $destination) { throw "Recovery destination already exists: $destination" }
    Move-Item -LiteralPath $target -Destination $destination
    $restored.Add([ordered]@{ target=$target; recoveredCopy=$destination; sha256=Get-Sha256 $destination; originalState='ABSENT' }) | Out-Null
}
$result = [ordered]@{ schemaVersion=1; kind='SoloCollectionsWeaponShadowRestore'; restoredAtUtc=[DateTime]::UtcNow.ToString('o'); installationManifest=$manifestPath; restored=$restored }
[IO.File]::WriteAllText((Join-Path $runRoot 'restore-manifest.json'), (($result | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "restore_manifest=$(Join-Path $runRoot 'restore-manifest.json')"
Write-Host "restored_count=$($restored.Count)"
