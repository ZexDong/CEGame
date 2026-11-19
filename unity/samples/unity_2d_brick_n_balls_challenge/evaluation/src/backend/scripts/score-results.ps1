param(
    [Parameter(Mandatory=$true)][string]$EditXml,
    [Parameter(Mandatory=$true)][string]$PlayXml,
    [Parameter(Mandatory=$true)][string]$ReopenXml,
    [Parameter(Mandatory=$true)][string]$RulesPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$CliExitsPath,
    [Parameter(Mandatory=$true)][string]$EvaluationStartedUtc,
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$DirtyReceiptPath,
    [Parameter(Mandatory=$true)][string]$BindingsPath
)
$ErrorActionPreference='Stop'
$rules=Get-Content -LiteralPath $RulesPath -Raw|ConvertFrom-Json
$scores=[ordered]@{D1=0.0;D2=0.0;D3=0.0;D4=0.0;D5=0.0}
$cases=@();$healthErrors=@();$seen=@{};$supportSeen=@{};$rawXml=@{}
$started=[DateTime]::Parse($EvaluationStartedUtc).ToUniversalTime()
$cliExits=Get-Content -LiteralPath $CliExitsPath -Raw|ConvertFrom-Json
$bindings=Get-Content -LiteralPath $BindingsPath -Raw|ConvertFrom-Json
$candidateCompileFailed=([int]$cliExits.candidate_compile -ne 0)
$candidateCompileDiagnostic=($cliExits.candidate_compile_diagnostic -eq $true)

function Get-OptionalXmlText([System.Xml.XmlNode]$node,[string[]]$xpaths){
    if($null-eq$node){return ''}
    foreach($xpath in $xpaths){
        $match=$node.SelectSingleNode($xpath)
        if($null-ne$match){
            if($match-is[System.Xml.XmlAttribute]){return [string]$match.Value}
            return [string]$match.InnerText
        }
    }
    return ''
}

if($candidateCompileFailed){
    if(!$candidateCompileDiagnostic){$healthErrors+='Candidate-only compile failed without a candidate-owned C# diagnostic; host/import health is unresolved.'}
    foreach($property in $rules.tests.PSObject.Properties){
        $rule=$property.Value
        $cases += [pscustomobject]@{source='candidate_compile';name=$property.Name;dimension=[string]$rule[0];weight=[double]$rule[1];passed=$false;result='NotRun';failure_message='Candidate project did not compile before evaluator injection.';classification='candidate_compile_failure'}
    }
}else{
    if($null -eq $cliExits.evaluator_compile -or [int]$cliExits.evaluator_compile -ne 0){$healthErrors+='Evaluator injection compile/import did not complete successfully.'}
    foreach($entry in @(@{name='editmode';path=$EditXml},@{name='playmode';path=$PlayXml},@{name='reopen';path=$ReopenXml})){
        if(!(Test-Path -LiteralPath $entry.path)){$healthErrors += "Missing XML: $($entry.name)";continue}
        if((Get-Item -LiteralPath $entry.path).LastWriteTimeUtc -lt $started.AddSeconds(-2)){$healthErrors += "Stale XML predating this evaluation: $($entry.name)";continue}
        try{
            $raw=Get-Content -LiteralPath $entry.path -Raw;$rawXml[$entry.name]=$raw;[xml]$xml=$raw
            $leaf=@($xml.SelectNodes('//test-case'));if($leaf.Count -eq 0){$healthErrors += "Zero discovered tests: $($entry.name)";continue}
            foreach($case in $leaf){
                $name=[string]$case.name;$ruleProperty=$rules.tests.PSObject.Properties[$name]
                if($null -ne $ruleProperty){
                    if(!$seen.ContainsKey($name)){$seen[$name]=0};$seen[$name]++
                    $rule=$ruleProperty.Value;$passed=([string]$case.result -eq 'Passed');$dimension=[string]$rule[0];$weight=[double]$rule[1]
                    if($passed){$scores[$dimension]+=$weight}
                    # Passing cases omit failure/reason; skipped or inconclusive
                    # cases may use reason instead of failure. XPath lookup keeps all
                    # optional NUnit nodes safe when the wrapper inherits StrictMode.
                    $message=Get-OptionalXmlText $case @('failure/message','reason/message')
                    $cases += [pscustomobject]@{source=$entry.name;name=$name;dimension=$dimension;weight=$weight;passed=$passed;result=[string]$case.result;failure_message=$message.Trim();classification=if($passed){'passed'}else{'candidate_requirement_failure'}}
                }elseif(@($rules.support_tests) -contains $name){
                    if(!$supportSeen.ContainsKey($name)){$supportSeen[$name]=0};$supportSeen[$name]++
                }
            }
        }catch{$healthErrors += "Unreadable XML $($entry.name): $($_.Exception.Message)"}
    }
    foreach($property in $rules.tests.PSObject.Properties){$count=if($seen.ContainsKey($property.Name)){[int]$seen[$property.Name]}else{0};if($count -ne 1){$healthErrors += "Expected exactly one scored leaf '$($property.Name)', found $count"}}
    foreach($name in @($rules.support_tests)){$count=if($supportSeen.ContainsKey($name)){[int]$supportSeen[$name]}else{0};if($count -ne 1){$healthErrors += "Expected exactly one support leaf '$name', found $count"}}
}

