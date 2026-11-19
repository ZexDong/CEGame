[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $InputRoot).Path

function Assert-PublicInput([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    Assert-PublicInput (Test-Path -LiteralPath $path -PathType Leaf) "Missing required JSON file: $RelativePath"
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$required = @(
    'INITIAL_AGENT_PROMPT.md', 'tools/INPUT_GUIDE.md', 'GDD.md', 'FIXED_LAYOUT.md',
    'BENCHMARK_MANIFEST.json', 'tools/TOOLCHAIN.md',
    'tools/TOOL_GUIDE.md',
    'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json',
    'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz',
    'ASSET_MANIFEST.json', 'assets/ASSET_CATALOG.json', 'assets/ASSET_CATALOG.md', 'ASSET_COVERAGE.json',
    'THIRD_PARTY_NOTICES.md', 'assets/legal/MIT-RollBall.txt', 'assets/legal/ASSET_LICENSE_MAP.json',
    'contracts/GAME_SESSION_SPEC.md', 'contracts/game-state.schema.json',
    'starter-project/RollBallStarter.uproject', 'starter-project/Config/FixedRollBallLayout.json',
    'self-check/PublicSmoke/Invoke-PublicSmoke.ps1', 'tools/Search-UnrealInterfaceCatalog.ps1', 'tools/Resolve-Unreal57.ps1'
)
foreach ($relative in $required) {
    Assert-PublicInput (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf) "Missing required file: $relative"
}

$benchmark = Read-Json 'BENCHMARK_MANIFEST.json'
Assert-PublicInput ([string]$benchmark.task_id -ceq 'RollBall') 'Unexpected task identity.'
Assert-PublicInput ([string]$benchmark.language -ceq 'en') 'The public input language must be English.'
Assert-PublicInput ([string]$benchmark.engine.version -ceq '5.7.4') 'Unexpected Unreal Engine version.'
Assert-PublicInput ([int64]$benchmark.engine.changelist -eq 51494982) 'Unexpected Unreal Engine changelist.'
Assert-PublicInput ([string]$benchmark.paths.project_file -ceq 'starter-project/RollBallStarter.uproject') 'Unexpected project entry.'
Assert-PublicInput ([bool]$benchmark.starter_boundary.target_gameplay_present -eq $false) 'The starter boundary claims target gameplay is present.'
Assert-PublicInput ([string]$benchmark.fixed_layout.layout_id -ceq 'rollball-fixed-maze-10x10-v2') 'Unexpected fixed layout identity.'

$layoutPath = Join-Path $root 'starter-project/Config/FixedRollBallLayout.json'
$layout = Read-Json 'starter-project/Config/FixedRollBallLayout.json'
Assert-PublicInput ([string]$layout.layout_id -ceq 'rollball-fixed-maze-10x10-v2') 'The fixed layout ID is invalid.'
Assert-PublicInput ([int]$layout.grid.width -eq 10 -and [int]$layout.grid.height -eq 10) 'The fixed layout must be 10x10.'
Assert-PublicInput ([int]$layout.grid.cell_size_unreal_units -eq 400) 'The fixed cell size must be 400 Unreal units.'
Assert-PublicInput ([int]$layout.start_cell.x -eq 0 -and [int]$layout.start_cell.y -eq 0) 'The start cell is invalid.'
Assert-PublicInput ([int]$layout.exit_cell.x -eq 9 -and [int]$layout.exit_cell.y -eq 9) 'The exit cell is invalid.'

$expectedTraps = @('4,9','6,8','0,8','8,6','0,7','3,7','6,7','1,5','4,4','7,4','6,3','1,1','8,1','9,1','6,0','7,0')
$actualTraps = @($layout.trap_cells | ForEach-Object { '{0},{1}' -f [int]$_.x,[int]$_.y })
Assert-PublicInput ($actualTraps.Count -eq 16) 'The fixed layout must contain exactly sixteen trap cells.'
Assert-PublicInput (@($actualTraps | Select-Object -Unique).Count -eq 16) 'Trap cells must be unique.'
foreach ($trap in $expectedTraps) { Assert-PublicInput ($actualTraps -ccontains $trap) "Missing fixed trap cell: $trap" }

$vertical = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($wall in @($layout.vertical_walls)) {
    $x = [int]$wall.x; $y = [int]$wall.y
    Assert-PublicInput ($x -ge 0 -and $x -le 10 -and $y -ge 0 -and $y -lt 10) 'A vertical wall is outside the grid.'
    Assert-PublicInput ($vertical.Add("$x,$y")) 'Vertical walls must be unique.'
}
$horizontal = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($wall in @($layout.horizontal_walls)) {
    $x = [int]$wall.x; $y = [int]$wall.y
    Assert-PublicInput ($x -ge 0 -and $x -lt 10 -and $y -ge 0 -and $y -le 10) 'A horizontal wall is outside the grid.'
    Assert-PublicInput ($horizontal.Add("$x,$y")) 'Horizontal walls must be unique.'
}
Assert-PublicInput ($vertical.Count -eq 67 -and $horizontal.Count -eq 54) 'Fixed wall counts are invalid.'
for ($y = 0; $y -lt 10; $y++) {
    Assert-PublicInput ($vertical.Contains("0,$y") -and $vertical.Contains("10,$y")) 'The vertical perimeter is incomplete.'
}
for ($x = 0; $x -lt 10; $x++) {
    Assert-PublicInput ($horizontal.Contains("$x,0") -and $horizontal.Contains("$x,10")) 'The horizontal perimeter is incomplete.'
}

$passages = 0
for ($y = 0; $y -lt 10; $y++) {
    for ($x = 0; $x -lt 10; $x++) {
        if ($x -lt 9 -and -not $vertical.Contains("$($x + 1),$y")) { $passages++ }
        if ($y -lt 9 -and -not $horizontal.Contains("$x,$($y + 1)")) { $passages++ }
    }
}
Assert-PublicInput ($passages -eq 99) 'The fixed layout passage count is invalid.'

$assetManifest = Read-Json 'ASSET_MANIFEST.json'
$assetCatalog = Read-Json 'assets/ASSET_CATALOG.json'
$manifestItems = @($assetManifest.items)
$catalogItems = @($assetCatalog.items)
Assert-PublicInput ($manifestItems.Count -eq $catalogItems.Count) 'Asset manifest and catalog counts differ.'
Assert-PublicInput ($manifestItems.Count -ge 5) 'The supplied visual mesh kit is incomplete.'
$catalogById = @{}
foreach ($entry in $catalogItems) {
    $id = [string]$entry.asset_id
    Assert-PublicInput (-not $catalogById.ContainsKey($id)) "Duplicate asset catalog ID: $id"
    $catalogById[$id] = $entry
    $relative = [string]$entry.relative_path
    $full = Join-Path $root $relative
    Assert-PublicInput (Test-Path -LiteralPath $full -PathType Leaf) "Missing catalog asset: $relative"
    Assert-PublicInput ([int64]$entry.byte_length -eq (Get-Item -LiteralPath $full).Length) "Asset byte length is stale: $relative"
    Assert-PublicInput ([string]$entry.sha256 -ceq (Get-Sha256 $full)) "Asset hash is stale: $relative"
}
foreach ($entry in $manifestItems) {
    $id = [string]$entry.asset_id
    Assert-PublicInput ($catalogById.ContainsKey($id)) "Manifest asset is missing from catalog: $id"
    Assert-PublicInput ([string]$entry.path -ceq [string]$catalogById[$id].relative_path) "Manifest/catalog path mismatch: $id"
}
$fixedAsset = $catalogById['fixed-layout-data']
Assert-PublicInput ([string]$fixedAsset.relative_path -ceq 'starter-project/Config/FixedRollBallLayout.json') 'Unexpected fixed-layout catalog path.'
Assert-PublicInput ([string]$fixedAsset.sha256 -ceq (Get-Sha256 $layoutPath)) 'The layout catalog hash is stale.'
Assert-PublicInput ([int64]$fixedAsset.byte_length -eq (Get-Item -LiteralPath $layoutPath).Length) 'The layout catalog byte length is stale.'
$catalogBinaryPaths = @($catalogItems | ForEach-Object { [string]$_.relative_path } | Where-Object { $_ -match '\.(uasset|umap)$' } | Sort-Object)
$actualBinaryPaths = @(Get-ChildItem -LiteralPath (Join-Path $root 'starter-project/Content') -Recurse -File -Include '*.uasset','*.umap' | ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/') } | Sort-Object)
Assert-PublicInput (($catalogBinaryPaths -join "`n") -ceq ($actualBinaryPaths -join "`n")) 'The released binary asset set is not cataloged.'
foreach ($binaryPath in $actualBinaryPaths) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $root $binaryPath))
    $binaryText = [Text.Encoding]::ASCII.GetString($bytes)
    $binaryUnicodeText = [Text.Encoding]::Unicode.GetString($bytes)
    # Generic Starter Content package labels such as /SourceArt/ are not host
    # paths. Reject only machine-specific absolute locations.
    $hostPathPattern = '(?i)([A-Za-z]:\\|/Users/|/home/|/Dropbox/|/Rocket/)'
    Assert-PublicInput ($binaryText -notmatch $hostPathPattern -and $binaryUnicodeText -notmatch $hostPathPattern) "Host source path found in binary asset: $binaryPath"
}

$catalogIndex = Read-Json 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json'
$catalogArchive = Join-Path $root 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz'
Assert-PublicInput ([string]$catalogIndex.engine.version -ceq '5.7.4' -and [int64]$catalogIndex.engine.changelist -eq 51494982) 'The interface catalog engine identity is invalid.'
Assert-PublicInput ([int]$catalogIndex.entry_count -eq 546387) 'The interface catalog entry count is invalid.'
Assert-PublicInput ([int64]$catalogIndex.catalog_byte_length -eq (Get-Item -LiteralPath $catalogArchive).Length) 'The interface catalog byte length is invalid.'
Assert-PublicInput ([string]$catalogIndex.catalog_sha256 -ceq (Get-Sha256 $catalogArchive)) 'The interface catalog hash is invalid.'
Assert-PublicInput ([bool]$catalogIndex.host_paths_recorded -eq $false) 'The interface catalog records host paths.'

$forbiddenGenerated = @('starter-project/Binaries','starter-project/DerivedDataCache','starter-project/Intermediate','starter-project/Saved','starter-project/.vs')
foreach ($relative in $forbiddenGenerated) {
    Assert-PublicInput (-not (Test-Path -LiteralPath (Join-Path $root $relative))) "Generated directory is present: $relative"
}

$sourceRoot = Join-Path $root 'starter-project/Source'
$sourceText = (Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Get-Content -Raw) -join "`n"
foreach ($pattern in @('EKeys::W','EKeys::A','EKeys::S','EKeys::D','EKeys::R','AddForce','SetSimulatePhysics','OnComponentBeginOverlap','MAZE COMPLETE','STATUS: RUNNING')) {
    Assert-PublicInput ($sourceText -notmatch [regex]::Escape($pattern)) "The starter contains target gameplay marker: $pattern"
}

