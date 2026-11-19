param([Parameter(Mandatory=$true)][string]$CandidateProject,[Parameter(Mandatory=$true)][string]$OutputPlace,[string]$RunnerScript='')
$ErrorActionPreference='Stop'
$here=Split-Path -Parent $PSCommandPath; $root=(Resolve-Path (Join-Path $here '..')).Path
if(-not $RunnerScript){$RunnerScript=Join-Path $here 'runtime\rfp_formal_runner.client.luau'}
$packageRoot=(Resolve-Path (Join-Path $here '..\..')).Path
$rojo=if($env:ROJO_EXE){$env:ROJO_EXE}else{Join-Path $packageRoot 'input\Tools\rojo.exe'}
$project=(Resolve-Path (Join-Path $CandidateProject 'default.project.json')).Path
foreach($p in @($rojo,$project,(Join-Path $here 'runtime\rfp_observer.client.luau'),$RunnerScript)){if(-not(Test-Path -LiteralPath $p)){throw "Missing required path: $p"};Write-Host "Resolved: $((Resolve-Path -LiteralPath $p).Path)"}
$j=Get-Content -Raw -LiteralPath $project|ConvertFrom-Json
function Absolutize($node){if($node -is [pscustomobject]){foreach($p in @($node.PSObject.Properties)){if($p.Name -eq '$path'){$p.Value=(Resolve-Path -LiteralPath (Join-Path $CandidateProject $p.Value)).Path}else{Absolutize $p.Value}}}}
Absolutize $j
$sp=$j.tree.StarterPlayer.StarterPlayerScripts
$sp|Add-Member -Force NoteProperty RFP_QAObserver ([pscustomobject]@{'$path'=(Resolve-Path "$here\runtime\rfp_observer.client.luau").Path})
$sp|Add-Member -Force NoteProperty RFP_FormalRunner ([pscustomobject]@{'$path'=(Resolve-Path -LiteralPath $RunnerScript).Path})
$generated=Join-Path (Split-Path -Parent $OutputPlace) 'generated.qa.project.json'; [IO.File]::WriteAllText($generated,($j|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))
& $rojo build $generated -o $OutputPlace;if($LASTEXITCODE -ne 0){throw "Rojo failed: $LASTEXITCODE"};Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPlace
