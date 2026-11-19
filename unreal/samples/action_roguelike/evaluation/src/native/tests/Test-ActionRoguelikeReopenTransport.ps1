[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$runner=Join-Path $PSScriptRoot '../scripts/Invoke-ActionRoguelikeCanonicalEvaluation.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$null,[ref]$null)
$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Reopen-TaskWithFreshTransport'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
$startDefinition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Start-TaskEvaluationSession'},$true)
. ([scriptblock]::Create($startDefinition.Extent.Text))
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
function Start-ActionRoguelikeTransportRecorder($SnapshotPath,$EventsPath){
    Assert ($SnapshotPath.StartsWith($script:OutputFull)-and$EventsPath.StartsWith($script:OutputFull)) 'Recorder escaped the active run.'
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ar-reopen-'+[guid]::NewGuid().ToString('N'))
$script:OutputFull=$temp;$script:ProcessId=42;$script:ProcessToken='old-token';$script:Session='old-session';$script:SessionActive=$true
$script:FixtureChannel=Join-Path $temp 'fixture';$script:StateRoot=Join-Path $temp 'state/old'
[void][IO.Directory]::CreateDirectory($script:StateRoot)
$oldFile=Join-Path $script:StateRoot 'batch-0.json';[IO.File]::WriteAllText($oldFile,'old immutable evidence')
$oldRoot=$script:StateRoot;$script:stopFails=$false;$script:started=$false;$script:neutralFaults=1;$script:leaseFaults=1;$script:startAttempts=0
function Save-Receipt($Value,$Name){return "receipts/$Name.json"}
function Assert-ExecutorOperationHealth($Receipt,$Path){}
function Stop-UnrealEvaluationSession($Session,$GraceTimeoutMs,$FaultCleanupTimeoutMs){
    Assert ($Session-ceq'old-session') 'Wrong session stopped.'
    return @{status=$(if($script:stopFails){'error'}else{'ok'})}
}
function Start-UnrealEvaluationSession($ProjectPath,$RunRoot,$StatePath,$ProcessToken,$EngineRoot,$WindowWidth,$WindowHeight,$TimeoutMs,$FocusTimeoutMs,[switch]$ObserverDisabledControl,$AdditionalArguments){
    $script:startAttempts++
    if($script:leaseFaults-gt0){$script:leaseFaults--;return [pscustomobject]@{status='executor_fault';input_dispatched=$false;result=$null;fault=@{code='active_input_session_exists'}}}
    if($script:neutralFaults-gt0){
        $script:neutralFaults--
        return [pscustomobject]@{status='environment_fault';input_dispatched=$false;result=$null;fault=@{code='input_state_not_neutral'}}
    }
    Assert (-not$script:SessionActive) 'New process started before confirmed stop.'
    Assert ($script:StateRoot-cne$oldRoot-and$StatePath.StartsWith($script:StateRoot)) 'Reopen reused the old state channel.'
    Assert ($ProcessToken-cne'old-token') 'Reopen reused old process identity.'
    Assert (@($AdditionalArguments|Where-Object{$_-ceq"-ActionRoguelikeEventsPath=$($script:EventsPath)"}).Count-eq1) 'Fresh event path not passed to publisher.'
    $script:started=$true
    return [pscustomobject]@{operation='Start';status='ok';result=[pscustomobject]@{process_id=43;process_token=$ProcessToken;session='new-session'}}
}
try{
    $r=Reopen-TaskWithFreshTransport 'candidate.uproject' 'engine'
    Assert ($r.operation-ceq'Reopen'-and$r.result.old_process_id-eq42-and$r.result.normal_old_stop_confirmed) 'Missing composed Reopen provenance.'
    Assert ($script:startAttempts-eq3) 'Transient pre-dispatch lease/key conditions did not recover.'
    Assert ([IO.File]::ReadAllText($oldFile)-ceq'old immutable evidence') 'Prior evidence was overwritten.'
    $script:stopFails=$true;$script:started=$false;$failed=$false
    try{$null=Reopen-TaskWithFreshTransport 'candidate.uproject' 'engine'}catch{$failed=$_.Exception.Message-like'*REOPEN_STOP_FAILED*'}
    Assert ($failed-and-not$script:started) 'Unconfirmed termination allowed a second process.'
    Write-Output 'ACTIONROGUELIKE_REOPEN_TRANSPORT_OK fresh_channel=true old_evidence_preserved=true stop_failure_blocks_start=true'
}finally{
    $absolute=[IO.Path]::GetFullPath($temp)
    if([IO.Path]::GetDirectoryName($absolute)-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())-or[IO.Path]::GetFileName($absolute)-notlike'ar-reopen-*'){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
