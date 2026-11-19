Set-StrictMode -Version Latest

function Publish-ARFixtureRequest {
    param([Parameter(Mandatory)][string]$Path,[int]$TimeoutMilliseconds=3000)
    $publication=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        try{[IO.File]::Move(($Path+'.tmp'),$Path,$true);return}
        # Windows replacement can report either sharing violation (IOException)
        # or access denied while the native reader owns the destination handle.
        # Retry publication of the same request; never create another setup.
        catch [IO.IOException],[UnauthorizedAccessException]{
            if($publication.ElapsedMilliseconds-ge$TimeoutMilliseconds){throw 'run_invalid|FIXTURE_REQUEST_PUBLICATION_FAILED|Native reader held the request file beyond the publication budget.'}
            Start-Sleep -Milliseconds 10
        }
    }
}

function Invoke-ARFixture {
    param([Collections.IDictionary]$Writes,[string]$Name='setup',[int]$CaptureAttempt=0)
    $request=[ordered]@{request_id=[guid]::NewGuid().ToString('N')}
    foreach($key in $Writes.Keys){$request[$key]=$Writes[$key]}
    $allowed=@('invulnerable','health','credits','teleport_acquired','remaining_seconds','near_position_m','distance_m','position_m','freeze_enemies','remove_props','aim','aim_position_m','block_forward_space','capture_pointer')
    foreach($key in $Writes.Keys){if($key -notin $allowed){throw "run_invalid|FIXTURE_WRITE_FORBIDDEN|Unsupported precondition: $key"}}
    if($Writes.Contains('health') -and [double]$Writes.health -le0){throw 'run_invalid|FIXTURE_RESULT_WRITE_FORBIDDEN|Health setup must leave the player alive.'}
    if($Writes.Contains('capture_pointer') -and $Writes.capture_pointer){
        # Acquire the bound OS foreground before asking Unreal for capture.
        $focus=Move-UnrealPointer -Session $script:Session -NormalizedX .5 -NormalizedY .5
        $focusPath=Save-Receipt $focus "fixture-$Name-foreground"
        # A newly created viewport can still be resizing behind its splash.
        # Retry only this positively identified host fault, before any dispatch.
        for($attempt=1;$attempt-le3-and$focus.status-cne'ok';$attempt++){
            if($focus.fault.code-cne'pointer_move_bound_dispatch_failed'-or$focus.fault.details.validation_code-cne'POINTER_TARGET_OCCLUDED'-or$focus.fault.details.dispatch_occurred_before_fault-ne$false){break}
            Start-Sleep -Milliseconds 150
            $focus=Move-UnrealPointer -Session $script:Session -NormalizedX .5 -NormalizedY .5
            $focusPath=Save-Receipt $focus "fixture-$Name-foreground-retry-$attempt"
        }
        if($focus.status-cne'ok'-or-not$focus.input_dispatched){throw "run_invalid|FIXTURE_FOREGROUND_FAILED|Bound viewport focus failed: $focusPath"}
    }
    $requestPath=Join-Path $script:FixtureChannel 'request.json'
    Write-JsonFile $request ($requestPath+'.tmp')
    Publish-ARFixtureRequest -Path $requestPath
    $watch=[Diagnostics.Stopwatch]::StartNew();$reply=$null
    do {
        $candidate=Read-Json (Join-Path $script:FixtureChannel 'response.json')
        if($candidate -and $candidate.request_id -ceq $request.request_id){$reply=$candidate;break}
        Start-Sleep -Milliseconds 20
    } while($watch.Elapsed.TotalSeconds-lt3)
    $receivedHostMs=[Environment]::TickCount64
    $receivedUtc=[DateTime]::UtcNow
    $path=Save-Receipt ([ordered]@{fixture_version='ar-private-fixture-2.0.0';writes=$request;response=$reply;response_received_host_ms=$receivedHostMs;response_received_utc=$receivedUtc.ToString('o')}) "fixture-$Name"
    if(-not$reply){throw "run_invalid|FIXTURE_RESPONSE_TIMEOUT|No native fixture response: $path"}
    if($reply.adapter_version-cne'ar-private-fixture-2.0.0' -or $reply.engine_capabilities_version-cne'ue-fixture-capabilities-1.0.0' -or $reply.candidate_adapter_id-cne$script:FixtureAdapterIdentity){throw "run_invalid|FIXTURE_ADAPTER_IDENTITY_MISMATCH|Response does not match the staged adapter: $path"}
    if($reply.process_id-ne$script:ProcessId -or -not$reply.applied){throw "run_invalid|FIXTURE_NATIVE_MAPPING_OR_GEOMETRY_FAILED|Native fixture could not confirm setup: $path"}
    if($reply.readback_verified-ne$true){throw "run_invalid|FIXTURE_READBACK_MISMATCH|Adapter did not verify its writes: $path"}
    $captureConfirmation=$null
    if($Writes.Contains('capture_pointer') -and $Writes.capture_pointer -and $reply.viewport_capture -ne $true){
        if($CaptureAttempt-ge3){throw "run_invalid|FIXTURE_VIEWPORT_CAPTURE_FAILED|Native viewport mouse capture was not confirmed: $path"}
        # Slate applies capture at a frame boundary. Retry only the input
        # precondition, never health, position, clock or other native writes.
        Start-Sleep -Milliseconds 100
        $captureConfirmation=Invoke-ARFixture @{capture_pointer=$true} ($Name+'-capture-confirm') ($CaptureAttempt+1)
    }
    foreach($key in @('health','credits','teleport_acquired','remaining_seconds','invulnerable')){
        if($Writes.Contains($key)){
            $matches=if($key-in@('teleport_acquired','invulnerable')){$reply.$key-eq$Writes[$key]}else{[Math]::Abs([double]$reply.$key-[double]$Writes[$key])-le0.0001}
            if(-not$matches){throw "run_invalid|FIXTURE_READBACK_MISMATCH|Native readback differs for $key : $path"}
            if($key-cne'invulnerable' -and $reply.verified_fields.$key-ne$true){throw "run_invalid|FIXTURE_READBACK_MISMATCH|Missing verified field $key : $path"}
        }
    }
    return [ordered]@{receipt_path=$path;response=$reply;writes=$Writes;capture_confirmation=$captureConfirmation;response_received_host_ms=$receivedHostMs;response_received_utc=$receivedUtc}
}

