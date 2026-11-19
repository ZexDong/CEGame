#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$CandidateEvidenceDirectory = '',
    [string]$OutputRoot = '',
    [ValidateSet('gpt-5.6-sol')][string]$Model = 'gpt-5.6-sol',
    [ValidateRange(3, 3)][int]$Rounds = 3,
    [ValidateRange(2, 30)][int]$DeadlineMinutesPerCall = 10,
    [switch]$Execute,
    [switch]$ParserSelfTest,
    [string]$BaseUrl = $env:D6_BASE_URL,
    [string]$ApiKeyEnvironment = 'D6_API_KEY'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EvaluationRoot = Split-Path -Parent $PSScriptRoot
$VisualRoot = Join-Path $EvaluationRoot 'visual'
$ManifestPath = Join-Path $VisualRoot 'manifest.json'
$AllowedScores = @(0.0, 0.5, 1.0, 1.5, 2.0)
$ResponseKeys = @(
    'Scene completeness and asset assembly', 'Composition and layout', 'Scale, hierarchy, and clarity',
    'Style and color consistency', 'Overall polish')
function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-Inside([string]$Path, [string]$Root) {
    $full = Get-FullPath $Path
    $rootFull = Get-FullPath $Root
    return [string]::Equals($full, $rootFull, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Text)))).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Write-Text([string]$Path, [AllowEmptyString()][string]$Text) {
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-Json([string]$Path, $Value, [int]$Depth = 50) {
    Write-Text -Path $Path -Text ($Value | ConvertTo-Json -Depth $Depth)
}

function Round-One([double]$Value) {
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

function Test-Image([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered]@{ valid = $false; status = 'missing'; width = 0; height = 0; sha256 = $null }
    }
    $stream = $null
    $image = $null
    try {
        Add-Type -AssemblyName System.Drawing
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
            [IO.FileShare]::Read)
        $image = [Drawing.Image]::FromStream($stream, $true, $true)
        $valid = $image.Width -gt 1 -and $image.Height -gt 1
        return [ordered]@{
            valid = $valid
            status = if ($valid) { 'decoded' } else { 'invalid_dimensions' }
            width = [int]$image.Width
            height = [int]$image.Height
            bytes = [long](Get-Item -LiteralPath $Path).Length
            sha256 = Get-Sha256 $Path
        }
    }
    catch {
        return [ordered]@{
            valid = $false; status = 'undecodable'; width = 0; height = 0
            bytes = [long](Get-Item -LiteralPath $Path).Length
            sha256 = Get-Sha256 $Path; error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $image) { $image.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function New-StatePrompt([string]$BasePrompt, [string]$Label) {
    $placeholder = '<short state label: menu, initial gameplay, mid/late game, management, success, or failure>'
    if (-not $BasePrompt.Contains($placeholder, [StringComparison]::Ordinal)) {
        throw 'Frozen visual prompt is missing its exact state placeholder.'
    }
    return $BasePrompt.Replace($placeholder, $Label, [StringComparison]::Ordinal)
}

function Parse-VisualResponse([string]$Text) {
    $normalized = $Text.Replace("`r`n", "`n").Trim()
    # Keep the seven-line protocol strict, but do not reject an otherwise
    # exact response only because the model emitted harmless horizontal
    # whitespace at a line boundary.  The category names, order, score grid,
    # totals, and non-empty reason remain fully validated below.
    $lines = @($normalized -split "`n" | ForEach-Object { $_.Trim() })
    if ($lines.Count -ne 7) { throw "D6 response must contain exactly seven lines; found $($lines.Count)." }
    $values = [ordered]@{}
    for ($index = 0; $index -lt 5; $index++) {
        $match = [regex]::Match($lines[$index],
            '^' + [regex]::Escape($ResponseKeys[$index]) + ':(?<score>[0-2](?:\.0|\.5)?)/2$')
        if (-not $match.Success) { throw "Malformed D6 category line: $($lines[$index])" }
        $score = [double]::Parse($match.Groups['score'].Value,
            [Globalization.CultureInfo]::InvariantCulture)
        if ($score -notin $AllowedScores) { throw "Unsupported D6 category score: $score" }
        $values[$ResponseKeys[$index]] = $score
    }
    $totalMatch = [regex]::Match($lines[5],
        '^Total:(?<score>(?:10(?:\.0)?|[0-9](?:\.0|\.5)?))/10$')
    if (-not $totalMatch.Success) { throw "Malformed D6 total line: $($lines[5])" }
    $declared = [double]::Parse($totalMatch.Groups['score'].Value,
        [Globalization.CultureInfo]::InvariantCulture)
    $computed = Round-One ((@($values.Values) | Measure-Object -Sum).Sum)
    if ([Math]::Abs($declared - $computed) -gt 0.0001) {
        throw "D6 total $declared does not equal category sum $computed."
    }
    if ($lines[6] -notmatch '^Reason:\S') { throw 'D6 reason line is missing or empty.' }
    return [ordered]@{
        scene_assembly = [double]$values[$ResponseKeys[0]]
        composition_layout = [double]$values[$ResponseKeys[1]]
        scale_layering_clarity = [double]$values[$ResponseKeys[2]]
        style_color_cohesion = [double]$values[$ResponseKeys[3]]
        overall_finish = [double]$values[$ResponseKeys[4]]
        total = $computed
        reason = $lines[6].Substring('Reason:'.Length).Trim()
        raw_seven_lines = $normalized
    }
}

function New-ZeroResponse([string]$Reason) {
    $raw = @"
Scene completeness and asset assembly:0/2
Composition and layout:0/2
Scale, hierarchy, and clarity:0/2
Style and color consistency:0/2
Overall polish:0/2
Total:0/10
Reason:Candidate screenshot $Reason; score zero under the missing-state rule.
"@.Trim()
    return [ordered]@{ raw = $raw; parsed = Parse-VisualResponse $raw }
}

function New-VisualRequest([string]$PromptText, [string]$Reference, [string]$Candidate) {
    $images = @($Reference, $Candidate | ForEach-Object {
        [pscustomobject]@{
            type = 'input_image'
            image_url = 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($_))
            detail = 'high'
        }
    })
    return [pscustomobject]@{
        model = $Model
        input = @([pscustomobject]@{
            role = 'user'
            content = @([pscustomobject]@{ type = 'input_text'; text = $PromptText }) + $images
        })
        store = $false
    }
}

function Invoke-VisualReview(
    $Payload, [string]$RequestPath, [string]$ResponsePath, [int]$TimeoutSeconds = 600) {
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        throw 'Supply -BaseUrl or D6_BASE_URL for the visual-review service.'
    }
    $uri = $null
    if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('https', 'http') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Visual-review base URL must be an HTTP(S) API root without credentials or query parameters.'
    }
    $apiKey = [Environment]::GetEnvironmentVariable($ApiKeyEnvironment)
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'The visual-review API credential environment variable is empty.'
    }
    $requestText = $Payload | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($RequestPath, $requestText, [Text.UTF8Encoding]::new($false))
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $content = [Net.Http.StringContent]::new($requestText, [Text.Encoding]::UTF8, 'application/json')
    $response = $null
    try {
        $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $apiKey)
        $actor = [Environment]::GetEnvironmentVariable('D6_ACTOR_AUTHORIZATION')
        if (-not [string]::IsNullOrWhiteSpace($actor)) {
            $client.DefaultRequestHeaders.Add('x-openai-actor-authorization', $actor)
        }
        $response = $client.PostAsync($BaseUrl.TrimEnd('/') + '/responses', $content).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        [IO.File]::WriteAllText($ResponsePath, $body, [Text.UTF8Encoding]::new($false))
        if (-not $response.IsSuccessStatusCode) {
            throw "Visual-review service returned HTTP $([int]$response.StatusCode)."
        }
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        $content.Dispose()
        $client.Dispose()
    }
    $raw = $body | ConvertFrom-Json
    if ([string]$raw.status -cne 'completed' -or
        [string]::IsNullOrWhiteSpace([string]$raw.id) -or
        [string]$raw.model -cne $Model -or
        @($raw.output | Where-Object { [string]$_.type -notin @('message', 'reasoning') }).Count -ne 0) {
        throw 'Visual-review response is incomplete, has an unexpected model, or used a tool.'
    }
    $messages = @($raw.output | Where-Object { [string]$_.type -ceq 'message' })
    if ($messages.Count -ne 1 -or [string]$messages[0].role -cne 'assistant' -or
        @($messages[0].content).Count -ne 1 -or
        [string]$messages[0].content[0].type -cne 'output_text') {
        throw 'Visual-review response must contain one assistant text response.'
    }
    return [pscustomobject]@{
        text = [string]$messages[0].content[0].text
        response_id = [string]$raw.id
        model = [string]$raw.model
        usage = $raw.usage
        request_path = $RequestPath
        request_sha256 = Get-Sha256 $RequestPath
        response_path = $ResponsePath
        response_sha256 = Get-Sha256 $ResponsePath
    }
}

