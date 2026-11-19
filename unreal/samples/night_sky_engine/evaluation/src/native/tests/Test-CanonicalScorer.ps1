[CmdletBinding()]
param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
& $Python -m unittest discover -s $PSScriptRoot -p 'test_*.py' -v
exit $LASTEXITCODE