function Get-ARFixtureTarget($Snapshot,[string]$Type) {
    $items=@(Get-ARObjects $Snapshot $Type | Where-Object { (Get-ARValue $_ 'available') -eq $true })
    if(-not$items.Count){throw "unreachable|CANDIDATE_ITEM_POSITION_UNAVAILABLE|No available $Type with a published position."}
    $item=$items[0]
    # Missing, untrusted and incomplete positions are candidate contract defects.
    $position=Get-ARValue $item 'position_m'
    foreach($axis in @('x','y','z')){if($null-eq(Get-ActionRoguelikeAtomicProperty $position $axis)){throw "unreachable|CANDIDATE_ITEM_POSITION_UNAVAILABLE|Incomplete $Type position."}}
    return @{entity=$item;position=$position;id=Get-AREntityId $item}
}

function Add-ARLiveSample($List,[switch]$AllowRoundReset) {
    $pair=Read-TaskState -TimeoutMilliseconds 250 -RequireNewSample -AllowRoundReset:$AllowRoundReset
    if($pair){$List.Add(@{snapshot=$pair.snapshot;events=$pair.events})}
    return $pair
}

function Wait-ARLiveWindow($List,[double]$Seconds,[scriptblock]$Until) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        $pair=Add-ARLiveSample $List
        if($pair -and $Until -and (& $Until $pair.snapshot $pair.events)){return $pair}
        Start-Sleep -Milliseconds 15
    } while($watch.Elapsed.TotalSeconds-lt$Seconds)
    return $null
}

function Invoke-ARLiveInput($Snapshot,[string]$Action,[string]$Name,[int]$DurationMs=45) {
    $physical=if($Action-ceq'move_toward'){'move_forward'}else{$Action}
    $binding=Get-ControlActivation $Snapshot $physical
    if(-not$binding){throw "unreachable|CANDIDATE_CONTROL_UNAVAILABLE|Missing published control: $physical"}
    $sampleHost=$script:ARSampleHostTimes[[string]$Snapshot.identity.snapshot_id]
    $ok=Invoke-ControlActivation $binding $Name $DurationMs
    $receipt=Read-Json (Join-Path $script:OutputFull "receipts/$Name.json")
    if($binding.kind-ceq'keyboard'){
        # Executor Press performs key down/up in a finally block. Its detailed
        # receipt, rather than the candidate's input event, proves dispatch.
        $released=$ok -and $receipt.status-ceq'ok' -and $receipt.input_dispatched -eq $true -and $receipt.result.up_monotonic_ms -ge $receipt.result.down_monotonic_ms
    }else{$released=$ok-and$receipt.release_verified-eq$true}
    if(-not$released){throw "run_invalid|ATOMIC_INPUT_NOT_VERIFIED|Input dispatch/release failed: $Name"}
    $hostDown=if($binding.kind-ceq'keyboard'){$receipt.result.down_monotonic_ms}else{$receipt.down.observer_monotonic_ms}
    $hostUp=if($binding.kind-ceq'keyboard'){$receipt.result.up_monotonic_ms}else{$receipt.up.observer_monotonic_ms}
    if($null-eq$sampleHost){throw 'run_invalid|ATOMIC_INPUT_CLOCK_UNBOUND|No host clock anchor for the input snapshot.'}
    return @{semantic_action=$Action;monotonic_ms=([long]$Snapshot.identity.monotonic_ms+[long]$hostDown-[long]$sampleHost);input_dispatched=$true;release_verified=$released;attribution='evaluator';evidence_path="receipts/$Name.json";process_token=$Snapshot.identity.process_token;round_id=$Snapshot.identity.round_id;clock_mapping=@{method='publisher_sample_host_offset';snapshot_id=$Snapshot.identity.snapshot_id;sample_host_ms=$sampleHost;dispatch_host_ms=$hostDown;release_host_ms=$hostUp;publisher_sample_ms=$Snapshot.identity.monotonic_ms}}
}

