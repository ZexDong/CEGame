param([string]$Rojo = 'rojo')
$ErrorActionPreference = 'Stop'
$projectFile = Join-Path $PSScriptRoot 'default.project.json'
$outputFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'TideLockCandidate.rbxlx'
& $Rojo build $projectFile -o $outputFile
if ($LASTEXITCODE -ne 0) { throw "Rojo build failed: $LASTEXITCODE" }
Write-Host "Built $outputFile. Building does not prove successful Play."
