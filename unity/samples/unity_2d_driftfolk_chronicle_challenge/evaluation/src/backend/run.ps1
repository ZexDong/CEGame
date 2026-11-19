[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [string]$UnityEditorPath=$env:UNITY_EDITOR,
  [string]$UnityCliPath=$env:UNITY_CLI
)
$ErrorActionPreference='Stop'
$evaluationRoot=(Resolve-Path -LiteralPath $PSScriptRoot).Path
$demoRoot=Split-Path -Parent (Split-Path -Parent $evaluationRoot)
$repoRoot=Split-Path -Parent (Split-Path -Parent $demoRoot)
. (Join-Path $repoRoot 'tools\unity\temporary-unity-identity-v2.ps1')
$identity=$null
$ProjectPath=(Resolve-Path -LiteralPath $ProjectPath).Path.TrimEnd('\')
$UnityEditorPath=(Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath=(Resolve-Path -LiteralPath $UnityCliPath).Path
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$repoBoundary=$repoRoot.TrimEnd('\')+'\'
$tmpBoundary=([IO.Path]::GetFullPath((Join-Path $repoRoot 'tmp'))).TrimEnd('\')+'\'
$runsBoundary=([IO.Path]::GetFullPath((Join-Path $repoRoot 'runs'))).TrimEnd('\')+'\'
foreach($path in @($ProjectPath,$OutputRoot)){if(-not (($path.TrimEnd('\')+'\').StartsWith($repoBoundary,[StringComparison]::OrdinalIgnoreCase))){throw "Path must stay inside repository: $path"}}
$outBoundary=$OutputRoot+'\'
if(-not ($outBoundary.StartsWith($tmpBoundary,[StringComparison]::OrdinalIgnoreCase)-or$outBoundary.StartsWith($runsBoundary,[StringComparison]::OrdinalIgnoreCase))){throw 'OutputRoot must be a new directory under repository tmp/ or runs/.'}
if($outBoundary.StartsWith($ProjectPath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'OutputRoot must not be inside candidate project.'}
if(Test-Path -LiteralPath $OutputRoot){throw "OutputRoot already exists: $OutputRoot"}
if(-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Packages\manifest.json') -PathType Leaf)){throw 'Candidate is not a Unity project.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')){throw 'Candidate project is open; close its exact Unity process before evaluation.'}

$runId='stormbound-session-eval-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$scratch=Join-Path $repoRoot ('tmp\'+$runId+'\project')
$hostTemp=Join-Path $OutputRoot 'host-temp'
$skip=@('Library','Temp','Logs','UserSettings','obj','bin','.git','.vs')
$exit=3
$priorPid=0
$priorSession=''

function Quote([string]$value){'"'+($value-replace '"','\"')+'"'}
function Get-Sha([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-TreeBinding([string]$root){
  $resolved=(Resolve-Path -LiteralPath $root).Path.TrimEnd('\');$records=[Collections.Generic.List[string]]::new();$pending=[Collections.Generic.Stack[string]]::new();$pending.Push($resolved);$fileCount=0;$directoryCount=0;$byteCount=[long]0
  while($pending.Count){$current=$pending.Pop();foreach($directory in [IO.Directory]::EnumerateDirectories($current)){$relative=$directory.Substring($resolved.Length+1).Replace('\','/');if($current-ceq$resolved-and[IO.Path]::GetFileName($directory)-in$skip){continue};$item=Get-Item -LiteralPath $directory -Force;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Tree contains a directory reparse point: $directory"};$records.Add('D|'+$relative);$directoryCount++;$pending.Push($directory)};foreach($file in [IO.Directory]::EnumerateFiles($current)){$item=Get-Item -LiteralPath $file -Force;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Tree contains a file reparse point: $file"};$relative=$file.Substring($resolved.Length+1).Replace('\','/');$length=[long]$item.Length;$records.Add("F|$relative|$length|$(Get-Sha $file)");$fileCount++;$byteCount+=$length}}
  $records.Sort([StringComparer]::Ordinal);$bytes=[Text.Encoding]::UTF8.GetBytes(($records-join"`n"));$sha=[Security.Cryptography.SHA256]::Create();try{$digest=([BitConverter]::ToString($sha.ComputeHash($bytes))-replace'-','').ToLowerInvariant()}finally{$sha.Dispose()}
  [ordered]@{file_count=$fileCount;directory_count=$directoryCount;byte_count=$byteCount;sha256=$digest;algorithm='sha256(utf8(join(ordinal-sorted(D|path,F|path|bytes|sha256), LF)))'}
}
function Copy-Tree([string]$source,[string]$destination){
  [IO.Directory]::CreateDirectory($destination)|Out-Null
  foreach($file in [IO.Directory]::EnumerateFiles($source)){[IO.File]::Copy($file,(Join-Path $destination ([IO.Path]::GetFileName($file))),$true)}
  foreach($directory in [IO.Directory]::EnumerateDirectories($source)){$name=[IO.Path]::GetFileName($directory);if($skip-contains$name){continue};$item=Get-Item -LiteralPath $directory -Force;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Candidate contains a reparse point: $directory"};Copy-Tree $directory (Join-Path $destination $name)}
}
function Get-EvaluatorContractBinding{
  $paths=@('rules.json','checkpoint-script.json','baseline-applicability.json','requirement-coverage.json','session-profile.json','session-dependencies.json','run.ps1','scripts\score.ps1','scripts\score.py')|ForEach-Object{Join-Path $evaluationRoot $_}
  $files=@();$records=@();foreach($path in $paths){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing evaluator contract file: $path"};$rel=$path.Substring($evaluationRoot.Length+1).Replace('\','/');$hash=Get-Sha $path;$item=Get-Item -LiteralPath $path;$files+=[ordered]@{path=$rel;bytes=[long]$item.Length;sha256=$hash};$records+="$rel`t$hash"};$records=[Collections.Generic.List[string]]$records;$records.Sort([StringComparer]::Ordinal);$bytes=[Text.Encoding]::UTF8.GetBytes(($records-join"`n"));$sha=[Security.Cryptography.SHA256]::Create();try{$digest=([BitConverter]::ToString($sha.ComputeHash($bytes))-replace'-','').ToLowerInvariant()}finally{$sha.Dispose()};[ordered]@{file_count=$files.Count;sha256=$digest;algorithm='sha256(utf8(join(ordinal-sorted(relative-path + TAB + file-sha256), LF)))';files=$files}
}
function Set-Identity([string]$project){$script:identity=Set-ScopedUnityIdentity -Project $project -RunId $runId}
function Inject-Evaluator([string]$project){
  $packageName='com.gamecreate.benchmark.stormbound.evaluator'
  $packageSource=Join-Path $evaluationRoot 'package-v2'
  $packageTarget=Join-Path $project ('Packages\'+$packageName)
  if(Test-Path -LiteralPath $packageTarget){throw "Scratch evaluator package already exists: $packageTarget"}
  Copy-Tree $packageSource $packageTarget
  $sessionName='com.gamecreate.evaluation.session';Copy-Tree (Join-Path $repoRoot 'tools\unity\session-evaluation-scoped-v2') (Join-Path $project ('Packages\'+$sessionName))
  $path=Join-Path $project 'Packages\manifest.json';$manifest=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;$dependencies=[ordered]@{};$manifest.dependencies.psobject.Properties|ForEach-Object{$dependencies[$_.Name]=$_.Value};$dependencies[$packageName]='file:'+$packageName;$dependencies[$sessionName]='file:'+$sessionName;$testables=@($manifest.testables|Where-Object{$_});if($testables-notcontains$packageName){$testables+=$packageName};$output=[ordered]@{dependencies=$dependencies;testables=$testables};[IO.File]::WriteAllText($path,($output|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}
function Invoke-Cli([string]$name,[string[]]$arguments,[int]$hostTimeout){
  if(Test-Path -LiteralPath (Join-Path $scratch 'Temp\UnityLockfile')){throw "Scratch project is still owned before $name."}
  $stdout=Join-Path $OutputRoot ($name+'-cli.stdout.log');$stderr=Join-Path $OutputRoot ($name+'-cli.stderr.log')
  $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$UnityCliPath;$psi.WorkingDirectory=$scratch;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  foreach($argument in $arguments){$psi.ArgumentList.Add([string]$argument)}
  $process=[Diagnostics.Process]::new();$process.StartInfo=$psi;$started=$false
  $outStream=[IO.File]::Open($stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$errStream=[IO.File]::Open($stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{
    $started=$process.Start();if(-not$started){throw 'Unity CLI did not start.'};$ownedPid=$process.Id
    $outTask=$process.StandardOutput.BaseStream.CopyToAsync($outStream);$errTask=$process.StandardError.BaseStream.CopyToAsync($errStream)
    $timedOut=-not$process.WaitForExit($hostTimeout*1000)
    if($timedOut){if(-not$process.HasExited){$process.Kill($true)};if(-not$process.WaitForExit(10000)){throw 'Owned CLI tree did not exit after timeout.'};$code=124}else{$code=[int]$process.ExitCode}
    if(-not[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($outTask,$errTask),10000)){throw 'Unity output pipes did not drain.'}
  }finally{if($started-and-not$process.HasExited){$process.Kill($true);$process.WaitForExit(10000)|Out-Null};$outStream.Dispose();$errStream.Dispose();$process.Dispose()}
  [ordered]@{name=$name;executor='unity-cli';cli_process_id=[int]$ownedPid;exit_code=$code;timed_out=$timedOut;stdout=$stdout;stderr=$stderr}
}
function Run-Compile([string]$name,[int]$timeout){
  $log=Join-Path $OutputRoot ($name+'.log');$args=@('--json','--non-interactive','--proxy-disable','run',$scratch,'--editor-path',$UnityEditorPath,'--timeout',$timeout.ToString(),'--','-logFile',$log);$result=Invoke-Cli $name $args ($timeout+60);$result.log=$log;return $result
}
function Run-Test([string]$name,[string]$assembly,[int]$timeout){
  $xml=Join-Path $OutputRoot ($name+'.xml');$log=Join-Path $OutputRoot ($name+'.log');$evidence=Join-Path $OutputRoot ($name+'-evidence.json');$env:STORMBOUND_EVIDENCE_FILE=$evidence
  $identityReceipt=Join-Path $OutputRoot ($name+'-identity.jsonl');$env:STORMBOUND_HOST_IDENTITY_RECEIPT=$identityReceipt
  if($name-eq'dynamic'){$env:STORMBOUND_SCREENSHOT_DIR=Join-Path $OutputRoot 'visual-candidates'}else{Remove-Item Env:STORMBOUND_SCREENSHOT_DIR -ErrorAction SilentlyContinue}
  $args=@('--json','--non-interactive','--proxy-disable','test',$scratch,'--mode','PlayMode','--filter',$assembly,'--output',$xml,'--editor-path',$UnityEditorPath,'--timeout',$timeout.ToString(),'--','-logFile',$log);$result=Invoke-Cli $name $args ($timeout+60);$result.xml=$xml;$result.log=$log;$result.evidence=$evidence;Assert-ScopedIdentityReceipt -Path $identityReceipt -Identity $identity;$result.identity_receipt=$identityReceipt;return $result
}
function Candidate-CompilerErrors([string]$log){if(-not(Test-Path -LiteralPath $log)){return @()};@(Select-String -LiteralPath $log -Pattern '(?i)(?:^|[\\/])Assets[\\/].*error CS\d+'|ForEach-Object{$_.Line.Trim()}|Sort-Object -Unique)}
function Evaluator-CompilerErrors([string]$log){if(-not(Test-Path -LiteralPath $log)){return @()};@(Select-String -LiteralPath $log -Pattern '(?i)evaluation[\\/]package.*error CS\d+|com\.gamecreate\.benchmark\.stormbound\.evaluator.*error CS\d+'|ForEach-Object{$_.Line.Trim()}|Sort-Object -Unique)}

[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null;[IO.Directory]::CreateDirectory($hostTemp)|Out-Null
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
try{
  $sourceBefore=Get-TreeBinding $ProjectPath;$evaluatorPackageSource=Join-Path $evaluationRoot 'package-v2';$evaluatorPackageBefore=Get-TreeBinding $evaluatorPackageSource;$evaluatorContractBefore=Get-EvaluatorContractBinding;Copy-Tree $ProjectPath $scratch;Set-Identity $scratch;$env:TEMP=$hostTemp;$env:TMP=$hostTemp;$env:UseSharedCompilation='false';$env:STORMBOUND_RUN_ID=$runId
  $env:STORMBOUND_HOST_COMPANY=$identity.company;$env:STORMBOUND_HOST_PRODUCT=$identity.product;$env:STORMBOUND_HOST_COMPANY_ROOT=$identity.company_root
  [IO.File]::WriteAllText((Join-Path $OutputRoot 'requested-identity.json'),($identity|ConvertTo-Json -Depth 8))
  $baseline=Run-Compile 'candidate-compile' 600;$candidateErrors=Candidate-CompilerErrors $baseline.log
  if($baseline.exit_code-ne0-and$candidateErrors.Count-gt0){[ordered]@{schema_version=1;classification='candidate_compile_failure';diagnostics=$candidateErrors;baseline=$baseline}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputRoot 'candidate-compile-failure.json') -Encoding utf8;& (Join-Path $evaluationRoot 'scripts\score.ps1') -OutputRoot $OutputRoot -ProjectPath $ProjectPath -StaticExit $baseline.exit_code -DynamicExit -10 -FreshExit -10 -CandidateCompileFailure;$scoreExit=$LASTEXITCODE;$staticExit=$baseline.exit_code;$dynamicExit=-10;$freshExit=-10;$candidateCompileFailure=$true}
  elseif($baseline.exit_code-ne0){throw "Unity CLI candidate compile/import failed without a candidate-owned C# diagnostic. Exit=$($baseline.exit_code)."}
  else{
    $candidateCompileFailure=$false;Inject-Evaluator $scratch;$evaluatorCompile=Run-Compile 'evaluator-compile' 600;$evaluatorErrors=Evaluator-CompilerErrors $evaluatorCompile.log;if($evaluatorCompile.exit_code-ne0-or$evaluatorErrors.Count){throw "Private evaluator failed to compile. Exit=$($evaluatorCompile.exit_code); errors=$($evaluatorErrors -join ' | ')"}
    $static=Run-Test 'static' 'GameCreate.Stormbound.Evaluator.Static' 300;$staticExit=$static.exit_code
    $dynamic=Run-Test 'dynamic' 'GameCreate.Stormbound.Evaluator.Dynamic' 1800;$dynamicExit=$dynamic.exit_code
    if(Test-Path -LiteralPath $dynamic.evidence){$dynamicEvidence=Get-Content -LiteralPath $dynamic.evidence -Raw|ConvertFrom-Json;$priorPid=[int]$dynamicEvidence.process_id;$priorSession=[string]$dynamicEvidence.session_id}
    $env:STORMBOUND_PRIOR_PROCESS_ID=$priorPid.ToString();$env:STORMBOUND_PRIOR_SESSION_ID=$priorSession
    $dirty=Join-Path $OutputRoot 'dirty-close.json';$env:STORMBOUND_PRIOR_DIRTY_STATUS='blocked';$env:STORMBOUND_PRIOR_DIRTY_REASON='Independent dirty-close service preparation failed; see facts/T99_DirtyClose.json'
    if(Test-Path -LiteralPath $dirty){$d=Get-Content -LiteralPath $dirty -Raw|ConvertFrom-Json;$saved=$d.save_json|ConvertFrom-Json;if($saved.contentVersion-eq'driftfolk-stormbound-v2-20260918'-and$saved.entryId-eq'archipelago'-and$saved.phase-eq'playing'-and@($saved.values|Where-Object{$_.name-eq'day'-and$_.value-eq2}).Count-eq1){$env:STORMBOUND_PRIOR_DIRTY_STATUS='ready'}else{throw 'Dirty close receipt is not the prepared real state.'}}
    $fresh=Run-Test 'fresh' 'GameCreate.Stormbound.Evaluator.Fresh' 360;$freshExit=$fresh.exit_code
    & (Join-Path $evaluationRoot 'scripts\score.ps1') -OutputRoot $OutputRoot -ProjectPath $ProjectPath -StaticExit $staticExit -DynamicExit $dynamicExit -FreshExit $freshExit;$scoreExit=$LASTEXITCODE
  }
  $scorePath=Join-Path $OutputRoot 'score.json';$scoreValid=$false;if(Test-Path -LiteralPath $scorePath){$scoreValid=[bool](Get-Content -LiteralPath $scorePath -Raw|ConvertFrom-Json).valid_score}
  $sourceAfter=Get-TreeBinding $ProjectPath;$sourceUnchanged=$sourceBefore.sha256-eq$sourceAfter.sha256-and$sourceBefore.file_count-eq$sourceAfter.file_count;if(-not$sourceUnchanged){throw 'Evaluator modified the source candidate project.'}
  $evaluatorPackageAfter=Get-TreeBinding $evaluatorPackageSource;$evaluatorPackageSourceUnchanged=$evaluatorPackageBefore.sha256-eq$evaluatorPackageAfter.sha256-and$evaluatorPackageBefore.file_count-eq$evaluatorPackageAfter.file_count;if(-not$evaluatorPackageSourceUnchanged){throw 'Unity or the evaluator modified the canonical private evaluator package.'};$evaluatorContractAfter=Get-EvaluatorContractBinding;$evaluatorContractUnchanged=$evaluatorContractBefore.sha256-eq$evaluatorContractAfter.sha256-and$evaluatorContractBefore.file_count-eq$evaluatorContractAfter.file_count;if(-not$evaluatorContractUnchanged){throw 'Evaluator contract changed during evaluation.'}
  [ordered]@{schema_version=3;run_id=$runId;executor='unity-cli-1.0.0-beta.3';unity_cli=$UnityCliPath;unity_editor=$UnityEditorPath;static_exit=$staticExit;dynamic_exit=$dynamicExit;fresh_exit=$freshExit;candidate_compile_failure=$candidateCompileFailure;valid_score=$scoreValid;source_unchanged=$sourceUnchanged;source_before=$sourceBefore;source_after=$sourceAfter;evaluator_package_source_unchanged=$evaluatorPackageSourceUnchanged;evaluator_package_before=$evaluatorPackageBefore;evaluator_package_after=$evaluatorPackageAfter;evaluator_contract_source_unchanged=$evaluatorContractUnchanged;evaluator_contract_before=$evaluatorContractBefore;evaluator_contract_after=$evaluatorContractAfter;prior_dynamic_process_id=if($null-ne$priorPid){$priorPid}else{0};prior_dynamic_session_id=if($null-ne$priorSession){$priorSession}else{''}}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputRoot 'run-summary.json') -Encoding utf8
  $exit=if($scoreExit-eq0-and$scoreValid-and$sourceUnchanged-and$evaluatorPackageSourceUnchanged-and$evaluatorContractUnchanged){0}else{3}
}
catch{[IO.File]::WriteAllText((Join-Path $OutputRoot 'evaluator-error.txt'),$_.Exception.ToString(),[Text.UTF8Encoding]::new($false));$exit=3}
finally{
  $env:TEMP=$oldTemp;$env:TMP=$oldTmp;Remove-Item Env:STORMBOUND_RUN_ID,Env:STORMBOUND_EVIDENCE_FILE,Env:STORMBOUND_SCREENSHOT_DIR,Env:STORMBOUND_PRIOR_PROCESS_ID,Env:STORMBOUND_PRIOR_SESSION_ID,Env:STORMBOUND_PRIOR_DIRTY_STATUS,Env:STORMBOUND_PRIOR_DIRTY_REASON -ErrorAction SilentlyContinue
  if($null-ne$identity){
    $ownedCompany=Assert-OwnedCompanyLeaf -Identity $identity
    $cleanup=[ordered]@{path=$ownedCompany;company=$identity.company;product=$identity.product;existed=[IO.Directory]::Exists($ownedCompany);removed=$false;scope='only exact run-owned company leaf'}
    if([IO.Directory]::Exists($ownedCompany)){if((Get-Item -LiteralPath $ownedCompany).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Refuse linked persistence leaf.'};Remove-Item -LiteralPath $ownedCompany -Recurse -Force;$cleanup.removed=-not[IO.Directory]::Exists($ownedCompany)}
    $cleanup|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputRoot 'unity-persistence-cleanup.json') -Encoding utf8
  }
  Remove-Item Env:STORMBOUND_HOST_COMPANY,Env:STORMBOUND_HOST_PRODUCT,Env:STORMBOUND_HOST_COMPANY_ROOT,Env:STORMBOUND_HOST_IDENTITY_RECEIPT -ErrorAction SilentlyContinue
  $ownedScratch=[IO.Path]::GetFullPath((Split-Path -Parent $scratch)).TrimEnd('\');$expectedScratch=[IO.Path]::GetFullPath((Join-Path $repoRoot ('tmp\'+$runId))).TrimEnd('\')
  if($ownedScratch-cne$expectedScratch-or-not$ownedScratch.StartsWith($tmpBoundary,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe scratch cleanup boundary.'}
  if([IO.Directory]::Exists($ownedScratch)){
    if($exit-eq0){try{Remove-Item -LiteralPath $ownedScratch -Recurse -Force}catch{Write-Warning "Valid evidence retained; temporary cleanup failed: $($_.Exception.Message)"}}
    else{Write-Warning "Preserving failed evaluator scratch: $ownedScratch"}
  }
}
exit $exit
