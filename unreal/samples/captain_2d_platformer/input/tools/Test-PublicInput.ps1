[CmdletBinding()]
param(
    [string]$InputRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-PublicInput {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )
    return [IO.Path]::GetRelativePath($Root, $Path).Replace([IO.Path]::DirectorySeparatorChar, '/')
}

function Resolve-ReleasedPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )
    Assert-PublicInput ($RelativePath -eq $RelativePath.Replace('\', '/')) "Manifest path is not normalized: $RelativePath"
    Assert-PublicInput (-not [IO.Path]::IsPathRooted($RelativePath)) "Manifest path is rooted: $RelativePath"
    Assert-PublicInput (-not ($RelativePath -split '/' -contains '..')) "Manifest path contains traversal: $RelativePath"
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $rootPrefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    Assert-PublicInput ($candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) "Manifest path escaped the input root: $RelativePath"
    return $candidate
}

function Assert-NoReparseAncestor {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )
    $rootFull = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $current = Get-Item -LiteralPath $Path -Force
    while ($null -ne $current) {
        Assert-PublicInput (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Reparse point is not allowed: $(Get-RelativePath -Root $Root -Path $current.FullName)"
        if ($current.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar) -ieq $rootFull) {
            break
        }
        $current = if ($current -is [IO.DirectoryInfo]) { $current.Parent } else { $current.Directory }
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "JSON parsing failed for $Path"
    }
}

function Get-PngChunkNames {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    Assert-PublicInput ($bytes.Length -ge 12) "PNG file is truncated: $Path"
    $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    for ($i = 0; $i -lt $signature.Length; ++$i) {
        Assert-PublicInput ($bytes[$i] -eq $signature[$i]) "PNG signature is invalid: $Path"
    }
    $chunks = [Collections.Generic.List[string]]::new()
    $offset = 8
    while ($offset + 12 -le $bytes.Length) {
        $lengthBytes = [byte[]]@($bytes[$offset], $bytes[$offset + 1], $bytes[$offset + 2], $bytes[$offset + 3])
        [Array]::Reverse($lengthBytes)
        $length = [BitConverter]::ToUInt32($lengthBytes, 0)
        $type = [Text.Encoding]::ASCII.GetString($bytes, $offset + 4, 4)
        $chunks.Add($type)
        $next = [int64]$offset + 12 + [int64]$length
        Assert-PublicInput ($next -le $bytes.Length) "PNG chunk is truncated: $Path"
        $offset = [int]$next
        if ($type -ceq 'IEND') {
            break
        }
    }
    Assert-PublicInput ($chunks.Count -ge 3 -and $chunks[0] -ceq 'IHDR' -and $chunks[$chunks.Count - 1] -ceq 'IEND') "PNG chunk order is invalid: $Path"
    return @($chunks)
}

