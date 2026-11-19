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

function Test-FbxArtPayload {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Kind
    )
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    Assert-PublicInput ($text.StartsWith('; FBX 7.3.0 project file', [StringComparison]::Ordinal)) "Expected an art-only FBX 7.3 ASCII file: $Path"
    Assert-PublicInput ($text -notmatch '[^\x09\x0a\x0d\x20-\x7e]') "Non-ASCII data in FBX payload: $Path"
    Assert-PublicInput ($text -notmatch '[A-Za-z]:[\\/]|/(?:home|Users|root)/') "Host path in FBX metadata: $Path"
    Assert-PublicInput ($text -notmatch '(?i)/Game/|/Script/|Blueprint|AnimNotify|MoveData_|LS_manny|ABP_') "Source implementation metadata in FBX payload: $Path"
    $allowedObjects = @('Document', 'NodeAttribute', 'Model', 'Geometry', 'Pose', 'Material', 'Deformer', 'AnimationStack', 'AnimationLayer', 'AnimationCurve', 'AnimationCurveNode')
    $objectMatches = [regex]::Matches($text, '(?m)^\t(\w+): \d+, "[^"]*", "([^"]*)"')
    Assert-PublicInput ($objectMatches.Count -gt 0) "FBX object table is missing: $Path"
    foreach ($objectMatch in $objectMatches) {
        $objectType = $objectMatch.Groups[1].Value
        Assert-PublicInput ($allowedObjects -ccontains $objectType) "Non-art object in FBX payload: $objectType"
        if ($Kind -ceq 'animation_sequence') {
            Assert-PublicInput ($objectType -notin @('Geometry', 'Material', 'Deformer', 'Pose')) "Animation-only FBX contains mesh data: $Path"
        }
    }
    $allowedChannels = @('Lcl Translation', 'Lcl Rotation', 'Lcl Scaling', 'd|X', 'd|Y', 'd|Z')
    foreach ($connection in [regex]::Matches($text, 'C: "OP",\d+,\d+, "([^"]+)"')) {
        Assert-PublicInput ($allowedChannels -ccontains $connection.Groups[1].Value) "Custom animation channel in FBX payload: $Path"
    }
    $objectTypes = @($objectMatches | ForEach-Object { $_.Groups[1].Value })
    if ($Kind -ceq 'skeletal_mesh') {
        Assert-PublicInput ($objectTypes -ccontains 'Geometry' -and $objectTypes -ccontains 'Deformer' -and $objectTypes -ccontains 'Pose') "Skeletal mesh is missing geometry, skin, or bind pose: $Path"
    }
    else {
        Assert-PublicInput ($Kind -ceq 'animation_sequence' -and $objectTypes -ccontains 'AnimationCurve') "Animation-only FBX is missing bone motion: $Path"
    }
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
    Assert-PublicInput ($benchmark.engine.compiler_toolset_version -ceq '14.44.35228') 'The public compiler toolset identity is incorrect.'
    Assert-PublicInput ($benchmark.engine.compiler_version -ceq '19.44.35223') 'The public compiler identity is incorrect.'
    Assert-PublicInput ($benchmark.paths.project_root -ceq 'starter-project') 'Project root must be project.'
    Assert-PublicInput ($benchmark.paths.project_file -ceq 'starter-project/NightSkyDuelScaffold.uproject') 'Project file identity is incorrect.'
    Assert-PublicInput ($benchmark.paths.engine_resolver -ceq 'tools/Resolve-Unreal57.ps1') 'Engine resolver identity is incorrect.'
    Assert-PublicInput (Test-Path -LiteralPath (Join-Path $root 'tools/Resolve-Unreal57.ps1') -PathType Leaf) 'Engine resolver is missing.'
    Assert-PublicInput ($benchmark.workspace.writable_roots.Count -eq 1 -and $benchmark.workspace.writable_roots[0] -ceq 'starter-project') 'project must be the only writable root.'
    Assert-PublicInput (-not (@($benchmark.workspace.protected_roots) -ccontains 'starter-project')) 'The writable project root cannot also be protected.'
    Assert-PublicInput ($benchmark.observation.task_state_schema -ceq 'contracts/duel-state.schema.json') 'Task-state schema path is incorrect.'
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













































    foreach ($artifact in @($benchmark.artifacts)) {
        $artifactPath = Resolve-ReleasedPath -Root $root -RelativePath ([string]$artifact.path)
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
        'ASSET_MANIFEST.json',
        'assets/ASSET_CATALOG.json',
        'assets/ASSET_CATALOG.md',
        'ASSET_COVERAGE.json',
        'assets/legal/LICENSE_SCOPE.md',
        'contracts/GAME_SESSION_SPEC.md',
        'contracts/duel-state.schema.json',
        'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json',
        'tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz',
        'self-check/PublicSmoke/CONTRACT.md',
        'self-check/PublicSmoke/Invoke-PublicSmoke.ps1',
        'self-check/PublicSmoke/schemas/public-smoke-result.schema.json',
        'starter-project/NightSkyDuelScaffold.uproject'
    )
    $declaredArtifactPaths = @($benchmark.artifacts | ForEach-Object { [string]$_.path })
    foreach ($requiredArtifactPath in $requiredArtifactPaths) {
        Assert-PublicInput ($declaredArtifactPaths -ccontains $requiredArtifactPath) "Required benchmark artifact identity is missing: $requiredArtifactPath"
    }
    $toolGuidePath = Join-Path $root 'tools/TOOL_GUIDE.md'
    $toolGuideHash = (Get-FileHash -LiteralPath $toolGuidePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-PublicInput ($benchmark.tooling.guide -ceq 'tools/TOOL_GUIDE.md') 'Tool guide path is incorrect.'
    Assert-PublicInput ($benchmark.tooling.guide_sha256 -ceq $toolGuideHash) 'Tool guide identity is stale.'

    foreach ($jsonFile in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -Filter '*.json')) {
        [void](Read-JsonFile -Path $jsonFile.FullName)
    }

    $uproject = Read-JsonFile -Path (Join-Path $root 'starter-project/NightSkyDuelScaffold.uproject')
    Assert-PublicInput ([string]$uproject.EngineAssociation -ceq '5.7') 'The public project must be associated with Unreal Engine 5.7.'
    $enabledPlugins = @($uproject.Plugins | Where-Object { $_.Enabled -eq $true } | ForEach-Object { [string]$_.Name })
    Assert-PublicInput ($enabledPlugins.Count -eq 1 -and $enabledPlugins[0] -ceq 'Paper2D') 'The public starter must enable only built-in Paper2D.'

    $projectRoot = Join-Path $root 'starter-project'
    $starterSourceAllowlist = @(
        'Source/NightSkyDuelScaffold.Target.cs',
        'Source/NightSkyDuelScaffold/NightSkyDuelHealthState.cpp',
        'Source/NightSkyDuelScaffold/NightSkyDuelHealthState.h',
        'Source/NightSkyDuelScaffold/NightSkyDuelScaffold.Build.cs',
        'Source/NightSkyDuelScaffold/NightSkyDuelScaffold.cpp',
        'Source/NightSkyDuelScaffold/NightSkyDuelScaffoldGameMode.cpp',
        'Source/NightSkyDuelScaffold/NightSkyDuelScaffoldGameMode.h',
        'Source/NightSkyDuelScaffold/NightSkyDuelScaffoldHUD.cpp',
        'Source/NightSkyDuelScaffold/NightSkyDuelScaffoldHUD.h',
        'Source/NightSkyDuelScaffoldEditor.Target.cs'
    )
    $actualStarterSources = @(
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Source') -File -Recurse -Force |
            ForEach-Object { Get-RelativePath -Root $projectRoot -Path $_.FullName }
    )
    Assert-PublicInput ($actualStarterSources.Count -eq $starterSourceAllowlist.Count) 'The answer-free starter source set changed without updating the release gate.'
    foreach ($sourcePath in $actualStarterSources) {
        Assert-PublicInput ($starterSourceAllowlist -ccontains $sourcePath) "Unexpected source file in the answer-free starter: $sourcePath"
    }
    $allowedArtPackages = @(
        'Content/Provided/Manny/SKM_Manny.uasset',
        'Content/Provided/Manny/SKM_Manny_Skeleton.uasset',
        'Content/Provided/Manny/Animations/AS_manny_stand.uasset',
        'Content/Provided/Manny/Animations/AS_manny_fwalk.uasset',
        'Content/Provided/Manny/Animations/AS_manny_bwalk.uasset',
        'Content/Provided/Manny/Animations/AS_manny_jump.uasset',
        'Content/Provided/Manny/Animations/AS_manny_5a.uasset',
        'Content/Provided/Manny/Animations/AS_manny_fireball.uasset',
        'Content/Provided/Manny/Animations/AS_manny_standblock.uasset',
        'Content/Provided/Manny/Animations/AS_manny_hitstun.uasset'
    )
    $answerBearingBinaryFiles = @(
        Get-ChildItem -LiteralPath $projectRoot -File -Recurse -Force |
            Where-Object { $_.Extension -in @('.uasset', '.umap', '.sav') }
    )
    $binaryRelativePaths = @($answerBearingBinaryFiles | ForEach-Object { Get-RelativePath -Root $projectRoot -Path $_.FullName })
    $unexpectedBinaryFiles = @($binaryRelativePaths | Where-Object { $allowedArtPackages -notcontains $_ })
    Assert-PublicInput ($unexpectedBinaryFiles.Count -eq 0) 'The starter contains an unallowlisted binary asset, map, or save file.'
    Assert-PublicInput ($binaryRelativePaths.Count -eq $allowedArtPackages.Count) 'The starter art package set is incomplete or duplicated.'
    foreach ($packagePath in $allowedArtPackages) {
        Assert-PublicInput ($binaryRelativePaths -contains $packagePath) "Preimported art package is missing: $packagePath"
    }
    $inputConfigText = Get-Content -LiteralPath (Join-Path $projectRoot 'Config/DefaultInput.ini') -Raw -Encoding UTF8
    Assert-PublicInput ($inputConfigText -notmatch '(?im)^\s*\+(?:ActionMappings|AxisMappings)=') 'The answer-free starter must not contain gameplay input mappings.'
    $starterSourceText = ($actualStarterSources | ForEach-Object {
            Get-Content -LiteralPath (Join-Path $projectRoot $_) -Raw -Encoding UTF8
        }) -join "`n"
    Assert-PublicInput ($starterSourceText -notmatch '(?i)\bCheatManager\b|\bUFUNCTION\s*\([^)]*\bExec\b') 'The answer-free starter must not expose a cheat or console execution entry.'

    $assetCatalog = Read-JsonFile -Path (Join-Path $root 'assets/ASSET_CATALOG.json')
    $assetManifest = Read-JsonFile -Path (Join-Path $root 'ASSET_MANIFEST.json')
    $assetCoverage = Read-JsonFile -Path (Join-Path $root 'ASSET_COVERAGE.json')
    $packageIndex = Read-JsonFile -Path (Join-Path $root 'ASSET_PACKAGE_INDEX.json')
    Assert-PublicInput ($packageIndex.scope -ceq 'static_asset_package_index' -and $packageIndex.engine.version -ceq $benchmark.engine.version -and @($packageIndex.assets).Count -eq 9) 'Asset package index has the wrong scope, engine, or file count.'
    $requiredAssetNames = @('SKM_Manny', 'AS_manny_stand', 'AS_manny_fwalk', 'AS_manny_bwalk', 'AS_manny_jump', 'AS_manny_5a', 'AS_manny_fireball', 'AS_manny_standblock', 'AS_manny_hitstun')
    Assert-PublicInput (@($assetCatalog.assets).Count -eq $requiredAssetNames.Count) 'The release requires one Manny model and all eight animation clips.'
    Assert-PublicInput ($assetManifest.asset_count -eq 9 -and $assetCoverage.delivered_asset_count -eq 9 -and $benchmark.assets.asset_count -eq 9) 'Asset counts disagree across release documents.'
    Assert-PublicInput ($assetManifest.delivery_root -ceq 'starter-project/Content/Provided/Manny' -and $assetManifest.delivery_format -ceq 'preimported_unreal_assets_with_fbx_references') 'Asset delivery location or format is incorrect.'
    Assert-PublicInput ($assetManifest.reference_root -ceq 'assets/files/Manny' -and $assetManifest.preimported_package_root -ceq 'starter-project/Content/Provided/Manny') 'Asset reference or package root is incorrect.'
    Assert-PublicInput ($assetManifest.policy.all_assets_required -and -not $assetManifest.policy.equivalent_replacement_allowed) 'Required model and animation replacements must not be permitted.'
    Assert-PublicInput ($benchmark.assets.all_required -and -not $benchmark.assets.equivalent_replacement_allowed) 'Benchmark asset policy disagrees with mandatory GDD asset use.'
    Assert-PublicInput (@($benchmark.workspace.protected_roots) -ccontains 'assets') 'Source art must be protected outside the writable project.'
    Assert-PublicInput (@($assetManifest.assets).Count -eq 9) 'Asset manifest must enumerate all nine files.'
    $gddText = Get-Content -LiteralPath (Join-Path $root 'GDD.md') -Raw -Encoding UTF8
    foreach ($requirementId in @('ASSET-01', 'ASSET-02')) {
        $requirementPattern = '(?m)^\| ' + [regex]::Escape(([char]96 + $requirementId + [char]96)) + ' \|'
        Assert-PublicInput ($gddText -match $requirementPattern) "Numbered mandatory asset requirement is missing: $requirementId"
        Assert-PublicInput (@($assetManifest.policy.hard_asset_requirement_ids) -ccontains $requirementId) "Asset manifest requirement is missing: $requirementId"
        Assert-PublicInput (@($assetCoverage.hard_asset_requirement_ids) -ccontains $requirementId) "Asset coverage requirement is missing: $requirementId"
    }
    foreach ($assetName in $requiredAssetNames) {
        $matches = @($assetCatalog.assets | Where-Object { $_.id -ceq $assetName })
        Assert-PublicInput ($matches.Count -eq 1) "Required asset is missing or duplicated: $assetName"
        $asset = $matches[0]
        $expectedPath = "assets/files/Manny/$assetName.fbx"
        Assert-PublicInput ($asset.path -ceq $expectedPath -and $asset.original_name -ceq $assetName) "Original asset name or path changed: $assetName"
        Assert-PublicInput ($asset.required -and -not $asset.equivalent_replacement_allowed) "Mandatory asset was marked replaceable: $assetName"
        Assert-PublicInput ($asset.format -ceq 'fbx_7_3_ascii') "Unexpected delivered asset format: $assetName"
        $expectedKind = if ($assetName -ceq 'SKM_Manny') { 'skeletal_mesh' } else { 'animation_sequence' }
        $expectedRequirement = if ($assetName -ceq 'SKM_Manny') { 'ASSET-01' } else { 'ASSET-02' }
        Assert-PublicInput ($asset.kind -ceq $expectedKind -and @($asset.requirement_ids) -ccontains $expectedRequirement) "Asset type or requirement mapping is incorrect: $assetName"
        $manifestEntries = @($assetManifest.assets | Where-Object { $_.id -ceq $assetName -and $_.path -ceq $expectedPath -and $_.required -and -not $_.equivalent_replacement_allowed })
        Assert-PublicInput ($manifestEntries.Count -eq 1) "Asset manifest mapping is missing or duplicated: $assetName"
        $coverageEntries = @($assetCoverage.coverage | Where-Object { @($_.asset_ids) -ccontains $assetName -and @($_.requirement_ids) -ccontains $expectedRequirement -and -not $_.gap })
        Assert-PublicInput ($coverageEntries.Count -eq 1) "Asset coverage mapping is missing or duplicated: $assetName"
        Assert-PublicInput ($gddText.Contains($expectedPath)) "GDD asset lookup path is missing: $assetName"
        $expectedDependencies = if ($assetName -ceq 'SKM_Manny') { @() } else { @('SKM_Manny') }
        Assert-PublicInput ((@($asset.dependencies) -join ',') -ceq ($expectedDependencies -join ',')) "Asset dependency mapping is incorrect: $assetName"
        $assetPath = Resolve-ReleasedPath -Root $root -RelativePath $expectedPath
        $assetItem = Get-Item -LiteralPath $assetPath
        $assetHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-PublicInput ([int64]$asset.byte_length -eq [int64]$assetItem.Length) "Asset byte length mismatch: $expectedPath"
        Assert-PublicInput ([string]$asset.sha256 -ceq $assetHash) "Asset SHA-256 mismatch: $expectedPath"
        Assert-PublicInput (Test-Path -LiteralPath (Resolve-ReleasedPath -Root $root -RelativePath $asset.license_notice) -PathType Leaf) "Asset license notice is missing: $assetName"
        $importEntries = @($packageIndex.assets | Where-Object { $_.id -ceq $assetName -and $_.path -ceq $expectedPath -and $_.sha256 -ceq $assetHash -and $_.skeleton_compatible })
        Assert-PublicInput ($importEntries.Count -eq 1 -and $importEntries[0].preimported -eq $true) "Preimported asset index is missing or stale: $assetName"
        $expectedObjectPath = if ($assetName -ceq 'SKM_Manny') { "/Game/Provided/Manny/$assetName.$assetName" } else { "/Game/Provided/Manny/Animations/$assetName.$assetName" }
        Assert-PublicInput ($asset.preimported_object_path -ceq $expectedObjectPath -and $importEntries[0].object_path -ceq $expectedObjectPath) "Preimported object path is incorrect: $assetName"
        if ($expectedKind -ceq 'animation_sequence') {
            Assert-PublicInput ($importEntries[0].bone_track_count -gt 0 -and $importEntries[0].notify_count -eq 0 -and $importEntries[0].float_curve_count -eq 0) "Unexpected animation package properties: $assetName"
        }
        Test-FbxArtPayload -Path $assetPath -Kind $expectedKind
    }
    $payloadFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'assets/files') -File -Recurse -Force)
    Assert-PublicInput ($payloadFiles.Count -eq 9) 'Only the nine allowlisted art-only FBX files may be released under assets.'
    Assert-PublicInput (Test-Path -LiteralPath (Join-Path $root 'assets/legal/MIT-NightSkyEngine.txt') -PathType Leaf) 'The upstream MIT notice is missing.'

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
