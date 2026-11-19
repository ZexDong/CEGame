$ErrorActionPreference = 'Stop'
$inputRoot = Split-Path -Parent $PSScriptRoot

function Require-File([string]$relativePath) {
    $fullPath = Join-Path $inputRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing required public file: $relativePath" }
}

$manifest = Get-Content -LiteralPath (Join-Path $inputRoot 'BENCHMARK_MANIFEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.time_limit_seconds -ne 3600) { throw 'Expected time_limit_seconds = 3600.' }
if ($manifest.timeout_policy -notmatch 'no second') { throw 'Timeout policy must prohibit a second development window.' }

$required = @(
    'README.md','INITIAL_AGENT_PROMPT.md','GDD.md','BENCHMARK_MANIFEST.json','ASSET_MANIFEST.json',
    'ASSET_CATALOG.json','ASSET_CATALOG.md','ASSET_COVERAGE.json','ASSET_CONTACT_SHEET.png',
    'ROBLOX_STUDIO_TOOL_GUIDE.md','TOOLCHAIN.md','EVALUABILITY_CONTRACT.md','EVALUATION_SCHEMA.json',
    'VISUAL_DIRECTION.md','TaskAssets\style_palette.json','DeepRelayStart.rbxlx',
    'project\default.project.json','project\src\shared\DeepRelaySchema.luau','legal\LICENSE.txt'
)
foreach ($item in $required) { Require-File $item }

foreach ($privateName in @('gold','evaluation','original','formal_evidence','score.json','evidence.json')) {
    if (Test-Path -LiteralPath (Join-Path $inputRoot $privateName)) { throw "Private material leaked into input: $privateName" }
}

$projectPath = Join-Path $inputRoot 'project\default.project.json'
$projectRaw = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8
$project = $projectRaw | ConvertFrom-Json
if (-not $project.name) { throw 'Starter project has no name.' }
if ($projectRaw -match '"\$path"\s*:\s*"([A-Za-z]:|\\\\|/)') { throw 'Rojo project contains an absolute $path.' }

$schemaPath = Join-Path $inputRoot 'project\src\shared\DeepRelaySchema.luau'
$schemaRaw = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
if ($schemaRaw -notmatch 'DeepRelay|deep-relay-v1' -or $schemaRaw -notmatch 'DR_NavLink') { throw 'Public Deep Relay Schema identity check failed.' }

$contractRaw = Get-Content -LiteralPath (Join-Path $inputRoot 'EVALUABILITY_CONTRACT.md') -Raw -Encoding UTF8
if ($contractRaw -notmatch 'Configuration' -or $contractRaw -match 'Each edge uses PathfindingLink') { throw 'Deep Relay NavLink protocol correction is missing.' }

try { [xml](Get-Content -LiteralPath (Join-Path $inputRoot 'DeepRelayStart.rbxlx') -Raw -Encoding UTF8) | Out-Null }
catch { throw "Starter RBXLX is not readable XML: $($_.Exception.Message)" }

$toolResult = [ordered]@{ rojo = 'NOT_RUN'; luau_compile = 'NOT_RUN' }
$rojo = Get-Command rojo -ErrorAction SilentlyContinue
if ($rojo) {
    $tempPlace = Join-Path ([System.IO.Path]::GetTempPath()) ("deep_relay_scaffold_" + [guid]::NewGuid().ToString('N') + '.rbxlx')
    & $rojo.Source build $projectPath -o $tempPlace | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPlace)) { throw 'Optional Rojo starter build failed.' }
    Remove-Item -LiteralPath $tempPlace -Force
    $toolResult.rojo = 'PASS'
}
$luau = Get-Command luau-compile -ErrorAction SilentlyContinue
if ($luau) {
    & $luau.Source $schemaPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Optional luau-compile check failed.' }
    $toolResult.luau_compile = 'PASS'
}

Write-Host 'Scaffold input check: PASS'
Write-Host ("Optional surfaces: " + ($toolResult | ConvertTo-Json -Compress))
