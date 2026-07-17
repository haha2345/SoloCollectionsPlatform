[CmdletBinding()]
param(
    [string]$AddonRoot = '',
    [string]$DbcRoot = 'D:\AzerothCore_NPCBots_Clean\Data\dbc',
    [string]$WorldConfig = 'D:\AzerothCore_NPCBots_Clean\configs\worldserver.conf',
    [string]$MySqlExe = 'D:\AzerothCore_NPCBots_Clean\mysql\mysql-8.4.10-winx64\bin\mysql.exe',
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'catalog_manifest.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$specs = [ordered]@{
    Mounts = @{ File = 'Mounts.lua'; Count = 24; Fields = @('id', 'creatureId', 'spellId', 'name', 'icon', 'source', 'description', 'collected', 'favorite') }
    Pets = @{ File = 'Pets.lua'; Count = 24; Fields = @('id', 'creatureId', 'spellId', 'name', 'icon', 'source', 'description', 'collected', 'favorite') }
    Toys = @{ File = 'Toys.lua'; Count = 36; Fields = @('id', 'itemId', 'name', 'icon', 'source', 'description', 'collected', 'favorite') }
    Appearances = @{ File = 'Appearances.lua'; Count = 48; Fields = @('id', 'itemId', 'slot', 'classMask', 'name', 'icon', 'source', 'collected', 'favorite') }
    Sets = @{ File = 'Sets.lua'; Count = 8; Fields = @('id', 'classToken', 'name', 'icon', 'itemIds', 'collected', 'favorite') }
}

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

if ([string]::IsNullOrWhiteSpace($AddonRoot)) {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $addonCandidates = @(Get-ChildItem -LiteralPath $projectRoot -Directory | ForEach-Object {
        $candidate = Join-Path $_.FullName 'SoloCollections'
        if (Test-Path -LiteralPath (Join-Path $candidate 'SoloCollections.toc') -PathType Leaf) {
            $candidate
        }
    })
    Assert-Condition ($addonCandidates.Count -eq 1) "Could not uniquely discover the SoloCollections AddOn under $projectRoot"
    $AddonRoot = $addonCandidates[0]
}

function Get-LuaRecords {
    param([string]$Path)
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Missing catalog source: $Path"
    return @(Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_ -match '^\s*\{\s*id\s*=.*\}\s*,?\s*$' })
}

function Get-IntegerField {
    param([string]$Record, [string]$Field)
    $match = [regex]::Match($Record, "\b$([regex]::Escape($Field))\s*=\s*(\d+)")
    Assert-Condition $match.Success "Missing integer field '$Field': $Record"
    return [int]$match.Groups[1].Value
}

function Get-IntegerListField {
    param([string]$Record, [string]$Field)
    $match = [regex]::Match($Record, "\b$([regex]::Escape($Field))\s*=\s*\{([^}]*)\}")
    Assert-Condition $match.Success "Missing integer-list field '$Field': $Record"
    return @([regex]::Matches($match.Groups[1].Value, '\d+') | ForEach-Object { [int]$_.Value })
}

