[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$ProjectPath,
    [Parameter(Mandatory=$true)] [string]$OutputDirectory,
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [string]$UnityCliPath=$env:UNITY_CLI,
    [switch]$RetainInvalidDiagnostics
)
$ErrorActionPreference='Stop'
$evaluationRoot=(Resolve-Path -LiteralPath $PSScriptRoot).Path
$demoRoot=Split-Path -Parent $evaluationRoot
$repositoryRoot=Split-Path -Parent (Split-Path -Parent $demoRoot)
$ProjectPath=(Resolve-Path -LiteralPath $ProjectPath).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$repoBoundary=$repositoryRoot.TrimEnd('\')+'\'
$repositoryTmpBoundary=([IO.Path]::GetFullPath((Join-Path $repositoryRoot 'tmp'))).TrimEnd('\')+'\'
foreach($path in @($ProjectPath,$OutputDirectory)){
    if(-not (($path.TrimEnd('\')+'\').StartsWith($repoBoundary,[StringComparison]::OrdinalIgnoreCase))){
        throw "Path must remain inside repository: $path"
    }
}
$projectBoundary=$ProjectPath.TrimEnd('\')+'\'
if(($OutputDirectory.TrimEnd('\')+'\').StartsWith($projectBoundary,[StringComparison]::OrdinalIgnoreCase)){
    throw "OutputDirectory must not be inside the candidate project: $OutputDirectory"
}
if($RetainInvalidDiagnostics -and
   -not (($OutputDirectory.TrimEnd('\')+'\').StartsWith($repositoryTmpBoundary,[StringComparison]::OrdinalIgnoreCase))){
    throw 'RetainInvalidDiagnostics is author-only and requires OutputDirectory under repository tmp/.'
}
if(Test-Path -LiteralPath $OutputDirectory){
    throw "OutputDirectory must not already exist: $OutputDirectory"
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $OutputDirectory))|Out-Null
[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
$runId='dungeon-v2-eval-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$scratch=Join-Path $repositoryRoot ('tmp\'+$runId)
if(Test-Path -LiteralPath $scratch){throw "Scratch already exists: $scratch"}
$temporaryCompany='OmniGameBenchmarkTemp'
$temporaryProduct=$runId
$localLowRoot=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) '..\LocalLow'))
$localLowCompany=Join-Path $localLowRoot $temporaryCompany
$localLowLeaf=Join-Path $localLowCompany $temporaryProduct
$registryCompany='HKCU:\Software\'+$temporaryCompany
$registryLeaf=$registryCompany+'\'+$temporaryProduct
$companyExistedBefore=Test-Path -LiteralPath $localLowCompany -PathType Container
$registryCompanyExistedBefore=Test-Path -LiteralPath $registryCompany
$skip=@('Library','Temp','Logs','UserSettings','obj','.git')
function Copy-Tree([string]$source,[string]$destination){
    [IO.Directory]::CreateDirectory($destination)|Out-Null
    foreach($file in [IO.Directory]::EnumerateFiles($source)){
        [IO.File]::Copy($file,(Join-Path $destination ([IO.Path]::GetFileName($file))),$true)
    }
    foreach($dir in [IO.Directory]::EnumerateDirectories($source)){
        $name=[IO.Path]::GetFileName($dir)
        if($skip -contains $name){continue}
        Copy-Tree $dir (Join-Path $destination $name)
    }
}
$runnerLog=$OutputDirectory+'.runner.log'
$runnerErr=$OutputDirectory+'.runner.err.log'
$exitCode=3
$previousTemp=$env:TEMP
$previousTmp=$env:TMP
$cleanupHealthy=$true
$cleanupEvents=[System.Collections.Generic.List[object]]::new()
function Quote([string]$value){ '"'+($value-replace '"','\"')+'"' }
function Set-TemporaryUnityIdentity([string]$project){
    $settings=Join-Path $project 'ProjectSettings\ProjectSettings.asset'
    if(-not (Test-Path -LiteralPath $settings -PathType Leaf)){
        throw "Unity project is missing ProjectSettings.asset: $project"
    }
    $text=Get-Content -Raw -Encoding UTF8 -LiteralPath $settings
    $companyPattern='(?m)^  companyName:.*$'
    $productPattern='(?m)^  productName:.*$'
    if(([regex]::Matches($text,$companyPattern)).Count -ne 1 -or
       ([regex]::Matches($text,$productPattern)).Count -ne 1){
        throw 'ProjectSettings.asset must contain exactly one companyName and productName.'
    }
    $text=[regex]::Replace($text,$companyPattern,'  companyName: '+$temporaryCompany)
    $text=[regex]::Replace($text,$productPattern,'  productName: '+$temporaryProduct)
    [IO.File]::WriteAllText($settings,$text,[Text.UTF8Encoding]::new($false))
}
function Remove-ExactLocalLowLeaf{
    $rootBoundary=$localLowRoot.TrimEnd('\')+'\'
    $companyBoundary=([IO.Path]::GetFullPath($localLowCompany)).TrimEnd('\')+'\'
    $leafFull=[IO.Path]::GetFullPath($localLowLeaf)
    if(-not $companyBoundary.StartsWith($rootBoundary,[StringComparison]::OrdinalIgnoreCase) -or
       -not (($leafFull.TrimEnd('\')+'\').StartsWith($companyBoundary,[StringComparison]::OrdinalIgnoreCase)) -or
       [IO.Path]::GetFileName($leafFull) -ne $temporaryProduct){
        throw "Refusing unsafe LocalLow cleanup: $leafFull"
    }
    if(Test-Path -LiteralPath $leafFull -PathType Container){
        [IO.Directory]::Delete($leafFull,$true)
        $cleanupEvents.Add([pscustomobject]@{kind='local_low_leaf';path=$leafFull;removed=$true})
    }else{
        $cleanupEvents.Add([pscustomobject]@{kind='local_low_leaf';path=$leafFull;removed=$false})
    }
    if(-not $companyExistedBefore -and (Test-Path -LiteralPath $localLowCompany -PathType Container) -and
       @(Get-ChildItem -LiteralPath $localLowCompany -Force).Count -eq 0){
        [IO.Directory]::Delete($localLowCompany,$false)
    }
}
function Remove-ExactPlayerPrefsLeaf{
    if(-not $registryLeaf.StartsWith('HKCU:\Software\OmniGameBenchmarkTemp\',[StringComparison]::OrdinalIgnoreCase) -or
       $registryLeaf -ne ('HKCU:\Software\'+$temporaryCompany+'\'+$temporaryProduct)){
        throw "Refusing unsafe PlayerPrefs cleanup: $registryLeaf"
    }
    $removed=Test-Path -LiteralPath $registryLeaf
    if($removed){Remove-Item -LiteralPath $registryLeaf -Recurse -Force}
    $cleanupEvents.Add([pscustomobject]@{kind='player_prefs_leaf';path=$registryLeaf;removed=$removed})
    if(-not $registryCompanyExistedBefore -and (Test-Path -LiteralPath $registryCompany) -and
       @(Get-ChildItem -LiteralPath $registryCompany -Force).Count -eq 0){
        Remove-Item -LiteralPath $registryCompany -Force
    }
}
try{
    Copy-Tree $ProjectPath $scratch
    Set-TemporaryUnityIdentity $scratch
    $processTemp=Join-Path $scratch '_os-temp'
    [IO.Directory]::CreateDirectory($processTemp)|Out-Null
    # Unity CLI, the Editor and every child process inherit repository-local
    # process temp roots. They are restored and deleted in finally.
    $env:TEMP=$processTemp
    $env:TMP=$processTemp
    $shell=(Get-Process -Id $PID).Path
    $inner=Join-Path $evaluationRoot 'scripts\run-evaluation.ps1'
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote $inner),
        '-ProjectPath',(Quote $scratch),'-OutputDirectory',(Quote $OutputDirectory),
        '-UnityEditorPath',(Quote $UnityEditorPath),'-UnityCliPath',(Quote $UnityCliPath),
        '-AllowRepositoryTmpOutput')
    # Windows PowerShell 5.1 can report ExitCode=0 after a manual WaitForExit()
    # when redirected child streams are involved. Let Start-Process own the wait
    # so both Windows PowerShell 5.1 and pwsh 7 observe the real child exit code.
    $process=Start-Process -FilePath $shell -ArgumentList $args -WorkingDirectory $repositoryRoot `
        -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $runnerLog -RedirectStandardError $runnerErr
    $innerExitCode=[int]$process.ExitCode
    $exitCode=if($innerExitCode -eq 0){0}else{3}
    if(Test-Path -LiteralPath $runnerLog){Get-Content -LiteralPath $runnerLog}
    if($exitCode -ne 0 -and (Test-Path -LiteralPath $runnerErr)){
        Get-Content -LiteralPath $runnerErr -ErrorAction SilentlyContinue | Write-Warning
    }
}
catch{
    $exitCode=3
    Write-Warning $_.Exception.Message
}
finally{
    $env:TEMP=$previousTemp
    $env:TMP=$previousTmp
    try{Remove-ExactLocalLowLeaf}catch{
        $cleanupHealthy=$false
        $cleanupEvents.Add([pscustomobject]@{kind='local_low_leaf';path=$localLowLeaf;removed=$false;error=$_.Exception.Message})
    }
    try{Remove-ExactPlayerPrefsLeaf}catch{
        $cleanupHealthy=$false
        $cleanupEvents.Add([pscustomobject]@{kind='player_prefs_leaf';path=$registryLeaf;removed=$false;error=$_.Exception.Message})
    }
    try{
        if(Test-Path -LiteralPath $scratch){
            $resolved=(Resolve-Path -LiteralPath $scratch).Path
            if(-not (($resolved.TrimEnd('\')+'\').StartsWith($repositoryTmpBoundary,[StringComparison]::OrdinalIgnoreCase))){
                throw "Refusing unsafe scratch cleanup: $resolved"
            }
            Get-ChildItem -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}}
            [IO.Directory]::Delete($resolved,$true)
        }
    }catch{
        $cleanupHealthy=$false
        $cleanupEvents.Add([pscustomobject]@{kind='repository_scratch';path=$scratch;removed=$false;error=$_.Exception.Message})
    }
    if(Test-Path -LiteralPath $OutputDirectory -PathType Container){
        $cleanupRecord=[pscustomobject]@{
            schema_version=1
            run_id=$runId
            company=$temporaryCompany
            product=$temporaryProduct
            cleanup_healthy=$cleanupHealthy
            events=@($cleanupEvents)
        }
        [IO.File]::WriteAllText((Join-Path $OutputDirectory 'host-cleanup.json'),
            ($cleanupRecord|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    }
}
if(Test-Path -LiteralPath $runnerLog){[IO.File]::Delete($runnerLog)}
if(Test-Path -LiteralPath $runnerErr){[IO.File]::Delete($runnerErr)}
if(-not $cleanupHealthy){$exitCode=3}
if($exitCode -ne 0 -and $RetainInvalidDiagnostics -and
   (Test-Path -LiteralPath $OutputDirectory -PathType Container)){
    $diagnosticMarker=[pscustomobject]@{
        schema_version=1
        author_diagnostic_only=$true
        valid_score=$false
        run_id=$runId
        retained_path=$OutputDirectory
        cleanup_instruction='Inspect, copy the minimal fix evidence into the Demo if needed, then delete this exact directory.'
    }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'AUTHOR_DIAGNOSTIC_INVALID.json'),
        ($diagnosticMarker|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    Write-Warning "Author diagnostic invalid output retained at: $OutputDirectory"
}elseif($exitCode -ne 0 -and (Test-Path -LiteralPath $OutputDirectory -PathType Container)){
    $resolvedOutput=(Resolve-Path -LiteralPath $OutputDirectory).Path
    if(-not (($resolvedOutput.TrimEnd('\')+'\').StartsWith($repoBoundary,[StringComparison]::OrdinalIgnoreCase))){
        throw "Refusing unsafe invalid-output cleanup: $resolvedOutput"
    }
    [IO.Directory]::Delete($resolvedOutput,$true)
}
exit $exitCode
