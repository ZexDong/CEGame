Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or later is required.'
}

$nativeSource = Join-Path $PSScriptRoot 'Private/WindowsEvaluationNative.cs'
if (-not ('VibeGaming.UnrealEvaluation.WindowsEvaluationNative' -as [type])) {
    Add-Type -Path $nativeSource -ErrorAction Stop
}
if ([VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::InteropVersion -cne '1.1.0') {
    throw 'WindowsEvaluationNative interop version 1.1.0 is required; start a fresh PowerShell process.'
}

$script:SchemaVersion = '1.0.0'
$script:Sessions = @{}
$script:EngineRoots = @{}
$script:DefaultFocusTimeoutMs = 1500
$script:InputLeaseFileName = 'vibe-gaming-unreal-evaluation-input.lock'

$script:VirtualKeys = @{
    'BACKSPACE'    = @{ Canonical = 'Backspace';    VirtualKey = [uint16]0x08; Extended = $false }
    'TAB'          = @{ Canonical = 'Tab';          VirtualKey = [uint16]0x09; Extended = $false }
    'ENTER'        = @{ Canonical = 'Enter';        VirtualKey = [uint16]0x0D; Extended = $false }
    'RETURN'       = @{ Canonical = 'Enter';        VirtualKey = [uint16]0x0D; Extended = $false }
    'SHIFT'        = @{ Canonical = 'Shift';        VirtualKey = [uint16]0x10; Extended = $false }
    'CTRL'         = @{ Canonical = 'Control';      VirtualKey = [uint16]0x11; Extended = $false }
    'CONTROL'      = @{ Canonical = 'Control';      VirtualKey = [uint16]0x11; Extended = $false }
    'ALT'          = @{ Canonical = 'Alt';          VirtualKey = [uint16]0x12; Extended = $false }
    'PAUSE'        = @{ Canonical = 'Pause';        VirtualKey = [uint16]0x13; Extended = $false }
    'CAPSLOCK'     = @{ Canonical = 'CapsLock';     VirtualKey = [uint16]0x14; Extended = $false }
    'ESC'          = @{ Canonical = 'Escape';       VirtualKey = [uint16]0x1B; Extended = $false }
    'ESCAPE'       = @{ Canonical = 'Escape';       VirtualKey = [uint16]0x1B; Extended = $false }
    'SPACE'        = @{ Canonical = 'Space';        VirtualKey = [uint16]0x20; Extended = $false }
    'PAGEUP'       = @{ Canonical = 'PageUp';       VirtualKey = [uint16]0x21; Extended = $true }
    'PAGEDOWN'     = @{ Canonical = 'PageDown';     VirtualKey = [uint16]0x22; Extended = $true }
    'END'          = @{ Canonical = 'End';          VirtualKey = [uint16]0x23; Extended = $true }
    'HOME'         = @{ Canonical = 'Home';         VirtualKey = [uint16]0x24; Extended = $true }
    'LEFT'         = @{ Canonical = 'Left';         VirtualKey = [uint16]0x25; Extended = $true }
    'UP'           = @{ Canonical = 'Up';           VirtualKey = [uint16]0x26; Extended = $true }
    'RIGHT'        = @{ Canonical = 'Right';        VirtualKey = [uint16]0x27; Extended = $true }
    'DOWN'         = @{ Canonical = 'Down';         VirtualKey = [uint16]0x28; Extended = $true }
    'INSERT'       = @{ Canonical = 'Insert';       VirtualKey = [uint16]0x2D; Extended = $true }
    'DELETE'       = @{ Canonical = 'Delete';       VirtualKey = [uint16]0x2E; Extended = $true }
    'LEFTSHIFT'    = @{ Canonical = 'LeftShift';    VirtualKey = [uint16]0xA0; Extended = $false }
    'RIGHTSHIFT'   = @{ Canonical = 'RightShift';   VirtualKey = [uint16]0xA1; Extended = $false }
    'LEFTCONTROL'  = @{ Canonical = 'LeftControl';  VirtualKey = [uint16]0xA2; Extended = $false }
    'LEFTCTRL'     = @{ Canonical = 'LeftControl';  VirtualKey = [uint16]0xA2; Extended = $false }
    'RIGHTCONTROL' = @{ Canonical = 'RightControl'; VirtualKey = [uint16]0xA3; Extended = $true }
    'RIGHTCTRL'    = @{ Canonical = 'RightControl'; VirtualKey = [uint16]0xA3; Extended = $true }
    'LEFTALT'      = @{ Canonical = 'LeftAlt';      VirtualKey = [uint16]0xA4; Extended = $false }
    'RIGHTALT'     = @{ Canonical = 'RightAlt';     VirtualKey = [uint16]0xA5; Extended = $true }
}

function Get-UnrealMonotonicMs {
    return [long][Environment]::TickCount64
}

function Enter-UnrealInputLease {
    $stream = $null
    try {
        $leasePath = Join-Path ([IO.Path]::GetTempPath()) $script:InputLeaseFileName
        $stream = [IO.FileStream]::new(
            $leasePath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None)
        return $stream
    }
    catch {
        if ($stream) {
            try { $stream.Dispose() } catch { }
        }
        return $null
    }
}

function Exit-UnrealInputLease {
    param([AllowNull()]$Lease)

    if (-not $Lease) { return $true }
    try {
        $Lease.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function New-UnrealFault {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('executor', 'environment', 'unsupported')]
        [string]$Domain,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z][A-Z0-9_]{2,63}$')]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$Message,

        [bool]$Retryable = $false,

        [object]$Details = $null
    )

    [pscustomobject][ordered]@{
        domain = if ($Domain -eq 'unsupported') { 'capability' } else { $Domain }
        code = $Code.ToLowerInvariant()
        message = $Message
        retryable = $Retryable
        evidence_paths = @()
        details = $Details
    }
}

function New-UnrealOperationResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]
        [ValidateSet('ok', 'timeout', 'executor_fault', 'environment_fault', 'unsupported')]
        [string]$Status,
        [bool]$InputDispatched = $false,
        [AllowNull()][object]$FeedbackObserved = $null,
        [AllowNull()][object]$TargetVisible = $null,
        [AllowNull()][object]$Result = $null,
        [AllowNull()][object]$Fault = $null,
        [AllowNull()][object[]]$Evidence = @()
    )

    [pscustomobject][ordered]@{
        schema_version = $script:SchemaVersion
        operation = $Operation
        status = $Status
        observer_monotonic_ms = Get-UnrealMonotonicMs
        input_dispatched = $InputDispatched
        feedback_observed = $FeedbackObserved
        target_visible = $TargetVisible
        executor_fault = ($Status -eq 'executor_fault')
        environment_fault = ($Status -eq 'environment_fault')
        unsupported = ($Status -eq 'unsupported')
        result = $Result
        fault = $Fault
        evidence = @($Evidence)
    }
}

function New-UnrealExecutorFaultResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [bool]$InputDispatched = $false,
        [AllowNull()][object]$TargetVisible = $null,
        [bool]$Retryable = $false,
        [AllowNull()][object]$Details = $null,
        [AllowNull()][object]$Result = $null
    )

    New-UnrealOperationResult -Operation $Operation -Status executor_fault `
        -InputDispatched $InputDispatched -TargetVisible $TargetVisible -Result $Result `
        -Fault (New-UnrealFault -Domain executor -Code $Code -Message $Message `
            -Retryable $Retryable -Details $Details)
}

function New-UnrealEnvironmentFaultResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [bool]$Retryable = $false,
        [AllowNull()][object]$Details = $null,
        [AllowNull()][object]$Result = $null
    )

    New-UnrealOperationResult -Operation $Operation -Status environment_fault -Result $Result `
        -Fault (New-UnrealFault -Domain environment -Code $Code -Message $Message `
            -Retryable $Retryable -Details $Details)
}

function New-UnrealUnsupportedResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message
    )

    New-UnrealOperationResult -Operation $Operation -Status unsupported `
        -Fault (New-UnrealFault -Domain unsupported -Code $Code -Message $Message)
}

function Get-SafeFullPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireLeaf,
        [switch]$RequireContainer
    )

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if ($RequireLeaf -and -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            return $null
        }
        if ($RequireContainer -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            return $null
        }

        $existingPath = $fullPath
        while (-not (Test-Path -LiteralPath $existingPath)) {
            $parent = Split-Path -Parent $existingPath
            if (-not $parent -or $parent -eq $existingPath) { return $null }
            $existingPath = $parent
        }
        $item = Get-Item -LiteralPath $existingPath -Force -ErrorAction Stop
        while ($item) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $null
            }
            $parentPath = Split-Path -Parent $item.FullName
            if (-not $parentPath -or $parentPath -eq $item.FullName) { break }
            $item = Get-Item -LiteralPath $parentPath -Force -ErrorAction Stop
        }
        return $fullPath
    }
    catch {
        return $null
    }
}

function Get-SafeEvidenceRelativePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    try {
        $rootFull = [IO.Path]::GetFullPath($Root)
        $pathFull = [IO.Path]::GetFullPath($Path)
        $relative = [IO.Path]::GetRelativePath($rootFull, $pathFull).Replace('\', '/')
        if ([IO.Path]::IsPathRooted($relative) -or
            $relative -eq '..' -or
            $relative.StartsWith('../', [StringComparison]::Ordinal) -or
            $relative.Contains(':') -or
            $relative.Contains('://')) {
            return $null
        }
        return $relative
    }
    catch {
        return $null
    }
}

function Get-UnrealEngineVersionInfo {
    param([Parameter(Mandatory)][string]$EngineRoot)

    try {
        $versionPath = Join-Path $EngineRoot 'Engine/Build/Build.version'
        $editorPath = Join-Path $EngineRoot 'Engine/Binaries/Win64/UnrealEditor.exe'
        if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $editorPath -PathType Leaf)) {
            return $null
        }
        if ((Get-Item -LiteralPath $versionPath -ErrorAction Stop).Length -gt 65536) {
            return $null
        }
        $version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ([int]$version.MajorVersion -ne 5 -or [int]$version.MinorVersion -ne 7) {
            return $null
        }
        return [pscustomobject]@{
            EngineRoot = [IO.Path]::GetFullPath($EngineRoot)
            EditorPath = [IO.Path]::GetFullPath($editorPath)
            Version = ('{0}.{1}.{2}' -f [int]$version.MajorVersion,
                [int]$version.MinorVersion, [int]$version.PatchVersion)
        }
    }
    catch {
        return $null
    }
}

function Find-UnrealEngine57Installation {
    param(
        [AllowNull()][string]$EngineRoot,
        [AllowNull()][string]$EditorPath,
        [AllowNull()][string]$LauncherManifestPath
    )

    if (-not $IsWindows) {
        return [pscustomobject]@{
            Installation = $null
            Fault = New-UnrealFault -Domain unsupported -Code 'WINDOWS_PLATFORM_REQUIRED' `
                -Message 'The Unreal Windows executor is available only on Windows.'
        }
    }

    if ($EngineRoot -and $EditorPath) {
        return [pscustomobject]@{
            Installation = $null
            Fault = New-UnrealFault -Domain executor -Code 'ENGINE_SELECTION_AMBIGUOUS' `
                -Message 'Specify either an engine root or an editor executable, not both.'
        }
    }

    if ($EditorPath) {
        $editorFull = Get-SafeFullPath -Path $EditorPath -RequireLeaf
        if (-not $editorFull -or [IO.Path]::GetFileName($editorFull) -ine 'UnrealEditor.exe') {
            return [pscustomobject]@{
                Installation = $null
                Fault = New-UnrealFault -Domain environment -Code 'UE57_EDITOR_INVALID' `
                    -Message 'The requested Unreal Editor executable is unavailable or invalid.'
            }
        }
        try {
            $editorDirectory = [IO.FileInfo]::new($editorFull).Directory
            $rootCandidate = $editorDirectory.Parent.Parent.Parent.FullName
        }
        catch {
            $rootCandidate = $null
        }
        $installation = if ($rootCandidate) {
            Get-UnrealEngineVersionInfo -EngineRoot $rootCandidate
        }
        else { $null }
        if (-not $installation -or $installation.EditorPath -ine $editorFull) {
            return [pscustomobject]@{
                Installation = $null
                Fault = New-UnrealFault -Domain environment -Code 'UE57_VERSION_MISMATCH' `
                    -Message 'The requested editor is not a valid Unreal Engine 5.7 installation.'
            }
        }
        $installation | Add-Member -NotePropertyName Source -NotePropertyValue 'explicit_editor'
        return [pscustomobject]@{ Installation = $installation; Fault = $null }
    }

    if ($EngineRoot) {
        $rootFull = Get-SafeFullPath -Path $EngineRoot -RequireContainer
        $installation = if ($rootFull) {
            Get-UnrealEngineVersionInfo -EngineRoot $rootFull
        }
        else { $null }
        if (-not $installation) {
            return [pscustomobject]@{
                Installation = $null
                Fault = New-UnrealFault -Domain environment -Code 'UE57_ROOT_INVALID' `
                    -Message 'The requested Unreal Engine root is unavailable or is not version 5.7.'
            }
        }
        $installation | Add-Member -NotePropertyName Source -NotePropertyValue 'explicit_root'
        return [pscustomobject]@{ Installation = $installation; Fault = $null }
    }

    $candidates = [Collections.Generic.List[object]]::new()
    $manifestCandidates = [Collections.Generic.List[string]]::new()
    if ($LauncherManifestPath) {
        $manifestCandidates.Add($LauncherManifestPath)
    }
    elseif ($env:ProgramData) {
        $manifestCandidates.Add((Join-Path $env:ProgramData 'Epic/UnrealEngineLauncher/LauncherInstalled.dat'))
    }

    foreach ($manifestCandidate in $manifestCandidates) {
        $manifestFull = Get-SafeFullPath -Path $manifestCandidate -RequireLeaf
        if (-not $manifestFull) { continue }
        try {
            if ((Get-Item -LiteralPath $manifestFull -ErrorAction Stop).Length -gt 4194304) {
                continue
            }
            $manifest = Get-Content -LiteralPath $manifestFull -Raw -Encoding UTF8 -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            foreach ($entry in @($manifest.InstallationList)) {
                if (-not $entry.InstallLocation) { continue }
                $installation = Get-UnrealEngineVersionInfo -EngineRoot ([string]$entry.InstallLocation)
                if ($installation) {
                    $installation | Add-Member -NotePropertyName Source -NotePropertyValue 'launcher_manifest'
                    $candidates.Add($installation)
                }
            }
        }
        catch {
            continue
        }
    }

    $standardParents = [Collections.Generic.List[string]]::new()
    if ($env:ProgramFiles) {
        $standardParents.Add((Join-Path $env:ProgramFiles 'Epic Games'))
    }
    if ($env:SystemDrive) {
        $standardParents.Add((Join-Path $env:SystemDrive 'Epic Games'))
    }
    foreach ($standardParent in @($standardParents | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $standardParent -PathType Container)) { continue }
        try {
            foreach ($directory in @(Get-ChildItem -LiteralPath $standardParent -Directory -Filter 'UE_5.7*' `
                        -ErrorAction SilentlyContinue | Sort-Object Name)) {
                $installation = Get-UnrealEngineVersionInfo -EngineRoot $directory.FullName
                if ($installation) {
                    $installation | Add-Member -NotePropertyName Source -NotePropertyValue 'standard_install'
                    $candidates.Add($installation)
                }
            }
        }
        catch {
            continue
        }
    }

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Installation = $null
            Fault = New-UnrealFault -Domain environment -Code 'UE57_NOT_FOUND' `
                -Message 'No valid Unreal Engine 5.7 installation was found.' -Retryable $true
        }
    }

    $selected = @($candidates | Sort-Object @{ Expression = {
                    switch ($_.Source) {
                        'launcher_manifest' { 0 }
                        'standard_install' { 1 }
                        default { 2 }
                    }
                }; Ascending = $true },
            @{ Expression = { [version]$_.Version }; Descending = $true } |
            Select-Object -First 1)[0]
    return [pscustomobject]@{ Installation = $selected; Fault = $null }
}

function Register-UnrealEngineInstallation {
    param([Parameter(Mandatory)]$Installation)

    $token = 'engine-' + [guid]::NewGuid().ToString('N')
    $script:EngineRoots[$token] = $Installation
    return $token
}

function Resolve-UnrealEngine57Root {
    [CmdletBinding()]
    param(
        [string]$EngineRoot,
        [string]$EditorPath,
        [string]$LauncherManifestPath
    )

    $operation = 'ResolveEngine'
    $resolved = Find-UnrealEngine57Installation -EngineRoot $EngineRoot -EditorPath $EditorPath `
        -LauncherManifestPath $LauncherManifestPath
    if ($resolved.Fault) {
        $status = switch ($resolved.Fault.domain) {
            'unsupported' { 'unsupported' }
            'environment' { 'environment_fault' }
            default { 'executor_fault' }
        }
        return New-UnrealOperationResult -Operation $operation -Status $status -Fault $resolved.Fault
    }

    $token = Register-UnrealEngineInstallation -Installation $resolved.Installation
    New-UnrealOperationResult -Operation $operation -Status ok -Result ([pscustomobject][ordered]@{
            engine_token = $token
            engine = 'Unreal Engine'
            engine_version = $resolved.Installation.Version
            source = $resolved.Installation.Source
            editor_available = $true
        })
}

