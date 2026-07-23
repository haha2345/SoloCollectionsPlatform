[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientRoot,
    [Parameter(Mandatory = $true)][string]$AddonSource,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-PathChecked {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label, [bool]$MustExist = $true)
    if (-not [IO.Path]::IsPathRooted($Path) -or [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "$Label must be an absolute non-wildcard path: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($full.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Label must not target C: $full" }
    if ($MustExist -and -not (Test-Path -LiteralPath $full)) { throw "$Label is missing: $full" }
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

$client = Resolve-PathChecked $ClientRoot 'ClientRoot'
$source = Resolve-PathChecked $AddonSource 'AddonSource'
$evidence = Resolve-PathChecked $EvidenceRoot 'EvidenceRoot' $false
if (-not $source.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase) -or -not $evidence.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'AddonSource and EvidenceRoot must be on F:.'
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'SoloCollections.toc') -PathType Leaf)) {
    throw "AddonSource is not a SoloCollections AddOn: $source"
}
if (Get-Process -Name 'Wow', 'Wow-SoloCam-PoC', 'Wow-CQM-SoloCam' -ErrorAction SilentlyContinue) {
    throw 'Close the client before staging the production AddOn.'
}
$target = Join-Path $client 'Interface\AddOns\SoloCollections'
$targetParent = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) { throw "Client AddOns path is missing: $targetParent" }
$runId = 'stage8-presentation-addon-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$runRoot = Join-Path $evidence $runId
if (Test-Path -LiteralPath $runRoot) { throw "Deployment evidence path already exists: $runRoot" }
$backupRoot = Join-Path $runRoot 'backup'
$backupAddon = Join-Path $backupRoot 'SoloCollections'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$hadTarget = Test-Path -LiteralPath $target -PathType Container
$beforeHash = if ($hadTarget) { Get-TreeHash $target } else { $null }
$sourceHash = Get-TreeHash $source
$moved = $false
try {
    if ($hadTarget) {
        Move-Item -LiteralPath $target -Destination $backupAddon
        $moved = $true
    }
    Copy-Item -LiteralPath $source -Destination $target -Recurse
    $installedHash = Get-TreeHash $target
    if ($installedHash -ne $sourceHash) { throw 'Staged AddOn tree hash does not match source.' }
}
catch {
    if (Test-Path -LiteralPath $target -PathType Container) {
        Move-Item -LiteralPath $target -Destination (Join-Path $backupRoot 'failed-new-SoloCollections')
    }
    if ($moved -and (Test-Path -LiteralPath $backupAddon -PathType Container)) {
        Move-Item -LiteralPath $backupAddon -Destination $target
    }
    throw
}
$manifest = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsStage8PresentationAddonDeployment'; runId=$runId
    deployedAtUtc=[DateTime]::UtcNow.ToString('o'); clientRoot=$client; addonSource=$source; target=$target
    hadTarget=$hadTarget; beforeTreeHash=$beforeHash; sourceTreeHash=$sourceHash; installedTreeHash=(Get-TreeHash $target)
    backupAddon=if ($hadTarget) { $backupAddon } else { $null }
}
$manifestPath = Join-Path $runRoot 'deployment-manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "deployment_manifest=$manifestPath"
Write-Host "installed_tree_hash=$($manifest.installedTreeHash)"
