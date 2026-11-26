[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$EvaluatorRoot,
    [string]$BaseUrl,
    [string]$Model,
    [ValidateRange(1,240)][int]$TimeoutSeconds = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonFile([object]$Value, [string]$Path) {
    $parent = Split-Path -Parent $Path
    if ($parent) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText("$Path.tmp", (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move("$Path.tmp", $Path, $true)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Sha256Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-ImageDataUri([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    return 'data:image/png;base64,' + [Convert]::ToBase64String($bytes)
}

function Get-EnvValue([string[]]$Names) {
    foreach ($name in $Names) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $null
}

function Invoke-VlmRequest([string]$Uri, [string]$ApiKey, [object]$Payload, [int]$Timeout) {
    $json = $Payload | ConvertTo-Json -Depth 100 -Compress
    $headers = @{ Authorization = "Bearer $ApiKey" }
    try {
        $transport = Invoke-WebRequest -Method Post -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $json -TimeoutSec $Timeout
        # Persist the original body before decoding JSON, including malformed bodies.
        return [string]$transport.Content
    }
    catch { throw "VLM_REQUEST_FAILED:$($_.Exception.GetType().Name): transport failed; no candidate score was assigned." }
}

function Read-VlmResponse([string]$Path) {
    try {
        $value=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
        if([string]::IsNullOrWhiteSpace([string]$value.model) -or @($value.choices).Count -ne 1 -or $value.choices[0].message.content -isnot [string]) { throw 'shape' }
    } catch { throw 'VLM_RESPONSE_ENVELOPE_INVALID' }
    return $value
}

function Archive-VlmEvidence([string[]]$Paths, [string]$Root) {
    $existing=@($Paths|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf})
    if(-not $existing.Count){return}
    $archive=Join-Path $Root ('attempts/'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $archive -Force)
    foreach($path in $existing){Move-Item -LiteralPath $path -Destination $archive}
}

$runFull=[IO.Path]::GetFullPath($RunDirectory)
$evaluatorFull=[IO.Path]::GetFullPath($EvaluatorRoot)
Import-Module (Join-Path $evaluatorFull 'scripts/BomberD6.psm1') -Force
Import-Module (Join-Path $evaluatorFull 'scripts/BomberObservation.psm1') -Force
Assert-BomberD6Protocol $evaluatorFull
$manifest=Assert-BomberOriginalReferences $evaluatorFull
$candidate=Get-Content -LiteralPath (Join-Path $runFull 'candidate-manifest.json') -Raw|ConvertFrom-Json
$d6Root=Join-Path $evaluatorFull 'd6'
$promptPath=Join-Path $d6Root 'FIXED_VLM_PROMPT.txt'
$prompt=Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$modelBinding=Get-Content -LiteralPath (Join-Path $d6Root 'model-binding.json') -Raw|ConvertFrom-Json
$requestedModel=if($Model){$Model}else{Get-EnvValue @('BOMBER_VLM_MODEL')}
if(-not $requestedModel){$requestedModel=$modelBinding.default_model}
$output=Join-Path $runFull 'vlm'
$map=@{'active-duel'='active-arena';'chain-reaction'='chain-reaction';'player1-win'='player1-win'}
$pairs=[Collections.Generic.List[object]]::new()
foreach($state in $manifest.states){
    $path=Join-Path $runFull "captures/$($map[$state.state_id]).png"
    Assert-BomberSemanticCapture $path $state.state_id $candidate.candidate_identity_sha256
    $health=Get-BomberD6CaptureHealth $path
    $label=if($state.PSObject.Properties['visual_label']){[string]$state.visual_label}else{[string]$state.state_id}
    $pairs.Add([pscustomobject]@{state_id=$state.state_id;visual_label=$label;reference_path=(Join-Path $d6Root $state.reference_image);reference_sha256=$state.sha256;candidate_path=$path;candidate_sha256=$health.sha256;candidate_status=$health.status;reason_code=$health.reason_code})
}
$apiKey=$null
if(@($pairs|Where-Object candidate_status -eq 'healthy').Count){
    $apiKey=Get-EnvValue @('D6_API_KEY','OPENAI_API_KEY')
    if(-not $apiKey){throw 'VLM_CONFIGURATION_REQUIRED'}
    if(-not $BaseUrl){$BaseUrl=Get-EnvValue @('BOMBER_VLM_BASE_URL','OPENAI_BASE_URL')}
    if(-not $BaseUrl){throw 'VLM_BASE_URL_REQUIRED'}
}
$rounds=[Collections.Generic.List[object]]::new();$returnedModel=$null;$calls=0;$httpAttempts=0
$pairHashes=@($pairs|Select-Object state_id,reference_sha256,candidate_sha256,candidate_status,reason_code)
$binding=[ordered]@{schema_version='2.2.0';protocol='canonical_five_criteria_three_rounds';status='running';model_requested=$requestedModel;model_returned=$null;independent_calls=0;http_attempts=0;rounds=3;pairs=$pairHashes;credential_persisted=$false;transport=$modelBinding.transport;parameters=[ordered]@{max_tokens=[int]$modelBinding.max_tokens;sampling=$modelBinding.sampling;timeout_seconds=[Math]::Min($TimeoutSeconds,[int]$modelBinding.timeout_seconds);image_detail='high';max_request_bytes=8MB};prompt_sha256=Get-Sha256 $promptPath;model_binding_sha256=Get-Sha256 (Join-Path $d6Root 'model-binding.json')}
$invocation=[ordered]@{candidate_identity_sha256=$candidate.candidate_identity_sha256;reference_manifest_sha256=Get-Sha256 (Join-Path $d6Root 'd6-reference-manifest.json');endpoint_sha256=Get-Sha256Text ([string]$BaseUrl).TrimEnd('/');binding=$binding}
$binding.invocation_identity_sha256=Get-Sha256Text ($invocation|ConvertTo-Json -Depth 100 -Compress)
# Hold an exclusive file handle so two completion processes cannot issue the same calls.
try{$lock=[IO.File]::Open((Join-Path $runFull 'd6-vlm.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'D6_VLM_RUN_BUSY'}
try {
$bindingPath=Join-Path $output 'binding.json'
if(Test-Path -LiteralPath $bindingPath){
    $previous=Get-Content -LiteralPath $bindingPath -Raw|ConvertFrom-Json -Depth 100
    if($previous.schema_version -cne '2.2.0' -or $previous.invocation_identity_sha256 -cne $binding.invocation_identity_sha256){throw 'D6_VLM_RESUME_IDENTITY_MISMATCH'}
    $returnedModel=$previous.model_returned;$httpAttempts=[int]$previous.http_attempts
}elseif((Test-Path -LiteralPath $output) -and @(Get-ChildItem -LiteralPath $output -Force).Count){throw 'D6_VLM_RESUME_BINDING_MISSING'}
[void](New-Item -ItemType Directory -Path $output -Force)
$binding.model_returned=$returnedModel;$binding.http_attempts=$httpAttempts
Write-JsonFile $binding (Join-Path $output 'binding.json')
$round=0;$pair=$null
try {
for($round=1;$round -le 3;++$round){
    $states=[Collections.Generic.List[object]]::new()
    foreach($pair in $pairs){
        if($pair.candidate_status -ne 'healthy'){$states.Add([ordered]@{state_id=$pair.state_id;response_text=$null;reason_code=$pair.reason_code});continue}
        $statePrompt=$prompt.Replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',$pair.visual_label)
        # Exactly one pair per serial request; never create a multi-state image batch.
        if(((Get-Item -LiteralPath $pair.reference_path).Length+(Get-Item -LiteralPath $pair.candidate_path).Length) -gt 6MB){throw 'D6_VLM_REQUEST_TOO_LARGE'}
        $content=@([ordered]@{type='text';text=$statePrompt},[ordered]@{type='image_url';image_url=[ordered]@{url=Get-ImageDataUri $pair.reference_path;detail='high'}},[ordered]@{type='image_url';image_url=[ordered]@{url=Get-ImageDataUri $pair.candidate_path;detail='high'}})
        $payload=[ordered]@{model=$requestedModel;messages=@([ordered]@{role='user';content=$content});max_tokens=[int]$modelBinding.max_tokens}
        $requestJson=$payload|ConvertTo-Json -Depth 100 -Compress
        if([Text.Encoding]::UTF8.GetByteCount($requestJson) -gt $binding.parameters.max_request_bytes){throw 'D6_VLM_REQUEST_TOO_LARGE'}
        $requestHash=Get-Sha256Text $requestJson
        $stem="round-$round-$($pair.state_id)"
        $requestPath=Join-Path $output "$stem-request.json"
        $responsePath=Join-Path $output "$stem-response.json"
        $checkpointPath=Join-Path $output "$stem.json"
        if(Test-Path -LiteralPath $checkpointPath){
            $checkpoint=Get-Content -LiteralPath $checkpointPath -Raw|ConvertFrom-Json -Depth 100
            $requestReceipt=Get-Content -LiteralPath $requestPath -Raw|ConvertFrom-Json -Depth 100
            if($checkpoint.request_sha256 -cne $requestHash -or $requestReceipt.request_sha256 -cne $requestHash -or $checkpoint.envelope_sha256 -cne (Get-Sha256 $responsePath)){throw 'D6_VLM_RESUME_EVIDENCE_INVALID'}
            $value=Read-VlmResponse $responsePath
        }else{
        # Only an unfinished call is retried on explicit re-invocation. Keep its evidence.
        Archive-VlmEvidence @($requestPath,$responsePath) $output
        # The image bytes are retained in the bound PNGs; this request receipt keeps
        # their order and hashes without duplicating base64 or persisting credentials.
        Write-JsonFile ([ordered]@{round=$round;state_id=$pair.state_id;model=$requestedModel;prompt=$statePrompt;parameters=$binding.parameters;image_order=@('reference','candidate');reference_sha256=$pair.reference_sha256;candidate_sha256=$pair.candidate_sha256;request_sha256=$requestHash}) $requestPath
        ++$httpAttempts;$binding.http_attempts=$httpAttempts;Write-JsonFile $binding $bindingPath
        $body=Invoke-VlmRequest -Uri ($BaseUrl.TrimEnd('/')+'/chat/completions') -ApiKey $apiKey -Payload $payload -Timeout $binding.parameters.timeout_seconds
        [IO.File]::WriteAllText($responsePath,$body,[Text.UTF8Encoding]::new($false))
        $value=Read-VlmResponse $responsePath
        }
        $actual=[string]$value.model
        if(-not $actual -or ($returnedModel -and $returnedModel -cne $actual)){throw 'VLM_MODEL_DRIFT'}
        $returnedModel=$actual; $raw=[string]$value.choices[0].message.content
        $parsed=ConvertFrom-BomberVisualResponse $raw
        Write-JsonFile ([ordered]@{round=$round;state_id=$pair.state_id;model=$actual;request_sha256=$requestHash;reference_sha256=$pair.reference_sha256;candidate_sha256=$pair.candidate_sha256;response_text=$raw;response_sha256=Get-Sha256Text $raw;envelope_sha256=Get-Sha256 $responsePath;parsed=$parsed}) $checkpointPath
        ++$calls;$binding.independent_calls=$calls;$binding.model_returned=$returnedModel;Write-JsonFile $binding $bindingPath
        $states.Add([ordered]@{state_id=$pair.state_id;response_text=$raw})
    }
    $rounds.Add([ordered]@{round=$round;states=@($states)})
}
if(-not $returnedModel){$returnedModel=$requestedModel}
$binding.status='completed';$binding.model_returned=$returnedModel;$binding.independent_calls=$calls
Write-JsonFile $binding (Join-Path $output 'binding.json')
Archive-VlmEvidence @((Join-Path $output 'fault.json')) $output
$result=[ordered]@{schema_version='2.0.0';game_id='Bomber';task_revision='2.0.1';protocol='canonical_five_criteria_three_rounds';candidate_identity_sha256=$candidate.candidate_identity_sha256;prompt_sha256=Get-Sha256 $promptPath;reference_manifest_sha256=Get-Sha256 (Join-Path $d6Root 'd6-reference-manifest.json');model_id=$returnedModel;pairs=$pairHashes;rounds=@($rounds)}
$path=Join-Path $runFull 'd6-vlm-responses.json';Write-JsonFile $result $path;Write-Output $path
} catch {
    $binding.status='run_invalid';$binding.independent_calls=$calls;$binding.model_returned=$returnedModel
    Write-JsonFile $binding (Join-Path $output 'binding.json')
    Archive-VlmEvidence @((Join-Path $output 'fault.json')) $output
    Write-JsonFile (@{status='run_invalid';attribution='infrastructure';reason_code=($_.Exception.Message -split ':')[0];round=$round;state_id=$(if($pair){$pair.state_id}else{$null})}) (Join-Path $output 'fault.json')
    throw
}
}finally{$lock.Dispose()}
