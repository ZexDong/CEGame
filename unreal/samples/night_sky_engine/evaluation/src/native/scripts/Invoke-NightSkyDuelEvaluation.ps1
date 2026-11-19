[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateProject,
    [Parameter(Mandatory)][string]$EngineRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$RunId = ('run-' + [guid]::NewGuid().ToString('N')),
    [string]$CandidateId = 'candidate',
    [string]$SourceReview,
    [string]$Python = 'python',
    [string]$PowerShell = 'pwsh'
)
$ErrorActionPreference = 'Stop'
$ReviewArguments = @()
if ($SourceReview) { $ReviewArguments = @('--source-review', $SourceReview) }
& $Python (Join-Path $PSScriptRoot 'evaluate.py') --project $CandidateProject --engine $EngineRoot --pwsh $PowerShell --output $OutputDirectory --run-id $RunId --candidate-id $CandidateId @ReviewArguments
exit $LASTEXITCODE
