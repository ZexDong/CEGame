[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/ActionRoguelikeAtomicChecks.ps1')
. (Join-Path $root 'scripts/ActionRoguelikeStateAdapter.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Invoke-ActionRoguelikeCanonicalEvaluation.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Runner syntax errors.'}
foreach($name in @('Write-JsonFile','Get-Relative','Save-Receipt','Set-Checkpoint','Set-AtomicCheckpoint','Get-CanonicalEventChain','New-CanonicalAtomicTrace')){
    $definition=$ast.Find({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-eq$name},$true)
    Invoke-Expression $definition.Extent.Text
}
$script:checks=0
function Assert([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message};$script:checks++}
function Pair([long]$Sequence,[string]$Previous=''){
    $identity=@{process_token='test-process';round_id='test-round';snapshot_id="s-$Sequence";sequence=$Sequence;monotonic_ms=$Sequence*100}
    $eventIdentity=$identity.Clone();$eventIdentity.batch_id="b-$Sequence"
    @{snapshot=@{identity=$identity};events=@{identity=$eventIdentity;coverage=@{stream_epoch='test-epoch';previous_batch_id=$(if($Previous){$Previous}else{$null});cursor_start=0;cursor_end=0;head_watermark=0;tail_watermark=0;dropped_event_count=0};events=@()}}
}
function Context {
    @{event_epoch=$null;event_cursor_start=[long]-1;event_cursor_end=[long]-1;event_batch_id=$null;event_ids=@{};event_chain_verified=$false;event_empty_compatibility_count=0;event_sample_count=0}
}
$temporaryParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$script:OutputFull=Join-Path $temporaryParent ('actionroguelike-health-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:OutputFull|Out-Null
try{
    $map=Get-ActionRoguelikeAtomicVariantMap
    $faults=[Collections.Generic.List[object]]::new();$script:VerdictsById=@{}
    foreach($id in $map.Keys){
        $script:VerdictsById[$id]=[pscustomobject]@{checkpoint_id=$id;verdict=$null;detail='';reason_code=$null;attribution=$null;first_failure=$null;score_impact=$null;evidence=@()}
        $result=Test-ActionRoguelikeAtomicCheckpoint $id @{}
        Set-AtomicCheckpoint $id $result
        $row=$script:VerdictsById[$id]
        Assert ($row.attribution-ceq'evaluator'-and$row.score_impact-ceq'run_invalid') 'Uncollected variants were converted to candidate zeroes.'
        Assert (Test-Path -LiteralPath (Join-Path $script:OutputFull $row.first_failure)) 'The collection blocker has no actual receipt.'
    }
    Assert ($faults.Count-eq8) 'Missing collectors did not invalidate all affected atomic checks.'
    $first=Pair 1;$next=Pair 2 'b-1'
    $trace=New-CanonicalAtomicTrace 'resources.initial' @($first,$next)
    Assert ($trace.execution.status-ceq'evaluator_blocked'-and$trace.execution.reason_code-ceq'ATOMIC_TRACE_NOT_ISOLATED') 'Shared smoke samples were promoted to independent evidence.'
    Assert (-not$trace.Contains('cleanup')-and-not$trace.Contains('input_receipts')-and-not$trace.Contains('setup')) 'The runner fabricated a setup, input, or cleanup receipt.'
    Assert (@(Get-ChildItem (Join-Path $script:OutputFull 'receipts') -Filter 'atomic-cleanup-*').Count-eq0) 'The runner wrote a fake process-stop receipt.'
    $heartbeat=Pair 2;$heartbeat.events.identity.batch_id='b-1'
    $trace=New-CanonicalAtomicTrace 'resources.initial' @($first,$heartbeat)
    Assert ($trace.execution.reason_code-ceq'ATOMIC_EVENT_STREAM_UNAVAILABLE') 'The live runner misclassified legacy Gold heartbeats.'
    $result=Test-ActionRoguelikeAtomicCheckpoint 'D3-07' @{'resources.initial'=$trace}
    Assert ($result.verdict-ceq'run_invalid'-and$result.reason_code-ceq'ATOMIC_EVENT_STREAM_UNAVAILABLE') 'An evaluator collection fault lost its root cause.'
    $context=Context
    $null=Test-ActionRoguelikeEventChainStep $context $first.events
    $chain=Test-ActionRoguelikeEventChainStep $context $next.events
    Assert ($chain.verified) 'Linked empty event batches did not establish valid coverage.'
    $context=Context;$null=Test-ActionRoguelikeEventChainStep $context $first.events
    $chain=Test-ActionRoguelikeEventChainStep $context $heartbeat.events -AllowEmptyCompatibility
    Assert (-not$chain.verified) 'A repeated heartbeat established event absence.'
    $changed=Pair 3;$changed.events.coverage.stream_epoch='changed-epoch';$rejected=$false
    try{$null=Test-ActionRoguelikeEventChainStep $context $changed.events -AllowEmptyCompatibility}catch{$rejected=$_.Exception.Message-ceq'state_event_chain_epoch_changed'}
    Assert $rejected 'Empty compatibility concealed an epoch change.'
    $context=Context;$null=Test-ActionRoguelikeEventChainStep $context $first.events
    $context.event_cursor_end=2;$rejected=$false
    try{$null=Test-ActionRoguelikeEventChainStep $context $heartbeat.events -AllowEmptyCompatibility}catch{$rejected=$_.Exception.Message-ceq'state_event_chain_cumulative_truncated'}
    Assert $rejected 'An empty heartbeat erased an already observed event range.'
    Write-Output "ACTIONROGUELIKE_HEALTH_GATE_OK checks=$script:checks empty_variants=true honest_receipts=true heartbeat_attribution=true"
}finally{
    $target=[IO.Path]::GetFullPath($script:OutputFull)
    if([IO.Path]::GetDirectoryName($target)-cne[IO.Path]::TrimEndingDirectorySeparator($temporaryParent)-or[IO.Path]::GetFileName($target)-notlike'actionroguelike-health-*'){throw 'Unsafe temporary cleanup path.'}
    if((Get-Item -LiteralPath $target).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Unsafe temporary cleanup reparse point.'}
    Remove-Item -LiteralPath $target -Recurse -Force
}
