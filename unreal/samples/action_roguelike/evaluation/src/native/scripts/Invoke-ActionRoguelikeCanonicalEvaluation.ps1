[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateProject,
    [Parameter(Mandatory)][string]$EngineRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')][string]$RunId = ('run-' + [guid]::NewGuid().ToString('N')),
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')][string]$CandidateId,
    [switch]$SkipBuild,
    [switch]$TransportHealthOnly,
    [string]$FixtureBindingsPath,
    [string]$ReuseAtomicRunRoot,
    [string[]]$AtomicVariants=@(),
    [ValidateRange(1,5)][int]$TerminalTimeoutSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) 'ActionRoguelikeStateAdapter.ps1')
. (Join-Path (Split-Path -Parent $PSCommandPath) 'ActionRoguelikeAtomicChecks.ps1')
. (Join-Path (Split-Path -Parent $PSCommandPath) 'ActionRoguelikeRunBinding.ps1')
. (Join-Path (Split-Path -Parent $PSCommandPath) 'ActionRoguelikeFixtureRuntime.ps1')
$script:ARMetricBinding=$null
if([bool]$ReuseAtomicRunRoot-ne[bool]$AtomicVariants.Count){throw 'Incremental collection requires both ReuseAtomicRunRoot and explicit AtomicVariants.'}

