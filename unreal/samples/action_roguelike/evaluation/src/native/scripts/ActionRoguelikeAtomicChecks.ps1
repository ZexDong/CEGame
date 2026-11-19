Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ActionRoguelikeMetricAdapter.ps1')

# This module accepts evaluator-owned independent traces, never candidate-authored
# pass flags. Gameplay facts use only the published snapshot/event vocabulary.
function Get-ActionRoguelikeAtomicProperty($Object,[string]$Name) {
    if($null-eq$Object){return $null}
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name)){return $Object[$Name]};return $null}
    $p=$Object.PSObject.Properties[$Name];if($p){return $p.Value};return $null
}
function Get-ARPath($Object,[string]$Path){foreach($part in $Path.Split('.')){$Object=Get-ActionRoguelikeAtomicProperty $Object $part};return $Object}
function Assert-ARRule([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){throw "fail|$Code|$Detail"}}
function Assert-ARHealth([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){throw "run_invalid|$Code|$Detail"}}
function Get-ARValue($Object,[string]$Path){
    $o=Get-ARPath $Object $Path
    Assert-ARRule ($null-ne$o -and (Get-ActionRoguelikeAtomicProperty $o 'trust') -in @('verified','corroborated') -and $null-ne(Get-ActionRoguelikeAtomicProperty $o 'value')) 'CANDIDATE_OBSERVATION_UNAVAILABLE' "Required read-only field is unavailable: $Path"
    return Convert-ARMetricValue (Get-ActionRoguelikeAtomicProperty $o 'value') $Path
}
function Get-AREntityId($Entity){return [string](Get-ARValue $Entity 'entity_id')}
function Get-ARDistance($A,$B){$sum=0.0;foreach($axis in @('x','y','z')){$aValue=Get-ActionRoguelikeAtomicProperty $A $axis;$bValue=Get-ActionRoguelikeAtomicProperty $B $axis;Assert-ARRule ($null-ne$aValue-and$null-ne$bValue) 'CANDIDATE_POSITION_UNAVAILABLE' 'A position is incomplete.';$sum+=[Math]::Pow(([double]$aValue-[double]$bValue),2)};return [Math]::Sqrt($sum)}
function Get-AREventEntity($Event,[string]$Role){foreach($side in @('subject','object')){$ref=Get-ActionRoguelikeAtomicProperty $Event $side;if((Get-ActionRoguelikeAtomicProperty $ref 'role') -ceq $Role){return [string](Get-ActionRoguelikeAtomicProperty $ref 'entity_id')}};return $null}
function Get-ARObjects($State,[string]$Type){return @(Get-ActionRoguelikeAtomicProperty $State 'objects'|Where-Object{(Get-ARValue $_ 'object_type')-ceq$Type})}
function Get-ARProcesses($State,[string]$Type){return @(Get-ActionRoguelikeAtomicProperty $State 'processes'|Where-Object{(Get-ARValue $_ 'process_type')-ceq$Type})}
function Get-ARBoundObject($State,$Trace,[string]$Type){
    $id=[string](Get-ARPath $Trace 'setup.target_entity_id');$objects=@(Get-ARObjects $State $Type)
    if($id){$objects=@($objects|Where-Object{(Get-AREntityId $_)-ceq$id})}
    Assert-ARHealth ($id -or $objects.Count-le1) 'ATOMIC_TARGET_AMBIGUOUS' 'The evaluator must bind one observed semantic target when several exist.'
    Assert-ARRule ($objects.Count-eq1) 'CANDIDATE_TARGET_UNAVAILABLE' "The bound $Type is absent."
    return $objects[0]
}
function Get-ARInput($Context,[string]$Action){return @($Context.inputs|Where-Object{$_.semantic_action-ceq$Action})}
function Assert-ARCleanup($Trace,[string]$Token,[string]$Round){
    # A bare verified=true is not evidence. Cleanup is an evaluator-owned
    # receipt and must identify what was released, what was stopped, and where
    # the receipt can be audited.
    $cleanup=Get-ActionRoguelikeAtomicProperty $Trace 'cleanup'
    Assert-ARHealth ($null-ne$cleanup-and(Get-ActionRoguelikeAtomicProperty $cleanup 'verified')-eq$true) 'ATOMIC_CLEANUP_UNVERIFIED' 'Input and process cleanup was not verified.'
    Assert-ARHealth ([bool](Get-ActionRoguelikeAtomicProperty $cleanup 'receipt_id')) 'ATOMIC_CLEANUP_RECEIPT_MISSING' 'Cleanup has no evaluator receipt identity.'
    Assert-ARHealth ((Get-ActionRoguelikeAtomicProperty $cleanup 'attribution')-ceq'evaluator') 'ATOMIC_CLEANUP_ATTRIBUTION' 'Cleanup receipt is not evaluator-owned.'
    Assert-ARHealth ((Get-ActionRoguelikeAtomicProperty $cleanup 'release_all_inputs')-eq$true-and(Get-ActionRoguelikeAtomicProperty $cleanup 'fixture_cleared')-eq$true-and(Get-ActionRoguelikeAtomicProperty $cleanup 'process_tree_stopped')-eq$true) 'ATOMIC_CLEANUP_INCOMPLETE' 'Cleanup receipt does not prove input release, fixture clearing, and process-tree stop.'
    $paths=@(@(Get-ActionRoguelikeAtomicProperty $cleanup 'evidence_paths')|Where-Object{$_})
    Assert-ARHealth ($paths.Count-gt0) 'ATOMIC_CLEANUP_EVIDENCE_MISSING' 'Cleanup receipt has no auditable evidence path.'
    Assert-ARHealth ((Get-ActionRoguelikeAtomicProperty $cleanup 'process_token')-ceq$Token-and(Get-ActionRoguelikeAtomicProperty $cleanup 'round_id')-ceq$Round) 'ATOMIC_CLEANUP_IDENTITY' 'Cleanup receipt is not bound to the trace process and round.'
}
function Get-ARVector($Object,[string]$Path,[string]$Code){
    $value=Get-ARPath $Object $Path
    if($null-ne(Get-ActionRoguelikeAtomicProperty $value 'value')){$value=Get-ARValue $Object $Path}
    Assert-ARHealth ($null-ne$value-and$null-ne(Get-ActionRoguelikeAtomicProperty $value 'x')-and$null-ne(Get-ActionRoguelikeAtomicProperty $value 'y')-and$null-ne(Get-ActionRoguelikeAtomicProperty $value 'z')) $Code 'Direction evidence must contain a complete x/y/z vector.'
    return $value
}
function Assert-ARDirectionChange($Context){
    # Latest-direction cases need a real, observed direction change before the
    # ability is fired. Comparing one flight vector with current facing alone
    # permits a trace author to claim a direction change that never happened.
    $change=Get-ARPath $Context.trace 'setup.direction_change'
    Assert-ARHealth ($null-ne$change-and(Get-ActionRoguelikeAtomicProperty $change 'confirmed')-eq$true) 'ATOMIC_DIRECTION_CHANGE_UNCONFIRMED' 'The evaluator did not confirm a direction change.'
    $old=Get-ARVector $change 'before_facing' 'ATOMIC_DIRECTION_CHANGE_EVIDENCE'
    $new=Get-ARVector $change 'after_facing' 'ATOMIC_DIRECTION_CHANGE_EVIDENCE'
    Assert-ARHealth ((Get-ARDistance $old $new)-gt0.01) 'ATOMIC_DIRECTION_CHANGE_MISSING' 'The direction-change evidence contains identical vectors.'
    $receipt=Get-ActionRoguelikeAtomicProperty $change 'input_receipt'
    Assert-ARHealth ($null-ne$receipt-and$receipt.input_dispatched-eq$true-and$receipt.release_verified-eq$true-and$receipt.attribution-ceq'evaluator' -and$receipt.evidence_path) 'ATOMIC_DIRECTION_INPUT_UNVERIFIED' 'Direction change has no evaluator input receipt.'
    Assert-ARHealth ($receipt.process_token-ceq$Context.token-and$receipt.round_id-ceq$Context.round-and[long]$receipt.monotonic_ms-le$Context.start) 'ATOMIC_DIRECTION_INPUT_WINDOW' 'Direction input is not before the ability trace.'
    $facing=Get-ARValue $Context.before 'player.facing'
    Assert-ARHealth ((Get-ARDistance $facing $new)-lt0.0001) 'ATOMIC_DIRECTION_FACING_MISMATCH' 'The first sample is not the direction established by the receipt.'
}
function Test-ARSparseEventRole($Context,$Event,[string]$Role,[string]$EntityId){
    # References are nullable in the public schema. Infer only a unique scalar
    # transition and, for an item, its bound availability transition. Never
    # replace an explicit reference or manufacture a process/action event.
    if($null-ne$Event.subject-or$null-ne$Event.object){return $false}
    $type=[string]$Event.event_type
    if($type-cnotin@('pickup','payment','healing','damage','ability_acquired')){return $false}
    $before=@($Context.states|Where-Object{$_.identity.monotonic_ms-lt$Event.monotonic_ms}|Select-Object -Last 1)
    $after=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$Event.monotonic_ms}|Select-Object -First 1)
    if($before.Count-ne1-or$after.Count-ne1){return $false}
    if($type-ceq'ability_acquired'){
        if((Get-ARPath $Event 'payload.process_type')-cne'teleport'-or(Get-ARValue $before[0] 'player.teleport_acquired')-ne$false-or(Get-ARValue $after[0] 'player.teleport_acquired')-ne$true){return $false}
    }else{
        $resource=if($type-in@('pickup','payment')){'credits'}else{'health'}
        $old=Get-ARPath $Event 'payload.value_before';$new=Get-ARPath $Event 'payload.value_after'
        if((Get-ARPath $Event 'payload.resource')-cne$resource-or$null-eq$old-or$null-eq$new-or$old-eq$new-or$old-ne(Get-ARValue $before[0] "player.$resource")-or$new-ne(Get-ARValue $after[0] "player.$resource")){return $false}
        if(($type-in@('pickup','healing')-and$new-le$old)-or($type-in@('payment','damage')-and$new-ge$old)){return $false}
    }
    if($Role-ceq'player'){return -not$EntityId-or$EntityId-ceq(Get-AREntityId $Context.before.player)}
    $expected=if($type-ceq'pickup'){'credits_pickup'}elseif($type-in@('payment','healing')){'potion'}elseif($type-ceq'ability_acquired'){'teleport_pickup'}else{''}
    $target=[string](Get-ARPath $Context.trace 'setup.target_entity_id')
    if($Role-cne$expected-or-not$target-or($EntityId-and$EntityId-cne$target)){return $false}
    $oldItems=@(Get-ARObjects $before[0] $expected|Where-Object{(Get-AREntityId $_)-ceq$target})
    $newItems=@(Get-ARObjects $after[0] $expected|Where-Object{(Get-AREntityId $_)-ceq$target})
    return $oldItems.Count-eq1-and$newItems.Count-eq1-and(Get-ARValue $oldItems[0] 'available')-eq$true-and(Get-ARValue $newItems[0] 'available')-eq$false
}
function Get-AREvents($Context,[string]$Type,[string]$Role='',[string]$EntityId=''){
    return @($Context.events|Where-Object{
        $same=$_.event_type-ceq$Type
        # Both public event forms describe process creation/termination. Keep
        # raw records untouched; an alias still needs the exact semantic role.
        if($Type-ceq'projectile_spawned'-and$Role-in@('player_projectile','black_hole_projectile')-and$_.event_type-ceq'ability_started'-and(Get-ARPath $_ 'payload.process_type')-ceq$Role){$same=$true}
        if($Type-ceq'entity_removed'-and$Role-in@('player_projectile','black_hole_projectile')-and$_.event_type-ceq'ability_ended'){$same=$true}
        if($same-and$_.event_type-cne$Type){
            # Some publishers emit both valid vocabularies for one transition.
            # Prefer its canonical event; aliases must not double the count.
            $aliasId=Get-AREventEntity $_ $Role
            if(@($Context.events|Where-Object{$_.event_type-ceq$Type-and(Get-AREventEntity $_ $Role)-ceq$aliasId}).Count){$same=$false}
        }
        $referenced=(-not$Role-or$null-ne(Get-AREventEntity $_ $Role))-and(-not$EntityId-or$EntityId-cin@([string](Get-ARPath $_ 'subject.entity_id'),[string](Get-ARPath $_ 'object.entity_id')))
        $same-and($referenced-or($Role-and(Test-ARSparseEventRole $Context $_ $Role $EntityId)))
    })
}
function Get-ARHealthFingerprint($State){
    $parts=[Collections.Generic.List[string]]::new();$parts.Add('player:'+([string](Get-ARValue $State 'player.health')))
    foreach($enemy in @($State.enemies|Sort-Object{Get-AREntityId $_})){$parts.Add((Get-AREntityId $enemy)+':'+[string](Get-ARValue $enemy 'health'))}
    return $parts -join '|'
}
function Assert-ARNoDamage($Context){Assert-ARRule (@(Get-AREvents $Context 'damage').Count-eq0) 'UNEXPECTED_DAMAGE' 'This isolated case must not produce damage.';$health=Get-ARHealthFingerprint $Context.before;foreach($state in $Context.states){Assert-ARRule ((Get-ARHealthFingerprint $state)-ceq$health) 'UNEXPECTED_HEALTH_CHANGE' 'Health changed during a no-damage case.'}}
function Assert-ARUnchanged($Context,[string[]]$Paths){foreach($path in $Paths){$before=Get-ARValue $Context.before $path;foreach($state in $Context.states){$after=Get-ARValue $state $path;Assert-ARRule (($before|ConvertTo-Json -Compress -Depth 20)-ceq($after|ConvertTo-Json -Compress -Depth 20)) 'UNEXPECTED_STATE_CHANGE' "The rejected action changed $path."}}}

