param([Parameter(Mandatory)][string]$OutputRoot,[Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][int]$StaticExit,[Parameter(Mandatory)][int]$DynamicExit,[Parameter(Mandatory)][int]$FreshExit,[switch]$CandidateCompileFailure)
$ErrorActionPreference='Stop'
$python=$env:GAMECREATE_PYTHON;if(-not $python){$python=(Get-Command python -ErrorAction Stop).Source}
$args=@((Join-Path $PSScriptRoot 'score.py'),'--output',$OutputRoot,'--project',$ProjectPath,'--static-exit',$StaticExit.ToString(),'--dynamic-exit',$DynamicExit.ToString(),'--fresh-exit',$FreshExit.ToString())
if($CandidateCompileFailure){$args+='--compile-failure'}
& $python @args
exit $LASTEXITCODE
