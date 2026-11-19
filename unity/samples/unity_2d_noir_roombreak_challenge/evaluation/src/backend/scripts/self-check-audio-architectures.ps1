[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$EvaluationRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $EvaluationRoot))
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$Work = Join-Path $RepoRoot "tmp\noir-audio-architecture-regression-$Stamp"
$DotNet = 'D:\game\engine\unity\6000.0.80f1\Editor\Data\NetCoreRuntime\dotnet.exe'
$Csc = 'D:\game\engine\unity\6000.0.80f1\Editor\Data\DotNetSdkRoslyn\csc.dll'
$Source = Join-Path $EvaluationRoot 'package\Tests\Dynamic\SuppliedAssetRules.cs'
$Test = Join-Path $PSScriptRoot 'NoirAudioArchitectureRegression.cs'
foreach ($Path in @($DotNet,$Csc,$Source,$Test)) { if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing regression input: $Path" } }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Rsp = Join-Path $Work 'compile.rsp'
$Exe = Join-Path $Work 'NoirAudioArchitectureRegression.exe'
$RuntimeConfig = Join-Path $Work 'NoirAudioArchitectureRegression.runtimeconfig.json'
$Refs = @(
  'D:\game\engine\unity\6000.0.80f1\Editor\Data\NetStandard\ref\2.1.0\netstandard.dll'
)
$Lines = @('/nologo','/target:exe','/langversion:9.0',('/out:"' + $Exe + '"'))
foreach ($Ref in $Refs) { $Lines += ('/reference:"' + $Ref + '"') }
$Lines += ('"' + $Source + '"')
$Lines += ('"' + $Test + '"')
[IO.File]::WriteAllLines($Rsp,$Lines,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($RuntimeConfig,'{"runtimeOptions":{"tfm":"net6.0","framework":{"name":"Microsoft.NETCore.App","version":"6.0.21"}}}',[Text.UTF8Encoding]::new($false))
try {
  & $DotNet $Csc "@$Rsp"
  if ($LASTEXITCODE -ne 0) { throw "Regression compilation failed: $LASTEXITCODE" }
  & $DotNet $Exe
  if ($LASTEXITCODE -ne 0) { throw "Regression execution failed: $LASTEXITCODE" }
} finally {
  if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
}
