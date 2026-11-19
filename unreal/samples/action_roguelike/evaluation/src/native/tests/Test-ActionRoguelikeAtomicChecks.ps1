[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/ActionRoguelikeAtomicChecks.ps1')
$script:checks=0
function Assert([bool]$Condition,[string]$Detail){if(-not$Condition){throw $Detail};$script:checks++}
function Copy-Fixture($Value){return $Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -AsHashtable}
function Vec([double]$x,[double]$y=0,[double]$z=0){return @{x=$x;y=$y;z=$z}}
function Observation([long]$Time=0){return @{trust='corroborated';provenance=@{kind='readonly_probe';source_ref='runtime/read-only';probe_id='protected-test-publisher';probe_version='1.0.0'};freshness=@{observed_monotonic_ms=$Time;valid_for_ms=600000}}}
function O($Value){$o=Observation;$o.value=$Value;return $o}
function Entity([string]$Id,[string]$Role,[double]$x=0){$e=@{entity_id=(O $Id);position_m=(O(Vec $x))};if($Role-in@('credits_pickup','teleport_pickup','potion','physics_prop')){$e.object_type=O $Role;$e.available=O $true;$e.acquired=O $false}else{$e.process_type=O $Role;$e.phase=O 'active';$e.started_monotonic_ms=O 100};return $e}
function Event([string]$Type,[long]$Time,[string]$SubjectRole,[string]$SubjectId,[string]$ObjectRole,[string]$ObjectId,[hashtable]$Payload){return @{event_id='assigned-later';sequence=0;monotonic_ms=$Time;category='ability';event_type=$Type;subject=$(if($SubjectRole){@{role=$SubjectRole;entity_id=$SubjectId}}else{$null});object=$(if($ObjectRole){@{role=$ObjectRole;entity_id=$ObjectId}}else{$null});payload=$Payload;observation=(Observation $Time);evidence=@(@{path='evidence/frame.json';sha256=('a'*64);media_type='application/json';byte_length=1;captured_monotonic_ms=$Time})}}
function BaseState {return @{world=@{round_phase=(O 'in_progress');survival_time_seconds=(O 0);terminal_result_count=(O 0)};player=@{entity_id=(O 'player-opaque');alive=(O $true);health=(O 100);health_max=(O 100);credits=(O 0);teleport_acquired=(O $false);position_m=(O(Vec 0));facing=(O(Vec 1));ground_state=(O 'grounded')};enemies=@(@{entity_id=(O 'target-opaque');health=(O 100);alive=(O $true);position_m=(O(Vec 6))});objects=@();processes=@()}}
function Input([string]$Action,[long]$Time){return @{semantic_action=$Action;monotonic_ms=$Time}}
function DirectionSetup([string]$Round){return @{direction_change=@{confirmed=$true;before_facing=(O(Vec 0 1));after_facing=(O(Vec 1 0));input_receipt=@{semantic_action='move_right';monotonic_ms=0;input_dispatched=$true;release_verified=$true;attribution='evaluator';evidence_path='receipts/direction-change.json';process_token='owned-process';round_id=$Round}}}}
function New-Trace([string]$Key,[hashtable]$Base,[hashtable[]]$Frames,[object[]]$Events=@(),[object[]]$Inputs=@(),[hashtable]$Setup=@{}){
    $publisher=@{publisher_id='protected-test-publisher';publisher_version='1.0.0';readonly=$true;accepts_commands=$false;source_ref='runtime/read-only'}
    $orderedEvents=@($Events|Sort-Object monotonic_ms);for($i=0;$i-lt$orderedEvents.Count;$i++){$orderedEvents[$i].event_id="event-$i";$orderedEvents[$i].sequence=$i}
    $pairs=[Collections.Generic.List[object]]::new();$index=0
    foreach($frame in $Frames){
        $state=if($frame.ContainsKey('state')){Copy-Fixture $frame.state}else{Copy-Fixture $Base};if($frame.ContainsKey('change')){& $frame.change $state}
        $clock=[long]$frame.time;$identity=@{process_token='owned-process';round_id=$Key;snapshot_id="sample-$index";sequence=$index;monotonic_ms=$clock;observation=(Observation $clock)}
        $evidence=@(@{path='evidence/frame.json';sha256=('a'*64);media_type='application/json';byte_length=1;captured_monotonic_ms=$clock})
        $controls=@('move_forward','move_backward','move_left','move_right','jump','sprint','primary_attack','black_hole','teleport','interact','restart'|ForEach-Object{@{semantic_action=$_;discovery_source='public_input_mapping';activation=@{kind='keyboard';operation='Press';physical_control='W';mouse_button=$null;target_id=$null};observation=(Observation $clock)}})
        $snapshot=@{schema_version='1.0.0';publisher=$publisher;identity=$identity;world=$state.world;player=$state.player;enemies=$state.enemies;objects=$state.objects;processes=$state.processes;ui=@();controls=$controls;recent_event_ids=@();evidence=$evidence}
        $inWindow=@($orderedEvents|Where-Object{$_.monotonic_ms-le$clock});$batchIdentity=$identity.Clone();$batchIdentity.batch_id="batch-$index"
        $batch=@{schema_version='2.0.0';publisher=$publisher;identity=$batchIdentity;coverage=@{stream_epoch=$Key;previous_batch_id=$(if($index-gt0){'batch-'+($index-1)}else{$null});cursor_start=0;cursor_end=$inWindow.Count;head_watermark=0;tail_watermark=$inWindow.Count;dropped_event_count=0};events=$inWindow;evidence=$evidence}
        $pairs.Add(@{snapshot=$snapshot;events=$batch});$index++
    }
    $receiptInputs=@($Inputs|ForEach-Object{$_+@{input_dispatched=$true;release_verified=$true;attribution='evaluator';evidence_path='receipts/normal-input.json';process_token='owned-process';round_id=$Key}})
    return @{execution=@{status='completed';attribution='evaluator';evidence_paths=@('trace/'+$Key+'.json')};setup=(@{confirmed=$true;method='normal_input';before_identity=$pairs[0].snapshot.identity;after_identity=$pairs[0].snapshot.identity}+$Setup);input_receipts=$receiptInputs;samples=@($pairs);capture_paths=@('captures/'+$Key+'.png');cleanup=@{verified=$true;receipt_id='cleanup-'+$Key;attribution='evaluator';release_all_inputs=$true;fixture_cleared=$true;process_tree_stopped=$true;evidence_paths=@('receipts/cleanup-'+$Key+'.json');process_token='owned-process';round_id=$Key}}
}
function Result([string]$Id,$Traces,[string]$Expected='pass'){$r=Test-ActionRoguelikeAtomicCheckpoint -CheckpointId $Id -Traces $Traces;Assert ($r.verdict-ceq$Expected) "$Id expected $Expected got $($r.verdict): $($r.variants|ConvertTo-Json -Depth 10 -Compress)";return $r}
$traces=@{};$base=BaseState
$traces['primary.hit']=New-Trace 'hit-round' $base @(@{time=0},@{time=150;change={param($s)$s.processes=@(Entity 'bolt-a' 'player_projectile' 1)}},@{time=200;change={param($s)$s.processes=@(Entity 'bolt-a' 'player_projectile' 2)}},@{time=400;change={param($s)$s.enemies[0].health=O 80}}) @((Event 'projectile_spawned' 100 'player_projectile' 'bolt-a' 'player' 'player-opaque' @{process_type='player_projectile'}),(Event 'contact' 200 'player_projectile' 'bolt-a' 'enemy' 'target-opaque' @{reason='first_contact'}),(Event 'damage' 201 'player_projectile' 'bolt-a' 'enemy' 'target-opaque' @{resource='health';amount=20;value_before=100;value_after=80}),(Event 'entity_removed' 202 'player_projectile' 'bolt-a' '' '' @{reason='collision'})) @((Input 'primary_attack' 100))
foreach($mode in @('obstacle','miss')){
    $events=@((Event 'projectile_spawned' 100 'player_projectile' 'bolt-a' 'player' 'player-opaque' @{process_type='player_projectile'}));if($mode-ceq'obstacle'){$events+=@(Event 'contact' 200 'player_projectile' 'bolt-a' 'static_world' 'opaque-wall' @{reason='first_contact'})};$events+=@(Event 'entity_removed' 202 'player_projectile' 'bolt-a' '' '' @{reason=$(if($mode-ceq'miss'){'out_of_bounds'}else{'collision'})})
    $traces['primary.'+$mode]=New-Trace ($mode+'-round') $base @(@{time=0},@{time=150;change={param($s)$s.processes=@(Entity 'bolt-a' 'player_projectile' 1)}},@{time=400}) $events @((Input 'primary_attack' 100))
}
$traces['primary.latest_direction']=New-Trace 'aim-round' $base @(@{time=0},@{time=150;change={param($s)$s.processes=@(Entity 'bolt-a' 'player_projectile' 1)}},@{time=200;change={param($s)$s.processes=@(Entity 'bolt-a' 'player_projectile' 2)}}) @((Event 'projectile_spawned' 100 'player_projectile' 'bolt-a' 'player' 'player-opaque' @{process_type='player_projectile'})) @((Input 'primary_attack' 100)) (DirectionSetup 'aim-round')
$traces['primary.repeat_reuse']=New-Trace 'repeat-round' $base @(@{time=0},@{time=150;change={param($s)$s.processes=@(Entity 'bolt-a' 'player_projectile' 1)}},@{time=600},@{time=1300;change={param($s)$s.processes=@(Entity 'bolt-b' 'player_projectile' 1)}},@{time=1700}) @((Event 'action_started' 100 'player' 'player-opaque' '' '' @{action='primary_cast'}),(Event 'projectile_spawned' 100 'player_projectile' 'bolt-a' 'player' 'player-opaque' @{process_type='player_projectile'}),(Event 'action_ended' 500 'player' 'player-opaque' '' '' @{action='primary_cast'}),(Event 'action_started' 1200 'player' 'player-opaque' '' '' @{action='primary_cast'}),(Event 'projectile_spawned' 1200 'player_projectile' 'bolt-b' 'player' 'player-opaque' @{process_type='player_projectile'}),(Event 'action_ended' 1600 'player' 'player-opaque' '' '' @{action='primary_cast'})) @((Input 'primary_attack' 100),(Input 'primary_attack' 200),(Input 'primary_attack' 1200))
foreach($key in @('resources.pickup','resources.pickup_recovery')){
    $b=BaseState;$b.objects=@(Entity 'credit-opaque' 'credits_pickup')
    $traces[$key]=New-Trace ($key.Replace('.','-')) $b @(@{time=0},@{time=100;change={param($s)$s.player.credits=O 80;$s.objects[0].available=O $false}},@{time=500;change={param($s)$s.player.credits=O 80;$s.objects[0].available=O $false}},@{time=10100;change={param($s)$s.player.credits=O 80}}) @((Event 'pickup' 100 'credits_pickup' 'credit-opaque' 'player' 'player-opaque' @{resource='credits';amount=80}),(Event 'availability_changed' 100 'credits_pickup' 'credit-opaque' '' '' @{available=$false}),(Event 'availability_changed' 10100 'credits_pickup' 'credit-opaque' '' '' @{available=$true})) @((Input 'move_toward' 50),(Input 'move_toward' 500))
}
foreach($key in @('resources.heal_basic','resources.heal_exact50')){
    $b=BaseState;$b.player.health=O 50;$b.player.credits=O 50;$b.objects=@(Entity 'potion-opaque' 'potion')
    $traces[$key]=New-Trace ($key.Replace('.','-')) $b @(@{time=0},@{time=100;change={param($s)$s.player.credits=O 0;$s.player.health=O 100;$s.objects[0].available=O $false}},@{time=500;change={param($s)$s.player.credits=O 0;$s.player.health=O 100;$s.objects[0].available=O $false}},@{time=4100;change={param($s)$s.player.credits=O 0;$s.player.health=O 100}}) @((Event 'payment' 100 'potion' 'potion-opaque' 'player' 'player-opaque' @{resource='credits';amount=50}),(Event 'healing' 100 'potion' 'potion-opaque' 'player' 'player-opaque' @{resource='health';amount=50}),(Event 'availability_changed' 100 'potion' 'potion-opaque' '' '' @{available=$false}),(Event 'availability_changed' 4100 'potion' 'potion-opaque' '' '' @{available=$true})) @((Input 'interact' 100),(Input 'interact' 500))
}
$traces['resources.initial']=New-Trace 'resource-initial' (BaseState) @(@{time=0},@{time=100})
foreach($mode in @('full','poor')){$b=BaseState;$b.objects=@(Entity 'potion-opaque' 'potion');if($mode-ceq'poor'){$b.player.health=O 50;$b.player.credits=O 49};$traces['resources.reject_'+$mode]=New-Trace ('reject-'+$mode) $b @(@{time=0},@{time=100},@{time=300}) @() @((Input 'interact' 50),(Input 'interact' 200))}
foreach($key in @('teleport.pickup','teleport.pickup_repeat')){$b=BaseState;$b.objects=@(Entity 'ability-opaque' 'teleport_pickup');$traces[$key]=New-Trace ($key.Replace('.','-')) $b @(@{time=0},@{time=100;change={param($s)$s.player.teleport_acquired=O $true;$s.objects[0].available=O $false}},@{time=300;change={param($s)$s.player.teleport_acquired=O $true;$s.objects[0].available=O $false}}) @((Event 'ability_acquired' 100 'teleport_pickup' 'ability-opaque' 'player' 'player-opaque' @{process_type='teleport';successful=$true})) @((Input 'move_toward' 50),(Input 'move_toward' 200))}
$traces['teleport.locked']=New-Trace 'locked-round' (BaseState) @(@{time=0},@{time=200},@{time=600}) @() @((Input 'teleport' 100),(Input 'teleport' 300))
$b=BaseState;$b.player.teleport_acquired=O $true
$teleportEvents=@((Event 'ability_started' 100 'teleport_process' 'tele-a' 'player' 'player-opaque' @{process_type='teleport';phase='started'}),(Event 'action_started' 300 'teleport_process' 'tele-a' 'player' 'player-opaque' @{process_type='teleport';phase='resolved';target_position_m=(Vec 3)}),(Event 'ability_ended' 500 'teleport_process' 'tele-a' 'player' 'player-opaque' @{process_type='teleport';successful=$true;phase='ended'}))
$teleportFrames=@(@{time=0},@{time=100;change={param($s)$s.processes=@(Entity 'tele-a' 'teleport' 0)}},@{time=200;change={param($s)$s.processes=@(Entity 'tele-a' 'teleport' 1)}},@{time=300;change={param($s)$p=Entity 'tele-a' 'teleport' 3;$p.target_position_m=O(Vec 3);$s.processes=@($p)}},@{time=400;change={param($s)$p=Entity 'tele-a' 'teleport' 3;$p.target_position_m=O(Vec 3);$s.processes=@($p)}},@{time=500;change={param($s)$s.player.position_m=O(Vec 3)}},@{time=600;change={param($s)$s.player.position_m=O(Vec 3)}})
$traces['teleport.legal']=New-Trace 'legal-round' $b $teleportFrames $teleportEvents @((Input 'teleport' 100)) @{endpoint_class='legal'}
$traces['teleport.latest_direction']=New-Trace 'tele-aim-round' $b $teleportFrames $teleportEvents @((Input 'teleport' 100)) ((DirectionSetup 'tele-aim-round')+@{endpoint_class='legal'})
$traces['teleport.invalid']=New-Trace 'illegal-round' $b @(@{time=0},@{time=100;change={param($s)$s.processes=@(Entity 'tele-a' 'teleport' 0)}},@{time=300},@{time=400}) @((Event 'ability_started' 100 'teleport_process' 'tele-a' 'player' 'player-opaque' @{process_type='teleport';phase='started'}),(Event 'ability_ended' 300 'teleport_process' 'tele-a' 'player' 'player-opaque' @{process_type='teleport';successful=$false;phase='blocked'})) @((Input 'teleport' 100)) @{endpoint_class='illegal'}
$events=Copy-Fixture $teleportEvents;$events+=@((Event 'ability_started' 700 'teleport_process' 'tele-b' 'player' 'player-opaque' @{process_type='teleport';phase='started'}),(Event 'action_started' 900 'teleport_process' 'tele-b' 'player' 'player-opaque' @{process_type='teleport';phase='resolved';target_position_m=(Vec 6)}),(Event 'ability_ended' 1100 'teleport_process' 'tele-b' 'player' 'player-opaque' @{process_type='teleport';successful=$true;phase='ended'}))
$frames=$teleportFrames+@(@{time=700;change={param($s)$s.player.position_m=O(Vec 3);$s.processes=@(Entity 'tele-b' 'teleport' 3)}},@{time=900;change={param($s)$s.player.position_m=O(Vec 3);$p=Entity 'tele-b' 'teleport' 6;$p.target_position_m=O(Vec 6);$s.processes=@($p)}},@{time=1100;change={param($s)$s.player.position_m=O(Vec 6)}},@{time=1200;change={param($s)$s.player.position_m=O(Vec 6)}})
$traces['teleport.repeat_reuse']=New-Trace 'tele-repeat' $b $frames $events @((Input 'teleport' 100),(Input 'teleport' 200),(Input 'teleport' 700)) @{endpoint_class='legal'}
foreach($phase in @('victory','failure','failure_repeat')){
    $b=BaseState;$resultPhase=if($phase-ceq'victory'){'victory'}else{'failure'};$terminalClock=if($phase-ceq'victory'){60000}else{2000}
    $events=@();if($resultPhase-ceq'failure'){$events+=@(Event 'damage' ($terminalClock-1) 'enemy' 'target-opaque' 'player' 'player-opaque' @{resource='health';amount=100;value_before=100;value_after=0})};$events+=@(Event 'terminal_result' $terminalClock 'round' 'round-entity' '' '' @{terminal_result=$resultPhase})
    $terminalState=Copy-Fixture $b;$terminalState.world.round_phase=O $resultPhase;$terminalState.world.terminal_result_count=O 1;$terminalState.world.survival_time_seconds=O ($terminalClock/1000);if($resultPhase-ceq'failure'){$terminalState.player.health=O 0}
    $traces['journey.'+$phase]=New-Trace ('journey-'+$phase) $b @(@{time=0},@{time=$terminalClock;state=$terminalState},@{time=($terminalClock+100);state=$terminalState}) $events @((Input 'move_toward' 100))
}
$b=BaseState;$b.world.round_phase=O 'failure';$b.player.health=O 0;$restartTrace=New-Trace 'failure-followup' $b @(@{time=0},@{time=100}) @() @((Input 'restart' 50));$restartResult=New-Trace 'restart-new-round' (BaseState) @(@{time=150},@{time=250}) @((Event 'restart_completed' 150 'round' 'round-entity' '' '' @{round_phase='in_progress';successful=$true}));$restartTrace.setup.restart_result=$restartResult;$traces['journey.failure_restart']=$restartTrace
foreach($mode in @('props','empty','multiple')){
    $b=BaseState;if($mode-ne'empty'){$b.objects=@(Entity 'enemy-named-opaque-prop' 'physics_prop' 5)}
    $events=@((Event 'projectile_spawned' 100 'black_hole_projectile' 'bh-bolt-a' 'player' 'player-opaque' @{process_type='black_hole_projectile'}),(Event 'ability_started' 500 'black_hole_field' 'field-a' 'black_hole_projectile' 'bh-bolt-a' @{process_type='black_hole_field'}),(Event 'ability_ended' 5300 'black_hole_field' 'field-a' '' '' @{process_type='black_hole_field'}))
    if($mode-ne'empty'){$events+=@((Event 'contact' 2000 'black_hole_field' 'field-a' 'physics_prop' 'enemy-named-opaque-prop' @{reason='absorbed'}),(Event 'entity_removed' 2000 'black_hole_field' 'field-a' 'physics_prop' 'enemy-named-opaque-prop' @{reason='absorbed'}))}
    else{$events+=@(Event 'contact' 2000 'enemy_projectile' 'incidental-bolt' 'black_hole_field' 'field-a' @{process_type='enemy_projectile';reason='first_contact'})}
    $multiple=$mode-ceq'multiple';if($multiple){$events+=@((Event 'projectile_spawned' 200 'black_hole_projectile' 'bh-bolt-b' 'player' 'player-opaque' @{process_type='black_hole_projectile'}),(Event 'ability_started' 600 'black_hole_field' 'field-b' 'black_hole_projectile' 'bh-bolt-b' @{process_type='black_hole_field'}),(Event 'ability_ended' 5400 'black_hole_field' 'field-b' '' '' @{process_type='black_hole_field'}))}
    $frames=@(@{time=0});foreach($time in @(150,250,350,500,600,1000,2000,3000,5300,5400,5500)){$at=$time;$s=Copy-Fixture $b;$s.processes=@();if($at-lt500){$s.processes+=@(Entity 'bh-bolt-a' 'black_hole_projectile' ($at/100))};if($multiple-and$at-ge200-and$at-lt600){$s.processes+=@(Entity 'bh-bolt-b' 'black_hole_projectile' (($at-100)/100))};if($at-ge500-and$at-lt5300){$s.processes+=@(Entity 'field-a' 'black_hole_field' 3)};if($multiple-and$at-ge600-and$at-lt5400){$s.processes+=@(Entity 'field-b' 'black_hole_field' 3)};if($mode-ne'empty'){if($at-gt2000){$s.objects=@()}elseif($at-ge1000){$s.objects[0].position_m=O(Vec $(if($at-ge2000){3}else{4}))}};$frames+=@(@{time=$at;state=$s})}
    $inputs=@((Input 'black_hole' 100));if($multiple){$inputs+=@(Input 'black_hole' 200)};$traces['blackhole.'+$mode]=New-Trace ('blackhole-'+$mode) $b $frames $events $inputs @{isolated_motion=$true}
}
$snapshotSchema=Join-Path $root '../input/contracts/actionroguelike-probe-snapshot.schema.json';$eventSchema=Join-Path $root '../input/contracts/actionroguelike-probe-events.schema.json'
$contract=Get-Content -Raw -LiteralPath (Join-Path $root 'contracts/atomic-check-contract.json')|ConvertFrom-Json -Depth 100 -AsHashtable
$variantMap=Get-ActionRoguelikeAtomicVariantMap
Assert ($contract.schema_version-ceq'4.0.0'-and$contract.engine-ceq'Unreal Engine 5.6.1 CL 44394996') 'The atomic contract lost its v4 or UE 5.6.1 binding.'
Assert ($contract.functions.Count-eq2-and'run_invalid'-cin$contract.verdicts) 'The atomic contract must expose only the checkpoint API and variant map with run_invalid.'
foreach($id in $variantMap.Keys){Assert (($contract.checkpoints[$id]-join'|')-ceq($variantMap[$id]-join'|')) "Atomic contract variant map differs at $id."}
$variantIds=@($variantMap.Values|ForEach-Object{$_}|Select-Object -Unique)
Assert ($contract.variants.Count-eq$variantIds.Count) 'The atomic contract variant catalog differs from the executable map.'
foreach($variant in $variantIds){$spec=$contract.variants[$variant];Assert ($null-ne$spec-and$spec.max_actions-ge$spec.minimum_actions-and$spec.max_serial_seconds-gt0) "Atomic contract omits the action/time budget for $variant.";if($spec.max_actions-gt2){Assert ([bool]$spec.action_budget_reason) "Atomic contract omits the longer-input reason for $variant."}}
foreach($trace in $traces.Values){foreach($sample in $trace.samples){Assert ($sample.snapshot|ConvertTo-Json -Depth 100|Test-Json -SchemaFile $snapshotSchema) 'Fixture snapshot violates the public schema.';Assert ($sample.events|ConvertTo-Json -Depth 100|Test-Json -SchemaFile $eventSchema) 'Fixture event batch violates the public schema.'}}
foreach($id in (Get-ActionRoguelikeAtomicVariantMap).Keys){$null=Result $id $traces}
$bad=Copy-Fixture $traces;$last=$bad['primary.hit'].samples[-1].events;$extra=Copy-Fixture $last.events[2];$extra.event_id='duplicate-damage';$extra.sequence=4;$extra.monotonic_ms=203;$last.events+=@($extra);$last.coverage.cursor_end=5;$last.coverage.tail_watermark=5;$r=Result 'D3-03' $bad 'fail';Assert (@($r.variants|Where-Object reason_code -eq 'PROJECTILE_SINGLE_DAMAGE').Count-eq1) 'Double damage to the same target passed.'
$bad=Copy-Fixture $traces;$bad.Remove('primary.obstacle');$null=Result 'D3-03' $bad 'run_invalid'
$partial=Test-ActionRoguelikeAtomicCheckpoint -CheckpointId 'D3-03' -Traces $bad;Assert ($partial.verdict-ceq'run_invalid' -and 'primary.obstacle'-cin$partial.measurements.missing_variants -and -not$partial.measurements.collection_complete) 'Partial collection escaped the evaluator health gate.'
foreach($id in $variantMap.Keys){
    $empty=Test-ActionRoguelikeAtomicCheckpoint -CheckpointId $id -Traces @{}
    Assert ($empty.verdict-ceq'run_invalid'-and-not$empty.passed-and$empty.attribution-ceq'evaluator') "Empty collection crashed or passed: $id"
    Assert ($empty.measurements.missing_variants.Count-eq$variantMap[$id].Count-and$empty.measurements.completed_variants-eq0) "Empty collection lost required variants: $id"
}
$legacy=Copy-Fixture $traces['resources.initial'];foreach($pair in $legacy.samples){$pair.events.identity.batch_id='batch-1-0';$pair.events.coverage.previous_batch_id=$null}
$chain=Get-ActionRoguelikeEventCoverage $legacy.samples
Assert (-not$chain.complete-and'ATOMIC_EVENT_STREAM_UNAVAILABLE'-cin$chain.reason_codes-and'ATOMIC_EVENT_LINK'-cnotin$chain.reason_codes) 'Legacy empty heartbeats were mistaken for a broken event link or healthy evidence.'
$bad=Copy-Fixture $traces;$bad['resources.initial']=$legacy;$r=Result 'D3-07' $bad 'fail'
Assert ($r.reason_code-ceq'CANDIDATE_EVENT_STREAM_UNAVAILABLE') 'A legacy heartbeat passed a forbidden-event assertion or escaped candidate attribution.'
$chain=Get-ActionRoguelikeEventCoverage $traces['resources.initial'].samples
Assert ($chain.complete-and-not$chain.event_observations_present) 'A properly linked empty event stream must prove a no-event window.'
$bad=Copy-Fixture $traces;$bad['primary.hit'].samples[-1].events.coverage.previous_batch_id='wrong-batch';$r=Result 'D3-03' $bad 'run_invalid'
Assert ($r.reason_code-ceq'ATOMIC_EVENT_LINK') 'A real broken link was accepted.'
$pair=Copy-Fixture $traces['primary.hit'].samples[-1];$repeat=Copy-Fixture $pair
$repeat.snapshot.identity.sequence++;$repeat.snapshot.identity.snapshot_id='repeat-snapshot';$repeat.events.identity.sequence++;$repeat.events.identity.snapshot_id='repeat-snapshot'
$chain=Get-ActionRoguelikeEventCoverage @($pair,$repeat)
Assert ($chain.complete) 'An unchanged cumulative batch was required to link to itself.'
$repeat.events.events[-1].payload.reason='rewritten';$chain=Get-ActionRoguelikeEventCoverage @($pair,$repeat)
Assert (-not$chain.complete-and'ATOMIC_EVENT_BATCH_REUSED'-cin$chain.reason_codes) 'A reused batch identity concealed changed events.'
$reset=Copy-Fixture $legacy.samples[-1];$reset.snapshot.identity.sequence=100;$chain=Get-ActionRoguelikeEventCoverage @($pair,$reset)
Assert (-not$chain.complete-and'ATOMIC_EVENT_GAP'-cin$chain.reason_codes) 'A legacy empty batch erased observed events.'
$bad=Copy-Fixture $traces;$bad['primary.hit'].input_receipts[0].attribution='candidate';$null=Result 'D3-03' $bad 'run_invalid'
$bad=Copy-Fixture $traces;$bad['resources.reject_poor'].samples[-1].snapshot.player.credits.value=48;$null=Result 'D3-07' $bad 'fail'
$bad=Copy-Fixture $traces;foreach($s in $bad['resources.pickup_recovery'].samples){foreach($e in $s.events.events){if($e.event_type-ceq'availability_changed'-and$e.payload.available-eq$true){$e.monotonic_ms=10099}}};$null=Result 'D3-07' $bad 'fail'
$bad=Copy-Fixture $traces;foreach($s in $bad['resources.heal_exact50'].samples){foreach($e in $s.events.events){if($e.event_type-ceq'availability_changed'-and$e.payload.available-eq$true){$e.monotonic_ms=4099}}};$null=Result 'D3-07' $bad 'fail'
$bad=Copy-Fixture $traces;$bad['teleport.legal'].samples[3].snapshot.player.position_m.value=Vec 3;$null=Result 'D3-05' $bad 'fail'
$bad=Copy-Fixture $traces;foreach($s in $bad['blackhole.props'].samples){foreach($e in $s.events.events){if($e.event_type-ceq'contact'){$e.object.role='enemy';$e.object.entity_id='target-opaque'}}};$null=Result 'D3-04' $bad 'fail'
$bad=Copy-Fixture $traces;foreach($s in $bad['blackhole.empty'].samples){foreach($e in $s.events.events){if($e.event_type-ceq'contact'){$e.subject=@{role='black_hole_field';entity_id='field-a'};$e.object=@{role='static_world';entity_id='opaque-wall'}}}};$r=Result 'D3-04' $bad 'fail'
Assert (@($r.variants|Where-Object reason_code -eq 'BLACK_HOLE_INVALID_TARGET_ROLE').Count-eq1) 'Field-originated forbidden contact escaped the causal filter.'
$bad=Copy-Fixture $traces;$bad['primary.hit'].samples[-1].events.coverage.cursor_start=3;$bad['primary.hit'].samples[-1].events.coverage.head_watermark=3;$bad['primary.hit'].samples[-1].events.events=@($bad['primary.hit'].samples[-1].events.events|Where-Object sequence -ge 3);$null=Result 'D3-03' $bad 'run_invalid'
$bad=Copy-Fixture $traces;$bad['primary.hit'].samples[-1].snapshot.identity.round_id='different';$bad['primary.hit'].samples[-1].events.identity.round_id='different';$null=Result 'D3-03' $bad 'run_invalid'
$bad=Copy-Fixture $traces;$bad['primary.hit'].cleanup=@{verified=$true};$null=Result 'D3-03' $bad 'run_invalid'
$bad=Copy-Fixture $traces;$bad['journey.failure_restart'].setup.restart_result=$bad['journey.failure_restart'].setup.restart_result.samples[0].snapshot;$null=Result 'D4-02' $bad 'run_invalid'
$bad=Copy-Fixture $traces;$bad['primary.latest_direction'].setup.direction_change.before_facing=$bad['primary.latest_direction'].setup.direction_change.after_facing;$null=Result 'D3-03' $bad 'run_invalid'
# A single opaque process can change role without changing identity.
$same=Copy-Fixture $traces
foreach($key in @('blackhole.props','blackhole.empty','blackhole.multiple')){
    foreach($sample in $same[$key].samples){
        foreach($p in $sample.snapshot.processes){if($p.entity_id.value-ceq'field-a'){$p.entity_id.value='bh-bolt-a'};if($p.entity_id.value-ceq'field-b'){$p.entity_id.value='bh-bolt-b'}}
        foreach($e in $sample.events.events){foreach($ref in @($e.subject,$e.object)){if($ref-and$ref.entity_id-ceq'field-a'){$ref.entity_id='bh-bolt-a'};if($ref-and$ref.entity_id-ceq'field-b'){$ref.entity_id='bh-bolt-b'}};if($e.event_type-ceq'ability_started'){$e.object=$null}}
    }
}
$null=Result 'D3-04' $same
# Exact commit observation survives a subsequent engine floor adjustment.
$floor=Copy-Fixture $traces
foreach($sample in $floor['teleport.legal'].samples){
    foreach($event in $sample.events.events){if($event.event_type-ceq'ability_ended'){$event.payload.position_m=Vec 3}}
    if($sample.snapshot.identity.monotonic_ms-ge500){$sample.snapshot.player.position_m=O(Vec 3 0 -.0085)}
}
$null=Result 'D3-05' $floor
foreach($sample in $floor['teleport.legal'].samples){if($sample.snapshot.identity.monotonic_ms-ge500){$sample.snapshot.player.position_m=O(Vec 3.2 0 -.0085)}}
$null=Result 'D3-05' $floor 'fail'
# Timers can recover on the next engine update, but never after the first
# continuous sample at/after their deadline or before the deadline.
$tick=Copy-Fixture $traces
foreach($key in @('resources.pickup_recovery','resources.heal_exact50')){
    $sample=$tick[$key].samples[-1];$sample.snapshot.identity.monotonic_ms+=6;$sample.events.identity.monotonic_ms+=6
    foreach($event in $sample.events.events){if($event.event_type-ceq'availability_changed'-and$event.payload.available-eq$true){$event.monotonic_ms+=6}}
}
$null=Result 'D3-07' $tick
$pitched=Copy-Fixture $traces
$pitched['blackhole.props'].setup.native_aim=@{confirmed=$true;receipt_path='receipts/setup.json';direction=(Vec 1 0 -.2)}
foreach($sample in $pitched['blackhole.props'].samples){foreach($process in $sample.snapshot.processes){if($process.process_type.value-ceq'black_hole_projectile'){$process.position_m.value.z=-.2*$process.position_m.value.x}}}
$null=Result 'D3-04' $pitched
$pitched['blackhole.props'].setup.native_aim.direction=Vec 1 0 .2
$r=Result 'D3-04' $pitched 'fail'
Assert (@($r.variants|Where-Object reason_code -eq 'ABILITY_STALE_DIRECTION').Count-eq1) 'Explicit native pitch did not reject a contrary flight direction.'
$pitched['blackhole.props'].setup.native_aim.confirmed=$false
$null=Result 'D3-04' $pitched 'run_invalid'
# Candidate heartbeats cannot establish negative event assertions, but cannot
# conceal missing setup, input, cleanup, or inconsistent collection either.
$heartbeat=Copy-Fixture $traces
foreach($pair in $heartbeat['teleport.locked'].samples){$pair.events.coverage.previous_batch_id=$null}
$r=Result 'D3-05' $heartbeat 'fail'
Assert (@($r.variants|Where-Object reason_code -eq 'CANDIDATE_EVENT_STREAM_UNAVAILABLE').Count-eq1) 'A fully collected candidate heartbeat escaped candidate attribution.'
foreach($defect in @('setup','cleanup','input','identity','collector')){
    $bad=Copy-Fixture $heartbeat
    switch($defect){
        'setup' {$bad['teleport.locked'].setup.confirmed=$false}
        'cleanup' {$bad['teleport.locked'].cleanup.verified=$false}
        'input' {$bad['teleport.locked'].input_receipts=@()}
        'identity' {$bad['teleport.locked'].samples[-1].events.identity.process_token='another-process'}
        'collector' {$bad.Remove('teleport.locked')}
    }
    $null=Result 'D3-05' $bad 'run_invalid'
}
# Public optional payload fields may be omitted when the same fact is proved
# by correlated state. Raw contradictory values must still be rejected.
$optional=Copy-Fixture $traces
foreach($key in $optional.Keys){
    foreach($sample in $optional[$key].samples){foreach($event in $sample.events.events){
        if($key-like'teleport.*'){$event.payload.Remove('successful')}
        if($key-like'resources.*'){
            $event.payload.Remove('amount');$event.payload.Remove('available')
            if($event.event_type-ceq'healing'){$event.subject=@{role='player';entity_id='player-opaque'};$event.object=$null}
        }
        if($event.event_type-ceq'projectile_spawned'-and(Get-AREventEntity $event 'player_projectile')){$event.event_type='ability_started';$event.payload.process_type='player_projectile'}
        if($event.payload.Count-eq0){$event.payload.reason='State transition recorded'}
    }}
}
$null=Result 'D3-05' $optional
$null=Result 'D2-10' $optional
$null=Result 'D3-07' $optional
$null=Result 'D3-03' $optional
foreach($sample in $optional['teleport.legal'].samples){foreach($event in $sample.events.events){if($event.event_type-ceq'ability_ended'){$event.payload.successful=$false}}}
$null=Result 'D2-08' $optional 'fail'
$phase=Copy-Fixture $traces
foreach($sample in $phase['journey.failure_restart'].setup.restart_result.samples){foreach($event in $sample.events.events){$event.payload.Remove('round_phase');if($event.payload.Count-eq0){$event.payload.reason='Round restarted'}}}
$null=Result 'D4-02' $phase
# Dual vocabulary is one transition. Duplicate canonical events remain visible
# to the cardinality rule; deduplication applies only to the optional alias.
$canonical=Event 'projectile_spawned' 100 'black_hole_projectile' 'same-process' '' '' @{process_type='black_hole_projectile'}
$alias=Event 'ability_started' 100 'black_hole_projectile' 'same-process' '' '' @{process_type='black_hole_projectile'}
Assert (@(Get-AREvents @{events=@($canonical,$alias)} 'projectile_spawned' 'black_hole_projectile').Count-eq1) 'Canonical creation plus its alias was double-counted.'
Assert (@(Get-AREvents @{events=@($canonical,$canonical,$alias)} 'projectile_spawned' 'black_hole_projectile').Count-eq2) 'Duplicate canonical events were incorrectly erased.'
# A source-less player damage event needs one enclosing enemy action. An
# unrelated, ended action or two possible attackers cannot supply causality.
foreach($mode in @('unique','ended','ambiguous')){
    $sourceLess=Copy-Fixture $traces
    $start=Event 'action_started' 1500 'enemy' 'target-opaque' '' '' @{action='melee_attack'}
    $end=Event 'action_ended' $(if($mode-ceq'ended'){1900}else{2000}) 'enemy' 'target-opaque' '' '' @{action='melee_attack'}
    $damage=Event 'damage' 1999 'player' 'player-opaque' '' '' @{resource='health';amount=100}
    $terminal=Event 'terminal_result' 2000 'round' 'round-entity' '' '' @{terminal_result='failure'}
    $events=@($start,$damage,$end,$terminal)
    if($mode-ceq'ambiguous'){$events+=@((Event 'action_started' 1500 'enemy' 'second-enemy' '' '' @{action='melee_attack'}),(Event 'action_ended' 2000 'enemy' 'second-enemy' '' '' @{action='melee_attack'}))}
    $dead=Copy-Fixture $traces['journey.failure'].samples[1].snapshot
    $sourceLess['journey.failure']=New-Trace 'sourceless-failure' (BaseState) @(@{time=0},@{time=2000;state=$dead},@{time=2100;state=$dead}) $events @((Input 'move_toward' 100))
    $null=Result 'D4-02' $sourceLess $(if($mode-ceq'unique'){'pass'}else{'fail'})
}
# Optional subject/object references and equivalent resource publications must
# not make the private Gold event layout a hidden public requirement.
$sparse=Copy-Fixture $traces
foreach($key in $sparse.Keys){foreach($sample in $sparse[$key].samples){foreach($event in $sample.events.events){
    if($event.event_type-ceq'ability_acquired'){$event.subject=@{role='player';entity_id='player-opaque'};$event.object=$null}
    if($event.event_type-ceq'terminal_result'){$event.subject=$null;$event.object=$null}
    if($key-like'resources.heal*'-and$event.event_type-ceq'payment'){$event.event_type='resource_changed';$event.subject=@{role='player';entity_id='player-opaque'};$event.object=$null;$event.payload=@{resource='credits';value_after=0}}
    if($key-like'resources.heal*'-and$event.event_type-ceq'healing'){$event.subject=@{role='player';entity_id='player-opaque'};$event.object=$null;$event.payload=@{resource='health';value_after=100}}
    if($event.event_type-ceq'availability_changed'){$event.subject=$null;$event.object=$null}
}}}
foreach($id in @('D2-08','D2-10','D3-05','D3-07','D2-13','D4-02')){$null=Result $id $sparse}
$bad=Copy-Fixture $sparse
foreach($sample in $bad['teleport.pickup'].samples){$sample.snapshot.objects[0].available=O $true}
$null=Result 'D2-08' $bad 'fail'
$bad=Copy-Fixture $sparse
foreach($sample in $bad['resources.heal_basic'].samples){foreach($event in $sample.events.events){if($event.event_type-ceq'resource_changed'){$event.subject.entity_id='different-player'}}}
$null=Result 'D2-10' $bad 'fail'
$dual=Copy-Fixture $sparse
foreach($sample in $dual['resources.heal_basic'].samples){foreach($event in $sample.events.events){
    if($event.event_type-ceq'availability_changed'-and$event.payload.available-eq$false){$event.event_type='healing';$event.subject=@{role='player';entity_id='player-opaque'};$event.payload=@{successful=$true;reason='healed'}}
}}
$null=Result 'D2-10' $dual
foreach($sample in $dual['resources.heal_basic'].samples){foreach($event in $sample.events.events){if($event.event_type-ceq'healing'){$event.payload=@{successful=$true;reason='healed'}}}}
$null=Result 'D2-10' $dual 'fail'
$roundAlias=Copy-Fixture $traces
foreach($pair in $roundAlias['journey.failure_restart'].setup.restart_result.samples){foreach($event in $pair.events.events){if($event.event_type-ceq'restart_completed'){$event.event_type='round_phase_changed';$event.subject=$null;$event.object=$null}}}
$null=Result 'D4-02' $roundAlias
foreach($pair in $roundAlias['journey.failure_restart'].setup.restart_result.samples){foreach($event in $pair.events.events){$event.payload.round_phase='failure'}}
$null=Result 'D4-02' $roundAlias 'fail'
Write-Output "ACTIONROGUELIKE_ATOMIC_CHECKS_OK checks=$script:checks checkpoints=8 public_schema_valid=true independent_variants=true optional_payload_state_corroboration=true sparse_event_roles=true mutation_regressions=true"
