[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VerdictsPath,
    [uri]$BaseUrl,
    [string]$ModelId,
    [string]$ModelVersion,
    [string]$ApiKeyEnvironment='NEWAPI_API_KEY',
    [string]$CaptureHealthRunRoot,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ActionRoguelikeD6Protocol.ps1')
. (Join-Path $PSScriptRoot 'ActionRoguelikeD6Configuration.ps1')
$configuration=Resolve-ActionRoguelikeD6Configuration -BaseUrl $BaseUrl -ModelId $ModelId
$BaseUrl=$configuration.base_url;$ModelId=$configuration.model_id
function Write-Record($Value,$Path){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100)+"`n",[Text.UTF8Encoding]::new($false))}
$run=Read-D6Json ([IO.Path]::GetFullPath($VerdictsPath))
Assert-D6 ($run.run_status-ceq'completed'-and$run.mode-ceq'canonical_independent_atomic_cases'-and@($run.faults).Count-eq0) 'D6_GAMEPLAY_RUN_INVALID'
Assert-D6 ($BaseUrl.Scheme-cin@('http','https')-and-not$BaseUrl.UserInfo-and-not$BaseUrl.Query) 'D6_ENDPOINT_INVALID'
$key=[Environment]::GetEnvironmentVariable($ApiKeyEnvironment)
$out=[IO.Path]::GetFullPath($OutputDirectory)
Assert-D6 (-not(Test-Path -LiteralPath $out)) 'D6_OUTPUT_ALREADY_EXISTS'
[void][IO.Directory]::CreateDirectory($out)
$root=Split-Path -Parent $PSScriptRoot;$runRoot=Split-Path -Parent ([IO.Path]::GetFullPath($VerdictsPath))
$manifest=Read-D6Json (Join-Path $root 'd6/d6-reference-manifest.json')
$promptPath=Join-Path $root $manifest.fixed_prompt;$prompt=[IO.File]::ReadAllText($promptPath)
Assert-D6 ((Get-D6Hash $promptPath)-ceq$manifest.fixed_prompt_sha256) 'D6_PROMPT_HASH_MISMATCH'
$identity=$run.candidate_identity_sha256
$captures=Join-Path $runRoot 'captures';$controlRoot=$runRoot;$control=Join-Path $captures 'active-arena.png'
if((Get-D6Frame $control)-cne'healthy'-and$CaptureHealthRunRoot){
    $controlRoot=[IO.Path]::GetFullPath($CaptureHealthRunRoot)
    $controlRun=Read-D6Json (Join-Path $controlRoot 'verdicts.json')
    Assert-D6 ($controlRun.run_status-ceq'completed'-and@($controlRun.faults).Count-eq0) 'D6_CONTROL_RUN_INVALID'
    $control=Join-Path $controlRoot 'captures/active-arena.png'
}
Assert-D6 ((Get-D6Frame $control)-ceq'healthy') 'D6_CAPTURE_HEALTH_UNAVAILABLE'
[void][IO.Directory]::CreateDirectory((Join-Path $out 'health'))
Copy-Item -LiteralPath $control -Destination (Join-Path $out 'health/control.png')
Write-Record @{status='healthy';candidate_identity_sha256=$identity;control_sha256=(Get-D6Hash $control);source_run=$(if($controlRoot-ceq$runRoot){$run.run_id}else{$controlRun.run_id});source_verdicts_sha256=(Get-D6Hash (Join-Path $controlRoot 'verdicts.json'));capture_receipt_sha256=(Get-D6Hash (Join-Path $controlRoot 'receipts/capture-active-arena.json'))} (Join-Path $out 'health/receipt.json')
$health=@{status='healthy';control_image='health/control.png';control_sha256=(Get-D6Hash $control);receipt='health/receipt.json';receipt_sha256=(Get-D6Hash (Join-Path $out 'health/receipt.json'))}
$states=@();$pairs=@{}
foreach($state in $manifest.states){
    $id=$state.state_id;$reference=Assert-D6Artifact (Join-Path $root 'd6') $state.reference_image $state.sha256
    $candidate=Join-Path $captures ($id+'.png');$status=Get-D6Frame $candidate
    Assert-D6 ($status-cin@('healthy','missing','black_or_blank')) 'D6_CAPTURE_INFRASTRUCTURE_FAULT'
    $attribution=if($status-ceq'healthy'){'none'}else{'candidate'}
    $receipt='receipts/'+$id+'.json'
    Write-Record @{state_id=$id;candidate_identity_sha256=$identity;status=$status;attribution=$attribution;source_run=$run.run_id} (Join-Path $out $receipt)
    $states+=@{state_id=$id;status=$status;attribution=$attribution;receipt=$receipt;receipt_sha256=(Get-D6Hash (Join-Path $out $receipt))}
    $pairs[$id]=@{reference=$reference;candidate=$candidate;status=$status}
}
$parameters=@{max_completion_tokens=8192;image_detail='high'};$model=@{id=$ModelId;version=$null;parameters=$parameters};$rounds=@();$requestCount=0
for($round=1;$round-le3;$round++){
    $records=@()
    foreach($state in $manifest.states){
        $id=$state.state_id;$pair=$pairs[$id]
        if($pair.status-cne'healthy'){$records+=@{state_id=$id;request=$null;response=$null};continue}
        $requestId=[guid]::NewGuid().ToString('N');$label="round-$round-$id"
        Assert-D6 (-not[string]::IsNullOrWhiteSpace($key)) 'D6_API_KEY_UNAVAILABLE'
        $text=$prompt.Replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',$state.label)
        $content=@(@{type='text';text=$text})
        foreach($path in @($pair.reference,$pair.candidate)){$content+=@{type='image_url';image_url=@{url=('data:image/png;base64,'+[Convert]::ToBase64String([IO.File]::ReadAllBytes($path)));detail='high'}}}
        $payload=@{model=$ModelId;max_completion_tokens=8192;messages=@(@{role='user';content=$content})}
        # Raw artifacts retain exactly what was sent and received; headers and
        # credentials are never written to the evidence directory.
        Write-Record $payload (Join-Path $out "raw/$label-request.json")
        $response=Invoke-RestMethod -Uri ($BaseUrl.AbsoluteUri.TrimEnd('/')+'/chat/completions') -Method Post -Headers @{Authorization=('Bearer '+$key)} -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 30 -Compress))) -TimeoutSec 60
        Write-Record $response (Join-Path $out "raw/$label-response.json")
        $requestCount++
        $returned=[string]$response.model
        Assert-D6 (-not[string]::IsNullOrWhiteSpace($returned)) 'D6_MODEL_IDENTITY_MISSING'
        if($null-eq$model.version){$model.version=$returned}else{Assert-D6 ($model.version-ceq$returned) 'D6_MODEL_CHANGED'}
        $answer=[string]$response.choices[0].message.content
        $null=ConvertFrom-D6Response $answer
        $request=@{request_id=$requestId;model=$model;prompt=$text;images=@(@{role='reference';sha256=$state.sha256},@{role='candidate';sha256=(Get-D6Hash $pair.candidate)})}
        $records+=@{state_id=$id;request=$request;response=@{request_id=$requestId;model=$model;text=$answer}}
        Write-Output "D6 round=$round state=$id collected"
    }
    $rounds+=@{round=$round;states=$records}
}
if($requestCount-eq0){
    # No visual judgement is made for unreachable frames. Bind the configured
    # version explicitly instead of inventing a returned provider identity.
    $model.version=if($ModelVersion){$ModelVersion}else{$ModelId}
}
$bundle=@{schema_version='3.0.0';game_id='ActionRoguelike';candidate_id=$run.candidate_id;candidate_identity_sha256=$identity;prompt_sha256=(Get-D6Hash $promptPath);model=$model;capture_health=$health;states=$states;rounds=$rounds}
$bundlePath=Join-Path $out 'bundle.json';Write-Record $bundle $bundlePath
Write-Record @{status='healthy';model=$model;version_source=$(if($requestCount){'provider_response'}else{'configured_no_vlm_requests'});requests=$requestCount;reference_manifest_sha256=(Get-D6Hash (Join-Path $root 'd6/d6-reference-manifest.json'));raw_evidence='raw/'} (Join-Path $out 'capability.json')
& (Join-Path $PSScriptRoot 'Invoke-ActionRoguelikeD6Aggregation.ps1') -CandidateCapturesDirectory $captures -CandidateId $run.candidate_id -CandidateIdentitySha256 $identity -ModelId $ModelId -ResponsesPath $bundlePath -OutputDirectory (Join-Path $out 'aggregate')
