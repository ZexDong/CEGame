[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [string]$UnityEditorPath=$env:UNITY_EDITOR,
  [string]$UnityCliPath=$env:UNITY_CLI
)
$ErrorActionPreference='Stop'
$evaluationRoot=(Resolve-Path -LiteralPath $PSScriptRoot).Path
$ruleManifest=Get-Content -LiteralPath (Join-Path $evaluationRoot 'rules.json') -Raw|ConvertFrom-Json
$evaluatorProtocol=[string]$ruleManifest.evaluator_protocol
$evaluatorRevision=[string]$ruleManifest.evaluator_revision
$demoRoot=(Resolve-Path (Join-Path $evaluationRoot '..\..')).Path
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
$priorDirtyStatus=''
$priorDirtyMarker=''
$priorChainValid=$false
$priorChainReasons=@()
$freshChainValid=$false
$d6InputManifest=''
$visualCaptureValidation=''
$standaloneBuild=$null
$standalonePlayer=$null
$standaloneCaptureReceipt=''
$standaloneCaptureHostReceipt=''
$d6CaptureReady=$false

function Quote([string]$value){'"'+($value-replace '"','\"')+'"'}
function Get-Sha([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-EvaluatorContractBinding{
  $paths=@((Join-Path $evaluationRoot 'rules.json'),(Join-Path $evaluationRoot 'requirement-coverage.json'),(Join-Path $evaluationRoot 'checkpoint-script.json'),(Join-Path $evaluationRoot 'baseline-applicability.json'),(Join-Path $evaluationRoot 'evaluator-routing.json'),$PSCommandPath)+@(Get-ChildItem -LiteralPath (Join-Path $evaluationRoot 'scripts') -File|Sort-Object FullName|Select-Object -ExpandProperty FullName);$paths+=@((Join-Path $repoRoot 'tools\unity\read-symbol-hud.py'),(Join-Path $repoRoot 'tools\unity\read-image-text.ps1'),(Join-Path $repoRoot 'tools\unity\invoke-native-ui-capture.ps1'),(Join-Path $repoRoot 'tools\unity\private-state-fixtures\Runtime\PreparedStateSession.cs'));$paths+=@(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tools\unity\session-evaluation') -Recurse -File | Where-Object Extension -in @('.cs','.asmdef','.json') | Select-Object -ExpandProperty FullName);$records=[Collections.Generic.List[string]]::new();$files=@();foreach($path in $paths){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing evaluator contract file: $path"};$relative=[IO.Path]::GetRelativePath($evaluationRoot,$path).Replace('\','/');$hash=Get-Sha $path;$records.Add("$relative`t$hash");$files+=[ordered]@{path=$relative;bytes=[long](Get-Item -LiteralPath $path).Length;sha256=$hash}};$records.Sort([StringComparer]::Ordinal);$bytes=[Text.Encoding]::UTF8.GetBytes(($records-join"`n"));$sha=[Security.Cryptography.SHA256]::Create();try{$digest=([BitConverter]::ToString($sha.ComputeHash($bytes))-replace'-','').ToLowerInvariant()}finally{$sha.Dispose()};[ordered]@{file_count=$files.Count;sha256=$digest;algorithm='sha256(utf8(join(ordinal-sorted(relative-path + TAB + file-sha256), LF)))';files=$files}
}
function Get-PngSize([string]$path){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [ordered]@{valid=$false;width=0;height=0}}
  $bytes=[IO.File]::ReadAllBytes($path);if($bytes.Length-lt24-or$bytes[0]-ne0x89-or$bytes[1]-ne0x50-or$bytes[2]-ne0x4e-or$bytes[3]-ne0x47-or$bytes[4]-ne0x0d-or$bytes[5]-ne0x0a-or$bytes[6]-ne0x1a-or$bytes[7]-ne0x0a){return [ordered]@{valid=$false;width=0;height=0}}
  $width=([int]$bytes[16]-shl24)-bor([int]$bytes[17]-shl16)-bor([int]$bytes[18]-shl8)-bor[int]$bytes[19];$height=([int]$bytes[20]-shl24)-bor([int]$bytes[21]-shl16)-bor([int]$bytes[22]-shl8)-bor[int]$bytes[23]
  [ordered]@{valid=($width-gt0-and$height-gt0);width=$width;height=$height}
}
function Get-RuntimeSnapshotFields([string]$snapshot){
  $fields=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
  $errors=[Collections.Generic.List[string]]::new()
  if([string]::IsNullOrWhiteSpace($snapshot)){$errors.Add('runtime_snapshot is empty.');return [ordered]@{fields=$fields;errors=@($errors)}}
  foreach($part in @($snapshot-split';')){
    $separator=$part.IndexOf('=')
    if($separator-le0){continue}
    $key=$part.Substring(0,$separator).Trim();$value=$part.Substring($separator+1).Trim()
    if([string]::IsNullOrWhiteSpace($key)){continue}
    if($fields.ContainsKey($key)){$errors.Add("runtime_snapshot duplicates field '$key'.");continue}
    $fields.Add($key,$value)
  }
  [ordered]@{fields=$fields;errors=@($errors)}
}
function Write-D6Artifacts([string]$evidencePath,[string]$standaloneReceiptPath,[string]$hostReceiptPath){
  $visualRoot=Join-Path $OutputRoot 'visual';[IO.Directory]::CreateDirectory($visualRoot)|Out-Null;$candidateRoot=Join-Path $OutputRoot 'visual-candidates';$referenceRoot=Join-Path (Split-Path -Parent $evaluationRoot) 'reference\visual\reference';$candidate=Join-Path $candidateRoot '01_initial_gameplay.png';$reference=(Resolve-Path -LiteralPath (Join-Path $referenceRoot '01_initial_gameplay.png')).Path
  $document=$null;$documentError='';if(Test-Path -LiteralPath $evidencePath -PathType Leaf){try{$document=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json}catch{$documentError=$_.Exception.Message}}else{$documentError='dynamic evidence is missing.'};$checks=if($null-ne$document){@($document.checks)}else{@()}
  $receipt=$null;$receiptError='';if(Test-Path -LiteralPath $standaloneReceiptPath -PathType Leaf){try{$receipt=Get-Content -LiteralPath $standaloneReceiptPath -Raw|ConvertFrom-Json}catch{$receiptError=$_.Exception.Message}}else{$receiptError='standalone capture receipt is missing.'}
  $captureHostDocument=$null;$hostError='';if(Test-Path -LiteralPath $hostReceiptPath -PathType Leaf){try{$captureHostDocument=Get-Content -LiteralPath $hostReceiptPath -Raw|ConvertFrom-Json}catch{$hostError=$_.Exception.Message}}else{$hostError='standalone capture host receipt is missing.'}
  $png=Get-PngSize $candidate;$exists=Test-Path -LiteralPath $candidate -PathType Leaf;$actualBytes=if($exists){[long](Get-Item -LiteralPath $candidate).Length}else{0};$actualSha=if($exists){Get-Sha $candidate}else{''};$reasons=[Collections.Generic.List[string]]::new();$semanticChecks=[ordered]@{}
  if($null-eq$document){$reasons.Add($(if([string]::IsNullOrWhiteSpace($documentError)){'dynamic evidence is unreadable.'}else{$documentError}))}else{if([string]$document.phase-cne'dynamic'){$reasons.Add("evidence phase is '$($document.phase)', expected 'dynamic'.")};if([int]$document.process_id-le0){$reasons.Add('dynamic evidence process_id is missing.')}}

  if($null-eq$receipt){$reasons.Add($(if([string]::IsNullOrWhiteSpace($receiptError)){'standalone capture receipt is unreadable.'}else{$receiptError}))}else{
    if([int]$receipt.schema_version-ne2){$reasons.Add("standalone receipt schema_version is '$($receipt.schema_version)', expected 2.")}
    if([string]$receipt.method-cne'standalone-visible-two-layer-internal-composite-v3'){$reasons.Add("standalone receipt method is '$($receipt.method)'.")}
    if([string]$receipt.run_id-cne$runId){$reasons.Add('standalone receipt run_id does not bind this evaluation run.')}
    if(-not($receipt.valid-is[bool])-or-not[bool]$receipt.valid){$reasons.Add("standalone receipt is not valid; status='$($receipt.status)', classification='$($receipt.classification)'.")}
    if([string]$receipt.status-cne'captured'){$reasons.Add("standalone receipt status is '$($receipt.status)', expected 'captured'.")}
    if([string]$receipt.state-cne'initial_gameplay'){$reasons.Add("standalone receipt state is '$($receipt.state)'.")}
    if([int]$receipt.process_id-le0){$reasons.Add('standalone receipt process_id is missing.')}
    if([string]$receipt.screenshot_path-cne$candidate){$reasons.Add('standalone receipt screenshot_path does not match the formal D6 candidate path.')}
    if([int]$receipt.width-ne1280-or[int]$receipt.height-ne720){$reasons.Add("standalone receipt dimensions are $($receipt.width)x$($receipt.height).")}
    if([long]$receipt.bytes-ne$actualBytes-or[string]$receipt.sha256-cne$actualSha){$reasons.Add('standalone receipt bytes/hash do not match the formal PNG.')}
    $snapshot=Get-RuntimeSnapshotFields ([string]$receipt.runtime_snapshot);foreach($error in @($snapshot.errors)){$reasons.Add([string]$error)};$requiredSnapshot=[ordered]@{screen='Playing'}
    foreach($entry in $requiredSnapshot.GetEnumerator()){$observed=if($snapshot.fields.ContainsKey([string]$entry.Key)){[string]$snapshot.fields[[string]$entry.Key]}else{''};$matches=if([string]$entry.Key-ceq'alive'){$observed.Equals([string]$entry.Value,[StringComparison]::OrdinalIgnoreCase)}else{$observed.Equals([string]$entry.Value,[StringComparison]::Ordinal)};$semanticChecks['runtime_'+[string]$entry.Key]=[ordered]@{expected=[string]$entry.Value;observed=$observed;passed=$matches};if(-not$matches){$reasons.Add("runtime_snapshot $($entry.Key) is '$observed', expected '$($entry.Value)'.")}}
    if(-not[bool]$receipt.sentinel.proof_valid-or[int]$receipt.sentinel.proof_match_pixels-lt180){$reasons.Add('standalone OnGUI sentinel proof is invalid.')}
    if(-not[bool]$receipt.sentinel.clean_valid-or[int]$receipt.sentinel.clean_match_pixels-ge24){$reasons.Add('formal clean base retained the evaluator sentinel.')}
    if([int]$receipt.overlay.dedicated_layer-ne31-or[int]$receipt.overlay.culling_mask-ne-2147483648){$reasons.Add('UI overlay was not isolated on dedicated layer 31.')}
    if([string]$receipt.overlay.render_path-notmatch'layer31$'){$reasons.Add("UI overlay render_path is '$($receipt.overlay.render_path)'.")}
    if(-not[bool]$receipt.restoration.canvas_settings_restored-or-not[bool]$receipt.restoration.layers_restored-or-not[bool]$receipt.restoration.completed){$reasons.Add('standalone capture did not prove complete Canvas/layer restoration.')}
  }
  if($null-eq$captureHostDocument){$reasons.Add($(if([string]::IsNullOrWhiteSpace($hostError)){'standalone host receipt is unreadable.'}else{$hostError}))}else{if([string]$captureHostDocument.run_id-cne$runId){$reasons.Add('standalone host receipt run_id mismatch.')};if($null-eq$captureHostDocument.player){$reasons.Add('standalone host receipt has no player process.')}else{if([bool]$captureHostDocument.player.timed_out){$reasons.Add('standalone player exceeded the 90 second hard timeout.')};if([int]$captureHostDocument.player.exit_code-ne0){$reasons.Add("standalone player exit code is $($captureHostDocument.player.exit_code).")};if($null-ne$receipt-and[int]$captureHostDocument.player.process_id-ne[int]$receipt.process_id){$reasons.Add('standalone player PID does not match the runtime receipt.')}};if([string]$captureHostDocument.capture_receipt_sha256-cne$(Get-Sha $standaloneReceiptPath)){$reasons.Add('standalone host receipt hash does not bind the runtime receipt.')}}
  if(-not$exists-or-not[bool]$png.valid-or[int]$png.width-ne1280-or[int]$png.height-ne720-or$actualBytes-le128){$reasons.Add('formal standalone PNG is missing, unreadable, or not 1280x720.')}
  $receiptPresent=$null-ne$receipt
  $receiptMatchesFile=$receiptPresent-and[string]$receipt.screenshot_path-ceq$candidate-and[int]$receipt.width-eq[int]$png.width-and[int]$receipt.height-eq[int]$png.height-and[long]$receipt.bytes-eq$actualBytes-and[string]$receipt.sha256-ceq$actualSha
  $valid=$reasons.Count-eq0;$captureReceiptHash=if(Test-Path -LiteralPath $standaloneReceiptPath -PathType Leaf){Get-Sha $standaloneReceiptPath}else{''}
  $validationState=[ordered]@{id='initial_gameplay';file='01_initial_gameplay.png';valid=$valid;status=if($valid){'captured'}elseif(-not$exists){'missing'}else{'invalid'};capture_source='standalone_visible_two_layer_internal_composite';width=[int]$png.width;height=[int]$png.height;bytes=$actualBytes;sha256=$actualSha;receipt_present=[bool]$receiptPresent;receipt_matches_file=[bool]$receiptMatchesFile;standalone_receipt=$standaloneReceiptPath;standalone_receipt_sha256=$captureReceiptHash;standalone_host_receipt=$hostReceiptPath;semantic_gate_reasons=@($reasons);semantic_checks=$semanticChecks;runtime_snapshot=if($null-ne$receipt){[string]$receipt.runtime_snapshot}else{''}}
  $validationPath=Join-Path $visualRoot 'capture-validation.json';$validation=[ordered]@{schema_version=2;valid=$valid;required_resolution=@(1280,720);formal_capture_source='standalone_visible_two_layer_internal_composite';states=@($validationState)};[IO.File]::WriteAllText($validationPath,($validation|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  $batchRoot=Join-Path $OutputRoot 'visual-diagnostics\batch-camera';$standaloneDiagnosticRoot=Join-Path $OutputRoot 'visual-diagnostics\standalone';$diagnosticInventory=@([ordered]@{id='batch_initial_camera';candidate=Join-Path $batchRoot '01_initial_gameplay.png';exists=Test-Path -LiteralPath (Join-Path $batchRoot '01_initial_gameplay.png') -PathType Leaf;role='diagnostic_camera_only_not_formal'},[ordered]@{id='batch_dash_camera';candidate=Join-Path $batchRoot '03_dash_action.png';exists=Test-Path -LiteralPath (Join-Path $batchRoot '03_dash_action.png') -PathType Leaf;role='diagnostic_camera_only_not_formal'},[ordered]@{id='standalone_sentinel_proof';candidate=Join-Path $standaloneDiagnosticRoot 'standalone-sentinel-proof.png';exists=Test-Path -LiteralPath (Join-Path $standaloneDiagnosticRoot 'standalone-sentinel-proof.png') -PathType Leaf;role='diagnostic_not_formal'},[ordered]@{id='standalone_clean_base';candidate=Join-Path $standaloneDiagnosticRoot 'standalone-clean-base.png';exists=Test-Path -LiteralPath (Join-Path $standaloneDiagnosticRoot 'standalone-clean-base.png') -PathType Leaf;role='diagnostic_not_formal'},[ordered]@{id='standalone_ui_overlay';candidate=Join-Path $standaloneDiagnosticRoot 'standalone-ui-overlay.png';exists=Test-Path -LiteralPath (Join-Path $standaloneDiagnosticRoot 'standalone-ui-overlay.png') -PathType Leaf;role='diagnostic_not_formal'})
  $manifestPath=Join-Path $visualRoot 'd6-input.json';$manifest=[ordered]@{schema_version=3;benchmark_id='unity.noir_roombreak_challenge.v1';protocol='public-requirements-visual-quality-20260908';formal_reference_ready=$true;primary_state_id='initial_gameplay';required_rounds=1;manifest_role='native formal single-state D6 input';formal_capture_source='standalone_visible_two_layer_internal_composite';visual_evaluator=[ordered]@{model='gpt-5.6-sol';rounds=1;prompt_sha256='6ac0e9665ad0f46bf33312ceede92bea5bc543ba6f0d37752a8493110ac3e77d'};capture_validation=$validationPath;states=@([ordered]@{id='initial_gameplay';label='initial gameplay';reference=$reference;candidate=$candidate});diagnostic_inventory=$diagnosticInventory};[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false));[ordered]@{manifest=$manifestPath;validation=$validationPath}
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
  $packageSource=Join-Path $evaluationRoot 'package-v2'
  $packageTarget=Join-Path $project ('Packages\'+$packageName)
  if(Test-Path -LiteralPath $packageTarget){throw "Scratch evaluator package already exists: $packageTarget"}
  Copy-Tree $packageSource $packageTarget
  $fixtureName='com.gamecreate.evaluation.private-state-fixtures'
  Copy-Tree (Join-Path $repoRoot 'tools\unity\private-state-fixtures') (Join-Path $project ('Packages\'+$fixtureName))
  $sessionName='com.gamecreate.evaluation.session';Copy-Tree (Join-Path $repoRoot 'tools\unity\session-evaluation') (Join-Path $project ('Packages\'+$sessionName))
  $path=Join-Path $project 'Packages\manifest.json';$manifest=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;$dependencies=[ordered]@{};$manifest.dependencies.psobject.Properties|ForEach-Object{$dependencies[$_.Name]=$_.Value};$dependencies[$packageName]='file:'+$packageName;$dependencies[$fixtureName]='file:'+$fixtureName;$dependencies[$sessionName]='file:'+$sessionName;$testables=@($manifest.testables|Where-Object{$_});if($testables-notcontains$packageName){$testables+=$packageName};$output=[ordered]@{dependencies=$dependencies;testables=$testables};[IO.File]::WriteAllText($path,($output|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}
function Invoke-Cli([string]$name,[string[]]$arguments,[int]$hostTimeout){
  if(Test-Path -LiteralPath (Join-Path $scratch 'Temp\UnityLockfile')){throw "Scratch project is still owned before $name."}
  $stdout=Join-Path $OutputRoot ($name+'-cli.stdout.log');$stderr=Join-Path $OutputRoot ($name+'-cli.stderr.log')
  $process=Start-Process -FilePath $UnityCliPath -ArgumentList $arguments -WorkingDirectory $scratch -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $timedOut=-not$process.WaitForExit($hostTimeout*1000);if($timedOut){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;$process.WaitForExit(10000)|Out-Null;$code=124}else{$process.WaitForExit();$code=[int]$process.ExitCode}
  [ordered]@{name=$name;executor='unity-cli';cli_process_id=[int]$process.Id;exit_code=$code;timed_out=$timedOut;stdout=$stdout;stderr=$stderr}
}
function Run-Compile([string]$name,[int]$timeout){
  $log=Join-Path $OutputRoot ($name+'.log')
  $result=Invoke-UnityProcess $name @('-batchmode','-nographics','-quit','-projectPath',$scratch,'-logFile',$log) $timeout $false
  $result.log=$log;return $result
}
function Run-Test([string]$name,[string]$assembly,[int]$timeout){
  $xml=Join-Path $OutputRoot ($name+'.xml');$log=Join-Path $OutputRoot ($name+'.log');$evidence=Join-Path $OutputRoot ($name+'-evidence.json');$env:NOIR_ROOMBREAK_EVIDENCE_FILE=$evidence
  if($name-eq'dynamic'){$env:NOIR_ROOMBREAK_SCREENSHOT_DIR=Join-Path $OutputRoot 'visual-diagnostics\batch-camera';$env:NOIR_ROOMBREAK_HEADFUL_SCREENSHOT_PATH=Join-Path $OutputRoot 'visual-candidates\01_initial_gameplay.png'}else{Remove-Item Env:NOIR_ROOMBREAK_SCREENSHOT_DIR,Env:NOIR_ROOMBREAK_HEADFUL_SCREENSHOT_PATH -ErrorAction SilentlyContinue}
  $args=@('-batchmode','-runTests','-projectPath',$scratch,'-testPlatform','PlayMode','-testFilter',$assembly,'-testResults',$xml,'-logFile',$log)
  $result=Invoke-UnityProcess $name $args $timeout $false;$result.xml=$xml;$result.log=$log;$result.evidence=$evidence;return $result
}

function Invoke-UnityProcess([string]$name,[string[]]$arguments,[int]$timeout,[bool]$visible){
  $stdout=Join-Path $OutputRoot ($name+'.stdout.log');$stderr=Join-Path $OutputRoot ($name+'.stderr.log');$argumentString=($arguments|ForEach-Object{Quote $_})-join' '
  $start=[DateTime]::UtcNow; if($visible){$process=Start-Process -FilePath $UnityEditorPath -ArgumentList $argumentString -WorkingDirectory $scratch -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr}else{$process=Start-Process -FilePath $UnityEditorPath -ArgumentList $argumentString -WorkingDirectory $scratch -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr}
  $timedOut=-not$process.WaitForExit($timeout*1000);if($timedOut){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;$process.WaitForExit(10000)|Out-Null;$code=124}else{$process.WaitForExit();$code=[int]$process.ExitCode}
  [ordered]@{name=$name;process_id=[int]$process.Id;exit_code=$code;timed_out=$timedOut;started_utc=$start.ToString('o');ended_utc=[DateTime]::UtcNow.ToString('o');stdout=$stdout;stderr=$stderr}
}

function Write-SyntheticStandaloneReceipt([string]$path,[string]$status,[string]$classification,[string]$message,[int]$processId){
  $receipt=[ordered]@{schema_version=2;method='standalone-visible-two-layer-internal-composite-v3';run_id=$runId;status=$status;classification=$classification;valid=$false;process_id=$processId;unity_version='6000.0.80f1';scene='';state='initial_gameplay';input_path='';width=0;height=0;bytes=0;sha256='';screenshot_path=(Join-Path $OutputRoot 'visual-candidates\01_initial_gameplay.png');runtime_snapshot='';semantic=[ordered]@{screen='';room_index=-1;room_count=0;bonds=0;maximum_bonds=0;dash=0;maximum_dash=0;alive=$false;defeated=0;soft=0;global=0};sentinel=[ordered]@{proof_valid=$false;proof_match_pixels=0;proof_sha256='';clean_valid=$false;clean_match_pixels=0;clean_base_sha256='';rect=''};overlay=[ordered]@{canvas_count=0;moved_ui_object_count=0;displaced_foreign_layer31_count=0;dedicated_layer=31;culling_mask=-2147483648;nonzero_alpha_pixels=0;partial_alpha_pixels=0;render_path='';sha256=''};restoration=[ordered]@{canvas_settings_restored=$false;layers_restored=$false;completed=$false};created_utc=[DateTime]::UtcNow.ToString('o');error=$message;planned_exit_code=if($classification-ceq'candidate_state_unavailable'){0}else{3}}
  [IO.Directory]::CreateDirectory((Split-Path -Parent $path))|Out-Null;[IO.File]::WriteAllText($path,($receipt|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}

function Run-StandaloneCapture{
  $visualRoot=Join-Path $OutputRoot 'visual';$candidateRoot=Join-Path $OutputRoot 'visual-candidates';$diagnosticRoot=Join-Path $OutputRoot 'visual-diagnostics\standalone';[IO.Directory]::CreateDirectory($visualRoot)|Out-Null;[IO.Directory]::CreateDirectory($candidateRoot)|Out-Null;[IO.Directory]::CreateDirectory($diagnosticRoot)|Out-Null
  $buildRoot=Join-Path (Split-Path -Parent $scratch) 'standalone-player';$buildLog=Join-Path $OutputRoot 'standalone-build.log';$buildReceipt=Join-Path $visualRoot 'standalone-build-host.json';$captureReceipt=Join-Path $visualRoot 'standalone-capture-receipt.json';$captureHost=Join-Path $visualRoot 'standalone-capture-host.json';$screenshot=Join-Path $candidateRoot '01_initial_gameplay.png';$playerLog=Join-Path $OutputRoot 'standalone-player.log'
  $priorBuildRoot=$env:NOIR_STANDALONE_BUILD_ROOT
  try{
    $env:NOIR_STANDALONE_BUILD_ROOT=$buildRoot
    $buildArgs=@('-batchmode','-quit','-projectPath',$scratch,'-executeMethod','GameCreate.NoirRoombreak.Evaluator.Standalone.Editor.StandaloneCaptureBuild.BuildPlayer','-logFile',$buildLog)
    $build=Invoke-UnityProcess 'standalone-build-process' $buildArgs 600 $false;$build.executable=Join-Path $buildRoot 'NoirRoombreakCapture.exe';$build.log=$buildLog;$build.executable_exists=Test-Path -LiteralPath $build.executable -PathType Leaf;if($build.executable_exists){$build.executable_sha256=Get-Sha $build.executable}else{$build.executable_sha256=''}
    [IO.File]::WriteAllText($buildReceipt,($build|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
  }finally{$env:NOIR_STANDALONE_BUILD_ROOT=$priorBuildRoot}
  if($build.exit_code-ne0-or$build.timed_out-or-not$build.executable_exists){Write-SyntheticStandaloneReceipt $captureReceipt 'standalone_build_failed' 'evaluator_capture_error' "Standalone build failed or timed out. Exit=$($build.exit_code)." 0;$captureHostDocument=[ordered]@{schema_version=1;run_id=$runId;valid=$false;build=$build;player=$null;capture_receipt=$captureReceipt};[IO.File]::WriteAllText($captureHost,($captureHostDocument|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false));return [ordered]@{build=$build;player=$null;capture_receipt=$captureReceipt;host_receipt=$captureHost}}
  $priorEnabled=$env:NOIR_STANDALONE_CAPTURE_ENABLED;$priorScreenshot=$env:NOIR_STANDALONE_SCREENSHOT_PATH;$priorReceipt=$env:NOIR_STANDALONE_RECEIPT_PATH;$priorDiagnostic=$env:NOIR_STANDALONE_DIAGNOSTIC_DIR;$priorRun=$env:NOIR_STANDALONE_RUN_ID
  try{
    $env:NOIR_STANDALONE_CAPTURE_ENABLED='1';$env:NOIR_STANDALONE_SCREENSHOT_PATH=$screenshot;$env:NOIR_STANDALONE_RECEIPT_PATH=$captureReceipt;$env:NOIR_STANDALONE_DIAGNOSTIC_DIR=$diagnosticRoot;$env:NOIR_STANDALONE_RUN_ID=$runId
    $playerStdout=Join-Path $OutputRoot 'standalone-player.stdout.log';$playerStderr=Join-Path $OutputRoot 'standalone-player.stderr.log';$playerArgs=(@('-screen-width','1280','-screen-height','720','-screen-fullscreen','0','-logFile',$playerLog)|ForEach-Object{Quote $_})-join' ';$started=[DateTime]::UtcNow;$process=Start-Process -FilePath $build.executable -ArgumentList $playerArgs -WorkingDirectory $buildRoot -PassThru -RedirectStandardOutput $playerStdout -RedirectStandardError $playerStderr
    $timedOut=-not$process.WaitForExit(90000);if($timedOut){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;$process.WaitForExit(10000)|Out-Null;$playerExit=124}else{$process.WaitForExit();$playerExit=[int]$process.ExitCode}
    $player=[ordered]@{process_id=[int]$process.Id;exit_code=$playerExit;timed_out=$timedOut;started_utc=$started.ToString('o');ended_utc=[DateTime]::UtcNow.ToString('o');log=$playerLog;stdout=$playerStdout;stderr=$playerStderr;visible_window_required=$true}
  }finally{$env:NOIR_STANDALONE_CAPTURE_ENABLED=$priorEnabled;$env:NOIR_STANDALONE_SCREENSHOT_PATH=$priorScreenshot;$env:NOIR_STANDALONE_RECEIPT_PATH=$priorReceipt;$env:NOIR_STANDALONE_DIAGNOSTIC_DIR=$priorDiagnostic;$env:NOIR_STANDALONE_RUN_ID=$priorRun}
  if(-not(Test-Path -LiteralPath $captureReceipt -PathType Leaf)){if($player.timed_out){Write-SyntheticStandaloneReceipt $captureReceipt 'standalone_player_timeout' 'evaluator_capture_error' 'Standalone capture player exceeded the 90 second hard timeout.' $player.process_id}else{Write-SyntheticStandaloneReceipt $captureReceipt 'standalone_receipt_missing' 'evaluator_capture_error' "Standalone player exited $($player.exit_code) without a receipt." $player.process_id}}
  $captureHostDocument=[ordered]@{schema_version=1;run_id=$runId;valid=(-not$player.timed_out-and$player.exit_code-eq0);build=$build;player=$player;capture_receipt=$captureReceipt;capture_receipt_sha256=Get-Sha $captureReceipt;screenshot=$screenshot;screenshot_exists=Test-Path -LiteralPath $screenshot -PathType Leaf};[IO.File]::WriteAllText($captureHost,($captureHostDocument|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false));[ordered]@{build=$build;player=$player;capture_receipt=$captureReceipt;host_receipt=$captureHost}
}
function Candidate-CompilerErrors([string]$log){if(-not(Test-Path -LiteralPath $log)){return @()};@(Select-String -LiteralPath $log -Pattern '(?i)(?:^|[\\/])Assets[\\/].*error CS\d+'|ForEach-Object{$_.Line.Trim()}|Sort-Object -Unique)}
function Evaluator-CompilerErrors([string]$log){if(-not(Test-Path -LiteralPath $log)){return @()};@(Select-String -LiteralPath $log -Pattern '(?i)evaluation[\\/]package.*error CS\d+|com\.gamecreate\.benchmark\.noir-roombreak\.evaluator.*error CS\d+'|ForEach-Object{$_.Line.Trim()}|Sort-Object -Unique)}

& (Join-Path $evaluationRoot 'scripts\score.ps1') -OutputRoot $OutputRoot -ProjectPath $ProjectPath -StaticExit 0 -DynamicExit 0 -FreshExit 0 -SelfCheck | Out-Null
if($LASTEXITCODE -ne 0){throw 'Session scoring metadata preflight failed.'}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null;[IO.Directory]::CreateDirectory($hostTemp)|Out-Null
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
try{
  $sourceBefore=Get-TreeBinding $ProjectPath;$evaluatorPackageSource=Join-Path $evaluationRoot 'package-v2';$evaluatorPackageBefore=Get-TreeBinding $evaluatorPackageSource;$evaluatorContractBefore=Get-EvaluatorContractBinding;Copy-Tree $ProjectPath $scratch;Set-Identity $scratch;$env:TEMP=$hostTemp;$env:TMP=$hostTemp;$env:UseSharedCompilation='false'
  $baseline=Run-Compile 'candidate-compile' 1200;$candidateErrors=Candidate-CompilerErrors $baseline.log
  if($baseline.exit_code-ne0-and$candidateErrors.Count-gt0){[ordered]@{schema_version=1;classification='candidate_compile_failure';diagnostics=$candidateErrors;baseline=$baseline}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputRoot 'candidate-compile-failure.json') -Encoding utf8;& (Join-Path $evaluationRoot 'scripts\score.ps1') -OutputRoot $OutputRoot -ProjectPath $ProjectPath -StaticExit $baseline.exit_code -DynamicExit -10 -FreshExit -10 -StaticTimedOut:$false -DynamicTimedOut:$false -FreshTimedOut:$false -CandidateCompileFailure;$scoreExit=$LASTEXITCODE;$staticExit=$baseline.exit_code;$dynamicExit=-10;$freshExit=-10;$candidateCompileFailure=$true;$visualRoot=Join-Path $OutputRoot 'visual';[IO.Directory]::CreateDirectory($visualRoot)|Out-Null;$standaloneCaptureReceipt=Join-Path $visualRoot 'standalone-capture-receipt.json';$standaloneCaptureHostReceipt=Join-Path $visualRoot 'standalone-capture-host.json';Write-SyntheticStandaloneReceipt $standaloneCaptureReceipt 'candidate_compile_failure' 'candidate_state_unavailable' 'Candidate compilation failed before standalone capture could run.' 0;$captureHostDocument=[ordered]@{schema_version=1;run_id=$runId;valid=$true;build=$null;player=$null;capture_receipt=$standaloneCaptureReceipt;capture_receipt_sha256=Get-Sha $standaloneCaptureReceipt;screenshot='';screenshot_exists=$false;classification='candidate_compile_failure'};[IO.File]::WriteAllText($standaloneCaptureHostReceipt,($captureHostDocument|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false));$visualArtifacts=Write-D6Artifacts (Join-Path $OutputRoot 'dynamic-evidence.json') $standaloneCaptureReceipt $standaloneCaptureHostReceipt;$d6InputManifest=$visualArtifacts.manifest;$visualCaptureValidation=$visualArtifacts.validation}
  elseif($baseline.exit_code-ne0){throw "Unity CLI candidate compile/import failed without a candidate-owned C# diagnostic. Exit=$($baseline.exit_code)."}
  else{
    $candidateCompileFailure=$false;Inject-Evaluator $scratch;$evaluatorCompile=Run-Compile 'evaluator-compile' 1200;$evaluatorErrors=Evaluator-CompilerErrors $evaluatorCompile.log;if($evaluatorCompile.exit_code-ne0-or$evaluatorErrors.Count){throw "Private evaluator failed to compile. Exit=$($evaluatorCompile.exit_code); errors=$($evaluatorErrors -join ' | ')"}

    # Capture the real headful player frame before Dynamic so D1-D5 visual
    # assembly checks can inspect the same complete IMGUI+uGUI presentation
    # that D6 will receive. Batch Camera.Render remains diagnostic only.
    $visualMutex=[Threading.Mutex]::new($false,'Local\GameCreateNoirVisualCapture')
    $visualOwned=$false
    try {
      while(-not $visualMutex.WaitOne(1000)){}
      $visualOwned=$true
    $standalone=Run-StandaloneCapture;$standaloneBuild=$standalone.build;$standalonePlayer=$standalone.player;$standaloneCaptureReceipt=$standalone.capture_receipt;$standaloneCaptureHostReceipt=$standalone.host_receipt
    if(Test-Path -LiteralPath (Join-Path $scratch 'Assets\NoirChallenge\Scenes\NoirRoombreak.unity')){
      $uiRoot=Join-Path $OutputRoot 'ui'
      & (Join-Path $repoRoot 'tools\unity\invoke-native-ui-capture.ps1') -Executable $standaloneBuild.executable -OutputRoot $uiRoot | Out-Null
      $env:NOIR_UI_OBSERVATIONS=Join-Path $uiRoot 'ui-observations.json'
    }
    } finally {if($visualOwned){$visualMutex.ReleaseMutex()};$visualMutex.Dispose()}
    $static=Run-Test 'static' 'GameCreate.NoirRoombreak.Evaluator.Static' 600;$staticExit=$static.exit_code
    $dynamic=Run-Test 'dynamic' 'GameCreate.NoirRoombreak.Evaluator.Dynamic' 1800;$dynamicExit=$dynamic.exit_code
    if(Test-Path -LiteralPath $dynamic.evidence){try{$dynamicEvidence=Get-Content -LiteralPath $dynamic.evidence -Raw|ConvertFrom-Json;$priorPid=[int]$dynamicEvidence.process_id;$dirty=@($dynamicEvidence.trajectories|Where-Object{[string]$_.id-ceq'TRAJ10'});if($dirty.Count-ne1){$priorChainReasons+=@("expected exactly one TRAJ10; observed $($dirty.Count)")}else{$priorSession=[string]$dirty[0].session_id;$priorDirtyStatus=[string]$dirty[0].status;if($priorDirtyStatus-cne'completed-dirty-close'){$priorChainReasons+=@("TRAJ10 status is '$priorDirtyStatus'")};if([string]::IsNullOrWhiteSpace($priorSession)){$priorChainReasons+=@('TRAJ10 session_id is empty')};if([int]$dirty[0].process_id-ne$priorPid-or$priorPid-le0){$priorChainReasons+=@('TRAJ10 process_id mismatch')}}}catch{$priorChainReasons+=@('dynamic lifecycle evidence unreadable: '+$_.Exception.Message)}}else{$priorChainReasons+=@('dynamic lifecycle evidence missing')}
    if($priorChainReasons.Count-eq0){$priorDirtyMarker="TRAJ10|completed-dirty-close|session=$priorSession|process=$priorPid";$priorChainValid=$true}
    $env:NOIR_ROOMBREAK_PRIOR_PROCESS_ID=$priorPid.ToString();$env:NOIR_ROOMBREAK_PRIOR_SESSION_ID=$priorSession;$env:NOIR_ROOMBREAK_PRIOR_DIRTY_MARKER=$priorDirtyMarker
    $fresh=Run-Test 'fresh' 'GameCreate.NoirRoombreak.Evaluator.Fresh' 600;$freshExit=$fresh.exit_code
    if(Test-Path -LiteralPath $fresh.evidence){try{$freshEvidence=Get-Content -LiteralPath $fresh.evidence -Raw|ConvertFrom-Json;$freshChainValid=$priorChainValid-and[bool]$freshEvidence.prior_dirty_chain_valid-and[int]$freshEvidence.prior_process_id-eq$priorPid-and[string]$freshEvidence.prior_session_id-ceq$priorSession-and[string]$freshEvidence.prior_dirty_marker-ceq$priorDirtyMarker}catch{$freshChainValid=$false}}
    $visualArtifacts=Write-D6Artifacts $dynamic.evidence $standaloneCaptureReceipt $standaloneCaptureHostReceipt;$d6InputManifest=$visualArtifacts.manifest;$visualCaptureValidation=$visualArtifacts.validation;$d6CaptureReady=[bool](Get-Content -LiteralPath $visualCaptureValidation -Raw|ConvertFrom-Json).valid
    & (Join-Path $evaluationRoot 'scripts\score.ps1') -OutputRoot $OutputRoot -ProjectPath $ProjectPath -StaticExit $staticExit -DynamicExit $dynamicExit -FreshExit $freshExit -StaticTimedOut:([bool]$static.timed_out) -DynamicTimedOut:([bool]$dynamic.timed_out) -FreshTimedOut:([bool]$fresh.timed_out);$scoreExit=$LASTEXITCODE
  }
  $scorePath=Join-Path $OutputRoot 'score.json';$scoreValid=$false;if(Test-Path -LiteralPath $scorePath){$scoreValid=[bool](Get-Content -LiteralPath $scorePath -Raw|ConvertFrom-Json).valid_score}
  $sourceAfter=Get-TreeBinding $ProjectPath;$sourceUnchanged=$sourceBefore.sha256-eq$sourceAfter.sha256-and$sourceBefore.file_count-eq$sourceAfter.file_count;if(-not$sourceUnchanged){throw 'Evaluator modified the source candidate project.'}
  $evaluatorPackageAfter=Get-TreeBinding $evaluatorPackageSource;$evaluatorPackageSourceUnchanged=$evaluatorPackageBefore.sha256-eq$evaluatorPackageAfter.sha256-and$evaluatorPackageBefore.file_count-eq$evaluatorPackageAfter.file_count;if(-not$evaluatorPackageSourceUnchanged){throw 'Unity or the evaluator modified the canonical private evaluator package.'};$evaluatorContractAfter=Get-EvaluatorContractBinding;$evaluatorContractUnchanged=$evaluatorContractBefore.sha256-eq$evaluatorContractAfter.sha256-and$evaluatorContractBefore.file_count-eq$evaluatorContractAfter.file_count;if(-not$evaluatorContractUnchanged){throw 'Evaluator rules, coverage, runner, or scoring scripts changed during evaluation.'}
  [ordered]@{schema_version=7;run_id=$runId;executor='unity-editor-6000.0.80f1-direct';unity_cli=$UnityCliPath;unity_editor=$UnityEditorPath;static_exit=$staticExit;dynamic_exit=$dynamicExit;fresh_exit=$freshExit;candidate_compile_failure=$candidateCompileFailure;valid_score=$scoreValid;score_scope='D1-D5_only';final_score_ready=$false;d6_capture_ready=$d6CaptureReady;source_unchanged=$sourceUnchanged;source_before=$sourceBefore;source_after=$sourceAfter;evaluator_package_source_unchanged=$evaluatorPackageSourceUnchanged;evaluator_package_before=$evaluatorPackageBefore;evaluator_package_after=$evaluatorPackageAfter;evaluator_contract_source_unchanged=$evaluatorContractUnchanged;evaluator_contract_before=$evaluatorContractBefore;evaluator_contract_after=$evaluatorContractAfter;prior_dynamic_process_id=$priorPid;prior_dynamic_trajectory_id='TRAJ10';prior_dynamic_status=$priorDirtyStatus;prior_dynamic_session_id=$priorSession;prior_dynamic_dirty_marker=$priorDirtyMarker;prior_dynamic_chain_valid=$priorChainValid;prior_dynamic_chain_reasons=@($priorChainReasons);fresh_lifecycle_chain_valid=$freshChainValid;standalone_build=$standaloneBuild;standalone_player=$standalonePlayer;standalone_capture_receipt=$standaloneCaptureReceipt;standalone_capture_host_receipt=$standaloneCaptureHostReceipt;d6_input_manifest=$d6InputManifest;visual_capture_validation=$visualCaptureValidation}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $OutputRoot 'run-summary.json') -Encoding utf8
  $exit=if($scoreExit-eq0-and$scoreValid-and$sourceUnchanged-and$evaluatorPackageSourceUnchanged){0}else{3}
}
catch{
  $message=$_.Exception.ToString();[IO.File]::WriteAllText((Join-Path $OutputRoot 'evaluator-error.txt'),$message,[Text.UTF8Encoding]::new($false))
  [ordered]@{schema_version=4;evaluator_protocol=$evaluatorProtocol;evaluator_revision=$evaluatorRevision;generated_utc=[DateTime]::UtcNow.ToString('o');project_path=$ProjectPath;valid_score=$false;candidate_status='evaluator_invalid';validation_reasons=@($message);score=$null;score_status='evaluator_invalid';automated_score=$null;automated_maximum_score=90.0;maximum_score=100.0;overall=[ordered]@{score=$null;maximum_score=100.0;status='evaluator_invalid'};executable=$null;solved=$null;checks=@()}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutputRoot 'score.json') -Encoding utf8
  $exit=3
}
finally{
  $env:TEMP=$oldTemp;$env:TMP=$oldTmp;Remove-Item Env:NOIR_UI_OBSERVATIONS,Env:NOIR_ROOMBREAK_EVIDENCE_FILE,Env:NOIR_ROOMBREAK_SCREENSHOT_DIR,Env:NOIR_ROOMBREAK_HEADFUL_SCREENSHOT_PATH,Env:NOIR_ROOMBREAK_PRIOR_PROCESS_ID,Env:NOIR_ROOMBREAK_PRIOR_SESSION_ID,Env:NOIR_ROOMBREAK_PRIOR_DIRTY_MARKER,Env:NOIR_STANDALONE_BUILD_ROOT,Env:NOIR_STANDALONE_CAPTURE_ENABLED,Env:NOIR_STANDALONE_SCREENSHOT_PATH,Env:NOIR_STANDALONE_RECEIPT_PATH,Env:NOIR_STANDALONE_DIAGNOSTIC_DIR,Env:NOIR_STANDALONE_RUN_ID -ErrorAction SilentlyContinue
  $localLowCompany=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) '..\LocalLow\GameCreateBenchmarkTemp'));$localLow=Join-Path $localLowCompany $runId
  $cleanup=[ordered]@{path=$localLow;existed=[IO.Directory]::Exists($localLow);removed=$false};if([IO.Directory]::Exists($localLow)){[IO.Directory]::Delete($localLow,$true);$cleanup.removed=-not[IO.Directory]::Exists($localLow)};$cleanup|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputRoot 'unity-persistence-cleanup.json') -Encoding utf8
  if([IO.Directory]::Exists((Split-Path -Parent $scratch))){Get-ChildItem (Split-Path -Parent $scratch) -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};[IO.Directory]::Delete((Split-Path -Parent $scratch),$true)}
}
exit $exit



