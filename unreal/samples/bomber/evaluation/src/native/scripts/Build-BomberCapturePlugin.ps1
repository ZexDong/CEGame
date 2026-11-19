[CmdletBinding()]
param([Parameter(Mandatory)][string]$EngineRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$source=Join-Path $root 'native/BomberEvalCapture'
$versionPath=Join-Path $EngineRoot 'Engine/Build/Build.version'
$identity=@((Get-FileHash -LiteralPath $versionPath).Hash)+@(Get-ChildItem -LiteralPath $source -File -Recurse | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
$key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($identity -join ':')))).ToLowerInvariant()
$cache=Join-Path $root (".scratch/n-"+$key.Substring(0,12))
$plugin=Join-Path $cache 'BomberEvalCapture.uplugin'
$receipt=Join-Path $cache 'build-complete.json'
if(-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    # BuildPlugin may clear PackageDir; verify the fully resolved exact cache first.
    $full=[IO.Path]::GetFullPath($cache)
    $allowed=[IO.Path]::GetFullPath((Join-Path $root '.scratch'))+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $cache)) { throw 'evaluator_capture_build_requires_fresh_private_cache' }
    & (Join-Path $EngineRoot 'Engine/Build/BatchFiles/RunUAT.bat') BuildPlugin "-Plugin=$source/BomberEvalCapture.uplugin" "-Package=$full" -NoTargetPlatforms -Unattended | Out-Host
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $cache 'Binaries/Win64/UnrealEditor-BomberEvalCapture.dll'))) { throw 'evaluator_capture_plugin_build_failed' }
    [IO.File]::WriteAllText($receipt,(@{source_engine_identity=$key;build_only=$true;runtime_validated=$false}|ConvertTo-Json))
}
Write-Output $plugin
