[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateEvidenceDirectory,
    [string]$OutputPath = "",
    [string]$Model = "gpt-5.6-terra",
    [string]$BaseUrl = $env:D6_BASE_URL,
    [string]$ApiKeyEnvironment = "D6_API_KEY",
    [ValidateRange(3, 3)][int]$Rounds = 3,
    [string]$VisualRoot = "",
    [switch]$DryRun,
    [switch]$PromptInputAuditOnly,
    [switch]$ParserSelfTest,
    [switch]$NoExitOnInvalid
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($VisualRoot)) {
    $VisualRoot = Join-Path $evaluationRoot "visual"
}
$VisualRoot = (Resolve-Path -LiteralPath $VisualRoot).Path
$manifestPath = Join-Path $VisualRoot "manifest.json"
$statesPath = Join-Path $VisualRoot "states.json"
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$states = Get-Content -Raw -Encoding UTF8 -LiteralPath $statesPath | ConvertFrom-Json
$promptPath = Join-Path $VisualRoot ([string]$manifest.prompt)
$frozenPromptText = Get-Content -Raw -Encoding UTF8 -LiteralPath $promptPath
$fullWidthColon = [char]0xFF1A
$placeholderOutputLinePattern = '^.+[' +
    [regex]::Escape([string]$fullWidthColon) + ':]<.+>$'
$formatLines = @($frozenPromptText -split '\r?\n' | Where-Object {
    $_ -match '/(2|10)\s*$' -or $_ -match $placeholderOutputLinePattern
})
$frozenCriterionLabels = [System.Collections.Generic.List[string]]::new()
$frozenTotalLabel = $null
$frozenReasonLabel = $null
foreach ($formatLine in $formatLines) {
    $lineMatch = [regex]::Match($formatLine,
        '^(?<label>.+?)[' + [regex]::Escape([string]$fullWidthColon) + ':]')
    if (-not $lineMatch.Success) { continue }
    $label = $lineMatch.Groups['label'].Value.Trim()
    if ($formatLine -match '/2\s*$') { $frozenCriterionLabels.Add($label) }
    elseif ($formatLine -match '/10\s*$') { $frozenTotalLabel = $label }
    else { $frozenReasonLabel = $label }
}
$placeholderMatch = [regex]::Match($frozenPromptText, '<[^<>]+>')
$frozenStatePlaceholder = if ($placeholderMatch.Success) { $placeholderMatch.Value } else { $null }
$CandidateEvidenceDirectory = (Resolve-Path -LiteralPath $CandidateEvidenceDirectory).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $CandidateEvidenceDirectory "visual-score.json"
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$rawDirectory = Join-Path $outputDirectory "visual-raw"
New-Item -ItemType Directory -Path $rawDirectory -Force | Out-Null

