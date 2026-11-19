[CmdletBinding()]
param(
    [ValidatePattern('^run-[A-Za-z0-9][A-Za-z0-9._-]{0,119}$')]
    [string]$RunId,

    [string]$EngineRoot,

    [string]$EditorPath,

    [string]$LauncherManifestPath,

    [ValidateRange(3, 10)]
    [int]$RepeatCount = 3,

    [ValidateRange(1000, 300000)]
    [int]$StartTimeoutMs = 90000,

    [ValidateRange(1000, 1800000)]
    [int]$BuildTimeoutMs = 900000,

    [ValidateRange(100, 120000)]
    [int]$StopTimeoutMs = 15000,

    [ValidateRange(100, 10000)]
    [int]$ObserverMaxAgeMs = 2000,

    [ValidateRange(50, 5000)]
    [int]$ControlFeedbackBoundaryMs = 1500,

    [switch]$NoPublishLatest,

    [Parameter(DontShow)]
    [switch]$NoInvoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ValidationSchemaVersion = '1.0.0'
$script:ValidationCommandPath = [IO.Path]::GetFullPath($PSCommandPath)
$script:ValidationClock = [Diagnostics.Stopwatch]::StartNew()
$script:CapabilityNames = @(
    'Start', 'Stop', 'PressKey', 'HoldKey', 'ReleaseKey', 'MovePointer',
    'MouseDown', 'MouseUp', 'Click', 'Drag', 'FindVisibleTarget', 'ReadState',
    'WaitUntil', 'Capture', 'Restart', 'Reopen'
)
$script:GeneratedDirectoryNames = @(
    'Binaries', 'DerivedDataCache', 'Intermediate', 'Saved', 'CollectedPSOs'
)

function Get-ValidationMonotonicMs {
    return [long]$script:ValidationClock.ElapsedMilliseconds
}

function New-ValidationRunId {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ',
        [Globalization.CultureInfo]::InvariantCulture)
    return 'run-{0}-{1}' -f $stamp, [guid]::NewGuid().ToString('N').Substring(0, 12)
}

function Test-ValidationRelativePath {
    param([AllowNull()][string]$Path)

    return -not [string]::IsNullOrWhiteSpace($Path) -and
        $Path.Length -le 1024 -and
        $Path -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$'
}

function Test-ValidationAncestorChainSafe {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $full = [IO.Path]::GetFullPath($Path)
        $cursorPath = $full
        while (-not [IO.File]::Exists($cursorPath) -and
            -not [IO.Directory]::Exists($cursorPath)) {
            $parent = [IO.Path]::GetDirectoryName($cursorPath)
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $cursorPath) {
                return $false
            }
            $cursorPath = $parent
        }

        $cursor = Get-Item -LiteralPath $cursorPath -Force -ErrorAction Stop
        while ($null -ne $cursor) {
            if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $false
            }
            if ($cursor -is [IO.FileInfo]) {
                $cursor = $cursor.Directory
            }
            else {
                $cursor = $cursor.Parent
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Get-ValidationSafeFullPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireLeaf,
        [switch]$RequireContainer
    )

    try {
        if ($Path.IndexOf([char]0) -ge 0) { return $null }
        $full = [IO.Path]::GetFullPath($Path)
        if (-not (Test-ValidationAncestorChainSafe -Path $full)) { return $null }
        if ($RequireLeaf -and -not [IO.File]::Exists($full)) { return $null }
        if ($RequireContainer -and -not [IO.Directory]::Exists($full)) { return $null }
        return $full
    }
    catch {
        return $null
    }
}

function Test-ValidationPathWithinRoot {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowRoot
    )

    $rootFull = Get-ValidationSafeFullPath -Path $Root
    $pathFull = Get-ValidationSafeFullPath -Path $Path
    if (-not $rootFull -or -not $pathFull) { return $false }
    if ($AllowRoot -and $pathFull.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $rootFull.TrimEnd([char[]]@(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
    return $pathFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function New-ValidationDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$RefuseExisting
    )

    $full = Get-ValidationSafeFullPath -Path $Path
    if (-not $full) { throw [InvalidOperationException]::new('validation_path_unsafe') }
    if ([IO.File]::Exists($full) -or [IO.Directory]::Exists($full)) {
        if ($RefuseExisting) {
            throw [InvalidOperationException]::new('validation_output_exists')
        }
        if (-not [IO.Directory]::Exists($full)) {
            throw [InvalidOperationException]::new('validation_path_not_directory')
        }
        return $full
    }
    $parent = [IO.Path]::GetDirectoryName($full)
    if ([string]::IsNullOrEmpty($parent) -or
        -not [IO.Directory]::Exists($parent) -or
        -not (Test-ValidationAncestorChainSafe -Path $parent)) {
        throw [InvalidOperationException]::new('validation_parent_unavailable')
    }
    $created = New-Item -ItemType Directory -Path $full -ErrorAction Stop
    if (($created.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw [InvalidOperationException]::new('validation_directory_reparse_point')
    }
    return $full
}

function New-ValidationRunLayout {
    param(
        [Parameter(Mandatory)][string]$ValidationRoot,
        [Parameter(Mandatory)][string]$RequestedRunId
    )

    if ($RequestedRunId -cnotmatch '^run-[A-Za-z0-9][A-Za-z0-9._-]{0,119}$') {
        throw [InvalidOperationException]::new('validation_run_id_invalid')
    }
    $validationFull = Get-ValidationSafeFullPath -Path $ValidationRoot
    if (-not $validationFull) {
        $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ValidationRoot))
        if (-not [IO.Directory]::Exists($parent) -or
            -not (Test-ValidationAncestorChainSafe -Path $parent)) {
            throw [InvalidOperationException]::new('validation_root_parent_unsafe')
        }
        $validationFull = New-ValidationDirectory -Path $ValidationRoot -RefuseExisting
    }
    elseif (-not [IO.Directory]::Exists($validationFull)) {
        $validationFull = New-ValidationDirectory -Path $validationFull -RefuseExisting
    }

    $runsRoot = Join-Path $validationFull 'runs'
    if (-not [IO.Directory]::Exists($runsRoot)) {
        [void](New-ValidationDirectory -Path $runsRoot -RefuseExisting)
    }
    elseif (-not (Test-ValidationAncestorChainSafe -Path $runsRoot)) {
        throw [InvalidOperationException]::new('validation_runs_root_unsafe')
    }

    $runRoot = Join-Path $runsRoot $RequestedRunId
    [void](New-ValidationDirectory -Path $runRoot -RefuseExisting)
    foreach ($name in @('raw')) {
        [void](New-ValidationDirectory -Path (Join-Path $runRoot $name) -RefuseExisting)
    }
    return [pscustomobject][ordered]@{
        validation_root = $validationFull
        runs_root = $runsRoot
        run_root = $runRoot
        raw_root = Join-Path $runRoot 'raw'
        fixture_root = Join-Path $runRoot 'fixture'
    }
}

function Resolve-ValidationArtifactDestination {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    if (-not (Test-ValidationRelativePath -Path $RelativePath)) {
        throw [InvalidOperationException]::new('validation_artifact_path_invalid')
    }
    $runFull = Get-ValidationSafeFullPath -Path $RunRoot -RequireContainer
    if (-not $runFull) { throw [InvalidOperationException]::new('validation_run_root_unsafe') }
    $nativeRelative = $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $destination = [IO.Path]::GetFullPath([IO.Path]::Combine($runFull, $nativeRelative))
    if (-not (Test-ValidationPathWithinRoot -Root $runFull -Path $destination)) {
        throw [InvalidOperationException]::new('validation_artifact_path_escape')
    }

    $parent = [IO.Path]::GetDirectoryName($destination)
    $rootPrefix = $runFull.TrimEnd([char[]]@(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
    $relativeParent = if ($parent.Equals($runFull, [StringComparison]::OrdinalIgnoreCase)) {
        ''
    }
    else { $parent.Substring($rootPrefix.Length) }
    $cursor = $runFull
    if (-not [string]::IsNullOrEmpty($relativeParent)) {
        foreach ($segment in $relativeParent.Split(
                [char[]]@([IO.Path]::DirectorySeparatorChar),
                [StringSplitOptions]::RemoveEmptyEntries)) {
            $cursor = [IO.Path]::Combine($cursor, $segment)
            if (-not [IO.Directory]::Exists($cursor)) {
                [void](New-ValidationDirectory -Path $cursor -RefuseExisting)
            }
            if (-not (Test-ValidationAncestorChainSafe -Path $cursor)) {
                throw [InvalidOperationException]::new('validation_artifact_parent_unsafe')
            }
        }
    }
    if ([IO.File]::Exists($destination) -or [IO.Directory]::Exists($destination)) {
        throw [InvalidOperationException]::new('validation_artifact_exists')
    }
    return $destination
}

function Get-ValidationSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return -join ($algorithm.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-ValidationCurrentRuntimeIdentity {
    $unrealRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $paths = [ordered]@{
        executor_sha256 = Join-Path $unrealRoot 'executor/UnrealEvaluationExecutor.psm1'
        observer_sha256 = Join-Path $unrealRoot 'observer/UnrealEvaluationObserver.psm1'
        validation_command_sha256 = $script:ValidationCommandPath
    }
    $identity = [ordered]@{}
    foreach ($name in $paths.Keys) {
        $fullPath = Get-ValidationSafeFullPath -Path ([string]$paths[$name]) -RequireLeaf
        if (-not $fullPath) {
            throw [InvalidOperationException]::new('validation_runtime_identity_input_unsafe')
        }
        $identity[$name] = Get-ValidationSha256 -Bytes ([IO.File]::ReadAllBytes($fullPath))
    }
    return [pscustomobject]$identity
}

function New-ValidationEvidenceReference {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$MediaType,
        [Parameter(Mandatory)]
        [ValidateSet('state', 'wait_samples', 'capture', 'input_receipt', 'process',
            'cleanup', 'redacted_log', 'report')]
        [string]$Kind,
        [string]$ProducerId = 'unreal-capability-validation',
        [string]$ProducerVersion = '1.0.0'
    )

    return [pscustomobject][ordered]@{
        path = $RelativePath
        sha256 = Get-ValidationSha256 -Bytes $Bytes
        media_type = $MediaType
        byte_length = [long]$Bytes.Length
        captured_monotonic_ms = Get-ValidationMonotonicMs
        kind = $Kind
        producer = [pscustomobject][ordered]@{
            id = $ProducerId
            version = $ProducerVersion
        }
    }
}

function Write-ValidationBytesArtifact {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$MediaType,
        [Parameter(Mandatory)][string]$Kind
    )

    $destination = Resolve-ValidationArtifactDestination -RunRoot $RunRoot `
        -RelativePath $RelativePath
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($destination)) `
        ('validation-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    try {
        $stream = [IO.FileStream]::new(
            $temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($Bytes, 0, $Bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
        [IO.File]::Move($temporary, $destination)
        $temporary = $null
    }
    finally {
        if ($temporary -and [IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
    }
    return New-ValidationEvidenceReference -RelativePath $RelativePath -Bytes $Bytes `
        -MediaType $MediaType -Kind $Kind
}

function Write-ValidationJsonArtifact {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Kind
    )

    $json = $Value | ConvertTo-Json -Depth 64
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
    return Write-ValidationBytesArtifact -RunRoot $RunRoot -RelativePath $RelativePath `
        -Bytes $bytes -MediaType 'application/json' -Kind $Kind
}

function Write-ValidationTextArtifact {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Kind,
        [string]$MediaType = 'text/plain'
    )

    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    return Write-ValidationBytesArtifact -RunRoot $RunRoot -RelativePath $RelativePath `
        -Bytes $bytes -MediaType $MediaType -Kind $Kind
}

function Protect-ValidationText {
    param(
        [AllowNull()][string]$Text,
        [string[]]$SensitiveValues = @()
    )

    if ($null -eq $Text) { return $null }
    $safe = [string]$Text
    $orderedValues = @($SensitiveValues |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object Length -Descending -Unique)
    foreach ($value in $orderedValues) {
        $escapedValue = [regex]::Escape($value)
        $pattern = if ($value.IndexOfAny([char[]]@(
                    [IO.Path]::DirectorySeparatorChar,
                    [IO.Path]::AltDirectorySeparatorChar, ':')) -ge 0) {
            $escapedValue
        }
        else { '(?<![A-Za-z0-9_.-])' + $escapedValue + '(?![A-Za-z0-9_.-])' }
        $safe = [regex]::Replace($safe, $pattern, '[REDACTED]',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    $safe = [regex]::Replace(
        $safe,
        '(?is)-----BEGIN [^-\r\n]*PRIVATE KEY-----.*?-----END [^-\r\n]*PRIVATE KEY-----',
        '[REDACTED_PRIVATE_KEY]')
    $safe = [regex]::Replace(
        $safe,
        '(?i)\b(password|secret|api[_-]?key|authorization)\b\s*[:=]\s*[^\s,;]+',
        '$1=[REDACTED]')
    $safe = [regex]::Replace(
        $safe,
        '(?i)(?<![A-Za-z0-9_.-])[A-Z]:[\\/][^\r\n\t"<>|]*',
        '[REDACTED_PATH]')
    $safe = [regex]::Replace(
        $safe,
        '(?i)\\\\[^\\/\s]+[\\/][^\r\n\t"<>|]*',
        '[REDACTED_PATH]')
    return $safe
}

function ConvertTo-ValidationPublicValue {
    param(
        [AllowNull()][object]$Value,
        [string[]]$SensitiveValues = @(),
        [ValidateRange(0, 32)][int]$Depth = 0
    )

    if ($null -eq $Value) { return $null }
    if ($Depth -ge 20) { return '[TRUNCATED]' }
    if ($Value -is [string]) {
        return Protect-ValidationText -Text ([string]$Value) -SensitiveValues $SensitiveValues
    }
    if ($Value -is [bool] -or $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or
        $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal] -or
        $Value -is [DateTime]) {
        return $Value
    }
    if ($Value -is [Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in @($Value.Keys)) {
            $name = [string]$key
            if ($name -cmatch '^(EngineRoot|EditorPath|ProjectPath|RunRoot|StatePath|Process|JobHandle|WindowHandle)$') {
                continue
            }
            $copy[$name] = ConvertTo-ValidationPublicValue -Value $Value[$key] `
                -SensitiveValues $SensitiveValues -Depth ($Depth + 1)
        }
        return [pscustomobject]$copy
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object {
                ConvertTo-ValidationPublicValue -Value $_ -SensitiveValues $SensitiveValues `
                    -Depth ($Depth + 1)
            })
    }

    $properties = @($Value.PSObject.Properties | Where-Object {
            $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')
        })
    if ($properties.Count -eq 0) {
        return Protect-ValidationText -Text ([string]$Value) -SensitiveValues $SensitiveValues
    }
    $copy = [ordered]@{}
    foreach ($property in $properties) {
        if ($property.Name -cmatch '^(session|EngineRoot|EditorPath|ProjectPath|RunRoot|StatePath|Process|JobHandle|WindowHandle)$') {
            continue
        }
        try { $propertyValue = $property.Value } catch { $propertyValue = $null }
        $copy[$property.Name] = ConvertTo-ValidationPublicValue -Value $propertyValue `
            -SensitiveValues $SensitiveValues -Depth ($Depth + 1)
    }
    return [pscustomobject]$copy
}

function Get-ValidationPublicOperationRecord {
    param(
        [Parameter(Mandatory)][object]$OperationResult,
        [string[]]$SensitiveValues = @()
    )

    return [pscustomobject][ordered]@{
        schema_version = if ($OperationResult.PSObject.Properties['schema_version']) {
            [string]$OperationResult.schema_version
        }
        else { $script:ValidationSchemaVersion }
        operation = if ($OperationResult.PSObject.Properties['operation']) {
            [string]$OperationResult.operation
        }
        else { 'Unknown' }
        status = if ($OperationResult.PSObject.Properties['status']) {
            [string]$OperationResult.status
        }
        else { 'executor_fault' }
        observer_monotonic_ms = if ($OperationResult.PSObject.Properties['observer_monotonic_ms']) {
            [long]$OperationResult.observer_monotonic_ms
        }
        else { Get-ValidationMonotonicMs }
        input_dispatched = [bool]($OperationResult.PSObject.Properties['input_dispatched'] -and
            $OperationResult.input_dispatched)
        feedback_observed = if ($OperationResult.PSObject.Properties['feedback_observed']) {
            $OperationResult.feedback_observed
        }
        else { $null }
        target_visible = if ($OperationResult.PSObject.Properties['target_visible']) {
            $OperationResult.target_visible
        }
        else { $null }
        executor_fault = [bool]($OperationResult.PSObject.Properties['executor_fault'] -and
            $OperationResult.executor_fault)
        environment_fault = [bool]($OperationResult.PSObject.Properties['environment_fault'] -and
            $OperationResult.environment_fault)
        unsupported = [bool]($OperationResult.PSObject.Properties['unsupported'] -and
            $OperationResult.unsupported)
        result = if ($OperationResult.PSObject.Properties['result']) {
            ConvertTo-ValidationPublicValue -Value $OperationResult.result `
                -SensitiveValues $SensitiveValues
        }
        else { $null }
        fault = if ($OperationResult.PSObject.Properties['fault']) {
            ConvertTo-ValidationPublicValue -Value $OperationResult.fault `
                -SensitiveValues $SensitiveValues
        }
        else { $null }
        evidence = if ($OperationResult.PSObject.Properties['evidence']) {
            @(ConvertTo-ValidationPublicValue -Value @($OperationResult.evidence) `
                    -SensitiveValues $SensitiveValues)
        }
        else { @() }
    }
}

function Test-ValidationEvidenceIntegrity {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][object]$Evidence
    )

    foreach ($requiredProperty in @('path', 'sha256', 'byte_length')) {
        if (-not $Evidence.PSObject.Properties[$requiredProperty]) {
            return [pscustomobject]@{
                valid = $false
                classification = 'evidence_metadata_invalid'
            }
        }
    }
    if (-not (Test-ValidationRelativePath -Path ([string]$Evidence.path))) {
        return [pscustomobject]@{ valid = $false; classification = 'evidence_path_invalid' }
    }
    try { $expectedLength = [long]$Evidence.byte_length }
    catch {
        return [pscustomobject]@{
            valid = $false
            classification = 'evidence_metadata_invalid'
        }
    }
    if ([string]$Evidence.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $expectedLength -lt 0) {
        return [pscustomobject]@{
            valid = $false
            classification = 'evidence_metadata_invalid'
        }
    }
    $nativeRelative = ([string]$Evidence.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath([IO.Path]::Combine($RunRoot, $nativeRelative))
    if (-not (Test-ValidationPathWithinRoot -Root $RunRoot -Path $full) -or
        -not [IO.File]::Exists($full)) {
        return [pscustomobject]@{ valid = $false; classification = 'evidence_missing' }
    }
    if (-not (Test-ValidationAncestorChainSafe -Path $full)) {
        return [pscustomobject]@{ valid = $false; classification = 'evidence_reparse_point' }
    }
    try {
        [byte[]]$bytes = [IO.File]::ReadAllBytes($full)
        $hash = Get-ValidationSha256 -Bytes $bytes
        if ($hash -cne [string]$Evidence.sha256 -or
            [long]$bytes.Length -ne $expectedLength) {
            return [pscustomobject]@{ valid = $false; classification = 'evidence_corrupted' }
        }
        return [pscustomobject]@{ valid = $true; classification = 'verified' }
    }
    catch {
        return [pscustomobject]@{ valid = $false; classification = 'evidence_unreadable' }
    }
}

function Copy-ValidationFixtureTree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $sourceFull = Get-ValidationSafeFullPath -Path $Source -RequireContainer
    if (-not $sourceFull) {
        throw [InvalidOperationException]::new('fixture_source_unsafe')
    }
    if ([IO.File]::Exists($Destination) -or [IO.Directory]::Exists($Destination)) {
        throw [InvalidOperationException]::new('fixture_destination_exists')
    }
    $destinationFull = Get-ValidationSafeFullPath -Path $Destination
    if (-not $destinationFull) {
        throw [InvalidOperationException]::new('fixture_destination_unsafe')
    }

    $sourceItems = @(Get-ChildItem -LiteralPath $sourceFull -Force -Recurse -ErrorAction Stop)
    foreach ($item in $sourceItems) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw [InvalidOperationException]::new('fixture_source_reparse_point')
        }
    }

    [void](New-ValidationDirectory -Path $destinationFull -RefuseExisting)
    foreach ($item in $sourceItems | Sort-Object FullName) {
        $relative = [IO.Path]::GetRelativePath($sourceFull, $item.FullName)
        $segments = $relative.Split([char[]]@(
                [IO.Path]::DirectorySeparatorChar,
                [IO.Path]::AltDirectorySeparatorChar),
            [StringSplitOptions]::RemoveEmptyEntries)
        if (@($segments | Where-Object { $_ -in $script:GeneratedDirectoryNames }).Count -gt 0) {
            continue
        }
        $target = [IO.Path]::Combine($destinationFull, $relative)
        if ($item.PSIsContainer) {
            if (-not [IO.Directory]::Exists($target)) {
                [void](New-ValidationDirectory -Path $target -RefuseExisting)
            }
        }
        else {
            $targetParent = [IO.Path]::GetDirectoryName($target)
            if (-not [IO.Directory]::Exists($targetParent)) {
                [void](New-ValidationDirectory -Path $targetParent -RefuseExisting)
            }
            [IO.File]::Copy($item.FullName, $target, $false)
        }
    }

    $project = Join-Path $destinationFull 'MinimalInterface.uproject'
    if (-not [IO.File]::Exists($project)) {
        throw [InvalidOperationException]::new('fixture_project_missing')
    }
    return [pscustomobject][ordered]@{
        fixture_root = $destinationFull
        project_path = $project
    }
}

function Remove-ValidationFixtureTree {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$FixtureRoot
    )

    try {
        $runFull = Get-ValidationSafeFullPath -Path $RunRoot -RequireContainer
        $fixtureFull = Get-ValidationSafeFullPath -Path $FixtureRoot -RequireContainer
        if (-not $runFull -or -not $fixtureFull -or
            -not (Test-ValidationPathWithinRoot -Root $runFull -Path $fixtureFull) -or
            [IO.Path]::GetFileName($fixtureFull) -cne 'fixture') {
            return $false
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $fixtureFull -Force -Recurse -ErrorAction Stop)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $false
            }
        }
        [IO.Directory]::Delete($fixtureFull, $true)
        return -not [IO.Directory]::Exists($fixtureFull)
    }
    catch {
        return $false
    }
}

function Get-ValidationEngineVersion {
    param([Parameter(Mandatory)][string]$CandidateRoot)

    $rootFull = Get-ValidationSafeFullPath -Path $CandidateRoot -RequireContainer
    if (-not $rootFull) { return $null }
    $versionPath = Join-Path $rootFull 'Engine/Build/Build.version'
    $editor = Join-Path $rootFull 'Engine/Binaries/Win64/UnrealEditor.exe'
    $buildTool = Join-Path $rootFull 'Engine/Build/BatchFiles/Build.bat'
    if (-not (Get-ValidationSafeFullPath -Path $versionPath -RequireLeaf) -or
        -not (Get-ValidationSafeFullPath -Path $editor -RequireLeaf) -or
        -not (Get-ValidationSafeFullPath -Path $buildTool -RequireLeaf)) {
        return $null
    }
    try {
        if ((Get-Item -LiteralPath $versionPath -ErrorAction Stop).Length -gt 65536) {
            return $null
        }
        $version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ([int]$version.MajorVersion -ne 5 -or [int]$version.MinorVersion -ne 6) {
            return $null
        }
        return [pscustomobject][ordered]@{
            engine_root = $rootFull
            editor_path = [IO.Path]::GetFullPath($editor)
            build_tool_path = [IO.Path]::GetFullPath($buildTool)
            version = '{0}.{1}.{2}' -f [int]$version.MajorVersion,
                [int]$version.MinorVersion, [int]$version.PatchVersion
            source = 'unknown'
        }
    }
    catch {
        return $null
    }
}

function Resolve-ValidationEngineInstallation {
    param(
        [AllowNull()][string]$RequestedEngineRoot,
        [AllowNull()][string]$RequestedEditorPath,
        [AllowNull()][string]$RequestedLauncherManifestPath
    )

    if ($RequestedEngineRoot -and $RequestedEditorPath) {
        throw [InvalidOperationException]::new('engine_selection_ambiguous')
    }
    if ($RequestedEngineRoot) {
        $installation = Get-ValidationEngineVersion -CandidateRoot $RequestedEngineRoot
        if (-not $installation) {
            throw [InvalidOperationException]::new('ue56_root_invalid')
        }
        $installation.source = 'explicit_root'
        return $installation
    }
    if ($RequestedEditorPath) {
        $editorFull = Get-ValidationSafeFullPath -Path $RequestedEditorPath -RequireLeaf
        if (-not $editorFull -or [IO.Path]::GetFileName($editorFull) -ine 'UnrealEditor.exe') {
            throw [InvalidOperationException]::new('ue56_editor_invalid')
        }
        try {
            $candidateRoot = ([IO.FileInfo]::new($editorFull)).Directory.Parent.Parent.Parent.FullName
        }
        catch {
            throw [InvalidOperationException]::new('ue56_editor_invalid')
        }
        $installation = Get-ValidationEngineVersion -CandidateRoot $candidateRoot
        if (-not $installation -or $installation.editor_path -ine $editorFull) {
            throw [InvalidOperationException]::new('ue56_editor_invalid')
        }
        $installation.source = 'explicit_editor'
        return $installation
    }

    $candidates = [Collections.Generic.List[object]]::new()
    $manifestCandidates = [Collections.Generic.List[string]]::new()
    if ($RequestedLauncherManifestPath) {
        $manifestCandidates.Add($RequestedLauncherManifestPath)
    }
    elseif ($env:ProgramData) {
        $manifestCandidates.Add((Join-Path $env:ProgramData `
                    'Epic/UnrealEngineLauncher/LauncherInstalled.dat'))
    }
    foreach ($manifestCandidate in $manifestCandidates) {
        $manifestFull = Get-ValidationSafeFullPath -Path $manifestCandidate -RequireLeaf
        if (-not $manifestFull) { continue }
        try {
            if ((Get-Item -LiteralPath $manifestFull).Length -gt 4194304) { continue }
            $manifest = Get-Content -LiteralPath $manifestFull -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop
            foreach ($entry in @($manifest.InstallationList)) {
                if (-not $entry.InstallLocation) { continue }
                $candidate = Get-ValidationEngineVersion -CandidateRoot ([string]$entry.InstallLocation)
                if ($candidate) {
                    $candidate.source = 'launcher_manifest'
                    $candidates.Add($candidate)
                }
            }
        }
        catch { }
    }

    $parents = [Collections.Generic.List[string]]::new()
    if ($env:ProgramFiles) { $parents.Add((Join-Path $env:ProgramFiles 'Epic Games')) }
    if ($env:SystemDrive) { $parents.Add((Join-Path $env:SystemDrive 'Epic Games')) }
    foreach ($parent in @($parents | Select-Object -Unique)) {
        $safeParent = Get-ValidationSafeFullPath -Path $parent -RequireContainer
        if (-not $safeParent) { continue }
        try {
            foreach ($directory in @(Get-ChildItem -LiteralPath $safeParent -Directory `
                        -Filter 'UE_5.6*' -ErrorAction SilentlyContinue)) {
                $candidate = Get-ValidationEngineVersion -CandidateRoot $directory.FullName
                if ($candidate) {
                    $candidate.source = 'standard_install'
                    $candidates.Add($candidate)
                }
            }
        }
        catch { }
    }
    if ($candidates.Count -eq 0) {
        throw [InvalidOperationException]::new('ue56_not_found')
    }
    return @($candidates | Sort-Object `
            @{ Expression = {
                    switch ($_.source) {
                        'launcher_manifest' { 0 }
                        'standard_install' { 1 }
                        default { 2 }
                    }
                }; Ascending = $true },
            @{ Expression = { [version]$_.version }; Descending = $true } |
            Select-Object -First 1)[0]
}

function Invoke-ValidationFixtureBuild {
    param(
        [Parameter(Mandatory)][object]$Installation,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][int]$TimeoutMs,
        [Parameter(Mandatory)][string[]]$SensitiveValues
    )

    foreach ($unsafe in @($Installation.build_tool_path, $ProjectPath)) {
        if ($unsafe.IndexOfAny([char[]]@("`r", "`n", [char]0, '"', '%')) -ge 0) {
            return [pscustomobject][ordered]@{
                success = $false
                classification = 'build_argument_unsafe'
                exit_code = $null
                timed_out = $false
                evidence = $null
            }
        }
    }
    $wrapperPath = Resolve-ValidationArtifactDestination -RunRoot $RunRoot `
        -RelativePath 'raw/build-fixture.cmd'
    $wrapperText = @'
@echo off
chcp 65001 >nul
call "%VIBE_UE_BUILD_TOOL%" MinimalInterfaceEditor Win64 Development "-Project=%VIBE_UE_PROJECT%" -WaitMutex -NoHotReloadFromIDE
exit /b %errorlevel%
'@
    if ([IO.File]::Exists($wrapperPath)) {
        return [pscustomobject][ordered]@{
            success = $false
            classification = 'build_wrapper_exists'
            exit_code = $null
            timed_out = $false
            evidence = $null
        }
    }
    [IO.File]::WriteAllText($wrapperPath, $wrapperText,
        [Text.UTF8Encoding]::new($false))
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = [IO.Path]::GetDirectoryName($ProjectPath)
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.Environment['VIBE_UE_BUILD_TOOL'] = $Installation.build_tool_path
    $startInfo.Environment['VIBE_UE_PROJECT'] = $ProjectPath
    [void]$startInfo.ArgumentList.Add('/d')
    [void]$startInfo.ArgumentList.Add('/s')
    [void]$startInfo.ArgumentList.Add('/c')
    [void]$startInfo.ArgumentList.Add($wrapperPath)

    $process = $null
    $stdout = ''
    $stderr = ''
    $timedOut = $false
    $exitCode = $null
    try {
        $process = [Diagnostics.Process]::Start($startInfo)
        if (-not $process) { throw [InvalidOperationException]::new('build_process_start_failed') }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) {
            $timedOut = $true
            try { $process.Kill($true) } catch { }
            try { [void]$process.WaitForExit(10000) } catch { }
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.HasExited) { $exitCode = [int]$process.ExitCode }
    }
    catch {
        $stderr = 'The isolated fixture build process could not be completed.'
    }
    finally {
        if ($process) { $process.Dispose() }
        if ([IO.File]::Exists($wrapperPath)) {
            try { [IO.File]::Delete($wrapperPath) } catch { }
        }
    }

    $redacted = Protect-ValidationText -Text (($stdout + "`n" + $stderr).Trim() + "`n") `
        -SensitiveValues $SensitiveValues
    $evidence = Write-ValidationTextArtifact -RunRoot $RunRoot `
        -RelativePath 'raw/build.redacted.log' -Text $redacted -Kind redacted_log
    $expectedModule = Join-Path ([IO.Path]::GetDirectoryName($ProjectPath)) `
        'Binaries/Win64/UnrealEditor-MinimalInterface.dll'
    $modulePresent = [IO.File]::Exists($expectedModule)
    return [pscustomobject][ordered]@{
        success = (-not $timedOut -and $exitCode -eq 0 -and $modulePresent)
        classification = if ($timedOut) { 'build_timeout' }
        elseif ($exitCode -ne 0) { 'build_failed' }
        elseif (-not $modulePresent) { 'build_output_missing' }
        else { 'built' }
        exit_code = $exitCode
        timed_out = $timedOut
        evidence = $evidence
    }
}

function New-ValidationContext {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][int]$RepeatCount,
        [string[]]$SensitiveValues = @()
    )

    $ledger = [ordered]@{}
    foreach ($name in $script:CapabilityNames) {
        $ledger[$name] = [Collections.Generic.List[object]]::new()
    }
    return [pscustomobject][ordered]@{
        run_id = $RunId
        run_root = $RunRoot
        repeat_count = $RepeatCount
        sensitive_values = @($SensitiveValues)
        ledger = $ledger
        faults = [Collections.Generic.List[object]]::new()
        evidence_by_path = @{}
        attempt_details = [Collections.Generic.List[object]]::new()
        negative_results = [Collections.Generic.List[object]]::new()
        control_results = [Collections.Generic.List[object]]::new()
        enabled_space_metrics = [Collections.Generic.List[object]]::new()
        cleanup_records = [Collections.Generic.List[object]]::new()
        build = $null
    }
}

function Add-ValidationEvidence {
    param(
        [Parameter(Mandatory)][object]$Context,
        [AllowNull()][object]$Evidence
    )

    foreach ($item in @($Evidence)) {
        if ($null -eq $item -or -not $item.PSObject.Properties['path']) { continue }
        $path = [string]$item.path
        if (-not (Test-ValidationRelativePath -Path $path)) { continue }
        $Context.evidence_by_path[$path] = ConvertTo-ValidationPublicValue -Value $item `
            -SensitiveValues $Context.sensitive_values
    }
}

function Add-ValidationOperationEvidence {
    param(
        [Parameter(Mandatory)][object]$Context,
        [AllowNull()][object]$OperationResult
    )

    if ($OperationResult -and $OperationResult.PSObject.Properties['evidence']) {
        Add-ValidationEvidence -Context $Context -Evidence @($OperationResult.evidence)
    }
}

function ConvertTo-ValidationFaultCode {
    param([AllowNull()][string]$Code)

    $normalized = if ([string]::IsNullOrWhiteSpace($Code)) { 'unknown_fault' }
    else { $Code.ToLowerInvariant() -replace '[^a-z0-9_]', '_' }
    if ($normalized -notmatch '^[a-z]') { $normalized = 'fault_' + $normalized }
    if ($normalized.Length -gt 128) { $normalized = $normalized.Substring(0, 128) }
    return $normalized
}

function Add-ValidationFault {
    param(
        [Parameter(Mandatory)][object]$Context,
        [ValidateSet('observer', 'evidence', 'executor', 'environment', 'capability')]
        [string]$Domain,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [bool]$Retryable = $false,
        [string[]]$AffectedCapabilities = @(),
        [string[]]$Evidence = @()
    )

    $Context.faults.Add([pscustomobject][ordered]@{
            domain = $Domain
            code = ConvertTo-ValidationFaultCode -Code $Code
            message = Protect-ValidationText -Text $Message `
                -SensitiveValues $Context.sensitive_values
            retryable = $Retryable
            affected_capabilities = @($AffectedCapabilities |
                    Where-Object { $_ -in $script:CapabilityNames } | Select-Object -Unique)
            evidence = @($Evidence | Where-Object { Test-ValidationRelativePath -Path $_ } |
                    Select-Object -Unique)
        })
}

function Add-ValidationFaultFromOperation {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$OperationResult,
        [string[]]$AffectedCapabilities = @()
    )

    $fault = if ($OperationResult.PSObject.Properties['fault']) { $OperationResult.fault } else { $null }
    $domain = if ($fault -and $fault.PSObject.Properties['domain'] -and
        [string]$fault.domain -in @('observer', 'evidence', 'executor', 'environment', 'capability')) {
        [string]$fault.domain
    }
    elseif ($OperationResult.PSObject.Properties['environment_fault'] -and
        $OperationResult.environment_fault) { 'environment' }
    elseif ($OperationResult.PSObject.Properties['unsupported'] -and
        $OperationResult.unsupported) { 'capability' }
    else { 'executor' }
    $code = if ($fault -and $fault.PSObject.Properties['code']) { [string]$fault.code }
    else { 'operation_failed' }
    $message = if ($fault -and $fault.PSObject.Properties['message']) { [string]$fault.message }
    else { 'The validation operation did not complete successfully.' }
    $retryable = [bool]($fault -and $fault.PSObject.Properties['retryable'] -and $fault.retryable)
    $evidencePaths = @()
    if ($fault -and $fault.PSObject.Properties['evidence_paths']) {
        $evidencePaths = @($fault.evidence_paths)
    }
    Add-ValidationFault -Context $Context -Domain $domain -Code $code -Message $message `
        -Retryable $retryable -AffectedCapabilities $AffectedCapabilities `
        -Evidence $evidencePaths
}

function Save-ValidationOperationReceipt {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$OperationResult,
        [Parameter(Mandatory)][string]$RelativePath
    )

    try {
        $public = Get-ValidationPublicOperationRecord -OperationResult $OperationResult `
            -SensitiveValues $Context.sensitive_values
        $evidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
            -RelativePath $RelativePath -Value $public -Kind input_receipt
        Add-ValidationEvidence -Context $Context -Evidence $evidence
        Add-ValidationOperationEvidence -Context $Context -OperationResult $OperationResult
        return $evidence
    }
    catch {
        $affected = if ($OperationResult -and
            $OperationResult.PSObject.Properties['operation'] -and
            [string]$OperationResult.operation -in $script:CapabilityNames) {
            @([string]$OperationResult.operation)
        }
        else { $script:CapabilityNames }
        Add-ValidationFault -Context $Context -Domain evidence `
            -Code 'operation_receipt_write_failed' `
            -Message 'A structured operation receipt could not be saved safely.' `
            -AffectedCapabilities $affected
        throw
    }
}

