[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientDirectory,
    [Parameter(Mandatory = $true)][string]$StormMpq,
    [string]$WorkRootBase = '',
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($WorkRootBase)) {
    $WorkRootBase = Join-Path $RepoRoot '_work\weapon-models'
}
$SourceArchive = Join-Path $ClientDirectory 'Data\common-2.MPQ'
$TargetArchive = Join-Path $ClientDirectory 'Data\Patch-W.MPQ'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$WorkRoot = Join-Path $WorkRootBase "diagnostic_$Timestamp"
$ExtractRoot = Join-Path $WorkRoot 'extract'
$StageRoot = Join-Path $WorkRoot 'stage'
$VerifyRoot = Join-Path $WorkRoot 'verify'
$BuiltArchive = Join-Path $WorkRoot 'Patch-W.MPQ'
$TexturePatcher = Join-Path $PSScriptRoot 'patch_item_m2_textures.py'
$CameraPatcher = Join-Path $PSScriptRoot 'append_item_camera.py'

New-Item -ItemType Directory -Force -Path $ExtractRoot, $StageRoot, $VerifyRoot | Out-Null

$Models = @(
    [pscustomobject]@{
        Label = 'A converted OBJECT_SKIN to hardcoded'
        Source = 'Item\ObjectComponents\Weapon\Sword_2H_Blackwing_A_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Sword_2H_Blackwing_A_02_19364'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\SWORD_2H_BLACKWING_A_02.BLP'
    },
    [pscustomobject]@{
        Label = 'B original OBJECT_SKIN for ReplaceIconTexture'
        Source = 'Item\ObjectComponents\Weapon\Sword_2H_Ashbringer02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Sword_2H_Ashbringer02_19019'
        Texture = $null
    },
    [pscustomobject]@{
        Label = 'C stock native hardcoded texture'
        Source = 'Item\ObjectComponents\Shield\Shield_Blood_A_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Glave_1H_DualBlade_D_02_32837'
        Texture = $null
    }
)

foreach ($model in $Models) {
    $sourceM2Internal = $model.Source + '.m2'
    $sourceSkinInternal = $model.Source + '00.skin'
    $sourceM2 = Join-Path $ExtractRoot $sourceM2Internal
    $sourceSkin = Join-Path $ExtractRoot $sourceSkinInternal
    $targetM2 = Join-Path $StageRoot ($model.Target + '.m2')
    $targetSkin = Join-Path $StageRoot ($model.Target + '00.skin')
    & $StormMpq -Command extract -Archive $SourceArchive -ArchiveFile $sourceM2Internal -OutputPath $sourceM2
    & $StormMpq -Command extract -Archive $SourceArchive -ArchiveFile $sourceSkinInternal -OutputPath $sourceSkin
    if ($model.Texture) {
        python $TexturePatcher --input $sourceM2 --output $targetM2 --texture $model.Texture
    } else {
        python $CameraPatcher --input $sourceM2 --output $targetM2
    }
    if ($LASTEXITCODE -ne 0) { throw "M2 diagnostic patch failed: $($model.Label)" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetSkin) | Out-Null
    Copy-Item -LiteralPath $sourceSkin -Destination $targetSkin
}

& $StormMpq -Command create -Archive $BuiltArchive -MaxFiles 64
& $StormMpq -Command add -Archive $BuiltArchive -SourceRoot $StageRoot

$archiveToVerify = $BuiltArchive
$backupPath = $null
if ($Deploy) {
    if (Test-Path -LiteralPath $TargetArchive) {
        $backupRoot = Join-Path $WorkRootBase "backups\$Timestamp"
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
        $backupPath = Join-Path $backupRoot 'Patch-W.MPQ'
        Copy-Item -LiteralPath $TargetArchive -Destination $backupPath
    }
    Copy-Item -LiteralPath $BuiltArchive -Destination $TargetArchive -Force
    $archiveToVerify = $TargetArchive
}

$verification = foreach ($stageFile in Get-ChildItem -LiteralPath $StageRoot -Recurse -File) {
    $relativePath = $stageFile.FullName.Substring($StageRoot.Length).TrimStart('\')
    $verifyFile = Join-Path $VerifyRoot $relativePath
    & $StormMpq -Command extract -Archive $archiveToVerify -ArchiveFile $relativePath -OutputPath $verifyFile
    $stageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stageFile.FullName).Hash
    $verifyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $verifyFile).Hash
    [pscustomobject]@{ Path = $relativePath; Match = $stageHash -eq $verifyHash }
}
if ($verification.Match -contains $false) { throw 'Diagnostic MPQ round-trip verification failed' }
$verification | Export-Csv -LiteralPath (Join-Path $WorkRoot 'verification.csv') -NoTypeInformation -Encoding UTF8

Write-Host "Diagnostic archive: $archiveToVerify"
if ($backupPath) { Write-Host "Previous backup:   $backupPath" }
Write-Host "Verified files:    $($verification.Count)"