if ($ParserSelfTest) {
    $fixture = @"
  Scene completeness and asset assembly:2/2  
Composition and layout:1.5/2
Scale, hierarchy, and clarity:1/2
Style and color consistency:0.5/2
Overall polish:0/2
Total:5/10  
Reason:parser fixture.  
"@
    $parsed = Parse-VisualResponse $fixture
    if ($parsed.total -ne 5.0) { throw 'Parser self-test failed.' }
    [ordered]@{ valid = $true; parsed = $parsed } | ConvertTo-Json -Depth 10
    exit 0
}

if ([string]::IsNullOrWhiteSpace($CandidateEvidenceDirectory) -or
    [string]::IsNullOrWhiteSpace($OutputRoot)) {
    throw 'CandidateEvidenceDirectory and OutputRoot are required unless -ParserSelfTest is used.'
}

$CandidateEvidenceDirectory = (Resolve-Path -LiteralPath $CandidateEvidenceDirectory).Path
$OutputRoot = Get-FullPath $OutputRoot
if (Test-Inside $OutputRoot $EvaluationRoot) {
    throw 'Visual output must be outside the distributed evaluator.'
}
if ($Execute -and (Test-Path -LiteralPath $OutputRoot)) {
    throw "Visual output already exists; refusing to mix evidence: $OutputRoot"
}

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
if ([int]$manifest.required_rounds -ne 3 -or @($manifest.states).Count -ne 3 -or $Rounds -ne 3) {
    throw 'Dungeon Duel D6 is frozen to exactly three states and three rounds.'
}
$promptPath = Join-Path $VisualRoot ([string]$manifest.prompt_file)
$promptText = Get-Content -Raw -Encoding UTF8 -LiteralPath $promptPath
$promptHash = Get-Sha256 $promptPath
if ($promptHash -cne ([string]$manifest.prompt_sha256).ToLowerInvariant()) {
    throw 'Frozen D6 prompt hash mismatch.'
}

