[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$OutputPath,[string]$FixtureBindingsPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ActionRoguelikeAtomicChecks.ps1')
$script:ARMetricBinding=$null
if($FixtureBindingsPath){
    $stage=Get-Content (Join-Path $RunRoot 'runtime/fixture-stage.json') -Raw|ConvertFrom-Json -Depth 100
    if((Get-FileHash $FixtureBindingsPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne$stage.binding_sha256){throw 'Replay binding differs from staged source audit.'}
    $binding=@((Get-Content $FixtureBindingsPath -Raw|ConvertFrom-Json -Depth 100).bindings|Where-Object id -CEQ $stage.binding_id)
    if($binding.Count-ne1){throw 'Replay adapter is ambiguous.'}
    $script:ARMetricBinding=Get-ActionRoguelikeAtomicProperty $binding[0] 'observation_units'
}
$path=Join-Path $RunRoot 'receipts/atomic-live-traces.json'
$traces=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
$results=@(foreach($id in (Get-ActionRoguelikeAtomicVariantMap).Keys){Test-ActionRoguelikeAtomicCheckpoint $id $traces})
$record=@{scope='Current predicates over retained evidence; no gameplay rerun';trace_sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();observation_units=$script:ARMetricBinding;results=$results}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($record|ConvertTo-Json -Depth 100)+"`n")
$results|Select-Object checkpoint_id,verdict,reason_code|ConvertTo-Json
