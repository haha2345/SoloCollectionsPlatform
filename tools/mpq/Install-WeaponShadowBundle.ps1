[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [Parameter(Mandatory = $true)][string]$ClientRoot,
    [Parameter(Mandatory = $true)][string]$AssetTargetRelativePath,
    [Parameter(Mandatory = $true)][string]$LocaleTargetRelativePath,
    [Parameter(Mandatory = $true)][string]$BackupRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-AbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "Wildcard paths are forbidden: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Required path is missing: $full"
    }
    return $full
}

function Assert-NonCPath {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label)
    if ($Path.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must not target C: $Path"
    }
}

function Assert-UnderRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root, [string]$Label)
    $fullPath = Resolve-AbsolutePath $Path -AllowMissing
    $fullRoot = Resolve-AbsolutePath $Root -AllowMissing
    $prefix = $fullRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escapes its approved root: $fullPath"
    }
    return $fullPath
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Convert-TargetRelativePath {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ([IO.Path]::IsPathRooted($Value) -or [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Value)) {
        throw "Target must be a plain relative path: $Value"
    }
    $relative = $Value.Replace('/', '\').TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains(':') -or $relative.Split('\') -contains '..') {
        throw "Unsafe target relative path: $Value"
    }
    if (-not $relative.EndsWith('.mpq', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target must be an MPQ file: $Value"
    }
    return $relative
}

function Assert-HighPriorityLocaleTarget {
    param([Parameter(Mandatory = $true)][string]$Relative)
    $parts = @($Relative.Split('\'))
    if ($parts.Count -ne 3 -or -not [string]::Equals($parts[0], 'Data', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Locale target must be Data\\<locale>\\patch-<locale>-z.MPQ: $Relative"
    }
    $locale = $parts[1]
    if ([string]::IsNullOrWhiteSpace($locale)) {
        throw "Locale target has no locale segment: $Relative"
    }
    $expectedFileName = "patch-$locale-z.MPQ"
    if (-not [string]::Equals($parts[2], $expectedFileName, [StringComparison]::OrdinalIgnoreCase)) {
        # Numeric suffixes are not a safe priority contract: in this client a
        # later existing locale patch can silently replace the generated DBC.
        throw "Locale target must use the high-priority $expectedFileName name: $Relative"
    }
}

$bundle = Resolve-AbsolutePath $BundleRoot
$client = Resolve-AbsolutePath $ClientRoot
$backup = Resolve-AbsolutePath $BackupRoot -AllowMissing
Assert-NonCPath $bundle 'BundleRoot'
Assert-NonCPath $client 'ClientRoot'
Assert-NonCPath $backup 'BackupRoot'
if (-not $backup.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "BackupRoot must be on F:, got: $backup"
}
if (Get-Process -Name 'Wow', 'Wow-SoloCam-PoC', 'Wow-CQM-SoloCam' -ErrorAction SilentlyContinue) {
    throw 'The client must be closed before a weapon bundle is installed.'
}

$ownerPath = Join-Path $bundle 'ownership.json'
$packPath = Join-Path $bundle 'weapon-mpq-manifest.json'
if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf) -or -not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
    throw 'Bundle ownership or MPQ manifest is missing.'
}
$owner = Get-Content -LiteralPath $ownerPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pack = Get-Content -LiteralPath $packPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($owner.owner -ne 'SoloCollectionsWeaponShadow' -or $pack.kind -ne 'SoloCollectionsWeaponShadowMpqBundle' -or
    [string]$owner.bundleId -ne [string]$pack.bundleId) {
    throw 'Bundle ownership contract mismatch.'
}
if ($pack.deployment.status -ne 'NOT_DEPLOYED') { throw 'Bundle is not eligible for first-time deployment.' }
$assetArchive = Assert-UnderRoot (Join-Path $bundle ([string]$owner.assetArchiveFileName)) $bundle 'Asset archive'
$localeArchive = Assert-UnderRoot (Join-Path $bundle ([string]$owner.localeArchiveFileName)) $bundle 'Locale archive'
$archives = @{}
foreach ($entry in @($pack.archives)) { $archives[[string]$entry.role] = $entry }
foreach ($pair in @(
    [pscustomobject]@{ role='assets'; path=$assetArchive },
    [pscustomobject]@{ role='locale'; path=$localeArchive }
)) {
    $entry = $archives[[string]$pair.role]
    if ($null -eq $entry -or -not (Test-Path -LiteralPath $pair.path -PathType Leaf) -or
        (Get-Sha256 $pair.path) -ne [string]$entry.sha256) {
        throw "Bundle archive hash mismatch: $($pair.role)"
    }
}

$assetRelative = Convert-TargetRelativePath $AssetTargetRelativePath
$localeRelative = Convert-TargetRelativePath $LocaleTargetRelativePath
Assert-HighPriorityLocaleTarget $localeRelative
$dataRoot = Assert-UnderRoot (Join-Path $client 'Data') $client 'Client data root'
$assetTarget = Assert-UnderRoot (Join-Path $client $assetRelative) $dataRoot 'Asset target'
$localeTarget = Assert-UnderRoot (Join-Path $client $localeRelative) $dataRoot 'Locale target'
foreach ($target in @($assetTarget, $localeTarget)) {
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        throw "Target ownership is unknown; refusing to overwrite: $target"
    }
}

$runId = 'weapon-shadow-install-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$runRoot = Join-Path $backup $runId
if (Test-Path -LiteralPath $runRoot) { throw "Recovery run already exists: $runRoot" }
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$records = New-Object System.Collections.Generic.List[object]
$copied = New-Object System.Collections.Generic.List[object]
try {
    foreach ($operation in @(
        [pscustomobject]@{ role='assets'; source=$assetArchive; target=$assetTarget; targetRelativePath=$assetRelative },
        [pscustomobject]@{ role='locale'; source=$localeArchive; target=$localeTarget; targetRelativePath=$localeRelative }
    )) {
        $parent = Split-Path -Parent $operation.target
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        Copy-Item -LiteralPath $operation.source -Destination $operation.target -ErrorAction Stop
        $installedSha = Get-Sha256 $operation.target
        if ($installedSha -ne (Get-Sha256 $operation.source)) {
            throw "Post-copy hash mismatch: $($operation.target)"
        }
        $record = [ordered]@{
            role=$operation.role; source=$operation.source; sourceSha256=Get-Sha256 $operation.source
            target=$operation.target; targetRelativePath=$operation.targetRelativePath
            existedBefore=$false; originalSha256=$null; installedSha256=$installedSha
        }
        $records.Add($record) | Out-Null
        $copied.Add($record) | Out-Null
    }
}
catch {
    $failedRoot = Join-Path $runRoot 'failed-new-files'
    New-Item -ItemType Directory -Force -Path $failedRoot | Out-Null
    foreach ($record in @($copied | Sort-Object role -Descending)) {
        if (Test-Path -LiteralPath $record.target -PathType Leaf) {
            $failed = Join-Path $failedRoot ([IO.Path]::GetFileName([string]$record.target))
            Move-Item -LiteralPath $record.target -Destination $failed
        }
    }
    throw
}

$manifest = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsWeaponShadowInstallation'; runId=$runId
    bundleId=[string]$pack.bundleId; bundleRoot=$bundle; clientRoot=$client
    installedAtUtc=[DateTime]::UtcNow.ToString('o'); status='INSTALLED'
    bundlePackHash=[string]$pack.bundlePackHash; stageBundleManifestHash=[string]$pack.stageBundleManifestHash
    localePatchPriorityPolicy='HIGH_PRIORITY_SUFFIX_Z'
    records=$records
}
$manifestPath = Join-Path $runRoot 'installation-manifest.json'
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "installation_manifest=$manifestPath"
Write-Host "installed_count=$($records.Count)"
