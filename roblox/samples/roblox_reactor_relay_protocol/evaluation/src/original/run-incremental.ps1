param(
    [Parameter(Mandatory=$true)][string]$Game,
    [Parameter(Mandatory=$true)][string]$SourceZip
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$trace = Join-Path $root 'evidence\incremental-runtime-trace.jsonl'
$script = Join-Path $root 'checkpoint-script-incremental.json'
$baseline = Join-Path $root 'evaluation-report.json'
$python = 'E:\python\python.exe'
$env:REACTOR_GUI_ONLY = '1'

Write-Host 'Reactor Relay incremental supplemental evaluation'
Write-Host 'Only retry_rules and retry_win are executed; completed checks are retained from the prior report.'
Write-Host 'Do not use the keyboard or mouse until the run completes.'
& $python -B (Join-Path $root 'player_runtime.py') --game $Game --trace $trace --script $script
if ($LASTEXITCODE -ne 0) { throw "incremental player runtime failed with exit code $LASTEXITCODE" }
& $python -B (Join-Path $root 'evaluate.py') --game $Game --source-zip $SourceZip --trace $trace --script $script --baseline $baseline --out $baseline
$scoreExit = $LASTEXITCODE
if ($scoreExit -eq 2) {
    Write-Warning "Report was produced but remains incomplete_evidence; no formal total is claimed."
    exit 2
}
if ($scoreExit -ne 0) { throw "incremental evaluator failed with exit code $scoreExit" }
Write-Host "Report: $baseline"
