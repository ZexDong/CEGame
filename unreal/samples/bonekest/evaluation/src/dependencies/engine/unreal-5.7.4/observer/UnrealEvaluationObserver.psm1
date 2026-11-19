Set-StrictMode -Version Latest

$script:ObserverSchemaVersion = '1.0.0'
$script:ObserverClock = [System.Diagnostics.Stopwatch]::StartNew()

function Get-ObserverMonotonicMilliseconds {
    return [long]$script:ObserverClock.ElapsedMilliseconds
}

function Get-ObserverProperty {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return [pscustomobject][ordered]@{ Exists = $false; Value = $null }
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return [pscustomobject][ordered]@{ Exists = $false; Value = $null }
    }

    return [pscustomobject][ordered]@{ Exists = $true; Value = $property.Value }
}

function Test-ObserverNumber {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [bool]) {
        return $false
    }

    $isNumber =
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or
        $Value -is [decimal]

    if (-not $isNumber) {
        return $false
    }

    $number = [double]$Value
    return -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)
}

function Test-ObserverNonnegativeInteger {
    param([AllowNull()][object]$Value)

    if (-not (Test-ObserverNumber -Value $Value)) {
        return $false
    }

    $number = [double]$Value
    return $number -ge 0 -and [Math]::Truncate($number) -eq $number
}

function Test-ObserverStableId {
    param([AllowNull()][object]$Value)

    return $Value -is [string] -and
        $Value.Length -ge 1 -and
        $Value.Length -le 128 -and
        $Value -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

function New-ObserverFault {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('observer', 'evidence', 'executor', 'environment', 'capability')]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [bool]$Retryable,

        [AllowNull()]
        [object]$Details = $null
    )

    return [pscustomobject][ordered]@{
        domain = $Domain
        code = $Code
        message = $Message
        retryable = $Retryable
        evidence_paths = @()
        details = $Details
    }
}

function New-ObserverOperationResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ReadState', 'WaitUntil', 'FindVisibleTarget')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateSet('ok', 'timeout', 'executor_fault', 'environment_fault', 'unsupported')]
        [string]$Status,

        [AllowNull()]
        [object]$Result = $null,

        [AllowNull()]
        [object]$Fault = $null,

        [AllowNull()]
        [Nullable[bool]]$FeedbackObserved = $null,

        [AllowNull()]
        [Nullable[bool]]$TargetVisible = $null,

        [object[]]$Evidence = @()
    )

    return [pscustomobject][ordered]@{
        schema_version = $script:ObserverSchemaVersion
        operation = $Operation
        status = $Status
        observer_monotonic_ms = Get-ObserverMonotonicMilliseconds
        input_dispatched = $false
        feedback_observed = if ($null -ne $FeedbackObserved) { [bool]$FeedbackObserved } else { $null }
        target_visible = if ($null -ne $TargetVisible) { [bool]$TargetVisible } else { $null }
        executor_fault = $Status -eq 'executor_fault'
        environment_fault = $Status -eq 'environment_fault'
        unsupported = $Status -eq 'unsupported'
        result = $Result
        fault = $Fault
        evidence = @($Evidence)
    }
}

function New-SnapshotContractFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return [pscustomobject][ordered]@{
        valid = $false
        fault = New-ObserverFault -Domain observer -Code $Code -Message $Message -Retryable $false
    }
}

function Test-NormalizedPoint {
    param([AllowNull()][object]$Point)

    $x = Get-ObserverProperty -InputObject $Point -Name 'x'
    $y = Get-ObserverProperty -InputObject $Point -Name 'y'
    if (-not $x.Exists -or -not $y.Exists) {
        return $false
    }
    if (-not (Test-ObserverNumber -Value $x.Value) -or -not (Test-ObserverNumber -Value $y.Value)) {
        return $false
    }

    return [double]$x.Value -ge 0 -and [double]$x.Value -le 1 -and
        [double]$y.Value -ge 0 -and [double]$y.Value -le 1
}

