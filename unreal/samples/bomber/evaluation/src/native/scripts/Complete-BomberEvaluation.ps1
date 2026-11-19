[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [string]$Model,
    [string]$BaseUrl,
    [ValidateRange(1,240)][int]$TimeoutSeconds=240,
    [string]$D6RunPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'BomberEvaluator.Common.psm1') -Force
$run=[IO.Path]::GetFullPath($RunDirectory)
$resultPath=Join-Path $run 'evaluation-result.json'
if(Test-Path -LiteralPath $resultPath){throw 'EVALUATION_RESULT_EXISTS: completed evidence cannot be overwritten.'}
try{$lock=[IO.File]::Open((Join-Path $run 'completion.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'EVALUATION_COMPLETION_BUSY'}
try {
if(Test-Path -LiteralPath $resultPath){throw 'EVALUATION_RESULT_EXISTS: completed evidence cannot be overwritten.'}
$verdictsPath=Join-Path $run 'verdicts.json'
$verdicts=Get-Content -LiteralPath $verdictsPath -Raw|ConvertFrom-Json -Depth 100
$candidate=Get-Content -LiteralPath (Join-Path $run 'candidate-manifest.json') -Raw|ConvertFrom-Json
try {
    if($verdicts.run_status -cne 'completed'){throw 'DYNAMIC_RUN_INVALID'}
    if($verdicts.candidate_identity_sha256 -cne $candidate.candidate_identity_sha256 -or $verdicts.candidate_id -cne $candidate.candidate_id){throw 'CANDIDATE_IDENTITY_MISMATCH'}
    if(-not $D6RunPath){
        $D6RunPath=Join-Path $run 'd6/d6-run.json'
        if(-not (Test-Path -LiteralPath $D6RunPath)){
            $responsesPath=Join-Path $run 'd6-vlm-responses.json'
            if(-not (Test-Path -LiteralPath $responsesPath)){
                $responsesPath=& (Join-Path $PSScriptRoot 'Invoke-BomberD6Vlm.ps1') -RunDirectory $run -EvaluatorRoot $root -Model $Model -BaseUrl $BaseUrl -TimeoutSeconds $TimeoutSeconds
            }
            $responses=Get-Content -LiteralPath $responsesPath -Raw|ConvertFrom-Json -Depth 100
            $d6Directory=Resolve-BomberSafePath -Root $run -Path (Join-Path $run 'd6') -RequireContainer
            if(Test-Path -LiteralPath $d6Directory){
                # A failed aggregation can leave raw round files. Preserve them and
                # rebuild only the aggregate from the already completed VLM evidence.
                $archive=Resolve-BomberSafePath -Root $run -Path (Join-Path $run ('d6-incomplete-'+[guid]::NewGuid().ToString('N')))
                Move-Item -LiteralPath $d6Directory -Destination $archive
            }
            $D6RunPath=& (Join-Path $PSScriptRoot 'Invoke-BomberD6Aggregation.ps1') -CandidateCapturesDirectory (Join-Path $run 'captures') -CandidateId $candidate.candidate_id -CandidateIdentitySha256 $candidate.candidate_identity_sha256 -ModelId $responses.model_id -ResponsesPath $responsesPath -OutputDirectory (Join-Path $run 'd6')
        }
    }
    $pendingResult=Join-Path $run 'evaluation-result.pending.json'
    & (Join-Path $PSScriptRoot 'Invoke-BomberCanonicalScorer.ps1') -VerdictsPath $verdictsPath -D6RunPath $D6RunPath -OutputPath $pendingResult | Out-Null
    $incomplete=Join-Path $run 'evaluation-not-completed.json'
    if(Test-Path -LiteralPath $incomplete){
        # Preserve the diagnostic history while retiring the stale active status.
        Move-Item -LiteralPath $incomplete -Destination (Join-Path $run ('evaluation-not-completed-'+[guid]::NewGuid().ToString('N')+'.json'))
    }
    [IO.File]::Move($pendingResult,$resultPath,$false)
    Write-BomberJson (@{schema_version='1.0.0';status='completed';run_id=$verdicts.run_id;result='evaluation-result.json';d6=[IO.Path]::GetRelativePath($run,[IO.Path]::GetFullPath($D6RunPath)).Replace('\','/')}) (Join-Path $run 'completion.json')
    Write-Output $resultPath
} catch {
    if(-not (Test-Path -LiteralPath $resultPath)){
        $incomplete=Join-Path $run 'evaluation-not-completed.json'
        if(Test-Path -LiteralPath $incomplete){Move-Item -LiteralPath $incomplete -Destination (Join-Path $run ('evaluation-not-completed-'+[guid]::NewGuid().ToString('N')+'.json'))}
        Write-BomberJson (@{schema_version='1.0.0';status='evaluation_not_completed';run_id=$verdicts.run_id;reason_code=($_.Exception.Message -split ':')[0];attribution='infrastructure';verdicts='verdicts.json';score_published=$false}) $incomplete
    }
    throw
}
}finally{$lock.Dispose()}