function Get-ActionRoguelikeAtomicVariantMap {
    return [ordered]@{
        'D2-08'=@('teleport.pickup','teleport.legal')
        'D2-10'=@('resources.pickup','resources.heal_basic')
        'D2-13'=@('journey.victory','journey.failure')
        'D3-03'=@('primary.hit','primary.obstacle','primary.miss','primary.repeat_reuse','primary.latest_direction')
        'D3-04'=@('blackhole.props','blackhole.empty','blackhole.multiple')
        'D3-05'=@('teleport.locked','teleport.pickup_repeat','teleport.legal','teleport.invalid','teleport.repeat_reuse','teleport.latest_direction')
        'D3-07'=@('resources.initial','resources.pickup_recovery','resources.reject_full','resources.reject_poor','resources.heal_exact50')
        'D4-02'=@('journey.failure','journey.failure_repeat','journey.failure_restart')
    }
}

function Test-ARPairCorrelation($Pair){
    $s=$Pair.snapshot;$e=$Pair.events
    foreach($field in @('process_token','round_id')){if($s.identity.$field-cne$e.identity.$field){return $false}}
    $proof=Get-ActionRoguelikeAtomicProperty $Pair 'independent_transport'
    if($null-eq$proof){return $s.identity.snapshot_id-ceq$e.identity.snapshot_id-and$s.identity.monotonic_ms-eq$e.identity.monotonic_ms}
    return $proof.version-ceq'ar-independent-streams-1.0.0'-and$proof.snapshot_path-and$proof.events_path-and
        $proof.snapshot_sha256-match'^[0-9a-f]{64}$'-and$proof.events_sha256-match'^[0-9a-f]{64}$'-and
        $proof.anchor_snapshot_id-ceq$e.identity.snapshot_id-and$e.identity.monotonic_ms-le$s.identity.monotonic_ms
}

function Test-ARSnapshotForVariant($Snapshot,[string]$Variant,[string]$Schema){
    # Validate every field used by this rule. Malformed unrelated process kinds
    # still fail D1, but do not erase independently valid resource observations.
    $view=$Snapshot|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $roles=if($Variant-like'primary.*'){@('player_projectile')}
        elseif($Variant-like'blackhole.*'){@('black_hole_projectile','black_hole_field')}
        elseif($Variant-like'teleport.*'-and$Variant-notlike'teleport.pickup*'){@('teleport')}
        elseif($Variant-ceq'journey.failure_restart'){@('player_projectile','enemy_projectile','black_hole_projectile','black_hole_field','teleport')}
        else{@()}
    $view.processes=@($view.processes|Where-Object{(Get-ARValue $_ 'process_type')-in$roles})
    return ($view|ConvertTo-Json -Depth 100 -Compress|Test-Json -Schema $Schema -ErrorAction SilentlyContinue)
}

function Get-ActionRoguelikeEventCoverage {
    param([object[]]$Pairs=@())
    $reasons=[Collections.Generic.List[string]]::new();$seen=@{};$sequences=@{};$last=$null;$lastBody=$null;$nonEmpty=0;$legacyEmpty=$false
    $valid=@($Pairs|Where-Object{$_ -and $_.snapshot -and $_.events})
    foreach($pair in $valid){
        $s=$pair.snapshot;$batch=$pair.events;$c=$batch.coverage;$events=@($batch.events)
        $start=[long]$c.cursor_start;$end=[long]$c.cursor_end
        if(-not(Test-ARPairCorrelation $pair)){$reasons.Add('ATOMIC_TORN_PAIR')}
        if($end-lt$start-or$c.dropped_event_count-ne0-or$c.head_watermark-ne$start-or$c.tail_watermark-ne$end-or$events.Count-ne($end-$start)){$reasons.Add('ATOMIC_EVENT_COVERAGE')}
        $body=@{coverage=$c;events=$events}|ConvertTo-Json -Depth 100 -Compress
        if($last){
            $previous=$last.events
            if($s.identity.process_token-cne$last.snapshot.identity.process_token-or$s.identity.round_id-cne$last.snapshot.identity.round_id){$reasons.Add('ATOMIC_IDENTITY_CHANGED')}
            if($s.identity.sequence-le$last.snapshot.identity.sequence-or$s.identity.monotonic_ms-lt$last.snapshot.identity.monotonic_ms){$reasons.Add('ATOMIC_SAMPLE_REPLAY')}
            if($c.stream_epoch-cne$previous.coverage.stream_epoch){$reasons.Add('ATOMIC_EVENT_EPOCH')}
            $repeated=$batch.identity.batch_id-ceq$previous.identity.batch_id
            $emptyReset=$start-eq0-and$end-eq0-and$null-eq$c.previous_batch_id
            if($repeated-and$body-cne$lastBody){$reasons.Add('ATOMIC_EVENT_BATCH_REUSED')}
            if($emptyReset-and$previous.coverage.cursor_end-eq0){
                # A legacy heartbeat proves fresh snapshots, not event coverage.
                $legacyEmpty=$true
            }elseif(-not$repeated-and$c.previous_batch_id-cne$previous.identity.batch_id){$reasons.Add('ATOMIC_EVENT_LINK')}
            if($start-gt$previous.coverage.cursor_end-or$end-lt$previous.coverage.cursor_end){$reasons.Add('ATOMIC_EVENT_GAP')}
        }
        for($i=0;$i-lt$events.Count;$i++){
            $event=$events[$i];$id=[string]$event.event_id;$seq=[long]$event.sequence;$bytes=$event|ConvertTo-Json -Depth 100 -Compress
            if($seq-ne($start+$i)){$reasons.Add('ATOMIC_EVENT_SEQUENCE')}
            if($event.monotonic_ms-gt$s.identity.monotonic_ms){$reasons.Add('ATOMIC_EVENT_FUTURE')}
            if($seen.ContainsKey($id)-and$seen[$id]-cne$bytes){$reasons.Add('ATOMIC_EVENT_ID_REUSED')}
            if($sequences.ContainsKey($seq)-and$sequences[$seq]-cne$id){$reasons.Add('ATOMIC_EVENT_SEQUENCE_REUSED')}
            $seen[$id]=$bytes;$sequences[$seq]=$id
        }
        if($events.Count){$nonEmpty++}
        $last=$pair;$lastBody=$body
    }
    if($valid.Count-lt2){$reasons.Add('ATOMIC_EVENT_CHAIN_WINDOW')}
    if($legacyEmpty){$reasons.Add('ATOMIC_EVENT_STREAM_UNAVAILABLE')}
    return [ordered]@{complete=($reasons.Count-eq0);sample_count=$valid.Count;non_empty_batch_count=$nonEmpty;unique_event_count=$seen.Count;reason_codes=@($reasons|Select-Object -Unique);event_observations_present=($nonEmpty-gt0);legacy_empty_heartbeat=$legacyEmpty}
}

