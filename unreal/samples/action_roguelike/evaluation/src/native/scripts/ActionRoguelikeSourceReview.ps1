Set-StrictMode -Version Latest

function Apply-ActionRoguelikeSourceReview {
    param($Run, $Catalog, [string]$VerdictsPath, [string]$ReviewPath, [string]$EvaluatorRoot)
    $reviewFull=[IO.Path]::GetFullPath($ReviewPath)
    $review=Get-Content -LiteralPath $reviewFull -Raw | ConvertFrom-Json -Depth 100
    $root=Split-Path -Parent ([IO.Path]::GetFullPath($VerdictsPath))
    $evaluationRoot=Split-Path -Parent $root
    $projectRoot=Join-Path (Split-Path -Parent $evaluationRoot) 'input/project'
    $hash={param($p)(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
    if($review.schema_version -cne '1.0.0' -or $review.policy -cne 'source-corroborated-1.0.0' -or
       $review.source_run_id -cne $Run.run_id -or $review.candidate_id -cne $Run.candidate_id -or
       $review.candidate_identity_sha256 -cne $Run.candidate_identity_sha256 -or
       $review.verdicts_sha256 -cne (& $hash $VerdictsPath) -or
       $review.catalog_sha256 -cne (& $hash (Join-Path $EvaluatorRoot 'catalog/checkpoints.json')) -or
       [string]::IsNullOrWhiteSpace($review.reassessment_id) -or $review.reassessment_id -ceq $Run.run_id){
        throw 'SOURCE_REVIEW_IDENTITY_MISMATCH'
    }
    $ids=@($review.checkpoints | ForEach-Object checkpoint_id)
    $expected=@($Catalog.checkpoints | ForEach-Object id)
    if($ids.Count -ne $expected.Count -or @($ids|Sort-Object -Unique).Count -ne $ids.Count -or
       (($ids|Sort-Object)-join "`n") -cne (($expected|Sort-Object)-join "`n")){throw 'SOURCE_REVIEW_COVERAGE_INCOMPLETE'}

    $validateArtifact={param($a,[string]$allowedRoot,[bool]$isSource)
        if([IO.Path]::IsPathRooted($a.path) -or $a.path.Contains(':')){throw 'SOURCE_REVIEW_ABSOLUTE_PATH'}
        $full=[IO.Path]::GetFullPath((Join-Path $root $a.path))
        $allowed=[IO.Path]::GetFullPath($allowedRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or
           -not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'SOURCE_REVIEW_PATH_ESCAPE_OR_MISSING'}
        # Reject junction/symlink escape as well as lexical traversal.
        for($cursor=Get-Item -LiteralPath $full; $cursor; $cursor=$cursor.Parent){
            if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'SOURCE_REVIEW_REPARSE_POINT'}
            if($cursor.FullName.TrimEnd('\','/') -ieq [IO.Path]::GetFullPath($allowedRoot).TrimEnd('\','/')){break}
            if($cursor -is [IO.FileInfo]){$cursor=$cursor.Directory; if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'SOURCE_REVIEW_REPARSE_POINT'}}
        }
        if($a.sha256 -cne (& $hash $full)){throw 'SOURCE_REVIEW_ARTIFACT_CHANGED'}
        if($isSource){
            if([IO.Path]::GetExtension($full) -notin @('.cpp','.h','.ini','.cs','.uproject')){throw 'SOURCE_REVIEW_SOURCE_TYPE'}
            $lines=[IO.File]::ReadAllLines($full)
            if($a.line_start -isnot [long] -and $a.line_start -isnot [int]){throw 'SOURCE_REVIEW_LINE_INVALID'}
            if($a.line_end -isnot [long] -and $a.line_end -isnot [int]){throw 'SOURCE_REVIEW_LINE_INVALID'}
            if($a.line_start -lt 1 -or $a.line_end -lt $a.line_start -or $a.line_end -gt $lines.Count){throw 'SOURCE_REVIEW_LINE_INVALID'}
            $excerpt=($lines[($a.line_start-1)..($a.line_end-1)] -join "`n")
            if([string]::IsNullOrWhiteSpace($a.symbol) -or $a.excerpt -cne $excerpt){throw 'SOURCE_REVIEW_EXCERPT_CHANGED'}
        }
        return $full
    }
    $identityPath=& $validateArtifact $review.current_candidate $evaluationRoot $false
    $identity=Get-Content -LiteralPath $identityPath -Raw|ConvertFrom-Json
    if($identity.candidate_identity_sha256 -cne $Run.candidate_identity_sha256){throw 'SOURCE_REVIEW_CURRENT_CANDIDATE_MISMATCH'}
    foreach($entry in $review.checkpoints){
        $old=@($Run.checkpoints|Where-Object checkpoint_id -CEQ $entry.checkpoint_id)[0]
        $cat=@($Catalog.checkpoints|Where-Object id -CEQ $entry.checkpoint_id)[0]
        if($entry.original_verdict -cne $old.verdict -or $entry.pass_condition -cne $cat.pass_condition -or
           $entry.verdict -notin @('pass','fail') -or
           $entry.basis -notin @('source_and_runtime','implementation_defect','unresolved_after_source_review') -or
           [string]::IsNullOrWhiteSpace($entry.rationale) -or
           @($entry.evidence).Count -eq 0 -or @($entry.source_evidence).Count -eq 0){throw 'SOURCE_REVIEW_ENTRY_INVALID'}
        if(($entry.verdict -ceq 'pass') -ne ($entry.basis -ceq 'source_and_runtime')){throw 'SOURCE_REVIEW_BASIS_INVALID'}
        if($entry.verdict -ceq 'pass' -and @($entry.missing_requirements).Count -ne 0){throw 'SOURCE_REVIEW_PASS_WITH_GAP'}
        if($entry.verdict -ceq 'fail' -and @($entry.missing_requirements).Count -eq 0){throw 'SOURCE_REVIEW_FAILURE_WITHOUT_REASON'}
        if($old.verdict -cne 'pass' -and $entry.verdict -ceq 'pass' -and [string]::IsNullOrWhiteSpace($entry.promotion_reason)){throw 'SOURCE_REVIEW_UNEXPLAINED_PROMOTION'}
        foreach($a in $entry.evidence){$null=& $validateArtifact $a $evaluationRoot $false}
        foreach($a in $entry.source_evidence){$null=& $validateArtifact $a $projectRoot $true}
    }
    # All-or-nothing validation above: failed reviews cannot partially change verdicts.
    $gaps=[Collections.Generic.List[object]]::new()
    foreach($entry in $review.checkpoints){
        $item=@($Run.checkpoints|Where-Object checkpoint_id -CEQ $entry.checkpoint_id)[0]
        $item.verdict=$entry.verdict
        $item.detail=$entry.rationale
        $item.evidence=@($entry.evidence|ForEach-Object path)+@($entry.source_evidence|ForEach-Object path)
        $item|Add-Member -NotePropertyName evidence_basis -NotePropertyValue $entry.basis -Force
        if($entry.verdict -ceq 'pass'){
            $item.reason_code=$null;$item.attribution=$null;$item.first_failure=$null;$item.score_impact='full_credit'
        }else{
            $item.reason_code=if($entry.basis -ceq 'implementation_defect'){'SOURCE_CONFIRMED_REQUIREMENT_VIOLATION'}else{'UNRESOLVED_AFTER_SOURCE_REVIEW'}
            $item.attribution=if($entry.basis -ceq 'implementation_defect'){'candidate'}else{'evidence_gap'}
            $item.first_failure=[IO.Path]::GetRelativePath($root,$reviewFull).Replace('\','/')+'#'+$entry.checkpoint_id
            $item.score_impact='checkpoint_zero'
            if($item.attribution -ceq 'evidence_gap'){$gaps.Add([ordered]@{checkpoint_id=$item.checkpoint_id;reason_code=$item.reason_code;attribution=$item.attribution;detail=$item.detail;missing_requirements=$entry.missing_requirements;evidence=$item.evidence})}
        }
    }
    $Run.candidate_failures=@($Run.checkpoints|Where-Object attribution -CEQ 'candidate')
    $Run.run_id=$review.reassessment_id
    return [ordered]@{policy=$review.policy;source_run_id=$review.source_run_id;review_path=$reviewFull;review_sha256=(& $hash $reviewFull);evidence_gaps=@($gaps.ToArray())}
}
