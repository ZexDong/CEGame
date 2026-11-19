[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Import-Module (Join-Path $root 'scripts/BomberObservation.psm1') -Force
function Assert([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Clone($Value){return $Value|ConvertTo-Json -Depth 50|ConvertFrom-Json -Depth 50}
$layout=Get-Content -LiteralPath (Join-Path $root '../input/project/Config/BomberArenaLayout.json') -Raw|ConvertFrom-Json
$before=[pscustomobject]@{process_token='test';round_id='r1';monotonic_ms=1000;game_state=[pscustomobject]@{
    bombs=@([pscustomobject]@{object_id='a';owner_id='player_1';cell=@{x=3;y=1};captured_fire=2;fuse_remaining_ms=1000;state='armed'},[pscustomobject]@{object_id='b';owner_id='player_1';cell=@{x=1;y=1};captured_fire=2;fuse_remaining_ms=1400;state='armed'})
    crates=@([pscustomobject]@{cell=@{x=5;y=1};state='present'},[pscustomobject]@{cell=@{x=3;y=3};state='present'})
    players=@([pscustomobject]@{object_id='player_1';resources=@{bombs_available=0}},[pscustomobject]@{object_id='player_2';resources=@{bombs_available=1}})
    explosion_cells=@()
}}
$expected=Get-BomberChainExpectation $before $layout
Assert ($expected.cells.Count -eq 9 -and $expected.later_due_ms -eq 2400) 'Expected public chain geometry or fuse deadline is wrong.'
$removed=Clone $before; $removed.monotonic_ms=2050; $removed.game_state.bombs=@();$removed.game_state.explosion_cells=@($expected.cells|ForEach-Object{$xy=$_ -split ',';[pscustomobject]@{x=[int]$xy[0];y=[int]$xy[1]}})
$removed.game_state.players[0].resources.bombs_available=2
$retained=Clone $removed;$retained.game_state.bombs=Clone $before.game_state.bombs;foreach($b in $retained.game_state.bombs){$b.state='exploding'}
Assert (Test-BomberChainSample $removed $expected) 'Removed resolved records were rejected.'
Assert (Test-BomberChainSample $retained $expected) 'Retained exploding records were rejected.'
Assert (Test-BomberChainRefund $removed $expected) 'Correct owner refunds were rejected.'
$bad=Clone $removed;$bad.game_state.explosion_cells=$bad.game_state.explosion_cells|Select-Object -Skip 1
Assert (-not(Test-BomberChainSample $bad $expected)) 'Missing blast cell was accepted.'
$bad=Clone $removed;$bad.game_state.bombs=@($before.game_state.bombs[1])
Assert (-not(Test-BomberChainPresence $bad $expected)) 'An untriggered armed bomb was accepted as a chain.'
$bad=Clone $removed;$bad.game_state.players[0].resources.bombs_available=1
Assert (-not(Test-BomberChainRefund $bad $expected)) 'Missing refund was accepted.'
$bad=Clone $removed;$bad.round_id='r2'
Assert (-not(Test-BomberChainSample $bad $expected)) 'Cross-round evidence was accepted.'

function MovementSamples([int]$Step,[int]$Duration,[int]$Period=50){
    foreach($t in 0..([int]($Duration/$Period))){$ms=$t*$Period;$x=if($ms -lt 10){1}else{2+[int][Math]::Floor(($ms-10)/$Step)}
        [pscustomobject]@{process_token='test';round_id='r1';monotonic_ms=$ms;game_state=@{players=@(@{object_id='player_1';cell=@{x=$x;y=1}})}}
    }
}
$base=Measure-BomberMovementSamples @(MovementSamples 180 400) player_1 160 200
$fast=Measure-BomberMovementSamples @(MovementSamples 115 600) player_1 100 130
$slow=Measure-BomberMovementSamples @(MovementSamples 300 650) player_1 160 200
Assert ($base.pass -and $fast.pass -and $fast.interval_estimate_ms -lt $base.interval_estimate_ms) 'Legal base/Skate samples failed.'
Assert (-not $slow.pass -and $slow.status -eq 'measured') 'A real slow-motion defect was accepted.'
$sparse=Measure-BomberMovementSamples @(MovementSamples 180 750 250) player_1 160 200
Assert ($sparse.status -eq 'measurement_invalid') 'Coarse transport sampling was blamed on the candidate.'
$refined=Merge-BomberMovementMeasurements @(@{interval_lower_ms=100;interval_upper_ms=202},@{interval_lower_ms=153;interval_upper_ms=251}) 160 200
Assert ($refined.status -eq 'measured' -and $refined.pass -and $refined.interval_lower_ms -eq 153 -and $refined.interval_upper_ms -eq 202) 'Independent timing brackets were not intersected.'
$inconsistent=Merge-BomberMovementMeasurements @(@{interval_lower_ms=160;interval_upper_ms=200},@{interval_lower_ms=280;interval_upper_ms=320}) 160 200
Assert ($inconsistent.status -eq 'measurement_invalid' -and -not $inconsistent.pass) 'Contradictory trials must not select a favorable result or become a candidate zero.'
$stillSparse=Merge-BomberMovementMeasurements @(@{interval_lower_ms=100;interval_upper_ms=202},@{interval_lower_ms=110;interval_upper_ms=210}) 160 200
Assert ($stillSparse.status -eq 'measurement_invalid') 'Refinement relaxed the precision limit.'

$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Invoke-BomberCanonicalEvaluation.ps1'),[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'Runner has syntax errors.'
$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-SemanticCapture'},$true)
. ([scriptblock]::Create($node.Extent.Text))
$script:CaptureCalls=0
function Save-Capture { $script:CaptureCalls++;throw 'Should not capture an absent state.' }
$result=Save-SemanticCapture chain-reaction chain-reaction $null {param($s)$true}
Assert ($null -eq $result -and $script:CaptureCalls -eq 0) 'Timed-out state produced a misleading screenshot.'
Write-Output 'OBSERVATION_OK equivalent_bomb_lifetimes=true negative_chain_cases=true clock_bounds=true missing_state_no_capture=true'