function New-ARContext($Trace,[string]$Variant,[string]$SnapshotSchema,[string]$EventsSchema){
    Assert-ARHealth ($null-ne$Trace) 'ATOMIC_VARIANT_NOT_EXECUTED' "Required independent variant was not executed: $Variant"
    $status=[string](Get-ARPath $Trace 'execution.status')
    if($status-ceq'candidate_blocked'){
        Assert-ARHealth ((Get-ARPath $Trace 'execution.attribution')-ceq'candidate'-and@((Get-ARPath $Trace 'execution.evidence_paths')).Count-gt0) 'ATOMIC_BLOCKER_UNATTRIBUTED' 'Candidate-blocked setup needs direct evidence and attribution.'
        throw ('unreachable|'+[string](Get-ARPath $Trace 'execution.reason_code')+'|'+[string](Get-ARPath $Trace 'execution.detail'))
    }
    if($status-ceq'evaluator_blocked'){
        Assert-ARHealth ((Get-ARPath $Trace 'execution.attribution')-ceq'evaluator'-and@(Get-ARPath $Trace 'execution.evidence_paths').Count-gt0) 'ATOMIC_BLOCKER_UNATTRIBUTED' 'Evaluator-blocked collection needs a diagnostic receipt.'
        throw ('run_invalid|'+[string](Get-ARPath $Trace 'execution.reason_code')+'|'+[string](Get-ARPath $Trace 'execution.detail'))
    }
    Assert-ARHealth ($status-ceq'completed') 'ATOMIC_VARIANT_NOT_EXECUTED' "Variant $Variant has no completed execution."
    Assert-ARHealth ((Get-ARPath $Trace 'setup.confirmed')-eq$true) 'ATOMIC_SETUP_UNCONFIRMED' 'The evaluator did not confirm the independent setup.'
    Assert-ARHealth ((Get-ARPath $Trace 'setup.method')-in@('normal_input','state_fixture','hybrid')) 'ATOMIC_SETUP_METHOD' 'Unknown setup method.'
    Assert-ARHealth (@((Get-ActionRoguelikeAtomicProperty $Trace 'capture_paths')|Where-Object{$_}).Count-gt0) 'ATOMIC_CAPTURE_NOT_COLLECTED' 'No synchronized client capture was collected.'
    $pairs=@(Get-ActionRoguelikeAtomicProperty $Trace 'samples');Assert-ARHealth ($pairs.Count-ge2) 'ATOMIC_SAMPLE_WINDOW_INCOMPLETE' 'A before sample and a distinct after sample are required.'
    foreach($pair in $pairs){
        Assert-ARRule (Test-ARSnapshotForVariant $pair.snapshot $Variant $SnapshotSchema) 'CANDIDATE_SNAPSHOT_SCHEMA' 'The snapshot fields required by this rule do not satisfy their schema.'
        Assert-ARRule (($pair.events|ConvertTo-Json -Depth 100 -Compress|Test-Json -Schema $EventsSchema -ErrorAction SilentlyContinue)) 'CANDIDATE_EVENTS_SCHEMA' 'The public event batch does not satisfy its schema.'
    }
    $chain=Get-ActionRoguelikeEventCoverage $pairs
    # Fresh, schema-valid but unlinked empty heartbeats are a candidate
    # observation defect. Defer that disposition until collection health has
    # been verified; a missing collector or corrupt chain remains invalid.
    $collectionReasons=@($chain.reason_codes|Where-Object{$_-cne'ATOMIC_EVENT_STREAM_UNAVAILABLE'})
    if($collectionReasons.Count){throw ('run_invalid|'+$collectionReasons[0]+'|Event coverage was not established: '+($chain.reason_codes -join ', '))}
    $inputs=@(Get-ActionRoguelikeAtomicProperty $Trace 'input_receipts')
    foreach($input in $inputs){Assert-ARHealth ($input.input_dispatched-eq$true-and$input.release_verified-eq$true-and$input.attribution-ceq'evaluator'-and$input.evidence_path) 'ATOMIC_INPUT_NOT_VERIFIED' 'A candidate event is not an evaluator input receipt.'}
    $states=[Collections.Generic.List[object]]::new();$events=[Collections.Generic.List[object]]::new();$seen=@{};$last=$null;$cursor=$null;$lastBatch=$null;$epoch=$null;$round=$null;$token=$null
    foreach($pair in $pairs){
        $s=$pair.snapshot;$batch=$pair.events
        Assert-ARRule (Test-ARSnapshotForVariant $s $Variant $SnapshotSchema) 'CANDIDATE_SNAPSHOT_SCHEMA' 'The snapshot fields required by this rule do not satisfy their schema.'
        Assert-ARRule (($batch|ConvertTo-Json -Depth 100 -Compress|Test-Json -Schema $EventsSchema -ErrorAction SilentlyContinue)) 'CANDIDATE_EVENTS_SCHEMA' 'The public event batch does not satisfy its schema.'
        Assert-ARHealth (Test-ARPairCorrelation $pair) 'ATOMIC_TORN_PAIR' 'Snapshot/event correlation is unbound.'
        if($null-eq$last){$token=$s.identity.process_token;$round=$s.identity.round_id;$epoch=$batch.coverage.stream_epoch;$cursor=[long]$batch.coverage.cursor_start}
        Assert-ARHealth ($s.identity.process_token-ceq$token-and$s.identity.round_id-ceq$round) 'ATOMIC_IDENTITY_CHANGED' 'One atomic trace cannot mix processes or rounds.'
        if($last){Assert-ARHealth ($s.identity.sequence-gt$last.identity.sequence-and$s.identity.monotonic_ms-ge$last.identity.monotonic_ms) 'ATOMIC_SAMPLE_REPLAY' 'Samples are replayed, unordered, or not distinct.'}
        Assert-ARHealth ($batch.coverage.dropped_event_count-eq0-and$batch.coverage.stream_epoch-ceq$epoch-and$batch.coverage.head_watermark-eq$batch.coverage.cursor_start-and$batch.coverage.tail_watermark-eq$batch.coverage.cursor_end) 'ATOMIC_EVENT_COVERAGE' 'Lossless event coverage is unavailable.'
        $batchEvents=@($batch.events);Assert-ARHealth ($batchEvents.Count-eq($batch.coverage.cursor_end-$batch.coverage.cursor_start)) 'ATOMIC_EVENT_COVERAGE' 'Event count differs from the declared half-open cursor range.'
        # Repeated cumulative batches are accepted only when every duplicate ID
        # retains identical bytes; they never inflate cardinality assertions.
        Assert-ARHealth ($batch.coverage.cursor_start-le$cursor-and$batch.coverage.cursor_end-ge$cursor) 'ATOMIC_EVENT_GAP' 'The evaluator did not retain the entire event stream.'
        $seq=[long]$batch.coverage.cursor_start
        foreach($event in $batchEvents){
            Assert-ARHealth ($event.sequence-eq$seq) 'ATOMIC_EVENT_SEQUENCE' 'An event is missing or unordered.';$seq++
            Assert-ARHealth ($event.monotonic_ms-le$s.identity.monotonic_ms) 'ATOMIC_EVENT_FUTURE' 'An event occurs after its correlated snapshot.'
            Assert-ARRule ($event.observation.trust-in@('verified','corroborated')) 'CANDIDATE_EVENT_UNRELIABLE' 'The gameplay event is not observable.'
            $serialized=$event|ConvertTo-Json -Depth 50 -Compress
            if($seen.ContainsKey($event.event_id)){Assert-ARHealth ($seen[$event.event_id]-ceq$serialized) 'ATOMIC_EVENT_ID_REUSED' 'An event ID was reused with different content.'}
            else{$seen[$event.event_id]=$serialized;$events.Add($event)}
        }
        $cursor=[long]$batch.coverage.cursor_end;$lastBatch=$batch.identity.batch_id;$last=$s;$states.Add($s)
    }
    foreach($identityName in @('before_identity','after_identity')){$identity=Get-ARPath $Trace ('setup.'+$identityName);Assert-ARHealth ($null-ne$identity-and$identity.process_token-ceq$token-and$identity.round_id-ceq$round) 'ATOMIC_SETUP_IDENTITY' 'Setup receipt is not bound to this independent trace.'}
    Assert-ARCleanup $Trace $token $round
    foreach($input in $inputs){
        $upper=[long]$states[-1].identity.monotonic_ms
        # An immediate Restart can replace the world before another old-round
        # snapshot. Its real dispatch is bounded by the first NEW-round sample.
        $restartSamples=@(Get-ARPath $Trace 'setup.restart_result.samples')
        if($input.semantic_action-ceq'restart'-and$restartSamples.Count-and$restartSamples[0]){$upper=[long]$restartSamples[0].snapshot.identity.monotonic_ms}
        Assert-ARHealth ($input.process_token-ceq$token-and$input.round_id-ceq$round-and$input.monotonic_ms-ge$states[0].identity.monotonic_ms-and$input.monotonic_ms-le$upper) 'ATOMIC_INPUT_IDENTITY' 'Input receipt is outside the trace identity/time window.'
    }
    if(-not$chain.complete){
        $contract=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../contracts/atomic-check-contract.json') -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable -Depth 100
        $spec=$contract.variants[$Variant]
        Assert-ARHealth ($null-ne$spec-and$inputs.Count-ge$spec.minimum_actions) 'ATOMIC_TRIGGER_NOT_EXECUTED' 'The evaluator did not collect the required trigger inputs.'
        Assert-ARRule $false 'CANDIDATE_EVENT_STREAM_UNAVAILABLE' 'Fresh candidate snapshots contain only unlinked empty event heartbeats; event occurrence or absence cannot be established.'
    }
    $observedEvents=@($events|Where-Object{$_.monotonic_ms-ge$states[0].identity.monotonic_ms}|Sort-Object sequence)
    return @{trace=$Trace;variant=$Variant;before=$states[0];after=$states[-1];states=@($states);events=$observedEvents;inputs=$inputs;round=$round;token=$token;start=[long]$states[0].identity.monotonic_ms;end=[long]$states[-1].identity.monotonic_ms;event_chain_verified=$true}
}