function Get-UnrealEngineFromReference {
    param(
        [AllowNull()][object]$EngineReference,
        [AllowNull()][string]$EngineRoot,
        [AllowNull()][string]$EditorPath,
        [AllowNull()][string]$LauncherManifestPath
    )

    if ($EngineReference -and ($EngineRoot -or $EditorPath)) {
        return [pscustomobject]@{
            Installation = $null
            Fault = New-UnrealFault -Domain executor -Code 'ENGINE_SELECTION_AMBIGUOUS' `
                -Message 'Use either an engine reference or an explicit engine location.'
        }
    }

    if ($EngineReference) {
        $token = if ($EngineReference -is [string]) {
            [string]$EngineReference
        }
        elseif ($EngineReference.PSObject.Properties['engine_token']) {
            [string]$EngineReference.engine_token
        }
        elseif ($EngineReference.PSObject.Properties['result'] -and
            $EngineReference.result -and $EngineReference.result.PSObject.Properties['engine_token']) {
            [string]$EngineReference.result.engine_token
        }
        else { $null }
        if (-not $token -or -not $script:EngineRoots.ContainsKey($token)) {
            return [pscustomobject]@{
                Installation = $null
                Fault = New-UnrealFault -Domain executor -Code 'ENGINE_REFERENCE_INVALID' `
                    -Message 'The engine reference is unknown or expired.'
            }
        }
        return [pscustomobject]@{ Installation = $script:EngineRoots[$token]; Fault = $null }
    }

    return Find-UnrealEngine57Installation -EngineRoot $EngineRoot -EditorPath $EditorPath `
        -LauncherManifestPath $LauncherManifestPath
}

function Get-UnrealSessionId {
    param([AllowNull()][object]$Session)

    if ($null -eq $Session) { return $null }
    if ($Session -is [string]) { return [string]$Session }
    if ($Session.PSObject.Properties['SessionId']) { return [string]$Session.SessionId }
    if ($Session.PSObject.Properties['session_id']) { return [string]$Session.session_id }
    if ($Session.PSObject.Properties['session'] -and $Session.session) {
        return Get-UnrealSessionId -Session $Session.session
    }
    if ($Session.PSObject.Properties['result'] -and $Session.result) {
        return Get-UnrealSessionId -Session $Session.result
    }
    return $null
}

function Get-UnrealSessionState {
    param([AllowNull()][object]$Session)

    $sessionId = Get-UnrealSessionId -Session $Session
    if (-not $sessionId -or -not $script:Sessions.ContainsKey($sessionId)) {
        return $null
    }
    return $script:Sessions[$sessionId]
}

function Test-UnrealTargetWindow {
    param(
        [Parameter(Mandatory)]$State,
        [switch]$AcquireForeground,
        [int]$FocusTimeoutMs = $script:DefaultFocusTimeoutMs
    )

    try {
        if ($State.Stopped -or $State.Process.HasExited) {
            return [pscustomobject]@{
                ok = $false; code = 'TARGET_PROCESS_EXITED'; native_error = 0
                target_visible = $false; snapshot = $null
            }
        }
    }
    catch {
        return [pscustomobject]@{
            ok = $false; code = 'TARGET_PROCESS_QUERY_FAILED'; native_error = 0
            target_visible = $null; snapshot = $null
        }
    }

    $snapshot = $null
    $validationCode = $null
    $nativeError = 0
    $valid = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetWindowSnapshot(
        $State.WindowHandle, [uint32]$State.ProcessId, $false,
        [ref]$snapshot, [ref]$validationCode, [ref]$nativeError)
    if (-not $valid) {
        $visible = if ($validationCode -in @('FOREGROUND_NOT_CONFIRMED')) { $true } else { $false }
        return [pscustomobject]@{
            ok = $false; code = [string]$validationCode; native_error = [int]$nativeError
            target_visible = $visible; snapshot = $null
        }
    }

    if ($AcquireForeground -and -not $snapshot.IsForeground) {
        $deadline = (Get-UnrealMonotonicMs) + [Math]::Max(0, $FocusTimeoutMs)
        do {
            $focusError = 0
            $focusCode = $null
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RequestForegroundBound(
                $State.WindowHandle, [uint32]$State.ProcessId,
                [ref]$focusCode, [ref]$focusError)
            $snapshot = $null
            $validationCode = $null
            $nativeError = 0
            $valid = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetWindowSnapshot(
                $State.WindowHandle, [uint32]$State.ProcessId, $true,
                [ref]$snapshot, [ref]$validationCode, [ref]$nativeError)
            if ($valid) { break }
            if ((Get-UnrealMonotonicMs) -ge $deadline) { break }
            Start-Sleep -Milliseconds 50
        } while ($true)
        if (-not $valid) {
            return [pscustomobject]@{
                ok = $false; code = 'FOREGROUND_NOT_CONFIRMED'; native_error = [int]$focusError
                target_visible = $true; snapshot = $null
            }
        }
    }
    elseif (-not $snapshot.IsForeground) {
        return [pscustomobject]@{
            ok = $false; code = 'FOREGROUND_NOT_CONFIRMED'; native_error = 0
            target_visible = $true; snapshot = $snapshot
        }
    }

    return [pscustomobject]@{
        ok = $true; code = 'OK'; native_error = 0
        target_visible = $true; snapshot = $snapshot
    }
}

function New-UnrealWindowFaultResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]$Validation,
        [bool]$InputDispatched = $false
    )

    $messages = @{
        TARGET_PROCESS_EXITED = 'The bound target process is no longer running.'
        TARGET_PROCESS_QUERY_FAILED = 'The target process state could not be confirmed.'
        WINDOW_INVALID = 'The bound target window is no longer valid.'
        WINDOW_NOT_VISIBLE = 'The bound target window is not visible.'
        WINDOW_MINIMIZED = 'The bound target window is minimized.'
        WINDOW_PID_QUERY_FAILED = 'The target window process could not be confirmed.'
        WINDOW_PID_MISMATCH = 'The target window no longer belongs to the bound process.'
        CLIENT_RECT_QUERY_FAILED = 'The target client rectangle could not be read.'
        CLIENT_AREA_INVALID = 'The target window has no usable client area.'
        CLIENT_ORIGIN_QUERY_FAILED = 'The target client origin could not be read.'
        FOREGROUND_NOT_CONFIRMED = 'The target window could not be confirmed as foreground.'
        FOREGROUND_REQUEST_FAILED = 'The target window rejected the foreground request.'
        DPI_AWARENESS_CONTEXT_FAILED = 'A per-monitor DPI coordinate transaction could not be established.'
        WINDOW_NOT_UNOWNED_TOP_LEVEL = 'The bound handle is no longer the expected top-level game window.'
    }
    $code = if ($messages.ContainsKey([string]$Validation.code)) {
        [string]$Validation.code
    }
    else { 'TARGET_VALIDATION_FAILED' }
    $message = if ($messages.ContainsKey($code)) { $messages[$code] } else {
        'The target window validation failed.'
    }
    $details = if ([int]$Validation.native_error -ne 0) {
        [pscustomobject]@{ native_error = [int]$Validation.native_error }
    }
    else { $null }
    New-UnrealExecutorFaultResult -Operation $Operation -Code $code -Message $message `
        -InputDispatched $InputDispatched -TargetVisible $Validation.target_visible `
        -Retryable ($code -eq 'FOREGROUND_NOT_CONFIRMED') -Details $details
}

function New-UnrealBoundNativeFaultResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$FallbackCode,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][string]$ValidationCode,
        [int]$NativeError = 0,
        [bool]$InputDispatched = $false,
        [AllowNull()][object]$TargetVisible = $true
    )

    $windowCodes = @(
        'WINDOW_INVALID', 'WINDOW_NOT_VISIBLE', 'WINDOW_MINIMIZED',
        'WINDOW_PID_QUERY_FAILED', 'WINDOW_PID_MISMATCH',
        'CLIENT_RECT_QUERY_FAILED', 'CLIENT_AREA_INVALID',
        'CLIENT_ORIGIN_QUERY_FAILED', 'FOREGROUND_NOT_CONFIRMED',
        'FOREGROUND_REQUEST_FAILED', 'DPI_AWARENESS_CONTEXT_FAILED',
        'WINDOW_NOT_UNOWNED_TOP_LEVEL'
    )
    if (-not $InputDispatched -and $ValidationCode -in $windowCodes) {
        return New-UnrealWindowFaultResult -Operation $Operation -InputDispatched $false `
            -Validation ([pscustomobject]@{
                    code = $ValidationCode
                    native_error = $NativeError
                    target_visible = $TargetVisible
                })
    }
    $details = [pscustomobject][ordered]@{
        validation_code = if ($ValidationCode) { $ValidationCode } else { 'UNKNOWN' }
        native_error = $NativeError
        dispatch_occurred_before_fault = $InputDispatched
    }
    New-UnrealExecutorFaultResult -Operation $Operation -Code $FallbackCode -Message $Message `
        -InputDispatched $InputDispatched -TargetVisible $TargetVisible -Details $details
}

function Get-UnrealInputWatchdogState {
    param([Parameter(Mandatory)]$State)

    $active = $false
    $faulted = $false
    $faultCode = $null
    $nativeError = 0
    $queried = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::QueryInputWatchdog(
        $State.WindowHandle, [uint32]$State.ProcessId,
        [ref]$active, [ref]$faulted, [ref]$faultCode, [ref]$nativeError)
    if ($queried -and $faulted -and $active) {
        $postInputState = $null
        $failedReleaseCount = 0
        $releaseError = 0
        [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::ReleaseAllControlledInputs(
            [ref]$postInputState, [ref]$failedReleaseCount, [ref]$releaseError)
        $active = $false
        $faulted = $false
        $faultCode = $null
        $nativeError = 0
        $queried = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::QueryInputWatchdog(
            $State.WindowHandle, [uint32]$State.ProcessId,
            [ref]$active, [ref]$faulted, [ref]$faultCode, [ref]$nativeError)
    }
    if ($queried -and $faulted -and -not $active) {
        $State.HeldKeys.Clear()
        $State.HeldMouseButtons.Clear()
    }
    [pscustomobject][ordered]@{
        ok = [bool]$queried
        active = [bool]$active
        faulted = [bool]$faulted
        fault_code = if ($faultCode) { [string]$faultCode } else { 'UNKNOWN' }
        native_error = [int]$nativeError
    }
}

function Stop-UnrealInputWatchdog {
    param([Parameter(Mandatory)]$State)

    $faulted = $false
    $faultCode = $null
    $nativeError = 0
    $stopped = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::StopInputWatchdog(
        $State.WindowHandle, [uint32]$State.ProcessId,
        [ref]$faulted, [ref]$faultCode, [ref]$nativeError)
    if ($stopped) {
        $State.HeldKeys.Clear()
        $State.HeldMouseButtons.Clear()
    }
    [pscustomobject][ordered]@{
        stopped = [bool]$stopped
        faulted = [bool]$faulted
        fault_code = if ($faultCode) { [string]$faultCode } else { 'UNKNOWN' }
        native_error = [int]$nativeError
    }
}

function New-UnrealWatchdogFaultResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]$Watchdog,
        [bool]$InputDispatched = $false,
        [AllowNull()][object]$TargetVisible = $null
    )

    $code = if ($Watchdog.faulted -and $Watchdog.active) {
        'INPUT_WATCHDOG_RELEASE_INCOMPLETE'
    }
    elseif ($Watchdog.faulted) {
        'INPUT_WATCHDOG_FAULT_LATCHED'
    }
    else { 'INPUT_WATCHDOG_QUERY_FAILED' }
    $message = if ($Watchdog.faulted -and $Watchdog.active) {
        'The input watchdog detected a target fault but could not confirm that every held input was released.'
    }
    elseif ($Watchdog.faulted) {
        'The input watchdog released held input after the target binding or foreground was lost.'
    }
    else { 'The input watchdog state could not be confirmed.' }
    New-UnrealExecutorFaultResult -Operation $Operation -Code $code -Message $message `
        -InputDispatched $InputDispatched -TargetVisible $TargetVisible `
        -Details ([pscustomobject][ordered]@{
                watchdog_active = [bool]$Watchdog.active
                watchdog_faulted = [bool]$Watchdog.faulted
                watchdog_fault_code = [string]$Watchdog.fault_code
                native_error = [int]$Watchdog.native_error
            })
}

function Invoke-UnrealStartFailureCleanup {
    param(
        [AllowNull()]$Process,
        [IntPtr]$JobHandle,
        [IntPtr]$WindowHandle = [IntPtr]::Zero,
        [AllowNull()]$InputLease
    )

    try {
        if ($WindowHandle -ne [IntPtr]::Zero -and $Process) {
            $watchdogFaulted = $false
            $watchdogFaultCode = $null
            $nativeError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::StopInputWatchdog(
                $WindowHandle, [uint32]$Process.Id,
                [ref]$watchdogFaulted, [ref]$watchdogFaultCode, [ref]$nativeError)
        }
    }
    catch { }

    try {
        if ($WindowHandle -ne [IntPtr]::Zero -and $Process) {
            $nativeError = 0
            $validationCode = $null
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::PostCloseBound(
                $WindowHandle, [uint32]$Process.Id,
                [ref]$validationCode, [ref]$nativeError)
        }
        if ($Process -and -not $Process.HasExited) {
            [void]$Process.WaitForExit(500)
        }
    }
    catch { }

    if ($JobHandle -ne [IntPtr]::Zero) {
        try {
            $nativeError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TerminateJob(
                $JobHandle, [uint32]3758096385, [ref]$nativeError)
        }
        catch { }
        try {
            $nativeError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::CloseJob(
                $JobHandle, [ref]$nativeError)
        }
        catch { }
    }
    if ($Process) {
        try {
            if (-not $Process.HasExited) { $Process.Kill($true) }
        }
        catch { }
    }
    [void](Exit-UnrealInputLease -Lease $InputLease)
}

function Start-UnrealEvaluationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RunRoot,
        [string]$StatePath,
        [string]$ProcessToken,
        [object]$EngineReference,
        [string]$EngineRoot,
        [string]$EditorPath,
        [string]$LauncherManifestPath,
        [ValidateRange(320, 16384)][int]$WindowWidth = 1280,
        [ValidateRange(240, 16384)][int]$WindowHeight = 720,
        [ValidateRange(1000, 300000)][int]$TimeoutMs = 60000,
        [ValidateRange(0, 10000)][int]$FocusTimeoutMs = 1500,
        [switch]$ObserverDisabledControl,
        [string[]]$AdditionalArguments = @()
    )

    $operation = 'Start'
    if (-not $IsWindows) {
        return New-UnrealUnsupportedResult -Operation $operation -Code 'WINDOWS_PLATFORM_REQUIRED' `
            -Message 'The Unreal Windows executor is available only on Windows.'
    }

    $projectFull = Get-SafeFullPath -Path $ProjectPath -RequireLeaf
    if (-not $projectFull -or [IO.Path]::GetExtension($projectFull) -ine '.uproject') {
        return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'PROJECT_FILE_INVALID' `
            -Message 'The requested Unreal project file is unavailable or invalid.'
    }
    $runRootFull = Get-SafeFullPath -Path $RunRoot -RequireContainer
    if (-not $runRootFull) {
        return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'RUN_ROOT_INVALID' `
            -Message 'The run root is unavailable.'
    }

    $normalizedAdditionalArguments = [Collections.Generic.List[string]]::new()
    $argumentStatePath = $null
    $argumentProcessToken = $null
    $argumentObserverDisabled = $false
    foreach ($argument in @($AdditionalArguments)) {
        if ($null -eq $argument -or $argument.IndexOfAny([char[]]@("`r", "`n", [char]0)) -ge 0) {
            return New-UnrealExecutorFaultResult -Operation $operation -Code 'LAUNCH_ARGUMENT_INVALID' `
                -Message 'A launch argument is invalid.'
        }
        if ($argument -match '^-EvalStatePath=(.+)$') {
            $argumentStatePath = $Matches[1]
            continue
        }
        if ($argument -match '^-EvalProcessToken=(.+)$') {
            $argumentProcessToken = $Matches[1]
            continue
        }
        if ($argument -ieq '-EvalObserverDisabled') {
            $argumentObserverDisabled = $true
            continue
        }
        $normalizedAdditionalArguments.Add([string]$argument)
    }
    if ($argumentObserverDisabled) { $ObserverDisabledControl = $true }

    if (-not $StatePath) { $StatePath = $argumentStatePath }
    elseif ($argumentStatePath) {
        $explicitStateFull = Get-SafeFullPath -Path $StatePath
        $argumentStateFull = Get-SafeFullPath -Path $argumentStatePath
        if (-not $explicitStateFull -or -not $argumentStateFull -or
            $explicitStateFull -ine $argumentStateFull) {
            return New-UnrealExecutorFaultResult -Operation $operation -Code 'STATE_PATH_CONFLICT' `
                -Message 'The state path arguments do not identify the same file.'
        }
    }
    if (-not $StatePath) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'STATE_PATH_REQUIRED' `
            -Message 'A state path is required for the read-only observer.'
    }
    $stateFull = Get-SafeFullPath -Path $StatePath
    $stateParent = if ($stateFull) { Split-Path -Parent $stateFull } else { $null }
    if (-not $stateFull -or -not $stateParent -or
        -not (Test-Path -LiteralPath $stateParent -PathType Container)) {
        return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'STATE_PATH_INVALID' `
            -Message 'The state path parent is unavailable.'
    }
    $stateRelative = Get-SafeEvidenceRelativePath -Root $runRootFull -Path $stateFull
    if (-not $stateRelative) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'STATE_PATH_OUTSIDE_RUN_ROOT' `
            -Message 'The state path must remain inside the run root.'
    }
    if (-not $ProcessToken) { $ProcessToken = $argumentProcessToken }
    elseif ($argumentProcessToken -and $argumentProcessToken -cne $ProcessToken) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'PROCESS_TOKEN_CONFLICT' `
            -Message 'The process token arguments do not match.'
    }
    if (-not $ProcessToken) { $ProcessToken = 'process-' + [guid]::NewGuid().ToString('N') }
    if ($ProcessToken -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'PROCESS_TOKEN_INVALID' `
            -Message 'The process token is invalid.'
    }

    $engine = Get-UnrealEngineFromReference -EngineReference $EngineReference `
        -EngineRoot $EngineRoot -EditorPath $EditorPath -LauncherManifestPath $LauncherManifestPath
    if ($engine.Fault) {
        $status = switch ($engine.Fault.domain) {
            'unsupported' { 'unsupported' }
            'environment' { 'environment_fault' }
            default { 'executor_fault' }
        }
        return New-UnrealOperationResult -Operation $operation -Status $status -Fault $engine.Fault
    }

    $inputLease = Enter-UnrealInputLease
    if (-not $inputLease) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'ACTIVE_INPUT_SESSION_EXISTS' `
            -Message 'Another Unreal evaluation session currently owns the host input lease.' `
            -Retryable $true
    }
    if (Test-Path -LiteralPath $stateFull) {
        try {
            $stateItem = Get-Item -LiteralPath $stateFull -Force -ErrorAction Stop
            if (($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $stateItem.PSIsContainer) {
                [void](Exit-UnrealInputLease -Lease $inputLease)
                return New-UnrealExecutorFaultResult -Operation $operation `
                    -Code 'STATE_PATH_UNSAFE' `
                    -Message 'The existing state path is not a replaceable regular file.'
            }
            [IO.File]::Delete($stateFull)
        }
        catch {
            [void](Exit-UnrealInputLease -Lease $inputLease)
            return New-UnrealEnvironmentFaultResult -Operation $operation `
                -Code 'STALE_STATE_REMOVE_FAILED' `
                -Message 'The stale state snapshot could not be removed before launch.' `
                -Retryable $true
        }
    }

    $cursorX = 0
    $cursorY = 0
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetCursorPosition(
            [ref]$cursorX, [ref]$cursorY, [ref]$nativeError)) {
        [void](Exit-UnrealInputLease -Lease $inputLease)
        return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'CURSOR_POSITION_UNAVAILABLE' `
            -Message 'The original pointer position could not be recorded.' -Retryable $true `
            -Details ([pscustomobject]@{ native_error = [int]$nativeError })
    }
    $initialInputState = $null
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::QueryAllControlledInputState(
            [ref]$initialInputState, [ref]$nativeError)) {
        [void](Exit-UnrealInputLease -Lease $inputLease)
        return New-UnrealEnvironmentFaultResult -Operation $operation `
            -Code 'INPUT_STATE_QUERY_FAILED' `
            -Message 'The initial controlled keyboard and pointer state could not be queried.' `
            -Retryable $true -Details ([pscustomobject]@{ native_error = [int]$nativeError })
    }
    if ($initialInputState.AnyDown) {
        [void](Exit-UnrealInputLease -Lease $inputLease)
        return New-UnrealEnvironmentFaultResult -Operation $operation `
            -Code 'INPUT_STATE_NOT_NEUTRAL' `
            -Message 'A controlled key or pointer button was already down before the session.' `
            -Retryable $true -Details ([pscustomobject]@{
                    controlled_key_count = @($initialInputState.KeysDown).Count
                    controlled_mouse_button_count = @($initialInputState.MouseButtonsDown).Count
                })
    }

    $jobHandle = [IntPtr]::Zero
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::CreateKillOnCloseJob(
            [ref]$jobHandle, [ref]$nativeError)) {
        [void](Exit-UnrealInputLease -Lease $inputLease)
        return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'JOB_CREATE_FAILED' `
            -Message 'A process-tree job object could not be created.' -Retryable $true `
            -Details ([pscustomobject]@{ native_error = [int]$nativeError })
    }

    $process = $null
    $windowHandle = [IntPtr]::Zero
    try {
        $launchArguments = [Collections.Generic.List[string]]::new()
        $launchArguments.Add($projectFull)
        $launchArguments.Add('-game')
        $launchArguments.Add('-windowed')
        $launchArguments.Add("-ResX=$WindowWidth")
        $launchArguments.Add("-ResY=$WindowHeight")
        $launchArguments.Add('-NoSplash')
        foreach ($argument in $normalizedAdditionalArguments) {
            $launchArguments.Add($argument)
        }
        $launchArguments.Add("-EvalStatePath=$stateFull")
        $launchArguments.Add("-EvalProcessToken=$ProcessToken")
        if ($ObserverDisabledControl) {
            $launchArguments.Add('-EvalObserverDisabled')
        }

        $nativeError = 0
        if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::StartProcessSuspendedInJob(
                $jobHandle,
                $engine.Installation.EditorPath,
                [string[]]$launchArguments.ToArray(),
                (Split-Path -Parent $projectFull),
                [ref]$process,
                [ref]$nativeError)) {
            Invoke-UnrealStartFailureCleanup -Process $process -JobHandle $jobHandle `
                -InputLease $inputLease
            return New-UnrealEnvironmentFaultResult -Operation $operation `
                -Code 'SUSPENDED_PROCESS_START_FAILED' `
                -Message 'The Unreal process could not be created suspended, assigned to its job, and resumed.' `
                -Details ([pscustomobject]@{ native_error = [int]$nativeError })
        }

        $deadline = (Get-UnrealMonotonicMs) + $TimeoutMs
        $lastWindowWasVisible = $false
        $focusError = 0
        $snapshot = $null
        do {
            if ($process.HasExited) {
                Invoke-UnrealStartFailureCleanup -Process $process -JobHandle $jobHandle `
                    -InputLease $inputLease
                return New-UnrealEnvironmentFaultResult -Operation $operation `
                    -Code 'PROCESS_EXITED_DURING_START' `
                    -Message 'The Unreal process exited before a usable game window was bound.' -Retryable $true
            }

            $windows = @([VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::EnumerateVisibleTopLevelWindows(
                    [uint32]$process.Id))
            if ($windows.Count -gt 0) {
                $lastWindowWasVisible = $true
                $windowHandle = $windows[0].Handle
                $focusCode = $null
                [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RequestForegroundBound(
                    $windowHandle, [uint32]$process.Id,
                    [ref]$focusCode, [ref]$focusError)
                $validationCode = $null
                $nativeError = 0
                $snapshot = $null
                $valid = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetWindowSnapshot(
                    $windowHandle, [uint32]$process.Id, $true,
                    [ref]$snapshot, [ref]$validationCode, [ref]$nativeError)
                if ($valid) { break }
            }

            if ((Get-UnrealMonotonicMs) -ge $deadline) { break }
            Start-Sleep -Milliseconds 100
        } while ($true)

        if (-not $snapshot -or -not $snapshot.IsForeground) {
            Invoke-UnrealStartFailureCleanup -Process $process -JobHandle $jobHandle `
                -WindowHandle $windowHandle -InputLease $inputLease
            if ($lastWindowWasVisible) {
                return New-UnrealExecutorFaultResult -Operation $operation `
                    -Code 'FOREGROUND_ACQUISITION_TIMEOUT' `
                    -Message 'A game window appeared but foreground ownership could not be confirmed.' `
                    -TargetVisible $true -Retryable $true `
                    -Details ([pscustomobject]@{ native_error = [int]$focusError })
            }
            return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'WINDOW_DISCOVERY_TIMEOUT' `
                -Message 'No usable top-level game window appeared before the startup timeout.' `
                -Retryable $true
        }

        $activeProcessCount = 0
        $nativeError = 0
        if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetJobActiveProcessCount(
                $jobHandle, [ref]$activeProcessCount, [ref]$nativeError) -or $activeProcessCount -lt 1) {
            Invoke-UnrealStartFailureCleanup -Process $process -JobHandle $jobHandle `
                -WindowHandle $windowHandle -InputLease $inputLease
            return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'JOB_ACCOUNTING_FAILED' `
                -Message 'The Unreal process tree could not be confirmed in its job object.' `
                -Details ([pscustomobject]@{ native_error = [int]$nativeError })
        }

        $sessionId = 'session-' + [guid]::NewGuid().ToString('N')
        $windowToken = 'window-' + [guid]::NewGuid().ToString('N')
        $state = [pscustomobject]@{
            SessionId = $sessionId
            ProcessId = [int]$process.Id
            ProcessToken = $ProcessToken
            WindowToken = $windowToken
            WindowHandle = $windowHandle
            Process = $process
            JobHandle = $jobHandle
            ProjectPath = $projectFull
            EditorPath = $engine.Installation.EditorPath
            EngineRoot = $engine.Installation.EngineRoot
            StatePath = $stateFull
            StateRelativePath = $stateRelative
            RunRoot = $runRootFull
            WindowWidth = $WindowWidth
            WindowHeight = $WindowHeight
            FocusTimeoutMs = $FocusTimeoutMs
            AdditionalArguments = @($normalizedAdditionalArguments)
            ObserverDisabledControl = [bool]$ObserverDisabledControl
            OriginalCursorX = [int]$cursorX
            OriginalCursorY = [int]$cursorY
            CursorRestored = $false
            HeldKeys = @{}
            HeldMouseButtons = @{}
            InputLease = $inputLease
            Stopped = $false
        }

        $readyRead = $null
        $windowStabilitySamples = 0
        do {
            try {
                if ($process.HasExited) { break }
            }
            catch { break }
            if ($ObserverDisabledControl) {
                $controlValidation = Test-UnrealTargetWindow -State $state
                if ($controlValidation.ok) {
                    ++$windowStabilitySamples
                    if ($windowStabilitySamples -ge 3) { break }
                }
                else {
                    $windowStabilitySamples = 0
                }
            }
            else {
                $candidate = Read-UnrealStateSnapshotDirect -State $state
                if ($candidate.status -eq 'ok' -and
                    [int]$candidate.result.snapshot.process_id -eq [int]$process.Id -and
                    $candidate.result.snapshot.ready -is [bool] -and
                    [bool]$candidate.result.snapshot.ready -and
                    $candidate.result.snapshot.first_frame -is [bool] -and
                    [bool]$candidate.result.snapshot.first_frame) {
                    $readyRead = $candidate
                    break
                }
            }
            if ((Get-UnrealMonotonicMs) -ge $deadline) { break }
            Start-Sleep -Milliseconds 50
        } while ($true)
        if ((-not $ObserverDisabledControl -and -not $readyRead) -or
            ($ObserverDisabledControl -and $windowStabilitySamples -lt 3)) {
            Invoke-UnrealStartFailureCleanup -Process $process -JobHandle $jobHandle `
                -WindowHandle $windowHandle -InputLease $inputLease
            return New-UnrealEnvironmentFaultResult -Operation $operation `
                -Code $(if ($ObserverDisabledControl) {
                        'CONTROL_WINDOW_STABILITY_TIMEOUT'
                    }
                    else { 'FIRST_FRAME_STATE_TIMEOUT' }) `
                -Message $(if ($ObserverDisabledControl) {
                        'The observer-disabled control window did not remain stable before timeout.'
                    }
                    else {
                        'The current process did not publish a ready first-frame state before timeout.'
                    }) `
                -Retryable $true
        }

        $watchdogValidationCode = $null
        $nativeError = 0
        if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::ClearInputWatchdog(
                $windowHandle, [uint32]$process.Id,
                [ref]$watchdogValidationCode, [ref]$nativeError)) {
            Invoke-UnrealStartFailureCleanup -Process $process -JobHandle $jobHandle `
                -WindowHandle $windowHandle -InputLease $inputLease
            return New-UnrealExecutorFaultResult -Operation $operation `
                -Code 'INPUT_WATCHDOG_INITIALIZATION_FAILED' `
                -Message 'The input focus watchdog could not be initialized for the bound target.' `
                -TargetVisible $true -Details ([pscustomobject]@{
                        validation_code = $watchdogValidationCode
                        native_error = [int]$nativeError
                    })
        }

        $script:Sessions[$sessionId] = $state
        $handle = [VibeGaming.UnrealEvaluation.UnrealEvaluationSessionHandle]::new(
            $sessionId, [int]$process.Id, $windowToken, $ProcessToken)

        return New-UnrealOperationResult -Operation $operation -Status ok -TargetVisible $true `
            -Result ([pscustomobject][ordered]@{
                    session = $handle
                    session_id = $sessionId
                    process_id = [int]$process.Id
                    process_token = $ProcessToken
                    window_handle_token = $windowToken
                    client_size = [pscustomobject]@{
                        width = [int]$snapshot.ClientWidth
                        height = [int]$snapshot.ClientHeight
                    }
                    coordinate_space = [string]$snapshot.CoordinateSpace
                    window_dpi = [int]$snapshot.Dpi
                    state_path = if ($ObserverDisabledControl) { $null } else { $stateRelative }
                    initial_snapshot_id = if ($readyRead) {
                        [long]$readyRead.result.snapshot.snapshot_id
                    }
                    else { $null }
                    initial_round_id = if ($readyRead) {
                        [string]$readyRead.result.snapshot.round_id
                    }
                    else { $null }
                    state_first_frame_confirmed = (-not $ObserverDisabledControl)
                    stable_visible_frame_confirmed = $false
                    observer_disabled_control = [bool]$ObserverDisabledControl
                    launch_mode = 'editor_game'
                    process_containment = 'suspended_job_before_resume'
                    job_active_process_count = [int]$activeProcessCount
                })
    }
    catch {
        Invoke-UnrealStartFailureCleanup -Process $process -JobHandle $jobHandle `
            -WindowHandle $windowHandle -InputLease $inputLease
        return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'PROCESS_START_FAILED' `
            -Message 'The Unreal editor game process could not be started.' -Retryable $true
    }
}

function Resolve-UnrealKeyDefinition {
    param([Parameter(Mandatory)][string]$Key)

    $normalized = $Key.Trim().Replace(' ', '').Replace('-', '').Replace('_', '').ToUpperInvariant()
    if ($script:VirtualKeys.ContainsKey($normalized)) {
        return $script:VirtualKeys[$normalized]
    }
    if ($normalized -match '^[A-Z]$') {
        return @{ Canonical = $normalized; VirtualKey = [uint16][char]$normalized; Extended = $false }
    }
    if ($normalized -match '^[0-9]$') {
        return @{ Canonical = $normalized; VirtualKey = [uint16][char]$normalized; Extended = $false }
    }
    if ($normalized -match '^F([1-9]|1[0-9]|2[0-4])$') {
        $functionNumber = [int]$Matches[1]
        return @{
            Canonical = "F$functionNumber"
            VirtualKey = [uint16](0x70 + $functionNumber - 1)
            Extended = $false
        }
    }
    return $null
}

function Resolve-UnrealMouseButton {
    param([Parameter(Mandatory)][string]$Button)

    switch ($Button.Trim().Replace(' ', '').Replace('-', '').Replace('_', '').ToLowerInvariant()) {
        'left' { return 'left' }
        'leftbutton' { return 'left' }
        'right' { return 'right' }
        'rightbutton' { return 'right' }
        'middle' { return 'middle' }
        'middlebutton' { return 'middle' }
        'x1' { return 'x1' }
        'x2' { return 'x2' }
        default { return $null }
    }
}

function Get-UnrealScreenPoint {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][double]$NormalizedX,
        [Parameter(Mandatory)][double]$NormalizedY
    )

    if ([double]::IsNaN($NormalizedX) -or [double]::IsInfinity($NormalizedX) -or
        [double]::IsNaN($NormalizedY) -or [double]::IsInfinity($NormalizedY) -or
        $NormalizedX -lt 0 -or $NormalizedX -gt 1 -or
        $NormalizedY -lt 0 -or $NormalizedY -gt 1) {
        return $null
    }
    $clientX = [Math]::Min($Snapshot.ClientWidth - 1,
        [Math]::Max(0, [int][Math]::Floor($NormalizedX * $Snapshot.ClientWidth)))
    $clientY = [Math]::Min($Snapshot.ClientHeight - 1,
        [Math]::Max(0, [int][Math]::Floor($NormalizedY * $Snapshot.ClientHeight)))
    [pscustomobject]@{
        normalized_x = $NormalizedX
        normalized_y = $NormalizedY
        client_x = $clientX
        client_y = $clientY
        screen_x = [int]$Snapshot.ClientLeft + $clientX
        screen_y = [int]$Snapshot.ClientTop + $clientY
    }
}

function Get-UnrealVisibleTargetsFromSnapshot {
    param([AllowNull()]$Snapshot)

    if ($null -eq $Snapshot) { return @() }
    foreach ($propertyName in @('visible_targets', 'targets')) {
        if ($Snapshot.PSObject.Properties[$propertyName]) {
            return @($Snapshot.$propertyName)
        }
    }
    if ($Snapshot.PSObject.Properties['ui'] -and $Snapshot.ui -and
        $Snapshot.ui.PSObject.Properties['visible_targets']) {
        return @($Snapshot.ui.visible_targets)
    }
    return @()
}

function Read-UnrealStateSnapshotDirect {
    param(
        [Parameter(Mandatory)]$State,
        [int]$MaxBytes = 1048576
    )

    if (-not (Test-Path -LiteralPath $State.StatePath -PathType Leaf)) {
        return New-UnrealExecutorFaultResult -Operation 'ReadState' `
            -Code 'STATE_FILE_UNAVAILABLE' -Message 'The read-only state snapshot is unavailable.' `
            -Retryable $true
    }

    try {
        $file = Get-Item -LiteralPath $State.StatePath -ErrorAction Stop
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_FILE_REPARSE_POINT' `
                -Message 'The read-only state snapshot cannot be a reparse point.'
        }
        if ($file.Length -le 1 -or $file.Length -gt $MaxBytes) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_FILE_SIZE_INVALID' `
                -Message 'The read-only state snapshot has an invalid size.' -Retryable $true
        }
        $bytes = [IO.File]::ReadAllBytes($State.StatePath)
        if ($bytes.Length -ne $file.Length) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_FILE_CHANGED_DURING_READ' `
                -Message 'The read-only state snapshot changed during the read.' -Retryable $true
        }
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $text = $utf8.GetString($bytes)
        $snapshot = $text | ConvertFrom-Json -Depth 64 -ErrorAction Stop
        if (-not $snapshot.PSObject.Properties['schema_version'] -or
            [string]$snapshot.schema_version -cne $script:SchemaVersion) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_SCHEMA_UNSUPPORTED' `
                -Message 'The state snapshot schema version is missing or unsupported.'
        }
        if (-not $snapshot.PSObject.Properties['process_token'] -or
            [string]$snapshot.process_token -cne [string]$State.ProcessToken) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_PROCESS_TOKEN_MISMATCH' `
                -Message 'The state snapshot does not belong to the active process token.'
        }
        if (-not $snapshot.PSObject.Properties['process_id'] -or
            [int64]$snapshot.process_id -ne [int64]$State.ProcessId) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_PROCESS_ID_MISMATCH' `
                -Message 'The state snapshot does not belong to the bound process identifier.'
        }
        foreach ($required in @('snapshot_id', 'round_id', 'monotonic_ms')) {
            if (-not $snapshot.PSObject.Properties[$required] -or $null -eq $snapshot.$required) {
                return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                    -Code 'STATE_REQUIRED_FIELD_MISSING' `
                -Message 'The state snapshot is missing a required identity or clock field.'
            }
        }
        if (-not $snapshot.PSObject.Properties['object'] -or -not $snapshot.object -or
            -not $snapshot.object.PSObject.Properties['object_id'] -or
            $null -eq $snapshot.object.object_id) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_REQUIRED_FIELD_MISSING' `
                -Message 'The state snapshot is missing the observed object identity.'
        }
        if ([long]$snapshot.monotonic_ms -lt 0) {
            return New-UnrealExecutorFaultResult -Operation 'ReadState' `
                -Code 'STATE_MONOTONIC_TIME_INVALID' `
                -Message 'The state snapshot monotonic time is invalid.'
        }
        return New-UnrealOperationResult -Operation 'ReadState' -Status ok -FeedbackObserved $true `
            -Result ([pscustomobject][ordered]@{
                    snapshot = $snapshot
                    state_path = $State.StateRelativePath
                    byte_length = [long]$bytes.Length
                    process_token_match = $true
                })
    }
    catch {
        return New-UnrealExecutorFaultResult -Operation 'ReadState' `
            -Code 'STATE_READ_FAILED' -Message 'The read-only state snapshot could not be parsed.' `
            -Retryable $true
    }
}

function Read-UnrealEvaluationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [ValidateRange(1024, 16777216)][int]$MaxBytes = 1048576
    )

    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation 'ReadState' -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $watchdog = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdog.ok -or $watchdog.faulted) {
        return New-UnrealWatchdogFaultResult -Operation 'ReadState' -Watchdog $watchdog
    }
    return Read-UnrealStateSnapshotDirect -State $state -MaxBytes $MaxBytes
}

function Wait-UnrealEvaluationCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][scriptblock]$Predicate,
        [ValidateRange(1, 300000)][int]$TimeoutMs = 5000,
        [ValidateRange(10, 60000)][int]$IntervalMs = 50,
        [ValidateRange(1, 10000)][int]$MaximumSamples = 200
    )

    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation 'WaitUntil' -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $watchdog = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdog.ok -or $watchdog.faulted) {
        return New-UnrealWatchdogFaultResult -Operation 'WaitUntil' -Watchdog $watchdog
    }
    $samples = [Collections.Generic.List[object]]::new()
    $started = Get-UnrealMonotonicMs
    $deadline = $started + $TimeoutMs
    while ($samples.Count -lt $MaximumSamples) {
        $watchdog = Get-UnrealInputWatchdogState -State $state
        if (-not $watchdog.ok -or $watchdog.faulted) {
            return New-UnrealWatchdogFaultResult -Operation 'WaitUntil' -Watchdog $watchdog
        }
        $read = Read-UnrealStateSnapshotDirect -State $state
        if ($read.status -ne 'ok') {
            return New-UnrealOperationResult -Operation 'WaitUntil' -Status executor_fault `
                -Result ([pscustomobject]@{
                        termination_reason = 'observer_fault'
                        sample_count = $samples.Count
                        samples = @($samples)
                    }) -Fault $read.fault
        }
        $sample = [pscustomobject][ordered]@{
            sample_index = $samples.Count
            observed_monotonic_ms = Get-UnrealMonotonicMs
            snapshot_monotonic_ms = [long]$read.result.snapshot.monotonic_ms
            process_token = [string]$read.result.snapshot.process_token
            round_id = $read.result.snapshot.round_id
            object_id = $read.result.snapshot.object.object_id
            matched = $false
        }
        try {
            $sample.matched = [bool](& $Predicate $read.result.snapshot)
        }
        catch {
            return New-UnrealExecutorFaultResult -Operation 'WaitUntil' `
                -Code 'WAIT_PREDICATE_FAILED' -Message 'The wait predicate raised an error.' `
                -Result ([pscustomobject]@{
                        termination_reason = 'predicate_fault'
                        sample_count = $samples.Count
                        samples = @($samples)
                    })
        }
        $samples.Add($sample)
        if ($sample.matched) {
            $watchdogAfterMatch = Get-UnrealInputWatchdogState -State $state
            if (-not $watchdogAfterMatch.ok -or $watchdogAfterMatch.faulted) {
                return New-UnrealWatchdogFaultResult -Operation 'WaitUntil' `
                    -Watchdog $watchdogAfterMatch
            }
            return New-UnrealOperationResult -Operation 'WaitUntil' -Status ok `
                -FeedbackObserved $true -Result ([pscustomobject][ordered]@{
                        termination_reason = 'condition_met'
                        elapsed_ms = (Get-UnrealMonotonicMs) - $started
                        sample_count = $samples.Count
                        samples = @($samples)
                        snapshot = $read.result.snapshot
                    })
        }
        if ((Get-UnrealMonotonicMs) -ge $deadline) { break }
        Start-Sleep -Milliseconds $IntervalMs
    }

    $watchdogAfterWait = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogAfterWait.ok -or $watchdogAfterWait.faulted) {
        return New-UnrealWatchdogFaultResult -Operation 'WaitUntil' -Watchdog $watchdogAfterWait
    }
    New-UnrealOperationResult -Operation 'WaitUntil' -Status timeout -FeedbackObserved $false `
        -Result ([pscustomobject][ordered]@{
                termination_reason = if ($samples.Count -ge $MaximumSamples) {
                    'maximum_samples_reached'
                }
                else { 'timeout' }
                elapsed_ms = (Get-UnrealMonotonicMs) - $started
                sample_count = $samples.Count
                samples = @($samples)
            }) `
        -Fault (New-UnrealFault -Domain executor -Code 'WAIT_CONDITION_TIMEOUT' `
            -Message 'The bounded wait ended before its condition was observed.' -Retryable $true)
}

function Start-UnrealKeyHold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Key
    )

    $operation = 'HoldKey'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $definition = Resolve-UnrealKeyDefinition -Key $Key
    if (-not $definition) {
        return New-UnrealUnsupportedResult -Operation $operation -Code 'KEY_UNSUPPORTED' `
            -Message 'The requested key is not in the public physical-key mapping.'
    }
    if ($state.HeldKeys.ContainsKey($definition.Canonical)) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'KEY_ALREADY_HELD' `
            -Message 'The requested key is already held by this session.'
    }
    $watchdog = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdog.ok -or $watchdog.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation -Watchdog $watchdog
    }
    $validation = Test-UnrealTargetWindow -State $state -AcquireForeground `
        -FocusTimeoutMs $state.FocusTimeoutMs
    if (-not $validation.ok) {
        return New-UnrealWindowFaultResult -Operation $operation -Validation $validation
    }
    $inputDispatched = $false
    $validationCode = $null
    $nativeError = 0
    $sent = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboardBound(
        $state.WindowHandle, [uint32]$state.ProcessId,
        [uint16]$definition.VirtualKey, $false, [bool]$definition.Extended,
        [ref]$inputDispatched, [ref]$validationCode, [ref]$nativeError)
    if (-not $sent) {
        $watchdogAfterFailure = Get-UnrealInputWatchdogState -State $state
        if (-not $watchdogAfterFailure.ok -or $watchdogAfterFailure.faulted) {
            return New-UnrealWatchdogFaultResult -Operation $operation `
                -Watchdog $watchdogAfterFailure -InputDispatched $inputDispatched `
                -TargetVisible $false
        }
        $emergencyReleased = $false
        if ($inputDispatched) {
            $cleanupError = 0
            $emergencyReleased = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboard(
                [uint16]$definition.VirtualKey, $true, [bool]$definition.Extended,
                [ref]$cleanupError)
        }
        return New-UnrealBoundNativeFaultResult -Operation $operation `
            -FallbackCode 'KEY_DOWN_BOUND_DISPATCH_FAILED' `
            -Message 'The bound key-down transaction did not complete safely.' `
            -ValidationCode $validationCode -NativeError $nativeError `
            -InputDispatched $inputDispatched -TargetVisible $true
    }
    $state.HeldKeys[$definition.Canonical] = $definition
    $watchdogAfterDispatch = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogAfterDispatch.ok -or $watchdogAfterDispatch.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogAfterDispatch -InputDispatched $true -TargetVisible $false
    }
    New-UnrealOperationResult -Operation $operation -Status ok -InputDispatched $true `
        -TargetVisible $true -Result ([pscustomobject][ordered]@{
                key = $definition.Canonical
                edge = 'down'
                held = $true
                window_handle_token = $state.WindowToken
                process_token = $state.ProcessToken
            })
}

function Stop-UnrealKeyHold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Key,
        [switch]$Cleanup
    )

    $operation = 'ReleaseKey'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $definition = Resolve-UnrealKeyDefinition -Key $Key
    if (-not $definition) {
        return New-UnrealUnsupportedResult -Operation $operation -Code 'KEY_UNSUPPORTED' `
            -Message 'The requested key is not in the public physical-key mapping.'
    }
    if (-not $state.HeldKeys.ContainsKey($definition.Canonical)) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'KEY_NOT_HELD' `
            -Message 'The requested key is not held by this session.'
    }

    $watchdogBeforeRelease = Get-UnrealInputWatchdogState -State $state
    if ($watchdogBeforeRelease.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogBeforeRelease -InputDispatched $true -TargetVisible $false
    }
    if (-not $watchdogBeforeRelease.ok) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogBeforeRelease -InputDispatched $true
    }

    $validation = Test-UnrealTargetWindow -State $state -AcquireForeground `
        -FocusTimeoutMs $state.FocusTimeoutMs
    $inputDispatched = $false
    $validationCode = if ($validation.ok) { $null } else { [string]$validation.code }
    $nativeError = 0
    $sent = if ($validation.ok) {
        [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboardBound(
            $state.WindowHandle, [uint32]$state.ProcessId,
            [uint16]$definition.VirtualKey, $true, [bool]$definition.Extended,
            [ref]$inputDispatched, [ref]$validationCode, [ref]$nativeError)
    }
    else { $false }
    $emergencyReleased = $false
    if (-not $sent) {
        $watchdogAfterFailure = Get-UnrealInputWatchdogState -State $state
        if (-not $watchdogAfterFailure.ok -or $watchdogAfterFailure.faulted) {
            return New-UnrealWatchdogFaultResult -Operation $operation `
                -Watchdog $watchdogAfterFailure -InputDispatched $inputDispatched `
                -TargetVisible $validation.target_visible
        }
        $cleanupError = 0
        $emergencyReleased = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboard(
            [uint16]$definition.VirtualKey, $true, [bool]$definition.Extended,
            [ref]$cleanupError)
        if ($emergencyReleased) { $inputDispatched = $true }
    }
    if ($sent -or $emergencyReleased) { $state.HeldKeys.Remove($definition.Canonical) }
    if (-not $sent) {
        if ($emergencyReleased) {
            return New-UnrealExecutorFaultResult -Operation $operation `
                -Code 'KEY_UP_REQUIRED_EMERGENCY_RELEASE' `
                -Message 'The bound key-up failed; an unbound emergency release prevented a stuck key.' `
                -InputDispatched $true -TargetVisible $validation.target_visible `
                -Details ([pscustomobject]@{
                        validation_code = $validationCode
                        native_error = [int]$nativeError
                        cleanup = [bool]$Cleanup
                        emergency_release = $true
                    })
        }
        return New-UnrealBoundNativeFaultResult -Operation $operation `
            -FallbackCode 'KEY_UP_BOUND_DISPATCH_FAILED' `
            -Message 'The bound key-up transaction did not complete safely.' `
            -ValidationCode $validationCode -NativeError $nativeError `
            -InputDispatched $inputDispatched -TargetVisible $validation.target_visible
    }
    $watchdogAfterRelease = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogAfterRelease.ok -or $watchdogAfterRelease.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogAfterRelease -InputDispatched $true `
            -TargetVisible $validation.target_visible
    }
    New-UnrealOperationResult -Operation $operation -Status ok -InputDispatched $true `
        -TargetVisible $validation.target_visible -Result ([pscustomobject][ordered]@{
                key = $definition.Canonical
                edge = 'up'
                held = $false
                cleanup = [bool]$Cleanup
                emergency_release = $false
                window_handle_token = $state.WindowToken
                process_token = $state.ProcessToken
            })
}

