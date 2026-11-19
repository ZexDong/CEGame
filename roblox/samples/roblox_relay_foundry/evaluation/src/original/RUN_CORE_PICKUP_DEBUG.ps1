param([string]$Python='')
$ErrorActionPreference='Stop';$OutputEncoding=[Text.UTF8Encoding]::new($false)
$version='v20260825.2245'
Write-Host "Relay Foundry controller diagnostic $version" -ForegroundColor Cyan
$here=Split-Path -Parent $PSCommandPath;$root=(Resolve-Path (Join-Path $here '..')).Path
if(-not $Python){$cmd=Get-Command python -ErrorAction SilentlyContinue;if($cmd){$Python=$cmd.Source}}
if(-not $Python -or -not(Test-Path -LiteralPath $Python)){throw 'Python was not found.'}
$candidate=Join-Path $root 'qa_project\candidate_project';$qa=Join-Path $root 'qa_project\RelayFoundryCandidate_QA_DEBUG.rbxlx'
$runner=Join-Path $here 'runtime\rfp_core_pickup_debug.client.luau'
& (Join-Path $here 'build_qa_place.ps1') -CandidateProject $candidate -OutputPlace $qa -RunnerScript $runner
$out=Join-Path $root ('results\invalid_debug\wrong_mode_purge_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
Write-Host "About to run invalid controller diagnostic: WrongMode -> Purge -> correct Charge single-fire. No score will be produced." -ForegroundColor Cyan
& $Python (Join-Path $here 'run_formal.py') --qa $qa --output $out --debug
$exitCode=$LASTEXITCODE
if($exitCode -ne 0 -and (Test-Path -LiteralPath (Join-Path $out 'STARTUP_RETRYABLE.txt'))){
  $retry=$out+'_startup_retry'
  Write-Host 'Startup failed before Play. Launching one fresh Studio retry; still no scoring.' -ForegroundColor Yellow
  Start-Sleep -Seconds 4
  & $Python (Join-Path $here 'run_formal.py') --qa $qa --output $retry --debug
  $exitCode=$LASTEXITCODE
}
if($exitCode -ne 0){Write-Host 'Diagnostic did not reach gameplay; inspect bridge_error.txt.' -ForegroundColor Yellow}
Read-Host 'Press Enter to close'
exit $exitCode