function Invoke-ValidationCaptureWithRetry {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$')]
        [string]$ArtifactId,
        [Parameter(Mandatory)][string]$ReceiptStem,
        [ValidateRange(0, [long]::MaxValue)][long]$DeadlineMonotonicMs = 0,
        [AllowNull()][scriptblock]$CaptureAction
    )

    $invokeCapture = if ($CaptureAction) { $CaptureAction }
    else {
        {
            param($captureSession, $capturePath, $captureArtifactId)
            Save-UnrealClientCapture -Session $captureSession -OutputPath $capturePath `
                -ArtifactId $captureArtifactId
        }
    }
    $attempts = [Collections.Generic.List[object]]::new()
    $receiptPaths = [Collections.Generic.List[string]]::new()
    $completionTimes = [Collections.Generic.List[long]]::new()
    for ($attemptIndex = 1; $attemptIndex -le 2; ++$attemptIndex) {
        if ($attemptIndex -gt 1 -and $DeadlineMonotonicMs -gt 0 -and
            (Get-ValidationMonotonicMs) -ge $DeadlineMonotonicMs) {
            break
        }
        $attemptArtifactId = if ($attemptIndex -eq 1) { $ArtifactId }
        else { $ArtifactId + '-retry' }
        $capture = & $invokeCapture $Session $OutputPath $attemptArtifactId
        $completionTimes.Add([long](Get-ValidationMonotonicMs))
        $attempts.Add($capture)
        $receiptPath = '{0}-{1:d2}.json' -f ([object[]]@($ReceiptStem, $attemptIndex))
        $receipt = Save-ValidationOperationReceipt -Context $Context `
            -OperationResult $capture -RelativePath $receiptPath
        $receiptPaths.Add($receipt.path)
        if ($capture -and $capture.status -eq 'ok') { break }
        if ($DeadlineMonotonicMs -gt 0 -and
            $completionTimes[$completionTimes.Count - 1] -ge $DeadlineMonotonicMs) {
            break
        }

        $retryableEnvironmentFault = $capture -and
            $capture.status -eq 'environment_fault' -and
            $capture.PSObject.Properties['environment_fault'] -and
            $capture.environment_fault -and $capture.PSObject.Properties['fault'] -and
            $capture.fault -and $capture.fault.domain -ceq 'environment' -and
            $capture.fault.PSObject.Properties['retryable'] -and $capture.fault.retryable
        if (-not $retryableEnvironmentFault -or [IO.File]::Exists($OutputPath)) { break }
        $retrySleepMs = 50
        if ($DeadlineMonotonicMs -gt 0) {
            $remainingMs = $DeadlineMonotonicMs - [long](Get-ValidationMonotonicMs)
            if ($remainingMs -le 0) { break }
            $retrySleepMs = [int][Math]::Min([long]$retrySleepMs, $remainingMs)
        }
        if ($retrySleepMs -gt 0) { Start-Sleep -Milliseconds $retrySleepMs }
    }

    return [pscustomobject][ordered]@{
        attempted_count = $attempts.Count
        recovered_after_retry = $attempts.Count -gt 1 -and
            $attempts[$attempts.Count - 1].status -eq 'ok'
        attempts = @($attempts)
        receipt_paths = @($receiptPaths)
        final = $attempts[$attempts.Count - 1]
        final_completed_monotonic_ms = $completionTimes[$completionTimes.Count - 1]
        deadline_monotonic_ms = if ($DeadlineMonotonicMs -gt 0) {
            $DeadlineMonotonicMs
        }
        else { $null }
        deadline_reached = [bool]($DeadlineMonotonicMs -gt 0 -and
            (Get-ValidationMonotonicMs) -ge $DeadlineMonotonicMs)
    }
}

function Get-ValidationFeedbackProbePlan {
    param(
        [ValidateRange(50, 30000)][int]$TimeoutMs = 2000,
        [ValidateRange(1, 1000)][int]$PollIntervalMs = 50
    )

    return [pscustomobject][ordered]@{
        timeout_ms = $TimeoutMs
        poll_interval_ms = $PollIntervalMs
        max_attempts = [Math]::Clamp(
            [int][Math]::Ceiling($TimeoutMs / [double]$PollIntervalMs) + 1,
            2, 40)
    }
}

function Get-ValidationPixelChangeAssessment {
    param([Parameter(Mandatory)][object]$Difference)

    $minimumChangedPixelCount = 16L
    $minimumChangedRatio = 0.0005
    $contractValid = [bool](
        $Difference.PSObject.Properties['changed_pixel_count'] -and
        $Difference.PSObject.Properties['pixel_count'] -and
        [long]$Difference.pixel_count -gt 0)
    $changedPixelCount = if ($Difference.PSObject.Properties['changed_pixel_count']) {
        [long]$Difference.changed_pixel_count
    }
    else { 0L }
    $pixelCount = if ($Difference.PSObject.Properties['pixel_count']) {
        [long]$Difference.pixel_count
    }
    else { 0L }
    $changedRatio = if ($Difference.PSObject.Properties['changed_ratio']) {
        [double]$Difference.changed_ratio
    }
    elseif ($pixelCount -gt 0) { $changedPixelCount / [double]$pixelCount }
    else { 0.0 }
    $ratioPixelCount = [long][Math]::Ceiling(
        $pixelCount * $minimumChangedRatio)
    $requiredChangedPixelCount = [Math]::Max(
        $minimumChangedPixelCount, $ratioPixelCount)
    return [pscustomobject][ordered]@{
        contract_valid = $contractValid
        meaningful = [bool]($contractValid -and $changedPixelCount -ge
            $requiredChangedPixelCount)
        changed_pixel_count = $changedPixelCount
        pixel_count = $pixelCount
        changed_ratio = $changedRatio
        required_changed_pixel_count = [long]$requiredChangedPixelCount
        minimum_changed_pixel_count = $minimumChangedPixelCount
        minimum_changed_ratio = $minimumChangedRatio
    }
}

function New-ValidationLocalCapabilities {
    $local = [ordered]@{}
    foreach ($name in $script:CapabilityNames) {
        $local[$name] = [pscustomobject][ordered]@{
            attempted = $false
            success = $false
            evidence = [Collections.Generic.List[string]]::new()
            limitation = $null
        }
    }
    return $local
}

function Start-ValidationLocalCapability {
    param(
        [Parameter(Mandatory)][object]$Local,
        [Parameter(Mandatory)][string]$Name
    )

    $Local[$Name].attempted = $true
    $Local[$Name].success = $false
}

function Complete-ValidationLocalCapability {
    param(
        [Parameter(Mandatory)][object]$Local,
        [Parameter(Mandatory)][string]$Name,
        [bool]$Success,
        [string[]]$Evidence = @(),
        [AllowNull()][string]$Limitation = $null
    )

    $Local[$Name].attempted = $true
    $Local[$Name].success = $Success
    foreach ($path in $Evidence) {
        if (Test-ValidationRelativePath -Path $path) { $Local[$Name].evidence.Add($path) }
    }
    if ($Limitation) { $Local[$Name].limitation = $Limitation }
}

function Add-ValidationLocalCapabilityEvidence {
    param(
        [Parameter(Mandatory)][object]$Local,
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Evidence = @()
    )

    foreach ($path in $Evidence) {
        if (Test-ValidationRelativePath -Path $path) {
            $Local[$Name].evidence.Add($path)
        }
    }
}

function Set-ValidationLocalCapabilitiesFailedFromFaults {
    param(
        [Parameter(Mandatory)][object]$Local,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Faults
    )

    foreach ($fault in $Faults) {
        if (-not $fault -or
            -not $fault.PSObject.Properties['affected_capabilities']) {
            continue
        }
        foreach ($name in @($fault.affected_capabilities)) {
            if ([string]$name -notin $script:CapabilityNames -or
                -not $Local[[string]$name].attempted) {
                continue
            }
            $Local[[string]$name].success = $false
        }
    }
}

function Get-ValidationReopenAffectedCapabilities {
    param([AllowNull()][object]$OperationResult)

    $terminationReason = if ($OperationResult -and
        $OperationResult.PSObject.Properties['result'] -and
        $OperationResult.result -and
        $OperationResult.result.PSObject.Properties['termination_reason']) {
        [string]$OperationResult.result.termination_reason
    }
    else { $null }
    switch ($terminationReason) {
        'old_session_stop_failed' { return @('Reopen', 'Stop') }
        'new_session_start_failed' { return @('Reopen', 'Start') }
        'process_id_not_renewed_cleanup_failed' { return @('Reopen', 'Stop') }
        default { return @('Reopen') }
    }
}

function Commit-ValidationLocalCapabilities {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Local,
        [Parameter(Mandatory)][int]$AttemptIndex
    )

    foreach ($name in $script:CapabilityNames) {
        if (-not $Local[$name].attempted) { continue }
        $Context.ledger[$name].Add([pscustomobject][ordered]@{
                attempt_index = $AttemptIndex
                success = [bool]$Local[$name].success
                evidence = @($Local[$name].evidence | Select-Object -Unique)
                limitation = $Local[$name].limitation
            })
    }
}

function Commit-ValidationCoreAttemptCapabilities {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Local,
        [Parameter(Mandatory)][int]$AttemptIndex,
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)][int]$FaultCountBefore
    )

    if ($Context.faults.Count -gt $FaultCountBefore) {
        Set-ValidationLocalCapabilitiesFailedFromFaults -Local $Local `
            -Faults @($Context.faults | Select-Object -Skip $FaultCountBefore)
    }
    Commit-ValidationLocalCapabilities -Context $Context -Local $Local `
        -AttemptIndex $AttemptIndex
}

function Get-ValidationWaitSnapshot {
    param([AllowNull()][object]$WaitResult)

    if (-not $WaitResult -or -not $WaitResult.PSObject.Properties['result'] -or
        -not $WaitResult.result -or -not $WaitResult.result.PSObject.Properties['samples']) {
        return $null
    }
    $healthy = @($WaitResult.result.samples | Where-Object {
            $_.read_status -eq 'ok' -and $null -ne $_.snapshot
        })
    if ($healthy.Count -eq 0) { return $null }
    return $healthy[-1].snapshot
}

function Invoke-ValidationHeldAction {
    param(
        [Parameter(Mandatory)][scriptblock]$DownAction,
        [Parameter(Mandatory)][scriptblock]$Body,
        [Parameter(Mandatory)][scriptblock]$UpAction
    )

    $down = & $DownAction
    if (-not $down -or $down.status -ne 'ok') {
        return [pscustomobject][ordered]@{
            success = $false
            down = $down
            body = $null
            body_fault = $null
            release = $null
            release_attempted = $false
        }
    }
    $bodyResult = $null
    $bodyFault = $null
    $release = $null
    try {
        $bodyResult = & $Body
    }
    catch {
        $bodyFault = [pscustomobject][ordered]@{
            domain = 'executor'
            code = 'held_body_failed'
            message = 'The controlled held-input body raised an error.'
            retryable = $false
        }
    }
    finally {
        $release = & $UpAction
    }
    return [pscustomobject][ordered]@{
        success = ($null -eq $bodyFault -and $release -and $release.status -eq 'ok')
        down = $down
        body = $bodyResult
        body_fault = $bodyFault
        release = $release
        release_attempted = $true
    }
}

function Get-ValidationPngPlayerVisibleQuality {
    param([Parameter(Mandatory)][string]$Path)

    $full = Get-ValidationSafeFullPath -Path $Path -RequireLeaf
    if (-not $full) {
        throw [InvalidOperationException]::new('capture_quality_input_invalid')
    }
    Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue
    $bitmap = $null
    try {
        $bitmap = [Drawing.Bitmap]::new($full)
        $imageWidth = [int]$bitmap.Width
        $imageHeight = [int]$bitmap.Height
        $minimumDimension = 32
        $interiorMargin = 0.08
        $left = [Math]::Clamp([int][Math]::Floor($imageWidth * $interiorMargin),
            0, [Math]::Max(0, $imageWidth - 1))
        $top = [Math]::Clamp([int][Math]::Floor($imageHeight * $interiorMargin),
            0, [Math]::Max(0, $imageHeight - 1))
        $right = [Math]::Clamp([int][Math]::Ceiling($imageWidth * (1 - $interiorMargin)),
            [Math]::Min($imageWidth, $left + 1), $imageWidth)
        $bottom = [Math]::Clamp([int][Math]::Ceiling($imageHeight * (1 - $interiorMargin)),
            [Math]::Min($imageHeight, $top + 1), $imageHeight)
        $sampleStep = [Math]::Max(1, [int][Math]::Floor(
                [Math]::Min($imageWidth, $imageHeight) / 80.0))
        $signatureColumns = 8
        $signatureRows = 6
        $signatureCellCount = $signatureColumns * $signatureRows
        [long[]]$signatureRedSums = [long[]]::new($signatureCellCount)
        [long[]]$signatureGreenSums = [long[]]::new($signatureCellCount)
        [long[]]$signatureBlueSums = [long[]]::new($signatureCellCount)
        [int[]]$signatureCounts = [int[]]::new($signatureCellCount)
        $colorBins = [Collections.Generic.HashSet[int]]::new()
        $sampleCount = 0L
        $nonDarkCount = 0L
        $brightCount = 0L
        $colorfulCount = 0L
        $luminanceSum = 0.0
        $luminanceSquaredSum = 0.0
        $minimumLuminance = 255
        $maximumLuminance = 0
        $clickTargetSamples = 0L
        $clickTargetMatches = 0L
        $clickTargetInitialBlueMatches = 0L
        $clickTargetActivatedGreenMatches = 0L
        $dragTargetSamples = 0L
        $dragTargetMatches = 0L
        $backgroundSamples = 0L
        $backgroundMatches = 0L

        for ($pixelY = $top; $pixelY -lt $bottom; $pixelY += $sampleStep) {
            $normalizedY = ($pixelY + 0.5) / [double]$imageHeight
            for ($pixelX = $left; $pixelX -lt $right; $pixelX += $sampleStep) {
                $normalizedX = ($pixelX + 0.5) / [double]$imageWidth
                $color = $bitmap.GetPixel($pixelX, $pixelY)
                $red = [int]$color.R
                $green = [int]$color.G
                $blue = [int]$color.B
                $luminance = [int][Math]::Round(
                    (0.2126 * $red) + (0.7152 * $green) + (0.0722 * $blue))
                $channelMaximum = [Math]::Max($red, [Math]::Max($green, $blue))
                $channelMinimum = [Math]::Min($red, [Math]::Min($green, $blue))
                $channelSpread = $channelMaximum - $channelMinimum
                ++$sampleCount
                $luminanceSum += $luminance
                $luminanceSquaredSum += $luminance * $luminance
                if ($luminance -ge 16) { ++$nonDarkCount }
                if ($luminance -ge 160) { ++$brightCount }
                if ($channelSpread -ge 32 -and $channelMaximum -ge 80) { ++$colorfulCount }
                if ($luminance -lt $minimumLuminance) { $minimumLuminance = $luminance }
                if ($luminance -gt $maximumLuminance) { $maximumLuminance = $luminance }
                $quantizedColor = (([int]($red / 32)) -shl 6) -bor
                    (([int]($green / 32)) -shl 3) -bor ([int]($blue / 32))
                [void]$colorBins.Add($quantizedColor)

                $cellX = [Math]::Clamp([int][Math]::Floor(
                        (($pixelX - $left) * $signatureColumns) /
                        [double]($right - $left)), 0, $signatureColumns - 1)
                $cellY = [Math]::Clamp([int][Math]::Floor(
                        (($pixelY - $top) * $signatureRows) /
                        [double]($bottom - $top)), 0, $signatureRows - 1)
                $cellIndex = ($cellY * $signatureColumns) + $cellX
                $signatureRedSums[$cellIndex] += $red
                $signatureGreenSums[$cellIndex] += $green
                $signatureBlueSums[$cellIndex] += $blue
                ++$signatureCounts[$cellIndex]

                if ($normalizedX -ge 0.71 -and $normalizedX -le 0.89 -and
                    $normalizedY -ge 0.22 -and $normalizedY -le 0.38) {
                    ++$clickTargetSamples
                    $initialBlue = $blue - $red -ge 40 -and
                        $blue - $green -ge 20 -and $green - $red -ge 20 -and
                        $blue -ge 120
                    $activatedGreen = $green - $red -ge 40 -and
                        $green - $blue -ge 30 -and $green -ge 120
                    if ($initialBlue) { ++$clickTargetInitialBlueMatches }
                    if ($activatedGreen) { ++$clickTargetActivatedGreenMatches }
                    if ($initialBlue -or $activatedGreen) {
                        ++$clickTargetMatches
                    }
                }
                if ($normalizedX -ge 0.46 -and $normalizedX -le 0.64 -and
                    $normalizedY -ge 0.42 -and $normalizedY -le 0.58) {
                    ++$dragTargetSamples
                    if ($red - $green -ge 30 -and $blue - $green -ge 15 -and $red -ge 120) {
                        ++$dragTargetMatches
                    }
                }
                if ($normalizedX -ge 0.10 -and $normalizedX -le 0.35 -and
                    $normalizedY -ge 0.25 -and $normalizedY -le 0.58) {
                    ++$backgroundSamples
                    if ($red -ge 8 -and $blue -ge 16 -and
                        $red -le 100 -and $green -le 100 -and $blue -le 100 -and
                        $blue -ge $green -and $green -ge $red) {
                        ++$backgroundMatches
                    }
                }
            }
        }

        $meanLuminance = if ($sampleCount -gt 0) {
            $luminanceSum / [double]$sampleCount
        }
        else { 0.0 }
        $variance = if ($sampleCount -gt 0) {
            [Math]::Max(0.0, ($luminanceSquaredSum / [double]$sampleCount) -
                ($meanLuminance * $meanLuminance))
        }
        else { 0.0 }
        $standardDeviation = [Math]::Sqrt($variance)
        $nonDarkRatio = if ($sampleCount -gt 0) {
            $nonDarkCount / [double]$sampleCount
        }
        else { 0.0 }
        $brightRatio = if ($sampleCount -gt 0) {
            $brightCount / [double]$sampleCount
        }
        else { 0.0 }
        $colorfulRatio = if ($sampleCount -gt 0) {
            $colorfulCount / [double]$sampleCount
        }
        else { 0.0 }
        $clickTargetRatio = if ($clickTargetSamples -gt 0) {
            $clickTargetMatches / [double]$clickTargetSamples
        }
        else { 0.0 }
        $clickTargetInitialBlueRatio = if ($clickTargetSamples -gt 0) {
            $clickTargetInitialBlueMatches / [double]$clickTargetSamples
        }
        else { 0.0 }
        $clickTargetActivatedGreenRatio = if ($clickTargetSamples -gt 0) {
            $clickTargetActivatedGreenMatches / [double]$clickTargetSamples
        }
        else { 0.0 }
        $dragTargetRatio = if ($dragTargetSamples -gt 0) {
            $dragTargetMatches / [double]$dragTargetSamples
        }
        else { 0.0 }
        $backgroundRatio = if ($backgroundSamples -gt 0) {
            $backgroundMatches / [double]$backgroundSamples
        }
        else { 0.0 }

        $visualSignature = [Collections.Generic.List[object]]::new()
        [byte[]]$signatureBytes = [byte[]]::new($signatureCellCount * 3)
        for ($cellIndex = 0; $cellIndex -lt $signatureCellCount; ++$cellIndex) {
            $count = [Math]::Max(1, $signatureCounts[$cellIndex])
            $averageRed = [Math]::Clamp([int][Math]::Round(
                    $signatureRedSums[$cellIndex] / [double]$count), 0, 255)
            $averageGreen = [Math]::Clamp([int][Math]::Round(
                    $signatureGreenSums[$cellIndex] / [double]$count), 0, 255)
            $averageBlue = [Math]::Clamp([int][Math]::Round(
                    $signatureBlueSums[$cellIndex] / [double]$count), 0, 255)
            $signatureBytes[$cellIndex * 3] = [byte]$averageRed
            $signatureBytes[($cellIndex * 3) + 1] = [byte]$averageGreen
            $signatureBytes[($cellIndex * 3) + 2] = [byte]$averageBlue
            $visualSignature.Add([pscustomobject][ordered]@{
                    r = $averageRed
                    g = $averageGreen
                    b = $averageBlue
                })
        }

        $thresholds = [pscustomobject][ordered]@{
            minimum_non_dark_ratio = 0.10
            minimum_bright_ratio = 0.02
            minimum_colorful_ratio = 0.04
            minimum_luminance_range = 80
            minimum_luminance_standard_deviation = 12
            minimum_occupied_color_bins = 5
            minimum_click_target_color_ratio = 0.60
            minimum_drag_target_magenta_ratio = 0.60
            minimum_background_dark_blue_ratio = 0.75
        }
        $dimensionsSufficient = $imageWidth -ge $minimumDimension -and
            $imageHeight -ge $minimumDimension
        $distributionVisible = $nonDarkRatio -ge $thresholds.minimum_non_dark_ratio -and
            $brightRatio -ge $thresholds.minimum_bright_ratio -and
            $colorfulRatio -ge $thresholds.minimum_colorful_ratio -and
            ($maximumLuminance - $minimumLuminance) -ge $thresholds.minimum_luminance_range -and
            $standardDeviation -ge $thresholds.minimum_luminance_standard_deviation -and
            $colorBins.Count -ge $thresholds.minimum_occupied_color_bins
        $fixtureSignatureVisible =
            $clickTargetRatio -ge $thresholds.minimum_click_target_color_ratio -and
            $dragTargetRatio -ge $thresholds.minimum_drag_target_magenta_ratio -and
            $backgroundRatio -ge $thresholds.minimum_background_dark_blue_ratio
        $playerVisible = $dimensionsSufficient -and $distributionVisible -and
            $fixtureSignatureVisible
        $classification = if (-not $dimensionsSufficient) { 'capture_dimensions_too_small' }
        elseif ($backgroundRatio -lt $thresholds.minimum_background_dark_blue_ratio) {
            'fixture_background_not_visible'
        }
        elseif ($clickTargetRatio -lt $thresholds.minimum_click_target_color_ratio) {
            'fixture_click_target_not_visible'
        }
        elseif ($dragTargetRatio -lt $thresholds.minimum_drag_target_magenta_ratio) {
            'fixture_drag_target_not_visible'
        }
        elseif (-not $distributionVisible) { 'fixture_visual_distribution_incomplete' }
        else { 'fixture_player_visible' }

        return [pscustomobject][ordered]@{
            player_visible = [bool]$playerVisible
            classification = $classification
            image_width = $imageWidth
            image_height = $imageHeight
            sample_step = $sampleStep
            sample_count = $sampleCount
            interior_region = [pscustomobject][ordered]@{
                x = $interiorMargin
                y = $interiorMargin
                width = 1 - (2 * $interiorMargin)
                height = 1 - (2 * $interiorMargin)
            }
            mean_luminance = [Math]::Round($meanLuminance, 4)
            luminance_standard_deviation = [Math]::Round($standardDeviation, 4)
            minimum_luminance = $minimumLuminance
            maximum_luminance = $maximumLuminance
            luminance_range = $maximumLuminance - $minimumLuminance
            non_dark_ratio = [Math]::Round($nonDarkRatio, 8)
            bright_ratio = [Math]::Round($brightRatio, 8)
            colorful_ratio = [Math]::Round($colorfulRatio, 8)
            occupied_color_bin_count = $colorBins.Count
            fixture_signature = [pscustomobject][ordered]@{
                click_target_color_ratio = [Math]::Round($clickTargetRatio, 8)
                click_target_initial_blue_ratio =
                    [Math]::Round($clickTargetInitialBlueRatio, 8)
                click_target_activated_green_ratio =
                    [Math]::Round($clickTargetActivatedGreenRatio, 8)
                drag_target_magenta_ratio = [Math]::Round($dragTargetRatio, 8)
                background_dark_blue_ratio = [Math]::Round($backgroundRatio, 8)
            }
            visual_signature_sha256 = Get-ValidationSha256 -Bytes $signatureBytes
            visual_signature = @($visualSignature)
            thresholds = $thresholds
        }
    }
    finally {
        if ($bitmap) { $bitmap.Dispose() }
    }
}