function Invoke-UnrealPressKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Key,
        [ValidateRange(0, 60000)][int]$DurationMs = 40
    )

    $down = Start-UnrealKeyHold -Session $Session -Key $Key
    if ($down.status -ne 'ok') {
        $down.operation = 'PressKey'
        return $down
    }
    try {
        if ($DurationMs -gt 0) { Start-Sleep -Milliseconds $DurationMs }
    }
    finally {
        $up = Stop-UnrealKeyHold -Session $Session -Key $Key -Cleanup
    }
    if ($up.status -ne 'ok') {
        $up.operation = 'PressKey'
        $up.input_dispatched = $true
        return $up
    }
    New-UnrealOperationResult -Operation 'PressKey' -Status ok -InputDispatched $true `
        -TargetVisible $true -Result ([pscustomobject][ordered]@{
                key = $down.result.key
                duration_ms = $DurationMs
                down_monotonic_ms = $down.observer_monotonic_ms
                up_monotonic_ms = $up.observer_monotonic_ms
                window_handle_token = $down.result.window_handle_token
                process_token = $down.result.process_token
            })
}

function Move-UnrealPointer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$NormalizedX,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$NormalizedY
    )

    $operation = 'MovePointer'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $watchdog = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdog.ok -or $watchdog.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation -Watchdog $watchdog
    }
    $validation = Test-UnrealTargetWindow -State $state -AcquireForeground `
        -FocusTimeoutMs $state.FocusTimeoutMs
    if (-not $validation.ok) {
        return New-UnrealWindowFaultResult -Operation $operation -Validation $validation
    }
    $dispatchSnapshot = $null
    $screenX = 0
    $screenY = 0
    $inputDispatched = $false
    $validationCode = $null
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendMouseMoveBound(
            $state.WindowHandle, [uint32]$state.ProcessId,
            [double]$NormalizedX, [double]$NormalizedY,
            [ref]$dispatchSnapshot, [ref]$screenX, [ref]$screenY,
            [ref]$inputDispatched, [ref]$validationCode, [ref]$nativeError)) {
        $watchdogAfterFailure = Get-UnrealInputWatchdogState -State $state
        if (-not $watchdogAfterFailure.ok -or $watchdogAfterFailure.faulted) {
            return New-UnrealWatchdogFaultResult -Operation $operation `
                -Watchdog $watchdogAfterFailure -InputDispatched $inputDispatched `
                -TargetVisible $false
        }
        return New-UnrealBoundNativeFaultResult -Operation $operation `
            -FallbackCode 'POINTER_MOVE_BOUND_DISPATCH_FAILED' `
            -Message 'The bound pointer-move transaction did not complete safely.' `
            -ValidationCode $validationCode -NativeError $nativeError `
            -InputDispatched $inputDispatched -TargetVisible $true
    }
    $watchdogAfterDispatch = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogAfterDispatch.ok -or $watchdogAfterDispatch.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogAfterDispatch -InputDispatched $true -TargetVisible $false
    }
    $clientX = $screenX - [int]$dispatchSnapshot.ClientLeft
    $clientY = $screenY - [int]$dispatchSnapshot.ClientTop
    New-UnrealOperationResult -Operation $operation -Status ok -InputDispatched $true `
        -TargetVisible $true -Result ([pscustomobject][ordered]@{
                normalized_x = $NormalizedX
                normalized_y = $NormalizedY
                client_x = $clientX
                client_y = $clientY
                coordinate_space = [string]$dispatchSnapshot.CoordinateSpace
                window_dpi = [int]$dispatchSnapshot.Dpi
                window_handle_token = $state.WindowToken
                process_token = $state.ProcessToken
            })
}

function Start-UnrealMouseHold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Button
    )

    $operation = 'MouseDown'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $buttonName = Resolve-UnrealMouseButton -Button $Button
    if (-not $buttonName) {
        return New-UnrealUnsupportedResult -Operation $operation -Code 'MOUSE_BUTTON_UNSUPPORTED' `
            -Message 'The requested pointer button is not supported.'
    }
    if ($state.HeldMouseButtons.ContainsKey($buttonName)) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'MOUSE_BUTTON_ALREADY_HELD' `
            -Message 'The requested pointer button is already held by this session.'
    }
    $watchdog = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdog.ok -or $watchdog.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation -Watchdog $watchdog
    }
    $validation = Test-UnrealTargetWindow -State $state -AcquireForeground `
        -FocusTimeoutMs $state.FocusTimeoutMs
    if (-not $validation.ok) {
        return New-UnrealWindowFaultResult -Operation $operation -Validation $validation
    }
    $inputDispatched = $false
    $validationCode = $null
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendMouseButtonBound(
            $state.WindowHandle, [uint32]$state.ProcessId,
            $buttonName, $false, [ref]$inputDispatched,
            [ref]$validationCode, [ref]$nativeError)) {
        $watchdogAfterFailure = Get-UnrealInputWatchdogState -State $state
        if (-not $watchdogAfterFailure.ok -or $watchdogAfterFailure.faulted) {
            return New-UnrealWatchdogFaultResult -Operation $operation `
                -Watchdog $watchdogAfterFailure -InputDispatched $inputDispatched `
                -TargetVisible $false
        }
        if ($inputDispatched) {
            $cleanupError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendMouseButton(
                $buttonName, $true, [ref]$cleanupError)
        }
        return New-UnrealBoundNativeFaultResult -Operation $operation `
            -FallbackCode 'MOUSE_DOWN_BOUND_DISPATCH_FAILED' `
            -Message 'The bound pointer button-down transaction did not complete safely.' `
            -ValidationCode $validationCode -NativeError $nativeError `
            -InputDispatched $inputDispatched -TargetVisible $true
    }
    $state.HeldMouseButtons[$buttonName] = $true
    $watchdogAfterDispatch = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogAfterDispatch.ok -or $watchdogAfterDispatch.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogAfterDispatch -InputDispatched $true -TargetVisible $false
    }
    New-UnrealOperationResult -Operation $operation -Status ok -InputDispatched $true `
        -TargetVisible $true -Result ([pscustomobject][ordered]@{
                button = $buttonName
                edge = 'down'
                held = $true
                window_handle_token = $state.WindowToken
                process_token = $state.ProcessToken
            })
}

function Stop-UnrealMouseHold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Button,
        [switch]$Cleanup
    )

    $operation = 'MouseUp'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $buttonName = Resolve-UnrealMouseButton -Button $Button
    if (-not $buttonName) {
        return New-UnrealUnsupportedResult -Operation $operation -Code 'MOUSE_BUTTON_UNSUPPORTED' `
            -Message 'The requested pointer button is not supported.'
    }
    if (-not $state.HeldMouseButtons.ContainsKey($buttonName)) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'MOUSE_BUTTON_NOT_HELD' `
            -Message 'The requested pointer button is not held by this session.'
    }
    $watchdogBeforeRelease = Get-UnrealInputWatchdogState -State $state
    if ($watchdogBeforeRelease.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogBeforeRelease -InputDispatched $true -TargetVisible $false
    }
    if (-not $watchdogBeforeRelease.ok) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogBeforeRelease -InputDispatched $true
    }
    $validation = Test-UnrealTargetWindow -State $state -AcquireForeground `
        -FocusTimeoutMs $state.FocusTimeoutMs
    $inputDispatched = $false
    $validationCode = if ($validation.ok) { $null } else { [string]$validation.code }
    $nativeError = 0
    $sent = if ($validation.ok) {
        [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendMouseButtonBound(
            $state.WindowHandle, [uint32]$state.ProcessId,
            $buttonName, $true, [ref]$inputDispatched,
            [ref]$validationCode, [ref]$nativeError)
    }
    else { $false }
    $emergencyReleased = $false
    if (-not $sent) {
        $watchdogAfterFailure = Get-UnrealInputWatchdogState -State $state
        if (-not $watchdogAfterFailure.ok -or $watchdogAfterFailure.faulted) {
            return New-UnrealWatchdogFaultResult -Operation $operation `
                -Watchdog $watchdogAfterFailure -InputDispatched $inputDispatched `
                -TargetVisible $validation.target_visible
        }
        $cleanupError = 0
        $emergencyReleased = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendMouseButton(
            $buttonName, $true, [ref]$cleanupError)
        if ($emergencyReleased) { $inputDispatched = $true }
    }
    if ($sent -or $emergencyReleased) { $state.HeldMouseButtons.Remove($buttonName) }
    if (-not $sent) {
        if ($emergencyReleased) {
            return New-UnrealExecutorFaultResult -Operation $operation `
                -Code 'MOUSE_UP_REQUIRED_EMERGENCY_RELEASE' `
                -Message 'The bound pointer button-up failed; an unbound emergency release prevented a stuck button.' `
                -InputDispatched $true -TargetVisible $validation.target_visible `
                -Details ([pscustomobject]@{
                        validation_code = $validationCode
                        native_error = [int]$nativeError
                        cleanup = [bool]$Cleanup
                        emergency_release = $true
                    })
        }
        return New-UnrealBoundNativeFaultResult -Operation $operation `
            -FallbackCode 'MOUSE_UP_BOUND_DISPATCH_FAILED' `
            -Message 'The bound pointer button-up transaction did not complete safely.' `
            -ValidationCode $validationCode -NativeError $nativeError `
            -InputDispatched $inputDispatched -TargetVisible $validation.target_visible
    }
    $watchdogAfterRelease = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogAfterRelease.ok -or $watchdogAfterRelease.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogAfterRelease -InputDispatched $true `
            -TargetVisible $validation.target_visible
    }
    New-UnrealOperationResult -Operation $operation -Status ok -InputDispatched $true `
        -TargetVisible $validation.target_visible -Result ([pscustomobject][ordered]@{
                button = $buttonName
                edge = 'up'
                held = $false
                cleanup = [bool]$Cleanup
                emergency_release = $false
                window_handle_token = $state.WindowToken
                process_token = $state.ProcessToken
            })
}

