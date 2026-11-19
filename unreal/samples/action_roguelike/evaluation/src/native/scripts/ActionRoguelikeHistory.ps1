Set-StrictMode -Version Latest

# Alternate immutable transport: batches carry hash-bound references to raw
# snapshot/event facts in the same launcher-owned channel. Never search the
# project or old runs, synthesize gameplay facts, or relax chain validation.
function Read-ActionRoguelikeSplitHistoryFrame($File,$Candidate,[int]$MaximumDocumentBytes){
    $bytes=Read-ActionRoguelikeBoundedDocument $File.FullName $MaximumDocumentBytes
    $batchText=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $batch=$batchText|ConvertFrom-Json -Depth 100
    $batchNode=[Text.Json.Nodes.JsonNode]::Parse($batchText)
    $references=@($batch.evidence)
    if($references.Count-ne1){throw 'state_history_fact_reference_invalid'}
    $ref=$references[0]
    if($ref.path-cnotmatch '^records/snapshot-(0|[1-9][0-9]*)\.json$'-or$ref.media_type-cne'application/json'){throw 'state_history_fact_reference_invalid'}
    $path=Join-Path ([IO.Path]::GetDirectoryName($Candidate.snapshot_path)) $ref.path
    if(-not(Test-ActionRoguelikeRegularPath $path)){throw 'state_transport_reparse_point'}
    if(-not[IO.File]::Exists($path)){throw 'state_history_fact_missing'}
    $raw=Read-ActionRoguelikeBoundedDocument $path $MaximumDocumentBytes
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($raw)).ToLowerInvariant()
    if($hash-cne$ref.sha256-or$raw.Length-ne$ref.byte_length){throw 'state_history_fact_hash_mismatch'}
    $factsText=[Text.UTF8Encoding]::new($false,$true).GetString($raw)
    $facts=$factsText|ConvertFrom-Json -Depth 100
    $factsNode=[Text.Json.Nodes.JsonNode]::Parse($factsText)
    if($facts.snapshot.identity.snapshot_id-cne[IO.Path]::GetFileNameWithoutExtension($ref.path)-or$ref.captured_monotonic_ms-ne$facts.snapshot.identity.monotonic_ms){throw 'state_history_fact_identity_mismatch'}
    if(@($facts.events).Count-ne@($batch.events).Count){throw 'state_history_fact_events_mismatch'}
    for($i=0;$i-lt@($facts.events).Count;$i++){
        $copy=$batchNode['events'][$i].DeepClone()
        if(-not[Text.Json.Nodes.JsonNode]::DeepEquals($copy['evidence'],$batchNode['evidence'])){throw 'state_history_fact_events_mismatch'}
        [void]$copy.Remove('evidence')
        if(-not[Text.Json.Nodes.JsonNode]::DeepEquals($copy,$factsNode['events'][$i])){throw 'state_history_fact_events_mismatch'}
    }
    # The publisher adds this exact evidence envelope after hashing raw facts.
    # Copy only the envelope; all snapshot fields come from the hash-bound bytes.
    $snapshotNode=$factsNode['snapshot'].DeepClone()
    $snapshotNode['evidence']=$batchNode['evidence'].DeepClone()
    $pairNode=[Text.Json.Nodes.JsonObject]::new()
    $pairNode['snapshot']=$snapshotNode;$pairNode['events']=$batchNode
    return @{node=$pairNode;source_bytes=$bytes;fact_path=$path;fact_sha256=$hash}
}

