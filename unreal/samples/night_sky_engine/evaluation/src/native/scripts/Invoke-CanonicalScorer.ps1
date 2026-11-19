[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RawPath,
    [string]$SemanticReviewPath,
    [Parameter(Mandatory)][string]$D6RunPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$scorerArguments = @('--raw', $RawPath, '--d6', $D6RunPath, '--output', $OutputPath)
if ($SemanticReviewPath) { $scorerArguments += @('--semantic', $SemanticReviewPath) }
& $Python (Join-Path $PSScriptRoot 'score.py') @scorerArguments
exit $LASTEXITCODE
