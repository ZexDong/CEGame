[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $evaluationRoot "visual\reference-manifest.json"
$promptPath = (Resolve-Path -LiteralPath (Join-Path $evaluationRoot "visual\visual_prompt.txt")).Path
$InputPath = (Resolve-Path -LiteralPath $InputPath).Path
$inputRoot = Split-Path -Parent $InputPath
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$input = Get-Content -Raw -Encoding UTF8 -LiteralPath $InputPath | ConvertFrom-Json

function Resolve-EvidencePath([string]$PathValue, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw "$Context path is empty."
    }
    $candidate = if ([System.IO.Path]::IsPathRooted($PathValue)) {
        $PathValue
    } else {
        Join-Path $inputRoot $PathValue
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "$Context file does not exist: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Assert-Hash([string]$PathValue, [string]$DeclaredHash, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($DeclaredHash) -or
        $DeclaredHash -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Context must declare a 64-character SHA256."
    }
    $actual = (Get-FileHash -LiteralPath $PathValue -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $DeclaredHash.ToLowerInvariant()) {
        throw "$Context SHA256 mismatch. Declared $DeclaredHash, actual $actual."
    }
    return $actual
}

function Assert-Png([string]$PathValue, [string]$Context) {
    $bytes = [System.IO.File]::ReadAllBytes($PathValue)
    $signature = @(137,80,78,71,13,10,26,10)
    if ($bytes.Length -lt 32) {
        throw "$Context is too small to be a PNG."
    }
    for ($index = 0; $index -lt $signature.Count; $index++) {
        if ([int]$bytes[$index] -ne $signature[$index]) {
            throw "$Context is not a PNG file."
        }
    }
}