$states = [System.Collections.Generic.List[object]]::new()
foreach ($state in @($manifest.states)) {
    $reference = Join-Path $VisualRoot ([string]$state.reference_file)
    $candidate = Join-Path $CandidateEvidenceDirectory (
        'visual-candidates\' + [string]$state.candidate_file)
    $referenceCheck = Test-Image $reference
    if (-not [bool]$referenceCheck.valid -or
        [string]$referenceCheck.sha256 -cne ([string]$state.reference_sha256).ToLowerInvariant()) {
        throw "Reference image is missing, unreadable, or hash-mismatched: $($state.id)"
    }
    $candidateCheck = Test-Image $candidate
    $states.Add([ordered]@{
        id = [string]$state.id; label = [string]$state.label
        reference = (Resolve-Path -LiteralPath $reference).Path
        reference_check = $referenceCheck
        candidate = Get-FullPath $candidate
        candidate_check = $candidateCheck
        candidate_policy = if ([bool]$candidateCheck.valid) { 'three_vlm_calls' } else { 'zero_each_round_without_model_call' }
    })
}

$preflight = [ordered]@{
    schema_version = 1; execute = [bool]$Execute; valid = $true
    protocol = 'dungeon-duel-three-state-three-round-20260826'
    benchmark_id = [string]$manifest.benchmark_id
    model = $Model
    required_rounds = $Rounds; state_count = $states.Count
    prompt = [ordered]@{ path = $promptPath; sha256 = $promptHash }
    manifest = [ordered]@{ path = $ManifestPath; sha256 = Get-Sha256 $ManifestPath }
    candidate_evidence_directory = $CandidateEvidenceDirectory
    output_root = $OutputRoot
    states = @($states)
}
if (-not $Execute) { $preflight | ConvertTo-Json -Depth 20; exit 0 }

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
Write-Json -Path (Join-Path $OutputRoot 'preflight.json') -Value $preflight
Write-Text -Path (Join-Path $OutputRoot 'frozen-prompt.txt') -Text $promptText
[IO.File]::Copy($ManifestPath, (Join-Path $OutputRoot 'visual-manifest.json'), $true)

$bindings = @($states | ForEach-Object {
    [ordered]@{
        id = $_.id
        reference_sha256 = $_.reference_check.sha256
        candidate_sha256 = if ([bool]$_.candidate_check.valid) { $_.candidate_check.sha256 } else { '' }
    }
})
$roundDocuments = [System.Collections.Generic.List[object]]::new()
$totalUsage = [ordered]@{
    input_tokens = 0L; output_tokens = 0L; total_tokens = 0L
}

$responseIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
for ($round = 1; $round -le $Rounds; $round++) {
    $roundRoot = Join-Path $OutputRoot ('round-{0:d2}' -f $round)
    New-Item -ItemType Directory -Force -Path $roundRoot | Out-Null
    $stateDocuments = [System.Collections.Generic.List[object]]::new()
    $rawSections = [System.Collections.Generic.List[string]]::new()
    foreach ($state in @($states)) {
        $callRoot = Join-Path $roundRoot ([string]$state.id)
        New-Item -ItemType Directory -Force -Path $callRoot | Out-Null
        $statePrompt = New-StatePrompt $promptText ([string]$state.label)
        $promptFile = Join-Path $callRoot 'prompt.txt'
        Write-Text -Path $promptFile -Text $statePrompt
        $finalPath = Join-Path $callRoot 'final-response.txt'

        if (-not [bool]$state.candidate_check.valid) {
            $zero = New-ZeroResponse "has status $($state.candidate_check.status)"
            Write-Text -Path $finalPath -Text $zero.raw
            $parsed = $zero.parsed
            $call = [ordered]@{
                schema_version = 1; round = $round; state_id = $state.id
                status = 'candidate_missing_scored_zero'; model_called = $false
                prompt_sha256 = Get-TextSha256 $statePrompt
                reference_sha256 = $state.reference_check.sha256
                candidate_sha256 = $null; candidate_status = $state.candidate_check.status
                final_response = $finalPath; final_response_sha256 = Get-Sha256 $finalPath
                parsed = $parsed
            }
        }
        else {
            $requestPath = Join-Path $callRoot 'request.json'
            $responsePath = Join-Path $callRoot 'provider-response.json'
            $request = New-VisualRequest $statePrompt $state.reference $state.candidate
            $response = Invoke-VisualReview $request $requestPath $responsePath ($DeadlineMinutesPerCall * 60)
            if (-not $responseIds.Add($response.response_id)) { throw 'Visual-review response ID was reused.' }
            Write-Text -Path $finalPath -Text $response.text
            $events = [ordered]@{
                response_id = $response.response_id
                request_path = $requestPath; request_sha256 = $response.request_sha256
                response_path = $responsePath; response_sha256 = $response.response_sha256
                usage = [ordered]@{
                    input_tokens = [long]$response.usage.input_tokens
                    output_tokens = [long]$response.usage.output_tokens
                    total_tokens = [long]$response.usage.total_tokens
                }
            }
            foreach ($name in @($totalUsage.Keys)) {
                $totalUsage[$name] = [long]$totalUsage[$name] + [long]$events.usage[$name]
            }
            $parsed = Parse-VisualResponse (Get-Content -Raw -Encoding UTF8 -LiteralPath $finalPath)
            $call = [ordered]@{
                schema_version = 1; round = $round; state_id = $state.id
                status = 'evaluated'; model_called = $true
                request = $requestPath; provider_response = $responsePath; evidence = $events
                prompt_sha256 = Get-TextSha256 $statePrompt
                reference_sha256 = $state.reference_check.sha256
                candidate_sha256 = $state.candidate_check.sha256
                final_response = $finalPath; final_response_sha256 = Get-Sha256 $finalPath
                parsed = $parsed
            }
        }
        Write-Json -Path (Join-Path $callRoot 'call.json') -Value $call
        $rawSections.Add("STATE $($state.id)`n$($parsed.raw_seven_lines)")
        $stateDocuments.Add([ordered]@{
            id = $state.id
            scene_assembly = [double]$parsed.scene_assembly
            composition_layout = [double]$parsed.composition_layout
            scale_layering_clarity = [double]$parsed.scale_layering_clarity
            style_color_cohesion = [double]$parsed.style_color_cohesion
            overall_finish = [double]$parsed.overall_finish
            total = [double]$parsed.total
            reason = [string]$parsed.reason
        })
    }
    $rawRelative = 'raw/round-{0}.txt' -f $round
    $rawPath = Join-Path $OutputRoot $rawRelative
    Write-Text -Path $rawPath -Text ($rawSections -join "`n`n")
    $stateTotals = @($stateDocuments | ForEach-Object { [double]$_['total'] })
    $average = Round-One (($stateTotals | Measure-Object -Average).Average)
    $roundDocuments.Add([ordered]@{
        round = $round; model_id = $Model
        raw_response_file = $rawRelative
        raw_response_sha256 = Get-Sha256 $rawPath
        states = @($stateDocuments); average = $average
    })
}

$roundAverages = @($roundDocuments | ForEach-Object { [double]$_['average'] })
$finalScore = Round-One (($roundAverages | Measure-Object -Average).Average)
$score = [ordered]@{
    schema_version = 2
    benchmark_id = [string]$manifest.benchmark_id
    prompt_sha256 = $promptHash
    image_bindings = @($bindings)
    rounds = @($roundDocuments)
    final_score = $finalScore
    protocol = 'dungeon-duel-three-state-three-round-20260826'
    evidence = [ordered]@{
        model = $Model
        manifest_sha256 = Get-Sha256 $ManifestPath
        candidate_evidence_directory = $CandidateEvidenceDirectory
        missing_candidate_policy = 'zero_each_round_without_model_call'
        usage = $totalUsage
    }
}
$scorePath = Join-Path $OutputRoot 'visual-score.json'
Write-Json -Path $scorePath -Value $score
Write-Json -Path (Join-Path $OutputRoot 'd6-result.json') -Value ([ordered]@{
    schema_version = 1; valid = $true; status = 'evaluated'; dimension = 'D6'
    protocol = $score.protocol; model = $Model
    required_rounds = $Rounds; state_count = $states.Count
    rounds = @($roundDocuments | ForEach-Object {
        [ordered]@{ round = $_.round; average = $_.average; state_scores = @($_.states | ForEach-Object { [ordered]@{ id = $_.id; score = $_.total } }) }
    })
    score = $finalScore; maximum_score = 10.0; usage = $totalUsage
    score_file = $scorePath; score_file_sha256 = Get-Sha256 $scorePath
})

$artifactPath = Join-Path $OutputRoot 'artifact-manifest.json'
$files = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -File -Force |
    Where-Object { $_.FullName -ne $artifactPath } | Sort-Object FullName |
    ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($OutputRoot.Length).TrimStart('\').Replace('\', '/')
            bytes = [long]$_.Length; sha256 = Get-Sha256 $_.FullName
        }
    })
Write-Json -Path $artifactPath -Value ([ordered]@{ schema_version = 1; files = $files })
$score | ConvertTo-Json -Depth 20
exit 0
