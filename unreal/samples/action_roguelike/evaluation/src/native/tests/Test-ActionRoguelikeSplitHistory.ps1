[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/ActionRoguelikeStateAdapter.ps1')
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-ActionRoguelikeStateLocator.ps1'),[ref]$null,[ref]$null)
$factory=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'New-Pair'},$true)
. ([scriptblock]::Create($factory.Extent.Text))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ar-split-history-'+[guid]::NewGuid().ToString('N'))
$events=Join-Path $temp 'state/channel with spaces/opaque events.json';$snapshot=Join-Path $temp 'state/channel with spaces/opaque snapshot.json'
$ss=Join-Path $PSScriptRoot '../../input/contracts/actionroguelike-probe-snapshot.schema.json'
$es=Join-Path $PSScriptRoot '../../input/contracts/actionroguelike-probe-events.schema.json'
function Context {New-ActionRoguelikeStateReaderContext $ss $es 'launcher-token' 4242}
function Write-Frame([long]$Sequence,[string]$Round='round-1'){
    $pair=New-Pair -Sequence $Sequence -Round $Round
    $pair.events.coverage.stream_epoch='epoch-'+$Round
    if($Sequence-gt0-and$Round-ceq'round-1'){$pair.events.coverage.previous_batch_id='batch-'+($Sequence-1)}
    $cursor=if($Round-ceq'round-1'){$Sequence}else{0}
    $event=@{event_id="$Round-event-$cursor";sequence=$cursor;monotonic_ms=$pair.snapshot.identity.monotonic_ms;category='combat';event_type='action_started';subject=@{entity_id='player';role='player'};object=$null;payload=@{action='idle'};observation=$pair.snapshot.identity.observation}
    $pair.snapshot.recent_event_ids=@($event.event_id)
    $pair.events.coverage.cursor_start=$cursor;$pair.events.coverage.head_watermark=$cursor
    $pair.events.coverage.cursor_end=$cursor+1;$pair.events.coverage.tail_watermark=$cursor+1
    $pair.snapshot.Remove('evidence')
    $path=Join-Path (Split-Path $snapshot) "records/snapshot-$Sequence.json"
    [void][IO.Directory]::CreateDirectory((Split-Path $path))
    [IO.File]::WriteAllText(($path+'.tmp'),(@{snapshot=$pair.snapshot;events=@($event)}|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move(($path+'.tmp'),$path,$true)
    $pair.events.evidence=@(@{path="records/snapshot-$Sequence.json";sha256=(Get-FileHash $path).Hash.ToLowerInvariant();media_type='application/json';byte_length=(Get-Item $path).Length;captured_monotonic_ms=$pair.snapshot.identity.monotonic_ms})
    $event.evidence=$pair.events.evidence;$pair.events.events=@($event)
    $batch=Join-Path (Split-Path $events) "batches/batch-$Sequence.json"
    [void][IO.Directory]::CreateDirectory((Split-Path $batch))
    [IO.File]::WriteAllText(($batch+'.tmp'),($pair.events|ConvertTo-Json -Depth 100))
    [IO.File]::Move(($batch+'.tmp'),$batch,$true)
    return $batch
}
function Read-Pair($Context){Resolve-ActionRoguelikeStatePair -RunRoot $temp -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242 -PreferredSnapshotPath $snapshot -PreferredEventsPath $events -ReaderContext $Context -TimeoutMilliseconds 1000}
try{
    0..12|ForEach-Object{$null=Write-Frame $_}
    $ctx=Context;$read=Read-Pair $ctx
    Assert $read.success "Split history failed: $($read.diagnostic.last_reason_code)"
    Assert ($ctx.history_pairs.Count-eq13-and$read.snapshot.identity.sequence-eq12) 'Numeric ordering or skipped-poll coverage failed.'
    Assert ($read.path_source-ceq'launcher_owned_split_event_history'-and$read.diagnostic.event_coverage_verified) 'Split history must prove linked coverage.'
    Assert ($ctx.history_pairs[0].fact_sha256-eq(Get-FileHash (Join-Path (Split-Path $snapshot) 'records/snapshot-0.json')).Hash.ToLowerInvariant()) 'Raw facts were not bound.'
    $null=Write-Frame 13 'round-2';$read=Read-Pair $ctx
    Assert ($read.success-and$read.snapshot.identity.round_id-ceq'round-2') 'Restart failed.'
    $fact=Join-Path (Split-Path $snapshot) 'records/snapshot-1.json'
    [IO.File]::AppendAllText($fact,' ')
    Assert ((Read-Pair $ctx).diagnostic.last_reason_code-ceq'state_history_rewritten') 'Committed raw facts can be rewritten.'
    Assert ((Read-Pair (Context)).diagnostic.last_reason_code-ceq'state_history_fact_hash_mismatch') 'Corrupt hash accepted.'
    $batch=Write-Frame 1
    $bad=Get-Content $batch -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $bad.evidence[0].path='../foreign.json'
    [IO.File]::WriteAllText($batch,($bad|ConvertTo-Json -Depth 100))
    Assert ((Read-Pair (Context)).diagnostic.last_reason_code-ceq'state_history_fact_reference_invalid') 'Escaping evidence accepted.'
    $batch=Write-Frame 1
    $bad=Get-Content $batch -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $bad.events[0].payload.action='forged'
    [IO.File]::WriteAllText($batch,($bad|ConvertTo-Json -Depth 100))
    Assert ((Read-Pair (Context)).diagnostic.last_reason_code-ceq'state_history_fact_events_mismatch') 'Events disagreeing with hashed facts accepted.'
    $batch=Write-Frame 1
    [IO.File]::Move($batch,$batch+'.tmp')
    Assert ((Read-Pair (Context)).diagnostic.last_reason_code-ceq'state_history_sequence_gap') 'Missing intermediate batch accepted.'
    $snapshot=Join-Path $temp 'concurrent/snapshot.json';$events=Join-Path $temp 'concurrent/events.json'
    $job=Start-Job -ArgumentList $snapshot,$events,$factory.Extent.Text,(Get-Command Write-Frame).Definition -ScriptBlock {
        param($snapshot,$events,$factoryText,$writeBody)
        . ([scriptblock]::Create($factoryText))
        . ([scriptblock]::Create("function Write-Frame {`n$writeBody`n}"))
        0..40|ForEach-Object{$null=Write-Frame $_;Start-Sleep -Milliseconds 10}
    }
    $ctx=Context;$watch=[Diagnostics.Stopwatch]::StartNew()
    do{
        $read=Read-Pair $ctx
        Assert (-not$ctx.ContainsKey('history_fault')) 'Concurrent atomic publication was permanently rejected.'
        if($job.State-ceq'Failed'){throw 'Concurrent publisher failed'}
        if($read.success-and$read.snapshot.identity.sequence-eq40){break}
    }while($watch.Elapsed.TotalSeconds-lt15)
    $null=Receive-Job $job -Wait -AutoRemoveJob
    Assert ($read.success-and$ctx.history_pairs.Count-eq41) 'Concurrent publication lost an intermediate frame.'
    Write-Output 'ACTIONROGUELIKE_SPLIT_HISTORY_OK concurrent_publication=true numeric_order=true skipped_polls=true restart=true hash_rewrite_escape_gap_rejected=true'
}finally{
    $absolute=[IO.Path]::GetFullPath($temp)
    if([IO.Path]::GetDirectoryName($absolute)-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())-or[IO.Path]::GetFileName($absolute)-notlike'ar-split-history-*'){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
