[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestFixture.ps1')
$fixture=New-BomberTestFixture (Split-Path -Parent $PSScriptRoot)
function Assert([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Json($Value,$Path){$Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding utf8}
$oldKey=$env:D6_API_KEY
$oldNewApiKey=$env:NEWAPI_API_KEY;$oldOpenAiKey=$env:OPENAI_API_KEY
$env:D6_API_KEY='synthetic-test-key'
$global:BomberD6TestCalls=0;$global:BomberD6TestMode='valid'
# Mock only the HTTP boundary; exercise the real request builder, parser,
# aggregation, completion entry point, and canonical scorer together.
function global:Invoke-WebRequest {
    param($Method,$Uri,$Headers,$ContentType,$Body,$TimeoutSec)
    ++$global:BomberD6TestCalls
    $request=$Body|ConvertFrom-Json -Depth 100
    Assert ([Text.Encoding]::UTF8.GetByteCount($Body) -le 8MB) 'Request exceeded image budget.'
    Assert ($request.messages[0].content.Count -eq 3) 'Expected prompt followed by two images.'
    Assert ($request.messages[0].content[1].image_url.url.StartsWith('data:image/png;base64,')) 'Reference image missing.'
    Assert ($request.messages[0].content[2].image_url.url.StartsWith('data:image/png;base64,')) 'Candidate image missing.'
    $text="Scene completeness and asset assembly:2/2`nComposition and layout:1.5/2`nScale, hierarchy, and clarity:1/2`nStyle and color consistency:0.5/2`nOverall polish:2/2`nTotal:7/10`nReason:Synthetic transport fixture."
    if($global:BomberD6TestMode -eq 'malformed'){$text='invalid response'}
    if($global:BomberD6TestMode -eq 'non_json'){return @{Content='<html>upstream unavailable</html>'}}
    if($global:BomberD6TestMode -eq 'interrupted' -and $global:BomberD6TestCalls -eq 4){throw 'Synthetic transport interruption.'}
    $model=if($global:BomberD6TestMode -eq 'drift' -and $global:BomberD6TestCalls -gt 1){'different-model'}else{'test-model-v1'}
    return @{Content=(@{id='synthetic';model=$model;usage=@{total_tokens=7};choices=@(@{message=@{content=$text}})}|ConvertTo-Json -Depth 20)}
}
function New-Run([string]$Name,[string]$ImageKind='healthy') {
    $run=Join-Path $fixture.temp $Name;$captures=Join-Path $run 'captures'
    [void](New-Item -ItemType Directory -Path $captures -Force)
    Json @{candidate_id=$Name;candidate_identity_sha256=('a'*64)} (Join-Path $run 'candidate-manifest.json')
    $map=@{'active-duel'='active-arena';'chain-reaction'='chain-reaction';'player1-win'='player1-win'}
    foreach($id in @('active-duel','chain-reaction','player1-win')) {
        $image=Join-Path $captures "$($map[$id]).png"
        if($ImageKind -eq 'missing'){continue}
        if($ImageKind -eq 'broken') { [IO.File]::WriteAllText($image,'not a png') }
        elseif($ImageKind -in @('black','resolution')) {
            $width=if($ImageKind -eq 'resolution'){640}else{1280}
            $bitmap=[Drawing.Bitmap]::new($width,720);$g=[Drawing.Graphics]::FromImage($bitmap)
            try{$g.Clear([Drawing.Color]::Black);$bitmap.Save($image,[Drawing.Imaging.ImageFormat]::Png)}finally{$g.Dispose();$bitmap.Dispose()}
        } else {Copy-Item -LiteralPath (Join-Path $fixture.root "d6/reference/$id.png") -Destination $image}
        $phase=if($id -eq 'player1-win'){'player1_win'}else{'active'}
        $shape=@{phase=$phase;bombs=@();explosion_cells=@(@{x=1;y=1},@{x=3;y=1})}
        $expected=@{process_token='test';round_id='r1';bombs=@(@{object_id='a';cell=@{x=1;y=1}},@{object_id='b';cell=@{x=3;y=1}})}
        Json @{status='bound';state_id=$id;candidate_identity_sha256=('a'*64);capture_sha256=(Get-FileHash -LiteralPath $image).Hash.ToLowerInvariant();before=@{process_token='test';round_id='r1';monotonic_ms=100;game_state=$shape};after=@{process_token='test';round_id='r1';monotonic_ms=200;game_state=$shape};chain_expectation=$expected;native_capture=@{producer='ue-native-viewport';status='ok';process_token='test';width=1280;height=720;monotonic_ms=150}} ([IO.Path]::ChangeExtension($image,'.semantic.json'))
    }
    return $run
}
function Add-Verdicts([string]$Run){
    $name=Split-Path -Leaf $Run
    $config=Get-Content -LiteralPath "$($fixture.root)/contracts/evaluator-config.json" -Raw|ConvertFrom-Json
    $catalog=Get-Content -LiteralPath "$($fixture.root)/catalog/checkpoints.json" -Raw|ConvertFrom-Json
    $checkpoints=@($catalog.checkpoints|ForEach-Object{@{checkpoint_id=$_.id;dimension=$_.dimension;verdict='pass';detail='unit';reason_code=$null;attribution=$null;first_failure=$null;score_impact='full_credit';evidence=@()}})
    Json @{schema_version='3.0.0';game_id='Bomber';task_name='Bomber Local Duel';task_revision=$config.task_revision;run_id='unit';candidate_id=$name;candidate_identity_sha256=('a'*64);evaluator_revision=$config.evaluator_revision;run_status='completed';checkpoints=$checkpoints;candidate_failures=@();faults=@();warnings=@();budget=@{}} "$Run/verdicts.json"
}
try {
    $vlm=Join-Path $fixture.root 'scripts/Invoke-BomberD6Vlm.ps1'
    $aggregate=Join-Path $fixture.root 'scripts/Invoke-BomberD6Aggregation.ps1'
    $complete=Join-Path $fixture.root 'scripts/Complete-BomberEvaluation.ps1'
    foreach($kind in @('missing','black','broken','resolution')) {
        $run=New-Run $kind $kind;$global:BomberD6TestCalls=0
        $responses=& $vlm -RunDirectory $run -EvaluatorRoot $fixture.root -Model test
        $output=& $aggregate -CandidateCapturesDirectory "$run/captures" -CandidateId $kind -CandidateIdentitySha256 ('a'*64) -ModelId test -ResponsesPath $responses -OutputDirectory "$run/d6"
        $zero=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json -Depth 100
        Assert ($global:BomberD6TestCalls -eq 0 -and $zero.score -eq 0 -and $zero.rounds.Count -eq 3) "$kind must get three numeric zero rounds without HTTP."
    }
    $run=New-Run 'healthy';$global:BomberD6TestCalls=0
    Add-Verdicts $run
    & $complete -RunDirectory $run -Model test -BaseUrl 'http://unit.invalid/v1' | Out-Null
    $result=Get-Content -LiteralPath "$run/evaluation-result.json" -Raw|ConvertFrom-Json -Depth 100
    Assert ($global:BomberD6TestCalls -eq 9 -and $result.dimensions.D6.score -eq 7 -and $result.overall -eq 97) 'End-to-end D6/scorer result incorrect.'
    Assert (Test-Json -LiteralPath "$run/evaluation-result.json" -SchemaFile "$($fixture.root)/schemas/evaluation-result.schema.json") 'Published result did not match its schema.'
    Assert (@(Get-ChildItem "$run/vlm/*-response.json").Count -eq 9 -and @(Get-ChildItem "$run/vlm/*-request.json").Count -eq 9) 'Raw request/response evidence incomplete.'
    Assert (-not ((Get-Content "$run/vlm/*.json" -Raw) -match 'synthetic-test-key')) 'Credential leaked into evidence.'
    $rejected=$false;try{& $complete -RunDirectory $run|Out-Null}catch{$rejected=$_.Exception.Message -match 'EVALUATION_RESULT_EXISTS'}
    Assert ($rejected -and $global:BomberD6TestCalls -eq 9) 'Completed run was overwritten or evaluated twice.'
    foreach($mode in @('malformed','non_json','drift')) {
        $run=New-Run $mode;$global:BomberD6TestCalls=0;$global:BomberD6TestMode=$mode;$rejected=$false
        try {& $vlm -RunDirectory $run -EvaluatorRoot $fixture.root -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null}catch{$rejected=$true}
        Assert ($rejected -and (Test-Path "$run/vlm/fault.json") -and -not (Test-Path "$run/d6-vlm-responses.json")) "$mode should invalidate scoring and retain fault evidence."
        Assert (@(Get-ChildItem "$run/vlm/*-response.json").Count -gt 0) 'Rejected raw response was lost.'
    }
    # A transport interruption after one full round must not repeat those three calls.
    $run=New-Run 'resume';Add-Verdicts $run
    $verdictHash=(Get-FileHash "$run/verdicts.json").Hash
    $global:BomberD6TestCalls=0;$global:BomberD6TestMode='interrupted';$rejected=$false
    try{& $complete -RunDirectory $run -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null}catch{$rejected=$true}
    Assert ($rejected -and (Test-Path "$run/evaluation-not-completed.json") -and -not (Test-Path "$run/evaluation-result.json")) 'Infrastructure failure published a score.'
    Assert ((Get-Content "$run/vlm/fault.json" -Raw|ConvertFrom-Json).reason_code -eq 'VLM_REQUEST_FAILED') 'Transport failure was not attributed.'
    $rejected=$false
    try{& $vlm -RunDirectory $run -EvaluatorRoot $fixture.root -Model changed -BaseUrl 'http://unit.invalid/v1'|Out-Null}catch{$rejected=$_.Exception.Message -match 'D6_VLM_RESUME_IDENTITY_MISMATCH'}
    Assert ($rejected -and $global:BomberD6TestCalls -eq 4) 'Resume mixed model configurations.'
    $global:BomberD6TestMode='valid'
    & $complete -RunDirectory $run -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null
    $binding=Get-Content "$run/vlm/binding.json" -Raw|ConvertFrom-Json
    Assert ($global:BomberD6TestCalls -eq 10 -and $binding.http_attempts -eq 10 -and $binding.independent_calls -eq 9) 'Resume repeated completed calls or lost attempt history.'
    Assert ((Get-FileHash "$run/verdicts.json").Hash -eq $verdictHash) 'D6 completion changed D1-D5 evidence.'
    Assert ((Test-Path "$run/evaluation-result.json") -and -not (Test-Path "$run/evaluation-not-completed.json") -and -not (Test-Path "$run/vlm/fault.json")) 'Successful resume retained a stale active failure.'
    Assert (@(Get-ChildItem "$run/vlm/attempts" -Filter fault.json -Recurse).Count -eq 1) 'Resume discarded failure history.'
    # Configuration failures should leave the same directory usable after repair.
    $run=New-Run 'config';$env:D6_API_KEY='';$env:NEWAPI_API_KEY='';$env:OPENAI_API_KEY='';$rejected=$false
    try{& $vlm -RunDirectory $run -EvaluatorRoot $fixture.root -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null}catch{$rejected=$_.Exception.Message -match 'VLM_CONFIGURATION_REQUIRED'}
    Assert ($rejected -and -not (Test-Path "$run/vlm")) 'Configuration failure stranded an output directory.'
    $env:D6_API_KEY='synthetic-test-key';$global:BomberD6TestCalls=0
    & $vlm -RunDirectory $run -EvaluatorRoot $fixture.root -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null
    # Reuse completed responses after an aggregation interruption without HTTP.
    Add-Verdicts $run
    [void](New-Item -ItemType Directory -Path "$run/d6/rounds" -Force)
    [IO.File]::WriteAllText("$run/d6/rounds/interrupted.json",'partial evidence')
    & $complete -RunDirectory $run -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null
    Assert ($global:BomberD6TestCalls -eq 9 -and @(Get-ChildItem $run -Directory -Filter 'd6-incomplete-*').Count -eq 1) 'Partial aggregation could not resume from existing responses.'
    # Mixed availability keeps the failed state in all denominators.
    $run=New-Run 'mixed';Remove-Item -LiteralPath "$run/captures/player1-win.png"
    $global:BomberD6TestCalls=0;Add-Verdicts $run
    & $complete -RunDirectory $run -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null
    $result=Get-Content "$run/evaluation-result.json" -Raw|ConvertFrom-Json
    Assert ($global:BomberD6TestCalls -eq 6 -and $result.dimensions.D6.score -eq 4.7) 'Missing state was dropped or sent to VLM.'
    # A valid PNG with excessive trailing bytes must fail before creating a large request.
    $run=New-Run 'oversized';$global:BomberD6TestCalls=0
    $image="$run/captures/active-arena.png"
    $stream=[IO.File]::Open($image,[IO.FileMode]::Append)
    try{$padding=[byte[]]::new(6MB);$stream.Write($padding,0,$padding.Length)}finally{$stream.Dispose()}
    $sidecar=[IO.Path]::ChangeExtension($image,'.semantic.json')
    $proof=Get-Content $sidecar -Raw|ConvertFrom-Json -Depth 100
    $proof.capture_sha256=(Get-FileHash $image).Hash.ToLowerInvariant();Json $proof $sidecar
    $rejected=$false
    try{& $vlm -RunDirectory $run -EvaluatorRoot $fixture.root -Model test -BaseUrl 'http://unit.invalid/v1'|Out-Null}catch{$rejected=$_.Exception.Message -match 'D6_VLM_REQUEST_TOO_LARGE'}
    Assert ($rejected -and $global:BomberD6TestCalls -eq 0 -and -not (Test-Path "$run/d6-vlm-responses.json")) 'Oversized image request was sent or scored.'
    Write-Output 'D6_PIPELINE_OK calls=9 health_zero_cases=4 raw_evidence=true model_drift_rejected=true malformed_response_retained=true completion_scorer=true resume=true bounded_pair_requests=true mixed_states=true'
} finally {
    $env:D6_API_KEY=$oldKey
    $env:NEWAPI_API_KEY=$oldNewApiKey;$env:OPENAI_API_KEY=$oldOpenAiKey
    Remove-Item Function:/Invoke-WebRequest
    Remove-Variable BomberD6TestCalls,BomberD6TestMode -Scope Global
    Remove-BomberTestFixture $fixture.temp
}