try {
    $rootItem = Get-Item -LiteralPath $InputRoot -Force
    Assert-PublicInput $rootItem.PSIsContainer 'InputRoot must identify a directory.'
    $root = $rootItem.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)

    $benchmarkPath = Join-Path $root 'BENCHMARK_MANIFEST.json'

    Assert-PublicInput (Test-Path -LiteralPath $benchmarkPath -PathType Leaf) 'BENCHMARK_MANIFEST.json is missing.'


    $benchmark = Read-JsonFile -Path $benchmarkPath

    Assert-PublicInput ($benchmark.schema_version -ceq '1.0.0') 'Benchmark schema version is not 1.0.0.'
    Assert-PublicInput ($benchmark.language -ceq 'en') 'Benchmark language must be en.'
    Assert-PublicInput ($benchmark.engine.version -ceq '5.7.4') 'The public engine identity must be Unreal Engine 5.7.4.'
    Assert-PublicInput ([int64]$benchmark.engine.changelist -eq 51494982) 'The public engine changelist must be 51494982.'
    Assert-PublicInput ($benchmark.engine.compiler_toolset_version -ceq '14.44.35207') 'The public compiler toolset identity is incorrect.'
    Assert-PublicInput ($benchmark.engine.compiler_version -ceq '19.44.35228') 'The public compiler identity is incorrect.'
    Assert-PublicInput ($null -eq $benchmark.PSObject.Properties['generation']) 'Public input must not prescribe an external generation method or time budget.'
    Assert-PublicInput ($benchmark.paths.project_root -ceq 'starter-project') 'Project root must be project.'
    Assert-PublicInput ($benchmark.paths.project_file -ceq 'starter-project/Captain2DScaffold.uproject') 'Project file identity is incorrect.'
    Assert-PublicInput ($benchmark.paths.tool_catalog_index -ceq 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json') 'Interface-catalog index path is incorrect.'
    Assert-PublicInput ($benchmark.paths.tool_catalog_archive -ceq 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz') 'Interface-catalog archive path is incorrect.'
    Assert-PublicInput ($benchmark.paths.tool_catalog_search -ceq 'tools/Search-UnrealInterfaceCatalog.ps1') 'Interface-catalog search path is incorrect.'
    Assert-PublicInput ($benchmark.workspace.writable_roots.Count -eq 1 -and $benchmark.workspace.writable_roots[0] -ceq 'starter-project') 'project must be the only writable root.'
    Assert-PublicInput (-not (@($benchmark.workspace.protected_roots) -ccontains 'starter-project')) 'The writable project root cannot also be protected.'
    Assert-PublicInput ($null -eq $benchmark.workspace.PSObject.Properties['scaffold_game_name']) 'Public input must not encode an external scaffold directory name.'
    Assert-PublicInput ($null -eq $benchmark.workspace.PSObject.Properties['external_scaffold_layout']) 'Public input must not encode an external scaffold layout.'
    Assert-PublicInput ($benchmark.observation.task_state_schema -ceq 'contracts/game-state.schema.json') 'Task-state schema path is incorrect.'
    Assert-PublicInput ($benchmark.observation.final_candidate_provider_required -eq $true) 'The final task-state provider must be required.'
    Assert-PublicInput ($benchmark.engine.executor_module -ceq 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1') 'Executor module identity path is incorrect.'
    Assert-PublicInput ($benchmark.engine.executor_native_interop -ceq 'engine/unreal-5.7.4/executor/Private/WindowsEvaluationNative.cs') 'Executor native interop identity path is incorrect.'
    Assert-PublicInput ($benchmark.engine.executor_native_interop_version -ceq '1.1.0') 'Executor native interop version is incorrect.'
    Assert-PublicInput ($benchmark.engine.observer_module -ceq 'engine/unreal-5.7.4/observer/UnrealEvaluationObserver.psm1') 'Observer module identity path is incorrect.'
    Assert-PublicInput ($benchmark.engine.operation_result_schema -ceq 'engine/unreal-5.7.4/executor/schemas/operation-result.schema.json') 'Operation-result schema identity path is incorrect.'
    Assert-PublicInput ($benchmark.observation.engine_state_schema -ceq 'engine/unreal-5.7.4/executor/schemas/state-snapshot.schema.json') 'State-snapshot schema identity path is incorrect.'
    Assert-PublicInput ($benchmark.tooling.capabilities_contract -ceq 'engine/unreal-5.7.4/CAPABILITIES.md') 'Capability contract identity path is incorrect.'
    foreach ($toolHash in @(
            [string]$benchmark.tooling.executor_sha256,
            [string]$benchmark.tooling.executor_native_interop_sha256,
            [string]$benchmark.tooling.observer_sha256,
            [string]$benchmark.tooling.operation_result_schema_sha256,
            [string]$benchmark.tooling.state_snapshot_schema_sha256,
            [string]$benchmark.tooling.capabilities_contract_sha256
        )) {
        Assert-PublicInput ($toolHash -cmatch '^[a-f0-9]{64}$') 'A declared public-tool SHA-256 is malformed.'
    }













































    $catalogArchivePath = if (Test-Path -LiteralPath (Join-Path $root $benchmark.paths.tool_catalog_archive)) {
        Join-Path $root $benchmark.paths.tool_catalog_archive
    } elseif ($root -eq (Split-Path -Parent $PSScriptRoot)) {
        & (Join-Path $PSScriptRoot 'Search-UnrealInterfaceCatalog.ps1') -ResolveCatalog
    } else { throw 'Missing interface catalog in the supplied input.' }
    foreach ($artifact in @($benchmark.artifacts)) {
        $artifactPath = Resolve-ReleasedPath -Root $root -RelativePath ([string]$artifact.path)
        if ($artifact.path -ceq $benchmark.paths.tool_catalog_archive) { $artifactPath = $catalogArchivePath }
        Assert-PublicInput (Test-Path -LiteralPath $artifactPath -PathType Leaf) "Declared artifact is missing: $($artifact.path)"
        $artifactItem = Get-Item -LiteralPath $artifactPath
        $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()


    }
    $requiredArtifactPaths = @(
        'INITIAL_AGENT_PROMPT.md',
        'tools/INPUT_GUIDE.md',
        'GDD.md',
        'tools/TOOLCHAIN.md',
        'tools/TOOL_GUIDE.md',
        'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json',
        'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz',
        'ASSET_MANIFEST.json',
        'assets/ASSET_CATALOG.json',
        'assets/ASSET_CATALOG.md',
        'ASSET_COVERAGE.json',
        'assets/legal/ASSET_LICENSE_MAP.json',
        'assets/legal/CC0-1.0.txt',
        'contracts/GAME_SESSION_SPEC.md',
        'contracts/game-state.schema.json',
        'self-check/PublicSmoke/CONTRACT.md',
        'self-check/PublicSmoke/Invoke-PublicSmoke.ps1',
        'self-check/PublicSmoke/schemas/public-smoke-result.schema.json',
        'tools/Search-UnrealInterfaceCatalog.ps1',
        'tools/Test-PublicInput.ps1',
        'starter-project/Captain2DScaffold.uproject'
    )
    $declaredArtifactPaths = @($benchmark.artifacts | ForEach-Object { [string]$_.path })
    foreach ($requiredArtifactPath in $requiredArtifactPaths) {
        Assert-PublicInput ($declaredArtifactPaths -ccontains $requiredArtifactPath) "Required benchmark artifact identity is missing: $requiredArtifactPath"
    }
    $toolGuidePath = Join-Path $root 'tools/TOOL_GUIDE.md'
    $toolGuideHash = (Get-FileHash -LiteralPath $toolGuidePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-PublicInput ($benchmark.tooling.guide -ceq 'tools/TOOL_GUIDE.md') 'Tool guide path is incorrect.'
    Assert-PublicInput ($benchmark.tooling.guide_sha256 -ceq $toolGuideHash) 'Tool guide identity is stale.'

    $catalogIndexPath = Join-Path $root 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json'
    $catalogIndex = Read-JsonFile -Path $catalogIndexPath
    $catalogIndexHash = (Get-FileHash -LiteralPath $catalogIndexPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $catalogArchiveHash = (Get-FileHash -LiteralPath $catalogArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-PublicInput ([string]$catalogIndex.engine.version -ceq '5.7.4') 'Interface catalog engine version is incorrect.'
    Assert-PublicInput ([int64]$catalogIndex.engine.changelist -eq 51494982) 'Interface catalog engine changelist is incorrect.'
    Assert-PublicInput ([string]$catalogIndex.engine.platform -ceq 'Windows x64') 'Interface catalog platform is incorrect.'
    Assert-PublicInput ([string]$catalogIndex.engine.mode -ceq 'editor_game') 'Interface catalog runtime mode is incorrect.'
    Assert-PublicInput ([int]$catalogIndex.entry_count -eq 546387) 'Interface catalog entry count is incorrect.'
    Assert-PublicInput ([int64]$catalogIndex.catalog_byte_length -eq (Get-Item -LiteralPath $catalogArchivePath).Length) 'Interface catalog byte length is stale.'
    Assert-PublicInput ([string]$catalogIndex.catalog_sha256 -ceq $catalogArchiveHash) 'Interface catalog archive hash is stale.'
    Assert-PublicInput ([bool]$catalogIndex.host_paths_recorded -eq $false) 'Interface catalog records host paths.'
    Assert-PublicInput ([string]$benchmark.tooling.complete_engine_and_plugin_interface_catalog_status -ceq 'complete_source_and_descriptor_catalog_generated') 'Complete interface catalog status is incorrect.'
    Assert-PublicInput ([string]$benchmark.tooling.complete_catalog_index_sha256 -ceq $catalogIndexHash) 'Benchmark interface-catalog index hash is stale.'
    Assert-PublicInput ([string]$benchmark.tooling.complete_catalog_archive_sha256 -ceq $catalogArchiveHash) 'Benchmark interface-catalog archive hash is stale.'
    Assert-PublicInput ([int]$benchmark.tooling.complete_catalog_entry_count -eq [int]$catalogIndex.entry_count) 'Benchmark interface-catalog count is stale.'

    foreach ($jsonFile in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -Filter '*.json')) {
        [void](Read-JsonFile -Path $jsonFile.FullName)
    }

    $uproject = Read-JsonFile -Path (Join-Path $root 'starter-project/Captain2DScaffold.uproject')
    Assert-PublicInput ([string]$uproject.EngineAssociation -ceq '5.7') 'The public project must be associated with Unreal Engine 5.7.'
    $enabledPlugins = @($uproject.Plugins | Where-Object { $_.Enabled -eq $true } | ForEach-Object { [string]$_.Name })
    Assert-PublicInput ($enabledPlugins.Count -eq 1 -and $enabledPlugins[0] -ceq 'Paper2D') 'The public starter must enable only built-in Paper2D.'

    $projectRoot = Join-Path $root 'starter-project'
    $starterSourceAllowlist = @(
        'Source/Captain2DScaffold.Target.cs',
        'Source/Captain2DScaffold/Captain2DHealthState.cpp',
        'Source/Captain2DScaffold/Captain2DHealthState.h',
        'Source/Captain2DScaffold/Captain2DScaffold.Build.cs',
        'Source/Captain2DScaffold/Captain2DScaffold.cpp',
        'Source/Captain2DScaffold/Captain2DScaffoldGameMode.cpp',
        'Source/Captain2DScaffold/Captain2DScaffoldGameMode.h',
        'Source/Captain2DScaffold/Captain2DScaffoldHUD.cpp',
        'Source/Captain2DScaffold/Captain2DScaffoldHUD.h',
        'Source/Captain2DScaffoldEditor.Target.cs'
    )
    $actualStarterSources = @(
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Source') -File -Recurse -Force |
            ForEach-Object { Get-RelativePath -Root $projectRoot -Path $_.FullName }
    )
    Assert-PublicInput ($actualStarterSources.Count -eq $starterSourceAllowlist.Count) 'The answer-free starter source set changed without updating the release gate.'
    foreach ($sourcePath in $actualStarterSources) {
        Assert-PublicInput ($starterSourceAllowlist -ccontains $sourcePath) "Unexpected source file in the answer-free starter: $sourcePath"
    }
    $answerBearingBinaryFiles = @(
        Get-ChildItem -LiteralPath $projectRoot -File -Recurse -Force |
            Where-Object { $_.Extension -in @('.uasset', '.umap', '.sav') }
    )
    Assert-PublicInput ($answerBearingBinaryFiles.Count -eq 0) 'The answer-free starter must not contain assembled Unreal assets, maps, or save data.'
    $inputConfigText = Get-Content -LiteralPath (Join-Path $projectRoot 'Config/DefaultInput.ini') -Raw -Encoding UTF8
    Assert-PublicInput ($inputConfigText -notmatch '(?im)^\s*\+(?:ActionMappings|AxisMappings)=') 'The answer-free starter must not contain gameplay input mappings.'
    $starterSourceText = ($actualStarterSources | ForEach-Object {
            Get-Content -LiteralPath (Join-Path $projectRoot $_) -Raw -Encoding UTF8
        }) -join "`n"
    Assert-PublicInput ($starterSourceText -notmatch '(?i)\bCheatManager\b|\bUFUNCTION\s*\([^)]*\bExec\b') 'The answer-free starter must not expose a cheat or console execution entry.'

    $assetCatalog = Read-JsonFile -Path (Join-Path $root 'assets/ASSET_CATALOG.json')
    foreach ($asset in @($assetCatalog.assets)) {
        $assetPath = Resolve-ReleasedPath -Root $root -RelativePath ([string]$asset.path)
        $assetItem = Get-Item -LiteralPath $assetPath
        $assetHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-PublicInput ([int64]$asset.byte_length -eq [int64]$assetItem.Length) "Asset byte length mismatch: $($asset.path)"
        Assert-PublicInput ([string]$asset.sha256 -ceq $assetHash) "Asset SHA-256 mismatch: $($asset.path)"
        $chunks = if ($asset.media_type -ceq 'image/png') { @(Get-PngChunkNames -Path $assetPath) } else { @() }
        $forbiddenChunks = @($chunks | Where-Object { $_ -in @('tEXt', 'zTXt', 'iTXt', 'eXIf') })
        Assert-PublicInput ($forbiddenChunks.Count -eq 0) "PNG metadata chunk is not allowed: $($asset.path)"
    }

    $gddText = Get-Content -LiteralPath (Join-Path $root 'GDD.md') -Raw -Encoding UTF8
    $sectionSixStart = $gddText.IndexOf('## 6. Numbered Requirements: Sole Acceptance Authority', [StringComparison]::Ordinal)
    $sectionSevenStart = $gddText.IndexOf('## 7. Success, Failure, and Objective Flow Summary', [StringComparison]::Ordinal)
    Assert-PublicInput ($sectionSixStart -ge 0 -and $sectionSevenStart -gt $sectionSixStart) 'GDD Section 6 or Section 7 boundary is missing.'
    $sectionSix = $gddText.Substring($sectionSixStart, $sectionSevenStart - $sectionSixStart)
    $requirementMatches = [regex]::Matches($sectionSix, '(?m)^\| `([A-Z]+-[0-9]{2})` \|')
    $requirementIds = @($requirementMatches | ForEach-Object { $_.Groups[1].Value })
    Assert-PublicInput ($requirementIds.Count -eq 30) 'GDD Section 6 must define exactly thirty numbered requirements.'
    Assert-PublicInput (@($requirementIds | Select-Object -Unique).Count -eq $requirementIds.Count) 'GDD Section 6 contains duplicate requirement IDs.'
    $knownRequirementIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($requirementId in $requirementIds) { [void]$knownRequirementIds.Add($requirementId) }
    foreach ($referenceMatch in [regex]::Matches($gddText, '`([A-Z]+-[0-9]{2})`')) {
        Assert-PublicInput ($knownRequirementIds.Contains($referenceMatch.Groups[1].Value)) "GDD references an undefined requirement ID: $($referenceMatch.Groups[1].Value)"
    }

    $assetManifest = Read-JsonFile -Path (Join-Path $root 'ASSET_MANIFEST.json')
    $coverage = Read-JsonFile -Path (Join-Path $root 'ASSET_COVERAGE.json')
    $licenses = Read-JsonFile -Path (Join-Path $root 'assets/legal/ASSET_LICENSE_MAP.json')
    $assetIds = @($assetCatalog.assets | ForEach-Object { [string]$_.id })
    $assetPaths = @($assetCatalog.assets | ForEach-Object { [string]$_.path })
    Assert-PublicInput (@($assetIds | Select-Object -Unique).Count -eq $assetIds.Count) 'Duplicate asset identity.'
    Assert-PublicInput (@($assetPaths | Select-Object -Unique).Count -eq $assetPaths.Count) 'Duplicate asset path.'
    Assert-PublicInput ([int]$assetManifest.asset_count -eq $assetIds.Count -and [int]$benchmark.assets.asset_count -eq $assetIds.Count) 'Asset counts are stale.'
    $licensedPaths = @($licenses.sources | ForEach-Object { $_.files })
    Assert-PublicInput (@(Compare-Object ($licensedPaths | Sort-Object) ($assetPaths | Sort-Object)).Count -eq 0) 'Per-file license coverage does not match delivered assets.'
    Assert-PublicInput (@(Compare-Object (@($assetManifest.assets.path) | Sort-Object) ($assetPaths | Sort-Object)).Count -eq 0) 'Asset manifest paths do not match the catalog.'
    foreach ($asset in $assetCatalog.assets) {
        Assert-PublicInput ($asset.required -eq $true -and $asset.replacement_allowed -eq $false) "Original asset use policy is inconsistent: $($asset.id)"
        foreach ($dependency in $asset.hard_dependencies) {
            Assert-PublicInput ($assetPaths -ccontains $dependency) "Undeclared asset dependency: $dependency"
        }
        foreach ($id in $asset.requirement_ids) {
            Assert-PublicInput ($knownRequirementIds.Contains($id)) "Unknown asset requirement: $id"
            $covered = @($coverage.coverage | Where-Object { $_.requirement_id -ceq $id -and $_.asset_ids -ccontains $asset.id })
            Assert-PublicInput ($covered.Count -eq 1) "Missing or duplicate asset coverage: $($asset.id) / $id"
        }
    }
    foreach ($item in $coverage.coverage) {
        Assert-PublicInput ($knownRequirementIds.Contains($item.requirement_id)) "Unknown coverage requirement: $($item.requirement_id)"
        foreach ($id in $item.asset_ids) {
            $asset = @($assetCatalog.assets | Where-Object { $_.id -ceq $id })
            Assert-PublicInput ($asset.Count -eq 1 -and $asset[0].requirement_ids -ccontains $item.requirement_id) "Unresolved asset coverage: $id"
        }
    }

    $layout = Read-JsonFile -Path (Join-Path $root 'assets/files/map/room-layout.json')
    $layoutKeys = @('schema_version','classification','width_cells','height_cells','tile_size_px','coordinate_space','tileset_image','layers','decorations','contains_gameplay','contains_collision')
    Assert-PublicInput (@(Compare-Object ($layoutKeys | Sort-Object) (@($layout.PSObject.Properties.Name) | Sort-Object)).Count -eq 0) 'Static map contains undeclared data fields.'
    Assert-PublicInput ($layout.classification -ceq 'static_art_layout' -and $layout.contains_gameplay -eq $false -and $layout.contains_collision -eq $false) 'Static map must contain presentation data only.'
    Assert-PublicInput ($layout.width_cells -eq 27 -and $layout.height_cells -eq 20 -and $layout.layers.Count -eq 3) 'Room art dimensions or layer count are incorrect.'
    Assert-PublicInput ($layout.tile_size_px.Count -eq 2 -and $layout.tile_size_px[0] -eq 32 -and $layout.tile_size_px[1] -eq 32) 'Room tile size is incorrect.'
    $tileset = @($assetCatalog.assets | Where-Object { $_.path -ceq $layout.tileset_image })
    Assert-PublicInput ($tileset.Count -eq 1) 'Room tileset is missing from the catalog.'
    $tileCount = ($tileset[0].sheet_width_px / 32) * ($tileset[0].sheet_height_px / 32)
    foreach ($layer in $layout.layers) {
        Assert-PublicInput (@(Compare-Object (@('id','draw_order','rows') | Sort-Object) (@($layer.PSObject.Properties.Name) | Sort-Object)).Count -eq 0) 'Art layer has undeclared fields.'
        Assert-PublicInput ($layer.rows.Count -eq $layout.height_cells) 'Art layer row count is incorrect.'
        foreach ($row in $layer.rows) {
            Assert-PublicInput ($row.Count -eq $layout.width_cells) 'Art layer column count is incorrect.'
            foreach ($cell in $row) {
                if ($null -eq $cell) { continue }
                Assert-PublicInput (@(Compare-Object (@('tile','flip_x','flip_y','flip_diagonal') | Sort-Object) (@($cell.PSObject.Properties.Name) | Sort-Object)).Count -eq 0) 'Art cell has undeclared fields.'
                Assert-PublicInput ($cell.tile -ge 0 -and $cell.tile -lt $tileCount) 'Art cell references an invalid atlas tile.'
            }
        }
    }
    foreach ($decoration in $layout.decorations) {
        Assert-PublicInput (@(Compare-Object (@('image','center_px','scale_xy','rotation_degrees','depth') | Sort-Object) (@($decoration.PSObject.Properties.Name) | Sort-Object)).Count -eq 0) 'Decoration has undeclared fields.'
        Assert-PublicInput ($assetPaths -ccontains $decoration.image) 'Decoration references an unavailable image.'
    }
    foreach ($publicDocument in @('GDD.md','tools/INPUT_GUIDE.md','INITIAL_AGENT_PROMPT.md','assets/ASSET_CATALOG.md','assets/files/map/README.md')) {
        $document = Get-Content -LiteralPath (Join-Path $root $publicDocument) -Raw -Encoding UTF8
        Assert-PublicInput ($document -notmatch '(?i)\b(?:level|stage)[ _:-]*[0-9]+\b|\bnext (?:level|stage)\b|\bmultiple levels\b') "Scene numbering or progression leaked into $publicDocument"
    }

    $forbiddenDirectoryNames = @('Binaries', 'DerivedDataCache', 'Intermediate', 'Saved', '.vs', '.idea')
    foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force)) {
        Assert-NoReparseAncestor -Root $root -Path $directory.FullName
        if ($forbiddenDirectoryNames -ccontains $directory.Name) {
            $containsFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force -ErrorAction SilentlyContinue).Count -gt 0
            Assert-PublicInput (-not $containsFiles) "Generated directory contains released files: $(Get-RelativePath -Root $root -Path $directory.FullName)"
        }
    }

    $textExtensions = @('.md', '.json', '.ini', '.cs', '.cpp', '.h', '.ps1', '.uproject', '.gitignore', '.txt', '.csv')
    $nonEnglishScriptPattern = '[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u0400-\u052f\u0590-\u08ff\u0900-\u0dff\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]'
    $drivePathPattern = '(?<![A-Za-z0-9])[A-Za-z]:[\\/]'
    $slash = '/'
    $privatePathLiterals = @(
        $slash + 'home' + $slash,
        $slash + 'Users' + $slash,
        $slash + 'root' + $slash
    )
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force)) {
        if ($textExtensions -notcontains $file.Extension -and $file.Name -ne '.gitignore') {
            continue
        }
        $relative = Get-RelativePath -Root $root -Path $file.FullName
        $lineNumber = 0
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
            ++$lineNumber
            Assert-PublicInput (-not ($line -match $nonEnglishScriptPattern)) "Non-English script found at ${relative}:$lineNumber"
            Assert-PublicInput (-not ($line -match $drivePathPattern)) "Host absolute path found at ${relative}:$lineNumber"
            foreach ($literal in $privatePathLiterals) {
                Assert-PublicInput ($line.IndexOf($literal, [StringComparison]::OrdinalIgnoreCase) -lt 0) "Host absolute path found at ${relative}:$lineNumber"
            }
        }
    }

    $requiredReadOrder = @(
        'INITIAL_AGENT_PROMPT.md',
        'tools/INPUT_GUIDE.md',
        'GDD.md',
        'ASSET_MANIFEST.json',
        'assets/ASSET_CATALOG.md',
        'tools/TOOLCHAIN.md',
        'tools/TOOL_GUIDE.md',
        'contracts/GAME_SESSION_SPEC.md'
    )
    Assert-PublicInput (@($benchmark.read_order).Count -eq $requiredReadOrder.Count) 'Benchmark read order has the wrong length.'
    for ($index = 0; $index -lt $requiredReadOrder.Count; ++$index) {
        Assert-PublicInput ([string]$benchmark.read_order[$index] -ceq $requiredReadOrder[$index]) "Benchmark read order differs at index $index."
    }

    Assert-PublicInput ($benchmark.starter_boundary.strategy -ceq 'clean_blank_forward_build') 'Starter strategy identity is incorrect.'
    Assert-PublicInput ($benchmark.starter_boundary.target_gameplay_present -eq $false) 'The release manifest must declare the verified answer-free starter state.'
    Assert-PublicInput ($benchmark.english_only.opaque_identifier_allowlist.Count -eq 0) 'No opaque non-English identifier exception is expected for this input.'


    exit 0
}
catch {
    [Console]::Error.WriteLine("PUBLIC_INPUT_VALIDATION_FAILED: $($_.Exception.Message)")
    exit 1
}
