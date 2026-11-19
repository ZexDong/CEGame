[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StagedProjectsJson,
    [Parameter(Mandatory)][string]$EngineRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$NativeOnly
)
# Bounded adapter authoring check. This does not run or publish gameplay scores.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ActionRoguelikeFixtureRuntime.ps1')
. (Join-Path $PSScriptRoot 'ActionRoguelikeRunBinding.ps1')
$task=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$repository=[IO.Path]::GetFullPath((Join-Path $task '../..'))
$manifest=Get-Content -Raw (Join-Path $task 'input/BENCHMARK_MANIFEST.json')|ConvertFrom-Json
$engine=Resolve-ActionRoguelikeEngineBinding $repository $EngineRoot $manifest
if(-not$engine.success){throw $engine.detail}
Import-Module $engine.executor_path -Force
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Health output must be fresh.'}
New-Item -ItemType Directory -Path $output|Out-Null
function Write-JsonFile($Value,[string]$Path){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))}
function Read-Json([string]$Path){try{Get-Content -Raw -LiteralPath $Path -ErrorAction Stop|ConvertFrom-Json -Depth 100}catch{$null}}
function Save-Receipt($Value,[string]$Name){$path=Join-Path $script:OutputFull ($Name+'.json');Write-JsonFile $Value $path;return ($Name+'.json')}
function Wait-IndependentState($Writes,[datetime]$After){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do{
        $state=Read-Json $script:SnapshotPath
        # Diagnostic state corroboration; the canonical scorer retains its
        # stricter public state schema/identity gate. Never rewrite observations.
        $file=Get-Item -LiteralPath $script:SnapshotPath -ErrorAction SilentlyContinue
        if($state -and $file -and $state.identity.process_token-cin@($script:ProcessToken,"process-$script:ProcessId","proc-$script:ProcessId","pid$script:ProcessId") -and $file.LastWriteTimeUtc-gt$After){
            $matches=$true
            foreach($key in @('health','credits','teleport_acquired')){
                $field=$state.player.$key
                if($field.trust-cne'verified'-or$field.value-ne$Writes[$key]){$matches=$false}
            }
            if($matches){return $state}
        }
        Start-Sleep -Milliseconds 30
    }while($watch.Elapsed.TotalSeconds-lt5)
    throw 'FIXTURE_OBSERVATION_MISMATCH: no fresh independent observation corroborated semantic writes.'
}
$results=[Collections.Generic.List[object]]::new()
foreach($item in (Get-Content -Raw $StagedProjectsJson|ConvertFrom-Json)){
    $script:OutputFull=Join-Path $output $item.name
    New-Item -ItemType Directory -Path $script:OutputFull|Out-Null
    $script:FixtureChannel=Join-Path $script:OutputFull 'fixture'
    New-Item -ItemType Directory -Path $script:FixtureChannel|Out-Null
    $script:SnapshotPath=Join-Path $script:OutputFull 'snapshot.json'
    $eventPath=Join-Path $script:OutputFull 'events.json'
    $staged=Read-Json (Join-Path (Split-Path -Parent (Split-Path -Parent $item.project)) 'fixture-stage.json')
    $script:FixtureAdapterIdentity=$staged.adapter_analysis.adapter_identity
    $script:ProcessToken='fixture-health-'+[guid]::NewGuid().ToString('N')
    $script:Session=$null
    $result=[ordered]@{candidate=$item.name;adapter_identity=$script:FixtureAdapterIdentity;status='run_invalid';checks=@();failure=$null;cleanup_verified=$false}
    try{
        foreach($edit in $staged.edits){
            if((Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $item.project) $edit.path) -Algorithm SHA256).Hash.ToLowerInvariant()-cne$edit.after_sha256){throw 'Staged source identity changed before health.'}
        }
        $start=Start-UnrealEvaluationSession -ProjectPath $item.project -RunRoot $script:OutputFull -StatePath (Join-Path $script:OutputFull 'engine.json') -ProcessToken $script:ProcessToken -EngineRoot $EngineRoot -WindowWidth 1280 -WindowHeight 720 -TimeoutMs 60000 -FocusTimeoutMs 3000 -ObserverDisabledControl -AdditionalArguments @("-ActionRoguelikeStateRoot=$($script:OutputFull)","-ActionRoguelikeSnapshotPath=$($script:SnapshotPath)","-ActionRoguelikeEventsPath=$eventPath","-AREvaluationFixture=$($script:FixtureChannel)",'-Windowed','-ResX=1280','-ResY=720','-ForceRes')
        $null=Save-Receipt $start 'start'
        if($start.status-cne'ok'){throw 'Fixture health launch failed; see start.json.'}
        $script:Session=$start.result.session;$script:ProcessId=[int]$start.result.process_id
        $startup=[Diagnostics.Stopwatch]::StartNew()
        while(-not(Read-Json $script:SnapshotPath)){
            if($NativeOnly-and$startup.Elapsed.TotalSeconds-ge5){break}
            if($startup.Elapsed.TotalSeconds-ge30){throw 'Fixture authoring startup did not publish a snapshot.'}
            Start-Sleep -Milliseconds 50
        }
        if(-not$NativeOnly){$null=Invoke-ARFixture @{capture_pointer=$true} 'viewport'}
        foreach($health in @(50,65)){
            $writes=@{health=$health;credits=50;teleport_acquired=($health-eq50);remaining_seconds=45;invulnerable=$true}
            $reply=Invoke-ARFixture $writes "state-$health"
            if($NativeOnly){$result.checks+=@("native_write_readback_$health")}
            else{
                $state=Wait-IndependentState $writes $reply.response_received_utc
                $null=Save-Receipt $state "observed-$health"
                $result.checks+=@("native_and_observed_state_$health")
            }
        }
        if($NativeOnly){$result.status='native_only_passed'}else{
        $null=Invoke-ARFixture @{position_m=$state.player.position_m.value;aim='up'} 'geometry'
        $result.checks+=@('engine_player_placement_collision_orientation','engine_viewport_capture')
        $inputReceipt=Invoke-UnrealPressKey -Session $script:Session -Key 'W' -DurationMs 45
        $null=Save-Receipt $inputReceipt 'input'
        if($inputReceipt.status-cne'ok'-or-not$inputReceipt.input_dispatched){throw 'Engine input dispatch failed.'}
        $capture=Save-UnrealClientCapture -Session $script:Session -OutputPath (Join-Path $script:OutputFull 'client.png') -ArtifactId 'fixture-health'
        $null=Save-Receipt $capture 'capture'
        if($capture.status-cne'ok'){throw 'Engine capture failed.'}
        $result.checks+=@('engine_input','engine_client_capture');$result.status='passed'
        }
    }catch{$result.failure=$_.Exception.Message}
    finally{
        if($script:Session){
            $stop=Stop-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -FaultCleanupTimeoutMs 5000
            $null=Save-Receipt $stop 'stop'
            $result.cleanup_verified=$stop.status-ceq'ok'-and$stop.result.process_exited-and$stop.result.input_lease_released-and$stop.result.input_cleanup.all_released
            if(-not$result.cleanup_verified){$result.status='run_invalid';$result.failure='Engine cleanup failed.'}
        }
        Write-JsonFile $result (Join-Path $script:OutputFull 'result.json')
        $results.Add($result)
        Write-Output "$($item.name): $($result.status) $($result.failure)"
    }
}
Write-JsonFile @($results) (Join-Path $output 'summary.json')
if(@($results|Where-Object{$_.status-notin@('passed','native_only_passed')}).Count){exit 1}
