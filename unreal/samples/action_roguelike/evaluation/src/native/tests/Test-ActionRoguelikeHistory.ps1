[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/ActionRoguelikeStateAdapter.ps1')
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
# Reuse the schema-valid minimal documents from the transport regressions.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-ActionRoguelikeStateLocator.ps1'),[ref]$null,[ref]$null)
$factory=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'New-Pair'},$true)
. ([scriptblock]::Create($factory.Extent.Text))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ar-history-'+[guid]::NewGuid().ToString('N'))
$events=Join-Path $temp 'state/events.json';$snapshot=Join-Path $temp 'state/snapshot.json'
$ss=Join-Path $PSScriptRoot '../../input/contracts/actionroguelike-probe-snapshot.schema.json'
$es=Join-Path $PSScriptRoot '../../input/contracts/actionroguelike-probe-events.schema.json'
function Context {New-ActionRoguelikeStateReaderContext $ss $es 'launcher-token' 4242}
function Write-Frame([long]$Sequence,[string]$Round='round-1'){
    $pair=New-Pair -Sequence $Sequence -Round $Round
    $pair.events.coverage.stream_epoch='epoch-'+$Round
    if($Sequence-gt0-and$Round-ceq'round-1'){$pair.events.coverage.previous_batch_id='batch-'+($Sequence-1)}
    $path=Join-Path ($events+'.history/launcher-token/'+$Round) ($Sequence.ToString('D20')+'.json')
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path,($pair|ConvertTo-Json -Depth 100))
    return $path
}
function Read-Pair($Context){Resolve-ActionRoguelikeStatePair -RunRoot $temp -SnapshotSchemaPath $ss -EventsSchemaPath $es -ExpectedProcessToken 'launcher-token' -ExpectedProcessId 4242 -PreferredSnapshotPath $snapshot -PreferredEventsPath $events -ReaderContext $Context -TimeoutMilliseconds 1000}
try{
    $p0=Write-Frame 0;$p1=Write-Frame 1;$p2=Write-Frame 2
    $ctx=Context;$read=Read-Pair $ctx
    Assert $read.success "History read failed: $($read.diagnostic.last_reason_code)"
    Assert ($ctx.history_pairs.Count-eq3-and$read.snapshot.identity.sequence-eq2) 'Slow polling lost a pair.'
    Assert $read.diagnostic.event_coverage_verified 'Linked empty batches must prove coverage.'
    Assert ((Read-Pair $ctx).success-and$ctx.history_pairs.Count-eq3) 'Cached history duplicated pairs.'
    $p3=Write-Frame 3 'round-2';$read=Read-Pair $ctx
    Assert ($read.success-and$read.snapshot.identity.round_id-ceq'round-2') 'Restart failed to reset round-local cursor.'
    $window=Expand-ActionRoguelikeHistoryWindow @($ctx.history_pairs[0],$ctx.history_pairs[2]) $ctx
    Assert ($window.Count-eq3) 'The scoring window omitted an intermediate pair.'
    $uiContext=@{history_pairs=@(
        @{snapshot=@{identity=@{round_id='old';sequence=0}};events=@{events=@(@{event_type='ui_value_changed';observation=@{trust='verified'};payload=@{ui_role='old-round';visible=$true}})}},
        @{snapshot=@{identity=@{round_id='current';sequence=1}};events=@{events=@(@{event_type='ui_value_changed';observation=@{trust='verified'};payload=@{ui_role='health';visible=$true}},@{event_type='ui_value_changed';observation=@{trust='unavailable'};payload=@{ui_role='untrusted';visible=$true}})}},
        @{snapshot=@{identity=@{round_id='current';sequence=2}};events=@{events=@(@{event_type='ui_visibility_changed';observation=@{trust='verified'};payload=@{ui_role='health';visible=$false}})}}
    )}
    $uiSnapshot=@{identity=@{round_id='current';sequence=1};ui=@()}
    Assert ((@(Get-ActionRoguelikeUiRoles $uiSnapshot $uiContext)-join',')-ceq'health') 'UI history crossed a round, accepted untrusted data, or read future visibility.'
    $uiSnapshot.identity.sequence=2
    Assert (@(Get-ActionRoguelikeUiRoles $uiSnapshot $uiContext).Count-eq0) 'A hidden UI role remained visible.'
    $changed=Get-Content $p1 -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $changed.events.coverage.previous_batch_id='forged'
    [IO.File]::WriteAllText($p1,($changed|ConvertTo-Json -Depth 100))
    Assert ((Read-Pair $ctx).diagnostic.last_reason_code-ceq'state_history_rewritten') 'A committed pair was rewritten.'
    Assert ((Read-Pair (Context)).diagnostic.last_reason_code-ceq'state_history_event_link') 'Broken batch link accepted.'
    $null=Write-Frame 1
    [IO.File]::Move($p1,$p1+'.tmp')
    Assert ((Read-Pair (Context)).diagnostic.last_reason_code-ceq'state_history_sequence_gap') 'Missing frame accepted.'
    [IO.File]::Move($p1+'.tmp',$p1)
    $bad=Get-Content $p2 -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $bad.snapshot.identity.process_token='foreign'
    [IO.File]::WriteAllText($p2,($bad|ConvertTo-Json -Depth 100))
    Assert (-not(Read-Pair (Context)).success) 'Foreign identity accepted.'
    Write-Output 'ACTIONROGUELIKE_HISTORY_OK skipped_polls=true linked_empty=true restart=true rewrite_gap_foreign_rejected=true'
}finally{
    $absolute=[IO.Path]::GetFullPath($temp)
    if([IO.Path]::GetDirectoryName($absolute)-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())-or[IO.Path]::GetFileName($absolute)-notlike'ar-history-*'){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
