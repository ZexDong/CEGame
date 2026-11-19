[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExecutorPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
Import-Module $ExecutorPath -Force -WarningAction SilentlyContinue
$session=$null
try {
    while($line=[Console]::ReadLine()) {
        try {
            $c=$line|ConvertFrom-Json
            $r=switch($c.op) {
                'start' {
                    $args=@{ProjectPath=$c.project;EngineRoot=$c.engine;RunRoot=$c.root;StatePath=(Join-Path $c.root 'engine-health.json');WindowWidth=$c.width;WindowHeight=$c.height;TimeoutMs=120000;ObserverDisabledControl=$true;AdditionalArguments=@('-ForceRes','-NoSplash','-NoMessaging','-NoUDPMessaging','-NoTcpMessaging')+@($c.arguments)}
                    $v=Start-UnrealEvaluationSession @args
                    if($v.status -eq 'ok'){$session=$v.result.session}
                    $v
                }
                'press' {Invoke-UnrealPressKey -Session $session -Key $c.key -DurationMs $c.ms}
                'down' {Start-UnrealKeyHold -Session $session -Key $c.key}
                'up' {Stop-UnrealKeyHold -Session $session -Key $c.key}
                'click' {Invoke-UnrealClick -Session $session -NormalizedX $c.x -NormalizedY $c.y -Button $c.button -DurationMs $c.ms}
                'move' {Move-UnrealPointer -Session $session -NormalizedX $c.x -NormalizedY $c.y}
                'capture' {Save-UnrealClientCapture -Session $session -OutputPath $c.path -ArtifactId $c.id}
                'process_status' {@{status='ok';result=@{alive=($null -ne (Get-Process -Id $session.ProcessId -ErrorAction SilentlyContinue));process_id=$session.ProcessId}}}
                'stop' {
                    $v=Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000
                    if($v.status -eq 'ok' -or ($null -ne $v.result -and $v.result.input_lease_released)){$session=$null}
                    $v
                }
                default {throw 'Unknown player operation'}
            }
            [Console]::WriteLine('@@'+($r|ConvertTo-Json -Depth 50 -Compress))
        } catch {[Console]::WriteLine('@@'+(@{status='host_exception';exception_type=$_.Exception.GetType().Name;message=$_.Exception.Message}|ConvertTo-Json -Compress))}
    }
} finally {if($null -ne $session){Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000|Out-Null}}