function Get-ValidationVisibleFrameStability {
    param(
        [Parameter(Mandatory)][object]$PreviousQuality,
        [Parameter(Mandatory)][object]$CurrentQuality
    )

    $dimensionsMatch = [int]$PreviousQuality.image_width -eq
        [int]$CurrentQuality.image_width -and
        [int]$PreviousQuality.image_height -eq [int]$CurrentQuality.image_height
    $previousSignature = @($PreviousQuality.visual_signature)
    $currentSignature = @($CurrentQuality.visual_signature)
    $signatureShapeMatch = $previousSignature.Count -eq $currentSignature.Count -and
        $previousSignature.Count -gt 0
    $signatureDeltaSum = 0.0
    $signatureMaximumDelta = 0.0
    if ($signatureShapeMatch) {
        for ($index = 0; $index -lt $previousSignature.Count; ++$index) {
            foreach ($channel in @('r', 'g', 'b')) {
                $delta = [Math]::Abs(
                    [int]$previousSignature[$index].$channel -
                    [int]$currentSignature[$index].$channel)
                $signatureDeltaSum += $delta
                if ($delta -gt $signatureMaximumDelta) { $signatureMaximumDelta = $delta }
            }
        }
    }
    $signatureMeanDelta = if ($signatureShapeMatch) {
        $signatureDeltaSum / [double]($previousSignature.Count * 3)
    }
    else { [double]::PositiveInfinity }
    $meanLuminanceDelta = [Math]::Abs(
        [double]$PreviousQuality.mean_luminance - [double]$CurrentQuality.mean_luminance)
    $standardDeviationDelta = [Math]::Abs(
        [double]$PreviousQuality.luminance_standard_deviation -
        [double]$CurrentQuality.luminance_standard_deviation)
    $clickTargetDelta = [Math]::Abs(
        [double]$PreviousQuality.fixture_signature.click_target_color_ratio -
        [double]$CurrentQuality.fixture_signature.click_target_color_ratio)
    $dragTargetDelta = [Math]::Abs(
        [double]$PreviousQuality.fixture_signature.drag_target_magenta_ratio -
        [double]$CurrentQuality.fixture_signature.drag_target_magenta_ratio)
    $backgroundDelta = [Math]::Abs(
        [double]$PreviousQuality.fixture_signature.background_dark_blue_ratio -
        [double]$CurrentQuality.fixture_signature.background_dark_blue_ratio)
    $thresholds = [pscustomobject][ordered]@{
        maximum_signature_mean_channel_delta = 4.0
        maximum_signature_channel_delta = 24.0
        maximum_mean_luminance_delta = 4.0
        maximum_luminance_standard_deviation_delta = 6.0
        maximum_semantic_region_ratio_delta = 0.05
    }
    $bothVisible = [bool]$PreviousQuality.player_visible -and
        [bool]$CurrentQuality.player_visible
    $stable = $bothVisible -and $dimensionsMatch -and $signatureShapeMatch -and
        $signatureMeanDelta -le $thresholds.maximum_signature_mean_channel_delta -and
        $signatureMaximumDelta -le $thresholds.maximum_signature_channel_delta -and
        $meanLuminanceDelta -le $thresholds.maximum_mean_luminance_delta -and
        $standardDeviationDelta -le
            $thresholds.maximum_luminance_standard_deviation_delta -and
        $clickTargetDelta -le $thresholds.maximum_semantic_region_ratio_delta -and
        $dragTargetDelta -le $thresholds.maximum_semantic_region_ratio_delta -and
        $backgroundDelta -le $thresholds.maximum_semantic_region_ratio_delta
    $classification = if (-not $bothVisible) { 'consecutive_frames_not_player_visible' }
    elseif (-not $dimensionsMatch) { 'visible_frame_dimensions_changed' }
    elseif (-not $signatureShapeMatch) { 'visible_frame_signature_shape_changed' }
    elseif ($stable) { 'visible_frame_stable' }
    else { 'visible_frame_signature_changed' }
    return [pscustomobject][ordered]@{
        stable = [bool]$stable
        classification = $classification
        dimensions_match = [bool]$dimensionsMatch
        signature_shape_match = [bool]$signatureShapeMatch
        signature_mean_channel_delta = if ($signatureShapeMatch) {
            [Math]::Round($signatureMeanDelta, 4)
        }
        else { $null }
        signature_maximum_channel_delta = if ($signatureShapeMatch) {
            [Math]::Round($signatureMaximumDelta, 4)
        }
        else { $null }
        mean_luminance_delta = [Math]::Round($meanLuminanceDelta, 4)
        luminance_standard_deviation_delta = [Math]::Round($standardDeviationDelta, 4)
        click_target_ratio_delta = [Math]::Round($clickTargetDelta, 8)
        drag_target_ratio_delta = [Math]::Round($dragTargetDelta, 8)
        background_ratio_delta = [Math]::Round($backgroundDelta, 8)
        thresholds = $thresholds
    }
}

function Get-ValidationProbePngQuality {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Evidence = @(),
        [string[]]$AffectedCapabilities = @('Capture')
    )

    try {
        return Get-ValidationPngPlayerVisibleQuality -Path $Path
    }
    catch {
        Add-ValidationFault -Context $Context -Domain evidence `
            -Code 'capture_artifact_invalid' `
            -Message 'A captured PNG could not be decoded or inspected safely.' `
            -AffectedCapabilities $AffectedCapabilities -Evidence $Evidence
        throw [IO.InvalidDataException]::new(
            'validation_capture_artifact_invalid', $_.Exception)
    }
}

function Get-ValidationProbePngDifference {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$BeforePath,
        [Parameter(Mandatory)][string]$AfterPath,
        [ValidateRange(0, 1)][double]$X = 0,
        [ValidateRange(0, 1)][double]$Y = 0,
        [ValidateRange(0.0001, 1)][double]$Width = 1,
        [ValidateRange(0.0001, 1)][double]$Height = 0.20,
        [AllowNull()][object]$BeforeQuality,
        [AllowNull()][object]$AfterQuality,
        [string[]]$Evidence = @(),
        [string[]]$AffectedCapabilities = @('Capture')
    )

    try {
        return Get-ValidationPngRegionDifference -BeforePath $BeforePath `
            -AfterPath $AfterPath -X $X -Y $Y -Width $Width -Height $Height `
            -BeforeQuality $BeforeQuality -AfterQuality $AfterQuality
    }
    catch {
        Add-ValidationFault -Context $Context -Domain evidence `
            -Code 'capture_artifact_invalid' `
            -Message 'Captured PNGs could not be compared safely.' `
            -AffectedCapabilities $AffectedCapabilities -Evidence $Evidence
        throw [IO.InvalidDataException]::new(
            'validation_capture_artifact_invalid', $_.Exception)
    }
}

function Invoke-ValidationStableVisibleBaselineProbe {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$EvidencePrefix,
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$ArtifactIdStem,
        [ValidateRange(2, 12)][int]$MaxAttempts = 8,
        [ValidateRange(100, 10000)][int]$TimeoutMs = 5000,
        [ValidateRange(0, 1000)][int]$PollIntervalMs = 50,
        [switch]$RequireInitialFixtureState,
        [ValidateSet('Start', 'Reopen')][string]$Operation = 'Start',
        [AllowNull()][scriptblock]$CaptureAction
    )

    $probeEvidenceRelative = '{0}/probes/visible-baseline.json' -f $EvidencePrefix
    if (-not (Test-ValidationRelativePath -Path $probeEvidenceRelative)) {
        throw [InvalidOperationException]::new('visible_baseline_probe_path_invalid')
    }
    $started = [long](Get-ValidationMonotonicMs)
    $deadline = $started + $TimeoutMs
    $attempts = [Collections.Generic.List[object]]::new()
    $evidencePaths = [Collections.Generic.List[string]]::new()
    $previousVisibleQuality = $null
    $previousVisiblePath = $null
    $acceptedPath = $null
    $acceptedAttemptIndex = $null
    $probeAffectedCapabilities = @($Operation, 'Capture')

    for ($attemptIndex = 1; $attemptIndex -le $MaxAttempts; ++$attemptIndex) {
        if ($attemptIndex -gt 1 -and (Get-ValidationMonotonicMs) -ge $deadline) { break }
        $captureRelative = '{0}/captures/visible-baseline-{1:d2}.png' -f
            $EvidencePrefix, $attemptIndex
        $capturePath = Resolve-ValidationArtifactDestination -RunRoot $Context.run_root `
            -RelativePath $captureRelative
        $captureArguments = @{
            Context = $Context
            Session = $Session
            OutputPath = $capturePath
            ArtifactId = '{0}-{1:d2}' -f $ArtifactIdStem, $attemptIndex
            ReceiptStem = '{0}/receipts/capture-visible-baseline-{1:d2}' -f
                $EvidencePrefix, $attemptIndex
            DeadlineMonotonicMs = $deadline
        }
        if ($CaptureAction) { $captureArguments.CaptureAction = $CaptureAction }
        $captureSequence = Invoke-ValidationCaptureWithRetry @captureArguments
        $capture = $captureSequence.final
        $captureCompleted = [long]$captureSequence.final_completed_monotonic_ms
        $captureCompletedWithinDeadline = $captureCompleted -le $deadline
        Assert-ValidationOperationOk -Context $Context -OperationResult $capture `
            -AffectedCapabilities $probeAffectedCapabilities
        Add-ValidationOperationEvidence -Context $Context -OperationResult $capture
        $evidencePaths.Add($captureRelative)
        foreach ($receiptPath in $captureSequence.receipt_paths) {
            $evidencePaths.Add($receiptPath)
        }
        $processingStartedWithinDeadline = [bool](
            (Get-ValidationMonotonicMs) -le $deadline)
        if (-not $captureCompletedWithinDeadline -or
            -not $processingStartedWithinDeadline) {
            $attempts.Add([pscustomobject][ordered]@{
                    attempt_index = $attemptIndex
                    capture_path = $captureRelative
                    capture_completed_monotonic_ms = $captureCompleted
                    capture_completed_within_deadline = $captureCompletedWithinDeadline
                    processing_started_within_deadline = $processingStartedWithinDeadline
                    analysis_completed_within_deadline = $false
                    capture_attempted_count = [int]$captureSequence.attempted_count
                    capture_recovered_after_retry = [bool]$captureSequence.recovered_after_retry
                    quality = $null
                    fixture_state_accepted = $false
                    stability_from_previous_visible_frame = $null
                    pixel_difference_from_previous_visible_frame = $null
                    pixel_stable_from_previous_visible_frame = $false
                })
            break
        }

        $quality = Get-ValidationProbePngQuality -Context $Context -Path $capturePath `
            -Evidence @($captureRelative) `
            -AffectedCapabilities $probeAffectedCapabilities
        $fixtureStateAccepted = [bool](-not $RequireInitialFixtureState -or
            [double]$quality.fixture_signature.click_target_initial_blue_ratio -ge
            [double]$quality.thresholds.minimum_click_target_color_ratio)
        $stability = if ($captureCompletedWithinDeadline -and
            $quality.player_visible -and $fixtureStateAccepted -and $previousVisibleQuality) {
            Get-ValidationVisibleFrameStability -PreviousQuality $previousVisibleQuality `
                -CurrentQuality $quality
        }
        else { $null }
        $pixelDifference = if ($stability -and $previousVisiblePath) {
            Get-ValidationProbePngDifference -Context $Context `
                -BeforePath $previousVisiblePath `
                -AfterPath $capturePath -X 0 -Y 0 -Width 1 -Height 1 `
                -BeforeQuality $previousVisibleQuality -AfterQuality $quality `
                -Evidence @($evidencePaths) `
                -AffectedCapabilities $probeAffectedCapabilities
        }
        else { $null }
        $pixelStable = [bool]($pixelDifference -and
            $pixelDifference.player_visible_pair -and
            $pixelDifference.changed_pixel_count -eq 0 -and
            $pixelDifference.before_sha256 -ceq $pixelDifference.after_sha256)
        $analysisCompletedWithinDeadline = [bool](
            (Get-ValidationMonotonicMs) -le $deadline)
        $attempts.Add([pscustomobject][ordered]@{
                attempt_index = $attemptIndex
                capture_path = $captureRelative
                capture_completed_monotonic_ms =
                    $captureCompleted
                capture_completed_within_deadline = $captureCompletedWithinDeadline
                processing_started_within_deadline = $processingStartedWithinDeadline
                analysis_completed_within_deadline = $analysisCompletedWithinDeadline
                capture_attempted_count = [int]$captureSequence.attempted_count
                capture_recovered_after_retry = [bool]$captureSequence.recovered_after_retry
                quality = $quality
                fixture_state_accepted = $fixtureStateAccepted
                stability_from_previous_visible_frame = $stability
                pixel_difference_from_previous_visible_frame = $pixelDifference
                pixel_stable_from_previous_visible_frame = $pixelStable
            })
        if ($analysisCompletedWithinDeadline -and $quality.player_visible -and
            $fixtureStateAccepted) {
            if ($stability -and $stability.stable -and $pixelStable) {
                $acceptedPath = $captureRelative
                $acceptedAttemptIndex = $attemptIndex
                break
            }
            $previousVisibleQuality = $quality
            $previousVisiblePath = $capturePath
        }
        else {
            $previousVisibleQuality = $null
            $previousVisiblePath = $null
        }

        $remainingMs = $deadline - [long](Get-ValidationMonotonicMs)
        if (-not $analysisCompletedWithinDeadline -or
            $attemptIndex -ge $MaxAttempts -or $remainingMs -le 0) { break }
        if ($PollIntervalMs -gt 0) {
            $sleepMs = [int][Math]::Min([long]$PollIntervalMs, $remainingMs)
            if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
        }
    }

    $completed = [long](Get-ValidationMonotonicMs)
    $accepted = -not [string]::IsNullOrWhiteSpace($acceptedPath)
    $probeRecord = [pscustomobject][ordered]@{
        schema_version = $script:ValidationSchemaVersion
        accepted = [bool]$accepted
        classification = if ($accepted) { 'stable_player_visible_baseline' }
        elseif ($Operation -ceq 'Reopen') { 'reopen_visible_first_frame_timeout' }
        else { 'visible_first_frame_timeout' }
        operation = $Operation
        required_consecutive_visible_frames = 2
        required_fixture_state = if ($RequireInitialFixtureState) { 'initial' }
        else { 'any' }
        attempted_count = $attempts.Count
        max_attempts = $MaxAttempts
        timeout_ms = $TimeoutMs
        poll_interval_ms = $PollIntervalMs
        started_monotonic_ms = $started
        completed_monotonic_ms = $completed
        deadline_reached = [bool](-not $accepted -and $completed -ge $deadline)
        attempt_limit_reached = [bool](-not $accepted -and
            $attempts.Count -ge $MaxAttempts)
        accepted_attempt_index = $acceptedAttemptIndex
        accepted_path = $acceptedPath
        attempts = @($attempts)
    }
    try {
        $probeEvidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
            -RelativePath $probeEvidenceRelative -Value $probeRecord -Kind report
    }
    catch {
        Add-ValidationFault -Context $Context -Domain evidence `
            -Code 'capture_probe_evidence_write_failed' `
            -Message 'The visible baseline probe record could not be saved safely.' `
            -AffectedCapabilities $probeAffectedCapabilities -Evidence @($evidencePaths)
        throw [IO.IOException]::new(
            'validation_capture_probe_evidence_write_failed', $_.Exception)
    }
    Add-ValidationEvidence -Context $Context -Evidence $probeEvidence
    $evidencePaths.Add($probeEvidence.path)
    $probeRecord | Add-Member -NotePropertyName probe_evidence_path `
        -NotePropertyValue $probeEvidence.path
    $probeRecord | Add-Member -NotePropertyName evidence_paths `
        -NotePropertyValue @($evidencePaths | Select-Object -Unique)
    return $probeRecord
}

function Assert-ValidationStableVisibleBaseline {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Probe,
        [ValidateSet('Start', 'Reopen')][string]$Operation = 'Start'
    )

    if ($Probe.accepted) { return }
    $faultCode = if ($Operation -ceq 'Reopen') {
        'reopen_visible_first_frame_timeout'
    }
    else { 'visible_first_frame_timeout' }
    $message = if ($Operation -ceq 'Reopen') {
        'The reopened target client did not present two consecutive stable fixture-visible frames within the bounded startup probe.'
    }
    else {
        'The target client did not present two consecutive stable fixture-visible frames within the bounded startup probe.'
    }
    Add-ValidationFault -Context $Context -Domain environment `
        -Code $faultCode -Message $message `
        -AffectedCapabilities $(if ($Operation -ceq 'Reopen') {
                @('Reopen', 'Capture')
            }
            else { @('Start', 'Capture') }) -Evidence @($Probe.evidence_paths)
    throw [InvalidOperationException]::new(('validation_' + $faultCode))
}

function Invoke-ValidationPlayerVisibleCaptureProbe {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$EvidencePrefix,
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$ArtifactIdStem,
        [ValidateRange(1, 40)][int]$MaxAttempts = 6,
        [ValidateRange(50, 30000)][int]$TimeoutMs = 2000,
        [ValidateRange(0, 1000)][int]$PollIntervalMs = 50,
        [AllowNull()][string]$BaselinePath,
        [switch]$RequireVisualChange,
        [ValidateRange(0, 1)][double]$X = 0,
        [ValidateRange(0, 1)][double]$Y = 0,
        [ValidateRange(0.0001, 1)][double]$Width = 1,
        [ValidateRange(0.0001, 1)][double]$Height = 0.20,
        [AllowNull()][scriptblock]$CaptureAction
    )

    $probeEvidenceRelative = '{0}/probes/{1}.json' -f $EvidencePrefix, $ArtifactIdStem
    if (-not (Test-ValidationRelativePath -Path $probeEvidenceRelative)) {
        throw [InvalidOperationException]::new('visible_capture_probe_path_invalid')
    }
    $baselineFull = $null
    $baselineQuality = $null
    if ($RequireVisualChange) {
        if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
            throw [InvalidOperationException]::new('visible_capture_baseline_required')
        }
        $baselineFull = Get-ValidationSafeFullPath -Path $BaselinePath -RequireLeaf
        if (-not $baselineFull) {
            throw [InvalidOperationException]::new('visible_capture_baseline_invalid')
        }
        $baselineQuality = Get-ValidationProbePngQuality -Context $Context `
            -Path $baselineFull -Evidence @() -AffectedCapabilities @('Capture')
        if (-not $baselineQuality.player_visible) {
            throw [InvalidOperationException]::new(
                'visible_capture_baseline_not_player_visible')
        }
    }
    $started = [long](Get-ValidationMonotonicMs)
    $deadline = $started + $TimeoutMs
    $attempts = [Collections.Generic.List[object]]::new()
    $evidencePaths = [Collections.Generic.List[string]]::new()
    $acceptedPath = $null
    $acceptedOperation = $null
    $acceptedCompleted = $null
    $acceptedDifference = $null
    $lastVisibleDifference = $null
    $lastVisibleCompleted = $null
    $lastVisiblePath = $null
    for ($attemptIndex = 1; $attemptIndex -le $MaxAttempts; ++$attemptIndex) {
        if ($attemptIndex -gt 1 -and (Get-ValidationMonotonicMs) -ge $deadline) { break }
        $captureRelative = '{0}/captures/{1}-{2:d2}.png' -f
            $EvidencePrefix, $ArtifactIdStem, $attemptIndex
        $capturePath = Resolve-ValidationArtifactDestination -RunRoot $Context.run_root `
            -RelativePath $captureRelative
        $captureArguments = @{
            Context = $Context
            Session = $Session
            OutputPath = $capturePath
            ArtifactId = '{0}-{1:d2}' -f $ArtifactIdStem, $attemptIndex
            ReceiptStem = '{0}/receipts/capture-{1}-{2:d2}' -f
                $EvidencePrefix, $ArtifactIdStem, $attemptIndex
            DeadlineMonotonicMs = $deadline
        }
        if ($CaptureAction) { $captureArguments.CaptureAction = $CaptureAction }
        $captureSequence = Invoke-ValidationCaptureWithRetry @captureArguments
        $capture = $captureSequence.final
        $captureCompleted = [long]$captureSequence.final_completed_monotonic_ms
        $captureCompletedWithinDeadline = $captureCompleted -le $deadline
        Assert-ValidationOperationOk -Context $Context -OperationResult $capture `
            -AffectedCapabilities @('Capture')
        Add-ValidationOperationEvidence -Context $Context -OperationResult $capture
        $evidencePaths.Add($captureRelative)
        foreach ($receiptPath in $captureSequence.receipt_paths) {
            $evidencePaths.Add($receiptPath)
        }
        $processingStartedWithinDeadline = [bool](
            (Get-ValidationMonotonicMs) -le $deadline)
        if (-not $captureCompletedWithinDeadline -or
            -not $processingStartedWithinDeadline) {
            $attempts.Add([pscustomobject][ordered]@{
                    attempt_index = $attemptIndex
                    capture_path = $captureRelative
                    capture_completed_monotonic_ms = $captureCompleted
                    capture_completed_within_deadline = $captureCompletedWithinDeadline
                    processing_started_within_deadline = $processingStartedWithinDeadline
                    analysis_completed_within_deadline = $false
                    capture_attempted_count = [int]$captureSequence.attempted_count
                    capture_recovered_after_retry = [bool]$captureSequence.recovered_after_retry
                    quality = $null
                    difference_from_baseline = $null
                    change_assessment = $null
                    visual_change_observed = $false
                })
            break
        }
        $quality = Get-ValidationProbePngQuality -Context $Context -Path $capturePath `
            -Evidence @($captureRelative) -AffectedCapabilities @('Capture')
        $difference = if ($quality.player_visible -and $RequireVisualChange) {
            Get-ValidationProbePngDifference -Context $Context `
                -BeforePath $baselineFull `
                -AfterPath $capturePath -X $X -Y $Y -Width $Width -Height $Height `
                -BeforeQuality $baselineQuality -AfterQuality $quality `
                -Evidence @($evidencePaths) -AffectedCapabilities @('Capture')
        }
        else { $null }
        $changeAssessment = if ($difference) {
            Get-ValidationPixelChangeAssessment -Difference $difference
        }
        else { $null }
        $visualChangeObserved = [bool]($difference -and
            $difference.player_visible_pair -and $changeAssessment.meaningful -and
            $difference.before_sha256 -cne $difference.after_sha256)
        $analysisCompletedWithinDeadline = [bool](
            (Get-ValidationMonotonicMs) -le $deadline)
        $attempts.Add([pscustomobject][ordered]@{
                attempt_index = $attemptIndex
                capture_path = $captureRelative
                capture_completed_monotonic_ms =
                    $captureCompleted
                capture_completed_within_deadline = $captureCompletedWithinDeadline
                processing_started_within_deadline = $processingStartedWithinDeadline
                analysis_completed_within_deadline = $analysisCompletedWithinDeadline
                capture_attempted_count = [int]$captureSequence.attempted_count
                capture_recovered_after_retry = [bool]$captureSequence.recovered_after_retry
                quality = $quality
                difference_from_baseline = $difference
                change_assessment = $changeAssessment
                visual_change_observed = $visualChangeObserved
            })
        if ($analysisCompletedWithinDeadline -and $quality.player_visible) {
            if ($difference -and $difference.player_visible_pair) {
                $lastVisibleDifference = $difference
                $lastVisibleCompleted = $captureCompleted
                $lastVisiblePath = $captureRelative
            }
            if (-not $RequireVisualChange -or $visualChangeObserved) {
                $acceptedPath = $captureRelative
                $acceptedOperation = $capture
                $acceptedCompleted = $captureCompleted
                $acceptedDifference = $difference
                break
            }
        }
        $remainingMs = $deadline - [long](Get-ValidationMonotonicMs)
        if (-not $analysisCompletedWithinDeadline -or
            $attemptIndex -ge $MaxAttempts -or $remainingMs -le 0) { break }
        if ($PollIntervalMs -gt 0) {
            $sleepMs = [int][Math]::Min([long]$PollIntervalMs, $remainingMs)
            if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
        }
    }
    $completed = [long](Get-ValidationMonotonicMs)
    $accepted = -not [string]::IsNullOrWhiteSpace($acceptedPath)
    $probeRecord = [pscustomobject][ordered]@{
        schema_version = $script:ValidationSchemaVersion
        accepted = [bool]$accepted
        classification = if ($accepted -and $RequireVisualChange) {
            'player_visible_changed_capture'
        }
        elseif ($accepted) { 'player_visible_capture' }
        elseif ($RequireVisualChange -and $lastVisibleDifference) {
            'visible_capture_change_timeout'
        }
        else { 'visible_capture_timeout' }
        require_visual_change = [bool]$RequireVisualChange
        comparison_region = if ($RequireVisualChange) {
            [pscustomobject][ordered]@{
                x = $X
                y = $Y
                width = $Width
                height = $Height
            }
        }
        else { $null }
        attempted_count = $attempts.Count
        max_attempts = $MaxAttempts
        timeout_ms = $TimeoutMs
        poll_interval_ms = $PollIntervalMs
        started_monotonic_ms = $started
        completed_monotonic_ms = $completed
        deadline_reached = [bool](-not $accepted -and $completed -ge $deadline)
        attempt_limit_reached = [bool](-not $accepted -and
            $attempts.Count -ge $MaxAttempts)
        accepted_path = $acceptedPath
        attempts = @($attempts)
    }
    try {
        $probeEvidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
            -RelativePath $probeEvidenceRelative -Value $probeRecord -Kind report
    }
    catch {
        Add-ValidationFault -Context $Context -Domain evidence `
            -Code 'capture_probe_evidence_write_failed' `
            -Message 'The player-visible capture probe record could not be saved safely.' `
            -AffectedCapabilities @('Capture') -Evidence @($evidencePaths)
        throw [IO.IOException]::new(
            'validation_capture_probe_evidence_write_failed', $_.Exception)
    }
    Add-ValidationEvidence -Context $Context -Evidence $probeEvidence
    $evidencePaths.Add($probeEvidence.path)
    $probeRecord | Add-Member -NotePropertyName accepted_operation `
        -NotePropertyValue $acceptedOperation
    $probeRecord | Add-Member -NotePropertyName accepted_completed_monotonic_ms `
        -NotePropertyValue $acceptedCompleted
    $probeRecord | Add-Member -NotePropertyName accepted_difference `
        -NotePropertyValue $acceptedDifference
    $probeRecord | Add-Member -NotePropertyName last_visible_difference `
        -NotePropertyValue $lastVisibleDifference
    $probeRecord | Add-Member -NotePropertyName last_visible_completed_monotonic_ms `
        -NotePropertyValue $lastVisibleCompleted
    $probeRecord | Add-Member -NotePropertyName last_visible_path `
        -NotePropertyValue $lastVisiblePath
    $probeRecord | Add-Member -NotePropertyName probe_evidence_path `
        -NotePropertyValue $probeEvidence.path
    $probeRecord | Add-Member -NotePropertyName evidence_paths `
        -NotePropertyValue @($evidencePaths | Select-Object -Unique)
    return $probeRecord
}

function Get-ValidationPngRegionDifference {
    param(
        [Parameter(Mandatory)][string]$BeforePath,
        [Parameter(Mandatory)][string]$AfterPath,
        [ValidateRange(0, 1)][double]$X = 0,
        [ValidateRange(0, 1)][double]$Y = 0,
        [ValidateRange(0.0001, 1)][double]$Width = 1,
        [ValidateRange(0.0001, 1)][double]$Height = 0.20,
        [AllowNull()][object]$BeforeQuality,
        [AllowNull()][object]$AfterQuality
    )

    $beforeFull = Get-ValidationSafeFullPath -Path $BeforePath -RequireLeaf
    $afterFull = Get-ValidationSafeFullPath -Path $AfterPath -RequireLeaf
    if (-not $beforeFull -or -not $afterFull) {
        throw [InvalidOperationException]::new('capture_comparison_input_invalid')
    }
    $beforeQuality = if ($BeforeQuality) { $BeforeQuality }
    else { Get-ValidationPngPlayerVisibleQuality -Path $beforeFull }
    $afterQuality = if ($AfterQuality) { $AfterQuality }
    else { Get-ValidationPngPlayerVisibleQuality -Path $afterFull }
    Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue
    $before = $null
    $after = $null
    try {
        $before = [Drawing.Bitmap]::new($beforeFull)
        $after = [Drawing.Bitmap]::new($afterFull)
        if ($before.Width -ne $after.Width -or $before.Height -ne $after.Height) {
            throw [InvalidOperationException]::new('capture_dimensions_mismatch')
        }
        $left = [Math]::Clamp([int][Math]::Floor($X * $before.Width), 0, $before.Width - 1)
        $top = [Math]::Clamp([int][Math]::Floor($Y * $before.Height), 0, $before.Height - 1)
        $right = [Math]::Clamp([int][Math]::Ceiling(($X + $Width) * $before.Width),
            $left + 1, $before.Width)
        $bottom = [Math]::Clamp([int][Math]::Ceiling(($Y + $Height) * $before.Height),
            $top + 1, $before.Height)
        $regionWidth = $right - $left
        $regionHeight = $bottom - $top
        $pixelCount = $regionWidth * $regionHeight
        $rectangle = [Drawing.Rectangle]::new($left, $top, $regionWidth, $regionHeight)
        $pixelFormat = [Drawing.Imaging.PixelFormat]::Format32bppArgb
        $beforeData = $null
        $afterData = $null
        try {
            $beforeData = $before.LockBits($rectangle,
                [Drawing.Imaging.ImageLockMode]::ReadOnly, $pixelFormat)
            $afterData = $after.LockBits($rectangle,
                [Drawing.Imaging.ImageLockMode]::ReadOnly, $pixelFormat)
            $rowByteLength = $regionWidth * 4
            [byte[]]$beforeBytes = [byte[]]::new($pixelCount * 4)
            [byte[]]$afterBytes = [byte[]]::new($pixelCount * 4)
            for ($row = 0; $row -lt $regionHeight; ++$row) {
                [Runtime.InteropServices.Marshal]::Copy(
                    [IntPtr]::Add($beforeData.Scan0, $row * $beforeData.Stride),
                    $beforeBytes, $row * $rowByteLength, $rowByteLength)
                [Runtime.InteropServices.Marshal]::Copy(
                    [IntPtr]::Add($afterData.Scan0, $row * $afterData.Stride),
                    $afterBytes, $row * $rowByteLength, $rowByteLength)
            }
        }
        finally {
            if ($beforeData) { $before.UnlockBits($beforeData) }
            if ($afterData) { $after.UnlockBits($afterData) }
        }
        [int[]]$beforePixels = [int[]]::new($pixelCount)
        [int[]]$afterPixels = [int[]]::new($pixelCount)
        [Buffer]::BlockCopy($beforeBytes, 0, $beforePixels, 0, $beforeBytes.Length)
        [Buffer]::BlockCopy($afterBytes, 0, $afterPixels, 0, $afterBytes.Length)
        $changed = 0L
        for ($pixelIndex = 0; $pixelIndex -lt $pixelCount; ++$pixelIndex) {
            if ($beforePixels[$pixelIndex] -ne $afterPixels[$pixelIndex]) { ++$changed }
        }
        return [pscustomobject][ordered]@{
            before_sha256 = Get-ValidationSha256 -Bytes $beforeBytes
            after_sha256 = Get-ValidationSha256 -Bytes $afterBytes
            player_visible_pair = [bool]($beforeQuality.player_visible -and
                $afterQuality.player_visible)
            before_quality = $beforeQuality
            after_quality = $afterQuality
            changed_pixel_count = [long]$changed
            pixel_count = [long]$pixelCount
            changed_ratio = [Math]::Round($changed / [double]$pixelCount, 8)
            region = [pscustomobject][ordered]@{
                x = $X
                y = $Y
                width = $Width
                height = $Height
            }
            image_width = [int]$before.Width
            image_height = [int]$before.Height
        }
    }
    finally {
        if ($before) { $before.Dispose() }
        if ($after) { $after.Dispose() }
    }
}