function Invoke-UnrealClick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$NormalizedX,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$NormalizedY,
        [string]$Button = 'Left',
        [ValidateRange(0, 60000)][int]$DurationMs = 40
    )

    $move = Move-UnrealPointer -Session $Session -NormalizedX $NormalizedX -NormalizedY $NormalizedY
    if ($move.status -ne 'ok') {
        $move.operation = 'Click'
        return $move
    }
    $down = Start-UnrealMouseHold -Session $Session -Button $Button
    if ($down.status -ne 'ok') {
        $down.operation = 'Click'
        $down.input_dispatched = $true
        return $down
    }
    try {
        if ($DurationMs -gt 0) { Start-Sleep -Milliseconds $DurationMs }
    }
    finally {
        $up = Stop-UnrealMouseHold -Session $Session -Button $Button -Cleanup
    }
    if ($up.status -ne 'ok') {
        $up.operation = 'Click'
        $up.input_dispatched = $true
        return $up
    }
    New-UnrealOperationResult -Operation 'Click' -Status ok -InputDispatched $true `
        -TargetVisible $true -Result ([pscustomobject][ordered]@{
                normalized_x = $NormalizedX
                normalized_y = $NormalizedY
                client_x = $move.result.client_x
                client_y = $move.result.client_y
                button = $down.result.button
                duration_ms = $DurationMs
                window_handle_token = $down.result.window_handle_token
                process_token = $down.result.process_token
            })
}

function Invoke-UnrealDrag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$StartX,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$StartY,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$EndX,
        [Parameter(Mandatory)][ValidateRange(0, 1)][double]$EndY,
        [string]$Button = 'Left',
        [ValidateRange(1, 60000)][int]$DurationMs = 500,
        [ValidateRange(1, 1000)][int]$Steps = 10
    )

    $moveStart = Move-UnrealPointer -Session $Session -NormalizedX $StartX -NormalizedY $StartY
    if ($moveStart.status -ne 'ok') {
        $moveStart.operation = 'Drag'
        return $moveStart
    }
    $down = Start-UnrealMouseHold -Session $Session -Button $Button
    if ($down.status -ne 'ok') {
        $down.operation = 'Drag'
        $down.input_dispatched = $true
        return $down
    }
    $moves = [Collections.Generic.List[object]]::new()
    $moveFault = $null
    try {
        $stepDelay = [int][Math]::Floor($DurationMs / $Steps)
        for ($index = 1; $index -le $Steps; $index++) {
            $fraction = $index / [double]$Steps
            $x = $StartX + (($EndX - $StartX) * $fraction)
            $y = $StartY + (($EndY - $StartY) * $fraction)
            $move = Move-UnrealPointer -Session $Session -NormalizedX $x -NormalizedY $y
            if ($move.status -ne 'ok') {
                $moveFault = $move
                break
            }
            $moves.Add([pscustomobject]@{
                    step = $index
                    monotonic_ms = $move.observer_monotonic_ms
                    normalized_x = $x
                    normalized_y = $y
                    client_x = $move.result.client_x
                    client_y = $move.result.client_y
                })
            if ($stepDelay -gt 0 -and $index -lt $Steps) {
                Start-Sleep -Milliseconds $stepDelay
            }
        }
    }
    finally {
        $up = Stop-UnrealMouseHold -Session $Session -Button $Button -Cleanup
    }
    if ($up.status -ne 'ok') {
        $up.operation = 'Drag'
        $up.input_dispatched = $true
        return $up
    }
    if ($moveFault) {
        $moveFault.operation = 'Drag'
        $moveFault.input_dispatched = $true
        return $moveFault
    }
    New-UnrealOperationResult -Operation 'Drag' -Status ok -InputDispatched $true `
        -TargetVisible $true -Result ([pscustomobject][ordered]@{
                start = [pscustomobject]@{ x = $StartX; y = $StartY }
                end = [pscustomobject]@{ x = $EndX; y = $EndY }
                button = $down.result.button
                duration_ms = $DurationMs
                steps = @($moves)
                window_handle_token = $down.result.window_handle_token
                process_token = $down.result.process_token
            })
}

