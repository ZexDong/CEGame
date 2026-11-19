[CmdletBinding()]param()
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
. (Join-Path $PSScriptRoot 'ActionRoguelikeD6TestFixture.ps1')
$source=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('actionroguelike-d6-'+[guid]::NewGuid().ToString('N'))
try{
    $fixture=New-TestD6Fixture $source $temp
    . (Join-Path $fixture.root 'scripts/ActionRoguelikeD6Configuration.ps1')
    $savedEndpoint=[Environment]::GetEnvironmentVariable('NEWAPI_BASE_URL');$savedModel=[Environment]::GetEnvironmentVariable('NEWAPI_MODEL_ID')
    try{
        [Environment]::SetEnvironmentVariable('NEWAPI_BASE_URL',$null);[Environment]::SetEnvironmentVariable('NEWAPI_MODEL_ID',$null)
        $missingConfigurationRejected=$false
        try{$null=Resolve-ActionRoguelikeD6Configuration}catch{$missingConfigurationRejected=$true}
        Assert $missingConfigurationRejected 'Missing explicit configuration must not read a user profile provider.'
        $configPath=Join-Path $temp 'provider.toml'
        [IO.File]::WriteAllText($configPath,"model = `"unit-model`"`nmodel_provider = `"unit-provider`"`n[model_providers.unit-provider]`nbase_url = `"https://unit.invalid/v1`"`n")
        $resolved=Resolve-ActionRoguelikeD6Configuration -ConfigurationPath $configPath
        Assert ($resolved.model_id-ceq'unit-model'-and$resolved.base_url.AbsoluteUri-ceq'https://unit.invalid/v1') 'Explicit provider configuration was not resolved.'
        [Environment]::SetEnvironmentVariable('NEWAPI_MODEL_ID','environment-model')
        $resolved=Resolve-ActionRoguelikeD6Configuration -ConfigurationPath $configPath
        Assert ($resolved.model_id-ceq'environment-model') 'Environment model did not override local provider metadata.'
    }finally{[Environment]::SetEnvironmentVariable('NEWAPI_BASE_URL',$savedEndpoint);[Environment]::SetEnvironmentVariable('NEWAPI_MODEL_ID',$savedModel)}
    $runRoot=Join-Path $temp 'run'
    [void][IO.Directory]::CreateDirectory($runRoot)
    Copy-Item -LiteralPath $fixture.captures -Destination (Join-Path $runRoot 'captures') -Recurse
    $verdict=@{run_id='synthetic-collector-test';candidate_id='unit';candidate_identity_sha256=('a'*64);run_status='completed';mode='canonical_independent_atomic_cases';faults=@()}
    Write-TestD6Json $verdict (Join-Path $runRoot 'verdicts.json')
    Write-TestD6Json @{status='ok';synthetic_test=$true} (Join-Path $runRoot 'receipts/capture-active-arena.json')
    $d6TestState=@{calls=0;answer=$fixture.bundle.rounds[0].states[0].response.text}
    function Invoke-RestMethod($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec){
        $payload=[Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json
        Assert ($payload.messages[0].content.Count-eq3) 'Request omitted the reference/candidate image pair.'
        $d6TestState.calls++
        return @{model='test-returned-version';choices=@(@{message=@{content=$d6TestState.answer}})}
    }
    [Environment]::SetEnvironmentVariable('AR_D6_TEST_KEY','synthetic-unit-test-only')
    $collector=Join-Path $fixture.root 'scripts/Invoke-ActionRoguelikeD6Collection.ps1'
    $out=Join-Path $temp 'collected'
    $null=& $collector -VerdictsPath (Join-Path $runRoot 'verdicts.json') -BaseUrl https://unit.invalid/v1 -ModelId unit-vlm -ApiKeyEnvironment AR_D6_TEST_KEY -OutputDirectory $out
    $result=Get-Content (Join-Path $out 'aggregate/d6-run.json') -Raw|ConvertFrom-Json
    Assert ($d6TestState.calls-eq9-and$result.status-ceq'completed'-and$result.score-eq10) 'The live collector did not preserve nine protocol-valid calls.'
    Assert (@(Get-ChildItem (Join-Path $out 'raw') -File).Count-eq18) 'Raw request/response pairs were not retained.'
    Assert (-not((Get-Content (Join-Path $out 'raw/round-1-active-arena-request.json') -Raw).Contains('synthetic-unit-test-only'))) 'Authentication leaked into raw evidence.'
    $empty=Join-Path $temp 'empty'
    [void][IO.Directory]::CreateDirectory((Join-Path $empty 'captures'))
    Write-TestD6Json $verdict (Join-Path $empty 'verdicts.json')
    $zeroOut=Join-Path $temp 'zero-collected'
    $null=& $collector -VerdictsPath (Join-Path $empty 'verdicts.json') -BaseUrl https://unit.invalid/v1 -ModelId unit-vlm -ModelVersion test-returned-version -CaptureHealthRunRoot $runRoot -ApiKeyEnvironment AR_D6_TEST_KEY -OutputDirectory $zeroOut
    $zero=Get-Content (Join-Path $zeroOut 'aggregate/d6-run.json') -Raw|ConvertFrom-Json
    Assert ($d6TestState.calls-eq9-and$zero.status-ceq'completed'-and$zero.score-eq0) 'Missing candidate frames invoked a model or failed to produce attributed zeroes.'
    Write-Output 'ACTIONROGUELIKE_D6_COLLECTION_OK requests=9 raw_pairs=9 independent_capture_control=true all_missing_zero=true'
}finally{
    [Environment]::SetEnvironmentVariable('AR_D6_TEST_KEY',$null)
    if(Test-Path -LiteralPath $temp){Remove-TestD6Temp $temp}
}