function Round-Visual([double]$Value) {
    [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

function Assert-CategoryScore([object]$Value, [string]$Context) {
    if ($null -eq $Value) { throw "$Context is missing." }
    $number = [double]$Value
    if ($number -lt 0 -or $number -gt 2 -or
        [Math]::Abs(($number * 2) - [Math]::Round($number * 2)) -gt 0.0001) {
        throw "$Context must be one of 0, 0.5, 1, 1.5, or 2."
    }
    return $number
}

function Parse-RawResponse([string]$PathValue, [string]$Context) {
    $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $PathValue
    # Keep these labels ASCII-only in the script so Windows PowerShell 5.1
    # cannot reinterpret UTF-8 source text that has no BOM. The escapes are
    # the exact fixed English labels from visual_prompt.txt.
    $patterns = [ordered]@{
        scene_assembly = '(?m)^\s*Scene completeness and asset assembly\s*(?:\uFF1A|:)\s*(0|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)\s*/\s*2\s*$'
        composition_layout = '(?m)^\s*Composition and layout\s*(?:\uFF1A|:)\s*(0|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)\s*/\s*2\s*$'
        scale_layer_clarity = '(?m)^\s*Scale, hierarchy, and clarity\s*(?:\uFF1A|:)\s*(0|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)\s*/\s*2\s*$'
        style_color = '(?m)^\s*Style and color consistency\s*(?:\uFF1A|:)\s*(0|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)\s*/\s*2\s*$'
        overall_finish = '(?m)^\s*Overall polish\s*(?:\uFF1A|:)\s*(0|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)\s*/\s*2\s*$'
        total = '(?m)^\s*Total\s*(?:\uFF1A|:)\s*(0|0\.5|[1-9](?:\.0|\.5)?|10(?:\.0)?)\s*/\s*10\s*$'
    }
    $parsed = [ordered]@{}
    foreach ($entry in $patterns.GetEnumerator()) {
        $match = [regex]::Match($raw, $entry.Value,
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $match.Success) {
            throw "$Context raw response is missing '$($entry.Key)' in the fixed prompt format."
        }
        $parsed[$entry.Key] = [double]$match.Groups[1].Value
    }
    $sum = [double]$parsed.scene_assembly + [double]$parsed.composition_layout +
        [double]$parsed.scale_layer_clarity + [double]$parsed.style_color +
        [double]$parsed.overall_finish
    if ([Math]::Abs($sum - [double]$parsed.total) -gt 0.0001) {
        throw "$Context raw response total does not equal its five category scores."
    }
    return [pscustomobject]$parsed
}

if ([int]$input.schema_version -ne 2) {
    throw "Visual score input schema_version must be 2."
}
if ([string]$input.status -ne "evaluated") {
    throw "Visual score input status must be evaluated."
}
$formalProtocol = 'user-simplified-single-state-single-round-20260824'
if ([string]$input.protocol -cne $formalProtocol -or
    [int]$input.required_rounds -ne 1 -or
    [string]$input.primary_state_id -cne 'initial_gameplay') {
    throw "Visual score input must bind the current single-state single-round protocol."
}
if ([string]$manifest.protocol -cne $formalProtocol -or
    -not [bool]$manifest.formal_reference_ready -or
    [int]$manifest.required_rounds -ne 1 -or
    [string]$manifest.primary_state_id -cne 'initial_gameplay' -or
    @($manifest.states).Count -ne 1) {
    throw "reference-manifest.json is not a formal one-state/one-round declaration."
}
$modelId = [string]$input.model_id
if ($modelId -cne 'gpt-5.6-sol') {
    throw "D6 must use the frozen gpt-5.6-sol visual judge."
}

$declaredPromptPath = Resolve-EvidencePath ([string]$input.prompt.path) "Prompt"
if (-not [string]::Equals($declaredPromptPath, $promptPath,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Prompt path must resolve to the fixed evaluator visual_prompt.txt."
}
$promptHash = Assert-Hash $promptPath ([string]$input.prompt.sha256) "Prompt"

$expectedIds = @($manifest.states | ForEach-Object { [string]$_.id })
$actualIds = @($input.states | ForEach-Object { [string]$_.id })
if (($expectedIds -join "|") -ne ($actualIds -join "|")) {
    throw "Visual state IDs/order must exactly match reference-manifest.json."
}

$stateResults = [System.Collections.Generic.List[object]]::new()
$usedCandidatePaths = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$usedRawPaths = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
for ($stateIndex = 0; $stateIndex -lt $expectedIds.Count; $stateIndex++) {
    $state = $input.states[$stateIndex]
    $manifestState = $manifest.states[$stateIndex]
    $stateId = [string]$state.id
    $referenceExpected = (Resolve-Path -LiteralPath (
        Join-Path (Join-Path $evaluationRoot "visual") ([string]$manifestState.reference))).Path
    $referencePath = Resolve-EvidencePath ([string]$state.reference.path) "State $stateId reference"
    if (-not [string]::Equals($referencePath, $referenceExpected,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "State $stateId reference path does not match reference-manifest.json."
    }
    $candidatePath = Resolve-EvidencePath ([string]$state.candidate.path) "State $stateId candidate"
    if (-not $usedCandidatePaths.Add($candidatePath)) {
        throw "State $stateId reuses a candidate image already bound to another state."
    }
    Assert-Png $referencePath "State $stateId reference"
    Assert-Png $candidatePath "State $stateId candidate"
    $referenceHash = Assert-Hash $referencePath ([string]$state.reference.sha256) `
        "State $stateId reference"
    $candidateHash = Assert-Hash $candidatePath ([string]$state.candidate.sha256) `
        "State $stateId candidate"

    $roundInputs = @($state.rounds)
    if ($roundInputs.Count -ne 1) {
        throw "State $stateId must contain exactly one bound round record."
    }
    $roundResults = [System.Collections.Generic.List[object]]::new()
    for ($roundIndex = 1; $roundIndex -le 1; $roundIndex++) {
        $round = $roundInputs[$roundIndex - 1]
        $context = "State $stateId round $roundIndex"
        if ([int]$round.round_index -ne $roundIndex) {
            throw "$context round_index is not bound to its list position."
        }
        if ([string]$round.model_id -ne $modelId) {
            throw "$context model_id differs from the run model_id."
        }
        $rawPath = Resolve-EvidencePath ([string]$round.raw_response.path) "$context raw response"
        if (-not $usedRawPaths.Add($rawPath)) {
            throw "$context reuses a raw response already bound to another state/round."
        }
        $rawHash = Assert-Hash $rawPath ([string]$round.raw_response.sha256) `
            "$context raw response"
        $rawParsed = Parse-RawResponse $rawPath $context
        $declared = $round.parsed
        $declaredValues = [ordered]@{
            scene_assembly = Assert-CategoryScore $declared.scene_assembly "$context scene_assembly"
            composition_layout = Assert-CategoryScore $declared.composition_layout "$context composition_layout"
            scale_layer_clarity = Assert-CategoryScore $declared.scale_layer_clarity "$context scale_layer_clarity"
            style_color = Assert-CategoryScore $declared.style_color "$context style_color"
            overall_finish = Assert-CategoryScore $declared.overall_finish "$context overall_finish"
        }
        $declaredTotal = [double]$declared.total
        $declaredSum = ($declaredValues.Values | Measure-Object -Sum).Sum
        if ($declaredTotal -lt 0 -or $declaredTotal -gt 10 -or
            [Math]::Abs($declaredSum - $declaredTotal) -gt 0.0001) {
            throw "$context parsed total must equal the five declared category scores."
        }
        foreach ($key in $declaredValues.Keys) {
            if ([Math]::Abs([double]$declaredValues[$key] - [double]$rawParsed.$key) -gt 0.0001) {
                throw "$context parsed '$key' differs from the raw VLM response."
            }
        }
        if ([Math]::Abs($declaredTotal - [double]$rawParsed.total) -gt 0.0001) {
            throw "$context parsed total differs from the raw VLM response."
        }
        $roundResults.Add([pscustomobject]@{
            round_index = $roundIndex
            model_id = $modelId
            raw_response = [pscustomobject]@{
                path = $rawPath
                sha256 = $rawHash
            }
            parsed = [pscustomobject]@{
                scene_assembly = [double]$declaredValues.scene_assembly
                composition_layout = [double]$declaredValues.composition_layout
                scale_layer_clarity = [double]$declaredValues.scale_layer_clarity
                style_color = [double]$declaredValues.style_color
                overall_finish = [double]$declaredValues.overall_finish
                total = [double]$declaredTotal
            }
        })
    }
    $roundScores = @($roundResults | ForEach-Object { [double]$_.parsed.total })
    $stateResults.Add([pscustomobject]@{
        id = $stateId
        label = [string]$manifestState.label
        reference = [pscustomobject]@{ path = $referencePath; sha256 = $referenceHash }
        candidate = [pscustomobject]@{ path = $candidatePath; sha256 = $candidateHash }
        rounds = @($roundResults)
        round_scores = $roundScores
        average = Round-Visual (($roundScores | Measure-Object -Average).Average)
    })
}

$roundEvidence = [System.Collections.Generic.List[object]]::new()
$roundAverages = @()
for ($roundIndex = 1; $roundIndex -le 1; $roundIndex++) {
    $scores = @($stateResults | ForEach-Object {
        [double]$_.rounds[$roundIndex - 1].parsed.total
    })
    $average = Round-Visual (($scores | Measure-Object -Average).Average)
    $roundAverages += $average
    $roundEvidence.Add([pscustomobject]@{
        round_index = $roundIndex
        model_id = $modelId
        states = @($stateResults | ForEach-Object {
            [pscustomobject]@{
                id = [string]$_.id
                raw_response_path = [string]$_.rounds[$roundIndex - 1].raw_response.path
                raw_response_sha256 = [string]$_.rounds[$roundIndex - 1].raw_response.sha256
                total = [double]$_.rounds[$roundIndex - 1].parsed.total
            }
        })
        average = $average
    })
}
$d6 = Round-Visual (($roundAverages | Measure-Object -Average).Average)
$result = [pscustomobject]@{
    schema_version = 2
    status = "evaluated"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    input_path = $InputPath
    input_sha256 = (Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    protocol = $formalProtocol
    required_rounds = 1
    primary_state_id = 'initial_gameplay'
    model_id = $modelId
    prompt = [pscustomobject]@{ path = $promptPath; sha256 = $promptHash }
    states = @($stateResults)
    rounds = $roundAverages
    round_evidence = @($roundEvidence)
    d6_score = $d6
}
$json = $result | ConvertTo-Json -Depth 16
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $json,
        [System.Text.UTF8Encoding]::new($false))
}
$json