function Find-UnrealVisibleTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')]
        [string]$TargetId,
        [switch]$RequireTopmost
    )

    $operation = 'FindVisibleTarget'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $watchdog = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdog.ok -or $watchdog.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation -Watchdog $watchdog
    }
    $validation = Test-UnrealTargetWindow -State $state
    if (-not $validation.ok) {
        return New-UnrealWindowFaultResult -Operation $operation -Validation $validation
    }
    $read = Read-UnrealStateSnapshotDirect -State $state
    if ($read.status -ne 'ok') {
        $read.operation = $operation
        return $read
    }
    $target = @(Get-UnrealVisibleTargetsFromSnapshot -Snapshot $read.result.snapshot |
            Where-Object {
                ($_.PSObject.Properties['target_id'] -and [string]$_.target_id -ceq $TargetId) -or
                ($_.PSObject.Properties['id'] -and [string]$_.id -ceq $TargetId)
            }) | Select-Object -First 1
    if (-not $target) {
        return New-UnrealOperationResult -Operation $operation -Status ok -TargetVisible $false `
            -FeedbackObserved $true -Result ([pscustomobject]@{
                    target_id = $TargetId
                    found = $false
                    reason = 'not_published_in_current_snapshot'
                    process_token = $state.ProcessToken
                    window_handle_token = $state.WindowToken
                })
    }
    $bounds = if ($target.PSObject.Properties['normalized_bounds']) {
        $target.normalized_bounds
    }
    else { $null }
    if (-not $bounds -or
        -not $bounds.PSObject.Properties['x'] -or
        -not $bounds.PSObject.Properties['y'] -or
        -not $bounds.PSObject.Properties['width'] -or
        -not $bounds.PSObject.Properties['height']) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'TARGET_BOUNDS_INVALID' `
            -Message 'The visible target snapshot lacks usable normalized bounds.' `
            -TargetVisible $null
    }
    $values = @([double]$bounds.x, [double]$bounds.y, [double]$bounds.width, [double]$bounds.height)
    if ($values | Where-Object { [double]::IsNaN($_) -or [double]::IsInfinity($_) } | Select-Object -First 1) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'TARGET_BOUNDS_INVALID' `
            -Message 'The visible target snapshot contains non-finite bounds.'
    }
    if ([double]$bounds.x -lt 0 -or [double]$bounds.y -lt 0 -or
        [double]$bounds.width -le 0 -or [double]$bounds.height -le 0 -or
        ([double]$bounds.x + [double]$bounds.width) -gt 1 -or
        ([double]$bounds.y + [double]$bounds.height) -gt 1) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'TARGET_BOUNDS_OUTSIDE_CLIENT' `
            -Message 'The visible target bounds are outside the current client area.'
    }
    $visible = if ($target.PSObject.Properties['visible']) { [bool]$target.visible } else { $false }
    $topmost = if ($target.PSObject.Properties['topmost']) { [bool]$target.topmost } else { $false }
    $opacity = if ($target.PSObject.Properties['opacity']) { [double]$target.opacity } else { 1.0 }
    if ($RequireTopmost -and -not $topmost) { $visible = $false }
    if ($opacity -le 0) { $visible = $false }
    New-UnrealOperationResult -Operation $operation -Status ok -TargetVisible $visible `
        -FeedbackObserved $true -Result ([pscustomobject][ordered]@{
                target_id = $TargetId
                found = $true
                visible = $visible
                topmost = $topmost
                opacity = $opacity
                normalized_bounds = $bounds
                center = [pscustomobject]@{
                    x = [double]$bounds.x + ([double]$bounds.width / 2)
                    y = [double]$bounds.y + ([double]$bounds.height / 2)
                }
                process_token = $state.ProcessToken
                round_id = $read.result.snapshot.round_id
                object_id = $read.result.snapshot.object.object_id
                window_handle_token = $state.WindowToken
            })
}

