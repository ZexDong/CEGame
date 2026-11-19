[CmdletBinding()]
param([string]$InputRoot = (Split-Path $PSScriptRoot), [switch]$AllowProjectChanges)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $InputRoot).Path
$manifest = Get-Content -LiteralPath (Join-Path $root 'BENCHMARK_MANIFEST.json') -Raw | ConvertFrom-Json

$errors = [Collections.Generic.List[string]]::new()

























if (-not (Test-Path -LiteralPath (Join-Path $root $manifest.project_file))) { $errors.Add('Project descriptor is missing.') }
@{status=$(if($errors.Count){'failed'}else{'passed'});allow_project_changes=[bool]$AllowProjectChanges;errors=@($errors);gameplay_verified=$false} | ConvertTo-Json -Depth 5
if ($errors.Count) { exit 1 }
exit 0