function Invoke-ARContactInput($Snapshot,$Samples,$Target,[string]$Name,[switch]$Away){
    $binding=Get-ControlActivation $Snapshot $(if($Away){'move_backward'}else{'move_forward'})
    if(-not$binding-or$binding.kind-cne'keyboard'){throw 'unreachable|CANDIDATE_CONTROL_UNAVAILABLE|Contact movement requires the published forward key.'}
    $sampleHost=$script:ARSampleHostTimes[[string]$Snapshot.identity.snapshot_id]
    if($null-eq$sampleHost){throw 'run_invalid|ATOMIC_INPUT_CLOCK_UNBOUND|Contact input has no host clock anchor.'}
    $initial=Get-ARBoundObject $Snapshot @{setup=@{target_entity_id=$Target.id}} (Get-ARValue $Target.entity 'object_type')
    $wasAvailable=Get-ARValue $initial 'available'
    $down=$null;$up=$null;$reason='bounded_contact_window_expired';$watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        $down=Start-UnrealKeyHold -Session $script:Session -Key $binding.key
        if($down.status-cne'ok'-or-not$down.input_dispatched){throw 'run_invalid|ATOMIC_INPUT_NOT_VERIFIED|Contact key down failed.'}
        do{
            $pair=Add-ARLiveSample $Samples
            if($pair){
                $item=Get-ARBoundObject $pair.snapshot @{setup=@{target_entity_id=$Target.id}} (Get-ARValue $Target.entity 'object_type')
                if(-not$Away-and$wasAvailable-and(Get-ARValue $item 'available')-eq$false){$reason='target_became_unavailable';break}
                $p=Get-ARValue $pair.snapshot 'player.position_m';$q=Get-ARValue $item 'position_m'
                $distance=[Math]::Sqrt([Math]::Pow($p.x-$q.x,2)+[Math]::Pow($p.y-$q.y,2))
                if($Away-and$distance-ge2.4){$reason='returned_to_setup_distance';break}
                if(-not$Away-and$distance-le.35){$reason='reached_target_center';break}
            }
            Start-Sleep -Milliseconds 10
        }while($watch.Elapsed.TotalSeconds-lt2)
    }finally{
        if($down-and$down.input_dispatched){$up=Stop-UnrealKeyHold -Session $script:Session -Key $binding.key}
        $released=$up-and$up.status-ceq'ok'-and$up.result.held-eq$false
        [void](Save-Receipt @{operation='observed_contact_hold';down=$down;up=$up;release_verified=[bool]$released;target_entity_id=$Target.id;stop_reason=$reason;elapsed_seconds=$watch.Elapsed.TotalSeconds} $Name)
    }
    if(-not$released){throw 'run_invalid|ATOMIC_INPUT_NOT_VERIFIED|Contact key release failed.'}
    return @{semantic_action=$(if($Away){'move_backward'}else{'move_toward'});monotonic_ms=([long]$Snapshot.identity.monotonic_ms+[long]$down.observer_monotonic_ms-[long]$sampleHost);input_dispatched=$true;release_verified=$true;attribution='evaluator';evidence_path="receipts/$Name.json";process_token=$Snapshot.identity.process_token;round_id=$Snapshot.identity.round_id;clock_mapping=@{method='publisher_sample_host_offset';snapshot_id=$Snapshot.identity.snapshot_id;sample_host_ms=$sampleHost;dispatch_host_ms=$down.observer_monotonic_ms;release_host_ms=$up.observer_monotonic_ms;publisher_sample_ms=$Snapshot.identity.monotonic_ms}}
}

