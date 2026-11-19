[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CandidateProject,
  [Parameter(Mandatory=$true)][string]$OutputRoot
)
& (Join-Path $PSScriptRoot 'run.ps1') -ProjectPath $CandidateProject -OutputRoot $OutputRoot
exit $LASTEXITCODE