function Write-JsonFile {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $parent=Split-Path -Parent $Path;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
}
function Get-Relative([string]$Path){[IO.Path]::GetRelativePath($script:OutputFull,[IO.Path]::GetFullPath($Path)).Replace('\','/')}
function Save-Receipt($Value,[string]$Name){$p=Join-Path $script:OutputFull "receipts/$Name.json";Write-JsonFile $Value $p;Get-Relative $p}
function Save-State($Value,[string]$Name){$p=Join-Path $script:OutputFull "states/$Name.json";Write-JsonFile $Value $p;Get-Relative $p}
function Assert-ExecutorOperationHealth($Receipt,[string]$EvidencePath){
    if([string](Get-ActionRoguelikePropertyValue $Receipt 'status') -eq 'ok'){return}
    $fault=Get-ActionRoguelikePropertyValue $Receipt 'fault'
    $code=[string](Get-ActionRoguelikePropertyValue $fault 'code')
    # These failures can originate in the candidate; the enclosing case records
    # them normally. Explicit executor/environment failures stay infrastructure.
    if($code -in @('process_exited_during_start','target_process_exited','first_frame_state_timeout','window_discovery_timeout','key_unsupported','mouse_button_unsupported')){return}
    if((Get-ActionRoguelikePropertyValue $Receipt 'executor_fault') -or (Get-ActionRoguelikePropertyValue $Receipt 'environment_fault') -or (Get-ActionRoguelikePropertyValue $Receipt 'unsupported')){
        $faults.Add([pscustomobject]@{domain=[string](Get-ActionRoguelikePropertyValue $fault 'domain');code=$code;message=[string](Get-ActionRoguelikePropertyValue $fault 'message');evidence_paths=@($EvidencePath)})
        throw 'evaluator_operation_stop'
    }
}
function Read-Json([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}catch{return $null}
}
function Get-ProjectIdentity([string]$Root){
    $safeRoot=Assert-ActionRoguelikeBindingPath -Path $Root
    $pending=[Collections.Generic.Queue[string]]::new();$pending.Enqueue($safeRoot)
    $files=[Collections.Generic.List[object]]::new()
    while($pending.Count){
        foreach($item in Get-ChildItem -LiteralPath $pending.Dequeue() -Force -ErrorAction Stop){
            if($item.Name -in @('Binaries','DerivedDataCache','Intermediate','Saved','.vs','.idea','.git','evaluation')){continue}
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne0){throw 'Candidate identity traversal encountered a reparse point.'}
            if($item.PSIsContainer){$pending.Enqueue($item.FullName)}else{$files.Add($item)}
        }
    }
    $lines=foreach($file in $files|Sort-Object FullName){$rel=[IO.Path]::GetRelativePath($Root,$file.FullName).Replace('\','/');$hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();"$rel`t$hash`t$($file.Length)"}
    $sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes(($lines-join"`n"))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Set-Checkpoint {
    param([string]$Id,[ValidateSet('pass','fail','unreachable')][string]$Verdict,[string]$Detail,[string[]]$Evidence=@(),[string]$ReasonCode,[string]$FirstFailure)
    $item=$script:VerdictsById[$Id];if($null-eq$item){throw "Unknown checkpoint: $Id"}
    $requested=@($Evidence|Where-Object{$_}|Sort-Object -Unique)
    $present=@($requested|Where-Object{Test-Path -LiteralPath (Join-Path $script:OutputFull $_) -PathType Leaf})
    $missing=@($requested|Where-Object{$_ -notin $present})
    if($missing.Count){
        $evidenceReceipt=Save-Receipt ([ordered]@{checkpoint_id=$Id;available=$present;missing=$missing;note='Missing requested artifacts are not observations. Consult the condition/input receipts for the direct failure.'}) "evidence-$Id"
        $present+=@($evidenceReceipt)
    }
    $item.verdict=$Verdict;$item.detail=$Detail;$item.evidence=$present
    $item.reason_code=if($Verdict-eq'pass'){$null}elseif($ReasonCode){$ReasonCode}elseif($Verdict-eq'unreachable'){'CANDIDATE_PREREQUISITE_UNREACHABLE'}else{'CANDIDATE_REQUIREMENT_FAILED'}
    $item.attribution=if($Verdict-eq'pass'){$null}else{'candidate'}
    $item.first_failure=if($Verdict-eq'pass'){$null}elseif($FirstFailure-and(Test-Path -LiteralPath (Join-Path $script:OutputFull $FirstFailure) -PathType Leaf)){$FirstFailure}elseif($item.evidence.Count){$item.evidence[0]}else{'candidate-manifest.json'}
    $item.score_impact=if($Verdict-eq'pass'){'full_credit'}else{'checkpoint_zero'}
}
function Set-Unresolved {
    param([ValidateSet('fail','unreachable')][string]$Verdict,[string]$Detail,[string[]]$Dimensions,[string]$ReasonCode,[string]$FirstFailure)
    foreach($item in $script:Verdicts){if($item.dimension-in$Dimensions-and$null-eq$item.verdict){Set-Checkpoint $item.checkpoint_id $Verdict $Detail @() $ReasonCode $FirstFailure}}
}
function Set-AtomicCheckpoint {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)]$Result,
        [string[]]$Evidence = @()
    )
    $verdict=[string](Get-ActionRoguelikeAtomicProperty $Result 'verdict')
    # Missing or corrupt collection is an evaluator fault. The atomic module
    # separately attributes deficient candidate events after health checks.
    $atomicRunInvalid=($verdict -eq 'run_invalid')
    if($atomicRunInvalid){
        $code=[string](Get-ActionRoguelikeAtomicProperty $Result 'reason_code')
        if([string]::IsNullOrWhiteSpace($code)){$code='ATOMIC_VARIANT_NOT_EXECUTED'}
        $verdict='unreachable'
    }
    if($verdict -notin @('pass','fail','unreachable')){$verdict='unreachable'}
    $detail=[string](Get-ActionRoguelikeAtomicProperty $Result 'detail')
    $reason=[string](Get-ActionRoguelikeAtomicProperty $Result 'reason_code')
    $measurement=Get-ActionRoguelikeAtomicProperty $Result 'measurements'
    $measurementPath=$null
    $collectionPath=$null
    if($null -ne $measurement){
        $measurementPath=Save-Receipt ([ordered]@{checkpoint_id=$Id;atomic_result=$Result}) "atomic-$Id"
        $collectionPath=Save-Receipt ([ordered]@{
                schema_version='1.0.0';checkpoint_id=$Id;required_variants=@(Get-ActionRoguelikeAtomicProperty $measurement 'required_variants')
                collected_variants=@(Get-ActionRoguelikeAtomicProperty $measurement 'collected_variants')
                missing_variants=@(Get-ActionRoguelikeAtomicProperty $measurement 'missing_variants')
                collection_complete=[bool](Get-ActionRoguelikeAtomicProperty $measurement 'collection_complete')
                diagnostic_only=$true;event_chain_required=$true;attribution=$(if($atomicRunInvalid){'evaluator'}else{$null})
            }) "atomic-$Id-collection-gate"
    }
    $allEvidence=@($Evidence|Where-Object{$_})+@($measurementPath|Where-Object{$_})+@($collectionPath|Where-Object{$_})
    Set-Checkpoint $Id $verdict $detail $allEvidence $reason $(if($allEvidence.Count){$allEvidence[0]}else{$null})
    if($atomicRunInvalid){
        $faultEvidence=@($allEvidence|Where-Object{Test-Path -LiteralPath (Join-Path $script:OutputFull $_) -PathType Leaf})
        $faults.Add([pscustomobject][ordered]@{domain='evaluator';code=$code;message=[string](Get-ActionRoguelikeAtomicProperty $Result 'detail');evidence_paths=$faultEvidence})
        $script:VerdictsById[$Id].attribution='evaluator'
        $script:VerdictsById[$Id].score_impact='run_invalid'
    }
}
function Get-ObservedValue($Observed){Get-ActionRoguelikeObservedValue -Observed $Observed}
function Get-ObservedPath($State,[string]$Path){Convert-ARMetricValue (Get-ActionRoguelikeObservedPathValue -State $State -Path $Path) $Path}
function Get-VectorDistance($A,$B){
    if($null-eq$A-or$null-eq$B){return 0.0}
    $ax=Get-ActionRoguelikePropertyValue $A 'x';$ay=Get-ActionRoguelikePropertyValue $A 'y';$az=Get-ActionRoguelikePropertyValue $A 'z'
    $bx=Get-ActionRoguelikePropertyValue $B 'x';$by=Get-ActionRoguelikePropertyValue $B 'y';$bz=Get-ActionRoguelikePropertyValue $B 'z'
    if($null-in@($ax,$ay,$az,$bx,$by,$bz)){return 0.0}
    $dx=[double]$ax-[double]$bx;$dy=[double]$ay-[double]$by;$dz=[double]$az-[double]$bz;[Math]::Sqrt($dx*$dx+$dy*$dy+$dz*$dz)
}
function Test-CaptureVisible([string]$Path){
    $bmp=$null;try{Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue;$bmp=[Drawing.Bitmap]::new($Path);$sum=0.0;$sumSq=0.0;$max=0.0;$count=0;for($y=10;$y-lt$bmp.Height;$y+=40){for($x=10;$x-lt$bmp.Width;$x+=40){$p=$bmp.GetPixel($x,$y);$l=.2126*$p.R+.7152*$p.G+.0722*$p.B;$sum+=$l;$sumSq+=$l*$l;$max=[Math]::Max($max,$l);++$count}};$mean=$sum/$count;$sd=[Math]::Sqrt([Math]::Max(0,($sumSq/$count)-$mean*$mean));return ($max-ge18-and-not($sd-lt2-and$mean-lt30))}catch{return $false}finally{if($bmp){$bmp.Dispose()}}}
function Measure-CaptureDifference([string]$A,[string]$B){
    $one=$null;$two=$null;try{Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue;$one=[Drawing.Bitmap]::new($A);$two=[Drawing.Bitmap]::new($B);if($one.Width-ne$two.Width-or$one.Height-ne$two.Height){return 255.0};$sum=0.0;$count=0;for($y=12;$y-lt$one.Height;$y+=24){for($x=12;$x-lt$one.Width;$x+=24){$p=$one.GetPixel($x,$y);$q=$two.GetPixel($x,$y);$sum+=[Math]::Abs($p.R-$q.R)+[Math]::Abs($p.G-$q.G)+[Math]::Abs($p.B-$q.B);$count+=3}};return ($sum/$count)}catch{return 0.0}finally{if($one){$one.Dispose()};if($two){$two.Dispose()}}}
function Save-CanonicalCapture([string]$Name){
    $raw=Join-Path $script:OutputFull "captures/raw/$Name.png";$canonical=Join-Path $script:OutputFull "captures/$Name.png";New-Item -ItemType Directory -Path (Split-Path -Parent $raw) -Force|Out-Null;New-Item -ItemType Directory -Path (Split-Path -Parent $canonical) -Force|Out-Null
    $receipt=Save-UnrealClientCapture -Session $script:Session -OutputPath $raw -ArtifactId "actionroguelike-$Name";[void](Save-Receipt $receipt "capture-$Name")
    Assert-ExecutorOperationHealth $receipt "receipts/capture-$Name.json"
    if($receipt.status-ne'ok'){return $null}
    $source=$null;$target=$null;$graphics=$null
    try{
        Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue;$source=[Drawing.Bitmap]::new($raw);$ratio=[double]$source.Width/[double]$source.Height
        if([Math]::Abs($ratio-(16.0/9.0))-gt0.01){return $null}
        if($source.Width-eq1280-and$source.Height-eq720){[IO.File]::Copy($raw,$canonical,$false)}else{$target=[Drawing.Bitmap]::new(1280,720,[Drawing.Imaging.PixelFormat]::Format24bppRgb);$graphics=[Drawing.Graphics]::FromImage($target);$graphics.CompositingQuality=[Drawing.Drawing2D.CompositingQuality]::HighQuality;$graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic;$graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::HighQuality;$graphics.DrawImage($source,0,0,1280,720);$target.Save($canonical,[Drawing.Imaging.ImageFormat]::Png)}
    }finally{if($graphics){$graphics.Dispose()};if($target){$target.Dispose()};if($source){$source.Dispose()}}
    $normalization=[ordered]@{schema_version='1.0.0';raw_path=Get-Relative $raw;canonical_path=Get-Relative $canonical;raw_width=[int]$receipt.result.width;raw_height=[int]$receipt.result.height;canonical_width=1280;canonical_height=720;method='deterministic_bicubic_if_needed';canonical_sha256=(Get-FileHash $canonical -Algorithm SHA256).Hash.ToLowerInvariant();visible=(Test-CaptureVisible $canonical)};Write-JsonFile $normalization (Join-Path $script:OutputFull "receipts/capture-$Name-normalization.json")
    if(-not$normalization.visible){return $null};Get-Relative $canonical
}
function Reset-StateReaderContext {
    $script:ARSampleHostTimes=@{}
    $script:StateReaderContext=New-ActionRoguelikeStateReaderContext `
        -SnapshotSchemaPath $script:SnapshotSchemaPath -EventsSchemaPath $script:EventsSchemaPath `
        -ExpectedProcessToken $script:ProcessToken -ExpectedProcessId $script:ProcessId `
        -SessionStartedUtc $script:SessionStartedUtc
}
function Start-TaskEvaluationSession {
    param($ProjectPath,$RunRoot,$StatePath,$ProcessToken,$EngineRoot,$WindowWidth,$WindowHeight,$TimeoutMs,$FocusTimeoutMs,[switch]$ObserverDisabledControl,$AdditionalArguments)
    $arguments=@{};foreach($key in $PSBoundParameters.Keys){$arguments[$key]=$PSBoundParameters[$key]}
    $captureSnapshot=@($AdditionalArguments|Where-Object{$_-like'-ActionRoguelikeSnapshotPath=*'})
    $captureEvents=@($AdditionalArguments|Where-Object{$_-like'-ActionRoguelikeEventsPath=*'})
    if($captureSnapshot.Count-eq1-and$captureEvents.Count-eq1){
        Start-ActionRoguelikeTransportRecorder ($captureSnapshot[0]-split'=',2)[1] ($captureEvents[0]-split'=',2)[1]
    }
    $watch=[Diagnostics.Stopwatch]::StartNew();$attempt=0;$lastCondition='';$conditionStarted=0.0
    do{
        $receipt=Start-UnrealEvaluationSession @arguments
        if($receipt.status-ceq'ok'-or$receipt.fault.code-cnotin@('input_state_not_neutral','active_input_session_exists')-or$receipt.input_dispatched-ne$false-or$null-ne$receipt.result){return $receipt}
        [void](Save-Receipt $receipt ('start-neutral-retry-'+(++$attempt)))
        if($receipt.fault.code-cne$lastCondition){$lastCondition=$receipt.fault.code;$conditionStarted=$watch.Elapsed.TotalSeconds}
        # Wait for a physical key release without injecting input or launching
        # a second process. Only this pre-dispatch host condition is retried.
        $leaseBusy=$receipt.fault.code-ceq'active_input_session_exists'
        if($watch.Elapsed.TotalSeconds-ge185-or($watch.Elapsed.TotalSeconds-$conditionStarted)-ge$(if($leaseBusy){180}else{5})){return $receipt}
        Start-Sleep -Milliseconds $(if($leaseBusy){1000}else{100})
    }while($true)
}
function Reopen-TaskWithFreshTransport([string]$Project,[string]$Engine){
    # Split archives have process-local filenames. Reusing their directory on
    # Reopen overwrites evidence and leaves a foreign tail from the old process.
    # Compose the same bound Stop/Start capabilities with a fresh channel.
    $oldProcess=$script:ProcessId;$oldToken=$script:ProcessToken
    $stop=Stop-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -FaultCleanupTimeoutMs 5000
    $stopPath=Save-Receipt $stop 'reopen-old-stop'
    Assert-ExecutorOperationHealth $stop $stopPath
    if($stop.status-cne'ok'){throw 'run_invalid|REOPEN_STOP_FAILED|Old process termination was not confirmed.'}
    $script:SessionActive=$false
    $script:StateRoot=Join-Path $script:OutputFull ('state/channel-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:StateRoot)
    $script:SnapshotPath=Join-Path $script:StateRoot 'snapshot.json';$script:EventsPath=Join-Path $script:StateRoot 'events.json'
    $script:SessionStartedUtc=[DateTime]::UtcNow
    $start=Start-TaskEvaluationSession -ProjectPath $Project -RunRoot $script:OutputFull -StatePath (Join-Path $script:StateRoot 'engine.json') -ProcessToken ('process-'+[guid]::NewGuid().ToString('N')) -EngineRoot $Engine -WindowWidth 1280 -WindowHeight 720 -TimeoutMs 60000 -FocusTimeoutMs 3000 -ObserverDisabledControl -AdditionalArguments @("-ActionRoguelikeStateRoot=$($script:StateRoot)","-ActionRoguelikeSnapshotPath=$($script:SnapshotPath)","-ActionRoguelikeEventsPath=$($script:EventsPath)","-AREvaluationFixture=$($script:FixtureChannel)",'-Windowed','-ResX=1280','-ResY=720','-ForceRes')
    [void](Save-Receipt $start 'reopen-new-start')
    $start.operation='Reopen'
    $start.result|Add-Member -NotePropertyName old_process_id -NotePropertyValue $oldProcess -Force
    $start.result|Add-Member -NotePropertyName old_process_token -NotePropertyValue $oldToken -Force
    $start.result|Add-Member -NotePropertyName normal_old_stop_confirmed -NotePropertyValue $true -Force
    return $start
}
function Read-TaskState([int]$TimeoutMilliseconds=500,[switch]$RequireNewSample,[switch]$AllowRoundReset) {
    $read=Resolve-ActionRoguelikeStatePair -RunRoot $script:OutputFull `
        -SnapshotSchemaPath $script:SnapshotSchemaPath -EventsSchemaPath $script:EventsSchemaPath `
        -ExpectedProcessToken $script:ProcessToken -ExpectedProcessId $script:ProcessId `
        -PreferredSnapshotPath $script:SnapshotPath -PreferredEventsPath $script:EventsPath `
        -ReaderContext $script:StateReaderContext -RequireNewSample:$RequireNewSample -AllowEmptyEventBatchCompatibility -AllowRoundSequenceResetCompatibility:$AllowRoundReset `
        -TimeoutMilliseconds $TimeoutMilliseconds -PollMilliseconds 40 -SessionStartedUtc $script:SessionStartedUtc
    $script:LastStateReadDiagnostic=$read.diagnostic
    if($read.success){
        if(-not(Get-Variable -Name ARSampleHostTimes -Scope Script -ErrorAction SilentlyContinue)){$script:ARSampleHostTimes=@{}}
        $publicationAge=Get-ActionRoguelikePropertyValue $read.diagnostic 'publication_age_ms'
        $script:ARSampleHostTimes[[string]$read.snapshot.identity.snapshot_id]=[Environment]::TickCount64-[long]$publicationAge
        $script:SnapshotPath=[string]$read.snapshot_path;$script:EventsPath=[string]$read.events_path
        return [pscustomobject]@{snapshot=$read.snapshot;events=$read.events;validation=$read.validation;diagnostic=$read.diagnostic;snapshot_path=$read.snapshot_path;events_path=$read.events_path;path_source=$read.path_source;independent_transport=(Get-ActionRoguelikePropertyValue $read 'independent_transport')}
    }
    return $null
}
function Save-StateProviderReceipt($Pair,[string]$Name){
    $valid=$null-ne$Pair
    $receipt=[ordered]@{schema_version='1.1.0';valid=$valid;identity_binding=$(if($valid){[string]$Pair.validation.identity_binding}else{$null});snapshot_schema='1.0.0';events_schema='2.0.0';snapshot_path=$(if($valid){Get-Relative ([string]$Pair.snapshot_path)}else{$null});events_path=$(if($valid){Get-Relative ([string]$Pair.events_path)}else{$null});path_source=$(if($valid){[string]$Pair.path_source}else{$null});transport_root=Get-Relative $script:StateRoot;diagnostic=$(if($valid){$Pair.diagnostic}else{$script:LastStateReadDiagnostic})}
    Save-Receipt $receipt "state-provider-$Name"
}
function Get-StateEvidencePath {
    if($script:SnapshotPath -and (Test-Path -LiteralPath $script:SnapshotPath -PathType Leaf)) { return Get-Relative $script:SnapshotPath }
    return 'receipts/state-provider-initial.json'
}
function Get-ControlActivation($Snapshot,[string]$SemanticAction){
    foreach($control in @(Get-ActionRoguelikePropertyValue $Snapshot 'controls')){
        $semantic=[string](Get-ActionRoguelikePropertyValue $control 'semantic_action')
        if($semantic -cne $SemanticAction){continue}
        $activation=Get-ActionRoguelikePropertyValue $control 'activation'
        if($null -eq $activation){return $null}
        $kind=[string](Get-ActionRoguelikePropertyValue $activation 'kind')
        if($kind -ceq 'keyboard'){
            $key=[string](Get-ActionRoguelikePropertyValue $activation 'physical_control')
            if($key-ceq'SpaceBar'){$key='Space'}
            if([string]::IsNullOrWhiteSpace($key)){return $null}
            if($key -in @('LeftMouseButton','RightMouseButton','MiddleMouseButton')){
                return [pscustomobject]@{semantic_action=$SemanticAction;kind='mouse';key=$null;button=$key.Replace('MouseButton','')}
            }
            return [pscustomobject]@{semantic_action=$SemanticAction;kind='keyboard';key=$key;button=$null}
        }
        if($kind -ceq 'mouse'){
            $button=[string](Get-ActionRoguelikePropertyValue $activation 'mouse_button')
            if($button -notin @('left','right','middle')){return $null}
            return [pscustomobject]@{semantic_action=$SemanticAction;kind='mouse';key=$null;button=$button.Substring(0,1).ToUpperInvariant()+$button.Substring(1)}
        }
        return $null
    }
    return $null
}
function Invoke-ControlActivation($Activation,[string]$Name,[int]$DurationMs=55){
    if($null -eq $Activation){return $false}
    if($Activation.kind -ceq 'keyboard'){return (Invoke-Press ([string]$Activation.key) $Name $DurationMs)}
    if($Activation.kind -eq 'mouse'){
        $down=$null
        $up=$null
        try{
            $down=Start-UnrealMouseHold -Session $script:Session -Button ([string]$Activation.button);[void](Save-Receipt $down "$Name-mousedown")
            if($down.status -ne 'ok'){return $false}
            Start-Sleep -Milliseconds $DurationMs
            return $true
        }finally{
            try{$up=Stop-UnrealMouseHold -Session $script:Session -Button ([string]$Activation.button);[void](Save-Receipt $up "$Name-mouseup")}catch{}
            [void](Save-Receipt ([ordered]@{operation='published_mouse_control';activation=$Activation;down=$down;up=$up;input_dispatched=($null-ne$down-and$down.status-eq'ok');release_verified=($null-ne$up-and$up.status-eq'ok')}) $Name)
        }
    }
    return $false
}
function Get-ControlActivations($Snapshot,[string[]]$SemanticActions){
    foreach($semantic in $SemanticActions){$activation=Get-ControlActivation $Snapshot $semantic;if($activation){$activation}}
}
function Wait-CanonicalCapture([string]$Name,[int]$TimeoutSeconds=30){
    $watch=[Diagnostics.Stopwatch]::StartNew();$attempt=0;$consecutive=0;$samples=@()
    do{
        ++$attempt;$label="$Name-ready-$attempt";$capture=Save-CanonicalCapture $label
        $samples+=@{attempt=$attempt;visible=([bool]$capture);capture=$capture;elapsed_seconds=$watch.Elapsed.TotalSeconds}
        if($capture){++$consecutive}else{$consecutive=0}
        if($consecutive-ge2){
            foreach($relative in @("captures/$label.png","captures/raw/$label.png","receipts/capture-$label.json","receipts/capture-$label-normalization.json")){
                $target=$relative.Replace($label,$Name)
                [IO.File]::Copy((Join-Path $script:OutputFull $relative),(Join-Path $script:OutputFull $target),$true)
            }
            [void](Save-Receipt @{condition='two_consecutive_visible_client_frames';timeout_seconds=$TimeoutSeconds;samples=$samples;success=$true} "$Name-readiness")
            return "captures/$Name.png"
        }
        Start-Sleep -Milliseconds 250
    }while($watch.Elapsed.TotalSeconds-lt$TimeoutSeconds)
    [void](Save-Receipt @{condition='two_consecutive_visible_client_frames';timeout_seconds=$TimeoutSeconds;samples=$samples;success=$false} "$Name-readiness")
    return $null
}
function Wait-TaskState([scriptblock]$Condition,[double]$TimeoutSeconds,[string]$SaveAs,[int]$StableSamples=1,[switch]$AllowRoundReset){
    $watch=[Diagnostics.Stopwatch]::StartNew();$samples=[Collections.Generic.List[object]]::new()
    $label=if($SaveAs){$SaveAs}else{'wait-'+[guid]::NewGuid().ToString('N')}
    $lastIdentity='';$consecutive=0;$accepted=$null
    do {
        $remaining=[Math]::Max(1,[int](1000*$TimeoutSeconds-$watch.Elapsed.TotalMilliseconds))
        $readArguments=@{TimeoutMilliseconds=([Math]::Min(500,$remaining));RequireNewSample=$true}
        if($AllowRoundReset){$readArguments.AllowRoundReset=$true}
        $pair=Read-TaskState @readArguments
        $entry=[ordered]@{elapsed_ms=[Math]::Round($watch.Elapsed.TotalMilliseconds,3);valid=($null-ne$pair);matches=$false;distinct=$false;snapshot=$null;events=$null;diagnostic=$script:LastStateReadDiagnostic}
        if($pair){
            $identity=[string](Get-ActionRoguelikePathValue $pair.snapshot 'identity.process_token')+'|'+[string](Get-ActionRoguelikePathValue $pair.snapshot 'identity.round_id')+'|'+[string](Get-ActionRoguelikePathValue $pair.snapshot 'identity.snapshot_id')
            $entry.distinct=$identity-cne$lastIdentity;$lastIdentity=$identity
            $entry.matches=[bool](& $Condition $pair.snapshot $pair.events)
            if($entry.distinct){
                $sampleName='observations/'+$label+'/sample-'+$samples.Count.ToString('D4')
                $entry.snapshot=Save-State $pair.snapshot $sampleName
                $entry.events=Save-State $pair.events ($sampleName+'-events')
                if($entry.matches){$consecutive++}else{$consecutive=0}
            }
            if($entry.matches-and$consecutive-ge$StableSamples){$accepted=$pair}
        }else{$consecutive=0}
        $samples.Add([pscustomobject]$entry)
        if($accepted-or$watch.Elapsed.TotalSeconds-ge$TimeoutSeconds){break}
        Start-Sleep -Milliseconds ([Math]::Min(40,[Math]::Max(1,[int](1000*$TimeoutSeconds-$watch.Elapsed.TotalMilliseconds))))
    }while($watch.Elapsed.TotalSeconds-lt$TimeoutSeconds)
    [void](Save-Receipt ([ordered]@{success=($null-ne$accepted);timeout_seconds=$TimeoutSeconds;required_distinct_samples=$StableSamples;elapsed_ms=[Math]::Round($watch.Elapsed.TotalMilliseconds,3);samples=@($samples)}) ('wait-'+$label))
    if($accepted-and$SaveAs){[void](Save-State $accepted.snapshot $SaveAs);[void](Save-State $accepted.events ($SaveAs+'-events'))}
    $lastReason=Get-ActionRoguelikePropertyValue $script:LastStateReadDiagnostic 'last_reason_code'
    # A final truncated poll may have only a few milliseconds left. It cannot
    # erase the preceding fresh, validated nonmatching samples and relabel a
    # normal condition timeout as evaluator backlog. A real journal backlog, or
    # an entire window without recent valid samples, still invalidates the run.
    $healthyTail=$lastReason-ceq'state_read_budget_exhausted'-and
        (Get-ActionRoguelikePropertyValue $script:LastStateReadDiagnostic 'timeout_ms')-lt500-and
        @($samples|Where-Object{$_.valid-and$_.distinct-and$_.elapsed_ms-ge(1000*$TimeoutSeconds-500)}).Count-gt0
    if(-not$accepted-and$lastReason-in@('state_history_pending','state_read_budget_exhausted')-and-not$healthyTail){throw 'run_invalid|STATE_READER_BACKLOG|The evaluator could not validate the live journal within the condition budget.'}
    return $accepted
}
function Invoke-Press([string]$Key,[string]$Name,[int]$DurationMs=55){$r=Invoke-UnrealPressKey -Session $script:Session -Key $Key -DurationMs $DurationMs;[void](Save-Receipt $r $Name);return ($r.status-eq'ok')}
function Invoke-HoldSample([string[]]$Keys,[int]$Milliseconds,[string]$Name){$started=[Collections.Generic.List[string]]::new();try{foreach($key in $Keys){$r=Start-UnrealKeyHold -Session $script:Session -Key $key;[void](Save-Receipt $r "$Name-start-$key");if($r.status-ne'ok'){return $null};$started.Add($key)};Start-Sleep -Milliseconds $Milliseconds;Read-TaskState -TimeoutMilliseconds 2000 -RequireNewSample}finally{foreach($key in @($started)){try{$r=Stop-UnrealKeyHold -Session $script:Session -Key $key;[void](Save-Receipt $r "$Name-stop-$key")}catch{}}}}

function Get-CanonicalEventChain {
    param([object[]]$Pairs=@())
    Get-ActionRoguelikeEventCoverage -Pairs $Pairs
}

function New-CanonicalAtomicTrace {
    param([Parameter(Mandatory)][string]$Variant,[object[]]$Pairs=@(),[string[]]$Actions=@(),[string[]]$Captures=@())
    $valid=@($Pairs|Where-Object{$_ -and $_.snapshot -and $_.events})
    if($valid.Count-lt2){return $null}
    $chain=Get-CanonicalEventChain $valid
    $reason=if($chain.complete){'ATOMIC_TRACE_NOT_ISOLATED'}else{$chain.reason_codes[0]}
    $detail=if($chain.complete){'Shared smoke samples do not establish an independent variant setup, trigger, and cleanup.'}else{'Shared smoke event coverage is unavailable: '+($chain.reason_codes -join ', ')}
    # Preserve real observations without manufacturing input timestamps,
    # successful setup, capture provenance, or a process-stop receipt.
    $receipt=Save-Receipt ([ordered]@{variant_id=$Variant;scope='shared_smoke_diagnostic';event_chain=$chain;samples=$valid;requested_actions=$Actions;evidence_paths=$Captures;reason_code=$reason}) ('atomic-observations-'+$Variant)
    return [ordered]@{variant_id=$Variant;event_chain=$chain;execution=[ordered]@{status='evaluator_blocked';attribution='evaluator';reason_code=$reason;detail=$detail;evidence_paths=@($receipt)}}
}

$scriptRoot=Split-Path -Parent $PSCommandPath;$evaluatorRoot=[IO.Path]::GetFullPath((Join-Path $scriptRoot '..'));$script:TaskRoot=[IO.Path]::GetFullPath((Join-Path $evaluatorRoot '..'));$repositoryRoot=[IO.Path]::GetFullPath((Join-Path $script:TaskRoot '..\..'))
$CandidateFull=[IO.Path]::GetFullPath($CandidateProject);$EngineFull=[IO.Path]::GetFullPath($EngineRoot);$script:OutputFull=Assert-ActionRoguelikeBindingPath -Path $OutputDirectory
if(Test-Path $script:OutputFull){if(@(Get-ChildItem $script:OutputFull -Force).Count-gt0){throw 'OutputDirectory must be absent or empty.'}};New-Item -ItemType Directory -Path $script:OutputFull -Force|Out-Null
$taskManifestPath=Join-Path $script:TaskRoot 'input/BENCHMARK_MANIFEST.json';$taskManifest=Read-Json $taskManifestPath
if($null-eq$taskManifest){throw 'The public benchmark manifest could not be read.'}
$catalog=Get-Content -Raw (Join-Path $evaluatorRoot 'catalog/checkpoints.json') -Encoding UTF8|ConvertFrom-Json -Depth 100
$script:Verdicts=@($catalog.checkpoints|ForEach-Object{[pscustomobject][ordered]@{checkpoint_id=[string]$_.id;dimension=[string]$_.dimension;verdict=$null;detail='';reason_code=$null;attribution=$null;first_failure=$null;score_impact=$null;evidence=@()}});$script:VerdictsById=@{};foreach($v in $script:Verdicts){$script:VerdictsById[$v.checkpoint_id]=$v}
$candidateBinding=Resolve-ActionRoguelikeCandidateBinding -CandidateProject $CandidateFull
if($candidateBinding.success){$CandidateFull=[IO.Path]::GetFullPath([string]$candidateBinding.project_file)}
$projectRoot=if($candidateBinding.project_root){[IO.Path]::GetFullPath([string]$candidateBinding.project_root)}else{Split-Path -Parent $CandidateFull}
$candidateIdentity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($CandidateFull))).ToLowerInvariant()
if($candidateBinding.success){try{$candidateIdentity=Get-ProjectIdentity $projectRoot}catch{$candidateBinding.success=$false;$candidateBinding.reason_code='CANDIDATE_PROJECT_BINDING_INVALID';$candidateBinding.detail=$_.Exception.Message}}
if(-not$CandidateId){$CandidateId='candidate-'+$candidateIdentity.Substring(0,16)}
$manifest=[ordered]@{schema_version='1.1.0';candidate_id=$CandidateId;candidate_identity_sha256=$candidateIdentity;project_file=$(if($candidateBinding.project_file){[IO.Path]::GetFileName([string]$candidateBinding.project_file)}else{$null});project_root_name=[IO.Path]::GetFileName($projectRoot);candidate_input_manifest=$(if($candidateBinding.manifest_path){Get-Relative ([string]$candidateBinding.manifest_path)}else{$null});declared_project_root=$(if($candidateBinding.manifest){[string](Get-ActionRoguelikeBindingProperty (Get-ActionRoguelikeBindingProperty $candidateBinding.manifest 'paths') 'project_root')}else{$null});declared_project_file=$(if($candidateBinding.manifest){[string](Get-ActionRoguelikeBindingProperty (Get-ActionRoguelikeBindingProperty $candidateBinding.manifest 'paths') 'project_file')}else{$null});manifest_path_matches_candidate=$candidateBinding.manifest_path_matches_candidate;binding_source=$candidateBinding.source;binding_reason_code=$candidateBinding.reason_code;binding_detail=$candidateBinding.detail;generated_utc=[DateTime]::UtcNow.ToString('o')};Write-JsonFile $manifest (Join-Path $script:OutputFull 'candidate-manifest.json')
$transportId=[guid]::NewGuid().ToString('N');$script:StateRoot=Join-Path $script:OutputFull ("state/channel-$transportId");New-Item -ItemType Directory -Path $script:StateRoot -Force|Out-Null;$script:SnapshotPath=Join-Path $script:StateRoot ("snapshot-$transportId.json");$script:EventsPath=Join-Path $script:StateRoot ("events-$transportId.json");$engineStatePath=Join-Path $script:StateRoot ("engine-$transportId.json")
$schemaSnapshotRel=[string](Get-ActionRoguelikeBindingProperty $taskManifest.paths 'task_snapshot_schema');$schemaEventsRel=[string](Get-ActionRoguelikeBindingProperty $taskManifest.paths 'task_events_schema');$script:SnapshotSchemaPath=Resolve-ActionRoguelikeManifestPath -ManifestPath $taskManifestPath -RelativePath $schemaSnapshotRel;$script:EventsSchemaPath=Resolve-ActionRoguelikeManifestPath -ManifestPath $taskManifestPath -RelativePath $schemaEventsRel
$faults=[Collections.Generic.List[object]]::new();$warnings=[Collections.Generic.List[object]]::new();$script:Session=$null;$script:SessionActive=$false;$script:LastStateReadDiagnostic=$null;$script:StateReaderContext=$null;New-Item -ItemType Directory -Path (Split-Path -Parent $engineStatePath) -Force|Out-Null;$script:ProcessToken='';$script:ProcessId=0;$script:SessionStartedUtc=[DateTime]::MinValue;$started=[DateTime]::UtcNow;$providerHealthy=$false;$activeCapture=$null;$blackHoleCapture=$null;$terminalCapture=$null
try{
    $present=$candidateBinding.success-and(Test-Path $CandidateFull -PathType Leaf);$descriptor=$candidateBinding.descriptor;$engineVersion=[string](Get-ActionRoguelikeBindingProperty $taskManifest.engine 'version');$engineMajorMinor=if($engineVersion -match '^([0-9]+\.[0-9]+)'){$Matches[1]}else{$engineVersion}
    $targetBinding=if($present){Resolve-ActionRoguelikeEditorTarget -ProjectFile $CandidateFull -Descriptor $descriptor}else{[pscustomobject]@{success=$false;reason_code='CANDIDATE_PROJECT_MISSING';build_required=$true;target_name=$null}}
    $descriptorOk=$false;if($present-and$descriptor){try{$association=[string](Get-ActionRoguelikeBindingProperty $descriptor 'EngineAssociation');$modules=@(Get-ActionRoguelikeBindingProperty $descriptor 'Modules');$descriptorOk=($association -like "$engineMajorMinor*")-and($modules.Count-ge1-or(-not$targetBinding.build_required))}catch{}}
    Set-Checkpoint 'D1-01' $(if($descriptorOk){'pass'}else{'fail'}) 'The project descriptor, Unreal association, and runtime module declarations were checked.' @('candidate-manifest.json') $(if(-not$present){$candidateBinding.reason_code}else{'CANDIDATE_DESCRIPTOR_INVALID'}) 'candidate-manifest.json'
    $privacyOk=$true;if($present){foreach($file in Get-ChildItem $projectRoot -Recurse -File|Where-Object{$_.Extension-in'.cpp','.h','.cs','.ini','.uproject','.md','.json'-and$_.FullName-notmatch'[\\/](Binaries|Intermediate|Saved|DerivedDataCache)[\\/]'} ){if((Get-Content -Raw $file.FullName -ErrorAction SilentlyContinue)-match'(?i)[A-Z]:\\Users\\|client_secret\s*=|AKIA[A-Z0-9]{16}'){$privacyOk=$false;break}}}
    $targetName=[string]$targetBinding.target_name;$manifest.target_name=$targetName;$manifest.engine_version=$engineVersion;$manifest.target_binding=$targetBinding;Write-JsonFile $manifest (Join-Path $script:OutputFull 'candidate-manifest.json')
    $engineBinding=Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $EngineFull -Manifest $taskManifest
    $engineBindingReceipt=Save-Receipt $engineBinding 'engine-binding'
    if(-not$engineBinding.success){$faults.Add([pscustomobject][ordered]@{domain=$engineBinding.attribution;code=$engineBinding.reason_code;message='The exact evaluator engine/tool binding was not healthy.';diagnostic=$engineBinding.detail;evidence_paths=@($engineBindingReceipt)});throw 'evaluator_engine_binding_stop'}
    $buildOk=$false;$buildLog=Join-Path $script:OutputFull 'logs/build.log';New-Item -ItemType Directory -Path (Split-Path -Parent $buildLog) -Force|Out-Null;Write-JsonFile ([ordered]@{status='not_started';reason='build_not_requested_yet'}) $buildLog
    if(-not$present-or-not$descriptorOk-or-not$targetBinding.success){Set-Checkpoint 'D1-03' 'fail' 'The candidate project or its unambiguous Editor target was unavailable.' @('candidate-manifest.json') $(if(-not$present){$candidateBinding.reason_code}else{$targetBinding.reason_code}) 'candidate-manifest.json';throw 'candidate_static_stop'}
    if($targetBinding.build_required-and$SkipBuild){$buildOk=$true;Write-JsonFile ([ordered]@{status='skipped';reason='explicit_skip_build';target_name=$targetName}) $buildLog}elseif($targetBinding.build_required){& $engineBinding.build_tool $targetName Win64 Development $CandidateFull -WaitMutex -NoHotReloadFromIDE *> $buildLog;$buildOk=$LASTEXITCODE-eq0}else{$buildOk=$true;Write-JsonFile ([ordered]@{status='not_required';target_name='UnrealEditor';reason='content_only_project'}) $buildLog}
    Set-Checkpoint 'D1-03' $(if($buildOk){'pass'}else{'fail'}) 'The Unreal Development Editor build was executed or the content-only target was verified.' @('candidate-manifest.json',(Get-Relative $buildLog)) $(if($buildOk){$null}else{'CANDIDATE_BUILD_FAILED'}) $(if($buildOk){$null}else{Get-Relative $buildLog})
    if(-not$buildOk){throw 'candidate_static_stop'}
    $runtimeProject=$CandidateFull;$fixtureAvailable=$false
    $script:FixtureChannel=Join-Path $script:OutputFull 'fixture'
    New-Item -ItemType Directory -Path $script:FixtureChannel -Force|Out-Null
    if(-not$TransportHealthOnly){
        $stageRoot=Join-Path $script:OutputFull 'runtime/project'
        $python=Join-Path $EngineFull 'Engine/Binaries/ThirdParty/Python3/Win64/python.exe'
        $stageLog=Join-Path $script:OutputFull 'logs/fixture-stage.log'
        $stageArguments=@('--project',$CandidateFull,'--destination',$stageRoot)
        if($FixtureBindingsPath){$stageArguments+=@('--bindings',(Assert-ActionRoguelikeBindingPath -Path $FixtureBindingsPath))}
        & $python (Join-Path $scriptRoot 'stage_fixture.py') @stageArguments *> $stageLog
        if($LASTEXITCODE-eq0){
            $stageReceipt=Read-Json (Join-Path $script:OutputFull 'runtime/fixture-stage.json')
            $script:FixtureAdapterIdentity=[string]$stageReceipt.adapter_analysis.adapter_identity
            if($FixtureBindingsPath){
                $profile=@((Read-Json $FixtureBindingsPath).bindings|Where-Object id -CEQ $stageReceipt.binding_id)[0]
                $script:ARMetricBinding=Get-ActionRoguelikePropertyValue $profile 'observation_units'
                if($script:ARMetricBinding){[void](Save-Receipt @{adapter_identity=$script:FixtureAdapterIdentity;mapping=$script:ARMetricBinding;raw_publications_unchanged=$true;public_unit_contract_violation=$true} 'observation-units')}
            }
            if(-not$script:FixtureAdapterIdentity){throw 'Fixture staging omitted the candidate adapter identity.'}
            $runtimeProject=Join-Path $stageRoot ([IO.Path]::GetFileName($CandidateFull))
            $fixtureBuildLog=Join-Path $script:OutputFull 'logs/fixture-build.log'
            & $engineBinding.build_tool $targetName Win64 Development $runtimeProject -WaitMutex -NoHotReloadFromIDE *> $fixtureBuildLog
            if($LASTEXITCODE-ne0){$faults.Add([pscustomobject]@{domain='evaluator';code='FIXTURE_BUILD_FAILED';message='Private native instrumentation failed to build.';evidence_paths=@('logs/fixture-build.log')});throw 'evaluator_operation_stop'}
            $fixtureAvailable=$true
        }elseif((Get-Content -Raw $stageLog)-notmatch'FIXTURE_BINDING_UNAVAILABLE'){
            $faults.Add([pscustomobject]@{domain='evaluator';code='FIXTURE_STAGE_FAILED';message='Private native instrumentation could not be staged.';evidence_paths=@('logs/fixture-stage.log')});throw 'evaluator_operation_stop'
        }
    }
    Import-Module $engineBinding.executor_path -Force
    $token='actionroguelike-'+[guid]::NewGuid().ToString('N');$script:SessionStartedUtc=[DateTime]::UtcNow;$start=Start-TaskEvaluationSession -ProjectPath $runtimeProject -RunRoot $script:OutputFull -StatePath $engineStatePath -ProcessToken $token -EngineRoot $EngineFull -WindowWidth 1280 -WindowHeight 720 -TimeoutMs 60000 -FocusTimeoutMs 3000 -ObserverDisabledControl -AdditionalArguments @("-ActionRoguelikeStateRoot=$($script:StateRoot)","-ActionRoguelikeSnapshotPath=$($script:SnapshotPath)","-ActionRoguelikeEventsPath=$($script:EventsPath)","-AREvaluationFixture=$($script:FixtureChannel)",'-Windowed','-ResX=1280','-ResY=720','-ForceRes');[void](Save-Receipt $start 'start')
    Assert-ExecutorOperationHealth $start 'receipts/start.json'
    if($start.status-ne'ok'){Set-Checkpoint 'D1-02' 'fail' 'The public state pair could not be reached because the candidate failed to start.' @('receipts/start.json') 'CANDIDATE_START_FAILED' 'receipts/start.json';Set-Checkpoint 'D1-04' 'fail' 'The candidate did not establish a stable no-input game window.' @('receipts/start.json') 'CANDIDATE_START_FAILED' 'receipts/start.json';Set-Checkpoint 'D1-05' 'fail' 'Reopen was unavailable after start failure.' @('receipts/start.json') 'CANDIDATE_START_FAILED' 'receipts/start.json';Set-Unresolved 'fail' 'Runtime content and feedback were absent after candidate start failure.' @('D2','D5') 'CANDIDATE_START_FAILED' 'receipts/start.json';Set-Unresolved 'unreachable' 'Gameplay and lifecycle rules were unreachable after candidate start failure.' @('D3','D4') 'CANDIDATE_START_FAILED' 'receipts/start.json';throw 'candidate_start_stop'}
    $script:Session=$start.result.session;$script:SessionActive=$true;$script:ProcessToken=[string]$start.result.process_token;$script:ProcessId=[int]$start.result.process_id;Reset-StateReaderContext
    [void](Save-Receipt ([ordered]@{schema_version='1.0.0';channel_root=Get-Relative $script:StateRoot;snapshot_path=Get-Relative $script:SnapshotPath;events_path=Get-Relative $script:EventsPath;process_id=$script:ProcessId;process_token=$script:ProcessToken;session_started_utc=$script:SessionStartedUtc.ToString('o');reader_context_initialized=$true}) 'state-transport-start')
    $activeCapture=Wait-CanonicalCapture 'active-arena';Set-Checkpoint 'D1-04' $(if($activeCapture){'pass'}else{'fail'}) 'A no-input client frame was started, captured, decoded, and checked for visible content.' @('receipts/start.json',$activeCapture) $(if($activeCapture){$null}else{'CANDIDATE_START_FRAME_INVALID'}) $(if($activeCapture){$null}else{'receipts/capture-active-arena.json'})
    $initial=Wait-TaskState {param($s,$e)$true} 10 'initial';$providerHealthy=$null-ne$initial;$initialProviderReceipt=Save-StateProviderReceipt $initial 'initial'
    if(-not$providerHealthy-and$script:LastStateReadDiagnostic.last_reason_code-in@('state_history_pending','state_read_budget_exhausted')){throw 'run_invalid|STATE_READER_BACKLOG|The evaluator did not catch up with the live journal within its bootstrap budget.'}
    if($providerHealthy-and[string]$initial.validation.identity_binding-ceq'active_process_id'){$warnings.Add([pscustomobject][ordered]@{code='state_identity_active_process_compatibility';message='The state pair used the exact active process-ID identity instead of echoing the launcher nonce.';evidence_paths=@($initialProviderReceipt)})}
    $completeProvider=$providerHealthy-and(Get-ActionRoguelikePropertyValue $initial.diagnostic 'complete_snapshot_schema')-ne$false
    Set-Checkpoint 'D1-02' $(if($privacyOk-and$completeProvider){'pass'}else{'fail'}) 'Portability and the complete read-only schema were checked; malformed process records do not suppress independent valid state fields.' @('candidate-manifest.json',$initialProviderReceipt,$(if($providerHealthy){'states/initial.json'}else{'receipts/start.json'})) $(if(-not$privacyOk){'CANDIDATE_PRIVACY_OR_PORTABILITY_FAILURE'}else{'CANDIDATE_STATE_PROVIDER_INVALID'}) $(if(-not$privacyOk){'candidate-manifest.json'}else{Get-StateEvidencePath})
    if($TransportHealthOnly){
        $healthRounds=[Collections.Generic.List[object]]::new();$healthState=$initial
        if($providerHealthy){
            $healthRestart=Get-ControlActivation $initial.snapshot 'restart'
            for($roundAttempt=1;$roundAttempt-le2;$roundAttempt++){
                $oldHealthRound=[string]$healthState.snapshot.identity.round_id
                [void](Invoke-ControlActivation $healthRestart ('health-restart-'+$roundAttempt))
                $healthState=Wait-TaskState {param($s,$e)[string]$s.identity.round_id -cne $oldHealthRound} 6 ('health-round-'+$roundAttempt) -AllowRoundReset
                $healthRounds.Add([pscustomobject]@{attempt=$roundAttempt;success=($null-ne$healthState);previous_round=$oldHealthRound;new_round=$(if($healthState){[string]$healthState.snapshot.identity.round_id}else{$null})})
                if(-not$healthState){break}
            }
        }
        [void](Save-Receipt ([ordered]@{initial_provider_valid=$providerHealthy;round_transitions=@($healthRounds);scope='transport_health_only_no_gameplay_scores'}) 'transport-health')
    }elseif(-not$providerHealthy){
        Set-Unresolved 'fail' 'The candidate did not provide a schema-valid same-process state pair; dynamic content and visible semantic feedback could not be corroborated.' @('D2','D5') 'CANDIDATE_STATE_PROVIDER_INVALID' (Get-StateEvidencePath)
        Set-Unresolved 'unreachable' 'Detailed gameplay rules and lifecycle state transitions were unreachable because the required read-only provider was invalid.' @('D3','D4') 'CANDIDATE_STATE_PROVIDER_INVALID' (Get-StateEvidencePath)
        # No gameplay input is dispatched when the candidate cannot publish its
        # semantic controls. The public contract, rather than a private fallback
        # key, is the only source for undocumented ability bindings.
        # Preserve diagnostic pictures without labelling an unreached semantic
        # state as a D6 candidate capture. Those state slots remain missing/zero.
        $blackHoleCapture=Save-CanonicalCapture 'unreachable-black-hole-combat'
        $terminalCapture=Save-CanonicalCapture 'unreachable-terminal-result'
    }else{
        if(-not$fixtureAvailable){$faults.Add([pscustomobject]@{domain='evaluator';code='FIXTURE_BINDING_UNAVAILABLE';message='A healthy candidate needs an audited native precondition binding.';evidence_paths=@('logs/fixture-stage.log')});throw 'evaluator_operation_stop'}
        $smokeProtection=Invoke-ARFixture @{invulnerable=$true;capture_pointer=$true} 'smoke-protection'
        Assert-ARMetricCorroboration $initial.snapshot $smokeProtection.response
        if($script:ARMetricBinding){Set-Checkpoint 'D1-02' 'fail' 'The publisher labels Unreal centimeter positions and velocities as meters. A source-bound metric view, corroborated against native world position, allows independent gameplay evaluation; raw evidence is preserved.' @('receipts/observation-units.json','receipts/fixture-smoke-protection.json','states/initial.json') 'CANDIDATE_OBSERVATION_UNIT_MISMATCH' 'receipts/observation-units.json'}
        $s0=$initial.snapshot;$primaryBinding=Get-ControlActivation $s0 'primary_attack';$blackHoleBinding=Get-ControlActivation $s0 'black_hole';$teleportBinding=Get-ControlActivation $s0 'teleport';$restartBinding=Get-ControlActivation $s0 'restart';$p0=Get-ObservedPath $s0 'player.position_m';$normal=Invoke-HoldSample @('W') 550 'move-forward';$p1=if($normal){Get-ObservedPath $normal.snapshot 'player.position_m'}else{$null};$moveDistance=Get-VectorDistance $p0 $p1;$releaseHostMs=[Environment]::TickCount64;$stopped=Wait-TaskState {param($s,$e)$script:ARSampleHostTimes[[string]$s.identity.snapshot_id]-gt$releaseHostMs-and(Get-ActionRoguelikeVectorMagnitude (Get-ObservedPath $s 'player.velocity_mps'))-lt1.0} 2 'stopped';$stoppedSpeed=if($stopped){$speed=Get-ActionRoguelikeVectorMagnitude (Get-ObservedPath $stopped.snapshot 'player.velocity_mps');if($null-ne$speed){$speed}else{999}}else{999}
        [void](Invoke-ControlActivation (Get-ControlActivation $s0 'jump') 'jump');$air=Wait-TaskState {param($s,$e)(Get-ObservedPath $s 'player.ground_state')-eq'airborne'} 2 'airborne';if($air){[void](Invoke-ControlActivation (Get-ControlActivation $s0 'jump') 'jump-repeat-air')};$land=Wait-TaskState {param($s,$e)(Get-ObservedPath $s 'player.ground_state')-eq'grounded'} 3 'landed'
        $baseSpeed=if($normal){$speed=Get-ActionRoguelikeVectorMagnitude (Get-ObservedPath $normal.snapshot 'player.velocity_mps');if($null-ne$speed){$speed}else{0}}else{0};$sprint=Invoke-HoldSample @('W','LeftShift') 550 'sprint';$sprintSpeed=if($sprint){$speed=Get-ActionRoguelikeVectorMagnitude (Get-ObservedPath $sprint.snapshot 'player.velocity_mps');if($null-ne$speed){$speed}else{0}}else{0};$controlCapture=Save-CanonicalCapture 'control-after-input'
        if($normal){[void](Save-State $normal.snapshot 'normal-movement')};if($stopped){[void](Save-State $stopped.snapshot 'stopped')};if($sprint){[void](Save-State $sprint.snapshot 'sprint')};$playerAsset=[string](Get-ObservedPath $s0 'player.asset_semantic');$movementOk=$moveDistance-gt0.1-and$stoppedSpeed-lt1.0;$jumpOk=$air-and$land;$sprintOk=$sprintSpeed-gt[Math]::Max(0.5,$baseSpeed*1.1)
        [void](Save-Receipt @{move_distance_m=$moveDistance;stopped_speed_mps=$stoppedSpeed;normal_speed_mps=$baseSpeed;sprint_speed_mps=$sprintSpeed;jump_airborne=[bool]$air;jump_landed=[bool]$land;movement_ok=[bool]$movementOk;jump_ok=[bool]$jumpOk;sprint_ok=[bool]$sprintOk;player_asset_semantic=$playerAsset} 'control-observation');Set-Checkpoint 'D2-01' $(if($movementOk){'pass'}else{'fail'}) "Normal input moved the controlled player by $([Math]::Round($moveDistance,2)) m and stopped after release." @('states/initial.json','receipts/move-forward-start-W.json','receipts/move-forward-stop-W.json')
        Set-Checkpoint 'D2-02' $(if($jumpOk-and$sprintOk){'pass'}else{'fail'}) 'Jump and sprint were exercised through normal input.' @('states/airborne.json','states/landed.json')
        Set-Checkpoint 'D2-03' $(if($playerAsset-and$controlCapture){'pass'}else{'fail'}) 'A player asset role and input-driven presentation were captured.' @('states/initial.json',$controlCapture)
        Set-Checkpoint 'D3-01' $(if($movementOk){'pass'}else{'fail'}) 'Movement causality and stop-after-release were checked.' @('states/initial.json')
        Set-Checkpoint 'D3-02' $(if($jumpOk-and$sprintOk){'pass'}else{'fail'}) 'Ground-air-ground and higher-speed sprint transitions were checked.' @('states/airborne.json','states/landed.json')
        Set-Checkpoint 'D5-01' $(if($activeCapture-and$controlCapture){'pass'}else{'fail'}) 'The controlled character and initial player feedback remained visibly rendered.' @($activeCapture,$controlCapture)
        [void](Invoke-ControlActivation $primaryBinding 'primary-attack');Start-Sleep -Milliseconds 180;$primaryCapture=Save-CanonicalCapture 'primary-attack';$primaryPair=Read-TaskState;[void](Invoke-ControlActivation $blackHoleBinding 'black-hole');Start-Sleep -Milliseconds 350;$blackHoleCapture=Save-CanonicalCapture 'black-hole-combat';$blackPair=Read-TaskState;$beforeTeleport=Read-TaskState;[void](Invoke-ControlActivation $teleportBinding 'teleport-before-pickup');Start-Sleep -Milliseconds 250;$afterTeleport=Read-TaskState
        $primaryVisible=$primaryCapture-and$activeCapture-and(Measure-CaptureDifference (Join-Path $script:OutputFull $activeCapture) (Join-Path $script:OutputFull $primaryCapture))-gt1.0;$blackVisible=$blackHoleCapture-and$activeCapture-and(Measure-CaptureDifference (Join-Path $script:OutputFull $activeCapture) (Join-Path $script:OutputFull $blackHoleCapture))-gt1.0
        $types=@(@(Get-ActionRoguelikePropertyValue $s0 'objects')|ForEach-Object{[string](Get-ObservedValue (Get-ActionRoguelikePropertyValue $_ 'object_type'))});$requiredObjects=@('credits_pickup','potion','teleport_pickup','physics_prop');$objectsOk=@($requiredObjects|Where-Object{$_-notin$types}).Count-eq0;$teleportLocked=$true;if($beforeTeleport-and$afterTeleport){$teleportLocked=(Get-VectorDistance (Get-ObservedPath $beforeTeleport.snapshot 'player.position_m') (Get-ObservedPath $afterTeleport.snapshot 'player.position_m'))-lt0.25}
        Set-Checkpoint 'D2-05' $(if($objectsOk-and$primaryVisible-and$blackVisible){'pass'}else{'fail'}) 'Required object categories and visible ability processes were sampled.' @('states/initial.json',$primaryCapture,$blackHoleCapture)
        Set-Checkpoint 'D2-06' $(if($primaryVisible){'pass'}else{'fail'}) 'Primary Attack produced a distinct visible runtime frame.' @($primaryCapture,'receipts/primary-attack.json')
        Set-Checkpoint 'D2-07' $(if($blackVisible){'pass'}else{'fail'}) 'Black Hole input produced a distinct visible runtime frame.' @($blackHoleCapture,'receipts/black-hole.json')
        Set-Checkpoint 'D5-02' $(if($primaryVisible-and$blackVisible){'pass'}else{'fail'}) 'Primary Attack and Black Hole feedback were compared with the active frame.' @($primaryCapture,$blackHoleCapture)
        $aiBefore=Wait-TaskState {param($s,$e)$true} 3 'ai-before'
        if(-not$aiBefore){throw 'run_invalid|STATE_READER_BACKLOG|AI preconditions need a current snapshot.'}
        $damagePosition=$null
        foreach($enemy in @(Get-ActionRoguelikePropertyValue $aiBefore.snapshot 'enemies')){
            $position=Get-ObservedPath $enemy 'position_m'
            if($position-and$null-notin@((Get-ActionRoguelikePropertyValue $position 'x'),(Get-ActionRoguelikePropertyValue $position 'y'),(Get-ActionRoguelikePropertyValue $position 'z'))){$damagePosition=$position;break}
        }
        if($damagePosition){$null=Invoke-ARFixture @{health=100;invulnerable=$false;near_position_m=$damagePosition;distance_m=1.6} 'ai-damage-window'}
        else{[void](Save-Receipt @{attribution='candidate';reason_code='CANDIDATE_ENEMY_POSITION_UNAVAILABLE';detail='No observed enemy position; the AI damage prerequisite cannot be established.'} 'ai-damage-prerequisite')}
        $initialHealth=[double](Get-ObservedPath $s0 'player.health');$initialMax=[double](Get-ObservedPath $s0 'player.health_max');$enemySamples=[Collections.Generic.List[object]]::new();$enemyPairs=[Collections.Generic.List[object]]::new();for($i=0;$i-lt40;++$i){$pair=Read-TaskState;if($pair){$enemySamples.Add($pair.snapshot);$enemyPairs.Add($pair);if([double](Get-ObservedPath $pair.snapshot 'player.health')-lt$initialHealth){$null=Invoke-ARFixture @{invulnerable=$true} ('ai-hit-protection-'+$i)}};Start-Sleep -Milliseconds 250};$modes=@($enemySamples|ForEach-Object{@(Get-ActionRoguelikePropertyValue $_ 'enemies')}|ForEach-Object{Get-ObservedValue (Get-ActionRoguelikePropertyValue $_ 'ai_mode')}|Where-Object{$null-ne$_}|Sort-Object -Unique);$anyDamage=@($enemySamples|Where-Object{[double](Get-ObservedPath $_ 'player.health')-lt$initialHealth}).Count-gt0;$enemyCount=@(Get-ActionRoguelikePropertyValue $s0 'enemies').Count
        $null=Invoke-ARFixture @{health=100;invulnerable=$true} 'after-ai-protection'
        Set-Checkpoint 'D2-04' $(if($enemyCount-gt0){'pass'}else{'fail'}) 'Runtime enemy characters were present in the public state.' @('states/initial.json')
        Set-Checkpoint 'D2-09' $(if($initialMax-gt0-and$enemyCount-gt0){'pass'}else{'fail'}) 'Player and enemy health content was present; damage was sampled when it occurred.' @('states/initial.json')
        Set-Checkpoint 'D2-11' $(if('melee'-in$modes-and'ranged'-in$modes){'pass'}else{'fail'}) 'Enemy mode samples were collected over a bounded ten-second window.' @('states/initial.json')
        Set-Checkpoint 'D3-06' $(if($initialHealth-ge0-and$initialMax-gt0-and$initialHealth-le$initialMax){'pass'}else{'fail'}) 'Initial player health invariants were checked.' @('states/initial.json')
        Set-Checkpoint 'D3-08' $(if('melee'-in$modes-and'ranged'-in$modes-and$anyDamage){'pass'}else{'fail'}) 'Dual AI modes and a player-health transition were required in the bounded sample.' @('states/initial.json')
        [void](Save-State @($enemySamples) 'enemy-samples');$aiCapture=Save-CanonicalCapture 'ai-and-resources';Set-Checkpoint 'D5-03' $(if($aiCapture-and$objectsOk){'pass'}else{'fail'}) 'Enemy/object presentation and a contemporaneous client frame were preserved.' @('states/initial.json',$aiCapture)
        $null=Invoke-ARFixture @{remaining_seconds=0;invulnerable=$true} 'smoke-expire-countdown'
        $terminalPair=$null;$maxTime=0.0;$maxRefresh=0;$maxEnemies=$enemyCount;$watch=[Diagnostics.Stopwatch]::StartNew();do{$pair=Read-TaskState;if($pair){$time=[double](Get-ObservedPath $pair.snapshot 'world.survival_time_seconds');$refresh=[int](Get-ObservedPath $pair.snapshot 'world.refresh_opportunities');$alive=[int](Get-ObservedPath $pair.snapshot 'world.alive_enemy_count');$maxTime=[Math]::Max($maxTime,$time);$maxRefresh=[Math]::Max($maxRefresh,$refresh);$maxEnemies=[Math]::Max($maxEnemies,$alive);$phase=[string](Get-ObservedPath $pair.snapshot 'world.round_phase');if($phase-in@('victory','failure')){$terminalPair=$pair;break}};Start-Sleep -Milliseconds 200}while($watch.Elapsed.TotalSeconds-lt$TerminalTimeoutSeconds)
        if($terminalPair){[void](Save-State $terminalPair.snapshot 'terminal')};$terminalCapture=Save-CanonicalCapture 'terminal-result';$terminalPhase=if($terminalPair){[string](Get-ObservedPath $terminalPair.snapshot 'world.round_phase')}else{''};$fingerprint=if($terminalPair){"$terminalPhase|$([double](Get-ObservedPath $terminalPair.snapshot 'player.health'))|$([double](Get-ObservedPath $terminalPair.snapshot 'world.survival_time_seconds'))"}else{''};foreach($activation in @(Get-ControlActivations $s0 @('primary_attack','black_hole','teleport','interact'))){[void](Invoke-ControlActivation $activation "terminal-lock-$($activation.semantic_action)")};Start-Sleep -Milliseconds 400;$afterTerminal=Wait-TaskState {param($s,$e)$true} 3 'terminal-after-inputs';$afterFingerprint=if($afterTerminal){"$([string](Get-ObservedPath $afterTerminal.snapshot 'world.round_phase'))|$([double](Get-ObservedPath $afterTerminal.snapshot 'player.health'))|$([double](Get-ObservedPath $afterTerminal.snapshot 'world.survival_time_seconds'))"}else{''};$terminalLocked=$fingerprint-and$afterFingerprint-eq$fingerprint;[void](Save-Receipt @{before=$fingerprint;after=$afterFingerprint;locked=[bool]$terminalLocked} 'terminal-lock-observation')
        Set-Checkpoint 'D2-12' $(if($maxTime-ge55-and$maxRefresh-ge5){'pass'}else{'fail'}) "Observed survival progress reached $([Math]::Round($maxTime,1)) seconds and $maxRefresh refresh opportunities." @('states/terminal.json')
        $uiRoles=@(Get-ActionRoguelikeUiRoles $s0 $script:StateReaderContext);$uiCount=$uiRoles.Count
        $uiReceipt=Save-Receipt @{identity=$s0.identity;visible_roles=$uiRoles;source='schema_valid_snapshot_or_verified_same_round_ui_history'} 'ui-observation'
        Set-Checkpoint 'D2-14' $(if($uiCount-ge5){'pass'}else{'fail'}) 'Five synchronized UI roles were required in the public observations.' @('states/initial.json',$uiReceipt)
        Set-Checkpoint 'D3-09' $(if($maxTime-ge55-and$maxRefresh-ge5-and$maxEnemies-gt$enemyCount){'pass'}else{'fail'}) 'Survival deadline was injected; the natural tick and refresh response were observed.' @('states/terminal.json')
        Set-Checkpoint 'D3-10' $(if($terminalPair-and$terminalLocked){'pass'}else{'fail'}) 'Terminal arbitration and post-terminal input lock were checked.' @('states/terminal.json')
        Set-Checkpoint 'D5-04' $(if($uiCount-ge5-and$activeCapture-and$terminalCapture){'pass'}else{'fail'}) 'HUD roles and active/terminal captures were checked for synchronization evidence.' @('states/initial.json',$activeCapture,$terminalCapture)
        Set-Checkpoint 'D5-05' $(if($terminalPair-and$terminalCapture-and$terminalLocked){'pass'}else{'fail'}) 'Terminal feedback and post-terminal stability were checked.' @('states/terminal.json',$terminalCapture)
         $beforeRestart=$terminalPair;if(-not$beforeRestart){$beforeRestart=Read-TaskState};$oldRound=if($beforeRestart){[string](Get-ActionRoguelikePathValue $beforeRestart.snapshot 'identity.round_id')}else{''};[void](Invoke-ControlActivation $restartBinding 'restart-1');$restart1=Wait-TaskState {param($s,$e)[string](Get-ActionRoguelikePathValue $s 'identity.round_id')-cne$oldRound} 6 'restart-1' -AllowRoundReset;$restart1After=$null;if($restart1){Start-Sleep -Milliseconds 250;$restart1After=Read-TaskState};$round1=if($restart1){[string](Get-ActionRoguelikePathValue $restart1.snapshot 'identity.round_id')}else{''};[void](Invoke-ControlActivation $restartBinding 'restart-2');$restart2=Wait-TaskState {param($s,$e)[string](Get-ActionRoguelikePathValue $s 'identity.round_id')-cne$round1} 6 'restart-2' -AllowRoundReset;$restartOk=$restart1-and$restart2
        Set-Checkpoint 'D4-03' $(if($restartOk){'pass'}else{'fail'}) 'Public Restart established a new playable round identity.' @('states/restart-1.json')
        Set-Checkpoint 'D4-04' $(if($restartOk){'pass'}else{'fail'}) 'Consecutive Restart established another clean identity without reusing the prior round.' @('states/restart-1.json','states/restart-2.json')
        Set-Checkpoint 'D2-15' $(if($restartOk){'pass'}else{'fail'}) 'Restart content was dynamically exercised; true Reopen is completed below.' @('states/restart-1.json','states/restart-2.json')

    }
    $oldPid=$script:ProcessId;$oldToken=$script:ProcessToken;$script:SessionStartedUtc=[DateTime]::UtcNow
    $reopen=Reopen-TaskWithFreshTransport $runtimeProject $EngineFull
    [void](Save-Receipt $reopen 'reopen');$reopenCapture=$null;$reopenState=$null;$reopenProviderReceipt=$null;$reopenOk=$false
    if($reopen.status-ne'ok'){$script:SessionActive=[bool](Get-ActionRoguelikePropertyValue $reopen.result 'session_retained_for_cleanup_retry');if($script:SessionActive){$script:Session=Get-ActionRoguelikePropertyValue $reopen.result 'session'}}
    Assert-ExecutorOperationHealth $reopen 'receipts/reopen.json'
    if($reopen.status-eq'ok'){$script:Session=$reopen.result.session;$script:SessionActive=$true;$script:ProcessId=[int]$reopen.result.process_id;$script:ProcessToken=[string]$reopen.result.process_token;Reset-StateReaderContext;[void](Save-Receipt ([ordered]@{schema_version='1.0.0';channel_root=Get-Relative $script:StateRoot;snapshot_path=Get-Relative $script:SnapshotPath;events_path=Get-Relative $script:EventsPath;process_id=$script:ProcessId;process_token=$script:ProcessToken;session_started_utc=$script:SessionStartedUtc.ToString('o');reader_context_initialized=$true}) 'state-transport-reopen');$reopenCapture=Wait-CanonicalCapture 'reopened';if($providerHealthy){$reopenState=Wait-TaskState {param($s,$e)$true} 5 'reopened';$reopenProviderReceipt=Save-StateProviderReceipt $reopenState 'reopened';if($reopenState-and[string]$reopenState.validation.identity_binding-ceq'active_process_id'){$warnings.Add([pscustomobject][ordered]@{code='state_identity_active_process_compatibility';message='The reopened state pair used the exact active process-ID identity instead of echoing the launcher nonce.';evidence_paths=@($reopenProviderReceipt)})}};$reopenOk=$script:ProcessId-ne$oldPid-and$script:ProcessToken-cne$oldToken-and$reopenCapture}
    Set-Checkpoint 'D1-05' $(if($reopenOk){'pass'}else{'fail'}) 'True Reopen renewed process identity and produced a second visible client frame.' @('receipts/reopen.json',$reopenCapture) 'CANDIDATE_REOPEN_FAILED' 'receipts/reopen.json'
    if($providerHealthy){Set-Checkpoint 'D4-05' $(if($reopenOk-and$reopenState){'pass'}else{'fail'}) 'True Reopen discarded process-local progress and re-established a fresh state pair.' @('states/reopened.json',$reopenProviderReceipt,$reopenCapture) 'CANDIDATE_REOPEN_FAILED' 'receipts/reopen.json';if($script:VerdictsById['D2-15'].verdict-ne'pass'-and$reopenOk-and$reopenState){Set-Checkpoint 'D2-15' 'pass' 'Public Restart and true Reopen content were exercised.' @('states/reopened.json',$reopenProviderReceipt,$reopenCapture)}}
    if($providerHealthy-and-not$TransportHealthOnly){
        $smokeStop=Stop-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -FaultCleanupTimeoutMs 5000
        [void](Save-Receipt $smokeStop 'smoke-stop');$script:SessionActive=$false
        if($smokeStop.status-cne'ok'-or-not$smokeStop.result.process_exited-or-not$smokeStop.result.input_lease_released-or-not$smokeStop.result.input_cleanup.all_released){throw 'run_invalid|ATOMIC_CLEANUP_UNVERIFIED|Shared smoke cleanup failed.'}
        $atomicTraces=Invoke-ARCollectAtomicVariants -Project $runtimeProject -Engine $EngineFull -Variants $AtomicVariants
        if($ReuseAtomicRunRoot){
            $reuseRoot=Assert-ActionRoguelikeBindingPath -Path $ReuseAtomicRunRoot
            $prior=Read-Json (Join-Path $reuseRoot 'candidate-manifest.json')
            $priorStage=Read-Json (Join-Path $reuseRoot 'runtime/fixture-stage.json')
            if($prior.candidate_identity_sha256-cne$candidateIdentity-or$priorStage.adapter_analysis.adapter_identity-cne$script:FixtureAdapterIdentity){throw 'Incremental source candidate or adapter identity differs.'}
            $priorTraces=Get-Content (Join-Path $reuseRoot 'receipts/atomic-live-traces.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 100
            $reused=@()
            foreach($variant in @((Get-ActionRoguelikeAtomicVariantMap).Values|ForEach-Object{$_}|Select-Object -Unique)){
                if($variant-cin$AtomicVariants){continue}
                $trace=$priorTraces[$variant]
                if($null-eq$trace-or$trace.execution.status-cnotin@('completed','candidate_blocked')-or$trace.cleanup.verified-ne$true){throw "Unhealthy trace cannot be reused: $variant"}
                $from=Assert-ActionRoguelikeBindingPath -Path (Join-Path $reuseRoot "variants/$variant") -Root $reuseRoot
                $to=Join-Path $script:OutputFull "variants/$variant"
                if(Test-Path $to){throw 'Refusing to overwrite collected variant.'}
                Copy-Item -LiteralPath $from -Destination $to -Recurse
                $atomicTraces[$variant]=$trace
                $reused+=@{variant=$variant;trace_sha256=(Get-FileHash (Join-Path $from 'receipts/trace.json') -Algorithm SHA256).Hash.ToLowerInvariant()}
            }
            [void](Save-Receipt @{source_run=[IO.Path]::GetFileName($reuseRoot);candidate_identity_sha256=$candidateIdentity;adapter_identity=$script:FixtureAdapterIdentity;recollected=$AtomicVariants;reused=$reused;reason='Repair stale stop sampling and repeat-before-observed-healing collection; retain unaffected raw evidence.'} 'incremental-reuse')
            [void](Save-Receipt $atomicTraces 'atomic-live-traces')
        }
        foreach($id in (Get-ActionRoguelikeAtomicVariantMap).Keys){
            $result=Test-ActionRoguelikeAtomicCheckpoint -CheckpointId $id -Traces $atomicTraces
            Set-AtomicCheckpoint $id $result @('receipts/atomic-live-traces.json')
        }
    }
}catch{
    if($_.Exception.Message -eq 'candidate_static_stop'){Set-Unresolved 'fail' 'The candidate could not establish build or runtime prerequisites.' @('D1','D2','D5') 'CANDIDATE_STATIC_PREREQUISITE_FAILED' 'candidate-manifest.json';Set-Unresolved 'unreachable' 'The candidate could not establish gameplay prerequisites.' @('D3','D4') 'CANDIDATE_STATIC_PREREQUISITE_FAILED' 'candidate-manifest.json'}
    if($_.Exception.Message-notin@('candidate_static_stop','candidate_start_stop','evaluator_engine_binding_stop','evaluator_operation_stop')){$faults.Add([pscustomobject][ordered]@{domain='evaluator';code='runtime_exception';message='The evaluator raised an unexpected exception.';diagnostic=$_.Exception.Message;stack=$_.ScriptStackTrace;evidence_paths=@()})}
}finally{
    if($script:SessionActive-and$script:Session){try{$stop=Stop-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -FaultCleanupTimeoutMs 5000;[void](Save-Receipt $stop 'stop');$clean=$stop.result-and$stop.result.process_exited-eq$true-and$stop.result.input_lease_released-eq$true-and$stop.result.input_cleanup.all_released-eq$true;if(-not$clean){$faults.Add([pscustomobject]@{domain='cleanup';code='cleanup_not_verified';message='Process or controlled-input cleanup was not verified.';evidence_paths=@('receipts/stop.json')})}}catch{$faults.Add([pscustomobject]@{domain='cleanup';code='cleanup_exception';message='Final cleanup raised an exception.';evidence_paths=@()})}}
    if($faults.Count-eq0){Set-Unresolved 'fail' 'The completed candidate path did not demonstrate this content or feedback checkpoint.' @('D2','D5') 'CANDIDATE_REQUIREMENT_NOT_DEMONSTRATED' (Get-StateEvidencePath);Set-Unresolved 'unreachable' 'The completed candidate path did not establish this rule or lifecycle prerequisite.' @('D3','D4') 'CANDIDATE_PREREQUISITE_UNREACHABLE' (Get-StateEvidencePath);Set-Unresolved 'fail' 'The completed candidate path did not establish this static checkpoint.' @('D1') 'CANDIDATE_STATIC_CHECK_FAILED' 'candidate-manifest.json'}
    $failures=@($script:Verdicts|Where-Object{$_.verdict-in@('fail','unreachable')-and$_.attribution-ceq'candidate'}|Group-Object reason_code|ForEach-Object{[ordered]@{reason_code=[string]$_.Name;attribution=$(if(@($_.Group|Where-Object attribution -eq 'evaluator').Count){'evaluator'}else{'candidate'});first_failure=[string]$_.Group[0].first_failure;affected_checkpoints=@($_.Group|ForEach-Object checkpoint_id);score_impact='checkpoint_zero';evidence=@($_.Group|ForEach-Object{$_.evidence}|Sort-Object -Unique)}})
    try{Stop-ActionRoguelikeTransportRecorder}catch{$faults.Add([pscustomobject]@{domain='evaluator';code='STATE_RECORDER_FAILED';message=$_.Exception.Message;evidence_paths=@()})}
    $elapsed=([DateTime]::UtcNow-$started).TotalSeconds;$runStatus=if($faults.Count-eq0){'completed'}else{'run_invalid'}
    if($runStatus -eq 'run_invalid'){Write-JsonFile ([ordered]@{schema_version='1.0.0';status='evaluation_not_completed';run_status='run_invalid';generated_utc=[DateTime]::UtcNow.ToString('o');reason_codes=@($faults|ForEach-Object{[string]$_.code}|Sort-Object -Unique);faults=@($faults);message='No canonical score was produced because evaluator, tooling, or authoring prerequisites were incomplete.'}) (Join-Path $script:OutputFull 'evaluation-not-completed.json')}
    $record=[ordered]@{schema_version='4.0.0';game_id='ActionRoguelike';task_name='Rift Hunting';task_revision='2.2.0-diagnostic';run_id=$RunId;candidate_id=$CandidateId;candidate_identity_sha256=$candidateIdentity;evaluator_revision='actionroguelike-evaluator-4.1.0';mode=$(if($TransportHealthOnly){'transport_health_only'}else{'canonical_independent_atomic_cases'});run_status=$runStatus;checkpoints=$script:Verdicts;candidate_failures=$failures;faults=@($faults);warnings=@($warnings);budget=[ordered]@{declared_serial_worst_case_seconds=3600;session_watchdog_seconds=3900;terminal_timeout_seconds=$TerminalTimeoutSeconds;elapsed_seconds=[Math]::Round($elapsed,3);within_watchdog=$elapsed-lt3900;watchdog_enforced=$false;serial_bound_verified=$false}}
    Write-JsonFile $record (Join-Path $script:OutputFull 'verdicts.json')
}
Write-Output (Join-Path $script:OutputFull 'verdicts.json')
