[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Source,
    [string] $Destination = (Join-Path $PSScriptRoot '..\build\Interface\AddOns\SoloCollections_EzUI')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedVersion = '2.2'
$ExpectedSourceTreeHash = '218c65a59b42d810935963013cdf6b729cd7d1d69dc67a52a70632b89911c7f6'
$ExpectedAssetTreeHash = '4673b2c8631c5f28050b9eecde7dad4a6bb33dc6a2ed5f0630a64a17945dbf53'
$HashAlgorithm = 'sha256(sorted relative-path + NUL + lowercase file-sha256 + LF)'

$KeyFiles = [ordered]@{
    'ezCollections.toc' = 'eb7c70619885a2311d3fea84509c2a538cc12f03f0e69ee8fe2857d9c5dc528a'
    'Interface\AddOns\Blizzard_Collections\Blizzard_Collections.xml' = 'b3885904754987c7c251d82a556cda044bd00b52b33f786237b5e8f44903b35d'
    'Interface\AddOns\Blizzard_Collections\Blizzard_MountCollection.xml' = '82715b8dbc4e31e5fcd65791e38ee94c3e1815bc618b60177e2e5e8a9fbe8f07'
    'Interface\AddOns\Blizzard_Collections\Blizzard_PetCollection.xml' = '39835c0ec059d9ef7972f6ef45fe1863111e2c54b9bde30b83b171ced02633e4'
    'Interface\AddOns\Blizzard_Collections\Blizzard_ToyBox.xml' = '41762b00662695a6bc6a2df01e4a7a86874687791b53b2744ea93877d05825bf'
    'Interface\AddOns\Blizzard_Collections\Blizzard_Wardrobe.xml' = '67caa7284c7e32175bd4eeb93aad0a7f8ede076d0ee6954ff24da97320d1926d'
    'Interface\AddOns\Blizzard_Collections\Blizzard_Wardrobe.lua' = '27d58536f64838633abb0365de2f775bb58dd9609273aa9d0de359acef843657'
    'Interface\FrameXML\WardrobeOutfits.xml' = '8a66703869d4ba8a2b3fd1f7ac69f0bfbed039b031a480814dffbb73b885c260'
    'Interface\FrameXML\WardrobeOutfits.lua' = 'b14ea11c76ccf508fb9f41dc04834c1b81b90570886f1593c1e2e30631cad0bb'
}

$AssetExtensions = @('.blp', '.tga', '.wav')

function Get-FileSetHash {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [System.IO.FileInfo[]] $Files
    )
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $orderedFiles = @($Files | Sort-Object {
            [IO.Path]::GetRelativePath($resolvedRoot, $_.FullName).Replace('\', '/')
        })
        foreach ($file in $orderedFiles) {
            $relative = [IO.Path]::GetRelativePath($resolvedRoot, $file.FullName).Replace('\', '/')
            $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $bytes = [Text.Encoding]::UTF8.GetBytes("$relative`0$fileHash`n")
            [void] $sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
        }
        [void] $sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return [BitConverter]::ToString($sha.Hash).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-AssetFiles {
    param([Parameter(Mandatory)] [string] $Root)
    $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Where-Object {
        $_.Extension.ToLowerInvariant() -in $AssetExtensions
    })
    if ($files.Count -eq 0) {
        throw 'No ezCollections media assets were found.'
    }
    return $files
}

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$tocPath = Join-Path $sourcePath 'ezCollections.toc'
if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
    throw "Source is not an ezCollections AddOn root: $sourcePath"
}
$toc = Get-Content -LiteralPath $tocPath -Raw
if ($toc -notmatch "(?m)^## Version:\s*$([regex]::Escape($ExpectedVersion))\s*$") {
    throw "Expected ezCollections version $ExpectedVersion in ezCollections.toc"
}

$sourceFiles = @(Get-ChildItem -LiteralPath $sourcePath -File -Recurse -Force)
$sourceTreeHash = Get-FileSetHash -Root $sourcePath -Files $sourceFiles
if ($sourceTreeHash -ne $ExpectedSourceTreeHash) {
    throw "ezCollections source tree hash mismatch. expected=$ExpectedSourceTreeHash actual=$sourceTreeHash"
}
foreach ($entry in $KeyFiles.GetEnumerator()) {
    $path = Join-Path $sourcePath $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required ezCollections reference file is missing: $($entry.Key)"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $entry.Value) {
        throw "ezCollections key file hash mismatch for $($entry.Key). expected=$($entry.Value) actual=$actualHash"
    }
}

