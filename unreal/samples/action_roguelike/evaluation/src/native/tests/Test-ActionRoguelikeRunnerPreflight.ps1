[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$evaluator=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture=Join-Path $temporaryParent ('actionroguelike-preflight-'+[guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-Fixture([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text)}
try {
    $engine=Join-Path $fixture 'engine with spaces'
    Write-Fixture (Join-Path $engine 'Engine/Build/Build.version') '{"MajorVersion":5,"MinorVersion":6,"PatchVersion":1,"Changelist":44394996}'
    # These files are never executed: the missing candidate must stop preflight.
    foreach($path in @('Engine/Binaries/Win64/UnrealEditor.exe','Engine/Binaries/Win64/UnrealEditor-Cmd.exe','Engine/Build/BatchFiles/Build.bat')){Write-Fixture (Join-Path $engine $path) ''}
    $output=Join-Path $fixture 'run with spaces'
    & (Join-Path $evaluator 'scripts/Invoke-ActionRoguelikeCanonicalEvaluation.ps1') -CandidateProject (Join-Path $fixture 'missing/project.uproject') -EngineRoot $engine -OutputDirectory $output -RunId 'preflight-test' -CandidateId 'missing-project' | Out-Null
    $run=Get-Content -LiteralPath (Join-Path $output 'verdicts.json') -Raw|ConvertFrom-Json -Depth 100
    Assert ([string]$run.evaluator_revision -match '^actionroguelike-evaluator-[0-9]+\.[0-9]+\.[0-9]+$' -and $run.run_status -ceq 'completed') 'A candidate preflight failure must produce a completed numeric verdict run.'
    Assert (@($run.faults|Where-Object code -eq 'runtime_exception').Count -eq 0) 'The real runner raised an unexpected exception.'
    Assert (@($run.checkpoints|Where-Object reason_code -eq 'EVALUATOR_CASE_NOT_IMPLEMENTED').Count -eq 0 -and @($run.checkpoints|Where-Object verdict -eq 'not_evaluated').Count -eq 0) 'Early static failure retained a removed authoring-gap verdict.'
    Assert (@($run.checkpoints|Where-Object {$_.checkpoint_id -eq 'D1-01' -and $_.reason_code -eq 'CANDIDATE_PROJECT_MISSING'}).Count -eq 1) 'Missing candidate attribution was lost.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $output 'evaluation-not-completed.json'))) 'A candidate failure incorrectly produced an evaluator-incomplete result.'
    Assert (-not(Test-Path -LiteralPath (Join-Path $output 'receipts/start.json'))) 'Preflight attempted to launch a missing candidate.'
    foreach($check in $run.checkpoints){foreach($path in $check.evidence){Assert (Test-Path -LiteralPath (Join-Path $output $path) -PathType Leaf) "Missing checkpoint evidence: $path"}}
    foreach($fault in $run.faults){foreach($path in $fault.evidence_paths){Assert (Test-Path -LiteralPath (Join-Path $output $path) -PathType Leaf) "Missing fault evidence: $path"}}
    . (Join-Path $evaluator 'scripts/ActionRoguelikeStateAdapter.ps1')
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $evaluator 'scripts/Invoke-ActionRoguelikeCanonicalEvaluation.ps1'),[ref]$tokens,[ref]$parseErrors)
    $healthFunction=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-ExecutorOperationHealth'},$true)
    . ([scriptblock]::Create($healthFunction.Extent.Text))
    $faults=[Collections.Generic.List[object]]::new();$rejected=$false
    try{Assert-ExecutorOperationHealth @{status='environment_fault';environment_fault=$true;fault=@{domain='environment';code='input_state_not_neutral';message='A pointer button is held.'}} 'receipts/reopen.json'}catch{$rejected=$_.Exception.Message -eq 'evaluator_operation_stop'}
    Assert ($rejected -and $faults.Count -eq 1 -and $faults[0].domain -eq 'environment') 'Host input interference became a candidate failure.'
    $faults.Clear()
    Assert-ExecutorOperationHealth @{status='environment_fault';environment_fault=$true;fault=@{domain='environment';code='process_exited_during_start';message='Candidate exited.'}} 'receipts/start.json'
    Assert ($faults.Count -eq 0) 'Candidate process exit was converted into infrastructure failure.'
    Write-Output 'ACTIONROGUELIKE_RUNNER_PREFLIGHT_OK full_script=true early_failure_attribution=true atomic_cases_executable=true evidence_exists=true no_unreal_started=true'
} finally {
    $cleanup=[IO.Path]::GetFullPath($fixture)
    if([IO.Path]::TrimEndingDirectorySeparator((Split-Path -Parent $cleanup)) -ne [IO.Path]::TrimEndingDirectorySeparator($temporaryParent) -or [IO.Path]::GetFileName($cleanup) -notlike 'actionroguelike-preflight-*'){throw 'Unsafe fixture cleanup path.'}
    if(Test-Path -LiteralPath $cleanup){Remove-Item -LiteralPath $cleanup -Recurse -Force}
}
