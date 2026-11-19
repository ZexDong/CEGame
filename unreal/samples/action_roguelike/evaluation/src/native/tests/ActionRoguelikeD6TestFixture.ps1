# Disposable, synthetic protocol fixture. Never edits a checked-in reference.
function Write-TestD6Json($Value,[string]$Path){New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force|Out-Null;[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100)+"`n",[Text.UTF8Encoding]::new($false))}
function New-TestD6Fixture([string]$SourceRoot,[string]$TempRoot){
    $root=Join-Path $TempRoot 'evaluator';New-Item -ItemType Directory -Path $root -Force|Out-Null
    foreach($name in @('scripts','catalog','schemas')){Copy-Item -LiteralPath (Join-Path $SourceRoot $name) -Destination $root -Recurse}
    New-Item -ItemType Directory -Path (Join-Path $root 'd6/reference') -Force|Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'd6/FIXED_VLM_PROMPT.txt') -Destination (Join-Path $root 'd6/FIXED_VLM_PROMPT.txt')
    . (Join-Path $root 'scripts/ActionRoguelikeD6Protocol.ps1')
    $evidence=Join-Path $TempRoot 'evidence';$captures=Join-Path $TempRoot 'candidate';New-Item -ItemType Directory -Path $captures,(Join-Path $evidence 'health'),(Join-Path $evidence 'receipts') -Force|Out-Null
    Add-Type -AssemblyName System.Drawing.Common
    $bitmap=[Drawing.Bitmap]::new(1280,720);$graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{$graphics.Clear([Drawing.Color]::CornflowerBlue);$bitmap.Save((Join-Path $evidence 'health/control.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
    Write-TestD6Json @{synthetic_test=$true;status='healthy';candidate_identity_sha256=('a'*64);control_sha256=(Get-D6Hash (Join-Path $evidence 'health/control.png'))} (Join-Path $evidence 'health/receipt.json')
    Write-TestD6Json @{synthetic_test=$true;source='generated_unit_test_image';source_identity_sha256=('d'*64)} (Join-Path $root 'd6/reference/provenance.json')
    $states=@();$captureStates=@();foreach($id in @('active-arena','black-hole-combat','terminal-result')){
        Copy-Item -LiteralPath (Join-Path $evidence 'health/control.png') -Destination (Join-Path $root ('d6/reference/'+$id+'.png'))
        Copy-Item -LiteralPath (Join-Path $evidence 'health/control.png') -Destination (Join-Path $captures ($id+'.png'))
        Write-TestD6Json @{synthetic_test=$true;state_id=$id;status='healthy';attribution='none';candidate_identity_sha256=('a'*64)} (Join-Path $evidence ('receipts/'+$id+'.json'))
        $states+=@{state_id=$id;label=$id;reference_image=('reference/'+$id+'.png');sha256=(Get-D6Hash (Join-Path $root ('d6/reference/'+$id+'.png')));width=1280;height=720;source='original_baseline';provenance=@{source_identity_sha256=('d'*64);reference_metadata='reference/provenance.json';reference_metadata_sha256=(Get-D6Hash (Join-Path $root 'd6/reference/provenance.json'))}}
        $captureStates+=@{state_id=$id;status='healthy';attribution='none';receipt=('receipts/'+$id+'.json');receipt_sha256=(Get-D6Hash (Join-Path $evidence ('receipts/'+$id+'.json')))}
    }
    $promptPath=Join-Path $root 'd6/FIXED_VLM_PROMPT.txt';$prompt=[IO.File]::ReadAllText($promptPath);$hash=Get-D6Hash $promptPath
    $manifest=@{schema_version='4.0.0';protocol='canonical_d6_v4';reference_status='ready';fixed_prompt='d6/FIXED_VLM_PROMPT.txt';fixed_prompt_sha256=$hash;states=$states};Write-TestD6Json $manifest (Join-Path $root 'd6/d6-reference-manifest.json')
    $model=@{id='unit-vlm';version='test-version-1';parameters=@{temperature=0;top_p=1;seed=123;max_output_tokens=512;image_detail='high'}}
    $rounds=@();for($round=1;$round-le3;$round++){$records=@();foreach($s in $states){$rid="test-$round-$($s.state_id)";$request=@{request_id=$rid;model=$model;prompt=$prompt.Replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',$s.label);images=@(@{role='reference';sha256=$s.sha256},@{role='candidate';sha256=$s.sha256})};$response=@{request_id=$rid;model=$model;text="Scene completeness and asset assembly:2/2`nComposition and layout:2/2`nScale, hierarchy, and clarity:2/2`nStyle and color consistency:2/2`nOverall polish:2/2`nTotal:10/10`nReason:The scene is complete."};$records+=@{state_id=$s.state_id;request=$request;response=$response}};$rounds+=@{round=$round;states=$records}}
    $bundle=@{schema_version='3.0.0';game_id='ActionRoguelike';candidate_id='unit';candidate_identity_sha256=('a'*64);prompt_sha256=$hash;model=$model;capture_health=@{status='healthy';control_image='health/control.png';control_sha256=(Get-D6Hash (Join-Path $evidence 'health/control.png'));receipt='health/receipt.json';receipt_sha256=(Get-D6Hash (Join-Path $evidence 'health/receipt.json'))};states=$captureStates;rounds=$rounds};$bundlePath=Join-Path $evidence 'bundle.json';Write-TestD6Json $bundle $bundlePath
    return @{root=$root;captures=$captures;evidence=$evidence;bundle_path=$bundlePath;bundle=$bundle;manifest=$manifest}
}
function Invoke-TestD6($Fixture,[string]$Output){
    Write-TestD6Json $Fixture.bundle $Fixture.bundle_path
    $path=& (Join-Path $Fixture.root 'scripts/Invoke-ActionRoguelikeD6Aggregation.ps1') -CandidateCapturesDirectory $Fixture.captures -CandidateId unit -CandidateIdentitySha256 ('a'*64) -ModelId unit-vlm -ResponsesPath $Fixture.bundle_path -OutputDirectory $Output
    return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
}
function Remove-TestD6Temp([string]$Temp){
    $resolved=[IO.Path]::GetFullPath($Temp);$expected=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($resolved)-notmatch'^actionroguelike-(d6|scorer)-[0-9a-f]{32}$'){throw 'Unsafe test cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