$assetFiles = @(Get-AssetFiles -Root $sourcePath)
$assetTreeHash = Get-FileSetHash -Root $sourcePath -Files $assetFiles
if ($assetTreeHash -ne $ExpectedAssetTreeHash) {
    throw "ezCollections asset projection hash mismatch. expected=$ExpectedAssetTreeHash actual=$assetTreeHash"
}

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$allowedDestination = [IO.Path]::GetFullPath((Join-Path $suiteRoot 'build\Interface\AddOns\SoloCollections_EzUI'))
$destinationPath = [IO.Path]::GetFullPath($Destination)
if ($destinationPath -ne $allowedDestination) {
    throw "Destination must be the suite's exact ignored SoloCollections_EzUI build directory: $destinationPath"
}
$destinationParent = [IO.Path]::GetDirectoryName($destinationPath)
[IO.Directory]::CreateDirectory($destinationParent) | Out-Null
$stagingPath = Join-Path $destinationParent ('.SoloCollections_EzUI-staging-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stagingPath) | Out-Null

try {
    foreach ($file in $assetFiles) {
        $relative = [IO.Path]::GetRelativePath($sourcePath, $file.FullName)
        $target = Join-Path $stagingPath $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }

    $portraitSource = Join-Path $stagingPath 'Interface\Icons\MountJournalPortrait.blp'
    $portraitOutput = Join-Path $stagingPath 'Interface\Icons\MountJournalPortraitCircular.tga'
    & python (Join-Path $PSScriptRoot 'Build-EzCircularPortrait.py') `
        --source $portraitSource --output $portraitOutput
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $portraitOutput -PathType Leaf)) {
        throw 'Failed to build the local circular ezCollections mount portrait projection.'
    }

    $assetsLua = @"
-- Generated local integration marker. Do not edit or publish with SoloCollections source.
_G.SoloCollectionsEzUIAssets = {
    schemaVersion = 1,
    sourceName = "ezCollections",
    sourceVersion = "$ExpectedVersion",
    sourceTreeHash = "$ExpectedSourceTreeHash",
    assetTreeHash = "$ExpectedAssetTreeHash",
    root = "Interface\\AddOns\\SoloCollections_EzUI",
}
"@
    Set-Content -LiteralPath (Join-Path $stagingPath 'Assets.lua') -Value $assetsLua -Encoding utf8NoBOM

    $generatedToc = @"
## Interface: 30300
## Title: SoloCollections ezCollections UI Assets (Local)
## Notes: Generated local-only visual assets for SoloCollections.
## Author: Local integration generator; source visual assets by ZEUStiger
## Version: $ExpectedVersion-local-ui-1
## X-SoloCollections-EzUI-Schema: 1
## X-SoloCollections-EzUI-AssetHash: $ExpectedAssetTreeHash

Assets.lua
"@
    Set-Content -LiteralPath (Join-Path $stagingPath 'SoloCollections_EzUI.toc') -Value $generatedToc -Encoding utf8NoBOM

    $provenance = [ordered]@{
        schemaVersion = 1
        generatedAddon = 'SoloCollections_EzUI'
        sourceName = 'ezCollections'
        sourceVersion = $ExpectedVersion
        sourceAuthor = 'ZEUStiger'
        sourceTreeHash = $ExpectedSourceTreeHash
        assetTreeHash = $ExpectedAssetTreeHash
        hashAlgorithm = $HashAlgorithm
        assetScope = 'all .blp, .tga, and .wav files in the authorized local snapshot'
        assetFileCount = $assetFiles.Count
        sourcePathRecorded = $false
        importedCode = $false
        localDerivedAssets = @('Interface/Icons/MountJournalPortraitCircular.tga')
        excludedRuntime = @('C_Transmog*', 'ezCollections server Lua', 'ezCollections message protocol')
        publicReleaseState = 'blocked pending explicit license and provenance review'
    }
    $provenance | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $stagingPath 'EZUI-PROVENANCE.json') -Encoding utf8NoBOM

    $copiedAssetFiles = @(Get-ChildItem -LiteralPath $stagingPath -File -Recurse -Force | Where-Object {
        $_.Name -notin @(
            'Assets.lua',
            'SoloCollections_EzUI.toc',
            'EZUI-PROVENANCE.json',
            'MountJournalPortraitCircular.tga'
        )
    })
    $copiedAssetHash = Get-FileSetHash -Root $stagingPath -Files $copiedAssetFiles
    if ($copiedAssetHash -ne $ExpectedAssetTreeHash) {
        throw "Copied ezCollections asset projection hash mismatch. expected=$ExpectedAssetTreeHash actual=$copiedAssetHash"
    }

    if (Test-Path -LiteralPath $destinationPath) {
        [IO.Directory]::Delete($destinationPath, $true)
    }
    [IO.Directory]::Move($stagingPath, $destinationPath)
    Write-Output "Generated local ezCollections UI assets: $destinationPath"
    Write-Output "Source tree SHA-256: $sourceTreeHash"
    Write-Output "Asset projection SHA-256: $assetTreeHash ($($assetFiles.Count) files)"
} finally {
    if (Test-Path -LiteralPath $stagingPath) {
        [IO.Directory]::Delete($stagingPath, $true)
    }
}
