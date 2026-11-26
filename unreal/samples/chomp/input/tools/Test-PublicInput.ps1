[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputRoot, [switch]$VerifySnapshot)
$ErrorActionPreference = 'Stop'
$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($python) { $pythonPath = $python.Source } else {
    $engineInfo = & (Join-Path $PSScriptRoot 'Resolve-Unreal57.ps1') | ConvertFrom-Json
    $pythonPath = Join-Path $engineInfo.engine_root 'Engine/Binaries/ThirdParty/Python3/Win64/python.exe'
}
$scriptArgs = @((Join-Path $PSScriptRoot 'check_input.py'), '--input-root', $InputRoot)
if ($VerifySnapshot) { $scriptArgs += '--verify-snapshot' }
& $pythonPath -B @scriptArgs
if ($LASTEXITCODE -ne 0) { throw 'Public input checks failed.' }
