param(
  [string]$Project = (Join-Path $PSScriptRoot '..\Starter\project\default.project.json'),
  [string]$Output = (Join-Path $PSScriptRoot '..\public_smoke_build.rbxlx')
)
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $PSScriptRoot 'luau-compile.exe'
$rojo = Join-Path $PSScriptRoot 'rojo.exe'
$projectPath = (Resolve-Path -LiteralPath $Project).Path
$projectRoot = Split-Path -Parent $projectPath
foreach ($tool in @($compiler,$rojo)) { if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing tool: $tool" } }
$scripts = Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.luau'
if ($scripts.Count -eq 0) { throw 'No Luau files found.' }
foreach ($script in $scripts) { & $compiler $script.FullName | Out-Null; if ($LASTEXITCODE -ne 0) { throw "Luau compile failed: $($script.FullName)" } }
& $rojo build $projectPath --output $Output
if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Output).Hash
[ordered]@{passed=$true;script_count=$scripts.Count;project=$projectPath;output=(Resolve-Path -LiteralPath $Output).Path;sha256=$hash} | ConvertTo-Json
