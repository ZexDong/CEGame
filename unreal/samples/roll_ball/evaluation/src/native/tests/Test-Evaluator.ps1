param()
$ErrorActionPreference='Stop'
$python = $env:ROLLBALL_PYTHON
if ([string]::IsNullOrWhiteSpace($python)) {
    $command = Get-Command python3,python -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $python = $command.Source }
}
if ([string]::IsNullOrWhiteSpace($python)) { throw 'Python 3.11+ is required; set ROLLBALL_PYTHON to the interpreter.' }
& $python -B -m unittest discover -s (Join-Path $PSScriptRoot '.') -v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
