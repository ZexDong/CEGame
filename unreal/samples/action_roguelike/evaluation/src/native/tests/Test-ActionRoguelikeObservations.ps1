[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$evaluatorRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $evaluatorRoot 'scripts/ActionRoguelikeStateAdapter.ps1')
. (Join-Path $evaluatorRoot 'scripts/ActionRoguelikeAtomicChecks.ps1')
$runnerPath = Join-Path $evaluatorRoot 'scripts/Invoke-ActionRoguelikeCanonicalEvaluation.ps1'
$tokens = $null; $parseErrors = $null
$runnerAst = [Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'The runner has syntax errors.' }
foreach ($name in @('Write-JsonFile', 'Get-Relative', 'Save-State', 'Save-Receipt', 'Wait-TaskState', 'Set-AtomicCheckpoint')) {
    $definition = $runnerAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($null -eq $definition) { throw "Missing runner function: $name" }
    Invoke-Expression $definition.Extent.Text
}

$script:assertionCount = 0
function Assert-Observation([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    ++$script:assertionCount
}
function New-ObservationPair([int]$Revision, [bool]$Ready) {
    return [pscustomobject]@{
        snapshot = [pscustomobject]@{ identity = [pscustomobject]@{ process_token = 'fixture-process'; round_id = 'fixture-round'; snapshot_id = "revision-$Revision" }; ready = $Ready }
        events = [pscustomobject]@{ identity = [pscustomobject]@{ process_token = 'fixture-process'; round_id = 'fixture-round'; snapshot_id = "revision-$Revision" }; events = @() }
    }
}
function Set-ObservationSequence([object[]]$Pairs) {
    $script:mockPairs = $Pairs
    $script:readCount = 0
    $script:budgetAfter = -1
    $script:LastStateReadDiagnostic = [pscustomobject]@{ code = 'fixture_read'; detail = 'Mock read-only observation transport.' }
}
function Read-TaskState([int]$TimeoutMilliseconds = 500) {
    Assert-Observation ($TimeoutMilliseconds -ge 1 -and $TimeoutMilliseconds -le 500) 'A read exceeded the bounded poll budget.'
    if($script:budgetAfter-ge0-and$script:readCount-ge$script:budgetAfter){
        $script:LastStateReadDiagnostic=@{last_reason_code='state_read_budget_exhausted';timeout_ms=$TimeoutMilliseconds}
        Start-Sleep -Milliseconds $TimeoutMilliseconds
        return $null
    }
    $index = [Math]::Min($script:readCount, $script:mockPairs.Count - 1)
    ++$script:readCount
    if ($index -lt 0) { return $null }
    return $script:mockPairs[$index]
}
function Read-WaitReceipt([string]$Name) {
    $path = Join-Path $script:OutputFull "receipts/wait-$Name.json"
    Assert-Observation (Test-Path -LiteralPath $path -PathType Leaf) "The wait has no real receipt: $Name"
    $receipt = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    Assert-Observation (@($receipt.samples).Count -gt 0) "The wait receipt contains no observations: $Name"
    foreach ($sample in $receipt.samples) {
        foreach ($field in @('snapshot', 'events')) {
            $relative = [string]$sample.$field
            if ($relative) { Assert-Observation (Test-Path -LiteralPath (Join-Path $script:OutputFull $relative) -PathType Leaf) "A wait receipt references nonexistent evidence: $relative" }
        }
    }
    return $receipt
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$script:OutputFull = Join-Path $temporaryParent ('actionroguelike-observations-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:OutputFull)
try {
    Set-ObservationSequence @((New-ObservationPair 1 $false), (New-ObservationPair 2 $true))
    $accepted = Wait-TaskState -Condition { param($snapshot, $events) $snapshot.ready } -TimeoutSeconds 0.5 -SaveAs 'ready'
    $receipt = Read-WaitReceipt 'ready'
    Assert-Observation ($null -ne $accepted -and $receipt.success -and $receipt.samples.Count -eq 2) 'A matching transition did not produce a successful wait receipt.'
    Assert-Observation ((Test-Path -LiteralPath (Join-Path $script:OutputFull 'states/ready.json')) -and (Test-Path -LiteralPath (Join-Path $script:OutputFull 'states/ready-events.json'))) 'A successful wait did not persist both accepted state documents.'
    $saved = Get-Content -LiteralPath (Join-Path $script:OutputFull 'states/ready.json') -Raw | ConvertFrom-Json
    Assert-Observation ($saved.identity.snapshot_id -eq 'revision-2') 'The saved success snapshot came from the wrong observation.'

    Set-ObservationSequence @((New-ObservationPair 3 $false), (New-ObservationPair 4 $false))
    $accepted = Wait-TaskState -Condition { param($snapshot, $events) $snapshot.ready } -TimeoutSeconds 0.13 -SaveAs 'never-ready'
    $receipt = Read-WaitReceipt 'never-ready'
    Assert-Observation ($null -eq $accepted -and -not $receipt.success -and @($receipt.samples | Where-Object distinct).Count -ge 2) 'A timeout did not retain its nonmatching observations.'
    Assert-Observation (-not (Test-Path -LiteralPath (Join-Path $script:OutputFull 'states/never-ready.json')) -and -not (Test-Path -LiteralPath (Join-Path $script:OutputFull 'states/never-ready-events.json'))) 'A timeout fabricated accepted snapshots.'

    Set-ObservationSequence @((New-ObservationPair 5 $true))
    $accepted = Wait-TaskState -Condition { param($snapshot, $events) $snapshot.ready } -TimeoutSeconds 0.13 -SaveAs 'duplicate-only' -StableSamples 2
    $receipt = Read-WaitReceipt 'duplicate-only'
    Assert-Observation ($null -eq $accepted -and -not $receipt.success -and $script:readCount -ge 2) 'Repeated reads of one revision satisfied two stable samples.'
    Assert-Observation (@($receipt.samples | Where-Object distinct).Count -eq 1 -and $receipt.required_distinct_samples -eq 2) 'A duplicate revision was recorded as independent evidence.'
    Assert-Observation (-not (Test-Path -LiteralPath (Join-Path $script:OutputFull 'states/duplicate-only.json'))) 'A repeated revision created a false success snapshot.'

    Set-ObservationSequence @((New-ObservationPair 6 $true), (New-ObservationPair 6 $true), (New-ObservationPair 7 $true))
    $accepted = Wait-TaskState -Condition { param($snapshot, $events) $snapshot.ready } -TimeoutSeconds 0.5 -SaveAs 'stable-ready' -StableSamples 2
    $receipt = Read-WaitReceipt 'stable-ready'
    Assert-Observation ($null -ne $accepted -and $receipt.success -and $script:readCount -eq 3 -and $accepted.snapshot.identity.snapshot_id -eq 'revision-7') 'Stable readiness did not wait for the second distinct matching revision.'
    Assert-Observation (-not $receipt.samples[1].distinct -and $null -eq $receipt.samples[1].snapshot) 'A duplicate observation was saved as new state evidence.'

    Set-ObservationSequence @()
    $accepted = Wait-TaskState -Condition { param($snapshot, $events) $true } -TimeoutSeconds 0.06 -SaveAs 'no-provider'
    $receipt = Read-WaitReceipt 'no-provider'
    Assert-Observation ($null -eq $accepted -and -not $receipt.success -and @($receipt.samples | Where-Object valid).Count -eq 0) 'A missing provider did not produce a failed observation receipt.'
    Assert-Observation ($receipt.samples[0].diagnostic.code -eq 'fixture_read') 'A provider timeout discarded its read diagnostic.'
    Assert-Observation (-not (Test-Path -LiteralPath (Join-Path $script:OutputFull 'states/no-provider.json'))) 'A missing provider fabricated success evidence.'

    Set-ObservationSequence @((New-ObservationPair 8 $false))
    $script:budgetAfter=1
    $accepted=Wait-TaskState {param($s,$e)$s.ready} .15 'healthy-tail-timeout'
    Assert-Observation ($null-eq$accepted) 'A final short poll hid a proven nonmatching condition window.'
    $receipt=Read-WaitReceipt 'healthy-tail-timeout'
    Assert-Observation ($receipt.samples[0].valid-and-not$receipt.samples[0].matches) 'The timeout lost its valid negative observation.'
    Set-ObservationSequence @()
    $script:budgetAfter=0
    $blocked=$false
    try{$null=Wait-TaskState {param($s,$e)$true} .08 'actual-reader-backlog'}catch{$blocked=$_.Exception.Message-like'*STATE_READER_BACKLOG*'}
    Assert-Observation $blocked 'A whole window without validated state was scored as candidate behavior.'

    $enemyLoop=$runnerAst.Find({param($n)$n-is[Management.Automation.Language.ForEachStatementAst]-and$n.Extent.Text-like'*$aiBefore.snapshot*'},$true)
    $damageSetup=$runnerAst.Find({param($n)$n-is[Management.Automation.Language.IfStatementAst]-and$n.Extent.Text.StartsWith('if($damagePosition)')},$true)
    Assert-Observation ($null-ne$enemyLoop-and$null-ne$damageSetup) 'Shared smoke lacks a bounded enemy prerequisite check.'
    $aiBefore=@{snapshot=@{enemies=@()}};$damagePosition=$null
    function Invoke-ARFixture {throw 'A missing enemy must not cause a native geometry write.'}
    Invoke-Expression $enemyLoop.Extent.Text
    Invoke-Expression $damageSetup.Extent.Text
    $missing=Get-Content -Raw (Join-Path $script:OutputFull 'receipts/ai-damage-prerequisite.json')|ConvertFrom-Json
    Assert-Observation ($missing.attribution-ceq'candidate'-and$missing.reason_code-ceq'CANDIDATE_ENEMY_POSITION_UNAVAILABLE') 'An empty enemy list became an evaluator exception.'

    $atomicIds = @('D2-08', 'D2-10', 'D2-13', 'D3-03', 'D3-04', 'D3-05', 'D3-07', 'D4-02')
    $scoreLoop=$runnerAst.Find({param($node)$node-is[Management.Automation.Language.ForEachStatementAst]-and$node.Extent.Text-match'Get-ActionRoguelikeAtomicVariantMap\)\.Keys'},$true)
    Assert-Observation ($null-ne$scoreLoop) 'No loop dispatches the independent variant map.'
    $atomicTraces=@{collection='independent-live-traces'};$scored=[Collections.Generic.List[string]]::new()
    function Test-ActionRoguelikeAtomicCheckpoint($CheckpointId,$Traces){
        Assert-Observation ($Traces.collection-ceq'independent-live-traces') 'Scoring did not receive the independent collection.'
        return @{checkpoint_id=$CheckpointId;verdict='pass'}
    }
    function Set-AtomicCheckpoint($Id,$Result,$Evidence){
        Assert-Observation ($Id-ceq$Result.checkpoint_id-and'receipts/atomic-live-traces.json'-cin$Evidence) 'Scoring lost its actual collection evidence.'
        $scored.Add($Id)
    }
    Invoke-Expression $scoreLoop.Extent.Text
    foreach($id in $atomicIds){Assert-Observation (@($scored|Where-Object{$_-ceq$id}).Count-eq1) "Atomic checkpoint $id is missing or duplicated in the live dispatch."}
    $atomicModule = Join-Path $evaluatorRoot 'scripts/ActionRoguelikeAtomicChecks.ps1'
    $moduleText = Get-Content -LiteralPath $atomicModule -Raw
    foreach ($functionName in @('Test-ActionRoguelikeAtomicCheckpoint','Get-ActionRoguelikeAtomicVariantMap')) {
        Assert-Observation ($moduleText -match "function\s+$functionName\b") "Missing executable atomic function: $functionName"
    }
    $variantMap = Get-ActionRoguelikeAtomicVariantMap
    Assert-Observation ($variantMap.Keys.Count -eq 8 -and @($variantMap['D2-08']).Count -eq 2 -and @($variantMap['D3-03']).Count -eq 5) 'The generic atomic variant map is incomplete.'
    Assert-Observation (-not ($moduleText -match 'EVALUATOR_CASE_NOT_IMPLEMENTED|Set-AuthoringGap')) 'The atomic module retained an authoring-gap escape hatch.'
    Write-Output "ACTIONROGUELIKE_OBSERVATIONS_OK checks=$script:assertionCount success_receipts=true timeout_receipts=true distinct_stable_samples=true atomic_cases=8 no_unreal_started=true"
} finally {
    $cleanupRoot = [IO.Path]::GetFullPath($script:OutputFull)
    $expectedParent = [IO.Path]::TrimEndingDirectorySeparator($temporaryParent)
    if ([IO.Path]::TrimEndingDirectorySeparator((Split-Path -Parent $cleanupRoot)) -ne $expectedParent -or [IO.Path]::GetFileName($cleanupRoot) -notlike 'actionroguelike-observations-*') { throw 'Refusing cleanup outside the named temporary fixture root.' }
    if (Test-Path -LiteralPath $cleanupRoot) {
        if (((Get-Item -LiteralPath $cleanupRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing cleanup through a reparse point.' }
        Remove-Item -LiteralPath $cleanupRoot -Recurse -Force
    }
}
