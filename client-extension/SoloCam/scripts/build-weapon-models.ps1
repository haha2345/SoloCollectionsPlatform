[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientDirectory,
    [string]$StormMpq = $env:SOLOCOLLECTIONS_STORM_MPQ,
    [string]$StormDll = $env:SOLOCOLLECTIONS_STORM_DLL,
    [ValidatePattern('^[A-Za-z]{4}$')][string]$Locale = '',
    [string]$LocaleDbcArchive = '',
    [ValidateRange(2, 9)][int]$LocalePatchNumber = 6,
    [ValidatePattern('^[^\\/:*?"<>|]+\.MPQ$')][string]$AssetPatchName = 'Patch-W.MPQ',
    [string]$WorkRootBase = '',
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($StormMpq)) {
    $StormMpq = Join-Path $RepoRoot 'tools\mpq\StormMpq.ps1'
}
if ([string]::IsNullOrWhiteSpace($WorkRootBase)) {
    $WorkRootBase = Join-Path $RepoRoot '_work\weapon-models'
}
$ClientDirectory = [System.IO.Path]::GetFullPath($ClientDirectory)
$DataRoot = Join-Path $ClientDirectory 'Data'
if ([string]::IsNullOrWhiteSpace($Locale)) {
    $ConfigPath = Join-Path $ClientDirectory 'WTF\Config.wtf'
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        $ConfigText = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
        $LocaleMatch = [regex]::Match($ConfigText, '(?im)^SET\s+locale\s+"([A-Za-z]{4})"')
        if ($LocaleMatch.Success) {
            $Locale = $LocaleMatch.Groups[1].Value
        }
    }
}
if ([string]::IsNullOrWhiteSpace($Locale)) {
    $LocaleDirectories = @(Get-ChildItem -LiteralPath $DataRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^[A-Za-z]{4}$' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName ("locale-{0}.MPQ" -f $_.Name)) -PathType Leaf)
    })
    if ($LocaleDirectories.Count -eq 1) {
        $Locale = $LocaleDirectories[0].Name
    }
}
if ([string]::IsNullOrWhiteSpace($Locale)) {
    throw 'Unable to detect client locale. Pass -Locale enUS/zhCN/zhTW/deDE/etc.'
}
$LocaleRoot = Join-Path $DataRoot $Locale
if (-not (Test-Path -LiteralPath $LocaleRoot -PathType Container)) {
    throw "Client locale directory is missing: $LocaleRoot"
}
$SourceArchive = Join-Path $ClientDirectory 'Data\common-2.MPQ'
$TextureArchives = @(
    (Join-Path $ClientDirectory 'Data\patch-3.MPQ'),
    (Join-Path $ClientDirectory 'Data\patch-2.MPQ'),
    (Join-Path $ClientDirectory 'Data\patch.MPQ'),
    (Join-Path $ClientDirectory 'Data\lichking.MPQ'),
    (Join-Path $ClientDirectory 'Data\expansion.MPQ'),
    (Join-Path $ClientDirectory 'Data\common-2.MPQ'),
    (Join-Path $ClientDirectory 'Data\common.MPQ')
)
$TargetAssetArchive = Join-Path $DataRoot $AssetPatchName
$TargetLocalePatchName = "patch-$Locale-$LocalePatchNumber.MPQ"
$TargetDbcArchive = Join-Path $LocaleRoot $TargetLocalePatchName
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$WorkRoot = Join-Path $WorkRootBase "build_$Timestamp"
$ExtractRoot = Join-Path $WorkRoot 'extract'
$StageRoot = Join-Path $WorkRoot 'stage'
$AssetStageRoot = Join-Path $WorkRoot 'asset-stage'
$DbcStageRoot = Join-Path $WorkRoot 'dbc-stage'
$VerifyRoot = Join-Path $WorkRoot 'verify'
$TempRoot = Join-Path $WorkRoot 'temp'
$BuiltAssetArchive = Join-Path $WorkRoot $AssetPatchName
$BuiltDbcArchive = Join-Path $WorkRoot $TargetLocalePatchName
$Builder = Join-Path $PSScriptRoot 'build_creature_weapon_assets.py'

foreach ($required in @($StormMpq, $StormDll, $SourceArchive, $Builder)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path is missing: $required"
    }
}

