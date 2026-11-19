[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Assert([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}

$root=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSCommandPath) '..'))
. (Join-Path $root 'scripts/ActionRoguelikeStateAdapter.ps1')

function New-Identity([string]$Token){
    [pscustomobject]@{process_token=$Token;round_id='round-1';snapshot_id='snapshot-1'}
}
function New-Snapshot([string]$Token){
    [pscustomobject]@{
        schema_version='1.0.0'
        identity=New-Identity $Token
        player=[pscustomobject]@{position_m=[pscustomobject]@{value=[pscustomobject]@{x=1;y=2;z=3}}}
        controls=@('move_forward','move_backward','move_left','move_right','jump','sprint','primary_attack','black_hole','teleport','interact','restart'|ForEach-Object{[pscustomobject]@{semantic_action=$_}})
    }
}
function New-Events([string]$Token){
    [pscustomobject]@{
        schema_version='2.0.0'
        identity=New-Identity $Token
        coverage=[pscustomobject]@{cursor_start=0;cursor_end=0;head_watermark=0;tail_watermark=0;dropped_event_count=0}
    }
}

$launcher=Test-ActionRoguelikeStatePair -Snapshot (New-Snapshot 'launcher-token') -Events (New-Events 'launcher-token') -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242
Assert $launcher.valid 'The launcher-token identity was rejected.'
Assert ($launcher.identity_binding -ceq 'launcher_process_token') 'The launcher-token binding was not classified correctly.'

$sameProcess=Test-ActionRoguelikeStatePair -Snapshot (New-Snapshot 'process-4242') -Events (New-Events 'process-4242') -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242
Assert $sameProcess.valid 'The exact active-process identity was rejected.'
Assert ($sameProcess.identity_binding -ceq 'active_process_id') 'The active-process binding was not classified correctly.'

$foreign=Test-ActionRoguelikeStatePair -Snapshot (New-Snapshot 'process-9999') -Events (New-Events 'process-9999') -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242
Assert (-not$foreign.valid) 'A foreign process identity was accepted.'
Assert ($foreign.reason_code -ceq 'state_process_identity_mismatch') 'The foreign process reason code is unstable.'

$mismatched=New-Events 'process-4242';$mismatched.identity.snapshot_id='snapshot-2'
$pairMismatch=Test-ActionRoguelikeStatePair -Snapshot (New-Snapshot 'process-4242') -Events $mismatched -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242
Assert (-not$pairMismatch.valid) 'A torn snapshot/event identity pair was accepted.'
Assert ($pairMismatch.reason_code -ceq 'state_pair_identity_mismatch') 'The torn-pair reason code is unstable.'

$sparse=New-Snapshot 'process-4242'
Assert ($null-eq(Get-ActionRoguelikeObservedPathValue $sparse 'player.velocity_mps')) 'A missing optional observation did not return null.'
$position=Get-ActionRoguelikeObservedPathValue $sparse 'player.position_m'
Assert ((Get-ActionRoguelikeVectorMagnitude $position)-gt2.2) 'The safe vector helper returned an invalid magnitude.'

# Cross-sample event continuity is a separate gate from snapshot identity. A
# cumulative batch may repeat old events, but only byte-identical IDs are valid.
$eventContext=New-ActionRoguelikeStateReaderContext -SnapshotSchemaPath (Join-Path $root '../input/contracts/actionroguelike-probe-snapshot.schema.json') -EventsSchemaPath (Join-Path $root '../input/contracts/actionroguelike-probe-events.schema.json') -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242
$eventObservation=@{trust='verified';provenance=@{kind='readonly_probe';source_ref='public/runtime';probe_id='fixture';probe_version='1.0.0'};freshness=@{observed_monotonic_ms=1;valid_for_ms=1000}}
$event1=@{event_id='event-1';sequence=0;monotonic_ms=1;payload=@{reason='first'}}
$batch1=@{identity=@{batch_id='batch-1'};coverage=@{stream_epoch='epoch-1';previous_batch_id=$null;cursor_start=0;cursor_end=1;head_watermark=0;tail_watermark=1;dropped_event_count=0};events=@($event1)}
$chain1=Test-ActionRoguelikeEventChainStep -ReaderContext $eventContext -Events $batch1
Assert (-not$chain1.verified -and $chain1.unique_event_count -eq 1) 'A single event batch incorrectly proved a complete two-sample chain.'
$event2=@{event_id='event-2';sequence=1;monotonic_ms=2;payload=@{reason='second'}}
$batch2=@{identity=@{batch_id='batch-2'};coverage=@{stream_epoch='epoch-1';previous_batch_id='batch-1';cursor_start=0;cursor_end=2;head_watermark=0;tail_watermark=2;dropped_event_count=0};events=@($event1,$event2)}
$chain2=Test-ActionRoguelikeEventChainStep -ReaderContext $eventContext -Events $batch2
Assert ($chain2.verified -and $chain2.unique_event_count -eq 2) 'A valid cumulative event chain was not verified.'
$rewritten=@{identity=@{batch_id='batch-3'};coverage=@{stream_epoch='epoch-1';previous_batch_id='batch-2';cursor_start=0;cursor_end=2;head_watermark=0;tail_watermark=2;dropped_event_count=0};events=@(@{event_id='event-1';sequence=0;monotonic_ms=1;payload=@{reason='rewritten'}},$event2)}
$rewriteRejected=$false;try{$null=Test-ActionRoguelikeEventChainStep -ReaderContext $eventContext -Events $rewritten}catch{$rewriteRejected=$_.Exception.Message -eq 'state_event_chain_event_rewritten'}
Assert $rewriteRejected 'A repeated event ID with changed bytes was accepted.'

$task=[IO.Path]::GetFullPath((Join-Path $root '..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('actionroguelike-state-adapter-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
    [IO.File]::WriteAllText((Join-Path $temp 'snapshot.json'),'{}',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $temp 'events.json'),'{}',[Text.UTF8Encoding]::new($false))
    $invalidRead=Read-ActionRoguelikeStatePair -SnapshotPath (Join-Path $temp 'snapshot.json') -EventsPath (Join-Path $temp 'events.json') -SnapshotSchemaPath (Join-Path $task 'input/contracts/actionroguelike-probe-snapshot.schema.json') -EventsSchemaPath (Join-Path $task 'input/contracts/actionroguelike-probe-events.schema.json') -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242 -TimeoutMilliseconds 500 -PollMilliseconds 5
    Assert (-not$invalidRead.success) 'Invalid schema documents were accepted.'
    Assert ($invalidRead.diagnostic.last_reason_code -ceq 'snapshot_schema_invalid') 'Schema failure diagnostics are not specific.'
}finally{if(Test-Path $temp){Get-ChildItem $temp -File|ForEach-Object{[IO.File]::Delete($_.FullName)};[IO.Directory]::Delete($temp)}}

Write-Output 'ACTIONROGUELIKE_STATE_ADAPTER_OK launcher_token=true active_process_id=true sparse_optional_fields=true torn_pair_rejected=true schema_diagnostics=true event_chain=true duplicate_event_rewrite_rejected=true'
