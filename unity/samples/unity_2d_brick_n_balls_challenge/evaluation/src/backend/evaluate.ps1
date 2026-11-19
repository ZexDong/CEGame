[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateProject,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$evaluationStartedUtc=[DateTime]::UtcNow
$evaluationRoot=(Resolve-Path -LiteralPath $PSScriptRoot).Path.TrimEnd('\')
$demoRoot=Split-Path -Parent $evaluationRoot
$repositoryRoot=(Split-Path -Parent (Split-Path -Parent $demoRoot)).TrimEnd('\')
$candidate=(Resolve-Path -LiteralPath $CandidateProject).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$cli=(Resolve-Path -LiteralPath $env:UNITY_CLI).Path
$editor=(Resolve-Path -LiteralPath $env:UNITY_EDITOR).Path

function Test-PathInside([string]$path,[string]$root,[bool]$allowRoot=$true){
  $full=[IO.Path]::GetFullPath($path).TrimEnd('\')
  $boundary=[IO.Path]::GetFullPath($root).TrimEnd('\')
  if($full.Equals($boundary,[StringComparison]::OrdinalIgnoreCase)){return $allowRoot}
  return ($full+'\').StartsWith($boundary+'\',[StringComparison]::OrdinalIgnoreCase)
}

if(-not (Test-PathInside $evaluationRoot $repositoryRoot)){throw "Evaluator must remain inside repository: $evaluationRoot"}
if(-not (Test-PathInside $candidate $repositoryRoot)){throw "CandidateProject must remain inside repository: $candidate"}
$allowedRoots=@((Join-Path $repositoryRoot 'tmp'),(Join-Path $repositoryRoot 'runs'))
if(-not ($allowedRoots|Where-Object{Test-PathInside $output $_ $false})){throw 'OutputRoot must be a new directory below repository tmp/ or runs/.'}
if(Test-PathInside $output $candidate){throw 'OutputRoot must not be inside CandidateProject.'}
if(Test-Path -LiteralPath $output){throw "OutputRoot already exists: $output"}
if(-not(Test-Path -LiteralPath (Join-Path $candidate 'Packages\manifest.json') -PathType Leaf)){throw 'CandidateProject is not a Unity project.'}
if(-not(Test-Path -LiteralPath (Join-Path $candidate 'ProjectSettings\ProjectSettings.asset') -PathType Leaf)){throw 'CandidateProject has no ProjectSettings.asset.'}
if(Test-Path -LiteralPath (Join-Path $candidate 'Temp\UnityLockfile')){throw 'CandidateProject is open; close its exact Unity process before evaluation.'}

$sessionId='brick-eval-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$temporaryCompany='GameCreateBenchmarkTemp'
$temporaryProduct=$sessionId
$workspaceRoot=Join-Path $output 'workspace'
$workspace=Join-Path $workspaceRoot 'project'
$hostTemp=Join-Path $output 'host-temp'
$screenshotDir=Join-Path $output 'candidate-screenshots'
$bindingDir=Join-Path $output 'tree-bindings'
$dirtyReceipt=Join-Path $output 'reopen-dirty.json'
$editXml=Join-Path $output 'editmode.xml'
$playXml=Join-Path $output 'playmode.xml'
$reopenXml=Join-Path $output 'reopen.xml'
$candidateCompileLog=Join-Path $output 'candidate-compile.log'
$evaluatorCompileLog=Join-Path $output 'evaluator-compile.log'
$editLog=Join-Path $output 'editmode.log'
$playLog=Join-Path $output 'playmode.log'
$reopenLog=Join-Path $output 'reopen.log'
$cliExitsPath=Join-Path $output 'cli-exits.json'
$bindingsPath=Join-Path $output 'tree-bindings.json'
$localAppData=[Environment]::GetFolderPath('LocalApplicationData')
if([string]::IsNullOrWhiteSpace($localAppData)){throw 'LocalApplicationData could not be resolved.'}
$localLowRoot=[IO.Path]::GetFullPath((Join-Path $localAppData '..\LocalLow')).TrimEnd('\')
$localLowCompany=Join-Path $localLowRoot $temporaryCompany
$localLowLeaf=Join-Path $localLowCompany $temporaryProduct
$externalTestResults=Join-Path $localLowLeaf 'TestResults.xml'
$oldTemp=$env:TEMP;$oldTmp=$env:TMP;$oldShared=$env:UseSharedCompilation
$oldSession=$env:BRICK_EVALUATION_SESSION_ID;$oldReceipt=$env:BRICK_REOPEN_RECEIPT_PATH;$oldScreens=$env:BRICK_CANDIDATE_SCREENSHOT_DIR
$candidateBefore=$null;$evaluatorBefore=$null;$bindings=$null
$excludedCandidateDirectories=@('Library','Temp','Logs','UserSettings','obj','bin','.git','.vs')

function Write-JsonNoBom([string]$path,[object]$value,[int]$depth=12){
  [IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth $depth),[Text.UTF8Encoding]::new($false))
}

function Remove-EvaluationScratch([string]$path){
  if(!(Test-Path -LiteralPath $path)){return}
  $full=[IO.Path]::GetFullPath($path)
  if(-not (Test-PathInside $full $output)){throw "Refusing cleanup outside OutputRoot: $full"}
  for($attempt=0;$attempt -lt 12;$attempt++){
    try{Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop;return}catch{Start-Sleep -Milliseconds 500}
  }
  Write-JsonNoBom (Join-Path $output 'cleanup-warning.json') ([ordered]@{path=$full;error='Scratch cleanup remained locked after retries.'}) 4
}

function Copy-Tree([string]$source,[string]$destination,[string[]]$excludedDirectories=@()){
  $sourceItem=Get-Item -LiteralPath $source -Force
  if(($sourceItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Source tree root is a reparse point: $source"}
  [IO.Directory]::CreateDirectory($destination)|Out-Null
  foreach($filePath in [IO.Directory]::EnumerateFiles($source)){
    $item=Get-Item -LiteralPath $filePath -Force
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Source tree contains a reparse-point file: $filePath"}
    [IO.File]::Copy($filePath,(Join-Path $destination ([IO.Path]::GetFileName($filePath))),$true)
  }
  foreach($directory in [IO.Directory]::EnumerateDirectories($source)){
    $name=[IO.Path]::GetFileName($directory)
    if($excludedDirectories-contains$name){continue}
    $item=Get-Item -LiteralPath $directory -Force
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Source tree contains a reparse-point directory: $directory"}
    Copy-Tree $directory (Join-Path $destination $name) $excludedDirectories
  }
}

function Set-TemporaryUnityIdentity([string]$project){
  $path=Join-Path $project 'ProjectSettings\ProjectSettings.asset'
  $text=[IO.File]::ReadAllText($path)
  $companyPattern='(?m)^  companyName:.*$'
  $productPattern='(?m)^  productName:.*$'
  if(([regex]::Matches($text,$companyPattern)).Count-ne1-or([regex]::Matches($text,$productPattern)).Count-ne1){throw 'ProjectSettings.asset must contain exactly one companyName and one productName.'}
  $text=[regex]::Replace($text,$companyPattern,'  companyName: '+$temporaryCompany)
  $text=[regex]::Replace($text,$productPattern,'  productName: '+$temporaryProduct)
  [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
}

function Write-TreeBinding([string]$root,[string]$name,[scriptblock]$include){
  $resolved=(Resolve-Path -LiteralPath $root).Path.TrimEnd('\')
  if(-not (Test-PathInside $resolved $repositoryRoot)){throw "Binding source escaped repository: $resolved"}
  $lines=@()
  foreach($file in Get-ChildItem -LiteralPath $resolved -Recurse -Force -File|Sort-Object FullName){
    $relative=$file.FullName.Substring($resolved.Length+1).Replace('\','/')
    if(& $include $relative){
      if(($file.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Binding source contains a reparse-point file: $($file.FullName)"}
      $lines += ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()+'  '+$relative)
    }
  }
  $manifest=Join-Path $bindingDir ($name+'-tree.sha256')
  [IO.File]::WriteAllLines($manifest,$lines,[Text.UTF8Encoding]::new($false))
  $digest=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLower()
  [ordered]@{name=$name;root=$resolved;file_count=$lines.Count;manifest=(Split-Path -Leaf $manifest);manifest_sha256=$digest}
}

function Save-Bindings([object]$value){Write-JsonNoBom $bindingsPath $value 10}

function Complete-ImmutableBindings{
  if($null-eq$candidateBefore-or$null-eq$evaluatorBefore-or$null-eq$bindings){return $null}
  $candidateAfter=Write-TreeBinding $candidate 'candidate-after' {param($r) $r-notmatch'^(Library|Temp|Logs|UserSettings|obj|bin|\.git|\.vs)/'}
  $evaluatorAfter=Write-TreeBinding $evaluationRoot 'evaluator-definition-after' {param($r) $r-notmatch'^reference/calibration/'-and$r-notmatch'^reference/candidate-screenshots/'}
  $candidateUnchanged=($candidateBefore.file_count-eq$candidateAfter.file_count-and$candidateBefore.manifest_sha256-eq$candidateAfter.manifest_sha256)
  $evaluatorUnchanged=($evaluatorBefore.file_count-eq$evaluatorAfter.file_count-and$evaluatorBefore.manifest_sha256-eq$evaluatorAfter.manifest_sha256)
  $bindings['candidate_after']=$candidateAfter
  $bindings['candidate_unchanged']=$candidateUnchanged
  $bindings['evaluator_definition_after']=$evaluatorAfter
  $bindings['evaluator_definition_unchanged']=$evaluatorUnchanged
  Save-Bindings $bindings
  [ordered]@{candidate_unchanged=$candidateUnchanged;evaluator_definition_unchanged=$evaluatorUnchanged}
}

function Remove-ExactPersistentDataLeaf{
  $rootBoundary=$localLowRoot+'\'
  $companyFull=[IO.Path]::GetFullPath($localLowCompany).TrimEnd('\')
  $leafFull=[IO.Path]::GetFullPath($localLowLeaf).TrimEnd('\')
  if(-not(($companyFull+'\').StartsWith($rootBoundary,[StringComparison]::OrdinalIgnoreCase))-or
     -not(($leafFull+'\').StartsWith($companyFull+'\',[StringComparison]::OrdinalIgnoreCase))-or
     [IO.Path]::GetFileName($leafFull)-ne$temporaryProduct-or
     [IO.Path]::GetFileName($companyFull)-ne$temporaryCompany){throw "Refusing unsafe persistent-data cleanup: $leafFull"}
  $existed=Test-Path -LiteralPath $leafFull
  $testResultsDetected=Test-Path -LiteralPath $externalTestResults -PathType Leaf
  $archived=$null;$testResultsSha=$null
  if($testResultsDetected){
    $archived=Join-Path $output 'unity-persistent-data-TestResults.xml'
    Copy-Item -LiteralPath $externalTestResults -Destination $archived -Force
    $testResultsSha=(Get-FileHash -LiteralPath $archived -Algorithm SHA256).Hash.ToLower()
  }
  if($existed){
    $leafItem=Get-Item -LiteralPath $leafFull -Force
    if(-not$leafItem.PSIsContainer-or($leafItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Persistent-data leaf is not a safe ordinary directory: $leafFull"}
    Get-ChildItem -LiteralPath $leafFull -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}}
    [IO.Directory]::Delete($leafFull,$true)
  }
  $removed=-not(Test-Path -LiteralPath $leafFull)
  [ordered]@{
    schema_version=1;company_name=$temporaryCompany;product_name=$temporaryProduct
    application_persistent_data_path=$leafFull;cleanup_scope='exact_unique_company_product_leaf_only'
    existed=$existed;external_test_results_detected=$testResultsDetected
    external_test_results_archive=$archived;external_test_results_sha256=$testResultsSha
    removed=$removed
  }
}

if(Test-Path -LiteralPath $localLowLeaf){throw "Unique persistent-data leaf unexpectedly existed before run: $localLowLeaf"}
New-Item -ItemType Directory -Force -Path $output,$workspace,$hostTemp,$screenshotDir,$bindingDir|Out-Null
try{
  $candidateBefore=Write-TreeBinding $candidate 'candidate' {param($r) $r-notmatch'^(Library|Temp|Logs|UserSettings|obj|bin|\.git|\.vs)/'}
  $inputBinding=Write-TreeBinding (Join-Path $demoRoot 'input') 'input' {param($r) $true}
  # Candidate scoring consumes the frozen input and evaluator, not private Gold.
  # The former Gold tree hash was author bookkeeping, never a gameplay oracle.
  $goldBinding=$null
  $evaluatorBefore=Write-TreeBinding $evaluationRoot 'evaluator-definition' {param($r) $r-notmatch'^reference/calibration/'-and$r-notmatch'^reference/candidate-screenshots/'}
  $bindings=[ordered]@{
    schema_version=2;algorithm='SHA256 of UTF-8 no-BOM sorted per-file manifest'
    candidate=$candidateBefore;input=$inputBinding;gold=$goldBinding;evaluator_definition=$evaluatorBefore
    gold_binding_scope='not_distributed_or_consumed_for_candidate_measurement'
    candidate_after=$null;candidate_unchanged=$null;evaluator_definition_after=$null;evaluator_definition_unchanged=$null
  }
  Save-Bindings $bindings

  Copy-Tree $candidate $workspace $excludedCandidateDirectories
  Set-TemporaryUnityIdentity $workspace

  $env:TEMP=$hostTemp;$env:TMP=$hostTemp;$env:UseSharedCompilation='false'
  $env:BRICK_EVALUATION_SESSION_ID=$sessionId
  $env:BRICK_REOPEN_RECEIPT_PATH=$dirtyReceipt
  $env:BRICK_CANDIDATE_SCREENSHOT_DIR=$screenshotDir
  Write-JsonNoBom (Join-Path $output 'evaluation-session.json') ([ordered]@{
    schema_version=2;session_id=$sessionId;started_utc=$evaluationStartedUtc.ToString('o');candidate_source=$candidate
    scratch_project=$workspace;temporary_company_name=$temporaryCompany;temporary_product_name=$temporaryProduct
    application_persistent_data_path=$localLowLeaf;entry_scene='Assets/Scenes/BrickChallenge.unity';input_route='NewInputSystemVirtualMouseKeyboard'
    timeout_budgets_seconds=[ordered]@{candidate_compile=600;evaluator_compile=600;editmode=600;playmode=1200;reopen=600}
    expected_phases=@('candidate_compile','evaluator_compile','editmode','playmode_dirty','process_exit','distinct_pid_reopen')
    repository_local_outputs=[ordered]@{candidate_compile_log=$candidateCompileLog;evaluator_compile_log=$evaluatorCompileLog;editmode_xml=$editXml;editmode_log=$editLog;playmode_xml=$playXml;playmode_log=$playLog;reopen_xml=$reopenXml;reopen_log=$reopenLog}
  }) 10

  & $cli --json --non-interactive --proxy-disable run $workspace --editor-path $editor --timeout 600 -- -logFile $candidateCompileLog 2>&1|Set-Content -LiteralPath (Join-Path $output 'candidate-compile-cli.txt') -Encoding utf8
  $candidateCompileExit=$LASTEXITCODE
  $candidateCompileDiagnostic=$false
  if(Test-Path -LiteralPath $candidateCompileLog){
    $compileText=Get-Content -LiteralPath $candidateCompileLog -Raw
    $candidateCompileDiagnostic=($compileText-match'(?im)(Assets[/\\].*\berror\s+CS\d+|error\s+CS\d+.*Assets[/\\])')
  }

  $evaluatorCompileExit=$null;$editExit=$null;$playExit=$null;$reopenExit=$null
  if($candidateCompileExit-eq0){
    $packageTarget=Join-Path $workspace 'Packages/com.omnigame.benchmark.brick-challenge.evaluator'
    if(Test-Path -LiteralPath $packageTarget){throw "Scratch evaluator package already exists: $packageTarget"}
    Copy-Tree (Join-Path $evaluationRoot 'package') $packageTarget
    $manifestPath=Join-Path $workspace 'Packages/manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    $manifest.dependencies|Add-Member -NotePropertyName 'com.omnigame.benchmark.brick-challenge.evaluator' -NotePropertyValue 'file:com.omnigame.benchmark.brick-challenge.evaluator' -Force
    Write-JsonNoBom $manifestPath $manifest 12

    & $cli --json --non-interactive --proxy-disable run $workspace --editor-path $editor --timeout 600 -- -logFile $evaluatorCompileLog 2>&1|Set-Content -LiteralPath (Join-Path $output 'evaluator-compile-cli.txt') -Encoding utf8
    $evaluatorCompileExit=$LASTEXITCODE
    if($evaluatorCompileExit-eq0){
      & $cli --json --non-interactive --proxy-disable test $workspace --mode EditMode --filter 'OmniGame.Benchmark.BrickChallenge.Evaluator.EditMode' --output $editXml --editor-path $editor --timeout 600 -- -logFile $editLog 2>&1|Set-Content -LiteralPath (Join-Path $output 'editmode-cli.txt') -Encoding utf8
      $editExit=$LASTEXITCODE
      & $cli --json --non-interactive --proxy-disable test $workspace --mode PlayMode --filter 'OmniGame.Benchmark.BrickChallenge.Evaluator.PlayMode' --output $playXml --editor-path $editor --timeout 1200 -- -logFile $playLog 2>&1|Set-Content -LiteralPath (Join-Path $output 'playmode-cli.txt') -Encoding utf8
      $playExit=$LASTEXITCODE
      & $cli --json --non-interactive --proxy-disable test $workspace --mode PlayMode --filter 'OmniGame.Benchmark.BrickChallenge.Evaluator.Reopen' --output $reopenXml --editor-path $editor --timeout 600 -- -logFile $reopenLog 2>&1|Set-Content -LiteralPath (Join-Path $output 'reopen-cli.txt') -Encoding utf8
      $reopenExit=$LASTEXITCODE
    }
  }

  Write-JsonNoBom $cliExitsPath ([ordered]@{candidate_compile=$candidateCompileExit;candidate_compile_diagnostic=$candidateCompileDiagnostic;evaluator_compile=$evaluatorCompileExit;editmode=$editExit;playmode=$playExit;reopen=$reopenExit}) 5
  $immutability=Complete-ImmutableBindings
  if($null-eq$immutability-or-not$immutability.candidate_unchanged-or-not$immutability.evaluator_definition_unchanged){throw 'Candidate source or canonical evaluator changed during the isolated Unity phases.'}

  & (Join-Path $evaluationRoot 'scripts/score-results.ps1') `
    -EditXml $editXml -PlayXml $playXml -ReopenXml $reopenXml -RulesPath (Join-Path $evaluationRoot 'rules.json') `
    -OutputPath (Join-Path $output 'score.json') -CliExitsPath $cliExitsPath -EvaluationStartedUtc $evaluationStartedUtc.ToString('o') `
    -SessionId $sessionId -DirtyReceiptPath $dirtyReceipt -BindingsPath $bindingsPath |
    Set-Content -LiteralPath (Join-Path $output 'score.stdout.json') -Encoding utf8

  $finalImmutability=Complete-ImmutableBindings
  Write-JsonNoBom (Join-Path $output 'source-integrity.json') ([ordered]@{schema_version=1;candidate_unchanged=$finalImmutability.candidate_unchanged;evaluator_definition_unchanged=$finalImmutability.evaluator_definition_unchanged;checked_utc=[DateTime]::UtcNow.ToString('o')}) 5
  if(-not$finalImmutability.candidate_unchanged-or-not$finalImmutability.evaluator_definition_unchanged){throw 'Candidate source or canonical evaluator changed during scoring.'}
  Get-Content -LiteralPath (Join-Path $output 'score.json')
}catch{
  try{if($null-ne$bindings){Complete-ImmutableBindings|Out-Null}}catch{}
  Write-JsonNoBom (Join-Path $output 'evaluator-error.json') ([ordered]@{schema_version=1;valid_score=$false;classification='evaluator_wrapper_error';message=$_.Exception.Message;generated_utc=[DateTime]::UtcNow.ToString('o')}) 5
  throw
}finally{
  $env:TEMP=$oldTemp;$env:TMP=$oldTmp;$env:UseSharedCompilation=$oldShared
  $env:BRICK_EVALUATION_SESSION_ID=$oldSession;$env:BRICK_REOPEN_RECEIPT_PATH=$oldReceipt;$env:BRICK_CANDIDATE_SCREENSHOT_DIR=$oldScreens
  $persistenceCleanupError=$null
  try{
    $cleanup=Remove-ExactPersistentDataLeaf
    Write-JsonNoBom (Join-Path $output 'unity-persistence-cleanup.json') $cleanup 6
    if(-not$cleanup.removed){throw "Unique persistent-data leaf remained: $localLowLeaf"}
  }catch{
    $persistenceCleanupError=$_.Exception
    Write-JsonNoBom (Join-Path $output 'unity-persistence-cleanup.json') ([ordered]@{schema_version=1;company_name=$temporaryCompany;product_name=$temporaryProduct;application_persistent_data_path=$localLowLeaf;cleanup_scope='exact_unique_company_product_leaf_only';removed=$false;error=$_.Exception.Message}) 6
  }
  Remove-EvaluationScratch $workspaceRoot
  Remove-EvaluationScratch $hostTemp
  if($null-ne$persistenceCleanupError){
    Write-JsonNoBom (Join-Path $output 'evaluator-error.json') ([ordered]@{schema_version=1;valid_score=$false;classification='evaluator_wrapper_error';message=('Persistent-data cleanup failed: '+$persistenceCleanupError.Message);generated_utc=[DateTime]::UtcNow.ToString('o')}) 5
    throw $persistenceCleanupError
  }
}
