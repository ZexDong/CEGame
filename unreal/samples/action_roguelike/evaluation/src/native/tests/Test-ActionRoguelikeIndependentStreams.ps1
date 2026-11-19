[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/ActionRoguelikeStateAdapter.ps1')
. (Join-Path $PSScriptRoot '../scripts/ActionRoguelikeAtomicChecks.ps1')
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
# Reuse the schema-valid generic factory; do not execute the locator tests.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-ActionRoguelikeStateLocator.ps1'),[ref]$null,[ref]$null)
$factory=$ast.Find({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'New-Pair'},$true)
. ([scriptblock]::Create($factory.Extent.Text))
$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root=Join-Path $temporary ('ar-streams-'+[guid]::NewGuid().ToString('N'))
$transport=Join-Path $root 'state';[void][IO.Directory]::CreateDirectory($transport)
$sp=Join-Path $transport 'snapshot.json';$ep=Join-Path $transport 'events.json'
$ss=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../input/contracts/actionroguelike-probe-snapshot.schema.json'))
$es=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../input/contracts/actionroguelike-probe-events.schema.json'))
function Publish($Path,$Document){[IO.File]::WriteAllText($Path+'.tmp',($Document|ConvertTo-Json -Depth 100));[IO.File]::Move($Path+'.tmp',$Path,$true);Start-Sleep -Milliseconds 45}
function Read-Pair($Context){Resolve-ActionRoguelikeStatePair -RunRoot $root -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 42 -PreferredSnapshotPath $sp -PreferredEventsPath $ep -ReaderContext $Context -TimeoutMilliseconds 1500}
try{
    Start-ActionRoguelikeTransportRecorder $sp $ep
    $first=New-Pair -Sequence 0
    Publish $sp $first.snapshot
    $first.events.identity.monotonic_ms=10050
    $first.events.identity.observation.freshness.observed_monotonic_ms=10050
    Publish $ep $first.events
    $second=New-Pair -Sequence 1
    $second.snapshot.identity.observation.freshness.observed_monotonic_ms++
    Publish $sp $second.snapshot
    $context=New-ActionRoguelikeStateReaderContext -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 42
    $read=Read-Pair $context
    Assert $read.success "Independent publication rejected: $($read.diagnostic.last_reason_code)"
    Assert ($read.snapshot.identity.snapshot_id-ceq'snapshot-1'-and$read.events.identity.snapshot_id-ceq'snapshot-0') 'The adapter rewrote publisher identities.'
    Assert (Test-ARPairCorrelation $read) 'Captured independent correlation was lost.'
    $wrong=$read|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $wrong.events.identity.process_token='foreign'
    Assert (-not(Test-ARPairCorrelation $wrong)) 'Foreign process accepted.'
    Assert ($context.stream_records-eq3) 'The recorder failed to retain independent raw files.'
    $partial=$second.snapshot|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100
    $id=$partial.identity.observation.Clone();$id.value=''
    $role=$partial.identity.observation.Clone();$role.value='enemy_projectile'
    $partial.processes=@(@{entity_id=$id;process_type=$role})
    $node=[Text.Json.Nodes.JsonNode]::Parse(($partial|ConvertTo-Json -Depth 100))
    $health=Test-ActionRoguelikeSnapshotUsability $node $context.schemas.snapshot.compiled
    Assert ($health.usable-and-not$health.complete) 'An unrelated malformed projectile suppressed healthy controls.'
    Assert (Test-ARSnapshotForVariant $partial 'resources.pickup' $context.schemas.snapshot.text) 'Resource validation depends on enemy projectile identity.'
    Assert (-not(Test-ARSnapshotForVariant $partial 'journey.failure_restart' $context.schemas.snapshot.text)) 'A malformed required process was hidden from restart validation.'
    $partial.player.health=@{value='invalid'}
    Assert (-not(Test-ARSnapshotForVariant $partial 'resources.pickup' $context.schemas.snapshot.text)) 'A malformed required health field was accepted.'
    $raw=$script:ARTransportRecorder.ReadRecords()[0]
    Assert ((Get-FileHash $raw.Path).Hash.ToLowerInvariant()-ceq$raw.Sha256) 'Captured bytes are not hash-bound.'
    $captureFault=$false
    try {
        [IO.File]::SetLastWriteTimeUtc($raw.Path,$raw.PublishedUtc.AddSeconds(1))
        $null=Read-Pair $context
    } catch {$captureFault=$_.Exception.Message-like'run_invalid|STATE_CAPTURE_INTEGRITY|*'}
    finally {[IO.File]::SetLastWriteTimeUtc($raw.Path,$raw.PublishedUtc)}
    Assert $captureFault 'Host capture integrity failure was attributed to the candidate.'
    # An internally valid next batch with a broken link must fail closed.
    $third=New-Pair -Sequence 2
    $third.events.coverage.previous_batch_id='missing-batch'
    Publish $sp $third.snapshot;Publish $ep $third.events
    $broken=Read-Pair $context
    Assert (-not$broken.success-and$broken.diagnostic.last_reason_code-ceq'state_event_chain_previous_batch_mismatch') 'A missing batch was silently accepted.'
    $fourth=New-Pair -Sequence 3
    $fourth.snapshot.identity.observation.freshness.observed_monotonic_ms+=$fourth.snapshot.identity.observation.freshness.valid_for_ms+1
    Publish $sp $fourth.snapshot
    $outsideWindow=Read-Pair $context
    Assert (-not$outsideWindow.success-and$outsideWindow.diagnostic.last_reason_code-ceq'state_observation_stale') 'Clock skew outside the declared freshness window was accepted.'
    Stop-ActionRoguelikeTransportRecorder
    $receipt=Get-Content -Raw ($ep+'.captured/receipt.json')|ConvertFrom-Json
    Assert ($null-eq$receipt.fault-and$receipt.records.Count-eq6) 'Recorder cleanup or receipt failed.'
    # Restart can reset a publisher's sequence in a new round. It requires
    # explicit reset permission, a new epoch and a non-regressing process clock.
    $restartRoot=Join-Path $root 'restart';[void][IO.Directory]::CreateDirectory($restartRoot)
    $sp=Join-Path $restartRoot 'snapshot.json';$ep=Join-Path $restartRoot 'events.json'
    Start-ActionRoguelikeTransportRecorder $sp $ep
    $restartContext=New-ActionRoguelikeStateReaderContext -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 42
    $before=New-Pair -Sequence 10
    Publish $sp $before.snapshot;Publish $ep $before.events
    Assert ((Read-Pair $restartContext).success) 'Restart control failed.'
    $after=New-Pair -Sequence 0 -Round 'round-2'
    $after.snapshot.identity.monotonic_ms=13000;$after.events.identity.monotonic_ms=13000
    $after.snapshot.identity.observation.freshness.observed_monotonic_ms=13000
    $after.events.coverage.stream_epoch='epoch-2'
    Publish $sp $after.snapshot;Publish $ep $after.events
    $noReset=Read-Pair $restartContext
    Assert (-not$noReset.success-and$noReset.diagnostic.last_reason_code-ceq'state_sequence_regressed') 'Sequence reset accepted without permission.'
    $resetRead=Resolve-ActionRoguelikeStatePair -RunRoot $root -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 42 -PreferredSnapshotPath $sp -PreferredEventsPath $ep -ReaderContext $restartContext -TimeoutMilliseconds 1500 -AllowRoundSequenceResetCompatibility -RequireNewSample
    Assert ($resetRead.success-and$resetRead.diagnostic.new_sample-and$resetRead.snapshot.identity.sequence-eq0) 'A genuine Restart sequence reset was rejected.'
    $sameEpoch=New-Pair -Sequence 0 -Round 'round-3'
    $sameEpoch.snapshot.identity.monotonic_ms=13500;$sameEpoch.events.identity.monotonic_ms=13500
    $sameEpoch.snapshot.identity.observation.freshness.observed_monotonic_ms=13500
    $sameEpoch.events.coverage.stream_epoch='epoch-2'
    Publish $sp $sameEpoch.snapshot;Publish $ep $sameEpoch.events
    $epochRead=Resolve-ActionRoguelikeStatePair -RunRoot $root -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 42 -PreferredSnapshotPath $sp -PreferredEventsPath $ep -ReaderContext $restartContext -TimeoutMilliseconds 1500 -AllowRoundSequenceResetCompatibility
    Assert (-not$epochRead.success-and$epochRead.diagnostic.last_reason_code-ceq'state_event_epoch_not_reset') 'A changed round reused its event epoch.'
    $replayed=New-Pair -Sequence 11
    $replayed.snapshot.identity.monotonic_ms=14000;$replayed.events.identity.monotonic_ms=14000
    $replayed.snapshot.identity.observation.freshness.observed_monotonic_ms=14000
    Publish $sp $replayed.snapshot;Publish $ep $replayed.events
    $replayRead=Resolve-ActionRoguelikeStatePair -RunRoot $root -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 42 -PreferredSnapshotPath $sp -PreferredEventsPath $ep -ReaderContext $restartContext -TimeoutMilliseconds 1500 -AllowRoundSequenceResetCompatibility
    Assert (-not$replayRead.success-and$replayRead.diagnostic.last_reason_code-ceq'state_round_replayed') 'A previous round was accepted again.'
    Stop-ActionRoguelikeTransportRecorder
    # Exercise the real Windows delete/rename publication race. A path lookup
    # can return a 1601 missing-file time while a later Open reads the new file.
    Add-Type -TypeDefinition @'
using System.IO;
using System.Threading;
using System.Threading.Tasks;
public static class ARReplacementPublisherTest {
    public static Task Start(string path) {
        return Task.Run(() => {
            for (int i = 0; i < 400; i++) {
                File.WriteAllText(path + ".tmp", "{\"sequence\":" + i + "}");
                File.Delete(path);
                Thread.Sleep(1);
                File.Move(path + ".tmp", path);
                Thread.Sleep(2);
            }
        });
    }
}
'@
    $stress=Join-Path $root 'replacement';[void][IO.Directory]::CreateDirectory($stress)
    $stressSnapshot=Join-Path $stress 'snapshot.json';$stressEvents=Join-Path $stress 'events.json'
    $began=[DateTime]::UtcNow
    Start-ActionRoguelikeTransportRecorder $stressSnapshot $stressEvents
    $publisher=[ARReplacementPublisherTest]::Start($stressSnapshot)
    $publisher.GetAwaiter().GetResult()
    $captured=$script:ARTransportRecorder.ReadRecords()
    Assert ($captured.Count-gt10) 'Replacement stress did not exercise capture.'
    foreach($record in $captured){
        Assert ($record.PublishedUtc-ge$began) 'Replacement recorded a missing-file timestamp.'
        Assert ([IO.File]::GetLastWriteTimeUtc($record.Path)-eq$record.PublishedUtc) 'Bytes and publication time came from different file versions.'
    }
    Stop-ActionRoguelikeTransportRecorder
    Write-Output 'ACTIONROGUELIKE_INDEPENDENT_STREAMS_OK raw_bytes=true async_identity=true missing_batch_rejected=true replacement_handle_time=true restart_sequence_reset=true old_round_and_epoch_reuse_rejected=true'
}finally{
    Stop-ActionRoguelikeTransportRecorder
    $resolved=[IO.Path]::GetFullPath($root)
    if([IO.Path]::GetDirectoryName($resolved)-ne$temporary.TrimEnd('\')-or[IO.Path]::GetFileName($resolved)-notlike'ar-streams-*'){throw 'Unsafe cleanup path.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