function Test-UnrealSnapshotContract {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Snapshot,

        [AllowNull()]
        [string]$ExpectedProcessToken,

        [AllowNull()]
        [Nullable[int]]$ExpectedProcessId,

        [AllowNull()]
        [string]$ExpectedRoundId,

        [AllowNull()]
        [string]$ExpectedObjectId,

        [AllowNull()]
        [Nullable[long]]$MinimumSnapshotId,

        [AllowNull()]
        [Nullable[double]]$MinimumMonotonicMs
    )

    if ($null -eq $Snapshot -or $Snapshot -is [string] -or $Snapshot -is [System.Array]) {
        return New-SnapshotContractFailure -Code 'snapshot_root_invalid' -Message 'The state snapshot root must be one JSON object.'
    }

    $schemaVersion = Get-ObserverProperty -InputObject $Snapshot -Name 'schema_version'
    if (-not $schemaVersion.Exists -or $schemaVersion.Value -cne $script:ObserverSchemaVersion) {
        return New-SnapshotContractFailure -Code 'snapshot_schema_unsupported' -Message 'The state snapshot schema version is missing or unsupported.'
    }

    $processToken = Get-ObserverProperty -InputObject $Snapshot -Name 'process_token'
    if (-not $processToken.Exists -or -not (Test-ObserverStableId -Value $processToken.Value)) {
        return New-SnapshotContractFailure -Code 'snapshot_process_token_invalid' -Message 'The state snapshot process token is missing or invalid.'
    }
    if (-not [string]::IsNullOrEmpty($ExpectedProcessToken) -and $processToken.Value -cne $ExpectedProcessToken) {
        return New-SnapshotContractFailure -Code 'snapshot_process_token_mismatch' -Message 'The state snapshot belongs to a different process token.'
    }

    $processId = Get-ObserverProperty -InputObject $Snapshot -Name 'process_id'
    if (-not $processId.Exists -or -not (Test-ObserverNonnegativeInteger -Value $processId.Value) -or [double]$processId.Value -lt 1) {
        return New-SnapshotContractFailure -Code 'snapshot_process_id_invalid' -Message 'The state snapshot process identifier is missing or invalid.'
    }
    if ($null -ne $ExpectedProcessId -and [int64]$processId.Value -ne [int64]$ExpectedProcessId) {
        return New-SnapshotContractFailure -Code 'snapshot_process_id_mismatch' -Message 'The state snapshot belongs to a different process identifier.'
    }

    $snapshotId = Get-ObserverProperty -InputObject $Snapshot -Name 'snapshot_id'
    if (-not $snapshotId.Exists -or -not (Test-ObserverNonnegativeInteger -Value $snapshotId.Value)) {
        return New-SnapshotContractFailure -Code 'snapshot_id_invalid' -Message 'The state snapshot identity is missing or invalid.'
    }
    if ($null -ne $MinimumSnapshotId -and [int64]$snapshotId.Value -lt [int64]$MinimumSnapshotId) {
        return New-SnapshotContractFailure -Code 'snapshot_id_regressed' -Message 'The state snapshot identity regressed within the bound process.'
    }

    $roundId = Get-ObserverProperty -InputObject $Snapshot -Name 'round_id'
    if (-not $roundId.Exists -or -not (Test-ObserverStableId -Value $roundId.Value)) {
        return New-SnapshotContractFailure -Code 'snapshot_round_id_invalid' -Message 'The state snapshot round identity is missing or invalid.'
    }
    if (-not [string]::IsNullOrEmpty($ExpectedRoundId) -and $roundId.Value -cne $ExpectedRoundId) {
        return New-SnapshotContractFailure -Code 'snapshot_round_id_mismatch' -Message 'The state snapshot belongs to a different round identity.'
    }

    foreach ($name in @('round_index', 'restart_count')) {
        $field = Get-ObserverProperty -InputObject $Snapshot -Name $name
        if (-not $field.Exists -or -not (Test-ObserverNonnegativeInteger -Value $field.Value)) {
            return New-SnapshotContractFailure -Code ('snapshot_{0}_invalid' -f $name) -Message ('The state snapshot {0} field is missing or invalid.' -f $name)
        }
    }

    $monotonic = Get-ObserverProperty -InputObject $Snapshot -Name 'monotonic_ms'
    if (-not $monotonic.Exists -or -not (Test-ObserverNumber -Value $monotonic.Value) -or [double]$monotonic.Value -lt 0) {
        return New-SnapshotContractFailure -Code 'snapshot_monotonic_time_invalid' -Message 'The state snapshot monotonic time is missing or invalid.'
    }
    if ($null -ne $MinimumMonotonicMs -and [double]$monotonic.Value -lt [double]$MinimumMonotonicMs) {
        return New-SnapshotContractFailure -Code 'snapshot_monotonic_time_regressed' -Message 'The state snapshot monotonic time regressed within the bound process.'
    }

    $scene = Get-ObserverProperty -InputObject $Snapshot -Name 'scene'
    $ready = Get-ObserverProperty -InputObject $Snapshot -Name 'ready'
    $firstFrame = Get-ObserverProperty -InputObject $Snapshot -Name 'first_frame'
    if (-not $scene.Exists -or -not (Test-ObserverStableId -Value $scene.Value) -or
        -not $ready.Exists -or $ready.Value -isnot [bool] -or
        -not $firstFrame.Exists -or $firstFrame.Value -isnot [bool]) {
        return New-SnapshotContractFailure -Code 'snapshot_lifecycle_invalid' -Message 'The state snapshot lifecycle fields are missing or invalid.'
    }

    $object = Get-ObserverProperty -InputObject $Snapshot -Name 'object'
    $objectId = if ($object.Exists) { Get-ObserverProperty -InputObject $object.Value -Name 'object_id' } else { $null }
    $objectPosition = if ($object.Exists) { Get-ObserverProperty -InputObject $object.Value -Name 'normalized_position' } else { $null }
    if (-not $object.Exists -or -not $objectId.Exists -or -not (Test-ObserverStableId -Value $objectId.Value) -or
        -not $objectPosition.Exists -or -not (Test-NormalizedPoint -Point $objectPosition.Value)) {
        return New-SnapshotContractFailure -Code 'snapshot_object_invalid' -Message 'The state snapshot object identity or normalized position is missing or invalid.'
    }
    if (-not [string]::IsNullOrEmpty($ExpectedObjectId) -and $objectId.Value -cne $ExpectedObjectId) {
        return New-SnapshotContractFailure -Code 'snapshot_object_id_mismatch' -Message 'The state snapshot contains a different observed object identity.'
    }

    $keyboard = Get-ObserverProperty -InputObject $Snapshot -Name 'keyboard'
    if (-not $keyboard.Exists) {
        return New-SnapshotContractFailure -Code 'snapshot_keyboard_invalid' -Message 'The state snapshot keyboard state is missing.'
    }
    $keysDown = Get-ObserverProperty -InputObject $keyboard.Value -Name 'keys_down'
    $wDown = Get-ObserverProperty -InputObject $keyboard.Value -Name 'w_down'
    $discreteCount = Get-ObserverProperty -InputObject $keyboard.Value -Name 'discrete_count'
    $holdCount = Get-ObserverProperty -InputObject $keyboard.Value -Name 'hold_count'
    if (-not $keysDown.Exists -or $keysDown.Value -isnot [System.Array] -or
        -not $wDown.Exists -or $wDown.Value -isnot [bool] -or
        -not $discreteCount.Exists -or -not (Test-ObserverNonnegativeInteger -Value $discreteCount.Value) -or
        -not $holdCount.Exists -or -not (Test-ObserverNonnegativeInteger -Value $holdCount.Value)) {
        return New-SnapshotContractFailure -Code 'snapshot_keyboard_invalid' -Message 'The state snapshot keyboard fields are missing or invalid.'
    }
    foreach ($key in @($keysDown.Value)) {
        if (-not (Test-ObserverStableId -Value $key)) {
            return New-SnapshotContractFailure -Code 'snapshot_keyboard_invalid' -Message 'The state snapshot contains an invalid key identity.'
        }
    }

    $pointer = Get-ObserverProperty -InputObject $Snapshot -Name 'pointer'
    if (-not $pointer.Exists) {
        return New-SnapshotContractFailure -Code 'snapshot_pointer_invalid' -Message 'The state snapshot pointer state is missing.'
    }
    $leftDown = Get-ObserverProperty -InputObject $pointer.Value -Name 'left_down'
    if (-not $leftDown.Exists -or $leftDown.Value -isnot [bool]) {
        return New-SnapshotContractFailure -Code 'snapshot_pointer_invalid' -Message 'The state snapshot pointer button state is missing or invalid.'
    }
    foreach ($name in @('normalized_position', 'press_origin', 'drag_position')) {
        $point = Get-ObserverProperty -InputObject $pointer.Value -Name $name
        if (-not $point.Exists -or -not (Test-NormalizedPoint -Point $point.Value)) {
            return New-SnapshotContractFailure -Code 'snapshot_pointer_invalid' -Message 'The state snapshot pointer position fields are missing or invalid.'
        }
    }
    foreach ($name in @('click_count', 'drag_count')) {
        $count = Get-ObserverProperty -InputObject $pointer.Value -Name $name
        if (-not $count.Exists -or -not (Test-ObserverNonnegativeInteger -Value $count.Value)) {
            return New-SnapshotContractFailure -Code 'snapshot_pointer_invalid' -Message 'The state snapshot pointer counters are missing or invalid.'
        }
    }

    $hud = Get-ObserverProperty -InputObject $Snapshot -Name 'hud'
    $hudRevision = if ($hud.Exists) { Get-ObserverProperty -InputObject $hud.Value -Name 'revision' } else { $null }
    $hudFeedback = if ($hud.Exists) { Get-ObserverProperty -InputObject $hud.Value -Name 'feedback' } else { $null }
    if (-not $hud.Exists -or -not $hudRevision.Exists -or -not (Test-ObserverNonnegativeInteger -Value $hudRevision.Value) -or
        -not $hudFeedback.Exists -or $hudFeedback.Value -isnot [string] -or $hudFeedback.Value.Length -gt 1024) {
        return New-SnapshotContractFailure -Code 'snapshot_hud_invalid' -Message 'The state snapshot HUD fields are missing or invalid.'
    }

    $targets = Get-ObserverProperty -InputObject $Snapshot -Name 'targets'
    if (-not $targets.Exists -or $targets.Value -isnot [System.Array]) {
        return New-SnapshotContractFailure -Code 'snapshot_targets_invalid' -Message 'The state snapshot target collection is missing or invalid.'
    }

    return [pscustomobject][ordered]@{
        valid = $true
        snapshot = $Snapshot
        process_token = [string]$processToken.Value
        process_id = [int64]$processId.Value
        snapshot_id = [int64]$snapshotId.Value
        round_id = [string]$roundId.Value
        object_id = [string]$objectId.Value
        monotonic_ms = [double]$monotonic.Value
        fault = $null
    }
}