function Invoke-UnrealEmergencyInputCleanup {
    param(
        [Parameter(Mandatory)]$State,
        [switch]$RestorePointer
    )

    $errors = [Collections.Generic.List[object]]::new()
    $releasedKeys = [Collections.Generic.List[string]]::new()
    $releasedButtons = [Collections.Generic.List[string]]::new()
    foreach ($keyName in @($State.HeldKeys.Keys)) {
        $definition = $State.HeldKeys[$keyName]
        $nativeError = 0
        $released = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendKeyboard(
            [uint16]$definition.VirtualKey, $true, [bool]$definition.Extended, [ref]$nativeError)
        if ($released) {
            $State.HeldKeys.Remove($keyName)
            $releasedKeys.Add([string]$keyName)
        }
        else {
            $errors.Add([pscustomobject]@{
                    code = 'KEY_UP_CLEANUP_FAILED'
                    input = [string]$keyName
                    native_error = [int]$nativeError
                })
        }
    }
    foreach ($buttonName in @($State.HeldMouseButtons.Keys)) {
        $nativeError = 0
        $released = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::SendMouseButton(
            [string]$buttonName, $true, [ref]$nativeError)
        if ($released) {
            $State.HeldMouseButtons.Remove($buttonName)
            $releasedButtons.Add([string]$buttonName)
        }
        else {
            $errors.Add([pscustomobject]@{
                    code = 'MOUSE_UP_CLEANUP_FAILED'
                    input = [string]$buttonName
                    native_error = [int]$nativeError
                })
        }
    }

    $postInputState = $null
    $failedReleaseCount = 0
    $nativeError = 0
    $fullReleaseSucceeded = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::ReleaseAllControlledInputs(
        [ref]$postInputState, [ref]$failedReleaseCount, [ref]$nativeError)
    if (-not $fullReleaseSucceeded) {
        $errors.Add([pscustomobject]@{
                code = 'FULL_INPUT_CLEANUP_FAILED'
                input = $null
                native_error = [int]$nativeError
                failed_release_count = [int]$failedReleaseCount
            })
    }
    if ($postInputState -and -not $postInputState.AnyDown) {
        $State.HeldKeys.Clear()
        $State.HeldMouseButtons.Clear()
    }

    $cursorRestored = $State.CursorRestored
    if ($RestorePointer -and -not $State.CursorRestored) {
        $nativeError = 0
        $cursorRestored = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::RestoreCursorPosition(
            [int]$State.OriginalCursorX, [int]$State.OriginalCursorY, [ref]$nativeError)
        if ($cursorRestored) {
            $State.CursorRestored = $true
        }
        else {
            $errors.Add([pscustomobject]@{
                    code = 'POINTER_RESTORE_FAILED'
                    input = $null
                    native_error = [int]$nativeError
                })
        }
    }

    [pscustomobject][ordered]@{
        all_released = ($State.HeldKeys.Count -eq 0 -and
            $State.HeldMouseButtons.Count -eq 0 -and
            $fullReleaseSucceeded -and $postInputState -and -not $postInputState.AnyDown)
        cursor_restored = [bool]$cursorRestored
        released_keys = @($releasedKeys)
        released_mouse_buttons = @($releasedButtons)
        remaining_key_count = $State.HeldKeys.Count
        remaining_mouse_button_count = $State.HeldMouseButtons.Count
        controlled_input_postcheck_passed = [bool]($postInputState -and -not $postInputState.AnyDown)
        controlled_keys_down = if ($postInputState) { @($postInputState.KeysDown) } else { @() }
        controlled_mouse_buttons_down = if ($postInputState) {
            @($postInputState.MouseButtonsDown)
        }
        else { @() }
        full_release_failed_count = [int]$failedReleaseCount
        errors = @($errors)
    }
}

function Test-UnrealCaptureEnvironmentFailureCode {
    param([AllowNull()][string]$Code)

    return $Code -in @(
        'CLIENT_OVERLAPPED_BY_HIGHER_WINDOW', 'POINTER_TARGET_OCCLUDED',
        'POINTER_HIT_TEST_FAILED', 'POINTER_HIT_PID_QUERY_FAILED',
        'TARGET_NOT_IN_Z_ORDER', 'WINDOW_Z_ORDER_ENUMERATION_FAILED',
        'WINDOW_Z_ORDER_RECT_QUERY_FAILED',
        'CAPTURE_BITBLT_FAILED', 'SCREEN_DC_ACQUISITION_FAILED',
        'CAPTURE_DC_CREATION_FAILED', 'CAPTURE_BITMAP_CREATION_FAILED',
        'CAPTURE_BITMAP_SELECTION_FAILED', 'CAPTURE_PIXEL_READ_FAILED',
        'CAPTURE_MEMORY_ALLOCATION_FAILED', 'CAPTURE_SIZE_UNSAFE'
    )
}

