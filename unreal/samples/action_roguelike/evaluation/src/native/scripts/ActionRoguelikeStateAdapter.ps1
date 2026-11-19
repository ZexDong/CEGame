Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ActionRoguelikeHistory.ps1')
. (Join-Path $PSScriptRoot 'ActionRoguelikeIndependentStreams.ps1')

function Get-ActionRoguelikePropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-ActionRoguelikePathValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Path
    )

    $current = $InputObject
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) { return $null }
        $current = Get-ActionRoguelikePropertyValue -InputObject $current -Name $segment
    }
    return $current
}

function Get-ActionRoguelikeObservedValue {
    param([AllowNull()]$Observed)
    return Get-ActionRoguelikePropertyValue -InputObject $Observed -Name 'value'
}

function Get-ActionRoguelikeObservedPathValue {
    param(
        [AllowNull()]$State,
        [Parameter(Mandatory)][string]$Path
    )

    $observed = Get-ActionRoguelikePathValue -InputObject $State -Path $Path
    return Get-ActionRoguelikeObservedValue -Observed $observed
}

function Get-ActionRoguelikeVectorMagnitude {
    param([AllowNull()]$Vector)

    if ($null -eq $Vector) { return $null }
    $x = Get-ActionRoguelikePropertyValue -InputObject $Vector -Name 'x'
    $y = Get-ActionRoguelikePropertyValue -InputObject $Vector -Name 'y'
    if ($null -eq $x -or $null -eq $y) { return $null }
    return [Math]::Sqrt(([double]$x * [double]$x) + ([double]$y * [double]$y))
}

function New-ActionRoguelikeStatePairResult {
    param(
        [Parameter(Mandatory)][bool]$Valid,
        [Parameter(Mandatory)][string]$ReasonCode,
        [string]$IdentityBinding = $null,
        [string]$PublishedProcessToken = $null
    )

    return [pscustomobject][ordered]@{
        valid = $Valid
        reason_code = $ReasonCode
        identity_binding = $IdentityBinding
        published_process_token = $PublishedProcessToken
    }
}

