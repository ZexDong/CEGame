[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/ActionRoguelikeStateAdapter.ps1')
$schemaSnapshot=Join-Path $root '../input/contracts/actionroguelike-probe-snapshot.schema.json'
$schemaEvents=Join-Path $root '../input/contracts/actionroguelike-probe-events.schema.json'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('actionroguelike locator '+[guid]::NewGuid().ToString('N'))
$transport=Join-Path $temp 'state/channel with spaces'
[void][IO.Directory]::CreateDirectory($transport)
$snapshot=Join-Path $transport ('frame '+[guid]::NewGuid().ToString('N')+'.json')
$events=Join-Path $transport ('batch '+[guid]::NewGuid().ToString('N')+'.json')

function New-Pair([string]$Token='launcher-token',[long]$Sequence=1,[string]$Round='round-1') {
    $clock=10000+$Sequence*250
    $provenance=@{kind='readonly_probe';source_ref='public/runtime';probe_id='fixture';probe_version='1.0.0'}
    $observation=@{trust='corroborated';provenance=$provenance;freshness=@{observed_monotonic_ms=$clock;valid_for_ms=2000}}
    $publisher=@{publisher_id='fixture';publisher_version='1.0.0';readonly=$true;accepts_commands=$false;source_ref='public/runtime'}
    $evidence=@(@{path='public/runtime';sha256=('0'*64);media_type='application/json';byte_length=0;captured_monotonic_ms=$clock})
    $identity=@{process_token=$Token;round_id=$Round;snapshot_id="snapshot-$Sequence";sequence=$Sequence;monotonic_ms=$clock;observation=$observation}
    $controls=@('move_forward','move_backward','move_left','move_right','jump','sprint','primary_attack','black_hole','teleport','interact','restart'|ForEach-Object{
        @{semantic_action=$_;discovery_source='public_input_mapping';activation=@{kind='keyboard';operation='Press';physical_control='W';mouse_button=$null;target_id=$null};observation=$observation}
    })
    $s=@{schema_version='1.0.0';publisher=$publisher;identity=$identity;world=@{};player=@{};enemies=@();processes=@();objects=@();ui=@();controls=$controls;recent_event_ids=@();evidence=$evidence}
    $ei=$identity.Clone();$ei.batch_id="batch-$Sequence"
    $e=@{schema_version='2.0.0';publisher=$publisher;identity=$ei;coverage=@{stream_epoch='epoch-1';previous_batch_id=$null;cursor_start=0;cursor_end=0;dropped_event_count=0;head_watermark=0;tail_watermark=0};events=@();evidence=$evidence}
    return @{snapshot=$s;events=$e}
}
function Write-Document([string]$Path,$Value) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
    [void][IO.File]::Move($temporary,$Path,$true)
}
function Write-Pair($Pair) { Write-Document $events $Pair.events;Write-Document $snapshot $Pair.snapshot }
function Context([string]$Token='launcher-token',[int]$ProcessId=4242,[DateTime]$Started=[DateTime]::MinValue) {
    New-ActionRoguelikeStateReaderContext -SnapshotSchemaPath $schemaSnapshot -EventsSchemaPath $schemaEvents -ExpectedProcessToken $Token -ExpectedProcessId $ProcessId -SessionStartedUtc $Started
}
function Read-Pair($Context,[int]$Timeout=500,[long]$Minimum=-1,[switch]$AllowEmptyEvents,[switch]$AllowRoundReset) {
    Resolve-ActionRoguelikeStatePair -RunRoot $temp -PreferredSnapshotPath $snapshot -PreferredEventsPath $events -SnapshotSchemaPath $schemaSnapshot -EventsSchemaPath $schemaEvents -ExpectedProcessToken $Context.expected_process_token -ExpectedProcessId $Context.expected_process_id -ReaderContext $Context -TimeoutMilliseconds $Timeout -PollMilliseconds 5 -MinimumSequence $Minimum -AllowEmptyEventBatchCompatibility:$AllowEmptyEvents -AllowRoundSequenceResetCompatibility:$AllowRoundReset
}
function Reject-Reason($Result,[string]$Reason) {
    Assert (-not $Result.success) "Unexpected accepted state: $Reason"
    Assert ($Result.diagnostic.last_reason_code -ceq $Reason) "Expected $Reason, got $($Result.diagnostic.last_reason_code)"
}
try {
    $pair=New-Pair
    Assert (($pair.snapshot|ConvertTo-Json -Depth 100|Test-Json -SchemaFile $schemaSnapshot)) 'Fixture snapshot must satisfy the actual public schema.'
    Assert (($pair.events|ConvertTo-Json -Depth 100|Test-Json -SchemaFile $schemaEvents)) 'Fixture events must satisfy the actual public schema.'
    Write-Pair $pair
    $published=[DateTime]::UtcNow.AddMilliseconds(-180)
    [IO.File]::SetLastWriteTimeUtc($snapshot,$published)
    [IO.File]::SetLastWriteTimeUtc($events,$published)
    $context=Context
    $good=Read-Pair $context
    Assert $good.success "Paths with spaces failed: $($good.diagnostic.last_reason_code)"
    Assert ($good.diagnostic.publication_age_ms-ge180) 'Latest-pair clock mapping used poll arrival instead of actual publication age.'
    Assert ($good.path_source -eq 'launcher_generated_transport' -and $good.snapshot_path -ceq $snapshot) 'The launcher transport binding changed.'
    $repeat=Read-Pair $context
    Assert ($repeat.success -and -not $repeat.diagnostic.new_sample -and $repeat.diagnostic.schema_cache_hit) 'A fresh duplicate is readable, cached, and never a new sample.'
    Reject-Reason (Read-Pair $context 50 1) 'state_sequence_not_advanced'
    Write-Pair (New-Pair -Sequence 2)
    Assert ((Read-Pair $context 500 1).success) 'An advancing fresh pair was rejected.'
    Write-Pair (New-Pair -Sequence 1)
    Reject-Reason (Read-Pair $context 500) 'state_sequence_regressed'
    $reused=New-Pair -Sequence 2;$reused.snapshot.publisher.publisher_version='1.0.1';Write-Pair $reused
    Reject-Reason (Read-Pair $context 500) 'state_sequence_reused'
    $oldEvents=New-Pair -Sequence 3;$oldEvents.events.identity.sequence=1;Write-Pair $oldEvents
    Reject-Reason (Read-Pair $context 500) 'state_event_sequence_regressed'
    $staleObservation=New-Pair -Sequence 3;$staleObservation.events.identity.observation.freshness.observed_monotonic_ms=0;Write-Pair $staleObservation
    Reject-Reason (Read-Pair $context 500) 'state_observation_stale'
    Write-Pair (New-Pair -Sequence 3)
    Assert ((Read-Pair $context).success) 'A valid next revision was rejected after invalid frames.'
    $context.last_progress_ticks=[Diagnostics.Stopwatch]::GetTimestamp()-3*[Diagnostics.Stopwatch]::Frequency
    Reject-Reason (Read-Pair $context 60) 'state_sequence_stalled'
    Write-Pair (New-Pair -Token 'process-4242')
    $pidPair=Read-Pair (Context)
    Assert ($pidPair.success -and $pidPair.validation.identity_binding -eq 'active_process_id') 'Active PID compatibility failed.'
    foreach($pidToken in @('proc-4242','pid4242')){
        Write-Pair (New-Pair -Token $pidToken)
        Assert ((Read-Pair (Context)).success) "Active PID spelling rejected: $pidToken"
        Reject-Reason (Read-Pair (Context -ProcessId 9999) 60) 'state_process_identity_mismatch'
    }
    Reject-Reason (Read-Pair (Context -ProcessId 9999) 60) 'state_process_identity_mismatch'
    Write-Pair (New-Pair)
    Reject-Reason (Read-Pair (Context -Token 'reopened-token' -ProcessId 9999) 60) 'state_process_identity_mismatch'
    [IO.File]::SetLastWriteTimeUtc($snapshot,[DateTime]::UtcNow.AddMinutes(-1))
    [IO.File]::SetLastWriteTimeUtc($events,[DateTime]::UtcNow.AddMinutes(-1))
    Reject-Reason (Read-Pair (Context) 60) 'state_file_stale'
    Write-Pair (New-Pair)
    [IO.File]::SetLastWriteTimeUtc($snapshot,[DateTime]::UtcNow.AddSeconds(-1))
    Reject-Reason (Read-Pair (Context -Started ([DateTime]::UtcNow)) 60) 'state_before_session'
    $torn=New-Pair -Sequence 3;$torn.events.identity.snapshot_id='snapshot-2';Write-Pair $torn
    Reject-Reason (Read-Pair (Context) 60) 'state_pair_identity_mismatch'
    $fixed=New-Pair -Sequence 3
    $writer=[PowerShell]::Create()
    $null=$writer.AddScript({param($Path,$Json) Start-Sleep -Milliseconds 100;[IO.File]::WriteAllText($Path+'.tmp',$Json,[Text.UTF8Encoding]::new($false));[IO.File]::Move($Path+'.tmp',$Path,$true)}).AddArgument($events).AddArgument(($fixed.events|ConvertTo-Json -Depth 100))
    $async=$writer.BeginInvoke()
    try {$recovered=Read-Pair (Context) 1000;Assert ($recovered.success -and $recovered.diagnostic.attempts -gt 1) 'The reader did not recover an atomic torn pair within one budget.'}
    finally {$null=$writer.EndInvoke($async);$writer.Dispose()}
    # The real legacy Gold emits fresh snapshots with a constant empty batch.
    # Strict event mode rejects it; compatibility mode preserves only snapshot
    # usability and must never upgrade empty batches into event-absence proof.
    $emptyContext=Context
    $empty=New-Pair -Sequence 10;$empty.events.identity.sequence=0;$empty.events.identity.batch_id='empty-batch';Write-Pair $empty
    Assert ((Read-Pair $emptyContext).success) 'Initial empty batch was rejected.'
    $empty=New-Pair -Sequence 11;$empty.events.identity.sequence=0;$empty.events.identity.batch_id='empty-batch';Write-Pair $empty
    Reject-Reason (Read-Pair $emptyContext 100) 'state_event_sequence_reused'
    $compatible=Read-Pair $emptyContext -AllowEmptyEvents
    Assert ($compatible.success -and $compatible.diagnostic.new_sample -and $compatible.diagnostic.empty_event_batch_compatibility -and -not $compatible.diagnostic.event_coverage_verified) 'Legacy empty batch compatibility lost fresh state or claimed event coverage.'
    $empty=New-Pair -Sequence 12;$empty.events.identity.sequence=0;$empty.events.identity.batch_id='empty-batch';$empty.events.coverage.cursor_end=1;$empty.events.coverage.tail_watermark=1;Write-Pair $empty
    Reject-Reason (Read-Pair $emptyContext 100 -AllowEmptyEvents) 'state_event_sequence_reused'
    $roundContext=Context;Write-Pair (New-Pair -Sequence 20);Assert ((Read-Pair $roundContext).success) 'Initial round setup failed.'
    $nextRound=New-Pair -Sequence 1 -Round 'round-2';$nextRound.snapshot.identity.monotonic_ms=20000;$nextRound.events.identity.monotonic_ms=20000;$nextRound.snapshot.identity.observation.freshness.observed_monotonic_ms=20000;$nextRound.events.coverage.stream_epoch='epoch-2';Write-Pair $nextRound
    Reject-Reason (Read-Pair $roundContext 100) 'state_sequence_regressed'
    $roundAccepted=Read-Pair $roundContext -Minimum 20 -AllowRoundReset
    Assert ($roundAccepted.success -and $roundAccepted.diagnostic.round_sequence_reset_compatibility) 'Explicit Restart compatibility did not accept a fresh unseen round and new event epoch.'
    $oldRound=New-Pair -Sequence 50 -Round 'round-1';Write-Pair $oldRound
    Reject-Reason (Read-Pair $roundContext 100 -AllowRoundReset) 'state_round_replayed'
    # Coherent copied evidence is deliberately not a transport fallback.
    Write-Document (Join-Path $temp 'receipts/copied-snapshot.json') $fixed.snapshot
    Write-Document (Join-Path $temp 'receipts/copied-events.json') $fixed.events
    Write-Document (Join-Path $temp 'history/snapshot.json') $fixed.snapshot
    Write-Document (Join-Path $temp 'history/events.json') $fixed.events
    [IO.File]::Delete($snapshot);[IO.File]::Delete($events)
    $context=Context;$watch=[Diagnostics.Stopwatch]::StartNew();$missing=Read-Pair $context 60
    Reject-Reason $missing 'state_publication_gap'
    Assert ($watch.Elapsed.TotalMilliseconds -lt 400 -and $missing.diagnostic.candidate_count -eq 1) 'A read multiplied its timeout or scanned undeclared paths.'
    $badDeclaration=$false
    try {Resolve-ActionRoguelikeStatePair -RunRoot $temp -PreferredSnapshotPath (Join-Path $temp 'receipts/copied-snapshot.json') -PreferredEventsPath (Join-Path $temp 'receipts/copied-events.json') -SnapshotSchemaPath $schemaSnapshot -EventsSchemaPath $schemaEvents -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242|Out-Null}
    catch {$badDeclaration=$_.Exception.Message -like 'EVALUATOR_STATE_TRANSPORT_EVIDENCE_PATH*'}
    Assert $badDeclaration 'Evidence paths were accepted as launcher transport.'
    $outside=$false
    try {Get-ActionRoguelikeStateCandidatePaths -RunRoot $temp -PreferredSnapshotPath (Join-Path ([IO.Path]::GetTempPath()) 'outside.json') -PreferredEventsPath $events|Out-Null}
    catch {$outside=$_.Exception.Message -like 'EVALUATOR_STATE_TRANSPORT_OUTSIDE_RUN*'}
    Assert $outside 'An outside transport was accepted.'
    $undeclared=$false
    try {Get-ActionRoguelikeStateCandidatePaths -RunRoot $temp|Out-Null}
    catch {$undeclared=$_.Exception.Message -like 'EVALUATOR_STATE_TRANSPORT_UNDECLARED*'}
    Assert $undeclared 'Missing launcher declarations enabled implicit discovery.'
    $schemaFault=$false
    try {New-ActionRoguelikeStateReaderContext -SnapshotSchemaPath (Join-Path $temp 'missing-schema.json') -EventsSchemaPath $schemaEvents -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242|Out-Null}
    catch {$schemaFault=$_.Exception.Message -like 'EVALUATOR_STATE_SCHEMA_UNAVAILABLE*'}
    Assert $schemaFault 'Missing evaluator schemas were blamed on the candidate.'
    # Directory junctions work without symbolic-link privileges on Windows.
    $destination=Join-Path $temp 'regular-files';[IO.Directory]::CreateDirectory($destination)|Out-Null
    Write-Document (Join-Path $destination 'snapshot.json') $fixed.snapshot
    Write-Document (Join-Path $destination 'events.json') $fixed.events
    $link=Join-Path $temp 'linked-transport'
    New-Item -ItemType Junction -Path $link -Target $destination|Out-Null
    $linked=Resolve-ActionRoguelikeStatePair -RunRoot $temp -PreferredSnapshotPath (Join-Path $link 'snapshot.json') -PreferredEventsPath (Join-Path $link 'events.json') -SnapshotSchemaPath $schemaSnapshot -EventsSchemaPath $schemaEvents -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242 -ReaderContext (Context) -TimeoutMilliseconds 60
    Reject-Reason $linked 'state_transport_reparse_point'
    Remove-Item -LiteralPath $link -Force
    Write-Output 'ACTIONROGUELIKE_STATE_LOCATOR_OK real_schemas=true declared_transport_only=true space_paths=true stale_reopen_rejected=true sequence_progress=true atomic_retry=true bounded_timeout=true reparse_rejected=true schema_fault_attribution=true'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    $allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'actionroguelike locator *') {throw 'Unsafe test cleanup target.'}
    if (Test-Path -LiteralPath $resolved) {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
