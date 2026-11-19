[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExecutorPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Import-Module $ExecutorPath -Force -WarningAction SilentlyContinue
$session = $null
try {
    while ($line = [Console]::ReadLine()) {
        try {
            $c = $line | ConvertFrom-Json
            $result = switch ($c.op) {
                'start' {
                    $a = @{
                        ProjectPath = $c.project; EngineRoot = $c.engine; RunRoot = $c.root
                        StatePath = (Join-Path $c.root 'engine-health.json')
                        WindowWidth = $c.width; WindowHeight = $c.height; TimeoutMs = 120000
                        ObserverDisabledControl = $true
                        AdditionalArguments = @('-ForceRes','-NoSplash','-NoMessaging','-NoUDPMessaging','-NoTcpMessaging',"-ObservationPath=$($c.dashboard)","-UserDir=$($c.userdir)")
                    }
                    $r = Start-UnrealEvaluationSession @a
                    if ($r.status -ne 'ok' -and $r.fault.code -eq 'active_input_session_exists') {
                        $probe = $null
                        try {
                            $probe = [IO.FileStream]::new((Join-Path ([IO.Path]::GetTempPath()) 'vibe-gaming-unreal-evaluation-input.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                            $r.fault.details = @{ lease_probe = 'available_after_executor_failure' }
                        } catch {
                            $r.fault.details = @{ lease_probe = 'unavailable'; exception_type = $_.Exception.GetType().Name; hresult = $_.Exception.HResult; message = $_.Exception.Message }
                        } finally { if ($null -ne $probe) { $probe.Dispose() } }
                    }
                    if ($r.status -eq 'ok') { $session = $r.result.session }
                    $r
                }
                'press' { Invoke-UnrealPressKey -Session $session -Key $c.key -DurationMs $c.ms }
                'down' { Start-UnrealKeyHold -Session $session -Key $c.key }
                'up' { Stop-UnrealKeyHold -Session $session -Key $c.key }
                'mouse_down' { Start-UnrealMouseHold -Session $session -Button $c.button }
                'mouse_up' { Stop-UnrealMouseHold -Session $session -Button $c.button }
                'move' { Move-UnrealPointer -Session $session -NormalizedX $c.x -NormalizedY $c.y }
                'click' { Invoke-UnrealClick -Session $session -NormalizedX $c.x -NormalizedY $c.y -Button $c.button -DurationMs $c.ms }
                'drag' { Invoke-UnrealDrag -Session $session -StartX $c.x -StartY $c.y -EndX $c.end_x -EndY $c.end_y -Button 'Left' -DurationMs $c.ms -Steps $c.steps }
                'mouse_chord' {
                    $receipts = @()
                    try {
                        foreach ($button in $c.buttons) { $receipts += Start-UnrealMouseHold -Session $session -Button $button }
                        Start-Sleep -Milliseconds $c.ms
                    } finally {
                        foreach ($button in $c.buttons) { $receipts += Stop-UnrealMouseHold -Session $session -Button $button }
                    }
                    $failed = @($receipts | Where-Object { $_.status -ne 'ok' })
                    if ($failed.Count) { $failed[0] } else { @{status='ok';result=@{receipts=$receipts;operation='ordinary_multiple_mouse_buttons'}} }
                }
                'capture' { Save-UnrealClientCapture -Session $session -OutputPath $c.path -ArtifactId $c.id }
                'process_status' {
                    $p = Get-Process -Id $session.ProcessId -ErrorAction SilentlyContinue
                    @{ status='ok'; result=@{ alive=($null -ne $p); process_id=$session.ProcessId } }
                }
                'acknowledge_focus_release' {
                    # Acknowledge only a proven automatic release after the
                    # expected focus probe, once this same process is foreground.
                    $windows = @([VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::EnumerateVisibleTopLevelWindows([uint32]$session.ProcessId) | Where-Object { $_.IsForeground })
                    if ($windows.Count -ne 1) { throw 'Focus recovery requires one foreground window owned by the session process.' }
                    $w = $windows[0]; $active = $false; $faulted = $false; $code = $null; $nativeError = 0
                    $queried = [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::QueryInputWatchdog($w.Handle,[uint32]$session.ProcessId,[ref]$active,[ref]$faulted,[ref]$code,[ref]$nativeError)
                    if (-not $queried -or $active -or -not $faulted -or $code -ne 'FOREGROUND_NOT_CONFIRMED') { throw 'Unexpected input watchdog state; cannot acknowledge.' }
                    $state = $null
                    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::QueryAllControlledInputState([ref]$state,[ref]$nativeError) -or $state.AnyDown) { throw 'Controlled inputs are not released.' }
                    $validation = $null
                    if (-not [VibeGaming.UnrealEvaluation.WindowsEvaluationNative]::ClearInputWatchdog($w.Handle,[uint32]$session.ProcessId,[ref]$validation,[ref]$nativeError)) { throw 'Unable to acknowledge released focus watchdog.' }
                    @{status='ok';result=@{process_id=$session.ProcessId;foreground_confirmed=$true;all_inputs_released=$true;prior_fault=$code;operation='acknowledge_expected_focus_release'}}
                }
                'audio_start' {
                    if (-not ('PlayerEvidence.Loopback' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'AudioCapture.cs') }
                    [PlayerEvidence.Loopback]::Start($c.path)
                    @{ status='ok'; result=@{ source='render_endpoint_loopback'; microphone=$false } }
                }
                'audio_stop' {
                    [PlayerEvidence.Loopback]::Stop()
                    @{ status='ok'; result=@{ error=[PlayerEvidence.Loopback]::Error; frames=[PlayerEvidence.Loopback]::Frames; sample_rate=[PlayerEvidence.Loopback]::SampleRate; channels=[PlayerEvidence.Loopback]::Channels; bits=[PlayerEvidence.Loopback]::Bits; started_qpc=[PlayerEvidence.Loopback]::StartedQpc; qpc_frequency=[PlayerEvidence.Loopback]::QpcFrequency } }
                }
                'reopen' {
                    $r = Reopen-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000 -StartTimeoutMs 120000
                    if ($r.status -eq 'ok') { $session = $r.result.session }
                    $r
                }
                'stop' {
                    $r = Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000
                    if ($r.status -eq 'ok' -or ($null -ne $r.result -and $r.result.input_lease_released -eq $true)) { $session = $null }
                    $r
                }
                default { throw 'Unknown public player operation' }
            }
            [Console]::WriteLine('@@' + ($result | ConvertTo-Json -Depth 40 -Compress))
        } catch {
            [Console]::WriteLine('@@' + (@{status='host_exception';exception_type=$_.Exception.GetType().Name;message=$_.Exception.Message} | ConvertTo-Json -Compress))
        }
    }
} finally {
    if ('PlayerEvidence.Loopback' -as [type]) { [PlayerEvidence.Loopback]::Stop() }
    if ($null -ne $session) { Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000 | Out-Null }
    Remove-Module UnrealEvaluationExecutor -ErrorAction SilentlyContinue
}
