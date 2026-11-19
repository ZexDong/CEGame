Set-StrictMode -Version Latest

function Test-ActionRoguelikeSnapshotUsability($Node,$CompiledSchema,[switch]$KnownInvalid,$Options=$null){
    if($null-eq$Options){$Options=[Json.Schema.EvaluationOptions]::new();$Options.RequireFormatValidation=$true}
    if(-not$KnownInvalid-and$CompiledSchema.Evaluate($Node,$Options).IsValid){return @{usable=$true;complete=$true}}
    # A malformed process record must not suppress independent player, object,
    # control, UI and lifecycle observations. This clone is validation-only:
    # return and persist the publisher's original bytes, including the defect.
    $view=$Node.DeepClone();$view['processes']=[Text.Json.Nodes.JsonArray]::new()
    return @{usable=$CompiledSchema.Evaluate($view,$Options).IsValid;complete=$false}
}

function Start-ActionRoguelikeTransportRecorder([string]$SnapshotPath,[string]$EventsPath){
    Stop-ActionRoguelikeTransportRecorder
    if(-not('ARTransportRecorder'-as[type])){Add-Type -Path (Join-Path $PSScriptRoot 'ActionRoguelikeTransportRecorder.cs')}
    foreach($path in @($SnapshotPath,$EventsPath)){
        if(-not(Test-ActionRoguelikeRegularPath $path)){throw 'run_invalid|STATE_RECORDER_PATH|The launcher channel contains a reparse point.'}
    }
    $script:ARTransportRecorder=[ARTransportRecorder]::new($SnapshotPath,$EventsPath)
}

function Stop-ActionRoguelikeTransportRecorder {
    if(Get-Variable ARTransportRecorder -Scope Script -ErrorAction SilentlyContinue){
        if($null-ne$script:ARTransportRecorder){
            $script:ARTransportRecorder.Dispose()
            $records=@($script:ARTransportRecorder.ReadRecords())
            $integrityFault=$null
            foreach($record in $records){
                if(-not(Test-ActionRoguelikeRegularPath $record.Path)-or-not(Test-Path -LiteralPath $record.Path)-or(Get-FileHash -LiteralPath $record.Path -Algorithm SHA256).Hash.ToLowerInvariant()-cne$record.Sha256){$integrityFault='Captured raw publication was removed or rewritten.';break}
            }
            $receipt=@{version='ar-independent-streams-1.0.0';fault=$(if($integrityFault){$integrityFault}else{$script:ARTransportRecorder.Fault});records=@($records|ForEach-Object{
                @{kind=$_.Kind;path=[IO.Path]::GetFileName($_.Path);sha256=$_.Sha256;byte_length=$_.ByteLength;published_utc=$_.PublishedUtc.ToString('o')}
            })}
            [IO.File]::WriteAllText(($script:ARTransportRecorder.EventsPath+'.captured/receipt.json'),($receipt|ConvertTo-Json -Depth 10))
            $fault=if($integrityFault){$integrityFault}else{$script:ARTransportRecorder.Fault}
            $script:ARTransportRecorder=$null
            if($fault){throw "run_invalid|STATE_RECORDER_FAILED|$fault"}
        }
    }
}

