$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$here = (Resolve-Path -LiteralPath (Split-Path -Parent $PSCommandPath)).Path
$root = (Resolve-Path -LiteralPath (Join-Path $here '..')).Path
$launcher = Join-Path $here 'RUN_FORMAL_EVALUATION.ps1'
$logDir = Join-Path $root 'results\launcher_logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ('formal_launcher_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -LiteralPath $log -Force | Out-Null
try {
    $candidateProject = if($env:CANDIDATE_PROJECT){$env:CANDIDATE_PROJECT}else{Join-Path $root 'qa_project\candidate_project'}
    $candidate = Join-Path $candidateProject 'default.project.json'
    $runner = Join-Path $here 'run_formal.py'
    foreach ($required in @($launcher, $candidate, $runner)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing required file: $required" }
        Write-Host "Resolved: $((Resolve-Path -LiteralPath $required).Path)"
    }
    $python = $env:PYTHON_EXE
    if (-not $python) {
        $command = Get-Command python -ErrorAction SilentlyContinue
        if ($command) { $python = $command.Source }
    }
    if (-not $python -or -not (Test-Path -LiteralPath $python)) {
        throw 'Python was not discovered. Set PYTHON_EXE to an absolute python.exe path and run again.'
    }
    Write-Host "Python: $((Resolve-Path -LiteralPath $python).Path)"
    Write-Host 'About to run the single formal trajectory: readiness -> death/checkpoint -> R -> error recovery -> full completion -> final R.' -ForegroundColor Cyan
    $formalOutput = Join-Path $root ('results\formal\run_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    & $launcher -Python $python -OutputDirectory $formalOutput -CandidateProject $candidateProject
    if ($LASTEXITCODE -ne 0) { throw "Formal runner exited with code $LASTEXITCODE" }
} catch {
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript | Out-Null
    Write-Host "Launcher log: $log"
}