function Test-ObserverMissingPathAncestorSafety {
    param([Parameter(Mandatory = $true)][string]$FullPath)

    $cursorPath = [System.IO.Path]::GetDirectoryName($FullPath)
    $cursor = $null
    while (-not [string]::IsNullOrEmpty($cursorPath)) {
        try {
            $cursor = Get-Item -LiteralPath $cursorPath -Force -ErrorAction Stop
            break
        }
        catch [System.Management.Automation.ItemNotFoundException] { }
        catch [System.IO.FileNotFoundException] { }
        catch [System.IO.DirectoryNotFoundException] { }
        catch [System.UnauthorizedAccessException] {
            return [pscustomobject][ordered]@{
                safe = $false
                fault = New-ObserverFault -Domain environment `
                    -Code 'snapshot_access_denied' `
                    -Message 'The state snapshot ancestor chain could not be inspected because access was denied.' `
                    -Retryable $false
            }
        }
        catch [System.IO.IOException] {
            return [pscustomobject][ordered]@{
                safe = $false
                fault = New-ObserverFault -Domain environment `
                    -Code 'snapshot_path_unreadable' `
                    -Message 'The state snapshot ancestor chain could not be inspected during a publisher update.' `
                    -Retryable $true -Details ([pscustomobject][ordered]@{
                        exception_type = $_.Exception.GetType().FullName
                    })
            }
        }
        catch {
            return [pscustomobject][ordered]@{
                safe = $false
                fault = New-ObserverFault -Domain environment `
                    -Code 'snapshot_path_unreadable' `
                    -Message 'The state snapshot ancestor chain could not be inspected.' `
                    -Retryable $false -Details ([pscustomobject][ordered]@{
                        exception_type = $_.Exception.GetType().FullName
                    })
            }
        }

        $parentPath = [System.IO.Path]::GetDirectoryName($cursorPath)
        if ([string]::IsNullOrEmpty($parentPath) -or $parentPath -ceq $cursorPath) { break }
        $cursorPath = $parentPath
    }

    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return [pscustomobject][ordered]@{
                safe = $false
                fault = New-ObserverFault -Domain observer `
                    -Code 'snapshot_path_reparse_point' `
                    -Message 'The state snapshot path traverses a reparse point.' `
                    -Retryable $false
            }
        }
        $cursor = $cursor.Parent
    }
    return [pscustomobject][ordered]@{ safe = $true; fault = $null }
}

function Get-ObserverMissingPathCheckResult {
    param([Parameter(Mandatory = $true)][string]$FullPath)

    $ancestorCheck = Test-ObserverMissingPathAncestorSafety -FullPath $FullPath
    if (-not $ancestorCheck.safe) {
        return [pscustomobject][ordered]@{
            valid = $false
            unavailable = $false
            full_path = $null
            fault = $ancestorCheck.fault
        }
    }
    return [pscustomobject][ordered]@{
        valid = $false
        unavailable = $true
        full_path = $null
        fault = $null
    }
}

function Test-ObserverPathForRead {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        $cursor = $item
        while ($null -ne $cursor) {
            if (($cursor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                return [pscustomobject][ordered]@{
                    valid = $false
                    unavailable = $false
                    full_path = $null
                    fault = New-ObserverFault -Domain observer -Code 'snapshot_path_reparse_point' -Message 'The state snapshot path traverses a reparse point.' -Retryable $false
                }
            }
            if ($cursor -is [System.IO.FileInfo]) {
                $cursor = $cursor.Directory
            }
            else {
                $cursor = $cursor.Parent
            }
        }

        if ($item.PSIsContainer) {
            return [pscustomobject][ordered]@{
                valid = $false
                unavailable = $false
                full_path = $null
                fault = New-ObserverFault -Domain observer -Code 'snapshot_path_not_file' -Message 'The state snapshot path does not identify a regular file.' -Retryable $false
            }
        }

        return [pscustomobject][ordered]@{ valid = $true; unavailable = $false; full_path = $fullPath; fault = $null }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        return Get-ObserverMissingPathCheckResult -FullPath $fullPath
    }
    catch [System.IO.FileNotFoundException] {
        return Get-ObserverMissingPathCheckResult -FullPath $fullPath
    }
    catch [System.IO.DirectoryNotFoundException] {
        return Get-ObserverMissingPathCheckResult -FullPath $fullPath
    }
    catch [System.UnauthorizedAccessException] {
        return [pscustomobject][ordered]@{
            valid = $false
            unavailable = $false
            full_path = $null
            fault = New-ObserverFault -Domain environment -Code 'snapshot_access_denied' -Message 'The state snapshot path could not be inspected because access was denied.' -Retryable $false
        }
    }
    catch [System.IO.IOException] {
        return [pscustomobject][ordered]@{
            valid = $false
            unavailable = $false
            full_path = $null
            fault = New-ObserverFault -Domain environment -Code 'snapshot_path_unreadable' -Message 'The state snapshot path could not be inspected during a publisher update.' -Retryable $true -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            valid = $false
            unavailable = $false
            full_path = $null
            fault = New-ObserverFault -Domain environment -Code 'snapshot_path_unreadable' -Message 'The state snapshot path could not be inspected.' -Retryable $false -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
        }
    }
}

function Get-LowercaseSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $algorithm.ComputeHash($Bytes)
        return -join ($hash | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $algorithm.Dispose()
    }
}