function Test-ActionRoguelikeStatePair {
    [CmdletBinding()]
    param(
        [AllowNull()]$Snapshot,
        [AllowNull()]$Events,
        [Parameter(Mandatory)][string]$ExpectedProcessToken,
        [Parameter(Mandatory)][int]$ExpectedProcessId
    )

    if ($null -eq $Snapshot -or $null -eq $Events) {
        return New-ActionRoguelikeStatePairResult -Valid $false -ReasonCode 'state_pair_missing'
    }

    try {
        if ([string](Get-ActionRoguelikePropertyValue $Snapshot 'schema_version') -cne '1.0.0' -or
            [string](Get-ActionRoguelikePropertyValue $Events 'schema_version') -cne '2.0.0') {
            return New-ActionRoguelikeStatePairResult -Valid $false -ReasonCode 'state_schema_version_mismatch'
        }

        $snapshotToken = [string](Get-ActionRoguelikePathValue $Snapshot 'identity.process_token')
        $eventsToken = [string](Get-ActionRoguelikePathValue $Events 'identity.process_token')
        if ([string]::IsNullOrWhiteSpace($snapshotToken) -or $snapshotToken -cne $eventsToken) {
            return New-ActionRoguelikeStatePairResult -Valid $false -ReasonCode 'state_pair_process_token_mismatch'
        }

        $identityBinding = $null
        if ($snapshotToken -ceq $ExpectedProcessToken) {
            $identityBinding = 'launcher_process_token'
        }
        elseif ($ExpectedProcessId -gt 0 -and $snapshotToken -cin @("process-$ExpectedProcessId","proc-$ExpectedProcessId","pid$ExpectedProcessId")) {
            # Some valid in-process publishers bind directly to the active OS
            # process identity instead of echoing the launcher nonce.  This is
            # accepted only for the exact PID owned by the active executor
            # session; arbitrary self-selected tokens remain invalid.
            $identityBinding = 'active_process_id'
        }
        else {
            return New-ActionRoguelikeStatePairResult -Valid $false `
                -ReasonCode 'state_process_identity_mismatch' `
                -PublishedProcessToken $snapshotToken
        }

        $snapshotRound = [string](Get-ActionRoguelikePathValue $Snapshot 'identity.round_id')
        $eventsRound = [string](Get-ActionRoguelikePathValue $Events 'identity.round_id')
        $snapshotId = [string](Get-ActionRoguelikePathValue $Snapshot 'identity.snapshot_id')
        $eventsSnapshotId = [string](Get-ActionRoguelikePathValue $Events 'identity.snapshot_id')
        if ([string]::IsNullOrWhiteSpace($snapshotRound) -or $snapshotRound -cne $eventsRound -or
            [string]::IsNullOrWhiteSpace($snapshotId) -or $snapshotId -cne $eventsSnapshotId) {
            return New-ActionRoguelikeStatePairResult -Valid $false -ReasonCode 'state_pair_identity_mismatch'
        }

        $cursorStart = Get-ActionRoguelikePathValue $Events 'coverage.cursor_start'
        $cursorEnd = Get-ActionRoguelikePathValue $Events 'coverage.cursor_end'
        $head = Get-ActionRoguelikePathValue $Events 'coverage.head_watermark'
        $tail = Get-ActionRoguelikePathValue $Events 'coverage.tail_watermark'
        $dropped = Get-ActionRoguelikePathValue $Events 'coverage.dropped_event_count'
        if ($null -eq $cursorStart -or $null -eq $cursorEnd -or $null -eq $head -or
            $null -eq $tail -or $null -eq $dropped -or
            [long]$cursorStart -ne [long]$head -or [long]$cursorEnd -ne [long]$tail -or
            [long]$cursorEnd -lt [long]$cursorStart -or [long]$dropped -ne 0) {
            return New-ActionRoguelikeStatePairResult -Valid $false -ReasonCode 'state_event_coverage_invalid'
        }

        $actions = @(
            @(Get-ActionRoguelikePropertyValue $Snapshot 'controls') |
                ForEach-Object { [string](Get-ActionRoguelikePropertyValue $_ 'semantic_action') }
        )
        foreach ($required in @(
            'move_forward','move_backward','move_left','move_right','jump','sprint',
            'primary_attack','black_hole','teleport','interact','restart')) {
            if ($required -notin $actions) {
                return New-ActionRoguelikeStatePairResult -Valid $false -ReasonCode 'state_required_control_missing'
            }
        }

        return New-ActionRoguelikeStatePairResult -Valid $true -ReasonCode 'ok' `
            -IdentityBinding $identityBinding -PublishedProcessToken $snapshotToken
    }
    catch {
        return New-ActionRoguelikeStatePairResult -Valid $false -ReasonCode 'state_pair_shape_invalid'
    }
}

function Test-ActionRoguelikePathUnderRoot {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
        return $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-ActionRoguelikeRelativePath {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    if (-not (Test-ActionRoguelikePathUnderRoot $Path $Root)) { return $null }
    return [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root), [IO.Path]::GetFullPath($Path)).Replace('\','/')
}

function Test-ActionRoguelikeRegularPath {
    param([Parameter(Mandatory)][string]$Path)
    # Check every existing ancestor too: a regular file inside a junction is
    # still outside the launcher's exclusive transport in filesystem terms.
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $true
}

function New-ActionRoguelikeStateReaderContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SnapshotSchemaPath,
        [Parameter(Mandatory)][string]$EventsSchemaPath,
        [Parameter(Mandatory)][string]$ExpectedProcessToken,
        [Parameter(Mandatory)][int]$ExpectedProcessId,
        [DateTime]$SessionStartedUtc = [DateTime]::MinValue
    )
    $schemas = @{}
    foreach ($entry in @(@('snapshot',$SnapshotSchemaPath), @('events',$EventsSchemaPath))) {
        $name = [string]$entry[0]; $path = [IO.Path]::GetFullPath([string]$entry[1])
        if (-not [IO.File]::Exists($path) -or -not (Test-ActionRoguelikeRegularPath $path)) {
            throw "EVALUATOR_STATE_SCHEMA_UNAVAILABLE:$name"
        }
        try {
            $schemaText = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false,$true))
            $parsed = $schemaText | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            if ([string](Get-ActionRoguelikePropertyValue $parsed '$schema') -ne 'https://json-schema.org/draft/2020-12/schema') {
                throw 'Unsupported schema dialect.'
            }
            # Compile the schema before candidate reads. Instance rejection is
            # expected; schema/parser errors are evaluator authoring failures.
            $schemaErrors = @()
            $null = '{}' | Test-Json -Schema $schemaText -ErrorAction SilentlyContinue -ErrorVariable schemaErrors
            if (@($schemaErrors | Where-Object { $_.FullyQualifiedErrorId -notlike 'InvalidJsonAgainstSchema*' }).Count) {
                throw 'Invalid evaluator schema.'
            }
            $schemas[$name] = @{path=$path;text=$schemaText;compiled=[Json.Schema.JsonSchema]::FromText($schemaText);sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($schemaText))).ToLowerInvariant()}
        } catch { throw "EVALUATOR_STATE_SCHEMA_INVALID:$name" }
    }
    return @{
        expected_process_token=$ExpectedProcessToken;expected_process_id=$ExpectedProcessId
        session_started_utc=$SessionStartedUtc.ToUniversalTime();schemas=$schemas
        last_sequence=[long]-1;last_clock=[long]-1;last_event_sequence=[long]-1;last_snapshot_id=$null;last_document_hash=$null
        last_progress_ticks=[long]0;last_pair=$null;validation_count=0
        seen_round_ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        # Event continuity is tracked independently from snapshot freshness. A
        # publisher may expose cumulative batches (cursor_start remains zero) or
        # incremental batches (cursor_start equals the previous cursor_end), but
        # it must never silently jump epochs, omit a batch link, or rewrite an
        # already published event ID.
        event_epoch=$null;event_cursor_start=[long]-1;event_cursor_end=[long]-1;event_batch_id=$null
        event_ids=@{};event_chain_verified=$false;event_empty_compatibility_count=0;event_sample_count=0
    }
}

function Test-ActionRoguelikeEventChainStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$ReaderContext,
        [Parameter(Mandatory)]$Events,
        [switch]$RoundReset,
        [switch]$AllowEmptyCompatibility
    )

    $coverage = Get-ActionRoguelikePathValue $Events 'coverage'
    $epoch = [string](Get-ActionRoguelikePropertyValue $coverage 'stream_epoch')
    $batchId = [string](Get-ActionRoguelikePathValue $Events 'identity.batch_id')
    $start = [long](Get-ActionRoguelikePropertyValue $coverage 'cursor_start')
    $end = [long](Get-ActionRoguelikePropertyValue $coverage 'cursor_end')
    $previous = Get-ActionRoguelikePropertyValue $coverage 'previous_batch_id'
    $batchEvents = @(Get-ActionRoguelikePropertyValue $Events 'events')
    if ($RoundReset) {
        $ReaderContext.event_epoch=$null
        $ReaderContext.event_cursor_start=[long]-1
        $ReaderContext.event_cursor_end=[long]-1
        $ReaderContext.event_batch_id=$null
        $ReaderContext.event_ids=@{}
        $ReaderContext.event_chain_verified=$false
        $ReaderContext.event_sample_count=0
        $ReaderContext.event_empty_compatibility_count=0
    }
    if ([string]::IsNullOrWhiteSpace($epoch) -or [string]::IsNullOrWhiteSpace($batchId) -or $end -lt $start) {
        throw 'state_event_chain_invalid'
    }
    if ($batchEvents.Count -ne ($end - $start)) { throw 'state_event_chain_count_mismatch' }
    for ($index = 0; $index -lt $batchEvents.Count; $index++) {
        $event = $batchEvents[$index]
        if ([long](Get-ActionRoguelikePropertyValue $event 'sequence') -ne ($start + $index)) {
            throw 'state_event_chain_sequence_gap'
        }
        $eventId = [string](Get-ActionRoguelikePropertyValue $event 'event_id')
        if ([string]::IsNullOrWhiteSpace($eventId)) { throw 'state_event_chain_event_id_missing' }
        $serialized = $event | ConvertTo-Json -Depth 100 -Compress
        if ($ReaderContext.event_ids.ContainsKey($eventId) -and $ReaderContext.event_ids[$eventId] -cne $serialized) {
            throw 'state_event_chain_event_rewritten'
        }
        $ReaderContext.event_ids[$eventId] = $serialized
    }

    $emptyCompatibility = $AllowEmptyCompatibility -and $batchEvents.Count -eq 0 -and
        $start -eq 0 -and $end -eq 0 -and $null -eq $previous
    $emptyShape = $batchEvents.Count -eq 0 -and $start -eq 0 -and $end -eq 0 -and $null -eq $previous
    $first = $ReaderContext.event_cursor_end -lt 0 -or $RoundReset
    if (-not $first -and [string]$ReaderContext.event_epoch -cne $epoch) { throw 'state_event_chain_epoch_changed' }
    if ($first) {
        if ($start -ne 0 -or $null -ne $previous) { throw 'state_event_chain_first_batch_invalid' }
    }
    elseif ($emptyShape) {
        if ([long]$ReaderContext.event_cursor_end -gt 0) { throw 'state_event_chain_cumulative_truncated' }
        # Legacy snapshot heartbeats are usable for transport health only.
        # They cannot erase an observed event or establish absence of events.
    }
    else {
        if ([string]$ReaderContext.event_epoch -cne $epoch) { throw 'state_event_chain_epoch_changed' }
        if ([string]$previous -cne [string]$ReaderContext.event_batch_id) { throw 'state_event_chain_previous_batch_mismatch' }
        # A batch is either cumulative (same cursor_start, all old events
        # repeated byte-for-byte) or incremental (starts exactly at the prior
        # cursor_end). Partial overlap is a publication gap.
        $cumulative = $start -eq [long]$ReaderContext.event_cursor_start
        $incremental = $start -eq [long]$ReaderContext.event_cursor_end
        if (-not ($cumulative -or $incremental)) { throw 'state_event_chain_cursor_gap' }
        if ($end -lt [long]$ReaderContext.event_cursor_end) {
            throw 'state_event_chain_cumulative_truncated'
        }
    }
    $ReaderContext.event_epoch=$epoch
    $ReaderContext.event_cursor_start=$start
    $ReaderContext.event_cursor_end=$end
    $ReaderContext.event_batch_id=$batchId
    $ReaderContext.event_sample_count++
    if ($emptyShape) {
        $ReaderContext.event_empty_compatibility_count++
        $ReaderContext.event_chain_verified=$false
    }
    else {
        $ReaderContext.event_chain_verified=$ReaderContext.event_sample_count -ge 2
    }
    return [pscustomobject]@{
        verified=[bool]$ReaderContext.event_chain_verified
        empty_compatibility=[bool]$emptyCompatibility
        epoch=$epoch;batch_id=$batchId;cursor_start=$start;cursor_end=$end
        unique_event_count=$ReaderContext.event_ids.Count
    }
}

function Get-ActionRoguelikeStateCandidatePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [string]$SnapshotSchemaPath, [string]$EventsSchemaPath,
        [string]$PreferredSnapshotPath, [string]$PreferredEventsPath,
        [object[]]$DeclaredPathPairs = @(), [int]$ProcessId = 0
    )
    # Only launcher-owned declarations are permitted. Do not inspect CIM,
    # enumerate candidate files, or recover copies from evidence/history.
    $pairs = [Collections.Generic.List[object]]::new()
    if ($PreferredSnapshotPath -or $PreferredEventsPath) {
        $pairs.Add(@{snapshot_path=$PreferredSnapshotPath;events_path=$PreferredEventsPath;source='launcher_generated_transport'})
    }
    if ($DeclaredPathPairs.Count -gt 4) { throw 'EVALUATOR_STATE_TRANSPORT_TOO_MANY_PATHS' }
    foreach ($pair in $DeclaredPathPairs) {
        $pairs.Add(@{snapshot_path=(Get-ActionRoguelikePropertyValue $pair 'snapshot_path');events_path=(Get-ActionRoguelikePropertyValue $pair 'events_path');source='launcher_declared_transport'})
    }
    if (-not $pairs.Count) { throw 'EVALUATOR_STATE_TRANSPORT_UNDECLARED' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pair in $pairs) {
        foreach ($field in @('snapshot_path','events_path')) {
            $path = [string]$pair[$field]
            if ([string]::IsNullOrWhiteSpace($path) -or -not [IO.Path]::IsPathFullyQualified($path) -or
                -not (Test-ActionRoguelikePathUnderRoot $path $RunRoot)) { throw 'EVALUATOR_STATE_TRANSPORT_OUTSIDE_RUN' }
            $relative = Get-ActionRoguelikeRelativePath $path $RunRoot
            if ($relative -match '(^|/)(receipts|states|captures|logs|d6|canonical-result|history|evaluation|evidence|results)(/|$)') {
                throw 'EVALUATOR_STATE_TRANSPORT_EVIDENCE_PATH'
            }
            if ($relative.Contains(':')) { throw 'EVALUATOR_STATE_TRANSPORT_ALTERNATE_STREAM' }
            $pair[$field] = [IO.Path]::GetFullPath($path)
        }
        if ($pair.snapshot_path -ieq $pair.events_path) { throw 'EVALUATOR_STATE_TRANSPORT_PATH_COLLISION' }
        if ($seen.Add("$($pair.snapshot_path)`n$($pair.events_path)")) { [pscustomobject]$pair }
    }
}

