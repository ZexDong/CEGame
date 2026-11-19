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

if (-not $StaticOnly) {
    Write-Host 'Using the previously proven Roblox EditFile handoff to open the QA place, then Windows SendInput for the real trajectory. Please do not operate the keyboard or mouse.'
    & python -B (Join-Path $root 'player_runtime.py') --game $Game --trace $trace
    if ($LASTEXITCODE -ne 0) { throw "player runtime failed with exit code $LASTEXITCODE" }
}

$args = @((Join-Path $root 'evaluate.py'), '--game', $Game, '--source-zip', $SourceZip, '--out', $report)
if (-not $StaticOnly) { $args += @('--trace', $trace) }
if ($null -ne $D6) { $args += @('--d6', [string]$D6) }
& python -B @args
if ($LASTEXITCODE -ne 0) { throw "evaluator failed with exit code $LASTEXITCODE" }
Write-Host "Report: $report"
