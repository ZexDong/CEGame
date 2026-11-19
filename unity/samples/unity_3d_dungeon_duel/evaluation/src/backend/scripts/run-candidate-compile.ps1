[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ProjectPath,
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [string]$UnityCliPath=$env:UNITY_CLI,
    [string]$OutputDirectory = '',
    [ValidateRange(1,3600)] [int]$TimeoutSeconds = 600,
    [switch]$NoExitOnCompletion
)
$ErrorActionPreference='Stop'
$ProjectPath=(Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath=(Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath=(Resolve-Path -LiteralPath $UnityCliPath).Path
$classifierPath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'classify-unity-phase-result.ps1')).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'OutputDirectory is required.' }
if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw "Project is open: $ProjectPath" }
$runId=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$resultPath=Join-Path $OutputDirectory "$runId-candidate-editmode.xml"
$logPath=Join-Path $OutputDirectory "$runId-candidate-compile.log"
$stdout=Join-Path $OutputDirectory "$runId-cli.stdout.log"
$stderr=Join-Path $OutputDirectory "$runId-cli.stderr.log"
function Quote([string]$v){'"'+($v-replace '"','\"')+'"'}
$args=@('--json','--non-interactive','test',(Quote $ProjectPath),'--mode','EditMode',
    '--filter','__OMNIGAME_COMPILE_ONLY__','--output',(Quote $resultPath),
    '--editor-path',(Quote $UnityEditorPath),'--timeout',$TimeoutSeconds.ToString(),
    '--','-logFile',(Quote $logPath))
$timedOut=$false;$exitCode=-1;$process=$null
$process=Start-Process -FilePath $UnityCliPath -ArgumentList $args -WorkingDirectory $ProjectPath `
    -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$graceSeconds=if($TimeoutSeconds -le 5){2}else{45}
if(-not $process.WaitForExit(($TimeoutSeconds+$graceSeconds)*1000)){
    $timedOut=$true;Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;$process.WaitForExit(10000)|Out-Null;$exitCode=124
}else{$process.WaitForExit();$exitCode=[int]$process.ExitCode}
if(-not(Test-Path -LiteralPath $logPath -PathType Leaf)){
    $parts=@();if(Test-Path $stdout){$parts+=Get-Content $stdout -Raw};if(Test-Path $stderr){$parts+=Get-Content $stderr -Raw};
    [IO.File]::WriteAllText($logPath,($parts-join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
}
$classificationRaw=& $classifierPath -ExitCode $exitCode -LogPath $logPath -ProjectPath $ProjectPath -ResultPath $resultPath -TimedOut:$timedOut
$classification=(($classificationRaw-join [Environment]::NewLine)|ConvertFrom-Json)
$result=[pscustomobject]@{phase='BaselineCompile';executor='unity-cli-test';cli_process_id=[int]$process.Id;exit_code=$exitCode;timed_out=$timedOut;timeout_seconds=$TimeoutSeconds;execution_status=[string]$classification.execution_status;failure_kind=[string]$classification.failure_kind;failure_reason=[string]$classification.failure_reason;compiler_errors=@($classification.compiler_errors);result=$resultPath;log=$logPath;cli_stdout=$stdout;cli_stderr=$stderr}
$result|ConvertTo-Json -Depth 6
if(-not $NoExitOnCompletion){exit $exitCode}