New-Item -ItemType Directory -Force -Path $ExtractRoot, $StageRoot, $AssetStageRoot, $DbcStageRoot, $VerifyRoot, $TempRoot | Out-Null
$env:TEMP = $TempRoot
$env:TMP = $TempRoot

$Models = @(
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\Sword_2H_Blackwing_A_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Sword_2H_Blackwing_A_02_19364'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\SWORD_2H_BLACKWING_A_02.BLP'
        TextureName = 'SC_Sword_2H_Blackwing_A_02_19364'
        ModelId = 4000
        DisplayId = 40000
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\Sword_2H_Ashbringer02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Sword_2H_Ashbringer02_19019'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\SWORD_2H_ASHBRINGER_A_01BLUE.BLP'
        TextureName = 'SC_Sword_2H_Ashbringer02_19019'
        ModelId = 4001
        DisplayId = 40001
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\Glave_1H_DualBlade_D_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Glave_1H_DualBlade_D_02_32837'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\GLAVE_1H_DUALBLADE_D_02.BLP'
        TextureName = 'SC_Glave_1H_DualBlade_D_02_32837'
        ModelId = 4002
        DisplayId = 40002
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\Glave_1H_DualBlade_D_02left'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Glave_1H_DualBlade_D_02left_32838'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\GLAVE_1H_DUALBLADE_D_02.BLP'
        TextureName = 'SC_Glave_1H_DualBlade_D_02left_32838'
        ModelId = 4003
        DisplayId = 40003
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Shield\Shield_2H_OutlandRaid_D_06'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Shield_2H_OutlandRaid_D_06_32375'
        Texture = 'ITEM\OBJECTCOMPONENTS\SHIELD\SHIELD_2H_OUTLANDRAID_D_06.BLP'
        TextureName = 'SC_Shield_2H_OutlandRaid_D_06_32375'
        ModelId = 4004
        DisplayId = 40004
    },
    # One source verified against the local 3.3.5 ItemDisplayInfo.dbc for
    # every practical WeaponSubclass. IDs 4005+/40005+ are reserved here.
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\axe_1h_icecrownraid_d_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Axe_1H_IcecrownRaid_D_01_50737'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\AXE_1H_ICECROWNRAID_D_01BLUE.BLP'
        TextureName = 'SC_Axe_1H_IcecrownRaid_D_01_50737'
        ModelId = 4005
        DisplayId = 40005
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\axe_2h_icecrownraid_d_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Axe_2H_IcecrownRaid_D_02_50709'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\AXE_2H_ICECROWNRAID_D_02BLUE.BLP'
        TextureName = 'SC_Axe_2H_IcecrownRaid_D_02_50709'
        ModelId = 4006
        DisplayId = 40006
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\bow_1h_icecrownraid_d_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Bow_1H_IcecrownRaid_D_01_50638'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\BOW_1H_ICECROWNRAID_D_01RED.BLP'
        TextureName = 'SC_Bow_1H_IcecrownRaid_D_01_50638'
        ModelId = 4007
        DisplayId = 40007
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\firearm_2h_rifle_icecrownraid_d_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Firearm_2H_Rifle_IcecrownRaid_D_01_50444'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\FIREARM_2H_RIFLE_ICECROWNRAID_D_01BLUE.BLP'
        TextureName = 'SC_Firearm_2H_Rifle_IcecrownRaid_D_01_50444'
        ModelId = 4008
        DisplayId = 40008
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\mace_1h_icecrownraid_d_04'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Mace_1H_IcecrownRaid_D_04_50734'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\MACE_1H_ICECROWNRAID_D_04_WHITE.BLP'
        TextureName = 'SC_Mace_1H_IcecrownRaid_D_04_50734'
        ModelId = 4009
        DisplayId = 40009
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\mace_2h_icecrownraid_d_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Mace_2H_IcecrownRaid_D_01_50603'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\MACE_2H_ICECROWNRAID_D_01GREEN.BLP'
        TextureName = 'SC_Mace_2H_IcecrownRaid_D_01_50603'
        ModelId = 4010
        DisplayId = 40010
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\polearm_2h_icecrownraid_d_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Polearm_2H_IcecrownRaid_D_01_50735'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\POLEARM_2H_ICECROWNRAID_D_01BLACK.BLP'
        TextureName = 'SC_Polearm_2H_IcecrownRaid_D_01_50735'
        ModelId = 4011
        DisplayId = 40011
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\Sword_1H_Crystal_C_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Sword_1H_Crystal_C_02_32466'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\SWORD_1H_CRYSTAL_C_02PURPLE.BLP'
        TextureName = 'SC_Sword_1H_Crystal_C_02_32466'
        ModelId = 4012
        DisplayId = 40012
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\Sword_2H_Frostmourne_D_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Sword_2H_Frostmourne_D_01_33350'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\SWORD_2H_FROSTMOURNE_D_01.BLP'
        TextureName = 'SC_Sword_2H_Frostmourne_D_01_33350'
        ModelId = 4013
        DisplayId = 40013
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\stave_2h_icecrownraid_d_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Stave_2H_IcecrownRaid_D_02_50731'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\STAVE_2H_ICECROWNRAID_D_02PURPLE.BLP'
        TextureName = 'SC_Stave_2H_IcecrownRaid_D_02_50731'
        ModelId = 4014
        DisplayId = 40014
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\hand_1h_icecrownraid_d_02right'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Hand_1H_IcecrownRaid_D_02Right_50692'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\HAND_1H_ICECROWNRAID_D_02BLUE.BLP'
        TextureName = 'SC_Hand_1H_IcecrownRaid_D_02Right_50692'
        ModelId = 4015
        DisplayId = 40015
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\knife_1h_icecrownraid_d_03'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Knife_1H_IcecrownRaid_D_03_50736'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\KNIFE_1H_ICECROWNRAID_D_03YELLOW.BLP'
        TextureName = 'SC_Knife_1H_IcecrownRaid_D_03_50736'
        ModelId = 4016
        DisplayId = 40016
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\thrown_1h_shuriken_a_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Thrown_1H_Shuriken_A_02_50474'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\THROWN_1H_SHURIKEN_A_02SILVER.BLP'
        TextureName = 'SC_Thrown_1H_Shuriken_A_02_50474'
        ModelId = 4017
        DisplayId = 40017
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\bow_2h_crossbow_icecrownraid_d_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Bow_2H_Crossbow_IcecrownRaid_D_01_50733'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\BOW_2H_CROSSBOW_ICECROWNRAID_D_01BLUE.BLP'
        TextureName = 'SC_Bow_2H_Crossbow_IcecrownRaid_D_01_50733'
        ModelId = 4018
        DisplayId = 40018
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\wand_1h_icecrownraid_d_02'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Wand_1H_IcecrownRaid_D_02_50631'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\WAND_1H_ICECORWNRAID_D_02BLUE.BLP'
        TextureName = 'SC_Wand_1H_IcecrownRaid_D_02_50631'
        ModelId = 4019
        DisplayId = 40019
    },
    [pscustomobject]@{
        Source = 'Item\ObjectComponents\Weapon\Misc_2H_FishingPole_A_01'
        Target = 'Item\ObjectComponents\SoloCollections\SC_Misc_2H_FishingPole_A_01_43651'
        Texture = 'ITEM\OBJECTCOMPONENTS\WEAPON\MISC_2H_FISHINGPOLE_A_01.BLP'
        TextureName = 'SC_Misc_2H_FishingPole_A_01_43651'
        ModelId = 4020
        DisplayId = 40020
    }
)