function Read-UnrealEvaluationStateOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedProcessToken,

        [ValidateRange(1, 600000)]
        [Alias('FreshnessLimitMs')]
        [int]$MaxAgeMs = 2000,

        [ValidateRange(1, 2147483647)]
        [int]$ExpectedProcessId,

        [string]$ExpectedRoundId,

        [string]$ExpectedObjectId,

        [ValidateRange(0, 9223372036854775807)]
        [long]$MinimumSnapshotId,

        [ValidateRange(0, 1.7976931348623157E+308)]
        [double]$MinimumMonotonicMs,

        [ValidateRange(256, 16777216)]
        [int]$MaxSnapshotBytes = 1048576
    )

    $pathCheck = Test-ObserverPathForRead -Path $StatePath
    if (-not $pathCheck.valid) {
        if ($pathCheck.unavailable) {
            $fault = New-ObserverFault -Domain capability -Code 'state_snapshot_unavailable' -Message 'No read-only state snapshot is currently available.' -Retryable $true
            return New-ObserverOperationResult -Operation ReadState -Status unsupported -Fault $fault
        }
        $status = if ($pathCheck.fault.domain -eq 'environment') { 'environment_fault' } else { 'executor_fault' }
        return New-ObserverOperationResult -Operation ReadState -Status $status -Fault $pathCheck.fault
    }

    try {
        $beforeWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($pathCheck.full_path)
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $stream = [System.IO.File]::Open($pathCheck.full_path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        try {
            if ($stream.Length -lt 2 -or $stream.Length -gt $MaxSnapshotBytes) {
                $fault = New-ObserverFault -Domain observer -Code 'snapshot_size_invalid' -Message 'The state snapshot size is outside the allowed range.' -Retryable $false
                return New-ObserverOperationResult -Operation ReadState -Status executor_fault -Fault $fault
            }

            $memory = New-Object System.IO.MemoryStream
            try {
                $stream.CopyTo($memory)
                [byte[]]$bytes = $memory.ToArray()
            }
            finally {
                $memory.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
        $afterWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($pathCheck.full_path)
    }
    catch [System.UnauthorizedAccessException] {
        $fault = New-ObserverFault -Domain environment -Code 'snapshot_access_denied' -Message 'The state snapshot could not be read because access was denied.' -Retryable $false
        return New-ObserverOperationResult -Operation ReadState -Status environment_fault -Fault $fault
    }
    catch [System.IO.IOException] {
        $fault = New-ObserverFault -Domain environment -Code 'snapshot_io_failure' -Message 'The state snapshot could not be read atomically.' -Retryable $true -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
        return New-ObserverOperationResult -Operation ReadState -Status environment_fault -Fault $fault
    }
    catch {
        $fault = New-ObserverFault -Domain observer -Code 'snapshot_read_failure' -Message 'The observer failed while reading the state snapshot.' -Retryable $false -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
        return New-ObserverOperationResult -Operation ReadState -Status executor_fault -Fault $fault
    }

    try {
        $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList @($false, $true)
        $json = $utf8.GetString($bytes)
        $snapshot = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $fault = New-ObserverFault -Domain observer -Code 'snapshot_json_invalid' -Message 'The atomic state snapshot is not valid UTF-8 JSON.' -Retryable $false -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
        return New-ObserverOperationResult -Operation ReadState -Status executor_fault -Fault $fault
    }

    $expectedPid = if ($PSBoundParameters.ContainsKey('ExpectedProcessId')) { [Nullable[int]]$ExpectedProcessId } else { [Nullable[int]]$null }
    $minimumId = if ($PSBoundParameters.ContainsKey('MinimumSnapshotId')) { [Nullable[long]]$MinimumSnapshotId } else { [Nullable[long]]$null }
    $minimumTime = if ($PSBoundParameters.ContainsKey('MinimumMonotonicMs')) { [Nullable[double]]$MinimumMonotonicMs } else { [Nullable[double]]$null }
    $contract = Test-UnrealSnapshotContract -Snapshot $snapshot -ExpectedProcessToken $ExpectedProcessToken -ExpectedProcessId $expectedPid -ExpectedRoundId $ExpectedRoundId -ExpectedObjectId $ExpectedObjectId -MinimumSnapshotId $minimumId -MinimumMonotonicMs $minimumTime
    if (-not $contract.valid) {
        return New-ObserverOperationResult -Operation ReadState -Status executor_fault -Fault $contract.fault
    }

    $conservativeWriteUtc = if ($beforeWriteUtc -le $afterWriteUtc) { $beforeWriteUtc } else { $afterWriteUtc }
    $ageMs = ([System.DateTime]::UtcNow - $conservativeWriteUtc).TotalMilliseconds
    if ($ageMs -lt -1000) {
        $fault = New-ObserverFault -Domain environment -Code 'snapshot_file_time_invalid' -Message 'The state snapshot file time is unexpectedly in the future.' -Retryable $false
        return New-ObserverOperationResult -Operation ReadState -Status environment_fault -Fault $fault
    }
    $ageMs = [Math]::Max(0.0, $ageMs)
    if ($ageMs -gt $MaxAgeMs) {
        $fault = New-ObserverFault -Domain observer -Code 'snapshot_stale' -Message 'The state snapshot is older than the configured freshness limit.' -Retryable $true -Details ([pscustomobject][ordered]@{
            observed_age_ms = [Math]::Round($ageMs, 3)
            max_age_ms = $MaxAgeMs
            snapshot_id = $contract.snapshot_id
            snapshot_monotonic_ms = $contract.monotonic_ms
        })
        return New-ObserverOperationResult -Operation ReadState -Status executor_fault -Fault $fault
    }

    $freshness = [pscustomobject][ordered]@{
        is_fresh = $true
        observed_age_ms = [Math]::Round($ageMs, 3)
        max_age_ms = $MaxAgeMs
        basis = 'conservative_file_last_write_utc'
        snapshot_monotonic_ms = $contract.monotonic_ms
        read_observer_monotonic_ms = Get-ObserverMonotonicMilliseconds
    }
    $result = [pscustomobject][ordered]@{
        snapshot = $snapshot
        freshness = $freshness
        snapshot_sha256 = Get-LowercaseSha256 -Bytes $bytes
        byte_length = $bytes.Length
    }
    return New-ObserverOperationResult -Operation ReadState -Status ok -Result $result
}

function Test-ObserverPublisherIoExceptionType {
    param([AllowNull()][string]$ExceptionType)

    return $ExceptionType -in @(
        'System.IO.IOException',
        'System.IO.FileNotFoundException',
        'System.IO.DirectoryNotFoundException',
        'System.Management.Automation.ItemNotFoundException')
}

function Test-ObserverPublisherRetryEligible {
    param([AllowNull()][object]$ReadResult)

    if ($null -eq $ReadResult -or
        -not $ReadResult.PSObject.Properties['status'] -or
        $ReadResult.status -eq 'ok' -or
        -not $ReadResult.PSObject.Properties['fault'] -or
        $null -eq $ReadResult.fault) {
        return $false
    }

    $fault = $ReadResult.fault
    $domain = Get-ObserverProperty -InputObject $fault -Name 'domain'
    $code = Get-ObserverProperty -InputObject $fault -Name 'code'
    $retryable = Get-ObserverProperty -InputObject $fault -Name 'retryable'
    if (-not $domain.Exists -or -not $code.Exists -or -not $retryable.Exists -or
        $retryable.Value -isnot [bool] -or -not [bool]$retryable.Value) {
        return $false
    }

    if ($ReadResult.status -eq 'unsupported' -and
        $domain.Value -ceq 'capability' -and
        $code.Value -ceq 'state_snapshot_unavailable') {
        return $true
    }
    if ($ReadResult.status -ne 'environment_fault' -or
        $domain.Value -cne 'environment' -or
        $code.Value -notin @('snapshot_path_unreadable', 'snapshot_io_failure')) {
        return $false
    }

    $details = Get-ObserverProperty -InputObject $fault -Name 'details'
    $exceptionType = if ($details.Exists -and $null -ne $details.Value) {
        Get-ObserverProperty -InputObject $details.Value -Name 'exception_type'
    }
    else { [pscustomobject][ordered]@{ Exists = $false; Value = $null } }
    return $exceptionType.Exists -and
        (Test-ObserverPublisherIoExceptionType -ExceptionType ([string]$exceptionType.Value))
}

function Add-ObserverReadTelemetry {
    param(
        [Parameter(Mandatory = $true)][object]$ReadResult,
        [ValidateRange(1, 3)][int]$ReadAttemptCount,
        [ValidateRange(0, 2)][int]$PublisherRetryCount
    )

    if ($ReadResult.status -eq 'ok') {
        if ($null -eq $ReadResult.result) {
            $ReadResult.result = [pscustomobject][ordered]@{}
        }
        $ReadResult.result | Add-Member -NotePropertyName read_attempt_count `
            -NotePropertyValue $ReadAttemptCount -Force
        $ReadResult.result | Add-Member -NotePropertyName publisher_retry_count `
            -NotePropertyValue $PublisherRetryCount -Force
        return $ReadResult
    }

    if ($ReadResult.PSObject.Properties['fault'] -and $null -ne $ReadResult.fault) {
        $merged = [ordered]@{}
        $details = Get-ObserverProperty -InputObject $ReadResult.fault -Name 'details'
        if ($details.Exists -and $null -ne $details.Value) {
            if ($details.Value -is [System.Collections.IDictionary]) {
                foreach ($key in $details.Value.Keys) {
                    $merged[[string]$key] = $details.Value[$key]
                }
            }
            else {
                foreach ($property in $details.Value.PSObject.Properties) {
                    $merged[[string]$property.Name] = $property.Value
                }
            }
        }
        $merged['read_attempt_count'] = $ReadAttemptCount
        $merged['publisher_retry_count'] = $PublisherRetryCount
        $ReadResult.fault.details = [pscustomobject]$merged
    }
    return $ReadResult
}

function Invoke-ObserverPublisherReadRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ReadAction,
        [ValidateRange(1, 3)][int]$MaxAttempts = 3,
        [ValidateRange(0, 10)][int]$RetryDelayMs = 10
    )

    $attemptCount = 0
    $read = $null
    do {
        ++$attemptCount
        $read = & $ReadAction
        if ($read.status -eq 'ok' -or
            $attemptCount -ge $MaxAttempts -or
            -not (Test-ObserverPublisherRetryEligible -ReadResult $read)) {
            break
        }
        if ($RetryDelayMs -gt 0) {
            [System.Threading.Thread]::Sleep($RetryDelayMs)
        }
    } while ($attemptCount -lt $MaxAttempts)

    return Add-ObserverReadTelemetry -ReadResult $read `
        -ReadAttemptCount $attemptCount -PublisherRetryCount ($attemptCount - 1)
}

function Read-UnrealEvaluationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedProcessToken,

        [ValidateRange(1, 600000)]
        [Alias('FreshnessLimitMs')]
        [int]$MaxAgeMs = 2000,

        [ValidateRange(1, 2147483647)]
        [int]$ExpectedProcessId,

        [string]$ExpectedRoundId,

        [string]$ExpectedObjectId,

        [ValidateRange(0, 9223372036854775807)]
        [long]$MinimumSnapshotId,

        [ValidateRange(0, 1.7976931348623157E+308)]
        [double]$MinimumMonotonicMs,

        [ValidateRange(256, 16777216)]
        [int]$MaxSnapshotBytes = 1048576
    )

    $onceParameters = @{
        StatePath = $StatePath
        ExpectedProcessToken = $ExpectedProcessToken
        MaxAgeMs = $MaxAgeMs
        MaxSnapshotBytes = $MaxSnapshotBytes
    }
    foreach ($optional in @('ExpectedProcessId', 'ExpectedRoundId', 'ExpectedObjectId',
            'MinimumSnapshotId', 'MinimumMonotonicMs')) {
        if ($PSBoundParameters.ContainsKey($optional)) {
            $onceParameters[$optional] = $PSBoundParameters[$optional]
        }
    }
    return Invoke-ObserverPublisherReadRetry -ReadAction {
        Read-UnrealEvaluationStateOnce @onceParameters
    } `
        -MaxAttempts 3 -RetryDelayMs 10
}

function Test-ObserverRelativeEvidencePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 1024) {
        return $false
    }
    if ($Path -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$') {
        return $false
    }
    return $true
}

function Resolve-ObserverEvidenceDestination {
    param(
        [Parameter(Mandatory = $true)][string]$EvidencePath,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    if (-not (Test-ObserverRelativeEvidencePath -Path $EvidencePath)) {
        return [pscustomobject][ordered]@{
            valid = $false
            fault = New-ObserverFault -Domain evidence -Code 'evidence_path_invalid' -Message 'The evidence path must be a safe run-relative path using forward slashes.' -Retryable $false
        }
    }

    try {
        $rootFull = [System.IO.Path]::GetFullPath($EvidenceRoot)
        if (-not [System.IO.Directory]::Exists($rootFull)) {
            return [pscustomobject][ordered]@{
                valid = $false
                fault = New-ObserverFault -Domain evidence -Code 'evidence_root_unavailable' -Message 'The evidence root does not exist.' -Retryable $false
            }
        }

        $rootItem = Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop
        $ancestor = $rootItem
        while ($null -ne $ancestor) {
            if (($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                return [pscustomobject][ordered]@{
                    valid = $false
                    fault = New-ObserverFault -Domain evidence -Code 'evidence_root_reparse_point' -Message 'The evidence root or one of its ancestors is a reparse point.' -Retryable $false
                }
            }
            $ancestor = $ancestor.Parent
        }

        $nativeRelative = $EvidencePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $destination = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $nativeRelative))
        $rootPrefix = $rootFull.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $destination.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject][ordered]@{
                valid = $false
                fault = New-ObserverFault -Domain evidence -Code 'evidence_path_escape' -Message 'The evidence path escapes its declared root.' -Retryable $false
            }
        }

        $parent = [System.IO.Path]::GetDirectoryName($destination)
        $relativeParent = $parent.Substring($rootPrefix.Length)
        $cursor = $rootFull
        if (-not [string]::IsNullOrEmpty($relativeParent)) {
            foreach ($segment in $relativeParent.Split([char[]]@([System.IO.Path]::DirectorySeparatorChar), [System.StringSplitOptions]::RemoveEmptyEntries)) {
                $cursor = [System.IO.Path]::Combine($cursor, $segment)
                if (-not [System.IO.Directory]::Exists($cursor)) {
                    [void][System.IO.Directory]::CreateDirectory($cursor)
                }
                $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    return [pscustomobject][ordered]@{
                        valid = $false
                        fault = New-ObserverFault -Domain evidence -Code 'evidence_path_reparse_point' -Message 'The evidence path traverses a reparse point.' -Retryable $false
                    }
                }
            }
        }

        if ([System.IO.File]::Exists($destination) -or [System.IO.Directory]::Exists($destination)) {
            return [pscustomobject][ordered]@{
                valid = $false
                fault = New-ObserverFault -Domain evidence -Code 'evidence_path_exists' -Message 'The evidence destination already exists and will not be overwritten.' -Retryable $false
            }
        }

        return [pscustomobject][ordered]@{
            valid = $true
            destination = $destination
            relative_path = $EvidencePath
            fault = $null
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            valid = $false
            fault = New-ObserverFault -Domain evidence -Code 'evidence_path_failure' -Message 'The evidence destination could not be prepared safely.' -Retryable $false -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
        }
    }
}