function Save-UnrealClientCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$OutputPath,
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')]
        [string]$ArtifactId = ('capture-' + [guid]::NewGuid().ToString('N'))
    )

    $operation = 'Capture'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $watchdog = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdog.ok -or $watchdog.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation -Watchdog $watchdog
    }
    $outputFull = Get-SafeFullPath -Path $OutputPath
    $outputParent = if ($outputFull) { Split-Path -Parent $outputFull } else { $null }
    if (-not $outputFull -or [IO.Path]::GetExtension($outputFull) -ine '.png' -or
        -not $outputParent -or -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'CAPTURE_PATH_INVALID' `
            -Message 'The capture output must be a PNG inside an existing run directory.'
    }
    $relativePath = Get-SafeEvidenceRelativePath -Root $state.RunRoot -Path $outputFull
    if (-not $relativePath) {
        return New-UnrealExecutorFaultResult -Operation $operation `
            -Code 'CAPTURE_PATH_OUTSIDE_RUN_ROOT' `
            -Message 'The capture output must remain inside the run root.'
    }
    if ($relativePath -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$') {
        return New-UnrealExecutorFaultResult -Operation $operation `
            -Code 'CAPTURE_EVIDENCE_PATH_INVALID' `
            -Message 'The capture evidence path is not a portable relative artifact path.'
    }
    if (Test-Path -LiteralPath $outputFull) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'CAPTURE_OUTPUT_EXISTS' `
            -Message 'The capture output already exists and will not be overwritten.'
    }
    try {
        $parentItem = Get-Item -LiteralPath $outputParent -Force -ErrorAction Stop
        if ($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return New-UnrealExecutorFaultResult -Operation $operation `
                -Code 'CAPTURE_PARENT_REPARSE_POINT' `
                -Message 'The capture output parent cannot be a reparse point.'
        }
    }
    catch {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'CAPTURE_PATH_INVALID' `
            -Message 'The capture output parent could not be validated.'
    }

    $validation = Test-UnrealTargetWindow -State $state
    if (-not $validation.ok) {
        return New-UnrealWindowFaultResult -Operation $operation -Validation $validation
    }
    $captureFrame = $null
    $failedSampleIndex = -1
    $validationCode = $null
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::CaptureClientBgraBound(
            $state.WindowHandle, [uint32]$state.ProcessId,
            [ref]$captureFrame, [ref]$failedSampleIndex,
            [ref]$validationCode, [ref]$nativeError)) {
        if (Test-UnrealCaptureEnvironmentFailureCode -Code $validationCode) {
            return New-UnrealEnvironmentFaultResult -Operation $operation `
                -Code 'CLIENT_CAPTURE_ENVIRONMENT_UNAVAILABLE' `
                -Message 'The bound client area could not be captured without a higher z-order overlap or host capture failure.' `
                -Retryable $true -Details ([pscustomobject]@{
                        validation_code = $validationCode
                        failed_sample_index = $failedSampleIndex
                        native_error = [int]$nativeError
                    })
        }
        return New-UnrealBoundNativeFaultResult -Operation $operation `
            -FallbackCode 'CLIENT_CAPTURE_BOUND_TRANSACTION_FAILED' `
            -Message 'The bound client capture transaction did not complete safely.' `
            -ValidationCode $validationCode -NativeError $nativeError `
            -TargetVisible $true
    }
    $captureMonotonicMs = Get-UnrealMonotonicMs
    $watchdogAfterCapture = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogAfterCapture.ok -or $watchdogAfterCapture.faulted) {
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogAfterCapture -TargetVisible $false
    }

    $bitmap = $null
    $stream = $null
    $created = $false
    try {
        Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue
        $bitmap = [Drawing.Bitmap]::new(
            [int]$captureFrame.Snapshot.ClientWidth,
            [int]$captureFrame.Snapshot.ClientHeight,
            [Drawing.Imaging.PixelFormat]::Format32bppRgb)
        $rectangle = [Drawing.Rectangle]::new(
            0, 0,
            [int]$captureFrame.Snapshot.ClientWidth,
            [int]$captureFrame.Snapshot.ClientHeight)
        $bitmapData = $bitmap.LockBits(
            $rectangle,
            [Drawing.Imaging.ImageLockMode]::WriteOnly,
            [Drawing.Imaging.PixelFormat]::Format32bppRgb)
        try {
            if ([int]$bitmapData.Stride -ne [int]$captureFrame.Stride) {
                throw [InvalidOperationException]::new('The capture stride does not match the PNG encoder stride.')
            }
            [Runtime.InteropServices.Marshal]::Copy(
                [byte[]]$captureFrame.Bgra32,
                0,
                $bitmapData.Scan0,
                [int]$captureFrame.Bgra32.Length)
        }
        finally {
            $bitmap.UnlockBits($bitmapData)
        }
        $stream = [IO.FileStream]::new(
            $outputFull,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None)
        $created = $true
        $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        $stream.Flush($true)
    }
    catch {
        if ($stream) { $stream.Dispose(); $stream = $null }
        if ($bitmap) { $bitmap.Dispose(); $bitmap = $null }
        if ($created) {
            try { [IO.File]::Delete($outputFull) } catch { }
        }
        return New-UnrealEnvironmentFaultResult -Operation $operation -Code 'CAPTURE_FAILED' `
            -Message 'The current target client area could not be captured as PNG.' -Retryable $true
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
    }

    try {
        $fileInfo = Get-Item -LiteralPath $outputFull -ErrorAction Stop
        $sha256 = (Get-FileHash -LiteralPath $outputFull -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    }
    catch {
        try { [IO.File]::Delete($outputFull) } catch { }
        return New-UnrealExecutorFaultResult -Operation $operation `
            -Code 'CAPTURE_INTEGRITY_FAILED' `
            -Message 'The capture integrity metadata could not be verified; the incomplete artifact was removed.' `
            -TargetVisible $true
    }
    $watchdogBeforeEvidenceCommit = Get-UnrealInputWatchdogState -State $state
    if (-not $watchdogBeforeEvidenceCommit.ok -or $watchdogBeforeEvidenceCommit.faulted) {
        try { [IO.File]::Delete($outputFull) } catch { }
        return New-UnrealWatchdogFaultResult -Operation $operation `
            -Watchdog $watchdogBeforeEvidenceCommit -TargetVisible $false
    }
    $evidence = [pscustomobject][ordered]@{
        path = $relativePath
        sha256 = $sha256
        media_type = 'image/png'
        byte_length = [long]$fileInfo.Length
        captured_monotonic_ms = $captureMonotonicMs
        kind = 'capture'
        producer = [pscustomobject]@{
            id = 'windows-client-capture'
            version = '1.0.0'
        }
    }
    New-UnrealOperationResult -Operation $operation -Status ok -TargetVisible $true `
        -Result ([pscustomobject][ordered]@{
                artifact = $evidence
                artifact_id = $ArtifactId
                width = [int]$captureFrame.Snapshot.ClientWidth
                height = [int]$captureFrame.Snapshot.ClientHeight
                window_handle_token = $state.WindowToken
                process_token = $state.ProcessToken
                client_only = $true
                foreground_confirmed = $true
                coordinate_space = [string]$captureFrame.Snapshot.CoordinateSpace
                window_dpi = [int]$captureFrame.Snapshot.Dpi
                exposure_assurance = [string]$captureFrame.ExposureAssurance
                exposure_sample_count = [int]$captureFrame.ExposureSampleCount
                pixel_level_unoccluded_proof = $false
            }) -Evidence @($evidence)
}

function Stop-UnrealEvaluationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [ValidateRange(100, 120000)][int]$GraceTimeoutMs = 10000,
        [ValidateRange(100, 30000)][int]$FaultCleanupTimeoutMs = 5000
    )

    $operation = 'Stop'
    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }

    $watchdogStop = Stop-UnrealInputWatchdog -State $state
    $watchdogStopAttempts = 1
    $cleanup = Invoke-UnrealEmergencyInputCleanup -State $state -RestorePointer
    if (-not $watchdogStop.stopped) {
        $watchdogRetry = Stop-UnrealInputWatchdog -State $state
        ++$watchdogStopAttempts
        $watchdogStop = [pscustomobject][ordered]@{
            stopped = [bool]$watchdogRetry.stopped
            faulted = [bool]($watchdogStop.faulted -or $watchdogRetry.faulted)
            fault_code = if ($watchdogStop.faulted) {
                [string]$watchdogStop.fault_code
            }
            else { [string]$watchdogRetry.fault_code }
            native_error = if ($watchdogStop.faulted) {
                [int]$watchdogStop.native_error
            }
            else { [int]$watchdogRetry.native_error }
        }
    }
    $cleanup | Add-Member -NotePropertyName input_watchdog_stopped `
        -NotePropertyValue ([bool]$watchdogStop.stopped)
    $cleanup | Add-Member -NotePropertyName input_watchdog_faulted `
        -NotePropertyValue ([bool]$watchdogStop.faulted)
    $cleanup | Add-Member -NotePropertyName input_watchdog_fault_code `
        -NotePropertyValue ([string]$watchdogStop.fault_code)
    $cleanup | Add-Member -NotePropertyName input_watchdog_native_error `
        -NotePropertyValue ([int]$watchdogStop.native_error)
    $cleanup | Add-Member -NotePropertyName input_watchdog_stop_attempts `
        -NotePropertyValue ([int]$watchdogStopAttempts)

    if (-not $cleanup.all_released -or -not $cleanup.cursor_restored -or
        -not $watchdogStop.stopped) {
        try { $processExitedBeforeClose = [bool]$state.Process.HasExited }
        catch { $processExitedBeforeClose = $true }
        $activeProcessesBeforeClose = 0
        $jobQueryError = 0
        $jobQueryPassed = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetJobActiveProcessCount(
            $state.JobHandle, [ref]$activeProcessesBeforeClose, [ref]$jobQueryError)
        $blockedResult = [pscustomobject][ordered]@{
            session_id = $state.SessionId
            process_id = $state.ProcessId
            process_token = $state.ProcessToken
            window_handle_token = $state.WindowToken
            normal_close_requested = $false
            process_exited = $processExitedBeforeClose
            job_active_process_count_before_close = if ($jobQueryPassed) {
                [int]$activeProcessesBeforeClose
            }
            else { $null }
            job_active_process_count_after_wait = $null
            job_handle_closed = $false
            forced_fault_cleanup = $false
            input_lease_released = $false
            session_retained_for_cleanup_retry = $true
            input_cleanup = $cleanup
        }
        if (-not $cleanup.all_released -or -not $cleanup.cursor_restored) {
            return New-UnrealExecutorFaultResult -Operation $operation -Code 'INPUT_CLEANUP_FAILED' `
                -Message 'One or more held inputs or the original pointer position could not be restored; the session and exclusive input lease were retained for cleanup retry.' `
                -TargetVisible $null -Retryable $true -Details ([pscustomobject]@{
                        remaining_key_count = $cleanup.remaining_key_count
                        remaining_mouse_button_count = $cleanup.remaining_mouse_button_count
                        cleanup_error_count = $cleanup.errors.Count
                    }) -Result $blockedResult
        }
        return New-UnrealExecutorFaultResult -Operation $operation `
            -Code 'INPUT_WATCHDOG_STOP_FAILED' `
            -Message 'The input watchdog could not clear its bound session; the session and exclusive input lease were retained for cleanup retry.' `
            -TargetVisible $null -Retryable $true -Details ([pscustomobject]@{
                    fault_code = [string]$watchdogStop.fault_code
                    native_error = [int]$watchdogStop.native_error
                }) -Result $blockedResult
    }
    $normalClosePosted = $false
    $forcedCleanup = $false
    $processExited = $false
    $activeBeforeClose = 0
    $activeAfterWait = 0
    $stopFault = $null

    try {
        $alreadyExited = $state.Process.HasExited
    }
    catch {
        $alreadyExited = $true
    }
    if ($alreadyExited) {
        $stopFault = New-UnrealFault -Domain executor -Code 'TARGET_EXITED_BEFORE_STOP' `
            -Message 'The target process exited before a normal close could be requested.'
    }
    else {
        $snapshot = $null
        $validationCode = $null
        $nativeError = 0
        $valid = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetWindowSnapshot(
            $state.WindowHandle, [uint32]$state.ProcessId, $false,
            [ref]$snapshot, [ref]$validationCode, [ref]$nativeError)
        if (-not $valid) {
            $stopFault = New-UnrealFault -Domain executor -Code 'STOP_WINDOW_INVALID' `
                -Message 'The bound target window could not be validated for normal close.' `
                -Details ([pscustomobject]@{ validation_code = [string]$validationCode })
        }
        else {
            $nativeError = 0
            $closeValidationCode = $null
            $normalClosePosted = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::PostCloseBound(
                $state.WindowHandle, [uint32]$state.ProcessId,
                [ref]$closeValidationCode, [ref]$nativeError)
            if (-not $normalClosePosted) {
                $stopFault = New-UnrealFault -Domain executor -Code 'WM_CLOSE_POST_FAILED' `
                    -Message 'The normal close request could not be posted to the target window.' `
                    -Details ([pscustomobject]@{
                            validation_code = $closeValidationCode
                            native_error = [int]$nativeError
                        })
            }
        }
    }

    $nativeError = 0
    [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetJobActiveProcessCount(
        $state.JobHandle, [ref]$activeBeforeClose, [ref]$nativeError)

    if (-not $stopFault) {
        $deadline = (Get-UnrealMonotonicMs) + $GraceTimeoutMs
        do {
            try { $processExited = $state.Process.HasExited } catch { $processExited = $true }
            $nativeError = 0
            $jobQueryOk = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetJobActiveProcessCount(
                $state.JobHandle, [ref]$activeAfterWait, [ref]$nativeError)
            if (-not $jobQueryOk) {
                $stopFault = New-UnrealFault -Domain executor -Code 'JOB_ACCOUNTING_FAILED' `
                    -Message 'The process-tree job could not be queried during Stop.' `
                    -Details ([pscustomobject]@{ native_error = [int]$nativeError })
                break
            }
            if ($processExited -and $activeAfterWait -eq 0) { break }
            if ((Get-UnrealMonotonicMs) -ge $deadline) {
                $stopFault = New-UnrealFault -Domain executor -Code 'STOP_GRACE_TIMEOUT' `
                    -Message 'The process tree did not exit within the normal-close grace period.'
                break
            }
            Start-Sleep -Milliseconds 50
        } while ($true)
    }

    if ($stopFault) {
        $forcedCleanup = $true
        $nativeError = 0
        [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TerminateJob(
            $state.JobHandle, [uint32]3758096386, [ref]$nativeError)
        $cleanupDeadline = (Get-UnrealMonotonicMs) + $FaultCleanupTimeoutMs
        do {
            $nativeError = 0
            $jobQueryOk = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetJobActiveProcessCount(
                $state.JobHandle, [ref]$activeAfterWait, [ref]$nativeError)
            if (-not $jobQueryOk -or $activeAfterWait -eq 0 -or
                (Get-UnrealMonotonicMs) -ge $cleanupDeadline) { break }
            Start-Sleep -Milliseconds 50
        } while ($true)
        try { $processExited = $state.Process.HasExited } catch { $processExited = $true }
        if (-not $processExited) {
            try {
                $state.Process.Kill($true)
                [void]$state.Process.WaitForExit($FaultCleanupTimeoutMs)
            }
            catch { }
            try { $processExited = $state.Process.HasExited } catch { $processExited = $true }
        }
        $nativeError = 0
        [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetJobActiveProcessCount(
            $state.JobHandle, [ref]$activeAfterWait, [ref]$nativeError)
    }

    $result = [pscustomobject][ordered]@{
        session_id = $state.SessionId
        process_id = $state.ProcessId
        process_token = $state.ProcessToken
        window_handle_token = $state.WindowToken
        normal_close_requested = $normalClosePosted
        process_exited = $processExited
        job_active_process_count_before_close = [int]$activeBeforeClose
        job_active_process_count_after_wait = [int]$activeAfterWait
        job_handle_closed = $false
        forced_fault_cleanup = $forcedCleanup
        input_lease_released = $false
        session_retained_for_cleanup_retry = $true
        input_cleanup = $cleanup
    }

    if (-not $processExited -or [int]$activeAfterWait -ne 0) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'PROCESS_TREE_CLEANUP_FAILED' `
            -Message 'The evaluation process tree remained active after cleanup.' -Result $result
    }

    $closeError = 0
    $jobClosed = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::CloseJob(
        $state.JobHandle, [ref]$closeError)
    $result.job_handle_closed = [bool]$jobClosed
    if (-not $jobClosed) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'JOB_HANDLE_CLOSE_FAILED' `
            -Message 'The process-tree job handle could not be closed.' `
            -Details ([pscustomobject]@{ native_error = [int]$closeError }) -Result $result
    }
    $state.JobHandle = [IntPtr]::Zero

    $inputLeaseReleased = Exit-UnrealInputLease -Lease $state.InputLease
    $result.input_lease_released = [bool]$inputLeaseReleased
    if (-not $inputLeaseReleased) {
        return New-UnrealExecutorFaultResult -Operation $operation -Code 'INPUT_LEASE_RELEASE_FAILED' `
            -Message 'The exclusive host input lease could not be released.' -Result $result
    }
    $state.InputLease = $null
    $state.Stopped = $true
    [void]$script:Sessions.Remove($state.SessionId)
    try { $state.Process.Dispose() } catch { }
    $result.session_retained_for_cleanup_retry = $false

    if ($stopFault) {
        return New-UnrealOperationResult -Operation $operation -Status executor_fault `
            -TargetVisible $null -Result $result -Fault $stopFault
    }
    if ($watchdogStop.faulted) {
        return New-UnrealExecutorFaultResult -Operation $operation `
            -Code 'INPUT_WATCHDOG_FAULT_LATCHED' `
            -Message 'The input watchdog released held input after the target binding or foreground was lost.' `
            -TargetVisible $null -Details ([pscustomobject]@{
                    watchdog_fault_code = [string]$watchdogStop.fault_code
                    native_error = [int]$watchdogStop.native_error
                }) -Result $result
    }
    New-UnrealOperationResult -Operation $operation -Status ok -TargetVisible $false -Result $result
}

