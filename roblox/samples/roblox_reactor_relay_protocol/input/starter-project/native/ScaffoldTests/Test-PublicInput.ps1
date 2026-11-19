$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$required = @(
  'ASSIGNMENT.txt','GDD.md','Reactor_Relay_Protocol_GDD.docx','EVALUABILITY_CONTRACT.md',
  'EVALUATION_SCHEMA.json','VISUAL_DIRECTION.md','ROBLOX_STUDIO_ENGINE_TOOL_INTERFACE_CATALOG.md',
  'RETURN_CHECKLIST.txt','DEVELOPMENT_TRACE_REQUIREMENTS.md','project\default.project.json',
  'project\src\shared\ReactorRelaySchema.luau','ReactorRelayStart.rbxlx','legal\LICENSE.txt'
)
foreach($rel in $required){ if(-not (Test-Path -LiteralPath (Join-Path $root $rel))){ throw "Missing: $rel" } }
$schema = Get-Content -Raw -LiteralPath (Join-Path $root 'EVALUATION_SCHEMA.json') | ConvertFrom-Json
$project = Get-Content -Raw -LiteralPath (Join-Path $root 'project\default.project.json') | ConvertFrom-Json
if($schema.contract_version -ne 'reactor-relay-v2-hard'){ throw 'Wrong contract version' }
if(@($schema.control_ids).Count -ne 19){ throw 'Control count must be 19' }
if(@($schema.hud_field_ids).Count -ne 16){ throw 'HUD field count must be 16' }
if(@($schema.bay_ids).Count -ne 3){ throw 'Bay count must be 3' }
if(@($schema.cycle_targets).Count -ne 6){ throw 'Cycle target count must be 6' }
if(@($schema.lock_orders).Count -ne 6){ throw 'Lock order count must be 6' }
if(@($schema.final_sequence).Count -ne 8){ throw 'Final sequence count must be 8' }
if(@($schema.logical_layout.controls.PSObject.Properties).Count -ne 19){ throw 'Logical control rectangle count must be 19' }
if($schema.logical_layout.canvas[0] -ne 1600 -or $schema.logical_layout.canvas[1] -ne 900){ throw 'Logical canvas must be 1600x900' }
if($project.name -ne 'ReactorRelayPublicStart'){ throw 'Wrong project name' }
$toolCatalog = Get-Content -Raw -LiteralPath (Join-Path $root 'ROBLOX_STUDIO_ENGINE_TOOL_INTERFACE_CATALOG.md')
if($toolCatalog -notmatch 'catalog_revision: 2026.08.31-base-interfaces'){ throw 'Wrong Roblox tool catalog' }
$gdd = Get-Content -Raw -LiteralPath (Join-Path $root 'GDD.md')
foreach($section in 1..14){ if($gdd -notmatch "(?m)^#+ $section( |$)"){ throw "GDD section missing: $section" } }
$combined = Get-Content -Raw -LiteralPath (Join-Path $root 'ASSIGNMENT.txt'),(Join-Path $root 'GDD.md'),(Join-Path $root 'EVALUABILITY_CONTRACT.md')
foreach($term in @('D1','D2','D3','D4','D5','D6','Gold implementation','private evaluator trajectory','expected score')){
  if(($combined -join "`n") -match [regex]::Escape($term)){ throw "Private/leak term found: $term" }
}
Write-Host 'Reactor Relay public input scaffold: PASS'
Write-Host 'This is static validation only; runtime gameplay is NOT RUN.'