function Assert-ARAction($Context,[string]$Action,[int]$Minimum=1){Assert-ARHealth (@(Get-ARInput $Context $Action).Count-ge$Minimum) 'ATOMIC_TRIGGER_NOT_EXECUTED' "The evaluator did not execute $Minimum $Action actions."}
function Assert-ARWindow($Context,[int]$Milliseconds){Assert-ARHealth (($Context.end-$Context.start)-ge$Milliseconds) 'ATOMIC_OBSERVATION_WINDOW_SHORT' "The evaluator observed less than $Milliseconds ms."}
function Assert-ARNoUnrelatedHealthChange($Context,[string]$EnemyId){
    Assert-ARUnchanged $Context @('player.health')
    foreach($enemy in $Context.before.enemies){$id=Get-AREntityId $enemy;if($id-ceq$EnemyId){continue};$health=Get-ARValue $enemy 'health';foreach($s in $Context.states){$same=@($s.enemies|Where-Object{(Get-AREntityId $_)-ceq$id});Assert-ARRule ($same.Count-eq1-and(Get-ARValue $same[0] 'health')-eq$health) 'PROJECTILE_WRONG_TARGET' 'An unrelated entity was damaged.'}}
}
function Assert-ARProjectile($Context,[string]$Mode){
    Assert-ARAction $Context 'primary_attack'
    $spawns=@(Get-AREvents $Context 'projectile_spawned' 'player_projectile');$shots=@(Get-ARInput $Context 'primary_attack')
    $expected=if($Mode-ceq'repeat_reuse'){2}else{1}
    Assert-ARRule ($spawns.Count-eq$expected) 'PROJECTILE_CARDINALITY' "Expected $expected independent projectile(s), observed $($spawns.Count)."
    $ids=@($spawns|ForEach-Object{Get-AREventEntity $_ 'player_projectile'});Assert-ARRule (@($ids|Select-Object -Unique).Count-eq$ids.Count) 'PROJECTILE_ID_REUSED' 'A new projectile reused an old entity identity.'
    foreach($spawn in $spawns){$projectileEntityId=Get-AREventEntity $spawn 'player_projectile';$active=@($Context.states|ForEach-Object{Get-ARProcesses $_ 'player_projectile'}|Where-Object{(Get-AREntityId $_)-ceq$projectileEntityId});Assert-ARRule ($active.Count-gt0) 'PROJECTILE_FLIGHT_MISSING' 'A magic projectile has no sampled flight.'}
    if($Mode-ceq'repeat_reuse'){
        Assert-ARAction $Context 'primary_attack' 3
        $starts=@($Context.events|Where-Object{$_.event_type-ceq'action_started'-and$_.payload.action-ceq'primary_cast'});$ends=@($Context.events|Where-Object{$_.event_type-ceq'action_ended'-and$_.payload.action-ceq'primary_cast'})
        Assert-ARRule ($starts.Count-eq2-and$ends.Count-eq2) 'PRIMARY_ACTION_CARDINALITY' 'Repeated input overlapped actions or reuse failed.'
        for($i=0;$i-lt2;$i++){Assert-ARRule ($ends[$i].monotonic_ms-ge$starts[$i].monotonic_ms-and($ends[$i].monotonic_ms-$starts[$i].monotonic_ms)-le1000) 'PRIMARY_ACTION_LIFETIME' 'The primary firing action did not end within one second.'}
        Assert-ARHealth ($shots[1].monotonic_ms-gt$starts[0].monotonic_ms-and$shots[1].monotonic_ms-lt$ends[0].monotonic_ms-and$shots[-1].monotonic_ms-gt$ends[0].monotonic_ms) 'ATOMIC_REPEAT_NOT_IN_FLIGHT' 'Repeat input must occur during the first action and reuse after it ends.'
        Assert-ARRule ($starts[1].monotonic_ms-ge$ends[0].monotonic_ms-and$spawns[1].monotonic_ms-ge$shots[-1].monotonic_ms) 'PRIMARY_ACTION_OVERLAP' 'Repeated input generated an overlapping projectile.'
        return
    }
    $projectileId=$ids[0];$contacts=@(Get-AREvents $Context 'contact' 'player_projectile' $projectileId);$damage=@(Get-AREvents $Context 'damage' 'player_projectile' $projectileId)
    if($Mode-ceq'hit'){
        Assert-ARRule ($contacts.Count-ge1) 'PROJECTILE_CONTACT_MISSING' 'The first enemy contact was not observed.'
        $target=Get-AREventEntity $contacts[0] 'enemy';Assert-ARRule ([bool]$target) 'PROJECTILE_FIRST_CONTACT_ROLE' 'The hit case did not first contact a living enemy.'
        Assert-ARRule ($damage.Count-eq1-and(Get-AREventEntity $damage[0] 'enemy')-ceq$target-and[double]$damage[0].payload.amount-eq20) 'PROJECTILE_SINGLE_DAMAGE' 'The projectile must cause exactly one 20-point damage event to its first enemy target.'
        $enemyBefore=@($Context.before.enemies|Where-Object{(Get-AREntityId $_)-ceq$target});$enemyAfter=@($Context.after.enemies|Where-Object{(Get-AREntityId $_)-ceq$target})
        Assert-ARHealth ($enemyBefore.Count-eq1-and(Get-ARValue $enemyBefore[0] 'health')-gt20) 'ATOMIC_DAMAGE_SETUP' 'Damage measurement needs a surviving enemy with more than 20 Health.'
        Assert-ARRule ($enemyAfter.Count-eq1-and((Get-ARValue $enemyBefore[0] 'health')-(Get-ARValue $enemyAfter[0] 'health'))-eq20) 'PROJECTILE_HEALTH_DELTA' 'The target Health delta differs from the 20-point hit.'
        Assert-ARNoUnrelatedHealthChange $Context $target
    }elseif($Mode-in@('obstacle','miss')){
        Assert-ARNoDamage $Context
        if($Mode-ceq'obstacle'){Assert-ARRule ($contacts.Count-ge1-and$null-ne(Get-AREventEntity $contacts[0] 'static_world')) 'PROJECTILE_OBSTACLE_CONTACT' 'The first obstacle contact was not observed.'}
    }elseif($Mode-ceq'latest_direction'){Assert-ARDirectionChange $Context;Assert-ARAiming $Context 'player_projectile' $projectileId;return}
    $ends=@(Get-AREvents $Context 'entity_removed' 'player_projectile' $projectileId)
    Assert-ARRule ($ends.Count-eq1) 'PROJECTILE_TERMINATION' 'The projectile must terminate exactly once.'
    if($contacts.Count){Assert-ARRule ($ends[0].monotonic_ms-ge$contacts[0].monotonic_ms) 'PROJECTILE_CONTACT_ORDER' 'Projectile removal preceded its first contact.';Assert-ARRule (@($damage|Where-Object{$_.monotonic_ms-gt$ends[0].monotonic_ms}).Count-eq0) 'PROJECTILE_POST_CONTACT_DAMAGE' 'The projectile dealt damage after termination.'}
    foreach($s in @($Context.states|Where-Object{$_.identity.monotonic_ms-gt$ends[0].monotonic_ms})){$remaining=@(Get-ARProcesses $s 'player_projectile'|Where-Object{(Get-AREntityId $_)-ceq$projectileId-and(Get-ARValue $_ 'phase')-in@('started','active')});Assert-ARRule ($remaining.Count-eq0) 'PROJECTILE_THROUGH_CONTACT' 'The projectile remained active after its first contact.'}
}

function Assert-ARAiming($Context,[string]$Type,[string]$EntityId){
    $aim=Get-ARValue $Context.before 'player.facing'
    $nativeAim=Get-ARPath $Context.trace 'setup.native_aim'
    if($null-ne$nativeAim){
        # Public facing can describe the upright character's yaw. A fixture
        # with explicit pitch binds the expected 3D aim to engine readback.
        Assert-ARHealth ((Get-ARPath $nativeAim 'confirmed')-eq$true-and[bool](Get-ARPath $nativeAim 'receipt_path')) 'ATOMIC_AIM_PRECONDITION_UNVERIFIED' 'Explicit fixture aim requires its native readback receipt.'
        $aim=Get-ARPath $nativeAim 'direction'
    }
    $positions=@($Context.states|ForEach-Object{Get-ARProcesses $_ $Type}|Where-Object{(Get-AREntityId $_)-ceq$EntityId}|ForEach-Object{Get-ARValue $_ 'position_m'})
    Assert-ARHealth ($positions.Count-ge2) 'ATOMIC_FLIGHT_WINDOW_MISSING' 'At least two flight positions are needed to check the latest aim.'
    $a=$positions[0];$b=$positions[-1];$dot=0.0;$length=0.0;$aimLength=0.0
    foreach($axis in @('x','y','z')){$delta=[double]$b.$axis-[double]$a.$axis;$dot+=$delta*[double]$aim.$axis;$length+=$delta*$delta;$aimLength+=[Math]::Pow([double]$aim.$axis,2)}
    Assert-ARRule ($length-gt0-and$aimLength-gt0-and$dot-gt0-and([Math]::Abs(1-$dot/[Math]::Sqrt($length*$aimLength)))-lt0.01) 'ABILITY_STALE_DIRECTION' 'The flight direction differs from the current observed aim.'
}

function Assert-ARPickup($Context,[switch]$Strict,[switch]$Repeat){
    Assert-ARAction $Context 'move_toward'
    $before=Get-ARBoundObject $Context.before $Context.trace 'teleport_pickup';$id=Get-AREntityId $before
    Assert-ARHealth ((Get-ARValue $before 'available')-eq$true-and(Get-ARValue $Context.before 'player.teleport_acquired')-eq$false) 'ATOMIC_PICKUP_PRECONDITION' 'Teleport pickup case must start unacquired with an available item.'
    $acquisition=@(Get-AREvents $Context 'ability_acquired' 'teleport_pickup' $id)
    if(-not$acquisition.Count){
        # The public event permits a player subject and no object reference.
        # Bind that sparse form to the observed transition of the setup target.
        $changed=@($Context.states|Where-Object{(Get-ARValue $_ 'player.teleport_acquired')-eq$true}|Select-Object -First 1)
        if($changed.Count-and(Get-ARValue (Get-ARBoundObject $changed[0] $Context.trace 'teleport_pickup') 'available')-eq$false){
            $prior=@($Context.states|Where-Object{$_.identity.monotonic_ms-lt$changed[0].identity.monotonic_ms-and(Get-ARValue $_ 'player.teleport_acquired')-eq$false}|Select-Object -Last 1)
            if($prior.Count){
                $playerEvents=@(Get-AREvents $Context 'ability_acquired' 'player' (Get-AREntityId $Context.before.player)|Where-Object{$null-eq$_.object-and(Get-ARPath $_ 'payload.successful')-ne$false-and$_.monotonic_ms-ge$Context.start})
                if($playerEvents.Count-gt1-or($playerEvents.Count-eq1-and$playerEvents[0].monotonic_ms-gt$prior[0].identity.monotonic_ms-and$playerEvents[0].monotonic_ms-le$changed[0].identity.monotonic_ms)){$acquisition=$playerEvents}
            }
        }
    }
    Assert-ARRule ($acquisition.Count-eq1-and(Get-ARValue $Context.after 'player.teleport_acquired')-eq$true) 'TELEPORT_ACQUISITION' 'Normal contact must acquire the ability exactly once.'
    $after=Get-ARBoundObject $Context.after $Context.trace 'teleport_pickup';Assert-ARRule ((Get-ARValue $after 'available')-eq$false) 'TELEPORT_PICKUP_CONSUMPTION' 'The acquired pickup must become unavailable.'
    if($Repeat){Assert-ARAction $Context 'move_toward' 2;Assert-ARHealth ((Get-ARInput $Context 'move_toward')[-1].monotonic_ms-gt$acquisition[0].monotonic_ms) 'ATOMIC_PICKUP_REPEAT_NOT_EXECUTED' 'Repeated contact must be after acquisition.'}
}