$playPid=$null;$reopenPid=$null
if(!$candidateCompileFailed){
    foreach($phase in @('playmode','reopen')){
        if(!$rawXml.ContainsKey($phase)){continue}
        $pidMatch=[regex]::Match($rawXml[$phase],'BENCHMARK_PROCESS_ID=(\d+)')
        if(!$pidMatch.Success){$healthErrors += "$phase process ID evidence missing"}elseif($phase -eq 'playmode'){$playPid=[int]$pidMatch.Groups[1].Value}else{$reopenPid=[int]$pidMatch.Groups[1].Value}
        if($rawXml[$phase] -notmatch [regex]::Escape("BENCHMARK_SESSION_ID=$SessionId")){$healthErrors += "$phase session binding missing or mismatched"}
        if($rawXml[$phase] -notmatch 'BENCHMARK_SCENE=BrickChallenge'){$healthErrors += "$phase scene evidence missing"}
    }
    if($rawXml.ContainsKey('playmode') -and $rawXml.playmode -notmatch 'BENCHMARK_INPUT_ROUTE=NewInputSystemVirtualMouseKeyboard'){$healthErrors+='PlayMode input-route evidence missing'}
    if($null -ne $playPid -and $null -ne $reopenPid -and $playPid -eq $reopenPid){$healthErrors+='Reopen did not run in a distinct Unity process'}
}

$valid=($healthErrors.Count -eq 0)
$automatic=if($valid){[math]::Round(($scores.Values|Measure-Object -Sum).Sum,1)}else{$null}
$result=[ordered]@{
    schema_version=3;valid_score=$valid;invalid_reasons=$healthErrors
    classification=if(!$valid){'evaluator_or_infrastructure_invalid'}elseif($candidateCompileFailed){'valid_candidate_compile_failure'}else{'valid_candidate_evaluation'}
    evaluator_health=[ordered]@{
        expected_scored_leaf_count=@($rules.tests.PSObject.Properties).Count;scored_leaf_count=$cases.Count
        expected_support_leaf_count=@($rules.support_tests).Count;session_id=$SessionId;scene='BrickChallenge';input_route='NewInputSystemVirtualMouseKeyboard'
        timeout_budgets_seconds=[ordered]@{candidate_compile=600;evaluator_compile=600;editmode=600;playmode=1200;reopen=600}
        freshness_started_utc=$EvaluationStartedUtc;candidate_compile_exit=$cliExits.candidate_compile;evaluator_compile_exit=$cliExits.evaluator_compile
        editmode_exit=$cliExits.editmode;playmode_exit=$cliExits.playmode;reopen_exit=$cliExits.reopen
        playmode_process_id=$playPid;reopen_process_id=$reopenPid;distinct_reopen_process=($null -ne $playPid -and $null -ne $reopenPid -and $playPid -ne $reopenPid)
        dirty_reopen_receipt_present=(Test-Path -LiteralPath $DirtyReceiptPath)
    }
    tree_bindings=$bindings
    D1=if($valid){$scores.D1}else{$null};D2=if($valid){$scores.D2}else{$null};D3=if($valid){$scores.D3}else{$null};D4=if($valid){$scores.D4}else{$null};D5=if($valid){$scores.D5}else{$null}
    automatic_score=$automatic;automatic_maximum=90
    D6=[ordered]@{status=if($valid){'pending_three_round_sol_high'}else{'invalid'};score=$null;maximum=10;required_states=@('menu','initial_gameplay','brick_hit')}
    overall=[ordered]@{status=if($valid){'pending_visual'}else{'invalid'};score=$null;maximum=100}
    test_cases=$cases;generated_utc=[DateTime]::UtcNow.ToString('o')
}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $OutputPath -Encoding utf8
$result|ConvertTo-Json -Depth 12
