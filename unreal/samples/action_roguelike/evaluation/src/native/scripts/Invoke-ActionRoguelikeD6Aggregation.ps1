[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateCapturesDirectory,
    [Parameter(Mandatory)][string]$CandidateId,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$CandidateIdentitySha256,
    [Parameter(Mandatory)][string]$ModelId,
    [string]$ResponsesPath,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ActionRoguelikeD6Protocol.ps1')
function Write-D6Json($Value,[string]$Path){$parent=Split-Path -Parent $Path;New-Item -ItemType Directory -Path $parent -Force|Out-Null;[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100)+"`n",[Text.UTF8Encoding]::new($false))}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$out=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $out){Assert-D6 (@(Get-ChildItem -LiteralPath $out -Force).Count-eq0) 'D6_OUTPUT_NOT_EMPTY'}
New-Item -ItemType Directory -Path $out -Force|Out-Null
$result=[ordered]@{schema_version='4.0.0';game_id='ActionRoguelike';task_revision='2.2.0-diagnostic';evaluator_revision='actionroguelike-evaluator-4.1.0';candidate_id=$CandidateId;candidate_identity_sha256=$CandidateIdentitySha256;protocol='canonical_d6_v4';status='run_invalid';faults=@();model_id=$ModelId;model=$null;vlm_version=$null;vlm_config_sha256=$null;reference_manifest_sha256=$null;prompt_sha256=$null;evidence_bundle='responses.json';evidence_bundle_sha256=$null;states=@();rounds=@();score_raw=$null;score=$null}
try {
    if($ResponsesPath){$ResponsesPath=[IO.Path]::GetFullPath($ResponsesPath)}
    $data=Get-D6Evaluation $root ([IO.Path]::GetFullPath($CandidateCapturesDirectory)) $ResponsesPath $CandidateId $CandidateIdentitySha256 $ModelId
    # Copy only explicitly bound artifacts, never scan candidate/history folders.
    Copy-Item -LiteralPath $ResponsesPath -Destination (Join-Path $out 'responses.json')
    foreach($rel in @($data.copy_artifacts|Sort-Object -Unique)){
        $source=Resolve-D6File (Split-Path -Parent $ResponsesPath) $rel;$target=Resolve-D6File $out $rel
        $canonicalRelative=[IO.Path]::GetRelativePath($out,$target).Replace('\','/')
        Assert-D6 ($canonicalRelative -notmatch '^(responses\.json|d6-run\.json|captures/|rounds/)') 'D6_RESERVED_EVIDENCE_PATH'
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null;Copy-Item -LiteralPath $source -Destination $target
    }
    New-Item -ItemType Directory -Path (Join-Path $out 'captures') -Force|Out-Null
    foreach($state in $data.states){if($state.candidate_status-cne'missing'){Copy-Item -LiteralPath (Join-Path $CandidateCapturesDirectory ($state.state_id+'.png')) -Destination (Join-Path $out ('captures/'+$state.state_id+'.png'))}}
    foreach($record in $data.raw_records){
        $base=Join-Path $out ('rounds/'+$record.round+'/'+$record.state_id)
        New-Item -ItemType Directory -Path $base -Force|Out-Null
        [IO.File]::WriteAllText((Join-Path $base 'request.json'),(ConvertTo-D6Canonical $record.request),[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $base 'response.json'),(ConvertTo-D6Canonical $record.response),[Text.UTF8Encoding]::new($false))
    }
    # Replay copied bytes to catch changed captures or evidence during copying.
    $replay=Get-D6Evaluation $root (Join-Path $out 'captures') (Join-Path $out 'responses.json') $CandidateId $CandidateIdentitySha256 $ModelId
    Assert-D6 ((ConvertTo-D6Canonical $replay)-ceq(ConvertTo-D6Canonical $data)) 'D6_EVIDENCE_CHANGED_DURING_COPY'
    foreach($key in @('states','rounds','score_raw','score','vlm_config_sha256','reference_manifest_sha256','prompt_sha256','model')){$result[$key]=$data[$key]}
    $result.vlm_version=$data.model.version;$result.evidence_bundle_sha256=Get-D6Hash (Join-Path $out 'responses.json');$result.status='completed'
} catch {
    $result.status='run_invalid';$result.faults=@(@{code=$(if($_.Exception.Message-cmatch'^D6_[A-Z_]+$'){$_.Exception.Message}else{'D6_PROTOCOL_OR_INFRASTRUCTURE_FAULT'});attribution='evaluator';detail=$_.Exception.Message})
    # Preserve supplied raw evidence even when parsing or provider validation fails.
    if($ResponsesPath-and(Test-Path -LiteralPath $ResponsesPath -PathType Leaf)-and-not(Test-Path -LiteralPath (Join-Path $out 'responses.json'))){Copy-Item -LiteralPath $ResponsesPath -Destination (Join-Path $out 'responses.json')}
    if(Test-Path -LiteralPath (Join-Path $out 'responses.json')){$result.evidence_bundle_sha256=Get-D6Hash (Join-Path $out 'responses.json')}
    $result.score_raw=$null;$result.score=$null
}
$path=Join-Path $out 'd6-run.json';Write-D6Json $result $path;Write-Output $path