function Read-WdbcIds {
    param([string]$Path)
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Missing DBC source: $Path"
    $stream = [System.IO.File]::OpenRead($Path)
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        $magic = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        Assert-Condition ($magic -eq 'WDBC') "Unsupported DBC header in ${Path}: $magic"
        $recordCount = $reader.ReadInt32()
        $fieldCount = $reader.ReadInt32()
        $recordSize = $reader.ReadInt32()
        [void]$reader.ReadInt32()
        Assert-Condition ($recordCount -ge 0 -and $fieldCount -gt 0 -and $recordSize -ge 4) "Invalid DBC dimensions in $Path"
        $ids = New-Object 'System.Collections.Generic.HashSet[int]'
        for ($index = 0; $index -lt $recordCount; $index++) {
            [void]$ids.Add($reader.ReadInt32())
            if ($recordSize -gt 4) {
                [void]$stream.Seek($recordSize - 4, [System.IO.SeekOrigin]::Current)
            }
        }
        return $ids
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Assert-IdsExist {
    param([int[]]$Ids, $KnownIds, [string]$SourceLabel)
    $missing = @($Ids | Sort-Object -Unique | Where-Object { -not $KnownIds.Contains([int]$_) })
    Assert-Condition ($missing.Count -eq 0) "IDs missing from ${SourceLabel}: $($missing -join ', ')"
}

function Get-WorldDatabaseSetting {
    param([string]$Path)
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Missing worldserver config: $Path"
    $line = Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_ -match '^\s*WorldDatabaseInfo\s*=' } | Select-Object -First 1
    Assert-Condition ($null -ne $line) "WorldDatabaseInfo was not found in $Path"
    $match = [regex]::Match($line, '^\s*WorldDatabaseInfo\s*=\s*"([^"]+)"')
    Assert-Condition $match.Success "WorldDatabaseInfo has an unsupported format in $Path"
    $parts = @($match.Groups[1].Value -split ';')
    Assert-Condition ($parts.Count -ge 5) "WorldDatabaseInfo must contain host, port, user, password, and database"
    return @{ Host = $parts[0]; Port = $parts[1]; User = $parts[2]; Password = $parts[3]; Database = $parts[4] }
}

function Get-WorldColumnIds {
    param([int[]]$Ids, [string]$Table, [string]$Column)
    Assert-Condition (Test-Path -LiteralPath $MySqlExe -PathType Leaf) "Missing mysql client: $MySqlExe"
    Assert-Condition (($Table -eq 'item_template' -and $Column -eq 'entry') -or ($Table -eq 'creature_template' -and $Column -eq 'entry')) "Unsupported world DB validation target: $Table.$Column"
    $database = Get-WorldDatabaseSetting $WorldConfig
    $uniqueIds = @($Ids | Sort-Object -Unique)
    Assert-Condition ($uniqueIds.Count -gt 0) "No IDs were supplied for $Table.$Column"
    $sql = "SELECT $Column FROM $Table WHERE $Column IN ($($uniqueIds -join ',')) ORDER BY $Column;"
    $oldPassword = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $database.Password
        $output = @(& $MySqlExe --batch --skip-column-names --raw "--host=$($database.Host)" "--port=$($database.Port)" "--user=$($database.User)" "--database=$($database.Database)" "--execute=$sql" 2>&1)
        Assert-Condition ($LASTEXITCODE -eq 0) "World DB query failed for $Table.$Column (credentials redacted): $($output -join ' ')"
        $known = New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($line in $output) {
            $value = 0
            if ([int]::TryParse(([string]$line).Trim(), [ref]$value)) {
                [void]$known.Add($value)
            }
        }
        return $known
    }
    finally {
        if ($null -eq $oldPassword) {
            Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        }
        else {
            $env:MYSQL_PWD = $oldPassword
        }
    }
}

$recordsByCatalog = [ordered]@{}
foreach ($catalogName in $specs.Keys) {
    $spec = $specs[$catalogName]
    $path = Join-Path (Join-Path $AddonRoot 'Data') $spec.File
    $records = @(Get-LuaRecords $path)
    Assert-Condition ($records.Count -eq $spec.Count) "$($spec.File) has $($records.Count) records; expected $($spec.Count)"

    $ids = @()
    $states = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($record in $records) {
        foreach ($field in $spec.Fields) {
            Assert-Condition ([regex]::IsMatch($record, "\b$([regex]::Escape($field))\s*=")) "$($spec.File) record is missing '$field': $record"
        }
        $ids += Get-IntegerField $record 'id'
        $state = [regex]::Match($record, '\bcollected\s*=\s*(true|false)')
        Assert-Condition $state.Success "$($spec.File) record has invalid collected state: $record"
        [void]$states.Add($state.Groups[1].Value)
    }
    Assert-Condition (($ids | Sort-Object -Unique).Count -eq $ids.Count) "$($spec.File) contains duplicate catalog IDs"
    Assert-Condition ($states.Contains('true') -and $states.Contains('false')) "$($spec.File) must contain collected and uncollected records"
    $recordsByCatalog[$catalogName] = $records
}