function Restart-UnrealEvaluationSession {
    [CmdletBinding(DefaultParameterSetName = 'Key')]
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(ParameterSetName = 'Key')][string]$Key = 'R',
        [Parameter(Mandatory, ParameterSetName = 'Click')][ValidateRange(0, 1)][double]$NormalizedX,
        [Parameter(Mandatory, ParameterSetName = 'Click')][ValidateRange(0, 1)][double]$NormalizedY,
        [Parameter(ParameterSetName = 'Click')][string]$Button = 'Left'
    )

    $primitive = if ($PSCmdlet.ParameterSetName -eq 'Click') {
        Invoke-UnrealClick -Session $Session -NormalizedX $NormalizedX -NormalizedY $NormalizedY `
            -Button $Button
    }
    else {
        Invoke-UnrealPressKey -Session $Session -Key $Key
    }
    $primitive.operation = 'Restart'
    if ($primitive.status -eq 'ok') {
        $primitive.result = [pscustomobject][ordered]@{
            activation_kind = if ($PSCmdlet.ParameterSetName -eq 'Click') { 'Click' } else { 'PressKey' }
            primitive_receipt = $primitive.result
            restart_feedback_requires_observer = $true
        }
        $primitive.feedback_observed = $null
    }
    return $primitive
}

function Test-UnrealReopenStopRetryEligible {
    param([AllowNull()][object]$StopResult)

    if ($null -eq $StopResult -or
        -not $StopResult.PSObject.Properties['status'] -or
        $StopResult.status -eq 'ok' -or
        -not $StopResult.PSObject.Properties['fault'] -or
        $null -eq $StopResult.fault -or
        -not $StopResult.fault.PSObject.Properties['retryable'] -or
        -not [bool]$StopResult.fault.retryable -or
        -not $StopResult.PSObject.Properties['result'] -or
        $null -eq $StopResult.result -or
        -not $StopResult.result.PSObject.Properties['session_retained_for_cleanup_retry']) {
        return $false
    }

    return [bool]$StopResult.result.session_retained_for_cleanup_retry
}

function Invoke-UnrealReopenStopSequence {
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][int]$GraceTimeoutMs,
        [AllowNull()][scriptblock]$StopAction = $null
    )

    if ($null -eq $StopAction) {
        $StopAction = {
            param($BoundSession, $BoundGraceTimeoutMs)
            Stop-UnrealEvaluationSession -Session $BoundSession `
                -GraceTimeoutMs $BoundGraceTimeoutMs
        }
    }

    $attempts = [Collections.Generic.List[object]]::new()
    $stop = & $StopAction $Session $GraceTimeoutMs
    [void]$attempts.Add($stop)
    if (Test-UnrealReopenStopRetryEligible -StopResult $stop) {
        $stop = & $StopAction $Session $GraceTimeoutMs
        [void]$attempts.Add($stop)
    }

    return [pscustomobject][ordered]@{
        attempts = @($attempts)
        attempted_count = [int]$attempts.Count
        retry_attempted = ($attempts.Count -gt 1)
        recovered_after_retry = ($attempts.Count -gt 1 -and $stop.status -eq 'ok')
        final = $stop
    }
}

function Reopen-UnrealEvaluationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [ValidateRange(100, 120000)][int]$GraceTimeoutMs = 10000,
        [ValidateRange(1000, 300000)][int]$StartTimeoutMs = 60000
    )

    $state = Get-UnrealSessionState -Session $Session
    if (-not $state) {
        return New-UnrealExecutorFaultResult -Operation 'Reopen' -Code 'SESSION_NOT_FOUND' `
            -Message 'The evaluation session is unknown or expired.'
    }
    $launch = [pscustomobject]@{
        ProjectPath = $state.ProjectPath
        RunRoot = $state.RunRoot
        StatePath = $state.StatePath
        EditorPath = $state.EditorPath
        WindowWidth = $state.WindowWidth
        WindowHeight = $state.WindowHeight
        FocusTimeoutMs = $state.FocusTimeoutMs
        ObserverDisabledControl = [bool]$state.ObserverDisabledControl
        AdditionalArguments = @($state.AdditionalArguments)
    }
    $oldSessionId = $state.SessionId
    $oldProcessId = $state.ProcessId
    $oldProcessToken = $state.ProcessToken

    $stopSequence = Invoke-UnrealReopenStopSequence -Session $Session `
        -GraceTimeoutMs $GraceTimeoutMs
    $stop = $stopSequence.final
    if ($stop.status -ne 'ok') {
        $sessionRetained = [bool]($stop.result -and
            $stop.result.PSObject.Properties['session_retained_for_cleanup_retry'] -and
            $stop.result.session_retained_for_cleanup_retry)
        return New-UnrealOperationResult -Operation 'Reopen' -Status $stop.status `
            -InputDispatched ([bool]$stop.input_dispatched) `
            -FeedbackObserved $stop.feedback_observed -TargetVisible $stop.target_visible `
            -Fault $stop.fault -Evidence @($stop.evidence) `
            -Result ([pscustomobject][ordered]@{
                    termination_reason = 'old_session_stop_failed'
                    old_session_id = $oldSessionId
                    old_process_id = $oldProcessId
                    old_process_token = $oldProcessToken
                    stop_attempt_count = [int]$stopSequence.attempted_count
                    stop_retry_attempted = [bool]$stopSequence.retry_attempted
                    stop_attempts = @($stopSequence.attempts)
                    stop_result = $stop.result
                    session_retained_for_cleanup_retry = $sessionRetained
                    session = if ($sessionRetained) { $Session } else { $null }
                })
    }

    $newProcessToken = 'process-' + [guid]::NewGuid().ToString('N')
    $start = Start-UnrealEvaluationSession -ProjectPath $launch.ProjectPath `
        -RunRoot $launch.RunRoot -StatePath $launch.StatePath -ProcessToken $newProcessToken `
        -EditorPath $launch.EditorPath -WindowWidth $launch.WindowWidth `
        -WindowHeight $launch.WindowHeight -FocusTimeoutMs $launch.FocusTimeoutMs `
        -ObserverDisabledControl:$launch.ObserverDisabledControl `
        -TimeoutMs $StartTimeoutMs -AdditionalArguments $launch.AdditionalArguments
    if ($start.status -ne 'ok') {
        $start.operation = 'Reopen'
        $start.result = [pscustomobject]@{
            termination_reason = 'new_session_start_failed'
            old_session_id = $oldSessionId
            old_process_id = $oldProcessId
            old_process_token = $oldProcessToken
            start_result = $start.result
        }
        return $start
    }
    if ([int]$start.result.process_id -eq [int]$oldProcessId) {
        $cleanupSequence = Invoke-UnrealReopenStopSequence `
            -Session $start.result.session -GraceTimeoutMs $GraceTimeoutMs
        $cleanup = $cleanupSequence.final
        if ($cleanup.status -ne 'ok') {
            $sessionRetained = [bool]($cleanup.result -and
                $cleanup.result.PSObject.Properties['session_retained_for_cleanup_retry'] -and
                $cleanup.result.session_retained_for_cleanup_retry)
            return New-UnrealOperationResult -Operation 'Reopen' -Status $cleanup.status `
                -InputDispatched ([bool]$cleanup.input_dispatched) `
                -FeedbackObserved $cleanup.feedback_observed `
                -TargetVisible $cleanup.target_visible -Fault $cleanup.fault `
                -Evidence @($cleanup.evidence) -Result ([pscustomobject][ordered]@{
                        termination_reason = 'process_id_not_renewed_cleanup_failed'
                        old_session_id = $oldSessionId
                        old_process_id = $oldProcessId
                        cleanup_attempt_count = [int]$cleanupSequence.attempted_count
                        cleanup_attempts = @($cleanupSequence.attempts)
                        cleanup_result = $cleanup.result
                        session_retained_for_cleanup_retry = $sessionRetained
                        session = if ($sessionRetained) { $start.result.session } else { $null }
                    })
        }
        return New-UnrealExecutorFaultResult -Operation 'Reopen' -Code 'PROCESS_ID_NOT_RENEWED' `
            -Message 'Reopen did not produce a distinct process identifier.' `
            -TargetVisible $null -Result ([pscustomobject]@{
                    old_session_id = $oldSessionId
                    old_process_id = $oldProcessId
                    cleanup_status = $cleanup.status
                    cleanup_attempt_count = [int]$cleanupSequence.attempted_count
                    cleanup_attempts = @($cleanupSequence.attempts)
                })
    }

    New-UnrealOperationResult -Operation 'Reopen' -Status ok -TargetVisible $true `
        -Result ([pscustomobject][ordered]@{
                old_session_id = $oldSessionId
                old_process_id = $oldProcessId
                old_process_token = $oldProcessToken
                normal_old_stop_confirmed = $true
                old_stop_attempt_count = [int]$stopSequence.attempted_count
                old_stop_recovered_after_retry = [bool]$stopSequence.recovered_after_retry
                old_stop_attempts = @($stopSequence.attempts)
                session = $start.result.session
                session_id = $start.result.session_id
                process_id = $start.result.process_id
                process_token = $start.result.process_token
                window_handle_token = $start.result.window_handle_token
                client_size = $start.result.client_size
                coordinate_space = $start.result.coordinate_space
                window_dpi = $start.result.window_dpi
                state_path = $start.result.state_path
                initial_snapshot_id = $start.result.initial_snapshot_id
                initial_round_id = $start.result.initial_round_id
                state_first_frame_confirmed = $start.result.state_first_frame_confirmed
                stable_visible_frame_confirmed = $start.result.stable_visible_frame_confirmed
                observer_disabled_control = $start.result.observer_disabled_control
                job_active_process_count = $start.result.job_active_process_count
            })
}

function Test-UnrealEvaluationNativeInterop {
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        return New-UnrealUnsupportedResult -Operation 'NativeSmoke' `
            -Code 'WINDOWS_PLATFORM_REQUIRED' `
            -Message 'The Unreal Windows executor is available only on Windows.'
    }
    $cursorX = 0
    $cursorY = 0
    $nativeError = 0
    $cursorReadable = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetCursorPosition(
        [ref]$cursorX, [ref]$cursorY, [ref]$nativeError)
    if (-not $cursorReadable) {
        return New-UnrealEnvironmentFaultResult -Operation 'NativeSmoke' `
            -Code 'CURSOR_POSITION_UNAVAILABLE' `
            -Message 'The pointer position could not be read during native smoke validation.' `
            -Details ([pscustomobject]@{ native_error = [int]$nativeError })
    }
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::EnsurePerMonitorDpiAwareness(
            [ref]$nativeError)) {
        return New-UnrealEnvironmentFaultResult -Operation 'NativeSmoke' `
            -Code 'DPI_TRANSACTION_UNAVAILABLE' `
            -Message 'A reversible per-monitor DPI transaction could not be established.' `
            -Details ([pscustomobject]@{ native_error = [int]$nativeError })
    }
    $inputState = $null
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::QueryAllControlledInputState(
            [ref]$inputState, [ref]$nativeError)) {
        return New-UnrealEnvironmentFaultResult -Operation 'NativeSmoke' `
            -Code 'INPUT_STATE_QUERY_FAILED' `
            -Message 'The controlled keyboard and pointer state could not be queried.' `
            -Details ([pscustomobject]@{ native_error = [int]$nativeError })
    }
    $jobHandle = [IntPtr]::Zero
    $nativeError = 0
    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::CreateKillOnCloseJob(
            [ref]$jobHandle, [ref]$nativeError)) {
        return New-UnrealEnvironmentFaultResult -Operation 'NativeSmoke' `
            -Code 'JOB_CREATE_FAILED' `
            -Message 'A process-tree job object could not be created during native smoke validation.' `
            -Details ([pscustomobject]@{ native_error = [int]$nativeError })
    }
    try {
        $activeProcessCount = 0
        $nativeError = 0
        if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TryGetJobActiveProcessCount(
                $jobHandle, [ref]$activeProcessCount, [ref]$nativeError)) {
            return New-UnrealEnvironmentFaultResult -Operation 'NativeSmoke' `
                -Code 'JOB_ACCOUNTING_FAILED' `
                -Message 'The empty native smoke job object could not be queried.' `
                -Details ([pscustomobject]@{ native_error = [int]$nativeError })
        }
        if ($activeProcessCount -ne 0) {
            return New-UnrealExecutorFaultResult -Operation 'NativeSmoke' `
                -Code 'EMPTY_JOB_NOT_EMPTY' `
                -Message 'The empty native smoke job unexpectedly contained a process.'
        }
    }
    finally {
        $closeError = 0
        $jobClosed = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::CloseJob(
            $jobHandle, [ref]$closeError)
    }
    if (-not $jobClosed) {
        return New-UnrealEnvironmentFaultResult -Operation 'NativeSmoke' `
            -Code 'JOB_HANDLE_CLOSE_FAILED' `
            -Message 'The native smoke job handle could not be closed.' `
            -Details ([pscustomobject]@{ native_error = [int]$closeError })
    }

    New-UnrealOperationResult -Operation 'NativeSmoke' -Status ok `
        -Result ([pscustomobject][ordered]@{
                interop_version = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::InteropVersion
                cursor_position_readable = $true
                reversible_dpi_transaction = $true
                controlled_input_state_query = $true
                controlled_input_any_down = [bool]$inputState.AnyDown
                empty_job_active_process_count = 0
                job_handle_closed = $true
                send_input_invoked = $false
            })
}

$ExecutionContext.SessionState.Module.OnRemove = {
    foreach ($state in @($script:Sessions.Values)) {
        try { [void](Invoke-UnrealEmergencyInputCleanup -State $state -RestorePointer) } catch { }
        try { [void](Stop-UnrealInputWatchdog -State $state) } catch { }
        try {
            if (-not $state.Process.HasExited -and $state.WindowHandle -ne [IntPtr]::Zero) {
                $nativeError = 0
                $validationCode = $null
                [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::PostCloseBound(
                    $state.WindowHandle, [uint32]$state.ProcessId,
                    [ref]$validationCode, [ref]$nativeError)
                [void]$state.Process.WaitForExit(500)
            }
        }
        catch { }
        try {
            $nativeError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::TerminateJob(
                $state.JobHandle, [uint32]3758096387, [ref]$nativeError)
        }
        catch { }
        try {
            $nativeError = 0
            [void][VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::CloseJob(
                $state.JobHandle, [ref]$nativeError)
        }
        catch { }
        try { [void](Exit-UnrealInputLease -Lease $state.InputLease) } catch { }
    }
    $script:Sessions.Clear()
    $script:EngineRoots.Clear()
}

Export-ModuleMember -Function @(
    'Resolve-UnrealEngine57Root',
    'Start-UnrealEvaluationSession',
    'Stop-UnrealEvaluationSession',
    'Invoke-UnrealPressKey',
    'Start-UnrealKeyHold',
    'Stop-UnrealKeyHold',
    'Move-UnrealPointer',
    'Start-UnrealMouseHold',
    'Stop-UnrealMouseHold',
    'Invoke-UnrealClick',
    'Invoke-UnrealDrag',
    'Save-UnrealClientCapture',
    'Restart-UnrealEvaluationSession',
    'Reopen-UnrealEvaluationSession',
    'Test-UnrealEvaluationNativeInterop'
)
