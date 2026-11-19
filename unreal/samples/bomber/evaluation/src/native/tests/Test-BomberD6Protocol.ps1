[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot 'TestFixture.ps1')
Import-Module (Join-Path $root 'scripts/BomberD6.psm1') -Force
Import-Module (Join-Path $root 'scripts/BomberObservation.psm1') -Force
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$valid=@'
Scene completeness and asset assembly:2/2
Composition and layout:1.5/2
Scale, hierarchy, and clarity:1/2
Style and color consistency:0.5/2
Overall polish:2/2
Total:7/10
Reason:Synthetic unit fixture.
'@
$parsed=ConvertFrom-BomberVisualResponse $valid
Assert ($parsed.score -eq 7 -and @($parsed.criteria.PSObject.Properties).Count -eq 5) 'Canonical response was not parsed.'
foreach($bad in @($valid.Replace('Total:7','Total:8'),$valid.Replace('1.5/2','1.7/2'),'{"state_scores":[7,7,7]}')){
    $rejected=$false;try{ConvertFrom-BomberVisualResponse $bad|Out-Null}catch{$rejected=$true};Assert $rejected 'Malformed or obsolete visual response was accepted.'
}
$fixture=New-BomberTestFixture $root
try{
    $run=Join-Path $fixture.temp 'run';$captures=Join-Path $run 'captures';[void](New-Item -ItemType Directory -Path $captures -Force)
    $manifest=@{candidate_id='unit';candidate_identity_sha256=('a'*64)};$manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $run 'candidate-manifest.json')
    $output=& (Join-Path $fixture.root 'scripts/Invoke-BomberD6Aggregation.ps1') -CandidateCapturesDirectory $captures -CandidateId unit -CandidateIdentitySha256 ('a'*64) -ModelId unit-vlm -OutputDirectory (Join-Path $run 'missing')
    $zero=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json -Depth 100
    Assert ($zero.score -eq 0 -and @($zero.rounds).Count -eq 3) 'Candidate missing images did not get numeric zero.'
    & (Join-Path $fixture.root 'scripts/Invoke-BomberD6Vlm.ps1') -RunDirectory $run -EvaluatorRoot $fixture.root -Model unit-vlm|Out-Null
    $binding=Get-Content -LiteralPath (Join-Path $run 'vlm/binding.json') -Raw|ConvertFrom-Json
    Assert ($binding.independent_calls -eq 0) 'Missing candidate states made unnecessary API calls.'
    $image=Join-Path $captures 'active-arena.png';Copy-Item -LiteralPath (Join-Path $fixture.root 'd6/reference/active-duel.png') -Destination $image
    $rejected=$false;try{Assert-BomberSemanticCapture $image active-duel ('a'*64)}catch{$rejected=$_.Exception.Message -match 'D6_SEMANTIC_EVIDENCE_MISSING'};Assert $rejected 'An image without semantic capture proof was accepted.'
    $before=@{process_token='test';round_id='r1';monotonic_ms=100;game_state=@{phase='active'}};$after=@{process_token='test';round_id='r1';monotonic_ms=200;game_state=@{phase='active'}}
    $proof=@{status='bound';state_id='active-duel';candidate_identity_sha256=('a'*64);capture_sha256=(Get-FileHash -LiteralPath $image).Hash.ToLowerInvariant();before=$before;after=$after;native_capture=@{producer='ue-native-viewport';status='ok';process_token='test';width=1280;height=720;monotonic_ms=150}}
    $sidecar=[IO.Path]::ChangeExtension($image,'.semantic.json');$proof|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $sidecar
    Assert-BomberSemanticCapture $image active-duel ('a'*64)
    $proof.native_capture.producer='desktop';$proof|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $sidecar
    $rejected=$false;try{Assert-BomberSemanticCapture $image active-duel ('a'*64)}catch{$rejected=$true};Assert $rejected 'A desktop capture was accepted.'
    $reference=Get-Content -LiteralPath (Join-Path $fixture.root 'd6/d6-reference-manifest.json') -Raw|ConvertFrom-Json
    $pairs=@();$map=@{'active-duel'='active-arena';'chain-reaction'='chain-reaction';'player1-win'='player1-win'}
    foreach($state in $reference.states){
        $image=Join-Path $captures "$($map[$state.state_id]).png"
        Copy-Item -LiteralPath (Join-Path $fixture.root "d6/$($state.reference_image)") -Destination $image -Force
        $phase=if($state.state_id -eq 'player1-win'){'player1_win'}else{'active'}
        $shape=@{phase=$phase;bombs=@();explosion_cells=@(@{x=1;y=1},@{x=3;y=1})}
        $before=@{process_token='test';round_id='r1';monotonic_ms=100;game_state=$shape};$after=@{process_token='test';round_id='r1';monotonic_ms=200;game_state=$shape}
        $expected=@{process_token='test';round_id='r1';bombs=@(@{object_id='a';cell=@{x=1;y=1}},@{object_id='b';cell=@{x=3;y=1}})}
        $imageHash=(Get-FileHash -LiteralPath $image).Hash.ToLowerInvariant()
        $proof=@{status='bound';state_id=$state.state_id;candidate_identity_sha256=('a'*64);capture_sha256=$imageHash;before=$before;after=$after;chain_expectation=$expected;native_capture=@{producer='ue-native-viewport';status='ok';process_token='test';width=1280;height=720;monotonic_ms=150}}
        $proof|ConvertTo-Json -Depth 100|Set-Content -LiteralPath ([IO.Path]::ChangeExtension($image,'.semantic.json'))
        $pairs+=@{state_id=$state.state_id;candidate_sha256=$imageHash;reference_sha256=$state.sha256}
    }
    function VisualText([double]$Score){
        $remaining=$Score;$lines=@(foreach($label in @('Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish')){$n=[Math]::Min(2.0,[double]$remaining);$remaining-=$n;"${label}:$($n.ToString([Globalization.CultureInfo]::InvariantCulture))/2"})
        return ($lines+"Total:$($Score.ToString([Globalization.CultureInfo]::InvariantCulture))/10"+'Reason:Synthetic fixture.' -join "`n")
    }
    $rounds=@(foreach($r in 1..3){$scores=if($r -eq 1){@(3.5,0,0)}elseif($r -eq 2){@(0.5,0,0)}else{@(0,0,0)};@{round=$r;states=@(for($i=0;$i -lt 3;++$i){@{state_id=$reference.states[$i].state_id;response_text=VisualText $scores[$i]}})}})
    $responses=@{schema_version='2.0.0';protocol='canonical_five_criteria_three_rounds';model_id='unit-vlm';candidate_identity_sha256=('a'*64);prompt_sha256=(Get-FileHash -LiteralPath (Join-Path $fixture.root 'd6/FIXED_VLM_PROMPT.txt')).Hash.ToLowerInvariant();reference_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $fixture.root 'd6/d6-reference-manifest.json')).Hash.ToLowerInvariant();pairs=$pairs;rounds=$rounds}
    $responsePath=Join-Path $run 'responses.json';$responses|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $responsePath
    $output=& (Join-Path $fixture.root 'scripts/Invoke-BomberD6Aggregation.ps1') -CandidateCapturesDirectory $captures -CandidateId unit -CandidateIdentitySha256 ('a'*64) -ModelId unit-vlm -ResponsesPath $responsePath -OutputDirectory (Join-Path $run 'healthy')
    $value=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json -Depth 100
    Assert ($value.score -eq 0.4 -and $value.rounds[0].score -eq 1.2 -and $value.rounds[1].score -eq 0.2) 'Final score was calculated from prematurely rounded round means.'
    $responses.pairs[0].candidate_sha256='b'*64;$responses|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $responsePath
    $rejected=$false;try{& (Join-Path $fixture.root 'scripts/Invoke-BomberD6Aggregation.ps1') -CandidateCapturesDirectory $captures -CandidateId unit -CandidateIdentitySha256 ('a'*64) -ModelId unit-vlm -ResponsesPath $responsePath -OutputDirectory (Join-Path $run 'mismatch')|Out-Null}catch{$rejected=$_.Exception.Message -match 'D6_RESPONSE_IMAGE_BINDING_INVALID'};Assert $rejected 'Responses for another image were accepted.'
    $referencePath=Join-Path $fixture.root 'd6/d6-reference-manifest.json';$m=Get-Content -LiteralPath $referencePath -Raw|ConvertFrom-Json;$m.status='original_captures_required';$m|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $referencePath
    $rejected=$false;try{Assert-BomberOriginalReferences $fixture.root|Out-Null}catch{$rejected=$_.Exception.Message -match 'D6_ORIGINAL_REFERENCES_REQUIRED'};Assert $rejected 'Missing original references were treated as candidate zero.'
    Write-Output 'D6_PROTOCOL_OK canonical_parser=true original_reference_gate=true native_semantic_binding=true candidate_missing_zero=true healthy_aggregation=true full_precision_average=true response_image_binding=true'
}finally{Remove-BomberTestFixture $fixture.temp}
