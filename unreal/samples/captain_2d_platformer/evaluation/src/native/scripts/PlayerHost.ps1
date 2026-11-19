[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExecutorPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Import-Module $ExecutorPath -Force -WarningAction SilentlyContinue
$session = $null
$lastCleanup = $null
function Get-ReceiptField($Value, [string]$Name) {
    if ($null -ne $Value -and $Value.PSObject.Properties[$Name]) { return $Value.$Name }
    return $null
}
function Test-CleanupResult($Value) {
    $count = Get-ReceiptField $Value 'job_active_process_count_after_wait'
    return ((Get-ReceiptField $Value 'process_exited') -eq $true -and
        ($count -is [int] -or $count -is [long]) -and $count -eq 0 -and
        (Get-ReceiptField $Value 'job_handle_closed') -eq $true -and
        (Get-ReceiptField $Value 'input_lease_released') -eq $true)
}
try {
    while ($line = [Console]::ReadLine()) {
        try {
            $command = $line | ConvertFrom-Json
            $result = switch ($command.op) {
                'start' {
                    $args = @{
                        ProjectPath = $command.project
                        EngineRoot = $command.engine
                        RunRoot = $command.root
                        StatePath = (Join-Path $command.root 'state/engine-health.json')
                        WindowWidth = 1280
                        WindowHeight = 720
                        TimeoutMs = 60000
                        AdditionalArguments = @('-ForceRes', "-EvalGameStatePath=$($command.root)/state/game-state.json")
                    }
                    if ($command.PSObject.Properties.Name -contains 'observer_disabled' -and $command.observer_disabled) {
                        $args.ObserverDisabledControl = $true
                    }
                    if ($command.PSObject.Properties.Name -contains 'map') { $args.AdditionalArguments += [string]$command.map }
                    $start = Start-UnrealEvaluationSession @args
                    if ($start.status -eq 'ok') { $session = $start.result.session; $lastCleanup = $null }
                    $start
                }
                'press' { Invoke-UnrealPressKey -Session $session -Key $command.key -DurationMs 50 }
                'tap' { Invoke-UnrealPressKey -Session $session -Key $command.key -DurationMs ([Math]::Clamp([int]$command.duration_ms, 1, 1000)) }
                'chord' {
                    # Adjacent ordinary key events avoid a transport round trip
                    # between directional steering and a grounded jump.
                    $held = Start-UnrealKeyHold -Session $session -Key $command.held
                    if ($held.status -ne 'ok') { $held }
                    else {
                        $tap = Invoke-UnrealPressKey -Session $session -Key $command.key -DurationMs 50
                        $tap | Add-Member -NotePropertyName preceding_hold_receipt -NotePropertyValue $held -Force
                        $tap
                    }
                }
                'down' { Start-UnrealKeyHold -Session $session -Key $command.key }
                'up' { Stop-UnrealKeyHold -Session $session -Key $command.key }
                'capture' { Save-UnrealClientCapture -Session $session -OutputPath $command.path -ArtifactId $command.id }
                'reopen' {
                    $opened = Reopen-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000 -StartTimeoutMs 60000
                    if ($opened.status -eq 'ok') { $session = $opened.result.session; $lastCleanup = $null }
                    elseif ((Get-ReceiptField $opened.result 'termination_reason') -eq 'old_session_stop_failed' -and
                        (Test-CleanupResult (Get-ReceiptField $opened.result 'stop_result'))) {
                        $session = $null; $lastCleanup = $opened
                    }
                    $opened
                }
                'stop' {
                    if ($null -eq $session -and $null -ne $lastCleanup) { $lastCleanup }
                    else {
                        $stopped = Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000
                        if (Test-CleanupResult $stopped.result) { $session = $null; $lastCleanup = $stopped }
                        $stopped
                    }
                }
                default { throw 'Unknown player operation' }
            }
            [Console]::WriteLine('@@' + ($result | ConvertTo-Json -Depth 40 -Compress))
        }
        catch {
            [Console]::WriteLine('@@' + (@{status='host_exception';exception_type=$_.Exception.GetType().Name;message=$_.Exception.Message} | ConvertTo-Json -Compress))
        }
    }
}
finally {
    if ($null -ne $session) { Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000 | Out-Null }
    Remove-Module UnrealEvaluationExecutor -ErrorAction SilentlyContinue
}


