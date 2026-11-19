[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot
)

$ErrorActionPreference = 'Stop'

function Assert-PublicInput {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Read-Json {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $script:Root $RelativePath
    Assert-PublicInput (Test-Path -LiteralPath $path -PathType Leaf) "Missing required JSON file: $RelativePath"
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
}

function Get-RelativePath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetRelativePath($script:Root, $Path).Replace('\', '/')
}

$script:Root = [IO.Path]::GetFullPath($InputRoot)
Assert-PublicInput (Test-Path -LiteralPath $script:Root -PathType Container) 'InputRoot is not a directory.'

$required = @(
    'INITIAL_AGENT_PROMPT.md',
    'tools/INPUT_GUIDE.md',
    'GDD.md',
    'BENCHMARK_MANIFEST.json',

    'tools/TOOLCHAIN.md',
    'tools/TOOL_GUIDE.md',
    'tools/catalog/UNREAL_ENGINE_5_6_1_INTERFACE_CATALOG.index.json',
    'tools/catalog/UNREAL_ENGINE_5_6_1_INTERFACE_CATALOG.jsonl.gz',
    'ASSET_MANIFEST.json',
    'assets/ASSET_CATALOG.json',
    'assets/ASSET_CATALOG.md',
    'ASSET_COVERAGE.json',
    'THIRD_PARTY_NOTICES.md',
    'assets/legal/LICENSE_SCOPE.md',
    'assets/legal/ASSET_LICENSE_MAP.json',
    'contracts/GAME_SESSION_SPEC.md',
    'contracts/actionroguelike-probe-snapshot.schema.json',
    'contracts/actionroguelike-probe-events.schema.json',
    'self-check/PublicSmoke/CONTRACT.md',
    'self-check/PublicSmoke/Invoke-PublicSmoke.ps1',
    'self-check/PublicSmoke/schemas/public-smoke-result.schema.json',
    'tools/Search-UnrealInterfaceCatalog.ps1',
    'tools/Resolve-Unreal56.ps1',
    'starter-project/ArenaSlice.uproject'
)
foreach ($relative in $required) {
    Assert-PublicInput (Test-Path -LiteralPath (Join-Path $script:Root $relative) -PathType Leaf) "Missing required file: $relative"
}

$forbiddenRoots = @('original', 'baseline_ue5_6', 'gold', 'evaluator', 'planning', 'results', '.git')
foreach ($relative in $forbiddenRoots) {
    Assert-PublicInput (-not (Test-Path -LiteralPath (Join-Path $script:Root $relative))) "Private root entered the public input: $relative"
}

$generatedNames = @('Binaries', 'DerivedDataCache', 'Intermediate', 'Saved', '.vs', '.idea')
$generated = Get-ChildItem -LiteralPath (Join-Path $script:Root 'starter-project') -Directory -Recurse -Force |
    Where-Object { $_.Name -in $generatedNames }
Assert-PublicInput (@($generated).Count -eq 0) 'Generated project directories are present.'
Assert-PublicInput (-not (Test-Path -LiteralPath (Join-Path $script:Root 'starter-project/Source'))) 'The common start unexpectedly contains Source gameplay.'

$benchmark = Read-Json 'BENCHMARK_MANIFEST.json'
Assert-PublicInput ([string]$benchmark.language -ceq 'en') 'Benchmark language must be English.'
Assert-PublicInput ([string]$benchmark.engine.version -ceq '5.6.1') 'The exact engine version must be 5.6.1.'
Assert-PublicInput ([string]$benchmark.paths.project_file -ceq 'starter-project/ArenaSlice.uproject') 'Project file identity is incorrect.'
Assert-PublicInput ([string]$benchmark.paths.default_map_at_release -ceq '/Game/Arena/Maps/StarterArena') 'Default map identity is incorrect.'
Assert-PublicInput ([string]$benchmark.paths.license_map -ceq 'assets/legal/ASSET_LICENSE_MAP.json') 'License-map identity is incorrect.'
Assert-PublicInput ([string]$benchmark.paths.public_smoke -ceq 'self-check/PublicSmoke/Invoke-PublicSmoke.ps1') 'Public-smoke entry is incorrect.'
Assert-PublicInput ([string]$benchmark.paths.public_smoke_schema -ceq 'self-check/PublicSmoke/schemas/public-smoke-result.schema.json') 'Public-smoke schema identity is incorrect.'
Assert-PublicInput ([string]$benchmark.paths.engine_resolver -ceq 'tools/Resolve-Unreal56.ps1') 'Engine resolver identity is incorrect.'
Assert-PublicInput ([string]$benchmark.tooling.complete_engine_and_plugin_interface_catalog_status -ceq 'complete_source_and_descriptor_catalog_generated') 'The complete engine/plugin interface catalog is not release-bound.'
Assert-PublicInput ([string]$benchmark.public_smoke.entry -ceq [string]$benchmark.paths.public_smoke) 'Public-smoke entry declarations disagree.'
Assert-PublicInput ([string]$benchmark.public_smoke.result_schema -ceq [string]$benchmark.paths.public_smoke_schema) 'Public-smoke schema declarations disagree.'
Assert-PublicInput ($benchmark.public_smoke.gameplay_requirements_evaluated -eq $false) 'Public smoke must not claim gameplay evaluation.'
foreach ($requiredAssertion in @('package_identity','tool_identity','contract_schema','project_copy','data_validation','initial_start','initial_capture','reopen_identity','reopen_capture','final_cleanup')) {
    Assert-PublicInput ($requiredAssertion -cin @($benchmark.public_smoke.minimum_assertions)) "Public smoke is missing assertion: $requiredAssertion"
}
foreach ($protectedRoot in @('assets/legal','self-check')) {
    Assert-PublicInput ($protectedRoot -cin @($benchmark.workspace.protected_roots)) "Protected root is missing: $protectedRoot"
}

$catalogIndex = Read-Json 'tools/catalog/UNREAL_ENGINE_5_6_1_INTERFACE_CATALOG.index.json'
$catalogArchivePath = Join-Path $script:Root 'tools/catalog/UNREAL_ENGINE_5_6_1_INTERFACE_CATALOG.jsonl.gz'
$catalogHash = (Get-FileHash -LiteralPath $catalogArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-PublicInput ([string]$catalogIndex.engine.version -ceq '5.6.1' -and [long]$catalogIndex.engine.changelist -eq 44394996) 'The interface catalog engine identity is incorrect.'
Assert-PublicInput ([string]$catalogIndex.engine.platform -ceq 'Windows x64' -and [string]$catalogIndex.engine.mode -ceq 'editor_game') 'The interface catalog target identity is incorrect.'
Assert-PublicInput ([int]$catalogIndex.entry_count -eq 523937) 'The interface catalog entry count is incorrect.'
Assert-PublicInput ([long]$catalogIndex.catalog_byte_length -eq (Get-Item -LiteralPath $catalogArchivePath).Length) 'The interface catalog byte length is incorrect.'
Assert-PublicInput ([string]$catalogIndex.catalog_sha256 -ceq $catalogHash) 'The interface catalog archive hash is incorrect.'
Assert-PublicInput ($catalogIndex.host_paths_recorded -eq $false) 'The interface catalog records host paths.'
foreach ($kind in @('public_cpp_callable','blueprint_callable','blueprint_property','console_command','console_variable','config_setting','automation_tool_command','unreal_build_tool_mode','plugin_descriptor','plugin_module')) {
    Assert-PublicInput ([int]$catalogIndex.counts_by_kind.$kind -gt 0) "The interface catalog is missing kind: $kind"
}

$gdd = Get-Content -LiteralPath (Join-Path $script:Root 'GDD.md') -Raw -Encoding UTF8
$section6Match = [regex]::Match($gdd, '(?ms)^## 6\. Numbered Requirements: Sole Acceptance Authority\s*(?<body>.*?)^## 7\. ')
Assert-PublicInput ($section6Match.Success) 'GDD Section 6 boundary is missing.'
Assert-PublicInput ($section6Match.Groups['body'].Value.Contains('### 6.1 Requirement Splitting Rule')) 'GDD Section 6.1 splitting rule is missing.'
Assert-PublicInput ($section6Match.Groups['body'].Value.Contains('### 6.2 Task-Specific Requirements')) 'GDD Section 6.2 task-specific requirements are missing.'
Assert-PublicInput ($section6Match.Groups['body'].Value.Contains('### 6.3 Shared Quality Requirements')) 'GDD Section 6.3 shared quality requirements are missing.'
$requirementRows = [regex]::Matches($section6Match.Groups['body'].Value, '(?m)^\| (?:PLAYER-CONTROL|PRESENTATION|COMBAT|ATTRIBUTE|RESOURCE|AI|SURVIVAL|ENDGAME|UI|LIFECYCLE|QUALITY)-\d{2} \|')
Assert-PublicInput ($requirementRows.Count -eq 194) "GDD requirement row count is $($requirementRows.Count), expected 194."
$ids = [regex]::Matches($gdd, '(?<![A-Z0-9-])(?:PLAYER-CONTROL|PRESENTATION|COMBAT|ATTRIBUTE|RESOURCE|AI|SURVIVAL|ENDGAME|UI|LIFECYCLE|QUALITY)-\d{2}(?!\d)') |
    ForEach-Object Value | Sort-Object -Unique
Assert-PublicInput (@($ids).Count -eq 194) 'GDD does not expose exactly 194 unique requirement IDs.'
Assert-PublicInput ($gdd.Contains('## 13. Pre-Submission Self-Check')) 'GDD Section 13 is missing.'

$assetCatalog = Read-Json 'assets/ASSET_CATALOG.json'
$actualAssets = Get-ChildItem -LiteralPath (Join-Path $script:Root 'starter-project/Content') -File -Recurse |
    Where-Object { $_.Extension -in '.uasset', '.umap' }
Assert-PublicInput ([int]$assetCatalog.asset_count -eq @($actualAssets).Count) 'Asset catalog count does not match the project.'
foreach ($asset in $assetCatalog.assets) {
    $assetPath = Join-Path $script:Root ([string]$asset.path)
    Assert-PublicInput (Test-Path -LiteralPath $assetPath -PathType Leaf) "Cataloged asset is missing: $($asset.path)"
    $hash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-PublicInput ($hash -ceq [string]$asset.sha256) "Cataloged asset hash mismatch: $($asset.path)"
}

$coverage = Read-Json 'ASSET_COVERAGE.json'
Assert-PublicInput (@($coverage.requirements).Count -eq 27) 'Asset coverage must contain 27 presentation requirements.'
foreach ($entry in $coverage.requirements) {
    Assert-PublicInput (@($entry.object_paths).Count -gt 0) "Asset coverage is empty: $($entry.requirement_id)"
}

$assetManifest = Read-Json 'ASSET_MANIFEST.json'
Assert-PublicInput ([string]$assetManifest.license -ceq 'assets/legal/LICENSE_SCOPE.md') 'Asset manifest legal authority is incorrect.'
Assert-PublicInput ([string]$assetManifest.license_map -ceq 'assets/legal/ASSET_LICENSE_MAP.json') 'Asset manifest license map is incorrect.'
Assert-PublicInput ([string]$assetManifest.notices -ceq 'THIRD_PARTY_NOTICES.md') 'Asset manifest notices path is incorrect.'
$licenseMap = Read-Json 'assets/legal/ASSET_LICENSE_MAP.json'
$catalogLicenseCounts = @{}
foreach ($asset in $assetCatalog.assets) {
    $id = [string]$asset.license_id
    if (-not $catalogLicenseCounts.ContainsKey($id)) { $catalogLicenseCounts[$id] = 0 }
    $catalogLicenseCounts[$id]++
}
foreach ($license in $licenseMap.licenses) {
    $id = [string]$license.license_id
    Assert-PublicInput ($catalogLicenseCounts.ContainsKey($id)) "License map contains an unused license_id: $id"
    Assert-PublicInput ([int]$license.asset_count -eq [int]$catalogLicenseCounts[$id]) "License count mismatch: $id"
    [void]$catalogLicenseCounts.Remove($id)
}
Assert-PublicInput ($catalogLicenseCounts.Count -eq 0) 'One or more catalog license_id values are missing from the public license map.'

[void](Read-Json 'self-check/PublicSmoke/schemas/public-smoke-result.schema.json')
$smokeScriptPath = Join-Path $script:Root 'self-check/PublicSmoke/Invoke-PublicSmoke.ps1'
$smokeTokens = $null
$smokeErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($smokeScriptPath, [ref]$smokeTokens, [ref]$smokeErrors)
Assert-PublicInput (@($smokeErrors).Count -eq 0) 'Public-smoke PowerShell syntax is invalid.'

$textExtensions = @('.md', '.txt', '.json', '.ini', '.uproject', '.ps1', '.psm1', '.cs', '.cpp', '.h', '.csproj', '.xml', '.csv')
$textFiles = Get-ChildItem -LiteralPath $script:Root -File -Recurse -Force |
    Where-Object { $_.Extension.ToLowerInvariant() -in $textExtensions }
$absolutePathPattern = '(?i)(?:[A-Z]:\\(?:Users|Documents and Settings|home)\\|/(?:home|Users)/[^/\s]+/)'
$secretPattern = '(?i)(?:api[_-]?key|secret|token|password)\s*[:=]\s*["''][^"'']{8,}'
foreach ($file in $textFiles) {
    $relative = Get-RelativePath $file.FullName
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    Assert-PublicInput (-not [regex]::IsMatch($text, '[\u3400-\u9fff]')) "Non-English Han text found: $relative"
    Assert-PublicInput (-not [regex]::IsMatch($text, $absolutePathPattern)) "Host-specific absolute path found: $relative"
    Assert-PublicInput (-not [regex]::IsMatch($text.Replace("'process-'", "'prefix'"), $secretPattern)) "Potential credential found: $relative"
}
















[pscustomobject][ordered]@{
    status = 'passed'
    requirement_count = 194
    asset_count = @($actualAssets).Count

    engine_version = '5.6.1'
} | ConvertTo-Json -Depth 4
