[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/ActionRoguelikeAtomicChecks.ps1')
. (Join-Path $root 'scripts/ActionRoguelikeFixtureRuntime.ps1')
$script:checks=0
function Assert($Condition,[string]$Message){if(-not$Condition){throw $Message};$script:checks++}
function O($value){@{value=$value;trust='verified'}}
$contract=Get-Content -Raw (Join-Path $root 'contracts/atomic-check-contract.json')|ConvertFrom-Json -AsHashtable
$names=@((Get-ActionRoguelikeAtomicVariantMap).Values|ForEach-Object{$_}|Select-Object -Unique)
foreach($name in $names){
    $spec=$contract.variants[$name]
    Assert ($spec.collector-ceq'Invoke-ARAtomicVariant'-and$spec.trace_path-ceq"variants/$name/receipts/trace.json") "Missing real collector path: $name"
    Assert ($spec.default_invulnerable-eq(-not$name.StartsWith('journey.failure'))) "Wrong protection policy: $name"
}
Assert ($contract.variants['journey.victory'].max_serial_seconds-le12-and$contract.variants['journey.victory'].max_actions-eq0) 'Victory still requires the full sixty-second journey.'
Assert ($contract.variants['resources.pickup_recovery'].max_actions-eq4) 'Recovery must permit the final exit that prevents an automatic second collection.'
$trace=@{setup=@{fixture_receipt_path='receipts/setup.json';input_ready_receipt_path='receipts/input-ready.json'};samples=@(@{snapshot=@{evidence=@{path='captures/candidate-owned.png'}}});cleanup=@{evidence_paths=@('receipts/stop.json')};execution=@{status='completed';evidence_paths=@('receipts/trace.json')};capture_paths=@('captures/result.png');input_receipts=@(@{evidence_path='receipts/input.json'})}
$trace.setup.native_aim=@{confirmed=$true;receipt_path='receipts/setup.json';direction=@{x=1;y=0;z=-.2}}
$trace.samples[0].history_path='state/batches/batch-0.json';$trace.samples[0].fact_path='state/records/snapshot-0.json'
Convert-ARTraceEvidencePaths $trace 'variants/resources.pickup'
Assert ($trace.input_receipts[0].evidence_path-ceq'variants/resources.pickup/receipts/input.json') 'Run-relative input evidence path was not rebased.'
Assert ($trace.setup.input_ready_receipt_path-ceq'variants/resources.pickup/receipts/input-ready.json') 'Input precondition receipt was not rebased.'
Assert ($trace.setup.native_aim.receipt_path-ceq'variants/resources.pickup/receipts/setup.json') 'Native aim receipt was not rebased.'
Assert ($trace.samples[0].snapshot.evidence.path-ceq'captures/candidate-owned.png') 'Evidence rebasing rewrote a candidate observation.'
Assert ($trace.samples[0].history_path-ceq'variants/resources.pickup/state/batches/batch-0.json'-and$trace.samples[0].fact_path-ceq'variants/resources.pickup/state/records/snapshot-0.json') 'Split archive evidence paths were not both rebased.'
$state=@{objects=@(@{object_type=(O 'potion');available=(O $true);entity_id=(O 'opaque-id');position_m=(O @{x=813;y=-94;z=3})})}
$target=Get-ARFixtureTarget $state 'potion'
Assert ($target.id-ceq'opaque-id'-and$target.position.x-eq813) 'Target selection substituted a fixed map location.'
foreach($position in @($null,@{trust='unavailable';value=$null},(O @{x=813;y=-94}))){
    $state.objects[0].position_m=$position;$failed=$false
    try{$null=Get-ARFixtureTarget $state 'potion'}catch{$failed=$_.Exception.Message-match'^(fail|unreachable)\|CANDIDATE_(OBSERVATION|ITEM_POSITION)_UNAVAILABLE\|'}
    Assert $failed 'Missing candidate item position did not become a local candidate failure.'
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ar-fixture-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
    $script:FixtureChannel=$temp;$script:ProcessId=17;$script:Session=@{};$script:FixtureAdapterIdentity='test-adapter'
    $script:FocusFaultsRemaining=0
    function Move-UnrealPointer($Session,$NormalizedX,$NormalizedY){
        if($script:FocusFaultsRemaining-gt0){
            $script:FocusFaultsRemaining--
            return @{status='executor_fault';input_dispatched=$false;fault=@{code='pointer_move_bound_dispatch_failed';details=@{validation_code='POINTER_TARGET_OCCLUDED';dispatch_occurred_before_fault=$false}}}
        }
        return @{status='ok';input_dispatched=$true}
    }
    function Write-JsonFile($Value,$Path){$Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path}
    function Save-Receipt($Value,$Name){Write-JsonFile $Value (Join-Path $temp "$Name.json");return "$Name.json"}
    function Read-Json($Path){
        $r=Get-Content -Raw (Join-Path $temp 'request.json')|ConvertFrom-Json
        return @{request_id=$r.request_id;process_id=17;applied=$true;health=50;invulnerable=$true;viewport_capture=$script:CaptureConfirmed;adapter_version='ar-private-fixture-2.0.0';engine_capabilities_version='ue-fixture-capabilities-1.0.0';candidate_adapter_id=$script:ReplyAdapter;readback_verified=$script:ReadbackVerified;verified_fields=@{health=$true}}
    }
    $script:ReplyAdapter='test-adapter';$script:ReadbackVerified=$true
    $script:CaptureConfirmed=$true
    $null=Invoke-ARFixture @{capture_pointer=$true} 'capture'
    $script:FocusFaultsRemaining=1
    $null=Invoke-ARFixture @{capture_pointer=$true} 'capture-transient'
    Assert (Test-Path -LiteralPath (Join-Path $temp 'fixture-capture-transient-foreground-retry-1.json')) 'Safe foreground retry lost its failed-attempt evidence.'
    $script:FocusFaultsRemaining=4
    $failed=$false;try{$null=Invoke-ARFixture @{capture_pointer=$true} 'capture-occluded'}catch{$failed=$_.Exception.Message-like'*FIXTURE_FOREGROUND_FAILED*'}
    Assert $failed 'Persistent occlusion escaped the bounded evaluator-fault gate.'
    $script:FocusFaultsRemaining=0
    $script:CaptureConfirmed=$false
    $failed=$false;try{$null=Invoke-ARFixture @{capture_pointer=$true} 'capture-failed'}catch{$failed=$_.Exception.Message-like'*FIXTURE_VIEWPORT_CAPTURE_FAILED*'}
    Assert $failed 'Unconfirmed viewport capture was scored as candidate input failure.'
    $reply=Invoke-ARFixture @{health=50;invulnerable=$true} 'health'
    Assert ($reply.response.health-eq50-and$reply.response.invulnerable) 'Positive health injection with continuing protection failed.'
    foreach($writes in @(@{health=0},@{terminal_result='victory'},@{verdict='pass'},@{call_heal=$true})){
        $failed=$false;try{$null=Invoke-ARFixture $writes}catch{$failed=$_.Exception.Message-match'^run_invalid\|FIXTURE_(RESULT_WRITE|WRITE)_FORBIDDEN\|'}
        Assert $failed 'A result mutation escaped the precondition allowlist.'
    }
    $failed=$false;try{$null=Invoke-ARFixture @{health=49}}catch{$failed=$_.Exception.Message-like'*FIXTURE_READBACK_MISMATCH*'}
    Assert $failed 'Native readback mismatch was treated as candidate behavior.'
    $script:ReplyAdapter='foreign-adapter'
    $failed=$false;try{$null=Invoke-ARFixture @{health=50}}catch{$failed=$_.Exception.Message-like'*FIXTURE_ADAPTER_IDENTITY_MISMATCH*'}
    Assert $failed 'A response from another adapter was accepted.'
    $script:ReplyAdapter='test-adapter';$script:ReadbackVerified=$false
    $failed=$false;try{$null=Invoke-ARFixture @{health=50}}catch{$failed=$_.Exception.Message-like'*FIXTURE_READBACK_MISMATCH*'}
    Assert $failed 'Unverified native write was accepted.'
    # Contact movement must observe the item and release the real key even if
    # state collection fails while it is held.
    $script:ARSampleHostTimes=@{s=100};$script:releaseCount=0;$script:contactReadFails=$false
    function Get-ControlActivation($Snapshot,$Action){$script:lastContactAction=$Action;return @{kind='keyboard';key='W'}}
    function Start-UnrealKeyHold($Session,$Key){return @{status='ok';input_dispatched=$true;observer_monotonic_ms=110}}
    function Stop-UnrealKeyHold($Session,$Key){$script:releaseCount++;return @{status='ok';observer_monotonic_ms=130;result=@{held=$false}}}
    $contactItem=@{entity_id=(O 'item');object_type=(O 'credits_pickup');available=(O $true);position_m=(O @{x=3;y=0;z=0})}
    $contactState=@{identity=@{snapshot_id='s';process_token='p';round_id='r';monotonic_ms=1000};objects=@($contactItem);player=@{position_m=(O @{x=0;y=0;z=0})}}
    function Add-ARLiveSample($Samples){
        if($script:contactReadFails){throw 'Synthetic collector fault during contact'}
        $pair=@{snapshot=@{player=@{position_m=(O @{x=0;y=0;z=0})};objects=@(@{entity_id=(O 'item');object_type=(O 'credits_pickup');available=(O $false);position_m=(O @{x=3;y=0;z=0})})}}
        $Samples.Add($pair);return $pair
    }
    $contactSamples=[Collections.Generic.List[object]]::new()
    $contact=Invoke-ARContactInput $contactState $contactSamples @{id='item';entity=$contactItem} 'observed-contact'
    Assert ($contact.release_verified-and$script:releaseCount-eq1-and$contactSamples.Count-eq1) 'Observed collection failed to release the held movement key.'
    $script:contactReadFails=$true;$failed=$false
    try{$null=Invoke-ARContactInput $contactState $contactSamples @{id='item';entity=$contactItem} 'failed-contact'}catch{$failed=$_.Exception.Message-ceq'Synthetic collector fault during contact'}
    Assert ($failed-and$script:releaseCount-eq2) 'A collector fault left the movement key held.'
    $script:contactReadFails=$false
    $away=Invoke-ARContactInput $contactState $contactSamples @{id='item';entity=$contactItem} 'exit-contact' -Away
    Assert ($away.semantic_action-ceq'move_backward'-and$away.release_verified-and$script:lastContactAction-ceq'move_backward'-and$script:releaseCount-eq3) 'Contact exit did not observe separation using the published backward input.'
}finally{
    $full=[IO.Path]::GetFullPath($temp)
    if([IO.Path]::GetDirectoryName($full)-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())-or[IO.Path]::GetFileName($full)-notlike'ar-fixture-test-*'){throw 'Unsafe test cleanup'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
Write-Output "ACTIONROGUELIKE_FIXTURE_RUNTIME_OK checks=$script:checks variants=$($names.Count) arbitrary_layout=true local_candidate_failure=true result_writes_rejected=true"
