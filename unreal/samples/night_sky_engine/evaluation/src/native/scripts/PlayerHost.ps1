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
                        AdditionalArguments = @('-ForceRes', "-EvalGameStatePath=$($command.root)/state/duel-state.json")
                    }
                    if ($command.PSObject.Properties.Name -contains 'observer_disabled' -and $command.observer_disabled) {
                        $args.ObserverDisabledControl = $true
                    }
                    if ($command.PSObject.Properties.Name -contains 'map') { $args.AdditionalArguments += [string]$command.map }
                    $preflightRetries = [Collections.Generic.List[object]]::new()
                    $preflightClock = [Diagnostics.Stopwatch]::StartNew()
                    do {
                        $start = Start-UnrealEvaluationSession @args
                        $retryablePreflight = $start.status -ne 'ok' -and $start.fault.code -in @('active_input_session_exists','input_state_not_neutral')
                        if (-not $retryablePreflight -or $preflightClock.Elapsed.TotalSeconds -ge 120) { break }
                        $preflightRetries.Add([pscustomobject]@{code=$start.fault.code;elapsed_ms=$preflightClock.ElapsedMilliseconds})
                        Start-Sleep -Milliseconds 250
                    } while ($true)
                    if ($preflightRetries.Count) { $start | Add-Member -NotePropertyName host_preflight_retries -NotePropertyValue @($preflightRetries) }
                    if ($start.status -eq 'ok') { $session = $start.result.session }
                    $start
                }
                'press' { Invoke-UnrealPressKey -Session $session -Key $command.key -DurationMs 50 }
                'down' { Start-UnrealKeyHold -Session $session -Key $command.key }
                'up' { Stop-UnrealKeyHold -Session $session -Key $command.key }
                'capture' { Save-UnrealClientCapture -Session $session -OutputPath $command.path -ArtifactId $command.id }
                'reopen' {
                    $opened = Reopen-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000 -StartTimeoutMs 60000
                    if ($opened.status -eq 'ok') { $session = $opened.result.session }
                    $opened
                }
                'stop' {
                    $stopped = Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000
                    if ($stopped.status -eq 'ok') { $session = $null }
                    $stopped
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