function Get-Sha256([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-StringSha256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Round-One([double]$Value) {
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
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

function Read-ScoreLine([string]$Text, [string]$Label) {
    $match = [regex]::Match($Text,
        [regex]::Escape($Label) + '\s*[' + [regex]::Escape([string]$fullWidthColon) + ':]\s*(?<score>\d+(?:\.\d+)?)\s*/\s*2')
    if (-not $match.Success) { throw "Visual response is missing the frozen criterion '$Label'." }
    $value = [double]::Parse($match.Groups["score"].Value,
        [Globalization.CultureInfo]::InvariantCulture)
    if (@(0.0, 0.5, 1.0, 1.5, 2.0) -notcontains $value) {
        throw "$Label returned $value; only 0, 0.5, 1, 1.5, 2 are allowed."
    }
    return $value
}
function Parse-VisualResponse([string]$Text) {
    if ($frozenCriterionLabels.Count -ne 5 -or
        [string]::IsNullOrWhiteSpace($frozenTotalLabel) -or
        [string]::IsNullOrWhiteSpace($frozenReasonLabel)) {
        throw ("Frozen prompt output labels could not be derived exactly " +
            "(criteria={0}, total={1}, reason={2})." -f
            $frozenCriterionLabels.Count,
            (-not [string]::IsNullOrWhiteSpace($frozenTotalLabel)),
            (-not [string]::IsNullOrWhiteSpace($frozenReasonLabel)))
    }
    $assembly = Read-ScoreLine $Text $frozenCriterionLabels[0]
    $layout = Read-ScoreLine $Text $frozenCriterionLabels[1]
    $clarity = Read-ScoreLine $Text $frozenCriterionLabels[2]
    $style = Read-ScoreLine $Text $frozenCriterionLabels[3]
    $finish = Read-ScoreLine $Text $frozenCriterionLabels[4]
    $computed = $assembly + $layout + $clarity + $style + $finish
    $totalMatch = [regex]::Match($Text,
        [regex]::Escape($frozenTotalLabel) + '\s*[' +
        [regex]::Escape([string]$fullWidthColon) + ':]\s*(?<score>\d+(?:\.\d+)?)\s*/\s*10')
    if (-not $totalMatch.Success) { throw "Visual response is missing the frozen total line." }
    $declared = [double]::Parse($totalMatch.Groups["score"].Value,
        [Globalization.CultureInfo]::InvariantCulture)
    if ([Math]::Abs($declared - $computed) -gt 0.001) {
        throw "Visual response total $declared does not equal criterion sum $computed."
    }
    $reasonMatch = [regex]::Match($Text,
        [regex]::Escape($frozenReasonLabel) + '\s*[' +
        [regex]::Escape([string]$fullWidthColon) + ':]\s*(?<reason>.+)',
        [Text.RegularExpressions.RegexOptions]::Singleline)
    return [pscustomobject]@{
        scene_assembly = $assembly; composition_layout = $layout
        scale_layer_clarity = $clarity; style_color = $style
        overall_finish = $finish; score = $computed
        reason = if ($reasonMatch.Success) { $reasonMatch.Groups["reason"].Value.Trim() } else { "" }
    }
}
function Test-PngCandidate([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ usable=$false; kind="missing"; detail="Candidate image is missing." }
    }
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $signature = [byte[]](137,80,78,71,13,10,26,10)
        if ($bytes.Length -lt 33) { throw "PNG is too short." }
        for ($index=0; $index -lt $signature.Length; $index++) {
            if ($bytes[$index] -ne $signature[$index]) { throw "PNG signature is invalid." }
        }
        Add-Type -AssemblyName System.Drawing
        $bitmap = [Drawing.Bitmap]::new($Path)
        try {
            if ($bitmap.Width -lt 2 -or $bitmap.Height -lt 2) { throw "Image dimensions are invalid." }
            $samples = 0; $blackOrTransparent = 0
            $stepX = [Math]::Max(1, [int]($bitmap.Width / 48))
            $stepY = [Math]::Max(1, [int]($bitmap.Height / 27))
            for ($y=0; $y -lt $bitmap.Height; $y += $stepY) {
                for ($x=0; $x -lt $bitmap.Width; $x += $stepX) {
                    $pixel = $bitmap.GetPixel($x,$y); $samples++
                    if ($pixel.A -le 4 -or ($pixel.R -le 8 -and $pixel.G -le 8 -and $pixel.B -le 8)) {
                        $blackOrTransparent++
                    }
                }
            }
            if ($samples -gt 0 -and ($blackOrTransparent / [double]$samples) -ge 0.98) {
                return [pscustomobject]@{ usable=$false; kind="black_or_transparent"; detail="At least 98% of sampled pixels are black or transparent." }
            }
            return [pscustomobject]@{ usable=$true; kind="usable"; detail="$($bitmap.Width)x$($bitmap.Height) PNG decoded." }
        } finally { $bitmap.Dispose() }
    } catch {
        return [pscustomobject]@{ usable=$false; kind="broken"; detail=$_.Exception.Message }
    }
}
function New-ZeroParsed([string]$Reason) {
    return [pscustomobject]@{
        scene_assembly=0.0; composition_layout=0.0; scale_layer_clarity=0.0
        style_color=0.0; overall_finish=0.0; score=0.0; reason=$Reason
    }
}
function Write-VisualReport($Report) {
    $json = $Report | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
    $json
}
function Complete-Invalid($Report, [string]$Status = "invalid_visual") {
    $Report.valid = $false
    $Report.formal_score_complete = $false
    $Report.status = $Status
    $Report.errors = @($errors)
    Write-VisualReport ([pscustomobject]$Report)
    if (-not $NoExitOnInvalid) { exit 7 }
}

if ($ParserSelfTest) {
    if ([string]::IsNullOrWhiteSpace($frozenStatePlaceholder) -or
        -not $frozenPromptText.Contains($frozenStatePlaceholder)) {
        throw "Parser self-test: exact frozen state-label placeholder is missing."
    }
    $selfTestResponse = @(
        "$($frozenCriterionLabels[0])$($fullWidthColon)2/2",
        "$($frozenCriterionLabels[1])$($fullWidthColon)1.5/2",
        "$($frozenCriterionLabels[2])$($fullWidthColon)1/2",
        "$($frozenCriterionLabels[3])$($fullWidthColon)0.5/2",
        "$($frozenCriterionLabels[4])$($fullWidthColon)0/2",
        "$frozenTotalLabel$($fullWidthColon)5/10",
        "$frozenReasonLabel$($fullWidthColon)parser fixture") -join "`n"
    $selfTestParsed = Parse-VisualResponse $selfTestResponse
    if ([double]$selfTestParsed.score -ne 5.0 -or
        [double]$selfTestParsed.scene_assembly -ne 2.0 -or
        [double]$selfTestParsed.composition_layout -ne 1.5 -or
        [double]$selfTestParsed.scale_layer_clarity -ne 1.0 -or
        [double]$selfTestParsed.style_color -ne 0.5 -or
        [double]$selfTestParsed.overall_finish -ne 0.0) {
        throw "Parser self-test: fixed visual response was parsed incorrectly."
    }
    $selfTestReport = [pscustomobject]@{
        schema_version=4; valid=$true; formal_score_complete=$false
        status="parser_selftest_passed"; dry_run=$true
        generated_utc=[DateTime]::UtcNow.ToString("o")
        prompt_sha256=Get-Sha256 $promptPath
        placeholder_exact=$true; parsed=$selfTestParsed
        rounds_required=3; rounds_completed=0; rounds=@(); final_score=$null; errors=@()
    }
    Write-VisualReport $selfTestReport
    return
}

$errors = [System.Collections.Generic.List[string]]::new()
$expectedPromptHash = ([string]$manifest.prompt_sha256).ToLowerInvariant()
$actualPromptHash = Get-Sha256 $promptPath
$expectedStatesHash = ([string]$manifest.states_manifest_sha256).ToLowerInvariant()
$actualStatesHash = Get-Sha256 $statesPath
if ($actualPromptHash -ne $expectedPromptHash) { $errors.Add("Frozen prompt SHA256 mismatch.") }
if ($actualStatesHash -ne $expectedStatesHash) { $errors.Add("Frozen states manifest SHA256 mismatch.") }
if ($Model -ne [string]$manifest.model_id) {
    $errors.Add("Requested model '$Model' differs from frozen model '$($manifest.model_id)'.")
}
if ($Rounds -ne [int]$manifest.required_rounds) { $errors.Add("Exactly three visual rounds are required.") }
if (-not [bool]$manifest.formal_reference_ready -or -not [bool]$states.formal_reference_ready) {
    $errors.Add("Formal D6 reference set is blocked: $($manifest.reference_provenance.blocking_reason)")
}

$resolvedStates = [System.Collections.Generic.List[object]]::new()
foreach ($state in @($states.states)) {
    $reference = [IO.Path]::GetFullPath((Join-Path $VisualRoot ([string]$state.reference)))
    $candidate = [IO.Path]::GetFullPath((Join-Path $CandidateEvidenceDirectory ([string]$state.candidate)))
    $referencePresent = Test-Path -LiteralPath $reference -PathType Leaf
    if (-not $referencePresent) { $errors.Add("Reference image missing for state $($state.id): $reference") }
    if ([bool]$state.reference_is_gold_derived) { $errors.Add("State $($state.id) reference is Gold-derived.") }
    if (-not [bool]$state.same_state_verified) { $errors.Add("State $($state.id) is not verified as a same-state Reference/Candidate pair.") }
    $candidateCheck = Test-PngCandidate $candidate
    $resolvedStates.Add([pscustomobject]@{
        id=[string]$state.id; label=[string]$state.label
        reference_path=$reference; reference_present=$referencePresent
        reference_sha256=Get-Sha256 $reference
        reference_origin=[string]$state.reference_origin
        reference_is_gold_derived=[bool]$state.reference_is_gold_derived
        same_state_verified=[bool]$state.same_state_verified
        candidate_path=$candidate; candidate_present=(Test-Path -LiteralPath $candidate -PathType Leaf)
        candidate_sha256=Get-Sha256 $candidate
        candidate_image_status=[string]$candidateCheck.kind
        candidate_image_detail=[string]$candidateCheck.detail
        candidate_failure_zero=-not [bool]$candidateCheck.usable
    })
}

$baseReport = [ordered]@{
    schema_version=4; valid=$false; formal_score_complete=$false
    status="invalid_visual"; dry_run=[bool]$DryRun
    generated_utc=[DateTime]::UtcNow.ToString("o")
    protocol=[string]$manifest.protocol; model_id=$Model
    rounds_required=[int]$manifest.required_rounds; rounds_completed=0
    prompt=[pscustomobject]@{ path=$promptPath; sha256=$actualPromptHash; expected_sha256=$expectedPromptHash; verified=($actualPromptHash -eq $expectedPromptHash) }
    prompt_sha256=$actualPromptHash
    states_manifest=[pscustomobject]@{ path=$statesPath; sha256=$actualStatesHash; expected_sha256=$expectedStatesHash; verified=($actualStatesHash -eq $expectedStatesHash) }
    reference_preflight=[pscustomobject]@{ formal_reference_ready=[bool]$manifest.formal_reference_ready; status=[string]$manifest.reference_set_status; provenance=$manifest.reference_provenance }
    prompt_input_preflights=@(); states=@($resolvedStates); rounds=@(); final_score=$null; errors=@($errors)
}

if ($errors.Count -gt 0) {
    $referenceFailure = @($errors | Where-Object {
        $_ -like "Formal D6 reference set is blocked:*" -or
        $_ -like "Reference image missing for state*" -or
        $_ -like "State * reference is Gold-derived." -or
        $_ -like "State * is not verified as a same-state*"
    }).Count -gt 0
    Complete-Invalid $baseReport $(if($referenceFailure){"invalid_reference"}else{"invalid_visual"})
    return
}
if ($DryRun -and -not $PromptInputAuditOnly) {
    $baseReport.valid=$true; $baseReport.status="ready"; Write-VisualReport ([pscustomobject]$baseReport); return
}

$fixedPrompt = $frozenPromptText
$placeholder = $frozenStatePlaceholder
if ([string]::IsNullOrWhiteSpace($placeholder) -or -not $fixedPrompt.Contains($placeholder)) {
    $errors.Add("Frozen prompt no longer contains its state-label placeholder.")
    Complete-Invalid $baseReport; return
}
$preflights = [System.Collections.Generic.List[object]]::new()
foreach ($state in @($resolvedStates | Where-Object { -not $_.candidate_failure_zero })) {
    $safeId = [regex]::Replace($state.id, '[^A-Za-z0-9._-]', '_')
    $renderedPrompt = $fixedPrompt.Replace($placeholder, [string]$state.label)
    $auditPath = Join-Path $rawDirectory ("prompt-input-{0}.json" -f $safeId)
    $request = New-VisualRequest $renderedPrompt $state.reference_path $state.candidate_path
    [IO.File]::WriteAllText($auditPath, ($request | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $verified = $true; $messageCount = 1; $roles = @('user')
    $developerCount = 0; $environmentCount = 0
    $userPromptMatches = $true; $imageCount = 2; $parseError = $null
    $preflights.Add([pscustomobject]@{
        state_id=$state.id; verified=$verified
        message_count=$messageCount; roles=$roles; developer_message_count=$developerCount
        environment_context_count=$environmentCount; exact_user_prompt=$userPromptMatches
        image_count=$imageCount; rendered_prompt_sha256=Get-StringSha256 $renderedPrompt
        raw_path=$auditPath; raw_sha256=Get-Sha256 $auditPath
        parse_error=$parseError
    })
    if (-not $verified) {
        $errors.Add("Prompt-input preflight for state $($state.id) exposed non-frozen model-visible context or incorrect prompt/image order.")
    }
}
$baseReport.prompt_input_preflights=@($preflights)
if ($errors.Count -gt 0) { Complete-Invalid $baseReport "invalid_prompt_context"; return }
if ($PromptInputAuditOnly) {
    $baseReport.valid=$true; $baseReport.status="prompt_input_verified"; Write-VisualReport ([pscustomobject]$baseReport); return
}

$roundResults = [System.Collections.Generic.List[object]]::new()
$responseIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
for ($round=1; $round -le $Rounds -and $errors.Count -eq 0; $round++) {
    $stateResults = [System.Collections.Generic.List[object]]::new()
    foreach ($state in @($resolvedStates)) {
        $safeId=[regex]::Replace($state.id,'[^A-Za-z0-9._-]','_')
        $renderedPrompt=$fixedPrompt.Replace($placeholder,[string]$state.label)
        if ([bool]$state.candidate_failure_zero) {
            $parsed=New-ZeroParsed "Candidate state is $($state.candidate_image_status); GAME_INDEPENDENT_SCORING_GUIDE section 6.1 assigns this state 0."
            $stateResults.Add([pscustomobject]@{
                state_id=$state.id; label=$state.label; model_id=$Model; prompt_sha256=$actualPromptHash
                reference_sha256=$state.reference_sha256; candidate_sha256=$state.candidate_sha256
                candidate_failure_zero=$true; candidate_failure_kind=$state.candidate_image_status
                scoring_method="guide_zero_without_vlm_call"; raw_response_path=$null
                raw_response_sha256=$null; event_log_path=$null; event_log_sha256=$null
                invocation_path=$null; invocation_sha256=$null; parsed=$parsed; score=0.0
            })
            continue
        }
        $rawPath=Join-Path $rawDirectory ("round-{0}-{1}.response.txt" -f $round,$safeId)
        $eventPath=Join-Path $rawDirectory ("round-{0}-{1}.provider-response.json" -f $round,$safeId)
        $invocationPath=Join-Path $rawDirectory ("round-{0}-{1}.invocation.json" -f $round,$safeId)
        $request = New-VisualRequest $renderedPrompt $state.reference_path $state.candidate_path
        try {
            $call = Invoke-VisualReview $request $invocationPath $eventPath
            if (-not $responseIds.Add($call.response_id)) { throw 'Visual-review response ID was reused.' }
            $response = $call.text
            [IO.File]::WriteAllText($rawPath, $response, [Text.UTF8Encoding]::new($false))
            $parsed=Parse-VisualResponse $response
            $stateResults.Add([pscustomobject]@{
                state_id=$state.id; label=$state.label; model_id=$Model; prompt_sha256=$actualPromptHash
                reference_sha256=$state.reference_sha256; candidate_sha256=$state.candidate_sha256
                candidate_failure_zero=$false; candidate_failure_kind=$null; scoring_method="fixed_vlm_prompt"
                raw_response_path=$rawPath; raw_response_sha256=Get-Sha256 $rawPath
                event_log_path=$eventPath; event_log_sha256=Get-Sha256 $eventPath
                invocation_path=$invocationPath; invocation_sha256=Get-Sha256 $invocationPath
                parsed=$parsed; score=$parsed.score
            })
        } catch { $errors.Add("Round $round state $($state.id) failed: $($_.Exception.Message)"); break }
    }
    if ($errors.Count -gt 0) { break }
    $average=(@($stateResults)|Measure-Object -Property score -Average).Average
    $roundResults.Add([pscustomobject]@{ round=$round; model_id=$Model; prompt_sha256=$actualPromptHash; score=Round-One ([double]$average); states=@($stateResults) })
}
$baseReport.rounds=@($roundResults); $baseReport.rounds_completed=$roundResults.Count; $baseReport.errors=@($errors)
if ($errors.Count -eq 0 -and $roundResults.Count -eq $Rounds) {
    $final=(@($roundResults)|Measure-Object -Property score -Average).Average
    $baseReport.valid=$true; $baseReport.formal_score_complete=$true
    $baseReport.status="evaluated"; $baseReport.final_score=Round-One ([double]$final)
    Write-VisualReport ([pscustomobject]$baseReport); return
}
Complete-Invalid $baseReport
