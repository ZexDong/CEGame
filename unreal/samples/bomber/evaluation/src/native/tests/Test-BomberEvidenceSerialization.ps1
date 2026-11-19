[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Invoke-BomberCanonicalEvaluation.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Runner syntax error.' }
$node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-JsonFile'}, $true)
. ([scriptblock]::Create($node.Extent.Text))
$path = Join-Path ([IO.Path]::GetTempPath()) ('bomber-evidence-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    Write-JsonFile -Value @() -Path $path
    if ((Get-Content -LiteralPath $path -Raw).Trim() -cne '[]') { throw 'An empty observation must serialize as an empty array.' }
    Write-JsonFile -Value @([pscustomobject]@{snapshot_id=1}) -Path $path
    $json = Get-Content -LiteralPath $path -Raw
    if (-not $json.TrimStart().StartsWith('[')) { throw 'A single observation lost its array shape.' }
    Write-JsonFile -Value $null -Path $path
    if ((Get-Content -LiteralPath $path -Raw).Trim() -cne 'null') { throw 'An unavailable expectation must serialize as null.' }
    Write-JsonFile -Value ([ordered]@{available=$false;expectation=$null}) -Path $path
    $value = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($value.available -or $null -ne $value.expectation) { throw 'Missing-chain evidence was changed.' }
} finally {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
Write-Output 'EVIDENCE_SERIALIZATION_OK empty_samples=true singleton_array=true null_expectation=true'