function Invoke-ARAtomicVariant {
    param([string]$Variant,$Spec)
    $samples=[Collections.Generic.List[object]]::new();$inputs=[Collections.Generic.List[object]]::new()
    $trace=[ordered]@{variant_id=$Variant;execution=@{status='completed';evidence_paths=@()};setup=@{};input_receipts=@();samples=@();capture_paths=@();cleanup=@{}}
    $started=[Diagnostics.Stopwatch]::StartNew();$caseIdentity=$null;$restartIdentity=$null
    try {
        # A native window can precede the first playable tick during cold asset
        # loading in a freshly staged copy. Use the runner's startup allowance.
        $before=Wait-TaskState {param($s,$e)$true} 30 'fixture-entry'
        if(-not$before){throw 'unreachable|CANDIDATE_STATE_PROVIDER_INVALID|Fresh process did not publish a valid state pair.'}
        # Focus/capture can queue one real pointer delta. Complete that engine
        # update before applying aim, placement, or blocked-corridor setup.
        $inputReady=Invoke-ARFixture @{capture_pointer=$true} 'input-ready'
        Assert-ARMetricCorroboration $before.snapshot $inputReady.response
        $captureClock=[long]$inputReady.response_received_host_ms
        $ready=Wait-TaskState {param($s,$e)$script:ARSampleHostTimes[[string]$s.identity.snapshot_id]-ge($captureClock+250)} 3 'input-ready-settled'
        if(-not$ready){throw 'run_invalid|FIXTURE_INPUT_PRECONDITION_UNSETTLED|No engine update after viewport focus/capture.'}
        $before=$ready
        $caseIdentity=$before.snapshot.identity
        $setup=@{method='state_fixture';confirmed=$false;before_identity=$caseIdentity;after_identity=$caseIdentity;fixture_version='ar-private-fixture-2.0.0';adapter_identity=$script:FixtureAdapterIdentity;engine_capabilities_version='ue-fixture-capabilities-1.0.0';fixture_receipt_path=$null;allowed_fields=@();invulnerable=$true}
        $trace.setup=$setup
        $metricBinding=Get-Variable ARMetricBinding -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if($metricBinding){$trace.observation_units=$metricBinding}
        $setup.input_ready_receipt_path=$inputReady.receipt_path
        $request=[ordered]@{invulnerable=$true}
        $damageCase=$Variant -like 'journey.failure*'
        if(-not$damageCase){
            $positions=@($before.snapshot.enemies|ForEach-Object {Get-ARValue $_ 'position_m'})
            if($positions.Count){$request.freeze_enemies=$positions}
        }
        $target=$null
        if($Variant -match '^(resources\.pickup|teleport\.pickup)'){
            $type=if($Variant.StartsWith('resources.')){'credits_pickup'}else{'teleport_pickup'}
            $target=Get-ARFixtureTarget $before.snapshot $type
            $request.near_position_m=$target.position;$request.distance_m=2.4
            if($type-ceq'teleport_pickup'){$request.teleport_acquired=$false}
        }elseif($Variant -match '^resources\.(heal|reject)'){
            $target=Get-ARFixtureTarget $before.snapshot 'potion'
            $request.near_position_m=$target.position;$request.distance_m=1.4
            $maximum=Get-ARValue $before.snapshot 'player.health_max'
            $request.health=if($Variant-ceq'resources.reject_full'){$maximum}else{[Math]::Max(1,$maximum/2)}
            $request.credits=if($Variant-ceq'resources.reject_poor'){49}else{50}
        }elseif($Variant -like 'teleport.*'){
            $request.teleport_acquired=($Variant-cne'teleport.locked')
            if($Variant-cne'teleport.locked'){$request.aim='open'}
            if($Variant-ceq'teleport.invalid'){$request.block_forward_space=$true}
        }elseif($Variant -like 'primary.*'){
            if($Variant-ceq'primary.hit'){
                $enemies=@($before.snapshot.enemies|Where-Object{(Get-ARValue $_ 'health')-gt20})
                if(-not$enemies.Count){throw 'unreachable|CANDIDATE_ENEMY_UNAVAILABLE|No living observed enemy above 20 Health.'}
                $request.near_position_m=Get-ARValue $enemies[0] 'position_m';$request.distance_m=4
            }else{$request.aim=if($Variant-ceq'primary.obstacle'){'obstacle'}elseif($Variant-ceq'primary.miss'){'up'}else{'open'}}
        }elseif($Variant -like 'blackhole.*'){
            $props=@(Get-ARObjects $before.snapshot 'physics_prop')
            if($Variant-ceq'blackhole.empty'){$request.remove_props=@($props|ForEach-Object{Get-ARValue $_ 'position_m'});$request.aim='open'}
            else{
                if(-not$props.Count){throw 'unreachable|CANDIDATE_PROP_POSITION_UNAVAILABLE|No observed physics prop.'}
                $request.near_position_m=Get-ARValue $props[0] 'position_m';$request.distance_m=8
                $request.aim_position_m=$request.near_position_m
            }
            $setup.isolated_motion=$true
        }elseif($damageCase){
            $enemies=@($before.snapshot.enemies|Where-Object{(Get-ARValue $_ 'health')-gt0})
            if(-not$enemies.Count){throw 'unreachable|CANDIDATE_ENEMY_UNAVAILABLE|No enemy for the real damage trigger.'}
            $request.health=1;$request.invulnerable=$false;$setup.invulnerable=$false
            $request.near_position_m=Get-ARValue $enemies[0] 'position_m';$request.distance_m=1.6
        }
        if($target){$setup.target_entity_id=$target.id}
        $fixture=Invoke-ARFixture $request 'setup'
        $setup.fixture_receipt_path=$fixture.receipt_path;$setup.allowed_fields=@($request.Keys)
        if($request.Contains('aim_position_m')){$setup.native_aim=@{direction=$fixture.response.aim_direction;receipt_path=$fixture.receipt_path;confirmed=$true}}
        if($request.Contains('aim')){$setup.endpoint_class=$fixture.response.endpoint_class}
        $post=Wait-TaskState {
            param($s,$e)
            if($s.identity.sequence-le$caseIdentity.sequence){return $false}
            # Native and publisher clocks can have different epochs. Compare
            # observed file publication and response arrival on the host clock.
            if($script:ARSampleHostTimes[[string]$s.identity.snapshot_id]-le$fixture.response_received_host_ms){return $false}
            if($request.Contains('remove_props')-and@(Get-ARObjects $s 'physics_prop').Count-ne0){return $false}
            # A newer file can still have been published before the native
            # request arrived. Wait for the injected state, not just sequence+1.
            if(-not$damageCase){
                foreach($key in @('health','credits','teleport_acquired')){
                    if($request.Contains($key)-and(Get-ObservedPath $s "player.$key")-ne$request[$key]){return $false}
                }
                if($request.Contains('near_position_m')-and(Get-VectorDistance (Get-ObservedPath $s 'player.position_m') $fixture.response.position_m)-gt.4){return $false}
            }
            return $true
        } 3 'fixture-after'
        if(-not$post){throw 'run_invalid|FIXTURE_OBSERVATION_MISMATCH|Native writes were not corroborated by fresh independent observer samples.'}
        if($request.Contains('near_position_m') -and -not$damageCase){
            # Placement clears the capsule above the floor. Let real movement
            # settle before an assertion whose protected baseline is position.
            $settling=@{position=(Get-ARValue $post.snapshot 'player.position_m');sequence=$post.snapshot.identity.sequence}
            $settled=Wait-TaskState {
                param($s,$e)
                if($s.identity.sequence-le$settling.sequence){return $false}
                $position=Get-ARValue $s 'player.position_m'
                $stable=(Get-ARDistance $position $settling.position)-lt0.0001
                $settling.position=$position;$settling.sequence=$s.identity.sequence
                return $stable -and (Get-ARValue $s 'player.ground_state')-ceq'grounded'
            } 3 'fixture-settled'
            if(-not$settled){throw 'run_invalid|FIXTURE_POSITION_UNSETTLED|Native placement did not establish a stable grounded precondition.'}
            $post=$settled
        }
        if($setup.Contains('isolated_motion')-and$setup.isolated_motion){
            # A movement component can consume the AI's last queued input after
            # actor ticking is disabled. Confirm it has settled before testing
            # whether the field moves an enemy; never pin positions each frame.
            $motion=@{sequence=$post.snapshot.identity.sequence;positions=@{}}
            foreach($enemy in $post.snapshot.enemies){$motion.positions[(Get-AREntityId $enemy)]=Get-ARValue $enemy 'position_m'}
            $isolated=Wait-TaskState {
                param($s,$e)
                if($s.identity.sequence-le$motion.sequence){return $false}
                $stable=$true
                foreach($enemy in $s.enemies){
                    $id=Get-AREntityId $enemy;$position=Get-ARValue $enemy 'position_m'
                    if(-not$motion.positions.Contains($id)-or(Get-ARDistance $position $motion.positions[$id])-ge0.0001){$stable=$false}
                    $motion.positions[$id]=$position
                }
                $motion.sequence=$s.identity.sequence
                return $stable
            } 3 'fixture-motion-settled'
            if(-not$isolated){throw 'run_invalid|FIXTURE_MOTION_UNSETTLED|Independent enemy locomotion did not settle before the field test.'}
            $post=$isolated
        }
        # Verify injected scalar preconditions through the independent observer.
        foreach($key in @('health','credits','teleport_acquired')){
            if($request.Contains($key) -and -not$damageCase -and (Get-ARValue $post.snapshot "player.$key")-ne$request[$key]){throw "run_invalid|FIXTURE_OBSERVATION_MISMATCH|Native $key write was not reflected by the independent observer."}
        }
        $setup.after_identity=$post.snapshot.identity;$setup.confirmed=$true
        if($Variant-like'*.latest_direction'){
            # Absolute pointer dispatch can be a zero-distance move when the
            # previous process left the pointer at the same coordinate.
            $prepare=Move-UnrealPointer -Session $script:Session -NormalizedX .3 -NormalizedY .5
            $preparePath=Save-Receipt $prepare 'direction-prepare'
            if($prepare.status-cne'ok'-or-not$prepare.input_dispatched){throw 'run_invalid|ATOMIC_DIRECTION_INPUT_UNVERIFIED|Pointer preparation failed.'}
            $anchor=$post.snapshot.identity.monotonic_ms+([long]$prepare.observer_monotonic_ms-[long]$script:ARSampleHostTimes[[string]$post.snapshot.identity.snapshot_id])
            $prepared=Wait-TaskState {param($s,$e)$s.identity.monotonic_ms-ge($anchor+150)} 2 'direction-prepared'
            if(-not$prepared){throw 'unreachable|CANDIDATE_DIRECTION_OBSERVATION_MISSING|No fresh state after pointer preparation.'}
            $post=$prepared
            $oldFacing=Get-ARValue $post.snapshot 'player.facing'
            $pointer=Move-UnrealPointer -Session $script:Session -NormalizedX .7 -NormalizedY .5
            $pointerPath=Save-Receipt $pointer 'direction-change'
            if($pointer.status-cne'ok'-or-not$pointer.input_dispatched){throw 'run_invalid|ATOMIC_DIRECTION_INPUT_UNVERIFIED|Pointer movement failed.'}
            $directionReceipt=@{input_dispatched=$true;release_verified=$true;attribution='evaluator';evidence_path=$pointerPath;process_token=$post.snapshot.identity.process_token;round_id=$post.snapshot.identity.round_id;monotonic_ms=$post.snapshot.identity.monotonic_ms}
            $changed=Wait-TaskState {param($s,$e)(Get-ARDistance (Get-ARValue $s 'player.facing') $oldFacing)-gt0.01} 2 'direction-after'
            if(-not$changed){throw 'unreachable|CANDIDATE_DIRECTION_UNRESPONSIVE|Published look input did not change facing.'}
            $setup.direction_change=@{confirmed=$true;before_facing=$oldFacing;after_facing=(Get-ARValue $changed.snapshot 'player.facing');input_receipt=$directionReceipt}
            $post=$changed
        }
        # Failure may be triggered immediately after setup; keep its live entry
        # sample so real damage and the transition remain in the evidence window.
        if($damageCase){$samples.Add(@{snapshot=$before.snapshot;events=$before.events})}
        $samples.Add(@{snapshot=$post.snapshot;events=$post.events})
        if($Variant-ceq'journey.victory'){
            $clock=Invoke-ARFixture @{remaining_seconds=0;invulnerable=$true} 'expire-countdown'
            $setup.clock_receipt_path=$clock.receipt_path;$setup.remaining_seconds=0
            $null=Wait-ARLiveWindow $samples 2 {param($s,$e)(Get-ARValue $s 'world.round_phase')-ceq'victory'}
            $null=Wait-ARLiveWindow $samples 1
        }elseif($damageCase){
            $terminal=if((Get-ARValue $post.snapshot 'world.round_phase')-ceq'failure'){$post}else{Wait-ARLiveWindow $samples 5 {param($s,$e)(Get-ARValue $s 'world.round_phase')-ceq'failure'}}
            # Re-enable protection as soon as the tested damage window ends.
            $null=Invoke-ARFixture @{invulnerable=$true} 'restore-protection'
            $null=Wait-ARLiveWindow $samples 1
            if($Variant-ceq'journey.failure_restart'){
                if(-not$terminal){throw 'unreachable|CANDIDATE_FAILURE_UNREACHABLE|Real enemy attack did not produce failure.'}
                $samples.Clear();$samples.Add(@{snapshot=$terminal.snapshot;events=$terminal.events})
                $null=Wait-ARLiveWindow $samples .1
                $restartInput=Invoke-ARLiveInput $samples[-1].snapshot 'restart' 'restart'
                $inputs.Add($restartInput)
                $fresh=Wait-TaskState {param($s,$e)$s.identity.round_id-cne$caseIdentity.round_id} 6 'restart-result' -AllowRoundReset
                if(-not$fresh){throw 'unreachable|CANDIDATE_RESTART_FAILED|Restart did not establish a new round.'}
                $restartIdentity=$fresh.snapshot.identity
                $newSamples=[Collections.Generic.List[object]]::new();$newSamples.Add(@{snapshot=$fresh.snapshot;events=$fresh.events})
                $null=Wait-ARLiveWindow $newSamples 1
                $setup.restart_result=@{execution=@{status='completed'};setup=@{method='normal_input';confirmed=$true;before_identity=$restartIdentity;after_identity=$restartIdentity};samples=@($newSamples);input_receipts=@();capture_paths=@();cleanup=@{}}
            }
        }elseif($Variant-ceq'resources.initial'){$null=Wait-ARLiveWindow $samples .25}
        else {
            $action=[string]$Spec.required_input
            if($action-ceq'move_toward'){$inputs.Add((Invoke-ARContactInput $samples[-1].snapshot $samples $target 'trigger-1'))}
            else{$inputs.Add((Invoke-ARLiveInput $samples[-1].snapshot $action 'trigger-1'))}
            if($Spec.minimum_actions-lt2-or$action-ceq'move_toward'){$null=Wait-ARLiveWindow $samples .1}
            if($Spec.minimum_actions-ge2){
                if($Variant-ceq'resources.heal_exact50'){
                    $observedUse=Wait-ARLiveWindow $samples 1.5 {param($s,$e)
                        $items=@(Get-ARObjects $s 'potion'|Where-Object{(Get-AREntityId $_)-ceq$target.id})
                        $items.Count-eq1-and(Get-ARValue $items[0] 'available')-eq$false
                    }
                    if(-not$observedUse){throw 'unreachable|CANDIDATE_HEAL_NOT_OBSERVED|The first interaction did not make the bound potion unavailable.'}
                }
                if($action-ceq'move_toward'){
                    $inputs.Add((Invoke-ARContactInput $samples[-1].snapshot $samples $target 'contact-exit' -Away))
                    $null=Wait-ARLiveWindow $samples .1
                }
                if($action-ceq'move_toward'){$inputs.Add((Invoke-ARContactInput $samples[-1].snapshot $samples $target 'trigger-2'))}
                else{$inputs.Add((Invoke-ARLiveInput $samples[-1].snapshot $action 'trigger-2'))}
                if($Variant-ceq'resources.pickup_recovery'){
                    $null=Wait-ARLiveWindow $samples .1
                    # Leave the overlap before recovery, otherwise a correct
                    # auto-pickup legitimately awards another 80 on reactivation.
                    $inputs.Add((Invoke-ARContactInput $samples[-1].snapshot $samples $target 'recovery-exit' -Away))
                }
            }
            if($Spec.minimum_actions-ge3){
                $endType=if($Variant-like'primary.*'){'action_ended'}else{'ability_ended'}
                $null=Wait-ARLiveWindow $samples 1.3 {param($s,$e)@($e.events|Where-Object{
                    $_.event_type-ceq$endType-and
                    $(if($action-ceq'primary_attack'){(Get-ARPath $_ 'payload.action')-ceq'primary_cast'}else{(Get-ARPath $_ 'payload.process_type')-ceq'teleport'-and$null-ne(Get-AREventEntity $_ 'teleport_process')})
                }).Count-gt0}
                if($Variant-ceq'teleport.repeat_reuse'){
                    $reuse=Invoke-ARFixture @{aim='open'} 'reuse-aim'
                    $setup.reuse_receipt_path=$reuse.receipt_path
                    $previousSequence=$samples[-1].snapshot.identity.sequence
                    $ready=Wait-TaskState {param($s,$e)$s.identity.sequence-gt$previousSequence} 2 'reuse-ready'
                    if(-not$ready){throw 'run_invalid|FIXTURE_REUSE_OBSERVATION_MISSING|No current sample after establishing the second legal direction.'}
                    $samples.Add(@{snapshot=$ready.snapshot;events=$ready.events})
                }
                $inputs.Add((Invoke-ARLiveInput $samples[-1].snapshot $action 'trigger-3'))
            }
            $seconds=if($Variant-ceq'resources.pickup_recovery'){10.4}elseif($Variant-ceq'resources.heal_exact50'){4.4}elseif($Variant-like'blackhole.*'){6.2}elseif($Variant-like'primary.*'){2.8}else{.9}
            $null=Wait-ARLiveWindow $samples $seconds
        }
        $capture=Save-CanonicalCapture 'result'
        if(-not$capture){throw 'unreachable|CANDIDATE_CAPTURE_UNAVAILABLE|No visible client frame for this variant.'}
        $trace.capture_paths=@($capture)
        if($setup.ContainsKey('restart_result')){$setup.restart_result.capture_paths=@($capture)}
    }catch{
        $parts=$_.Exception.Message.Split('|',3)
        $candidate=$parts.Count-eq3-and$parts[0]-in@('fail','unreachable')
        $reason=if($parts.Count-eq3){$parts[1]}else{'ATOMIC_COLLECTOR_EXCEPTION'}
        $receipt=Save-Receipt @{variant=$Variant;message=$_.Exception.Message;diagnostic=$_.ScriptStackTrace} 'failure'
        $trace.execution=@{status=$(if($candidate){'candidate_blocked'}else{'evaluator_blocked'});attribution=$(if($candidate){'candidate'}else{'evaluator'});reason_code=$reason;detail=$_.Exception.Message;evidence_paths=@($receipt)}
    }finally{
        $trace.samples=Expand-ActionRoguelikeHistoryWindow $samples $script:StateReaderContext
        if($trace.setup.ContainsKey('restart_result')){$trace.setup.restart_result.samples=Expand-ActionRoguelikeHistoryWindow $trace.setup.restart_result.samples $script:StateReaderContext -FromRoundStart}
        $trace.input_receipts=@($inputs)
        $stop=Stop-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -FaultCleanupTimeoutMs 5000
        $stopPath=Save-Receipt $stop 'stop';$script:SessionActive=$false
        $clean=$stop.status-ceq'ok'-and$stop.result.process_exited-eq$true-and$stop.result.input_lease_released-eq$true-and$stop.result.input_cleanup.all_released-eq$true
        $cleanup=@{verified=$clean;receipt_id=[guid]::NewGuid().ToString('N');attribution='evaluator';release_all_inputs=$clean;fixture_cleared=$clean;process_tree_stopped=$clean;evidence_paths=@($stopPath);process_token=$(if($caseIdentity){$caseIdentity.process_token}else{$script:ProcessToken});round_id=$(if($caseIdentity){$caseIdentity.round_id}else{''})}
        $trace.cleanup=$cleanup
        if($trace.setup.ContainsKey('restart_result')){$newCleanup=$cleanup.Clone();$newCleanup.round_id=$restartIdentity.round_id;$trace.setup.restart_result.cleanup=$newCleanup}
        if(-not$clean){$trace.execution=@{status='evaluator_blocked';attribution='evaluator';reason_code='ATOMIC_CLEANUP_UNVERIFIED';detail='Native fixture process/input cleanup failed.';evidence_paths=@($stopPath)}}
        $trace.execution.evidence_paths=@($trace.execution.evidence_paths)+@('receipts/trace.json')
        $trace.elapsed_seconds=$started.Elapsed.TotalSeconds
        [void](Save-Receipt $trace 'trace')
    }
    return $trace
}