function Write-ObserverEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][object]$Destination
    )

    $temporaryPath = $null
    try {
        $json = $Payload | ConvertTo-Json -Depth 32 -Compress
        $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList @($false)
        $parent = [System.IO.Path]::GetDirectoryName($Destination.destination)
        $temporaryPath = [System.IO.Path]::Combine($parent, ('observer-{0}.tmp' -f [Guid]::NewGuid().ToString('N')))
        [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8)
        [System.IO.File]::Move($temporaryPath, $Destination.destination)
        $temporaryPath = $null

        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Destination.destination)
        return [pscustomobject][ordered]@{
            written = $true
            evidence = [pscustomobject][ordered]@{
                path = $Destination.relative_path
                sha256 = Get-LowercaseSha256 -Bytes $bytes
                media_type = 'application/json'
                byte_length = $bytes.Length
                captured_monotonic_ms = Get-ObserverMonotonicMilliseconds
                kind = 'wait_samples'
                producer = [pscustomobject][ordered]@{
                    id = 'unreal-evaluation-observer'
                    version = $script:ObserverSchemaVersion
                }
            }
            fault = $null
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            written = $false
            evidence = $null
            fault = New-ObserverFault -Domain evidence -Code 'evidence_write_failure' -Message 'The observer could not persist the requested sample evidence.' -Retryable $false -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
        }
    }
    finally {
        if ($null -ne $temporaryPath -and [System.IO.File]::Exists($temporaryPath)) {
            [System.IO.File]::Delete($temporaryPath)
        }
    }
}

function Wait-UnrealEvaluationCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedProcessToken,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [scriptblock]$Predicate,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 600000)]
        [int]$TimeoutMs,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 60000)]
        [int]$IntervalMs,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 10000)]
        [int]$MaxSamples,

        [ValidateRange(1, 600000)]
        [Alias('FreshnessLimitMs')]
        [int]$MaxAgeMs = 2000,

        [ValidateRange(1, 2147483647)]
        [int]$ExpectedProcessId,

        [string]$ExpectedRoundId,

        [string]$ExpectedObjectId,

        [Alias('SamplesPath')]
        [string]$EvidencePath,

        [string]$EvidenceRoot = (Get-Location).Path
    )

    $destination = $null
    if ($PSBoundParameters.ContainsKey('EvidencePath')) {
        $destination = Resolve-ObserverEvidenceDestination -EvidencePath $EvidencePath -EvidenceRoot $EvidenceRoot
        if (-not $destination.valid) {
            $result = [pscustomobject][ordered]@{
                matched = $false
                termination_reason = 'evidence_fault'
                timeout_ms = $TimeoutMs
                interval_ms = $IntervalMs
                max_samples = $MaxSamples
                sample_count = 0
                samples = @()
            }
            return New-ObserverOperationResult -Operation WaitUntil -Status executor_fault -Result $result -Fault $destination.fault
        }
    }

    $started = Get-ObserverMonotonicMilliseconds
    $samples = New-Object System.Collections.Generic.List[object]
    $matched = $false
    $terminationReason = $null
    $finalStatus = 'timeout'
    $finalFault = $null
    [Nullable[long]]$minimumSnapshotId = $null
    [Nullable[double]]$minimumMonotonicMs = $null
    $successfulSamples = 0

    while ($samples.Count -lt $MaxSamples) {
        $readParameters = @{
            StatePath = $StatePath
            ExpectedProcessToken = $ExpectedProcessToken
            MaxAgeMs = $MaxAgeMs
        }
        if ($PSBoundParameters.ContainsKey('ExpectedProcessId')) { $readParameters.ExpectedProcessId = $ExpectedProcessId }
        if (-not [string]::IsNullOrEmpty($ExpectedRoundId)) { $readParameters.ExpectedRoundId = $ExpectedRoundId }
        if (-not [string]::IsNullOrEmpty($ExpectedObjectId)) { $readParameters.ExpectedObjectId = $ExpectedObjectId }
        if ($null -ne $minimumSnapshotId) { $readParameters.MinimumSnapshotId = [long]$minimumSnapshotId }
        if ($null -ne $minimumMonotonicMs) { $readParameters.MinimumMonotonicMs = [double]$minimumMonotonicMs }

        $read = Read-UnrealEvaluationState @readParameters
        $telemetrySource = if ($read.status -eq 'ok') {
            $read.result
        }
        elseif ($read.fault -and $read.fault.details) {
            $read.fault.details
        }
        else { $null }
        $readAttemptTelemetry = Get-ObserverProperty -InputObject $telemetrySource `
            -Name 'read_attempt_count'
        $publisherRetryTelemetry = Get-ObserverProperty -InputObject $telemetrySource `
            -Name 'publisher_retry_count'
        $sample = [pscustomobject][ordered]@{
            index = $samples.Count
            observed_monotonic_ms = Get-ObserverMonotonicMilliseconds
            read_status = $read.status
            read_attempt_count = if ($readAttemptTelemetry.Exists) {
                [int]$readAttemptTelemetry.Value
            }
            else { 1 }
            publisher_retry_count = if ($publisherRetryTelemetry.Exists) {
                [int]$publisherRetryTelemetry.Value
            }
            else { 0 }
            snapshot_id = $null
            snapshot_monotonic_ms = $null
            freshness = $null
            predicate_matched = $null
            snapshot = $null
            fault = $read.fault
        }

        if ($read.status -eq 'ok') {
            ++$successfulSamples
            $snapshot = $read.result.snapshot
            $sample.snapshot_id = [int64]$snapshot.snapshot_id
            $sample.snapshot_monotonic_ms = [double]$snapshot.monotonic_ms
            $sample.freshness = $read.result.freshness
            $sample.snapshot = $snapshot
            $minimumSnapshotId = [int64]$snapshot.snapshot_id
            $minimumMonotonicMs = [double]$snapshot.monotonic_ms

            try {
                $predicateResults = @(& $Predicate $snapshot)
            }
            catch {
                $sample.fault = New-ObserverFault -Domain observer -Code 'predicate_execution_failure' -Message 'The trusted wait predicate raised an exception.' -Retryable $false -Details ([pscustomobject][ordered]@{ exception_type = $_.Exception.GetType().FullName })
                $samples.Add($sample)
                $terminationReason = 'predicate_fault'
                $finalStatus = 'executor_fault'
                $finalFault = $sample.fault
                break
            }

            if ($predicateResults.Count -ne 1 -or $predicateResults[0] -isnot [bool]) {
                $sample.fault = New-ObserverFault -Domain observer -Code 'predicate_result_invalid' -Message 'The wait predicate must return exactly one Boolean value; text such as PASS is never accepted.' -Retryable $false
                $samples.Add($sample)
                $terminationReason = 'predicate_fault'
                $finalStatus = 'executor_fault'
                $finalFault = $sample.fault
                break
            }

            $sample.predicate_matched = [bool]$predicateResults[0]
            $samples.Add($sample)
            if ($sample.predicate_matched) {
                $matched = $true
                $terminationReason = 'matched'
                $finalStatus = 'ok'
                break
            }
        }
        else {
            $samples.Add($sample)
            if ($read.status -ne 'unsupported' -or
                -not $read.fault -or -not $read.fault.retryable) {
                $terminationReason = 'observer_fault'
                $finalStatus = $read.status
                $finalFault = $read.fault
                break
            }
        }

        $elapsed = (Get-ObserverMonotonicMilliseconds) - $started
        if ($elapsed -ge $TimeoutMs) {
            $terminationReason = 'timeout'
            $finalStatus = if ($successfulSamples -eq 0) { 'unsupported' } else { 'timeout' }
            if ($successfulSamples -eq 0) { $finalFault = $read.fault }
            break
        }
        if ($samples.Count -ge $MaxSamples) {
            $terminationReason = 'max_samples'
            $finalStatus = if ($successfulSamples -eq 0) { 'unsupported' } else { 'timeout' }
            if ($successfulSamples -eq 0) { $finalFault = $read.fault }
            break
        }

        $remaining = $TimeoutMs - $elapsed
        $sleepMs = [Math]::Min($IntervalMs, $remaining)
        if ($sleepMs -gt 0) {
            [System.Threading.Thread]::Sleep([int]$sleepMs)
        }
    }

    if ($null -eq $terminationReason) {
        $terminationReason = 'max_samples'
        $finalStatus = if ($successfulSamples -eq 0) { 'unsupported' } else { 'timeout' }
        if ($successfulSamples -eq 0 -and $samples.Count -gt 0) { $finalFault = $samples[$samples.Count - 1].fault }
    }

    $ended = Get-ObserverMonotonicMilliseconds
    [object[]]$sampleArray = $samples.ToArray()
    $result = [pscustomobject][ordered]@{
        matched = $matched
        termination_reason = $terminationReason
        started_observer_monotonic_ms = $started
        ended_observer_monotonic_ms = $ended
        elapsed_ms = $ended - $started
        timeout_ms = $TimeoutMs
        interval_ms = $IntervalMs
        max_samples = $MaxSamples
        sample_count = $samples.Count
        samples = $sampleArray
    }
    $evidence = @()

    if ($null -ne $destination) {
        $payload = [pscustomobject][ordered]@{
            schema_version = $script:ObserverSchemaVersion
            operation = 'WaitUntil'
            matched = $matched
            termination_reason = $terminationReason
            started_observer_monotonic_ms = $started
            ended_observer_monotonic_ms = $ended
            elapsed_ms = $ended - $started
            timeout_ms = $TimeoutMs
            interval_ms = $IntervalMs
            max_samples = $MaxSamples
            sample_count = $samples.Count
            samples = $sampleArray
        }
        $write = Write-ObserverEvidence -Payload $payload -Destination $destination
        if (-not $write.written) {
            $result.termination_reason = 'evidence_fault'
            $finalStatus = 'executor_fault'
            $finalFault = $write.fault
        }
        else {
            $evidence = @($write.evidence)
        }
    }

    return New-ObserverOperationResult -Operation WaitUntil -Status $finalStatus -Result $result -Fault $finalFault -Evidence $evidence
}