function Assert-ARTeleport($Context,[string]$Mode,[switch]$ContentOnly){
    Assert-ARAction $Context 'teleport' $(if($Mode-in@('locked','repeat_reuse')){2}else{1})
    $started=@($Context.events|Where-Object{$_.event_type-ceq'ability_started'-and(Get-ARPath $_ 'payload.process_type')-ceq'teleport'-and$null-ne(Get-AREventEntity $_ 'teleport_process')})
    if($Mode-ceq'locked'){
        Assert-ARHealth ((Get-ARValue $Context.before 'player.teleport_acquired')-eq$false) 'ATOMIC_TELEPORT_LOCK_SETUP' 'The locked case must start without the ability.'
        Assert-ARWindow $Context 500;Assert-ARRule ($started.Count-eq0) 'TELEPORT_UNLOCK_BYPASS' 'The unacquired ability launched a process.';Assert-ARUnchanged $Context @('player.position_m','player.teleport_acquired');return
    }
    Assert-ARHealth ((Get-ARValue $Context.before 'player.teleport_acquired')-eq$true) 'ATOMIC_TELEPORT_SETUP' 'A legal/illegal teleport variant must start acquired.'
    $expected=if($Mode-ceq'repeat_reuse'){2}else{1};Assert-ARRule ($started.Count-eq$expected) 'TELEPORT_PROCESS_CARDINALITY' "Expected $expected independent teleport process(es)."
    $firstId=Get-AREventEntity $started[0] 'teleport_process'
    if($Mode-ceq'latest_direction'){Assert-ARDirectionChange $Context;Assert-ARAiming $Context 'teleport' $firstId;return}
    foreach($start in $started){
        $id=Get-AREventEntity $start 'teleport_process';$stages=@($Context.states|ForEach-Object{$s=$_;Get-ARProcesses $s 'teleport'|Where-Object{(Get-AREntityId $_)-ceq$id}|ForEach-Object{@{state=$s;process=$_}}})
        $end=@(Get-AREvents $Context 'ability_ended' 'teleport_process' $id);Assert-ARRule ($end.Count-eq1) 'TELEPORT_END_CARDINALITY' 'The process must terminate once.'
        if($Mode-ceq'invalid'){
            Assert-ARHealth ((Get-ARPath $Context.trace 'setup.endpoint_class')-ceq'illegal') 'ATOMIC_ILLEGAL_ENDPOINT_NOT_CONFIRMED' 'A blocked endpoint must be independently established.'
            Assert-ARRule (($end[0].monotonic_ms-$start.monotonic_ms)-ge150-and($end[0].monotonic_ms-$start.monotonic_ms)-le250-and(Get-ARPath $end[0] 'payload.successful')-ne$true) 'TELEPORT_ILLEGAL_END' 'An illegal attempt must end at the 0.2-second resolution boundary.'
            Assert-ARUnchanged $Context @('player.position_m');foreach($stage in $stages){$target=Get-ActionRoguelikeAtomicProperty $stage.process 'target_position_m';Assert-ARRule ($null-eq$target-or$target.trust-in@('unavailable','unreliable')) 'TELEPORT_FALSE_ENDPOINT' 'An invalid attempt exposed a valid destination.'};continue
        }
        Assert-ARHealth ((Get-ARPath $Context.trace 'setup.endpoint_class')-ceq'legal') 'ATOMIC_LEGAL_ENDPOINT_NOT_CONFIRMED' 'Open legal ground must be independently established.'
        $targets=@($stages|Where-Object{$null-ne(Get-ActionRoguelikeAtomicProperty $_.process 'target_position_m')-and$_.process.target_position_m.trust-in@('verified','corroborated')})
        Assert-ARRule ($targets.Count-gt0) 'TELEPORT_DESTINATION_MISSING' 'The process never indicated a valid destination.'
        $target=Get-ARValue $targets[0].process 'target_position_m';$targetTime=[long]$targets[0].state.identity.monotonic_ms
        $resolution=@($Context.events|Where-Object{(Get-ARPath $_ 'payload.phase')-ceq'resolved'-and$id-cin@([string](Get-ARPath $_ 'subject.entity_id'),[string](Get-ARPath $_ 'object.entity_id'))})
        if($resolution.Count){$targetTime=[long]$resolution[0].monotonic_ms}
        if(-not$ContentOnly){Assert-ARRule (($targetTime-$start.monotonic_ms)-ge150-and($targetTime-$start.monotonic_ms)-le250) 'TELEPORT_TARGET_TIMING' 'Destination determination must occur after 0.2 ± 0.05 seconds.';Assert-ARRule (($end[0].monotonic_ms-$targetTime)-ge150-and($end[0].monotonic_ms-$targetTime)-le250) 'TELEPORT_COMMIT_TIMING' 'Commit must wait another 0.2 ± 0.05 seconds.'}
        foreach($stage in $targets){Assert-ARRule ((Get-ARDistance (Get-ARValue $stage.process 'target_position_m') $target)-lt0.0001) 'TELEPORT_ENDPOINT_CHANGED' 'The chosen endpoint changed after lock.'}
        $beforeStates=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$start.monotonic_ms-and$_.identity.monotonic_ms-lt$end[0].monotonic_ms});$origin=Get-ARValue $beforeStates[0] 'player.position_m'
        foreach($state in $beforeStates){Assert-ARRule ((Get-ARDistance (Get-ARValue $state 'player.position_m') $origin)-lt0.0001) 'TELEPORT_EARLY_COMMIT' 'The player moved before the commit boundary.'}
        $committed=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$end[0].monotonic_ms})
        $atCommit=Get-ARPath $end[0] 'payload.position_m'
        $landed=if($committed.Count){Get-ARValue $committed[0] 'player.position_m'}else{$null}
        # A later snapshot can include CharacterMovement's floor correction.
        # Prefer the complete position captured at the actual commit, then
        # corroborate its horizontal destination and grounded state after it.
        $matches=$committed.Count-gt0-and(Get-ARDistance $landed $target)-lt0.0001
        if(-not$matches-and$atCommit-and$landed){$matches=(Get-ARDistance $atCommit $target)-lt0.0001-and[Math]::Abs($landed.x-$target.x)-lt0.0001-and[Math]::Abs($landed.y-$target.y)-lt0.0001-and(Get-ARValue $committed[0] 'player.ground_state')-ceq'grounded'}
        Assert-ARRule ($matches-and(Get-ARDistance $origin $target)-gt0.0001) 'TELEPORT_DESTINATION_MISMATCH' 'The player did not reach the indicated distinct destination.'
        # A missing optional success flag is corroborated by the exact locked
        # destination and pre/post positions above. Explicit false still fails.
        $commits=@($Context.events|Where-Object{$_.event_type-ceq'ability_ended'-and$id-cin@([string](Get-ARPath $_ 'subject.entity_id'),[string](Get-ARPath $_ 'object.entity_id'))-and(Get-ARPath $_ 'payload.successful')-ne$false});Assert-ARRule ($commits.Count-eq1) 'TELEPORT_DUPLICATE_COMMIT' 'The process must commit exactly once.'
    }
    Assert-ARNoDamage $Context
    if($Mode-ceq'repeat_reuse'){
        Assert-ARAction $Context 'teleport' 3;$inputs=@(Get-ARInput $Context 'teleport');$endFirst=@(Get-AREvents $Context 'ability_ended' 'teleport_process' $firstId)[0]
        Assert-ARHealth ($inputs[1].monotonic_ms-gt$started[0].monotonic_ms-and$inputs[1].monotonic_ms-lt$endFirst.monotonic_ms-and$inputs[-1].monotonic_ms-gt$endFirst.monotonic_ms) 'ATOMIC_TELEPORT_REPEAT_TIMING' 'Repeat must occur during the first process and reuse after its end.'
        Assert-ARRule ($started[1].monotonic_ms-ge$inputs[-1].monotonic_ms) 'TELEPORT_OVERLAP' 'An in-process repeat launched another teleport.'
    }
}

