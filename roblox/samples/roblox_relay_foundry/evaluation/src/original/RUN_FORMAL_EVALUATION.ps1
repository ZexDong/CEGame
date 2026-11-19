param([string]$Python='', [string]$OutputDirectory='', [string]$CandidateProject='', [int]$TimeoutSeconds=3600, [switch]$NoPause)
$ErrorActionPreference='Stop';$OutputEncoding=[Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
Write-Host "Relay Foundry formal controller v20260908 (single-fire prompt hold; PID focus recovery; PromptShown gate; $TimeoutSeconds second limit)"
$here=Split-Path -Parent $PSCommandPath;$root=(Resolve-Path (Join-Path $here '..')).Path
if(-not $CandidateProject){$CandidateProject=Join-Path $root 'qa_project\candidate_project'}
$candidate=(Resolve-Path -LiteralPath $CandidateProject).Path;$qa=Join-Path $root 'qa_project\RelayFoundryCandidate_QA.rbxlx'
if(-not $Python){$cmd=Get-Command python -ErrorAction SilentlyContinue;if($cmd){$Python=$cmd.Source}}
if(-not $Python -or -not(Test-Path -LiteralPath $Python)){throw 'Python was not found. Run with -Python <absolute python.exe path>.'}
& (Join-Path $here 'build_qa_place.ps1') -CandidateProject $candidate -OutputPlace $qa
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root ('results\formal\run_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
Write-Host "Formal evidence directory: $OutputDirectory"
& $Python (Join-Path $here 'run_formal.py') --qa $qa --output $OutputDirectory --timeout $TimeoutSeconds
$firstExit=$LASTEXITCODE
if($firstExit -ne 0 -and (Test-Path -LiteralPath (Join-Path $OutputDirectory 'STARTUP_RETRYABLE.txt'))){
  $retryDirectory=$OutputDirectory+'_startup_retry'
  Write-Host 'Startup attempt was invalid before gameplay. Launching one fresh Studio retry; this is not a second formal trajectory.' -ForegroundColor Yellow
  Start-Sleep -Seconds 4
  & $Python (Join-Path $here 'run_formal.py') --qa $qa --output $retryDirectory --timeout $TimeoutSeconds
  $firstExit=$LASTEXITCODE
  if($firstExit -eq 0){Write-Host "Valid formal evidence directory: $retryDirectory" -ForegroundColor Green}
}
if($firstExit -ne 0){Write-Host 'Formal run did not produce a score. Inspect bridge_error.txt / Studio log.' -ForegroundColor Yellow}
if(-not $NoPause){Read-Host 'Press Enter to close'}
exit $firstExit
