[CmdletBinding()]
param(
    [string]$EngineRoot = $env:UE_5_7_ROOT
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-Engine([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }
    try { $resolved = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path } catch { return $null }
    $versionPath = Join-Path $resolved 'Engine/Build/Build.version'
    $editorPath = Join-Path $resolved 'Engine/Binaries/Win64/UnrealEditor.exe'
    $cmdPath = Join-Path $resolved 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe'
    $buildPath = Join-Path $resolved 'Engine/Build/BatchFiles/Build.bat'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $editorPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $cmdPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $buildPath -PathType Leaf)) { return $null }
    try { $version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if ([int]$version.MajorVersion -ne 5 -or [int]$version.MinorVersion -ne 7 -or [int]$version.PatchVersion -ne 4 -or [int64]$version.Changelist -ne 51494982) { return $null }
    return [pscustomobject]@{
        engine_root = $resolved
        version = '{0}.{1}.{2}' -f $version.MajorVersion,$version.MinorVersion,$version.PatchVersion
        changelist = [int64]$version.Changelist
        editor = $editorPath
        editor_cmd = $cmdPath
        build = $buildPath
        source = 'explicit_or_environment'
    }
}

$candidates = [Collections.Generic.List[string]]::new()
if ($EngineRoot) { [void]$candidates.Add($EngineRoot) }
$launcherManifest = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Epic/UnrealEngineLauncher/LauncherInstalled.dat'
if (Test-Path -LiteralPath $launcherManifest -PathType Leaf) {
    try {
        $launcher = Get-Content -LiteralPath $launcherManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($item in @($launcher.InstallationList)) {
            if ([string]$item.AppName -eq 'UE_5.7' -or [string]$item.ArtifactId -eq 'UE_5.7') { [void]$candidates.Add([string]$item.InstallLocation) }
        }
    } catch {}
}
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
if ($programFiles) { [void]$candidates.Add((Join-Path $programFiles 'Epic Games/UE_5.7')) }

$result = $null
foreach ($candidate in $candidates | Select-Object -Unique) {
    $result = Test-Engine $candidate
    if ($result) { break }
}
if (-not $result) {
    throw 'Unreal Engine 5.7.4 (CL 51494982) was not found. Set UE_5_7_ROOT or pass -EngineRoot to the installed UE 5.7.4 directory.'
}
$result | ConvertTo-Json -Depth 8