function Test-ValidationInitialSnapshot {
    param([Parameter(Mandatory)][object]$Snapshot)

    return $Snapshot.ready -eq $true -and $Snapshot.first_frame -eq $true -and
        [string]$Snapshot.scene -ceq 'minimal_interface' -and
        [string]$Snapshot.object.object_id -ceq 'movable_object' -and
        [Math]::Abs([double]$Snapshot.object.normalized_position.x - 0.18) -le 0.001 -and
        [int]$Snapshot.keyboard.discrete_count -eq 0 -and
        [int]$Snapshot.keyboard.hold_count -eq 0 -and
        $Snapshot.keyboard.w_down -eq $false -and
        [int]$Snapshot.pointer.click_count -eq 0 -and
        [int]$Snapshot.pointer.drag_count -eq 0 -and
        $Snapshot.pointer.left_down -eq $false
}

function Assert-ValidationOperationOk {
    param(
        [Parameter(Mandatory)][object]$Context,
        [AllowNull()][object]$OperationResult,
        [Parameter(Mandatory)][string[]]$AffectedCapabilities
    )

    if ($OperationResult -and $OperationResult.status -eq 'ok') { return }
    if ($OperationResult) {
        Add-ValidationFaultFromOperation -Context $Context -OperationResult $OperationResult `
            -AffectedCapabilities $AffectedCapabilities
    }
    else {
        Add-ValidationFault -Context $Context -Domain executor -Code 'operation_result_missing' `
            -Message 'A validation operation returned no structured result.' `
            -AffectedCapabilities $AffectedCapabilities
    }
    throw [InvalidOperationException]::new('validation_core_stage_failed')
}

function Resolve-ValidationCoreAttemptFault {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Stage,
        [ValidateRange(0, [int]::MaxValue)][int]$FaultCountBefore
    )

    if ($Context.faults.Count -eq $FaultCountBefore) {
        $faultDomain = if ($Stage -in @('ReadState', 'FindVisibleTarget', 'WaitUntil')) {
            'observer'
        }
        elseif ($Stage -eq 'Capture') { 'evidence' }
        elseif ($Stage -eq 'Start') { 'environment' }
        else { 'executor' }
        Add-ValidationFault -Context $Context -Domain $faultDomain `
            -Code 'core_attempt_incomplete' `
            -Message 'A core validation attempt ended outside a structured operation result.' `
            -AffectedCapabilities $(if ($Stage -in $script:CapabilityNames) {
                    @($Stage)
                }
                else { $script:CapabilityNames })
    }
    $terminalFault = $Context.faults[$Context.faults.Count - 1]
    return [pscustomobject][ordered]@{
        stage = $Stage
        domain = [string]$terminalFault.domain
        classification = [string]$terminalFault.code
    }
}