function Assert-ARResource($Context,[string]$Mode,[switch]$ContentOnly){
    if($Mode-ceq'initial'){Assert-ARRule ((Get-ARValue $Context.before 'player.credits')-eq0) 'INITIAL_CREDITS' 'A fresh round must begin with zero Credits.';return}
    $pickup=$Mode-in@('pickup','pickup_recovery');$type=if($pickup){'credits_pickup'}else{'potion'};$object=Get-ARBoundObject $Context.before $Context.trace $type;$id=Get-AREntityId $object
    Assert-ARHealth ((Get-ARValue $object 'available')-eq$true) 'ATOMIC_RESOURCE_SETUP' 'The independent object must be available before the action.'
    Assert-ARAction $Context $(if($pickup){'move_toward'}else{'interact'})
    $c0=Get-ARValue $Context.before 'player.credits';$h0=Get-ARValue $Context.before 'player.health';$max=Get-ARValue $Context.before 'player.health_max';$c1=Get-ARValue $Context.after 'player.credits';$h1=Get-ARValue $Context.after 'player.health'
    if($Mode-in@('reject_full','reject_poor')){
        Assert-ARAction $Context 'interact' 2
        Assert-ARHealth ($(if($Mode-ceq'reject_full'){$h0-eq$max}else{$h0-lt$max-and$c0-lt50})) 'ATOMIC_REJECTION_SETUP' 'The rejection boundary precondition is not satisfied.'
        Assert-ARUnchanged $Context @('player.health','player.credits');foreach($state in $Context.states){Assert-ARRule ((Get-ARValue (Get-ARBoundObject $state $Context.trace 'potion') 'available')-eq$true) 'REJECTED_POTION_CONSUMED' 'A rejected interaction consumed the potion.'}
        Assert-ARRule (@(Get-AREvents $Context 'payment').Count-eq0-and@(Get-AREvents $Context 'healing').Count-eq0) 'REJECTED_POTION_SIDE_EFFECT' 'A rejected interaction charged or healed.';return
    }
    if($pickup){
        $awards=@(Get-AREvents $Context 'pickup' 'credits_pickup' $id)
        Assert-ARRule ($awards.Count-eq1-and$c1-gt$c0) 'CREDITS_PICKUP' 'Normal contact must award Credits once.'
        $amount=Get-ARPath $awards[0] 'payload.amount'
        if(-not$ContentOnly){Assert-ARRule (($c1-$c0)-eq80-and($null-eq$amount-or[double]$amount-eq80)) 'CREDITS_AWARD_AMOUNT' 'One pickup must award exactly 80 Credits.'}
        $origin=$awards[0].monotonic_ms;$duration=10000
    }else{
        Assert-ARHealth ($h0-gt0-and$h0-lt$max-and$c0-ge50) 'ATOMIC_HEAL_SETUP' 'Paid healing needs positive damaged Health and at least 50 Credits.'
        if($Mode-ceq'heal_exact50'){Assert-ARHealth ($c0-eq50) 'ATOMIC_EXACT50_SETUP' 'The boundary case must start with exactly 50 Credits.'}
        $payments=@(Get-AREvents $Context 'payment' 'potion' $id);$heals=@(Get-AREvents $Context 'healing' 'potion' $id)
        if(-not$payments.Count-and$c1-lt$c0-and$h1-gt$h0){
            $changed=@($Context.states|Where-Object{(Get-ARValue $_ 'player.credits')-lt$c0-and(Get-ARValue $_ 'player.health')-gt$h0}|Select-Object -First 1)
            if($changed.Count-and(Get-ARValue (Get-ARBoundObject $changed[0] $Context.trace 'potion') 'available')-eq$false){
                $prior=@($Context.states|Where-Object{$_.identity.monotonic_ms-lt$changed[0].identity.monotonic_ms-and(Get-ARValue $_ 'player.credits')-eq$c0}|Select-Object -Last 1)
                if($prior.Count){$payments=@(Get-AREvents $Context 'resource_changed' 'player' (Get-AREntityId $Context.before.player)|Where-Object{$null-eq$_.object-and(Get-ARPath $_ 'payload.resource')-ceq'credits'-and(Get-ARPath $_ 'payload.value_after')-eq$c1-and$_.monotonic_ms-gt$prior[0].identity.monotonic_ms-and$_.monotonic_ms-le$changed[0].identity.monotonic_ms})}
            }
        }
        if(-not$heals.Count-and$payments.Count-eq1){
            # Some publishers identify the healed player rather than the item.
            # Accept only one payment and one player healing, ordered together,
            # with independently observed credit/health changes below.
            $heals=@(Get-AREvents $Context 'healing' 'player' (Get-AREntityId $Context.before.player)|Where-Object{$_.monotonic_ms-ge$payments[0].monotonic_ms})
            # One action event plus its health-value publication is one heal;
            # multiple action events or conflicting values remain failures.
            $actions=@($heals|Where-Object{(Get-ARPath $_ 'payload.successful')-eq$true-and$null-eq(Get-ARPath $_ 'payload.resource')})
            $updates=@($heals|Where-Object{(Get-ARPath $_ 'payload.resource')-ceq'health'-and(Get-ARPath $_ 'payload.value_after')-eq$h1})
            if($heals.Count-eq2-and$actions.Count-eq1-and$updates.Count-eq1-and$actions[0].monotonic_ms-eq$updates[0].monotonic_ms){$heals=$actions}
        }
        Assert-ARRule ($payments.Count-eq1-and$heals.Count-eq1-and$c1-lt$c0-and$h1-gt$h0) 'PAID_HEAL_BASIC' 'One normal interaction must pay and heal once.'
        $amount=Get-ARPath $payments[0] 'payload.amount'
        if(-not$ContentOnly){Assert-ARRule (($c0-$c1)-eq50-and($null-eq$amount-or[Math]::Abs([double]$amount)-eq50)-and$h1-eq$max) 'PAID_HEAL_AMOUNT' 'One potion must deduct 50 Credits and restore maximum Health.'}
        Assert-ARRule ($payments[0].monotonic_ms-le$heals[0].monotonic_ms) 'HEAL_BEFORE_PAYMENT' 'Healing preceded its payment.';$origin=$heals[0].monotonic_ms;$duration=4000
    }
    $availability=@(Get-AREvents $Context 'availability_changed' $type $id|ForEach-Object{
        $value=Get-ARPath $_ 'payload.available'
        if($null-eq$value){
            # Resolve by this event's clock, not a nested pipeline variable.
            $clock=$_.monotonic_ms;$at=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$clock}|Select-Object -First 1)
            if($at.Count){$value=Get-ARValue (Get-ARBoundObject $at[0] $Context.trace $type) 'available'}
        }
        @{monotonic_ms=$_.monotonic_ms;payload=@{available=$value};source_event_id=$_.event_id}
    })
    if(-not@($availability|Where-Object{$_.payload.available-eq$false}).Count){
        $afterUse=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$origin}|Select-Object -First 1)
        if($afterUse.Count-and(Get-ARValue (Get-ARBoundObject $afterUse[0] $Context.trace $type) 'available')-eq$false){
            $availability+=@(@{monotonic_ms=$origin;payload=@{available=$false};derived_from='successful_use_event_and_first_correlated_snapshot'})
        }
    }
    $inactive=@($availability|Where-Object{$_.payload.available-eq$false});Assert-ARRule ($inactive.Count-eq1) 'RESOURCE_NOT_INVALIDATED' 'The successfully used object must become unavailable once.'
    foreach($state in @($Context.states|Where-Object{$_.identity.monotonic_ms-ge$inactive[0].monotonic_ms-and$_.identity.monotonic_ms-lt($inactive[0].monotonic_ms+$duration)})){Assert-ARRule ((Get-ARValue (Get-ARBoundObject $state $Context.trace $type) 'available')-eq$false) 'RESOURCE_RECOVERED_EARLY' 'The object became available before its recovery deadline.'}
    if($Mode-in@('pickup_recovery','heal_exact50')){
        Assert-ARAction $Context $(if($pickup){'move_toward'}else{'interact'}) 2
        $again=@(Get-ARInput $Context $(if($pickup){'move_toward'}else{'interact'}))[-1]
        Assert-ARHealth ($again.monotonic_ms-gt$inactive[0].monotonic_ms-and$again.monotonic_ms-lt($inactive[0].monotonic_ms+$duration)) 'ATOMIC_RESOURCE_REPEAT_TIMING' 'The repeated action must occur while the object is unavailable.'
        Assert-ARHealth ($Context.end-ge($inactive[0].monotonic_ms+$duration)) 'ATOMIC_RECOVERY_WINDOW_SHORT' 'The evaluator stopped before the recovery deadline.'
        $recovery=@($availability|Where-Object{$_.payload.available-eq$true})
        if(-not$recovery.Count){
            $observed=@($Context.states|Where-Object{$_.identity.monotonic_ms-gt$origin-and(Get-ARValue (Get-ARBoundObject $_ $Context.trace $type) 'available')-eq$true}|Select-Object -First 1)
            if($observed.Count){$recovery=@(@{monotonic_ms=$observed[0].identity.monotonic_ms;derived_from='first_correlated_available_snapshot'})}
        }
        $deadline=$inactive[0].monotonic_ms+$duration
        $firstDue=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$deadline}|Select-Object -First 1)
        # The public timer expires on an engine update, not an exact host-clock
        # millisecond. Require no early event and recovery by the first sampled
        # update at/after the deadline; do not invent a fixed grace interval.
        Assert-ARRule ($recovery.Count-eq1-and$recovery[0].monotonic_ms-ge$deadline-and$firstDue.Count-eq1-and$recovery[0].monotonic_ms-le$firstDue[0].identity.monotonic_ms-and(Get-ARValue (Get-ARBoundObject $firstDue[0] $Context.trace $type) 'available')-eq$true) 'RESOURCE_RECOVERY_TIMING' "Recovery must be visible at the first sampled update after $duration ms, never earlier."
        Assert-ARRule ((Get-ARValue (Get-ARBoundObject $Context.after $Context.trace $type) 'available')-eq$true) 'RESOURCE_DID_NOT_RECOVER' 'The object never returned to availability.'
    }
}