function Read-ActionRoguelikeIndependentStreams($Candidate,[hashtable]$Context,[int]$MaximumAgeMilliseconds,[long]$MinimumSequence,[bool]$AllowRoundSequenceResetCompatibility=$false){
    if(-not(Get-Variable ARTransportRecorder -Scope Script -ErrorAction SilentlyContinue)-or$null-eq$script:ARTransportRecorder){return $null}
    $recorder=$script:ARTransportRecorder
    if($recorder.EventsPath-cne$Candidate.events_path-or$recorder.SnapshotPath-cne$Candidate.snapshot_path){throw 'EVALUATOR_STATE_RECORDER_BINDING'}
    if($recorder.Fault){throw ('EVALUATOR_STATE_RECORDER_FAILED: '+$recorder.Fault)}
    if(-not$Context.ContainsKey('stream_records')){
        $Context.stream_records=0;$Context.stream_snapshots=@{};$Context.stream_batches=[Collections.Generic.List[object]]::new()
        $Context.stream_latest=$null;$Context.stream_schema_errors=[Collections.Generic.List[object]]::new()
        $Context.history_pairs=[Collections.Generic.List[object]]::new();$Context.stream_pair_keys=@{}
        $Context.stream_schema_options=[Json.Schema.EvaluationOptions]::new();$Context.stream_schema_options.RequireFormatValidation=$true
    }
    $records=$recorder.ReadRecords()
    foreach($record in $records){
        $file=[IO.FileInfo]::new($record.Path)
        if(-not$file.Exists-or$file.Length-ne$record.ByteLength-or$file.LastWriteTimeUtc-ne$record.PublishedUtc){throw 'state_captured_bytes_rewritten'}
    }
    foreach($record in @($records|Select-Object -Skip $Context.stream_records)){
        $bytes=Read-ActionRoguelikeBoundedDocument $record.Path 4194304
        if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()-cne$record.Sha256){throw 'state_captured_bytes_rewritten'}
        if($record.PublishedUtc-lt$Context.session_started_utc){throw 'state_before_session'}
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        $node=[Text.Json.Nodes.JsonNode]::Parse($json);$doc=$json|ConvertFrom-Json -Depth 100
        $fresh=$doc.identity.observation.freshness
        # Identity construction and its observation metadata may read the
        # clock separately. Bind both to the declared validity window rather
        # than imposing an undocumented construction order. Host publication
        # age and monotonic sequence checks remain independent requirements.
        if([Math]::Abs([double]$doc.identity.monotonic_ms-[double]$fresh.observed_monotonic_ms)-gt$fresh.valid_for_ms){throw 'state_observation_stale'}
        $options=$Context.stream_schema_options
        $valid=$Context.schemas[$record.Kind].compiled.Evaluate($node,$options).IsValid
        $usable=$valid
        # The full validation just failed. Repeating it inside the local-field
        # check can make this consumer fall behind a 10 Hz publisher.
        if($record.Kind-ceq'snapshot'-and-not$valid){$usable=(Test-ActionRoguelikeSnapshotUsability $node $Context.schemas.snapshot.compiled -KnownInvalid -Options $options).usable}
        $entry=@{document=$doc;record=$record;schema_valid=$valid;usable=$usable}
        if($record.Kind-ceq'snapshot'){
            $key=[string]$doc.identity.round_id+'/'+[string]$doc.identity.snapshot_id
            if($Context.stream_snapshots.ContainsKey($key)-and$Context.stream_snapshots[$key].record.Sha256-cne$record.Sha256){throw 'state_sequence_reused'}
            $Context.stream_snapshots[$key]=$entry;$Context.stream_latest=$entry
        }else{
            $Context.stream_batches.Add($entry)
        }
        if(-not$valid){$Context.stream_schema_errors.Add(@{kind=$record.Kind;path=Get-ActionRoguelikeRelativePath $record.Path $Context.history_run_root;sha256=$record.Sha256})}
        $Context.stream_records++
    }
    $latest=$Context.stream_latest
    if($null-eq$latest){throw 'state_publication_gap'}
    if(-not$latest.usable){throw 'snapshot_schema_invalid'}
    $s=$latest.document
    if(([DateTime]::UtcNow-$latest.record.PublishedUtc).TotalMilliseconds-gt$MaximumAgeMilliseconds){throw 'state_file_stale'}
    $roundChanged=$null-ne$Context.last_pair-and$s.identity.round_id-cne$Context.last_pair.snapshot.identity.round_id
    if($roundChanged-and$Context.seen_round_ids.Contains([string]$s.identity.round_id)){throw 'state_round_replayed'}
    $roundResetCompatibility=$AllowRoundSequenceResetCompatibility-and$roundChanged-and$s.identity.monotonic_ms-ge$Context.last_clock
    if(($s.identity.sequence-lt$Context.last_sequence-and-not$roundResetCompatibility)-or$s.identity.monotonic_ms-lt$Context.last_clock){throw 'state_sequence_regressed'}
    if($s.identity.sequence-le$MinimumSequence-and-not$roundResetCompatibility){throw 'state_sequence_not_advanced'}
    # Independently published batches refer to a retained earlier snapshot.
    # Never edit their identity, timestamps, cursor, payload or trust metadata.
    $batches=@($Context.stream_batches|Where-Object{$_.document.identity.round_id-ceq$s.identity.round_id-and$_.document.identity.monotonic_ms-le$s.identity.monotonic_ms})
    if(-not$batches.Count){throw 'state_independent_batch_pending'}
    $chainContext=@{event_epoch=$null;event_cursor_start=[long]-1;event_cursor_end=[long]-1;event_batch_id=$null;event_ids=@{};event_chain_verified=$false;event_empty_compatibility_count=0;event_sample_count=0}
    $lastSequence=[long]-1;$lastClock=[long]-1
    foreach($entry in $batches){
        if(-not$entry.schema_valid){throw 'events_schema_invalid'}
        $e=$entry.document;$key=[string]$e.identity.round_id+'/'+[string]$e.identity.snapshot_id
        if(-not$Context.stream_snapshots.ContainsKey($key)){throw 'state_captured_anchor_missing'}
        $anchor=$Context.stream_snapshots[$key].document
        $binding=Test-ActionRoguelikeStatePair $anchor $e $Context.expected_process_token $Context.expected_process_id
        if(-not$binding.valid){throw $binding.reason_code}
        if($anchor.identity.monotonic_ms-gt$e.identity.monotonic_ms-or$e.identity.sequence-le$lastSequence-or$e.identity.monotonic_ms-lt$lastClock){throw 'state_independent_batch_order'}
        foreach($event in $e.events){if($event.monotonic_ms-gt$e.identity.monotonic_ms){throw 'state_event_future'}}
        $null=Test-ActionRoguelikeEventChainStep $chainContext $e
        $lastSequence=[long]$e.identity.sequence;$lastClock=[long]$e.identity.monotonic_ms
    }
    $e=$batches[-1].document
    if($roundChanged-and$e.coverage.stream_epoch-ceq$Context.last_pair.events.coverage.stream_epoch){throw 'state_event_epoch_not_reset'}
    if($s.identity.process_token-cne$e.identity.process_token){throw 'state_pair_process_token_mismatch'}
    $retained=@($Context.stream_snapshots.Values|Where-Object{$_.document.identity.round_id-ceq$s.identity.round_id}|Sort-Object {$_.document.identity.sequence})
    foreach($frame in $retained){
        $state=$frame.document;$key=[string]$state.identity.round_id+'/'+[string]$state.identity.snapshot_id
        if($Context.stream_pair_keys.ContainsKey($key)){continue}
        $eligible=@($batches|Where-Object{$_.document.identity.monotonic_ms-le$state.identity.monotonic_ms})
        if(-not$eligible.Count){continue}
        $batch=$eligible[-1];$known=@{}
        foreach($item in $eligible){foreach($event in $item.document.events){$known[[string]$event.event_id]=$true}}
        if(@($state.recent_event_ids|Where-Object{-not$known.ContainsKey([string]$_)}).Count){continue}
        if(-not$frame.usable){continue}
        $proof=@{version='ar-independent-streams-1.0.0';snapshot_path=Get-ActionRoguelikeRelativePath $frame.record.Path $Context.history_run_root;snapshot_sha256=$frame.record.Sha256;events_path=Get-ActionRoguelikeRelativePath $batch.record.Path $Context.history_run_root;events_sha256=$batch.record.Sha256;anchor_snapshot_id=$batch.document.identity.snapshot_id;complete_snapshot_schema=[bool]$frame.schema_valid}
        $Context.history_pairs.Add(@{snapshot=$state;events=$batch.document;independent_transport=$proof})
        $Context.stream_pair_keys[$key]=$true
    }
    $available=@($Context.history_pairs|Where-Object{$_.snapshot.identity.round_id-ceq$s.identity.round_id}|Sort-Object {$_.snapshot.identity.sequence})
    if(-not$available.Count){throw 'state_independent_batch_pending'}
    $pair=$available[-1];$s=$pair.snapshot;$e=$pair.events
    $latest=$Context.stream_snapshots[([string]$s.identity.round_id+'/'+[string]$s.identity.snapshot_id)]
    if($s.identity.sequence-le$MinimumSequence-and-not$roundResetCompatibility){throw 'state_sequence_not_advanced'}
    if(([DateTime]::UtcNow-$latest.record.PublishedUtc).TotalMilliseconds-gt$MaximumAgeMilliseconds){throw 'state_file_stale'}
    $newSample=$s.identity.sequence-gt$Context.last_sequence-or$roundResetCompatibility
    $Context.last_sequence=[long]$s.identity.sequence;$Context.last_clock=[long]$s.identity.monotonic_ms
    $Context.last_pair=@{snapshot=$s;events=$e}
    [void]$Context.seen_round_ids.Add([string]$s.identity.round_id)
    $validation=New-ActionRoguelikeStatePairResult -Valid $true -ReasonCode 'ok' -IdentityBinding $binding.identity_binding -PublishedProcessToken $s.identity.process_token
    return [pscustomobject]@{success=$true;snapshot=$s;events=$e;validation=$validation;independent_transport=$pair.independent_transport;snapshot_path=$Candidate.snapshot_path;events_path=$Candidate.events_path;path_source='host_captured_independent_streams';diagnostic=@{last_reason_code='ok';new_sample=$newSample;sequence=$s.identity.sequence;event_coverage_verified=[bool]$chainContext.event_chain_verified;empty_event_batch_compatibility=($chainContext.event_empty_compatibility_count-gt0);publication_age_ms=[Math]::Max(0,([DateTime]::UtcNow-$latest.record.PublishedUtc).TotalMilliseconds);captured_snapshots=$Context.stream_snapshots.Count;captured_batches=$Context.stream_batches.Count;schema_rejections=$Context.stream_schema_errors.Count;independent_streams=$true;complete_snapshot_schema=[bool]$latest.schema_valid}}
}