$BuildEntries = foreach ($model in $Models) {
    $SourceM2Internal = $model.Source + '.m2'
    $SourceSkinInternal = $model.Source + '00.skin'
    $SourceM2 = Join-Path $ExtractRoot $SourceM2Internal
    $SourceSkin = Join-Path $ExtractRoot $SourceSkinInternal
    $SourceTexture = Join-Path $ExtractRoot $model.Texture

    # WotLK patch archives can replace a model and its skin together; search
    # the full client chain just like textures instead of assuming common-2.
    foreach ($modelArchive in $TextureArchives) {
        if (-not (Test-Path -LiteralPath $modelArchive)) { continue }
        if (-not (Test-Path -LiteralPath $SourceM2)) {
            & $StormMpq -Command extract -Archive $modelArchive -ArchiveFile $SourceM2Internal -OutputPath $SourceM2 -StormLib $StormDll 2>$null
        }
        if (-not (Test-Path -LiteralPath $SourceSkin)) {
            & $StormMpq -Command extract -Archive $modelArchive -ArchiveFile $SourceSkinInternal -OutputPath $SourceSkin -StormLib $StormDll 2>$null
        }
        if ((Test-Path -LiteralPath $SourceM2) -and (Test-Path -LiteralPath $SourceSkin)) { break }
    }
    foreach ($textureArchive in $TextureArchives) {
        if (-not (Test-Path -LiteralPath $textureArchive)) { continue }
        & $StormMpq -Command extract -Archive $textureArchive -ArchiveFile $model.Texture -OutputPath $SourceTexture -StormLib $StormDll
        if (Test-Path -LiteralPath $SourceTexture) { break }
    }
    if (-not (Test-Path -LiteralPath $SourceM2) -or -not (Test-Path -LiteralPath $SourceSkin) -or -not (Test-Path -LiteralPath $SourceTexture)) {
        throw "Model extraction is incomplete: $($model.Source)"
    }
    [ordered]@{
        source_m2 = $SourceM2
        source_skin = $SourceSkin
        source_texture = $SourceTexture
        target = $model.Target
        texture_name = $model.TextureName
        model_id = $model.ModelId
        display_id = $model.DisplayId
    }
}

