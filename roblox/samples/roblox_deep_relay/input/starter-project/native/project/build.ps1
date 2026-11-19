$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$projectFile = Join-Path $projectRoot 'default.project.json'
$outputFile = Join-Path (Split-Path -Parent $projectRoot) 'DeepRelayCandidate.rbxlx'
$rojo = Get-Command rojo -ErrorAction Stop
& $rojo.Source build $projectFile -o $outputFile
if ($LASTEXITCODE -ne 0) { throw "Rojo build failed with exit code $LASTEXITCODE" }
Write-Host "Built candidate starter: $outputFile"
