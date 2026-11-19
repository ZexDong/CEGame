[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [string]$UnityEditorPath=$env:UNITY_EDITOR,
  [string]$UnityCliPath=$env:UNITY_CLI
)
$ErrorActionPreference='Stop'
$evaluationRoot=(Resolve-Path -LiteralPath $PSScriptRoot).Path
$demoRoot=Split-Path -Parent $evaluationRoot
$repoRoot=Split-Path -Parent (Split-Path -Parent $demoRoot)
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

$runId='noir-roombreak-eval-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$scratch=Join-Path $repoRoot ('tmp\'+$runId+'\project')
$hostTemp=Join-Path $OutputRoot 'host-temp'
$skip=@('Library','Temp','Logs','UserSettings','obj','bin','.git','.vs')
$exit=3
$priorPid=0
$priorSession=''
$d6InputManifest=''
$visualCaptureValidation=''

function Quote([string]$value){'"'+($value-replace '"','\"')+'"'}
function Get-Sha([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-EvaluatorContractBinding{
  $paths=@((Join-Path $evaluationRoot 'rules.json'),(Join-Path $evaluationRoot 'requirement-coverage.json'),$PSCommandPath)+@(Get-ChildItem -LiteralPath (Join-Path $evaluationRoot 'scripts') -File|Sort-Object FullName|Select-Object -ExpandProperty FullName);$records=[Collections.Generic.List[string]]::new();$files=@();foreach($path in $paths){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing evaluator contract file: $path"};$relative=$path.Substring($evaluationRoot.Length+1).Replace('\','/');$hash=Get-Sha $path;$records.Add("$relative`t$hash");$files+=[ordered]@{path=$relative;bytes=[long](Get-Item -LiteralPath $path).Length;sha256=$hash}};$records.Sort([StringComparer]::Ordinal);$bytes=[Text.Encoding]::UTF8.GetBytes(($records-join"`n"));$sha=[Security.Cryptography.SHA256]::Create();try{$digest=([BitConverter]::ToString($sha.ComputeHash($bytes))-replace'-','').ToLowerInvariant()}finally{$sha.Dispose()};[ordered]@{file_count=$files.Count;sha256=$digest;algorithm='sha256(utf8(join(ordinal-sorted(relative-path + TAB + file-sha256), LF)))';files=$files}
}
function Get-PngSize([string]$path){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [ordered]@{valid=$false;width=0;height=0}}
  $bytes=[IO.File]::ReadAllBytes($path);if($bytes.Length-lt24-or$bytes[0]-ne0x89-or$bytes[1]-ne0x50-or$bytes[2]-ne0x4e-or$bytes[3]-ne0x47-or$bytes[4]-ne0x0d-or$bytes[5]-ne0x0a-or$bytes[6]-ne0x1a-or$bytes[7]-ne0x0a){return [ordered]@{valid=$false;width=0;height=0}}
  $width=([int]$bytes[16]-shl24)-bor([int]$bytes[17]-shl16)-bor([int]$bytes[18]-shl8)-bor[int]$bytes[19];$height=([int]$bytes[20]-shl24)-bor([int]$bytes[21]-shl16)-bor([int]$bytes[22]-shl8)-bor[int]$bytes[23]
  [ordered]@{valid=($width-gt0-and$height-gt0);width=$width;height=$height}
}
function Write-D6Artifacts([string]$evidencePath){
  $visualRoot=Join-Path $OutputRoot 'visual';[IO.Directory]::CreateDirectory($visualRoot)|Out-Null;$candidateRoot=Join-Path $OutputRoot 'visual-candidates';$referenceRoot=Join-Path $evaluationRoot 'reference\visual\reference'
  $specs=@([ordered]@{id='initial_gameplay';label='initial gameplay';file='01_initial_gameplay.png'})
  $diagnosticSpecs=@([ordered]@{id='room_transition';label='mid-game room transition';file='02_room_transition.png'},[ordered]@{id='dash_action';label='active dash action';file='03_dash_action.png'})
  $document=if(Test-Path -LiteralPath $evidencePath -PathType Leaf){try{Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json}catch{$null}}else{$null};$receipts=if($null-ne$document){@($document.screenshot_receipts)}else{@()};$states=@();$validationStates=@()
  foreach($spec in $specs){
    $reference=(Resolve-Path -LiteralPath (Join-Path $referenceRoot $spec.file)).Path;$candidate=Join-Path $candidateRoot $spec.file;$receipt=@($receipts|Where-Object{[string]$_.name-ceq[string]$spec.file}|Select-Object -First 1);$png=Get-PngSize $candidate;$exists=Test-Path -LiteralPath $candidate -PathType Leaf;$actualBytes=if($exists){[long](Get-Item -LiteralPath $candidate).Length}else{0};$actualSha=if($exists){Get-Sha $candidate}else{''};$receiptValid=$receipt.Count-eq1-and[string]$receipt[0].status-ceq'captured'-and[int]$receipt[0].width-eq1280-and[int]$receipt[0].height-eq720-and[long]$receipt[0].bytes-eq$actualBytes;$valid=$exists-and[bool]$png.valid-and[int]$png.width-eq1280-and[int]$png.height-eq720-and$receiptValid
    $states+=[ordered]@{id=$spec.id;label=$spec.label;reference=$reference;candidate=$candidate}
    $validationStates+=[ordered]@{id=$spec.id;file=$spec.file;valid=$valid;status=if($valid){'captured'}elseif(-not$exists){'missing'}else{'invalid'};width=[int]$png.width;height=[int]$png.height;bytes=$actualBytes;sha256=$actualSha;receipt_present=$receipt.Count-eq1;receipt_matches_file=$receiptValid}
  }
  $validationPath=Join-Path $visualRoot 'capture-validation.json';$validation=[ordered]@{schema_version=1;valid=@($validationStates|Where-Object{-not$_.valid}).Count-eq0;required_resolution=@(1280,720);states=$validationStates};[IO.File]::WriteAllText($validationPath,($validation|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  $diagnosticInventory=@($diagnosticSpecs|ForEach-Object{$candidate=Join-Path $candidateRoot $_.file;[ordered]@{id=$_.id;label=$_.label;candidate=$candidate;exists=(Test-Path -LiteralPath $candidate -PathType Leaf);role='diagnostic_inventory_only'}})
  $manifestPath=Join-Path $visualRoot 'd6-input.json';$manifest=[ordered]@{schema_version=2;benchmark_id='unity.noir_roombreak_challenge.v1';protocol='user-simplified-single-state-single-round-20260824';formal_reference_ready=$true;primary_state_id='initial_gameplay';required_rounds=1;manifest_role='native formal single-state D6 input';visual_evaluator=[ordered]@{model='gpt-5.6-sol';rounds=1;prompt_sha256='558b4ccffad7d13d3ae3e5c6fc5a9b36a7bba37d9be47da895c2e50bc9c5a6ee'};capture_validation=$validationPath;states=$states;diagnostic_inventory=$diagnosticInventory};[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  [ordered]@{manifest=$manifestPath;validation=$validationPath}
}
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
function Set-Identity([string]$project){$path=Join-Path $project 'ProjectSettings\ProjectSettings.asset';$text=[IO.File]::ReadAllText($path);$text=[regex]::Replace($text,'(?m)^  companyName:.*$','  companyName: GameCreateBenchmarkTemp');$text=[regex]::Replace($text,'(?m)^  productName:.*$','  productName: '+$runId);[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))}
function Inject-Evaluator([string]$project){
  $packageName='com.gamecreate.benchmark.noir-roombreak.evaluator'
  $packageSource=Join-Path $evaluationRoot 'package'
  $packageTarget=Join-Path $project ('Packages\'+$packageName)
  if(Test-Path -LiteralPath $packageTarget){throw "Scratch evaluator package already exists: $packageTarget"}
  Copy-Tree $packageSource $packageTarget
  $path=Join-Path $project 'Packages\manifest.json';$manifest=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;$dependencies=[ordered]@{};$manifest.dependencies.psobject.Properties|ForEach-Object{$dependencies[$_.Name]=$_.Value};$dependencies[$packageName]='file:'+$packageName;$testables=@($manifest.testables|Where-Object{$_});if($testables-notcontains$packageName){$testables+=$packageName};$output=[ordered]@{dependencies=$dependencies;testables=$testables};[IO.File]::WriteAllText($path,($output|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}
function Invoke-Cli([string]$name,[string[]]$arguments,[int]$hostTimeout){
  if(Test-Path -LiteralPath (Join-Path $scratch 'Temp\UnityLockfile')){throw "Scratch project is still owned before $name."}
  $stdout=Join-Path $OutputRoot ($name+'-cli.stdout.log');$stderr=Join-Path $OutputRoot ($name+'-cli.stderr.log')
  $process=Start-Process -FilePath $UnityCliPath -ArgumentList $arguments -WorkingDirectory $scratch -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $timedOut=-not$process.WaitForExit($hostTimeout*1000);if($timedOut){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;$process.WaitForExit(10000)|Out-Null;$code=124}else{$process.WaitForExit();$code=[int]$process.ExitCode}
  [ordered]@{name=$name;executor='unity-cli';cli_process_id=[int]$process.Id;exit_code=$code;timed_out=$timedOut;stdout=$stdout;stderr=$stderr}
}
function Run-Compile([string]$name,[int]$timeout){
  $log=Join-Path $OutputRoot ($name+'.log');$args=@('--json','--non-interactive','--proxy-disable','run',(Quote $scratch),'--editor-path',(Quote $UnityEditorPath),'--timeout',$timeout.ToString(),'--','-logFile',(Quote $log));$result=Invoke-Cli $name $args ($timeout+60);$result.log=$log;return $result
}
function Run-Test([string]$name,[string]$assembly,[int]$timeout){
  $xml=Join-Path $OutputRoot ($name+'.xml');$log=Join-Path $OutputRoot ($name+'.log');$evidence=Join-Path $OutputRoot ($name+'-evidence.json');$env:NOIR_ROOMBREAK_EVIDENCE_FILE=$evidence
  if($name-eq'dynamic'){$env:NOIR_ROOMBREAK_SCREENSHOT_DIR=Join-Path $OutputRoot 'visual-candidates'}else{Remove-Item Env:NOIR_ROOMBREAK_SCREENSHOT_DIR -ErrorAction SilentlyContinue}
  $args=@('--json','--non-interactive','--proxy-disable','test',(Quote $scratch),'--mode','PlayMode','--filter',(Quote $assembly),'--output',(Quote $xml),'--editor-path',(Quote $UnityEditorPath),'--timeout',$timeout.ToString(),'--','-logFile',(Quote $log));$result=Invoke-Cli $name $args ($timeout+60);$result.xml=$xml;$result.log=$log;$result.evidence=$evidence;return $result
}
function Candidate-CompilerErrors([string]$log){if(-not(Test-Path -LiteralPath $log)){return @()};@(Select-String -LiteralPath $log -Pattern '(?i)(?:^|[\\/])Assets[\\/].*error CS\d+'|ForEach-Object{$_.Line.Trim()}|Sort-Object -Unique)}
function Evaluator-CompilerErrors([string]$log){if(-not(Test-Path -LiteralPath $log)){return @()};@(Select-String -LiteralPath $log -Pattern '(?i)evaluation[\\/]package.*error CS\d+|com\.gamecreate\.benchmark\.noir-roombreak\.evaluator.*error CS\d+'|ForEach-Object{$_.Line.Trim()}|Sort-Object -Unique)}

[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null;[IO.Directory]::CreateDirectory($hostTemp)|Out-Null
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
try{
  $sourceBefore=Get-TreeBinding $ProjectPath;$evaluatorPackageSource=Join-Path $evaluationRoot 'package';$evaluatorPackageBefore=Get-TreeBinding $evaluatorPackageSource;$evaluatorContractBefore=Get-EvaluatorContractBinding;Copy-Tree $ProjectPath $scratch;Set-Identity $scratch;$env:TEMP=$hostTemp;$env:TMP=$hostTemp;$env:UseSharedCompilation='false'
  $baseline=Run-Compile 'candidate-compile' 600;$candidateErrors=Candidate-CompilerErrors $baseline.log
  if($baseline.exit_code-ne0-and$candidateErrors.Count-gt0){[ordered]@{schema_version=1;classification='candidate_compile_failure';diagnostics=$candidateErrors;baseline=$baseline}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputRoot 'candidate-compile-failure.json') -Encoding utf8;& (Join-Path $evaluationRoot 'scripts\score.ps1') -OutputRoot $OutputRoot -ProjectPath $ProjectPath -StaticExit $baseline.exit_code -DynamicExit -10 -FreshExit -10 -StaticTimedOut:$false -DynamicTimedOut:$false -FreshTimedOut:$false -CandidateCompileFailure;$scoreExit=$LASTEXITCODE;$staticExit=$baseline.exit_code;$dynamicExit=-10;$freshExit=-10;$candidateCompileFailure=$true}
  elseif($baseline.exit_code-ne0){throw "Unity CLI candidate compile/import failed without a candidate-owned C# diagnostic. Exit=$($baseline.exit_code)."}
  else{
    $candidateCompileFailure=$false;Inject-Evaluator $scratch;$evaluatorCompile=Run-Compile 'evaluator-compile' 600;$evaluatorErrors=Evaluator-CompilerErrors $evaluatorCompile.log;if($evaluatorCompile.exit_code-ne0-or$evaluatorErrors.Count){throw "Private evaluator failed to compile. Exit=$($evaluatorCompile.exit_code); errors=$($evaluatorErrors -join ' | ')"}
    $static=Run-Test 'static' 'GameCreate.NoirRoombreak.Evaluator.Static' 300;$staticExit=$static.exit_code
    $dynamic=Run-Test 'dynamic' 'GameCreate.NoirRoombreak.Evaluator.Dynamic' 1200;$dynamicExit=$dynamic.exit_code;$visualArtifacts=Write-D6Artifacts $dynamic.evidence;$d6InputManifest=$visualArtifacts.manifest;$visualCaptureValidation=$visualArtifacts.validation
    if(Test-Path -LiteralPath $dynamic.evidence){$dynamicEvidence=Get-Content -LiteralPath $dynamic.evidence -Raw|ConvertFrom-Json;$priorPid=[int]$dynamicEvidence.process_id;$dirty=@($dynamicEvidence.trajectories|Where-Object { [string]$_.id -eq 'TRAJ06_CompleteJourneyResultRestartAndDirtyClose' }|Select-Object -First 1);if($dirty.Count){$priorSession=[string]$dirty[0].session_id}}
    $env:NOIR_ROOMBREAK_PRIOR_PROCESS_ID=$priorPid.ToString();$env:NOIR_ROOMBREAK_PRIOR_SESSION_ID=$priorSession
    $fresh=Run-Test 'fresh' 'GameCreate.NoirRoombreak.Evaluator.Fresh' 360;$freshExit=$fresh.exit_code
    & (Join-Path $evaluationRoot 'scripts\score.ps1') -OutputRoot $OutputRoot -ProjectPath $ProjectPath -StaticExit $staticExit -DynamicExit $dynamicExit -FreshExit $freshExit -StaticTimedOut:([bool]$static.timed_out) -DynamicTimedOut:([bool]$dynamic.timed_out) -FreshTimedOut:([bool]$fresh.timed_out);$scoreExit=$LASTEXITCODE
  }
  $scorePath=Join-Path $OutputRoot 'score.json';$scoreValid=$false;if(Test-Path -LiteralPath $scorePath){$scoreValid=[bool](Get-Content -LiteralPath $scorePath -Raw|ConvertFrom-Json).valid_score}
  $sourceAfter=Get-TreeBinding $ProjectPath;$sourceUnchanged=$sourceBefore.sha256-eq$sourceAfter.sha256-and$sourceBefore.file_count-eq$sourceAfter.file_count;if(-not$sourceUnchanged){throw 'Evaluator modified the source candidate project.'}
  $evaluatorPackageAfter=Get-TreeBinding $evaluatorPackageSource;$evaluatorPackageSourceUnchanged=$evaluatorPackageBefore.sha256-eq$evaluatorPackageAfter.sha256-and$evaluatorPackageBefore.file_count-eq$evaluatorPackageAfter.file_count;if(-not$evaluatorPackageSourceUnchanged){throw 'Unity or the evaluator modified the canonical private evaluator package.'};$evaluatorContractAfter=Get-EvaluatorContractBinding;$evaluatorContractUnchanged=$evaluatorContractBefore.sha256-eq$evaluatorContractAfter.sha256-and$evaluatorContractBefore.file_count-eq$evaluatorContractAfter.file_count;if(-not$evaluatorContractUnchanged){throw 'Evaluator rules, coverage, runner, or scoring scripts changed during evaluation.'}
  [ordered]@{schema_version=4;run_id=$runId;executor='unity-cli-1.0.0-beta.3';unity_cli=$UnityCliPath;unity_editor=$UnityEditorPath;static_exit=$staticExit;dynamic_exit=$dynamicExit;fresh_exit=$freshExit;candidate_compile_failure=$candidateCompileFailure;valid_score=$scoreValid;source_unchanged=$sourceUnchanged;source_before=$sourceBefore;source_after=$sourceAfter;evaluator_package_source_unchanged=$evaluatorPackageSourceUnchanged;evaluator_package_before=$evaluatorPackageBefore;evaluator_package_after=$evaluatorPackageAfter;evaluator_contract_source_unchanged=$evaluatorContractUnchanged;evaluator_contract_before=$evaluatorContractBefore;evaluator_contract_after=$evaluatorContractAfter;prior_dynamic_process_id=if($null-ne$priorPid){$priorPid}else{0};prior_dynamic_session_id=if($null-ne$priorSession){$priorSession}else{''};d6_input_manifest=$d6InputManifest;visual_capture_validation=$visualCaptureValidation}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $OutputRoot 'run-summary.json') -Encoding utf8
  $exit=if($scoreExit-eq0-and$scoreValid-and$sourceUnchanged-and$evaluatorPackageSourceUnchanged){0}else{3}
}
catch{
  $message=$_.Exception.ToString();[IO.File]::WriteAllText((Join-Path $OutputRoot 'evaluator-error.txt'),$message,[Text.UTF8Encoding]::new($false))
  [ordered]@{schema_version=3;evaluator_protocol='game-independent-d1-d6-v2';generated_utc=[DateTime]::UtcNow.ToString('o');project_path=$ProjectPath;valid_score=$false;candidate_status='evaluator_invalid';validation_reasons=@($message);score=$null;score_status='evaluator_invalid';automated_score=$null;automated_maximum_score=90.0;maximum_score=100.0;overall=[ordered]@{score=$null;maximum_score=100.0;status='evaluator_invalid'};executable=$null;solved=$null;checks=@()}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutputRoot 'score.json') -Encoding utf8
  $exit=3
}
finally{
  $env:TEMP=$oldTemp;$env:TMP=$oldTmp;Remove-Item Env:NOIR_ROOMBREAK_EVIDENCE_FILE,Env:NOIR_ROOMBREAK_SCREENSHOT_DIR,Env:NOIR_ROOMBREAK_PRIOR_PROCESS_ID,Env:NOIR_ROOMBREAK_PRIOR_SESSION_ID -ErrorAction SilentlyContinue
  $localLowCompany=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) '..\LocalLow\GameCreateBenchmarkTemp'));$localLow=Join-Path $localLowCompany $runId
  $cleanup=[ordered]@{path=$localLow;existed=[IO.Directory]::Exists($localLow);removed=$false};if([IO.Directory]::Exists($localLow)){[IO.Directory]::Delete($localLow,$true);$cleanup.removed=-not[IO.Directory]::Exists($localLow)};$cleanup|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputRoot 'unity-persistence-cleanup.json') -Encoding utf8
  if([IO.Directory]::Exists((Split-Path -Parent $scratch))){Get-ChildItem (Split-Path -Parent $scratch) -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};[IO.Directory]::Delete((Split-Path -Parent $scratch),$true)}
}
exit $exit


