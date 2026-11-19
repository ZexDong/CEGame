param([Parameter(Mandatory)][string]$ToolsRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $ToolsRoot 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1') -Force
$session = $null
try {
    while ($null -ne ($line = [Console]::ReadLine())) {
        try {
            $q = $line | ConvertFrom-Json -AsHashtable
            $r = switch ($q.op) {
                'start' {
                    $s = Start-UnrealEvaluationSession -ProjectPath $q.project -RunRoot $q.root -StatePath (Join-Path $q.root 'executor-state.json') -EngineRoot $q.engine -ObserverDisabledControl -TimeoutMs 120000 -WindowWidth 1280 -WindowHeight 720 -AdditionalArguments @("-RollBallStatePath=$($q.state)", '-nosound')
                    if ($s.status -eq 'ok') { $session = $s.result.session }
                    $s
                }
                'down' { Start-UnrealKeyHold -Session $session -Key $q.key }
                'up' { Stop-UnrealKeyHold -Session $session -Key $q.key }
                'capture' { Save-UnrealClientCapture -Session $session -OutputPath $q.path }
                'pointer' { Move-UnrealPointer -Session $session -NormalizedX 0.8 -NormalizedY 0.25 }
                'stop' { $s = Stop-UnrealEvaluationSession -Session $session; $session = $null; $s }
                'alive' { @{status='ok';result=@{alive=[bool](Get-Process -Id $q.pid -ErrorAction SilentlyContinue)}} }
                default { throw 'Unknown operation.' }
            }
            [Console]::WriteLine(($r | ConvertTo-Json -Depth 40 -Compress))
        } catch {
            [Console]::WriteLine((@{status='bridge_error';error=$_.Exception.Message} | ConvertTo-Json -Compress))
        }
    }
} finally {
    if ($session) { Stop-UnrealEvaluationSession -Session $session | Out-Null }
}