function Find-UnrealVisibleTarget {
    [CmdletBinding(DefaultParameterSetName = 'Snapshot')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Snapshot', Position = 0)]
        [ValidateNotNull()]
        [object]$Snapshot,

        [Parameter(Mandatory = $true, ParameterSetName = 'StatePath')]
        [ValidateNotNullOrEmpty()]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetId,

        [Parameter(Mandatory = $true, ParameterSetName = 'StatePath')]
        [Parameter(ParameterSetName = 'Snapshot')]
        [string]$ExpectedProcessToken,

        [ValidateRange(1, 600000)]
        [int]$MaxAgeMs = 2000,

        [ValidateRange(1, 2147483647)]
        [int]$ExpectedProcessId,

        [string]$ExpectedRoundId,

        [string]$ExpectedObjectId
    )

    $state = $null
    $freshness = $null
    if ($PSCmdlet.ParameterSetName -eq 'StatePath') {
        $readParameters = @{
            StatePath = $StatePath
            ExpectedProcessToken = $ExpectedProcessToken
            MaxAgeMs = $MaxAgeMs
        }
        if ($PSBoundParameters.ContainsKey('ExpectedProcessId')) { $readParameters.ExpectedProcessId = $ExpectedProcessId }
        if (-not [string]::IsNullOrEmpty($ExpectedRoundId)) { $readParameters.ExpectedRoundId = $ExpectedRoundId }
        if (-not [string]::IsNullOrEmpty($ExpectedObjectId)) { $readParameters.ExpectedObjectId = $ExpectedObjectId }
        $read = Read-UnrealEvaluationState @readParameters
        if ($read.status -ne 'ok') {
            return New-ObserverOperationResult -Operation FindVisibleTarget -Status $read.status -Fault $read.fault
        }
        $state = $read.result.snapshot
        $freshness = $read.result.freshness
    }
    else {
        $possibleOperation = Get-ObserverProperty -InputObject $Snapshot -Name 'operation'
        $possibleStatus = Get-ObserverProperty -InputObject $Snapshot -Name 'status'
        if ($possibleOperation.Exists -and $possibleOperation.Value -eq 'ReadState') {
            if (-not $possibleStatus.Exists -or $possibleStatus.Value -ne 'ok') {
                $fault = New-ObserverFault -Domain observer -Code 'source_snapshot_unusable' -Message 'FindVisibleTarget requires a successful ReadState result or a raw valid snapshot.' -Retryable $false
                return New-ObserverOperationResult -Operation FindVisibleTarget -Status executor_fault -Fault $fault
            }
            $readResult = Get-ObserverProperty -InputObject $Snapshot -Name 'result'
            $stateValue = if ($readResult.Exists) { Get-ObserverProperty -InputObject $readResult.Value -Name 'snapshot' } else { $null }
            $freshnessValue = if ($readResult.Exists) { Get-ObserverProperty -InputObject $readResult.Value -Name 'freshness' } else { $null }
            if (-not $readResult.Exists -or -not $stateValue.Exists) {
                $fault = New-ObserverFault -Domain observer -Code 'source_snapshot_unusable' -Message 'The ReadState result does not contain a usable snapshot.' -Retryable $false
                return New-ObserverOperationResult -Operation FindVisibleTarget -Status executor_fault -Fault $fault
            }
            $state = $stateValue.Value
            if ($freshnessValue.Exists) { $freshness = $freshnessValue.Value }
        }
        else {
            $state = $Snapshot
        }

        $expectedPid = if ($PSBoundParameters.ContainsKey('ExpectedProcessId')) { [Nullable[int]]$ExpectedProcessId } else { [Nullable[int]]$null }
        $contract = Test-UnrealSnapshotContract -Snapshot $state -ExpectedProcessToken $ExpectedProcessToken -ExpectedProcessId $expectedPid -ExpectedRoundId $ExpectedRoundId -ExpectedObjectId $ExpectedObjectId -MinimumSnapshotId ([Nullable[long]]$null) -MinimumMonotonicMs ([Nullable[double]]$null)
        if (-not $contract.valid) {
            return New-ObserverOperationResult -Operation FindVisibleTarget -Status executor_fault -Fault $contract.fault
        }
    }

    $matches = @($state.targets | Where-Object { $_.target_id -ceq $TargetId })
    if ($matches.Count -eq 0) {
        $result = [pscustomobject][ordered]@{
            found = $false
            usable = $false
            classification = 'target_not_found'
            target_id = $TargetId
            object_id = $null
            normalized_bounds = $null
            visible = $false
            enabled = $null
            topmost = $null
            activation = $null
            source_snapshot_id = [int64]$state.snapshot_id
            source_round_id = [string]$state.round_id
            source_monotonic_ms = [double]$state.monotonic_ms
            freshness = $freshness
        }
        return New-ObserverOperationResult -Operation FindVisibleTarget -Status ok -Result $result -TargetVisible $false
    }
    if ($matches.Count -ne 1) {
        $fault = New-ObserverFault -Domain observer -Code 'target_metadata_ambiguous' -Message 'The current snapshot contains duplicate target identities.' -Retryable $false
        return New-ObserverOperationResult -Operation FindVisibleTarget -Status executor_fault -Fault $fault
    }

    $target = $matches[0]
    $targetObjectId = Get-ObserverProperty -InputObject $target -Name 'object_id'
    $visible = Get-ObserverProperty -InputObject $target -Name 'visible'
    $enabled = Get-ObserverProperty -InputObject $target -Name 'enabled'
    $topmost = Get-ObserverProperty -InputObject $target -Name 'topmost'
    $activation = Get-ObserverProperty -InputObject $target -Name 'activation'
    $bounds = Get-ObserverProperty -InputObject $target -Name 'normalized_bounds'
    if (-not $targetObjectId.Exists -or -not (Test-ObserverStableId -Value $targetObjectId.Value) -or
        -not $visible.Exists -or $visible.Value -isnot [bool] -or
        -not $enabled.Exists -or $enabled.Value -isnot [bool] -or
        -not $topmost.Exists -or $topmost.Value -isnot [bool] -or
        -not $activation.Exists -or -not (Test-ObserverStableId -Value $activation.Value) -or
        -not $bounds.Exists) {
        $fault = New-ObserverFault -Domain observer -Code 'target_metadata_invalid' -Message 'The current snapshot target metadata is incomplete or invalid.' -Retryable $false
        return New-ObserverOperationResult -Operation FindVisibleTarget -Status executor_fault -Fault $fault
    }

    $x = Get-ObserverProperty -InputObject $bounds.Value -Name 'x'
    $y = Get-ObserverProperty -InputObject $bounds.Value -Name 'y'
    $width = Get-ObserverProperty -InputObject $bounds.Value -Name 'width'
    $height = Get-ObserverProperty -InputObject $bounds.Value -Name 'height'
    if (-not $x.Exists -or -not $y.Exists -or -not $width.Exists -or -not $height.Exists -or
        -not (Test-ObserverNumber -Value $x.Value) -or -not (Test-ObserverNumber -Value $y.Value) -or
        -not (Test-ObserverNumber -Value $width.Value) -or -not (Test-ObserverNumber -Value $height.Value)) {
        $fault = New-ObserverFault -Domain observer -Code 'target_bounds_invalid' -Message 'The target normalized bounds are missing or invalid.' -Retryable $false
        return New-ObserverOperationResult -Operation FindVisibleTarget -Status executor_fault -Fault $fault
    }

    $normalizedBounds = [pscustomobject][ordered]@{
        x = [double]$x.Value
        y = [double]$y.Value
        width = [double]$width.Value
        height = [double]$height.Value
    }
    if ($normalizedBounds.x -lt 0 -or $normalizedBounds.y -lt 0 -or
        $normalizedBounds.width -le 0 -or $normalizedBounds.height -le 0 -or
        $normalizedBounds.x + $normalizedBounds.width -gt 1 -or
        $normalizedBounds.y + $normalizedBounds.height -gt 1) {
        $fault = New-ObserverFault -Domain observer -Code 'target_bounds_out_of_range' -Message 'The target normalized bounds are outside the current client area.' -Retryable $false
        return New-ObserverOperationResult -Operation FindVisibleTarget -Status executor_fault -Fault $fault
    }

    $classification = 'usable'
    if (-not $visible.Value) { $classification = 'target_not_visible' }
    elseif (-not $enabled.Value) { $classification = 'target_disabled' }
    elseif (-not $topmost.Value) { $classification = 'target_not_topmost' }
    $usable = $classification -eq 'usable'

    $result = [pscustomobject][ordered]@{
        found = $true
        usable = $usable
        classification = $classification
        target_id = [string]$TargetId
        object_id = [string]$targetObjectId.Value
        normalized_bounds = if ($usable) { $normalizedBounds } else { $null }
        visible = [bool]$visible.Value
        enabled = [bool]$enabled.Value
        topmost = [bool]$topmost.Value
        activation = [string]$activation.Value
        source_snapshot_id = [int64]$state.snapshot_id
        source_round_id = [string]$state.round_id
        source_monotonic_ms = [double]$state.monotonic_ms
        freshness = $freshness
    }
    return New-ObserverOperationResult -Operation FindVisibleTarget -Status ok -Result $result -TargetVisible ([bool]$visible.Value)
}

Export-ModuleMember -Function @(
    'Read-UnrealEvaluationState',
    'Wait-UnrealEvaluationCondition',
    'Find-UnrealVisibleTarget'
)