# History is a live, launcher-owned transport, not a search through old evidence.
# Keep every coherent pair so a slow input/capture call cannot discard events.
function Read-ActionRoguelikeHistory {
    param($Candidate,[hashtable]$Context,[int]$MaximumDocumentBytes,[int]$MaximumAgeMilliseconds,
        [long]$MinimumSequence,[Diagnostics.Stopwatch]$Watch,[int]$TimeoutMilliseconds)
    $token=[string]$Context.expected_process_token
    if($Context.ContainsKey('stream_records')){return $null}
    if($Context.ContainsKey('history_fault')){throw $Context.history_fault}
    if($token -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){throw 'state_history_token_invalid'}
    $root=$Candidate.events_path+'.history'
    if(-not(Test-ActionRoguelikeRegularPath $root)){throw 'state_transport_reparse_point'}
    $splitRoot=Join-Path ([IO.Path]::GetDirectoryName($Candidate.events_path)) 'batches'
    $split=-not[IO.Directory]::Exists($root)-and[IO.Directory]::Exists($splitRoot)
    if(-not[IO.Directory]::Exists($root)-and-not$split-and-not$Context.ContainsKey('history_pairs')){return $null}
    if($Context.ContainsKey('history_format')){
        if(($Context.history_format-ceq'split_immutable_facts')-ne$split){throw 'state_history_transport_changed'}
    }
    $root=if($split){$splitRoot}else{Join-Path $root $token}
    if(-not(Test-ActionRoguelikeRegularPath $root)){throw 'state_transport_reparse_point'}
    $factsRoot=Join-Path ([IO.Path]::GetDirectoryName($Candidate.snapshot_path)) 'records'
    if($split-and-not(Test-ActionRoguelikeRegularPath $factsRoot)){throw 'state_transport_reparse_point'}
    $factFiles=@{}
    if($split-and[IO.Directory]::Exists($factsRoot)){
        foreach($fact in [IO.DirectoryInfo]::new($factsRoot).EnumerateFiles('snapshot-*.json')){$factFiles[$fact.Name]=$fact}
    }
    if(-not$Context.ContainsKey('history_pairs')){
        $Context.history_pairs=[Collections.Generic.List[object]]::new()
        $Context.history_files=@{};$Context.history_rounds=[Collections.Generic.HashSet[string]]::new()
        $Context.history_epochs=[Collections.Generic.HashSet[string]]::new()
        $Context.history_event_ids=[Collections.Generic.HashSet[string]]::new()
        $Context.history_event_clock=[long]-1
        $Context.history_transport=$Candidate.events_path
        $Context.history_format=if($split){'split_immutable_facts'}else{'coherent_pairs'}
    }
    if($Context.history_transport -cne $Candidate.events_path){throw 'state_history_transport_changed'}
    if(-not[IO.Directory]::Exists($root)){throw 'state_history_process_missing'}
    $files=[Collections.Generic.List[object]]::new()
    $rounds=if($split){@($root)}else{@([IO.Directory]::EnumerateDirectories($root))}
    foreach($round in $rounds){
        if(-not(Test-ActionRoguelikeRegularPath $round)){throw 'state_transport_reparse_point'}
        foreach($file in [IO.DirectoryInfo]::new($round).EnumerateFiles('*.json')){
            if(($file.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'state_transport_reparse_point'}
            if($split){
                if($file.BaseName-cnotmatch '^batch-(0|[1-9][0-9]*)$'){throw 'state_history_filename_invalid'}
                $fileSequence=[long]$Matches[1]
            }else{
                if($file.BaseName -cnotmatch '^\d{20}$'){throw 'state_history_filename_invalid'}
                $fileSequence=[long]$file.BaseName
            }
            $files.Add(@{file=$file;sequence=$fileSequence})
        }
    }
    $ordered=@($files|Sort-Object { $_.sequence })
    if($ordered.Count-lt$Context.history_pairs.Count){throw 'state_history_truncated'}
    $previousSequence=$Context.last_sequence
    foreach($entry in $ordered){
        $file=$entry.file
        $stamp="$($file.Length):$($file.LastWriteTimeUtc.Ticks)"
        if($split){
            $factFile=$factFiles["snapshot-$($entry.sequence).json"]
            # A publisher may complete a new fact+batch between the two
            # directory enumerations. Resolve that exact new fact once before
            # deciding it is missing; the cached inventory is not authoritative.
            if($null-eq$factFile){$factFile=[IO.FileInfo]::new([IO.Path]::Combine($factsRoot,"snapshot-$($entry.sequence).json"))}
            if(-not$factFile.Exists){throw 'state_history_fact_missing'}
            # Parent chain is checked once above. Rewalking every ancestor of
            # every retained fact on each poll starves the live read budget.
            if(($factFile.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'state_transport_reparse_point'}
            $stamp+=":$($factFile.Length):$($factFile.LastWriteTimeUtc.Ticks)"
            if($factFile.LastWriteTimeUtc-lt$Context.session_started_utc){throw 'state_before_session'}
        }
        if($Context.history_files.ContainsKey($file.FullName)){
            if($Context.history_files[$file.FullName] -cne $stamp){throw 'state_history_rewritten'}
            continue
        }
        if($Watch.Elapsed.TotalMilliseconds-ge($TimeoutMilliseconds-15)){break}
        if($file.LastWriteTimeUtc-lt$Context.session_started_utc){throw 'state_before_session'}
        if($split){
            $frame=Read-ActionRoguelikeSplitHistoryFrame $file $Candidate $MaximumDocumentBytes
            $bytes=$frame.source_bytes
            $node=$frame.node
            $frameText=$node.ToJsonString()
        }else{
            $bytes=Read-ActionRoguelikeBoundedDocument $file.FullName $MaximumDocumentBytes
            $frameText=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
            $node=[Text.Json.Nodes.JsonNode]::Parse($frameText,$null,[Text.Json.JsonDocumentOptions]::new())
        }
        $frame=$frameText|ConvertFrom-Json -Depth 100
        $s=$frame.snapshot;$e=$frame.events
        $validation=Test-ActionRoguelikeStatePair $s $e $token $Context.expected_process_id
        if(-not$validation.valid){throw $validation.reason_code}
        foreach($name in @('snapshot','events')){
            $options=[Json.Schema.EvaluationOptions]::new();$options.RequireFormatValidation=$true
            if(-not$Context.schemas[$name].compiled.Evaluate($node[$name],$options).IsValid){throw ($name+'_schema_invalid')}
        }
        $Context.validation_count++
        $seq=[long]$s.identity.sequence;$clock=[long]$s.identity.monotonic_ms
        if($seq-ne$Context.history_pairs.Count-or$entry.sequence-ne$seq){throw 'state_history_sequence_gap'}
        if(-not$split-and$s.identity.round_id-cne$file.Directory.Name){throw 'state_history_round_path_mismatch'}
        if($split-and$e.identity.batch_id-cne$file.BaseName){throw 'state_history_fact_identity_mismatch'}
        if($e.identity.sequence-ne$seq-or$e.identity.monotonic_ms-ne$clock-or$clock-lt$Context.last_clock){throw 'state_history_pair_clock_or_sequence'}
        foreach($fresh in @($s.identity.observation.freshness,$e.identity.observation.freshness)){
            if($clock-lt$fresh.observed_monotonic_ms-or$clock-$fresh.observed_monotonic_ms-gt$fresh.valid_for_ms){throw 'state_observation_stale'}
        }
        $prior=if($Context.history_pairs.Count){$Context.history_pairs[-1]}else{$null}
        $newRound=-not$prior-or$s.identity.round_id-cne$prior.snapshot.identity.round_id
        $c=$e.coverage
        if($newRound){
            if($Context.history_rounds.Contains($s.identity.round_id)-or$Context.history_epochs.Contains($c.stream_epoch)-or$c.cursor_start-ne0-or$null-ne$c.previous_batch_id){throw 'state_history_round_start_invalid'}
        }elseif($c.stream_epoch-cne$prior.events.coverage.stream_epoch-or$c.previous_batch_id-cne$prior.events.identity.batch_id-or$c.cursor_start-ne$prior.events.coverage.cursor_end){throw 'state_history_event_link'}
        if(@($e.events).Count-ne($c.cursor_end-$c.cursor_start)){throw 'state_event_chain_count_mismatch'}
        $ids=[Collections.Generic.HashSet[string]]::new();$eventClock=$Context.history_event_clock;$cursor=[long]$c.cursor_start
        foreach($event in $e.events){
            if($event.sequence-ne$cursor-or$Context.history_event_ids.Contains($event.event_id)-or-not$ids.Add($event.event_id)){throw 'state_history_event_sequence_or_duplicate'}
            if($event.monotonic_ms-lt$eventClock-or$event.monotonic_ms-gt$clock){throw 'state_history_event_clock'}
            $eventClock=[long]$event.monotonic_ms;$cursor++
        }
        foreach($id in $s.recent_event_ids){if(-not$ids.Contains($id)){throw 'state_history_recent_event_unbound'}}
        # Commit reader state only after the whole immutable pair validates.
        foreach($id in $ids){[void]$Context.history_event_ids.Add($id)}
        [void]$Context.history_rounds.Add($s.identity.round_id);[void]$Context.history_epochs.Add($c.stream_epoch)
        $Context.history_event_clock=$eventClock
        $Context.history_files[$file.FullName]=$stamp
        $retained=@{snapshot=$s;events=$e;history_path=(Get-ActionRoguelikeRelativePath $file.FullName $Context.history_run_root);history_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()}
        if($split){$retained.fact_path=Get-ActionRoguelikeRelativePath $factFile.FullName $Context.history_run_root;$retained.fact_sha256=$e.evidence[0].sha256}
        $Context.history_pairs.Add($retained)
        $Context.last_sequence=$seq;$Context.last_clock=$clock;$Context.last_event_sequence=$seq
        $Context.last_pair=@{snapshot=$s;events=$e;validation=$validation}
        $Context.history_last_write_utc=$file.LastWriteTimeUtc
    }
    if(-not$Context.history_pairs.Count-or$Context.history_files.Count-ne$ordered.Count){throw 'state_history_pending'}
    if($Context.last_sequence-le$MinimumSequence){throw 'state_sequence_not_advanced'}
    if(([DateTime]::UtcNow-$Context.history_last_write_utc).TotalMilliseconds-gt$MaximumAgeMilliseconds-or$Context.history_last_write_utc-gt[DateTime]::UtcNow.AddSeconds(1)){throw 'state_file_stale'}
    $pair=$Context.last_pair
    return [pscustomobject]@{
        success=$true;snapshot=$pair.snapshot;events=$pair.events;validation=$pair.validation
        snapshot_path=$Candidate.snapshot_path;events_path=$Candidate.events_path;path_source=$(if($split){'launcher_owned_split_event_history'}else{'launcher_owned_event_history'})
        diagnostic=[pscustomobject]@{attempts=1;elapsed_ms=$Watch.Elapsed.TotalMilliseconds;last_reason_code='ok';new_sample=($Context.last_sequence-gt$previousSequence);sequence=$Context.last_sequence;schema_cache_hit=($Context.last_sequence-eq$previousSequence);timeout_ms=$TimeoutMilliseconds;event_coverage_verified=$true;empty_event_batch_compatibility=$false;round_sequence_reset_compatibility=$false;history_pair_count=$Context.history_pairs.Count;history_path=$Context.history_pairs[-1].history_path;publication_age_ms=[Math]::Max(0,([DateTime]::UtcNow-$Context.history_last_write_utc).TotalMilliseconds)}
    }
}

function Expand-ActionRoguelikeHistoryWindow($Samples,[hashtable]$Context,[switch]$FromRoundStart){
    if(-not$Samples.Count-or-not$Context.ContainsKey('history_pairs')){return ,@($Samples)}
    $first=$Samples[0].snapshot.identity;$last=$Samples[-1].snapshot.identity
    return ,@($Context.history_pairs|Where-Object{($FromRoundStart-or$_.snapshot.identity.sequence-ge$first.sequence)-and$_.snapshot.identity.sequence-le$last.sequence-and$_.snapshot.identity.round_id-ceq$first.round_id})
}

function Get-ActionRoguelikeUiRoles($Snapshot,[hashtable]$Context){
    $roles=@{}
    foreach($item in @($Snapshot.ui)){
        if($item.semantic_role.trust-in@('verified','corroborated')-and$item.visible.value-eq$true){$roles[$item.semantic_role.value]=$true}
    }
    if($Context.ContainsKey('history_pairs')){
        foreach($pair in $Context.history_pairs){
            if($pair.snapshot.identity.round_id-cne$Snapshot.identity.round_id-or$pair.snapshot.identity.sequence-gt$Snapshot.identity.sequence){continue}
            foreach($event in $pair.events.events){
                if($event.event_type-in@('ui_value_changed','ui_visibility_changed')-and$event.observation.trust-in@('verified','corroborated')){
                    $roles[$event.payload.ui_role]=[bool]$event.payload.visible
                }
            }
        }
    }
    return @($roles.Keys|Where-Object{$roles[$_] }|Sort-Object)
}