function Convert-ARTraceEvidencePaths($Trace,[string]$Prefix) {
    foreach($pair in @($Trace.samples)){
        if($pair.Contains('independent_transport')-and$null-ne$pair.independent_transport){
            foreach($key in @('snapshot_path','events_path')){$pair.independent_transport[$key]="$Prefix/$($pair.independent_transport[$key])"}
        }
    }
    foreach($pair in @($Trace.samples)){
        foreach($key in @('history_path','fact_path')){if($pair.Contains($key)){$pair[$key]="$Prefix/$($pair[$key])"}}
    }
    foreach($key in @('capture_paths')){$Trace[$key]=@($Trace[$key]|ForEach-Object{"$Prefix/$_"})}
    foreach($receipt in @($Trace.cleanup,$Trace.execution)){
        if($receipt.Contains('evidence_paths')){$receipt.evidence_paths=@($receipt.evidence_paths|ForEach-Object{"$Prefix/$_"})}
    }
    foreach($input in @($Trace.input_receipts)){$input.evidence_path="$Prefix/$($input.evidence_path)"}
    foreach($key in @('fixture_receipt_path','clock_receipt_path','reuse_receipt_path','input_ready_receipt_path')){if($Trace.setup.Contains($key)-and$Trace.setup[$key]){$Trace.setup[$key]="$Prefix/$($Trace.setup[$key])"}}
    if($Trace.setup.Contains('native_aim')){$Trace.setup.native_aim.receipt_path="$Prefix/$($Trace.setup.native_aim.receipt_path)"}
    if($Trace.setup.Contains('direction_change')){$Trace.setup.direction_change.input_receipt.evidence_path="$Prefix/$($Trace.setup.direction_change.input_receipt.evidence_path)"}
    if($Trace.setup.Contains('restart_result')){Convert-ARTraceEvidencePaths $Trace.setup.restart_result $Prefix}
    # Candidate snapshots/events are deliberately never rewritten.
}

