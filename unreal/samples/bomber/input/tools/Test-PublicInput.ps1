[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot
)

$ErrorActionPreference = 'Stop'

function Assert-PublicInput {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64
}

function Get-RelativePath {
    param([string]$Root, [string]$Path)
    return [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

function Resolve-ReleasedPath {
    param([string]$Root, [string]$RelativePath)
    Assert-PublicInput ($RelativePath -eq $RelativePath.Replace('\', '/')) "Path is not normalized: $RelativePath"
    Assert-PublicInput (-not [IO.Path]::IsPathRooted($RelativePath)) "Path is rooted: $RelativePath"
    Assert-PublicInput (-not ($RelativePath -split '/' -contains '..')) "Path contains traversal: $RelativePath"
    $full = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    Assert-PublicInput ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Path escaped input root: $RelativePath"
    return $full
}

try {
    $root = (Resolve-Path -LiteralPath $InputRoot).Path
    Assert-PublicInput (Test-Path -LiteralPath $root -PathType Container) 'InputRoot must identify a directory.'

    $benchmarkPath = Join-Path $root 'BENCHMARK_MANIFEST.json'

    Assert-PublicInput (Test-Path -LiteralPath $benchmarkPath -PathType Leaf) 'BENCHMARK_MANIFEST.json is missing.'


    $benchmark = Read-JsonFile $benchmarkPath

    Assert-PublicInput ($benchmark.schema_version -ceq '1.0.0') 'Benchmark schema version must be 1.0.0.'
    Assert-PublicInput ($benchmark.language -ceq 'en') 'Benchmark language must be en.'
    Assert-PublicInput ($benchmark.task_name -ceq 'Bomber Local Duel') 'Benchmark task name is incorrect.'
    Assert-PublicInput ($benchmark.task_revision -ceq '2.0.1') 'Benchmark task revision is incorrect.'
    Assert-PublicInput ($benchmark.engine.version -ceq '5.7.4') 'The engine identity must be Unreal Engine 5.7.4.'
    Assert-PublicInput ([int64]$benchmark.engine.changelist -eq 51494982) 'The engine changelist is incorrect.'
    Assert-PublicInput ($benchmark.paths.project_file -ceq 'starter-project/BomberStarter.uproject') 'Project file identity is incorrect.'
    Assert-PublicInput ($benchmark.paths.fixed_layout -ceq 'starter-project/Config/BomberArenaLayout.json') 'Fixed layout identity is incorrect.'
    Assert-PublicInput ($benchmark.paths.tool_catalog_index -ceq 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json') 'Catalog index path is incorrect.'
    Assert-PublicInput ($benchmark.paths.tool_catalog_archive -ceq 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz') 'Catalog archive path is incorrect.'
    Assert-PublicInput ($benchmark.workspace.writable_roots.Count -eq 1 -and $benchmark.workspace.writable_roots[0] -ceq 'starter-project') 'project must be the only writable root.'



































    foreach ($artifact in @($benchmark.artifacts)) {
        $full = Resolve-ReleasedPath -Root $root -RelativePath ([string]$artifact.path)
        Assert-PublicInput (Test-Path -LiteralPath $full -PathType Leaf) "Declared artifact is missing: $($artifact.path)"


    }

    $catalogIndexPath = Join-Path $root 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json'
    $catalogArchivePath = Join-Path $root 'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz'
    $catalogIndex = Read-JsonFile $catalogIndexPath
    Assert-PublicInput ($catalogIndex.engine.version -ceq '5.7.4') 'Catalog engine version is incorrect.'
    Assert-PublicInput ([int64]$catalogIndex.engine.changelist -eq 51494982) 'Catalog engine changelist is incorrect.'
    Assert-PublicInput ($catalogIndex.engine.platform -ceq 'Windows x64') 'Catalog platform is incorrect.'
    Assert-PublicInput ($catalogIndex.engine.mode -ceq 'editor_game') 'Catalog mode is incorrect.'
    Assert-PublicInput ([bool]$catalogIndex.host_paths_recorded -eq $false) 'Catalog records host paths.'
    Assert-PublicInput ([string]$catalogIndex.catalog_sha256 -ceq (Get-FileHash $catalogArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()) 'Catalog archive hash is stale.'
    Assert-PublicInput ([int]$benchmark.tooling.complete_catalog_entry_count -eq [int]$catalogIndex.entry_count) 'Benchmark catalog count is stale.'

    $uproject = Read-JsonFile (Join-Path $root 'starter-project/BomberStarter.uproject')
    Assert-PublicInput ([string]$uproject.EngineAssociation -ceq '5.7') 'The public project must be associated with Unreal Engine 5.7.'
    Assert-PublicInput (@($uproject.Plugins).Count -eq 1) 'The source starter must enable exactly one project plugin.'
    Assert-PublicInput ([string]$uproject.Plugins[0].Name -ceq 'BlockoutMap' -and [bool]$uproject.Plugins[0].Enabled) 'The clean BlockoutMap content plugin must be enabled.'
    $pluginDescriptor = Read-JsonFile (Join-Path $root 'starter-project/Plugins/BlockoutMap/BlockoutMap.uplugin')
    Assert-PublicInput ([bool]$pluginDescriptor.CanContainContent) 'BlockoutMap must be a content plugin.'
    Assert-PublicInput ($null -eq $pluginDescriptor.PSObject.Properties['Modules']) 'BlockoutMap must not contain code modules.'

    $sourceAllowlist = @(
        'Source/BomberStarter.Target.cs',
        'Source/BomberStarter/BomberStarter.Build.cs',
        'Source/BomberStarter/BomberStarter.cpp',
        'Source/BomberStarter/BomberStarterGameMode.cpp',
        'Source/BomberStarter/BomberStarterGameMode.h',
        'Source/BomberStarter/BomberStarterHUD.cpp',
        'Source/BomberStarter/BomberStarterHUD.h',
        'Source/BomberStarter/BomberStarterHealthState.cpp',
        'Source/BomberStarter/BomberStarterHealthState.h',
        'Source/BomberStarterEditor.Target.cs'
    )
    $sourceRoot = Join-Path $root 'starter-project'
    $actualSources = @(Get-ChildItem (Join-Path $sourceRoot 'Source') -File -Recurse | ForEach-Object {
        Get-RelativePath -Root $sourceRoot -Path $_.FullName
    } | Sort-Object)
    Assert-PublicInput ($actualSources.Count -eq $sourceAllowlist.Count) 'The answer-free source set changed without updating the release gate.'
    foreach ($source in $actualSources) {
        Assert-PublicInput ($sourceAllowlist -ccontains $source) "Unexpected source file in starter: $source"
    }

    $assetManifest = Read-JsonFile (Join-Path $root 'ASSET_MANIFEST.json')
    $assetAllowlist = @($assetManifest.assets | ForEach-Object { ([string]$_.path).Substring('starter-project/'.Length) } | Sort-Object)
    $actualAssets = @(Get-ChildItem $sourceRoot -File -Recurse -Filter '*.uasset' | ForEach-Object {
        Get-RelativePath -Root $sourceRoot -Path $_.FullName
    } | Sort-Object)
    Assert-PublicInput ($actualAssets.Count -eq $assetAllowlist.Count) 'The clean asset set changed without updating the release gate.'
    foreach ($asset in $actualAssets) {
        Assert-PublicInput ($assetAllowlist -ccontains $asset) "Unexpected binary asset in starter: $asset"
    }

    $inputConfig = Get-Content (Join-Path $root 'starter-project/Config/DefaultInput.ini') -Raw -Encoding UTF8
    Assert-PublicInput ($inputConfig -notmatch '(?im)^\s*\+(?:ActionMappings|AxisMappings)=') 'The answer-free starter must not contain gameplay input mappings.'
    $sourceText = ($actualSources | ForEach-Object { Get-Content (Join-Path $sourceRoot $_) -Raw -Encoding UTF8 }) -join "`n"
    Assert-PublicInput ($sourceText -notmatch '(?i)\bCheatManager\b|\bUFUNCTION\s*\([^)]*\bExec\b') 'The answer-free starter exposes a cheat or console entry.'
    foreach ($term in @('dsc.gg', 'discord.gg', 'Give Feedback', 'Join our Discord')) {
        Assert-PublicInput ($sourceText.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -lt 0) "Author or community content leaked into starter source: $term"
    }

    $assetCatalog = Read-JsonFile (Join-Path $root 'assets/ASSET_CATALOG.json')
    Assert-PublicInput ([int]$assetCatalog.asset_count -eq $assetAllowlist.Count) 'Asset catalog count is incorrect.'
    foreach ($asset in @($assetCatalog.assets)) {
        $full = Resolve-ReleasedPath -Root $root -RelativePath ([string]$asset.path)
        Assert-PublicInput ([int64]$asset.byte_length -eq (Get-Item $full).Length) "Asset byte length mismatch: $($asset.path)"
        Assert-PublicInput ([string]$asset.sha256 -ceq (Get-FileHash $full -Algorithm SHA256).Hash.ToLowerInvariant()) "Asset SHA-256 mismatch: $($asset.path)"
        Assert-PublicInput ($asset.classification -in @('raw_visual_asset','raw_visual_dependency')) "Asset is not classified as raw visual content: $($asset.path)"
        # Validate the delivered asset bytes directly below.
        $bytes = [IO.File]::ReadAllBytes($full)
        $combined = [Text.Encoding]::ASCII.GetString($bytes) + "`n" + [Text.Encoding]::Unicode.GetString($bytes)
        foreach ($forbidden in @('dsc.gg', 'discord.gg', 'github.com', 'C:/Users/', 'C:\Users\')) {
            Assert-PublicInput ($combined.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -lt 0) "Forbidden metadata found in asset: $($asset.path)"
        }
    }

    $gdd = Get-Content (Join-Path $root 'GDD.md') -Raw -Encoding UTF8
    $s6 = $gdd.IndexOf('## 6. Numbered Requirements: Sole Acceptance Authority', [StringComparison]::Ordinal)
    $s7 = $gdd.IndexOf('## 7. Success, Failure, and Multi-Stage Flow Summary', [StringComparison]::Ordinal)
    Assert-PublicInput ($s6 -ge 0 -and $s7 -gt $s6) 'GDD Section 6 or Section 7 boundary is missing.'
    $sectionSix = $gdd.Substring($s6, $s7 - $s6)
    $ids = @([regex]::Matches($sectionSix, '(?m)^\| `([A-Z]+-[0-9]{2})` \|') | ForEach-Object { $_.Groups[1].Value })
    Assert-PublicInput ($ids.Count -eq 32) 'GDD Section 6 must define exactly thirty-two numbered requirements.'
    Assert-PublicInput (@($ids | Select-Object -Unique).Count -eq $ids.Count) 'GDD contains duplicate requirement IDs.'
    $known = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in $ids) { [void]$known.Add($id) }
    foreach ($match in [regex]::Matches($gdd, '`([A-Z]+-[0-9]{2})`')) {
        Assert-PublicInput ($known.Contains($match.Groups[1].Value)) "GDD references undefined requirement ID: $($match.Groups[1].Value)"
    }

    foreach ($generated in @('Binaries', 'DerivedDataCache', 'Intermediate', 'Saved', '.vs')) {
        $path = Join-Path $sourceRoot $generated
        if (Test-Path $path) {
            Assert-PublicInput (@(Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue).Count -eq 0) "Generated directory contains released files: starter-project/$generated"
        }
    }

    $textExtensions = @('.md', '.json', '.ini', '.cs', '.cpp', '.h', '.ps1', '.uproject', '.gitignore')
    $nonEnglishPattern = '[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af\u0400-\u04ff]'
    $drivePattern = '(?i)(?<![A-Za-z0-9_])[A-Z]:[\\/]'
    foreach ($file in Get-ChildItem $root -File -Recurse | Where-Object { $_.Extension -in $textExtensions }) {
        $relative = Get-RelativePath -Root $root -Path $file.FullName
        $lineNumber = 0
        foreach ($line in Get-Content $file.FullName -Encoding UTF8) {
            ++$lineNumber
            Assert-PublicInput (-not ($line -match $nonEnglishPattern)) "Non-English script found at ${relative}:$lineNumber"
            if ($relative -notin @('tools/Test-PublicInput.ps1')) {
                Assert-PublicInput (-not ($line -match $drivePattern)) "Host absolute path found at ${relative}:$lineNumber"
            }

        }
    }

    $requiredReadOrder = @('INITIAL_AGENT_PROMPT.md','tools/INPUT_GUIDE.md','GDD.md','ARENA_LAYOUT.md','ASSET_MANIFEST.json','assets/ASSET_CATALOG.md','tools/TOOLCHAIN.md','tools/TOOL_GUIDE.md','contracts/GAME_SESSION_SPEC.md')
    Assert-PublicInput (@($benchmark.read_order).Count -eq $requiredReadOrder.Count) 'Benchmark read order has the wrong length.'
    for ($i = 0; $i -lt $requiredReadOrder.Count; ++$i) {
        Assert-PublicInput ([string]$benchmark.read_order[$i] -ceq $requiredReadOrder[$i]) "Benchmark read order differs at index $i."
    }
    Assert-PublicInput ($benchmark.starter_boundary.strategy -ceq 'clean_blank_forward_build') 'Starter strategy identity is incorrect.'
    Assert-PublicInput ($benchmark.starter_boundary.target_gameplay_present -eq $false) 'The manifest must declare an answer-free starter.'
    Assert-PublicInput ($benchmark.starter_boundary.author_facing_content_present -eq $false) 'Author-facing content must be absent.'


    exit 0
}
catch {
    [Console]::Error.WriteLine("PUBLIC_INPUT_VALIDATION_FAILED: $($_.Exception.Message)")
    exit 1
}


