[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DeploymentManifest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-PathChecked {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label)
    if (-not [IO.Path]::IsPathRooted($Path) -or [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "$Label must be an absolute non-wildcard path: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($full.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full)) {
        throw "$Label is invalid: $full"
    }
    return $full
}

function Get-TreeHash {
    param([Parameter(Mandatory = $true)][string]$Root)
    $entries = foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $relative = $file.FullName.Substring($Root.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
        "$relative $((Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant())"
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes((($entries -join "`n") + "`n"))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return (($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $algorithm.Dispose() }
}

$manifestPath = Resolve-PathChecked $DeploymentManifest 'DeploymentManifest'
if (-not $manifestPath.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Deployment manifest must be on F:.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.kind -ne 'SoloCollectionsStage8PresentationAddonDeployment') { throw 'Unsupported deployment manifest.' }
$client = Resolve-PathChecked ([string]$manifest.clientRoot) 'ClientRoot'
if (Get-Process -Name 'Wow', 'Wow-SoloCam-PoC', 'Wow-CQM-SoloCam' -ErrorAction SilentlyContinue) {
    throw 'Close the client before restoring the production AddOn.'
}
$target = [IO.Path]::GetFullPath([string]$manifest.target)
if (-not $target.StartsWith($client + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $target -PathType Container)) {
    throw 'Installed AddOn target is missing or outside the client root.'
}
if ((Get-TreeHash $target) -ne [string]$manifest.installedTreeHash) {
    throw 'Installed AddOn changed after staging; refusing to overwrite it.'
}
$runRoot = Split-Path -Parent $manifestPath
$recovered = Join-Path $runRoot 'recovered-staged-SoloCollections'
if (Test-Path -LiteralPath $recovered) { throw "Recovery destination already exists: $recovered" }
Move-Item -LiteralPath $target -Destination $recovered
if ($manifest.hadTarget) {
    $backup = [IO.Path]::GetFullPath([string]$manifest.backupAddon)
    if (-not (Test-Path -LiteralPath $backup -PathType Container) -or (Get-TreeHash $backup) -ne [string]$manifest.beforeTreeHash) {
        throw 'Original AddOn backup is missing or changed.'
    }
    Move-Item -LiteralPath $backup -Destination $target
    if ((Get-TreeHash $target) -ne [string]$manifest.beforeTreeHash) { throw 'Original AddOn restore hash mismatch.' }
}
$result = [ordered]@{ schemaVersion=1; kind='SoloCollectionsStage8PresentationAddonRestore'; restoredAtUtc=[DateTime]::UtcNow.ToString('o'); deploymentManifest=$manifestPath; recoveredStagedAddon=$recovered; target=$target }
[IO.File]::WriteAllText((Join-Path $runRoot 'restore-manifest.json'), (($result | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 6