$CreatureModelData = Join-Path $ExtractRoot 'DBFilesClient\CreatureModelData.dbc'
$CreatureDisplayInfo = Join-Path $ExtractRoot 'DBFilesClient\CreatureDisplayInfo.dbc'
$LocaleDbcCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($LocaleDbcArchive)) {
    $LocaleDbcCandidates = @([System.IO.Path]::GetFullPath($LocaleDbcArchive))
}
else {
    $EscapedLocale = [regex]::Escape($Locale)
    $PatchCandidates = @(Get-ChildItem -LiteralPath $LocaleRoot -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)^patch-$EscapedLocale(?:-([0-9]+))?\.MPQ$" -and
        $_.FullName -ne $TargetDbcArchive
    } | Sort-Object {
        $match = [regex]::Match($_.Name, '(?i)-([0-9]+)\.MPQ$')
        if ($match.Success) { [int]$match.Groups[1].Value } else { 0 }
    } -Descending)
    $LocaleBaseArchive = Join-Path $LocaleRoot "locale-$Locale.MPQ"
    $LocaleDbcCandidates = @($PatchCandidates.FullName)
    if (Test-Path -LiteralPath $LocaleBaseArchive -PathType Leaf) {
        $LocaleDbcCandidates += $LocaleBaseArchive
    }
}
if ($LocaleDbcCandidates.Count -eq 0) {
    throw "No locale MPQ candidates found under: $LocaleRoot"
}

$SelectedLocaleDbcArchive = $null
for ($candidateIndex = 0; $candidateIndex -lt $LocaleDbcCandidates.Count; $candidateIndex++) {
    $candidate = $LocaleDbcCandidates[$candidateIndex]
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $CandidateRoot = Join-Path $ExtractRoot ("locale-candidate-{0}" -f $candidateIndex)
    $CandidateModelData = Join-Path $CandidateRoot 'DBFilesClient\CreatureModelData.dbc'
    $CandidateDisplayInfo = Join-Path $CandidateRoot 'DBFilesClient\CreatureDisplayInfo.dbc'
    try {
        & $StormMpq -Command extract -Archive $candidate -ArchiveFile 'DBFilesClient\CreatureModelData.dbc' -OutputPath $CandidateModelData -StormLib $StormDll
        & $StormMpq -Command extract -Archive $candidate -ArchiveFile 'DBFilesClient\CreatureDisplayInfo.dbc' -OutputPath $CandidateDisplayInfo -StormLib $StormDll
    }
    catch {
        continue
    }
    if ((Test-Path -LiteralPath $CandidateModelData -PathType Leaf) -and
        (Test-Path -LiteralPath $CandidateDisplayInfo -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CreatureModelData) | Out-Null
        Copy-Item -LiteralPath $CandidateModelData -Destination $CreatureModelData -Force
        Copy-Item -LiteralPath $CandidateDisplayInfo -Destination $CreatureDisplayInfo -Force
        $SelectedLocaleDbcArchive = $candidate
        break
    }
}
if (-not $SelectedLocaleDbcArchive) {
    throw "None of the locale MPQs contains both required Creature DBC files. Pass -LocaleDbcArchive explicitly. Checked: $($LocaleDbcCandidates -join '; ')"
}
$LocaleDbcArchive = $SelectedLocaleDbcArchive

$BuildConfig = Join-Path $WorkRoot 'weapon-creature-build.json'
$BuildEntries | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $BuildConfig -Encoding UTF8
python $Builder --config $BuildConfig --stage $StageRoot --creature-model-data $CreatureModelData --creature-display-info $CreatureDisplayInfo
if ($LASTEXITCODE -ne 0) {
    throw 'Creature weapon asset build failed.'
}