function Read-ActionRoguelikeBoundedDocument {
    param([string]$Path, [int]$MaximumDocumentBytes)
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if ($stream.Length -lt 2 -or $stream.Length -gt $MaximumDocumentBytes) { throw 'state_document_size_invalid' }
        $bytes = [byte[]]::new([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($read -le 0) { throw 'state_publication_gap' }
            $offset += $read
        }
        return ,$bytes
    } finally { if ($stream) { $stream.Dispose() } }
}

function Resolve-ActionRoguelikeStatePair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$SnapshotSchemaPath,
        [Parameter(Mandatory)][string]$EventsSchemaPath,
        [Parameter(Mandatory)][string]$ExpectedProcessToken,
        [Parameter(Mandatory)][int]$ExpectedProcessId,
        [string]$PreferredSnapshotPath, [string]$PreferredEventsPath,
        [object[]]$DeclaredPathPairs = @(), [hashtable]$ReaderContext,
        [ValidateRange(1,5000)][int]$TimeoutMilliseconds = 500,
        [ValidateRange(1,1000)][int]$PollMilliseconds = 25,
        [ValidateRange(1,600000)][int]$MaximumAgeMilliseconds = 2000,
        [ValidateRange(1024,16777216)][int]$MaximumDocumentBytes = 4194304,
        [long]$MinimumSequence = -1, [switch]$RequireNewSample,
        [switch]$AllowEmptyEventBatchCompatibility,
        [switch]$AllowRoundSequenceResetCompatibility,
        [DateTime]$SessionStartedUtc = [DateTime]::MinValue
    )
    $candidates = @(Get-ActionRoguelikeStateCandidatePaths -RunRoot $RunRoot -PreferredSnapshotPath $PreferredSnapshotPath -PreferredEventsPath $PreferredEventsPath -DeclaredPathPairs $DeclaredPathPairs)
    if (-not $ReaderContext) {
        $ReaderContext = New-ActionRoguelikeStateReaderContext -SnapshotSchemaPath $SnapshotSchemaPath -EventsSchemaPath $EventsSchemaPath -ExpectedProcessToken $ExpectedProcessToken -ExpectedProcessId $ExpectedProcessId -SessionStartedUtc $SessionStartedUtc
    }
    if ($ReaderContext.expected_process_token -cne $ExpectedProcessToken -or $ReaderContext.expected_process_id -ne $ExpectedProcessId -or
        $ReaderContext.schemas.snapshot.path -ine [IO.Path]::GetFullPath($SnapshotSchemaPath) -or
        $ReaderContext.schemas.events.path -ine [IO.Path]::GetFullPath($EventsSchemaPath)) { throw 'EVALUATOR_STATE_READER_CONTEXT_MISMATCH' }
    if ($RequireNewSample) { $MinimumSequence = [Math]::Max($MinimumSequence,$ReaderContext.last_sequence) }
    $ReaderContext.history_run_root=$RunRoot
    $watch = [Diagnostics.Stopwatch]::StartNew(); $attempts=0; $lastReason='state_pair_missing'
    $parsedDocumentHash=$null; $parsedPair=$null; $budgetExhausted=$false
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    do {
        foreach ($candidate in $candidates) {
            if ($watch.Elapsed.TotalMilliseconds -ge $TimeoutMilliseconds) { break }
            ++$attempts
            $eventStateBefore=$null
            try {
                $history=Read-ActionRoguelikeHistory $candidate $ReaderContext $MaximumDocumentBytes $MaximumAgeMilliseconds $MinimumSequence $watch $TimeoutMilliseconds
                if($null-ne$history){return $history}
                $independent=Read-ActionRoguelikeIndependentStreams $candidate $ReaderContext $MaximumAgeMilliseconds $MinimumSequence $AllowRoundSequenceResetCompatibility
                if($null-ne$independent){return $independent}
                $publicationUtc=[DateTime]::MinValue
                foreach ($path in @($candidate.snapshot_path,$candidate.events_path)) {
                    if (-not (Test-ActionRoguelikeRegularPath $path)) { throw 'state_transport_reparse_point' }
                    if (-not [IO.File]::Exists($path)) { throw 'state_publication_gap' }
                    $written = [IO.File]::GetLastWriteTimeUtc($path)
                    if($written-gt$publicationUtc){$publicationUtc=$written}
                    if ($written -lt $ReaderContext.session_started_utc) { throw 'state_before_session' }
                    if (([DateTime]::UtcNow-$written).TotalMilliseconds -gt $MaximumAgeMilliseconds -or $written -gt [DateTime]::UtcNow.AddSeconds(1)) { throw 'state_file_stale' }
                }
                $snapshotBytes = Read-ActionRoguelikeBoundedDocument $candidate.snapshot_path $MaximumDocumentBytes
                $eventsBytes = Read-ActionRoguelikeBoundedDocument $candidate.events_path $MaximumDocumentBytes
                $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($snapshotBytes)) + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($eventsBytes))
                $cached = $hash -ceq $ReaderContext.last_document_hash -and $null -ne $ReaderContext.last_pair
                if ($cached) {
                    $snapshot=$ReaderContext.last_pair.snapshot; $events=$ReaderContext.last_pair.events; $validation=$ReaderContext.last_pair.validation
                } elseif ($hash -ceq $parsedDocumentHash -and $null -ne $parsedPair) {
                    # A coherent frame rejected for sequence/freshness may be
                    # retried until publication advances, without recompiling
                    # its schemas on every poll in the same read budget.
                    $snapshot=$parsedPair.snapshot; $events=$parsedPair.events; $validation=$parsedPair.validation
                } else {
                    $snapshotText=$utf8.GetString($snapshotBytes); $eventsText=$utf8.GetString($eventsBytes)
                    $snapshot=$snapshotText | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                    $events=$eventsText | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                    $validation = Test-ActionRoguelikeStatePair $snapshot $events $ExpectedProcessToken $ExpectedProcessId
                    if (-not $validation.valid) {
                        # Retain precise schema diagnostics for malformed objects,
                        # while rejecting wrong identity/torn frames immediately.
                        if ($validation.reason_code -notin @('state_schema_version_mismatch','state_pair_shape_invalid')) { throw ([string]$validation.reason_code) }
                    }
                    if ($watch.Elapsed.TotalMilliseconds -ge $TimeoutMilliseconds) { throw 'state_read_budget_exhausted' }
                    $ReaderContext.validation_count++
                    if (-not ($snapshotText | Test-Json -Schema $ReaderContext.schemas.snapshot.text -ErrorAction SilentlyContinue)) { throw 'snapshot_schema_invalid' }
                    if ($watch.Elapsed.TotalMilliseconds -ge $TimeoutMilliseconds) { throw 'state_read_budget_exhausted' }
                    if (-not ($eventsText | Test-Json -Schema $ReaderContext.schemas.events.text -ErrorAction SilentlyContinue)) { throw 'events_schema_invalid' }
                    if (-not $validation.valid) { throw ([string]$validation.reason_code) }
                    $parsedDocumentHash=$hash
                    $parsedPair=@{snapshot=$snapshot;events=$events;validation=$validation}
                }
                $sequence=[long]$snapshot.identity.sequence; $clock=[long]$snapshot.identity.monotonic_ms
                $eventSequence=[long]$events.identity.sequence
                $roundChanged=$null -ne $ReaderContext.last_pair -and [string]$snapshot.identity.round_id -cne [string]$ReaderContext.last_pair.snapshot.identity.round_id
                if($roundChanged -and $ReaderContext.seen_round_ids.Contains([string]$snapshot.identity.round_id)){throw 'state_round_replayed'}
                $roundResetCompatibility=$AllowRoundSequenceResetCompatibility -and $roundChanged -and
                    [string]$events.coverage.stream_epoch -cne [string]$ReaderContext.last_pair.events.coverage.stream_epoch -and
                    $clock -ge $ReaderContext.last_clock
                # Legacy publishers may keep one empty event batch while their
                # correlated snapshots advance. This permits snapshot diagnosis
                # only; it can never prove event absence or lossless coverage.
                $emptyEventCompatibility=$AllowEmptyEventBatchCompatibility -and
                    @($events.events).Count -eq 0 -and $eventSequence -eq 0 -and
                    [long]$events.coverage.cursor_start -eq 0 -and [long]$events.coverage.cursor_end -eq 0 -and
                    $null -eq $events.coverage.previous_batch_id
                $eventStateBefore=@{
                    epoch=$ReaderContext.event_epoch;cursor_start=$ReaderContext.event_cursor_start
                    cursor_end=$ReaderContext.event_cursor_end;batch_id=$ReaderContext.event_batch_id
                        event_chain_verified=$ReaderContext.event_chain_verified
                    empty_count=$ReaderContext.event_empty_compatibility_count;sample_count=$ReaderContext.event_sample_count
                    event_ids=@{};event_ids_count=$ReaderContext.event_ids.Count
                }
                foreach($key in $ReaderContext.event_ids.Keys){$eventStateBefore.event_ids[$key]=$ReaderContext.event_ids[$key]}
                if (($sequence -lt $ReaderContext.last_sequence -and -not $roundResetCompatibility) -or $clock -lt $ReaderContext.last_clock) { throw 'state_sequence_regressed' }
                if ($sequence -eq $ReaderContext.last_sequence -and -not $cached -and -not $roundResetCompatibility) { throw 'state_sequence_reused' }
                if ($sequence -le $MinimumSequence -and -not $roundResetCompatibility) { throw 'state_sequence_not_advanced' }
                if ($eventSequence -lt $ReaderContext.last_event_sequence -and -not $roundResetCompatibility) { throw 'state_event_sequence_regressed' }
                if ($eventSequence -eq $ReaderContext.last_event_sequence -and -not $cached -and -not $emptyEventCompatibility -and -not $roundResetCompatibility) { throw 'state_event_sequence_reused' }
                if ($clock -ne [long]$events.identity.monotonic_ms) { throw 'state_pair_clock_mismatch' }
                foreach ($fresh in @($snapshot.identity.observation.freshness,$events.identity.observation.freshness)) {
                    if ($clock -lt [long]$fresh.observed_monotonic_ms -or $clock-[long]$fresh.observed_monotonic_ms -gt [long]$fresh.valid_for_ms) { throw 'state_observation_stale' }
                }
                # Validate the event stream only after snapshot/event sequence
                # freshness checks. This preserves the precise reused-sequence
                # diagnostic for a legacy empty batch while still fail-closing
                # real gaps and rewritten event IDs before cursor advancement.
                if ($cached) {
                    $eventChain=[pscustomobject]@{
                        verified=[bool]$ReaderContext.event_chain_verified
                        empty_compatibility=($ReaderContext.event_empty_compatibility_count -gt 0)
                        epoch=[string]$ReaderContext.event_epoch;batch_id=[string]$ReaderContext.event_batch_id
                        cursor_start=[long]$ReaderContext.event_cursor_start;cursor_end=[long]$ReaderContext.event_cursor_end
                        unique_event_count=$ReaderContext.event_ids.Count
                    }
                }
                else {
                    $eventChain = Test-ActionRoguelikeEventChainStep -ReaderContext $ReaderContext -Events $events -RoundReset:$roundResetCompatibility -AllowEmptyCompatibility:$emptyEventCompatibility
                }
                $newSample = $sequence -gt $ReaderContext.last_sequence -or $roundResetCompatibility
                $nowTicks = [Diagnostics.Stopwatch]::GetTimestamp()
                if (-not $newSample -and (($nowTicks-$ReaderContext.last_progress_ticks)*1000.0/[Diagnostics.Stopwatch]::Frequency) -gt $MaximumAgeMilliseconds) { throw 'state_sequence_stalled' }
                # This is one deadline shared by all paths and retries. Never
                # accept a sample that completed validation outside its budget.
                if ($watch.Elapsed.TotalMilliseconds -ge $TimeoutMilliseconds) { throw 'state_read_budget_exhausted' }
                if ($newSample) { $ReaderContext.last_progress_ticks=$nowTicks }
                $ReaderContext.last_sequence=$sequence; $ReaderContext.last_clock=$clock; $ReaderContext.last_event_sequence=$eventSequence
                $ReaderContext.last_snapshot_id=[string]$snapshot.identity.snapshot_id; $ReaderContext.last_document_hash=$hash
                $ReaderContext.last_pair=@{snapshot=$snapshot;events=$events;validation=$validation}
                [void]$ReaderContext.seen_round_ids.Add([string]$snapshot.identity.round_id)
                return [pscustomobject]@{
                    success=$true;snapshot=$snapshot;events=$events;validation=$validation
                    snapshot_path=$candidate.snapshot_path;events_path=$candidate.events_path;path_source=$candidate.source
                    diagnostic=[pscustomobject]@{attempts=$attempts;elapsed_ms=[Math]::Round($watch.Elapsed.TotalMilliseconds,3);candidate_count=$candidates.Count;last_reason_code='ok';new_sample=$newSample;sequence=$sequence;schema_cache_hit=$cached;timeout_ms=$TimeoutMilliseconds;publication_age_ms=[Math]::Max(0,([DateTime]::UtcNow-$publicationUtc).TotalMilliseconds);event_coverage_verified=[bool]$eventChain.verified;event_chain=$eventChain;empty_event_batch_compatibility=[bool]$emptyEventCompatibility;empty_event_batch_compatibility_count=[int]$ReaderContext.event_empty_compatibility_count;round_sequence_reset_compatibility=[bool]$roundResetCompatibility}
                }
            } catch {
                if($_.Exception.Message-like'EVALUATOR_STATE_RECORDER*'){throw}
                if($null -ne $eventStateBefore){
                    $ReaderContext.event_epoch=$eventStateBefore.epoch
                    $ReaderContext.event_cursor_start=$eventStateBefore.cursor_start
                    $ReaderContext.event_cursor_end=$eventStateBefore.cursor_end
                    $ReaderContext.event_batch_id=$eventStateBefore.batch_id
                    $ReaderContext.event_chain_verified=$eventStateBefore.event_chain_verified
                    $ReaderContext.event_empty_compatibility_count=$eventStateBefore.empty_count
                    $ReaderContext.event_sample_count=$eventStateBefore.sample_count
                    $ReaderContext.event_ids=@{}
                    foreach($key in $eventStateBefore.event_ids.Keys){$ReaderContext.event_ids[$key]=$eventStateBefore.event_ids[$key]}
                }
                $message=$_.Exception.Message
                if ($message -eq 'state_read_budget_exhausted') {
                    $budgetExhausted=$true
                    # Deadline exhaustion is a bound on retries, not a more
                    # specific diagnosis than an already observed bad frame.
                    if ($lastReason -eq 'state_pair_missing') { $lastReason=$message }
                }
                elseif ($message -match '^(state_|snapshot_schema_invalid|events_schema_invalid)') {
                    $lastReason=$message
                    if($ReaderContext.ContainsKey('history_pairs')-and$message-notin@('state_history_pending','state_sequence_not_advanced','state_file_stale','state_read_budget_exhausted')){$ReaderContext.history_fault=$message}
                }
                elseif ($_.Exception -is [Text.DecoderFallbackException]) { $lastReason='state_utf8_invalid' }
                elseif ($_.Exception -is [UnauthorizedAccessException]) { $lastReason='state_access_denied' }
                elseif ($_.Exception -is [IO.IOException]) { $lastReason='state_publication_gap' }
                else { $lastReason='state_document_invalid' }
            }
        }
        $remaining = $TimeoutMilliseconds-$watch.Elapsed.TotalMilliseconds
        if ($remaining -le 0) { break }
        Start-Sleep -Milliseconds ([int][Math]::Min($PollMilliseconds,[Math]::Ceiling($remaining)))
    } while ($watch.Elapsed.TotalMilliseconds -lt $TimeoutMilliseconds)
    # A missing host-retained anchor or damaged capture is a collector failure,
    # never evidence that the candidate failed to publish gameplay state.
    if($lastReason-in@('state_captured_anchor_missing','state_captured_bytes_rewritten')){
        throw "run_invalid|STATE_CAPTURE_INTEGRITY|$lastReason"
    }
    return [pscustomobject]@{
        success=$false;snapshot=$null;events=$null;validation=$null;snapshot_path=$null;events_path=$null;path_source=$null
        diagnostic=[pscustomobject]@{attempts=$attempts;elapsed_ms=[Math]::Round($watch.Elapsed.TotalMilliseconds,3);candidate_count=$candidates.Count;last_reason_code=$lastReason;new_sample=$false;timeout_ms=$TimeoutMilliseconds;deadline_exhausted=($budgetExhausted -or $watch.Elapsed.TotalMilliseconds -ge $TimeoutMilliseconds)}
    }
}

function Read-ActionRoguelikeStatePair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$EventsPath,
        [Parameter(Mandatory)][string]$SnapshotSchemaPath,
        [Parameter(Mandatory)][string]$EventsSchemaPath,
        [Parameter(Mandatory)][string]$ExpectedProcessToken,
        [Parameter(Mandatory)][int]$ExpectedProcessId,
        [ValidateRange(1,5000)][int]$TimeoutMilliseconds=500,
        [ValidateRange(1,1000)][int]$PollMilliseconds=25,
        [ValidateRange(1024,16777216)][int]$MaximumDocumentBytes=4194304
    )
    # Compatibility entry point accepts only the two explicitly named files.
    $runRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($SnapshotPath))
    return Resolve-ActionRoguelikeStatePair -RunRoot $runRoot -PreferredSnapshotPath $SnapshotPath -PreferredEventsPath $EventsPath -SnapshotSchemaPath $SnapshotSchemaPath -EventsSchemaPath $EventsSchemaPath -ExpectedProcessToken $ExpectedProcessToken -ExpectedProcessId $ExpectedProcessId -TimeoutMilliseconds $TimeoutMilliseconds -PollMilliseconds $PollMilliseconds -MaximumDocumentBytes $MaximumDocumentBytes
}
