Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function ConvertFrom-BomberVisualResponse {
    param([Parameter(Mandatory)][string]$Text)
    $labels=@('Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish')
    $criteria=[ordered]@{}
    foreach($label in $labels) {
        $matches=[regex]::Matches($Text,"(?m)^$([regex]::Escape($label))[::]\s*(0(?:\.0)?|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)\s*/2\s*$")
        if($matches.Count -ne 1) { throw "D6_RESPONSE_CRITERION_INVALID:$label" }
        $criteria[$label]=[double]::Parse($matches[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    }
    $total=[regex]::Matches($Text,'(?m)^Total[::]\s*(\d+(?:\.\d+)?)\s*/10\s*$')
    $reason=[regex]::Matches($Text,'(?m)^Reason[::]\s*(\S[^\r\n]*)\s*$')
    $sum=(@($criteria.Values)|Measure-Object -Sum).Sum
    if($total.Count -ne 1 -or $reason.Count -ne 1 -or [double]::Parse($total[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -ne $sum) { throw 'D6_RESPONSE_TOTAL_OR_RATIONALE_INVALID' }
    if(@($Text.Trim() -split '\r?\n').Count -ne 7) { throw 'D6_RESPONSE_EXTRA_CONTENT' }
    return [pscustomobject]@{score=[double]$sum;criteria=[pscustomobject]$criteria;rationale=$reason[0].Groups[1].Value.Trim()}
}

function Assert-BomberOriginalReferences {
    param([Parameter(Mandatory)][string]$EvaluatorRoot)
    $manifestPath=Join-Path $EvaluatorRoot 'd6/d6-reference-manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -Depth 100
    if($manifest.status -cne 'ready' -or $manifest.reference_source -cne 'original_game_baseline' -or $manifest.source_identity_sha256 -notmatch '^[a-f0-9]{64}$') {
        throw 'D6_ORIGINAL_REFERENCES_REQUIRED: three verified original-game captures must be bound before scoring; this is an evaluator setup gap, not a candidate zero.'
    }
    foreach($state in $manifest.states) {
        $path=Join-Path (Join-Path $EvaluatorRoot 'd6') $state.reference_image
        if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or $state.sha256 -cne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "D6_ORIGINAL_REFERENCE_INVALID:$($state.state_id)" }
    }
    return $manifest
}

function Assert-BomberD6Protocol {
    param([string]$EvaluatorRoot)
    $protocol=Get-Content -LiteralPath (Join-Path $EvaluatorRoot 'd6/protocol.json') -Raw|ConvertFrom-Json
    $guide=Join-Path $EvaluatorRoot '../../../gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md'
    $prompt=Join-Path $EvaluatorRoot 'd6/FIXED_VLM_PROMPT.txt'
    $manifest=Join-Path $EvaluatorRoot 'd6/d6-reference-manifest.json'
    if($protocol.protocol -cne 'canonical_five_criteria_three_rounds' -or $protocol.rounds -ne 3) { throw 'D6_PROTOCOL_UNSUPPORTED' }
    foreach($pair in @(@($guide,$protocol.guide_sha256),@($prompt,$protocol.prompt_sha256),@($manifest,$protocol.reference_manifest_sha256))) {
        if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pair[1]) { throw 'D6_PROTOCOL_HASH_MISMATCH' }
    }
}

function Get-BomberD6CaptureHealth {
    param([Parameter(Mandatory)][string]$Path, [int]$Width=1280, [int]$Height=720)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{status='missing';sha256=$null;width=$null;height=$null;reason_code='D6_CANDIDATE_STATE_MISSING'}
    }
    # Loading the decoder is infrastructure work; do not turn its failure into a candidate zero.
    Add-Type -AssemblyName System.Drawing.Common
    $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $bitmap=$null
    try { $bitmap=[Drawing.Bitmap]::new($Path) }
    catch { return [pscustomobject]@{status='invalid_png';sha256=$hash;width=$null;height=$null;reason_code='D6_CANDIDATE_BROKEN_FRAME'} }
    try {
        $status='healthy';$reason=$null
        if ($bitmap.Width -ne $Width -or $bitmap.Height -ne $Height) {
            $status='wrong_resolution';$reason='D6_CANDIDATE_WRONG_RESOLUTION'
        } else {
            $maximum=0.0;$sum=0.0;$sumSquares=0.0;$count=0;$buckets=[int[]]::new(16)
            for($y=10;$y -lt $Height;$y+=40) {
                for($x=10;$x -lt $Width;$x+=40) {
                    $pixel=$bitmap.GetPixel($x,$y)
                    $luma=0.2126*$pixel.R+0.7152*$pixel.G+0.0722*$pixel.B
                    $maximum=[Math]::Max($maximum,$luma);$sum+=$luma;$sumSquares+=$luma*$luma;++$count
                    ++$buckets[[Math]::Min(15,[Math]::Max(0,[int]($luma/16.0)))]
                }
            }
            $mean=$sum/$count;$deviation=[Math]::Sqrt([Math]::Max(0.0,$sumSquares/$count-$mean*$mean))
            if($maximum -lt 18 -or ($deviation -lt 2 -and $mean -lt 30) -or (@($buckets|Where-Object {$_ -gt 0}).Count -lt 2 -and $maximum -lt 45)) {
                $status='black_or_blank';$reason='D6_CANDIDATE_BLACK_SCREEN'
            }
        }
        return [pscustomobject]@{status=$status;sha256=$hash;width=$bitmap.Width;height=$bitmap.Height;reason_code=$reason}
    } finally { $bitmap.Dispose() }
}

Export-ModuleMember -Function ConvertFrom-BomberVisualResponse,Assert-BomberOriginalReferences,Assert-BomberD6Protocol,Get-BomberD6CaptureHealth
