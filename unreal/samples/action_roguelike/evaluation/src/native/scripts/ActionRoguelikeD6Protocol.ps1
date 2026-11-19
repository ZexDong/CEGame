# Shared canonical D6 validation. All assertions apply to imported evidence and
# scorer replay alike; no candidate result is accepted from a claimed total.
Set-StrictMode -Version Latest
function Assert-D6([bool]$Condition,[string]$Code) { if (-not $Condition) { throw $Code } }
function Get-D6Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-D6TextHash([string]$Text) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant() }
function ConvertTo-D6Canonical($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [Collections.IDictionary]) {
        $sortedKeys=[string[]]@($Value.Keys);[Array]::Sort($sortedKeys,[StringComparer]::Ordinal)
        $parts=@(foreach($key in $sortedKeys){($key|ConvertTo-Json -Compress)+':'+(ConvertTo-D6Canonical $Value[$key])})
        return '{'+($parts -join ',')+'}'
    }
    if ($Value -is [array]) { return '['+(@(foreach($v in $Value){ConvertTo-D6Canonical $v}) -join ',')+']' }
    return ($Value|ConvertTo-Json -Compress -Depth 50)
}
function Read-D6Json([string]$Path) {
    $text=[IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false,$true))
    $doc=[Text.Json.JsonDocument]::Parse($text)
    try {
        function Check-Keys($node) {
            if($node.ValueKind -eq [Text.Json.JsonValueKind]::Object){
                $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach($p in $node.EnumerateObject()){Assert-D6 ($keys.Add($p.Name)) 'D6_JSON_DUPLICATE_KEY';Check-Keys $p.Value}
            } elseif($node.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($v in $node.EnumerateArray()){Check-Keys $v}}
        }
        Check-Keys $doc.RootElement
    } finally {$doc.Dispose()}
    return ConvertFrom-Json -InputObject $text -AsHashtable -Depth 100
}
function Assert-D6Keys($Value,[string[]]$Keys) {
    Assert-D6 ($Value -is [Collections.IDictionary]) 'D6_OBJECT_REQUIRED'
    Assert-D6 ((@($Value.Keys|Sort-Object -CaseSensitive) -join '|') -ceq (@($Keys|Sort-Object -CaseSensitive) -join '|')) 'D6_OBJECT_KEYS_INVALID'
}
function Resolve-D6File([string]$Root,[string]$Relative) {
    Assert-D6 (-not [string]::IsNullOrWhiteSpace($Relative) -and -not [IO.Path]::IsPathRooted($Relative)) 'D6_EVIDENCE_PATH_INVALID'
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $full=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    Assert-D6 ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) 'D6_EVIDENCE_PATH_ESCAPE'
    $cursor=$full
    while($cursor.Length -ge $base.TrimEnd('\','/').Length){if(Test-Path -LiteralPath $cursor){Assert-D6 (((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'D6_EVIDENCE_REPARSE_POINT'};$cursor=Split-Path -Parent $cursor;if(-not $cursor){break}}
    return $full
}
function Assert-D6Artifact([string]$Root,[string]$Path,[string]$Hash) {
    $p=Resolve-D6File $Root $Path
    Assert-D6 ($Hash -cmatch '^[0-9a-f]{64}$' -and (Test-Path -LiteralPath $p -PathType Leaf)) 'D6_EVIDENCE_MISSING'
    Assert-D6 ((Get-D6Hash $p) -ceq $Hash) 'D6_EVIDENCE_HASH_MISMATCH'
    return $p
}
function Get-D6Frame([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return 'missing'}
    Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop
    $bitmap=$null
    try {
        $bitmap=[Drawing.Bitmap]::new($Path)
        if($bitmap.Width-ne1280-or$bitmap.Height-ne720){return 'wrong_resolution'}
        $max=0.0;$sum=0.0;$sumSq=0.0;$count=0
        for($y=10;$y-lt720;$y+=40){for($x=10;$x-lt1280;$x+=40){$p=$bitmap.GetPixel($x,$y);$l=.2126*$p.R+.7152*$p.G+.0722*$p.B;$max=[Math]::Max($max,$l);$sum+=$l;$sumSq+=$l*$l;++$count}}
        $mean=$sum/$count;$variance=[Math]::Max(0,($sumSq/$count)-($mean*$mean))
        if($max-lt18-or([Math]::Sqrt($variance)-lt2-and$mean-lt30)){return 'black_or_blank'}
        return 'healthy'
    } catch {return 'invalid_image'} finally {if($bitmap){$bitmap.Dispose()}}
}
function ConvertFrom-D6Response([string]$Text) {
    # The guide's exact seven-line response is parsed once per image pair.
    $labels=@('Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish')
    $normalized=$Text.Replace("`r`n","`n")
    if($normalized.EndsWith("`n")){$normalized=$normalized.Substring(0,$normalized.Length-1)}
    $lines=@($normalized -split "`n")
    Assert-D6 ($lines.Count-eq7) 'D6_RESPONSE_LINE_COUNT'
    $components=@()
    for($i=0;$i-lt5;$i++){
        $match=[regex]::Match($lines[$i],'^'+[regex]::Escape($labels[$i])+':(0(?:\.0)?|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)/2$')
        Assert-D6 $match.Success 'D6_RESPONSE_COMPONENT_INVALID'
        $components += [double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    }
    $sum=[double](($components|Measure-Object -Sum).Sum)
    $total=[regex]::Match($lines[5],'^Total:((?:[0-9]|10)(?:\.[05])?)/10$')
    Assert-D6 $total.Success 'D6_RESPONSE_TOTAL_INVALID'
    Assert-D6 ([double]::Parse($total.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)-eq$sum) 'D6_RESPONSE_TOTAL_MISMATCH'
    Assert-D6 ($lines[6] -cmatch '^Reason:\S[^\r\n]*$') 'D6_RESPONSE_RATIONALE_INVALID'
    $rationale=$lines[6].Substring('Reason:'.Length)
    Assert-D6 (@([regex]::Matches($rationale,'[.!?!?]+|\.(?=\s|$)')).Count-le2) 'D6_RESPONSE_RATIONALE_TOO_LONG'
    return @{components=$components;score_raw=$sum;score=$sum;rationale=$rationale}
}
function Get-D6Evaluation([string]$EvaluatorRoot,[string]$CapturesRoot,[string]$BundlePath,[string]$CandidateId,[string]$Identity,[string]$ModelId) {
    $manifestPath=Join-Path $EvaluatorRoot 'd6/d6-reference-manifest.json'
    $promptPath=Join-Path $EvaluatorRoot 'd6/FIXED_VLM_PROMPT.txt'
    $manifest=Read-D6Json $manifestPath;$prompt=[IO.File]::ReadAllText($promptPath);$promptHash=Get-D6Hash $promptPath
    Assert-D6 ($manifest.protocol-ceq'canonical_d6_v4'-and$manifest.fixed_prompt_sha256-ceq$promptHash-and@($manifest.states).Count-ge3-and@($manifest.states).Count-le5) 'D6_REFERENCE_MANIFEST_INVALID'
    Assert-D6 ($manifest.reference_status-ceq'ready') 'D6_REFERENCE_PROVENANCE_INVALID'
    $stateIds=@($manifest.states|ForEach-Object{$_.state_id})
    Assert-D6 (@($stateIds|Sort-Object -Unique).Count-eq$stateIds.Count) 'D6_REFERENCE_DUPLICATE_STATE'
    foreach($ref in $manifest.states){
        Assert-D6 ($ref.state_id-cmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'-and$ref.label-is[string]-and$ref.label-notmatch'[\r\n]'-and-not[string]::IsNullOrWhiteSpace($ref.label)) 'D6_REFERENCE_STATE_INVALID'
        Assert-D6 ($ref.source-cin@('original_game_derived','original-derived','original_baseline')) 'D6_REFERENCE_PROVENANCE_INVALID'
        $referencePath=Assert-D6Artifact (Join-Path $EvaluatorRoot 'd6') $ref.reference_image $ref.sha256
        Assert-D6 ((Get-D6Frame $referencePath)-ceq'healthy') 'D6_REFERENCE_FRAME_INVALID'
        Assert-D6 ($ref.provenance-is[Collections.IDictionary]-and$ref.provenance.source_identity_sha256-cmatch'^[0-9a-f]{64}$') 'D6_REFERENCE_PROVENANCE_INVALID'
        $null=Assert-D6Artifact (Join-Path $EvaluatorRoot 'd6') $ref.provenance.reference_metadata $ref.provenance.reference_metadata_sha256
    }
    Assert-D6 (-not[string]::IsNullOrWhiteSpace($BundlePath)) 'D6_EVIDENCE_BUNDLE_MISSING'
    $bundle=Read-D6Json $BundlePath;$evidenceRoot=Split-Path -Parent $BundlePath
    Assert-D6Keys $bundle @('schema_version','game_id','candidate_id','candidate_identity_sha256','prompt_sha256','model','capture_health','states','rounds')
    Assert-D6 ($bundle.schema_version-ceq'3.0.0'-and$bundle.game_id-ceq'ActionRoguelike'-and$bundle.candidate_id-ceq$CandidateId-and$bundle.candidate_identity_sha256-ceq$Identity-and$bundle.prompt_sha256-ceq$promptHash) 'D6_BUNDLE_IDENTITY_INVALID'
    Assert-D6Keys $bundle.model @('id','version','parameters')
    Assert-D6 ($bundle.model.id-ceq$ModelId-and-not[string]::IsNullOrWhiteSpace($ModelId)-and$bundle.model.version-is[string]-and-not[string]::IsNullOrWhiteSpace($bundle.model.version)-and$bundle.model.parameters-is[Collections.IDictionary]-and$bundle.model.parameters.Count-gt0) 'D6_MODEL_CONFIGURATION_INVALID'
    $modelJson=ConvertTo-D6Canonical $bundle.model;$modelHash=Get-D6TextHash $modelJson
    Assert-D6Keys $bundle.capture_health @('status','control_image','control_sha256','receipt','receipt_sha256')
    Assert-D6 ($bundle.capture_health.status-ceq'healthy') 'D6_CAPTURE_INFRASTRUCTURE_FAULT'
    $control=Assert-D6Artifact $evidenceRoot $bundle.capture_health.control_image $bundle.capture_health.control_sha256
    Assert-D6 ((Get-D6Frame $control)-ceq'healthy') 'D6_CAPTURE_INFRASTRUCTURE_FAULT'
    $healthReceiptPath=Assert-D6Artifact $evidenceRoot $bundle.capture_health.receipt $bundle.capture_health.receipt_sha256
    $healthReceipt=Read-D6Json $healthReceiptPath
    Assert-D6 ($healthReceipt.status-ceq'healthy'-and$healthReceipt.candidate_identity_sha256-ceq$Identity-and$healthReceipt.control_sha256-ceq$bundle.capture_health.control_sha256) 'D6_CAPTURE_HEALTH_RECEIPT_INVALID'
    Assert-D6 (@($bundle.states).Count-eq$stateIds.Count-and@($bundle.rounds).Count-eq3) 'D6_STATE_OR_ROUND_SET_INVALID'
    $states=@();$copyArtifacts=@($bundle.capture_health.control_image,$bundle.capture_health.receipt)
    for($i=0;$i-lt$stateIds.Count;$i++){
        $record=$bundle.states[$i];$ref=$manifest.states[$i];$id=$stateIds[$i]
        Assert-D6Keys $record @('state_id','status','attribution','receipt','receipt_sha256')
        Assert-D6 ($record.state_id-ceq$id) 'D6_STATE_ORDER_INVALID'
        $receiptPath=Assert-D6Artifact $evidenceRoot $record.receipt $record.receipt_sha256;$copyArtifacts+=$record.receipt
        $captureReceipt=Read-D6Json $receiptPath
        Assert-D6 ($captureReceipt.state_id-ceq$id-and$captureReceipt.candidate_identity_sha256-ceq$Identity-and$captureReceipt.status-ceq$record.status-and$captureReceipt.attribution-ceq$record.attribution) 'D6_CAPTURE_RECEIPT_IDENTITY_INVALID'
        $capture=Resolve-D6File $CapturesRoot ($id+'.png');$status=Get-D6Frame $capture
        Assert-D6 ($status-ceq$record.status) 'D6_CAPTURE_RECEIPT_MISMATCH'
        Assert-D6 ($status-cin@('healthy','missing','black_or_blank')) 'D6_CAPTURE_INFRASTRUCTURE_FAULT'
        Assert-D6 ($(if($status-ceq'healthy'){$record.attribution-ceq'none'}else{$record.attribution-ceq'candidate'})) 'D6_CAPTURE_ATTRIBUTION_INVALID'
        $hash=if($status-ceq'missing'){$null}else{Get-D6Hash $capture}
        $states+=@{state_id=$id;candidate_status=$status;candidate_sha256=$hash;reference_sha256=$ref.sha256;receipt=$record.receipt;receipt_sha256=$record.receipt_sha256}
    }
    $rounds=@();$rawRecords=@();$requestIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for($ri=0;$ri-lt3;$ri++){
        $round=$bundle.rounds[$ri];Assert-D6Keys $round @('round','states')
        Assert-D6 ($round.round-is[long]-or$round.round-is[int]) 'D6_ROUND_NUMBER_INVALID'
        Assert-D6 ($round.round-eq($ri+1)-and@($round.states).Count-eq$states.Count) 'D6_ROUND_SET_INVALID'
        $scores=@()
        for($si=0;$si-lt$states.Count;$si++){
            $state=$states[$si];$record=$round.states[$si];$id=$state.state_id
            Assert-D6Keys $record @('state_id','request','response')
            Assert-D6 ($record.state_id-ceq$id) 'D6_STATE_ORDER_INVALID'
            if($state.candidate_status-ceq'healthy'){
                $req=$record.request;$resp=$record.response
                Assert-D6Keys $req @('request_id','model','prompt','images')
                Assert-D6 ($req.request_id-is[string]-and-not[string]::IsNullOrWhiteSpace($req.request_id)-and$requestIds.Add($req.request_id)) 'D6_REQUEST_ID_INVALID'
                Assert-D6 ((ConvertTo-D6Canonical $req.model)-ceq$modelJson) 'D6_MODEL_CONFIGURATION_MISMATCH'
                $expectedPrompt=$prompt.Replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',$manifest.states[$si].label)
                Assert-D6 ($req.prompt-ceq$expectedPrompt) 'D6_REQUEST_PROMPT_MISMATCH'
                Assert-D6 (@($req.images).Count-eq2) 'D6_REQUEST_IMAGES_INVALID'
                foreach($img in $req.images){Assert-D6Keys $img @('role','sha256')}
                Assert-D6 ($req.images[0].role-ceq'reference'-and$req.images[0].sha256-ceq$state.reference_sha256-and$req.images[1].role-ceq'candidate'-and$req.images[1].sha256-ceq$state.candidate_sha256) 'D6_REQUEST_IMAGES_INVALID'
                Assert-D6Keys $resp @('request_id','model','text')
                Assert-D6 ($resp.request_id-ceq$req.request_id-and(ConvertTo-D6Canonical $resp.model)-ceq$modelJson-and$resp.text-is[string]) 'D6_RESPONSE_IDENTITY_INVALID'
                $score=ConvertFrom-D6Response $resp.text;$score.source='vlm';$score.reason_code=$null
                $score.request_sha256=Get-D6TextHash (ConvertTo-D6Canonical $req);$score.response_sha256=Get-D6TextHash (ConvertTo-D6Canonical $resp)
                $rawRecords+=@{round=($ri+1);state_id=$id;request=$req;response=$resp}
            }else{
                Assert-D6 ($null-eq$record.request-and$null-eq$record.response) 'D6_AUTOMATIC_ZERO_MUST_NOT_HAVE_VLM_RESPONSE'
                $score=@{components=@(0,0,0,0,0);score_raw=0.0;score=0.0;rationale=('Candidate '+$state.candidate_status);source='automatic_zero';reason_code=$(if($state.candidate_status-ceq'missing'){'D6_CANDIDATE_STATE_MISSING'}else{'D6_CANDIDATE_BLACK_SCREEN'});request_sha256=$null;response_sha256=$null}
            }
            $score.state_id=$id;$scores+=$score
        }
        $mean=[double](($scores|ForEach-Object{$_.score_raw}|Measure-Object -Average).Average)
        $rounds+=@{round=($ri+1);states=$scores;score_raw=$mean;score=[Math]::Round($mean,1,[MidpointRounding]::AwayFromZero)}
    }
    $raw=[double](($rounds|ForEach-Object{$_.score_raw}|Measure-Object -Average).Average)
    return @{model=$bundle.model;vlm_config_sha256=$modelHash;states=$states;rounds=$rounds;score_raw=$raw;score=[Math]::Round($raw,1,[MidpointRounding]::AwayFromZero);reference_manifest_sha256=(Get-D6Hash $manifestPath);prompt_sha256=$promptHash;raw_records=$rawRecords;copy_artifacts=$copyArtifacts}
}