function Assert-ARBlackHole($Context,[string]$Mode){
    $expected=if($Mode-ceq'multiple'){2}else{1};Assert-ARAction $Context 'black_hole' $expected
    $spawns=@(Get-AREvents $Context 'projectile_spawned' 'black_hole_projectile');Assert-ARRule ($spawns.Count-eq$expected) 'BLACK_HOLE_PROJECTILE_CARDINALITY' 'Each available input must launch one Black Hole projectile.'
    $fields=@($Context.events|Where-Object{$_.event_type-ceq'ability_started'-and((Get-ARPath $_ 'payload.process_type')-ceq'black_hole_field'-or$null-ne(Get-AREventEntity $_ 'black_hole_field'))});Assert-ARRule ($fields.Count-eq$expected) 'BLACK_HOLE_FIELD_CARDINALITY' 'Each projectile must form one independent field.'
    foreach($spawn in $spawns){$projectileEntityId=Get-AREventEntity $spawn 'black_hole_projectile';Assert-ARRule ([bool]$projectileEntityId) 'BLACK_HOLE_PROJECTILE_ID' 'Projectile identity is missing.';Assert-ARAiming $Context 'black_hole_projectile' $projectileEntityId}
    $fieldIds=@($fields|ForEach-Object{Get-AREventEntity $_ 'black_hole_field'});Assert-ARRule (@($fieldIds|Select-Object -Unique).Count-eq$expected) 'BLACK_HOLE_FIELD_ID_REUSED' 'Independent fields reused an identity.'
    foreach($field in $fields){
        $fid=Get-AREventEntity $field 'black_hole_field';$flight=Get-AREventEntity $field 'black_hole_projectile'
        # A process may retain its opaque identity while its semantic role
        # changes from projectile to field. Both published layouts are valid.
        if(-not$flight){$flight=$fid}
        $spawn=@($spawns|Where-Object{(Get-AREventEntity $_ 'black_hole_projectile')-ceq$flight});Assert-ARRule ($spawn.Count-eq1-and($field.monotonic_ms-$spawn[0].monotonic_ms)-ge0-and($field.monotonic_ms-$spawn[0].monotonic_ms)-le1000) 'BLACK_HOLE_ARRIVAL' 'The linked projectile must arrive within one second.'
        $end=@(Get-AREvents $Context 'ability_ended' 'black_hole_field' $fid);Assert-ARRule ($end.Count-eq1-and($end[0].monotonic_ms-$field.monotonic_ms)-ge4600-and($end[0].monotonic_ms-$field.monotonic_ms)-le5000) 'BLACK_HOLE_LIFETIME' 'Each field must last 4.8 ± 0.2 seconds.'
        Assert-ARHealth ($Context.end-gt$end[0].monotonic_ms) 'ATOMIC_BLACK_HOLE_POST_END_WINDOW' 'The evaluator did not observe after field expiry.'
        $samples=@($Context.states|ForEach-Object{$s=$_;Get-ARProcesses $s 'black_hole_field'|Where-Object{(Get-AREntityId $_)-ceq$fid}|ForEach-Object{@{state=$s;process=$_}}});Assert-ARRule ($samples.Count-ge2) 'BLACK_HOLE_FIELD_NOT_OBSERVED' 'Field formation and persistence need distinct samples.'
        # Only field-originated contacts describe attraction. Another projectile
        # may hit the field without the field acting on that projectile.
        $contacts=@(Get-AREvents $Context 'contact' 'black_hole_field' $fid|Where-Object{(Get-ARPath $_ 'subject.role')-ceq'black_hole_field'-and(Get-ARPath $_ 'subject.entity_id')-ceq$fid})
        foreach($contact in $contacts){Assert-ARRule ($null-ne(Get-AREventEntity $contact 'physics_prop')) 'BLACK_HOLE_INVALID_TARGET_ROLE' 'Only physics_prop may be affected; IDs are opaque and are never matched by name.';Assert-ARRule ($contact.monotonic_ms-le$end[0].monotonic_ms) 'BLACK_HOLE_POST_END_CONTACT' 'An expired field continued affecting a prop.'}
    }
    Assert-ARNoDamage $Context
    # The isolated setup freezes independent locomotion, so state deltas expose
    # forbidden attraction without interpreting candidate-specific object names.
    Assert-ARHealth ((Get-ARPath $Context.trace 'setup.isolated_motion')-eq$true) 'ATOMIC_BLACK_HOLE_MOTION_NOT_ISOLATED' 'Forbidden attraction requires a confirmed independent-motion setup.'
    Assert-ARUnchanged $Context @('player.position_m')
    foreach($enemy in $Context.before.enemies){$id=Get-AREntityId $enemy;foreach($state in $Context.states){$other=@($state.enemies|Where-Object{(Get-AREntityId $_)-ceq$id});Assert-ARRule ($other.Count-eq1-and(Get-ARDistance (Get-ARValue $enemy 'position_m') (Get-ARValue $other[0] 'position_m'))-lt0.0001) 'BLACK_HOLE_ENEMY_MOVED' 'Black Hole moved an enemy.'}}
    $removed=@(Get-AREvents $Context 'entity_removed' 'physics_prop');$removedIds=@($removed|ForEach-Object{Get-AREventEntity $_ 'physics_prop'});Assert-ARRule (@($removedIds|Select-Object -Unique).Count-eq$removedIds.Count) 'BLACK_HOLE_DUPLICATE_ABSORPTION' 'A prop was absorbed more than once.'
    if($Mode-ceq'empty'){Assert-ARHealth (@(Get-ARObjects $Context.before 'physics_prop').Count-eq0) 'ATOMIC_EMPTY_FIELD_SETUP' 'The empty-field variant contains props.';Assert-ARRule ($removed.Count-eq0) 'BLACK_HOLE_PHANTOM_ABSORPTION' 'An empty field removed an entity.';return}
    Assert-ARRule ($removed.Count-ge1) 'BLACK_HOLE_NO_ABSORPTION' 'No movable prop was absorbed.'
    foreach($removedEvent in $removed){$id=Get-AREventEntity $removedEvent 'physics_prop';$positions=@($Context.states|ForEach-Object{$s=$_;Get-ARObjects $s 'physics_prop'|Where-Object{(Get-AREntityId $_)-ceq$id}|ForEach-Object{@{state=$s;position=(Get-ARValue $_ 'position_m')}}});Assert-ARRule ($positions.Count-ge2) 'BLACK_HOLE_ATTRACTION_MISSING' 'Absorption alone does not prove visible attraction.';$fid=Get-AREventEntity $removedEvent 'black_hole_field';$core=@($Context.states|ForEach-Object{Get-ARProcesses $_ 'black_hole_field'}|Where-Object{(Get-AREntityId $_)-ceq$fid}|Select-Object -First 1);Assert-ARRule ($core.Count-eq1-and(Get-ARDistance $positions[-1].position (Get-ARValue $core[0] 'position_m'))-lt(Get-ARDistance $positions[0].position (Get-ARValue $core[0] 'position_m'))) 'BLACK_HOLE_ATTRACTION_DIRECTION' 'The prop did not approach its linked field core.';foreach($s in @($Context.states|Where-Object{$_.identity.monotonic_ms-gt$removedEvent.monotonic_ms})){Assert-ARRule (@(Get-ARObjects $s 'physics_prop'|Where-Object{(Get-AREntityId $_)-ceq$id}).Count-eq0) 'BLACK_HOLE_ABSORBED_PROP_REMAINS' 'An absorbed prop remained observable.'}}
}

function Assert-ARRestartResult($Context){
    $resultTrace=Get-ARPath $Context.trace 'setup.restart_result'
    Assert-ARHealth ($null-ne$resultTrace-and$null-ne(Get-ActionRoguelikeAtomicProperty $resultTrace 'samples')) 'ATOMIC_RESTART_RESULT_NOT_COLLECTED' 'Restart did not provide an independent post-restart trace.'
    Assert-ARHealth ((Get-ARPath $resultTrace 'setup.method')-ceq'normal_input') 'ATOMIC_RESTART_RESULT_SETUP' 'The post-restart trace must use normal input.'
    $schemaRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../input/contracts'))
    $snapshotSchema=[IO.File]::ReadAllText((Join-Path $schemaRoot 'actionroguelike-probe-snapshot.schema.json'))
    $eventSchema=[IO.File]::ReadAllText((Join-Path $schemaRoot 'actionroguelike-probe-events.schema.json'))
    $restart=New-ARContext $resultTrace 'journey.restart_result' $snapshotSchema $eventSchema
    Assert-ARHealth ($restart.token-ceq$Context.token-and$restart.round-cne$Context.round) 'ATOMIC_RESTART_RESULT_IDENTITY' 'Restart did not move to one distinct round under the same process.'
    $restartInputs=@(Get-ARInput $Context 'restart'|Sort-Object monotonic_ms)
    Assert-ARHealth ($restartInputs.Count-ge1) 'ATOMIC_RESTART_RESULT_ORDER' 'The restart input receipt is missing.'
    $restartInput=$restartInputs[-1]
    Assert-ARHealth ($restart.start-ge[long]$restartInput.monotonic_ms) 'ATOMIC_RESTART_RESULT_ORDER' 'The post-restart trace predates the evaluator restart input.'
    # BeginPlay completes before the first new-round publication. Its event is
    # in that first coherent batch, even though it precedes the snapshot clock.
    $completed=@($restart.trace.samples|ForEach-Object{$_.events.events}|Where-Object{$_.event_type-ceq'restart_completed'-and$null-ne(Get-AREventEntity $_ 'round')}|Sort-Object event_id -Unique)
    if(-not$completed.Count){
        # A new epoch's in-progress transition is an equivalent round event
        # only after verified Restart input and a different, clean round ID.
        $completed=@($restart.trace.samples|ForEach-Object{$_.events.events}|Where-Object{
            $_.event_type-ceq'round_phase_changed'-and(Get-ARPath $_ 'payload.round_phase')-ceq'in_progress'-and
            ($null-ne(Get-AREventEntity $_ 'round')-or($null-eq$_.subject-and$null-eq$_.object))
        }|Sort-Object event_id -Unique)
    }
    foreach($event in $completed){Assert-ARHealth ($event.monotonic_ms-ge[long]$restartInput.monotonic_ms) 'ATOMIC_RESTART_RESULT_ORDER' 'Restart completion predates the real input.'}
    Assert-ARRule ($completed.Count-eq1) 'FAILURE_RESTART_EVENT_MISSING' 'A new round requires one observed restart_completed event.'
    $reportedPhase=Get-ARPath $completed[0] 'payload.round_phase'
    Assert-ARRule ($null-eq$reportedPhase-or$reportedPhase-ceq'in_progress') 'FAILURE_RESTART_EVENT_PHASE' 'restart_completed reported a conflicting round phase.'
    Assert-ARRule ((Get-ARValue $restart.after 'world.round_phase')-ceq'in_progress' -and (Get-ARValue $restart.after 'player.health')-eq100 -and (Get-ARValue $restart.after 'player.credits')-eq0 -and (Get-ARValue $restart.after 'player.teleport_acquired')-eq$false) 'FAILURE_RESTART_INITIAL_STATE' 'Restart did not establish a clean playable new round.'
    return $restart
}