function Invoke-ARCollectAtomicVariants {
    param([string]$Project,[string]$Engine,[string[]]$Variants=@())
    $specs=Get-Content -Raw (Join-Path $PSScriptRoot '../contracts/atomic-check-contract.json')|ConvertFrom-Json -AsHashtable
    $baseOutput=$script:OutputFull;$traces=@{}
    try{
        $declared=@((Get-ActionRoguelikeAtomicVariantMap).Values|ForEach-Object{$_}|Select-Object -Unique)
        if(@($Variants|Where-Object{$_ -notin $declared}).Count){throw 'Unknown authoring variant selection.'}
        $selected=if($Variants.Count){$Variants}else{$declared}
        foreach($variant in $selected){
            $script:OutputFull=Join-Path $baseOutput "variants/$variant"
            New-Item -ItemType Directory -Path $script:OutputFull -Force|Out-Null
            $script:StateRoot=Join-Path $script:OutputFull 'state';$script:FixtureChannel=Join-Path $script:OutputFull 'fixture'
            New-Item -ItemType Directory -Path $script:StateRoot,$script:FixtureChannel -Force|Out-Null
            $script:SnapshotPath=Join-Path $script:StateRoot 'snapshot.json';$script:EventsPath=Join-Path $script:StateRoot 'events.json'
            $script:SessionStartedUtc=[DateTime]::UtcNow
            $start=Start-TaskEvaluationSession -ProjectPath $Project -RunRoot $script:OutputFull -StatePath (Join-Path $script:StateRoot 'engine.json') -ProcessToken ('atomic-'+[guid]::NewGuid().ToString('N')) -EngineRoot $Engine -WindowWidth 1280 -WindowHeight 720 -TimeoutMs 60000 -FocusTimeoutMs 3000 -ObserverDisabledControl -AdditionalArguments @("-ActionRoguelikeStateRoot=$($script:StateRoot)","-ActionRoguelikeSnapshotPath=$($script:SnapshotPath)","-ActionRoguelikeEventsPath=$($script:EventsPath)","-AREvaluationFixture=$($script:FixtureChannel)",'-Windowed','-ResX=1280','-ResY=720','-ForceRes')
            $startPath=Save-Receipt $start 'start'
            Assert-ExecutorOperationHealth $start $startPath
            if($start.status-cne'ok'){
                $traces[$variant]=@{execution=@{status='candidate_blocked';attribution='candidate';reason_code='CANDIDATE_START_FAILED';detail='Independent variant launch failed.';evidence_paths=@("variants/$variant/$startPath")}}
                continue
            }
            $script:Session=$start.result.session;$script:SessionActive=$true;$script:ProcessId=[int]$start.result.process_id;$script:ProcessToken=[string]$start.result.process_token
            Reset-StateReaderContext
            $trace=Invoke-ARAtomicVariant $variant $specs.variants[$variant]
            # Persist relative evidence paths at the run boundary, including all
            # nested input, setup and cleanup references.
            $copy=$trace|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100
            Convert-ARTraceEvidencePaths $copy "variants/$variant"
            $traces[$variant]=$copy
        }
    }finally{$script:OutputFull=$baseOutput}
    [void](Save-Receipt $traces 'atomic-live-traces')
    return $traces
}