Copy-Item -LiteralPath (Join-Path $StageRoot 'Item') -Destination $AssetStageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $StageRoot 'DBFilesClient') -Destination $DbcStageRoot -Recurse

& $StormMpq -Command create -Archive $BuiltAssetArchive -MaxFiles 128 -StormLib $StormDll
& $StormMpq -Command add -Archive $BuiltAssetArchive -SourceRoot $AssetStageRoot -StormLib $StormDll
& $StormMpq -Command create -Archive $BuiltDbcArchive -MaxFiles 16 -StormLib $StormDll
& $StormMpq -Command add -Archive $BuiltDbcArchive -SourceRoot $DbcStageRoot -StormLib $StormDll
foreach ($archive in @($BuiltAssetArchive, $BuiltDbcArchive)) {
    if (-not (Test-Path -LiteralPath $archive)) {
        throw "Archive creation failed: $archive"
    }
}

$AssetArchiveToVerify = $BuiltAssetArchive
$DbcArchiveToVerify = $BuiltDbcArchive
$BackupPaths = @()
if ($Deploy) {
    $BackupRoot = Join-Path $WorkRootBase "backups\$Timestamp"
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    foreach ($target in @($TargetAssetArchive, $TargetDbcArchive)) {
        if (Test-Path -LiteralPath $target) {
            $backup = Join-Path $BackupRoot ([IO.Path]::GetFileName($target))
            Copy-Item -LiteralPath $target -Destination $backup
            $BackupPaths += $backup
        }
    }
    Copy-Item -LiteralPath $BuiltAssetArchive -Destination $TargetAssetArchive -Force
    Copy-Item -LiteralPath $BuiltDbcArchive -Destination $TargetDbcArchive -Force
    $AssetArchiveToVerify = $TargetAssetArchive
    $DbcArchiveToVerify = $TargetDbcArchive
}

$VerificationSources = @(
    [pscustomobject]@{ Label = 'assets'; Stage = $AssetStageRoot; Archive = $AssetArchiveToVerify },
    [pscustomobject]@{ Label = 'dbc'; Stage = $DbcStageRoot; Archive = $DbcArchiveToVerify }
)
$Verification = foreach ($source in $VerificationSources) {
    foreach ($stageFile in Get-ChildItem -LiteralPath $source.Stage -Recurse -File) {
        $RelativePath = $stageFile.FullName.Substring($source.Stage.Length).TrimStart('\')
        $VerifyFile = Join-Path (Join-Path $VerifyRoot $source.Label) $RelativePath
        & $StormMpq -Command extract -Archive $source.Archive -ArchiveFile $RelativePath -OutputPath $VerifyFile -StormLib $StormDll
        if (-not (Test-Path -LiteralPath $VerifyFile)) {
            throw "Verification extraction failed: $RelativePath"
        }
        $StageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stageFile.FullName).Hash
        $VerifyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $VerifyFile).Hash
        [pscustomobject]@{
            Archive = $source.Archive
            Path = $RelativePath
            StageLength = $stageFile.Length
            VerifyLength = (Get-Item -LiteralPath $VerifyFile).Length
            StageSHA256 = $StageHash
            VerifySHA256 = $VerifyHash
            Match = $StageHash -eq $VerifyHash
        }
    }
}

$Manifest = Join-Path $WorkRoot 'weapon-model-verification.csv'
$Verification | Export-Csv -LiteralPath $Manifest -NoTypeInformation -Encoding UTF8
if ($Verification.Match -contains $false) {
    throw "One or more files failed archive round-trip verification. See $Manifest"
}

Write-Host "StormLib DLL:      $StormDll"
Write-Host "Source archive:    $SourceArchive"
Write-Host "Locale DBC base:   $LocaleDbcArchive"
Write-Host "Built assets:      $BuiltAssetArchive"
Write-Host "Built locale DBC:  $BuiltDbcArchive"
if ($Deploy) {
    Write-Host "Deployed assets:   $TargetAssetArchive"
    Write-Host "Deployed locale:   $TargetDbcArchive"
    foreach ($backup in $BackupPaths) { Write-Host "Previous backup:   $backup" }
}
Write-Host "Verified files:    $($Verification.Count)"
Write-Host "Verification CSV:  $Manifest"