function Get-ValidationObserverControlComparison {
    param(
        [Parameter(Mandatory)][int]$AttemptIndex,
        [Parameter(Mandatory)][long]$FeedbackLatencyMs,
        [Parameter(Mandatory)][int]$FeedbackLatencyDeltaBoundaryMs,
        [Parameter(Mandatory)][object]$Difference,
        [AllowNull()][object]$EnabledMetric,
        [Parameter(Mandatory)][bool]$ObserverStateFileAbsent
    )

    $mechanicallyComparable = $false
    $changeScale = $null
    $enabledFeedbackLatencyMs = $null
    $feedbackLatencyRatio = $null
    $feedbackLatencyDeltaMs = $null
    $latencyComparable = $false
    $differenceFramesVisible = [bool](
        $Difference.PSObject.Properties['player_visible_pair'] -and
        $Difference.player_visible_pair)
    $enabledFramesVisible = [bool]($EnabledMetric -and
        $EnabledMetric.PSObject.Properties['hud_difference'] -and
        $EnabledMetric.hud_difference -and
        $EnabledMetric.hud_difference.PSObject.Properties['player_visible_pair'] -and
        $EnabledMetric.hud_difference.player_visible_pair)
    $differenceChangeAssessment = Get-ValidationPixelChangeAssessment `
        -Difference $Difference
    $enabledChangeAssessment = if ($EnabledMetric -and
        $EnabledMetric.PSObject.Properties['hud_difference'] -and
        $EnabledMetric.hud_difference) {
        Get-ValidationPixelChangeAssessment -Difference $EnabledMetric.hud_difference
    }
    else { $null }
    if ($EnabledMetric -and
        $differenceFramesVisible -and $enabledFramesVisible -and
        $differenceChangeAssessment.meaningful -and
        $enabledChangeAssessment -and $enabledChangeAssessment.meaningful) {
        $enabledFeedbackLatencyMs = [long]$EnabledMetric.feedback_latency_ms
        $changeScale = [long]$Difference.changed_pixel_count /
            [double][long]$EnabledMetric.hud_difference.changed_pixel_count
        $mechanicallyComparable = $changeScale -ge 0.25 -and $changeScale -le 4.0 -and
            [int]$Difference.image_width -eq [int]$EnabledMetric.hud_difference.image_width -and
            [int]$Difference.image_height -eq [int]$EnabledMetric.hud_difference.image_height
        if ($enabledFeedbackLatencyMs -ge 1) {
            $feedbackLatencyRatio = $FeedbackLatencyMs / [double]$enabledFeedbackLatencyMs
            $feedbackLatencyDeltaMs = [Math]::Abs(
                $FeedbackLatencyMs - $enabledFeedbackLatencyMs)
            $latencyComparable = $feedbackLatencyDeltaMs -le $FeedbackLatencyDeltaBoundaryMs -and
                $feedbackLatencyRatio -ge 0.25 -and $feedbackLatencyRatio -le 4.0
        }
    }

    $passed = $differenceFramesVisible -and $enabledFramesVisible -and
        $differenceChangeAssessment.meaningful -and $enabledChangeAssessment -and
        $enabledChangeAssessment.meaningful -and
        $latencyComparable -and $mechanicallyComparable -and $ObserverStateFileAbsent
    $classification = if ($passed) { 'observer_non_interference_confirmed' }
    elseif (-not $differenceFramesVisible -or -not $enabledFramesVisible) {
        'control_feedback_frame_not_player_visible'
    }
    elseif (-not $differenceChangeAssessment.meaningful) {
        'control_hud_change_not_observed'
    }
    elseif (-not $enabledChangeAssessment -or -not $enabledChangeAssessment.meaningful) {
        'control_pixel_change_materially_different'
    }
    elseif (-not $latencyComparable) { 'control_feedback_latency_materially_different' }
    elseif (-not $mechanicallyComparable) { 'control_pixel_change_materially_different' }
    else { 'control_published_state_unexpectedly' }
    return [pscustomobject][ordered]@{
        passed = [bool]$passed
        classification = $classification
        metric = [pscustomobject][ordered]@{
            attempt_index = $AttemptIndex
            feedback_latency_ms = $FeedbackLatencyMs
            enabled_feedback_latency_ms = $enabledFeedbackLatencyMs
            feedback_latency_delta_ms = $feedbackLatencyDeltaMs
            feedback_latency_ratio = $feedbackLatencyRatio
            feedback_latency_delta_boundary_ms = $FeedbackLatencyDeltaBoundaryMs
            latency_comparable = $latencyComparable
            observer_disabled_frames_player_visible = $differenceFramesVisible
            observer_enabled_frames_player_visible = $enabledFramesVisible
            hud_difference = $Difference
            hud_change_assessment = $differenceChangeAssessment
            enabled_hud_change_assessment = $enabledChangeAssessment
            enabled_change_scale = $changeScale
            mechanically_comparable = $mechanicallyComparable
            observer_state_file_absent = $ObserverStateFileAbsent
        }
    }
}

function Test-ValidationObserverControlCapabilityFailure {
    param([Parameter(Mandatory)][string]$Classification)

    return $Classification -in @(
        'control_hud_change_not_observed',
        'control_feedback_latency_materially_different',
        'control_pixel_change_materially_different',
        'control_published_state_unexpectedly')
}

function Save-ValidationSnapshot {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][string]$RelativePath,
        [string[]]$AffectedCapabilities = @('ReadState')
    )

    try {
        $public = ConvertTo-ValidationPublicValue -Value $Snapshot `
            -SensitiveValues $Context.sensitive_values
        $evidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
            -RelativePath $RelativePath -Value $public -Kind state
        Add-ValidationEvidence -Context $Context -Evidence $evidence
        return $evidence
    }
    catch {
        Add-ValidationFault -Context $Context -Domain evidence `
            -Code 'state_evidence_write_failed' `
            -Message 'A redacted state evidence artifact could not be saved safely.' `
            -AffectedCapabilities $AffectedCapabilities
        throw
    }
}

function Invoke-ValidationCoreAttempt {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][int]$AttemptIndex,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][object]$EngineReference,
        [Parameter(Mandatory)][int]$StartTimeoutMs,
        [Parameter(Mandatory)][int]$StopTimeoutMs,
        [Parameter(Mandatory)][int]$ObserverMaxAgeMs
    )

    $attemptName = 'attempt-{0:d2}' -f $AttemptIndex
    $prefix = 'raw/{0}' -f $attemptName
    $stateRelative = '{0}/state/live.json' -f $prefix
    $statePath = Resolve-ValidationArtifactDestination -RunRoot $Context.run_root `
        -RelativePath $stateRelative
    $processToken = 'process-' + [guid]::NewGuid().ToString('N')
    $local = New-ValidationLocalCapabilities
    $session = $null
    $sessionActive = $false
    $stage = 'Start'
    $attemptFault = $null
    $allWaits = $false
    $captureEvidence = [Collections.Generic.List[string]]::new()
    $faultCountBefore = $Context.faults.Count

    try {
        Start-ValidationLocalCapability -Local $local -Name Start
        $start = Start-UnrealEvaluationSession -ProjectPath $ProjectPath `
            -RunRoot $Context.run_root -StatePath $statePath -ProcessToken $processToken `
            -EngineReference $EngineReference -WindowWidth 960 -WindowHeight 640 `
            -TimeoutMs $StartTimeoutMs -FocusTimeoutMs 1500
        $startReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $start `
            -RelativePath ('{0}/receipts/start.json' -f $prefix)
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Start `
            -Evidence @($startReceipt.path)
        Assert-ValidationOperationOk -Context $Context -OperationResult $start `
            -AffectedCapabilities @('Start')
        $session = $start.result.session
        $sessionActive = $true

        $stage = 'ReadState'
        Start-ValidationLocalCapability -Local $local -Name ReadState
        $initialRead = Read-UnrealEvaluationState -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs
        Assert-ValidationOperationOk -Context $Context -OperationResult $initialRead `
            -AffectedCapabilities @('ReadState', 'Start')
        if (-not (Test-ValidationInitialSnapshot -Snapshot $initialRead.result.snapshot)) {
            Add-ValidationFault -Context $Context -Domain observer `
                -Code 'initial_state_not_deterministic' `
                -Message 'The first-frame snapshot did not contain the deterministic fixture initial state.' `
                -AffectedCapabilities @('Start', 'ReadState')
            throw [InvalidOperationException]::new('validation_initial_state_invalid')
        }
        $initialStateEvidence = Save-ValidationSnapshot -Context $Context `
            -Snapshot $initialRead.result.snapshot `
            -RelativePath ('{0}/states/initial.json' -f $prefix) `
            -AffectedCapabilities @('Start', 'ReadState')
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Start `
            -Evidence @($initialStateEvidence.path)
        Complete-ValidationLocalCapability -Local $local -Name ReadState -Success $true `
            -Evidence @($initialStateEvidence.path)

        $stage = 'Capture'
        Start-ValidationLocalCapability -Local $local -Name Capture
        $initialBaselineProbe = Invoke-ValidationStableVisibleBaselineProbe `
            -Context $Context -Session $session -EvidencePrefix $prefix `
            -ArtifactIdStem ('initial-baseline-{0:d2}' -f $AttemptIndex) `
            -RequireInitialFixtureState
        foreach ($evidencePath in $initialBaselineProbe.evidence_paths) {
            $captureEvidence.Add($evidencePath)
        }
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Start `
            -Evidence @($initialBaselineProbe.evidence_paths)
        Assert-ValidationStableVisibleBaseline -Context $Context -Probe $initialBaselineProbe
        $initialCaptureRelative = [string]$initialBaselineProbe.accepted_path
        $initialCapturePath = Get-ValidationSafeFullPath -Path (Join-Path $Context.run_root `
                ($initialCaptureRelative.Replace('/', [IO.Path]::DirectorySeparatorChar))) `
            -RequireLeaf
        if (-not $initialCapturePath -or
            -not (Test-ValidationPathWithinRoot -Root $Context.run_root `
                -Path $initialCapturePath)) {
            throw [InvalidOperationException]::new('visible_baseline_artifact_invalid')
        }
        Complete-ValidationLocalCapability -Local $local -Name Start -Success $true `
            -Evidence (@($startReceipt.path, $initialStateEvidence.path) +
                @($initialBaselineProbe.evidence_paths))

        $stage = 'PressKey'
        Start-ValidationLocalCapability -Local $local -Name PressKey
        Start-ValidationLocalCapability -Local $local -Name WaitUntil
        $baseline = $initialRead.result.snapshot
        $pressStarted = Get-ValidationMonotonicMs
        $press = Invoke-UnrealPressKey -Session $session -Key Space -DurationMs 40
        $pressReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $press `
            -RelativePath ('{0}/receipts/press-space.json' -f $prefix)
        Assert-ValidationOperationOk -Context $Context -OperationResult $press `
            -AffectedCapabilities @('PressKey')
        $expectedDiscrete = [int]$baseline.keyboard.discrete_count + 1
        $minimumHud = [int]$baseline.hud.revision
        $spaceWaitPath = '{0}/waits/space-feedback.json' -f $prefix
        $spaceWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$baseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $spaceWaitPath `
            -Predicate {
                param($snapshot)
                return [int]$snapshot.keyboard.discrete_count -eq $expectedDiscrete -and
                    [int]$snapshot.hud.revision -gt $minimumHud
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $spaceWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $spaceWait `
            -AffectedCapabilities @('PressKey', 'WaitUntil')
        $spaceSnapshot = Get-ValidationWaitSnapshot -WaitResult $spaceWait
        if (-not $spaceSnapshot) {
            throw [InvalidOperationException]::new('validation_wait_snapshot_missing')
        }
        $spaceStateEvidence = Save-ValidationSnapshot -Context $Context -Snapshot $spaceSnapshot `
            -RelativePath ('{0}/states/after-space.json' -f $prefix)
        $feedbackProbePlan = Get-ValidationFeedbackProbePlan
        $spaceCaptureProbe = Invoke-ValidationPlayerVisibleCaptureProbe `
            -Context $Context -Session $session -EvidencePrefix $prefix `
            -ArtifactIdStem ('after-space-{0:d2}' -f $AttemptIndex) `
            -MaxAttempts $feedbackProbePlan.max_attempts `
            -TimeoutMs $feedbackProbePlan.timeout_ms `
            -PollIntervalMs $feedbackProbePlan.poll_interval_ms `
            -BaselinePath $initialCapturePath -RequireVisualChange `
            -X 0 -Y 0 -Width 1 -Height 0.20
        foreach ($evidencePath in $spaceCaptureProbe.evidence_paths) {
            $captureEvidence.Add($evidencePath)
        }
        if (-not $spaceCaptureProbe.accepted) {
            $feedbackFaultDomain = if ($spaceCaptureProbe.last_visible_difference) {
                'evidence'
            }
            else { 'environment' }
            $feedbackFaultCode = if ($spaceCaptureProbe.last_visible_difference) {
                'hud_feedback_not_visible'
            }
            else { 'visible_feedback_frame_timeout' }
            Add-ValidationFault -Context $Context -Domain $feedbackFaultDomain `
                -Code $feedbackFaultCode `
                -Message 'The observer-enabled client did not present a player-visible changed HUD frame within the bounded capture probe.' `
                -AffectedCapabilities @('PressKey', 'Capture') `
                -Evidence @($spaceCaptureProbe.evidence_paths)
            throw [InvalidOperationException]::new('validation_visible_feedback_frame_timeout')
        }
        $spaceCaptureRelative = [string]$spaceCaptureProbe.accepted_path
        $spaceCapturePath = Get-ValidationSafeFullPath -Path (Join-Path $Context.run_root `
                ($spaceCaptureRelative.Replace('/', [IO.Path]::DirectorySeparatorChar))) `
            -RequireLeaf
        if (-not $spaceCapturePath -or
            -not (Test-ValidationPathWithinRoot -Root $Context.run_root -Path $spaceCapturePath)) {
            throw [InvalidOperationException]::new('visible_feedback_artifact_invalid')
        }
        $spaceCaptureCompleted = [long]$spaceCaptureProbe.accepted_completed_monotonic_ms
        $hudDiff = $spaceCaptureProbe.accepted_difference
        if (-not $hudDiff.player_visible_pair -or $hudDiff.changed_pixel_count -le 0 -or
            $hudDiff.before_sha256 -ceq $hudDiff.after_sha256) {
            $hudFaultDomain = if ($hudDiff.player_visible_pair) { 'evidence' }
            else { 'environment' }
            $hudFaultCode = if ($hudDiff.player_visible_pair) { 'hud_feedback_not_visible' }
            else { 'hud_feedback_frame_not_player_visible' }
            Add-ValidationFault -Context $Context -Domain $hudFaultDomain -Code $hudFaultCode `
                -Message 'The fixed HUD capture pair was not both player-visible with a changed Space feedback region.' `
                -AffectedCapabilities @('PressKey', 'Capture') `
                -Evidence @($initialCaptureRelative, $spaceCaptureRelative)
            throw [InvalidOperationException]::new('validation_hud_feedback_missing')
        }
        $pressLatency = $spaceCaptureCompleted - $pressStarted
        $Context.enabled_space_metrics.Add([pscustomobject][ordered]@{
                attempt_index = $AttemptIndex
                feedback_latency_ms = [long]$pressLatency
                hud_difference = $hudDiff
                evidence = @($initialCaptureRelative, $spaceCaptureRelative, $spaceWaitPath)
            })
        Complete-ValidationLocalCapability -Local $local -Name Capture -Success $true `
            -Evidence @($captureEvidence)
        Complete-ValidationLocalCapability -Local $local -Name PressKey -Success $true `
            -Evidence @($pressReceipt.path, $spaceStateEvidence.path, $spaceWaitPath,
                $initialCaptureRelative, $spaceCaptureRelative)

        $stage = 'HoldRelease'
        Start-ValidationLocalCapability -Local $local -Name HoldKey
        Start-ValidationLocalCapability -Local $local -Name ReleaseKey
        $holdBaseline = $spaceSnapshot
        $hold = Invoke-ValidationHeldAction `
            -DownAction { Start-UnrealKeyHold -Session $session -Key W } `
            -Body {
                $firstHoldPath = '{0}/waits/hold-motion-1.json' -f $prefix
                $firstHold = Wait-UnrealEvaluationCondition -StatePath $statePath `
                    -ExpectedProcessToken $processToken `
                    -ExpectedProcessId ([int]$start.result.process_id) `
                    -ExpectedRoundId ([string]$holdBaseline.round_id) `
                    -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
                    -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
                    -EvidenceRoot $Context.run_root -EvidencePath $firstHoldPath `
                    -Predicate {
                        param($snapshot)
                        return $snapshot.keyboard.w_down -eq $true -and
                            [int]$snapshot.keyboard.hold_count -gt [int]$holdBaseline.keyboard.hold_count -and
                            [double]$snapshot.object.normalized_position.x -gt `
                                ([double]$holdBaseline.object.normalized_position.x + 0.005)
                    }
                Add-ValidationOperationEvidence -Context $Context -OperationResult $firstHold
                Assert-ValidationOperationOk -Context $Context -OperationResult $firstHold `
                    -AffectedCapabilities @('HoldKey', 'WaitUntil')
                $firstSnapshot = Get-ValidationWaitSnapshot -WaitResult $firstHold
                $secondHoldPath = '{0}/waits/hold-motion-2.json' -f $prefix
                $secondHold = Wait-UnrealEvaluationCondition -StatePath $statePath `
                    -ExpectedProcessToken $processToken `
                    -ExpectedProcessId ([int]$start.result.process_id) `
                    -ExpectedRoundId ([string]$holdBaseline.round_id) `
                    -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
                    -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
                    -EvidenceRoot $Context.run_root -EvidencePath $secondHoldPath `
                    -Predicate {
                        param($snapshot)
                        return $snapshot.keyboard.w_down -eq $true -and
                            [long]$snapshot.snapshot_id -gt [long]$firstSnapshot.snapshot_id -and
                            [int]$snapshot.keyboard.hold_count -gt [int]$firstSnapshot.keyboard.hold_count -and
                            [double]$snapshot.object.normalized_position.x -gt `
                                ([double]$firstSnapshot.object.normalized_position.x + 0.005)
                    }
                Add-ValidationOperationEvidence -Context $Context -OperationResult $secondHold
                Assert-ValidationOperationOk -Context $Context -OperationResult $secondHold `
                    -AffectedCapabilities @('HoldKey', 'WaitUntil')
                return [pscustomobject]@{
                    first = $firstHold
                    second = $secondHold
                    first_path = $firstHoldPath
                    second_path = $secondHoldPath
                }
            } `
            -UpAction { Stop-UnrealKeyHold -Session $session -Key W -Cleanup }
        $holdDownReceipt = Save-ValidationOperationReceipt -Context $Context `
            -OperationResult $hold.down -RelativePath ('{0}/receipts/hold-w.json' -f $prefix)
        if ($hold.release) {
            $holdUpReceipt = Save-ValidationOperationReceipt -Context $Context `
                -OperationResult $hold.release -RelativePath ('{0}/receipts/release-w.json' -f $prefix)
        }
        Assert-ValidationOperationOk -Context $Context -OperationResult $hold.down `
            -AffectedCapabilities @('HoldKey')
        if ($hold.body_fault) {
            Add-ValidationFault -Context $Context -Domain executor -Code $hold.body_fault.code `
                -Message $hold.body_fault.message -AffectedCapabilities @('HoldKey', 'WaitUntil')
            throw [InvalidOperationException]::new('validation_hold_body_failed')
        }
        Assert-ValidationOperationOk -Context $Context -OperationResult $hold.release `
            -AffectedCapabilities @('ReleaseKey')
        $secondHoldSnapshot = Get-ValidationWaitSnapshot -WaitResult $hold.body.second
        $releaseWaitPath = '{0}/waits/release.json' -f $prefix
        $releaseWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $releaseWaitPath `
            -Predicate {
                param($snapshot)
                return $snapshot.keyboard.w_down -eq $false -and
                    [long]$snapshot.snapshot_id -gt [long]$secondHoldSnapshot.snapshot_id
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $releaseWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $releaseWait `
            -AffectedCapabilities @('ReleaseKey', 'WaitUntil')
        $releasedSnapshot = Get-ValidationWaitSnapshot -WaitResult $releaseWait
        $stoppedX = [double]$releasedSnapshot.object.normalized_position.x
        $stoppedTicks = [int]$releasedSnapshot.keyboard.hold_count
        $stabilityWaitPath = '{0}/waits/release-stable.json' -f $prefix
        $stabilityWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 75 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $stabilityWaitPath `
            -Predicate {
                param($snapshot)
                return $snapshot.keyboard.w_down -eq $false -and
                    [long]$snapshot.snapshot_id -gt [long]$releasedSnapshot.snapshot_id -and
                    [int]$snapshot.keyboard.hold_count -eq $stoppedTicks -and
                    [Math]::Abs([double]$snapshot.object.normalized_position.x - $stoppedX) -le 0.001
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $stabilityWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $stabilityWait `
            -AffectedCapabilities @('ReleaseKey', 'WaitUntil')
        Complete-ValidationLocalCapability -Local $local -Name HoldKey -Success $true `
            -Evidence @($holdDownReceipt.path, $hold.body.first_path, $hold.body.second_path)
        Complete-ValidationLocalCapability -Local $local -Name ReleaseKey -Success $true `
            -Evidence @($holdUpReceipt.path, $releaseWaitPath, $stabilityWaitPath)
        Complete-ValidationLocalCapability -Local $local -Name WaitUntil -Success $true `
            -Evidence @($spaceWaitPath, $hold.body.first_path, $hold.body.second_path,
                $releaseWaitPath, $stabilityWaitPath)

        $stage = 'FindAndMove'
        Start-ValidationLocalCapability -Local $local -Name FindVisibleTarget
        Start-ValidationLocalCapability -Local $local -Name MovePointer
        $currentRead = Read-UnrealEvaluationState -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs
        Assert-ValidationOperationOk -Context $Context -OperationResult $currentRead `
            -AffectedCapabilities @('ReadState', 'FindVisibleTarget')
        $clickTarget = Find-UnrealVisibleTarget -Snapshot $currentRead -TargetId 'click_target' `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object'
        $findReceipt = Save-ValidationOperationReceipt -Context $Context `
            -OperationResult $clickTarget `
            -RelativePath ('{0}/receipts/find-click-target.json' -f $prefix)
        Assert-ValidationOperationOk -Context $Context -OperationResult $clickTarget `
            -AffectedCapabilities @('FindVisibleTarget')
        if (-not $clickTarget.result.usable) {
            Add-ValidationFault -Context $Context -Domain observer -Code 'click_target_not_usable' `
                -Message 'The current click target was not visible, enabled, topmost, and bounded.' `
                -AffectedCapabilities @('FindVisibleTarget', 'Click')
            throw [InvalidOperationException]::new('validation_click_target_unusable')
        }
        Complete-ValidationLocalCapability -Local $local -Name FindVisibleTarget -Success $true `
            -Evidence @($findReceipt.path)
        $clickX = [double]$clickTarget.result.normalized_bounds.x +
            ([double]$clickTarget.result.normalized_bounds.width / 2)
        $clickY = [double]$clickTarget.result.normalized_bounds.y +
            ([double]$clickTarget.result.normalized_bounds.height / 2)
        $move = Move-UnrealPointer -Session $session -NormalizedX $clickX -NormalizedY $clickY
        $moveReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $move `
            -RelativePath ('{0}/receipts/move-click-target.json' -f $prefix)
        Assert-ValidationOperationOk -Context $Context -OperationResult $move `
            -AffectedCapabilities @('MovePointer')
        $moveWaitPath = '{0}/waits/move-pointer.json' -f $prefix
        $moveWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $moveWaitPath `
            -Predicate {
                param($snapshot)
                return [Math]::Abs([double]$snapshot.pointer.normalized_position.x - $clickX) -le 0.03 -and
                    [Math]::Abs([double]$snapshot.pointer.normalized_position.y - $clickY) -le 0.03
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $moveWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $moveWait `
            -AffectedCapabilities @('MovePointer', 'WaitUntil')
        Complete-ValidationLocalCapability -Local $local -Name MovePointer -Success $true `
            -Evidence @($moveReceipt.path, $moveWaitPath)

        $stage = 'MouseDownUp'
        Start-ValidationLocalCapability -Local $local -Name MouseDown
        Start-ValidationLocalCapability -Local $local -Name MouseUp
        $moveSafe = Move-UnrealPointer -Session $session -NormalizedX 0.30 -NormalizedY 0.30
        Assert-ValidationOperationOk -Context $Context -OperationResult $moveSafe `
            -AffectedCapabilities @('MovePointer', 'MouseDown')
        $mouseHold = Invoke-ValidationHeldAction `
            -DownAction { Start-UnrealMouseHold -Session $session -Button Left } `
            -Body {
                $downWaitPath = '{0}/waits/mouse-down.json' -f $prefix
                $downWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
                    -ExpectedProcessToken $processToken `
                    -ExpectedProcessId ([int]$start.result.process_id) `
                    -ExpectedRoundId ([string]$holdBaseline.round_id) `
                    -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
                    -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
                    -EvidenceRoot $Context.run_root -EvidencePath $downWaitPath `
                    -Predicate { param($snapshot) return $snapshot.pointer.left_down -eq $true }
                Add-ValidationOperationEvidence -Context $Context -OperationResult $downWait
                Assert-ValidationOperationOk -Context $Context -OperationResult $downWait `
                    -AffectedCapabilities @('MouseDown', 'WaitUntil')
                return [pscustomobject]@{ wait = $downWait; path = $downWaitPath }
            } `
            -UpAction { Stop-UnrealMouseHold -Session $session -Button Left -Cleanup }
        $mouseDownReceipt = Save-ValidationOperationReceipt -Context $Context `
            -OperationResult $mouseHold.down `
            -RelativePath ('{0}/receipts/mouse-down.json' -f $prefix)
        if ($mouseHold.release) {
            $mouseUpReceipt = Save-ValidationOperationReceipt -Context $Context `
                -OperationResult $mouseHold.release `
                -RelativePath ('{0}/receipts/mouse-up.json' -f $prefix)
        }
        Assert-ValidationOperationOk -Context $Context -OperationResult $mouseHold.down `
            -AffectedCapabilities @('MouseDown')
        if ($mouseHold.body_fault) {
            throw [InvalidOperationException]::new('validation_mouse_hold_body_failed')
        }
        Assert-ValidationOperationOk -Context $Context -OperationResult $mouseHold.release `
            -AffectedCapabilities @('MouseUp')
        $mouseDownSnapshot = Get-ValidationWaitSnapshot -WaitResult $mouseHold.body.wait
        $mouseUpWaitPath = '{0}/waits/mouse-up.json' -f $prefix
        $mouseUpWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $mouseUpWaitPath `
            -Predicate {
                param($snapshot)
                return $snapshot.pointer.left_down -eq $false -and
                    [long]$snapshot.snapshot_id -gt [long]$mouseDownSnapshot.snapshot_id
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $mouseUpWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $mouseUpWait `
            -AffectedCapabilities @('MouseUp', 'WaitUntil')
        Complete-ValidationLocalCapability -Local $local -Name MouseDown -Success $true `
            -Evidence @($mouseDownReceipt.path, $mouseHold.body.path)
        Complete-ValidationLocalCapability -Local $local -Name MouseUp -Success $true `
            -Evidence @($mouseUpReceipt.path, $mouseUpWaitPath)

        $stage = 'Click'
        Start-ValidationLocalCapability -Local $local -Name Click
        $preClickRead = Read-UnrealEvaluationState -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs
        Assert-ValidationOperationOk -Context $Context -OperationResult $preClickRead `
            -AffectedCapabilities @('Click', 'ReadState')
        $clickTarget = Find-UnrealVisibleTarget -Snapshot $preClickRead -TargetId 'click_target' `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object'
        Assert-ValidationOperationOk -Context $Context -OperationResult $clickTarget `
            -AffectedCapabilities @('Click', 'FindVisibleTarget')
        if (-not $clickTarget.result.usable) {
            throw [InvalidOperationException]::new('validation_click_target_unusable')
        }
        $clickBounds = $clickTarget.result.normalized_bounds
        $clickX = [double]$clickBounds.x + ([double]$clickBounds.width / 2)
        $clickY = [double]$clickBounds.y + ([double]$clickBounds.height / 2)
        $feedbackProbePlan = Get-ValidationFeedbackProbePlan
        $preClickCaptureProbe = Invoke-ValidationPlayerVisibleCaptureProbe `
            -Context $Context -Session $session -EvidencePrefix $prefix `
            -ArtifactIdStem ('pre-click-{0:d2}' -f $AttemptIndex) `
            -MaxAttempts $feedbackProbePlan.max_attempts `
            -TimeoutMs $feedbackProbePlan.timeout_ms `
            -PollIntervalMs $feedbackProbePlan.poll_interval_ms
        foreach ($evidencePath in $preClickCaptureProbe.evidence_paths) {
            $captureEvidence.Add($evidencePath)
        }
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Click `
            -Evidence @($preClickCaptureProbe.evidence_paths)
        if (-not $preClickCaptureProbe.accepted) {
            Add-ValidationFault -Context $Context -Domain environment `
                -Code 'visible_feedback_frame_timeout' `
                -Message 'The client did not present a player-visible click baseline within the bounded capture probe.' `
                -AffectedCapabilities @('Click', 'Capture') `
                -Evidence @($preClickCaptureProbe.evidence_paths)
            throw [InvalidOperationException]::new('validation_visible_feedback_frame_timeout')
        }
        $preClickCaptureRelative = [string]$preClickCaptureProbe.accepted_path
        $preClickCapturePath = Get-ValidationSafeFullPath -Path (Join-Path $Context.run_root `
                ($preClickCaptureRelative.Replace('/', [IO.Path]::DirectorySeparatorChar))) `
            -RequireLeaf
        if (-not $preClickCapturePath -or
            -not (Test-ValidationPathWithinRoot -Root $Context.run_root `
                -Path $preClickCapturePath)) {
            throw [InvalidOperationException]::new('visible_feedback_artifact_invalid')
        }
        $clickBaselineCount = [int]$preClickRead.result.snapshot.pointer.click_count
        $clickBaselineHud = [int]$preClickRead.result.snapshot.hud.revision
        $click = Invoke-UnrealClick -Session $session -NormalizedX $clickX -NormalizedY $clickY `
            -Button Left -DurationMs 40
        $clickReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $click `
            -RelativePath ('{0}/receipts/click.json' -f $prefix)
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Click `
            -Evidence @($clickReceipt.path)
        Assert-ValidationOperationOk -Context $Context -OperationResult $click `
            -AffectedCapabilities @('Click')
        $clickWaitPath = '{0}/waits/click.json' -f $prefix
        $clickWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $clickWaitPath `
            -Predicate {
                param($snapshot)
                return [int]$snapshot.pointer.click_count -eq ($clickBaselineCount + 1) -and
                    [int]$snapshot.hud.revision -gt $clickBaselineHud
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $clickWait
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Click `
            -Evidence @($clickWaitPath)
        Assert-ValidationOperationOk -Context $Context -OperationResult $clickWait `
            -AffectedCapabilities @('Click', 'WaitUntil')
        $afterClickCaptureProbe = Invoke-ValidationPlayerVisibleCaptureProbe `
            -Context $Context -Session $session -EvidencePrefix $prefix `
            -ArtifactIdStem ('after-click-{0:d2}' -f $AttemptIndex) `
            -MaxAttempts $feedbackProbePlan.max_attempts `
            -TimeoutMs $feedbackProbePlan.timeout_ms `
            -PollIntervalMs $feedbackProbePlan.poll_interval_ms `
            -BaselinePath $preClickCapturePath -RequireVisualChange `
            -X ([double]$clickBounds.x) -Y ([double]$clickBounds.y) `
            -Width ([double]$clickBounds.width) -Height ([double]$clickBounds.height)
        foreach ($evidencePath in $afterClickCaptureProbe.evidence_paths) {
            $captureEvidence.Add($evidencePath)
        }
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Click `
            -Evidence @($afterClickCaptureProbe.evidence_paths)
        if (-not $afterClickCaptureProbe.accepted) {
            $clickFaultDomain = if ($afterClickCaptureProbe.last_visible_difference) {
                'evidence'
            }
            else { 'environment' }
            $clickFaultCode = if ($afterClickCaptureProbe.last_visible_difference) {
                'click_feedback_not_visible'
            }
            else { 'visible_feedback_frame_timeout' }
            Add-ValidationFault -Context $Context -Domain $clickFaultDomain `
                -Code $clickFaultCode `
                -Message 'The client did not present a player-visible changed click-target frame within the bounded capture probe.' `
                -AffectedCapabilities @('Click', 'Capture') `
                -Evidence @($afterClickCaptureProbe.evidence_paths)
            throw [InvalidOperationException]::new('validation_click_feedback_missing')
        }
        $afterClickCaptureRelative = [string]$afterClickCaptureProbe.accepted_path
        $clickDiff = $afterClickCaptureProbe.accepted_difference
        if (-not $clickDiff.player_visible_pair -or
            $clickDiff.changed_pixel_count -le 0 -or
            $clickDiff.before_sha256 -ceq $clickDiff.after_sha256) {
            throw [InvalidOperationException]::new('validation_click_feedback_missing')
        }
        Complete-ValidationLocalCapability -Local $local -Name Click -Success $true `
            -Evidence (@($clickReceipt.path, $clickWaitPath) +
                @($preClickCaptureProbe.evidence_paths) +
                @($afterClickCaptureProbe.evidence_paths))

        $stage = 'Drag'
        Start-ValidationLocalCapability -Local $local -Name Drag
        $preDragRead = Read-UnrealEvaluationState -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs
        Assert-ValidationOperationOk -Context $Context -OperationResult $preDragRead `
            -AffectedCapabilities @('Drag', 'ReadState')
        $dragTarget = Find-UnrealVisibleTarget -Snapshot $preDragRead -TargetId 'drag_target' `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object'
        Assert-ValidationOperationOk -Context $Context -OperationResult $dragTarget `
            -AffectedCapabilities @('Drag', 'FindVisibleTarget')
        if (-not $dragTarget.result.usable) {
            throw [InvalidOperationException]::new('validation_drag_target_unusable')
        }
        $dragBounds = $dragTarget.result.normalized_bounds
        $dragStartX = [double]$dragBounds.x + ([double]$dragBounds.width / 2)
        $dragStartY = [double]$dragBounds.y + ([double]$dragBounds.height / 2)
        $dragEndX = [Math]::Min(0.90, $dragStartX + 0.18)
        $dragEndY = [Math]::Min(0.90, $dragStartY + 0.15)
        $dragBaselineCount = [int]$preDragRead.result.snapshot.pointer.drag_count
        $drag = Invoke-UnrealDrag -Session $session -StartX $dragStartX -StartY $dragStartY `
            -EndX $dragEndX -EndY $dragEndY -Button Left -DurationMs 500 -Steps 10
        $dragReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $drag `
            -RelativePath ('{0}/receipts/drag.json' -f $prefix)
        Assert-ValidationOperationOk -Context $Context -OperationResult $drag `
            -AffectedCapabilities @('Drag')
        $dragWaitPath = '{0}/waits/drag.json' -f $prefix
        $dragWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedRoundId ([string]$holdBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $dragWaitPath `
            -Predicate {
                param($snapshot)
                $published = @($snapshot.targets | Where-Object { $_.target_id -ceq 'drag_target' })
                return [int]$snapshot.pointer.drag_count -eq ($dragBaselineCount + 1) -and
                    $published.Count -eq 1 -and
                    [Math]::Abs([double]$published[0].normalized_bounds.x - [double]$dragBounds.x) -gt 0.02
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $dragWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $dragWait `
            -AffectedCapabilities @('Drag', 'WaitUntil')
        Complete-ValidationLocalCapability -Local $local -Name Drag -Success $true `
            -Evidence @($dragReceipt.path, $dragWaitPath)
        $stage = 'Restart'
        Start-ValidationLocalCapability -Local $local -Name Restart
        $beforeRestart = Get-ValidationWaitSnapshot -WaitResult $dragWait
        $restartOne = Restart-UnrealEvaluationSession -Session $session -Key R
        $restartOneReceipt = Save-ValidationOperationReceipt -Context $Context `
            -OperationResult $restartOne `
            -RelativePath ('{0}/receipts/restart-1.json' -f $prefix)
        Assert-ValidationOperationOk -Context $Context -OperationResult $restartOne `
            -AffectedCapabilities @('Restart')
        $restartOneWaitPath = '{0}/waits/restart-1.json' -f $prefix
        $restartOneWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
            -TimeoutMs 4000 -IntervalMs 50 -MaxSamples 100 `
            -EvidenceRoot $Context.run_root -EvidencePath $restartOneWaitPath `
            -Predicate {
                param($snapshot)
                return [string]$snapshot.round_id -cne [string]$beforeRestart.round_id -and
                    [int]$snapshot.restart_count -eq ([int]$beforeRestart.restart_count + 1) -and
                    [int]$snapshot.keyboard.discrete_count -eq 0 -and
                    [int]$snapshot.keyboard.hold_count -eq 0 -and
                    [int]$snapshot.pointer.click_count -eq 0 -and
                    [int]$snapshot.pointer.drag_count -eq 0 -and
                    $snapshot.keyboard.w_down -eq $false -and
                    $snapshot.pointer.left_down -eq $false -and
                    [Math]::Abs([double]$snapshot.object.normalized_position.x - 0.18) -le 0.001
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $restartOneWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $restartOneWait `
            -AffectedCapabilities @('Restart', 'WaitUntil')
        $afterRestartOne = Get-ValidationWaitSnapshot -WaitResult $restartOneWait
        $restartTwo = Restart-UnrealEvaluationSession -Session $session -Key R
        $restartTwoReceipt = Save-ValidationOperationReceipt -Context $Context `
            -OperationResult $restartTwo `
            -RelativePath ('{0}/receipts/restart-2.json' -f $prefix)
        Assert-ValidationOperationOk -Context $Context -OperationResult $restartTwo `
            -AffectedCapabilities @('Restart')
        $restartTwoWaitPath = '{0}/waits/restart-2.json' -f $prefix
        $restartTwoWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$start.result.process_id) `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
            -TimeoutMs 4000 -IntervalMs 50 -MaxSamples 100 `
            -EvidenceRoot $Context.run_root -EvidencePath $restartTwoWaitPath `
            -Predicate {
                param($snapshot)
                return [string]$snapshot.round_id -cne [string]$afterRestartOne.round_id -and
                    [int]$snapshot.restart_count -eq ([int]$afterRestartOne.restart_count + 1) -and
                    [int]$snapshot.keyboard.discrete_count -eq 0 -and
                    [int]$snapshot.pointer.click_count -eq 0 -and
                    [int]$snapshot.pointer.drag_count -eq 0
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $restartTwoWait
        Assert-ValidationOperationOk -Context $Context -OperationResult $restartTwoWait `
            -AffectedCapabilities @('Restart', 'WaitUntil')
        $allWaits = $true
        $restartSnapshot = Get-ValidationWaitSnapshot -WaitResult $restartTwoWait
        $restartStateEvidence = Save-ValidationSnapshot -Context $Context -Snapshot $restartSnapshot `
            -RelativePath ('{0}/states/after-consecutive-restart.json' -f $prefix)
        Complete-ValidationLocalCapability -Local $local -Name Restart -Success $true `
            -Evidence @($restartOneReceipt.path, $restartOneWaitPath, $restartTwoReceipt.path,
                $restartTwoWaitPath, $restartStateEvidence.path)

        $stage = 'Reopen'
        Start-ValidationLocalCapability -Local $local -Name Reopen
        $oldSession = $session
        $oldProcessId = [int]$start.result.process_id
        $oldProcessToken = $processToken
        $sessionActive = $false
        $reopen = Reopen-UnrealEvaluationSession -Session $oldSession `
            -GraceTimeoutMs $StopTimeoutMs -StartTimeoutMs $StartTimeoutMs
        if ($reopen.status -eq 'ok' -and $reopen.result -and
            $reopen.result.PSObject.Properties['session'] -and $reopen.result.session) {
            $session = $reopen.result.session
            $sessionActive = $true
        }
        elseif ($reopen.status -ne 'ok' -and $reopen.result -and
            $reopen.result.PSObject.Properties['session_retained_for_cleanup_retry'] -and
            $reopen.result.session_retained_for_cleanup_retry -and
            $reopen.result.PSObject.Properties['session'] -and $reopen.result.session) {
            $session = $reopen.result.session
            $sessionActive = $true
        }
        if ($reopen.result -and $reopen.result.PSObject.Properties['old_stop_attempts']) {
            $reopenStopAttemptIndex = 0
            foreach ($reopenStopAttempt in @($reopen.result.old_stop_attempts)) {
                ++$reopenStopAttemptIndex
                [void](Save-ValidationOperationReceipt -Context $Context `
                        -OperationResult $reopenStopAttempt `
                        -RelativePath ('{0}/receipts/reopen-old-stop-{1:d2}.json' -f
                            $prefix, $reopenStopAttemptIndex))
                [void](Add-ValidationStopCleanupRecord -Context $Context `
                        -Source ('{0}-reopen-old-stop-{1:d2}' -f
                            $attemptName, $reopenStopAttemptIndex) `
                        -StopResult $reopenStopAttempt)
            }
        }
        elseif ($reopen.result -and $reopen.result.PSObject.Properties['stop_attempts']) {
            $reopenStopAttemptIndex = 0
            foreach ($reopenStopAttempt in @($reopen.result.stop_attempts)) {
                ++$reopenStopAttemptIndex
                [void](Save-ValidationOperationReceipt -Context $Context `
                        -OperationResult $reopenStopAttempt `
                        -RelativePath ('{0}/receipts/reopen-old-stop-{1:d2}.json' -f
                            $prefix, $reopenStopAttemptIndex))
                [void](Add-ValidationStopCleanupRecord -Context $Context `
                        -Source ('{0}-reopen-old-stop-{1:d2}' -f
                            $attemptName, $reopenStopAttemptIndex) `
                        -StopResult $reopenStopAttempt)
            }
        }
        $reopenReceipt = Save-ValidationOperationReceipt -Context $Context `
            -OperationResult $reopen -RelativePath ('{0}/receipts/reopen.json' -f $prefix)
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Reopen `
            -Evidence @($reopenReceipt.path)
        Assert-ValidationOperationOk -Context $Context -OperationResult $reopen `
            -AffectedCapabilities @(Get-ValidationReopenAffectedCapabilities `
                -OperationResult $reopen)
        $session = $reopen.result.session
        $sessionActive = $true
        $processToken = [string]$reopen.result.process_token
        if ([int]$reopen.result.process_id -eq $oldProcessId -or
            $processToken -ceq $oldProcessToken) {
            Add-ValidationFault -Context $Context -Domain executor `
                -Code 'reopen_identity_not_renewed' `
                -Message 'Reopen did not produce both a new process identifier and a new process token.' `
                -AffectedCapabilities @('Reopen')
            throw [InvalidOperationException]::new('validation_reopen_identity_invalid')
        }
        $reopenRead = Read-UnrealEvaluationState -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId ([int]$reopen.result.process_id) `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs
        Assert-ValidationOperationOk -Context $Context -OperationResult $reopenRead `
            -AffectedCapabilities @('Reopen', 'ReadState')
        if (-not (Test-ValidationInitialSnapshot -Snapshot $reopenRead.result.snapshot)) {
            Add-ValidationFault -Context $Context -Domain observer `
                -Code 'reopen_initial_state_not_deterministic' `
                -Message 'The reopened process did not publish the deterministic initial fixture state.' `
                -AffectedCapabilities @('Reopen')
            throw [InvalidOperationException]::new('validation_reopen_state_invalid')
        }
        $reopenStateEvidence = Save-ValidationSnapshot -Context $Context `
            -Snapshot $reopenRead.result.snapshot `
            -RelativePath ('{0}/states/reopen-initial.json' -f $prefix) `
            -AffectedCapabilities @('Reopen', 'ReadState')
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Reopen `
            -Evidence @($reopenStateEvidence.path)
        $reopenVisualPrefix = '{0}/reopen' -f $prefix
        $reopenBaselineProbe = Invoke-ValidationStableVisibleBaselineProbe `
            -Context $Context -Session $session -EvidencePrefix $reopenVisualPrefix `
            -ArtifactIdStem ('reopen-baseline-{0:d2}' -f $AttemptIndex) `
            -RequireInitialFixtureState -Operation Reopen
        Add-ValidationLocalCapabilityEvidence -Local $local -Name Reopen `
            -Evidence @($reopenBaselineProbe.evidence_paths)
        Assert-ValidationStableVisibleBaseline -Context $Context `
            -Probe $reopenBaselineProbe -Operation Reopen
        Complete-ValidationLocalCapability -Local $local -Name Reopen -Success $true `
            -Evidence (@($reopenReceipt.path, $reopenStateEvidence.path) +
                @($reopenBaselineProbe.evidence_paths))

    }
    catch {
        $attemptFault = Resolve-ValidationCoreAttemptFault -Context $Context `
            -Stage $stage -FaultCountBefore $faultCountBefore
    }
    finally {
        if ($sessionActive -and $session) {
            Start-ValidationLocalCapability -Local $local -Name Stop
            $stopSequence = Invoke-ValidationStopWithRetry -Session $session `
                -GraceTimeoutMs $StopTimeoutMs
            $stop = $stopSequence.final
            try {
                if ($stopSequence.attempted_count -gt 1) {
                    [void](Save-ValidationOperationReceipt -Context $Context `
                            -OperationResult $stopSequence.attempts[0] `
                            -RelativePath ('{0}/receipts/stop-retryable-01.json' -f $prefix))
                }
                $stopReceipt = Save-ValidationOperationReceipt -Context $Context `
                    -OperationResult $stop -RelativePath ('{0}/receipts/stop.json' -f $prefix)
            }
            catch {
                $stopReceipt = $null
            }
            if ($stop.status -eq 'ok') {
                Complete-ValidationLocalCapability -Local $local -Name Stop -Success $true `
                    -Evidence $(if ($stopReceipt) { @($stopReceipt.path) } else { @() })
            }
            else {
                Add-ValidationFaultFromOperation -Context $Context -OperationResult $stop `
                    -AffectedCapabilities @('Stop')
            }
            [void](Add-ValidationStopCleanupRecord -Context $Context `
                    -Source $attemptName -StopResult $stop)
            if ($stop.status -ne 'ok' -and $stop.result -and
                $stop.result.PSObject.Properties['session_retained_for_cleanup_retry'] -and
                $stop.result.session_retained_for_cleanup_retry) {
                $sessionActive = $true
            }
        }
        elseif ($session) {
            $Context.cleanup_records.Add([pscustomobject][ordered]@{
                    source = $attemptName
                    stop_status = 'not_available_after_reopen'
                    keys_released = $false
                    mouse_buttons_released = $false
                    cursor_restored = $false
                    process_tree_clean = $false
                })
        }
        Commit-ValidationCoreAttemptCapabilities -Context $Context -Local $local `
            -AttemptIndex $AttemptIndex -FaultCountBefore $faultCountBefore
        $success = $true
        foreach ($name in $script:CapabilityNames) {
            if (-not $local[$name].attempted -or -not $local[$name].success) {
                $success = $false
                break
            }
        }
        $Context.attempt_details.Add([pscustomobject][ordered]@{
                attempt_index = $AttemptIndex
                completed = $success
                terminal_stage = $stage
                fault = $attemptFault
                all_waits_completed = $allWaits
            })
    }
}

function Get-ValidationNegativePlan {
    return @(
        'wrong_pid_zero_dispatch',
        'invalid_window_zero_dispatch',
        'foreground_zero_dispatch_state_unchanged',
        'missing_visible_target',
        'state_interface_unavailable',
        'bounded_wait_timeout',
        'predicate_text_pass_rejected',
        'hold_exception_release',
        'hold_focus_loss_watchdog_release',
        'existing_run_refusal',
        'evidence_missing',
        'evidence_corrupted',
        'corrupt_state_classified',
        'reparse_ancestor_refusal',
        'executor_fault_not_game_failure'
    )
}

function Add-ValidationNegativeResult {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Classification,
        [string[]]$Evidence = @()
    )

    $Context.negative_results.Add([pscustomobject][ordered]@{
            name = $Name
            passed = $Passed
            classification = $Classification
            evidence = @($Evidence | Where-Object { Test-ValidationRelativePath -Path $_ } |
                    Select-Object -Unique)
        })
    if (-not $Passed) {
        Add-ValidationFault -Context $Context -Domain executor `
            -Code ('negative_' + $Name) `
            -Message 'A required negative validation did not produce its expected safe classification.' `
            -AffectedCapabilities @('Start', 'PressKey', 'HoldKey', 'ReleaseKey',
                'FindVisibleTarget', 'ReadState', 'WaitUntil') -Evidence $Evidence
    }
}

function Invoke-ValidationObserverDisabledControl {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][int]$AttemptIndex,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][object]$EngineReference,
        [Parameter(Mandatory)][int]$StartTimeoutMs,
        [Parameter(Mandatory)][int]$StopTimeoutMs,
        [Parameter(Mandatory)][int]$FeedbackBoundaryMs
    )

    $controlName = 'control-{0:d2}' -f $AttemptIndex
    $prefix = 'raw/{0}' -f $controlName
    $stateRelative = '{0}/state/disabled.json' -f $prefix
    $statePath = Resolve-ValidationArtifactDestination -RunRoot $Context.run_root `
        -RelativePath $stateRelative
    $processToken = 'process-control-' + [guid]::NewGuid().ToString('N')
    $session = $null
    $sessionActive = $false
    $passed = $false
    $classification = 'control_incomplete'
    $evidencePaths = [Collections.Generic.List[string]]::new()
    $metric = $null
    $stop = $null
    $controlStage = 'start'
    $faultCountBefore = $Context.faults.Count
    try {
        $controlStage = 'start'
        $start = Start-UnrealEvaluationSession -ProjectPath $ProjectPath `
            -RunRoot $Context.run_root -StatePath $statePath -ProcessToken $processToken `
            -EngineReference $EngineReference -WindowWidth 960 -WindowHeight 640 `
            -TimeoutMs $StartTimeoutMs -FocusTimeoutMs 1500 -ObserverDisabledControl
        $startReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $start `
            -RelativePath ('{0}/receipts/start.json' -f $prefix)
        $evidencePaths.Add($startReceipt.path)
        Assert-ValidationOperationOk -Context $Context -OperationResult $start `
            -AffectedCapabilities @('Start', 'ReadState')
        if (-not $start.result.observer_disabled_control -or [IO.File]::Exists($statePath)) {
            throw [InvalidOperationException]::new('observer_disabled_control_contract_failed')
        }
        $session = $start.result.session
        $sessionActive = $true

        $controlStage = 'visible_baseline'
        $beforeBaselineProbe = Invoke-ValidationStableVisibleBaselineProbe `
            -Context $Context -Session $session -EvidencePrefix $prefix `
            -ArtifactIdStem ('control-baseline-{0:d2}' -f $AttemptIndex) `
            -RequireInitialFixtureState
        foreach ($evidencePath in $beforeBaselineProbe.evidence_paths) {
            $evidencePaths.Add($evidencePath)
        }
        Assert-ValidationStableVisibleBaseline -Context $Context -Probe $beforeBaselineProbe
        $beforeRelative = [string]$beforeBaselineProbe.accepted_path
        $beforePath = Get-ValidationSafeFullPath -Path (Join-Path $Context.run_root `
                ($beforeRelative.Replace('/', [IO.Path]::DirectorySeparatorChar))) `
            -RequireLeaf
        if (-not $beforePath -or
            -not (Test-ValidationPathWithinRoot -Root $Context.run_root -Path $beforePath)) {
            throw [InvalidOperationException]::new('visible_baseline_artifact_invalid')
        }

        $controlStage = 'press'
        $started = Get-ValidationMonotonicMs
        $press = Invoke-UnrealPressKey -Session $session -Key Space -DurationMs 40
        $pressReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $press `
            -RelativePath ('{0}/receipts/press-space.json' -f $prefix)
        $evidencePaths.Add($pressReceipt.path)
        Assert-ValidationOperationOk -Context $Context -OperationResult $press `
            -AffectedCapabilities @('PressKey')

        $enabledMetric = @($Context.enabled_space_metrics |
                Where-Object { $_.attempt_index -eq $AttemptIndex } | Select-Object -First 1)
        $enabledFeedbackLatencyMs = if ($enabledMetric.Count -eq 1 -and
            [long]$enabledMetric[0].feedback_latency_ms -ge 1) {
            [long]$enabledMetric[0].feedback_latency_ms
        }
        else { $null }
        $controlStage = 'capture_after'
        $probeBudgetMs = if ($null -ne $enabledFeedbackLatencyMs) {
            $enabledFeedbackLatencyMs + $FeedbackBoundaryMs
        }
        else { $FeedbackBoundaryMs }
        $feedbackProbePlan = Get-ValidationFeedbackProbePlan `
            -TimeoutMs ([Math]::Clamp([int]$probeBudgetMs, 50, 30000))
        $feedbackProbe = Invoke-ValidationPlayerVisibleCaptureProbe `
            -Context $Context -Session $session -EvidencePrefix $prefix `
            -ArtifactIdStem ('control-after-space-{0:d2}' -f $AttemptIndex) `
            -MaxAttempts $feedbackProbePlan.max_attempts `
            -TimeoutMs $feedbackProbePlan.timeout_ms `
            -PollIntervalMs $feedbackProbePlan.poll_interval_ms `
            -BaselinePath $beforePath -RequireVisualChange `
            -X 0 -Y 0 -Width 1 -Height 0.20
        foreach ($evidencePath in $feedbackProbe.evidence_paths) {
            $evidencePaths.Add($evidencePath)
        }
        $controlStage = 'pixel_compare'
        if ($feedbackProbe.accepted) {
            $difference = $feedbackProbe.accepted_difference
            $captureCompleted = [long]$feedbackProbe.accepted_completed_monotonic_ms
        }
        elseif ($feedbackProbe.last_visible_difference) {
            $difference = $feedbackProbe.last_visible_difference
            $captureCompleted = [long]$feedbackProbe.last_visible_completed_monotonic_ms
        }
        else {
            Add-ValidationFault -Context $Context -Domain environment `
                -Code 'visible_feedback_frame_timeout' `
                -Message 'The observer-disabled client did not present a player-visible changed HUD frame within the bounded feedback probe.' `
                -AffectedCapabilities @('PressKey', 'Capture') -Evidence @($evidencePaths)
            throw [InvalidOperationException]::new('validation_visible_feedback_frame_timeout')
        }
        $elapsed = $captureCompleted - $started
        $comparison = Get-ValidationObserverControlComparison -AttemptIndex $AttemptIndex `
            -FeedbackLatencyMs $elapsed `
            -FeedbackLatencyDeltaBoundaryMs $FeedbackBoundaryMs -Difference $difference `
            -EnabledMetric $(if ($enabledMetric.Count -eq 1) { $enabledMetric[0] } else { $null }) `
            -ObserverStateFileAbsent (-not [IO.File]::Exists($statePath))
        $passed = [bool]$comparison.passed
        $classification = [string]$comparison.classification
        $metric = $comparison.metric
    }
    catch {
        $passed = $false
        if ($Context.faults.Count -gt $faultCountBefore) {
            $classification = [string]$Context.faults[$Context.faults.Count - 1].code
        }
        else {
            $controlDomain = if ($controlStage -eq 'visible_baseline') { 'environment' }
            elseif ($controlStage -in @('capture_after', 'pixel_compare')) {
                'evidence'
            }
            elseif ($controlStage -eq 'start') { 'environment' }
            else { 'executor' }
            $classification = 'observer_control_' + $controlStage + '_failed'
            Add-ValidationFault -Context $Context -Domain $controlDomain `
                -Code $classification `
                -Message 'The observer-disabled control ended outside a structured operation result.' `
                -AffectedCapabilities @('Start', 'PressKey', 'Capture')
        }
    }
    finally {
        if ($sessionActive -and $session) {
            $stopSequence = Invoke-ValidationStopWithRetry -Session $session `
                -GraceTimeoutMs $StopTimeoutMs
            $stop = $stopSequence.final
            try {
                if ($stopSequence.attempted_count -gt 1) {
                    $retryReceipt = Save-ValidationOperationReceipt -Context $Context `
                        -OperationResult $stopSequence.attempts[0] `
                        -RelativePath ('{0}/receipts/stop-retryable-01.json' -f $prefix)
                    $evidencePaths.Add($retryReceipt.path)
                }
                $stopReceipt = Save-ValidationOperationReceipt -Context $Context `
                    -OperationResult $stop -RelativePath ('{0}/receipts/stop.json' -f $prefix)
                $evidencePaths.Add($stopReceipt.path)
            }
            catch { }
            if ($stop.status -ne 'ok') {
                $passed = $false
                $classification = 'control_stop_failed'
                Add-ValidationFaultFromOperation -Context $Context -OperationResult $stop `
                    -AffectedCapabilities @('Stop')
            }
            [void](Add-ValidationStopCleanupRecord -Context $Context `
                    -Source $controlName -StopResult $stop)
            if ($stop.status -ne 'ok' -and $stop.result -and
                $stop.result.PSObject.Properties['session_retained_for_cleanup_retry'] -and
                $stop.result.session_retained_for_cleanup_retry) {
                $sessionActive = $true
            }
        }
        $record = [pscustomobject][ordered]@{
            attempt_index = $AttemptIndex
            passed = $passed
            classification = $classification
            metric = $metric
            evidence = @($evidencePaths | Select-Object -Unique)
        }
        $Context.control_results.Add($record)
        try {
            $controlEvidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
                -RelativePath ('{0}/control-result.json' -f $prefix) `
                -Value (ConvertTo-ValidationPublicValue -Value $record `
                    -SensitiveValues $Context.sensitive_values) -Kind report
            Add-ValidationEvidence -Context $Context -Evidence $controlEvidence
        }
        catch { }
        if (-not $passed -and
            (Test-ValidationObserverControlCapabilityFailure -Classification $classification)) {
            Add-ValidationFault -Context $Context -Domain capability `
                -Code 'observer_non_interference_not_confirmed' `
                -Message 'The observer-enabled and observer-disabled Space feedback controls were not mechanically equivalent within the declared boundary.' `
                -AffectedCapabilities @('PressKey', 'ReadState', 'Capture') `
                -Evidence @($evidencePaths)
        }
    }
}

function Invoke-ValidationNegativeMatrix {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][object]$EngineReference,
        [Parameter(Mandatory)][int]$StartTimeoutMs,
        [Parameter(Mandatory)][int]$StopTimeoutMs,
        [Parameter(Mandatory)][int]$ObserverMaxAgeMs
    )

    $prefix = 'raw/negative'
    $stateRelative = '{0}/state/live.json' -f $prefix
    $statePath = Resolve-ValidationArtifactDestination -RunRoot $Context.run_root `
        -RelativePath $stateRelative
    $processToken = 'process-negative-' + [guid]::NewGuid().ToString('N')
    $session = $null
    $sessionActive = $false
    $start = $null
    $targetWindow = $null
    $negativeStage = 'start_session'

    try {
        $start = Start-UnrealEvaluationSession -ProjectPath $ProjectPath `
            -RunRoot $Context.run_root -StatePath $statePath -ProcessToken $processToken `
            -EngineReference $EngineReference -WindowWidth 960 -WindowHeight 640 `
            -TimeoutMs $StartTimeoutMs -FocusTimeoutMs 1500
        $startReceipt = Save-ValidationOperationReceipt -Context $Context -OperationResult $start `
            -RelativePath ('{0}/receipts/start.json' -f $prefix)
        Assert-ValidationOperationOk -Context $Context -OperationResult $start `
            -AffectedCapabilities @('Start')
        $session = $start.result.session
        $sessionActive = $true
        $negativeStage = 'initial_state'
        $targetProcessId = [int]$start.result.process_id
        $read = Read-UnrealEvaluationState -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs
        Assert-ValidationOperationOk -Context $Context -OperationResult $read `
            -AffectedCapabilities @('ReadState')

        $windows = @([VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                EnumerateVisibleTopLevelWindows([uint32]$targetProcessId))
        if ($windows.Count -lt 1) {
            throw [InvalidOperationException]::new('negative_target_window_unavailable')
        }
        $targetWindow = $windows[0]

        $negativeStage = 'pid_and_window_boundaries'
        $wrongPid = if ($targetProcessId -lt [int]::MaxValue) {
            [uint32]($targetProcessId + 1)
        }
        else { [uint32]($targetProcessId - 1) }
        $inputDispatched = $false
        $validationCode = $null
        $nativeError = 0
        $wrongPidResult = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboardBound(
            $targetWindow.Handle, $wrongPid, [uint16]0x20, $false, $false,
            [ref]$inputDispatched, [ref]$validationCode, [ref]$nativeError)
        Add-ValidationNegativeResult -Context $Context -Name 'wrong_pid_zero_dispatch' `
            -Passed (-not $wrongPidResult -and -not $inputDispatched -and
                $validationCode -ceq 'WINDOW_PID_MISMATCH') `
            -Classification (ConvertTo-ValidationFaultCode -Code $validationCode)

        $inputDispatched = $false
        $validationCode = $null
        $nativeError = 0
        $invalidWindowResult = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboardBound(
            [IntPtr]::Zero, [uint32]$targetProcessId, [uint16]0x20, $false, $false,
            [ref]$inputDispatched, [ref]$validationCode, [ref]$nativeError)
        Add-ValidationNegativeResult -Context $Context -Name 'invalid_window_zero_dispatch' `
            -Passed (-not $invalidWindowResult -and -not $inputDispatched -and
                $validationCode -ceq 'WINDOW_INVALID') `
            -Classification (ConvertTo-ValidationFaultCode -Code $validationCode)

        $negativeStage = 'foreground_boundary'
        $focusBaseline = $read.result.snapshot
        $form = $null
        $focusDispatched = $false
        $focusValidationCode = $null
        $focusNativeError = 0
        $helperForeground = $false
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $form = [Windows.Forms.Form]::new()
            $form.Text = 'Evaluation focus boundary control'
            $form.Width = 180
            $form.Height = 90
            $form.ShowInTaskbar = $false
            $form.TopMost = $true
            $form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
            $form.Location = [Drawing.Point]::new(0, 0)
            $form.Show()
            [Windows.Forms.Application]::DoEvents()
            $focusRequestError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RequestForeground(
                $form.Handle, [ref]$focusRequestError)
            [Windows.Forms.Application]::DoEvents()
            $helperSnapshot = $null
            $helperCode = $null
            $helperError = 0
            $helperForeground = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                TryGetWindowSnapshot($form.Handle, [uint32][Environment]::ProcessId, $true,
                    [ref]$helperSnapshot, [ref]$helperCode, [ref]$helperError)
            $focusBoundResult = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboardBound(
                $targetWindow.Handle, [uint32]$targetProcessId, [uint16]0x20, $false, $false,
                [ref]$focusDispatched, [ref]$focusValidationCode, [ref]$focusNativeError)
        }
        finally {
            if ($form) {
                try { $form.Close() } catch { }
                try { $form.Dispose() } catch { }
                try { [Windows.Forms.Application]::DoEvents() } catch { }
            }
            $restoreError = 0
            try {
                [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RequestForeground(
                    $targetWindow.Handle, [ref]$restoreError)
            }
            catch { }
            if ($focusDispatched) {
                $releaseDispatched = $false
                $releaseCode = $null
                $releaseError = 0
                try {
                    [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboardBound(
                        $targetWindow.Handle, [uint32]$targetProcessId, [uint16]0x20, $true, $false,
                        [ref]$releaseDispatched, [ref]$releaseCode, [ref]$releaseError)
                }
                catch { }
            }
        }
        $focusWaitPath = '{0}/waits/focus-state-unchanged.json' -f $prefix
        $focusWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
            -ExpectedRoundId ([string]$focusBaseline.round_id) -ExpectedObjectId 'movable_object' `
            -MaxAgeMs $ObserverMaxAgeMs -TimeoutMs 3000 -IntervalMs 75 -MaxSamples 60 `
            -EvidenceRoot $Context.run_root -EvidencePath $focusWaitPath `
            -Predicate {
                param($snapshot)
                return [long]$snapshot.snapshot_id -gt [long]$focusBaseline.snapshot_id -and
                    [int]$snapshot.keyboard.discrete_count -eq [int]$focusBaseline.keyboard.discrete_count -and
                    $snapshot.keyboard.w_down -eq $false
            }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $focusWait
        $focusPassed = $helperForeground -and -not $focusDispatched -and
            $focusValidationCode -ceq 'FOREGROUND_NOT_CONFIRMED' -and
            $focusWait.status -eq 'ok'
        Add-ValidationNegativeResult -Context $Context `
            -Name 'foreground_zero_dispatch_state_unchanged' -Passed $focusPassed `
            -Classification (ConvertTo-ValidationFaultCode -Code $focusValidationCode) `
            -Evidence @($focusWaitPath)

        $negativeStage = 'focus_watchdog_cleanup'
        $watchdogEvidencePaths = [Collections.Generic.List[string]]::new()
        $watchdogDown = $null
        $watchdogDownWait = $null
        $watchdogReleaseWait = $null
        $watchdogFaultOperation = $null
        $watchdogCleanupRelease = $null
        $watchdogForm = $null
        $watchdogHelperForeground = $false
        $watchdogQueried = $false
        $watchdogActive = $false
        $watchdogFaulted = $false
        $watchdogFaultCode = 'UNKNOWN'
        $watchdogNativeError = 0
        $watchdogPostQueried = $false
        $watchdogPostState = $null
        $watchdogLatchCleared = $false
        try {
            $restoreError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RequestForeground(
                $targetWindow.Handle, [ref]$restoreError)
            $watchdogDown = Start-UnrealKeyHold -Session $session -Key W
            $watchdogDownReceipt = Save-ValidationOperationReceipt -Context $Context `
                -OperationResult $watchdogDown `
                -RelativePath ('{0}/receipts/watchdog-hold-down.json' -f $prefix)
            $watchdogEvidencePaths.Add($watchdogDownReceipt.path)
            if ($watchdogDown.status -eq 'ok') {
                $watchdogDownPath = '{0}/waits/watchdog-hold-observed.json' -f $prefix
                $watchdogDownWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
                    -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
                    -ExpectedRoundId ([string]$read.result.snapshot.round_id) `
                    -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
                    -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
                    -EvidenceRoot $Context.run_root -EvidencePath $watchdogDownPath `
                    -Predicate { param($snapshot) return $snapshot.keyboard.w_down -eq $true }
                Add-ValidationOperationEvidence -Context $Context `
                    -OperationResult $watchdogDownWait
                $watchdogEvidencePaths.Add($watchdogDownPath)

                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $watchdogForm = [Windows.Forms.Form]::new()
                $watchdogForm.Text = 'Evaluation watchdog focus boundary'
                $watchdogForm.Width = 180
                $watchdogForm.Height = 90
                $watchdogForm.ShowInTaskbar = $false
                $watchdogForm.TopMost = $true
                $watchdogForm.KeyPreview = $true
                $watchdogForm.StartPosition = [Windows.Forms.FormStartPosition]::Manual
                $watchdogForm.Location = [Drawing.Point]::new(0, 0)
                $watchdogForm.Show()
                [Windows.Forms.Application]::DoEvents()
                $focusRequestError = 0
                [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RequestForeground(
                    $watchdogForm.Handle, [ref]$focusRequestError)
                [Windows.Forms.Application]::DoEvents()
                $helperSnapshot = $null
                $helperCode = $null
                $helperError = 0
                $watchdogHelperForeground = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                    TryGetWindowSnapshot($watchdogForm.Handle,
                        [uint32][Environment]::ProcessId, $true,
                        [ref]$helperSnapshot, [ref]$helperCode, [ref]$helperError)

                $watchdogDeadline = (Get-ValidationMonotonicMs) + 2000
                do {
                    $watchdogQueried = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                        QueryInputWatchdog($targetWindow.Handle, [uint32]$targetProcessId,
                            [ref]$watchdogActive, [ref]$watchdogFaulted,
                            [ref]$watchdogFaultCode, [ref]$watchdogNativeError)
                    if ($watchdogQueried -and $watchdogFaulted -and -not $watchdogActive) {
                        break
                    }
                    [Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 25
                } while ((Get-ValidationMonotonicMs) -lt $watchdogDeadline)

                $watchdogFaultOperation = Move-UnrealPointer -Session $session `
                    -NormalizedX 0.50 -NormalizedY 0.50
                $watchdogFaultReceipt = Save-ValidationOperationReceipt -Context $Context `
                    -OperationResult $watchdogFaultOperation `
                    -RelativePath ('{0}/receipts/watchdog-fault-propagation.json' -f $prefix)
                $watchdogEvidencePaths.Add($watchdogFaultReceipt.path)

                $watchdogPostError = 0
                $watchdogPostQueried = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                    QueryAllControlledInputState([ref]$watchdogPostState,
                        [ref]$watchdogPostError)
                $watchdogReleasePath = '{0}/waits/watchdog-release-observed.json' -f $prefix
                $watchdogReleaseWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
                    -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
                    -ExpectedRoundId ([string]$read.result.snapshot.round_id) `
                    -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
                    -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
                    -EvidenceRoot $Context.run_root -EvidencePath $watchdogReleasePath `
                    -Predicate { param($snapshot) return $snapshot.keyboard.w_down -eq $false }
                Add-ValidationOperationEvidence -Context $Context `
                    -OperationResult $watchdogReleaseWait
                $watchdogEvidencePaths.Add($watchdogReleasePath)

                $clearCode = $null
                $clearError = 0
                $watchdogLatchCleared = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                    ClearInputWatchdog($targetWindow.Handle, [uint32]$targetProcessId,
                        [ref]$clearCode, [ref]$clearError)
            }
        }
        catch { }
        finally {
            if ($watchdogForm) {
                try { $watchdogForm.Close() } catch { }
                try { $watchdogForm.Dispose() } catch { }
                try { [Windows.Forms.Application]::DoEvents() } catch { }
            }
            $restoreError = 0
            try {
                [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RequestForeground(
                    $targetWindow.Handle, [ref]$restoreError)
            }
            catch { }
            if ($watchdogDown -and $watchdogDown.status -eq 'ok') {
                try {
                    $watchdogCleanupRelease = Stop-UnrealKeyHold -Session $session -Key W -Cleanup
                    $watchdogCleanupReceipt = Save-ValidationOperationReceipt -Context $Context `
                        -OperationResult $watchdogCleanupRelease `
                        -RelativePath ('{0}/receipts/watchdog-finally-release.json' -f $prefix)
                    $watchdogEvidencePaths.Add($watchdogCleanupReceipt.path)
                }
                catch { }
            }
            $releaseState = $null
            $releaseFailureCount = 0
            $releaseError = 0
            try {
                [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                    ReleaseAllControlledInputs([ref]$releaseState,
                        [ref]$releaseFailureCount, [ref]$releaseError)
            }
            catch { }
            $stopFaulted = $false
            $stopFaultCode = $null
            $stopNativeError = 0
            try {
                [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::StopInputWatchdog(
                    $targetWindow.Handle, [uint32]$targetProcessId, [ref]$stopFaulted,
                    [ref]$stopFaultCode, [ref]$stopNativeError)
            }
            catch { }
        }
        $watchdogFaultPropagated = $watchdogFaultOperation -and
            $watchdogFaultOperation.status -eq 'executor_fault' -and
            $watchdogFaultOperation.executor_fault -and
            $watchdogFaultOperation.fault.code -ceq 'input_watchdog_fault_latched'
        $watchdogPassed = $watchdogDown -and $watchdogDown.status -eq 'ok' -and
            $watchdogDownWait -and $watchdogDownWait.status -eq 'ok' -and
            $watchdogHelperForeground -and $watchdogQueried -and $watchdogFaulted -and
            -not $watchdogActive -and $watchdogFaultPropagated -and
            $watchdogPostQueried -and $watchdogPostState -and
            -not $watchdogPostState.AnyDown -and $watchdogReleaseWait -and
            $watchdogReleaseWait.status -eq 'ok' -and $watchdogLatchCleared
        $watchdogAudit = [pscustomobject][ordered]@{
            helper_foreground_confirmed = [bool]$watchdogHelperForeground
            watchdog_query_succeeded = [bool]$watchdogQueried
            watchdog_active_after_focus_loss = [bool]$watchdogActive
            watchdog_faulted = [bool]$watchdogFaulted
            watchdog_fault_code = ConvertTo-ValidationFaultCode -Code $watchdogFaultCode
            fault_propagated_as_executor_fault = [bool]$watchdogFaultPropagated
            controlled_input_postcheck_passed = [bool]($watchdogPostQueried -and
                $watchdogPostState -and -not $watchdogPostState.AnyDown)
            observer_release_confirmed = [bool]($watchdogReleaseWait -and
                $watchdogReleaseWait.status -eq 'ok')
            latch_clear_succeeded = [bool]$watchdogLatchCleared
        }
        $watchdogAuditEvidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
            -RelativePath ('{0}/watchdog/focus-loss-release.json' -f $prefix) `
            -Value $watchdogAudit -Kind cleanup
        Add-ValidationEvidence -Context $Context -Evidence $watchdogAuditEvidence
        $watchdogEvidencePaths.Add($watchdogAuditEvidence.path)
        Add-ValidationNegativeResult -Context $Context `
            -Name 'hold_focus_loss_watchdog_release' -Passed ([bool]$watchdogPassed) `
            -Classification $(if ($watchdogFaulted) {
                    ConvertTo-ValidationFaultCode -Code $watchdogFaultCode
                }
                else { 'input_watchdog_fault_not_observed' }) `
            -Evidence @($watchdogEvidencePaths)

        $negativeStage = 'observer_contracts'
        $missingTarget = Find-UnrealVisibleTarget -Snapshot $read -TargetId 'missing_target' `
            -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
            -ExpectedObjectId 'movable_object'
        Add-ValidationNegativeResult -Context $Context -Name 'missing_visible_target' `
            -Passed ($missingTarget.status -eq 'ok' -and -not $missingTarget.result.found -and
                -not $missingTarget.result.usable -and
                $missingTarget.result.classification -ceq 'target_not_found' -and
                $missingTarget.target_visible -eq $false) `
            -Classification ([string]$missingTarget.result.classification)

        $missingStatePath = Join-Path $Context.run_root 'raw/negative/state/never-created.json'
        $unavailable = Read-UnrealEvaluationState -StatePath $missingStatePath `
            -ExpectedProcessToken 'process-unavailable' -MaxAgeMs $ObserverMaxAgeMs
        Add-ValidationNegativeResult -Context $Context -Name 'state_interface_unavailable' `
            -Passed ($unavailable.status -eq 'unsupported' -and $unavailable.unsupported -and
                -not $unavailable.executor_fault -and $unavailable.fault.domain -ceq 'capability') `
            -Classification ([string]$unavailable.fault.code)

        $timeoutPath = '{0}/waits/expected-timeout.json' -f $prefix
        $timeout = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
            -ExpectedRoundId ([string]$read.result.snapshot.round_id) `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
            -TimeoutMs 250 -IntervalMs 50 -MaxSamples 8 `
            -EvidenceRoot $Context.run_root -EvidencePath $timeoutPath `
            -Predicate { param($snapshot) return $false }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $timeout
        Add-ValidationNegativeResult -Context $Context -Name 'bounded_wait_timeout' `
            -Passed ($timeout.status -eq 'timeout' -and -not $timeout.executor_fault -and
                $timeout.result.termination_reason -in @('timeout', 'max_samples') -and
                [int]$timeout.result.sample_count -le 8) `
            -Classification ([string]$timeout.result.termination_reason) `
            -Evidence @($timeoutPath)

        $textPredicatePath = '{0}/waits/text-pass-rejected.json' -f $prefix
        $textPredicate = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
            -ExpectedRoundId ([string]$read.result.snapshot.round_id) `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
            -TimeoutMs 1000 -IntervalMs 50 -MaxSamples 8 `
            -EvidenceRoot $Context.run_root -EvidencePath $textPredicatePath `
            -Predicate { param($snapshot) return 'PASS' }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $textPredicate
        Add-ValidationNegativeResult -Context $Context `
            -Name 'predicate_text_pass_rejected' `
            -Passed ($textPredicate.status -eq 'executor_fault' -and
                $textPredicate.executor_fault -and
                $textPredicate.result.termination_reason -ceq 'predicate_fault' -and
                $textPredicate.fault.domain -ceq 'observer' -and
                $textPredicate.fault.code -ceq 'predicate_result_invalid') `
            -Classification $(if ($textPredicate.fault) {
                    [string]$textPredicate.fault.code
                }
                else { 'fault_missing' }) -Evidence @($textPredicatePath)

        $negativeStage = 'held_input_cleanup'
        $holdExceptionWaitPath = '{0}/waits/hold-exception-down.json' -f $prefix
        $holdException = Invoke-ValidationHeldAction `
            -DownAction { Start-UnrealKeyHold -Session $session -Key W } `
            -Body {
                $heldWait = Wait-UnrealEvaluationCondition -StatePath $statePath `
                    -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
                    -ExpectedRoundId ([string]$read.result.snapshot.round_id) `
                    -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
                    -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
                    -EvidenceRoot $Context.run_root -EvidencePath $holdExceptionWaitPath `
                    -Predicate { param($snapshot) return $snapshot.keyboard.w_down -eq $true }
                Add-ValidationOperationEvidence -Context $Context -OperationResult $heldWait
                Assert-ValidationOperationOk -Context $Context -OperationResult $heldWait `
                    -AffectedCapabilities @('HoldKey', 'WaitUntil')
                throw [InvalidOperationException]::new('controlled_hold_exception')
            } `
            -UpAction { Stop-UnrealKeyHold -Session $session -Key W -Cleanup }
        if ($holdException.down) {
            [void](Save-ValidationOperationReceipt -Context $Context `
                    -OperationResult $holdException.down `
                    -RelativePath ('{0}/receipts/hold-exception-down.json' -f $prefix))
        }
        if ($holdException.release) {
            [void](Save-ValidationOperationReceipt -Context $Context `
                    -OperationResult $holdException.release `
                    -RelativePath ('{0}/receipts/hold-exception-release.json' -f $prefix))
        }
        $releaseAfterExceptionPath = '{0}/waits/hold-exception-released.json' -f $prefix
        $releaseAfterException = Wait-UnrealEvaluationCondition -StatePath $statePath `
            -ExpectedProcessToken $processToken -ExpectedProcessId $targetProcessId `
            -ExpectedRoundId ([string]$read.result.snapshot.round_id) `
            -ExpectedObjectId 'movable_object' -MaxAgeMs $ObserverMaxAgeMs `
            -TimeoutMs 3000 -IntervalMs 50 -MaxSamples 80 `
            -EvidenceRoot $Context.run_root -EvidencePath $releaseAfterExceptionPath `
            -Predicate { param($snapshot) return $snapshot.keyboard.w_down -eq $false }
        Add-ValidationOperationEvidence -Context $Context -OperationResult $releaseAfterException
        Add-ValidationNegativeResult -Context $Context -Name 'hold_exception_release' `
            -Passed ($holdException.body_fault -and $holdException.release_attempted -and
                $holdException.release.status -eq 'ok' -and $releaseAfterException.status -eq 'ok') `
            -Classification $(if ($holdException.body_fault) {
                    [string]$holdException.body_fault.code
                }
                else { 'hold_exception_not_observed' }) `
            -Evidence @($holdExceptionWaitPath, $releaseAfterExceptionPath)

        $negativeStage = 'artifact_integrity'
        $existingRejected = $false
        try { [void](New-ValidationDirectory -Path $Context.run_root -RefuseExisting) }
        catch { $existingRejected = $_.Exception.Message -ceq 'validation_output_exists' }
        Add-ValidationNegativeResult -Context $Context -Name 'existing_run_refusal' `
            -Passed $existingRejected -Classification 'validation_output_exists'

        $missingEvidence = [pscustomobject]@{
            path = 'raw/negative/evidence/missing.json'
            sha256 = ('0' * 64)
            byte_length = 1
        }
        $missingCheck = Test-ValidationEvidenceIntegrity -RunRoot $Context.run_root `
            -Evidence $missingEvidence
        Add-ValidationNegativeResult -Context $Context -Name 'evidence_missing' `
            -Passed (-not $missingCheck.valid -and
                $missingCheck.classification -ceq 'evidence_missing') `
            -Classification ([string]$missingCheck.classification)

        $validEvidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
            -RelativePath 'raw/negative/evidence/integrity-source.json' `
            -Value ([pscustomobject]@{ fixture = 'integrity-control' }) -Kind report
        Add-ValidationEvidence -Context $Context -Evidence $validEvidence
        $corruptMetadata = [pscustomobject]@{
            path = $validEvidence.path
            sha256 = ('0' * 64)
            byte_length = $validEvidence.byte_length
        }
        $corruptCheck = Test-ValidationEvidenceIntegrity -RunRoot $Context.run_root `
            -Evidence $corruptMetadata
        Add-ValidationNegativeResult -Context $Context -Name 'evidence_corrupted' `
            -Passed (-not $corruptCheck.valid -and
                $corruptCheck.classification -ceq 'evidence_corrupted') `
            -Classification ([string]$corruptCheck.classification) `
            -Evidence @($validEvidence.path)

        $corruptStateEvidence = Write-ValidationTextArtifact -RunRoot $Context.run_root `
            -RelativePath 'raw/negative/state/corrupt.json' -Text '{broken' -Kind state `
            -MediaType 'application/json'
        Add-ValidationEvidence -Context $Context -Evidence $corruptStateEvidence
        $corruptStatePath = Join-Path $Context.run_root `
            ($corruptStateEvidence.path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $corruptRead = Read-UnrealEvaluationState -StatePath $corruptStatePath `
            -ExpectedProcessToken $processToken -MaxAgeMs $ObserverMaxAgeMs
        Add-ValidationNegativeResult -Context $Context -Name 'corrupt_state_classified' `
            -Passed ($corruptRead.status -eq 'executor_fault' -and
                $corruptRead.executor_fault -and -not $corruptRead.environment_fault -and
                $corruptRead.fault.domain -ceq 'observer' -and
                $corruptRead.fault.code -ceq 'snapshot_json_invalid') `
            -Classification ([string]$corruptRead.fault.code) `
            -Evidence @($corruptStateEvidence.path)

        $negativeStage = 'reparse_boundary'
        $reparsePassed = $false
        $reparseClassification = 'reparse_creation_failed'
        $targetDirectory = Join-Path $Context.run_root 'raw/negative/reparse/target'
        $linkDirectory = Join-Path $Context.run_root 'raw/negative/reparse/link'
        [void](Resolve-ValidationArtifactDestination -RunRoot $Context.run_root `
            -RelativePath 'raw/negative/reparse/target/placeholder.txt')
        if (-not [IO.Directory]::Exists($targetDirectory)) {
            [void](New-ValidationDirectory -Path $targetDirectory -RefuseExisting)
        }
        try {
            $link = New-Item -ItemType Junction -Path $linkDirectory -Target $targetDirectory `
                -ErrorAction Stop
            $unsafeChild = Join-Path $linkDirectory 'child.json'
            $reparsePassed = $null -eq (Get-ValidationSafeFullPath -Path $unsafeChild)
            $reparseClassification = if ($reparsePassed) {
                'reparse_ancestor_rejected'
            }
            else { 'reparse_ancestor_accepted' }
        }
        catch {
            $reparsePassed = $false
            $reparseClassification = 'reparse_creation_failed'
        }
        finally {
            if ([IO.Directory]::Exists($linkDirectory)) {
                try {
                    $linkItem = Get-Item -LiteralPath $linkDirectory -Force -ErrorAction Stop
                    $runLexical = [IO.Path]::GetFullPath($Context.run_root).TrimEnd(
                        [char[]]@([IO.Path]::DirectorySeparatorChar,
                            [IO.Path]::AltDirectorySeparatorChar)) +
                        [IO.Path]::DirectorySeparatorChar
                    $linkLexical = [IO.Path]::GetFullPath($linkDirectory)
                    if (($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and
                        $linkLexical.StartsWith($runLexical,
                            [StringComparison]::OrdinalIgnoreCase) -and
                        [IO.Path]::GetFileName($linkLexical) -ceq 'link') {
                        [IO.Directory]::Delete($linkDirectory, $false)
                    }
                }
                catch { }
            }
        }
        Add-ValidationNegativeResult -Context $Context -Name 'reparse_ancestor_refusal' `
            -Passed $reparsePassed -Classification $reparseClassification
    }
    catch {
        $negativeFailureEvidence = @()
        try {
            $diagnostic = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
                -RelativePath 'raw/negative/incomplete.json' `
                -Value ([pscustomobject][ordered]@{
                        stage = $negativeStage
                        exception_type = $_.Exception.GetType().FullName
                    }) -Kind report
            Add-ValidationEvidence -Context $Context -Evidence $diagnostic
            $negativeFailureEvidence = @($diagnostic.path)
        }
        catch { }
        Add-ValidationFault -Context $Context -Domain executor `
            -Code 'negative_matrix_incomplete' `
            -Message ('The negative validation matrix ended during the {0} stage before every case was classified.' -f
                $negativeStage) `
            -AffectedCapabilities @('Start', 'PressKey', 'HoldKey', 'ReleaseKey',
                'FindVisibleTarget', 'ReadState', 'WaitUntil') `
            -Evidence $negativeFailureEvidence
    }
    finally {
        if ($sessionActive -and $session) {
            $stopSequence = Invoke-ValidationStopWithRetry -Session $session `
                -GraceTimeoutMs $StopTimeoutMs
            $stop = $stopSequence.final
            try {
                if ($stopSequence.attempted_count -gt 1) {
                    [void](Save-ValidationOperationReceipt -Context $Context `
                            -OperationResult $stopSequence.attempts[0] `
                            -RelativePath ('{0}/receipts/stop-retryable-01.json' -f $prefix))
                }
                $stopReceipt = Save-ValidationOperationReceipt -Context $Context `
                    -OperationResult $stop -RelativePath ('{0}/receipts/stop.json' -f $prefix)
            }
            catch { $stopReceipt = $null }
            if ($stop.status -ne 'ok') {
                Add-ValidationFaultFromOperation -Context $Context -OperationResult $stop `
                    -AffectedCapabilities @('Stop')
            }
            [void](Add-ValidationStopCleanupRecord -Context $Context `
                    -Source 'negative' -StopResult $stop)
            if ($stop.status -eq 'ok') {
                $sessionActive = $false
                $stalePress = Invoke-UnrealPressKey -Session $session -Key Space -DurationMs 0
                try {
                    $staleReceipt = Save-ValidationOperationReceipt -Context $Context `
                        -OperationResult $stalePress `
                        -RelativePath ('{0}/receipts/stale-session-press.json' -f $prefix)
                    $staleEvidence = @($staleReceipt.path)
                }
                catch { $staleEvidence = @() }
                $stalePassed = $stalePress.status -eq 'executor_fault' -and
                    $stalePress.executor_fault -and -not $stalePress.input_dispatched -and
                    $stalePress.fault.domain -ceq 'executor' -and
                    $stalePress.fault.code -ceq 'session_not_found' -and
                    -not $stalePress.PSObject.Properties['game_failure']
                Add-ValidationNegativeResult -Context $Context `
                    -Name 'executor_fault_not_game_failure' -Passed $stalePassed `
                    -Classification $(if ($stalePress.fault) {
                            ConvertTo-ValidationFaultCode -Code ([string]$stalePress.fault.code)
                        }
                        else { 'fault_missing' }) -Evidence $staleEvidence
            }
        }

        $completedNames = @($Context.negative_results | ForEach-Object { $_.name })
        foreach ($required in Get-ValidationNegativePlan) {
            if ($required -notin $completedNames) {
                Add-ValidationNegativeResult -Context $Context -Name $required -Passed $false `
                    -Classification 'not_executed'
            }
        }
        try {
            $negativeEvidence = Write-ValidationJsonArtifact -RunRoot $Context.run_root `
                -RelativePath 'raw/negative/results.json' `
                -Value (ConvertTo-ValidationPublicValue -Value @($Context.negative_results) `
                    -SensitiveValues $Context.sensitive_values) -Kind report
            Add-ValidationEvidence -Context $Context -Evidence $negativeEvidence
        }
        catch { }
    }
}

function Get-ValidationCapabilitySummary {
    param([Parameter(Mandatory)][object]$Context)

    $results = [Collections.Generic.List[object]]::new()
    foreach ($name in $script:CapabilityNames) {
        $entries = @($Context.ledger[$name])
        $attempts = $entries.Count
        $verifiedSuccesses = [Collections.Generic.List[object]]::new()
        $invalidEvidenceClassifications = [Collections.Generic.List[string]]::new()
        foreach ($entry in @($entries | Where-Object { $_.success })) {
            $paths = @($entry.evidence | Where-Object {
                    Test-ValidationRelativePath -Path ([string]$_)
                } | Select-Object -Unique)
            $entryEvidenceValid = $paths.Count -gt 0
            foreach ($path in $paths) {
                if (-not $Context.evidence_by_path.ContainsKey([string]$path)) {
                    $entryEvidenceValid = $false
                    $invalidEvidenceClassifications.Add('evidence_metadata_missing')
                    continue
                }
                $integrity = Test-ValidationEvidenceIntegrity -RunRoot $Context.run_root `
                    -Evidence $Context.evidence_by_path[[string]$path]
                if (-not $integrity.valid) {
                    $entryEvidenceValid = $false
                    $invalidEvidenceClassifications.Add([string]$integrity.classification)
                }
            }
            if ($entryEvidenceValid) { $verifiedSuccesses.Add($entry) }
        }
        $successes = $verifiedSuccesses.Count
        $status = if ($attempts -eq 0) { 'not_tested' }
        elseif ($successes -eq $attempts -and $successes -ge 3) { 'available' }
        elseif ($successes -gt 0) { 'unstable' }
        else { 'unavailable' }
        $evidence = @($entries | ForEach-Object { @($_.evidence) } |
                Where-Object { Test-ValidationRelativePath -Path $_ } |
                Select-Object -Unique)
        $limitations = @($entries | ForEach-Object { $_.limitation } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object {
                    Protect-ValidationText -Text ([string]$_) `
                        -SensitiveValues $Context.sensitive_values
                } | Select-Object -Unique)
        if ($name -eq 'Capture') {
            $limitations += 'Capture proves the current physical client frame and sampled exposure checks; it is not a pixel-complete proof that no small occluder exists.'
        }
        if ($invalidEvidenceClassifications.Count -gt 0) {
            $limitations += 'One or more otherwise successful attempts had missing or invalid evidence integrity and were not counted as evidenced successes.'
        }
        $results.Add([pscustomobject][ordered]@{
                name = $name
                status = $status
                attempts = $attempts
                successes = $successes
                evidence = $evidence
                limitations = @($limitations | Select-Object -Unique)
            })
    }
    return @($results)
}

function Test-ValidationPrivacyText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string[]]$SensitiveValues = @()
    )

    $findings = [Collections.Generic.List[object]]::new()
    foreach ($value in @($SensitiveValues | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -ge 3
            } | Sort-Object Length -Descending -Unique)) {
        $escapedValue = [regex]::Escape($value)
        $pattern = if ($value.IndexOfAny([char[]]@(
                    [IO.Path]::DirectorySeparatorChar,
                    [IO.Path]::AltDirectorySeparatorChar, ':')) -ge 0) {
            $escapedValue
        }
        else { '(?<![A-Za-z0-9_.-])' + $escapedValue + '(?![A-Za-z0-9_.-])' }
        if ([regex]::IsMatch($Text, $pattern,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $findings.Add([pscustomobject]@{ category = 'local_identifier'; match = '[REDACTED]' })
        }
    }
    $patterns = [ordered]@{
        absolute_path = '(?i)(?<![A-Za-z0-9_.-])[A-Z]:[\\/]|\\\\[^\\/\s]+[\\/]'
        username = '(?i)\\(?:Users|home)\\[^\\/\s]+'
        device_name = '(?i)\b(?:COMPUTERNAME|HOSTNAME)\b\s*[:=]\s*[^\s,;]+'
        credential = '(?i)\b(password|secret|api[_-]?key|authorization)\b\s*[:=]\s*(?!\[REDACTED\])[^\s,;]+'
        private_key = '(?i)-----BEGIN [^-\r\n]*PRIVATE KEY-----'
    }
    foreach ($entry in $patterns.GetEnumerator()) {
        $matches = [regex]::Matches($Text, $entry.Value)
        foreach ($match in $matches) {
            $findings.Add([pscustomobject]@{
                    category = [string]$entry.Key
                    match = '[REDACTED]'
                })
        }
    }
    return [pscustomobject][ordered]@{
        passed = $findings.Count -eq 0
        finding_count = $findings.Count
        checked_patterns = @('absolute_path', 'username', 'device_name', 'credential', 'private_key')
        findings = @($findings)
    }
}

function Test-ValidationEvidenceCollection {
    param([Parameter(Mandatory)][object]$Context)

    $verifiedPaths = [Collections.Generic.List[string]]::new()
    $integrityClassifications = [Collections.Generic.List[string]]::new()
    $privacyFindingCount = 0
    $privacyUnsafePaths = [Collections.Generic.List[string]]::new()
    $privacyScannedPaths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    $textEvidenceCount = 0
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    foreach ($evidence in @($Context.evidence_by_path.Values | Sort-Object path)) {
        $integrity = Test-ValidationEvidenceIntegrity -RunRoot $Context.run_root `
            -Evidence $evidence
        if (-not $integrity.valid) {
            $integrityClassifications.Add([string]$integrity.classification)
            continue
        }
        $verifiedPaths.Add([string]$evidence.path)

        $mediaType = if ($evidence.PSObject.Properties['media_type']) {
            [string]$evidence.media_type
        }
        else { '' }
        if ($mediaType -cnotmatch '^(?:text/[^;]+|application/(?:json|[^;]+\+json|xml|[^;]+\+xml|yaml|x-yaml))(?:;|$)') {
            continue
        }
        [void]$privacyScannedPaths.Add([string]$evidence.path)
        if ([long]$evidence.byte_length -gt 16777216) {
            $integrityClassifications.Add('evidence_text_size_limit_exceeded')
            ++$privacyFindingCount
            $privacyUnsafePaths.Add([string]$evidence.path)
            continue
        }
        ++$textEvidenceCount
        try {
            $nativeRelative = ([string]$evidence.path).Replace(
                '/', [IO.Path]::DirectorySeparatorChar)
            $full = [IO.Path]::GetFullPath([IO.Path]::Combine(
                    $Context.run_root, $nativeRelative))
            $text = $encoding.GetString([IO.File]::ReadAllBytes($full))
            $scan = Test-ValidationPrivacyText -Text $text `
                -SensitiveValues $Context.sensitive_values
            $privacyFindingCount += [int]$scan.finding_count
            if (-not $scan.passed) {
                $privacyUnsafePaths.Add([string]$evidence.path)
            }
        }
        catch {
            [void]$verifiedPaths.Remove([string]$evidence.path)
            $integrityClassifications.Add('evidence_text_unreadable')
            ++$privacyFindingCount
            $privacyUnsafePaths.Add([string]$evidence.path)
        }
    }

    $rawRoot = Join-Path $Context.run_root 'raw'
    if ([IO.Directory]::Exists($rawRoot)) {
        if (-not (Test-ValidationAncestorChainSafe -Path $rawRoot)) {
            $integrityClassifications.Add('raw_evidence_root_unsafe')
            ++$privacyFindingCount
        }
        else {
            $enumeration = [IO.EnumerationOptions]::new()
            $enumeration.RecurseSubdirectories = $true
            $enumeration.IgnoreInaccessible = $false
            $enumeration.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
            $textExtensions = @(
                '.json', '.jsonl', '.txt', '.log', '.md', '.xml', '.yaml', '.yml',
                '.csv', '.tsv', '.ini', '.cfg', '.uproject', '.cs', '.cpp', '.h',
                '.hpp', '.ps1', '.psm1')
            try {
                foreach ($full in [IO.Directory]::EnumerateFiles($rawRoot, '*', $enumeration)) {
                    $relative = [IO.Path]::GetRelativePath($Context.run_root, $full).
                        Replace([IO.Path]::DirectorySeparatorChar, '/')
                    if ($privacyScannedPaths.Contains($relative) -or
                        [IO.Path]::GetExtension($full).ToLowerInvariant() -notin $textExtensions) {
                        continue
                    }
                    [void]$privacyScannedPaths.Add($relative)
                    ++$textEvidenceCount
                    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
                    if ([long]$item.Length -gt 16777216) {
                        $integrityClassifications.Add('raw_text_size_limit_exceeded')
                        ++$privacyFindingCount
                        $privacyUnsafePaths.Add($relative)
                        continue
                    }
                    try {
                        $text = $encoding.GetString([IO.File]::ReadAllBytes($full))
                        $scan = Test-ValidationPrivacyText -Text $text `
                            -SensitiveValues $Context.sensitive_values
                        $privacyFindingCount += [int]$scan.finding_count
                        if (-not $scan.passed) { $privacyUnsafePaths.Add($relative) }
                    }
                    catch {
                        $integrityClassifications.Add('raw_text_unreadable')
                        ++$privacyFindingCount
                        $privacyUnsafePaths.Add($relative)
                    }
                }
            }
            catch {
                $integrityClassifications.Add('raw_text_enumeration_failed')
                ++$privacyFindingCount
            }
        }
    }

    return [pscustomobject][ordered]@{
        integrity_passed = $integrityClassifications.Count -eq 0
        integrity_failure_count = $integrityClassifications.Count
        integrity_failure_classifications = @($integrityClassifications |
                Select-Object -Unique)
        verified_paths = @($verifiedPaths)
        evidence_count = @($Context.evidence_by_path.Values).Count
        text_evidence_count = $textEvidenceCount
        privacy_unsafe_paths = @($privacyUnsafePaths | Select-Object -Unique)
        privacy_scan = [pscustomobject][ordered]@{
            passed = $privacyFindingCount -eq 0
            finding_count = $privacyFindingCount
            checked_patterns = @(
                'absolute_path', 'username', 'device_name', 'credential', 'private_key')
        }
    }
}

function Invoke-ValidationRawPrivacyFailClosed {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string[]]$RelativePaths
    )

    $removedCount = 0
    foreach ($relativePath in @($RelativePaths | Select-Object -Unique)) {
        if (-not (Test-ValidationRelativePath -Path $relativePath) -or
            -not $relativePath.StartsWith('raw/', [StringComparison]::Ordinal)) {
            throw [InvalidOperationException]::new('validation_privacy_target_invalid')
        }
        $full = [IO.Path]::GetFullPath([IO.Path]::Combine(
                $Context.run_root,
                $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)))
        if (-not (Test-ValidationPathWithinRoot -Root $Context.run_root -Path $full) -or
            -not [IO.File]::Exists($full) -or
            -not (Test-ValidationAncestorChainSafe -Path $full)) {
            throw [InvalidOperationException]::new('validation_privacy_target_unsafe')
        }
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw [InvalidOperationException]::new('validation_privacy_target_unsafe')
        }
        [IO.File]::Delete($full)
        if ([IO.File]::Exists($full)) {
            throw [InvalidOperationException]::new('validation_privacy_delete_failed')
        }
        [void]$Context.evidence_by_path.Remove($relativePath)
        ++$removedCount
    }
    return [pscustomobject][ordered]@{
        passed = $removedCount -eq @($RelativePaths | Select-Object -Unique).Count
        removed_count = $removedCount
    }
}

function Get-ValidationCleanupSummary {
    param(
        [Parameter(Mandatory)][object]$Context,
        [bool]$NativePostCheckPassed,
        [string[]]$NativePostDetails = @()
    )

    $records = @($Context.cleanup_records)
    $keysReleased = $records.Count -gt 0 -and
        @($records | Where-Object { -not $_.keys_released }).Count -eq 0
    $buttonsReleased = $records.Count -gt 0 -and
        @($records | Where-Object { -not $_.mouse_buttons_released }).Count -eq 0
    $cursorRestored = $records.Count -gt 0 -and
        @($records | Where-Object { -not $_.cursor_restored }).Count -eq 0
    $treeClean = $records.Count -gt 0 -and
        @($records | Where-Object { -not $_.process_tree_clean }).Count -eq 0
    $details = @(
        'Every acquired session was finalized through Stop or Reopen cleanup.',
        'Job active-process accounting was checked after each session cleanup.',
        'The controlled key/button post-state was queried after the full run.'
    ) + @($NativePostDetails)
    return [pscustomobject][ordered]@{
        passed = ($keysReleased -and $buttonsReleased -and $cursorRestored -and
            $treeClean -and $NativePostCheckPassed)
        keys_released = ($keysReleased -and $NativePostCheckPassed)
        mouse_buttons_released = ($buttonsReleased -and $NativePostCheckPassed)
        cursor_restored = $cursorRestored
        process_tree_clean = $treeClean
        details = @($details | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique)
    }
}

function Test-ValidationSummaryContract {
    param([Parameter(Mandatory)][object]$Summary)

    $errors = [Collections.Generic.List[string]]::new()
    try {
        $schemaPath = Join-Path $PSScriptRoot `
            '../executor/schemas/validation-summary.schema.json'
        $schemaFull = Get-ValidationSafeFullPath -Path $schemaPath -RequireLeaf
        $schemaJson = $Summary | ConvertTo-Json -Depth 64
        $schemaValid = $schemaFull -and (Test-Json -Json $schemaJson `
                -SchemaFile $schemaFull -ErrorAction Stop -WarningAction SilentlyContinue)
        if (-not $schemaValid) { $errors.Add('json_schema') }
    }
    catch {
        $errors.Add('json_schema')
    }
    if ($Summary.schema_version -cne '1.0.0') { $errors.Add('schema_version') }
    if ($Summary.run_id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { $errors.Add('run_id') }
    if ([string]$Summary.engine.name -cne 'Unreal Engine' -or
        [string]$Summary.engine.version -notmatch '^5\.6(?:\.[0-9]+)?$') {
        $errors.Add('engine')
    }
    $runtimeIdentityProperty = $Summary.PSObject.Properties['runtime_identity']
    if (-not $runtimeIdentityProperty -or -not $runtimeIdentityProperty.Value) {
        $errors.Add('runtime_identity')
    }
    else {
        $runtimeIdentity = $runtimeIdentityProperty.Value
        $requiredIdentityNames = @(
            'executor_sha256', 'observer_sha256', 'validation_command_sha256')
        $actualIdentityNames = @($runtimeIdentity.PSObject.Properties.Name)
        if ($actualIdentityNames.Count -ne $requiredIdentityNames.Count -or
            @($actualIdentityNames | Where-Object { $_ -cnotin $requiredIdentityNames }).Count -gt 0 -or
            @($requiredIdentityNames | Where-Object { $_ -cnotin $actualIdentityNames }).Count -gt 0) {
            $errors.Add('runtime_identity_shape')
        }
        $currentRuntimeIdentity = $null
        try { $currentRuntimeIdentity = Get-ValidationCurrentRuntimeIdentity }
        catch { $errors.Add('runtime_identity_current_files') }
        foreach ($name in $requiredIdentityNames) {
            $property = $runtimeIdentity.PSObject.Properties[$name]
            if (-not $property -or [string]$property.Value -cnotmatch '^[0-9a-f]{64}$') {
                $errors.Add('runtime_identity_' + $name)
            }
            elseif ($currentRuntimeIdentity -and
                [string]$property.Value -cne [string]$currentRuntimeIdentity.$name) {
                $errors.Add('runtime_identity_mismatch_' + $name)
            }
        }
    }
    $capabilities = @($Summary.capabilities)
    if ($capabilities.Count -ne $script:CapabilityNames.Count) {
        $errors.Add('capability_count')
    }
    foreach ($name in $script:CapabilityNames) {
        if (@($capabilities | Where-Object { $_.name -ceq $name }).Count -ne 1) {
            $errors.Add('capability_identity_' + $name)
        }
    }
    foreach ($capability in $capabilities) {
        if ([int]$capability.successes -gt [int]$capability.attempts) {
            $errors.Add('successes_exceed_attempts_' + $capability.name)
        }
        if ($capability.status -eq 'available' -and
            ([int]$capability.attempts -lt 3 -or [int]$capability.successes -lt 3 -or
                @($capability.evidence).Count -lt 1)) {
            $errors.Add('available_without_evidence_' + $capability.name)
        }
        if ($capability.status -eq 'not_tested' -and
            ([int]$capability.attempts -ne 0 -or [int]$capability.successes -ne 0)) {
            $errors.Add('not_tested_with_attempts_' + $capability.name)
        }
    }
    if ($Summary.overall_status -eq 'passed') {
        if (-not $Summary.formal_scoring_ready -or -not $Summary.privacy_scan.passed -or
            [int]$Summary.privacy_scan.finding_count -ne 0 -or -not $Summary.cleanup.passed) {
            $errors.Add('passed_invariant')
        }
        if (@($capabilities | Where-Object { $_.status -ne 'available' }).Count -gt 0) {
            $errors.Add('passed_with_unavailable_capability')
        }
    }
    return [pscustomobject][ordered]@{
        valid = $errors.Count -eq 0
        errors = @($errors)
    }
}

function Test-ValidationStopCleanupContract {
    param([AllowNull()][object]$StopResult)

    if (-not $StopResult -or -not $StopResult.PSObject.Properties['status'] -or
        -not $StopResult.PSObject.Properties['result'] -or -not $StopResult.result -or
        -not $StopResult.result.PSObject.Properties['input_cleanup'] -or
        -not $StopResult.result.input_cleanup) {
        return [pscustomobject][ordered]@{
            valid = $false
            retryable = $false
            session_retained_for_cleanup_retry = $false
            classification = 'stop_cleanup_contract_missing'
        }
    }
    $cleanup = $StopResult.result.input_cleanup
    foreach ($required in @('all_released', 'controlled_input_postcheck_passed',
            'input_watchdog_stopped', 'input_watchdog_faulted',
            'input_watchdog_stop_attempts')) {
        if (-not $cleanup.PSObject.Properties[$required]) {
            return [pscustomobject][ordered]@{
                valid = $false
                retryable = $false
                session_retained_for_cleanup_retry = $false
                classification = 'stop_cleanup_contract_missing'
            }
        }
    }
    $retryable = [bool]($StopResult.PSObject.Properties['fault'] -and
        $StopResult.fault -and $StopResult.fault.PSObject.Properties['retryable'] -and
        $StopResult.fault.retryable)
    $retained = [bool]($StopResult.result.PSObject.Properties[
            'session_retained_for_cleanup_retry'] -and
        $StopResult.result.session_retained_for_cleanup_retry)
    $valid = if ($StopResult.status -eq 'ok') {
        [bool]$cleanup.all_released -and
            [bool]$cleanup.controlled_input_postcheck_passed -and
            [bool]$cleanup.input_watchdog_stopped -and
            [int]$cleanup.input_watchdog_stop_attempts -ge 1 -and -not $retained
    }
    else {
        $StopResult.status -eq 'executor_fault' -and $retryable -and $retained -and
        [string]$StopResult.fault.code -in @('input_cleanup_failed',
                'input_watchdog_stop_failed')
    }
    return [pscustomobject][ordered]@{
        valid = [bool]$valid
        retryable = [bool]$retryable
        session_retained_for_cleanup_retry = [bool]$retained
        classification = if ($valid) { 'verified' }
        else { 'stop_cleanup_contract_invalid' }
    }
}

function Invoke-ValidationStopWithRetry {
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][int]$GraceTimeoutMs,
        [AllowNull()][scriptblock]$StopAction
    )

    $invokeStop = if ($StopAction) { $StopAction }
    else {
        { param($value, $timeout)
            Stop-UnrealEvaluationSession -Session $value -GraceTimeoutMs $timeout
        }
    }
    $attempts = [Collections.Generic.List[object]]::new()
    $first = & $invokeStop $Session $GraceTimeoutMs
    $attempts.Add($first)
    $firstContract = Test-ValidationStopCleanupContract -StopResult $first
    if ($first -and $first.status -eq 'executor_fault' -and
        $firstContract.valid -and $firstContract.retryable -and
        $firstContract.session_retained_for_cleanup_retry) {
        $attempts.Add((& $invokeStop $Session $GraceTimeoutMs))
    }
    return [pscustomobject][ordered]@{
        attempted_count = $attempts.Count
        recovered_after_retry = $attempts.Count -gt 1 -and
            $attempts[$attempts.Count - 1].status -eq 'ok'
        attempts = @($attempts)
        final = $attempts[$attempts.Count - 1]
    }
}

function Add-ValidationStopCleanupRecord {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Source,
        [AllowNull()][object]$StopResult
    )

    $contract = Test-ValidationStopCleanupContract -StopResult $StopResult
    $cleanupResult = if ($StopResult -and $StopResult.PSObject.Properties['result']) {
        $StopResult.result
    }
    else { $null }
    $inputCleanup = if ($cleanupResult -and
        $cleanupResult.PSObject.Properties['input_cleanup']) {
        $cleanupResult.input_cleanup
    }
    else { $null }
    $Context.cleanup_records.Add([pscustomobject][ordered]@{
            source = $Source
            stop_status = if ($StopResult -and
                $StopResult.PSObject.Properties['status']) {
                [string]$StopResult.status
            }
            else { 'missing' }
            stop_contract_valid = [bool]$contract.valid
            stop_retryable = [bool]$contract.retryable
            session_retained_for_cleanup_retry = [bool](
                $contract.session_retained_for_cleanup_retry)
            keys_released = [bool]($contract.valid -and $inputCleanup -and
                $inputCleanup.controlled_input_postcheck_passed -and
                $inputCleanup.input_watchdog_stopped)
            mouse_buttons_released = [bool]($contract.valid -and $inputCleanup -and
                $inputCleanup.controlled_input_postcheck_passed -and
                $inputCleanup.input_watchdog_stopped)
            cursor_restored = [bool]($contract.valid -and $inputCleanup -and
                $inputCleanup.cursor_restored)
            process_tree_clean = [bool]($contract.valid -and $cleanupResult -and
                $cleanupResult.process_exited -and
                [int]$cleanupResult.job_active_process_count_after_wait -eq 0)
        })
    return $contract
}

function New-ValidationInvalidSummaryFallback {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [AllowNull()][string]$EngineVersion,
        [Parameter(Mandatory)][string]$FaultCode,
        [Parameter(Mandatory)][string]$FaultMessage,
        [ValidateRange(0, [int]::MaxValue)][int]$PrivacyFindingCount = 0,
        [AllowNull()][object]$Cleanup
    )

    $safeEngineVersion = if ($EngineVersion -match '^5\.6(?:\.[0-9]+)?$') {
        $EngineVersion
    }
    else { '5.6.0' }
    $cleanupPassed = [bool]($Cleanup -and $Cleanup.PSObject.Properties['passed'] -and
        $Cleanup.passed)
    $keysReleased = [bool]($Cleanup -and
        $Cleanup.PSObject.Properties['keys_released'] -and $Cleanup.keys_released)
    $buttonsReleased = [bool]($Cleanup -and
        $Cleanup.PSObject.Properties['mouse_buttons_released'] -and
        $Cleanup.mouse_buttons_released)
    $cursorRestored = [bool]($Cleanup -and
        $Cleanup.PSObject.Properties['cursor_restored'] -and $Cleanup.cursor_restored)
    $treeClean = [bool]($Cleanup -and
        $Cleanup.PSObject.Properties['process_tree_clean'] -and
        $Cleanup.process_tree_clean)
    return [pscustomobject][ordered]@{
        schema_version = $script:ValidationSchemaVersion
        run_id = $RunId
        generated_utc = [DateTime]::UtcNow.ToString('o',
            [Globalization.CultureInfo]::InvariantCulture)
        engine = [pscustomobject][ordered]@{
            name = 'Unreal Engine'
            version = $safeEngineVersion
        }
        runtime_identity = Get-ValidationCurrentRuntimeIdentity
        overall_status = 'invalid'
        formal_scoring_ready = $false
        conclusion = 'The Unreal public executor is not ready for formal dynamic scoring.'
        capabilities = @($script:CapabilityNames | ForEach-Object {
                [pscustomobject][ordered]@{
                    name = $_
                    status = 'not_tested'
                    attempts = 0
                    successes = 0
                    evidence = @()
                    limitations = @('The detailed result was withheld by the validation safety gate.')
                }
            })
        faults = @([pscustomobject][ordered]@{
                domain = 'evidence'
                code = ConvertTo-ValidationFaultCode -Code $FaultCode
                message = $FaultMessage
                retryable = $false
                affected_capabilities = @($script:CapabilityNames)
                evidence = @()
            })
        evidence = @()
        privacy_scan = [pscustomobject][ordered]@{
            passed = $false
            finding_count = $PrivacyFindingCount
            checked_patterns = @(
                'absolute_path', 'username', 'device_name', 'credential', 'private_key')
        }
        cleanup = [pscustomobject][ordered]@{
            passed = $cleanupPassed
            keys_released = $keysReleased
            mouse_buttons_released = $buttonsReleased
            cursor_restored = $cursorRestored
            process_tree_clean = $treeClean
            details = @('Cleanup booleans were retained; detailed local records were withheld by the validation safety gate.')
        }
    }
}

function Get-ValidationReportText {
    param(
        [Parameter(Mandatory)][object]$Summary,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Attempts,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Controls,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$NegativeResults
    )

    $builder = [Text.StringBuilder]::new()
    [void]$builder.AppendLine('# Unreal Engine 5.6 Public Evaluation Executor Validation Report')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine(('Run ID:`{0}`' -f $Summary.run_id))
    [void]$builder.AppendLine()
    [void]$builder.AppendLine(('Generated at (UTC):`{0}`' -f $Summary.generated_utc))
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('## Conclusion')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine($Summary.conclusion)
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('This report verifies engine startup, player input, read-only observation, evidence, Restart, Reopen, and cleanup only. It contains no game requirements, evaluation trajectories, checkpoint scores, or semantic judgments.')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('## Capability matrix')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('| Capability | Status | Attempts | Successes | Evidence count |')
    [void]$builder.AppendLine('|---|---:|---:|---:|---:|')
    foreach ($capability in $Summary.capabilities) {
        $capabilityLine = '| {0} | {1} | {2} | {3} | {4} |' -f ([object[]]@(
                $capability.name,
                $capability.status,
                $capability.attempts,
                $capability.successes,
                [int]@($capability.evidence).Count))
        [void]$builder.AppendLine($capabilityLine)
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('## Core-loop repetitions')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('| Round | Completed | Terminal stage |')
    [void]$builder.AppendLine('|---:|---:|---|')
    foreach ($attempt in $Attempts) {
        $attemptLine = '| {0} | {1} | {2} |' -f ([object[]]@(
                $attempt.attempt_index,
                ([string][bool]$attempt.completed).ToLowerInvariant(),
                $attempt.terminal_stage))
        [void]$builder.AppendLine($attemptLine)
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('## Observer noninterference control')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('| Round | Result | Classification |')
    [void]$builder.AppendLine('|---:|---:|---|')
    foreach ($control in $Controls) {
        $controlLine = '| {0} | {1} | {2} |' -f ([object[]]@(
                $control.attempt_index,
                ([string][bool]$control.passed).ToLowerInvariant(),
                $control.classification))
        [void]$builder.AppendLine($controlLine)
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('This control compares visible pixel-change boundaries, scale, and resolution in a fixed HUD region after public Space input and verifies that disabled mode emits no state files. HUD text is not used as a gameplay verdict.')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('## Negative tests')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('| Test | Result | Classification |')
    [void]$builder.AppendLine('|---|---:|---|')
    foreach ($negative in $NegativeResults) {
        $negativeLine = '| {0} | {1} | {2} |' -f ([object[]]@(
                $negative.name,
                ([string][bool]$negative.passed).ToLowerInvariant(),
                $negative.classification))
        [void]$builder.AppendLine($negativeLine)
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('## Cleanup and privacy')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine(('- Input and process cleanup:`{0}`' -f
            ([string][bool]$Summary.cleanup.passed).ToLowerInvariant()))
    $privacyLine = '- Redaction scan:`{0}`,Finding count:`{1}`' -f ([object[]]@(
            ([string][bool]$Summary.privacy_scan.passed).ToLowerInvariant(),
            $Summary.privacy_scan.finding_count))
    [void]$builder.AppendLine($privacyLine)
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('Raw screenshots, state, wait samples, and redacted logs are stored under raw/ in this run directory and ignored by Git. summary.json and this report contain run-relative evidence paths only.')
    return $builder.ToString()
}

function Publish-ValidationLatest {
    param(
        [Parameter(Mandatory)][string]$ValidationRoot,
        [Parameter(Mandatory)][byte[]]$SummaryBytes,
        [Parameter(Mandatory)][byte[]]$ReportBytes
    )

    $validationFull = Get-ValidationSafeFullPath -Path $ValidationRoot -RequireContainer
    if (-not $validationFull) {
        throw [InvalidOperationException]::new('validation_latest_root_unsafe')
    }
    $mutexHash = Get-ValidationSha256 -Bytes `
        ([Text.UTF8Encoding]::new($false).GetBytes($validationFull.ToLowerInvariant()))
    $mutex = [Threading.Mutex]::new(
        $false, ('Local\VibeGaming.UnrealValidationLatest.' + $mutexHash.Substring(0, 32)))
    $lockTaken = $false
    $latest = $null
    $staging = $null
    $backup = $null
    $oldGenerationMoved = $false
    $newGenerationPublished = $false
    try {
        try { $lockTaken = $mutex.WaitOne(10000) }
        catch [Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) {
            throw [InvalidOperationException]::new('validation_latest_publish_busy')
        }

        $latest = Join-Path $validationFull 'latest'
        if ([IO.File]::Exists($latest)) {
            throw [InvalidOperationException]::new('validation_latest_target_invalid')
        }
        if ([IO.Directory]::Exists($latest)) {
            if (-not (Test-ValidationAncestorChainSafe -Path $latest)) {
                throw [InvalidOperationException]::new('validation_latest_unsafe')
            }
            $allowedNames = @('summary.json', 'VALIDATION_REPORT.md')
            foreach ($item in @(Get-ChildItem -LiteralPath $latest -Force -ErrorAction Stop)) {
                if ($item.PSIsContainer -or
                    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    $item.Name -notin $allowedNames) {
                    throw [InvalidOperationException]::new('validation_latest_unsafe')
                }
            }
        }

        $generationToken = [guid]::NewGuid().ToString('N')
        $staging = Join-Path $validationFull ('latest-staging-{0}.tmp' -f $generationToken)
        $backup = Join-Path $validationFull ('latest-backup-{0}.tmp' -f $generationToken)
        if (-not (Test-ValidationPathWithinRoot -Root $validationFull -Path $staging) -or
            -not (Test-ValidationPathWithinRoot -Root $validationFull -Path $backup)) {
            throw [InvalidOperationException]::new('validation_latest_generation_invalid')
        }
        [void](New-ValidationDirectory -Path $staging -RefuseExisting)
        $summaryTarget = Join-Path $staging 'summary.json'
        $reportTarget = Join-Path $staging 'VALIDATION_REPORT.md'
        [IO.File]::WriteAllBytes($summaryTarget, $SummaryBytes)
        [IO.File]::WriteAllBytes($reportTarget, $ReportBytes)

        if ([IO.Directory]::Exists($latest)) {
            [IO.Directory]::Move($latest, $backup)
            $oldGenerationMoved = $true
        }
        try {
            [IO.Directory]::Move($staging, $latest)
            $staging = $null
            $newGenerationPublished = $true
        }
        catch {
            if ($oldGenerationMoved -and -not [IO.Directory]::Exists($latest) -and
                [IO.Directory]::Exists($backup)) {
                [IO.Directory]::Move($backup, $latest)
                $backup = $null
                $oldGenerationMoved = $false
            }
            throw [InvalidOperationException]::new('validation_latest_publish_failed')
        }

        if ($backup -and [IO.Directory]::Exists($backup)) {
            foreach ($name in @('summary.json', 'VALIDATION_REPORT.md')) {
                $oldFile = Join-Path $backup $name
                if ([IO.File]::Exists($oldFile)) { [IO.File]::Delete($oldFile) }
            }
            [IO.Directory]::Delete($backup, $false)
            $backup = $null
            $oldGenerationMoved = $false
        }
    }
    finally {
        if (-not $newGenerationPublished -and $oldGenerationMoved -and $backup -and
            $latest -and -not [IO.Directory]::Exists($latest) -and
            [IO.Directory]::Exists($backup)) {
            try {
                [IO.Directory]::Move($backup, $latest)
                $backup = $null
            }
            catch { }
        }
        if ($staging -and [IO.Directory]::Exists($staging)) {
            try {
                foreach ($name in @('summary.json', 'VALIDATION_REPORT.md')) {
                    $stagedFile = Join-Path $staging $name
                    if ([IO.File]::Exists($stagedFile)) { [IO.File]::Delete($stagedFile) }
                }
                [IO.Directory]::Delete($staging, $false)
            }
            catch { }
        }
        if ($lockTaken) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        $mutex.Dispose()
    }
}

function Invoke-UnrealCapabilityValidation {
    [CmdletBinding()]
    param(
        [ValidatePattern('^run-[A-Za-z0-9][A-Za-z0-9._-]{0,119}$')]
        [string]$RunId,
        [string]$EngineRoot,
        [string]$EditorPath,
        [string]$LauncherManifestPath,
        [ValidateRange(3, 10)][int]$RepeatCount = 3,
        [ValidateRange(1000, 300000)][int]$StartTimeoutMs = 90000,
        [ValidateRange(1000, 1800000)][int]$BuildTimeoutMs = 900000,
        [ValidateRange(100, 120000)][int]$StopTimeoutMs = 15000,
        [ValidateRange(100, 10000)][int]$ObserverMaxAgeMs = 2000,
        [ValidateRange(50, 5000)][int]$ControlFeedbackBoundaryMs = 1500,
        [switch]$NoPublishLatest
    )

    if (-not $IsWindows) {
        throw [PlatformNotSupportedException]::new('The Unreal capability validator requires Windows.')
    }
    $commandRoot = $PSScriptRoot
    $unrealRoot = [IO.Path]::GetFullPath((Join-Path $commandRoot '..'))
    $engineDirectory = [IO.Path]::GetFullPath((Join-Path $unrealRoot '..'))
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $engineDirectory '..'))
    $fixtureSource = Join-Path $unrealRoot 'fixtures/minimal-interface'
    $validationRoot = Join-Path $unrealRoot 'validation'
    $executorModule = Join-Path $unrealRoot 'executor/UnrealEvaluationExecutor.psm1'
    $observerModule = Join-Path $unrealRoot 'observer/UnrealEvaluationObserver.psm1'
    if (-not (Get-ValidationSafeFullPath -Path $fixtureSource -RequireContainer) -or
        -not (Get-ValidationSafeFullPath -Path $executorModule -RequireLeaf) -or
        -not (Get-ValidationSafeFullPath -Path $observerModule -RequireLeaf)) {
        throw [InvalidOperationException]::new('validation_required_input_unsafe')
    }
    $validatedRuntimeIdentity = Get-ValidationCurrentRuntimeIdentity

    $effectiveRunId = if ($RunId) { $RunId } else { New-ValidationRunId }
    $layout = New-ValidationRunLayout -ValidationRoot $validationRoot `
        -RequestedRunId $effectiveRunId
    $sensitive = [Collections.Generic.List[string]]::new()
    foreach ($value in @(
            $repositoryRoot, $unrealRoot, $layout.validation_root, $layout.run_root,
            $env:USERNAME, $env:USERPROFILE, $env:COMPUTERNAME, $env:HOSTNAME)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { $sensitive.Add([string]$value) }
    }
    $context = New-ValidationContext -RunId $effectiveRunId -RunRoot $layout.run_root `
        -RepeatCount $RepeatCount -SensitiveValues @($sensitive)
    $fixture = $null
    $fixtureRemoved = $false
    $moduleImported = $false
    $fatal = $null
    $engineVersion = '5.6.0'
    $validationStage = 'engine_resolution'
    $stageFaults = [ordered]@{
        engine_resolution = [pscustomobject]@{
            code = 'validation_engine_resolution_failed'; domain = 'environment'
        }
        fixture_copy = [pscustomobject]@{
            code = 'validation_fixture_copy_failed'; domain = 'evidence'
        }
        fixture_build = [pscustomobject]@{
            code = 'validation_fixture_build_failed'; domain = 'environment'
        }
        module_import = [pscustomobject]@{
            code = 'validation_module_import_failed'; domain = 'environment'
        }
        engine_binding = [pscustomobject]@{
            code = 'validation_engine_binding_failed'; domain = 'environment'
        }
        native_smoke = [pscustomobject]@{
            code = 'validation_native_smoke_failed'; domain = 'environment'
        }
        core_matrix = [pscustomobject]@{
            code = 'validation_core_matrix_failed'; domain = 'executor'
        }
        observer_control_matrix = [pscustomobject]@{
            code = 'validation_observer_control_matrix_failed'; domain = 'observer'
        }
        negative_matrix = [pscustomobject]@{
            code = 'validation_negative_matrix_failed'; domain = 'executor'
        }
    }
    try {
        $validationStage = 'engine_resolution'
        $installation = Resolve-ValidationEngineInstallation `
            -RequestedEngineRoot $EngineRoot -RequestedEditorPath $EditorPath `
            -RequestedLauncherManifestPath $LauncherManifestPath
        $engineVersion = [string]$installation.version
        foreach ($value in @($installation.engine_root, $installation.editor_path,
                $installation.build_tool_path)) {
            $context.sensitive_values += $value
        }
        $validationStage = 'fixture_copy'
        $fixture = Copy-ValidationFixtureTree -Source $fixtureSource `
            -Destination $layout.fixture_root
        $context.sensitive_values += @($fixture.fixture_root, $fixture.project_path)
        $validationStage = 'fixture_build'
        $build = Invoke-ValidationFixtureBuild -Installation $installation `
            -ProjectPath $fixture.project_path -RunRoot $layout.run_root `
            -TimeoutMs $BuildTimeoutMs -SensitiveValues $context.sensitive_values
        $context.build = ConvertTo-ValidationPublicValue -Value $build `
            -SensitiveValues $context.sensitive_values
        Add-ValidationEvidence -Context $context -Evidence $build.evidence
        if (-not $build.success) {
            Add-ValidationFault -Context $context -Domain environment -Code $build.classification `
                -Message 'The isolated Unreal Engine 5.6 fixture build did not complete successfully.' `
                -Retryable $true -AffectedCapabilities $script:CapabilityNames `
                -Evidence @($build.evidence.path)
            throw [InvalidOperationException]::new('validation_build_failed')
        }
        $validationStage = 'module_import'
        Import-Module -Name $executorModule -Force -DisableNameChecking -ErrorAction Stop
        Import-Module -Name $observerModule -Force -DisableNameChecking -ErrorAction Stop
        $moduleImported = $true
        $validationStage = 'engine_binding'
        $engineReference = Resolve-UnrealEngine56Root `
            -EditorPath $installation.editor_path
        if ($engineReference.status -ne 'ok') {
            Add-ValidationFaultFromOperation -Context $context `
                -OperationResult $engineReference -AffectedCapabilities $script:CapabilityNames
            throw [InvalidOperationException]::new('validation_engine_resolve_failed')
        }
        $validationStage = 'native_smoke'
        $nativeSmoke = Test-UnrealEvaluationNativeInterop
        if ($nativeSmoke.status -ne 'ok') {
            Add-ValidationFaultFromOperation -Context $context -OperationResult $nativeSmoke `
                -AffectedCapabilities @('Start', 'Stop', 'PressKey', 'HoldKey', 'ReleaseKey',
                    'MovePointer', 'MouseDown', 'MouseUp', 'Click', 'Drag', 'Capture')
            throw [InvalidOperationException]::new('validation_native_smoke_failed')
        }
        $validationStage = 'core_matrix'
        for ($attempt = 1; $attempt -le $RepeatCount; ++$attempt) {
            Invoke-ValidationCoreAttempt -Context $context -AttemptIndex $attempt `
                -ProjectPath $fixture.project_path -EngineReference $engineReference `
                -StartTimeoutMs $StartTimeoutMs -StopTimeoutMs $StopTimeoutMs `
                -ObserverMaxAgeMs $ObserverMaxAgeMs
        }
        $validationStage = 'observer_control_matrix'
        for ($attempt = 1; $attempt -le $RepeatCount; ++$attempt) {
            Invoke-ValidationObserverDisabledControl -Context $context -AttemptIndex $attempt `
                -ProjectPath $fixture.project_path -EngineReference $engineReference `
                -StartTimeoutMs $StartTimeoutMs -StopTimeoutMs $StopTimeoutMs `
                -FeedbackBoundaryMs $ControlFeedbackBoundaryMs
        }
        $validationStage = 'negative_matrix'
        Invoke-ValidationNegativeMatrix -Context $context -ProjectPath $fixture.project_path `
            -EngineReference $engineReference -StartTimeoutMs $StartTimeoutMs `
            -StopTimeoutMs $StopTimeoutMs -ObserverMaxAgeMs $ObserverMaxAgeMs
    }
    catch {
        $stageFault = if ($stageFaults.Contains($validationStage)) {
            $stageFaults[$validationStage]
        }
        else {
            [pscustomobject]@{
                code = 'validation_stage_failed'
                domain = 'environment'
            }
        }
        $fatal = [pscustomobject][ordered]@{
            classification = [string]$stageFault.code
            stage = [string]$validationStage
        }
        if (@($context.faults).Count -eq 0) {
            Add-ValidationFault -Context $context -Domain ([string]$stageFault.domain) `
                -Code $fatal.classification `
                -Message 'The capability validation stopped during a fixed execution stage.' `
                -Retryable $true -AffectedCapabilities $script:CapabilityNames
        }
    }
    finally {
        if ($moduleImported) {
            try { Remove-Module -Name UnrealEvaluationObserver -Force -ErrorAction SilentlyContinue } catch { }
            try { Remove-Module -Name UnrealEvaluationExecutor -Force -ErrorAction SilentlyContinue } catch { }
        }
        if ($fixture) {
            $fixtureRemoved = Remove-ValidationFixtureTree -RunRoot $layout.run_root `
                -FixtureRoot $fixture.fixture_root
            if (-not $fixtureRemoved) {
                Add-ValidationFault -Context $context -Domain evidence `
                    -Code 'isolated_fixture_cleanup_failed' `
                    -Message 'The isolated fixture build tree could not be removed safely.' `
                    -AffectedCapabilities @('Stop')
            }
        }
    }

    $nativePostPassed = $false
    $nativeDetails = [Collections.Generic.List[string]]::new()
    try {
        if (-not ('VibeGaming.UnrealEvaluation.WindowsEvaluationNative' -as [type])) {
            Add-Type -Path (Join-Path $unrealRoot `
                    'executor/Private/WindowsEvaluationNative.cs') -ErrorAction Stop
        }
        $postState = $null
        $nativeError = 0
        $queried = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
            QueryAllControlledInputState([ref]$postState, [ref]$nativeError)
        if ($queried -and -not $postState.AnyDown) {
            $nativePostPassed = $true
            $nativeDetails.Add('Every executor-controlled key and supported mouse button was up at final post-check.')
        }
        else {
            $releaseState = $null
            $failedReleaseCount = 0
            $releaseError = 0
            $released = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::
                ReleaseAllControlledInputs([ref]$releaseState,
                    [ref]$failedReleaseCount, [ref]$releaseError)
            $nativePostPassed = $released -and -not $releaseState.AnyDown
            $nativeDetails.Add('The final post-check found controlled input state and invoked the bounded emergency release routine.')
        }
    }
    catch {
        $nativePostPassed = $false
        $nativeDetails.Add('The final controlled input post-state could not be queried.')
    }

    $evidenceAudit = Test-ValidationEvidenceCollection -Context $context
    if (-not $evidenceAudit.integrity_passed) {
        Add-ValidationFault -Context $context -Domain evidence `
            -Code 'validation_evidence_integrity_failed' `
            -Message 'One or more referenced evidence artifacts failed hash, length, path, or readability verification.' `
            -AffectedCapabilities $script:CapabilityNames
    }
    if (-not $evidenceAudit.privacy_scan.passed) {
        try {
            $privacyCleanup = Invoke-ValidationRawPrivacyFailClosed -Context $context `
                -RelativePaths @($evidenceAudit.privacy_unsafe_paths)
            if (-not $privacyCleanup.passed) {
                throw [InvalidOperationException]::new('validation_privacy_fail_closed_incomplete')
            }
        }
        catch {
            Add-ValidationFault -Context $context -Domain evidence `
                -Code 'validation_privacy_fail_closed_failed' `
                -Message 'One or more privacy-unsafe raw text artifacts could not be removed safely.' `
                -AffectedCapabilities $script:CapabilityNames
        }
        Add-ValidationFault -Context $context -Domain evidence `
            -Code 'validation_evidence_privacy_scan_failed' `
            -Message 'One or more textual evidence artifacts matched a protected local identifier or credential pattern.' `
            -AffectedCapabilities $script:CapabilityNames
    }
    $capabilities = Get-ValidationCapabilitySummary -Context $context
    $negativeComplete = @($context.negative_results).Count -eq @(Get-ValidationNegativePlan).Count -and
        @($context.negative_results | Where-Object { -not $_.passed }).Count -eq 0
    $controlsPassed = @($context.control_results).Count -eq $RepeatCount -and
        @($context.control_results | Where-Object { -not $_.passed }).Count -eq 0
    $cleanup = Get-ValidationCleanupSummary -Context $context `
        -NativePostCheckPassed $nativePostPassed -NativePostDetails @($nativeDetails)
    if (-not $fixtureRemoved -and $fixture) { $cleanup.passed = $false }
    $allAvailable = @($capabilities | Where-Object { $_.status -ne 'available' }).Count -eq 0
    $candidatePassed = $allAvailable -and $negativeComplete -and $controlsPassed -and
        $cleanup.passed -and $evidenceAudit.integrity_passed -and
        $evidenceAudit.privacy_scan.passed -and @($context.faults).Count -eq 0 -and
        $null -eq $fatal
    $conclusion = if ($candidatePassed) {
        'The Unreal public executor completed at least three consecutive dynamic loops in the minimal interface project, establishing engine prerequisites for game-specific dynamic evaluators.'
    }
    else {
        'The Unreal public executor is not ready for formal dynamic scoring.'
    }

    $summaryBase = [pscustomobject][ordered]@{
        schema_version = $script:ValidationSchemaVersion
        run_id = $effectiveRunId
        generated_utc = [DateTime]::UtcNow.ToString('o',
            [Globalization.CultureInfo]::InvariantCulture)
        engine = [pscustomobject][ordered]@{
            name = 'Unreal Engine'
            version = $engineVersion
        }
        runtime_identity = $validatedRuntimeIdentity
        overall_status = if ($candidatePassed) { 'passed' }
        elseif (@($context.ledger['Start']).Count -eq 0) { 'invalid' }
        else { 'failed' }
        formal_scoring_ready = $candidatePassed
        conclusion = $conclusion
        capabilities = $capabilities
        faults = @($context.faults)
        evidence = @($context.evidence_by_path.Values | Sort-Object path)
        privacy_scan = [pscustomobject][ordered]@{
            passed = $false
            finding_count = 0
            checked_patterns = @('absolute_path', 'username', 'device_name', 'credential', 'private_key')
        }
        cleanup = $cleanup
    }
    $draftValue = ConvertTo-ValidationPublicValue -Value $summaryBase `
        -SensitiveValues $context.sensitive_values
    $draftJson = $draftValue | ConvertTo-Json -Depth 64
    $draftScan = Test-ValidationPrivacyText -Text $draftJson `
        -SensitiveValues $context.sensitive_values
    if (-not $draftScan.passed) {
        Add-ValidationFault -Context $context -Domain evidence `
            -Code 'validation_summary_draft_privacy_failed' `
            -Message 'The detailed summary draft was replaced by a fixed privacy-safe draft.' `
            -AffectedCapabilities $script:CapabilityNames
        $draftJson = ([pscustomobject][ordered]@{
                schema_version = $script:ValidationSchemaVersion
                run_id = $effectiveRunId
                status = 'redacted'
                formal_scoring_ready = $false
                conclusion = 'The Unreal public executor is not ready for formal dynamic scoring.'
            }) | ConvertTo-Json -Depth 8
        $draftScan = Test-ValidationPrivacyText -Text $draftJson `
            -SensitiveValues $context.sensitive_values
        if (-not $draftScan.passed) {
            throw [InvalidOperationException]::new('validation_safe_draft_unavailable')
        }
    }
    $draftEvidence = Write-ValidationTextArtifact -RunRoot $layout.run_root `
        -RelativePath 'raw/summary.draft.json' -Text ($draftJson + "`n") `
        -Kind report -MediaType 'application/json'
    Add-ValidationEvidence -Context $context -Evidence $draftEvidence
    $integrityBeforeDraft = [bool]$evidenceAudit.integrity_passed
    $privacyBeforeDraft = [bool]$evidenceAudit.privacy_scan.passed
    $evidenceAudit = Test-ValidationEvidenceCollection -Context $context
    $evidenceAudit.integrity_passed = [bool](
        $integrityBeforeDraft -and $evidenceAudit.integrity_passed)
    $evidenceAudit.privacy_scan.passed = [bool](
        $privacyBeforeDraft -and $evidenceAudit.privacy_scan.passed)
    if (-not $evidenceAudit.integrity_passed -and
        @($context.faults | Where-Object {
                $_.code -ceq 'validation_evidence_integrity_failed'
            }).Count -eq 0) {
        Add-ValidationFault -Context $context -Domain evidence `
            -Code 'validation_evidence_integrity_failed' `
            -Message 'One or more referenced evidence artifacts failed hash, length, path, or readability verification.' `
            -AffectedCapabilities $script:CapabilityNames
    }
    if (-not $evidenceAudit.privacy_scan.passed -and
        @($context.faults | Where-Object {
                $_.code -ceq 'validation_evidence_privacy_scan_failed'
            }).Count -eq 0) {
        Add-ValidationFault -Context $context -Domain evidence `
            -Code 'validation_evidence_privacy_scan_failed' `
            -Message 'One or more textual evidence artifacts matched a protected local identifier or credential pattern.' `
            -AffectedCapabilities $script:CapabilityNames
    }
    $capabilities = Get-ValidationCapabilitySummary -Context $context
    $allAvailable = @($capabilities | Where-Object {
            $_.status -ne 'available'
        }).Count -eq 0
    $candidatePassed = $allAvailable -and $negativeComplete -and $controlsPassed -and
        $cleanup.passed -and $evidenceAudit.integrity_passed -and
        $evidenceAudit.privacy_scan.passed -and $draftScan.passed -and
        @($context.faults).Count -eq 0 -and $null -eq $fatal
    $summaryBase.overall_status = if ($candidatePassed) { 'passed' }
    elseif (@($context.ledger['Start']).Count -eq 0) { 'invalid' }
    else { 'failed' }
    $summaryBase.formal_scoring_ready = [bool]$candidatePassed
    $summaryBase.conclusion = if ($candidatePassed) {
        'The Unreal public executor completed at least three consecutive dynamic loops in the minimal interface project, establishing engine prerequisites for game-specific dynamic evaluators.'
    }
    else { 'The Unreal public executor is not ready for formal dynamic scoring.' }
    $summaryBase.capabilities = $capabilities
    $summaryBase.faults = @($context.faults)
    $summaryBase.evidence = @($context.evidence_by_path.Values | Sort-Object path)
    $prePrivacyJson = $summaryBase | ConvertTo-Json -Depth 64
    $privacy = Test-ValidationPrivacyText `
        -Text $prePrivacyJson `
        -SensitiveValues $context.sensitive_values
    $privacyFindingCount = [int]$privacy.finding_count +
        [int]$evidenceAudit.privacy_scan.finding_count
    $summaryBase.privacy_scan = [pscustomobject][ordered]@{
        passed = [bool]($privacyFindingCount -eq 0)
        finding_count = $privacyFindingCount
        checked_patterns = @($privacy.checked_patterns)
    }
    if (-not $summaryBase.privacy_scan.passed) {
        $summaryBase.overall_status = 'invalid'
        $summaryBase.formal_scoring_ready = $false
        $summaryBase.conclusion = 'The Unreal public executor is not ready for formal dynamic scoring.'
        Add-ValidationFault -Context $context -Domain evidence -Code 'privacy_scan_failed' `
            -Message 'The redacted validation summary still matched one or more privacy patterns.' `
            -AffectedCapabilities $script:CapabilityNames
        $summaryBase.faults = @($context.faults)
    }
    $detailOutputWithheld = $false
    $contract = Test-ValidationSummaryContract -Summary $summaryBase
    if (-not $contract.valid) {
        $detailOutputWithheld = $true
        $summaryBase = New-ValidationInvalidSummaryFallback -RunId $effectiveRunId `
            -EngineVersion $engineVersion `
            -FaultCode 'validation_summary_contract_failed' `
            -FaultMessage 'The detailed validation result was withheld because it did not satisfy the machine-readable summary contract.' `
            -PrivacyFindingCount ([int]$summaryBase.privacy_scan.finding_count) `
            -Cleanup $cleanup
    }

    $report = if ($detailOutputWithheld) {
        Get-ValidationReportText -Summary $summaryBase `
            -Attempts @() -Controls @() -NegativeResults @()
    }
    else {
        Get-ValidationReportText -Summary $summaryBase `
            -Attempts @($context.attempt_details) `
            -Controls @($context.control_results) `
            -NegativeResults @($context.negative_results)
    }
    $finalPrivacy = Test-ValidationPrivacyText `
        -Text (($summaryBase | ConvertTo-Json -Depth 64) + "`n" + $report) `
        -SensitiveValues $context.sensitive_values
    if (-not $finalPrivacy.passed) {
        $detailOutputWithheld = $true
        $summaryBase = New-ValidationInvalidSummaryFallback -RunId $effectiveRunId `
            -EngineVersion $engineVersion `
            -FaultCode 'privacy_scan_failed' `
            -FaultMessage 'The detailed validation result was withheld because privacy validation failed.' `
            -PrivacyFindingCount ([int]$finalPrivacy.finding_count) -Cleanup $cleanup
        $report = Get-ValidationReportText -Summary $summaryBase `
            -Attempts @() -Controls @() -NegativeResults @()
    }

    $finalContract = Test-ValidationSummaryContract -Summary $summaryBase
    if (-not $finalContract.valid) {
        throw [InvalidOperationException]::new('validation_fallback_contract_failed')
    }
    if ($finalPrivacy.passed -and $evidenceAudit.integrity_passed -and
        $evidenceAudit.privacy_scan.passed -and $draftScan.passed -and
        $summaryBase.privacy_scan.finding_count -eq 0) {
        $summaryBase.privacy_scan.passed = $true
    }
    $finalOutputPrivacy = Test-ValidationPrivacyText `
        -Text (($summaryBase | ConvertTo-Json -Depth 64) + "`n" + $report) `
        -SensitiveValues $context.sensitive_values
    if (-not $finalOutputPrivacy.passed) {
        throw [InvalidOperationException]::new('validation_safe_output_unavailable')
    }
    $publishAllowed = $finalContract.valid -and $finalPrivacy.passed -and
        $finalOutputPrivacy.passed -and $summaryBase.privacy_scan.passed -and
        $evidenceAudit.integrity_passed -and $evidenceAudit.privacy_scan.passed -and
        $draftScan.passed

    $summaryJson = $summaryBase | ConvertTo-Json -Depth 64
    $summaryBytes = [Text.UTF8Encoding]::new($false).GetBytes($summaryJson + "`n")
    $reportBytes = [Text.UTF8Encoding]::new($false).GetBytes($report)
    $summaryEvidence = Write-ValidationBytesArtifact -RunRoot $layout.run_root `
        -RelativePath 'summary.json' -Bytes $summaryBytes -MediaType 'application/json' `
        -Kind report
    $reportEvidence = Write-ValidationBytesArtifact -RunRoot $layout.run_root `
        -RelativePath 'VALIDATION_REPORT.md' -Bytes $reportBytes -MediaType 'text/markdown' `
        -Kind report
    if (-not $NoPublishLatest -and $publishAllowed) {
        Publish-ValidationLatest -ValidationRoot $layout.validation_root `
            -SummaryBytes $summaryBytes -ReportBytes $reportBytes
    }

    return [pscustomobject][ordered]@{
        schema_version = $script:ValidationSchemaVersion
        run_id = $effectiveRunId
        overall_status = [string]$summaryBase.overall_status
        formal_scoring_ready = [bool]$summaryBase.formal_scoring_ready
        conclusion = [string]$summaryBase.conclusion
        summary_path = 'summary.json'
        report_path = 'VALIDATION_REPORT.md'
        capability_statuses = @($summaryBase.capabilities | ForEach-Object {
                [pscustomobject]@{ name = $_.name; status = $_.status }
            })
        cleanup_passed = [bool]$summaryBase.cleanup.passed
        privacy_scan_passed = [bool]$summaryBase.privacy_scan.passed
    }
}

if (-not $NoInvoke) {
    $invokeParameters = @{
        RepeatCount = $RepeatCount
        StartTimeoutMs = $StartTimeoutMs
        BuildTimeoutMs = $BuildTimeoutMs
        StopTimeoutMs = $StopTimeoutMs
        ObserverMaxAgeMs = $ObserverMaxAgeMs
        ControlFeedbackBoundaryMs = $ControlFeedbackBoundaryMs
        NoPublishLatest = $NoPublishLatest
    }
    if ($RunId) { $invokeParameters.RunId = $RunId }
    if ($EngineRoot) { $invokeParameters.EngineRoot = $EngineRoot }
    if ($EditorPath) { $invokeParameters.EditorPath = $EditorPath }
    if ($LauncherManifestPath) {
        $invokeParameters.LauncherManifestPath = $LauncherManifestPath
    }
    Invoke-UnrealCapabilityValidation @invokeParameters
}
