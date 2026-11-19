param(
    [Parameter(Mandatory=$true)][string]$Game,
    [Parameter(Mandatory=$true)][string]$SourceZip,
    [switch]$StaticOnly,
    [Nullable[double]]$D6
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$trace = Join-Path $root 'evidence\runtime-trace.jsonl'
$report = Join-Path $root 'evaluation-report.json'
$script = Join-Path $root 'checkpoint-script.json'
$originalFailure = Join-Path $root 'evidence\candidate-runtime-failure.txt'
if (-not $StaticOnly) {
    Write-Host 'Starting the complete Reactor Relay hard-variant trajectory.'
    & python -B (Join-Path $root 'player_runtime.py') --game $Game --trace $trace --script $script
    $runtimeExit = $LASTEXITCODE
    if ($runtimeExit -ne 0 -and $runtimeExit -ne 3) { throw "player runtime failed with exit code $runtimeExit" }
}
$evalArgs = @((Join-Path $root 'evaluate.py'), '--game', $Game, '--source-zip', $SourceZip, '--out', $report, '--script', $script, '--original-runtime-failure', $originalFailure, '--finalize-incomplete-as-fail')
if (-not $StaticOnly -and $runtimeExit -eq 0) { $evalArgs += @('--trace', $trace) }
if (-not $StaticOnly -and $runtimeExit -eq 3) {
    $evalArgs += @('--candidate-runtime-failure', (Join-Path $root 'evidence\candidate-runtime-failure.txt'))
}
if ($null -ne $D6) { $evalArgs += @('--d6', [string]$D6) }
& python -B @evalArgs
if ($LASTEXITCODE -ne 0) { throw "evaluator failed with exit code $LASTEXITCODE" }
Write-Host "Report: $report"