$mountSpellIds = @($recordsByCatalog.Mounts | ForEach-Object { Get-IntegerField $_ 'spellId' })
$mountCreatureIds = @($recordsByCatalog.Mounts | ForEach-Object { Get-IntegerField $_ 'creatureId' })
$petSpellIds = @($recordsByCatalog.Pets | ForEach-Object { Get-IntegerField $_ 'spellId' })
$petCreatureIds = @($recordsByCatalog.Pets | ForEach-Object { Get-IntegerField $_ 'creatureId' })
$toyItemIds = @($recordsByCatalog.Toys | ForEach-Object { Get-IntegerField $_ 'itemId' })
$appearanceItemIds = @($recordsByCatalog.Appearances | ForEach-Object { Get-IntegerField $_ 'itemId' })
$setIds = @($recordsByCatalog.Sets | ForEach-Object { Get-IntegerField $_ 'id' })
$setItemIds = @($recordsByCatalog.Sets | ForEach-Object { Get-IntegerListField $_ 'itemIds' })

$spellDbc = Join-Path $DbcRoot 'Spell.dbc'
$itemSetDbc = Join-Path $DbcRoot 'ItemSet.dbc'
$spellIds = Read-WdbcIds $spellDbc
$itemSetIds = Read-WdbcIds $itemSetDbc

Assert-IdsExist ($mountSpellIds + $petSpellIds) $spellIds 'Spell.dbc'
Assert-IdsExist $setIds $itemSetIds 'ItemSet.dbc'

$allItemIds = @($toyItemIds + $appearanceItemIds + $setItemIds | Sort-Object -Unique)
$worldItemIds = Get-WorldColumnIds $allItemIds 'item_template' 'entry'
Assert-IdsExist $allItemIds $worldItemIds 'world.item_template'
$allCreatureIds = @($mountCreatureIds + $petCreatureIds | Sort-Object -Unique)
$worldCreatureIds = Get-WorldColumnIds $allCreatureIds 'creature_template' 'entry'
Assert-IdsExist $allCreatureIds $worldCreatureIds 'world.creature_template'

$manifest = [ordered]@{
    schemaVersion = 1
    counts = [ordered]@{
        mounts = $recordsByCatalog.Mounts.Count
        pets = $recordsByCatalog.Pets.Count
        toys = $recordsByCatalog.Toys.Count
        appearances = $recordsByCatalog.Appearances.Count
        sets = $recordsByCatalog.Sets.Count
    }
    catalogs = [ordered]@{
        mounts = [ordered]@{ ids = @($recordsByCatalog.Mounts | ForEach-Object { Get-IntegerField $_ 'id' }); spellIds = $mountSpellIds; creatureIds = $mountCreatureIds }
        pets = [ordered]@{ ids = @($recordsByCatalog.Pets | ForEach-Object { Get-IntegerField $_ 'id' }); spellIds = $petSpellIds; creatureIds = $petCreatureIds }
        toys = [ordered]@{ ids = @($recordsByCatalog.Toys | ForEach-Object { Get-IntegerField $_ 'id' }); itemIds = $toyItemIds }
        appearances = [ordered]@{ ids = @($recordsByCatalog.Appearances | ForEach-Object { Get-IntegerField $_ 'id' }); itemIds = $appearanceItemIds }
        sets = [ordered]@{ ids = $setIds; itemIds = $setItemIds }
    }
    verificationSources = [ordered]@{
        addonData = (Join-Path $AddonRoot 'Data')
        spellIds = $spellDbc
        creatureIds = [ordered]@{ config = $WorldConfig; table = 'creature_template'; column = 'entry' }
        itemSetIds = $itemSetDbc
        itemIds = [ordered]@{ config = $WorldConfig; table = 'item_template'; column = 'entry' }
    }
}

$json = ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine
$manifestDirectory = Split-Path -Parent $ManifestPath
if (-not (Test-Path -LiteralPath $manifestDirectory -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $manifestDirectory -Force)
}
[System.IO.File]::WriteAllText($ManifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "SoloCollections catalog verification passed."
Write-Host "Counts: mounts=24 pets=24 toys=36 appearances=48 sets=8"
Write-Host "Manifest: $ManifestPath"