$textExtensions = @('.md','.json','.ini','.cs','.cpp','.h','.ps1','.txt','.uproject')
$textFiles = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() }
foreach ($file in $textFiles) {
    $relative = $file.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/')
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    Assert-PublicInput ($text -notmatch '[\p{IsCJKUnifiedIdeographs}\p{IsHiragana}\p{IsKatakana}\p{IsCyrillic}]') "Non-English public text detected: $relative"
    if ($relative -cne 'tools/Test-PublicInput.ps1') {
        Assert-PublicInput ($text -notmatch '(?i)-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----') "Private key marker detected: $relative"
        Assert-PublicInput ($text -notmatch '(?i)(api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[\"''][^\"'']{8,}') "Secret-like assignment detected: $relative"
        Assert-PublicInput ($text -notmatch '(?m)(?<![A-Za-z0-9_])[A-Za-z]:[\\/]') "Absolute Windows path detected: $relative"
        Assert-PublicInput ($text -notmatch '(?m)(^|[\s\"''])\\\\[^\s\\]+\\') "UNC path detected: $relative"
        Assert-PublicInput ($text -notmatch '(?m)(/Users/|/home/)') "Host home path detected: $relative"
    }
}


















[pscustomobject]@{
    status = 'passed'
    task_id = 'RollBall'
    engine = 'Unreal Engine 5.7.4'
    layout_id = [string]$layout.layout_id

    interface_count = [int]$catalogIndex.entry_count
} | ConvertTo-Json -Depth 8