function Test-ARObservedMeleeSettlement($Context,$Event){
    if($null-ne$Event.object-or($null-ne$Event.subject-and(Get-ARPath $Event 'subject.role')-cne'player')){return $false}
    $prior=@($Context.states|Where-Object{$_.identity.monotonic_ms-lt$Event.monotonic_ms}|Select-Object -Last 2)
    $after=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$Event.monotonic_ms}|Select-Object -First 1)
    if($prior.Count-ne2-or$after.Count-ne1){return $false}
    $old=Get-ARPath $Event 'payload.value_before';$new=Get-ARPath $Event 'payload.value_after'
    if($null-eq$old-or$null-eq$new-or$old-le$new-or$new-ne(Get-ARValue $after[0] 'player.health')){return $false}
    $attacker=$null
    foreach($state in $prior){
        if((Get-ARValue $state 'player.health')-ne$old-or@(Get-ARProcesses $state 'enemy_projectile').Count){return $false}
        $melee=@($state.enemies|Where-Object{(Get-ARPath $_ 'ai_mode.trust')-in@('verified','corroborated')-and(Get-ARPath $_ 'action_state.trust')-in@('verified','corroborated')-and(Get-ARPath $_ 'ai_mode.value')-ceq'melee'-and(Get-ARPath $_ 'action_state.value')-ceq'melee_attack'})
        if($melee.Count-ne1){return $false}
        $id=Get-AREntityId $melee[0]
        if($attacker-and$attacker-cne$id){return $false};$attacker=$id
    }
    $settled=@($after[0].enemies|Where-Object{(Get-AREntityId $_)-ceq$attacker-and(Get-ARPath $_ 'action_state.trust')-in@('verified','corroborated')-and(Get-ARPath $_ 'action_state.value')-ceq'idle'})
    return $settled.Count-eq1-and@(Get-ARProcesses $after[0] 'enemy_projectile').Count-eq0
}
function Assert-ARJourney($Context,[string]$Phase,[switch]$Restart){
    $fixture=(Get-ARPath $Context.trace 'setup.method')-in@('state_fixture','hybrid')
    if($fixture){
        Assert-ARHealth ((Get-ARPath $Context.trace 'setup.fixture_version')-in@('ar-private-fixture-1.0.0','ar-private-fixture-2.0.0')-and[bool](Get-ARPath $Context.trace 'setup.fixture_receipt_path')) 'ATOMIC_JOURNEY_FIXTURE_UNVERIFIED' 'Terminal preconditions need a versioned native fixture receipt.'
        if($Phase-ceq'victory'){
            Assert-ARHealth ((Get-ARPath $Context.trace 'setup.remaining_seconds')-eq0-and[bool](Get-ARPath $Context.trace 'setup.clock_receipt_path')-and(Get-ARPath $Context.trace 'setup.invulnerable')-eq$true) 'ATOMIC_VICTORY_CLOCK_UNVERIFIED' 'Victory setup must expire only the countdown and protect the player.'
        }
    }
    if($Restart){
        Assert-ARAction $Context 'restart';Assert-ARHealth ((Get-ARValue $Context.before 'world.round_phase')-ceq'failure') 'ATOMIC_RESTART_NOT_AFTER_FAILURE' 'The follow-up case must start at failure.'
        # Restart's new round is captured as a separate independently validated
        # trace. A single unchecked snapshot is insufficient evidence.
        $null=Assert-ARRestartResult $Context;return
    }
    Assert-ARHealth ((Get-ARValue $Context.before 'world.round_phase')-ceq'in_progress'-and(Get-ARValue $Context.before 'player.health')-gt0-and($fixture-or((Get-ARValue $Context.before 'player.health')-eq100-and(Get-ARValue $Context.before 'player.credits')-eq0-and(Get-ARValue $Context.before 'world.survival_time_seconds')-le1))) 'ATOMIC_JOURNEY_NOT_FRESH' 'Journey must begin alive in an independently established active round.'
    $terminal=@(Get-AREvents $Context 'terminal_result' 'round')
    if(-not$terminal.Count){$terminal=@(Get-AREvents $Context 'terminal_result'|Where-Object{$null-eq$_.subject-and$null-eq$_.object})}
    Assert-ARRule ($terminal.Count-eq1-and$terminal[0].payload.terminal_result-ceq$Phase) 'TERMINAL_RESULT_CARDINALITY' 'The journey must reach exactly one requested terminal result.'
    Assert-ARRule ((Get-ARValue $Context.after 'world.round_phase')-ceq$Phase-and(Get-ARValue $Context.after 'world.terminal_result_count')-eq1) 'TERMINAL_STATE_MISMATCH' 'Snapshot and terminal event disagree.'
    if($Phase-ceq'failure'){
        $damage=@(Get-AREvents $Context 'damage' 'player')
        # A difference publisher may report the private health setup as damage.
        # Once an alive post-setup sample is confirmed, only later damage can
        # establish the tested failure. Keep the setup event in raw evidence.
        $setupClock=Get-ARPath $Context.trace 'setup.after_identity.monotonic_ms'
        $setupState=@($Context.states|Where-Object{$_.identity.monotonic_ms-eq$setupClock})
        if($fixture-and'health'-cin@(Get-ARPath $Context.trace 'setup.allowed_fields')-and$setupState.Count-eq1-and(Get-ARValue $setupState[0] 'player.health')-gt0){$damage=@($damage|Where-Object{$_.monotonic_ms-gt$setupClock})}
        Assert-ARRule ($damage.Count-ge1-and(Get-ARValue $Context.after 'player.health')-eq0) 'FAILURE_LEGAL_DAMAGE_MISSING' 'Failure must follow legal enemy damage to zero Health.'
        foreach($event in $damage){
            $source=$null-ne(Get-AREventEntity $event 'enemy')-or$null-ne(Get-AREventEntity $event 'enemy_projectile')
            if(-not$source-and$null-eq$event.object-and(Get-ARPath $event 'subject.role')-ceq'player'){
                $attacks=@(Get-AREvents $Context 'action_started' 'enemy'|Where-Object{(Get-ARPath $_ 'payload.action')-ceq'melee_attack'-and$_.monotonic_ms-lt$event.monotonic_ms})
                $matches=@($attacks|Where-Object{
                    $attacker=Get-AREventEntity $_ 'enemy';$startTime=$_.monotonic_ms
                    $ends=@(Get-AREvents $Context 'action_ended' 'enemy' $attacker|Where-Object{$_.monotonic_ms-ge$event.monotonic_ms})
                    $at=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$event.monotonic_ms}|Select-Object -First 1)
                    $priorEnd=@(Get-AREvents $Context 'action_ended' 'enemy' $attacker|Where-Object{$_.monotonic_ms-gt$startTime-and$_.monotonic_ms-lt$event.monotonic_ms})
                    $ends.Count-eq1-and$at.Count-eq1-and$ends[0].monotonic_ms-le$at[0].identity.monotonic_ms-and$priorEnd.Count-eq0
                })
                $source=$matches.Count-eq1
            }
            if(-not$source){$source=Test-ARObservedMeleeSettlement $Context $event}
            Assert-ARRule $source 'FAILURE_DAMAGE_SOURCE' 'Failure damage must originate from an enemy attack.'
        }
    }else{Assert-ARRule ((Get-ARValue $Context.after 'player.health')-gt0-and(Get-ARValue $Context.after 'world.survival_time_seconds')-ge60) 'VICTORY_TOO_EARLY' 'Victory requires 60 seconds with positive Health.'}
    $after=@($Context.states|Where-Object{$_.identity.monotonic_ms-ge$terminal[0].monotonic_ms});Assert-ARHealth ($after.Count-ge2) 'ATOMIC_TERMINAL_STABILITY_WINDOW' 'Terminal stability needs two distinct post-result samples.'
    foreach($s in $after){Assert-ARRule ((Get-ARValue $s 'world.round_phase')-ceq$Phase-and(Get-ARValue $s 'world.terminal_result_count')-eq1) 'TERMINAL_RESULT_CHANGED' 'The determined result changed or repeated.'}
}

function Test-ActionRoguelikeAtomicCheckpoint {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$CheckpointId,[Parameter(Mandatory)][Collections.IDictionary]$Traces)
    $map=Get-ActionRoguelikeAtomicVariantMap;Assert-ARHealth ($map.Contains($CheckpointId)) 'ATOMIC_UNKNOWN_CHECKPOINT' 'Unknown atomic checkpoint.'
    $schemaRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../input/contracts'))
    $snapshotSchema=[IO.File]::ReadAllText((Join-Path $schemaRoot 'actionroguelike-probe-snapshot.schema.json'));$eventSchema=[IO.File]::ReadAllText((Join-Path $schemaRoot 'actionroguelike-probe-events.schema.json'))
    $results=[Collections.Generic.List[object]]::new();$contexts=@{}
    foreach($variant in $map[$CheckpointId]){
        $trace=if($Traces.Contains($variant)){$Traces[$variant]}else{$null}
        if($null -eq $trace){
            $results.Add([pscustomobject]@{variant_id=$variant;verdict='run_invalid';reason_code='ATOMIC_VARIANT_NOT_EXECUTED';detail="No runtime trace was supplied for required variant: $variant";evidence=@()})
            continue
        }
        $verdict='pass';$reason='ATOMIC_VARIANT_PASSED';$detail='All required observations passed.'
        try{
            $context=New-ARContext $trace $variant $snapshotSchema $eventSchema;$contexts[$variant]=$context
            switch -Regex ($variant){
                '^primary\.(.+)$' {Assert-ARProjectile $context $Matches[1];break}
                '^blackhole\.(.+)$' {Assert-ARBlackHole $context $Matches[1];break}
                '^teleport\.pickup(_repeat)?$' {Assert-ARPickup $context -Strict:($CheckpointId-ceq'D3-05') -Repeat:($variant-ceq'teleport.pickup_repeat');break}
                '^teleport\.(.+)$' {Assert-ARTeleport $context $Matches[1] -ContentOnly:($CheckpointId-ceq'D2-08');break}
                '^resources\.(.+)$' {Assert-ARResource $context $Matches[1] -ContentOnly:($CheckpointId-ceq'D2-10');break}
                '^journey\.victory$' {Assert-ARJourney $context 'victory';break}
                '^journey\.failure_restart$' {Assert-ARJourney $context 'failure' -Restart;break}
                '^journey\.failure(_repeat)?$' {Assert-ARJourney $context 'failure';break}
                default {throw 'run_invalid|ATOMIC_UNKNOWN_VARIANT|The evaluator variant has no executable rule.'}
            }
        }catch{
            $parts=$_.Exception.Message.Split('|',3)
            if($parts.Count-eq3-and$parts[0]-in@('pass','fail','unreachable','run_invalid')){$verdict=$parts[0];$reason=$parts[1];$detail=$parts[2]}
            else{$verdict='run_invalid';$reason='ATOMIC_RULE_EXCEPTION';$detail=$_.Exception.Message}
        }
        $results.Add([pscustomobject]@{variant_id=$variant;verdict=$verdict;reason_code=$reason;detail=$detail;evidence=@(Get-ARPath $trace 'execution.evidence_paths')})
    }
    # Cross-case lifecycle claims require genuinely independent clean rounds.
    if($CheckpointId-in@('D2-13','D4-02')){
        $names=if($CheckpointId-ceq'D2-13'){@('journey.victory','journey.failure')}else{@('journey.failure','journey.failure_repeat')}
        if($contexts.ContainsKey($names[0])-and$contexts.ContainsKey($names[1])){
            $a=$contexts[$names[0]];$b=$contexts[$names[1]]
            if($a.token-ceq$b.token-and$a.round-ceq$b.round){$results.Add([pscustomobject]@{variant_id='independent_rounds';verdict='run_invalid';reason_code='ATOMIC_JOURNEY_REUSED';detail='The evaluator reused one round for independent journeys.';evidence=@()})}
        }
    }
    $overall='pass';foreach($priority in @('run_invalid','fail','unreachable')){if(@($results|Where-Object verdict -eq $priority).Count){$overall=$priority;break}}
    $first=$results|Where-Object verdict -eq $overall|Select-Object -First 1
    $missing=@($map[$CheckpointId]|Where-Object{-not$Traces.Contains($_)-or$null-eq$Traces[$_]})
    $collected=@($map[$CheckpointId]|Where-Object{$_ -notin $missing})
    $completed=@($results|Where-Object{$_.variant_id-in$map[$CheckpointId]-and$_.verdict-ne'run_invalid'})
    return [pscustomobject]@{checkpoint_id=$CheckpointId;verdict=$overall;passed=($overall-ceq'pass');reason_code=$first.reason_code;detail=$first.detail;attribution=$(if($overall-ceq'run_invalid'){'evaluator'}elseif($overall-ceq'pass'){$null}else{'candidate'});variants=@($results);evidence=@($results|ForEach-Object{$_.evidence}|Where-Object{$_}|Select-Object -Unique);measurements=@{required_variants=$map[$CheckpointId].Count;completed_variants=$completed.Count;collected_variants=$collected;missing_variants=$missing;collection_complete=($missing.Count-eq0)}}
}
