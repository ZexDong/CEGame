[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Import-Module (Join-Path $root 'scripts/BomberEvaluator.Common.psm1') -Force
$state = [pscustomobject]@{schema_version='2.0.0';process_token='test';process_id=1;snapshot_id=1;round_id='r1';round_index=0;restart_count=0;monotonic_ms=250;bridge_ready=$true;provider_ready=$false;game_state=$null}
$validation = Test-BomberStateEnvelope -State $state -ExpectedProcessToken test -ExpectedProcessId 1 -AllowProviderNotReady -PreviousState $state
if ($validation.code -ne 'STATE_SNAPSHOT_REPEATED') { throw 'Repeated heartbeat was not identified.' }
$regressed = $state.PSObject.Copy(); $regressed.snapshot_id=0
$validation = Test-BomberStateEnvelope -State $regressed -ExpectedProcessToken test -ExpectedProcessId 1 -AllowProviderNotReady -PreviousState $state
if ($validation.code -ne 'STATE_NOT_ADVANCING') { throw 'Regressed heartbeat was accepted.' }

# Load the actual wait function without launching a game or the full runner.
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Invoke-BomberCanonicalEvaluation.ps1'),[ref]$tokens,[ref]$errors)
$waitNode=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Wait-BomberState'},$true)
Invoke-Expression $waitNode.Extent.Text
$script:OutputFull=[IO.Path]::GetTempPath(); $script:StableSamples=2; $script:StatePollMs=1; $script:LastStateDiagnostic=$null
function Write-JsonFile { param($Value,$Path) }
function Save-State { param($Value,$Name) return 'mock.json' }
function Read-BomberState {
    param([switch]$AllowProviderNotReady)
    $next=$script:Samples.Dequeue()
    $script:LastStateDiagnostic=[pscustomobject]@{code=if($null -eq $next){'STATE_SNAPSHOT_REPEATED'}else{'OK'}}
    return $next
}
$second=$state.PSObject.Copy();$second.snapshot_id=2;$second.monotonic_ms=500
$script:Samples=[Collections.Generic.Queue[object]]::new()
foreach($sample in @($state,$null,$null,$null,$null,$second)){$script:Samples.Enqueue($sample)}
$result=Wait-BomberState -Condition {param($s) $true} -TimeoutSeconds 1
if($null -eq $result -or $result.snapshot_id -ne 2){throw '250 ms heartbeat could not satisfy two fresh samples.'}
if($script:Samples.Count -ne 0){throw 'Repeated samples were incorrectly counted as fresh evidence.'}
Write-Output 'HEARTBEAT_POLLING_OK repeated_samples_ignored=true regression_rejected=true two_distinct_samples_required=true'
